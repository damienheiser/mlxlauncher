import Foundation

// MARK: - Rule Trigger

/// What event type triggers a rule evaluation.
public enum RuleTrigger: String, Codable, Sendable, CaseIterable {
    case request            // Evaluate on incoming request
    case response           // Evaluate on completed response
    case toolCall           // Evaluate on tool use blocks
    case streamEvent        // Evaluate on each stream event
    case streamTextMatch    // Evaluate when streamed text matches pattern
}

// MARK: - Rule Severity

/// What action to take when a rule matches.
public enum RuleSeverity: String, Codable, Sendable, CaseIterable {
    case block   // Reject the request/event
    case warn    // Allow but log a warning
    case modify  // Allow with modifications
    case rewrite // Rewrite content
}

// MARK: - Policy Rule

/// A declarative governance rule.
public struct PolicyRule: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var trigger: RuleTrigger
    public var severity: RuleSeverity
    public var matchPatterns: [String]
    public var condition: String?
    public var modification: String?
    public var replacement: String?
    public var description: String?

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        trigger: RuleTrigger = .request,
        severity: RuleSeverity = .warn,
        matchPatterns: [String] = [],
        condition: String? = nil,
        modification: String? = nil,
        replacement: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.trigger = trigger
        self.severity = severity
        self.matchPatterns = matchPatterns
        self.condition = condition
        self.modification = modification
        self.replacement = replacement
        self.description = description
    }

    // MARK: - Built-in Rule Templates

    public static let blockDangerousBash = PolicyRule(
        name: "Block dangerous bash commands",
        trigger: .toolCall,
        severity: .block,
        matchPatterns: ["rm\\s+-rf", "sudo\\s+", "chmod\\s+777", "mkfs", "dd\\s+if=", "> /dev/"],
        description: "Blocks bash commands that could damage the system"
    )

    public static let warnLargeTokenUsage = PolicyRule(
        name: "Warn on high token usage",
        trigger: .request,
        severity: .warn,
        condition: "tokens_used > tokens_budget * 0.8",
        description: "Warns when token usage exceeds 80% of budget"
    )

    public static let blockSensitivePaths = PolicyRule(
        name: "Block access to sensitive paths",
        trigger: .toolCall,
        severity: .block,
        matchPatterns: ["\\.env$", "credentials", "\\.ssh/", "\\.aws/", "secrets\\."],
        description: "Blocks tool calls that access sensitive files"
    )

    public static let warnExternalNetwork = PolicyRule(
        name: "Warn on external network access",
        trigger: .toolCall,
        severity: .warn,
        matchPatterns: ["curl\\s+", "wget\\s+", "http://[^l]", "https://"],
        description: "Warns when tools attempt external network access"
    )

    public static let subAgentLaunchControl = PolicyRule(
        name: "Sub-Agent Launch Control",
        trigger: .request,
        severity: .warn,
        matchPatterns: [
            "spawn_agent",
            "sub[- ]?agent",
            "delegate .*agent",
            "parallel .*agent",
            "launch .*agent",
        ],
        description: "Intercepts sub-agent spawning intents so governance can evaluate task size, model choice, and redirection to cheaper/local runners."
    )

    public static let contextExhaustionRelay = PolicyRule(
        name: "Context Exhaustion Relay",
        trigger: .request,
        severity: .warn,
        matchPatterns: [
            "context window",
            "token budget",
            "compact",
            "handoff",
            "replacement agent",
        ],
        condition: "tokens_used > tokens_budget * 0.8",
        description: "Triggers context compaction/handoff planning when token budget thresholds are approached."
    )

    public static let humanInTheLoopInterception = PolicyRule(
        name: "Human In The Loop Interception",
        trigger: .request,
        severity: .warn,
        matchPatterns: [
            "send message",
            "respond to user",
            "execute without approval",
            "apply changes",
            "delete",
            "force push",
        ],
        description: "Flags inbound/outbound message or action boundaries where a human may hold, rewrite, approve, or modify content."
    )

    public static let workflowTaskDAG = PolicyRule(
        name: "UIA Prompt Decomposition And Task DAG",
        trigger: .request,
        severity: .warn,
        matchPatterns: [
            "multi[- ]?step",
            "decompose",
            "task dag",
            "workflow",
            "dependencies",
            "parallel",
        ],
        description: "Encourages UIA-style prompt decomposition into an editable workflow DAG with dependencies, handoffs, and verification nodes."
    )

    public static let gitCommitHygiene = PolicyRule(
        name: "Git Commit Hygiene",
        trigger: .toolCall,
        severity: .warn,
        matchPatterns: [
            "git\\s+commit",
            "git\\s+add\\s+\\.",
            "git\\s+merge",
            "git\\s+rebase",
        ],
        description: "Enforces one logical change per commit and one concern per branch."
    )

    public static let gitWorktreeHygiene = PolicyRule(
        name: "Git Worktree Hygiene",
        trigger: .toolCall,
        severity: .warn,
        matchPatterns: [
            "git\\s+worktree",
            "git\\s+status",
            "end of session",
            "uncommitted changes",
        ],
        description: "Warns when session/worktree changes need reconciliation before handoff or close."
    )

    public static let testDrivenDevelopment = PolicyRule(
        name: "Test Driven Development",
        trigger: .request,
        severity: .warn,
        matchPatterns: [
            "implement",
            "fix",
            "feature",
            "bug",
            "refactor",
        ],
        description: "Requires positive and negative tests for behavior-changing work."
    )

    public static let noUndocumentedMocksOrStubs = PolicyRule(
        name: "No Undocumented Mocks Or Stubs",
        trigger: .response,
        severity: .warn,
        matchPatterns: [
            "mock",
            "stub",
            "scaffold",
            "placeholder",
            "TODO",
            "fake",
        ],
        description: "Warns when mocked, stubbed, scaffolded, placeholder, or TODO-only code appears without explicit documentation."
    )

    public static var packagedGovernanceRules: [PolicyRule] {
        [
            .subAgentLaunchControl,
            .contextExhaustionRelay,
            .humanInTheLoopInterception,
            .workflowTaskDAG,
            .gitCommitHygiene,
            .gitWorktreeHygiene,
            .testDrivenDevelopment,
            .noUndocumentedMocksOrStubs,
        ]
    }
}
