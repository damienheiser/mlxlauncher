import Foundation
import Network

/// Protocol for governance evaluation — allows decoupling from EngraveGovernance module.
public protocol GovernanceEvaluator: AnyObject, Sendable {
    func evaluateRequest(_ body: [String: Any], provider: String) async -> (allowed: Bool, reason: String?)
    func evaluateToolCall(name: String, input: [String: Any]) async -> (allowed: Bool, reason: String?)
    func evaluateStreamText(_ text: String) async -> (allowed: Bool, reason: String?)
}

/// Handles a single client connection through the full proxy pipeline:
/// parse → route → translate → forward → translate back → respond
public actor ConnectionHandler {
    private let config: EngraveConfig
    private let routeResolver: RouteResolver
    private let backendClient: BackendClient
    private let logger: LogHandler
    private weak var governance: (any GovernanceEvaluator)?
    private let modelDiscovery: RunnerModelDiscovery?

    public init(config: EngraveConfig, backendClient: BackendClient, logger: @escaping LogHandler, governance: (any GovernanceEvaluator)? = nil, modelDiscovery: RunnerModelDiscovery? = nil) {
        self.config = config
        self.routeResolver = RouteResolver(config: config)
        self.backendClient = backendClient
        self.logger = logger
        self.governance = governance
        self.modelDiscovery = modelDiscovery
    }

    /// Process an HTTP request and generate a response.
    /// For streaming requests, returns SSE headers and a callback to stream chunks.
    public func handle(request: HTTPRequest) async -> ConnectionResult {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path

        // Handle CORS preflight
        if request.method == "OPTIONS" {
            return .complete(HTTPResponse.cors())
        }

        // Health check
        if path == "/health" {
            return .complete(HTTPResponse.json(["status": "ok", "version": "1.0.0"]))
        }

        // Model list — serve in the format the requesting client expects
        if request.method == "GET" && (path == "/v1/models" || path == "/v1beta/models") {
            return await handleModelList(request: request, path: path)
        }

        // Determine source provider from path
        let (sourceProvider, pathModel) = RouteResolver.sourceProvider(for: path)
        if sourceProvider == "unknown" {
            return .complete(HTTPResponse.error("Unknown endpoint: \(path)", status: 404))
        }

        // Non-POST methods don't carry a JSON body — return a stub response
        if request.method == "GET" || request.method == "HEAD" || request.method == "DELETE" {
            return handleNonPostRequest(method: request.method, path: path, sourceProvider: sourceProvider)
        }

        // Parse request body
        guard let body = request.jsonBody else {
            let preview = String(data: request.body.prefix(200), encoding: .utf8) ?? "<non-utf8 \(request.body.count) bytes>"
            logger("[engrave] ERROR: Invalid JSON body (\(request.body.count) bytes) from \(sourceProvider): \(preview)")
            return .complete(HTTPResponse.error("Invalid JSON body", status: 400))
        }

        // Parse into canonical IR
        var canonical: CanonicalRequest
        switch sourceProvider {
        case "anthropic":
            canonical = MessageTranslator.parseAnthropicRequest(body)
        case "openai_compatible":
            canonical = MessageTranslator.parseChatCompletionsRequest(body)
        case "openai":
            canonical = MessageTranslator.parseOpenAIRequest(body)
        case "gemini":
            canonical = MessageTranslator.parseGeminiRequest(body, model: pathModel)
            canonical.stream = path.contains(":streamGenerateContent")
        default:
            return .complete(HTTPResponse.error("Unsupported provider: \(sourceProvider)", status: 400))
        }

        logger("[engrave] \(sourceProvider) request: model=\(canonical.model) messages=\(canonical.messages.count) stream=\(canonical.stream)")

        // Governance check
        if let gov = governance {
            let result = await gov.evaluateRequest(body, provider: sourceProvider)
            if !result.allowed {
                let reason = result.reason ?? "Blocked by governance policy"
                logger("[engrave] BLOCKED by governance: \(reason)")
                return .complete(HTTPResponse.error(reason, status: 403))
            }
        }

        // Resolve route
        let route = routeResolver.resolve(sourceProvider: sourceProvider, model: canonical.model)
        logger("[engrave] route: \(sourceProvider)/\(canonical.model) → \(route.backend)/\(route.model)")

        // Forward incoming auth headers so CLI subscription tokens pass through
        let clientAuth = extractAuthHeaders(from: request.headers)

        // Prepare backend request
        guard let prepared = await backendClient.prepareBackendRequest(
            route: route, canonicalRequest: canonical, config: config, clientAuthHeaders: clientAuth
        ) else {
            logger("[engrave] ERROR: failed to prepare backend request for route \(route.backend)/\(route.model)")
            return .complete(HTTPResponse.error("Failed to prepare backend request", status: 500))
        }

        logger("[engrave] backend url: \(prepared.url) stream=\(canonical.stream)")

        // Determine backend response format for parsing
        let backendFormat = normalizeBackendType(route.backend)
        logger("[engrave] backendFormat: \(backendFormat) (from backend type: \(route.backend))")

        if !canonical.stream {
            do {
                let (data, backendResponse) = try await backendClient.send(
                    url: prepared.url, headers: prepared.headers, body: prepared.body
                )

                if backendResponse.statusCode >= 400 {
                    let errorBody = String(data: data, encoding: .utf8) ?? ""
                    logger("[engrave] backend error: HTTP \(backendResponse.statusCode) \(errorBody.prefix(500))")
                    return .complete(HTTPResponse.error("Backend error: HTTP \(backendResponse.statusCode)", status: backendResponse.statusCode))
                }

                return .complete(nonStreamingResponse(
                    sourceProvider: sourceProvider,
                    backendFormat: backendFormat,
                    data: data,
                    requestId: canonical.metadata.requestId,
                    model: route.model
                ))
            } catch {
                logger("[engrave] backend connection error: \(error.localizedDescription)")
                return .complete(HTTPResponse.error("Backend connection failed: \(error.localizedDescription)", status: 502))
            }
        }

        // Forward to backend with streaming
        do {
            let (byteStream, backendResponse) = try await backendClient.stream(
                url: prepared.url, headers: prepared.headers, body: prepared.body
            )

            if let httpResp = backendResponse, httpResp.statusCode >= 400 {
                // Collect error body
                var errorBody = ""
                for try await chunk in byteStream { errorBody += chunk }
                logger("[engrave] backend error: HTTP \(httpResp.statusCode) \(errorBody.prefix(500))")
                return .complete(HTTPResponse.error("Backend error: HTTP \(httpResp.statusCode)", status: httpResp.statusCode))
            }

            // Return streaming response
            return .streaming(StreamingContext(
                sourceProvider: sourceProvider,
                backendFormat: backendFormat,
                byteStream: byteStream,
                requestId: canonical.metadata.requestId,
                model: route.model,
                logger: logger
            ))
        } catch {
            logger("[engrave] backend connection error: \(error.localizedDescription)")
            return .complete(HTTPResponse.error("Backend connection failed: \(error.localizedDescription)", status: 502))
        }
    }

    private func nonStreamingResponse(
        sourceProvider: String,
        backendFormat: String,
        data: Data,
        requestId: String,
        model: String
    ) -> HTTPResponse {
        guard let json = JSON.parse(data) else {
            return HTTPResponse(
                statusCode: 200,
                statusText: "OK",
                headers: ["content-type": "application/json", "access-control-allow-origin": "*"],
                body: data
            )
        }

        let text = extractText(from: json, backendFormat: backendFormat)
        let response: [String: Any]
        switch sourceProvider {
        case "anthropic":
            response = [
                "id": requestId,
                "type": "message",
                "role": "assistant",
                "model": model,
                "content": [["type": "text", "text": text]],
                "stop_reason": "end_turn",
                "stop_sequence": NSNull(),
                "usage": usage(from: json),
            ]
        case "openai":
            response = [
                "id": requestId,
                "object": "response",
                "created_at": Int(Date().timeIntervalSince1970),
                "status": "completed",
                "model": model,
                "output": [[
                    "type": "message",
                    "id": "msg_\(requestId)",
                    "status": "completed",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": text]],
                ]],
                "usage": usage(from: json),
            ]
        case "gemini":
            response = [
                "candidates": [[
                    "content": [
                        "role": "model",
                        "parts": [["text": text]],
                    ],
                    "finishReason": "STOP",
                    "index": 0,
                ]],
                "usageMetadata": geminiUsage(from: json),
            ]
        default:
            response = [
                "id": requestId,
                "object": "chat.completion",
                "created": Int(Date().timeIntervalSince1970),
                "model": model,
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": text],
                    "finish_reason": "stop",
                ]],
                "usage": usage(from: json),
            ]
        }
        return HTTPResponse.json(response)
    }

    private func extractText(from json: [String: Any], backendFormat: String) -> String {
        if let choices = JSON.array(json["choices"]),
           let first = JSON.dict(choices.first) {
            if let message = JSON.dict(first["message"]),
               let content = JSON.string(message["content"]) {
                return content
            }
            if let delta = JSON.dict(first["delta"]),
               let content = JSON.string(delta["content"]) {
                return content
            }
            if let text = JSON.string(first["text"]) {
                return text
            }
        }

        if let output = JSON.array(json["output"]) {
            let parts = output.compactMap { item -> String? in
                guard let item = JSON.dict(item),
                      let content = JSON.array(item["content"]) else { return nil }
                return content.compactMap { part -> String? in
                    guard let part = JSON.dict(part) else { return nil }
                    return JSON.string(part["text"])
                }.joined()
            }
            if !parts.isEmpty { return parts.joined() }
        }

        if let content = JSON.array(json["content"]) {
            let parts = content.compactMap { part -> String? in
                guard let part = JSON.dict(part) else { return nil }
                return JSON.string(part["text"])
            }
            if !parts.isEmpty { return parts.joined() }
        }

        if let candidates = JSON.array(json["candidates"]),
           let first = JSON.dict(candidates.first),
           let content = JSON.dict(first["content"]),
           let parts = JSON.array(content["parts"]) {
            let texts = parts.compactMap { part -> String? in
                guard let part = JSON.dict(part) else { return nil }
                return JSON.string(part["text"])
            }
            if !texts.isEmpty { return texts.joined() }
        }

        if let text = JSON.string(json["text"]) { return text }
        return ""
    }

    private func usage(from json: [String: Any]) -> [String: Any] {
        if let usage = JSON.dict(json["usage"]) { return usage }
        if let usage = JSON.dict(json["usageMetadata"]) {
            return [
                "input_tokens": JSON.int(usage["promptTokenCount"]) ?? 0,
                "output_tokens": JSON.int(usage["candidatesTokenCount"]) ?? 0,
                "total_tokens": JSON.int(usage["totalTokenCount"]) ?? 0,
            ]
        }
        return ["input_tokens": 0, "output_tokens": 0, "total_tokens": 0]
    }

    private func geminiUsage(from json: [String: Any]) -> [String: Any] {
        if let usage = JSON.dict(json["usageMetadata"]) { return usage }
        if let usage = JSON.dict(json["usage"]) {
            return [
                "promptTokenCount": JSON.int(usage["prompt_tokens"]) ?? JSON.int(usage["input_tokens"]) ?? 0,
                "candidatesTokenCount": JSON.int(usage["completion_tokens"]) ?? JSON.int(usage["output_tokens"]) ?? 0,
                "totalTokenCount": JSON.int(usage["total_tokens"]) ?? 0,
            ]
        }
        return ["promptTokenCount": 0, "candidatesTokenCount": 0, "totalTokenCount": 0]
    }

    private func handleModelList(request: HTTPRequest, path: String) async -> ConnectionResult {
        // Collect all configured model names
        var modelNames: [String] = []
        for (_, routeTarget) in config.routes.defaults {
            if routeTarget.model != "*" {
                modelNames.append(routeTarget.model)
            }
        }
        for (_, providerConfig) in config.providers {
            for model in providerConfig.models ?? [] {
                if !modelNames.contains(model) {
                    modelNames.append(model)
                }
            }
        }
        // Also include alias keys
        for (alias, _) in config.routes.aliases {
            if !modelNames.contains(alias) {
                modelNames.append(alias)
            }
        }

        // Merge in models discovered from runner CLIs (e.g. `codex debug models`)
        if let discovery = modelDiscovery {
            let discovered = await discovery.allModels()
            for (_, names) in discovered {
                for name in names where !modelNames.contains(name) {
                    modelNames.append(name)
                }
            }
        }

        // Detect format from request headers or path
        let isGemini = path.contains("v1beta") ||
            request.headers["x-goog-api-key"] != nil
        let isAnthropic = request.headers["x-api-key"] != nil ||
            request.headers["anthropic-version"] != nil

        if isGemini {
            // Gemini format: {models: [{name: "models/...", displayName: "...", ...}]}
            let models = modelNames.map { name -> [String: Any] in
                [
                    "name": "models/\(name)",
                    "displayName": name,
                    "description": "Model served via Engrave interposer",
                    "supportedGenerationMethods": ["generateContent", "streamGenerateContent"],
                    "inputTokenLimit": 128000,
                    "outputTokenLimit": 8192,
                ]
            }
            return .complete(HTTPResponse.json(["models": models]))
        }

        if isAnthropic {
            // Anthropic format: {data: [{id, type: "model", display_name, ...}]}
            let models = modelNames.map { name -> [String: Any] in
                [
                    "id": name,
                    "type": "model",
                    "display_name": name,
                    "created_at": "2025-01-01T00:00:00Z",
                ]
            }
            return .complete(HTTPResponse.json([
                "data": models,
                "has_more": false,
                "first_id": modelNames.first as Any,
                "last_id": modelNames.last as Any,
            ]))
        }

        // OpenAI format (default): {object: "list", data: [{id, object: "model", ...}]}
        let models = modelNames.map { name -> [String: Any] in
            [
                "id": name,
                "object": "model",
                "created": Int(Date().timeIntervalSince1970),
                "owned_by": "engrave",
            ]
        }
        return .complete(HTTPResponse.json(["object": "list", "data": models]))
    }

    /// Handle GET/HEAD/DELETE requests to known provider endpoints.
    /// These typically request model info or response retrieval — return a
    /// reasonable stub so CLI tools don't crash.
    private func handleNonPostRequest(method: String, path: String, sourceProvider: String) -> ConnectionResult {
        // GET /v1/responses/{id} — Codex polls for response status
        if sourceProvider == "openai" && method == "GET" {
            let id = String(path.dropFirst("/v1/responses/".count))
            return .complete(HTTPResponse.json([
                "id": id.isEmpty ? "resp_stub" : id,
                "object": "response",
                "status": "completed",
                "output": [] as [Any],
            ]))
        }
        // Fallback: empty success
        return .complete(HTTPResponse.json(["status": "ok"]))
    }

    private func normalizeBackendType(_ backend: String) -> String {
        switch backend {
        case "openai_compatible", "local": return "chat_completions"
        case "claude_subscription": return "anthropic"
        case "gemini_subscription", "gemini_cli": return "gemini"
        default: return backend
        }
    }

    /// Extract auth-related headers from the incoming client request.
    /// These are forwarded to the backend so CLI subscription OAuth tokens
    /// and user-supplied API keys pass through the interposer transparently.
    private func extractAuthHeaders(from headers: [String: String]) -> [String: String] {
        var auth: [String: String] = [:]
        if let v = headers["authorization"] { auth["authorization"] = v }
        if let v = headers["x-api-key"] { auth["x-api-key"] = v }
        if let v = headers["anthropic-version"] { auth["anthropic-version"] = v }
        if let v = headers["x-goog-api-key"] { auth["x-goog-api-key"] = v }
        return auth
    }
}

// MARK: - Connection Result

public enum ConnectionResult {
    case complete(HTTPResponse)
    case streaming(StreamingContext)
}

// MARK: - Streaming Context

/// Holds everything needed to stream a translated response back to the client
public struct StreamingContext: @unchecked Sendable {
    public let sourceProvider: String
    public let backendFormat: String
    public let byteStream: AsyncThrowingStream<String, Error>
    public let requestId: String
    public let model: String
    public let logger: LogHandler

    /// Process the backend stream and yield translated SSE lines for the client
    public func translateStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let sourceTranslator = StreamTranslator()
                let backendParser = StreamTranslator()
                var sseParser = SSEParser()

                do {
                    var chunkCount = 0
                    for try await chunk in byteStream {
                        chunkCount += 1
                        if chunkCount <= 3 {
                            logger("[engrave] stream chunk #\(chunkCount): \(String(chunk.prefix(200)).replacingOccurrences(of: "\n", with: "\\n"))")
                        }
                        let events = sseParser.feed(chunk)
                        if chunkCount <= 3 {
                            logger("[engrave] SSE events from chunk: \(events.count)")
                        }
                        for sseEvent in events {
                            if sseEvent.isDone {
                                logger("[engrave] SSE [DONE]")
                                let canonical: [CanonicalStreamEvent] = [.messageEnd]
                                for ce in canonical {
                                    let lines = serializeCanonical(ce, provider: sourceProvider, translator: sourceTranslator, requestId: requestId, model: model)
                                    for line in lines { continuation.yield(line) }
                                }
                                continue
                            }

                            guard let data = sseEvent.data else {
                                logger("[engrave] SSE event with no parseable JSON data: \(sseEvent.rawData.prefix(200))")
                                continue
                            }

                            // Parse backend SSE into canonical events
                            let canonicalEvents: [CanonicalStreamEvent]
                            switch backendFormat {
                            case "anthropic":
                                canonicalEvents = backendParser.parseAnthropicSSE(eventType: sseEvent.eventType ?? "", data: data)
                            case "openai":
                                canonicalEvents = backendParser.parseOpenAISSE(eventType: sseEvent.eventType ?? "", data: data)
                            case "gemini":
                                canonicalEvents = backendParser.parseGeminiSSE(data: data)
                            case "chat_completions":
                                canonicalEvents = backendParser.parseChatCompletionsSSE(data: data)
                            default:
                                canonicalEvents = backendParser.parseChatCompletionsSSE(data: data)
                            }

                            if chunkCount <= 5 {
                                logger("[engrave] canonical events: \(canonicalEvents.map { "\($0)" })")
                            }

                            // Translate canonical events to source format
                            for canonical in canonicalEvents {
                                let lines = serializeCanonical(canonical, provider: sourceProvider, translator: sourceTranslator, requestId: requestId, model: model)
                                for line in lines { continuation.yield(line) }
                            }
                        }
                    }
                    logger("[engrave] stream ended after \(chunkCount) chunks")
                    continuation.finish()
                } catch {
                    logger("[engrave] stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Serialize a canonical event to the source provider's SSE format
private func serializeCanonical(
    _ event: CanonicalStreamEvent,
    provider: String,
    translator: StreamTranslator,
    requestId: String,
    model: String
) -> [String] {
    switch provider {
    case "anthropic":
        return translator.canonicalToAnthropicSSE(event)
    case "openai":
        return translator.canonicalToOpenAISSE(event)
    case "openai_compatible", "chat_completions":
        return translator.canonicalToChatCompletionsSSE(event, id: requestId, model: model)
    case "gemini":
        return translator.canonicalToGeminiSSE(event)
    default:
        return translator.canonicalToChatCompletionsSSE(event, id: requestId, model: model)
    }
}

/// Log handler type
public typealias LogHandler = @Sendable (String) -> Void
