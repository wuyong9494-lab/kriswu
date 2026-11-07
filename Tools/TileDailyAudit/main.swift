import Foundation
import ShiftCore

let arguments = CommandLine.arguments
let dayIndex = arguments.firstIndex(of: "--days")
let days = min(14, max(1, dayIndex.flatMap { $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil } ?? 7))
let depthEdition = arguments.contains("--depth")
let start = depthEdition ? TileGame.dailyDepthStart : DayKey(year: 2026, month: 11, day: 7)
var rows: [[String: Any]] = []
var invalid = false
for offset in 0..<days {
    let day = start.adding(days: offset, calendar: .dayMath)
    let began = Date()
    let old = depthEdition ? nil : TileGame.dailyPlanningSelection(day)
    let depth = depthEdition ? TileGame.dailyDepthSelection(day) : nil
    let seed = depth?.seed ?? old!.seed
    let qualified = depth?.phaseDepthVerified ?? old!.planningGapVerified
    let checked = depth?.candidatesChecked ?? old!.candidatesChecked
    let expanded = depth?.expanded ?? old!.expanded
    if depthEdition {
        if TileGame.dailyDepthSeed(day) != seed { invalid = true }
    } else if day < TileGame.dailyDepthStart, TileGame.dailyPlanningSeed(day) != seed { invalid = true }
    let baselineSeed = TileGame.dailyMasterSeed(day)
    let baseline = TileGame(level: .hard, seed: baselineSeed, ruleSet: .constellation)
    let game = TileGame(level: .hard, seed: seed, ruleSet: .constellation)
    let narrow = game.planningProbe(width: 4, nodeLimit: 16000)
    let wide = game.planningProbe(width: 32, nodeLimit: 100000)
    let baselineWide = baselineSeed == seed ? wide : baseline.planningProbe(width: 32, nodeLimit: 100000)
    var replay = game
    var legal = true
    for id in wide.solution {
        if !replay.pick(id) { legal = false; break }
        replay.settle()
    }
    let replayValid = wide.won && legal && replay.status == .won
    let forks = depthEdition ? game.planningPhaseForks(along: wide.solution) : game.planningForks(along: wide.solution)
    let phases = Set(forks.map { ($0.pickNumber - 1) * 3 / max(1, wide.solution.count) })
    let separated = zip(forks, forks.dropFirst()).allSatisfy { pair in
        pair.1.pickNumber - pair.0.pickNumber >= max(6, wide.solution.count / 4)
    }
    func forcedLoss(_ state: TileGame, picks: Int) -> Bool {
        if state.status == .lost { return true }
        if state.status == .won || picks == 0 { return false }
        let ids = state.freeIDs.sorted()
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { id in
            var next = state
            guard next.pick(id) else { return false }
            next.settle()
            return forcedLoss(next, picks: picks - 1)
        }
    }
    let witnessesValid = forks.allSatisfy { fork in
        var alternative = game
        for id in wide.solution.prefix(fork.pickNumber - 1) {
            guard alternative.pick(id) else { return false }
            alternative.settle()
        }
        if depthEdition {
            guard let bad = alternative.board.first(where: { $0.id == fork.losingTile }),
                  let good = alternative.board.first(where: { $0.id == fork.winningTile }),
                  alternative.tray.filter({ $0.kind == bad.kind }).count == 1,
                  alternative.tray.filter({ $0.kind == good.kind }).count < 2 else { return false }
        }
        guard alternative.pick(fork.losingTile) else { return false }
        alternative.settle()
        return alternative.status == .playing && forcedLoss(alternative, picks: 2)
    }
    if !witnessesValid || (depthEdition && (!separated || phases.count != forks.count)) { invalid = true }
    if depthEdition && (narrow.won || narrow.budgetReached) { invalid = true }
    if wide.won && !replayValid { invalid = true }
    if qualified && (!replayValid || narrow.won || narrow.budgetReached || forks.count < (depthEdition ? 2 : 1)) { invalid = true }
    let row: [String: Any] = [
        "day": day.description, "seed": seed, "baselineSeed": baselineSeed,
        "planningGapVerified": qualified, "phaseDepthVerified": depthEdition && qualified, "criticalForks": forks.count,
        "forks": forks.map { ["pickNumber": $0.pickNumber, "winningTile": $0.winningTile,
                              "losingTile": $0.losingTile, "lossWithinPicks": $0.lossWithinPicks] },
        "forkWitnessesReplayed": witnessesValid, "distinctPhases": phases.count,
        "phaseSpacingVerified": !depthEdition || separated,
        "selectedForks": depth?.forks.count ?? forks.count,
        "candidatesChecked": checked, "expanded": expanded,
        "narrowWon": narrow.won, "narrowBudgetReached": narrow.budgetReached,
        "wideWon": wide.won, "wideBudgetReached": wide.budgetReached,
        "baselineWideWon": baselineWide.won, "winningPathReplayed": replayValid,
        "elapsedSeconds": Date().timeIntervalSince(began)
    ]
    rows.append(row)
    let line = "Daily planning audit \(day): qualified=\(qualified), forks=\(forks.count), narrow=\(narrow.won), wide=\(wide.won), baselineWide=\(baselineWide.won)\n"
    FileHandle.standardError.write(Data(line.utf8))
}
let output: [String: Any] = [
    "edition": depthEdition ? "master-v3" : "master-v2", "sampleDays": days, "valid": !invalid,
    "humanWinRateMeasured": false, "targetFirstAttemptNoToolsWinRate": 0.001,
    "phaseSeparationRequired": depthEdition,
    "qualification": "narrow search fails without budget exhaustion; wider search has a replayed winning path and proven delayed-loss alternatives (edition 3 requires two separate thirds, at least a quarter of the route apart)",
    "days": rows
]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
if invalid { exit(1) }
