import SwiftUI
import EngraveGovernance

// MARK: - Dashboard Panel (Main Container)

struct DashboardPanel: View {
    @ObservedObject var state: AppState
    @State private var editMode = false
    @State private var showAddPanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            dashboardHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().background(Theme.muted.opacity(0.3))

            // Panel grid
            ScrollView {
                VStack(spacing: 12) {
                    let visible = state.dashboardConfig.panels.filter(\.visible)
                    ForEach(visible) { panel in
                        DashboardCardWrapper(
                            panel: panel,
                            editMode: editMode,
                            state: state,
                            onRemove: { removePanel(panel) }
                        )
                    }
                    if visible.isEmpty {
                        emptyDashboard
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showAddPanel) {
            AddPanelSheet(isPresented: $showAddPanel) { panelType in
                addPanel(panelType)
            }
        }
    }

    // MARK: Header

    private var dashboardHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.thIcon)
                .foregroundStyle(Theme.accent)
            Text("Dashboard")
                .font(.thTitle)
                .foregroundStyle(Theme.creamBold)

            Text(state.dashboardConfig.activeLayout)
                .font(.thSmall)
                .foregroundStyle(Theme.creamDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.bgHover.cornerRadius(4))

            Spacer()

            Button {
                showAddPanel = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("Add Panel")
                }
                .font(.thLabel)
                .foregroundStyle(Theme.accentBlue)
            }
            .buttonStyle(.plain)

            Button {
                editMode.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: editMode ? "checkmark.circle.fill" : "pencil.circle")
                    Text(editMode ? "Done" : "Edit")
                }
                .font(.thLabel)
                .foregroundStyle(editMode ? Theme.accentLime : Theme.cream)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyDashboard: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.muted)
            Text("No panels configured.")
                .font(.thBody)
                .foregroundStyle(Theme.creamDim)
            Text("Click \"Add Panel\" to get started.")
                .font(.thSmall)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: Actions

    private func addPanel(_ type: DashboardPanelType) {
        state.dashboardConfig.panels.append(DashboardPanelConfig(type: type))
    }

    private func removePanel(_ panel: DashboardPanelConfig) {
        state.dashboardConfig.panels.removeAll { $0.id == panel.id }
    }
}

// MARK: - Card Wrapper

private struct DashboardCardWrapper: View {
    let panel: DashboardPanelConfig
    let editMode: Bool
    @ObservedObject var state: AppState
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack(spacing: 8) {
                Image(systemName: panel.type.icon)
                    .font(.thIcon)
                    .foregroundStyle(Theme.accentBlue)
                Text(panel.type.rawValue)
                    .font(.thHeader)
                    .foregroundStyle(Theme.creamBold)

                Spacer()

                BreakoutButton(id: "dashboard-\(panel.type.rawValue)", title: panel.type.rawValue) {
                    panelContent(for: panel.type)
                }

                if editMode {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.thIcon)
                            .foregroundStyle(Theme.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.bgCard)

            Divider().background(Theme.muted.opacity(0.2))

            // Content area
            panelContent(for: panel.type)
                .frame(minHeight: 150)
                .padding(12)
        }
        .background(Theme.bgCard)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.muted.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func panelContent(for type: DashboardPanelType) -> some View {
        switch type {
        case .agentActivity:
            AgentActivityFeedView(events: state.agentActivityFeed)
        case .governanceEvents:
            GovernanceEventsPanel(events: state.governanceEvents)
        case .worktreeStatus:
            WorktreeStatusPanel(entries: state.worktreeStatus)
        case .fileChangeFeed:
            FileChangeFeedPanel(events: state.fileChangeFeed)
        case .merkleDSGLog:
            MerkleDSGLogPanel(entries: Binding(
                get: { state.merkleDSGLog },
                set: { state.merkleDSGLog = $0 }
            ))
        case .servicesMonitor:
            ServicesMonitorPanel(state: state)
        case .taskDAGViewer:
            TaskDAGViewerPanel(state: state)
        case .diffViewer:
            DiffViewerPanel()
        case .activeAgents:
            ActiveAgentsPanel(state: state)
        case .ungovernedAgents:
            UngovernedAgentsPanel(state: state)
        }
    }
}

// MARK: - Add Panel Sheet

private struct AddPanelSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (DashboardPanelType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add Panel")
                    .font(.thTitle)
                    .foregroundStyle(Theme.creamBold)
                Spacer()
                Button("Close") { isPresented = false }
                    .font(.thLabel)
                    .foregroundStyle(Theme.creamDim)
                    .buttonStyle(.plain)
            }
            .padding(16)

            Divider().background(Theme.muted.opacity(0.3))

            List {
                ForEach(DashboardPanelType.allCases, id: \.self) { panelType in
                    Button {
                        onAdd(panelType)
                        isPresented = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: panelType.icon)
                                .font(.thIcon)
                                .foregroundStyle(Theme.accentBlue)
                                .frame(width: 24)
                            Text(panelType.rawValue)
                                .font(.thBody)
                                .foregroundStyle(Theme.cream)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .font(.thSmall)
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.bgCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
        }
        .frame(width: 360, height: 400)
        .background(Theme.bg)
    }
}

// MARK: - Agent Activity Feed

struct AgentActivityFeedView: View {
    let events: [AgentActivityEvent]
    @State private var filterText = ""

    private var filtered: [AgentActivityEvent] {
        guard !filterText.isEmpty else { return events }
        let query = filterText.lowercased()
        return events.filter {
            $0.agentId.lowercased().contains(query)
            || $0.action.lowercased().contains(query)
            || $0.detail.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Filter
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.thSmall)
                    .foregroundStyle(Theme.muted)
                TextField("Filter activity...", text: $filterText)
                    .font(.thSmall)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.cream)
            }
            .padding(6)
            .background(Theme.bgHover.cornerRadius(6))

            if filtered.isEmpty {
                emptyState("No agent activity recorded yet.", icon: "list.bullet.rectangle")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { event in
                            agentActivityRow(event)
                        }
                    }
                }
            }
        }
    }

    private func agentActivityRow(_ event: AgentActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Risk dot
            Circle()
                .fill(riskColor(event.risk))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            // Timestamp
            Text(shortTimestamp(event.timestamp))
                .font(.thMonoSmall)
                .foregroundStyle(Theme.muted)
                .frame(width: 60, alignment: .leading)

            // Agent badge
            Text(event.agentId)
                .font(.thBadge)
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.bgHover.cornerRadius(4))

            // Action
            Text(event.action)
                .font(.thBody)
                .foregroundStyle(Theme.cream)

            // Detail
            Text(event.detail)
                .font(.thSmall)
                .foregroundStyle(Theme.creamDim)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Governance Events Panel

struct GovernanceEventsPanel: View {
    let events: [GovernanceEvent]
    @State private var filterText = ""
    @State private var decisionFilter = "All"

    private let decisionFilters = ["All", "Allow", "Warn", "Block"]

    private var filtered: [GovernanceEvent] {
        var result = events
        if decisionFilter != "All" {
            let key = decisionFilter.lowercased()
            result = result.filter { $0.decision.lowercased() == key }
        }
        if !filterText.isEmpty {
            let query = filterText.lowercased()
            result = result.filter {
                ($0.ruleName ?? "").lowercased().contains(query)
                || $0.eventType.lowercased().contains(query)
                || ($0.reason ?? "").lowercased().contains(query)
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Filters
            HStack(spacing: 8) {
                Picker("", selection: $decisionFilter) {
                    ForEach(decisionFilters, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.thSmall)
                        .foregroundStyle(Theme.muted)
                    TextField("Search events...", text: $filterText)
                        .font(.thSmall)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.cream)
                }
                .padding(6)
                .background(Theme.bgHover.cornerRadius(6))
            }

            if filtered.isEmpty {
                emptyState(
                    "No governance events. Enable governance to start recording.",
                    icon: "shield.checkered"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { event in
                            governanceEventRow(event)
                        }
                    }
                }
            }
        }
    }

    private func governanceEventRow(_ event: GovernanceEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(decisionColor(event.decision))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            Text(event.decision.capitalized)
                .font(.thBadge)
                .foregroundStyle(decisionColor(event.decision))
                .frame(width: 50, alignment: .leading)

            Text(event.eventType)
                .font(.thBody)
                .foregroundStyle(Theme.cream)

            if let ruleName = event.ruleName {
                Text(ruleName)
                    .font(.thSmall)
                    .foregroundStyle(Theme.teal)
            }

            Spacer()

            Text(shortTimestamp(event.timestamp))
                .font(.thMonoSmall)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Worktree Status Panel

struct WorktreeStatusPanel: View {
    let entries: [WorktreeEntry]
    @State private var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    refreshing = true
                    // Placeholder: in production, populate from `git worktree list`
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        refreshing = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if refreshing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.thLabel)
                    .foregroundStyle(Theme.accentBlue)
                }
                .buttonStyle(.plain)
                .disabled(refreshing)
            }

            if entries.isEmpty {
                emptyState("No git worktrees detected.", icon: "arrow.triangle.branch")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            worktreeRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func worktreeRow(_ entry: WorktreeEntry) -> some View {
        HStack(spacing: 8) {
            // Has-changes dot
            if entry.hasChanges {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(Theme.muted.opacity(0.3))
                    .frame(width: 8, height: 8)
            }

            // Branch name
            Text(entry.branch)
                .font(.thMono)
                .foregroundStyle(Theme.teal)

            // Path
            Text(entry.path)
                .font(.thSmall)
                .foregroundStyle(Theme.creamDim)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Agent label
            if let agentId = entry.agentId {
                Text(agentId)
                    .font(.thBadge)
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.bgHover.cornerRadius(4))
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - File Change Feed Panel

struct FileChangeFeedPanel: View {
    let events: [FileChangeEvent]

    var body: some View {
        if events.isEmpty {
            emptyState("No file changes recorded.", icon: "doc.badge.clock")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { event in
                        fileChangeRow(event)
                    }
                }
            }
        }
    }

    private func fileChangeRow(_ event: FileChangeEvent) -> some View {
        HStack(spacing: 8) {
            // Change type badge
            Text(event.changeType.uppercased())
                .font(.thBadge)
                .foregroundStyle(changeTypeColor(event.changeType))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(changeTypeColor(event.changeType).opacity(0.15).cornerRadius(4))

            // Path
            Text(event.path)
                .font(.thMono)
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Agent ID
            if let agentId = event.agentId {
                Text(agentId)
                    .font(.thBadge)
                    .foregroundStyle(Theme.creamDim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.bgHover.cornerRadius(3))
            }

            // Timestamp
            Text(shortTimestamp(event.timestamp))
                .font(.thMonoSmall)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Merkle DSG Log Panel

struct MerkleDSGLogPanel: View {
    @Binding var entries: [MerkleDSGEntry]
    @State private var verifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    verifying = true
                    // Placeholder: toggle verified on all entries
                    for i in entries.indices {
                        entries[i].verified = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        verifying = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if verifying {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Image(systemName: "checkmark.shield")
                        Text("Verify Chain")
                    }
                    .font(.thLabel)
                    .foregroundStyle(Theme.accentLime)
                }
                .buttonStyle(.plain)
                .disabled(verifying || entries.isEmpty)
            }

            if entries.isEmpty {
                emptyState("Audit log is empty.", icon: "link")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            merkleRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func merkleRow(_ entry: MerkleDSGEntry) -> some View {
        HStack(spacing: 8) {
            // Sequence
            Text("#\(entry.sequence)")
                .font(.thMonoSmall)
                .foregroundStyle(Theme.accentBlue)
                .frame(width: 40, alignment: .trailing)

            // Event type
            Text(entry.eventType)
                .font(.thBody)
                .foregroundStyle(Theme.cream)

            // Actor
            Text(entry.actor)
                .font(.thSmall)
                .foregroundStyle(Theme.teal)

            // Content hash (first 12 chars)
            if !entry.contentHash.isEmpty {
                let hashPrefix = String(entry.contentHash.prefix(12))
                Text(hashPrefix)
                    .font(.thMonoSmall)
                    .foregroundStyle(Theme.muted)
            }

            // Parent count
            if !entry.parentIds.isEmpty {
                Text("\(entry.parentIds.count)p")
                    .font(.thBadge)
                    .foregroundStyle(Theme.creamDim)
            }

            Spacer()

            // Verified badge
            if entry.verified {
                Image(systemName: "checkmark.circle.fill")
                    .font(.thSmall)
                    .foregroundStyle(Theme.green)
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.thSmall)
                    .foregroundStyle(Theme.muted)
            }

            // Timestamp
            Text(shortTimestamp(entry.timestamp))
                .font(.thMonoSmall)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Services Monitor Panel

struct ServicesMonitorPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        let hasAny = state.serverStatus.state != .stopped || state.interposerRunning
        if !hasAny && !state.inference.isLoaded {
            emptyState("Services not started.", icon: "server.rack")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // MLX status
                mlxStatusRow

                Divider().background(Theme.muted.opacity(0.2))

                // Interposer status
                interposerStatusRow

                // Log snippet
                if !state.interposerLog.isEmpty {
                    Divider().background(Theme.muted.opacity(0.2))
                    logSnippet
                }
            }
        }
    }

    private var mlxStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(mlxStatusColor)
                .frame(width: 10, height: 10)

            Text("MLX Inference")
                .font(.thBodyMedium)
                .foregroundStyle(Theme.creamBold)

            Spacer()

            if let name = state.inference.loadedModelName ?? state.serverStatus.modelName {
                Text(name)
                    .font(.thMono)
                    .foregroundStyle(Theme.teal)
                    .lineLimit(1)
            }

            if state.serverStatus.port > 0 {
                Text(":\(state.serverStatus.port)")
                    .font(.thMonoSmall)
                    .foregroundStyle(Theme.muted)
            }

            if state.inference.tokensPerSecond > 0 {
                Text(String(format: "%.1f tok/s", state.inference.tokensPerSecond))
                    .font(.thMonoSmall)
                    .foregroundStyle(Theme.accentLime)
            }
        }
    }

    private var mlxStatusColor: Color {
        if state.inference.isLoaded || state.serverStatus.state == .running {
            return Theme.green
        } else if state.serverStatus.state == .starting {
            return Theme.yellow
        } else {
            return Theme.red
        }
    }

    private var interposerStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.interposerRunning ? Theme.green : Theme.red)
                .frame(width: 10, height: 10)

            Text("Interposer")
                .font(.thBodyMedium)
                .foregroundStyle(Theme.creamBold)

            Spacer()

            Text(state.interposerRunning ? "Running" : "Stopped")
                .font(.thSmall)
                .foregroundStyle(state.interposerRunning ? Theme.creamDim : Theme.muted)
        }
    }

    private var logSnippet: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent Log")
                .font(.thLabel)
                .foregroundStyle(Theme.creamDim)
                .padding(.bottom, 2)

            let lines = Array(state.interposerLog.suffix(5))
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.thMonoSmall)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - Task DAG Viewer Panel

struct TaskDAGViewerPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        // Show InlineDAGView if uiaTaskGraph is available, otherwise empty state
        if state.uiaTaskGraph != nil {
            InlineDAGView(graph: Binding(
                get: { state.uiaTaskGraph! },
                set: { state.uiaTaskGraph = $0 }
            ))
        } else {
            emptyState(
                "No task graph. Use UIA Chat to decompose a task.",
                icon: "point.3.connected.trianglepath.dotted"
            )
        }
    }
}

// MARK: - Diff Viewer Panel

struct DiffViewerPanel: View {
    @State private var beforeText = ""
    @State private var afterText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste or load files to compare")
                .font(.thSmall)
                .foregroundStyle(Theme.creamDim)

            if beforeText.isEmpty && afterText.isEmpty {
                emptyDiffState
            } else {
                diffEditors
            }
        }
    }

    private var emptyDiffState: some View {
        VStack(spacing: 8) {
            diffEditors
        }
    }

    private var diffEditors: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Before")
                    .font(.thLabel)
                    .foregroundStyle(Theme.creamDim)
                TextEditor(text: $beforeText)
                    .font(.thMono)
                    .foregroundStyle(Theme.cream)
                    .scrollContentBackground(.hidden)
                    .background(Theme.bgHover.cornerRadius(4))
                    .frame(minHeight: 120)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("After")
                    .font(.thLabel)
                    .foregroundStyle(Theme.creamDim)
                TextEditor(text: $afterText)
                    .font(.thMono)
                    .foregroundStyle(Theme.cream)
                    .scrollContentBackground(.hidden)
                    .background(Theme.bgHover.cornerRadius(4))
                    .frame(minHeight: 120)
            }
        }
    }
}

// MARK: - Active Agents Panel

struct ActiveAgentsPanel: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.agentActivityFeed.isEmpty {
                Text("No active agents. Launch a runner to see governed agents here.")
                    .font(.thSmall).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                let agents = Dictionary(grouping: state.agentActivityFeed, by: \.agentId)
                ForEach(Array(agents.keys.sorted()), id: \.self) { agentId in
                    if let latest = agents[agentId]?.last {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.green).frame(width: 8, height: 8)
                            Text(agentId).font(.thBody).foregroundColor(Theme.cream)
                            Spacer()
                            Text(latest.action).font(.thSmall).foregroundColor(Theme.creamDim)
                        }
                        .padding(6).background(Theme.bgCard).cornerRadius(6)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Ungoverned Agents Panel

struct UngovernedAgentsPanel: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents running outside Engrave governance control.")
                .font(.thSmall).foregroundColor(Theme.muted)
            Text("Detection requires process scanning (future feature).")
                .font(.thSmall).foregroundColor(Theme.yellow)
                .padding(8).background(Theme.yellow.opacity(0.1)).cornerRadius(6)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

// MARK: - Shared Helpers

/// Risk level color
private func riskColor(_ risk: String) -> Color {
    switch risk.lowercased() {
    case "safe":   return Theme.green
    case "warn":   return Theme.yellow
    case "danger": return Theme.red
    default:       return Theme.muted
    }
}

/// Governance decision color
private func decisionColor(_ decision: String) -> Color {
    switch decision.lowercased() {
    case "allow":   return Theme.green
    case "warn":    return Color.orange
    case "block":   return Theme.red
    case "modify":  return Theme.yellow
    case "rewrite": return Theme.blue
    default:        return Theme.muted
    }
}

/// File change type color
private func changeTypeColor(_ changeType: String) -> Color {
    switch changeType.lowercased() {
    case "add":    return Theme.green
    case "modify": return Theme.yellow
    case "delete": return Theme.red
    default:       return Theme.muted
    }
}

/// Short timestamp formatter
private func shortTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

/// Reusable empty state view
@ViewBuilder
private func emptyState(_ message: String, icon: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: icon)
            .font(.system(size: 24))
            .foregroundStyle(Theme.muted)
        Text(message)
            .font(.thSmall)
            .foregroundStyle(Theme.creamDim)
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, minHeight: 100)
}
