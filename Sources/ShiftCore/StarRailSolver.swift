import Foundation

/// Search has access to the same fully inspectable board as the player. It
/// does not read a stored solution, seed generator, or classic TileGame rules.
public enum StarRailSolver {
    public enum Result: Equatable, Sendable {
        case solved([StarRail.Action], nodes:Int)
        case budgetExceeded(nodes:Int)
        case noPathWithinConstraints(nodes:Int)
    }
    private struct Key: Hashable {
        let remaining:UInt64
        let tray:UInt64
        let positions:Int
        let energy:Int
        let arrivals:Int
        let spentEnergy:Int
        let freeReturnUsed:Bool
        let pulseCharge:Int
        init(_ state:StarRail.State,game:StarRail.Game) {
            remaining=state.remaining;energy=state.energy;arrivals=state.arrivals
            spentEnergy = game.stage.journey?.energyBudget == nil ? 0 : state.spentEnergy
            freeReturnUsed = state.freeReturnUsed
            pulseCharge = state.pulseCharge
            positions=game.stage.poseIndex(state.positions)
            var counts=Array(repeating:UInt64(0),count:StarRail.names.count)
            for id in state.tray { counts[game.stage.cards[id].kind] += 1 }
            tray=counts.enumerated().reduce(0) { $0 | ($1.element << ($1.offset*2)) }
        }
    }
    private static func utility(_ state:StarRail.State,game:StarRail.Game) -> Double {
        switch game.status(of:state) {
        case .won:return 100_000-Double(state.shifts*3+state.peak)
        case .lost:return -100_000
        case .playing:break
        }
        let goals=(state.arrivals & game.stage.requiredArrivals).nonzeroBitCount
        let groups=Dictionary(grouping:state.tray,by:{ game.stage.cards[$0].kind })
        let pairs=groups.values.filter { $0.count==2 }.count
        if game.stage.journey?.objective == .escort {
            let objectiveScore = min(state.matches,3)*40 + goals*80
            let gateScore = game.gateOpen(in:state) ? 75 : 0
            let resourceScore = state.energy*2 - state.tray.count*9 - state.shifts*2 + pairs*2
            return Double(objectiveScore + gateScore + resourceScore) + Double(game.freeIDs(in:state).count)*0.3
        }
        // Keep the same integer arithmetic order without overloading one long
        // expression; Xcode 26.6 otherwise exceeds its type-checking budget.
        var score = state.matches * 40
        score += goals * 22
        score += state.energy * 2
        score -= state.tray.count * 9
        score -= state.shifts * 2
        score += pairs * 2
        return Double(score) + Double(game.freeIDs(in:state).count) * 0.3
    }
    public static func solve(_ game:StarRail.Game,nodeLimit:Int=100_000,maxShifts:Int?=nil,maxPeak:Int?=nil,firstDeparture:Int?=nil,firstDepartureRail:Int=0) -> Result {
        var visited:[Key:Int]=[:],path:[StarRail.Action]=[],answer:[StarRail.Action]?
        var nodes=0, exhausted=false
        func search(_ state:StarRail.State) -> Bool {
            if state.shifts > (maxShifts ?? 256) || state.peak > (maxPeak ?? 6) { return false }
            if game.status(of:state) == .won { answer=path;return true }
            guard game.status(of:state) == .playing else { return false }
            let key=Key(state,game:game)
            if let previous=visited[key],previous<=state.shifts { return false }
            guard nodes<nodeLimit else { exhausted=true;return false }
            visited[key]=state.shifts;nodes+=1
            let next=game.legalActions(in:state).compactMap { action -> (StarRail.Action,StarRail.State,Double)? in
                if let firstDeparture, game.stage.rails.indices.contains(firstDepartureRail), game.stage.rails[firstDepartureRail].stopCount == 3,
                   state.arrivals & (game.stage.arrivalBit(rail: firstDepartureRail, stop: 1) | game.stage.arrivalBit(rail: firstDepartureRail, stop: 2)) == 0,
                   case .travel(let rail, let to) = action, rail == firstDepartureRail, to != firstDeparture { return nil }
                guard let target=game.transition(action,from:state) else { return nil }
                return (action,target,utility(target,game:game))
            }.enumerated().sorted { a,b in a.element.2 == b.element.2 ? a.offset<b.offset : a.element.2>b.element.2 }
            for entry in next {
                path.append(entry.element.0)
                if search(entry.element.1) { return true }
                path.removeLast()
                if exhausted { return false }
            }
            return false
        }
        _=search(game.state)
        if let answer { return .solved(answer,nodes:nodes) }
        return exhausted ? .budgetExceeded(nodes:nodes) : .noPathWithinConstraints(nodes:nodes)
    }

    /// Offline journey audit: first seek a route without relying on carried energy.
    /// Higher starting energy changes greedy ordering dramatically, although every
    /// zero-energy solution remains legal. Replay the witness against the actual
    /// state before returning it; no solution table or seed generator is consulted.
    public static func solveJourney(_ game:StarRail.Game,nodeLimit:Int=30_000) -> Result {
        let limit=game.stage.plannedMoves, peak=game.stage.targetPeak
        if let c=game.stage.journey, c.openingEnergy > 0 {
            var stage=game.stage
            stage.journey=StarJourney.Configuration(runID:c.runID,ability:c.ability,chapter:c.chapter,route:c.route,openingEnergy:0)
            var conservative=StarRail.Game(stage:stage)
            if game.actions.allSatisfy({ conservative.perform($0) }),
               case .solved(let actions,let nodes)=solve(conservative,nodeLimit:nodeLimit,maxShifts:limit,maxPeak:peak) {
                var actual=game
                if actions.allSatisfy({ actual.perform($0) }), actual.status == .won,
                   actual.state.shifts <= limit, actual.state.peak <= peak { return .solved(actions,nodes:nodes) }
            }
        }
        return solve(game,nodeLimit:nodeLimit,maxShifts:limit,maxPeak:peak)
    }

    public enum Strategy:String,CaseIterable,Sendable { case random,greedy,lookahead }
    public struct Trial: Equatable, Sendable {
        public let won:Bool
        public let actions:[StarRail.Action]
        public let shifts:Int
        public let peak:Int
        public let stars:Int
    }
    /// Greedy uses one action; lookahead evaluates three actions with a
    /// six-state beam. Random seed changes tie breaks, never the level layout.
    public static func play(_ original:StarRail.Game,strategy:Strategy,seed:UInt64) -> Trial {
        var game=original,random=SeededRandom(seed:seed)
        func estimate(_ state:StarRail.State,depth:Int) -> Double {
            if depth==0 || game.status(of:state) != .playing { return utility(state,game:game) }
            var ranked: [(state: StarRail.State, score: Double, order: Int)] = []
            for (index, action) in game.legalActions(in: state).enumerated() {
                if let next = game.transition(action, from: state) {
                    ranked.append((next, utility(next, game: game), index))
                }
            }
            ranked.sort { a, b in a.score == b.score ? a.order < b.order : a.score > b.score }
            var best: Double?
            for candidate in ranked.prefix(6) {
                let score = estimate(candidate.state, depth: depth - 1)
                best = max(best ?? -Double.infinity, score)
            }
            return best ?? utility(state, game: game)
        }
        for _ in 0..<128 where game.status == .playing {
            var actions=game.legalActions(in:game.state);random.shuffle(&actions)
            guard !actions.isEmpty else { break }
            let action:StarRail.Action
            if strategy == .random { action=actions[0] }
            else {
                var best = -Double.infinity; var selected=actions[0]
                for candidate in actions {
                    guard let next=game.transition(candidate,from:game.state) else { continue }
                    let value=strategy == .greedy ? utility(next,game:game) : estimate(next,depth:2)
                    if value>best { best=value;selected=candidate }
                }
                action=selected
            }
            guard game.perform(action) else { break }
        }
        return Trial(won:game.status == .won,actions:game.actions,shifts:game.state.shifts,peak:game.state.peak,stars:game.stars)
    }
}
