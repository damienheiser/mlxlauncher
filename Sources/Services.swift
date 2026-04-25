import Foundation
import Combine
import EngraveInterposer
import EngraveGovernance

// MARK: - App State (shared across views)

@MainActor
class AppState: ObservableObject {
    @Published var localModels: [MLXModel] = []
    @Published var allModels: [MLXModel] = []
    @Published var selectedModel: MLXModel?
    @Published var selectedRunner: Runner = allRunners[0]
    @Published var serverStatus = ServerStatus(state: .stopped, port: 1234)
    @Published var profiles: [GenerationProfile] = []
    @Published var activeProfile: GenerationProfile = .default
    @Published var prompts: [SystemPrompt] = []
    @Published var serverLog: [String] = []
    @Published var interposerLog: [String] = []
    @Published var interposerRunning = false
    @Published var runnerSettings: [String: RunnerLaunchSettings] = [:]
    @Published var extraMLXServerArguments = ""
    @Published var modelStore = ModelStore()
    @Published var governanceConfig = GovernanceConfig()
    @Published var governanceEvents: [GovernanceEvent] = []
    @Published var governanceEnabled = false

    private var logTimer: Timer?
    private var interposer: Engrave?
    private var logStreamTask: Task<Void, Never>?
    private var policyEngine: PolicyEngine?
    private var governanceBridge: GovernanceBridge?

    let mlxBinDir: String
    let configDir: String
    let modelsDir: String
    let venvDir: String
    let modelConfigFile: String
    let interposerPort: UInt16 = 8900

    init() {
        let home = NSHomeDirectory()
        mlxBinDir = "\(home)/mlx/bin"
        configDir = "\(home)/.config/mlx-launcher"
        modelsDir = "\(home)/.lmstudio/models"
        venvDir = "\(home)/.lmstudio/venv"
        modelConfigFile = "\(home)/.lmstudio/model-configs.json"

        // Load non-blocking data synchronously
        runnerSettings = Dictionary(uniqueKeysWithValues: allRunners.map {
            ($0.id, RunnerLaunchSettings(workingDirectory: home, enabledFlags: [], values: [:], extraArguments: ""))
        })
        loadProfiles()
        loadPrompts()
    }

    /// Call this once the view is on screen — never from init().
    /// Process.waitUntilExit() pumps the run loop, which crashes
    /// AttributeGraph if the view graph isn't ready yet.
    func bootstrap() {
        guard !_bootstrapped else { return }
        _bootstrapped = true

        Task {
            refreshModels()
            checkServer()
            checkInterposer()
            startLogTailing()
            modelStore.scanLocalModels()
            modelStore.startNetworkDiscovery()
            loadGovernanceConfig()
        }
    }
    private var _bootstrapped = false

    // MARK: - Log Tailing (periodic, survives app relaunch)

    private func startLogTailing() {
        logTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tailServerLog()
                self?.checkServer()
            }
        }
    }

    private func tailServerLog() {
        guard let data = FileManager.default.contents(atPath: "/tmp/mlx-server.log"),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        serverLog = Array(lines.suffix(200))
    }

    // MARK: - Model Discovery

    func refreshModels() {
        Task.detached { [mlxBinDir] in
            let local = Self.discoverLocalModels(scriptPath: mlxBinDir + "/mlx-models")
            let cloud = loadCloudModels()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.localModels = local
                self.allModels = local + cloud
                if self.selectedModel == nil, let first = self.allModels.first {
                    self.selectedModel = first
                }
            }
        }
    }

    /// Runs entirely off the main thread — safe to call from anywhere.
    private nonisolated static func discoverLocalModels(scriptPath: String) -> [MLXModel] {
        guard FileManager.default.isExecutableFile(atPath: scriptPath) else { return [] }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", scriptPath]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.environment = ProcessInfo.processInfo.environment
        try? task.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var models: [MLXModel] = []
        let pattern = #"^\s*(\d+)\)\s+(\S+)\s+(\S+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return [] }

        regex.enumerateMatches(in: output, range: NSRange(output.startIndex..., in: output)) { match, _, _ in
            guard let match = match,
                  let idxRange = Range(match.range(at: 1), in: output),
                  let nameRange = Range(match.range(at: 2), in: output),
                  let sizeRange = Range(match.range(at: 3), in: output),
                  let index = Int(output[idxRange]) else { return }

            models.append(MLXModel(
                id: String(output[nameRange]),
                index: index,
                size: String(output[sizeRange]),
                source: .local
            ))
        }
        return models
    }

    // MARK: - Server Control

    func checkServer() {
        Task {
            let url = URL(string: "http://localhost:\(serverStatus.port)/v1/models")!
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let models = json["data"] as? [[String: Any]],
                       let modelId = models.first?["id"] as? String {
                        serverStatus = ServerStatus(state: .running, modelName: modelId, port: serverStatus.port)
                    } else {
                        serverStatus.state = .running
                    }
                } else {
                    serverStatus.state = .stopped
                }
            } catch {
                serverStatus.state = .stopped
            }
        }
    }

    func startServer(model: MLXModel) {
        guard model.source == .local else { return }
        stopServer()

        serverStatus = ServerStatus(state: .starting, modelName: model.id, port: serverStatus.port)
        serverLog = ["Starting MLX server for \(model.id)..."]

        let command = serverStartCommand(model: model, profile: activeProfile)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", command]
        proc.environment = ProcessInfo.processInfo.environment

        do {
            try proc.run()
            proc.waitUntilExit()  // bash returns immediately since we backgrounded with &
        } catch {
            serverStatus.state = .error
            serverLog.append("Failed to start: \(error)")
            return
        }

        serverLog.append("Server process launched (detached).")

        // Poll for readiness and discover the PID
        Task {
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // Tail the log file for UI feedback
                if let logData = FileManager.default.contents(atPath: "/tmp/mlx-server.log"),
                   let logText = String(data: logData, encoding: .utf8) {
                    let lines = logText.components(separatedBy: "\n").filter { !$0.isEmpty }
                    serverLog = ["Starting MLX server for \(model.id)..."] + lines.suffix(50)
                }

                let url = URL(string: "http://localhost:\(serverStatus.port)/v1/models")!
                if let (_, resp) = try? await URLSession.shared.data(from: url),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    // Discover PID of the running mlx_lm process
                    let pid = findMLXServerPID()
                    serverStatus = ServerStatus(state: .running, modelName: model.id, port: serverStatus.port, pid: pid)
                    serverLog.append("Server ready. PID: \(pid ?? 0)")
                    return
                }
            }
            serverStatus.state = .error
            serverLog.append("Server failed to become ready within 120s")
        }
    }

    /// Find the PID of the running mlx_lm.server process.
    private func findMLXServerPID() -> Int? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "mlx_lm"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int(str.components(separatedBy: "\n").first ?? "") else { return nil }
        return pid
    }

    func stopServer() {
        // Kill the detached mlx_lm.server process by PID or pattern
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-f", "mlx_lm"]
        killTask.standardOutput = FileHandle.nullDevice
        killTask.standardError = FileHandle.nullDevice
        try? killTask.run()
        killTask.waitUntilExit()

        serverStatus = ServerStatus(state: .stopped, port: serverStatus.port)
        serverLog.append("Server stopped.")
    }

    func restartServer() {
        guard let model = selectedModel, model.source == .local else { return }
        stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.startServer(model: model)
        }
    }

    private func serverStartCommand(model: MLXModel, profile: GenerationProfile) -> String {
        let python = "\(venvDir)/bin/python3"
        var args = [
            shellQuote(python), "-m", "mlx_lm", "server",
            "--model", shellQuote(modelPath(for: model)),
            "--port", shellQuote(String(serverStatus.port)),
        ]
        args.append(contentsOf: serverParameterArguments(model: model, profile: profile).map(shellQuote))
        args.append(contentsOf: splitShellWords(extraMLXServerArguments).map(shellQuote))
        return "nohup \(args.joined(separator: " ")) > /tmp/mlx-server.log 2>&1 &"
    }

    private func serverParameterArguments(model: MLXModel, profile: GenerationProfile) -> [String] {
        let config = resolvedModelConfig(for: model, profile: profile)
        var args: [String] = []

        appendArg(&args, config: config, key: "temp", flag: "--temp", fallback: profile.temp)
        appendArg(&args, config: config, key: "top_p", flag: "--top-p", fallback: profile.top_p)
        appendArg(&args, config: config, key: "top_k", flag: "--top-k", fallback: profile.top_k)
        appendArg(&args, config: config, key: "min_p", flag: "--min-p", fallback: profile.min_p)
        appendArg(&args, config: config, key: "max_tokens", flag: "--max-tokens", fallback: profile.max_tokens)

        if boolValue(config["use_default_chat_template"]) == true {
            args.append("--use-default-chat-template")
        }
        if let templateArgs = config["chat_template_args"] as? String, !templateArgs.isEmpty {
            args += ["--chat-template-args", templateArgs]
        }
        return args
    }

    private func appendArg<T>(_ args: inout [String], config: [String: Any], key: String, flag: String, fallback: T) {
        let value = config[key] ?? fallback
        args += [flag, "\(value)"]
    }

    private func resolvedModelConfig(for model: MLXModel, profile: GenerationProfile) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: modelConfigFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        let profileKey = normalizedProfileName(profile.name)
        let arch = modelArchitecture(for: model)
        var merged: [String: Any] = [:]

        if let architectures = root["architectures"] as? [String: Any],
           let defaultConfig = architectures["_default"] as? [String: Any] {
            mergeConfig(defaultConfig, profileKey: profileKey, into: &merged)
        }
        if let arch,
           let architectures = root["architectures"] as? [String: Any],
           let archConfig = architectures[arch] as? [String: Any] {
            mergeConfig(archConfig, profileKey: profileKey, into: &merged)
        }
        if let models = root["models"] as? [String: Any],
           let modelConfig = models[model.id] as? [String: Any] {
            mergeConfig(modelConfig, profileKey: profileKey, into: &merged)
        }

        return merged
    }

    private func mergeConfig(_ config: [String: Any], profileKey: String, into merged: inout [String: Any]) {
        for (key, value) in config where !key.hasPrefix("_") && key != "profiles" {
            merged[key] = value
        }
        guard let profiles = config["profiles"] as? [String: Any] else { return }
        let aliases = profileAliases(for: profileKey)
        for alias in aliases {
            if let profileConfig = profiles[alias] as? [String: Any] {
                for (key, value) in profileConfig where !key.hasPrefix("_") {
                    merged[key] = value
                }
            }
        }
    }

    private func modelArchitecture(for model: MLXModel) -> String? {
        let path = "\(modelPath(for: model))/config.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["model_type"] as? String
    }

    private func normalizedProfileName(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private func profileAliases(for key: String) -> [String] {
        switch key {
        case "precise": return ["reasoning", "precise"]
        case "coding": return ["agent", "coding"]
        default: return [key]
        }
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String { return ["true", "yes", "1"].contains(string.lowercased()) }
        return nil
    }

    // MARK: - Interposer (Engrave) Control — In-Process

    func checkInterposer() {
        Task {
            if let engrave = interposer {
                interposerRunning = await engrave.isRunning
            } else {
                interposerRunning = false
            }
        }
    }

    func startInterposer() {
        guard let model = selectedModel else {
            interposerLog.append("No model selected")
            return
        }

        if interposerRunning {
            interposerLog.append("Restarting engrave proxy...")
            stopInterposer()
        }

        let config = EngraveConfig.forLocalMLX(
            model: model.id,
            backendPort: UInt16(serverStatus.port),
            proxyPort: interposerPort
        )

        // Set up governance if enabled
        var bridge: GovernanceBridge? = nil
        if governanceConfig.enabled {
            let engine = PolicyEngine(config: governanceConfig)
            self.policyEngine = engine
            bridge = GovernanceBridge(engine: engine)
            self.governanceBridge = bridge
            interposerLog.append("[governance] enabled: \(governanceConfig.rules.filter(\.enabled).count) rules, sandbox=\(governanceConfig.sandboxLevel.rawValue)")
        } else {
            self.policyEngine = nil
            self.governanceBridge = nil
        }

        let engrave = Engrave(config: config, governance: bridge)
        self.interposer = engrave

        // Start streaming logs from the in-process interposer
        logStreamTask?.cancel()
        logStreamTask = Task { [weak self] in
            for await message in await engrave.logStream {
                await MainActor.run {
                    self?.interposerLog.append(message)
                    if let count = self?.interposerLog.count, count > 200 {
                        self?.interposerLog.removeFirst(count - 200)
                    }
                }
            }
        }

        interposerLog.append("Starting in-process engrave proxy on port \(interposerPort)...")

        Task {
            do {
                try await engrave.start()
                await MainActor.run {
                    self.interposerRunning = true
                    self.interposerLog.append("Engrave proxy running on port \(self.interposerPort)")
                }
            } catch {
                await MainActor.run {
                    self.interposerLog.append("Failed to start interposer: \(error.localizedDescription)")
                    self.interposerRunning = false
                }
            }
        }
    }

    func stopInterposer() {
        logStreamTask?.cancel()
        logStreamTask = nil
        if let engrave = interposer {
            Task {
                await engrave.stop()
                await MainActor.run {
                    self.interposerRunning = false
                    self.interposerLog.append("Interposer stopped.")
                }
            }
        }
        interposer = nil
        interposerRunning = false
    }

    // MARK: - Governance

    func updateGovernanceConfig(_ config: GovernanceConfig) {
        governanceConfig = config
        governanceEnabled = config.enabled
        // Save to disk
        let path = "\(configDir)/governance.json"
        try? config.save(to: path)
        // Update engine if running
        if let engine = policyEngine {
            Task { await engine.updateConfig(config) }
        }
        interposerLog.append("[governance] config updated: \(config.rules.filter(\.enabled).count) rules, sandbox=\(config.sandboxLevel.rawValue)")
    }

    func loadGovernanceConfig() {
        let path = "\(configDir)/governance.json"
        if let config = try? GovernanceConfig.load(from: path) {
            governanceConfig = config
            governanceEnabled = config.enabled
        }
    }

    func refreshGovernanceEvents() {
        guard let engine = policyEngine else {
            governanceEvents = []
            return
        }
        Task {
            let events = await engine.recentEvents(count: 100)
            await MainActor.run {
                self.governanceEvents = events
            }
        }
    }

    // MARK: - Profiles

    func loadProfiles() {
        let dir = "\(configDir)/profiles"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            profiles = [.default]
            return
        }
        var loaded: [GenerationProfile] = []
        for file in files where file.hasSuffix(".json") {
            let path = "\(dir)/\(file)"
            guard let data = FileManager.default.contents(atPath: path),
                  let profile = try? JSONDecoder().decode(GenerationProfile.self, from: data) else { continue }
            loaded.append(profile)
        }
        if loaded.isEmpty { loaded = [.default] }
        profiles = loaded.sorted { $0.name < $1.name }
        if let def = profiles.first(where: { $0.name == "Default" }) {
            activeProfile = def
        } else {
            activeProfile = profiles[0]
        }
    }

    func saveProfile(_ profile: GenerationProfile) {
        let dir = "\(configDir)/profiles"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/\(profile.name.lowercased().replacingOccurrences(of: " ", with: "_")).json"
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        loadProfiles()
        activeProfile = profile
    }

    func deleteProfile(_ profile: GenerationProfile) {
        guard profile.name != "Default" else { return }
        let dir = "\(configDir)/profiles"
        let path = "\(dir)/\(profile.name.lowercased().replacingOccurrences(of: " ", with: "_")).json"
        try? FileManager.default.removeItem(atPath: path)
        loadProfiles()
    }

    func resetToDefault() {
        activeProfile = .default
    }

    // MARK: - Runner Settings

    func settings(for runner: Runner) -> RunnerLaunchSettings {
        runnerSettings[runner.id] ?? RunnerLaunchSettings(
            workingDirectory: NSHomeDirectory(),
            enabledFlags: [],
            values: [:],
            extraArguments: ""
        )
    }

    func updateSettings(for runner: Runner, _ settings: RunnerLaunchSettings) {
        runnerSettings[runner.id] = settings
    }

    func runnerArguments(for runner: Runner) -> [String] {
        let settings = settings(for: runner)
        let definitions = RunnerArg.argsFor(runner.id)
        var result: [String] = []

        for arg in definitions where settings.enabledFlags.contains(arg.flag) {
            result.append(arg.flag)
            if arg.takesValue, let value = settings.values[arg.flag], !value.isEmpty {
                result.append(value)
            }
        }

        result.append(contentsOf: splitShellWords(settings.extraArguments))
        return result
    }

    func commandPreview() -> String {
        guard let model = selectedModel else { return "" }
        let command = runnerCommand(model: model, runner: selectedRunner, userArgs: runnerArguments(for: selectedRunner))
        return (["cd", shellQuote(settings(for: selectedRunner).workingDirectory), "&&"] + command.environment.map { "\($0.key)=\(shellQuote($0.value))" } + command.arguments.map(shellQuote)).joined(separator: " ")
    }

    // MARK: - System Prompts

    func loadPrompts() {
        let path = "\(configDir)/prompts/library.json"
        guard let data = FileManager.default.contents(atPath: path),
              let loaded = try? JSONDecoder().decode([SystemPrompt].self, from: data) else {
            prompts = []
            return
        }
        prompts = loaded
    }

    // MARK: - Launch

    func launch() {
        guard let model = selectedModel else { return }
        let runner = selectedRunner
        let settings = settings(for: runner)
        let userArgs = runnerArguments(for: runner)
        let command = runnerCommand(model: model, runner: runner, userArgs: userArgs)

        if model.source == .local {
            if serverStatus.state != .running || runningServerDoesNotMatch(model) {
                startServer(model: model)
            }
        }
        if runner.needsProxy || model.source != .local {
            startInterposer()
        }

        let envExports = command.environment.map { key, value in
            "export \(key)=\(shellQuote(value))"
        }
        let pathExport = "export PATH=\"\(mlxBinDir):/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:\(NSHomeDirectory())/.cargo/bin:$PATH\""
        let waitForMLX = model.source == .local
            ? "until curl -fsS \(shellQuote("http://localhost:\(serverStatus.port)/v1/models")) >/dev/null 2>&1; do sleep 1; done"
            : ""
        let pieces = [
            "cd \(shellQuote(settings.workingDirectory))",
            pathExport,
        ] + envExports + [waitForMLX, command.arguments.map(shellQuote).joined(separator: " ")]
        let shellCommand = pieces.filter { !$0.isEmpty }.joined(separator: " && ")

        let terminalCommand = "/bin/bash -lc \(shellQuote(shellCommand))"
        let escaped = terminalCommand.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    private func runnerCommand(model: MLXModel, runner: Runner, userArgs: [String]) -> (environment: [String: String], arguments: [String]) {
        let modelName = model.source == .local ? model.id : model.id
        let modelId = serverStatus.modelName ?? modelName

        switch runner.id {
        case "claude":
            var args = defaultModelArgs(userArgs, flag: "--model", model: modelName) + userArgs
            if !activeProfile.system_prompt.isEmpty &&
                !hasFlag(userArgs, "--system-prompt") &&
                !hasFlag(userArgs, "--append-system-prompt") {
                args += ["--append-system-prompt", activeProfile.system_prompt]
            }
            return ([
                "ANTHROPIC_BASE_URL": "http://localhost:\(interposerPort)",
            ], ["claude"] + args)
        case "codex":
            return ([
                "OPENAI_BASE_URL": "http://localhost:\(interposerPort)/v1",
                "OPENAI_API_KEY": "mlx-local",
            ], ["codex"] + defaultCodexArgs(userArgs, model: modelId) + userArgs)
        case "gemini":
            return ([
                "GOOGLE_GEMINI_BASE_URL": "http://localhost:\(interposerPort)",
                "GOOGLE_API_KEY": "mlx-local",
            ], ["gemini"] + defaultModelArgs(userArgs, flag: "--model", model: modelName) + userArgs)
        case "aider":
            return ([:], [
                "aider",
                "--openai-api-base", "http://localhost:\(serverStatus.port)/v1",
                "--openai-api-key", "mlx-local",
                "--model", "openai/\(modelId)",
            ] + userArgs)
        case "gptme":
            return ([
                "OPENAI_BASE_URL": "http://localhost:\(serverStatus.port)/v1",
                "OPENAI_API_KEY": "mlx-local",
            ], ["gptme"] + defaultModelArgs(userArgs, flag: "--model", model: modelName) + userArgs)
        default:
            return ([:], [runner.binary] + userArgs)
        }
    }

    private func runningServerDoesNotMatch(_ model: MLXModel) -> Bool {
        guard let running = serverStatus.modelName else { return true }
        return !running.contains(model.id)
    }

    private func defaultModelArgs(_ userArgs: [String], flag: String, model: String) -> [String] {
        hasFlag(userArgs, flag) ? [] : [flag, model]
    }

    private func defaultCodexArgs(_ userArgs: [String], model: String) -> [String] {
        hasFlag(userArgs, "--model") || userArgs.contains("-m") || userArgs.contains("-c") ? [] : ["-c", "model=\"\(model)\""]
    }

    private func hasFlag(_ args: [String], _ flag: String) -> Bool {
        args.contains(flag) || args.contains(where: { $0.hasPrefix(flag + "=") })
    }

    private func modelPath(for model: MLXModel) -> String {
        "\(modelsDir)/\(model.id)"
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func splitShellWords(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for char in input {
            if escaped {
                current.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if let active = quote {
                if char == active {
                    quote = nil
                } else {
                    current.append(char)
                }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if escaped { current.append("\\") }
        if !current.isEmpty { words.append(current) }
        return words
    }
}
