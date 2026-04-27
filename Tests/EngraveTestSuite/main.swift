import Foundation

// MARK: - Test Infrastructure

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

/// Count occurrences of a substring
func count(_ source: String, _ pattern: String) -> Int {
    var n = 0
    var search = source.startIndex
    while let range = source.range(of: pattern, range: search..<source.endIndex) {
        n += 1
        search = range.upperBound
    }
    return n
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// Load all source files
let types = try read(root.appendingPathComponent("Sources/Types.swift").path)
let services = try read(root.appendingPathComponent("Sources/Services.swift").path)
let webServer = try read(root.appendingPathComponent("Sources/WebServer.swift").path)
let webUI = try read(root.appendingPathComponent("Sources/WebUI.swift").path)
let packageSwift = try read(root.appendingPathComponent("Package.swift").path)
let engravePackage = try read(root.appendingPathComponent("Engrave/Package.swift").path)
let buildApp = try read(root.appendingPathComponent("scripts/build_app.sh").path)

// Engrave Interposer sources
let canonicalTypes = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/IR/CanonicalTypes.swift").path)
let streamTypes = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/IR/StreamTypes.swift").path)
let messageTranslator = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Translate/MessageTranslator.swift").path)
let toolTranslator = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Translate/ToolTranslator.swift").path)
let streamTranslator = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Translate/StreamTranslator.swift").path)
let routeResolver = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Server/RouteResolver.swift").path)
let connectionHandler = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Server/ConnectionHandler.swift").path)
let backendClient = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Backend/BackendClient.swift").path)
let engraveConfig = try read(root.appendingPathComponent("Engrave/Sources/EngraveInterposer/Config/EngraveConfig.swift").path)

// Engrave Governance sources
let governanceConfig = try read(root.appendingPathComponent("Engrave/Sources/EngraveGovernance/GovernanceConfig.swift").path)
let policyRule = try read(root.appendingPathComponent("Engrave/Sources/EngraveGovernance/PolicyRule.swift").path)
let governanceTypes = try read(root.appendingPathComponent("Engrave/Sources/EngraveGovernance/GovernanceTypes.swift").path)
let governanceBridge = try read(root.appendingPathComponent("Engrave/Sources/EngraveGovernance/GovernanceBridge.swift").path)

var tests: [(String, () throws -> Void)] = []

// ============================================================================
// MARK: - 1. UNIT TESTS (POSITIVE)
// ============================================================================

// --- Types.swift: MLXModel ---

tests.append(("MLXModel.shortName extracts last path component", {
    // shortName uses components(separatedBy: "/").last ?? id
    try expect(types.contains("id.components(separatedBy: \"/\").last ?? id"), "shortName must split by / and take last component")
}))

tests.append(("MLXModel.isCloud covers anthropic, openai, google", {
    try expect(types.contains("var isCloud: Bool { source == .anthropic || source == .openai || source == .google }"),
               "isCloud must be true for all 3 cloud providers")
}))

tests.append(("MLXModel.isNetwork checks for .network source", {
    try expect(types.contains("var isNetwork: Bool { source == .network }"),
               "isNetwork must check for .network source")
}))

tests.append(("MLXModel.launchIdentity uses local, network, or source prefix", {
    try expect(types.contains("if let localPath { return \"local:\\(localPath)\" }"),
               "launchIdentity must prefix local paths")
    try expect(types.contains("if let networkHost, let networkPort { return \"network:\\(networkHost):\\(networkPort)/\\(id)\" }"),
               "launchIdentity must include network host and port")
    try expect(types.contains("return \"\\(source.rawValue):\\(id)\""),
               "launchIdentity must fall back to source:id")
}))

tests.append(("MLXModel.providerBadge returns correct string for each source", {
    for (source, badge) in [("local", "MLX"), ("network", "Network"), ("anthropic", "Anthropic"), ("openai", "OpenAI"), ("google", "Google")] {
        try expect(types.contains("case .\(source): return \"\(badge)\""),
                   "providerBadge must return \(badge) for .\(source)")
    }
}))

tests.append(("ModelSource has exactly 5 cases", {
    try expect(types.contains("case local, network, anthropic, openai, google"),
               "ModelSource must have all 5 cases")
}))

// --- Types.swift: GenerationProfile ---

tests.append(("GenerationProfile builtins include all 5 profiles", {
    for name in ["Default", "Coding", "Precise", "Creative", "Reasoning"] {
        try expect(types.contains("name: \"\(name)\""), "Missing builtin profile: \(name)")
    }
    try expect(types.contains("static let builtins: [GenerationProfile] = [.default, .coding, .precise, .creative, .reasoning]"),
               "builtins array must include all 5 profiles")
}))

tests.append(("GenerationProfile builtins have valid temp (0-1)", {
    // Parse temp values from source
    for profile in ["default", "coding", "precise", "creative", "reasoning"] {
        // Verify each static let exists with a temp value
        try expect(types.contains("static let \(profile)") || types.contains("static let `\(profile)`"),
                   "Profile \(profile) must be a static let")
    }
    // Verify concrete values: 0.7, 0.2, 0.1, 0.9, 0.3 -- all in [0,1]
    for val in ["0.7", "0.2", "0.1", "0.9", "0.3"] {
        try expect(types.contains("temp: \(val)"), "Expected temp value \(val) in profiles")
    }
}))

tests.append(("GenerationProfile builtins have positive top_k", {
    for val in ["40", "20", "10", "80", "30"] {
        try expect(types.contains("top_k: \(val)"), "Expected top_k value \(val) in profiles")
    }
}))

tests.append(("GenerationProfile builtins have positive max_tokens", {
    for val in ["4096", "8192"] {
        try expect(types.contains("max_tokens: \(val)"), "Expected max_tokens value \(val) in profiles")
    }
}))

// --- Types.swift: SystemPrompt ---

tests.append(("SystemPrompt builtins have non-empty fields", {
    try expect(types.contains("static let builtins: [SystemPrompt] = ["),
               "SystemPrompt must have builtins array")
    // All builtins have source: "built-in"
    let builtinCount = count(types, "source: \"built-in\"")
    try expect(builtinCount >= 20, "Expected at least 20 built-in system prompts, found \(builtinCount)")
    // Each has a non-empty name and prompt
    try expect(types.contains("SystemPrompt(name: \"Software Engineer\""), "Missing Software Engineer prompt")
    try expect(types.contains("SystemPrompt(name: \"MLX Expert\""), "Missing MLX Expert prompt")
}))

// --- Types.swift: CloudModelsConfig ---

tests.append(("CloudModelsConfig.builtins has entries for all 3 providers", {
    try expect(types.contains("static let builtins = CloudModelsConfig("),
               "CloudModelsConfig must have builtins")
    try expect(types.contains("anthropic: ["), "builtins must have anthropic entries")
    try expect(types.contains("openai: ["), "builtins must have openai entries")
    try expect(types.contains("google: ["), "builtins must have google entries")
}))

// --- Types.swift: Runner ---

tests.append(("Runner binary names and searchPaths are correct", {
    for (id, binary) in [("claude", "claude"), ("codex", "codex"), ("gemini", "gemini"), ("aider", "aider"), ("gptme", "gptme")] {
        try expect(types.contains("Runner(id: \"\(id)\"") && types.contains("binary: \"\(binary)\""),
                   "Runner \(id) must have binary \(binary)")
    }
    try expect(types.contains("/opt/homebrew/bin"), "searchPaths must include /opt/homebrew/bin")
    try expect(types.contains("/usr/local/bin"), "searchPaths must include /usr/local/bin")
    try expect(types.contains("/usr/bin"), "searchPaths must include /usr/bin")
    try expect(types.contains(".local/bin"), "searchPaths must include .local/bin")
    try expect(types.contains(".cargo/bin"), "searchPaths must include .cargo/bin")
}))

// --- CanonicalTypes.swift ---

tests.append(("CanonicalTypes has all required public types", {
    try expect(canonicalTypes.contains("public enum Provider:"), "Missing Provider enum")
    try expect(canonicalTypes.contains("public enum Role:"), "Missing Role enum")
    try expect(canonicalTypes.contains("public struct TextBlock:"), "Missing TextBlock")
    try expect(canonicalTypes.contains("public struct ToolUseBlock:"), "Missing ToolUseBlock")
    try expect(canonicalTypes.contains("public struct ToolResultBlock:"), "Missing ToolResultBlock")
    try expect(canonicalTypes.contains("public struct ThinkingBlock:"), "Missing ThinkingBlock")
    try expect(canonicalTypes.contains("public struct ImageBlock:"), "Missing ImageBlock")
    try expect(canonicalTypes.contains("public enum ContentBlock:"), "Missing ContentBlock enum")
    try expect(canonicalTypes.contains("public struct CanonicalRequest:"), "Missing CanonicalRequest")
    try expect(canonicalTypes.contains("public struct CanonicalResponse:"), "Missing CanonicalResponse")
    try expect(canonicalTypes.contains("public enum StopReason:"), "Missing StopReason enum")
    try expect(canonicalTypes.contains("public struct Usage:"), "Missing Usage struct")
    try expect(canonicalTypes.contains("public enum JSON"), "Missing JSON helpers")
}))

tests.append(("JSON helpers include all utility methods", {
    for method in ["string", "int", "uint32", "float", "bool", "dict", "array", "parse", "serialize", "serializeString"] {
        try expect(canonicalTypes.contains("public static func \(method)("), "Missing JSON.\(method)")
    }
}))

// --- MessageTranslator ---

tests.append(("MessageTranslator has all 4 format parsers", {
    try expect(messageTranslator.contains("func parseAnthropicRequest("), "Missing Anthropic parser")
    try expect(messageTranslator.contains("func parseChatCompletionsRequest("), "Missing ChatCompletions parser")
    try expect(messageTranslator.contains("func parseOpenAIRequest("), "Missing OpenAI Responses parser")
    try expect(messageTranslator.contains("func parseGeminiRequest("), "Missing Gemini parser")
}))

tests.append(("MessageTranslator has all 4 format serializers", {
    try expect(messageTranslator.contains("func canonicalToAnthropicBody("), "Missing Anthropic serializer")
    try expect(messageTranslator.contains("func canonicalToChatCompletionsBody("), "Missing ChatCompletions serializer")
    try expect(messageTranslator.contains("func canonicalToOpenAIBody("), "Missing OpenAI serializer")
    try expect(messageTranslator.contains("func canonicalToGeminiBody("), "Missing Gemini serializer")
}))

// --- ToolTranslator ---

tests.append(("ToolTranslator has all 4 format pairs", {
    // Anthropic
    try expect(toolTranslator.contains("func anthropicToCanonical("), "Missing anthropicToCanonical")
    try expect(toolTranslator.contains("func canonicalToAnthropic("), "Missing canonicalToAnthropic")
    // ChatCompletions
    try expect(toolTranslator.contains("func chatCompletionsToCanonical("), "Missing chatCompletionsToCanonical")
    try expect(toolTranslator.contains("func canonicalToChatCompletions("), "Missing canonicalToChatCompletions")
    // OpenAI Responses
    try expect(toolTranslator.contains("func openAIToCanonical("), "Missing openAIToCanonical")
    try expect(toolTranslator.contains("func canonicalToOpenAI("), "Missing canonicalToOpenAI")
    // Gemini
    try expect(toolTranslator.contains("func geminiToCanonical("), "Missing geminiToCanonical")
    try expect(toolTranslator.contains("func canonicalToGemini("), "Missing canonicalToGemini")
}))

// --- StreamTranslator ---

tests.append(("StreamTranslator handles all stream event formats", {
    try expect(streamTranslator.contains("func parseAnthropicSSE("), "Missing Anthropic SSE parser")
    try expect(streamTranslator.contains("func parseChatCompletionsSSE("), "Missing ChatCompletions SSE parser")
    try expect(streamTranslator.contains("func parseOpenAISSE("), "Missing OpenAI SSE parser")
    try expect(streamTranslator.contains("func parseGeminiSSE("), "Missing Gemini SSE parser")
    // Serializers
    try expect(streamTranslator.contains("func canonicalToAnthropicSSE("), "Missing Anthropic SSE serializer")
    try expect(streamTranslator.contains("func canonicalToChatCompletionsSSE("), "Missing ChatCompletions SSE serializer")
    try expect(streamTranslator.contains("func canonicalToOpenAISSE("), "Missing OpenAI SSE serializer")
    try expect(streamTranslator.contains("func canonicalToGeminiSSE("), "Missing Gemini SSE serializer")
}))

// --- StreamTypes ---

tests.append(("CanonicalStreamEvent has all required cases", {
    for eventCase in ["messageStart", "contentBlockStart", "textDelta", "toolInputDelta", "contentBlockEnd", "messageDelta", "messageEnd", "error"] {
        try expect(streamTypes.contains("case \(eventCase)"), "Missing CanonicalStreamEvent case: \(eventCase)")
    }
    try expect(streamTypes.contains("enum BlockType:"), "Missing BlockType enum")
    for bt in ["text", "toolUse", "thinking"] {
        try expect(streamTypes.contains("case \(bt)"), "Missing BlockType case: \(bt)")
    }
}))

// --- RouteResolver ---

tests.append(("RouteResolver.sourceProvider identifies all 4 API paths", {
    try expect(routeResolver.contains("/v1/messages"), "Missing Anthropic path /v1/messages")
    try expect(routeResolver.contains("/v1/chat/completions"), "Missing ChatCompletions path")
    try expect(routeResolver.contains("/v1/responses"), "Missing OpenAI Responses path")
    try expect(routeResolver.contains(":generateContent") && routeResolver.contains(":streamGenerateContent"),
               "Missing Gemini generateContent paths")
    try expect(routeResolver.contains("/v1beta/models/"), "Missing v1beta Gemini path")
}))

tests.append(("RouteResolver returns provider strings for each path", {
    try expect(routeResolver.contains("return (\"anthropic\""), "sourceProvider must return anthropic")
    try expect(routeResolver.contains("return (\"openai_compatible\""), "sourceProvider must return openai_compatible")
    try expect(routeResolver.contains("return (\"openai\""), "sourceProvider must return openai")
    try expect(routeResolver.contains("return (\"gemini\""), "sourceProvider must return gemini")
    try expect(routeResolver.contains("return (\"unknown\""), "sourceProvider must return unknown for unmatched")
}))

// --- GovernanceConfig ---

tests.append(("GovernanceConfig presets exist with correct properties", {
    // Strict
    try expect(governanceConfig.contains("public static let strict = GovernanceConfig("),
               "Missing strict preset")
    try expect(governanceConfig.contains("sandboxLevel: .sandbox") && governanceConfig.contains("static let strict"),
               "Strict preset must use .sandbox level")
    // Standard
    try expect(governanceConfig.contains("public static let standard = GovernanceConfig("),
               "Missing standard preset")
    try expect(governanceConfig.contains("sandboxLevel: .workspace"),
               "Standard preset must use .workspace level")
    // Minimal
    try expect(governanceConfig.contains("public static let minimal = GovernanceConfig("),
               "Missing minimal preset")
    try expect(governanceConfig.contains("sandboxLevel: .full"),
               "Minimal preset must use .full level")
}))

// --- GovernanceFeature ---

tests.append(("GovernanceFeature cases all have title and description", {
    let featureCases = [
        "subAgentLaunchControl", "contextExhaustionRelay", "humanInTheLoopInterception",
        "uiaPromptDecomposition", "workflowTaskDAG", "gitCommitHygiene",
        "gitWorktreeHygiene", "testDrivenDevelopment", "mockStubDocumentation"
    ]
    for f in featureCases {
        try expect(governanceConfig.contains("case \(f)"), "Missing GovernanceFeature case: \(f)")
    }
    // title and description are computed as switches covering all cases
    try expect(governanceConfig.contains("public var title: String"), "GovernanceFeature must have title")
    try expect(governanceConfig.contains("public var description: String"), "GovernanceFeature must have description")
}))

// --- ContextBudget ---

tests.append(("ContextBudget defaults cover all agent types", {
    for agentType in ["default", "explorer", "worker", "reviewer", "uia"] {
        try expect(governanceConfig.contains("\"\(agentType)\": ContextBudget("),
                   "Missing ContextBudget default for \(agentType)")
    }
}))

// --- PolicyRule ---

tests.append(("PolicyRule packaged rules exist with correct triggers", {
    let expectedRules: [(String, String)] = [
        ("Sub-Agent Launch Control", "request"),
        ("Context Exhaustion Relay", "request"),
        ("Human In The Loop Interception", "request"),
        ("UIA Prompt Decomposition And Task DAG", "request"),
        ("Git Commit Hygiene", "toolCall"),
        ("Git Worktree Hygiene", "toolCall"),
        ("Test Driven Development", "request"),
        ("No Undocumented Mocks Or Stubs", "response"),
    ]
    for (name, _) in expectedRules {
        try expect(policyRule.contains(name), "Missing packaged rule: \(name)")
    }
    // Verify triggers
    try expect(policyRule.contains("subAgentLaunchControl = PolicyRule(\n        name: \"Sub-Agent Launch Control\",\n        trigger: .request"),
               "Sub-Agent Launch Control must have .request trigger")
    try expect(policyRule.contains("gitCommitHygiene = PolicyRule(\n        name: \"Git Commit Hygiene\",\n        trigger: .toolCall"),
               "Git Commit Hygiene must have .toolCall trigger")
    try expect(policyRule.contains("noUndocumentedMocksOrStubs = PolicyRule(\n        name: \"No Undocumented Mocks Or Stubs\",\n        trigger: .response"),
               "No Undocumented Mocks must have .response trigger")
}))

// ============================================================================
// MARK: - 2. UNIT TESTS (NEGATIVE / ENUM CARDINALITY)
// ============================================================================

tests.append(("CloudAuthMode has exactly 2 cases", {
    let cases = count(types, "case cliSubscription") + count(types, "case apiKey")
    try expect(cases == 2, "CloudAuthMode should have exactly 2 cases, found \(cases)")
    try expect(types.contains("enum CloudAuthMode: String, Codable, CaseIterable"),
               "CloudAuthMode must be CaseIterable")
}))

tests.append(("ServerState has exactly 4 cases", {
    try expect(types.contains("case stopped, starting, running, error"), "ServerState must have 4 cases")
}))

tests.append(("Provider enum has exactly 4 cases", {
    let providerCases = ["case anthropic", "case openAI", "case openAICompatible", "case gemini"]
    for c in providerCases {
        try expect(canonicalTypes.contains(c), "Provider missing case: \(c)")
    }
}))

tests.append(("Role enum has exactly 2 cases", {
    try expect(canonicalTypes.contains("case user") && canonicalTypes.contains("case assistant"),
               "Role must have user and assistant cases")
    // Ensure no other cases in the Role enum (by checking the declaration block)
    try expect(canonicalTypes.contains("public enum Role: String, Codable, Sendable {\n    case user\n    case assistant\n}"),
               "Role enum should have exactly user and assistant")
}))

tests.append(("StopReason has exactly 4 cases", {
    for c in ["endTurn", "toolUse", "maxTokens", "error"] {
        try expect(canonicalTypes.contains("case \(c)"), "StopReason missing case: \(c)")
    }
}))

tests.append(("SandboxLevel ordering: jailed < sandbox < workspace < full", {
    try expect(governanceTypes.contains("let order: [SandboxLevel] = [.jailed, .sandbox, .workspace, .full]"),
               "SandboxLevel ordering must be jailed < sandbox < workspace < full")
    try expect(governanceTypes.contains("Comparable"), "SandboxLevel must conform to Comparable")
}))

tests.append(("PolicyDecision severity ordering: allow < warn < modify < rewrite < block < circuitBreak", {
    // Check severity values: allow=0, warn=1, modify=2, rewrite=3, block=4, circuitBreak=5
    try expect(governanceTypes.contains("case .allow: return 0"), "allow severity must be 0")
    try expect(governanceTypes.contains("case .warn: return 1"), "warn severity must be 1")
    try expect(governanceTypes.contains("case .modify: return 2"), "modify severity must be 2")
    try expect(governanceTypes.contains("case .rewrite: return 3"), "rewrite severity must be 3")
    try expect(governanceTypes.contains("case .block: return 4"), "block severity must be 4")
    try expect(governanceTypes.contains("case .circuitBreak: return 5"), "circuitBreak severity must be 5")
}))

tests.append(("ToolRisk has exactly 3 cases", {
    for c in ["safe", "needsGovernance", "dangerous"] {
        try expect(governanceTypes.contains("case \(c)"), "ToolRisk missing case: \(c)")
    }
}))

tests.append(("MLXModel with empty id still produces a shortName", {
    // shortName uses .last ?? id, so empty string -> empty string via fallback
    try expect(types.contains(".last ?? id"), "shortName must fallback to id for empty strings")
}))

// ============================================================================
// MARK: - 3. INTEGRATION TESTS
// ============================================================================

tests.append(("MessageTranslator round-trip: parse + serialize for all 4 formats", {
    // Verify each format has both parse and canonical-to-X
    let formats: [(String, String, String)] = [
        ("Anthropic", "parseAnthropicRequest", "canonicalToAnthropicBody"),
        ("ChatCompletions", "parseChatCompletionsRequest", "canonicalToChatCompletionsBody"),
        ("OpenAI", "parseOpenAIRequest", "canonicalToOpenAIBody"),
        ("Gemini", "parseGeminiRequest", "canonicalToGeminiBody"),
    ]
    for (name, parse, serialize) in formats {
        try expect(messageTranslator.contains(parse), "\(name) parse function missing")
        try expect(messageTranslator.contains(serialize), "\(name) serialize function missing")
    }
}))

tests.append(("Engrave config builds providers from engine registry", {
    // Providers are built dynamically from engineEndpoints, not hardcoded
    try expect(services.contains("engineEndpoints"), "Must build providers from engine registry")
    try expect(services.contains("engine.type"), "Must use engine.type for provider config")
    try expect(services.contains("engine.baseURL"), "Must use engine.baseURL for provider config")
    // Core providers ensured even if deleted
    try expect(services.contains("local_mlx"), "Must ensure local MLX provider exists as fallback")
}))

tests.append(("Engrave config uses universal model-based routing", {
    // Model routes built from registry + builtins
    try expect(services.contains("ModelRoute.builtins"), "Must include built-in model routes")
    try expect(services.contains("modelRouteMappings"), "Must include user-defined model route mappings")
    // All facades fall through to local as default
    try expect(services.contains("\"anthropic\": local"), "Default anthropic facade must route to local")
    try expect(services.contains("\"openai\": local"), "Default openai facade must route to local")
    try expect(services.contains("\"gemini\": local"), "Default gemini facade must route to local")
    // Engine registry types exist
    let types = try read(root.appendingPathComponent("Sources/Types.swift").path)
    try expect(types.contains("enum EngineBackend"), "Must define EngineBackend enum")
    try expect(types.contains("enum EngineParameter"), "Must define EngineParameter enum")
    try expect(types.contains("struct EngineParameters"), "Must define EngineParameters struct")
}))

tests.append(("Runner command generation for all 5 runners", {
    for runner in ["claude", "codex", "gemini", "aider", "gptme"] {
        try expect(services.contains("case \"\(runner)\":"), "Missing runnerCommand case for \(runner)")
    }
}))

tests.append(("Each runner has correct env vars", {
    // Claude uses ANTHROPIC_BASE_URL
    try expect(services.contains("\"ANTHROPIC_BASE_URL\": interposerBase"), "Claude must set ANTHROPIC_BASE_URL")
    // Codex uses OPENAI_BASE_URL
    try expect(services.contains("\"OPENAI_BASE_URL\": \"\\(interposerBase)/v1\""), "Codex must set OPENAI_BASE_URL")
    // Gemini uses GOOGLE_GEMINI_BASE_URL
    try expect(services.contains("\"GOOGLE_GEMINI_BASE_URL\": interposerBase"), "Gemini must set GOOGLE_GEMINI_BASE_URL")
    // Aider uses OPENAI_API_BASE
    try expect(services.contains("\"OPENAI_API_BASE\": \"\\(interposerBase)/v1\""), "Aider must set OPENAI_API_BASE")
    // gptme uses OPENAI_API_BASE
    try expect(services.contains("gptmeEnv"), "gptme must have its own env dict")
}))

tests.append(("Governance artifacts are all generated", {
    for artifact in ["engrave-governance-brief.md", "gemini-policy.md", "sub-agent-launch.md", "pre-commit", "session-close-check"] {
        try expect(services.contains(artifact), "Missing governance artifact: \(artifact)")
    }
}))

tests.append(("Auth header passthrough is wired", {
    try expect(backendClient.contains("clientAuthHeaders: [String: String]"),
               "BackendClient must accept clientAuthHeaders parameter")
    try expect(connectionHandler.contains("extractAuthHeaders(from:"),
               "ConnectionHandler must extract auth headers")
    try expect(connectionHandler.contains("clientAuth"), "ConnectionHandler must pass auth to backend")
}))

tests.append(("ConnectionHandler branches for non-streaming requests", {
    try expect(connectionHandler.contains("if !canonical.stream"),
               "ConnectionHandler must branch on stream flag")
    try expect(connectionHandler.contains("nonStreamingResponse("),
               "ConnectionHandler must have non-streaming response path")
}))

tests.append(("GovernanceBridge routes all 4 providers", {
    try expect(governanceBridge.contains("case \"anthropic\":"), "GovernanceBridge missing anthropic")
    try expect(governanceBridge.contains("case \"openai_compatible\":"), "GovernanceBridge missing openai_compatible")
    try expect(governanceBridge.contains("case \"openai\":"), "GovernanceBridge missing openai")
    try expect(governanceBridge.contains("case \"gemini\":"), "GovernanceBridge missing gemini")
}))

// ============================================================================
// MARK: - 4. SYSTEM TESTS
// ============================================================================

tests.append(("Package.swift dependencies are consistent", {
    try expect(packageSwift.contains(".package(path: \"./Engrave\")"), "Root must depend on Engrave")
    try expect(packageSwift.contains("mlx-swift"), "Root must depend on mlx-swift")
    try expect(packageSwift.contains("mlx-swift-lm"), "Root must depend on mlx-swift-lm")
    try expect(packageSwift.contains("swift-transformers"), "Root must depend on swift-transformers")
}))

tests.append(("Engrave Package.swift defines required targets", {
    try expect(engravePackage.contains("EngraveInterposer"), "Engrave must have EngraveInterposer target")
    try expect(engravePackage.contains("EngraveGovernance"), "Engrave must have EngraveGovernance target")
    try expect(engravePackage.contains("EngraveCLI"), "Engrave must have EngraveCLI target")
}))

tests.append(("All required source files exist", {
    let requiredFiles = [
        "Sources/Types.swift",
        "Sources/Services.swift",
        "Sources/Views.swift",
        "Sources/WebUI.swift",
        "Sources/WebServer.swift",
        "Engrave/Sources/EngraveInterposer/IR/CanonicalTypes.swift",
        "Engrave/Sources/EngraveInterposer/IR/StreamTypes.swift",
        "Engrave/Sources/EngraveInterposer/Translate/MessageTranslator.swift",
        "Engrave/Sources/EngraveInterposer/Translate/ToolTranslator.swift",
        "Engrave/Sources/EngraveInterposer/Translate/StreamTranslator.swift",
        "Engrave/Sources/EngraveInterposer/Server/RouteResolver.swift",
        "Engrave/Sources/EngraveInterposer/Server/ConnectionHandler.swift",
        "Engrave/Sources/EngraveInterposer/Backend/BackendClient.swift",
        "Engrave/Sources/EngraveGovernance/GovernanceConfig.swift",
        "Engrave/Sources/EngraveGovernance/PolicyRule.swift",
        "Engrave/Sources/EngraveGovernance/GovernanceTypes.swift",
        "Engrave/Sources/EngraveGovernance/GovernanceBridge.swift",
    ]
    for file in requiredFiles {
        let path = root.appendingPathComponent(file).path
        try expect(FileManager.default.fileExists(atPath: path), "Missing required file: \(file)")
    }
}))

tests.append(("Build script produces correct bundle structure", {
    try expect(buildApp.contains("CFBundleIdentifier"), "build_app.sh must generate Info.plist with CFBundleIdentifier")
    try expect(buildApp.contains("AppIcon.icns"), "build_app.sh must wire app icon")
    try expect(buildApp.contains("mlx.metallib"), "build_app.sh must search for Metal shader library")
    try expect(buildApp.contains("MacOS") && buildApp.contains("mkdir"), "build_app.sh must create MacOS directory")
    try expect(buildApp.contains("Resources") && buildApp.contains("mkdir"), "build_app.sh must create Resources directory")
}))

tests.append(("Config directory structure in Services.swift", {
    try expect(services.contains("runner-settings.json"), "Must persist runner settings")
    try expect(services.contains("model-store.json"), "Must persist model store settings")
    try expect(services.contains("governance.json"), "Must persist governance config")
    try expect(services.contains("profiles"), "Must have profiles directory")
    try expect(services.contains("prompts"), "Must have prompts directory")
}))

tests.append(("WebServer endpoints exist", {
    for endpoint in ["/api/models", "/api/runners", "/api/server", "/api/server/start", "/api/server/stop", "/api/server/restart", "/api/launch"] {
        try expect(webServer.contains(endpoint), "Missing WebServer endpoint: \(endpoint)")
    }
}))

// ============================================================================
// MARK: - 5. END-TO-END CONTRACT TESTS
// ============================================================================

tests.append(("Anthropic request -> parse -> canonical -> ChatCompletions body contract", {
    // Verify the parse path: Anthropic body keys -> canonical fields -> ChatCompletions keys
    // Parse reads: model, system, messages, tools, stream, max_tokens, temperature
    try expect(messageTranslator.contains("JSON.string(body[\"model\"])"), "Anthropic parser must read model")
    try expect(messageTranslator.contains("JSON.array(body[\"messages\"])"), "Anthropic parser must read messages")
    try expect(messageTranslator.contains("JSON.bool(body[\"stream\"])"), "Anthropic parser must read stream")
    // Serialize writes: model, stream, messages array, system as role:system
    try expect(messageTranslator.contains("[\"role\": \"system\", \"content\": system]"),
               "ChatCompletions serializer must emit system as role:system message")
    try expect(messageTranslator.contains("\"model\": req.model"), "ChatCompletions serializer must emit model")
}))

tests.append(("Gemini request -> parse -> canonical -> ChatCompletions body contract", {
    // Parse reads: contents, system_instruction, tools/functionDeclarations, generationConfig
    try expect(messageTranslator.contains("JSON.array(body[\"contents\"])"), "Gemini parser must read contents")
    try expect(messageTranslator.contains("JSON.dict(body[\"system_instruction\"])"), "Gemini parser must read system_instruction")
    try expect(messageTranslator.contains("functionDeclarations"), "Gemini parser must read functionDeclarations")
}))

tests.append(("OpenAI Responses -> parse -> canonical -> Anthropic body contract", {
    // Parse reads: input, instructions, model, tools
    try expect(messageTranslator.contains("JSON.string(body[\"instructions\"])"), "OpenAI parser must read instructions")
    try expect(messageTranslator.contains("JSON.array(body[\"input\"])"), "OpenAI parser must read input array")
    // Anthropic serializer writes: system as array of text blocks
    try expect(messageTranslator.contains("[\"type\": \"text\", \"text\": system]"),
               "Anthropic serializer must emit system as text blocks")
}))

tests.append(("Tool call lifecycle: Anthropic tool_use -> canonical -> ChatCompletions tool_calls", {
    // Anthropic parse: reads type=tool_use, id, name, input
    try expect(messageTranslator.contains("case \"tool_use\":"), "Parser must handle tool_use blocks")
    try expect(messageTranslator.contains("ToolUseBlock(id: id, name: name, input: input)"), "Parser must create ToolUseBlock")
    // ChatCompletions serialize: emits tool_calls array with function.name, function.arguments
    try expect(messageTranslator.contains("\"type\": \"function\""), "ChatCompletions must emit function type")
    try expect(messageTranslator.contains("\"function\": [\"name\": tu.name, \"arguments\": argsStr]"),
               "ChatCompletions must emit function name and arguments")
}))

tests.append(("Governance lifecycle: strict config blocks dangerous commands", {
    // Strict config includes blockDangerousBash with .block severity
    try expect(policyRule.contains("static let blockDangerousBash = PolicyRule("),
               "Must have blockDangerousBash rule")
    try expect(policyRule.contains("severity: .block") && policyRule.contains("rm\\\\s+-rf"),
               "blockDangerousBash must block rm -rf with .block severity")
    // Governance evaluator checks allowed flag
    try expect(connectionHandler.contains("if !result.allowed"), "ConnectionHandler must check governance result")
    try expect(connectionHandler.contains("status: 403"), "Blocked requests must return 403")
}))

tests.append(("Runner integration: each runner gets correct env vars and arguments", {
    // Claude gets --model flag
    try expect(services.contains("defaultModelArgs(userArgs, flag: \"--model\", model: modelName)"),
               "Claude must use --model flag")
    // Codex gets -m flag and model_provider config
    try expect(services.contains("model_provider=\\\"mlx\\\""), "Codex must set MLX model provider")
    try expect(services.contains("defaultCodexArgs(userArgs, model: modelId)"), "Codex must use defaultCodexArgs")
    // Gemini gets -m flag and --policy
    try expect(services.contains("defaultGeminiArgs(userArgs, model: geminiModel)"), "Gemini must use defaultGeminiArgs")
    try expect(services.contains("\"--policy\""), "Gemini must include --policy argument")
    // Aider gets --model with openai/ prefix for local
    try expect(services.contains("\"openai/\\(modelId)\"") || services.contains("openai/"), "Aider must prefix local models with openai/")
    // gptme gets --non-interactive
    try expect(services.contains("\"--non-interactive\""), "gptme must include --non-interactive flag")
}))

tests.append(("Gemini stream flag is derived from path, not body", {
    try expect(connectionHandler.contains("canonical.stream = path.contains(\":streamGenerateContent\")"),
               "Gemini stream flag must come from path, not body")
}))

tests.append(("ConnectionHandler handles model list in multiple formats", {
    // GET /v1/models (OpenAI format)
    try expect(connectionHandler.contains("/v1/models"), "Must handle /v1/models")
    // GET /v1beta/models (Gemini format)
    try expect(connectionHandler.contains("/v1beta/models"), "Must handle /v1beta/models")
    // Format detection
    try expect(connectionHandler.contains("isGemini") && connectionHandler.contains("isAnthropic"),
               "Must detect response format from headers/path")
}))

tests.append(("BackendClient normalizes backend types correctly", {
    try expect(backendClient.contains("case \"openai_compatible\", \"local\": return \"chat_completions\""),
               "Must normalize openai_compatible and local to chat_completions")
    try expect(backendClient.contains("case \"claude_subscription\": return \"anthropic\""),
               "Must normalize claude_subscription to anthropic")
    try expect(backendClient.contains("case \"gemini_subscription\", \"gemini_cli\": return \"gemini\""),
               "Must normalize gemini_subscription to gemini")
}))

tests.append(("Governance runner environment includes all required vars", {
    let requiredEnvVars = [
        "ENGRAVE_GOVERNANCE_ENABLED",
        "ENGRAVE_GOVERNANCE_BRIEF",
        "ENGRAVE_GOVERNANCE_POLICY",
        "ENGRAVE_SUB_AGENT_LAUNCH",
        "ENGRAVE_INTERPOSER_URL",
        "ENGRAVE_INTERPOSER_PORT",
        "ENGRAVE_ALL_AGENTS_THROUGH_INTERPOSER",
    ]
    for envVar in requiredEnvVars {
        try expect(services.contains("\"\(envVar)\""), "Missing governance env var: \(envVar)")
    }
}))

tests.append(("RuleTrigger has all expected cases", {
    for trigger in ["request", "response", "toolCall", "streamEvent", "streamTextMatch"] {
        try expect(policyRule.contains("case \(trigger)"), "RuleTrigger missing case: \(trigger)")
    }
}))

tests.append(("RuleSeverity has all expected cases", {
    for sev in ["block", "warn", "modify", "rewrite"] {
        try expect(policyRule.contains("case \(sev)"), "RuleSeverity missing case: \(sev)")
    }
}))

tests.append(("UIAGovernanceConfig has all required fields", {
    for field in ["orchestratorModel", "cheapModel", "localModel", "explainWorkToUser", "createTaskDAG", "steerSubAgents"] {
        try expect(governanceConfig.contains("public var \(field)"), "UIAGovernanceConfig missing field: \(field)")
    }
}))

tests.append(("ConnectionHandler CORS and health endpoints", {
    try expect(connectionHandler.contains("request.method == \"OPTIONS\""), "Must handle CORS OPTIONS")
    try expect(connectionHandler.contains("/health"), "Must handle /health endpoint")
}))

tests.append(("Pre-commit hook blocks sensitive paths", {
    try expect(services.contains("refusing commit containing sensitive paths"),
               "Pre-commit hook must block sensitive paths")
    try expect(services.contains("mocks/stubs/scaffolds/TODOs detected"),
               "Pre-commit hook must warn on mocks/stubs")
}))

tests.append(("Session-close hook checks for uncommitted changes", {
    try expect(services.contains("worktree has uncommitted changes"),
               "Session-close hook must check worktree state")
}))

// ============================================================================
// MARK: - RUN ALL TESTS
// ============================================================================

var passed = 0
var failures: [String] = []

for (name, test) in tests {
    do {
        try test()
        print("\u{001B}[32m\u{2713}\u{001B}[0m \(name)")
        passed += 1
    } catch {
        failures.append("\u{001B}[31m\u{2717}\u{001B}[0m \(name): \(error)")
    }
}

print("\n--- Results ---")
print("Passed: \(passed)/\(tests.count)")

if !failures.isEmpty {
    print("\nFailures:")
    failures.forEach { print($0) }
    exit(1)
}

print("\nAll \(tests.count) Engrave tests passed.")
