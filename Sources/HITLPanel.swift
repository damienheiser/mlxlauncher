import SwiftUI

// MARK: - HITL Panel

/// Human-in-the-loop interception feed. Shows pending interceptions with countdown
/// timers, allows approve/deny/steer decisions, and displays resolved history.
struct HITLPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.muted.opacity(0.3))
            configBar
            Divider().background(Theme.muted.opacity(0.3))

            if state.hitlInterceptions.isEmpty {
                emptyState
            } else {
                interceptionList
            }
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.cream)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Human In The Loop")
                    .font(.thHeader)
                    .foregroundStyle(Theme.creamBold)
            }

            statusBadge

            Spacer()

            Toggle(isOn: Binding(
                get: { state.hitlEnabled },
                set: { state.hitlEnabled = $0 }
            )) {
                Text("Enabled")
                    .font(.thSmall)
                    .foregroundStyle(Theme.creamDim)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusBadge: some View {
        let isActive = state.hitlEnabled
        return Text(isActive ? "Active" : "Disabled")
            .font(.thBadge)
            .foregroundStyle(isActive ? Theme.green : Theme.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isActive ? Theme.green : Theme.muted).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Config Bar

    private var configBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("Delay")
                    .font(.thSmall)
                    .foregroundStyle(Theme.creamDim)
                Slider(
                    value: Binding(
                        get: { Double(state.hitlTimeDelaySeconds) },
                        set: { state.hitlTimeDelaySeconds = Int($0) }
                    ),
                    in: 0...30,
                    step: 1
                )
                .frame(maxWidth: 140)
                Text("\(state.hitlTimeDelaySeconds)s")
                    .font(.thMono)
                    .foregroundStyle(Theme.cream)
                    .frame(width: 30, alignment: .trailing)
            }

            Spacer()

            let pendingCount = state.hitlInterceptions.filter { $0.status == .pending }.count
            if pendingCount > 0 {
                HStack(spacing: 4) {
                    Text("\(pendingCount)")
                        .font(.thBadge)
                        .foregroundStyle(.white)
                        .frame(minWidth: 18)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Theme.red)
                        .clipShape(Capsule())
                    Text("pending")
                        .font(.thSmall)
                        .foregroundStyle(Theme.creamDim)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.bgCard.opacity(0.5))
    }

    // MARK: - Interception List

    private var interceptionList: some View {
        let pending = state.hitlInterceptions
            .filter { $0.status == .pending }
            .sorted { $0.expiresAt < $1.expiresAt }
        let resolved = state.hitlInterceptions
            .filter { $0.status != .pending }
            .sorted { $0.timestamp > $1.timestamp }

        return ScrollView {
            LazyVStack(spacing: 8) {
                if !pending.isEmpty {
                    sectionHeader("Pending", count: pending.count, color: Theme.yellow)
                    ForEach(pending) { interception in
                        HITLInterceptionRow(interception: interception, state: state)
                    }
                }

                if !resolved.isEmpty {
                    sectionHeader("Resolved", count: resolved.count, color: Theme.muted)
                        .padding(.top, pending.isEmpty ? 0 : 8)
                    ForEach(resolved) { interception in
                        HITLInterceptionRow(interception: interception, state: state)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.thLabel)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.thBadge)
                .foregroundStyle(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "shield.checkered")
                .font(.system(size: 32))
                .foregroundStyle(Theme.muted.opacity(0.5))
            Text("No interceptions")
                .font(.thBody)
                .foregroundStyle(Theme.creamDim)
            Text("Tool calls requiring review will appear here.")
                .font(.thSmall)
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Interception Row

/// Individual interception card with countdown ring, severity stripe, and action buttons.
struct HITLInterceptionRow: View {
    let interception: HITLInterception
    @ObservedObject var state: AppState

    @State private var isExpanded = false
    @State private var showSteerField = false
    @State private var steerText = ""

    private var severityColor: Color {
        switch interception.severity {
        case "block": return Theme.red
        case "warn":  return Theme.yellow
        default:      return Theme.accentBlue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Severity stripe
            Rectangle()
                .fill(severityColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                // Top row: tool name + countdown
                HStack {
                    Text(interception.toolName)
                        .font(.thBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.cream)

                    Spacer()

                    if interception.status == .pending {
                        CountdownRingView(expiresAt: interception.expiresAt)
                    } else {
                        resolvedBadge
                    }
                }

                // Reason
                Text(interception.reason)
                    .font(.thSmall)
                    .foregroundStyle(Theme.creamDim)
                    .lineLimit(2)

                // Tool input preview
                toolInputPreview

                // Action buttons (pending only)
                if interception.status == .pending {
                    actionButtons
                }

                // Steer text field
                if showSteerField && interception.status == .pending {
                    steerInput
                }
            }
            .padding(10)
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(severityColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Tool Input Preview

    private var toolInputPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("Input")
                        .font(.thSmall)
                    Spacer()
                }
                .foregroundStyle(Theme.creamDim)
            }
            .buttonStyle(.borderless)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(interception.toolInput)
                        .font(.thMonoSmall)
                        .foregroundStyle(Theme.creamDim)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(6)
                .background(Theme.bg.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(String(interception.toolInput.prefix(100)) + (interception.toolInput.count > 100 ? "..." : ""))
                    .font(.thMonoSmall)
                    .foregroundStyle(Theme.creamDim)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                state.handleHITLDecision(id: interception.id, decision: .allowed, steerDirective: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Allow")
                        .font(.thSmall)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.green.opacity(0.2))
                .foregroundStyle(Theme.green)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)

            Button {
                state.handleHITLDecision(id: interception.id, decision: .denied, steerDirective: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Deny")
                        .font(.thSmall)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.red.opacity(0.2))
                .foregroundStyle(Theme.red)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSteerField.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Steer")
                        .font(.thSmall)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accentBlue.opacity(0.2))
                .foregroundStyle(Theme.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)

            Spacer()
        }
    }

    // MARK: - Steer Input

    private var steerInput: some View {
        HStack(spacing: 8) {
            TextField("Steering directive...", text: $steerText)
                .textFieldStyle(.plain)
                .font(.thSmall)
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onSubmit { submitSteer() }

            Button {
                submitSteer()
            } label: {
                Text("Send")
                    .font(.thSmall)
                    .foregroundStyle(Theme.accentBlue)
            }
            .buttonStyle(.borderless)
            .disabled(steerText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submitSteer() {
        let trimmed = steerText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.handleHITLDecision(id: interception.id, decision: .steered, steerDirective: trimmed)
        steerText = ""
        showSteerField = false
    }

    // MARK: - Resolved Badge

    private var resolvedBadge: some View {
        let (text, color): (String, Color) = {
            switch interception.status {
            case .allowed: return ("Allowed", Theme.green)
            case .denied:  return ("Denied", Theme.red)
            case .steered: return ("Steered", Theme.accentBlue)
            case .expired: return ("Expired", Theme.muted)
            case .pending: return ("Pending", Theme.yellow)
            }
        }()
        return Text(text)
            .font(.thBadge)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Countdown Ring

/// Circular countdown indicator that updates every second via TimelineView.
/// Ring transitions green -> yellow -> red as time runs out.
struct CountdownRingView: View {
    let expiresAt: Date

    private let ringSize: CGFloat = 32
    private let lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = max(0, expiresAt.timeIntervalSince(context.date))
            let total = max(1, expiresAt.timeIntervalSince(expiresAt.addingTimeInterval(-60)))
            let fraction = remaining / total

            ZStack {
                // Background ring
                Circle()
                    .strokeBorder(Theme.muted.opacity(0.2), lineWidth: lineWidth)

                // Progress ring
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        ringColor(fraction: fraction),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Remaining seconds
                Text("\(Int(remaining))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ringColor(fraction: fraction))
            }
            .frame(width: ringSize, height: ringSize)
        }
    }

    private func ringColor(fraction: Double) -> Color {
        if fraction > 0.5 {
            return Theme.green
        } else if fraction > 0.2 {
            return Theme.yellow
        } else {
            return Theme.red
        }
    }
}

// MARK: - Preview

#if DEBUG
struct HITLPanel_Previews: PreviewProvider {
    static var previews: some View {
        HITLPanel(state: AppState())
            .frame(width: 420, height: 600)
    }
}
#endif
