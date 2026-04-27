import SwiftUI
import EngraveGovernance

// MARK: - Governance Wizard

/// Multi-step governance rule builder for non-technical users.
struct GovernanceWizardView: View {
    let onSave: (PolicyRule) -> Void
    let onCancel: () -> Void

    @State private var step: Int = 0
    @State private var selectedTrigger: RuleTrigger = .request
    @State private var patterns: [String] = []
    @State private var patternInput: String = ""
    @State private var conditionMode: ConditionMode = .always
    @State private var customCondition: String = ""
    @State private var modelNamePlaceholder: String = ""
    @State private var selectedSeverity: RuleSeverity = .warn
    @State private var ruleName: String = ""
    @State private var ruleDescription: String = ""

    private let totalSteps = 5

    enum ConditionMode: String, CaseIterable {
        case always = "Always"
        case highTokens = "When token usage is high"
        case specificModel = "When using a specific model"
        case custom = "Custom..."
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().background(Theme.muted.opacity(0.3))

            // Step content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0: stepWhen
                    case 1: stepMatch
                    case 2: stepCondition
                    case 3: stepThen
                    case 4: stepReview
                    default: EmptyView()
                    }
                }
                .padding(20)
            }

            Divider().background(Theme.muted.opacity(0.3))

            // Navigation
            navigationBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 480, minHeight: 520)
        .background(Theme.bg)
        .foregroundStyle(Theme.cream)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { i in
                VStack(spacing: 4) {
                    Circle()
                        .fill(i <= step ? Theme.accent : Theme.muted.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(stepLabel(i))
                        .font(.thBadge)
                        .foregroundStyle(i == step ? Theme.creamBold : Theme.creamDim)
                }
                if i < totalSteps - 1 {
                    Rectangle()
                        .fill(i < step ? Theme.accent : Theme.muted.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .offset(y: -6)
                }
            }
        }
    }

    private func stepLabel(_ i: Int) -> String {
        switch i {
        case 0: return "When"
        case 1: return "Match"
        case 2: return "Condition"
        case 3: return "Then"
        case 4: return "Review"
        default: return ""
        }
    }

    // MARK: - Step 1: When

    private var stepWhen: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When should this rule trigger?")
                .font(.thTitle)
                .foregroundStyle(Theme.creamBold)

            triggerCard(
                icon: "arrow.down.circle",
                title: "When a request comes in",
                description: "Evaluate on incoming requests before they reach the model",
                trigger: .request
            )
            triggerCard(
                icon: "arrow.up.circle",
                title: "When a response is generated",
                description: "Evaluate completed model responses before they are returned",
                trigger: .response
            )
            triggerCard(
                icon: "wrench.and.screwdriver",
                title: "When a tool is called",
                description: "Evaluate tool use blocks (bash, file writes, etc.)",
                trigger: .toolCall
            )
            triggerCard(
                icon: "text.magnifyingglass",
                title: "When streaming text appears",
                description: "Evaluate streamed text as it arrives, matching patterns in real time",
                trigger: .streamTextMatch
            )
        }
    }

    private func triggerCard(icon: String, title: String, description: String, trigger: RuleTrigger) -> some View {
        let isSelected = selectedTrigger == trigger
        return Button {
            selectedTrigger = trigger
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.thHeader)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.muted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.thBody)
                        .foregroundStyle(isSelected ? Theme.creamBold : Theme.cream)
                    Text(description)
                        .font(.thSmall)
                        .foregroundStyle(Theme.creamDim)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.bgHover : Theme.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Match

    private var stepMatch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What patterns should match?")
                .font(.thTitle)
                .foregroundStyle(Theme.creamBold)

            Text("Leave empty to match all events of this type.")
                .font(.thSmall)
                .foregroundStyle(Theme.creamDim)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgCard))

            HStack {
                TextField("Regex pattern...", text: $patternInput)
                    .textFieldStyle(.plain)
                    .font(.thMono)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgCard))
                    .foregroundStyle(Theme.cream)

                Button("Add Pattern") {
                    let trimmed = patternInput.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        patterns.append(trimmed)
                        patternInput = ""
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
                .disabled(patternInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !patterns.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(patterns.enumerated()), id: \.offset) { index, pattern in
                        HStack {
                            Text(pattern)
                                .font(.thMono)
                                .foregroundStyle(Theme.accentLime)
                            Spacer()
                            Button {
                                patterns.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(Theme.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgCard))
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Condition

    private var stepCondition: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Under what condition?")
                .font(.thTitle)
                .foregroundStyle(Theme.creamBold)

            ForEach(ConditionMode.allCases, id: \.rawValue) { mode in
                let isSelected = conditionMode == mode
                Button {
                    conditionMode = mode
                } label: {
                    HStack {
                        Text(mode.rawValue)
                            .font(.thBody)
                            .foregroundStyle(isSelected ? Theme.creamBold : Theme.cream)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Theme.bgHover : Theme.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if conditionMode == .specificModel {
                TextField("Model name (e.g. claude-opus-4-6)", text: $modelNamePlaceholder)
                    .textFieldStyle(.plain)
                    .font(.thMono)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgCard))
                    .foregroundStyle(Theme.cream)
            }

            if conditionMode == .custom {
                TextField("Condition expression...", text: $customCondition)
                    .textFieldStyle(.plain)
                    .font(.thMono)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgCard))
                    .foregroundStyle(Theme.cream)
            }
        }
    }

    // MARK: - Step 4: Then

    private var stepThen: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What should happen?")
                .font(.thTitle)
                .foregroundStyle(Theme.creamBold)

            severityCard(title: "Block it", description: "Reject the request or event entirely", severity: .block, badgeColor: Theme.red)
            severityCard(title: "Warn about it", description: "Allow but log a warning for review", severity: .warn, badgeColor: Theme.yellow)
            severityCard(title: "Modify the request", description: "Allow with modifications applied before forwarding", severity: .modify, badgeColor: Theme.yellow.opacity(0.8))
            severityCard(title: "Rewrite the content", description: "Replace matched content with an alternative", severity: .rewrite, badgeColor: Theme.accentBlue)
        }
    }

    private func severityCard(title: String, description: String, severity: RuleSeverity, badgeColor: Color) -> some View {
        let isSelected = selectedSeverity == severity
        return Button {
            selectedSeverity = severity
        } label: {
            HStack(spacing: 12) {
                Text(severity.rawValue.uppercased())
                    .font(.thBadge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(badgeColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.thBody)
                        .foregroundStyle(isSelected ? Theme.creamBold : Theme.cream)
                    Text(description)
                        .font(.thSmall)
                        .foregroundStyle(Theme.creamDim)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.bgHover : Theme.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: Review

    private var stepReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name & Review")
                .font(.thTitle)
                .foregroundStyle(Theme.creamBold)

            VStack(alignment: .leading, spacing: 6) {
                Text("Rule Name")
                    .font(.thLabel)
                    .foregroundStyle(Theme.creamDim)
                TextField("My governance rule", text: $ruleName)
                    .textFieldStyle(.plain)
                    .font(.thBody)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgCard))
                    .foregroundStyle(Theme.cream)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description (optional)")
                    .font(.thLabel)
                    .foregroundStyle(Theme.creamDim)
                TextEditor(text: $ruleDescription)
                    .font(.thBody)
                    .foregroundStyle(Theme.cream)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 100)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgCard))
            }

            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Rule Preview")
                    .font(.thLabel)
                    .foregroundStyle(Theme.creamDim)

                VStack(alignment: .leading, spacing: 6) {
                    previewRow(label: "Trigger", value: selectedTrigger.rawValue)
                    previewRow(label: "Severity", value: selectedSeverity.rawValue)
                    if !patterns.isEmpty {
                        previewRow(label: "Patterns", value: patterns.joined(separator: ", "))
                    }
                    if let cond = resolvedCondition {
                        previewRow(label: "Condition", value: cond)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bgCard))
            }

            Button {
                onSave(buildRule())
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Create Rule")
                }
                .font(.thHeader)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(ruleName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(ruleName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.thLabel)
                .foregroundStyle(Theme.muted)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.thMono)
                .foregroundStyle(Theme.accentLime)
        }
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.creamDim)

            Spacer()

            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.cream)
            }

            if step < totalSteps - 1 {
                Button {
                    withAnimation { step += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var resolvedCondition: String? {
        switch conditionMode {
        case .always:
            return nil
        case .highTokens:
            return "tokens_used > tokens_budget * 0.8"
        case .specificModel:
            let name = modelNamePlaceholder.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "model == \"<model_name>\"" : "model == \"\(name)\""
        case .custom:
            let c = customCondition.trimmingCharacters(in: .whitespaces)
            return c.isEmpty ? nil : c
        }
    }

    private func buildRule() -> PolicyRule {
        PolicyRule(
            name: ruleName.trimmingCharacters(in: .whitespaces),
            trigger: selectedTrigger,
            severity: selectedSeverity,
            matchPatterns: patterns,
            condition: resolvedCondition,
            description: ruleDescription.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : ruleDescription.trimmingCharacters(in: .whitespaces)
        )
    }
}

// MARK: - Sandbox Detail View

/// Standalone view showing all four sandbox levels with full descriptions.
struct SandboxDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sandbox Levels")
                    .font(.thTitle)
                    .foregroundStyle(Theme.creamBold)
                    .padding(.bottom, 4)

                sandboxCard(
                    name: "Jailed",
                    badgeColor: Theme.red,
                    description: "All tool execution blocked. Agent can only respond with text. No file reads, no commands, no network.",
                    allowed: [],
                    blocked: ["File reads", "File writes", "Bash commands", "Network access", "All tools"],
                    useCases: [
                        "Pure Q&A conversations",
                        "Brainstorming sessions",
                        "When you want zero side effects",
                    ]
                )

                sandboxCard(
                    name: "Sandbox",
                    badgeColor: Theme.yellow,
                    description: "Read-only tools allowed (Read, Glob, Grep). No writes, no commands. The agent can explore but cannot change anything.",
                    allowed: ["Read files", "Glob search", "Grep search"],
                    blocked: ["File writes", "Bash commands", "Network access"],
                    useCases: [
                        "Code review and analysis",
                        "Exploring unfamiliar codebases",
                        "Security audits",
                    ]
                )

                sandboxCard(
                    name: "Workspace",
                    badgeColor: Theme.yellow.opacity(0.7),
                    description: "Read-write within the project directory. Bash restricted to safe commands. The agent can edit project files but cannot escape the working directory.",
                    allowed: ["Read files", "Write files (project only)", "Safe bash commands", "Glob/Grep"],
                    blocked: ["Commands outside project", "Unrestricted bash", "System-level access"],
                    useCases: [
                        "Day-to-day coding tasks",
                        "Refactoring within a project",
                        "Running tests and builds",
                    ]
                )

                sandboxCard(
                    name: "Full",
                    badgeColor: Theme.green,
                    description: "Unrestricted access. All tools available. The agent operates with the same permissions as the user.",
                    allowed: ["All file operations", "Unrestricted bash", "Network access", "All tools"],
                    blocked: [],
                    useCases: [
                        "Infrastructure automation",
                        "Cross-repo operations",
                        "System administration tasks",
                    ]
                )
            }
            .padding(20)
        }
        .frame(minWidth: 420, minHeight: 480)
        .background(Theme.bg)
        .foregroundStyle(Theme.cream)
    }

    private func sandboxCard(
        name: String,
        badgeColor: Color,
        description: String,
        allowed: [String],
        blocked: [String],
        useCases: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Text(name.uppercased())
                    .font(.thBadge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(badgeColor))

                Text(name)
                    .font(.thHeader)
                    .foregroundStyle(Theme.creamBold)
            }

            // Description
            Text(description)
                .font(.thBody)
                .foregroundStyle(Theme.creamDim)
                .fixedSize(horizontal: false, vertical: true)

            // Allowed
            if !allowed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allowed")
                        .font(.thLabel)
                        .foregroundStyle(Theme.green)
                    ForEach(allowed, id: \.self) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.thBadge)
                                .foregroundStyle(Theme.green)
                            Text(item)
                                .font(.thSmall)
                                .foregroundStyle(Theme.cream)
                        }
                    }
                }
            }

            // Blocked
            if !blocked.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocked")
                        .font(.thLabel)
                        .foregroundStyle(Theme.red)
                    ForEach(blocked, id: \.self) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.thBadge)
                                .foregroundStyle(Theme.red)
                            Text(item)
                                .font(.thSmall)
                                .foregroundStyle(Theme.cream)
                        }
                    }
                }
            }

            // Use cases
            VStack(alignment: .leading, spacing: 4) {
                Text("Use Cases")
                    .font(.thLabel)
                    .foregroundStyle(Theme.teal)
                ForEach(useCases, id: \.self) { uc in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.thBadge)
                            .foregroundStyle(Theme.teal)
                        Text(uc)
                            .font(.thSmall)
                            .foregroundStyle(Theme.creamDim)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bgCard))
    }
}
