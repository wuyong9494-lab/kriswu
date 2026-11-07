import Foundation
import ShiftCore

let arguments = CommandLine.arguments
let dayIndex = arguments.firstIndex(of: "--days")
let days = min(14, max(1, dayIndex.flatMap { $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil } ?? 7))
let start = DayKey(year: 2026, month: 11, day: 7)
var rows: [[String: Any]] = []
var invalid = false
for offset in 0..<days {
    let day = start.adding(days: offset, calendar: .dayMath)
    let began = Date()
    let selection = TileGame.dailyPlanningSelection(day)
    let baselineSeed = TileGame.dailyMasterSeed(day)
    let baseline = TileGame(level: .hard, seed: baselineSeed, ruleSet: .constellation)
    let game = TileGame(level: .hard, seed: selection.seed, ruleSet: .constellation)
    let narrow = game.planningProbe(width: 4, nodeLimit: 16000)
    let wide = game.planningProbe(width: 32, nodeLimit: 100000)
    let baselineWide = baselineSeed == selection.seed ? wide : baseline.planningProbe(width: 32, nodeLimit: 100000)
    var replay = game
    var legal = true
    for id in wide.solution {
        if !replay.pick(id) { legal = false; break }
        replay.settle()
    }
    let replayValid = wide.won && legal && replay.status == .won
    let forks = game.planningForks(along: wide.solution)
    if wide.won && !replayValid { invalid = true }
    if selection.planningGapVerified && (!replayValid || narrow.won || narrow.budgetReached || forks.isEmpty) { invalid = true }
    let row: [String: Any] = [
        "day": day.description, "seed": selection.seed, "baselineSeed": baselineSeed,
        "planningGapVerified": selection.planningGapVerified, "criticalForks": forks.count,
        "candidatesChecked": selection.candidatesChecked, "expanded": selection.expanded,
        "narrowWon": narrow.won, "narrowBudgetReached": narrow.budgetReached,
        "wideWon": wide.won, "wideBudgetReached": wide.budgetReached,
        "baselineWideWon": baselineWide.won, "winningPathReplayed": replayValid,
        "elapsedSeconds": Date().timeIntervalSince(began)
    ]
    rows.append(row)
    let line = "Daily planning audit \(day): qualified=\(selection.planningGapVerified), forks=\(forks.count), narrow=\(narrow.won), wide=\(wide.won), baselineWide=\(baselineWide.won)\n"
    FileHandle.standardError.write(Data(line.utf8))
}
let output: [String: Any] = [
    "edition": "master-v2", "sampleDays": days, "valid": !invalid,
    "humanWinRateMeasured": false, "targetFirstAttemptNoToolsWinRate": 0.001,
    "qualification": "narrow search fails without budget exhaustion; wider search has a replayed winning path and at least one proven delayed-loss alternative",
    "days": rows
]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
if invalid { exit(1) }
