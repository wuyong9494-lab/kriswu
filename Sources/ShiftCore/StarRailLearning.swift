import Foundation

extension StarRail {
    public enum Lesson: String, Codable, CaseIterable, Sendable { case firstOrbit, firstFork, journeyAbility, journeyGate, journeyReturn }
    public struct LessonStep: Equatable, Sendable {
        public let title: String
        public let instruction: String
        public let highlightedCards: Set<Int>
        public let asksForPreview: Bool
        public static func current(game: Game, previewSeen: Bool, dismissed: Set<Lesson>) -> LessonStep? {
            guard game.status == .playing else { return nil }
            if let config = game.stage.journey {
                guard !dismissed.contains(config.lesson) else { return nil }
                if config.chapter == 0 && game.state.matches == 0 {
                    return .init(title:"1 / 3 · 三张同类会消除",instruction:"先点亮三张卫星，获得 1 点能量。\(config.ability.title)的效果已显示在能量与收集槽上。",highlightedCards:Set(game.stage.cards.filter { $0.kind == 0 && game.contains($0.id,in:game.state) }.map(\.id)),asksForPreview:false)
                }
                if config.chapter == 0 && game.state.shifts == 0 {
                    return .init(title:"2 / 3 · 预览 A 轨",instruction:previewSeen ? "比较近岔、远岔的费用与遮挡变化，再确认移动。" : "点 A 预览，先看移层后哪些牌会露出来。",highlightedCards:[],asksForPreview:true)
                }
                let gate = game.starGate
                if let gate, !game.gateOpen(in:game.state) {
                    return .init(title:"星门课堂 · 先配对再通行",instruction:"先消除三张\(StarRail.names[gate.kind])打开星门。点亮的是当前可取的钥匙图案。",
                        highlightedCards:Set(game.stage.cards.filter { $0.kind == gate.kind && game.freeIDs(in:game.state).contains($0.id) && !game.isAnchor($0.id,in:game.state) }.map(\.id)),asksForPreview:false)
                }
                if config.objective == .escort {
                    return .init(title:"星核不能取走，需要护送",instruction:"至少完成 2 组配对，让 B 轨让路，再预览 A 轨的\(config.route == .supply ? "近岔" : "远岔")。收集槽清空、星核送达即可通关。",highlightedCards:[config.coreID!],asksForPreview:true)
                }
                return .init(title:config.chapter == 0 ? "本轮能力 · \(config.ability.title)" : "总耗能有限，先算往返",instruction:config.chapter == 0 ? config.ability.detail : "每次确认移层都会计入总耗能。预览先看成本，再安排两轨返航。",highlightedCards:[],asksForPreview:true)
            }
            if game.stage.expeditionID != nil && !dismissed.contains(.firstFork) {
                guard !game.actions.contains(where: { if case .travel = $0 { return true }; return false }) else { return nil }
                return .init(title: "分岔课堂", instruction: "先储能，再分别预览近岔和远岔：留意成本，以及新露出的第三张。", highlightedCards: [], asksForPreview: true)
            }
            guard game.stage.id == 1, game.stage.trial == nil, game.stage.expeditionID == nil,
                  !dismissed.contains(.firstOrbit) else { return nil }
            if game.state.matches == 0 {
                return .init(title: "1 / 3 · 凑齐三枚卫星", instruction: "点亮的卫星可以取走。收集三张相同的牌，给轨道充能。",
                             highlightedCards: Set(game.stage.cards.filter { $0.kind == 0 && game.contains($0.id,in:game.state) }.map(\.id)), asksForPreview: false)
            }
            if game.state.shifts == 0 {
                return .init(title: "2 / 3 · 先预览，再移动", instruction: previewSeen ? "点下方 A 打开预览，再点「确认移动」。带图钉的牌会随轨道一起移动。" : "点棋盘下方的「A · 预览移层」，再点出现的「确认移动」。也可点带图钉的牌打开预览。", highlightedCards: [], asksForPreview: true)
            }
            return .init(title: "3 / 3 · 完成自己的航线", instruction: "现在收集新露出的同类牌。槽内三张会自动消除，清空棋盘即可完成课堂。", highlightedCards: [], asksForPreview: false)
        }
    }

    public struct ReviewMoment: Identifiable, Equatable, Sendable {
        /// Index of the action that caused the observed change; replay/restore uses its pre-state.
        public let id: Int
        public let title: String
        public let detail: String
        public let importance: Int
        public var restoreIndex: Int { max(0, id - 1) }
    }
}

extension StarRail.Game {
    /// Observed events, not an unproven assertion that a particular turn made
    /// the board mathematically unsolvable. No solver is run on the UI thread.
    public var reviewMoments: [StarRail.ReviewMoment] {
        let states = replayStates
        var result: [StarRail.ReviewMoment] = []
        for index in actions.indices {
            let before = states[index], after = states[index+1]
            if after.tray.count >= stage.capacity - 1 && after.tray.count > before.tray.count {
                let ready = kindPlans(in: after).contains(where: \.canComplete)
                let detail = after.tray.count >= stage.capacity
                    ? "第 \(index+1) 手后收集槽已满，本局结束。回到这一步之前，检查第三张的位置与取牌顺序。"
                    : "第 \(index+1) 手后占用 \(after.tray.count)/\(stage.capacity) 格。\(ready ? "当时仍有可直接完成的三张。" : "当时没有能直接凑齐的三张，需要重新安排取牌或移层。")"
                result.append(.init(id:index+1,title:"槽位接近上限",detail:detail,importance:3))
            }
            if after.shifts > before.shifts {
                let prior = kindPlans(in: before), next = kindPlans(in: after)
                if let blocked = prior.first(where: { plan in
                    plan.inTray > 0 && plan.available > 0 && next.first(where: { $0.kind == plan.kind })!.available < plan.available
                }) {
                    result.append(.init(id:index+1,title:"移层重新盖住配对牌",detail:"第 \(index+1) 手移层时，槽内已有 \(blocked.inTray) 张\(StarRail.names[blocked.kind])，可取的同类牌减少了。",importance:4))
                } else if after.energy == 0 && after.arrivals & stage.requiredArrivals != stage.requiredArrivals {
                    result.append(.init(id:index+1,title:"返航前用尽储能",detail:"第 \(index+1) 手后储能归零，航线尚未完成。检查当时能否留出下一组三消。",importance:2))
                }
            } else if after.overflowEnergy > before.overflowEnergy {
                result.append(.init(id:index+1,title:"满能量时继续消除",detail:"第 \(index+1) 手三消时能量已经存满，这一点能量没有储存下来。可以回看是否有更合适的移层时机。",importance:1))
            }
        }
        // Prefer actionable pressure/coverage events, then the most recent occurrence.
        result.sort { $0.importance == $1.importance ? $0.id > $1.id : $0.importance > $1.importance }
        var seen = Set<Int>()
        return Array(result.filter { seen.insert($0.id).inserted }.prefix(4)).sorted { $0.id < $1.id }
    }
    public func actionDescription(at index: Int) -> String {
        guard actions.indices.contains(index) else { return "初始棋盘" }
        switch actions[index] {
        case .pick(let id): return "取走\(StarRail.names[stage.cards[id].kind])"
        case .shift(let id): return "\(stage.rails[id].name)移往\(stage.rails[id].stopName(replayStates[index+1].positions[id]))"
        case .travel(let id, let to): return "\(stage.rails[id].name)移往\(stage.rails[id].stopName(to))"
        }
    }
}
