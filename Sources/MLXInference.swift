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

            // Set GPU memory cache to 75% of system RAM for optimal Metal performance
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            MLX.Memory.cacheLimit = Int(Double(totalMemory) * 0.75)

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

        let chatMessages = messages.map { msg -> Chat.Message in
            let role: Chat.Message.Role
            switch msg.role {
            case "system": role = .system
            case "assistant": role = .assistant
            default: role = .user
            }
            return Chat.Message(role: role, content: msg.content)
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

    /// Handle an OpenAI-compatible /v1/chat/completions request.
    /// Returns SSE-formatted streaming response lines.
    func handleChatCompletionsRequest(_ body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        let messages: [(role: String, content: String)] = (body["messages"] as? [[String: Any]])?.compactMap { msg in
            guard let role = msg["role"] as? String,
                  let content = msg["content"] as? String else { return nil }
            return (role: role, content: content)
        } ?? []

        let maxTokens = body["max_tokens"] as? Int ?? 4096
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
        let messages: [(role: String, content: String)] = (body["messages"] as? [[String: Any]])?.compactMap { msg in
            guard let role = msg["role"] as? String,
                  let content = msg["content"] as? String else { return nil }
            return (role: role, content: content)
        } ?? []

        let maxTokens = body["max_tokens"] as? Int ?? 4096
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
struct SwiftTokenizerLoader: MLXLMCommon.TokenizerLoader, Sendable {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerWrapper(upstream)
    }
}

/// Bridges swift-transformers Tokenizer to MLXLMCommon.Tokenizer protocol.
struct TokenizerWrapper: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let inner: any Tokenizers.Tokenizer

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
        // Convert to the format swift-transformers expects
        let stringMessages = messages.map { msg -> [String: String] in
            var result: [String: String] = [:]
            for (key, value) in msg {
                result[key] = "\(value)"
            }
            return result
        }
        return try inner.applyChatTemplate(messages: stringMessages)
    }
}
