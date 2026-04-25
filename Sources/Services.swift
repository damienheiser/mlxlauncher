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
    @Published var serverStatus = ServerStatus(state: .stopped, port: 8421)
    @Published var profiles: [GenerationProfile] = []
    @Published var activeProfile: GenerationProfile = .default
    @Published var prompts: [SystemPrompt] = []
    @Published var inference = MLXInference()
    @Published var serverLog: [String] = []
    @Published var interposerLog: [String] = []
    @Published var interposerRunning = false
    @Published var interposerTarget = "Not configured"
    @Published var runnerSettings: [String: RunnerLaunchSettings] = [:]
    @Published var extraMLXServerArguments = ""
    @Published var modelStore = ModelStore()
    @Published var governanceConfig = GovernanceConfig()
    @Published var governanceEvents: [GovernanceEvent] = []
    @Published var governanceEnabled = false
    @Published var cloudAuthMode: CloudAuthMode = .apiKey

    private var logTimer: Timer?
    private var interposer: Engrave?
    private var logStreamTask: Task<Void, Never>?
    private var policyEngine: PolicyEngine?
    private var governanceBridge: GovernanceBridge?
    private var modelStoreObserverCancellable: AnyCancellable?

    let mlxBinDir: String
    let configDir: String
    let modelsDir: String
    let interposerPort: UInt16 = 8900

    init() {
        let home = NSHomeDirectory()
        mlxBinDir = "\(home)/mlx/bin"
        configDir = "\(home)/.config/mlx-launcher"
        modelsDir = "\(home)/.config/mlx-launcher/models"
        // Load non-blocking data synchronously
        runnerSettings = Dictionary(uniqueKeysWithValues: allRunners.map {
            ($0.id, RunnerLaunchSettings(workingDirectory: home, enabledFlags: [], values: [:], extraArguments: ""))
        })
        loadRunnerSettings()
        loadModelStoreSettings()
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
            connectModelStore()
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
        logTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tailServerLog()
            }
        }
    }

    private func tailServerLog() {
        // Native MLX inference logs directly to serverLog — no file tailing needed.
        // Update inference status if model is loaded.
        if inference.isLoaded && serverStatus.state != .running {
            serverStatus.state = .running
        }
        if inference.tokensPerSecond > 0 {
            let tps = String(format: "%.1f", inference.tokensPerSecond)
            if serverLog.last?.hasPrefix("[tps:") != true {
                serverLog.append("[tps: \(tps) tokens/sec]")
            }
        }
    }

    // MARK: - Model Discovery

    func refreshModels() {
        let binDir = mlxBinDir
        Task {
            let local = await Task.detached(priority: .utility) {
                Self.discoverLocalModels(scriptPath: binDir + "/mlx-models")
            }.value
            let cloud = await Task.detached(priority: .utility) {
                loadCloudModels()
            }.value
            self.localModels = local
            self.mergeLaunchableModels(scriptModels: local, cloudModels: cloud)
        }
    }

    private func connectModelStore() {
        guard modelStoreObserverCancellable == nil else { return }
        modelStoreObserverCancellable = modelStore.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.mergeLaunchableModels()
            }
    }

    private func mergeLaunchableModels(scriptModels: [MLXModel]? = nil, cloudModels: [MLXModel]? = nil) {
        if let scriptModels { localModels = scriptModels }
        let cloud = cloudModels ?? allModels.filter(\.isCloud)
        let discoveredLocal = modelStore.localModels.enumerated().map { offset, model in
            MLXModel(
                id: model.id,
                index: model.index ?? offset,
                size: model.size,
                source: .local,
                localPath: model.localPath
            )
        }
        let network = modelStore.networkModels.enumerated().map { offset, model in
            MLXModel(
                id: model.id,
                index: -10_000 - offset,
                size: model.size,
                source: .network,
                networkHost: model.networkHost,
                networkPort: model.networkPort
            )
        }

        var seen = Set<String>()
        let merged = (localModels + discoveredLocal + network + cloud).filter { seen.insert($0.launchIdentity).inserted }
        allModels = merged
        if let selectedModel, !merged.contains(where: { $0.launchIdentity == selectedModel.launchIdentity }) {
            self.selectedModel = merged.first
        } else if selectedModel == nil {
            selectedModel = merged.first
        }
    }

    func selectDiscoveredModel(_ model: DiscoveredModel) {
        mergeLaunchableModels()
        selectedModel = allModels.first { $0.launchIdentity == model.launchIdentity }
        if selectedModel == nil {
            selectedModel = MLXModel(
                id: model.id,
                index: model.index ?? allModels.count,
                size: model.size,
                source: model.location == .network ? .network : .local,
                localPath: model.localPath,
                networkHost: model.networkHost,
                networkPort: model.networkPort
            )
            allModels.append(selectedModel!)
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
        if inference.isLoaded {
            serverStatus = ServerStatus(state: .running, modelName: inference.loadedModelName, port: serverStatus.port)
        } else if inference.isLoading {
            serverStatus = ServerStatus(state: .starting, modelName: inference.loadedModelName, port: serverStatus.port)
        } else if inference.loadError != nil {
            serverStatus = ServerStatus(state: .error, modelName: nil, port: serverStatus.port)
        } else {
            serverStatus = ServerStatus(state: .stopped, port: serverStatus.port)
        }
    }

    func startServer(model: MLXModel) {
        guard model.source == .local else { return }

        // Validate model has weight files before starting
        let path = modelPath(for: model)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let hasWeights = files.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".gguf") }
        if !hasWeights {
            serverStatus = ServerStatus(state: .error, modelName: model.id, port: serverStatus.port)
            serverLog.append("ERROR: No safetensors/gguf weight files found in \(path)")
            serverLog.append("The model may be an incomplete download. Re-download it from the Model Store.")
            return
        }

        stopServer()

        serverStatus = ServerStatus(state: .starting, modelName: model.id, port: serverStatus.port)
        serverLog = ["Loading model \(model.id) via native MLX inference..."]

        Task {
            await inference.loadModel(at: path)

            if inference.isLoaded {
                serverStatus = ServerStatus(state: .running, modelName: model.id, port: serverStatus.port)
                serverLog.append("Model loaded successfully: \(model.id)")
            } else if let error = inference.loadError {
                serverStatus = ServerStatus(state: .error, modelName: model.id, port: serverStatus.port)
                serverLog.append("Failed to load model: \(error)")
            }
        }
    }

    func stopServer() {
        inference.unload()
        serverStatus = ServerStatus(state: .stopped, port: serverStatus.port)
        serverLog.append("Server stopped.")
    }

    func restartServer() {
        guard let model = selectedModel, model.source == .local else { return }
        inference.unload()
        startServer(model: model)
    }

    /// Whether the selected model differs from the running server model.
    var selectedModelDiffersFromServer: Bool {
        guard let model = selectedModel, model.source == .local,
              serverStatus.state == .running else { return false }
        return runningServerDoesNotMatch(model)
    }

    /// Relaunch the MLX server with the currently selected model.
    func relaunchServerWithSelectedModel() {
        guard let model = selectedModel, model.source == .local else { return }
        inference.unload()
        startServer(model: model)
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

        // Don't restart if already running — just update the target description
        if interposerRunning {
            interposerTarget = targetDescription(for: model)
            interposerLog.append("Interposer already running, updated target to \(model.id)")
            return
        }

        let config = engraveConfig(for: model)
        interposerTarget = targetDescription(for: model)

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

    private func targetDescription(for model: MLXModel) -> String {
        switch model.source {
        case .local:
            return "local MLX \(model.id) via :\(serverStatus.port)"
        case .network:
            return "network MLX \(model.networkHost ?? "localhost"):\(model.networkPort ?? 1234) → \(model.id)"
        case .anthropic:
            return "Anthropic \(model.id)"
        case .openai:
            return "OpenAI \(model.id)"
        case .google:
            return "Gemini \(model.id)"
        }
    }

    private func engraveConfig(for model: MLXModel) -> EngraveConfig {
        // Use wildcard "*" routes so the interposer forwards ANY model name
        // without needing to restart when the selected model changes.
        let localRoute = EngraveConfig.RouteTarget(backend: "local", model: "*", provider: "local")

        return EngraveConfig(
            server: EngraveConfig.ServerConfig(port: interposerPort),
            routes: EngraveConfig.RouteConfig(defaults: [
                "anthropic": localRoute,
                "openai": localRoute,
                "openai_compatible": localRoute,
                "gemini": localRoute,
            ]),
            providers: [
                "local": EngraveConfig.ProviderConfig(
                    type: "chat_completions",
                    baseURL: "http://127.0.0.1:8421",
                    apiKeyEnv: "MLX_LAUNCHER_API_KEY",
                    models: nil
                ),
            ]
        )
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
        writeGovernanceArtifacts(config)
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
            writeGovernanceArtifacts(config)
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
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var loaded: [GenerationProfile] = []
        for file in files where file.hasSuffix(".json") {
            let path = "\(dir)/\(file)"
            guard let data = FileManager.default.contents(atPath: path),
                  let profile = try? JSONDecoder().decode(GenerationProfile.self, from: data) else { continue }
            loaded.append(profile)
        }
        if loaded.isEmpty {
            // Seed built-in profiles on first run
            loaded = GenerationProfile.builtins
            for profile in loaded { saveProfileToDisk(profile) }
        }
        profiles = loaded.sorted { $0.name < $1.name }
        if let def = profiles.first(where: { $0.name == "Default" }) {
            activeProfile = def
        } else {
            activeProfile = profiles[0]
        }
    }

    private func saveProfileToDisk(_ profile: GenerationProfile) {
        let dir = "\(configDir)/profiles"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/\(profile.name.lowercased().replacingOccurrences(of: " ", with: "_")).json"
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    func saveProfile(_ profile: GenerationProfile) {
        saveProfileToDisk(profile)
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
        saveRunnerSettings()
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
        let environment = command.environment.merging(governanceRunnerEnvironment()) { current, _ in current }
        return (["cd", shellQuote(settings(for: selectedRunner).workingDirectory), "&&"] + environment.map { "\($0.key)=\(shellQuote($0.value))" } + command.arguments.map(shellQuote)).joined(separator: " ")
    }

    // MARK: - System Prompts

    func loadPrompts() {
        let dir = "\(configDir)/prompts"
        let path = "\(dir)/library.json"
        if let data = FileManager.default.contents(atPath: path),
           let loaded = try? JSONDecoder().decode([SystemPrompt].self, from: data), !loaded.isEmpty {
            prompts = loaded
        } else {
            // Seed built-in prompts on first run
            prompts = SystemPrompt.builtins
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(SystemPrompt.builtins) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    // MARK: - Launch

    func launch() {
        guard let model = selectedModel else { return }
        let runner = selectedRunner
        let settings = settings(for: runner)
        let userArgs = runnerArguments(for: runner)
        let command = runnerCommand(model: model, runner: runner, userArgs: userArgs)
        let usesInterposer = shouldUseInterposer(runner: runner, model: model)

        // Start MLX server only if not running at all. Never restart on Launch.
        // If the model changed, the UI will show a confirmation dialog (see Views.swift).
        if model.source == .local && serverStatus.state != .running {
            startServer(model: model)
        }
        // Start interposer only if not running. Never restart on Launch.
        if usesInterposer && !interposerRunning {
            startInterposer()
        }

        let environment = command.environment.merging(governanceRunnerEnvironment()) { current, _ in current }
        let envExports = environment.map { key, value in
            "export \(key)=\(shellQuote(value))"
        }
        let pathExport = "export PATH=\"\(mlxBinDir):/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:\(NSHomeDirectory())/.cargo/bin:$PATH\""
        let waitForMLX = model.source == .local
            ? "echo 'Waiting for MLX inference on port \(serverStatus.port)...' && _t=0 && until curl -fsS \(shellQuote("http://127.0.0.1:\(serverStatus.port)/v1/models")) >/dev/null 2>&1; do sleep 1; _t=$((_t+1)); if [ $_t -ge 120 ]; then echo 'ERROR: MLX inference not ready after 120s'; exit 1; fi; done"
            : ""
        let waitForInterposer = usesInterposer
            ? "echo 'Waiting for interposer on port \(interposerPort)...' && _t=0 && until curl -fsS \(shellQuote("http://localhost:\(interposerPort)/health")) >/dev/null 2>&1; do sleep 1; _t=$((_t+1)); if [ $_t -ge 60 ]; then echo 'ERROR: Interposer failed to start after 60s'; exit 1; fi; done"
            : ""
        let pieces = [
            "cd \(shellQuote(settings.workingDirectory))",
            pathExport,
        ] + envExports + [waitForMLX, waitForInterposer, command.arguments.map(shellQuote).joined(separator: " ")]
        let shellCommand = pieces.filter { !$0.isEmpty }.joined(separator: " && ")

        let scriptPath = NSTemporaryDirectory() + "mlx-launcher-\(runner.id)-\(ProcessInfo.processInfo.globallyUniqueString).sh"
        let scriptContent = "#!/bin/bash -l\n" + shellCommand + "\n"
        try? scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        chmod(scriptPath, 0o755)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Prefer iTerm2 if installed, fall back to Terminal.app
        let terminalApp = FileManager.default.fileExists(atPath: "/Applications/iTerm.app") ? "iTerm" : "Terminal"
        task.arguments = ["-a", terminalApp, scriptPath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    private func runnerCommand(model: MLXModel, runner: Runner, userArgs: [String]) -> (environment: [String: String], arguments: [String]) {
        let modelName = model.source == .local ? model.id : model.id
        let modelId = model.source == .local ? (serverStatus.modelName ?? modelName) : modelName
        let usesInterposer = shouldUseInterposer(runner: runner, model: model)
        let nativeCloudAuth = model.isCloud && cloudAuthMode == .cliSubscription
        let openAIBaseURL = usesInterposer ? "http://127.0.0.1:\(interposerPort)/v1" : "http://127.0.0.1:\(serverStatus.port)/v1"

        switch runner.id {
        case "claude":
            var args = defaultModelArgs(userArgs, flag: "--model", model: modelName) + userArgs
            if !activeProfile.system_prompt.isEmpty &&
                !hasFlag(userArgs, "--system-prompt") &&
                !hasFlag(userArgs, "--append-system-prompt") {
                args += ["--append-system-prompt", activeProfile.system_prompt]
            }
            if !hasFlag(userArgs, "--append-system-prompt"),
               !hasFlag(userArgs, "--system-prompt"),
               governanceConfig.isFeatureEnabled(.subAgentLaunchControl) || governanceConfig.isFeatureEnabled(.workflowTaskDAG) {
                args += ["--append-system-prompt", governanceRunnerInstruction()]
            }
            // CLI subscription: let Claude use its native OAuth auth (Max/Pro plan)
            let claudeEnv: [String: String] = nativeCloudAuth ? [:] : [
                "ANTHROPIC_BASE_URL": "http://localhost:\(interposerPort)",
                "ANTHROPIC_API_KEY": "mlx-local",
            ]
            return (claudeEnv, ["claude"] + args)
        case "codex":
            let codexEnv: [String: String] = nativeCloudAuth ? [:] : [
                "OPENAI_BASE_URL": "http://127.0.0.1:\(interposerPort)/v1",
                "OPENAI_API_KEY": "mlx-local",
            ]
            let codexArgs = nativeCloudAuth
                ? defaultModelArgs(userArgs, flag: "-m", model: modelId) + userArgs
                : defaultCodexArgs(userArgs, model: modelId) + userArgs
            // Interactive launch: no "exec" subcommand (exec requires a prompt argument).
            // Sub-agent launches use "exec" — that's handled in the governance sub-agent instructions.
            return (codexEnv, ["codex"] + codexArgs)
        case "gemini":
            // For local models: use "gemini-2.0-flash" as model name so Gemini CLI accepts it.
            // The interposer wildcard route sends everything to local MLX regardless.
            // Set GOOGLE_GEMINI_BASE_URL to interposer so all API calls go through us.
            // Also set HTTPS_PROXY to intercept model validation calls.
            let geminiModel = model.source == .local ? "gemini-2.0-flash" : modelName
            let geminiArgs = defaultGeminiArgs(userArgs, model: geminiModel) + userArgs
            var geminiEnv: [String: String] = nativeCloudAuth ? [:] : [
                "GOOGLE_GEMINI_BASE_URL": "http://127.0.0.1:\(interposerPort)",
                "GEMINI_API_KEY": "mlx-local",
                "GOOGLE_API_KEY": "mlx-local",
            ]
            // Route ALL Gemini traffic through interposer (captures model validation too)
            if model.source == .local {
                geminiEnv["NODE_TLS_REJECT_UNAUTHORIZED"] = "0"
            }
            return (geminiEnv, ["gemini"] + geminiArgs)
        case "aider":
            var aiderEnv: [String: String] = [:]
            if !nativeCloudAuth {
                // Use OPENAI_API_BASE (legacy v0 env var that Aider expects)
                aiderEnv["OPENAI_API_BASE"] = openAIBaseURL
                aiderEnv["OPENAI_API_KEY"] = "mlx-local"
                // Also set Anthropic base so Aider can route anthropic-prefixed models
                aiderEnv["ANTHROPIC_BASE_URL"] = "http://localhost:\(interposerPort)"
                aiderEnv["ANTHROPIC_API_KEY"] = "mlx-local"
            }
            var aiderArgs = ["aider", "--yes-always", "--no-auto-commits"]
            if !hasFlag(userArgs, "--model") {
                aiderArgs += ["--model", "openai/\(modelId)"]
            }
            aiderArgs += userArgs
            return (aiderEnv, aiderArgs)
        case "gptme":
            var gptmeEnv: [String: String] = [:]
            if !nativeCloudAuth {
                // Use OPENAI_API_BASE (what gptme expects)
                gptmeEnv["OPENAI_API_BASE"] = openAIBaseURL
                gptmeEnv["OPENAI_API_KEY"] = "mlx-local"
            }
            let gptmeArgs = ["gptme", "--non-interactive"] + defaultModelArgs(userArgs, flag: "--model", model: modelName) + userArgs
            return (gptmeEnv, gptmeArgs)
        default:
            return ([:], [runner.binary] + userArgs)
        }
    }

    private func shouldUseInterposer(runner: Runner, model: MLXModel) -> Bool {
        // CLI subscription mode: skip interposer for cloud models, let the runner
        // use its native OAuth/session auth (Claude Max, Codex sub, Gemini CLI, etc.)
        if model.isCloud && cloudAuthMode == .cliSubscription {
            return false
        }
        return runner.needsProxy || model.source != .local
    }

    // MARK: - Persistence

    private func loadRunnerSettings() {
        let path = "\(configDir)/runner-settings.json"
        guard let data = FileManager.default.contents(atPath: path),
              let loaded = try? JSONDecoder().decode([String: RunnerLaunchSettings].self, from: data) else {
            return
        }
        runnerSettings.merge(loaded) { _, new in new }
    }

    private func saveRunnerSettings() {
        let path = "\(configDir)/runner-settings.json"
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(runnerSettings) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func loadModelStoreSettings() {
        let path = "\(configDir)/model-store.json"
        guard let data = FileManager.default.contents(atPath: path),
              let settings = try? JSONDecoder().decode(ModelStoreSettings.self, from: data),
              !settings.scanDirectories.isEmpty else {
            return
        }
        modelStore.scanDirectories = settings.scanDirectories
    }

    func saveModelStoreSettings() {
        let path = "\(configDir)/model-store.json"
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let settings = ModelStoreSettings(scanDirectories: modelStore.scanDirectories)
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private struct ModelStoreSettings: Codable {
        let scanDirectories: [String]
    }

    // MARK: - Governance Artifacts

    private func writeGovernanceArtifacts(_ config: GovernanceConfig) {
        let dir = "\(configDir)/governance"
        try? FileManager.default.createDirectory(atPath: "\(dir)/hooks", withIntermediateDirectories: true)
        try? governanceBrief(config).write(toFile: "\(dir)/engrave-governance-brief.md", atomically: true, encoding: .utf8)
        try? geminiPolicy(config).write(toFile: "\(dir)/gemini-policy.md", atomically: true, encoding: .utf8)
        try? subAgentInstructions(config).write(toFile: "\(dir)/sub-agent-launch.md", atomically: true, encoding: .utf8)
        try? preCommitHook(config).write(toFile: "\(dir)/hooks/pre-commit", atomically: true, encoding: .utf8)
        try? sessionCloseHook(config).write(toFile: "\(dir)/hooks/session-close-check", atomically: true, encoding: .utf8)
        _ = chmod("\(dir)/hooks/pre-commit", 0o755)
        _ = chmod("\(dir)/hooks/session-close-check", 0o755)
    }

    private func subAgentInstructions(_ config: GovernanceConfig) -> String {
        let uia = config.uiaConfig ?? .default
        let budgets = config.contextBudgets ?? ContextBudget.defaults
        return """
        # Engrave Sub-Agent Launch Protocol

        ALL sub-agent and model traffic MUST route through the Engrave interposer.
        Interposer URL: http://localhost:\(interposerPort)

        ## Sub-Agent Launch Commands

        ### Claude Code (Anthropic)
        ```bash
        ANTHROPIC_BASE_URL=http://localhost:\(interposerPort) ANTHROPIC_API_KEY=mlx-local \\
          claude --print --output-format stream-json --model <model> -p "<task>"
        ```
        For interactive sub-agents (long-running):
        ```bash
        ANTHROPIC_BASE_URL=http://localhost:\(interposerPort) ANTHROPIC_API_KEY=mlx-local \\
          claude --model <model> --permission-mode auto
        ```

        ### Codex CLI (OpenAI)
        ```bash
        OPENAI_BASE_URL=http://localhost:\(interposerPort)/v1 OPENAI_API_KEY=mlx-local \\
          codex exec --full-auto -m <model> "<task>"
        ```

        ### Gemini CLI (Google)
        ```bash
        GOOGLE_GEMINI_BASE_URL=http://localhost:\(interposerPort) GEMINI_API_KEY=mlx-local GOOGLE_API_KEY=mlx-local \\
          gemini --yolo -m <model> -p "<task>"
        ```

        ### Aider
        ```bash
        OPENAI_API_BASE=http://localhost:\(interposerPort)/v1 OPENAI_API_KEY=mlx-local \\
          aider --yes-always --no-auto-commits --model openai/<model> --message "<task>"
        ```

        ### gptme
        ```bash
        OPENAI_API_BASE=http://localhost:\(interposerPort)/v1 OPENAI_API_KEY=mlx-local \\
          gptme --non-interactive --model <model> "<task>"
        ```

        ## Model Routing

        | Task Type | Model | Rationale |
        |-----------|-------|-----------|
        | Bounded sub-tasks (file edits, simple code) | \(uia.cheapModel) | Cost-effective, fast |
        | Local-only (git, tests, file ops) | \(uia.localModel) | No API cost, private |
        | Complex reasoning, architecture | \(uia.orchestratorModel) | Full capability |
        | Context relay / handoff briefs | \(uia.cheapModel) | Compaction only |

        Governance may override model selection per policy rules.

        ## Context Exhaustion Protocol

        \(budgets.sorted { $0.key < $1.key }.map { "- **\($0.key)**: relay at \(Int($0.value.thresholdPercent * 100))% via `\($0.value.relayModel)`, handoff=`\($0.value.handoffStyle)`" }.joined(separator: "\n"))

        Before context exhaustion:
        1. Create a detailed handoff brief summarizing progress, remaining work, and key decisions
        2. Spawn a replacement agent with the brief as input
        3. The replacement agent continues from the handoff brief
        """
    }

    private func governanceBrief(_ config: GovernanceConfig) -> String {
        let enabledFeatures = GovernanceFeature.allCases.filter { config.isFeatureEnabled($0) }
        let budgets = config.contextBudgets ?? ContextBudget.defaults
        let uia = config.uiaConfig ?? .default
        return """
        # Engrave Governance Brief

        Governance is \(config.enabled ? "enabled" : "disabled").

        ## Active Features
        \(enabledFeatures.map { "- \($0.title): \($0.description)" }.joined(separator: "\n"))

        ## UIA
        - Orchestrator model: \(uia.orchestratorModel)
        - Cheap model: \(uia.cheapModel)
        - Local model: \(uia.localModel)
        - Explain work to user: \(uia.explainWorkToUser)
        - Create task DAG: \(uia.createTaskDAG)
        - Steer sub-agents: \(uia.steerSubAgents)

        ## Context Budgets
        \(budgets.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value.maxTokens.map(String.init) ?? "percentage-only") tokens at \(Int($0.value.thresholdPercent * 100))%, relay=\($0.value.relayModel), handoff=\($0.value.handoffStyle)" }.joined(separator: "\n"))

        ## Packaged Rules
        \(config.rules.map { "- [\($0.enabled ? "x" : " ")] \($0.name) (\($0.trigger.rawValue)/\($0.severity.rawValue)): \($0.description ?? "")" }.joined(separator: "\n"))
        """
    }

    private func geminiPolicy(_ config: GovernanceConfig) -> String {
        governanceBrief(config) + "\n\n" + subAgentInstructions(config) + """


        ## Runner Policy
        - Decompose multi-step work into a task DAG before spawning agents.
        - Route sub-agents to the cheapest model that can safely complete their scope.
        - Create a detailed handoff brief before context exhaustion.
        - Hold incoming/outgoing messages when human-in-the-loop interception is enabled.
        - Keep commits atomic and branches single-concern.
        - Add positive and negative tests for behavior changes.
        - Document every mock, stub, scaffold, placeholder, or TODO-only implementation.
        """
    }

    private func preCommitHook(_ config: GovernanceConfig) -> String {
        """
        #!/bin/sh
        # Generated by MLX Launcher / Engrave governance.
        set -eu
        files="$(git diff --cached --name-only)"
        if [ -z "$files" ]; then
          echo "No staged files."
          exit 1
        fi
        if echo "$files" | grep -E '(^|/)(\\.env|credentials|secrets\\.)' >/dev/null; then
          echo "Engrave governance: refusing commit containing sensitive paths."
          exit 1
        fi
        if git diff --cached | grep -Ei '\\b(mock|stub|scaffold|placeholder|TODO|fake)\\b' >/dev/null; then
          echo "Engrave governance warning: mocks/stubs/scaffolds/TODOs detected. Document intent before committing."
        fi
        if git diff --cached --name-only | grep -E '(Sources|Engrave/Sources)' >/dev/null &&
           ! git diff --cached --name-only | grep -E '(^Tests/|Tests/|test|spec)' >/dev/null; then
          echo "Engrave governance warning: code changed without staged tests."
        fi
        exit 0
        """
    }

    private func sessionCloseHook(_ config: GovernanceConfig) -> String {
        """
        #!/bin/sh
        # Generated by MLX Launcher / Engrave governance.
        set -eu
        if ! git diff --quiet || ! git diff --cached --quiet; then
          echo "Engrave governance: worktree has uncommitted changes."
          git status --short
          exit 1
        fi
        exit 0
        """
    }

    private func runningServerDoesNotMatch(_ model: MLXModel) -> Bool {
        guard let running = serverStatus.modelName else { return true }
        // The MLX server reports the full local path as the model ID.
        // Compare against both the model ID and its local path.
        let path = modelPath(for: model)
        let normalizedRunning = running.replacingOccurrences(of: "--", with: "/")
        let normalizedId = model.id.replacingOccurrences(of: "--", with: "/")
        return !running.contains(model.id)
            && !running.contains(path)
            && !path.contains(running)
            && !normalizedRunning.contains(normalizedId)
    }

    private func defaultModelArgs(_ userArgs: [String], flag: String, model: String) -> [String] {
        hasFlag(userArgs, flag) ? [] : [flag, model]
    }

    private func defaultCodexArgs(_ userArgs: [String], model: String) -> [String] {
        var args: [String] = []
        if !hasFlag(userArgs, "--model") && !userArgs.contains("-m") {
            args += ["-m", model]
        }
        if !userArgs.contains("-c") {
            args += [
                "-c", "model_provider=\"mlx\"",
                "-c", "model_providers.mlx={name=\"MLX via Engrave\",base_url=\"http://localhost:\(interposerPort)/v1\",env_key=\"OPENAI_API_KEY\",wire_api=\"responses\"}",
            ]
        }
        return args
    }

    private func defaultGeminiArgs(_ userArgs: [String], model: String) -> [String] {
        var args = defaultModelArgs(userArgs, flag: "-m", model: model)
        if !hasFlag(userArgs, "--policy") {
            args += ["--policy", "\(configDir)/governance/gemini-policy.md"]
        }
        return args
    }

    private func governanceRunnerEnvironment() -> [String: String] {
        [
            "ENGRAVE_GOVERNANCE_ENABLED": governanceConfig.enabled ? "1" : "0",
            "ENGRAVE_GOVERNANCE_BRIEF": "\(configDir)/governance/engrave-governance-brief.md",
            "ENGRAVE_GOVERNANCE_POLICY": "\(configDir)/governance/gemini-policy.md",
            "ENGRAVE_SUB_AGENT_LAUNCH": "\(configDir)/governance/sub-agent-launch.md",
            "ENGRAVE_INTERPOSER_URL": "http://localhost:\(interposerPort)",
            "ENGRAVE_INTERPOSER_PORT": String(interposerPort),
            "ENGRAVE_ALL_AGENTS_THROUGH_INTERPOSER": "1",
        ]
    }

    private func governanceRunnerInstruction() -> String {
        let uia = governanceConfig.uiaConfig ?? .default
        let budgets = governanceConfig.contextBudgets ?? ContextBudget.defaults
        let cheapModel = uia.cheapModel
        let localModel = uia.localModel

        return """
        ENGRAVE GOVERNANCE — SUB-AGENT LAUNCH PROTOCOL

        All sub-agent traffic MUST route through the Engrave interposer at http://localhost:\(interposerPort).

        When spawning sub-agents via Bash, use these exact patterns:

        Claude Code sub-agent:
          ANTHROPIC_BASE_URL=http://localhost:\(interposerPort) ANTHROPIC_API_KEY=mlx-local \\
          claude --print --output-format stream-json --model \(localModel) -p "<task>"

        Codex CLI sub-agent:
          OPENAI_BASE_URL=http://localhost:\(interposerPort)/v1 OPENAI_API_KEY=mlx-local \\
          codex exec --full-auto -m \(cheapModel) "<task>"

        Gemini CLI sub-agent:
          GOOGLE_GEMINI_BASE_URL=http://localhost:\(interposerPort) GEMINI_API_KEY=mlx-local GOOGLE_API_KEY=mlx-local \\
          gemini --yolo -m \(cheapModel) -p "<task>"

        Aider sub-agent:
          OPENAI_API_BASE=http://localhost:\(interposerPort)/v1 OPENAI_API_KEY=mlx-local \\
          aider --yes-always --no-auto-commits --model openai/\(cheapModel) --message "<task>"

        MODEL ROUTING:
        - Bounded, well-scoped sub-tasks: use \(cheapModel) (cheap model)
        - Local-only tasks (file ops, git, tests): use \(localModel) (local model)
        - Complex reasoning or architecture: use the orchestrator model
        - Governance may override model selection per policy rules

        CONTEXT BUDGETS:
        \(budgets.sorted { $0.key < $1.key }.map { "- \($0.key): relay at \(Int($0.value.thresholdPercent * 100))% via \($0.value.relayModel), handoff=\($0.value.handoffStyle)" }.joined(separator: "\n"))

        Before context exhaustion, create a detailed handoff brief and spawn a replacement agent with the brief as input.
        """
    }

    private func hasFlag(_ args: [String], _ flag: String) -> Bool {
        args.contains(flag) || args.contains(where: { $0.hasPrefix(flag + "=") })
    }

    private func modelPath(for model: MLXModel) -> String {
        if let localPath = model.localPath, !localPath.isEmpty { return localPath }
        return "\(modelsDir)/\(model.id)"
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
