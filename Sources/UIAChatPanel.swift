import SwiftUI

// MARK: - UIA Chat Panel

/// Chat interface for the UIA orchestrator. Allows users to decompose tasks,
/// view DAG visualizations inline, and interact with the unified intelligence layer.
struct UIAChatPanel: View {
    @ObservedObject var state: AppState

    @State private var inputText = ""
    @State private var showEmptyActions = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.muted.opacity(0.3))

            if state.uiaChatMessages.isEmpty {
                emptyState
            } else {
                messageList
            }

            if state.uiaIsProcessing {
                processingIndicator
            }

            Divider().background(Theme.muted.opacity(0.3))
            inputBar
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.cream)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("UIA Chat")
                    .font(.thHeader)
                    .foregroundStyle(Theme.creamBold)
                Text("Unified Intelligence Architecture")
                    .font(.thSmall)
                    .foregroundStyle(Theme.creamDim)
            }
            Spacer()
            if !state.uiaChatMessages.isEmpty {
                Button {
                    // No-op placeholder for future clear action
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.thSmall)
                        .foregroundStyle(Theme.creamDim)
                }
                .buttonStyle(.borderless)
                .help("Reset conversation")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(state.uiaChatMessages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: state.uiaChatMessages.count) { _ in
                if let last = state.uiaChatMessages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.accent.opacity(0.6))

                Text("UIA Orchestrator")
                    .font(.thTitle)
                    .foregroundStyle(Theme.creamBold)

                Text("Decompose complex tasks into manageable sub-tasks, visualize dependencies, and route work to the right models.")
                    .font(.thBody)
                    .foregroundStyle(Theme.creamDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 10) {
                quickActionButton("Decompose a task", icon: "square.grid.3x3.topleft.filled")
                quickActionButton("Explain task routing", icon: "arrow.triangle.branch")
                quickActionButton("Show model capabilities", icon: "cpu")
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickActionButton(_ title: String, icon: String) -> some View {
        Button {
            inputText = title
            sendMessage()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.thSmall)
                Text(title)
                    .font(.thSmall)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.bgCard)
            .foregroundStyle(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.muted.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            PulsingDotView()
            Text("Thinking...")
                .font(.thSmall)
                .foregroundStyle(Theme.creamDim)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask UIA to decompose a task...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.thBody)
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onSubmit { sendMessage() }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.thBody)
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.muted : Theme.accent)
            }
            .buttonStyle(.borderless)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        state.sendUIAMessage(trimmed)
    }
}

// MARK: - Chat Bubble View

/// Renders a single chat message with role-based alignment and styling.
struct ChatBubbleView: View {
    let message: UIAChatMessage

    private var alignment: HorizontalAlignment {
        switch message.role {
        case .user: return .trailing
        case .assistant: return .leading
        case .system: return .center
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Theme.accent.opacity(0.2)
        case .assistant: return Theme.bgCard
        case .system: return Theme.muted.opacity(0.3)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user: return Theme.cream
        case .assistant: return Theme.cream
        case .system: return Theme.muted
        }
    }

    private var frameAlignment: Alignment {
        switch message.role {
        case .user: return .trailing
        case .assistant: return .leading
        case .system: return .center
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            // Role label
            if message.role != .system {
                Text(message.role == .user ? "You" : "UIA")
                    .font(.thBadge)
                    .foregroundStyle(Theme.creamDim)
            }

            // Message content
            Text(message.content)
                .font(.thBody)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Inline task graph if present
            if let graphJSON = message.taskGraphJSON,
               let data = graphJSON.data(using: .utf8),
               let graph = try? JSONDecoder().decode(UIATaskGraph.self, from: data) {
                inlineTaskGraphView(graph)
            }

            // Timestamp
            Text(message.timestamp, style: .time)
                .font(.thSmall)
                .foregroundStyle(Theme.creamDim.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    /// Minimal inline DAG representation for messages that include task graph data.
    @ViewBuilder
    private func inlineTaskGraphView(_ graph: UIATaskGraph) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.thSmall)
                    .foregroundStyle(Theme.accentBlue)
                Text("Task Graph")
                    .font(.thLabel)
                    .foregroundStyle(Theme.accentBlue)
                Text("(\(graph.nodes.count) nodes)")
                    .font(.thSmall)
                    .foregroundStyle(Theme.creamDim)
            }

            ForEach(graph.nodes) { node in
                HStack(spacing: 6) {
                    statusIcon(for: node.status)
                    Text(node.title)
                        .font(.thSmall)
                        .foregroundStyle(Theme.cream)
                    Spacer()
                    if let model = node.assignedModel {
                        Text(model)
                            .font(.thMonoSmall)
                            .foregroundStyle(Theme.creamDim)
                    }
                    complexityBadge(node.complexity)
                }
            }
        }
        .padding(10)
        .background(Theme.bgHover.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusIcon(for status: TaskNodeStatus) -> some View {
        let (icon, color): (String, Color) = {
            switch status {
            case .pending:   return ("circle", Theme.muted)
            case .running:   return ("circle.dotted", Theme.yellow)
            case .completed: return ("checkmark.circle.fill", Theme.green)
            case .failed:    return ("xmark.circle.fill", Theme.red)
            }
        }()
        return Image(systemName: icon)
            .font(.thSmall)
            .foregroundStyle(color)
    }

    private func complexityBadge(_ complexity: TaskComplexity) -> some View {
        let color: Color = {
            switch complexity {
            case .trivial:  return Theme.muted
            case .simple:   return Theme.green
            case .medium:   return Theme.yellow
            case .complex:  return Theme.accent
            case .critical: return Theme.red
            }
        }()
        return Text(complexity.rawValue)
            .font(.thBadge)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Pulsing Dot

/// Animated pulsing dot used as a "thinking" indicator.
struct PulsingDotView: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.3 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.4)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Preview

#if DEBUG
struct UIAChatPanel_Previews: PreviewProvider {
    static var previews: some View {
        UIAChatPanel(state: AppState())
            .frame(width: 460, height: 600)
    }
}
#endif
