import Foundation

/// Discovers available cloud model names from two sources:
/// 1. Runner CLIs (e.g. `codex debug models` → OpenAI model slugs)
/// 2. The shared cloud-models.json config (Anthropic, OpenAI, Google)
///
/// Results are cached with a TTL so the interposer model-list endpoint stays fast.
public actor RunnerModelDiscovery {
    private var cache: [String: [String]] = [:]  // facade → model names
    private var lastFetch: Date = .distantPast
    private static let cacheTTL: TimeInterval = 600 // 10 minutes

    /// Search paths for runner binaries
    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.cargo/bin",
    ]

    public init() {}

    /// Get all discovered model names for a given facade (e.g. "openai_compatible", "gemini", "anthropic").
    public func models(for facade: String) async -> [String] {
        if Date().timeIntervalSince(lastFetch) < Self.cacheTTL, let cached = cache[facade] {
            return cached
        }
        await refresh()
        return cache[facade] ?? []
    }

    /// Get all discovered model names across all facades.
    public func allModels() async -> [String: [String]] {
        if Date().timeIntervalSince(lastFetch) < Self.cacheTTL, !cache.isEmpty {
            return cache
        }
        await refresh()
        return cache
    }

    /// Force refresh: load from cloud-models.json + query runner CLIs.
    public func refresh() async {
        var results: [String: Set<String>] = [:]

        // 1. Load from ~/.config/mlx-launcher/cloud-models.json (shared with MLX Launcher app)
        let configModels = Self.loadCloudModelsConfig()
        for (facade, names) in configModels {
            results[facade, default: []].formUnion(names)
        }

        // 2. Query Codex CLI for its model catalog
        if let codexPath = Self.findBinary("codex") {
            let codexModels = Self.queryCodexModels(path: codexPath)
            if !codexModels.isEmpty {
                results["openai_compatible", default: []].formUnion(codexModels)
                results["openai", default: []].formUnion(codexModels)
            }
        }

        // Convert sets to arrays
        cache = results.mapValues { Array($0).sorted() }
        lastFetch = Date()
    }

    // MARK: - Cloud Models Config

    /// Read ~/.config/mlx-launcher/cloud-models.json and extract model IDs per provider.
    private static func loadCloudModelsConfig() -> [String: [String]] {
        let path = NSHomeDirectory() + "/.config/mlx-launcher/cloud-models.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var result: [String: [String]] = [:]

        // Each key is a provider name ("anthropic", "openai", "google")
        // Each value is an array of {id: "model-id", ...}
        for (provider, entries) in json {
            guard let models = entries as? [[String: Any]] else { continue }
            let ids = models.compactMap { $0["id"] as? String }
            guard !ids.isEmpty else { continue }

            // Map provider names to interposer facade names
            switch provider {
            case "anthropic":
                result["anthropic"] = ids
            case "openai":
                result["openai_compatible"] = ids
                result["openai"] = ids
            case "google":
                result["gemini"] = ids
            default:
                break
            }
        }
        return result
    }

    // MARK: - Runner CLI Queries

    /// Query `codex debug models` and extract model slugs from JSON output.
    private static func queryCodexModels(path: String) -> [String] {
        let lines = runCommand(path: path, args: ["debug", "models"])
        let json = lines.joined()
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["slug"] as? String }
    }

    // MARK: - Helpers

    private static func findBinary(_ name: String) -> String? {
        for dir in searchPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func runCommand(path: String, args: [String]) -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            let deadline = DispatchTime.now() + .seconds(10)
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if proc.isRunning { proc.terminate() }
            }
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output.components(separatedBy: "\n")
        } catch {
            return []
        }
    }
}
