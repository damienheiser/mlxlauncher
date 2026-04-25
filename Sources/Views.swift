import SwiftUI
import WebKit
import EngraveGovernance

// MARK: - Synthaer Theme

/// Synthaer.ai color scheme: dark indigo background, cream text
enum Theme {
    // Core
    static let bg           = Color(red: 22/255, green: 18/255, blue: 40/255)     // #161228
    static let bgCard       = Color(red: 30/255, green: 25/255, blue: 55/255)     // slightly lighter card bg
    static let bgHover      = Color(red: 40/255, green: 35/255, blue: 70/255)     // hover/selection bg
    static let cream        = Color(red: 243/255, green: 235/255, blue: 221/255)  // #F3EBDD
    static let creamBold    = Color(red: 255/255, green: 243/255, blue: 224/255)  // #FFF3E0
    static let creamDim     = Color(red: 217/255, green: 208/255, blue: 198/255)  // #D9D0C6

    // Accents
    static let accent       = Color(red: 255/255, green: 79/255, blue: 216/255)   // #FF4FD8 hot pink
    static let accentLime   = Color(red: 166/255, green: 213/255, blue: 106/255)  // #A6D56A
    static let accentBlue   = Color(red: 134/255, green: 167/255, blue: 255/255)  // #86A7FF
    static let accentMagenta = Color(red: 201/255, green: 137/255, blue: 255/255) // #C989FF

    // ANSI-derived
    static let muted        = Color(red: 106/255, green: 100/255, blue: 139/255)  // #6A648B bright black
    static let mutedPurple  = Color(red: 75/255, green: 69/255, blue: 103/255)    // #4B4567
    static let teal         = Color(red: 112/255, green: 215/255, blue: 208/255)  // #70D7D0
    static let green        = Color(red: 126/255, green: 142/255, blue: 107/255)  // #7E8E6B
    static let red          = Color(red: 224/255, green: 138/255, blue: 168/255)  // #E08AA8
    static let yellow       = Color(red: 232/255, green: 199/255, blue: 111/255)  // #E8C76F
    static let blue         = Color(red: 112/255, green: 124/255, blue: 176/255)  // #707CB0
}

/// Accessibility-aware font helper. Minimum 12pt, respects system Dynamic Type scaling.
extension Font {
    /// Title text — 16pt base, semibold
    static let thTitle = Font.system(size: max(16, NSFont.systemFontSize), weight: .semibold)
    /// Section header — 14pt base, semibold
    static let thHeader = Font.system(size: max(14, NSFont.systemFontSize), weight: .semibold)
    /// Body text — 13pt base
    static let thBody = Font.system(size: max(13, NSFont.systemFontSize))
    /// Body text, medium weight
    static let thBodyMedium = Font.system(size: max(13, NSFont.systemFontSize), weight: .medium)
    /// Label text — 12pt base, medium
    static let thLabel = Font.system(size: max(12, NSFont.smallSystemFontSize), weight: .medium)
    /// Small label — 12pt base
    static let thSmall = Font.system(size: max(12, NSFont.smallSystemFontSize))
    /// Monospaced body
    static let thMono = Font.system(size: max(12, NSFont.smallSystemFontSize), design: .monospaced)
    /// Monospaced small — 12pt base
    static let thMonoSmall = Font.system(size: max(12, NSFont.smallSystemFontSize), design: .monospaced)
    /// Badge text — 10pt, bold (only for tiny status badges)
    static let thBadge = Font.system(size: max(10, NSFont.smallSystemFontSize - 1), weight: .bold)
    /// Icon size
    static let thIcon = Font.system(size: max(13, NSFont.systemFontSize))
}

// MARK: - Main 3-Column Layout

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var rightPanel: RightPanel = .parameters
    @State private var webServerStarted = false
    @State private var webServer: WebServer?
    @State private var showModelChangeWarning = false

    enum RightPanel: String, CaseIterable, Identifiable {
        case parameters = "Parameters"
        case prompts = "Prompts"
        case runner = "Runner Args"
        case server = "Server"
        case interposer = "Interposer"
        case modelStore = "Model Store"
        case governance = "Governance"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .parameters: return "slider.horizontal.3"
            case .prompts: return "doc.text"
            case .runner: return "terminal"
            case .server: return "server.rack"
            case .interposer: return "arrow.triangle.swap"
            case .modelStore: return "square.and.arrow.down"
            case .governance: return "shield.checkered"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1: Sidebar (nav + runner + launch)
            sidebarColumn.frame(width: 200)
            Divider()
            // Col 2: Model list (always visible)
            modelColumn.frame(minWidth: 320, idealWidth: 360)
            Divider()
            // Col 3: Right panel (context-dependent)
            rightPanelView.frame(minWidth: 380, idealWidth: 440)
        }
        .frame(minWidth: 1000, minHeight: 620)
        .background(Theme.bg)
        .foregroundStyle(Theme.cream)
        .onAppear {
            state.bootstrap()
            if !webServerStarted {
                let ws = WebServer(port: 8421, appState: state)
                ws.start()
                webServer = ws
                webServerStarted = true
            }
        }
    }

    // MARK: - Col 1: Sidebar

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            // Logo
            HStack(spacing: 8) {
                Text("🐱").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 1) {
                    Text("MLX Launcher").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.creamBold)
                    serverBadge
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            Divider().padding(.horizontal, 12)

            // Right panel selector
            VStack(spacing: 1) {
                ForEach(RightPanel.allCases) { panel in
                    Button { rightPanel = panel } label: {
                        HStack(spacing: 8) {
                            Image(systemName: panel.icon).font(.system(size: 13)).frame(width: 18)
                                .foregroundStyle(rightPanel == panel ? Theme.creamBold : Theme.creamDim)
                            Text(panel.rawValue).font(.system(size: 13))
                                .foregroundStyle(rightPanel == panel ? Theme.creamBold : Theme.cream)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(rightPanel == panel ? Theme.accentMagenta.opacity(0.35) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)

            Divider().padding(.horizontal, 12)

            // Runner selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Runner").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.creamDim)
                    .padding(.horizontal, 4)
                ForEach(allRunners) { runner in
                    RunnerRow(runner: runner, isSelected: state.selectedRunner == runner)
                        .onTapGesture { if runner.isInstalled { state.selectedRunner = runner } }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            // Cloud auth mode
            if state.selectedModel?.isCloud == true {
                Divider().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud Auth").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.creamDim)
                        .padding(.horizontal, 4)
                    Picker("", selection: $state.cloudAuthMode) {
                        ForEach(CloudAuthMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    Text(state.cloudAuthMode == .cliSubscription
                        ? "Uses runner's native login (Max/Pro)"
                        : "Routes through Engrave with API key")
                        .font(.system(size: 11)).foregroundStyle(Theme.creamDim)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }

            Spacer()

            Divider().padding(.horizontal, 12)

            // Selected model + Launch
            VStack(spacing: 8) {
                if let m = state.selectedModel {
                    Text(m.shortName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.creamDim).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    if state.selectedModelDiffersFromServer {
                        showModelChangeWarning = true
                    } else {
                        state.launch()
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill").font(.system(size: 12))
                        Text("Launch").font(.system(size: 12, weight: .semibold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(state.selectedModel == nil || !state.selectedRunner.isInstalled)
                .keyboardShortcut(.return, modifiers: .command)
                .alert("Model Change", isPresented: $showModelChangeWarning) {
                    Button("Relaunch MLX Server") {
                        state.relaunchServerWithSelectedModel()
                        // Delay launch to let server start
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { state.launch() }
                    }
                    Button("Launch Anyway", role: .destructive) { state.launch() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The selected model differs from the running MLX server. Relaunching the server will require any existing runners to be restarted to use the updated model.")
                }
            }
            .padding(12)
        }
        .background(Theme.bg)
    }

    private var serverBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(state.serverStatus.state == .running ? .green :
                          state.serverStatus.state == .starting ? .orange : .secondary.opacity(0.3))
                .frame(width: 5, height: 5)
            Text(state.serverStatus.state == .running ? "Running" :
                 state.serverStatus.state == .starting ? "Starting" : "Idle")
                .font(.system(size: 12)).foregroundStyle(Theme.creamDim)
        }
    }

    // MARK: - Col 2: Model List (always visible)

    private var modelColumn: some View {
        ModelListView(state: state)
    }

    // MARK: - Col 3: Right Panel

    @ViewBuilder
    private var rightPanelView: some View {
        switch rightPanel {
        case .parameters: ParametersPanel(state: state)
        case .prompts: PromptsPanel(state: state)
        case .runner: RunnerArgsPanel(state: state)
        case .server: ServerPanel(state: state)
        case .interposer: InterposerPanel(state: state)
        case .modelStore: ModelStorePanel(state: state)
        case .governance: GovernancePanel(state: state)
        }
    }
}

// MARK: - Runner Row

struct RunnerRow: View {
    let runner: Runner; let isSelected: Bool
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: runner.icon).font(.system(size: 13)).frame(width: 14)
            Text(runner.name).font(.system(size: 13))
            Spacer()
            if runner.isInstalled && isSelected {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.teal)
            }
            if !runner.isInstalled {
                Text("n/a").font(.system(size: 12)).foregroundStyle(Theme.creamDim)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isSelected ? Theme.teal.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(runner.isInstalled ? 1.0 : 0.3)
    }
}

// MARK: - Model List (Column 2)

struct ModelListView: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    @State private var sourceFilter: ModelSourceFilter = .all

    enum ModelSourceFilter: String, CaseIterable { case all = "All", local = "Local", cloud = "Cloud" }

    var filtered: [MLXModel] {
        state.allModels.filter { m in
            let s = search.isEmpty || m.id.localizedCaseInsensitiveContains(search)
            let f: Bool
            switch sourceFilter {
            case .all: f = true
            case .local: f = m.source == .local
            case .cloud: f = m.isCloud
            }
            return s && f
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                TextField("Filter...", text: $search).textFieldStyle(.plain).font(.system(size: 13))
                Picker("", selection: $sourceFilter) {
                    ForEach(ModelSourceFilter.allCases, id: \.self) { Text($0.rawValue) }
                }.pickerStyle(.segmented).frame(width: 140)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { model in
                        ModelRow(model: model, isSelected: state.selectedModel == model)
                            .contentShape(Rectangle())
                            .onTapGesture { state.selectedModel = model }
                    }
                }
            }

            Divider()
            HStack {
                Text("\(filtered.count) models").font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 4)
        }
    }
}

struct ModelRow: View {
    let model: MLXModel; let isSelected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(srcColor).frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.shortName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .lineLimit(1)
                if model.source == .local, let org = model.id.components(separatedBy: "/").first {
                    Text(org).font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                }
            }
            Spacer()
            Text(model.providerBadge)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(srcColor)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(srcColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 2))
            Text(model.size)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.creamDim)
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isSelected ? Theme.accentMagenta.opacity(0.2) : .clear)
    }
    var srcColor: Color {
        switch model.source {
        case .local: return .teal; case .network: return .purple; case .anthropic: return .orange
        case .openai: return .green; case .google: return .blue
        }
    }
}

// MARK: - Parameters Panel (Right Col)

struct ParametersPanel: View {
    @ObservedObject var state: AppState
    @State private var showSave = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Profile picker row
            HStack(spacing: 8) {
                Text("Profile").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.creamDim)
                Picker("", selection: $state.activeProfile.name) {
                    ForEach(state.profiles) { p in Text(p.name).tag(p.name) }
                }
                .frame(width: 120)
                .onChange(of: state.activeProfile.name) { _, newName in
                    if let p = state.profiles.first(where: { $0.name == newName }) {
                        state.activeProfile = p
                    }
                }
                Button("Default") { state.resetToDefault() }
                    .font(.system(size: 12)).buttonStyle(.bordered).controlSize(.mini)
                Spacer()
                Button("Save") { state.saveProfile(state.activeProfile) }
                    .font(.system(size: 12)).buttonStyle(.borderedProminent).tint(.teal).controlSize(.mini)
                Button("Save As...") { showSave = true }
                    .font(.system(size: 12)).buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PS(label: "Temperature", value: $state.activeProfile.temp, range: 0...2, step: 0.05, fmt: "%.2f")
                    PS(label: "Top P", value: $state.activeProfile.top_p, range: 0...1, step: 0.05, fmt: "%.2f")
                    PI(label: "Top K", value: $state.activeProfile.top_k, range: 0...200)
                    PS(label: "Min P", value: $state.activeProfile.min_p, range: 0...1, step: 0.01, fmt: "%.2f")
                    PI(label: "Max Tokens", value: $state.activeProfile.max_tokens, range: 64...32768)
                    PS(label: "Repetition Penalty", value: $state.activeProfile.repetition_penalty, range: 1.0...2.0, step: 0.05, fmt: "%.2f")
                    PI(label: "Rep. Context", value: $state.activeProfile.repetition_context_size, range: 0...1024)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt").font(.system(size: 13, weight: .medium))
                        TextEditor(text: $state.activeProfile.system_prompt)
                            .font(.system(size: 13, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(6).background(Theme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .frame(minHeight: 60, maxHeight: 120)
                    }
                }
                .padding(14)
            }
        }
        .sheet(isPresented: $showSave) {
            VStack(spacing: 12) {
                Text("Save Profile As").font(.system(size: 13, weight: .semibold))
                TextField("Name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 200)
                HStack {
                    Button("Cancel") { showSave = false }.keyboardShortcut(.cancelAction)
                    Button("Save") {
                        var p = state.activeProfile; p.name = newName
                        state.saveProfile(p); newName = ""; showSave = false
                    }.buttonStyle(.borderedProminent).disabled(newName.isEmpty).keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }
    }
}

struct PS: View {
    let label: String; @Binding var value: Double; let range: ClosedRange<Double>
    var step: Double = 0.1; var fmt: String = "%.1f"
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: fmt, value)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.teal)
            }
            Slider(value: $value, in: range, step: step).controlSize(.small)
        }
    }
}

struct PI: View {
    let label: String; @Binding var value: Int; let range: ClosedRange<Int>
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(value)").font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.teal)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1).controlSize(.small)
        }
    }
}

// MARK: - Prompts Panel (Right Col)

struct PromptsPanel: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    @State private var selected: SystemPrompt?
    @State private var showAdd = false
    @State private var newPromptName = ""
    @State private var newPromptText = ""

    var filtered: [SystemPrompt] {
        if search.isEmpty { return state.prompts }
        return state.prompts.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.prompt.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + add
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                TextField("Search...", text: $search).textFieldStyle(.plain).font(.system(size: 13))
                Button { showAdd = true } label: {
                    Image(systemName: "plus").font(.system(size: 12))
                }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            Divider()

            // Top: prompt list
            List(filtered, selection: $selected) { p in
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.system(size: 13, weight: .medium))
                    Text(String(p.prompt.prefix(50))).font(.system(size: 12)).foregroundStyle(Theme.creamDim).lineLimit(1)
                }.padding(.vertical, 1).tag(p)
            }
            .listStyle(.plain)
            .frame(maxHeight: 250)

            Divider()

            // Bottom: prompt content
            if let p = selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(p.name).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(p.source).font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                    }
                    ScrollView {
                        Text(p.prompt).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).lineSpacing(2)
                    }
                    HStack(spacing: 6) {
                        Button { state.activeProfile.system_prompt = p.prompt } label: {
                            Label("Use", systemImage: "arrow.right.circle")
                        }.buttonStyle(.borderedProminent).tint(.teal).controlSize(.mini)
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(p.prompt, forType: .string) } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }.buttonStyle(.bordered).controlSize(.mini)
                    }
                }.padding(10)
            } else {
                VStack {
                    Spacer()
                    Text("Select a prompt").font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            VStack(alignment: .leading, spacing: 10) {
                Text("New Prompt").font(.system(size: 13, weight: .semibold))
                TextField("Name", text: $newPromptName).textFieldStyle(.roundedBorder)
                TextEditor(text: $newPromptText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 360, height: 150).border(.quaternary)
                HStack {
                    Button("Cancel") { showAdd = false }.keyboardShortcut(.cancelAction)
                    Button("Add") {
                        addPrompt(name: newPromptName, text: newPromptText, state: state)
                        newPromptName = ""; newPromptText = ""; showAdd = false
                    }.buttonStyle(.borderedProminent).disabled(newPromptName.isEmpty || newPromptText.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }
    }

    private func addPrompt(name: String, text: String, state: AppState) {
        let configDir = NSHomeDirectory() + "/.config/mlx-launcher/prompts"
        let path = configDir + "/library.json"
        var prompts = state.prompts
        prompts.append(SystemPrompt(name: name, prompt: text, source: "custom"))
        if let data = try? JSONEncoder().encode(prompts) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        state.loadPrompts()
    }
}

// MARK: - Runner Args Panel (Right Col)

struct RunnerArgsPanel: View {
    @ObservedObject var state: AppState

    var runner: Runner { state.selectedRunner }

    var args: [RunnerArg] { RunnerArg.argsFor(runner.id) }

    var body: some View {
        let settings = state.settings(for: runner)
        VStack(spacing: 0) {
            HStack {
                Image(systemName: runner.icon).font(.system(size: 13))
                Text(runner.name).font(.system(size: 13, weight: .semibold))
                if !runner.isInstalled {
                    Text("not installed").font(.system(size: 12)).foregroundStyle(.red)
                }
                Spacer()
                Button("Clear All") {
                    var next = settings
                    next.enabledFlags.removeAll()
                    next.values.removeAll()
                    next.extraArguments = ""
                    state.updateSettings(for: runner, next)
                }
                    .font(.system(size: 12)).buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Runner Working Directory")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.creamDim)
                        HStack(spacing: 6) {
                            TextField("Directory", text: Binding(
                                get: { state.settings(for: runner).workingDirectory },
                                set: {
                                    var next = state.settings(for: runner)
                                    next.workingDirectory = $0
                                    state.updateSettings(for: runner, next)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            Button("Home") {
                                var next = state.settings(for: runner)
                                next.workingDirectory = NSHomeDirectory()
                                state.updateSettings(for: runner, next)
                            }
                            .font(.system(size: 12)).buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 14).padding(.top, 10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extra Arguments")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.creamDim)
                        TextField("--flag value --another", text: Binding(
                            get: { state.settings(for: runner).extraArguments },
                            set: {
                                var next = state.settings(for: runner)
                                next.extraArguments = $0
                                state.updateSettings(for: runner, next)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    }
                    .padding(.horizontal, 14)

                    Divider()

                    ForEach(args) { arg in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { state.settings(for: runner).enabledFlags.contains(arg.flag) },
                                set: {
                                    var next = state.settings(for: runner)
                                    if $0 {
                                        next.enabledFlags.insert(arg.flag)
                                    } else {
                                        next.enabledFlags.remove(arg.flag)
                                    }
                                    state.updateSettings(for: runner, next)
                                }
                            ))
                            .toggleStyle(.checkbox).labelsHidden()

                            VStack(alignment: .leading, spacing: 1) {
                                Text(arg.flag)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(state.settings(for: runner).enabledFlags.contains(arg.flag) ? .teal : .primary)
                                Text(arg.help)
                                    .font(.system(size: 12)).foregroundStyle(Theme.creamDim).lineLimit(2)
                            }

                            Spacer()

                            if arg.takesValue {
                                TextField("value", text: Binding(
                                    get: { state.settings(for: runner).values[arg.flag] ?? "" },
                                    set: {
                                        var next = state.settings(for: runner)
                                        next.values[arg.flag] = $0
                                        state.updateSettings(for: runner, next)
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 100)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(state.settings(for: runner).enabledFlags.contains(arg.flag) ? Color.teal.opacity(0.04) : .clear)
                    }
                }
            }

            Divider()

            // Preview command
            HStack {
                Text("Command: ").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                Text(state.commandPreview()).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.creamDim)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
    }
}

// MARK: - Runner Arg Definitions

struct RunnerArg: Identifiable {
    let flag: String; let help: String; let takesValue: Bool
    var id: String { flag }

    static func argsFor(_ runnerId: String) -> [RunnerArg] {
        switch runnerId {
        case "claude": return claudeArgs
        case "codex": return codexArgs
        case "gemini": return geminiArgs
        case "aider": return aiderArgs
        case "gptme": return gptmeArgs
        default: return []
        }
    }

    static let claudeArgs: [RunnerArg] = [
        .init(flag: "--dangerously-skip-permissions", help: "Bypass all permission checks (sandbox only)", takesValue: false),
        .init(flag: "--allow-dangerously-skip-permissions", help: "Enable skip-permissions as an option", takesValue: false),
        .init(flag: "-p", help: "Print response and exit (pipe mode)", takesValue: false),
        .init(flag: "--permission-mode", help: "Permission mode: default, auto, plan, bypassPermissions", takesValue: true),
        .init(flag: "--model", help: "Override model for the session", takesValue: true),
        .init(flag: "--effort", help: "Effort level: low, medium, high, max", takesValue: true),
        .init(flag: "--system-prompt", help: "Custom system prompt", takesValue: true),
        .init(flag: "--append-system-prompt", help: "Append to default system prompt", takesValue: true),
        .init(flag: "--max-budget-usd", help: "Max dollar spend (print mode only)", takesValue: true),
        .init(flag: "--verbose", help: "Verbose output", takesValue: false),
        .init(flag: "-c", help: "Continue most recent conversation", takesValue: false),
        .init(flag: "--bare", help: "Minimal mode: skip hooks, LSP, plugins", takesValue: false),
        .init(flag: "--debug", help: "Enable debug mode", takesValue: false),
        .init(flag: "--json-schema", help: "JSON schema for structured output", takesValue: true),
        .init(flag: "--output-format", help: "Output format: text, json, stream-json", takesValue: true),
        .init(flag: "--tools", help: "Available tools list (e.g. Bash,Edit,Read)", takesValue: true),
        .init(flag: "--allowedTools", help: "Allowed tool names", takesValue: true),
        .init(flag: "--add-dir", help: "Additional directories for tool access", takesValue: true),
        .init(flag: "--mcp-config", help: "MCP server config files", takesValue: true),
    ]

    static let codexArgs: [RunnerArg] = [
        .init(flag: "-m", help: "Override model name", takesValue: true),
        .init(flag: "-c", help: "Configuration override, e.g. model_provider=\"oss\"", takesValue: true),
        .init(flag: "--ask-for-approval", help: "Approval policy: untrusted, on-failure, on-request, never", takesValue: true),
        .init(flag: "--sandbox", help: "Sandbox mode: read-only, workspace-write, danger-full-access", takesValue: true),
        .init(flag: "--image", help: "Include image file", takesValue: true),
        .init(flag: "--enable", help: "Enable a feature flag", takesValue: true),
        .init(flag: "--disable", help: "Disable a feature flag", takesValue: true),
        .init(flag: "--full-auto", help: "Run with low-friction defaults", takesValue: false),
        .init(flag: "--dangerously-bypass-approvals-and-sandbox", help: "Bypass approvals and sandboxing", takesValue: false),
    ]

    static let geminiArgs: [RunnerArg] = [
        .init(flag: "-y", help: "YOLO mode: auto-accept all actions", takesValue: false),
        .init(flag: "--approval-mode", help: "Mode: default, auto_edit, yolo, plan", takesValue: true),
        .init(flag: "--sandbox", help: "Run in sandbox", takesValue: false),
        .init(flag: "-d", help: "Debug mode (F12 for console)", takesValue: false),
        .init(flag: "--policy", help: "Additional policy files to load", takesValue: true),
        .init(flag: "--admin-policy", help: "Admin policy files", takesValue: true),
        .init(flag: "--include-directories", help: "Additional workspace directories", takesValue: true),
        .init(flag: "-o", help: "Output format: text, json, stream-json", takesValue: true),
        .init(flag: "-r", help: "Resume previous session", takesValue: true),
        .init(flag: "--screen-reader", help: "Accessibility screen reader mode", takesValue: false),
    ]

    static let aiderArgs: [RunnerArg] = [
        .init(flag: "--no-auto-commits", help: "Disable automatic git commits", takesValue: false),
        .init(flag: "--auto-commits", help: "Enable automatic git commits", takesValue: false),
        .init(flag: "--yes", help: "Always say yes to every confirmation", takesValue: false),
        .init(flag: "--architect", help: "Use architect mode", takesValue: false),
        .init(flag: "--edit-format", help: "Edit format to use", takesValue: true),
        .init(flag: "--dark-mode", help: "Dark terminal colors", takesValue: false),
        .init(flag: "--no-git", help: "Disable git integration", takesValue: false),
        .init(flag: "--subtree-only", help: "Only consider files in current subtree", takesValue: false),
        .init(flag: "--lint-cmd", help: "Lint command to run", takesValue: true),
        .init(flag: "--test-cmd", help: "Test command to run", takesValue: true),
        .init(flag: "--auto-lint", help: "Auto-run linter after edits", takesValue: false),
        .init(flag: "--auto-test", help: "Auto-run tests after edits", takesValue: false),
        .init(flag: "--stream", help: "Stream responses", takesValue: false),
        .init(flag: "--cache-prompts", help: "Enable prompt caching", takesValue: false),
        .init(flag: "--map-tokens", help: "Max tokens for repo map", takesValue: true),
        .init(flag: "--show-diffs", help: "Show diffs after changes", takesValue: false),
    ]

    static let gptmeArgs: [RunnerArg] = [
        .init(flag: "--name", help: "Conversation name", takesValue: true),
        .init(flag: "-m", help: "Model to use", takesValue: true),
        .init(flag: "-w", help: "Workspace directory", takesValue: true),
        .init(flag: "--non-interactive", help: "Non-interactive mode", takesValue: false),
        .init(flag: "--no-confirm", help: "Skip all confirmations", takesValue: false),
        .init(flag: "--no-stream", help: "Disable streaming", takesValue: false),
        .init(flag: "--show-hidden", help: "Show hidden system messages", takesValue: false),
        .init(flag: "--tool-allowlist", help: "Allowed tools only", takesValue: true),
    ]
}

// MARK: - Server Panel

struct ServerPanel: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MLX Server").font(.system(size: 14, weight: .semibold))
                    Text("localhost:\(state.serverStatus.port)")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.creamDim)
                }
                Spacer()
                HStack(spacing: 4) {
                    Button { if let m = state.selectedModel, m.source == .local { state.startServer(model: m) } } label: {
                        Label("Start", systemImage: "play.fill")
                    }.disabled(state.serverStatus.state == .running || state.selectedModel?.isCloud == true)
                    Button { state.stopServer() } label: { Label("Stop", systemImage: "stop.fill") }
                        .tint(.red).disabled(state.serverStatus.state != .running)
                    Button { state.restartServer() } label: { Label("Restart", systemImage: "arrow.clockwise") }
                        .disabled(state.serverStatus.state != .running)
                }.buttonStyle(.bordered).controlSize(.mini)
            }.padding(12)

            Divider()

            HStack(spacing: 8) {
                SC(t: "State", v: state.serverStatus.state.rawValue.capitalized,
                   c: state.serverStatus.state == .running ? .green : .secondary)
                SC(t: "Model", v: state.serverStatus.modelName ?? "--", c: .teal)
                SC(t: "PID", v: state.serverStatus.pid.map(String.init) ?? "--", c: .secondary)
            }.padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Extra MLX Server Args")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.creamDim)
                TextField("--chat-template-args '{\"enable_thinking\":false}'", text: $state.extraMLXServerArguments)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Text("Typed sampling parameters are applied on start; use this for any additional mlx_lm server flag.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.creamDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            HStack {
                Text("Log").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                Spacer()
                Button("Clear") { state.serverLog.removeAll() }
                    .font(.system(size: 12)).buttonStyle(.borderless)
            }.padding(.horizontal, 12).padding(.vertical, 6)

            LogViewer(lines: state.serverLog)
        }
    }
}

struct SC: View {
    let t: String; let v: String; let c: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.creamDim).textCase(.uppercase)
            Text(v).font(.system(size: 12, design: .monospaced)).foregroundStyle(c).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        .background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Model Store Panel

struct ModelStorePanel: View {
    @ObservedObject var state: AppState
    @State private var searchText = ""
    @State private var activeTab: ModelTab = .local
    @State private var newServerHost = ""
    @State private var newServerPort = "1234"
    @State private var showAddDir = false
    @State private var newDirPath = ""

    enum ModelTab: String, CaseIterable {
        case local = "Local"
        case network = "Network"
        case search = "Search HF"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Model Store").font(.system(size: 14, weight: .semibold))
                    Text("Fetch, manage, and discover models")
                        .font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                }
                Spacer()
                Button { state.modelStore.scanLocalModels() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                }.buttonStyle(.bordered).controlSize(.mini)
            }.padding(12)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(ModelTab.allCases, id: \.self) { tab in
                    Button { activeTab = tab } label: {
                        Text(tab.rawValue).font(.system(size: 13, weight: activeTab == tab ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(activeTab == tab ? Color.accentColor.opacity(0.15) : .clear)
                    }.buttonStyle(.plain)
                }
            }.background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 12)

            Divider().padding(.top, 8)

            // Content
            switch activeTab {
            case .local: localModelsTab
            case .network: networkTab
            case .search: searchTab
            }
        }
    }

    // MARK: - Local Models Tab

    private var localModelsTab: some View {
        VStack(spacing: 0) {
            // Scan directories
            HStack {
                Text("Scan Directories").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                Spacer()
                Button { showAddDir.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: 12))
                }.buttonStyle(.borderless)
            }.padding(.horizontal, 12).padding(.vertical, 6)

            if showAddDir {
                HStack(spacing: 4) {
                    TextField("Path...", text: $newDirPath).textFieldStyle(.roundedBorder).font(.system(size: 12))
	                    Button("Add") {
	                        if !newDirPath.isEmpty {
	                            state.modelStore.addScanDirectory(newDirPath)
	                            state.saveModelStoreSettings()
	                            newDirPath = ""
	                            showAddDir = false
	                        }
                    }.buttonStyle(.bordered).controlSize(.mini)
                }.padding(.horizontal, 12).padding(.bottom, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(state.modelStore.scanDirectories, id: \.self) { dir in
                        HStack(spacing: 2) {
                            Text(abbreviatePath(dir)).font(.system(size: 12, design: .monospaced))
	                            Button {
	                                state.modelStore.removeScanDirectory(dir)
	                                state.saveModelStoreSettings()
	                            } label: {
	                                Image(systemName: "xmark").font(.system(size: 12))
	                            }.buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }.padding(.horizontal, 12).padding(.bottom, 6)

            Divider()

            // Model list
            if state.modelStore.isScanning {
                VStack { Spacer(); ProgressView("Scanning...").font(.system(size: 13)); Spacer() }
            } else if state.modelStore.localModels.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 24)).foregroundStyle(Theme.creamDim)
                    Text("No models found").font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                    Text("Add directories above or download from Search HF tab")
                        .font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(state.modelStore.localModels) { model in
                            localModelRow(model)
                        }
                    }
                }
            }
        }
    }

    private func localModelRow(_ model: DiscoveredModel) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.id).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.creamDim).lineLimit(1)
                }
            }
            Spacer()
            if let quant = model.quantization {
                Text(quant).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(quantColor(quant).opacity(0.15)).foregroundStyle(quantColor(quant))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if let arch = model.architecture {
                Text(arch).font(.system(size: 12)).foregroundStyle(Theme.creamDim)
            }
            Text(model.size).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.creamDim)
            Button {
                state.selectDiscoveredModel(model)
            } label: {
                Text(state.selectedModel?.launchIdentity == model.launchIdentity ? "Loaded" : "Load")
                    .font(.system(size: 12, weight: .medium))
            }.buttonStyle(.borderless)
            Button {
                state.modelStore.deleteModel(model)
            } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.red.opacity(0.6))
            }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color.clear)
    }

    // MARK: - Network Tab

    private var networkTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Network Servers").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                Spacer()
                Button { state.modelStore.startNetworkDiscovery() } label: {
                    Label("Scan", systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 12))
                }.buttonStyle(.bordered).controlSize(.mini)
            }.padding(.horizontal, 12).padding(.vertical, 8)

            // Manual server entry
            HStack(spacing: 4) {
                TextField("Host", text: $newServerHost).textFieldStyle(.roundedBorder).font(.system(size: 12))
                TextField("Port", text: $newServerPort).textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(width: 50)
                Button("Add") {
                    if let port = UInt16(newServerPort), !newServerHost.isEmpty {
                        state.modelStore.addNetworkServer(host: newServerHost, port: port)
                        newServerHost = ""
                    }
                }.buttonStyle(.bordered).controlSize(.mini)
            }.padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            if state.modelStore.networkModels.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "network").font(.system(size: 24)).foregroundStyle(Theme.creamDim)
                    Text("No network servers found").font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                    Text("Add a server manually or wait for Bonjour discovery")
                        .font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(state.modelStore.networkModels) { model in
                            HStack(spacing: 8) {
                                Image(systemName: "network").font(.system(size: 12)).foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text("\(model.networkHost ?? ""):\(model.networkPort ?? 0)")
                                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.creamDim)
                                }
	                                Spacer()
	                                Text("Network").font(.system(size: 12)).foregroundStyle(.blue)
	                                Button {
	                                    state.selectDiscoveredModel(model)
	                                } label: {
	                                    Text(state.selectedModel?.launchIdentity == model.launchIdentity ? "Loaded" : "Load")
	                                        .font(.system(size: 12, weight: .medium))
	                                }.buttonStyle(.borderless)
	                            }.padding(.horizontal, 12).padding(.vertical, 5)
	                        }
                    }
                }
            }
        }
    }

    // MARK: - HuggingFace Search Tab

    private var searchTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                TextField("Search HuggingFace for MLX models...", text: $searchText)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13))
                    .onSubmit { state.modelStore.searchHuggingFace(query: searchText) }
                Button { state.modelStore.searchHuggingFace(query: searchText) } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 13))
                }.buttonStyle(.bordered).controlSize(.mini)
            }.padding(12)

            Divider()

            if state.modelStore.isSearching {
                VStack { Spacer(); ProgressView("Searching...").font(.system(size: 13)); Spacer() }
            } else if state.modelStore.searchResults.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundStyle(Theme.creamDim)
                    Text("Search for MLX models on HuggingFace").font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                    Text("Try: \"llama 3 mlx\", \"qwen 4bit\", \"gemma mlx\"")
                        .font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(state.modelStore.searchResults) { model in
                            searchResultRow(model)
                        }
                    }
                }
            }
        }
    }

    private func searchResultRow(_ model: DiscoveredModel) -> some View {
        let isDownloading = state.modelStore.downloadingModels[model.id] != nil
        let isLocal = state.modelStore.localModels.contains { $0.id == model.id }

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(model.id).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.creamDim).lineLimit(1)
            }
            Spacer()
            if let quant = model.quantization {
                Text(quant).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(quantColor(quant).opacity(0.15)).foregroundStyle(quantColor(quant))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(model.size).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.creamDim)

            if isLocal {
                Text("Installed").font(.system(size: 12)).foregroundStyle(.green)
            } else if isDownloading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    state.modelStore.downloadModel(model)
                } label: {
                    Image(systemName: "arrow.down.circle").font(.system(size: 12))
                }.buttonStyle(.borderless).foregroundStyle(.blue)
            }
        }.padding(.horizontal, 12).padding(.vertical, 5)
    }

    // MARK: - Helpers

    private func quantColor(_ quant: String) -> Color {
        switch quant {
        case "2bit": return .red
        case "3bit": return .orange
        case "4bit": return .yellow
        case "8bit": return .green
        case "fp16", "bf16": return .blue
        default: return .secondary
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - Governance Panel

struct GovernancePanel: View {
    @ObservedObject var state: AppState
    @State private var editingRule: PolicyRule?
    @State private var showRuleEditor = false
    @State private var newBlockedPath = ""
    @State private var newBlockedCommand = ""
    @State private var newApprovalTool = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Governance Engine").font(.system(size: 16, weight: .semibold))
                    Text("Policy rules, tool interception, sandbox control")
                        .font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(state.governanceEnabled ? .green : .secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(state.governanceEnabled ? "Active" : "Disabled")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                }
            }.padding(14)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    enableSection
                    if state.governanceConfig.enabled {
                        sandboxSection
                        rulesSection
                        uiaSection
                        contextBudgetSection
                        toolInterceptionSection
                        presetsSection
                        eventLogSection
                    }
                }.padding(14)
            }
        }
    }

    // MARK: - Enable/Disable

    private var enableSection: some View {
        HStack {
            Toggle("Enable Governance", isOn: Binding(
                get: { state.governanceConfig.enabled },
                set: { enabled in
                    var config = state.governanceConfig
                    config.enabled = enabled
                    state.updateGovernanceConfig(config)
                }
            )).toggleStyle(.switch).font(.system(size: 13))
            Spacer()
        }
    }

    // MARK: - Sandbox Level

    private var sandboxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sandbox Level").font(.system(size: 14, weight: .semibold))
            Picker("", selection: Binding(
                get: { state.governanceConfig.sandboxLevel },
                set: { level in
                    var config = state.governanceConfig
                    config.sandboxLevel = level
                    state.updateGovernanceConfig(config)
                }
            )) {
                Text("Jailed").tag(SandboxLevel.jailed)
                Text("Sandbox").tag(SandboxLevel.sandbox)
                Text("Workspace").tag(SandboxLevel.workspace)
                Text("Full").tag(SandboxLevel.full)
            }.pickerStyle(.segmented).labelsHidden()

            Text(sandboxDescription(state.governanceConfig.sandboxLevel))
                .font(.system(size: 13)).foregroundStyle(Theme.creamDim)
        }.padding(10).background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sandboxDescription(_ level: SandboxLevel) -> String {
        switch level {
        case .jailed: return "All tool execution blocked. Read-only mode."
        case .sandbox: return "Read-only tools allowed. Write operations blocked."
        case .workspace: return "Read-write within project directory. System access restricted."
        case .full: return "Full system access. Use with caution."
        }
    }

    // MARK: - Policy Rules (unified: features + rules in one section)

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Policy Rules").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Install Packaged") { installPackagedRules() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button { addDefaultRule() } label: {
                    Image(systemName: "plus").font(.system(size: 12))
                }.buttonStyle(.borderless)
            }

            Text("Toggle rules to control runner and sub-agent behavior through Engrave.")
                .font(.system(size: 13)).foregroundStyle(Theme.creamDim)

            if state.governanceConfig.rules.isEmpty && !GovernanceFeature.allCases.isEmpty {
                // Show feature toggles only when no rules are installed
                ForEach(GovernanceFeature.allCases) { feature in
                    featureToggleRow(feature)
                }
            } else if !state.governanceConfig.rules.isEmpty {
                // Show unified rule list with enable/disable toggles
                ForEach(Array(state.governanceConfig.rules.enumerated()), id: \.element.id) { idx, rule in
                    ruleRow(rule, index: idx)
                }
            } else {
                Text("No rules configured. Click \"Install Packaged\" to add recommended rules.")
                    .font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                    .padding(.vertical, 8)
            }
        }.padding(10).background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func featureToggleRow(_ feature: GovernanceFeature) -> some View {
        Toggle(isOn: Binding(
            get: { state.governanceConfig.isFeatureEnabled(feature) },
            set: { enabled in
                var config = state.governanceConfig
                config.setFeature(feature, enabled: enabled)
                state.updateGovernanceConfig(config)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.system(size: 12, weight: .medium))
                Text(feature.description).font(.system(size: 13)).foregroundStyle(Theme.creamDim)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.vertical, 2)
    }

    private func ruleRow(_ rule: PolicyRule, index: Int) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { enabled in
                    var config = state.governanceConfig
                    config.rules[index].enabled = enabled
                    state.updateGovernanceConfig(config)
                }
            )).toggleStyle(.switch).controlSize(.small).labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    severityBadge(rule.severity)
                    Text(rule.trigger.rawValue).font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                    if !rule.matchPatterns.isEmpty {
                        Text("\(rule.matchPatterns.count) patterns").font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                    }
                }
            }
            Spacer()
            Button {
                var config = state.governanceConfig
                config.rules.remove(at: index)
                state.updateGovernanceConfig(config)
            } label: {
                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(.red.opacity(0.7))
            }.buttonStyle(.borderless)
        }.padding(.vertical, 4)
    }

    private func severityBadge(_ severity: RuleSeverity) -> some View {
        let color: Color
        switch severity {
        case .block: color = .red
        case .warn: color = .orange
        case .modify: color = .yellow
        case .rewrite: color = .blue
        }
        return Text(severity.rawValue).font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.25)).foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var uiaSection: some View {
        let uia = state.governanceConfig.uiaConfig ?? .default
        return VStack(alignment: .leading, spacing: 8) {
            Text("Engrave UIA").font(.system(size: 14, weight: .semibold))
            Text("User-facing orchestrator for prompt decomposition, workflow DAGs, sub-agent launch steering, and progress reporting.")
                .font(.system(size: 13)).foregroundStyle(Theme.creamDim)
            HStack(spacing: 8) {
                GChip(label: "Orchestrator", value: uia.orchestratorModel)
                GChip(label: "Cheap", value: uia.cheapModel)
                GChip(label: "Local", value: uia.localModel)
            }
            HStack(spacing: 10) {
                Label(uia.explainWorkToUser ? "User Updates" : "Silent", systemImage: "bubble.left.and.text.bubble.right")
                Label(uia.createTaskDAG ? "Task DAG" : "No DAG", systemImage: "point.3.connected.trianglepath.dotted")
                Label(uia.steerSubAgents ? "Steers Agents" : "No Steering", systemImage: "arrow.triangle.branch")
            }
            .font(.system(size: 13)).foregroundStyle(Theme.creamDim)
        }.padding(10).background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var contextBudgetSection: some View {
        let budgets = state.governanceConfig.contextBudgets ?? ContextBudget.defaults
        return VStack(alignment: .leading, spacing: 8) {
            Text("Context Exhaustion Relay").font(.system(size: 14, weight: .semibold))
            Text("Budgets trigger a local/cheap relay agent to compact context into a handoff brief before replacement agents continue.")
                .font(.system(size: 13)).foregroundStyle(Theme.creamDim)
            ForEach(budgets.keys.sorted(), id: \.self) { key in
                if let budget = budgets[key] {
                    HStack {
                        Text(key).font(.system(size: 12, weight: .medium, design: .monospaced))
                        Spacer()
                        Text("\(budget.maxTokens.map(String.init) ?? "—") tokens @ \(Int(budget.thresholdPercent * 100))%")
                            .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.creamDim)
                        Text(budget.relayModel).font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                    }
                }
            }
        }.padding(10).background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private struct GChip: View {
        let label: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                Text(value).font(.system(size: 13, design: .monospaced)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    // MARK: - Tool Interception

    private var toolInterceptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tool Interception").font(.system(size: 14, weight: .semibold))

            // Blocked paths
            VStack(alignment: .leading, spacing: 4) {
                Text("Blocked Paths").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                HStack(spacing: 6) {
                    TextField("Regex pattern...", text: $newBlockedPath).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    Button("Add") {
                        guard !newBlockedPath.isEmpty else { return }
                        var config = state.governanceConfig
                        config.blockedPaths.append(newBlockedPath)
                        state.updateGovernanceConfig(config)
                        newBlockedPath = ""
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                FlowLayout(spacing: 4) {
                    ForEach(state.governanceConfig.blockedPaths, id: \.self) { path in
                        HStack(spacing: 4) {
                            Text(path).font(.system(size: 13, design: .monospaced))
                            Button {
                                var config = state.governanceConfig
                                config.blockedPaths.removeAll { $0 == path }
                                state.updateGovernanceConfig(config)
                            } label: { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.borderless)
                        }.padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.red.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Divider()

            // Blocked commands
            VStack(alignment: .leading, spacing: 4) {
                Text("Blocked Commands").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                HStack(spacing: 6) {
                    TextField("Regex pattern...", text: $newBlockedCommand).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    Button("Add") {
                        guard !newBlockedCommand.isEmpty else { return }
                        var config = state.governanceConfig
                        config.blockedCommands.append(newBlockedCommand)
                        state.updateGovernanceConfig(config)
                        newBlockedCommand = ""
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                FlowLayout(spacing: 4) {
                    ForEach(state.governanceConfig.blockedCommands, id: \.self) { cmd in
                        HStack(spacing: 4) {
                            Text(cmd).font(.system(size: 13, design: .monospaced))
                            Button {
                                var config = state.governanceConfig
                                config.blockedCommands.removeAll { $0 == cmd }
                                state.updateGovernanceConfig(config)
                            } label: { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.borderless)
                        }.padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.orange.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Divider()

            // Approval-required tools
            VStack(alignment: .leading, spacing: 4) {
                Text("Require Approval For").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                HStack(spacing: 6) {
                    TextField("Tool name...", text: $newApprovalTool).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    Button("Add") {
                        guard !newApprovalTool.isEmpty else { return }
                        var config = state.governanceConfig
                        config.requireApprovalForTools.append(newApprovalTool)
                        state.updateGovernanceConfig(config)
                        newApprovalTool = ""
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                FlowLayout(spacing: 4) {
                    ForEach(state.governanceConfig.requireApprovalForTools, id: \.self) { tool in
                        HStack(spacing: 4) {
                            Text(tool).font(.system(size: 13, design: .monospaced))
                            Button {
                                var config = state.governanceConfig
                                config.requireApprovalForTools.removeAll { $0 == tool }
                                state.updateGovernanceConfig(config)
                            } label: { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.borderless)
                        }.padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.blue.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }.padding(10).background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                Button("Strict") { state.updateGovernanceConfig(.strict) }
                    .buttonStyle(.bordered).controlSize(.regular)
                Button("Standard") { state.updateGovernanceConfig(.standard) }
                    .buttonStyle(.bordered).controlSize(.regular)
                Button("Minimal") { state.updateGovernanceConfig(.minimal) }
                    .buttonStyle(.bordered).controlSize(.regular)
                Button("Packaged") {
                    var config = state.governanceConfig
                    config.enabled = true
                    config.rules = mergeRules(config.rules, with: PolicyRule.packagedGovernanceRules)
                    config.featureToggles = GovernanceFeature.defaults(enabled: true)
                    config.contextBudgets = ContextBudget.defaults
                    config.uiaConfig = .default
                    state.updateGovernanceConfig(config)
                }.buttonStyle(.bordered).controlSize(.regular)
                Button("Clear All") {
                    var config = GovernanceConfig()
                    config.enabled = true
                    state.updateGovernanceConfig(config)
                }.buttonStyle(.bordered).controlSize(.regular).tint(.red)
            }
        }.padding(10).background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Event Log

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Decisions").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { state.refreshGovernanceEvents() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                }.buttonStyle(.borderless)
            }

            if state.governanceEvents.isEmpty {
                Text("No governance decisions yet. Events appear when requests are evaluated.")
                    .font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                    .padding(.vertical, 6)
            } else {
                ForEach(state.governanceEvents.suffix(20)) { event in
                    HStack(spacing: 8) {
                        Circle().fill(eventColor(event.decision)).frame(width: 7, height: 7)
                        Text(event.decision).font(.system(size: 13, weight: .bold))
                            .foregroundStyle(eventColor(event.decision))
                        Text(event.eventType).font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                        if let rule = event.ruleName {
                            Text(rule).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.creamDim)
                        }
                        Spacer()
                        Text(event.timestamp, style: .time).font(.system(size: 12)).foregroundStyle(Theme.creamDim)
                    }.padding(.vertical, 2)
                }
            }
        }.padding(10).background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func eventColor(_ decision: String) -> Color {
        switch decision {
        case "allow": return .green
        case "warn": return .orange
        case "block": return .red
        case "modify": return .yellow
        case "rewrite": return .blue
        default: return .secondary
        }
    }

    // MARK: - Helpers

    private func addDefaultRule() {
        var config = state.governanceConfig
        config.rules.append(PolicyRule(
            name: "New Rule",
            trigger: .request,
            severity: .warn
        ))
        state.updateGovernanceConfig(config)
    }

    private func installPackagedRules() {
        var config = state.governanceConfig
        config.rules = mergeRules(config.rules, with: PolicyRule.packagedGovernanceRules)
        if config.featureToggles == nil {
            config.featureToggles = GovernanceFeature.defaults(enabled: true)
        }
        if config.contextBudgets == nil {
            config.contextBudgets = ContextBudget.defaults
        }
        if config.uiaConfig == nil {
            config.uiaConfig = .default
        }
        state.updateGovernanceConfig(config)
    }

    private func mergeRules(_ existing: [PolicyRule], with incoming: [PolicyRule]) -> [PolicyRule] {
        var names = Set(existing.map(\.name))
        var merged = existing
        for rule in incoming where !names.contains(rule.name) {
            merged.append(rule)
            names.insert(rule.name)
        }
        return merged
    }
}

// MARK: - Flow Layout (for tag chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Interposer Panel

struct InterposerPanel: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Engrave Interposer").font(.system(size: 14, weight: .semibold))
                    Text("port \(state.interposerPort) — Anthropic · OpenAI · Gemini")
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.creamDim)
                    Text(state.interposerTarget)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(state.interposerRunning ? .green : .secondary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(state.interposerRunning ? .green : .secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(state.interposerRunning ? "Running" : "Stopped")
                        .font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                }
                HStack(spacing: 4) {
                    Button { state.startInterposer() } label: { Label("Start", systemImage: "play.fill") }
                        .disabled(state.interposerRunning)
                    Button { state.stopInterposer() } label: { Label("Stop", systemImage: "stop.fill") }
                        .tint(.red).disabled(!state.interposerRunning)
                }.buttonStyle(.bordered).controlSize(.mini)
            }.padding(12)

            Divider()

            HStack {
                Text("Traffic Log").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.creamDim)
                Spacer()
                Button("Clear") {
                    state.interposerLog.removeAll()
                }.font(.system(size: 12)).buttonStyle(.borderless)
            }.padding(.horizontal, 12).padding(.vertical, 6)

            if state.interposerLog.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "arrow.triangle.swap").font(.system(size: 24)).foregroundStyle(Theme.creamDim)
                    Text(state.interposerRunning ? "Waiting for traffic..." : "Start interposer to see logs")
                        .font(.system(size: 13)).foregroundStyle(Theme.creamDim)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                LogViewer(lines: state.interposerLog)
            }
        }
    }
}

// MARK: - Log Viewer

struct LogViewer: View {
    let lines: [String]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(lc(line)).textSelection(.enabled)
                            .padding(.horizontal, 12).padding(.vertical, 1).id(idx)
                    }
                }
            }
            .background(Theme.bg.opacity(0.8))
            .onChange(of: lines.count) { _, _ in
                if let l = lines.indices.last { withAnimation(.none) { proxy.scrollTo(l, anchor: .bottom) } }
            }
        }
    }
    func lc(_ s: String) -> Color {
        if s.contains("ERROR") || s.contains("error") { return Theme.red }
        if s.contains("WARN") { return Theme.yellow }
        if s.contains("POST") || s.contains("GET") { return Theme.teal }
        return Theme.creamDim
    }
}

// MARK: - HuggingFace WebView

struct HFWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView { let w = WKWebView(); w.load(URLRequest(url: url)); return w }
    func updateNSView(_ w: WKWebView, context: Context) { if w.url != url { w.load(URLRequest(url: url)) } }
}
