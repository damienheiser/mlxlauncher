import Foundation

// MARK: - Governance Types (stub for future implementation)

/// Governance policy decision
public enum PolicyDecision: Sendable {
    case allow
    case warn(reason: String)
    case block(reason: String)
}

/// Sandbox security level
public enum SandboxLevel: String, Codable, Sendable, Comparable {
    case jailed
    case sandbox
    case workspace
    case full

    public static func < (lhs: SandboxLevel, rhs: SandboxLevel) -> Bool {
        let order: [SandboxLevel] = [.jailed, .sandbox, .workspace, .full]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Governance engine placeholder — full implementation deferred
public actor GovernanceEngine {
    private let enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    /// Evaluate a request against governance rules
    public func evaluateRequest(_ request: CanonicalRequest) -> PolicyDecision {
        guard enabled else { return .allow }
        return .allow
    }

    /// Evaluate a stream event against governance rules
    public func evaluateStreamEvent(_ event: CanonicalStreamEvent) -> PolicyDecision {
        guard enabled else { return .allow }
        return .allow
    }
}
