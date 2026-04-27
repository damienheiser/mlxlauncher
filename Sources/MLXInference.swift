import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Native Swift MLX inference engine — replaces the Python mlx_lm server entirely.
/// Thread-safe, concurrent-request capable, no Python dependency.
@MainActor
class MLXInference: ObservableObject {
    @Published var isLoaded = false
    @Published var isLoading = false
    @Published var loadedModelPath: String?
    @Published var loadedModelName: String?
    @Published var loadError: String?
    @Published var tokensPerSecond: Double = 0

    private var container: ModelContainer?

    /// Load a model from a local directory path.
    func loadModel(at path: String) async {
        isLoading = true
        loadError = nil

        do {
            let url = URL(fileURLWithPath: path)
            let modelName = extractModelName(from: path)

            // Let MLX manage its own GPU memory cache — the framework picks
            // safe defaults for unified-memory Apple Silicon.  Overriding with
            // a percentage of physicalMemory can exceed Metal's limits on
            // high-RAM machines (Mac Studio M1 Ultra, etc.) and crash.

            let container = try await LLMModelFactory.shared.loadContainer(
                from: url,
                using: SwiftTokenizerLoader()
            )

            self.container = container
            self.loadedModelPath = path
            self.loadedModelName = modelName
            self.isLoaded = true
            self.isLoading = false
        } catch {
            self.loadError = error.localizedDescription
            self.isLoading = false
        }
    }

    /// Unload the current model to free memory.
    func unload() {
        container = nil
        isLoaded = false
        loadedModelPath = nil
        loadedModelName = nil
        tokensPerSecond = 0
    }

    // MARK: - Message Extraction

    /// Extract messages from an OpenAI-compatible request body.
    /// Handles: string content, content-part arrays, null content, tool messages.
    private static func extractMessages(from body: [String: Any]) -> [(role: String, content: String)] {
        guard let rawMessages = body["messages"] as? [[String: Any]] else { return [] }

        return rawMessages.compactMap { msg -> (role: String, content: String)? in
            guard let role = msg["role"] as? String else { return nil }

            // Extract content from string, array-of-parts, or null
            let content: String
            if let s = msg["content"] as? String {
                content = s
            } else if let parts = msg["content"] as? [[String: Any]] {
                // OpenAI content array: [{"type":"text","text":"..."},...]
                content = parts.compactMap { part -> String? in
                    let ptype = (part["type"] as? String) ?? "text"
                    if ptype == "text" { return part["text"] as? String }
                    return nil
                }.joined(separator: "\n")
            } else {
                // null, missing, or non-string/non-array → empty
                content = ""
            }

            // Drop messages with no role or completely empty tool messages
            // but keep empty-content user/system/assistant messages (template handles them)
            return (role: role, content: content)
        }
    }

    // MARK: - Chat Completion

    /// Generate a streaming chat completion. Returns an AsyncStream of text chunks.
    /// Generation runs off-MainActor so Metal GPU compute isn't serialized with UI.
    func chatCompletion(
        messages: [(role: String, content: String)],
        maxTokens: Int = 4096,
        temperature: Float = 0.7,
        topP: Float = 0.9
    ) -> AsyncThrowingStream<String, Error> {
        guard let container = self.container else {
            return AsyncThrowingStream { $0.finish(throwing: InferenceError.modelNotLoaded) }
        }

        // Build Chat.Message array, mapping roles correctly
        var chatMessages: [Chat.Message] = []
        for msg in messages {
            let role: Chat.Message.Role
            switch msg.role {
            case "system", "developer": role = .system
            case "assistant":           role = .assistant
            case "tool":                role = .tool
            default:                    role = .user
            }
            chatMessages.append(Chat.Message(role: role, content: msg.content))
        }

        // Ensure at least one user message exists
        if !chatMessages.contains(where: { $0.role == .user }) {
            chatMessages.append(.user("Hello"))
        }

        return AsyncThrowingStream { continuation in
            Task.detached { [weak self] in
                do {
                    let input = UserInput(prompt: .chat(chatMessages))
                    let params = GenerateParameters(
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP
                    )

                    let lmInput = try await container.prepare(input: input)
                    let stream = try await container.generate(input: lmInput, parameters: params)

                    for await generation in stream {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(text)
                        case .info(let info):
                            let tps = info.tokensPerSecond
                            Task { @MainActor in
                                self?.tokensPerSecond = tps
                            }
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - OpenAI-Compatible Handlers

    /// Handle an OpenAI-compatible /v1/chat/completions request (streaming).
    func handleChatCompletionsRequest(_ body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        let messages = Self.extractMessages(from: body)

        let maxTokens = (body["max_tokens"] as? Int)
            ?? (body["max_completion_tokens"] as? Int)
            ?? 4096
        let temperature = (body["temperature"] as? NSNumber)?.floatValue ?? 0.7
        let topP = (body["top_p"] as? NSNumber)?.floatValue ?? 0.9
        let requestId = "chatcmpl-\(UUID().uuidString.prefix(12))"
        let modelName = loadedModelName ?? "mlx-local"

        let stream = self.chatCompletion(
            messages: messages,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )

        return AsyncThrowingStream { continuation in
            Task.detached {
                // First chunk: role announcement
                continuation.yield(Self.sseChunk(id: requestId, model: modelName,
                    delta: ["role": "assistant", "content": ""], finishReason: nil))

                do {
                    for try await text in stream {
                        continuation.yield(Self.sseChunk(id: requestId, model: modelName,
                            delta: ["content": text], finishReason: nil))
                    }

                    continuation.yield(Self.sseChunk(id: requestId, model: modelName,
                        delta: [:], finishReason: "stop"))
                    continuation.yield("data: [DONE]\n\n")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Handle a non-streaming /v1/chat/completions request.
    func handleChatCompletionsRequestNonStreaming(_ body: [String: Any]) async throws -> [String: Any] {
        let messages = Self.extractMessages(from: body)

        let maxTokens = (body["max_tokens"] as? Int)
            ?? (body["max_completion_tokens"] as? Int)
            ?? 4096
        let temperature = (body["temperature"] as? NSNumber)?.floatValue ?? 0.7
        let topP = (body["top_p"] as? NSNumber)?.floatValue ?? 0.9
        let requestId = "chatcmpl-\(UUID().uuidString.prefix(12))"
        let modelName = loadedModelName ?? "mlx-local"

        var fullText = ""
        let stream = chatCompletion(messages: messages, maxTokens: maxTokens, temperature: temperature, topP: topP)
        for try await chunk in stream {
            fullText += chunk
        }

        return [
            "id": requestId,
            "object": "chat.completion",
            "model": modelName,
            "created": Int(Date().timeIntervalSince1970),
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": fullText],
                "finish_reason": "stop",
            ] as [String: Any]],
        ]
    }

    /// Returns the model list in OpenAI format.
    func modelListJSON() -> [String: Any] {
        var models: [[String: Any]] = []
        if let name = loadedModelName {
            models.append(["id": name, "object": "model", "created": Int(Date().timeIntervalSince1970)])
        }
        if let path = loadedModelPath, path != loadedModelName {
            models.append(["id": path, "object": "model", "created": Int(Date().timeIntervalSince1970)])
        }
        return ["object": "list", "data": models]
    }

    // MARK: - Helpers

    private func extractModelName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent.replacingOccurrences(of: "--", with: "/")
    }

    nonisolated private static func sseChunk(id: String, model: String, delta: [String: Any], finishReason: String?) -> String {
        var choice: [String: Any] = ["index": 0, "delta": delta]
        choice["finish_reason"] = finishReason
        let chunk: [String: Any] = [
            "id": id, "object": "chat.completion.chunk", "model": model,
            "created": Int(Date().timeIntervalSince1970),
            "choices": [choice],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: chunk),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return "data: \(json)\n\n"
    }
}

enum InferenceError: Error, LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "No model loaded"
        }
    }
}

/// Loads tokenizer from local model directory using swift-transformers.
/// Handles community models that ship broken tokenizer_class values
/// (e.g. "TokenizersBackend") by patching the config before loading.
struct SwiftTokenizerLoader: MLXLMCommon.TokenizerLoader, Sendable {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        patchTokenizerConfigIfNeeded(in: directory)
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerWrapper(upstream)
    }

    /// Some community models set tokenizer_class to internal HuggingFace
    /// backend names ("TokenizersBackend", etc.) that swift-transformers
    /// doesn't recognise.  Detect this and rewrite to the correct class
    /// based on model_type from config.json.
    private func patchTokenizerConfigIfNeeded(in directory: URL) {
        let tokConfigURL = directory.appendingPathComponent("tokenizer_config.json")
        guard let tokDict = readJSON(tokConfigURL) else { return }
        guard let cls = tokDict["tokenizer_class"] as? String else { return }

        // Known good classes that swift-transformers supports
        let supported: Set<String> = [
            "BertTokenizer", "GPT2Tokenizer", "LlamaTokenizer",
            "CodeLlamaTokenizer", "GemmaTokenizer", "T5Tokenizer",
            "WhisperTokenizer", "CohereTokenizer", "Qwen2Tokenizer",
            "PreTrainedTokenizer",
            // Fast variants are stripped automatically
            "BertTokenizerFast", "GPT2TokenizerFast", "LlamaTokenizerFast",
            "GemmaTokenizerFast", "Qwen2TokenizerFast", "PreTrainedTokenizerFast",
        ]
        if supported.contains(cls) { return }

        // Determine replacement from model_type in config.json
        let configURL = directory.appendingPathComponent("config.json")
        let modelType = (readJSON(configURL)?["model_type"] as? String)?.lowercased() ?? ""
        let replacement: String
        switch modelType {
        case let t where t.hasPrefix("qwen"):  replacement = "Qwen2Tokenizer"
        case "llama", "mistral", "deepseek":    replacement = "LlamaTokenizer"
        case "gemma", "gemma2":                 replacement = "GemmaTokenizer"
        case "gpt2", "gpt_neo", "gpt_neox":     replacement = "GPT2Tokenizer"
        default:                                replacement = "PreTrainedTokenizer"
        }

        // Only patch the tokenizer_class field — preserve everything else byte-for-byte
        // by doing a targeted string replacement instead of full JSON round-trip
        // (which can corrupt Jinja chat templates with escape sequences).
        let rawURL = tokConfigURL
        guard let rawData = try? Data(contentsOf: rawURL),
              var rawString = String(data: rawData, encoding: .utf8) else { return }

        // Replace "tokenizer_class": "OldValue" with "tokenizer_class": "NewValue"
        let pattern = "\"tokenizer_class\"\\s*:\\s*\"[^\"]*\""
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: rawString, range: NSRange(rawString.startIndex..., in: rawString)) {
            let replacement = "\"tokenizer_class\": \"\(replacement)\""
            rawString = regex.stringByReplacingMatches(
                in: rawString, range: match.range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
            try? rawString.write(to: tokConfigURL, atomically: true, encoding: .utf8)
        }
    }

    private func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }
}

/// Bridges swift-transformers Tokenizer to MLXLMCommon.Tokenizer protocol.
/// PreTrainedTokenizer.compiledTemplate(for:) mutates an internal cache
/// dictionary and is NOT thread-safe.  All calls are serialized through a lock.
final class TokenizerWrapper: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let inner: any Tokenizers.Tokenizer
    private let lock = NSLock()

    init(_ tokenizer: any Tokenizers.Tokenizer) {
        self.inner = tokenizer
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        inner.encode(text: text)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        inner.decode(tokens: tokenIds)
    }

    func convertTokenToId(_ token: String) -> Int? {
        inner.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        inner.convertIdToToken(id)
    }

    var bosToken: String? { inner.bosToken }
    var eosToken: String? { inner.eosToken }
    var unknownToken: String? { inner.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        let stringMessages = messages.map { msg -> [String: String] in
            var result: [String: String] = [:]
            for (key, value) in msg {
                result[key] = "\(value)"
            }
            return result
        }

        // PreTrainedTokenizer.compiledTemplate(for:) mutates a cache dict —
        // concurrent calls from Task.detached crash with EXC_BAD_ACCESS.
        lock.lock()
        defer { lock.unlock() }

        do {
            return try inner.applyChatTemplate(messages: stringMessages)
        } catch {
            // The Swift Jinja library has a bug: [::-1] (reverse slice) returns
            // an empty array instead of reversing.  Many Qwen3 chat templates
            // use this and fail on multi-turn conversations.  Fall back to
            // manual ChatML formatting which all Qwen/Llama models understand.
            let errMsg = "\(error)"
            if errMsg.contains("No user query") || errMsg.contains("user query") {
                return inner.encode(text: buildChatML(stringMessages))
            }
            throw error
        }
    }

    /// Build ChatML-formatted prompt manually as a fallback when
    /// the Jinja chat template fails (e.g. due to [::-1] bug).
    private func buildChatML(_ messages: [[String: String]]) -> String {
        var prompt = ""
        for msg in messages {
            let role = msg["role"] ?? "user"
            let content = msg["content"] ?? ""
            prompt += "<|im_start|>\(role)\n\(content)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }
}
