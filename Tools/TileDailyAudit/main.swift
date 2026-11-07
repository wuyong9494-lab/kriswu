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
    if TileGame.dailyPlanningSeed(day) != seed { invalid = true }
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
    if wide.won && !replayValid { invalid = true }
    if qualified && (!replayValid || narrow.won || narrow.budgetReached || forks.count < (depthEdition ? 2 : 1)) { invalid = true }
    let row: [String: Any] = [
        "day": day.description, "seed": seed, "baselineSeed": baselineSeed,
        "planningGapVerified": qualified, "phaseDepthVerified": depthEdition && qualified, "criticalForks": forks.count,
        "forks": forks.map { ["pickNumber": $0.pickNumber, "winningTile": $0.winningTile,
                              "losingTile": $0.losingTile, "lossWithinPicks": $0.lossWithinPicks] },
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
