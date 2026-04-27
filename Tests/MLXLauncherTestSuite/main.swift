import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(message: message) }
}

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let types = try read(root.appendingPathComponent("Sources/Types.swift").path)
let services = try read(root.appendingPathComponent("Sources/Services.swift").path)
let views = try read(root.appendingPathComponent("Sources/Views.swift").path)
let webUI = try read(root.appendingPathComponent("Sources/WebUI.swift").path)
let webServer = try read(root.appendingPathComponent("Sources/WebServer.swift").path)
let backendClient = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Backend/BackendClient.swift").path)
let connectionHandler = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Server/ConnectionHandler.swift").path)
let governanceConfig = try read(root.appendingPathComponent("Engrave/Sources/EngraveGovernance/GovernanceConfig.swift").path)
let policyRule = try read(root.appendingPathComponent("Engrave/Sources/EngraveGovernance/PolicyRule.swift").path)
let readme = try read(root.appendingPathComponent("README.md").path)
let buildApp = try read(root.appendingPathComponent("scripts/build_app.sh").path)

var tests: [(String, () throws -> Void)] = []

tests.append(("Codex is configured for governed proxy", {
    try expect(types.contains("Runner(id: \"codex\", name: \"Codex CLI\", icon: \"terminal\", needsProxy: true"), "Codex must keep needsProxy true for interpositional governance")
    try expect(types.contains("Runner(id: \"aider\", name: \"Aider\", icon: \"wrench.adjustable\", needsProxy: true"), "Aider must stay on the Engrave interposer path")
    try expect(types.contains("Runner(id: \"gptme\", name: \"gptme\", icon: \"message\", needsProxy: true"), "gptme must stay on the Engrave interposer path")
    try expect(services.contains("waitForInterposer"), "Launch path must wait for Engrave health before proxy-governed runners start")
    try expect(services.contains("model_provider=\\\"mlx\\\""), "Codex launch must set an MLX/Engrave model provider")
    try expect(services.contains("ENGRAVE_ALL_AGENTS_THROUGH_INTERPOSER"), "Runner environments must assert all agents remain Engrave-governed")
}))

tests.append(("Cloud models route through selected-model Engrave config", {
    try expect(services.contains("private func engraveConfig(for model: MLXModel) -> EngraveConfig"), "AppState must build Engrave config from selected model")
    try expect(services.contains("model: \"*\""), "Interposer must use wildcard model routing to avoid restarts")
    try expect(services.contains("case .anthropic:") && services.contains("Anthropic"), "Anthropic cloud models must have target description")
    try expect(services.contains("case .openai:") && services.contains("OpenAI"), "OpenAI cloud models must have target description")
    try expect(services.contains("case .google:") && services.contains("Gemini"), "Google cloud models must have target description")
    try expect(services.contains("let modelId = model.source == .local ? (serverStatus.modelName ?? modelName) : modelName"), "Cloud/network commands must not inherit a running local model")
}))

tests.append(("Model identity preserves discovered paths", {
    try expect(types.contains("let localPath: String?"), "MLXModel must carry localPath")
    try expect(types.contains("let networkHost: String?"), "MLXModel must carry networkHost")
    try expect(types.contains("var launchIdentity: String"), "MLXModel must expose stable launchIdentity")
    try expect(services.contains("if let localPath = model.localPath"), "modelPath(for:) must prefer discovered localPath")
}))

tests.append(("Model Store is wired into launcher selection", {
    try expect(services.contains("func selectDiscoveredModel"), "AppState needs a bridge from DiscoveredModel to selectedModel")
    try expect(services.contains("mergeLaunchableModels"), "AppState must merge script, ModelStore, network, and cloud models")
    try expect(views.contains("state.selectDiscoveredModel(model)"), "Model Store rows must load models into the launcher viewport")
}))

tests.append(("Web UI remains live after async bootstrap", {
    try expect(webUI.contains("const models = [], runners = []") == false, "Web UI model/runner variables must be mutable")
    try expect(webUI.contains("let models = [], runners = [], selectedModel = null, selectedRunner = null;"), "Web UI model/runner variables must use let")
    try expect(webUI.contains("async function refreshModels()"), "Web UI must refetch models after async bootstrap")
    try expect(webUI.contains("setInterval(refreshModels, 5000)"), "Web UI must keep model list fresh")
}))

tests.append(("REST API exposes required launcher endpoints", {
    for endpoint in ["/api/models", "/api/runners", "/api/server", "/api/server/start", "/api/server/stop", "/api/server/restart", "/api/launch"] {
        try expect(webServer.contains(endpoint), "Missing endpoint \(endpoint)")
    }
    try expect(webServer.contains("model or runner not found"), "Launch API must return an error for missing models/runners")
    try expect(webServer.contains("readAndSplitRequest(from"), "WebServer must use a Content-Length aware request reader")
    try expect(webServer.contains("requestExpectedTotalBytes"), "WebServer must read split POST bodies by Content-Length")
}))

tests.append(("Engrave preserves non-streaming requests", {
    try expect(backendClient.contains("modifiedRequest.stream = true") == false, "BackendClient must not force every request to stream")
    try expect(backendClient.contains("let verb = modifiedRequest.stream ? \"streamGenerateContent\" : \"generateContent\""), "Gemini backend endpoint must follow request stream mode")
    try expect(connectionHandler.contains("if !canonical.stream"), "ConnectionHandler must branch for non-streaming responses")
    try expect(connectionHandler.contains("nonStreamingResponse("), "ConnectionHandler must translate common non-streaming backend JSON")
    try expect(connectionHandler.contains("canonical.stream = path.contains(\":streamGenerateContent\")"), "Gemini facade must distinguish generateContent from streamGenerateContent")
}))

tests.append(("Priority 3 packaged governance is available", {
    for name in [
        "Sub-Agent Launch Control",
        "Context Exhaustion Relay",
        "Human In The Loop Interception",
        "UIA Prompt Decomposition And Task DAG",
        "Git Commit Hygiene",
        "Git Worktree Hygiene",
        "Test Driven Development",
        "No Undocumented Mocks Or Stubs",
    ] {
        try expect(policyRule.contains(name), "Missing packaged rule \(name)")
    }
    try expect(governanceConfig.contains("enum GovernanceFeature"), "Governance feature toggles must be codified")
    try expect(governanceConfig.contains("struct ContextBudget"), "Context budgets must be persisted in governance config")
    try expect(governanceConfig.contains("struct UIAGovernanceConfig"), "UIA governance config must be persisted")
    try expect(services.contains("writeGovernanceArtifacts"), "Governance saves must generate runner policy artifacts")
    try expect(services.contains("pre-commit") && services.contains("session-close-check"), "Generated governance hooks must include commit/worktree hygiene")
}))

tests.append(("Priority 3 packaging and persistence are wired", {
    try expect(buildApp.contains("CFBundleIdentifier"), "App bundle script must generate Info.plist")
    try expect(buildApp.contains("AppIcon.icns"), "App bundle script must wire generated icon")
    try expect(readme.contains("./scripts/build_app.sh release"), "README install docs must use app build script")
    try expect(services.contains("runner-settings.json"), "Runner settings must persist")
    try expect(services.contains("model-store.json"), "Model Store directories must persist")
    try expect(views.contains("Install Packaged"), "Governance UI must expose packaged feature toggles")
    try expect(views.contains("Context Exhaustion Relay"), "Governance UI must expose context relay budgets")
    // UIA settings moved to Settings panel per user feedback — verify they exist somewhere
    let settingsPanel = try read(root.appendingPathComponent("Sources/SettingsPanel.swift").path)
    try expect(settingsPanel.contains("uia") || settingsPanel.contains("UIA"), "UIA settings must exist in Settings panel")
}))

tests.append(("All bundled runners are Engrave-governed", {
    let runnerFragments = [
        "Runner(id: \"claude\", name: \"Claude Code\", icon: \"brain.head.profile\", needsProxy: true",
        "Runner(id: \"codex\", name: \"Codex CLI\", icon: \"terminal\", needsProxy: true",
        "Runner(id: \"gemini\", name: \"Gemini CLI\", icon: \"sparkles\", needsProxy: true",
        "Runner(id: \"aider\", name: \"Aider\", icon: \"wrench.adjustable\", needsProxy: true",
        "Runner(id: \"gptme\", name: \"gptme\", icon: \"message\", needsProxy: true",
    ]
    for fragment in runnerFragments {
        try expect(types.contains(fragment), "Runner must be governed through Engrave: \(fragment)")
    }
    try expect(services.contains("governanceRunnerEnvironment()"), "Launches must include governance environment")
    try expect(services.contains("ENGRAVE_INTERPOSER_URL"), "Launches must expose Engrave interposer URL")
}))

tests.append(("Governance docs capture migration scope", {
    let hemNotes = try read(root.appendingPathComponent("private/docs/archive-hem-governance-priorities-april-25-2026.md").path)
    for phrase in ["Sub-Agent Launch Control", "Context Exhaustion Relay", "Human In The Loop Interception", "Git Commit Hygiene", "No Undocumented Mocks Or Stubs"] {
        try expect(hemNotes.contains(phrase), "Migration notes must mention \(phrase)")
    }
}))

var failures: [String] = []
for (name, test) in tests {
    do {
        try test()
        print("✓ \(name)")
    } catch {
        failures.append("✗ \(name): \(error)")
    }
}

if !failures.isEmpty {
    failures.forEach { print($0) }
    exit(1)
}
print("All \(tests.count) MLX Launcher tests passed.")
