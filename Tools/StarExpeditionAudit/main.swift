import Foundation
import Dispatch
import ShiftCore

// swift run -c release StarExpeditionAudit [automatic strategies per stage]
// Tests each fork/endpoint separately; no solver or solution is consulted at play time.
let samples = max(0, min(100, Int(CommandLine.arguments.dropFirst().first ?? "0") ?? 0))
var rows: [[String: Any]] = []
var allSolved = true
var verifiedRoutes = 0
var completedSave = StarRail.ExpeditionSave()
for expedition in StarRail.Expedition.all {
    let game = StarRail.Game(stage: expedition.stage)
    var paths: [[String: Any]] = []
    for rail in game.stage.rails where rail.stopCount == 3 {
        for stop in 1...2 {
            var path: [String: Any] = ["rail": rail.id, "firstDeparture": stop]
            switch StarRailSolver.solve(game, nodeLimit: 5_000, maxShifts: game.stage.plannedMoves,
                                       maxPeak: game.stage.targetPeak, firstDeparture: stop, firstDepartureRail: rail.id) {
            case .solved(let actions, let nodes):
                var replay = game
                var trace: [[String: Any]] = []
                for action in actions {
                    precondition(replay.perform(action))
                    precondition(replay.state.remaining.nonzeroBitCount + replay.state.tray.count + replay.state.matches*3 == game.stage.cards.count)
                    let board = replay.board(in: replay.state)
                    for a in board { for b in board where a.id < b.id && a.z == b.z { precondition(!replay.overlaps(a,b,in:replay.state)) } }
                    trace.append(["action": String(describing: action), "tray": replay.state.tray, "energy": replay.state.energy, "positions": replay.state.positions])
                }
                precondition(replay.status == .won && replay.stars == 3)
                precondition(actions.first(where: { if case .travel(let id, let to) = $0 { return id == rail.id && to > 0 }; return false }) == .travel(rail: rail.id, to: stop))
                precondition(StarRail.Game(archive: replay.archive) == replay)
                verifiedRoutes += 1
                precondition(completedSave.keep(replay))
                path["status"] = "solved"; path["nodes"] = nodes; path["trace"] = trace
                path["peak"] = replay.state.peak; path["shifts"] = replay.state.shifts; path["energySpent"] = replay.state.spentEnergy
            case .budgetExceeded(let nodes): path["status"] = "budgetExceeded"; path["nodes"] = nodes; allSolved = false
            case .noPathWithinConstraints(let nodes): path["status"] = "noPathWithinConstraints"; path["nodes"] = nodes; allSolved = false
            }
            paths.append(path)
        }
    }
    let strategies: [[String: Any]] = StarRailSolver.Strategy.allCases.map { strategy in
        let results = (0..<samples).map { StarRailSolver.play(game, strategy: strategy, seed: UInt64($0 + 1)) }
        return ["strategy": strategy.rawValue, "trials": samples, "wins": results.filter(\.won).count, "threeStars": results.filter { $0.stars == 3 }.count]
    }
    rows.append(["code": expedition.code, "template": expedition.template, "stage": game.stage.id,
                 "cards": game.stage.cards.count, "routes": paths, "strategies": strategies])
    FileHandle.standardError.write(Data("Audited \(expedition.code)\n".utf8))
}
var encodingNanos: [UInt64] = []
var encodedBytes = 0
for _ in 0..<200 {
    let start = DispatchTime.now().uptimeNanoseconds
    let data = completedSave.encoded()!
    encodingNanos.append(DispatchTime.now().uptimeNanoseconds - start)
    encodedBytes = data.count
}
encodingNanos.sort()
precondition(StarRail.ExpeditionSave(data: completedSave.encoded()!) == completedSave)
let benchmark: [String: Any] = ["records": completedSave.best.count, "bytes": encodedBytes,
    "iterations": encodingNanos.count, "medianMilliseconds": Double(encodingNanos[100])/1_000_000,
    "p95Milliseconds": Double(encodingNanos[190])/1_000_000, "scope": "Linux optimized JSON encode only; not iOS frame timing"]
let report: [String: Any] = ["catalog": "XP1", "allSolved": allSolved, "verifiedRoutes": verifiedRoutes,
                           "saveEncoding": benchmark, "automaticSamplesPerStrategy": samples, "humanCalibration": "excluded-by-user", "stages": rows]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]))
FileHandle.standardOutput.write(Data("\n".utf8))
if !allSolved { exit(1) }
