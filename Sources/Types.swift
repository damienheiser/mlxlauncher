import Foundation

// MARK: - Model

struct MLXModel: Identifiable, Hashable, Codable {
    let id: String
    let index: Int
    let size: String
    let source: ModelSource
    let localPath: String?
    let networkHost: String?
    let networkPort: UInt16?

    init(id: String, index: Int, size: String, source: ModelSource, localPath: String? = nil, networkHost: String? = nil, networkPort: UInt16? = nil) {
        self.id = id
        self.index = index
        self.size = size
        self.source = source
        self.localPath = localPath
        self.networkHost = networkHost
        self.networkPort = networkPort
    }

    var shortName: String {
        id.components(separatedBy: "/").last ?? id
    }

    var isCloud: Bool { source == .anthropic || source == .openai || source == .google }
    var isNetwork: Bool { source == .network }

    var launchIdentity: String {
        if let localPath { return "local:\(localPath)" }
        if let networkHost, let networkPort { return "network:\(networkHost):\(networkPort)/\(id)" }
        return "\(source.rawValue):\(id)"
    }

    var huggingFaceURL: URL? {
        guard source == .local else { return nil }
        return URL(string: "https://huggingface.co/\(id)")
    }

    var providerBadge: String {
        switch source {
        case .local: return "MLX"
        case .network: return "Network"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .google: return "Google"
        }
    }
}

enum ModelSource: String, Codable, Hashable {
    case local, network, anthropic, openai, google
}

// MARK: - Runner

struct Runner: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let needsProxy: Bool
    let binary: String

    static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.cargo/bin",
    ]

    var resolvedPath: String? {
        for dir in Self.searchPaths {
            let path = "\(dir)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    var isInstalled: Bool { resolvedPath != nil }
}

let allRunners: [Runner] = [
    Runner(id: "claude", name: "Claude Code", icon: "brain.head.profile", needsProxy: true, binary: "claude"),
    Runner(id: "codex", name: "Codex CLI", icon: "terminal", needsProxy: true, binary: "codex"),
    Runner(id: "gemini", name: "Gemini CLI", icon: "sparkles", needsProxy: true, binary: "gemini"),
    Runner(id: "aider", name: "Aider", icon: "wrench.adjustable", needsProxy: true, binary: "aider"),
    Runner(id: "gptme", name: "gptme", icon: "message", needsProxy: true, binary: "gptme"),
]

struct RunnerLaunchSettings: Codable, Equatable {
    var workingDirectory: String
    var enabledFlags: Set<String>
    var values: [String: String]
    var extraArguments: String

    static var `default`: RunnerLaunchSettings {
        RunnerLaunchSettings(
            workingDirectory: FileManager.default.currentDirectoryPath,
            enabledFlags: [],
            values: [:],
            extraArguments: ""
        )
    }
}

// MARK: - Generation Parameters

struct GenerationProfile: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var temp: Double
    var top_p: Double
    var top_k: Int
    var min_p: Double
    var max_tokens: Int
    var repetition_penalty: Double
    var repetition_context_size: Int
    var system_prompt: String

    static let `default` = GenerationProfile(
        name: "Default", temp: 0.7, top_p: 0.9, top_k: 40, min_p: 0.05,
        max_tokens: 4096, repetition_penalty: 1.15, repetition_context_size: 256,
        system_prompt: ""
    )

    static let coding = GenerationProfile(
        name: "Coding", temp: 0.2, top_p: 0.85, top_k: 20, min_p: 0.1,
        max_tokens: 8192, repetition_penalty: 1.05, repetition_context_size: 512,
        system_prompt: "You are an expert software engineer. Write clean, correct, well-structured code. Follow best practices for the language and framework in use. Be precise and avoid unnecessary verbosity in explanations."
    )

    static let precise = GenerationProfile(
        name: "Precise", temp: 0.1, top_p: 0.8, top_k: 10, min_p: 0.15,
        max_tokens: 4096, repetition_penalty: 1.1, repetition_context_size: 512,
        system_prompt: "You are a careful, precise assistant. Prioritize accuracy and correctness above all else. If uncertain, say so. Avoid speculation and clearly distinguish facts from inferences."
    )

    static let creative = GenerationProfile(
        name: "Creative", temp: 0.9, top_p: 0.95, top_k: 80, min_p: 0.02,
        max_tokens: 4096, repetition_penalty: 1.2, repetition_context_size: 256,
        system_prompt: "You are a creative, imaginative assistant. Explore ideas freely, offer novel perspectives, and embrace unconventional approaches when appropriate."
    )

    static let reasoning = GenerationProfile(
        name: "Reasoning", temp: 0.3, top_p: 0.85, top_k: 30, min_p: 0.1,
        max_tokens: 8192, repetition_penalty: 1.1, repetition_context_size: 512,
        system_prompt: "You are an analytical reasoning assistant. Think step by step. Break complex problems into parts. Show your work and verify your conclusions before presenting them."
    )

    static let builtins: [GenerationProfile] = [.default, .coding, .precise, .creative, .reasoning]
}

// MARK: - System Prompt

struct SystemPrompt: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let prompt: String
    let source: String

    static let builtins: [SystemPrompt] = [
        SystemPrompt(name: "Software Engineer", prompt: "You are an expert software engineer. Write clean, correct, well-structured code. Follow best practices for the language and framework in use. Explain your reasoning when making architectural decisions. Prioritize readability and maintainability.", source: "built-in"),
        SystemPrompt(name: "Code Reviewer", prompt: "You are a thorough code reviewer. Analyze code for bugs, security vulnerabilities, performance issues, and style inconsistencies. Provide specific, actionable feedback with line references. Suggest concrete improvements rather than vague criticism.", source: "built-in"),
        SystemPrompt(name: "Debug Assistant", prompt: "You are a debugging specialist. When presented with errors, systematically analyze root causes. Start with the error message, trace the call stack, examine relevant code, and propose targeted fixes. Explain why the error occurred and how the fix addresses it.", source: "built-in"),
        SystemPrompt(name: "Technical Writer", prompt: "You are a technical documentation specialist. Write clear, concise documentation that serves both beginners and experienced developers. Use consistent formatting, include code examples, and organize content logically. Prefer active voice and direct language.", source: "built-in"),
        SystemPrompt(name: "System Architect", prompt: "You are a systems architect. Design scalable, maintainable software architectures. Consider trade-offs between complexity and simplicity, performance and maintainability. Explain your choices with diagrams where helpful. Anticipate failure modes and propose mitigations.", source: "built-in"),
        SystemPrompt(name: "Security Analyst", prompt: "You are a security-focused analyst. Evaluate code and systems for vulnerabilities including OWASP Top 10, injection attacks, authentication weaknesses, and data exposure. Recommend specific remediations with priority rankings. Follow defense-in-depth principles.", source: "built-in"),
        SystemPrompt(name: "Test Engineer", prompt: "You are a test engineering specialist. Write comprehensive test cases covering happy paths, edge cases, error conditions, and boundary values. Use appropriate testing frameworks and patterns. Ensure tests are isolated, deterministic, and maintainable.", source: "built-in"),
        SystemPrompt(name: "DevOps Engineer", prompt: "You are a DevOps and infrastructure specialist. Design CI/CD pipelines, container configurations, deployment strategies, and monitoring solutions. Prioritize reliability, reproducibility, and observability. Follow infrastructure-as-code principles.", source: "built-in"),
        SystemPrompt(name: "Data Scientist", prompt: "You are a data science specialist. Analyze data methodically, choose appropriate statistical methods, and communicate findings clearly. Show your work with visualizations when helpful. Distinguish between correlation and causation. Quantify uncertainty.", source: "built-in"),
        SystemPrompt(name: "API Designer", prompt: "You are an API design specialist. Create RESTful, consistent, and well-documented APIs. Follow established conventions for naming, versioning, error handling, and pagination. Consider backwards compatibility and developer experience.", source: "built-in"),
        SystemPrompt(name: "Refactoring Guide", prompt: "You are a refactoring specialist. Identify code smells and suggest incremental improvements that preserve behavior. Apply established patterns like Extract Method, Replace Conditional with Polymorphism, and Introduce Parameter Object. Each refactoring step should leave the codebase in a working state.", source: "built-in"),
        SystemPrompt(name: "Performance Optimizer", prompt: "You are a performance optimization specialist. Profile before optimizing. Identify bottlenecks using data, not intuition. Suggest targeted optimizations with measurable impact. Consider algorithmic complexity, memory access patterns, caching strategies, and concurrency.", source: "built-in"),
        SystemPrompt(name: "Concise Assistant", prompt: "Be concise. Answer directly without preamble. Use short sentences. Show code, not explanations of code. Only elaborate when asked.", source: "built-in"),
        SystemPrompt(name: "Pair Programmer", prompt: "You are a pair programming partner. Think out loud as you work through problems. Ask clarifying questions before diving into implementation. Suggest alternatives when you see them. Catch potential issues early. Keep the conversation collaborative.", source: "built-in"),
        SystemPrompt(name: "Explainer", prompt: "You are a patient teacher. Explain concepts from first principles, building up complexity gradually. Use analogies to connect new ideas to familiar ones. Check understanding before moving forward. Adapt your explanation style to the learner's level.", source: "built-in"),
        SystemPrompt(name: "Database Expert", prompt: "You are a database specialist covering SQL, NoSQL, and data modeling. Design efficient schemas, write optimized queries, plan migrations, and advise on indexing strategies. Consider data integrity, consistency requirements, and query patterns.", source: "built-in"),
        SystemPrompt(name: "Frontend Specialist", prompt: "You are a frontend development specialist. Build accessible, responsive, and performant user interfaces. Follow semantic HTML practices, use modern CSS layout techniques, and write clean component-based JavaScript/TypeScript. Consider cross-browser compatibility and progressive enhancement.", source: "built-in"),
        SystemPrompt(name: "MLX Expert", prompt: "You are an expert in Apple's MLX framework for machine learning on Apple Silicon. Help with model loading, quantization, fine-tuning, and inference optimization. Understand the MLX memory model, lazy evaluation, and unified memory architecture. Guide users through mlx-lm server setup and configuration.", source: "built-in"),
        SystemPrompt(name: "Git Workflow", prompt: "You are a Git workflow specialist. Help with branching strategies, merge conflict resolution, rebasing, cherry-picking, and repository management. Write clear commit messages following conventional commit format. Advise on code review processes and PR best practices.", source: "built-in"),
        SystemPrompt(name: "Shell Scripting", prompt: "You are a shell scripting expert covering bash, zsh, and fish. Write portable, robust scripts with proper error handling, input validation, and cleanup. Use shellcheck-compliant patterns. Prefer clarity over cleverness. Handle edge cases in file paths and user input.", source: "built-in"),
        SystemPrompt(name: "Rust Developer", prompt: "You are a Rust specialist. Write idiomatic Rust code leveraging the ownership system, traits, and type system for safety and performance. Use appropriate error handling patterns, follow Clippy recommendations, and structure crates cleanly. Explain borrow checker issues clearly.", source: "built-in"),
        SystemPrompt(name: "Swift Developer", prompt: "You are a Swift specialist for Apple platforms. Write modern Swift using protocols, generics, actors, and structured concurrency. Follow Apple's Human Interface Guidelines. Use SwiftUI where appropriate. Handle memory management with ARC awareness.", source: "built-in"),
        SystemPrompt(name: "Python Developer", prompt: "You are a Python specialist. Write Pythonic code following PEP 8 and PEP 20. Use type hints, dataclasses, and modern Python features. Choose appropriate libraries from the ecosystem. Structure packages cleanly with proper dependency management.", source: "built-in"),
        SystemPrompt(name: "Creative Writing", prompt: "You are a creative writing assistant. Help develop stories, characters, dialogue, and world-building. Offer constructive feedback on narrative structure, pacing, and voice. Suggest alternatives without overriding the author's vision.", source: "built-in"),
    ]
}

// MARK: - Cloud Auth Mode

/// How cloud models authenticate when launched through a runner.
enum CloudAuthMode: String, Codable, CaseIterable, Identifiable {
    /// Use the runner's native CLI subscription (Max, Pro, etc.) — no interposer override.
    case cliSubscription = "CLI Subscription"
    /// Use an API key through the Engrave interposer.
    case apiKey = "API Key"

    var id: String { rawValue }
}

// MARK: - Server State

enum ServerState: String, Codable {
    case stopped, starting, running, error
}

struct ServerStatus: Codable {
    var state: ServerState
    var modelName: String?
    var port: Int
    var pid: Int?
}

// MARK: - Cloud Models (loaded from ~/.config/mlx-launcher/cloud-models.json)

struct CloudModelEntry: Codable {
    let id: String
    let name: String
    let context: String?
    let notes: String?
}

struct CloudModelsConfig: Codable {
    let anthropic: [CloudModelEntry]?
    let openai: [CloudModelEntry]?
    let google: [CloudModelEntry]?

    enum CodingKeys: String, CodingKey {
        case anthropic, openai, google
    }
}

extension CloudModelsConfig {
    static let builtins = CloudModelsConfig(
        anthropic: [
            CloudModelEntry(id: "claude-opus-4-6", name: "Claude Opus 4.6", context: "1M", notes: nil),
            CloudModelEntry(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", context: "200K", notes: nil),
            CloudModelEntry(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", context: "200K", notes: nil),
        ],
        openai: [
            CloudModelEntry(id: "gpt-5.5", name: "GPT-5.5", context: "1M", notes: nil),
            CloudModelEntry(id: "gpt-5.5-mini", name: "GPT-5.5 Mini", context: "1M", notes: nil),
            CloudModelEntry(id: "o3-pro", name: "o3-pro", context: "200K", notes: "Reasoning"),
            CloudModelEntry(id: "o3", name: "o3", context: "200K", notes: "Reasoning"),
            CloudModelEntry(id: "o4-mini", name: "o4-mini", context: "200K", notes: "Reasoning"),
            CloudModelEntry(id: "gpt-4.1", name: "GPT-4.1", context: "1M", notes: nil),
            CloudModelEntry(id: "gpt-4.1-mini", name: "GPT-4.1 Mini", context: "1M", notes: nil),
            CloudModelEntry(id: "gpt-4.1-nano", name: "GPT-4.1 Nano", context: "1M", notes: nil),
        ],
        google: [
            CloudModelEntry(id: "gemini-3.1-pro", name: "Gemini Pro 3.1", context: "2M", notes: nil),
            CloudModelEntry(id: "gemini-3.1-flash", name: "Gemini Flash 3.1", context: "2M", notes: nil),
            CloudModelEntry(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", context: "1M", notes: nil),
            CloudModelEntry(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", context: "1M", notes: nil),
        ]
    )
}

/// Current builtin version — bump when updating the hardcoded model list.
private let cloudModelsBuiltinVersion = 3

func loadCloudModels() -> [MLXModel] {
    let configPath = NSHomeDirectory() + "/.config/mlx-launcher/cloud-models.json"
    let versionPath = NSHomeDirectory() + "/.config/mlx-launcher/cloud-models-version"
    let config: CloudModelsConfig

    let savedVersion = (try? String(contentsOfFile: versionPath, encoding: .utf8)).flatMap(Int.init) ?? 0

    if savedVersion >= cloudModelsBuiltinVersion,
       let data = FileManager.default.contents(atPath: configPath),
       let loaded = try? JSONDecoder().decode(CloudModelsConfig.self, from: data) {
        config = loaded
    } else {
        // Builtins are newer — re-seed the file
        config = .builtins
        let dir = NSHomeDirectory() + "/.config/mlx-launcher"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(CloudModelsConfig.builtins) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
        try? String(cloudModelsBuiltinVersion).write(toFile: versionPath, atomically: true, encoding: .utf8)
    }

    var models: [MLXModel] = []
    var idx = -1

    func add(_ entries: [CloudModelEntry]?, source: ModelSource) {
        for entry in entries ?? [] {
            let size = entry.context.map { "\($0) ctx" } ?? "Cloud"
            models.append(MLXModel(id: entry.id, index: idx, size: size, source: source))
            idx -= 1
        }
    }

    add(config.anthropic, source: .anthropic)
    add(config.openai, source: .openai)
    add(config.google, source: .google)

    // Dynamically fetch models from provider APIs when keys are available
    let dynamicModels = fetchDynamicCloudModels()
    var seen = Set(models.map(\.id))
    for m in dynamicModels where seen.insert(m.id).inserted {
        models.append(MLXModel(id: m.id, index: idx, size: m.size, source: m.source))
        idx -= 1
    }

    return models
}

/// Query provider /v1/models endpoints when API keys are set.
/// Runs synchronously (called from a detached task in AppState).
private func fetchDynamicCloudModels() -> [MLXModel] {
    var models: [MLXModel] = []
    let session = URLSession(configuration: .ephemeral)
    let semaphore = DispatchSemaphore(value: 0)

    struct ModelsResponse: Codable {
        struct ModelEntry: Codable { let id: String }
        let data: [ModelEntry]?
    }

    // OpenAI
    if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty {
        if let url = URL(string: "https://api.openai.com/v1/models") {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            session.dataTask(with: req) { data, resp, _ in
                defer { semaphore.signal() }
                guard let data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data),
                      let entries = decoded.data else { return }
                let chatModels = entries.filter { e in
                    let id = e.id.lowercased()
                    return (id.hasPrefix("gpt-") || id.hasPrefix("o")) && !id.contains("realtime") && !id.contains("audio") && !id.contains("tts") && !id.contains("dall") && !id.contains("whisper") && !id.contains("embedding")
                }
                for entry in chatModels {
                    models.append(MLXModel(id: entry.id, index: 0, size: "Cloud", source: .openai))
                }
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
        }
    }

    // Google
    if let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !apiKey.isEmpty {
        if let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") {
            let req = URLRequest(url: url, timeoutInterval: 8)
            struct GeminiModelsResponse: Codable {
                struct Model: Codable { let name: String; let displayName: String? }
                let models: [Model]?
            }
            session.dataTask(with: req) { data, resp, _ in
                defer { semaphore.signal() }
                guard let data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(GeminiModelsResponse.self, from: data),
                      let entries = decoded.models else { return }
                let chatModels = entries.filter { e in
                    let name = e.name.lowercased()
                    return name.contains("gemini") && !name.contains("embedding") && !name.contains("aqa")
                }
                for entry in chatModels {
                    let id = entry.name.replacingOccurrences(of: "models/", with: "")
                    models.append(MLXModel(id: id, index: 0, size: "Cloud", source: .google))
                }
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
        }
    }

    // Anthropic
    if let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty {
        if let url = URL(string: "https://api.anthropic.com/v1/models") {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            session.dataTask(with: req) { data, resp, _ in
                defer { semaphore.signal() }
                guard let data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data),
                      let entries = decoded.data else { return }
                for entry in entries {
                    models.append(MLXModel(id: entry.id, index: 0, size: "Cloud", source: .anthropic))
                }
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
        }
    }

    return models
}

// MARK: - Engine Registry Types

/// A registered inference engine endpoint (local or remote).
/// Covers every major inference backend: cloud APIs, self-hosted servers,
/// and local engines. Each engine has its own API format, auth, and parameter set.
struct EngineEndpoint: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String                // e.g. "Home Ollama", "Lab vLLM", "Local MLX"
    var backend: EngineBackend      // which backend type (determines API format + params)
    var baseURL: String             // e.g. "http://192.168.1.50:11434"
    var apiKeyEnv: String?          // env var name for auth (nil = no auth required)
    var extraHeaders: [String: String]  // additional HTTP headers
    var isRemote: Bool              // true = network endpoint, false = local
    var enabled: Bool
    var parameters: EngineParameters    // engine-specific generation parameters

    init(name: String, backend: EngineBackend = .chatCompletions, baseURL: String,
         apiKeyEnv: String? = nil, extraHeaders: [String: String] = [:],
         isRemote: Bool = true, enabled: Bool = true, parameters: EngineParameters = .defaults) {
        self.id = UUID()
        self.name = name
        self.backend = backend
        self.baseURL = baseURL
        self.apiKeyEnv = apiKeyEnv
        self.extraHeaders = extraHeaders
        self.isRemote = isRemote
        self.enabled = enabled
        self.parameters = parameters
    }

    /// Interposer type string for BackendClient routing
    var type: String { backend.interposerType }

    static let builtins: [EngineEndpoint] = [
        // Local
        EngineEndpoint(name: "Local MLX", backend: .mlx,
                       baseURL: "http://127.0.0.1:8421", isRemote: false),
        // Cloud APIs
        EngineEndpoint(name: "Anthropic", backend: .anthropic,
                       baseURL: "https://api.anthropic.com", apiKeyEnv: "ANTHROPIC_API_KEY"),
        EngineEndpoint(name: "OpenAI", backend: .openai,
                       baseURL: "https://api.openai.com", apiKeyEnv: "OPENAI_API_KEY"),
        EngineEndpoint(name: "Google Gemini", backend: .gemini,
                       baseURL: "https://generativelanguage.googleapis.com", apiKeyEnv: "GOOGLE_API_KEY"),
        // Self-hosted (disabled by default — user enables when they have one)
        EngineEndpoint(name: "Ollama", backend: .ollama,
                       baseURL: "http://localhost:11434", apiKeyEnv: "OLLAMA_API_KEY", enabled: false),
        EngineEndpoint(name: "vLLM", backend: .vllm,
                       baseURL: "http://localhost:8000", apiKeyEnv: "VLLM_API_KEY", enabled: false),
        EngineEndpoint(name: "TGI", backend: .tgi,
                       baseURL: "http://localhost:8080", enabled: false),
        EngineEndpoint(name: "llama.cpp", backend: .llamaCpp,
                       baseURL: "http://localhost:8080", enabled: false),
        EngineEndpoint(name: "LM Studio", backend: .lmStudio,
                       baseURL: "http://localhost:1234", enabled: false),
        EngineEndpoint(name: "Kobold", backend: .kobold,
                       baseURL: "http://localhost:5001", enabled: false),
        EngineEndpoint(name: "TabbyAPI", backend: .tabbyAPI,
                       baseURL: "http://localhost:5000", apiKeyEnv: "TABBY_API_KEY", enabled: false),
        EngineEndpoint(name: "Aphrodite", backend: .aphrodite,
                       baseURL: "http://localhost:2242", enabled: false),
        EngineEndpoint(name: "Together AI", backend: .togetherAI,
                       baseURL: "https://api.together.xyz", apiKeyEnv: "TOGETHER_API_KEY", enabled: false),
        EngineEndpoint(name: "Fireworks AI", backend: .fireworksAI,
                       baseURL: "https://api.fireworks.ai", apiKeyEnv: "FIREWORKS_API_KEY", enabled: false),
        EngineEndpoint(name: "Groq", backend: .groq,
                       baseURL: "https://api.groq.com", apiKeyEnv: "GROQ_API_KEY", enabled: false),
        EngineEndpoint(name: "Mistral", backend: .mistral,
                       baseURL: "https://api.mistral.ai", apiKeyEnv: "MISTRAL_API_KEY", enabled: false),
        EngineEndpoint(name: "DeepSeek", backend: .deepseek,
                       baseURL: "https://api.deepseek.com", apiKeyEnv: "DEEPSEEK_API_KEY", enabled: false),
        EngineEndpoint(name: "Cerebras", backend: .cerebras,
                       baseURL: "https://api.cerebras.ai", apiKeyEnv: "CEREBRAS_API_KEY", enabled: false),
        EngineEndpoint(name: "SambaNova", backend: .sambanova,
                       baseURL: "https://api.sambanova.ai", apiKeyEnv: "SAMBANOVA_API_KEY", enabled: false),
        EngineEndpoint(name: "Cohere", backend: .cohere,
                       baseURL: "https://api.cohere.com", apiKeyEnv: "COHERE_API_KEY", enabled: false),
        EngineEndpoint(name: "HuggingFace Inference", backend: .huggingfaceInference,
                       baseURL: "https://api-inference.huggingface.co", apiKeyEnv: "HF_TOKEN", enabled: false),
        EngineEndpoint(name: "HuggingFace TGI Endpoint", backend: .huggingfaceTGI,
                       baseURL: "https://your-endpoint.endpoints.huggingface.cloud", apiKeyEnv: "HF_TOKEN", enabled: false),
    ]
}

/// All known inference backend types.
/// Each maps to an API wire format that the interposer knows how to translate.
enum EngineBackend: String, Codable, CaseIterable, Equatable {
    // Local engines
    case mlx                    // Native Swift MLX (built-in)
    case llamaCpp = "llama_cpp" // llama.cpp server (OpenAI-compat)
    case lmStudio = "lm_studio" // LM Studio (OpenAI-compat)
    case kobold                 // KoboldCpp (OpenAI-compat)

    // Self-hosted OpenAI-compatible
    case ollama                 // Ollama (OpenAI-compat + /api/generate)
    case vllm                   // vLLM (OpenAI-compat)
    case tgi                    // HuggingFace TGI (OpenAI-compat)
    case tabbyAPI = "tabby_api" // TabbyAPI (OpenAI-compat + ExLlamaV2)
    case aphrodite              // Aphrodite (OpenAI-compat, fork of vLLM)

    // Cloud APIs — native formats
    case anthropic              // Anthropic Messages API
    case openai                 // OpenAI Chat Completions / Responses
    case gemini                 // Google Gemini generateContent
    case mistral                // Mistral (OpenAI-compat)
    case cohere                 // Cohere Chat API
    case deepseek               // DeepSeek (OpenAI-compat)

    // Cloud inference platforms
    case togetherAI = "together_ai"     // Together AI (OpenAI-compat)
    case fireworksAI = "fireworks_ai"   // Fireworks AI (OpenAI-compat)
    case groq                           // Groq (OpenAI-compat)
    case cerebras                       // Cerebras (OpenAI-compat)
    case sambanova                      // SambaNova (OpenAI-compat)

    // HuggingFace
    case huggingfaceInference = "hf_inference"  // HF Inference API
    case huggingfaceTGI = "hf_tgi"              // HF Inference Endpoints (TGI)
    case chatCompletions = "chat_completions"   // Generic OpenAI-compatible

    /// The wire format type for the interposer's BackendClient
    var interposerType: String {
        switch self {
        case .anthropic: return "anthropic"
        case .openai: return "openai"
        case .gemini: return "gemini"
        case .cohere: return "chat_completions" // Cohere v2 is OpenAI-compat
        default: return "chat_completions"      // Most backends are OpenAI-compatible
        }
    }

    var displayName: String {
        switch self {
        case .mlx: return "MLX (Native Swift)"
        case .llamaCpp: return "llama.cpp"
        case .lmStudio: return "LM Studio"
        case .kobold: return "KoboldCpp"
        case .ollama: return "Ollama"
        case .vllm: return "vLLM"
        case .tgi: return "HuggingFace TGI"
        case .tabbyAPI: return "TabbyAPI"
        case .aphrodite: return "Aphrodite"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .mistral: return "Mistral"
        case .cohere: return "Cohere"
        case .deepseek: return "DeepSeek"
        case .togetherAI: return "Together AI"
        case .fireworksAI: return "Fireworks AI"
        case .groq: return "Groq"
        case .cerebras: return "Cerebras"
        case .sambanova: return "SambaNova"
        case .huggingfaceInference: return "HF Inference API"
        case .huggingfaceTGI: return "HF TGI Endpoint"
        case .chatCompletions: return "OpenAI-Compatible"
        }
    }

    /// Parameters this backend supports
    var supportedParameters: Set<EngineParameter> {
        switch self {
        case .anthropic:
            return [.temperature, .topP, .topK, .maxTokens, .stopSequences, .systemPrompt]
        case .openai:
            return [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty,
                    .stopSequences, .seed, .systemPrompt, .responseFormat]
        case .gemini:
            return [.temperature, .topP, .topK, .maxTokens, .stopSequences, .systemPrompt]
        case .ollama:
            return [.temperature, .topP, .topK, .maxTokens, .repeatPenalty, .seed,
                    .numCtx, .numGPU, .mirostat, .mirostatTau, .mirostatEta,
                    .systemPrompt, .stopSequences, .tfsZ, .typicalP]
        case .vllm, .aphrodite:
            return [.temperature, .topP, .topK, .maxTokens, .frequencyPenalty,
                    .presencePenalty, .repetitionPenalty, .seed, .stopSequences,
                    .minP, .bestOf, .systemPrompt, .responseFormat]
        case .tgi, .huggingfaceTGI:
            return [.temperature, .topP, .topK, .maxTokens, .repetitionPenalty,
                    .seed, .stopSequences, .typicalP, .watermark]
        case .llamaCpp:
            return [.temperature, .topP, .topK, .maxTokens, .repeatPenalty,
                    .seed, .minP, .tfsZ, .typicalP, .mirostat, .mirostatTau,
                    .mirostatEta, .stopSequences, .numCtx, .systemPrompt]
        case .groq, .togetherAI, .fireworksAI, .cerebras, .sambanova,
             .mistral, .deepseek, .cohere:
            return [.temperature, .topP, .maxTokens, .stopSequences,
                    .frequencyPenalty, .presencePenalty, .seed, .systemPrompt]
        default:
            return [.temperature, .topP, .topK, .maxTokens, .stopSequences, .systemPrompt]
        }
    }
}

/// All possible generation parameters across all inference backends.
enum EngineParameter: String, Codable, CaseIterable {
    case temperature            // 0.0-2.0, controls randomness
    case topP = "top_p"         // 0.0-1.0, nucleus sampling
    case topK = "top_k"         // 1-100, top-k sampling
    case minP = "min_p"         // 0.0-1.0, minimum probability threshold
    case maxTokens = "max_tokens"
    case frequencyPenalty = "frequency_penalty"   // -2.0 to 2.0
    case presencePenalty = "presence_penalty"     // -2.0 to 2.0
    case repetitionPenalty = "repetition_penalty" // 0.0-2.0
    case repeatPenalty = "repeat_penalty"         // Ollama/llama.cpp variant
    case seed                   // Int, for reproducibility
    case stopSequences = "stop" // [String]
    case systemPrompt = "system_prompt"
    case responseFormat = "response_format"       // "json_object", "text"
    case numCtx = "num_ctx"     // Context window size (Ollama/llama.cpp)
    case numGPU = "num_gpu"     // GPU layers (Ollama)
    case mirostat               // 0/1/2 (Ollama/llama.cpp)
    case mirostatTau = "mirostat_tau"
    case mirostatEta = "mirostat_eta"
    case tfsZ = "tfs_z"         // Tail-free sampling
    case typicalP = "typical_p" // Locally typical sampling
    case bestOf = "best_of"     // Generate N, return best (vLLM)
    case watermark              // TGI watermarking

    var displayName: String {
        switch self {
        case .temperature: return "Temperature"
        case .topP: return "Top P"
        case .topK: return "Top K"
        case .minP: return "Min P"
        case .maxTokens: return "Max Tokens"
        case .frequencyPenalty: return "Frequency Penalty"
        case .presencePenalty: return "Presence Penalty"
        case .repetitionPenalty: return "Repetition Penalty"
        case .repeatPenalty: return "Repeat Penalty"
        case .seed: return "Seed"
        case .stopSequences: return "Stop Sequences"
        case .systemPrompt: return "System Prompt"
        case .responseFormat: return "Response Format"
        case .numCtx: return "Context Window"
        case .numGPU: return "GPU Layers"
        case .mirostat: return "Mirostat"
        case .mirostatTau: return "Mirostat Tau"
        case .mirostatEta: return "Mirostat Eta"
        case .tfsZ: return "TFS-Z"
        case .typicalP: return "Typical P"
        case .bestOf: return "Best Of"
        case .watermark: return "Watermark"
        }
    }

    var description: String {
        switch self {
        case .temperature: return "Controls randomness. Higher = more creative, lower = more deterministic."
        case .topP: return "Nucleus sampling. Only consider tokens with cumulative probability above this."
        case .topK: return "Only consider the top K most likely tokens."
        case .minP: return "Minimum probability threshold relative to the most likely token."
        case .maxTokens: return "Maximum number of tokens to generate."
        case .frequencyPenalty: return "Penalize tokens based on their frequency in the text so far."
        case .presencePenalty: return "Penalize tokens based on whether they appear in the text so far."
        case .repetitionPenalty: return "Penalize repeated tokens. 1.0 = no penalty."
        case .repeatPenalty: return "Penalize repeated tokens (Ollama/llama.cpp variant)."
        case .seed: return "Random seed for reproducible generation."
        case .stopSequences: return "Stop generation when these strings are encountered."
        case .systemPrompt: return "System-level instructions prepended to the conversation."
        case .responseFormat: return "Force output format (e.g. JSON mode)."
        case .numCtx: return "Context window size in tokens."
        case .numGPU: return "Number of GPU layers to offload."
        case .mirostat: return "Mirostat sampling mode (0=disabled, 1=v1, 2=v2)."
        case .mirostatTau: return "Target perplexity for Mirostat."
        case .mirostatEta: return "Learning rate for Mirostat."
        case .tfsZ: return "Tail-free sampling parameter. 1.0 = disabled."
        case .typicalP: return "Locally typical sampling threshold."
        case .bestOf: return "Generate N completions and return the best."
        case .watermark: return "Enable text watermarking (TGI)."
        }
    }
}

/// Engine-specific parameter overrides. Stored per-engine, sent with requests.
struct EngineParameters: Codable, Equatable {
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var minP: Double?
    var maxTokens: Int?
    var frequencyPenalty: Double?
    var presencePenalty: Double?
    var repetitionPenalty: Double?
    var seed: Int?
    var stopSequences: [String]?
    var numCtx: Int?
    var numGPU: Int?
    var mirostat: Int?
    var mirostatTau: Double?
    var mirostatEta: Double?
    var tfsZ: Double?
    var typicalP: Double?
    var responseFormat: String?

    static let defaults = EngineParameters()
}

/// Maps a model name (or prefix) to an engine endpoint.
struct ModelRouteMapping: Identifiable, Codable, Equatable {
    let id: UUID
    var pattern: String             // model name prefix, e.g. "claude-", "ollama/", "my-lab/"
    var engineName: String          // references EngineEndpoint.name
    var stripPrefix: Bool           // if true, "ollama/mistral" → "mistral" when forwarding
    var description: String?

    init(pattern: String, engineName: String, stripPrefix: Bool = false, description: String? = nil) {
        self.id = UUID()
        self.pattern = pattern
        self.engineName = engineName
        self.stripPrefix = stripPrefix
        self.description = description
    }

    static let builtins: [ModelRouteMapping] = [
        ModelRouteMapping(pattern: "claude-", engineName: "Anthropic", description: "Anthropic Claude models"),
        ModelRouteMapping(pattern: "gpt-", engineName: "OpenAI", description: "OpenAI GPT models"),
        ModelRouteMapping(pattern: "o1-", engineName: "OpenAI", description: "OpenAI o1 reasoning"),
        ModelRouteMapping(pattern: "o3-", engineName: "OpenAI", description: "OpenAI o3 reasoning"),
        ModelRouteMapping(pattern: "o4-", engineName: "OpenAI", description: "OpenAI o4 reasoning"),
        ModelRouteMapping(pattern: "chatgpt-", engineName: "OpenAI", description: "OpenAI ChatGPT models"),
        ModelRouteMapping(pattern: "gemini-", engineName: "Google Gemini", description: "Google Gemini models"),
    ]
}

// MARK: - UIA Chat Types

struct UIAChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    var taskGraphJSON: String?  // serialized UIATaskGraph for display

    init(role: ChatRole, content: String, taskGraphJSON: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.taskGraphJSON = taskGraphJSON
    }
}

enum ChatRole: String, Codable {
    case user, assistant, system
}

struct UIATaskGraph: Identifiable, Codable {
    let id: UUID
    var nodes: [UIATaskNode]
    var edges: [UIATaskEdge]

    init(nodes: [UIATaskNode] = [], edges: [UIATaskEdge] = []) {
        self.id = UUID()
        self.nodes = nodes
        self.edges = edges
    }
}

struct UIATaskEdge: Codable, Identifiable {
    var id: String { "\(from)->\(to)" }
    let from: UUID
    let to: UUID
}

struct UIATaskNode: Identifiable, Codable {
    let id: UUID
    var title: String
    var status: TaskNodeStatus
    var complexity: TaskComplexity
    var assignedModel: String?
    var tokenBudget: UInt64?

    init(title: String, status: TaskNodeStatus = .pending, complexity: TaskComplexity = .simple, assignedModel: String? = nil, tokenBudget: UInt64? = nil) {
        self.id = UUID()
        self.title = title
        self.status = status
        self.complexity = complexity
        self.assignedModel = assignedModel
        self.tokenBudget = tokenBudget
    }
}

enum TaskNodeStatus: String, Codable, CaseIterable {
    case pending, running, completed, failed
}

enum TaskComplexity: String, Codable, CaseIterable {
    case trivial, simple, medium, complex, critical

    var tokenBudget: UInt64 {
        switch self {
        case .trivial:  return 5_000
        case .simple:   return 15_000
        case .medium:   return 50_000
        case .complex:  return 100_000
        case .critical: return 150_000
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .trivial:  return 30
        case .simple:   return 120
        case .medium:   return 300
        case .complex:  return 600
        case .critical: return 900
        }
    }
}

// MARK: - HITL Types

struct HITLInterception: Identifiable, Codable {
    let id: UUID
    var toolName: String
    var toolInput: String
    var severity: String  // "block", "warn", "modify"
    var reason: String
    var timestamp: Date
    var expiresAt: Date
    var status: HITLStatus
    var steerDirective: String?
    var relatedIds: [UUID]

    init(toolName: String, toolInput: String, severity: String, reason: String, timeoutSeconds: Int = 60) {
        self.id = UUID()
        self.toolName = toolName
        self.toolInput = toolInput
        self.severity = severity
        self.reason = reason
        self.timestamp = Date()
        self.expiresAt = Date().addingTimeInterval(Double(timeoutSeconds))
        self.status = .pending
        self.steerDirective = nil
        self.relatedIds = []
    }

    var isExpired: Bool { Date() >= expiresAt }
    var remainingSeconds: Int { max(0, Int(expiresAt.timeIntervalSinceNow)) }
}

enum HITLStatus: String, Codable, CaseIterable {
    case pending, allowed, denied, steered, expired
}

// MARK: - Dashboard Types

struct DashboardConfig: Codable {
    var panels: [DashboardPanelConfig]
    var activeLayout: String

    static let `default` = DashboardConfig(
        panels: [
            DashboardPanelConfig(type: .agentActivity),
            DashboardPanelConfig(type: .governanceEvents),
            DashboardPanelConfig(type: .servicesMonitor),
        ],
        activeLayout: "default"
    )
}

struct DashboardPanelConfig: Codable, Identifiable {
    let id: UUID
    var type: DashboardPanelType
    var visible: Bool

    init(type: DashboardPanelType, visible: Bool = true) {
        self.id = UUID()
        self.type = type
        self.visible = visible
    }
}

enum DashboardPanelType: String, Codable, CaseIterable {
    case agentActivity = "Agent Activity"
    case taskDAGViewer = "Task DAG"
    case governanceEvents = "Governance Events"
    case diffViewer = "Diff Viewer"
    case worktreeStatus = "Worktree Status"
    case fileChangeFeed = "File Changes"
    case merkleDSGLog = "Provenance Log"
    case servicesMonitor = "Services Monitor"

    var icon: String {
        switch self {
        case .agentActivity:    return "list.bullet.rectangle"
        case .taskDAGViewer:    return "point.3.connected.trianglepath.dotted"
        case .governanceEvents: return "shield.checkered"
        case .diffViewer:       return "doc.on.doc"
        case .worktreeStatus:   return "arrow.triangle.branch"
        case .fileChangeFeed:   return "doc.badge.clock"
        case .merkleDSGLog:     return "link"
        case .servicesMonitor:  return "server.rack"
        }
    }
}

struct AgentActivityEvent: Identifiable, Codable {
    let id: UUID
    var agentId: String
    var action: String
    var detail: String
    var risk: String  // "safe", "warn", "danger"
    var timestamp: Date

    init(agentId: String, action: String, detail: String, risk: String = "safe") {
        self.id = UUID()
        self.agentId = agentId
        self.action = action
        self.detail = detail
        self.risk = risk
        self.timestamp = Date()
    }
}

struct FileChangeEvent: Identifiable, Codable {
    let id: UUID
    var path: String
    var changeType: String  // "add", "modify", "delete"
    var agentId: String?
    var timestamp: Date

    init(path: String, changeType: String, agentId: String? = nil) {
        self.id = UUID()
        self.path = path
        self.changeType = changeType
        self.agentId = agentId
        self.timestamp = Date()
    }
}

struct WorktreeEntry: Identifiable {
    let id: UUID
    var path: String
    var branch: String
    var agentId: String?
    var hasChanges: Bool

    init(path: String, branch: String, agentId: String? = nil, hasChanges: Bool = false) {
        self.id = UUID()
        self.path = path
        self.branch = branch
        self.agentId = agentId
        self.hasChanges = hasChanges
    }
}

struct MerkleDSGEntry: Identifiable, Codable {
    let id: UUID
    var sequence: UInt64
    var eventType: String
    var actor: String
    var contentHash: String
    var parentIds: [UUID]
    var timestamp: Date
    var verified: Bool

    init(sequence: UInt64, eventType: String, actor: String, contentHash: String = "", parentIds: [UUID] = []) {
        self.id = UUID()
        self.sequence = sequence
        self.eventType = eventType
        self.actor = actor
        self.contentHash = contentHash
        self.parentIds = parentIds
        self.timestamp = Date()
        self.verified = false
    }
}

// Settings types are defined in Settings.swift (SettingsManager + AppSettings)
