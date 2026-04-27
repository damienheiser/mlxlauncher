import Foundation
import Combine

// MARK: - Settings Data Model

struct AppSettings: Codable, Equatable {
    var services: ServiceSettings
    var inference: InferenceSettings
    var ui: UISettings
    var advanced: AdvancedSettings

    static let defaults = AppSettings(
        services: .defaults,
        inference: .defaults,
        ui: .defaults,
        advanced: .defaults
    )

    struct ServiceSettings: Codable, Equatable {
        var mlxPort: Int
        var interposerPort: Int
        var autoStartMLX: Bool
        var autoStartInterposer: Bool

        static let defaults = ServiceSettings(
            mlxPort: 8080,
            interposerPort: 8888,
            autoStartMLX: false,
            autoStartInterposer: false
        )
    }

    struct InferenceSettings: Codable, Equatable {
        var defaultProfile: String
        var gpuCacheLimit: Double          // fraction 0.0–1.0
        var contextLength: Int
        var quantization: String           // "4bit", "8bit", "none"

        static let defaults = InferenceSettings(
            defaultProfile: "Default",
            gpuCacheLimit: 0.9,
            contextLength: 4096,
            quantization: "4bit"
        )
    }

    struct UISettings: Codable, Equatable {
        var theme: String
        var showTokensPerSecond: Bool
        var compactMode: Bool
        var fontSize: Int

        static let defaults = UISettings(
            theme: "synthaer-dark",
            showTokensPerSecond: true,
            compactMode: false,
            fontSize: 14
        )
    }

    struct AdvancedSettings: Codable, Equatable {
        var debugLogging: Bool
        var logRetentionDays: Int
        var telemetryEnabled: Bool
        var customEnvironment: [String: String]

        static let defaults = AdvancedSettings(
            debugLogging: false,
            logRetentionDays: 7,
            telemetryEnabled: false,
            customEnvironment: [:]
        )
    }
}

// MARK: - Layered Settings Manager

/// Layered settings: Defaults -> User (~/.config/mlx-launcher/settings.json)
///                  -> Workspace (.engrave/settings.json) -> Runtime (env vars)
@MainActor
class SettingsManager: ObservableObject {
    @Published var resolved: AppSettings
    @Published var userSettings: AppSettings
    @Published var workspaceSettings: AppSettings?

    private let userSettingsPath: String
    private let workspaceSettingsPath: String

    init() {
        let configDir = NSHomeDirectory() + "/.config/mlx-launcher"
        userSettingsPath = configDir + "/settings.json"
        workspaceSettingsPath = FileManager.default.currentDirectoryPath + "/.engrave/settings.json"

        // Initialize all stored properties first
        var loadedUser: AppSettings = .defaults
        if let data = FileManager.default.contents(atPath: configDir + "/settings.json"),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loadedUser = loaded
        }
        userSettings = loadedUser

        var loadedWorkspace: AppSettings? = nil
        let wsPath = FileManager.default.currentDirectoryPath + "/.engrave/settings.json"
        if let data = FileManager.default.contents(atPath: wsPath),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loadedWorkspace = loaded
        }
        workspaceSettings = loadedWorkspace

        resolved = SettingsManager.merge(base: .defaults, user: loadedUser, workspace: loadedWorkspace)
        applyRuntimeOverrides()
    }

    /// Re-resolve all layers and apply runtime overrides.
    func reloadAll() {
        if let data = FileManager.default.contents(atPath: userSettingsPath),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            userSettings = loaded
        }
        if let data = FileManager.default.contents(atPath: workspaceSettingsPath),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            workspaceSettings = loaded
        } else {
            workspaceSettings = nil
        }
        resolved = SettingsManager.merge(base: .defaults, user: userSettings, workspace: workspaceSettings)
        applyRuntimeOverrides()
    }

    private func applyRuntimeOverrides() {
        let env = ProcessInfo.processInfo.environment
        if let port = env["ENGRAVE_MLX_PORT"].flatMap(Int.init) {
            resolved.services.mlxPort = port
        }
        if let port = env["ENGRAVE_INTERPOSER_PORT"].flatMap(Int.init) {
            resolved.services.interposerPort = port
        }
        if env["ENGRAVE_DEBUG"] == "1" {
            resolved.advanced.debugLogging = true
        }
        if let theme = env["ENGRAVE_THEME"], !theme.isEmpty {
            resolved.ui.theme = theme
        }
    }

    // MARK: - Persistence

    func save() {
        let dir = (userSettingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(resolved) {
            try? data.write(to: URL(fileURLWithPath: userSettingsPath))
        }
        userSettings = resolved
    }

    func saveWorkspace() {
        let dir = (workspaceSettingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(resolved) {
            try? data.write(to: URL(fileURLWithPath: workspaceSettingsPath))
        }
        workspaceSettings = resolved
    }

    func resetToDefaults() {
        resolved = .defaults
        save()
    }

    func resetWorkspace() {
        try? FileManager.default.removeItem(atPath: workspaceSettingsPath)
        workspaceSettings = nil
        resolved = SettingsManager.merge(base: .defaults, user: userSettings, workspace: nil)
        applyRuntimeOverrides()
    }

    // MARK: - Layer Merge

    /// Workspace settings override user settings, which override defaults.
    /// Uses the workspace value when present, otherwise falls through to user/default.
    private static func merge(base: AppSettings, user: AppSettings, workspace: AppSettings?) -> AppSettings {
        let ws = workspace ?? user
        var merged = AppSettings.defaults
        // Services
        merged.services.mlxPort = ws.services.mlxPort
        merged.services.interposerPort = ws.services.interposerPort
        merged.services.autoStartMLX = ws.services.autoStartMLX
        merged.services.autoStartInterposer = ws.services.autoStartInterposer
        // Inference
        merged.inference.defaultProfile = ws.inference.defaultProfile
        merged.inference.gpuCacheLimit = ws.inference.gpuCacheLimit
        merged.inference.contextLength = ws.inference.contextLength
        merged.inference.quantization = ws.inference.quantization
        // UI
        merged.ui.theme = ws.ui.theme
        merged.ui.showTokensPerSecond = ws.ui.showTokensPerSecond
        merged.ui.compactMode = ws.ui.compactMode
        merged.ui.fontSize = ws.ui.fontSize
        // Advanced
        merged.advanced.debugLogging = ws.advanced.debugLogging
        merged.advanced.logRetentionDays = ws.advanced.logRetentionDays
        merged.advanced.telemetryEnabled = ws.advanced.telemetryEnabled
        merged.advanced.customEnvironment = user.advanced.customEnvironment
            .merging(ws.advanced.customEnvironment) { _, new in new }
        return merged
    }

    // MARK: - Convenience

    var mlxPort: Int { resolved.services.mlxPort }
    var interposerPort: Int { resolved.services.interposerPort }
    var isDebug: Bool { resolved.advanced.debugLogging }
    var themeName: String { resolved.ui.theme }

    /// Build environment dictionary for launching subprocesses,
    /// layering custom env vars onto the current process environment.
    func launchEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in resolved.advanced.customEnvironment {
            env[key] = value
        }
        env["MLX_PORT"] = String(resolved.services.mlxPort)
        return env
    }

    // MARK: - Import / Export

    func exportJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(resolved) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func importJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let imported = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return false
        }
        resolved = imported
        save()
        return true
    }
}
