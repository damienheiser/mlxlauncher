import SwiftUI

// MARK: - Settings Panel (Right Column)

struct SettingsPanel: View {
    @ObservedObject var state: AppState

    enum Category: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Appearance"
        case services = "Services"
        case governance = "Governance"
        case uia = "UIA"
        case keys = "Keys"
        case advanced = "Advanced"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            case .services: return "server.rack"
            case .governance: return "shield.checkered"
            case .uia: return "point.3.connected.trianglepath.dotted"
            case .keys: return "key"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    @State private var selectedCategory: Category = .general

    var body: some View {
        VStack(spacing: 0) {
            // Category picker
            categoryPicker
            Divider()
            // Detail area
            ScrollView {
                detailContent
                    .padding(14)
            }
            Divider()
            // Footer
            footer
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.cream)
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Category.allCases) { cat in
                    Button(action: { selectedCategory = cat }) {
                        Text(cat.rawValue)
                            .font(.thSmall)
                            .foregroundColor(selectedCategory == cat ? Theme.creamBold : Theme.creamDim)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selectedCategory == cat ? Theme.accent.opacity(0.2) : Theme.bgCard)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Detail Router

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory {
        case .general: generalSection
        case .appearance: appearanceSection
        case .services: servicesSection
        case .governance: governanceSection
        case .uia: uiaSection
        case .keys: keysSection
        case .advanced: advancedSection
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("General", subtitle: "Application-wide defaults")

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    settingsTextField(
                        label: "Default Working Directory",
                        text: Binding(
                            get: { state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_WORK_DIR"] ?? NSHomeDirectory() },
                            set: { state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_WORK_DIR"] = $0 }
                        ),
                        placeholder: NSHomeDirectory(),
                        mono: true
                    )

                    settingsToggle(
                        label: "Launch on Startup",
                        description: "Open Engrave when macOS starts",
                        isOn: Binding(
                            get: { state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_LAUNCH_ON_STARTUP"] == "1" },
                            set: { state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_LAUNCH_ON_STARTUP"] = $0 ? "1" : "0" }
                        )
                    )

                    settingsToggle(
                        label: "Auto-Start Services",
                        description: "Start MLX inference and interposer on launch",
                        isOn: Binding(
                            get: { state.appSettings.resolved.services.autoStartMLX && state.appSettings.resolved.services.autoStartInterposer },
                            set: {
                                state.appSettings.resolved.services.autoStartMLX = $0
                                state.appSettings.resolved.services.autoStartInterposer = $0
                            }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Appearance

    @State private var colorSchemeSelection: Int = 0  // 0=Auto, 1=Light, 2=Dark
    @State private var fontSizeMultiplier: Double = 1.0
    @State private var fontFamily: String = ""
    @State private var minimumFontSize: Int = 10

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Appearance", subtitle: "Theme, colors, and typography")

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    // Theme picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Theme").font(.thLabel).foregroundStyle(Theme.creamDim)
                        Picker("", selection: $state.appSettings.resolved.ui.theme) {
                            Text("Engrave Dark").tag("Engrave Dark")
                            Text("Engrave Light").tag("Engrave Light")
                            Text("Midnight").tag("midnight")
                            Text("Solarized").tag("solarized")
                        }
                        .labelsHidden()
                    }

                    Divider()

                    // Color scheme
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Color Scheme").font(.thLabel).foregroundStyle(Theme.creamDim)
                        Picker("", selection: $colorSchemeSelection) {
                            Text("Auto").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    // Font size multiplier
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Font Size Multiplier").font(.thLabel).foregroundStyle(Theme.creamDim)
                            Spacer()
                            Text(String(format: "%.2f", fontSizeMultiplier))
                                .font(.thMono).foregroundStyle(Theme.teal)
                        }
                        Slider(value: $fontSizeMultiplier, in: 0.8...1.5, step: 0.05)
                            .controlSize(.small)
                    }

                    // Font family
                    HStack {
                        Text("Font Family").font(.thLabel).foregroundStyle(Theme.creamDim)
                        Spacer()
                        Text(fontFamily.isEmpty ? "System Default" : fontFamily)
                            .font(.thBody).foregroundStyle(Theme.cream)
                    }

                    // Minimum font size
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Minimum Font Size").font(.thLabel).foregroundStyle(Theme.creamDim)
                            Spacer()
                            Text("\(minimumFontSize) pt").font(.thMono).foregroundStyle(Theme.teal)
                        }
                        Stepper("", value: $minimumFontSize, in: 8...24)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: - Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Services", subtitle: "MLX inference and interposer configuration")

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    settingsIntField(
                        label: "MLX Port",
                        value: $state.appSettings.resolved.services.mlxPort,
                        placeholder: "8080"
                    )

                    settingsIntField(
                        label: "Interposer Port",
                        value: $state.appSettings.resolved.services.interposerPort,
                        placeholder: "8888"
                    )

                    Divider()

                    settingsToggle(
                        label: "Auto-Start MLX Inference",
                        description: "Launch the MLX server when the app starts",
                        isOn: $state.appSettings.resolved.services.autoStartMLX
                    )

                    settingsToggle(
                        label: "Auto-Start Interposer",
                        description: "Launch the Engrave interposer when the app starts",
                        isOn: $state.appSettings.resolved.services.autoStartInterposer
                    )
                }
            }
        }
    }

    // MARK: - Governance

    @State private var governancePreset: String = "standard"
    @State private var governanceSandbox: String = "workspace"
    @State private var enableCircuitBreakers: Bool = true
    @State private var eventLogMaxEntries: Int = 200

    private var governanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Governance", subtitle: "Default policy engine settings")

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    // Default preset
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default Preset").font(.thLabel).foregroundStyle(Theme.creamDim)
                        Picker("", selection: $governancePreset) {
                            Text("Strict").tag("strict")
                            Text("Standard").tag("standard")
                            Text("Minimal").tag("minimal")
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    // Default sandbox level
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default Sandbox Level").font(.thLabel).foregroundStyle(Theme.creamDim)
                        Picker("", selection: $governanceSandbox) {
                            Text("Jailed").tag("jailed")
                            Text("Sandbox").tag("sandbox")
                            Text("Workspace").tag("workspace")
                            Text("Full").tag("full")
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    settingsToggle(
                        label: "Enable Circuit Breakers",
                        description: "Automatically trip breakers on repeated policy violations",
                        isOn: $enableCircuitBreakers
                    )

                    // Event log max entries
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Event Log Max Entries").font(.thLabel).foregroundStyle(Theme.creamDim)
                            Spacer()
                            Text("\(eventLogMaxEntries)").font(.thMono).foregroundStyle(Theme.teal)
                        }
                        Stepper("", value: $eventLogMaxEntries, in: 50...2000, step: 50)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: - UIA

    @State private var orchestratorModel: String = "selected"
    @State private var cheapModel: String = "cheap-cloud"
    @State private var localModel: String = "local-small"
    @State private var autoDecompose: Bool = true
    @State private var maxParallelAgents: Int = 4

    private var uiaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("UIA", subtitle: "User-facing orchestrator and agent routing")

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    settingsTextField(
                        label: "Orchestrator Model",
                        text: $orchestratorModel,
                        placeholder: "selected",
                        mono: true
                    )

                    settingsTextField(
                        label: "Cheap Model",
                        text: $cheapModel,
                        placeholder: "cheap-cloud",
                        mono: true
                    )

                    settingsTextField(
                        label: "Local Model",
                        text: $localModel,
                        placeholder: "local-small",
                        mono: true
                    )

                    Divider()

                    settingsToggle(
                        label: "Auto-Decompose Prompts",
                        description: "Automatically break complex prompts into task DAGs",
                        isOn: $autoDecompose
                    )

                    // Max parallel agents
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Parallel Agents").font(.thLabel).foregroundStyle(Theme.creamDim)
                            Spacer()
                            Text("\(maxParallelAgents)").font(.thMono).foregroundStyle(Theme.teal)
                        }
                        Stepper("", value: $maxParallelAgents, in: 1...16)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: - Keys

    @State private var anthropicKeyEnv: String = "ANTHROPIC_API_KEY"
    @State private var openaiKeyEnv: String = "OPENAI_API_KEY"
    @State private var googleKeyEnv: String = "GOOGLE_API_KEY"

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("API Keys", subtitle: "Environment variable names for provider keys")

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentBlue)
                        Text("Set actual keys as environment variables, not here.")
                            .font(.thSmall)
                            .foregroundStyle(Theme.accentBlue)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentBlue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Divider()

                    settingsTextField(
                        label: "Anthropic Key Env Var",
                        text: $anthropicKeyEnv,
                        placeholder: "ANTHROPIC_API_KEY",
                        mono: true
                    )

                    settingsTextField(
                        label: "OpenAI Key Env Var",
                        text: $openaiKeyEnv,
                        placeholder: "OPENAI_API_KEY",
                        mono: true
                    )

                    settingsTextField(
                        label: "Google Key Env Var",
                        text: $googleKeyEnv,
                        placeholder: "GOOGLE_API_KEY",
                        mono: true
                    )

                    // Show key presence indicators
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Detected Keys").font(.thLabel).foregroundStyle(Theme.creamDim)
                        keyPresenceRow("Anthropic", envVar: anthropicKeyEnv)
                        keyPresenceRow("OpenAI", envVar: openaiKeyEnv)
                        keyPresenceRow("Google", envVar: googleKeyEnv)
                    }
                }
            }
        }
    }

    private func keyPresenceRow(_ provider: String, envVar: String) -> some View {
        let present = ProcessInfo.processInfo.environment[envVar] != nil
        return HStack(spacing: 6) {
            Circle()
                .fill(present ? Theme.green : Theme.muted.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(provider).font(.thSmall)
            Spacer()
            Text(present ? "Set" : "Not set")
                .font(.thMonoSmall)
                .foregroundStyle(present ? Theme.green : Theme.creamDim)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Advanced", subtitle: "Debug, experiments, and limits")

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    settingsToggle(
                        label: "Debug Logging",
                        description: "Enable verbose debug output in service logs",
                        isOn: $state.appSettings.resolved.advanced.debugLogging
                    )

                    settingsToggle(
                        label: "Experimental Features",
                        description: "Enable features that are still in development",
                        isOn: Binding(
                            get: { state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_EXPERIMENTAL"] == "1" },
                            set: { state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_EXPERIMENTAL"] = $0 ? "1" : "0" }
                        )
                    )

                    Divider()

                    // Max request body MB
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Request Body (MB)").font(.thLabel).foregroundStyle(Theme.creamDim)
                            Spacer()
                            let maxMB = Int(state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_MAX_BODY_MB"] ?? "10") ?? 10
                            Text("\(maxMB) MB").font(.thMono).foregroundStyle(Theme.teal)
                        }
                        Stepper(
                            "",
                            value: Binding(
                                get: { Int(state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_MAX_BODY_MB"] ?? "10") ?? 10 },
                                set: { state.appSettings.resolved.advanced.customEnvironment["ENGRAVE_MAX_BODY_MB"] = String($0) }
                            ),
                            in: 1...100
                        )
                        .labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Reset to Defaults") {
                state.appSettings.resetToDefaults()
            }
            .font(.thSmall)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Theme.red)

            Button("Save") {
                state.appSettings.save()
            }
            .font(.thSmall)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Reusable Components

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.thTitle).foregroundStyle(Theme.creamBold)
            Text(subtitle).font(.thSmall).foregroundStyle(Theme.creamDim)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func settingsTextField(label: String, text: Binding<String>, placeholder: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.thLabel).foregroundStyle(Theme.creamDim)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(mono ? .thMono : .thBody)
        }
    }

    private func settingsIntField(label: String, value: Binding<Int>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.thLabel).foregroundStyle(Theme.creamDim)
            TextField(placeholder, text: Binding(
                get: { String(value.wrappedValue) },
                set: { if let v = Int($0) { value.wrappedValue = v } }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.thMono)
        }
    }

    private func settingsToggle(label: String, description: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.thLabel).foregroundStyle(Theme.cream)
                Text(description).font(.thSmall).foregroundStyle(Theme.creamDim)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
