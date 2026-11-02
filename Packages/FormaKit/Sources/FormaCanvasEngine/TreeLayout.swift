import FormaDomain
import FormaGeometry
import Foundation

public enum TreeLayout {
    public static func apply(to model: Diagram) throws -> [UUID: Rect] {
        if !model.panels.isEmpty {
            var result: [UUID: Rect] = [:]
            let groups: [(UUID?, Point)] =
                model.panels.filter { !$0.isLocked }.map {
                    (Optional($0.id), Point(x: $0.frame.x + 32, y: $0.frame.y + 64))
                } + [(nil, Point(x: 0, y: (model.panels.map { $0.frame.maxY }.max() ?? 0) + 96))]
            for (panelID, origin) in groups {
                let nodes = model.nodes.filter { $0.panelID == panelID }
                let ids = Set(nodes.map(\.id))
                let subset = Diagram(
                    nodes: nodes, edges: model.edges.filter { ids.contains($0.source) && ids.contains($0.target) })
                let frames = try apply(to: subset)
                for (id, var frame) in frames {
                    frame.x += origin.x
                    frame.y += origin.y
                    result[id] = frame
                }
            }
            return result
        }
        let nodes = model.nodes.filter { $0.kind != .text && !$0.isLocked && !$0.isHidden }
        let ids = Set(nodes.map(\.id))
        let edges = model.edges.filter { ids.contains($0.source) && ids.contains($0.target) }
        var parents: [UUID: Int] = [:]
        var children: [UUID: [UUID]] = [:]
        for edge in edges {
            parents[edge.target, default: 0] += 1
            guard parents[edge.target, default: 0] <= 1 else { throw DiagramError.layoutRequiresForest }
            children[edge.source, default: []].append(edge.target)
        }
        let roots = nodes.filter { parents[$0.id, default: 0] == 0 }
        var visited = Set<UUID>()
        var levels: [Int: [UUID]] = [:]
        var queue = roots.map { ($0.id, 0) }
        var cursor = 0
        while cursor < queue.count {
            let (id, depth) = queue[cursor]
            cursor += 1
            guard visited.insert(id).inserted else { throw DiagramError.layoutRequiresForest }
            levels[depth, default: []].append(id)
            queue += children[id, default: []].map { ($0, depth + 1) }
        }
        guard visited.count == nodes.count else { throw DiagramError.layoutRequiresForest }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var result: [UUID: Rect] = [:]
        var x = 0.0
        for level in levels.keys.sorted() {
            let levelIDs = levels[level]!
            let maxWidth = levelIDs.compactMap { byID[$0]?.frame.width }.max() ?? 176
            var y = 0.0
            for id in levelIDs {
                var frame = byID[id]!.frame
                frame.x = x
                frame.y = y
                result[id] = frame
                y += frame.height + 48
            }
            x += maxWidth + 100
        }
        return result
    }
}
