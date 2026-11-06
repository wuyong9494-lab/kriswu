import Foundation

/// Independent rules: never serialized as TileGame.RuleSet or TileRace.Message.
public enum StarRail {
    public static let version = "star-rails-v1"
    public static let capacity = 7
    public static let energyLimit = 2
    public static let names = ["卫星", "天线", "火箭", "地球", "月亮", "星星", "太阳", "土星", "彗星", "望远镜", "飞碟", "太空舱"]

    public struct Point: Equatable, Hashable, Sendable {
        public let x: Int
        public let y: Int
    }
    public struct Card: Identifiable, Equatable, Sendable {
        public let id: Int
        public let kind: Int
        public let x: Int
        public let y: Int
        public let z: Int
        public let rail: Int?
    }
    public struct Rail: Identifiable, Equatable, Sendable {
        public let id: Int
        public let name: String
        public let delta: Point
        public internal(set) var extraStops: [Point] = []
        public internal(set) var farCost: Int = 2
        public var stopCount: Int { 2 + extraStops.count }
        public func offset(at index: Int) -> Point { index == 0 ? Point(x:0,y:0) : index == 1 ? delta : extraStops[index-2] }
        public var stops: [Point] { [Point(x: 0, y: 0), delta] + extraStops }
        public func cost(to stop: Int) -> Int { stop >= 2 ? farCost : 1 }
        public func stopName(_ stop: Int) -> String { stop == 0 ? "起点" : stopCount == 2 ? "远端" : stop == 1 ? "近岔" : "远岔" }
    }
    public struct Stage: Identifiable, Equatable, Sendable {
        public let id: Int
        public let title: String
        public let lesson: String
        public let objective: String
        public let tip: String
        public let cards: [Card]
        public let rails: [Rail]
        /// One bit per stop, contiguous per rail; arrival requires an actual move.
        /// R1/R2 two-stop rails retain their original two-bit encoding.
        public let requiredArrivals: Int
        public let plannedMoves: Int
        public let targetPeak: Int
        public internal(set) var revision: Int = 1
        public internal(set) var trial: TrialRule? = nil
        public internal(set) var expeditionID: Int? = nil
        public internal(set) var journey: StarJourney.Configuration? = nil
        public var capacity: Int { journey?.ability.capacity ?? (trial == .compact || trial == .master ? 6 : StarRail.capacity) }
        public var energyLimit: Int { journey?.ability.energyLimit ?? (trial == .pulse || trial == .master ? 1 : StarRail.energyLimit) }
        public var shiftLimit: Int? { trial == .master ? plannedMoves : nil }
        public var width: Int { cards.map { c in c.x + (c.rail.map { rails[$0].stops.map(\.x).max() ?? 0 } ?? 0) + 4 }.max() ?? 20 }
        public var height: Int { cards.map { c in c.y + (c.rail.map { rails[$0].stops.map(\.y).max() ?? 0 } ?? 0) + 4 }.max() ?? 20 }
        public func arrivalBit(rail: Int, stop: Int) -> Int {
            1 << (rails.prefix(rail).reduce(0) { $0 + $1.stopCount } + stop)
        }
        public func goalMask(rail: Int) -> Int {
            (0..<rails[rail].stopCount).reduce(0) { $0 | arrivalBit(rail: rail, stop: $1) } & requiredArrivals
        }
        public func poseIndex(_ positions: [Int]) -> Int {
            var index = 0, stride = 1
            for rail in rails { index += positions[rail.id] * stride; stride *= rail.stopCount }
            return index
        }
    }
    public enum Action: Codable, Equatable, Hashable, Sendable {
        case pick(Int)
        case shift(Int)
        case travel(rail: Int, to: Int)
    }
    public enum Status: Equatable, Sendable { case playing, won, lost }
    public struct State: Equatable, Sendable {
        public internal(set) var remaining: UInt64
        public internal(set) var tray: [Int] = []
        public internal(set) var positions: [Int]
        public internal(set) var energy = 0
        public internal(set) var arrivals = 0
        public internal(set) var shifts = 0
        public internal(set) var peak = 0
        public internal(set) var matches = 0
        public internal(set) var overflowEnergy = 0
        public internal(set) var spentEnergy = 0
        public internal(set) var freeReturnUsed = false
    }
    public struct Preview: Equatable, Sendable {
        public let rail: Int
        public let proposed: State
        public let revealed: Set<Int>
        public let covered: Set<Int>
        public let reason: String?
        public var canMove: Bool { reason == nil }
    }

    public struct Game: Equatable, Sendable {
        public let stage: Stage
        public private(set) var state: State
        public private(set) var actions: [Action] = []
        public private(set) var rewinds = 0
        private var history: [State] = []
        private let coverMasks: [[UInt64]]
        private let collisionMasks: [[UInt64]]
        private let railMasks: [UInt64]
        public init(stage: Stage) {
            precondition(!stage.cards.isEmpty && stage.cards.count < 63)
            precondition(stage.cards.enumerated().allSatisfy { $0.offset == $0.element.id })
            precondition(stage.rails.allSatisfy { (2...3).contains($0.stopCount) && (1...2).contains($0.farCost) })
            precondition(stage.rails.count <= 2 && stage.rails.enumerated().allSatisfy { $0.offset == $0.element.id })
            precondition(stage.cards.allSatisfy { StarRail.names.indices.contains($0.kind) && ($0.rail.map { stage.rails.indices.contains($0) } ?? true) })
            self.stage = stage
            state = State(remaining: (UInt64(1) << stage.cards.count) - 1,
                          positions: Array(repeating:0,count:stage.rails.count))
            state.energy = stage.journey?.openingEnergy ?? 0
            railMasks = stage.rails.map { rail in stage.cards.filter { $0.rail == rail.id }.reduce(0) { $0 | (UInt64(1) << $1.id) } }
            var covers:[[UInt64]] = [], collisions:[[UInt64]] = []
            for pose in 0..<stage.rails.reduce(1, { $0 * $1.stopCount }) {
                var offsets: [Point] = [], stride = 1
                for rail in stage.rails {
                    offsets.append(rail.offset(at:(pose / stride) % rail.stopCount)); stride *= rail.stopCount
                }
                func at(_ c:Card) -> Point {
                    guard let rail = c.rail else { return Point(x:c.x,y:c.y) }
                    return Point(x:c.x+offsets[rail].x,y:c.y+offsets[rail].y)
                }
                var cover = Array(repeating:UInt64(0),count:stage.cards.count), collision = cover
                for a in stage.cards {
                    for b in stage.cards where a.id != b.id {
                        let p=at(a),q=at(b)
                        if abs(p.x-q.x)<4 && abs(p.y-q.y)<4 {
                            if b.z>a.z { cover[a.id] |= UInt64(1) << b.id }
                            if b.z==a.z { collision[a.id] |= UInt64(1) << b.id }
                        }
                    }
                }
                covers.append(cover);collisions.append(collision)
            }
            coverMasks=covers;collisionMasks=collisions
        }
        private func pose(_ state:State) -> Int { stage.poseIndex(state.positions) }
        public var replayStates: [State] { history + [state] }
        public var status: Status { status(of:state) }
        public var canUndo: Bool { !history.isEmpty }
        public var stars: Int {
            guard status == .won else { return 0 }
            guard state.shifts <= stage.plannedMoves else { return 1 }
            return state.peak <= stage.targetPeak ? 3 : 2
        }
        public func contains(_ id: Int, in state: State) -> Bool {
            stage.cards.indices.contains(id) && state.remaining & (UInt64(1) << id) != 0
        }
        public func board(in state: State) -> [Card] { stage.cards.filter { contains($0.id,in:state) } }
        public func remaining(on rail: Int, in state: State) -> Int {
            guard railMasks.indices.contains(rail) else { return 0 }
            return (state.remaining & railMasks[rail]).nonzeroBitCount
        }
        public func point(_ card: Card, in state: State) -> Point {
            guard let rail = card.rail else { return Point(x: card.x, y: card.y) }
            let offset = stage.rails[rail].offset(at:state.positions[rail])
            return Point(x: card.x + offset.x, y: card.y + offset.y)
        }
        public func overlaps(_ a: Card, _ b: Card, in state: State) -> Bool {
            let p = point(a,in:state), q = point(b,in:state)
            return abs(p.x-q.x) < 4 && abs(p.y-q.y) < 4
        }
        public func blockers(of id: Int, in state: State) -> [Int] {
            guard contains(id,in:state) else { return [] }
            let mask = coverMasks[pose(state)][id] & state.remaining
            return stage.cards.filter { mask & (UInt64(1) << $0.id) != 0 }.map(\.id)
        }
        public func freeIDs(in state: State) -> Set<Int> {
            let masks = coverMasks[pose(state)]
            return Set(stage.cards.filter { contains($0.id,in:state) && masks[$0.id] & state.remaining == 0 }.map(\.id))
        }
        public func status(of state: State) -> Status {
            if state.tray.count >= stage.capacity { return .lost }
            for rail in stage.rails {
                let required = stage.goalMask(rail: rail.id)
                if state.arrivals & required != required && state.remaining & railMasks[rail.id] == 0 { return .lost }
            }
            if objectiveComplete(in:state) { return .won }
            if stage.revision >= 2 && !freeIDs(in: state).contains(where: { !isAnchor($0, in: state) })
                && !stage.rails.contains(where: { rail in (0..<rail.stopCount).contains { stop in shiftReason(rail.id, to: stop, in: state, checkEnergy: true) == nil } }) { return .lost }
            return .playing
        }
        public func failureReason(in state: State) -> String? {
            guard status(of:state) == .lost else { return nil }
            if state.tray.count >= stage.capacity {
                return "\(stage.capacity == 6 ? "六格" : stage.capacity == 7 ? "七格" : "八格")已满，却没有凑齐三张。先撤回，检查第三张是否被轨道挡住，或改用移层腾出通路。"
            }
            if let limit = stage.shiftLimit, state.shifts >= limit {
                return "移层预算已用完，剩余锚牌还没有完成航线。撤回检查出发与返程顺序，每次移层都要为下一组消除开窗。"
            }
            if stage.revision >= 2 {
                return "剩余锚牌还需完成航线，但已经没有可用的移层或取牌。撤回检查：返程能量是否提前用掉，或轨道是否相互挡住。"
            }
            let exhausted = stage.rails.first { r in
                let goal = stage.goalMask(rail: r.id)
                return state.arrivals & goal != goal && !board(in:state).contains(where: { $0.rail == r.id })
            }
            return "\(exhausted?.name ?? "轨道")的牌已取完，但移层目标还未完成。撤回最后一次取牌，先完成航线再收走轨道牌。"
        }
        private func shiftReason(_ id: Int, to destination: Int, in state: State, checkEnergy: Bool) -> String? {
            guard stage.rails.indices.contains(id) else { return "没有这条轨道" }
            let rail = stage.rails[id]
            guard (0..<rail.stopCount).contains(destination), destination != state.positions[id] else { return "请选择另一个轨道终点" }
            if rail.stopCount > 2 && state.positions[id] != 0 && destination != 0 { return "两个岔口之间需先返回起点" }
            if let limit = stage.shiftLimit, state.shifts >= limit { return "移层预算已用完：撤回调整航线，或在当前位置完成消除" }
            if let gate = starGate, gate.rail == id, destination != 0, !gateOpen(in:state) {
                return "星门未开启：先完成三张\(StarRail.names[gate.kind])的配对"
            }
            let cost = moveCost(rail:id,to:destination,in:state)
            if let budget = stage.journey?.energyBudget, state.spentEnergy + cost > budget { return "总耗能将超出 \(budget) 点预算，改换路线或撤回调整" }
            let members = board(in:state).filter { $0.rail == id }
            guard !members.isEmpty else { return "这条轨道的牌已经取完" }
            guard members.allSatisfy({ coverMasks[pose(state)][$0.id] & state.remaining == 0 }) else { return "轨道上方还有牌：先移开上层轨道，或取走压住它的牌" }
            var target = state; target.positions[id] = destination
            for member in members {
                if collisionMasks[pose(target)][member.id] & state.remaining & ~railMasks[id] != 0 {
                    return "终点有同层牌或轨道占位：先取牌或移轨让路"
                }
            }
            if checkEnergy && state.energy < cost { return "需要 \(cost) 点能量；先消除相同的三张储能" }
            return nil
        }
        public func rejection(_ action: Action, in state: State) -> String? {
            guard status(of:state) == .playing else { return "本局已结束，可撤回或重试" }
            switch action {
            case .pick(let id):
                guard contains(id,in:state) else { return "这张牌已被取走" }
                if isStarCore(id) { return "星核需要由 A 轨护送，不能放入收集槽" }
                if isAnchor(id, in: state) { return "航线还未完成：带锚标记的最后一张轨道牌需留作返航，先完成移层目标" }
                return blockers(of:id,in:state).isEmpty ? nil : "这张牌仍被上层牌遮挡，可先预览移层"
            case .shift(let id):
                guard stage.rails.indices.contains(id), stage.rails[id].stopCount == 2 else { return "分岔轨道需要指定终点" }
                return shiftReason(id, to: 1-state.positions[id], in: state, checkEnergy: true)
            case .travel(let id, let to):
                guard stage.rails.indices.contains(id), stage.rails[id].stopCount == 3 else { return "这条轨道没有分岔" }
                return shiftReason(id, to: to, in: state, checkEnergy: true)
            }
        }
        public func preview(_ id: Int, to stop: Int? = nil, in state: State) -> Preview? {
            guard stage.rails.indices.contains(id) else { return nil }
            let destination = stop ?? (state.positions[id] == 0 ? 1 : 0)
            guard (0..<stage.rails[id].stopCount).contains(destination), destination != state.positions[id] else { return nil }
            let action = moveAction(rail: id, to: destination)
            var target = state; target.positions[id] = destination
            if let moved = transition(action, from: state) { target = moved }
            let before = freeIDs(in:state), after = freeIDs(in:target)
            return Preview(rail:id,proposed:target,revealed:after.subtracting(before),covered:before.subtracting(after),
                           reason:rejection(action,in:state))
        }
        public func legalActions(in state: State) -> [Action] {
            guard status(of:state) == .playing else { return [] }
            var result = freeIDs(in: state).sorted().map(Action.pick).filter { rejection($0, in: state) == nil }
            for rail in stage.rails {
                for destination in 0..<rail.stopCount where destination != state.positions[rail.id] {
                    let action = moveAction(rail: rail.id, to: destination)
                    if rejection(action, in: state) == nil { result.append(action) }
                }
            }
            return result
        }
        public func moveAction(rail: Int, to destination: Int) -> Action {
            stage.rails[rail].stopCount == 2 ? .shift(rail) : .travel(rail: rail, to: destination)
        }
        /// UI, replays and every solver use this exact transition function.
        public func transition(_ action: Action, from state: State) -> State? {
            guard rejection(action,in:state) == nil else { return nil }
            var next = state
            switch action {
            case .shift(let id), .travel(let id, _):
                let destination: Int
                if case .travel(_, let to) = action { destination = to } else { destination = 1-state.positions[id] }
                let cost = moveCost(rail:id,to:destination,in:state)
                next.positions[id] = destination
                next.energy -= cost; next.spentEnergy += cost; next.shifts += 1
                if stage.journey?.ability == .navigator && destination == 0 { next.freeReturnUsed = true }
                next.arrivals |= stage.arrivalBit(rail: id, stop: destination)
            case .pick(let id):
                next.remaining &= ~(UInt64(1) << id)
                next.tray.append(id)
                next.tray.sort { (stage.cards[$0].kind,$0) < (stage.cards[$1].kind,$1) }
                let kind = stage.cards[id].kind
                if next.tray.filter({ stage.cards[$0].kind == kind }).count == 3 {
                    next.tray.removeAll { stage.cards[$0].kind == kind }
                    next.matches += 1
                    if next.energy == stage.energyLimit { next.overflowEnergy += 1 }
                    next.energy = min(stage.energyLimit,next.energy+1)
                }
                next.peak = max(next.peak,next.tray.count)
            }
            return next
        }
        @discardableResult public mutating func perform(_ action: Action) -> Bool {
            guard actions.count < 256, let next = transition(action,from:state) else { return false }
            history.append(state); actions.append(action); state = next; return true
        }
        @discardableResult public mutating func undo() -> Bool {
            guard let previous = history.popLast() else { return false }
            state = previous; actions.removeLast()
            if stage.trial != nil || stage.expeditionID != nil || stage.journey != nil { rewinds = min(10_000, rewinds + 1) }
            return true
        }
        public struct Archive: Codable, Equatable, Sendable {
            public var version: String
            public var stage: Int
            public var actions: [Action]
            public var revision: Int
            public var trial: TrialRule?
            public var rewinds: Int
            public var expeditionID: Int?
            public var journey: StarJourney.Configuration?
            public init(version: String = StarRail.version, stage: Int, actions: [Action], revision: Int = StarRail.catalogRevision, trial: TrialRule? = nil, rewinds: Int = 0, expeditionID: Int? = nil, journey: StarJourney.Configuration? = nil) {
                self.journey = journey
                self.expeditionID = expeditionID
                self.trial = trial; self.rewinds = rewinds
                self.version = version; self.stage = stage; self.actions = actions; self.revision = revision
            }
            private enum CodingKeys: String, CodingKey { case version, stage, actions, revision, trial, rewinds, expeditionID, journey }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                version = try c.decode(String.self, forKey: .version)
                stage = try c.decode(Int.self, forKey: .stage)
                actions = try c.decode([Action].self, forKey: .actions)
                revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
                trial = try c.decodeIfPresent(TrialRule.self, forKey: .trial)
                rewinds = try c.decodeIfPresent(Int.self, forKey: .rewinds) ?? 0
                expeditionID = try c.decodeIfPresent(Int.self, forKey: .expeditionID)
                journey = try c.decodeIfPresent(StarJourney.Configuration.self, forKey: .journey)
            }
        }
        public var archive: Archive { .init(stage:stage.id,actions:actions,revision:stage.revision,trial:stage.trial,rewinds:rewinds,expeditionID:stage.expeditionID,journey:stage.journey) }
        public init?(archive: Archive) {
            guard archive.version == StarRail.version, archive.actions.count <= 256,
                  (0...10_000).contains(archive.rewinds), (archive.trial != nil || archive.expeditionID != nil || archive.journey != nil || archive.rewinds == 0),
                  let stage = StarRail.archivedStage(id: archive.stage, revision: archive.revision, trial: archive.trial, expeditionID: archive.expeditionID, journey:archive.journey) else { return nil }
            self.init(stage:stage)
            for action in archive.actions { if !perform(action) { return nil } }
            rewinds = archive.rewinds
        }
    }

    /// Atomic actions are saved before animation. A stale completion can never
    /// unlock or alter a restarted/restored board.
    public struct Session: Equatable, Sendable {
        public private(set) var game: Game
        public private(set) var pending: UUID?
        public private(set) var active = true
        public init(game: Game) { self.game = game }
        public var canInteract: Bool { active && pending == nil }
        public mutating func submit(_ action: Action) -> UUID? {
            guard canInteract, game.perform(action) else { return nil }
            let token = UUID(); pending = token; return token
        }
        public mutating func finish(_ token: UUID) { if pending == token { pending = nil } }
        public mutating func setActive(_ value: Bool) { active = value; if !value { pending = nil } }
        public mutating func restart() { pending = nil; game = Game(stage: game.stage.trial == nil && game.stage.expeditionID == nil && game.stage.journey == nil ? (StarRail.stage(game.stage.id) ?? game.stage) : game.stage) }
        /// Picks commit synchronously and never wait for a cosmetic animation.
        @discardableResult public mutating func take(_ id: Int) -> Bool { canInteract && game.perform(.pick(id)) }
        @discardableResult public mutating func undo() -> Bool { canInteract && game.undo() }
        @discardableResult public mutating func rewind(to count: Int) -> Bool {
            guard canInteract, count >= 0, count < game.actions.count else { return false }
            while game.actions.count > count { guard game.undo() else { return false } }
            return true
        }
    }

    public struct Progress: Codable, Equatable, Sendable {
        public let version: String
        public let catalogRevision: Int
        public private(set) var stars: [Int:Int] = [:]
        public private(set) var bestMoves: [Int:Int] = [:]
        public private(set) var bestPeak: [Int:Int] = [:]
        public private(set) var legacyStars: [Int:Int] = [:]
        public private(set) var legacyMoves: [Int:Int] = [:]
        public private(set) var legacyPeak: [Int:Int] = [:]
        public private(set) var unlockedThrough = 1

        public init() { version = StarRail.version; catalogRevision = StarRail.catalogRevision }
        public func unlocked(_ id: Int) -> Bool {
            version == StarRail.version && StarRail.stage(id) != nil && id <= unlockedThrough
        }
        public var totalStars: Int { stars.values.reduce(0, +) }
        public var nextStage: Stage {
            StarRail.stages.first { unlocked($0.id) && stars[$0.id] == nil } ?? StarRail.stages[5]
        }
        public var isValid: Bool {
            guard version == StarRail.version, catalogRevision == StarRail.catalogRevision,
                  (1...6).contains(unlockedThrough) else { return false }
            func valid(_ scores:[Int:Int], _ moves:[Int:Int], _ peaks:[Int:Int]) -> Bool {
                Set(scores.keys) == Set(moves.keys) && Set(scores.keys) == Set(peaks.keys)
                    && scores.allSatisfy { id, value in
                        unlocked(id) && (1...3).contains(value) && (0...256).contains(moves[id] ?? -1)
                            && (0..<StarRail.capacity).contains(peaks[id] ?? -1)
                    }
            }
            return valid(stars, bestMoves, bestPeak) && valid(legacyStars, legacyMoves, legacyPeak)
        }
        @discardableResult public mutating func record(_ game: Game) -> Bool {
            guard version == StarRail.version,
                  game.stage == StarRail.stage(game.stage.id, revision: game.stage.revision),
                  unlocked(game.stage.id), game.status == .won else { return false }
            let id = game.stage.id
            unlockedThrough = max(unlockedThrough, min(6, id + 1))
            if game.stage.revision == StarRail.catalogRevision {
                stars[id] = max(stars[id] ?? 0,game.stars)
                bestMoves[id] = min(bestMoves[id] ?? Int.max,game.state.shifts)
                bestPeak[id] = min(bestPeak[id] ?? Int.max,game.state.peak)
            } else {
                legacyStars[id] = max(legacyStars[id] ?? 0,game.stars)
                legacyMoves[id] = min(legacyMoves[id] ?? Int.max,game.state.shifts)
                legacyPeak[id] = min(legacyPeak[id] ?? Int.max,game.state.peak)
            }
            return true
        }

        private enum CodingKeys: String, CodingKey {
            case version, catalogRevision, stars, bestMoves, bestPeak, legacyStars, legacyMoves, legacyPeak, unlockedThrough
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(String.self, forKey: .version)
            let revision = try c.decodeIfPresent(Int.self, forKey: .catalogRevision) ?? 1
            catalogRevision = StarRail.catalogRevision
            stars = try c.decode([Int:Int].self, forKey: .stars)
            bestMoves = try c.decode([Int:Int].self, forKey: .bestMoves)
            bestPeak = try c.decode([Int:Int].self, forKey: .bestPeak)
            if revision == 1 {
                guard Set(stars.keys) == Set(bestMoves.keys), Set(stars.keys) == Set(bestPeak.keys),
                      stars.keys.allSatisfy({ (1...6).contains($0) && (1..<$0).allSatisfy { stars[$0] != nil } }) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid legacy progression"))
                }
                legacyStars = stars; legacyMoves = bestMoves; legacyPeak = bestPeak
                unlockedThrough = min(6, (stars.keys.max() ?? 0) + 1)
                stars = [:]; bestMoves = [:]; bestPeak = [:]
            } else if revision == StarRail.catalogRevision {
                legacyStars = try c.decode([Int:Int].self, forKey: .legacyStars)
                legacyMoves = try c.decode([Int:Int].self, forKey: .legacyMoves)
                legacyPeak = try c.decode([Int:Int].self, forKey: .legacyPeak)
                unlockedThrough = try c.decode(Int.self, forKey: .unlockedThrough)
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown star-rail catalog"))
            }
            guard isValid else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid star-rail scores"))
            }
        }
    }
}
