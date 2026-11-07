import Foundation

/// Independent J1 journey catalog. It never replaces the frozen R1/R2/XP1 boards.
public enum StarJourney {
    public enum Ability: String, Codable, CaseIterable, Sendable {
        case capacitor, navigator, buffer, pulse
        public var title: String { self == .capacitor ? "深空电容" : self == .navigator ? "返航导航" : self == .buffer ? "缓冲舱" : "脉冲引擎" }
        public var detail: String {
            switch self {
            case .capacitor: return "储能上限 3，收集槽 6 格；适合提前储备远岔能量。"
            case .navigator: return "每关首次返航免费，收集槽 7 格；关间能量不携带。"
            case .pulse: return "收集槽 6 格，储能上限 2；两次移层之间三消两组，下次移层免费（含远岔）。每次移层清空脉冲，关间不携带脉冲。"
            case .buffer: return "收集槽 8 格，储能上限 2；每次返航需要 2 点能量。"
            }
        }
        public var capacity: Int { self == .capacitor || self == .pulse ? 6 : self == .buffer ? 8 : 7 }
        public var energyLimit: Int { self == .capacitor ? 3 : 2 }
    }
    public enum Route: String, Codable, CaseIterable, Sendable {
        case supply, signal
        public var title: String { self == .supply ? "近航补给" : "远航追光" }
        public var detail: String {
            self == .supply ? "第二关额外补充 1 点能量，护送星核到近岔。" : "第二关护送星核到远岔；整轮完成额外获得 1 枚星章。"
        }
        public var destination: Int { self == .supply ? 1 : 2 }
    }
    public enum Objective: String, Codable, Sendable { case clear, escort, limitedReturn }
    public struct Gate: Equatable, Sendable {
        public let rail: Int
        public let kind: Int
    }
    public struct Configuration: Codable, Equatable, Sendable {
        public let version: Int
        public let runID: UUID
        public let ability: Ability
        public let chapter: Int
        public let route: Route?
        public let openingEnergy: Int
        public init(runID: UUID, ability: Ability, chapter: Int, route: Route? = nil, openingEnergy: Int = 0) {
            version = 1; self.runID = runID; self.ability = ability; self.chapter = chapter
            self.route = route; self.openingEnergy = openingEnergy
        }
        public var isValid: Bool {
            version == 1 && (0...2).contains(chapter) && (chapter == 0 ? route == nil && openingEnergy == 0 : route != nil)
                && (0...ability.energyLimit).contains(openingEnergy)
        }
        public var objective: Objective { chapter == 0 ? .clear : chapter == 1 ? .escort : .limitedReturn }
        public var gate: Gate? { chapter == 0 ? nil : Gate(rail:0,kind:chapter == 1 ? 2 : 3) }
        public var energyBudget: Int? { chapter == 2 ? (ability == .buffer ? 7 : 5) : nil }
        public var coreID: Int? { chapter == 1 ? 27 : nil }
        public var title: String { ["启航清空", "星门护送", "限能返航"][chapter] }
        public var objectiveText: String {
            switch objective {
            case .clear: return "完成 A 轨往返并清盘；" + (ability == .navigator ? "导航能力关间不携带能量" : "剩余能量可带入下一关")
            case .escort: return "至少配对 2 组，其中火箭开启星门；让 B 轨让行，把星核送到\(route == .supply ? "近岔" : "远岔")，收集槽需清空"
            case .limitedReturn: return "配对地球打开星门，在 \(energyBudget!) 点总耗能内完成双轨往返并清盘"
            }
        }
        // Curated together across all three abilities and every allowed starting energy.
        static let seeds: [UInt64] = [1, 57, 57, 2, 2]
        public var stage: StarRail.Stage {
            precondition(isValid)
            let template = chapter == 0 ? 0 : chapter == 1 ? 3 : 5
            let seedIndex = chapter == 0 ? 0 : (chapter == 1 ? 1 : 3) + (route == .signal ? 1 : 0)
            return authoredStage(seed:Self.seeds[seedIndex],template:template)
        }
        /// Used only by offline authoring and regression tests.
        func authoredStage(seed: UInt64, template: Int) -> StarRail.Stage {
            let base = StarRail.Expedition.make(template:template,seed:seed,id:1)
            let arrivals = chapter == 1 ? base.arrivalBit(rail:0,stop:route!.destination) | base.arrivalBit(rail:1,stop:1) : base.requiredArrivals
            // The cargo is a separate object, never one card stolen from a matchable triple.
            // Its extra deck position keeps both destination lanes clear after B yields.
            let cards = chapter == 1 ? base.cards + [StarRail.Card(id:27,kind:11,x:0,y:12,z:2,rail:0)] : base.cards
            return StarRail.Stage(id:201+chapter,title:title,lesson:ability.title,objective:objectiveText,
                tip:ability.detail + (chapter == 0 ? " 先为往返储能，再取走最后一张轨道牌。" : chapter == 1
                    ? " 星门只在火箭完成三消后打开；星核不能取走，需要用轨道护送。"
                    : " 星门只在地球完成三消后打开；预览会显示本次真实耗能。"),
                cards:cards,rails:base.rails,requiredArrivals:arrivals,
                plannedMoves:chapter == 1 ? 2 : base.plannedMoves,targetPeak:5,revision:4,journey:self)
        }
        public var lesson: StarRail.Lesson { chapter == 0 ? .journeyAbility : chapter == 1 ? .journeyGate : .journeyReturn }
    }
}

extension StarRail.Game {
    public var starGate: StarJourney.Gate? { stage.journey?.gate }
    public func gateOpen(in state: StarRail.State) -> Bool {
        guard let gate = starGate else { return true }
        let unmatched = stage.cards.filter { $0.kind == gate.kind && (contains($0.id,in:state) || state.tray.contains($0.id)) }.count
        return stage.cards.filter { $0.kind == gate.kind }.count - unmatched >= 3
    }
    public func isStarCore(_ id: Int) -> Bool { stage.journey?.coreID == id }
    public func moveCost(rail: Int, to stop: Int, in state: StarRail.State) -> Int {
        guard let journey = stage.journey else { return stage.rails[rail].cost(to:stop) }
        if journey.ability == .pulse && state.pulseCharge == 2 { return 0 }
        guard stop == 0 else { return stage.rails[rail].cost(to:stop) }
        if journey.ability == .buffer { return 2 }
        if journey.ability == .navigator && !state.freeReturnUsed { return 0 }
        return 1
    }
    public func objectiveComplete(in state: StarRail.State) -> Bool {
        guard let config = stage.journey, config.objective == .escort else { return state.remaining == 0 && state.tray.isEmpty }
        return state.positions[0] == config.route!.destination && state.arrivals & stage.requiredArrivals == stage.requiredArrivals
            && contains(config.coreID!,in:state) && gateOpen(in:state) && state.tray.isEmpty && state.matches >= 2
    }
}
