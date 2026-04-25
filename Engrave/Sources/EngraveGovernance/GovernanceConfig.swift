import Foundation

/// Configuration for the governance engine.
public struct GovernanceConfig: Codable, Sendable {
    public var enabled: Bool
    public var sandboxLevel: SandboxLevel
    public var rules: [PolicyRule]
    public var blockedPaths: [String]
    public var blockedCommands: [String]
    public var requireApprovalForTools: [String]
    public var maxTokensBudget: UInt32?
    public var eventLogPath: String?
    public var featureToggles: [String: Bool]?
    public var contextBudgets: [String: ContextBudget]?
    public var uiaConfig: UIAGovernanceConfig?

    public init(
        enabled: Bool = false,
        sandboxLevel: SandboxLevel = .workspace,
        rules: [PolicyRule] = [],
        blockedPaths: [String] = [],
        blockedCommands: [String] = [],
        requireApprovalForTools: [String] = [],
        maxTokensBudget: UInt32? = nil,
        eventLogPath: String? = nil,
        featureToggles: [String: Bool]? = nil,
        contextBudgets: [String: ContextBudget]? = nil,
        uiaConfig: UIAGovernanceConfig? = nil
    ) {
        self.enabled = enabled
        self.sandboxLevel = sandboxLevel
        self.rules = rules
        self.blockedPaths = blockedPaths
        self.blockedCommands = blockedCommands
        self.requireApprovalForTools = requireApprovalForTools
        self.maxTokensBudget = maxTokensBudget
        self.eventLogPath = eventLogPath
        self.featureToggles = featureToggles
        self.contextBudgets = contextBudgets
        self.uiaConfig = uiaConfig
    }

    // MARK: - Presets

    /// Strict governance: blocks dangerous ops, warns on writes, full audit
    public static let strict = GovernanceConfig(
        enabled: true,
        sandboxLevel: .sandbox,
        rules: [
            .blockDangerousBash,
            .blockSensitivePaths,
            .warnExternalNetwork,
            .warnLargeTokenUsage,
        ] + PolicyRule.packagedGovernanceRules,
        blockedPaths: ["\\.env$", "credentials", "\\.ssh/", "\\.aws/", "secrets\\."],
        blockedCommands: ["rm\\s+-rf", "sudo\\s+", "chmod\\s+777"],
        requireApprovalForTools: ["Bash"],
        maxTokensBudget: 100_000,
        featureToggles: GovernanceFeature.defaults(enabled: true),
        contextBudgets: ContextBudget.defaults,
        uiaConfig: .default
    )

    /// Standard governance: balanced safety
    public static let standard = GovernanceConfig(
        enabled: true,
        sandboxLevel: .workspace,
        rules: [
            .blockDangerousBash,
            .blockSensitivePaths,
            .subAgentLaunchControl,
            .contextExhaustionRelay,
            .gitCommitHygiene,
            .testDrivenDevelopment,
            .noUndocumentedMocksOrStubs,
        ],
        blockedPaths: ["\\.env$", "\\.ssh/"],
        blockedCommands: ["rm\\s+-rf", "sudo\\s+"],
        featureToggles: GovernanceFeature.defaults(enabled: true),
        contextBudgets: ContextBudget.defaults,
        uiaConfig: .default
    )

    /// Minimal: monitoring only
    public static let minimal = GovernanceConfig(
        enabled: true,
        sandboxLevel: .full,
        rules: [.warnLargeTokenUsage],
        featureToggles: GovernanceFeature.defaults(enabled: false),
        contextBudgets: ContextBudget.defaults,
        uiaConfig: .default
    )

    public mutating func setFeature(_ feature: GovernanceFeature, enabled: Bool) {
        var toggles = featureToggles ?? GovernanceFeature.defaults(enabled: false)
        toggles[feature.rawValue] = enabled
        featureToggles = toggles
    }

    public func isFeatureEnabled(_ feature: GovernanceFeature) -> Bool {
        (featureToggles ?? [:])[feature.rawValue] ?? false
    }

    // MARK: - Persistence

    public static func load(from path: String) throws -> GovernanceConfig {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GovernanceConfig.self, from: data)
    }

    public func save(to path: String) throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

public enum GovernanceFeature: String, Codable, Sendable, CaseIterable, Identifiable {
    case subAgentLaunchControl
    case contextExhaustionRelay
    case humanInTheLoopInterception
    case uiaPromptDecomposition
    case workflowTaskDAG
    case gitCommitHygiene
    case gitWorktreeHygiene
    case testDrivenDevelopment
    case mockStubDocumentation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subAgentLaunchControl: return "Sub-Agent Launch Control"
        case .contextExhaustionRelay: return "Context Exhaustion Relay"
        case .humanInTheLoopInterception: return "Human In The Loop Interception"
        case .uiaPromptDecomposition: return "Engrave UIA Prompt Decomposition"
        case .workflowTaskDAG: return "Workflow Task DAG"
        case .gitCommitHygiene: return "Git Commit Hygiene"
        case .gitWorktreeHygiene: return "Git Worktree Hygiene"
        case .testDrivenDevelopment: return "Test Driven Development"
        case .mockStubDocumentation: return "No Undocumented Mocks Or Stubs"
        }
    }

    public var description: String {
        switch self {
        case .subAgentLaunchControl: return "Evaluate sub-agent spawn intent and steer to cheaper/local models when appropriate."
        case .contextExhaustionRelay: return "Budget context by agent type and trigger handoff compaction near exhaustion."
        case .humanInTheLoopInterception: return "Hold inbound/outbound messages for human review or rewrite."
        case .uiaPromptDecomposition: return "Have a user-facing orchestrator decompose prompts and explain work."
        case .workflowTaskDAG: return "Represent work as an editable DAG with dependencies and handoffs."
        case .gitCommitHygiene: return "One logical change per commit and one concern per branch."
        case .gitWorktreeHygiene: return "Require worktree reconciliation by end of session."
        case .testDrivenDevelopment: return "Require positive and negative tests for behavior changes."
        case .mockStubDocumentation: return "Warn on mocks, stubs, scaffolds, and TODO-only code unless documented."
        }
    }

    public static func defaults(enabled: Bool) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, enabled) })
    }
}

public struct ContextBudget: Codable, Sendable, Equatable {
    public var maxTokens: UInt32?
    public var thresholdPercent: Double
    public var relayModel: String
    public var handoffStyle: String

    public init(
        maxTokens: UInt32? = nil,
        thresholdPercent: Double = 0.85,
        relayModel: String = "local-small",
        handoffStyle: String = "detailed"
    ) {
        self.maxTokens = maxTokens
        self.thresholdPercent = thresholdPercent
        self.relayModel = relayModel
        self.handoffStyle = handoffStyle
    }

    public static let defaults: [String: ContextBudget] = [
        "default": ContextBudget(maxTokens: 100_000, thresholdPercent: 0.85),
        "explorer": ContextBudget(maxTokens: 48_000, thresholdPercent: 0.80),
        "worker": ContextBudget(maxTokens: 96_000, thresholdPercent: 0.85),
        "reviewer": ContextBudget(maxTokens: 64_000, thresholdPercent: 0.80),
        "uia": ContextBudget(maxTokens: 120_000, thresholdPercent: 0.75),
    ]
}

public struct UIAGovernanceConfig: Codable, Sendable, Equatable {
    public var orchestratorModel: String
    public var cheapModel: String
    public var localModel: String
    public var explainWorkToUser: Bool
    public var createTaskDAG: Bool
    public var steerSubAgents: Bool

    public init(
        orchestratorModel: String = "selected",
        cheapModel: String = "cheap-cloud",
        localModel: String = "local-small",
        explainWorkToUser: Bool = true,
        createTaskDAG: Bool = true,
        steerSubAgents: Bool = true
    ) {
        self.orchestratorModel = orchestratorModel
        self.cheapModel = cheapModel
        self.localModel = localModel
        self.explainWorkToUser = explainWorkToUser
        self.createTaskDAG = createTaskDAG
        self.steerSubAgents = steerSubAgents
    }

    public static let `default` = UIAGovernanceConfig()
}
