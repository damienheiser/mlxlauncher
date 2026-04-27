import SwiftUI
import EngraveGovernance

// MARK: - Rule Editor View

struct RuleEditorView: View {
    @Binding var rule: PolicyRule
    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var showTemplatePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(rule.name.isEmpty ? "New Rule" : "Edit Rule")
                    .font(.thTitle).foregroundStyle(Theme.creamBold)
                Spacer()
                Button("Templates") { showTemplatePicker = true }
                    .font(.thSmall).buttonStyle(.bordered).controlSize(.small)
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Name + Description
                    nameSection

                    // 2. Enabled toggle
                    enabledSection

                    // 3. Trigger picker
                    triggerSection

                    // 4. Severity picker
                    severitySection

                    // 5. Regex patterns + test
                    regexSection

                    // 6. Condition
                    conditionSection

                    // 7. Action (conditional on severity)
                    actionSection
                }
                .padding(14)
            }

            Divider()

            // Save / Cancel
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { onCancel() }
                    .font(.thSmall).buttonStyle(.bordered).controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Save Rule") { onSave() }
                    .font(.thSmall).buttonStyle(.borderedProminent).controlSize(.small)
                    .tint(Theme.accent)
                    .disabled(rule.name.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 440, minHeight: 520)
        .background(Theme.bg)
        .foregroundStyle(Theme.cream)
        .sheet(isPresented: $showTemplatePicker) {
            RuleTemplatePickerView { template in
                rule = template
                showTemplatePicker = false
            } onCancel: {
                showTemplatePicker = false
            }
        }
    }

    // MARK: - Name + Description

    private var nameSection: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.thLabel).foregroundStyle(Theme.creamDim)
                    TextField("Rule name", text: $rule.name)
                        .textFieldStyle(.roundedBorder).font(.thBody)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.thLabel).foregroundStyle(Theme.creamDim)
                    TextField("What this rule does", text: Binding(
                        get: { rule.description ?? "" },
                        set: { rule.description = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder).font(.thBody)
                }
            }
        }
    }

    // MARK: - Enabled

    private var enabledSection: some View {
        editorCard {
            Toggle(isOn: $rule.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enabled").font(.thLabel).foregroundStyle(Theme.cream)
                    Text("Rule is evaluated when enabled")
                        .font(.thSmall).foregroundStyle(Theme.creamDim)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Trigger

    private var triggerSection: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Trigger").font(.thLabel).foregroundStyle(Theme.creamDim)
                Picker("", selection: $rule.trigger) {
                    Text("Request").tag(RuleTrigger.request)
                    Text("Response").tag(RuleTrigger.response)
                    Text("Tool Call").tag(RuleTrigger.toolCall)
                    Text("Stream Event").tag(RuleTrigger.streamEvent)
                    Text("Stream Text").tag(RuleTrigger.streamTextMatch)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(triggerDescription(rule.trigger))
                    .font(.thSmall).foregroundStyle(Theme.creamDim)
            }
        }
    }

    private func triggerDescription(_ trigger: RuleTrigger) -> String {
        switch trigger {
        case .request: return "Evaluate on incoming API requests"
        case .response: return "Evaluate on completed API responses"
        case .toolCall: return "Evaluate on tool use / function calls"
        case .streamEvent: return "Evaluate on each streaming event"
        case .streamTextMatch: return "Evaluate when streamed text matches a pattern"
        }
    }

    // MARK: - Severity

    private var severitySection: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Severity").font(.thLabel).foregroundStyle(Theme.creamDim)

                HStack(spacing: 4) {
                    ForEach(RuleSeverity.allCases, id: \.self) { sev in
                        Button {
                            rule.severity = sev
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(severityColor(sev))
                                    .frame(width: 6, height: 6)
                                Text(sev.rawValue.capitalized)
                                    .font(.thSmall)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(rule.severity == sev ? Theme.creamBold : Theme.creamDim)
                            .background(rule.severity == sev ? severityColor(sev).opacity(0.25) : Theme.bgHover.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(severityDescription(rule.severity))
                    .font(.thSmall).foregroundStyle(Theme.creamDim)
            }
        }
    }

    private func severityColor(_ severity: RuleSeverity) -> Color {
        switch severity {
        case .block: return Theme.red
        case .warn: return Theme.yellow
        case .modify: return Color.orange
        case .rewrite: return Theme.accentBlue
        }
    }

    private func severityDescription(_ severity: RuleSeverity) -> String {
        switch severity {
        case .block: return "Reject the request or event entirely"
        case .warn: return "Allow but log a warning for audit"
        case .modify: return "Allow with field modifications applied"
        case .rewrite: return "Rewrite the content before forwarding"
        }
    }

    // MARK: - Regex Patterns

    private var regexSection: some View {
        editorCard {
            RegexTestView(patterns: $rule.matchPatterns)
        }
    }

    // MARK: - Condition

    private var conditionSection: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Condition Expression").font(.thLabel).foregroundStyle(Theme.creamDim)
                TextField("e.g. tokens_used > tokens_budget * 0.8", text: Binding(
                    get: { rule.condition ?? "" },
                    set: { rule.condition = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.thMono)

                Text("Available variables: tokens_used, tokens_budget, request_count, sandbox_level, model, agent_id")
                    .font(.thSmall).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionSection: some View {
        if rule.severity == .modify {
            editorCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modification").font(.thLabel).foregroundStyle(Theme.creamDim)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Field to modify").font(.thSmall).foregroundStyle(Theme.muted)
                        TextField("e.g. max_tokens, temperature", text: Binding(
                            get: { rule.modification ?? "" },
                            set: { rule.modification = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder).font(.thMono)
                    }
                }
            }
        } else if rule.severity == .rewrite {
            editorCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Replacement Content").font(.thLabel).foregroundStyle(Theme.creamDim)

                    TextEditor(text: Binding(
                        get: { rule.replacement ?? "" },
                        set: { rule.replacement = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.thMono)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(minHeight: 80, maxHeight: 160)

                    Text("Content that will replace the matched text")
                        .font(.thSmall).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: - Card Helper

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Regex Test View

struct RegexTestView: View {
    @Binding var patterns: [String]
    @State private var testInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Match Patterns").font(.thLabel).foregroundStyle(Theme.creamDim)
                Spacer()
                Button {
                    patterns.append("")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 10))
                        Text("Add").font(.thSmall)
                    }
                }
                .buttonStyle(.bordered).controlSize(.mini)
            }

            // Pattern rows
            if patterns.isEmpty {
                Text("No patterns. Click Add to create one.")
                    .font(.thSmall).foregroundStyle(Theme.muted)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(patterns.enumerated()), id: \.offset) { index, _ in
                    patternRow(index: index)
                }
            }

            Divider()

            // Test input
            VStack(alignment: .leading, spacing: 4) {
                Text("Test Input").font(.thLabel).foregroundStyle(Theme.creamDim)
                TextEditor(text: $testInput)
                    .font(.thMono)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(minHeight: 50, maxHeight: 100)
            }

            // Match results
            if !testInput.isEmpty && !patterns.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Results").font(.thLabel).foregroundStyle(Theme.creamDim)

                    let results = evaluatePatterns()
                    let totalMatches = results.reduce(0) { $0 + $1.count }
                    Text("\(totalMatches) total match\(totalMatches == 1 ? "" : "es")")
                        .font(.thSmall)
                        .foregroundStyle(totalMatches > 0 ? Theme.green : Theme.creamDim)

                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        if index < patterns.count {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(result.count > 0 ? Theme.green : Theme.red.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(patterns[index])
                                    .font(.thMonoSmall)
                                    .lineLimit(1)
                                Spacer()
                                Text(result.count > 0 ? "\(result.count) match\(result.count == 1 ? "" : "es")" : "no match")
                                    .font(.thSmall)
                                    .foregroundStyle(result.count > 0 ? Theme.green : Theme.creamDim)
                            }
                        }
                    }
                }
            }
        }
    }

    private func patternRow(index: Int) -> some View {
        HStack(spacing: 6) {
            // Pattern status indicator
            if !testInput.isEmpty {
                let matched = matchCount(pattern: patterns[index], input: testInput) > 0
                Circle()
                    .fill(matched ? Theme.green : Theme.red.opacity(0.4))
                    .frame(width: 6, height: 6)
            }

            TextField("regex pattern", text: Binding(
                get: { index < patterns.count ? patterns[index] : "" },
                set: { if index < patterns.count { patterns[index] = $0 } }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.thMono)

            Button {
                if index < patterns.count {
                    patterns.remove(at: index)
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
    }

    private func evaluatePatterns() -> [(count: Int, pattern: String)] {
        patterns.map { pattern in
            (count: matchCount(pattern: pattern, input: testInput), pattern: pattern)
        }
    }

    private func matchCount(pattern: String, input: String) -> Int {
        guard !pattern.isEmpty else { return 0 }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(input.startIndex..., in: input)
        return regex.numberOfMatches(in: input, range: range)
    }
}

// MARK: - Rule Template Picker View

struct RuleTemplatePickerView: View {
    var onSelect: (PolicyRule) -> Void
    var onCancel: () -> Void

    private let templates: [(name: String, rule: PolicyRule)] = [
        ("Block Dangerous Bash", .blockDangerousBash),
        ("Block Sensitive Paths", .blockSensitivePaths),
        ("Warn External Network", .warnExternalNetwork),
        ("Warn Large Token Usage", .warnLargeTokenUsage),
        ("Sub-Agent Launch Control", .subAgentLaunchControl),
        ("Context Exhaustion Relay", .contextExhaustionRelay),
        ("Human In The Loop", .humanInTheLoopInterception),
        ("Workflow Task DAG", .workflowTaskDAG),
        ("Git Commit Hygiene", .gitCommitHygiene),
        ("Git Worktree Hygiene", .gitWorktreeHygiene),
        ("Test Driven Development", .testDrivenDevelopment),
        ("No Undocumented Mocks", .noUndocumentedMocksOrStubs),
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rule Templates").font(.thTitle).foregroundStyle(Theme.creamBold)
                    Text("Select a template to pre-fill the rule editor")
                        .font(.thSmall).foregroundStyle(Theme.creamDim)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .font(.thSmall).buttonStyle(.bordered).controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(templates.enumerated()), id: \.offset) { _, template in
                        templateCard(template.name, rule: template.rule)
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .background(Theme.bg)
        .foregroundStyle(Theme.cream)
    }

    private func templateCard(_ name: String, rule: PolicyRule) -> some View {
        Button {
            // Create a new copy with a fresh UUID
            var newRule = rule
            newRule.id = UUID()
            onSelect(newRule)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    severityBadge(rule.severity)
                    Spacer()
                    triggerBadge(rule.trigger)
                }

                Text(name)
                    .font(.thLabel)
                    .foregroundStyle(Theme.creamBold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let desc = rule.description {
                    Text(desc)
                        .font(.thSmall)
                        .foregroundStyle(Theme.creamDim)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                if !rule.matchPatterns.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.muted)
                        Text("\(rule.matchPatterns.count) pattern\(rule.matchPatterns.count == 1 ? "" : "s")")
                            .font(.thSmall)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.bgHover, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func severityBadge(_ severity: RuleSeverity) -> some View {
        let color: Color = switch severity {
        case .block: Theme.red
        case .warn: Theme.yellow
        case .modify: Color.orange
        case .rewrite: Theme.accentBlue
        }
        return Text(severity.rawValue.uppercased())
            .font(.thBadge)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func triggerBadge(_ trigger: RuleTrigger) -> some View {
        Text(trigger.rawValue)
            .font(.thBadge)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.muted)
            .background(Theme.bgHover.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
