import Foundation

extension StarRail.Game {
    /// Revision 2 removes the cheap instant-loss trap. It does not choose a
    /// move for the player: remaining energy, tray pressure and occlusion matter.
    public func isAnchor(_ id: Int, in state: StarRail.State) -> Bool {
        if isStarCore(id) { return true }
        guard stage.revision >= 2, contains(id, in: state), let rail = stage.cards[id].rail else { return false }
        let goal = stage.goalMask(rail: rail)
        return state.arrivals & goal != goal && remaining(on: rail, in: state) == 1
    }

    public struct KindPlan: Equatable, Sendable, Identifiable {
        public let kind: Int
        public let inTray: Int
        public let available: Int
        public let remaining: Int
        public let blockingRails: [Int]
        public let hasRoom: Bool
        public var id: Int { kind }
        public var canComplete: Bool { inTray + available >= 3 && hasRoom }
    }

    /// Immediate, visible facts only; never a hidden solution or a win forecast.
    public func kindPlans(in state: StarRail.State) -> [KindPlan] {
        let free = freeIDs(in: state)
        return Set(stage.cards.filter { !isStarCore($0.id) }.map(\.kind)).sorted().map { kind in
            let cards = board(in: state).filter { $0.kind == kind }
            let rails = Set(cards.flatMap { blockers(of: $0.id, in: state) }.compactMap { stage.cards[$0].rail })
            let trayCount = state.tray.filter { stage.cards[$0].kind == kind }.count
            var available = cards.filter { free.contains($0.id) && !isAnchor($0.id, in: state) }.count
            if stage.revision >= 2 {
                for rail in stage.rails {
                    let goal = stage.goalMask(rail: rail.id)
                    let members = board(in: state).filter { $0.rail == rail.id }
                    if state.arrivals & goal != goal && members.count > 1
                        && members.allSatisfy({ $0.kind == kind && free.contains($0.id) }) {
                        available -= 1 // Taking one would make the last member an anchor.
                    }
                }
            }
            return KindPlan(kind: kind, inTray: trayCount,
                            available: available,
                            remaining: cards.count, blockingRails: rails.sorted(),
                            hasRoom: state.tray.count + max(0, 2 - trayCount) < stage.capacity)
        }
    }

    public var review: [KindPlan] {
        kindPlans(in: state).filter { $0.inTray > 0 }.sorted {
            $0.inTray == $1.inTray ? $0.kind < $1.kind : $0.inTray > $1.inTray
        }
    }
}
