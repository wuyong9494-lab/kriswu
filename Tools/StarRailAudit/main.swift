import Foundation
import ShiftCore

// Run with `swift run -c release StarRailAudit [trials] [firstSeed] [revision] [--contracts]`. JSON is an evidence
// artifact; no solution is shipped in, or consulted by, the game.
let trials = max(0, Int(CommandLine.arguments.dropFirst().first ?? "20") ?? 20)
let firstSeed = UInt64(CommandLine.arguments.dropFirst(2).first ?? "1") ?? 1
let revision = Int(CommandLine.arguments.dropFirst(3).first ?? "\(StarRail.catalogRevision)") ?? StarRail.catalogRevision
guard [1, StarRail.catalogRevision].contains(revision) else { fatalError("Unknown catalog revision") }
let contracts = CommandLine.arguments.contains("--contracts")
guard !contracts || revision == 2 else { fatalError("Contracts pin catalog revision 2") }
let stages = contracts ? StarRail.Trial.all.map(\.stage) : (1...6).map { StarRail.stage($0, revision: revision)! }
var rows: [[String: Any]] = []
var allSolved = true
for stage in stages {
    let game = StarRail.Game(stage: stage)
    var row: [String: Any] = ["stage": stage.id, "title": stage.title, "cards": stage.cards.count]
    row["contract"] = stage.trial?.rawValue ?? "campaign"
    row["capacity"] = stage.capacity; row["energyLimit"] = stage.energyLimit
    if let limit = stage.shiftLimit { row["shiftLimit"] = limit }
    switch StarRailSolver.solve(game, nodeLimit: 300_000, maxShifts: stage.plannedMoves, maxPeak: stage.targetPeak) {
    case .solved(let actions, let nodes):
        var replay = game
        let trace: [[String: Any]] = actions.map { action in
            precondition(replay.perform(action))
            let label: String
            switch action {
            case .pick(let id): label = "pick:\(id):\(StarRail.names[stage.cards[id].kind])"
            case .travel(let id, let to): label = "travel:\(id):\(to)"
            case .shift(let id): label = "shift:\(id):\(replay.state.positions[id])"
            }
            return ["action": label, "energy": replay.state.energy, "tray": replay.state.tray,
                    "positions": replay.state.positions]
        }
        precondition(replay.status == .won && replay.stars == 3)
        row["solver"] = ["status": "solved", "nodes": nodes, "shifts": replay.state.shifts,
                         "peak": replay.state.peak, "stars": replay.stars, "trace": trace]
    case .budgetExceeded(let nodes):
        row["solver"] = ["status": "budgetExceeded", "nodes": nodes]; allSolved = false
    case .noPathWithinConstraints(let nodes):
        row["solver"] = ["status": "noPathWithinConstraints", "nodes": nodes]; allSolved = false
    }
    row["strategies"] = StarRailSolver.Strategy.allCases.map { strategy in
        let results = (0..<trials).map { StarRailSolver.play(game, strategy: strategy, seed: firstSeed + UInt64($0)) }
        var losses: [String: Int] = [:]
        var firstFailure: [String: Any]?
        for (index, trial) in results.enumerated() where !trial.won {
            var replay = game
            for action in trial.actions { precondition(replay.perform(action)) }
            let reason = replay.state.tray.count >= stage.capacity ? "fullTray"
                : replay.status == .lost ? (stage.revision >= 2 ? "noLegalAction" : "unfinishedRail") : "actionBudget"
            losses[reason, default: 0] += 1
            if firstFailure == nil {
                firstFailure = ["seed": firstSeed + UInt64(index), "reason": reason,
                                "actions": trial.actions.map { String(describing: $0) },
                                "explanation": replay.failureReason(in: replay.state) ?? "Action budget exhausted"]
            }
        }
        var summary: [String: Any] = ["strategy": strategy.rawValue, "trials": trials,
                                     "wins": results.filter(\.won).count,
                                     "threeStars": results.filter { $0.stars == 3 }.count, "losses": losses]
        if let firstFailure { summary["firstFailure"] = firstFailure }
        return summary
    }
    rows.append(row)
    FileHandle.standardError.write(Data("Audited stage \(stage.id) \(stage.trial?.rawValue ?? "campaign")\n".utf8))
}
let report: [String: Any] = ["version": StarRail.version, "catalogRevision": revision,
                           "contracts": contracts, "firstSeed": firstSeed, "trialsPerStrategy": trials, "allSolved": allSolved, "stages": rows]
let output = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))
if !allSolved { exit(1) }
