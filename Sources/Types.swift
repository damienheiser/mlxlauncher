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
}

// MARK: - System Prompt

struct SystemPrompt: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let prompt: String
    let source: String
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

func loadCloudModels() -> [MLXModel] {
    let configPath = NSHomeDirectory() + "/.config/mlx-launcher/cloud-models.json"
    guard let data = FileManager.default.contents(atPath: configPath),
          let config = try? JSONDecoder().decode(CloudModelsConfig.self, from: data) else {
        return []
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

    return models
}
