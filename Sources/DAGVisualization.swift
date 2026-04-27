import SwiftUI

// MARK: - Inline DAG View

/// Renders a UIATaskGraph as a topologically-sorted, left-to-right DAG.
/// Nodes are arranged in columns (layers) with edges drawn between them.
struct InlineDAGView: View {
    @Binding var graph: UIATaskGraph

    var body: some View {
        let layout = computeLayout()

        ScrollView(.horizontal, showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                // Edges
                ForEach(graph.edges) { edge in
                    if let fromPos = layout.positions[edge.from],
                       let toPos = layout.positions[edge.to] {
                        Path { path in
                            let startX = fromPos.x + DAGConstants.nodeWidth
                            let startY = fromPos.y + DAGConstants.nodeHeight / 2
                            let endX = toPos.x
                            let endY = toPos.y + DAGConstants.nodeHeight / 2
                            path.move(to: CGPoint(x: startX, y: startY))
                            path.addLine(to: CGPoint(x: endX, y: endY))
                        }
                        .stroke(Theme.muted.opacity(0.5), lineWidth: 1.5)
                    }
                }

                // Nodes
                ForEach(graph.nodes) { node in
                    if let pos = layout.positions[node.id] {
                        DAGNodeView(node: node)
                            .offset(x: pos.x, y: pos.y)
                    }
                }
            }
            .frame(
                width: layout.totalSize.width,
                height: layout.totalSize.height
            )
            .padding(DAGConstants.padding)
        }
        .background(Theme.bgCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Layout Computation

    private struct LayoutResult {
        var positions: [UUID: CGPoint]
        var totalSize: CGSize
    }

    private func computeLayout() -> LayoutResult {
        let nodes = graph.nodes
        let edges = graph.edges

        guard !nodes.isEmpty else {
            return LayoutResult(positions: [:], totalSize: .zero)
        }

        // Build adjacency and in-degree maps
        var adjacency: [UUID: [UUID]] = [:]
        var inDegree: [UUID: Int] = [:]

        for node in nodes {
            adjacency[node.id] = []
            inDegree[node.id] = 0
        }
        for edge in edges {
            adjacency[edge.from, default: []].append(edge.to)
            inDegree[edge.to, default: 0] += 1
        }

        // Kahn's algorithm — topological sort with layer assignment
        var layers: [[UUID]] = []
        var queue: [UUID] = nodes.filter { inDegree[$0.id, default: 0] == 0 }.map(\.id)

        var visited = Set<UUID>()

        while !queue.isEmpty {
            layers.append(queue)
            visited.formUnion(queue)
            var nextQueue: [UUID] = []
            for nodeID in queue {
                for neighbor in adjacency[nodeID, default: []] {
                    inDegree[neighbor, default: 1] -= 1
                    if inDegree[neighbor, default: 0] == 0 && !visited.contains(neighbor) {
                        nextQueue.append(neighbor)
                    }
                }
            }
            queue = nextQueue
        }

        // Place any unvisited nodes (cycles or disconnected) into a final layer
        let remaining = nodes.filter { !visited.contains($0.id) }.map(\.id)
        if !remaining.isEmpty {
            layers.append(remaining)
        }

        // Compute positions: layers left-to-right, nodes stacked top-to-bottom
        var positions: [UUID: CGPoint] = [:]
        var maxY: CGFloat = 0

        for (layerIndex, layer) in layers.enumerated() {
            let x = CGFloat(layerIndex) * (DAGConstants.nodeWidth + DAGConstants.horizontalSpacing)
            for (nodeIndex, nodeID) in layer.enumerated() {
                let y = CGFloat(nodeIndex) * (DAGConstants.nodeHeight + DAGConstants.verticalSpacing)
                positions[nodeID] = CGPoint(x: x, y: y)
                maxY = max(maxY, y + DAGConstants.nodeHeight)
            }
        }

        let totalWidth = CGFloat(layers.count) * (DAGConstants.nodeWidth + DAGConstants.horizontalSpacing) - DAGConstants.horizontalSpacing
        let totalHeight = maxY

        return LayoutResult(
            positions: positions,
            totalSize: CGSize(
                width: max(totalWidth, 0),
                height: max(totalHeight, 0)
            )
        )
    }
}

// MARK: - DAG Node View

/// Individual node rectangle with status color, title, and complexity badge.
struct DAGNodeView: View {
    let node: UIATaskNode

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(statusColor.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(statusColor, lineWidth: 1.5)
                )
                .frame(width: DAGConstants.nodeWidth, height: DAGConstants.nodeHeight)

            // Title
            Text(node.title)
                .font(.thSmall)
                .foregroundStyle(Theme.cream)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: DAGConstants.nodeWidth - 8, height: DAGConstants.nodeHeight)

            // Complexity badge
            Text(node.complexity.rawValue.prefix(3).uppercased())
                .font(.thBadge)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(statusColor))
                .offset(x: -4, y: 4)
        }
        .frame(width: DAGConstants.nodeWidth, height: DAGConstants.nodeHeight)
    }

    private var statusColor: Color {
        switch node.status {
        case .pending:   return Theme.muted
        case .running:   return Theme.accentBlue
        case .completed: return Theme.green
        case .failed:    return Theme.red
        }
    }
}

// MARK: - Constants

private enum DAGConstants {
    static let nodeWidth: CGFloat = 120
    static let nodeHeight: CGFloat = 40
    static let horizontalSpacing: CGFloat = 40
    static let verticalSpacing: CGFloat = 16
    static let padding: CGFloat = 12
}
