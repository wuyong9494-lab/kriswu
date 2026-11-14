import Foundation

/// Orders the recovered transparent particle renderers without confusing their
/// GameObject visibility mask with the renderer's sorting layer. Particle age
/// includes any prewarm already elapsed before an exported track begins.
public enum DuelSourceParticleOrder {
    public enum Failure: Error { case configuration }
    public struct Item: Equatable, Sendable {
        public let emitter: Int
        public let sortingLayer: Int
        public let sortingOrder: Int
        public let renderQueue: Int
        public let mode: Int
        public let age: Double
        /// Camera-space Z; the camera looks towards negative Z.
        public let viewDepth: Double

        public init(emitter: Int, sortingLayer: Int, sortingOrder: Int,
                    renderQueue: Int, mode: Int, age: Double, viewDepth: Double) {
            self.emitter = emitter; self.sortingLayer = sortingLayer
            self.sortingOrder = sortingOrder; self.renderQueue = renderQueue
            self.mode = mode; self.age = age; self.viewDepth = viewDepth
        }
    }

    public static func indices(_ items: [Item]) throws -> [Int] {
        guard items.count <= 16_384 else { throw Failure.configuration }
        var groups: [[Int]] = [], groupIndex: [Int: Int] = [:]
        for (index, item) in items.enumerated() {
            guard item.emitter >= 0, item.sortingLayer == 0,
                  (-1000...1000).contains(item.sortingOrder), (0...5000).contains(item.renderQueue),
                  [0, 2, 3, 4].contains(item.mode), item.age.isFinite, (0...72_000).contains(item.age),
                  item.viewDepth.isFinite, abs(item.viewDepth) <= 1_000_000 else { throw Failure.configuration }
            if let group = groupIndex[item.emitter] {
                let first = items[groups[group][0]]
                guard first.sortingLayer == item.sortingLayer, first.sortingOrder == item.sortingOrder,
                      first.renderQueue == item.renderQueue, first.mode == item.mode else { throw Failure.configuration }
                groups[group].append(index)
            } else {
                groupIndex[item.emitter] = groups.count; groups.append([index])
            }
        }
        // Group first: a comparator that alternates age and global ordinal for
        // particles from different emitters need not be transitive.
        groups.sort {
            let a = items[$0[0]], b = items[$1[0]]
            if a.sortingLayer != b.sortingLayer { return a.sortingLayer < b.sortingLayer }
            if a.sortingOrder != b.sortingOrder { return a.sortingOrder < b.sortingOrder }
            if a.renderQueue != b.renderQueue { return a.renderQueue < b.renderQueue }
            // Equal-priority renderer ties retain their source enumeration.
            // Unity's dynamic renderer-bounds sorting is not inferred here.
            return $0[0] < $1[0]
        }
        return groups.flatMap { group in
            group.sorted { left, right in
                let a = items[left], b = items[right]
                switch a.mode {
                case 2: if a.age != b.age { return a.age < b.age } // Oldest in front.
                case 3: if a.age != b.age { return a.age > b.age } // Youngest in front.
                case 4: if a.viewDepth != b.viewDepth { return a.viewDepth < b.viewDepth }
                default: break
                }
                return left < right
            }
        }
    }
}
