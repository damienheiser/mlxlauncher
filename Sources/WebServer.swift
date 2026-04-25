import Foundation

// Lightweight HTTP server using BSD sockets — no dependencies.

class WebServer {
    let port: UInt16
    let appState: AppState
    private var serverFd: Int32 = -1
    private let queue = DispatchQueue(label: "mlx.webserver", attributes: .concurrent)
    private let maxRequestBytes = 10 * 1024 * 1024

    init(port: UInt16, appState: AppState) {
        self.port = port
        self.appState = appState
    }

    func start() {
        queue.async { [self] in
            serverFd = socket(AF_INET, SOCK_STREAM, 0)
            guard serverFd >= 0 else { return }

            var yes: Int32 = 1
            setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(serverFd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = INADDR_ANY

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                    bind(serverFd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else { return }

            listen(serverFd, 128)

            while serverFd >= 0 {
                let clientFd = accept(serverFd, nil, nil)
                guard clientFd >= 0 else { continue }
                queue.async { self.handleClient(clientFd) }
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        guard let requestData = readRequest(from: fd),
              let raw = String(data: requestData, encoding: .utf8) else {
            sendRawResponse(fd: fd, status: 400, contentType: "application/json", body: #"{"error":"invalid request"}"#)
            return
        }
        let (method, path) = parseRequestLine(raw)
        let body = extractBody(raw)

        // OpenAI-compatible routes handle their own response writing (for streaming)
        if path.hasPrefix("/v1/") {
            handleOpenAI(fd: fd, method: method, path: path, body: body)
            return
        }

        if path == "/health" {
            sendRawResponse(fd: fd, status: 200, contentType: "application/json", body: #"{"status":"ok"}"#)
            return
        }

        let response: (Int, String, String) // (status, contentType, body)

        if path == "/" || path == "/index.html" {
            response = (200, "text/html", WebUI.html)
        } else if path.hasPrefix("/api/") {
            response = handleAPI(method: method, path: path, body: body)
        } else {
            response = (404, "application/json", #"{"error":"not found"}"#)
        }

        sendRawResponse(fd: fd, status: response.0, contentType: response.1, body: response.2)
    }

    private func readRequest(from fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var expectedTotal: Int?

        while data.count < maxRequestBytes {
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { break }
            data.append(buffer, count: n)

            if expectedTotal == nil {
                expectedTotal = requestExpectedTotalBytes(data)
            }
            if let expectedTotal, data.count >= expectedTotal {
                return data
            }
            if expectedTotal == nil, requestHeaderEndIndex(data) != nil {
                return data
            }
        }

        return data.isEmpty || data.count > maxRequestBytes ? nil : data
    }

    private func requestExpectedTotalBytes(_ data: Data) -> Int? {
        guard let headerEnd = requestHeaderEndIndex(data) else { return nil }
        let headerData = data.prefix(headerEnd)
        guard let header = String(data: headerData, encoding: .utf8) else { return nil }
        let contentLength = header
            .components(separatedBy: "\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0
        return headerEnd + 4 + contentLength
    }

    private func requestHeaderEndIndex(_ data: Data) -> Int? {
        let needle = Data([13, 10, 13, 10])
        guard let range = data.range(of: needle) else { return nil }
        return range.lowerBound
    }

    private func sendRawResponse(fd: Int32, status: Int, contentType: String, body: String) {
        let statusText = statusText(for: status)
        let headers = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType); charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n"
        let httpResponse = headers + body

        let data = Array(httpResponse.utf8)
        _ = send(fd, data, data.count, 0)
        close(fd)
    }

    private func statusText(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Error"
        }
    }

    private func parseRequestLine(_ raw: String) -> (String, String) {
        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return ("GET", "/") }
        return (String(parts[0]), String(parts[1]))
    }

    private func extractBody(_ raw: String) -> String {
        guard let range = raw.range(of: "\r\n\r\n") else { return "" }
        return String(raw[range.upperBound...])
    }

    // MARK: - API Router

    private func handleAPI(method: String, path: String, body: String) -> (Int, String, String) {
        let ct = "application/json"

        if method == "OPTIONS" {
            return (200, ct, "{}")
        }

        switch (method, path) {
        case ("GET", "/api/models"):
            return (200, ct, modelsJSON())
        case ("GET", "/api/runners"):
            return (200, ct, runnersJSON())
        case ("GET", "/api/server"):
            return (200, ct, serverJSON())
        case ("POST", "/api/server/start"):
            return startServerAPI(body: body)
        case ("POST", "/api/server/stop"):
            DispatchQueue.main.async { self.appState.stopServer() }
            return (200, ct, #"{"ok":true}"#)
        case ("POST", "/api/server/restart"):
            DispatchQueue.main.async { self.appState.restartServer() }
            return (200, ct, #"{"ok":true}"#)
        case ("GET", "/api/profiles"):
            return (200, ct, profilesJSON())
        case ("GET", "/api/prompts"):
            return (200, ct, promptsJSON())
        case ("POST", "/api/launch"):
            return launchAPI(body: body)
        default:
            return (404, ct, #"{"error":"unknown endpoint"}"#)
        }
    }

    private func modelsJSON() -> String {
        var models: [[String: Any]] = []
        DispatchQueue.main.sync {
            for m in appState.allModels {
                models.append([
                    "id": m.id, "index": m.index, "size": m.size,
                    "source": m.source.rawValue, "shortName": m.shortName,
                    "provider": m.providerBadge,
                    "launchIdentity": m.launchIdentity
                ])
            }
        }
        return jsonEncode(models)
    }

    private func runnersJSON() -> String {
        let runners = allRunners.map { r in
            ["id": r.id, "name": r.name, "installed": r.isInstalled, "needsProxy": r.needsProxy] as [String: Any]
        }
        return jsonEncode(runners)
    }

    private func serverJSON() -> String {
        var dict: [String: Any] = [:]
        DispatchQueue.main.sync {
            dict = [
                "state": appState.serverStatus.state.rawValue,
                "model": appState.serverStatus.modelName ?? "",
                "port": appState.serverStatus.port,
                "pid": appState.serverStatus.pid ?? 0
            ]
        }
        return jsonEncode(dict)
    }

    private func profilesJSON() -> String {
        var profiles: [[String: Any]] = []
        DispatchQueue.main.sync {
            for p in appState.profiles {
                profiles.append([
                    "name": p.name, "temp": p.temp, "top_p": p.top_p, "top_k": p.top_k,
                    "min_p": p.min_p, "max_tokens": p.max_tokens,
                    "repetition_penalty": p.repetition_penalty,
                    "repetition_context_size": p.repetition_context_size,
                    "system_prompt": p.system_prompt
                ])
            }
        }
        return jsonEncode(profiles)
    }

    private func promptsJSON() -> String {
        var prompts: [[String: Any]] = []
        DispatchQueue.main.sync {
            for p in appState.prompts {
                prompts.append(["name": p.name, "prompt": p.prompt, "source": p.source])
            }
        }
        return jsonEncode(prompts)
    }

    private func startServerAPI(body: String) -> (Int, String, String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelId = json["model"] as? String else {
            return (400, "application/json", #"{"error":"missing model field"}"#)
        }
        var didFindModel = false
        DispatchQueue.main.sync {
            didFindModel = self.appState.allModels.contains(where: { $0.id == modelId || $0.launchIdentity == modelId })
        }
        guard didFindModel else {
            return (404, "application/json", #"{"error":"model not found"}"#)
        }
        DispatchQueue.main.async {
            if let model = self.appState.allModels.first(where: { $0.id == modelId || $0.launchIdentity == modelId }) {
                self.appState.startServer(model: model)
            }
        }
        return (200, "application/json", #"{"ok":true}"#)
    }

    private func launchAPI(body: String) -> (Int, String, String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelId = json["model"] as? String,
              let runnerId = json["runner"] as? String else {
            return (400, "application/json", #"{"error":"missing model or runner"}"#)
        }
        var selected: (MLXModel, Runner)?
        DispatchQueue.main.sync {
           if let model = self.appState.allModels.first(where: { $0.id == modelId || $0.launchIdentity == modelId }),
               let runner = allRunners.first(where: { $0.id == runnerId }) {
                selected = (model, runner)
            }
        }
        guard let selected else {
            return (404, "application/json", #"{"error":"model or runner not found"}"#)
        }
        DispatchQueue.main.async {
                let model = selected.0
                let runner = selected.1
                self.appState.selectedModel = model
                self.appState.selectedRunner = runner
                var settings = self.appState.settings(for: runner)
                if let workingDirectory = json["workingDirectory"] as? String, !workingDirectory.isEmpty {
                    settings.workingDirectory = workingDirectory
                }
                if let args = json["args"] as? [String] {
                    settings.extraArguments = args.joined(separator: " ")
                } else if let args = json["args"] as? String {
                    settings.extraArguments = args
                }
                self.appState.updateSettings(for: runner, settings)
                self.appState.launch()
        }
        return (200, "application/json", #"{"ok":true}"#)
    }

    private func jsonEncode(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    // MARK: - OpenAI-Compatible Routes

    private func handleOpenAI(fd: Int32, method: String, path: String, body: String) {
        let ct = "application/json"

        if method == "OPTIONS" {
            sendRawResponse(fd: fd, status: 200, contentType: ct, body: "{}")
            return
        }

        switch (method, path) {
        case ("GET", "/v1/models"):
            var result: [String: Any] = [:]
            DispatchQueue.main.sync {
                result = self.appState.inference.modelListJSON()
            }
            sendRawResponse(fd: fd, status: 200, contentType: ct, body: jsonEncode(result))

        case ("POST", "/v1/chat/completions"):
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                sendRawResponse(fd: fd, status: 400, contentType: ct, body: #"{"error":"invalid JSON body"}"#)
                return
            }

            let wantStream = json["stream"] as? Bool ?? false

            if wantStream {
                handleStreamingCompletion(fd: fd, body: json)
            } else {
                handleNonStreamingCompletion(fd: fd, body: json)
            }

        default:
            sendRawResponse(fd: fd, status: 404, contentType: ct, body: #"{"error":"unknown endpoint"}"#)
        }
    }

    private func handleStreamingCompletion(fd: Int32, body: [String: Any]) {
        // Send SSE headers immediately
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n\r\n"
        sendRawBytes(fd: fd, string: headers)

        let sem = DispatchSemaphore(value: 0)
        var streamError: Error?

        // Get the stream on the main actor, then iterate it
        // MLXInference is @MainActor so we need to hop to main to call methods
        var stream: AsyncThrowingStream<String, Error>?
        DispatchQueue.main.sync {
            stream = self.appState.inference.handleChatCompletionsRequest(body)
        }

        guard let stream else {
            sendRawBytes(fd: fd, string: "data: {\"error\":\"failed to create stream\"}\n\n")
            close(fd)
            return
        }

        Task {
            do {
                for try await line in stream {
                    self.sendRawBytes(fd: fd, string: line)
                }
            } catch {
                streamError = error
            }
            sem.signal()
        }

        sem.wait()

        if let error = streamError {
            let errMsg = "data: {\"error\":\"\(error.localizedDescription)\"}\n\n"
            sendRawBytes(fd: fd, string: errMsg)
        }

        close(fd)
    }

    private func handleNonStreamingCompletion(fd: Int32, body: [String: Any]) {
        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        var completionError: Error?

        Task { @MainActor in
            do {
                result = try await self.appState.inference.handleChatCompletionsRequestNonStreaming(body)
            } catch {
                completionError = error
            }
            sem.signal()
        }

        sem.wait()

        if let error = completionError {
            let errBody = jsonEncode(["error": ["message": error.localizedDescription, "type": "server_error"]])
            sendRawResponse(fd: fd, status: 500, contentType: "application/json", body: errBody)
        } else if let result {
            sendRawResponse(fd: fd, status: 200, contentType: "application/json", body: jsonEncode(result))
        } else {
            sendRawResponse(fd: fd, status: 500, contentType: "application/json", body: #"{"error":{"message":"unknown error","type":"server_error"}}"#)
        }
    }

    private func sendRawBytes(fd: Int32, string: String) {
        let bytes = Array(string.utf8)
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let n = send(fd, base + sent, bytes.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}
