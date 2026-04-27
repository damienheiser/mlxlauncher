import SwiftUI
import EngraveInterposer

// MARK: - Engine Registry Panel

/// Configure inference engine endpoints (local + remote) and model→engine routing.
/// This is the configuration engine that allows registering new models and engines.
struct EngineRegistryPanel: View {
    @ObservedObject var state: AppState
    @State private var selectedTab = 0
    @State private var showAddEngine = false
    @State private var showAddRoute = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Engine Registry").font(.thHeader).foregroundColor(Theme.creamBold)
                        Text("Register inference engines and configure model routing")
                            .font(.thSmall).foregroundColor(Theme.creamDim)
                    }
                    Spacer()
                    Text("\(state.engineEndpoints.filter(\.enabled).count) engines")
                        .font(.thBadge).foregroundColor(Theme.teal)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.teal.opacity(0.15)).cornerRadius(4)
                }
                .padding(.horizontal).padding(.top, 8)

                // Tab picker
                Picker("", selection: $selectedTab) {
                    Text("Engines").tag(0)
                    Text("Model Routes").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedTab == 0 {
                    enginesSection
                } else {
                    modelRoutesSection
                }
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showAddEngine) { AddEngineSheet(state: state, isPresented: $showAddEngine) }
        .sheet(isPresented: $showAddRoute) { AddRouteSheet(state: state, isPresented: $showAddRoute) }
    }

    // MARK: - Engines Tab

    private var enginesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Registered Engines").font(.thBody).foregroundColor(Theme.cream)
                Spacer()
                Button(action: { showAddEngine = true }) {
                    Label("Add Engine", systemImage: "plus.circle")
                        .font(.thSmall).foregroundColor(Theme.accentBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            ForEach(state.engineEndpoints) { engine in
                engineRow(engine)
            }

            if state.engineEndpoints.isEmpty {
                Text("No engines registered. Add an inference engine to get started.")
                    .font(.thSmall).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity).padding()
            }
        }
    }

    private func engineRow(_ engine: EngineEndpoint) -> some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(engine.enabled ? Theme.green : Theme.muted)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(engine.name).font(.thBody).foregroundColor(Theme.cream)
                    Text(engine.backend.displayName).font(.thBadge).foregroundColor(Theme.accentBlue)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.accentBlue.opacity(0.15)).cornerRadius(3)
                    if engine.isRemote {
                        Image(systemName: "network").font(.thSmall).foregroundColor(Theme.muted)
                    } else {
                        Image(systemName: "desktopcomputer").font(.thSmall).foregroundColor(Theme.teal)
                    }
                }
                Text(engine.baseURL).font(.thMonoSmall).foregroundColor(Theme.creamDim)
                if let keyEnv = engine.apiKeyEnv, !keyEnv.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "key").font(.system(size: 9))
                        Text(keyEnv).font(.thMonoSmall)
                        // Show if key is set
                        if ProcessInfo.processInfo.environment[keyEnv] != nil {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundColor(Theme.green)
                        } else {
                            Image(systemName: "xmark.circle").font(.system(size: 9)).foregroundColor(Theme.red)
                        }
                    }
                    .foregroundColor(Theme.muted)
                }
            }

            Spacer()

            // Toggle enabled
            Toggle("", isOn: Binding(
                get: { engine.enabled },
                set: { newValue in
                    if let idx = state.engineEndpoints.firstIndex(where: { $0.id == engine.id }) {
                        state.engineEndpoints[idx].enabled = newValue
                        state.saveEngineRegistry()
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            // Delete (only non-builtins)
            if !EngineEndpoint.builtins.contains(where: { $0.name == engine.name }) {
                Button(action: { state.removeEngine(id: engine.id) }) {
                    Image(systemName: "trash").font(.thSmall).foregroundColor(Theme.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Theme.bgCard)
        .cornerRadius(8)
        .padding(.horizontal)
    }

    // MARK: - Model Routes Tab

    private var modelRoutesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model → Engine Routes").font(.thBody).foregroundColor(Theme.cream)
                Spacer()
                Button(action: { showAddRoute = true }) {
                    Label("Add Route", systemImage: "plus.circle")
                        .font(.thSmall).foregroundColor(Theme.accentBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            Text("When a request arrives, the model name is matched against these patterns (first match wins). Unmatched models fall through to the local MLX engine.")
                .font(.thSmall).foregroundColor(Theme.muted)
                .padding(.horizontal)

            ForEach(state.modelRouteMappings) { route in
                routeRow(route)
            }

            if state.modelRouteMappings.isEmpty {
                Text("No model routes configured. Built-in routes for Anthropic, OpenAI, and Google are always active.")
                    .font(.thSmall).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity).padding()
            }

            // Show built-in routes (read-only)
            Divider().padding(.horizontal)
            Text("Built-in Routes (always active)").font(.thLabel).foregroundColor(Theme.muted)
                .padding(.horizontal)
            ForEach(EngraveConfig.ModelRoute.builtins, id: \.pattern) { route in
                HStack(spacing: 8) {
                    Text(route.pattern).font(.thMono).foregroundColor(Theme.teal)
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(Theme.muted)
                    Text(route.provider).font(.thMono).foregroundColor(Theme.accentBlue)
                    Spacer()
                    Text("built-in").font(.thBadge).foregroundColor(Theme.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .padding(.horizontal)
            }
        }
    }

    private func routeRow(_ route: ModelRouteMapping) -> some View {
        HStack(spacing: 8) {
            Text(route.pattern).font(.thMono).foregroundColor(Theme.cream)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(Theme.muted)
            Text(route.engineName).font(.thBody).foregroundColor(Theme.accentBlue)
            if route.stripPrefix {
                Text("strip").font(.thBadge).foregroundColor(Theme.yellow)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Theme.yellow.opacity(0.15)).cornerRadius(3)
            }
            if let desc = route.description {
                Text(desc).font(.thSmall).foregroundColor(Theme.creamDim)
            }
            Spacer()
            Button(action: { state.removeModelRoute(id: route.id) }) {
                Image(systemName: "trash").font(.thSmall).foregroundColor(Theme.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Theme.bgCard)
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Add Engine Sheet

private struct AddEngineSheet: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var backend: EngineBackend = .chatCompletions
    @State private var baseURL = ""
    @State private var apiKeyEnv = ""
    @State private var isRemote = true

    // No static type options needed — use EngineBackend.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Engine Endpoint").font(.thHeader).foregroundColor(Theme.creamBold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.thLabel).foregroundColor(Theme.creamDim)
                TextField("e.g. Home Ollama, Lab vLLM, RunPod A100", text: $name)
                    .textFieldStyle(.roundedBorder).font(.thMono)

                Text("Backend Type").font(.thLabel).foregroundColor(Theme.creamDim)
                Picker("", selection: $backend) {
                    ForEach(EngineBackend.allCases, id: \.self) { b in
                        Text(b.displayName).tag(b)
                    }
                }

                Text("Base URL").font(.thLabel).foregroundColor(Theme.creamDim)
                TextField("e.g. http://192.168.1.50:11434", text: $baseURL)
                    .textFieldStyle(.roundedBorder).font(.thMono)

                Text("API Key Env Var (optional)").font(.thLabel).foregroundColor(Theme.creamDim)
                TextField("e.g. OLLAMA_API_KEY", text: $apiKeyEnv)
                    .textFieldStyle(.roundedBorder).font(.thMono)

                Toggle("Remote endpoint (network)", isOn: $isRemote)
                    .font(.thBody).foregroundColor(Theme.cream)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .font(.thSmall).foregroundColor(Theme.creamDim)
                Button("Add Engine") {
                    let engine = EngineEndpoint(
                        name: name, backend: backend, baseURL: baseURL,
                        apiKeyEnv: apiKeyEnv.isEmpty ? nil : apiKeyEnv,
                        isRemote: isRemote
                    )
                    state.addEngine(engine)
                    isPresented = false
                }
                .font(.thBody).foregroundColor(Theme.accent)
                .disabled(name.isEmpty || baseURL.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .background(Theme.bg)
    }
}

// MARK: - Add Route Sheet

private struct AddRouteSheet: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool
    @State private var pattern = ""
    @State private var engineName = ""
    @State private var stripPrefix = false
    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Model Route").font(.thHeader).foregroundColor(Theme.creamBold)

            Text("Map a model name prefix to an engine. When a request contains a model name starting with this pattern, it routes to the selected engine.")
                .font(.thSmall).foregroundColor(Theme.creamDim)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pattern (prefix)").font(.thLabel).foregroundColor(Theme.creamDim)
                TextField("e.g. ollama/, my-lab/, llama-", text: $pattern)
                    .textFieldStyle(.roundedBorder).font(.thMono)

                Text("Engine").font(.thLabel).foregroundColor(Theme.creamDim)
                Picker("", selection: $engineName) {
                    ForEach(state.engineEndpoints.filter(\.enabled)) { engine in
                        Text(engine.name).tag(engine.name)
                    }
                }

                Toggle("Strip prefix when forwarding", isOn: $stripPrefix)
                    .font(.thBody).foregroundColor(Theme.cream)
                Text("e.g. \"ollama/mistral\" → \"mistral\"")
                    .font(.thSmall).foregroundColor(Theme.muted)

                Text("Description (optional)").font(.thLabel).foregroundColor(Theme.creamDim)
                TextField("e.g. Home lab Ollama models", text: $description)
                    .textFieldStyle(.roundedBorder).font(.thBody)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .font(.thSmall).foregroundColor(Theme.creamDim)
                Button("Add Route") {
                    let route = ModelRouteMapping(
                        pattern: pattern, engineName: engineName,
                        stripPrefix: stripPrefix,
                        description: description.isEmpty ? nil : description
                    )
                    state.addModelRoute(route)
                    isPresented = false
                }
                .font(.thBody).foregroundColor(Theme.accent)
                .disabled(pattern.isEmpty || engineName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .background(Theme.bg)
    }
}
