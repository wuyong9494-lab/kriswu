import Foundation
import Dispatch
import ShiftCore

// Offline authoring evidence, never called by the app or consulted during play.
let runID = UUID(uuidString:"11111111-1111-1111-1111-111111111111")!
var boards: [[String:Any]] = [], chains: [[String:Any]] = []
func solve(_ initial: StarRail.Game) -> (StarRail.Game, Int, [[String:Any]]) {
    guard case .solved(let actions,let nodes) = StarRailSolver.solveJourney(initial) else {
        fatalError("No three-star solution: \(String(describing:initial.stage.journey))")
    }
    var game = initial
    var trace: [[String:Any]] = []
    for action in actions {
        precondition(game.perform(action))
        let state = game.state
        precondition(state.remaining.nonzeroBitCount + state.tray.count + state.matches*3 == game.stage.cards.count)
        precondition((0...game.stage.energyLimit).contains(state.energy))
        precondition(state.spentEnergy <= game.stage.journey?.energyBudget ?? Int.max)
        if let core = game.stage.journey?.coreID { precondition(game.contains(core,in:state)) }
        let remaining = game.board(in:state)
        for a in remaining { for b in remaining where a.id < b.id && a.z == b.z {
            precondition(!game.overlaps(a,b,in:state))
        } }
        trace.append(["action":String(describing:action),"energy":state.energy,"spentEnergy":state.spentEnergy,
            "tray":state.tray,"positions":state.positions,"gateOpen":game.gateOpen(in:state),"freeReturnUsed":state.freeReturnUsed,"pulseCharge":state.pulseCharge])
    }
    precondition(game.status == .won && game.stars == 3)
    precondition(StarRail.Game(archive:game.archive) == game)
    return (game,nodes,trace)
}
func fingerprint(_ stage: StarRail.Stage) -> String {
    let cards = stage.cards.map { "\($0.kind),\($0.x),\($0.y),\($0.z),\($0.rail ?? -1)" }.joined(separator:";")
    let rails = stage.rails.map { $0.stops.map { "\($0.x),\($0.y)" }.joined(separator:";") }.joined(separator:"|")
    let c = stage.journey!
    let text = "J1|\(c.ability.rawValue)|\(c.chapter)|\(c.route?.rawValue ?? "none")|\(c.openingEnergy)|\(stage.requiredArrivals)|\(stage.plannedMoves)|\(stage.targetPeak)|\(c.energyBudget ?? -1)|\(c.coreID ?? -1)|\(c.gate?.kind ?? -1)|\(cards)|\(rails)"
    return String(text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 })
}
for ability in StarJourney.Ability.allCases {
    for chapter in 0...2 {
        let routes: [StarJourney.Route?] = chapter == 0 ? [nil] : StarJourney.Route.allCases.map(Optional.some)
        let energies = chapter == 0 ? [0] : Array(0...ability.energyLimit)
        for route in routes { for energy in energies {
            let config = StarJourney.Configuration(runID:runID,ability:ability,chapter:chapter,route:route,openingEnergy:energy)
            let (won,nodes,trace) = solve(.init(stage:config.stage))
            boards.append(["ability":ability.rawValue,"chapter":chapter,"route":route?.rawValue ?? "none",
                "openingEnergy":energy,"fingerprint":fingerprint(won.stage),"nodes":nodes,"stars":won.stars,
                "remainingCards":won.state.remaining.nonzeroBitCount,"trace":trace])
            FileHandle.standardError.write(Data("Verified \(ability.rawValue)/\(chapter)/\(route?.rawValue ?? "none")/\(energy): \(nodes) nodes\n".utf8))
        } }
    }
}
var save = StarJourney.Save()
for ability in StarJourney.Ability.allCases { for route in StarJourney.Route.allCases {
    save.start(ability:ability)
    var chapters: [[String:Any]] = []
    for chapter in 0...2 {
        let run = save.active!, initial = run.game
        let (won,_,trace) = solve(initial)
        precondition(save.keep(won,otherStars:12))
        precondition(save.isValid)
        precondition(StarJourney.Save(data:save.encoded()!) == save)
        chapters.append(["chapter":chapter,"openingEnergy":initial.state.energy,"remainingEnergy":won.state.energy,
            "spentEnergy":won.state.spentEnergy,"score":won.stars,"trace":trace])
        if chapter < 2 { precondition(save.advance(route:chapter == 0 ? route : nil)) }
    }
    let reward = save.pendingReward!
    chains.append(["ability":ability.rawValue,"route":route.rawValue,"chapters":chapters,
        "score":save.active!.score,"earned":reward.earned,"totalStars":save.totalStars])
    precondition(save.keep(save.active!.game,otherStars:12))
    precondition(save.pendingReward == reward)
    save.acknowledgeReward(reward.id)
    precondition(save.keep(save.active!.game,otherStars:12) && save.pendingReward == nil)
} }
var encodeNanos: [UInt64] = []
for _ in 0..<200 {
    let start = DispatchTime.now().uptimeNanoseconds
    precondition(save.encoded() != nil)
    encodeNanos.append(DispatchTime.now().uptimeNanoseconds-start)
}
encodeNanos.sort()
let report: [String:Any] = ["catalog":"J1","verifiedBoards":boards.count,"verifiedChains":chains.count,
    "allThreeStar":true,"maximumJourneyStars":save.totalStars,"boards":boards,"chains":chains,
    "humanCalibration":"excluded-by-user","nativeVerification":"separate-Xcode-workflow-required",
    "saveEncoding":["records":save.best.count,"bytes":save.encoded()!.count,"iterations":200,
        "medianMilliseconds":Double(encodeNanos[100])/1_000_000,"p95Milliseconds":Double(encodeNanos[190])/1_000_000,
        "scope":"Linux optimized JSON encoding; not iOS frame timing"]]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]))
FileHandle.standardOutput.write(Data("\n".utf8))
