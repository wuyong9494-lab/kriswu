import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import UIKit
@testable import ShiftReminder

/// 数传计划的文字识别准确率：合成的「拍屏幕」照片（scripts/make_ocr_samples.py 生成，虚构数据）在模拟器里真的认一遍，
/// 和标准答案比。结果打印成 OCR| 开头的行（CI 里变成注解，方便对比几种认法）。
/// 识别失败、空结果、完全无法对应真值会失败；字段准确率按全部标准行报告，不用格式正确替代精度验收。
final class PlanReaderTests: XCTestCase {
    private struct Truth: Decodable {
        struct Row: Decodable {
            let satellite, station, orbit, start, end: String
            let emergency: Bool?
        }
        let kind: String
        let rules: [String: [String]]
        let rows: [Row]
    }

    func testSplitRereadBudgetIsSharedAcrossEveryPassAndStrip() {
        let samples: [(width: Int, height: Int, strips: Int)] = [
            (4032, 3024, 7), (3400, 1912, 4), (4032, 3024, 7), (1170, 7536, 6),
        ]
        for sample in samples {
            let count = PassPlan.strips(width: sample.width, height: sample.height).count
            XCTAssertEqual(count, sample.strips)
            let budgets = PlanReader.splitRereadBudgets(total: 400, stripCounts: [count, count, 1])
            XCTAssertEqual(budgets.map(\.count), [count, count, 1])
            XCTAssertEqual(budgets.flatMap { $0 }.reduce(0, +), 400, "不是每段各自获得400次")
            let passTotals = budgets.map { $0.reduce(0, +) }
            XCTAssertLessThanOrEqual((passTotals.max() ?? 0) - (passTotals.min() ?? 0), 1)
            for pass in budgets {
                XCTAssertLessThanOrEqual((pass.max() ?? 0) - (pass.min() ?? 0), 1, "各段都有固定公平份额")
            }
        }
        XCTAssertEqual(PlanReader.splitRereadBudgets(total: 400, stripCounts: [7, 7, 1]), [
            [20, 19, 19, 19, 19, 19, 19], [19, 19, 19, 19, 19, 19, 19], [133],
        ], "分配顺序固定，不取决于并发任务谁先完成")
    }

    func testSplitRereadBudgetCannotSpendAnIncompleteGroup() {
        var budget = PlanReader.SplitRereadBudget(limit: 5)
        XCTAssertTrue(budget.reserve(groupSize: 3))
        XCTAssertEqual(budget.used, 3)
        XCTAssertFalse(budget.reserve(groupSize: 3), "余量不够整组则不拆，调用方保留原框")
        XCTAssertEqual(budget.used, 3, "不允许只花剩下的两次、丢掉第三块")
        XCTAssertTrue(budget.reserve(groupSize: 2))
        XCTAssertEqual(budget.used, 5)
        XCTAssertFalse(budget.reserve(groupSize: 1))
        XCTAssertEqual(budget.used, 5)
    }

    func testZeroAndSmallSplitRereadBudgetsStayWithinThePhotoLimit() {
        let zero = PlanReader.splitRereadBudgets(total: 0, stripCounts: [7, 7, 1])
        XCTAssertTrue(zero.flatMap { $0 }.allSatisfy { $0 == 0 })
        let small = PlanReader.splitRereadBudgets(total: 2, stripCounts: [7, 7, 1])
        XCTAssertEqual(small.flatMap { $0 }.reduce(0, +), 2)
        var budget = PlanReader.SplitRereadBudget(limit: 0)
        XCTAssertFalse(budget.reserve(groupSize: 2))
        XCTAssertEqual(budget.used, 0)
        XCTAssertEqual(PlanReader.splitRereadBudgets(total: 400, stripCounts: []), [])
        XCTAssertFalse(PlanReader.Settings.standard.diagnostics, "正式使用默认不输出诊断日志")
    }

    func testRecognitionAccuracy() async throws {
        let bundle = Bundle(for: Self.self)
        // 模拟器里认字很慢（没有神经网络芯片），只跑现在的认法；要比较几种认法时在这里加
        let variants: [(String, PlanReader.Settings)] = [
            ("现在", .standard),
        ]
        for name in ["excel_photo", "excel_scan", "web_photo", "long_table"] {
            guard let imageURL = bundle.url(forResource: name, withExtension: "jpg"),
                  let truthURL = bundle.url(forResource: name, withExtension: "json"),
                  let image = UIImage(contentsOfFile: imageURL.path) else {
                XCTFail("缺测试图 \(name)")
                continue
            }
            let truth = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: truthURL))
            let rules = truth.rules.sorted { $0.key < $1.key }.map { PassPlan.OperatorRule(name: $0.key, prefixes: $0.value) }
            for (label, settings) in variants {
                let began = Date()
                var diagnosed = settings
                diagnosed.diagnostics = true
                let width = image.cgImage?.width ?? 0, height = image.cgImage?.height ?? 0
                print("OCRSTART|\(name)|\(label)|size=\(width)x\(height)|truthRows=\(truth.rows.count)")
                do {
                    let reading = try await PlanReader.read(pages: [image], rules: rules, settings: diagnosed)
                    dumpSyntheticRows(name, reading, rules)
                    let measured = accuracy(reading, truth, rules)
                    print(report(name, label, reading, truth, rules, seconds: Date().timeIntervalSince(began)))
                    XCTAssertNotNil(reading.layout, "\(name)：缺少表头布局")
                    XCTAssertFalse(reading.rows.isEmpty, "\(name)：没有读出计划行")
                    XCTAssertGreaterThan(measured.matched, 0, "\(name)：没有一条能唯一对应标准答案")
                    XCTAssertEqual(measured.unsafeEligibleRows, 0,
                                   "\(name)：\(measured.eligibleWrongCriticalRows) 条可发送结果的关键字段错误，"
                                   + "\(measured.eligibleUnmatched) 条可发送结果无法唯一对应真值；须保留核对或修正识别")
                    if let layout = reading.layout {
                        for row in reading.rows where !PassPlan.isExcludedFromSending(row)
                            && PlanReader.identifierColumn(for: row, layout: layout) != nil {
                            XCTAssertFalse(PassPlan.problems(row, rules: rules, layout: layout).isEmpty,
                                           "\(name)：照片编号在人工确认前不能仅凭多次 OCR 一致而放行")
                        }
                    }
                    if label == "现在" { await dumpOriginal(name, reading, rules) }
                } catch {
                    print("OCR|\(name)|\(label)|认不出：\(error.localizedDescription)")
                    XCTFail("\(name) / \(label) 识别失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 只由上面固定的公开虚构样例调用；保留全图最终字段，避免把单个首段当成整图结果。
    private func dumpSyntheticRows(_ fixture: String, _ reading: PassPlan.Reading, _ rules: [PassPlan.OperatorRule]) {
        guard ["excel_photo", "excel_scan", "web_photo", "long_table"].contains(fixture) else { return }
        for (index, row) in reading.rows.enumerated() {
            let emergency: Any = PassPlan.emergency(row, layout: reading.layout).map { $0 as Any } ?? NSNull()
            let fields: [String: Any] = [
                "index": index, "satellite": row.satellite, "satelliteID": row.satelliteID,
                "station": row.station, "orbit": row.orbit, "start": row.start, "end": row.end,
                "status": row.status, "emergency": emergency, "issues": row.recognitionIssues ?? [],
                "problems": PassPlan.problems(row, rules: rules, layout: reading.layout),
                "excluded": PassPlan.isExcludedFromSending(row),
                "operator": PassPlan.operatorName(of: row.station, rules: rules).map { $0 as Any } ?? NSNull(),
            ]
            if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
                print("OCRROW|\(fixture)|\(String(decoding: data, as: UTF8.self))")
            }
        }
    }

    /// 发原图：第一家拼出来的图（缩小）打到日志里看裁得对不对，再数一下几行有原图
    private func dumpOriginal(_ name: String, _ reading: PassPlan.Reading, _ rules: [PassPlan.OperatorRule]) async {
        let withStrip = reading.rows.filter { $0.region.flatMap { reading.strips[$0] } != nil }.count
        print("OCRSTRIPS|\(name)|有原图 \(withStrip)/\(reading.rows.count)|表头 \(reading.header.flatMap { reading.strips[$0] } != nil)")
        guard let group = PassPlan.grouped(reading.rows, rules: rules).first(where: { $0.name != PassPlan.unassigned }) else { return }
        let data: Data? = await MainActor.run {
            guard let image = PassPlanOriginal.image(name: group.name, rows: group.rows, header: reading.header,
                                                     strips: reading.strips, caption: "麻烦确认一下数传计划") else { return nil }
            let width = min(1100, image.size.width)
            let size = CGSize(width: width, height: image.size.height * width / image.size.width)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                .jpegData(compressionQuality: 0.6)
        }
        if let data { print("OCRIMG|\(name)|\(data.base64EncodedString())") }
    }

    private struct Accuracy {
        var matched = 0
        var station = 0
        var satellite = 0
        var orbit = 0
        var start = 0
        var end = 0
        var endTotal = 0
        var family = 0
        var emergency = 0
        var emergencyTotal = 0
        var emergencyUnknown = 0
        var ambiguous = 0
        var eligible = 0
        var reviewRequired = 0
        var excluded = 0
        var eligiblePaired = 0
        var eligibleWrongCriticalRows = 0
        var eligibleUnmatched = 0
        var criticalErrors: [String: Int] = [:]

        var unsafeEligibleRows: Int { eligibleWrongCriticalRows + eligibleUnmatched }
    }

    /// 一条实际结果最多对应一条真值。四个身份线索至少三个一致，且双方的最佳候选都唯一，
    /// 才算找到这条；结束时间不参与配对，避免把结束时间识错隐藏在漏行里。
    /// 不能只用开始时间：不同卫星/地面站可以同时开始。
    private func accuracy(_ reading: PassPlan.Reading, _ truth: Truth,
                          _ rules: [PassPlan.OperatorRule]) -> Accuracy {
        func identityScore(_ expected: Truth.Row, _ row: PassPlanRow) -> Int {
            let sameSatellite = !expected.satellite.isEmpty
                && (row.satellite == expected.satellite || row.satelliteID == expected.satellite)
            return [sameSatellite,
                    !expected.orbit.isEmpty && row.orbit == expected.orbit,
                    !expected.station.isEmpty && row.station == expected.station,
                    !expected.start.isEmpty && row.start == expected.start].filter { $0 }.count
        }
        let scores = truth.rows.map { expected in reading.rows.map { identityScore(expected, $0) } }
        var measured = Accuracy()
        let excluded = reading.rows.map(PassPlan.isExcludedFromSending)
        let problems = reading.rows.map { PassPlan.problems($0, rules: rules, layout: reading.layout) }
        let eligible = Set(reading.rows.indices.filter { !excluded[$0] && problems[$0].isEmpty })
        measured.excluded = excluded.filter { $0 }.count
        measured.eligible = eligible.count
        measured.reviewRequired = reading.rows.count - measured.excluded - measured.eligible
        var pairedEligible = Set<Int>()
        // 分母来自全部真值；漏掉的行、没认出的“否”都不能从分母中消失。
        measured.endTotal = truth.rows.filter { !$0.end.isEmpty }.count
        measured.emergencyTotal = truth.rows.filter { $0.emergency != nil }.count
        for (t, expected) in truth.rows.enumerated() {
            guard let best = scores[t].max(), best >= 3 else { continue }
            let candidates = reading.rows.indices.filter { scores[t][$0] == best }
            guard candidates.count == 1, let index = candidates.first else {
                measured.ambiguous += 1
                continue
            }
            let reverseBest = truth.rows.indices.map { scores[$0][index] }.max() ?? 0
            let reverse = truth.rows.indices.filter { scores[$0][index] == reverseBest }
            guard reverse.count == 1, reverse.first == t else {
                measured.ambiguous += 1
                continue
            }
            let row = reading.rows[index]
            measured.matched += 1
            if eligible.contains(index) {
                pairedEligible.insert(index)
                measured.eligiblePaired += 1
                let wrong = criticalMismatches(row, expected: expected, layout: reading.layout, rules: rules)
                if !wrong.isEmpty { measured.eligibleWrongCriticalRows += 1 }
                for field in wrong { measured.criticalErrors[field, default: 0] += 1 }
            }
            if row.station == expected.station { measured.station += 1 }
            if row.satellite == expected.satellite || row.satelliteID == expected.satellite { measured.satellite += 1 }
            if row.orbit == expected.orbit { measured.orbit += 1 }
            if row.start == expected.start { measured.start += 1 }
            if !expected.end.isEmpty, row.end == expected.end { measured.end += 1 }
            if let want = PassPlan.operatorName(of: expected.station, rules: rules),
               PassPlan.operatorName(of: row.station, rules: rules) == want { measured.family += 1 }
            if let want = expected.emergency {
                if let actual = PassPlan.emergency(row, layout: reading.layout) {
                    if actual == want { measured.emergency += 1 }
                } else {
                    measured.emergencyUnknown += 1
                }
            }
        }
        measured.eligibleUnmatched = eligible.subtracting(pairedEligible).count
        return measured
    }

    /// 发送保护按原始真值逐项比较；显式卫星 ID 优先，名称字段相似不能替它掩盖错误。
    /// 只检查真值实际提供的结束时间/应急；缺失、不确定的结果仍由 problems 归入待核对。
    private func criticalMismatches(_ row: PassPlanRow, expected: Truth.Row, layout: PassPlan.Layout?,
                                    rules: [PassPlan.OperatorRule]) -> [String] {
        var wrong: [String] = []
        let identifier = row.satelliteID.isEmpty ? row.satellite : row.satelliteID
        if identifier != expected.satellite { wrong.append("identifier") }
        if row.station != expected.station { wrong.append("station") }
        if PassPlan.operatorName(of: row.station, rules: rules) != PassPlan.operatorName(of: expected.station, rules: rules) {
            wrong.append("operator")
        }
        if row.orbit != expected.orbit { wrong.append("orbit") }
        if row.start != expected.start { wrong.append("start") }
        if !expected.end.isEmpty, row.end != expected.end { wrong.append("end") }
        if let expectedEmergency = expected.emergency, PassPlan.emergency(row, layout: layout) != expectedEmergency {
            wrong.append("emergency")
        }
        return wrong
    }

    private func report(_ name: String, _ label: String, _ reading: PassPlan.Reading, _ truth: Truth,
                        _ rules: [PassPlan.OperatorRule], seconds: Double) -> String {
        let measured = accuracy(reading, truth, rules)
        let total = truth.rows.count
        let included = reading.rows.count - measured.excluded
        let criticalDetails = measured.criticalErrors.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        // 真值未提供状态列，这里只报告非空覆盖，不能称为状态正确率或发送通过率。
        let statusCoverage: String
        if reading.layout?.columns.contains(.status) == true {
            let present = reading.rows.filter { !$0.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            statusCoverage = "\(present)/\(reading.rows.count)"
        } else {
            statusCoverage = "-"
        }
        func pct(_ n: Int, _ of: Int) -> String { of == 0 ? "-" : "\(n * 100 / of)%（\(n)/\(of)）" }
        return ["OCR", name, label,
                "唯一对应行 \(measured.matched)/\(total)",
                "站名 \(pct(measured.station, total))", "分家 \(pct(measured.family, total))",
                "卫星 \(pct(measured.satellite, total))", "圈号 \(pct(measured.orbit, total))",
                "开始时间 \(pct(measured.start, total))", "结束时间 \(pct(measured.end, measured.endTotal))",
                "应急 \(pct(measured.emergency, measured.emergencyTotal))", "应急未知 \(measured.emergencyUnknown)",
                "非空状态 \(statusCoverage)",
                "漏行或无法对应 \(total - measured.matched)", "身份歧义 \(measured.ambiguous)",
                "多出或无法对应 \(reading.rows.count - measured.matched)",
                "可发送 \(measured.eligible)/\(included)", "待核对 \(measured.reviewRequired)/\(included)",
                "test排除 \(measured.excluded)", "可发送且唯一对应 \(measured.eligiblePaired)/\(measured.eligible)",
                "可发送关键字段错误 \(measured.eligibleWrongCriticalRows)",
                "可发送无法唯一对应 \(measured.eligibleUnmatched)",
                "可发送错误字段 \(criticalDetails.isEmpty ? "无" : criticalDetails)",
                String(format: "%.1f 秒", seconds)].joined(separator: "|")
    }

    func testAccuracyDoesNotReuseRowsWithTheSameStartTime() {
        let time = "2026-10-27 10:00:00"
        let truth = Truth(kind: "test", rules: [:], rows: [
            Truth.Row(satellite: "SAT-A", station: "甲站-01", orbit: "100", start: time, end: "", emergency: false),
            Truth.Row(satellite: "SAT-B", station: "乙站-02", orbit: "200", start: time, end: "", emergency: false),
        ])
        let row = PassPlanRow(orbit: "100", satellite: "SAT-A", station: "甲站-01", start: time)
        let reading = PassPlan.Reading(rows: [row], layout: nil)
        let result = accuracy(reading, truth, [])
        XCTAssertEqual(result.matched, 1)
        XCTAssertEqual(result.satellite, 1)
        XCTAssertEqual(result.emergencyTotal, 2)
        XCTAssertEqual(result.emergency, 0, "未知应急不能算作识对了非应急")
        XCTAssertEqual(result.emergencyUnknown, 1)
        XCTAssertTrue(report("test", "test", reading, truth, [], seconds: 0).contains("卫星 50%（1/2）"))
    }

    func testAccuracyMeasuresWrongTimesAndUnknownEmergency() {
        let expected = Truth.Row(satellite: "SAT-A", station: "甲站-01", orbit: "100",
                                 start: "2026-10-27 10:00:00", end: "2026-10-27 10:05:00", emergency: false)
        let truth = Truth(kind: "test", rules: [:], rows: [expected])
        let row = PassPlanRow(orbit: "100", satellite: "SAT-A", station: "甲站-01",
                              start: "2026-10-27 10:00:08", end: "2026-10-27 10:05:08", cells: ["看不清"])
        let layout = PassPlan.Layout(slots: [.init(label: "是否应急", column: nil, x: 0)])
        let result = accuracy(PassPlan.Reading(rows: [row], layout: layout), truth, [])
        XCTAssertEqual(result.matched, 1)
        XCTAssertEqual(result.start, 0)
        XCTAssertEqual(result.end, 0)
        XCTAssertEqual(result.endTotal, 1)
        XCTAssertEqual(result.emergency, 0)
        XCTAssertEqual(result.emergencyUnknown, 1)
    }

    func testAccuracyRejectsAmbiguousDuplicateIdentity() {
        let expected = Truth.Row(satellite: "SAT-A", station: "甲站-01", orbit: "100",
                                 start: "2026-10-27 10:00:00", end: "", emergency: nil)
        let truth = Truth(kind: "test", rules: [:], rows: [expected, expected])
        let row = PassPlanRow(orbit: "100", satellite: "SAT-A", station: "甲站-01", start: expected.start)
        let result = accuracy(PassPlan.Reading(rows: [row], layout: nil), truth, [])
        XCTAssertEqual(result.matched, 0, "一条识别结果不能冒充两条同时开始的计划")
        XCTAssertEqual(result.ambiguous, 2)
    }

    private func dispatchMetricFixture() -> (truth: Truth, reading: PassPlan.Reading, rules: [PassPlan.OperatorRule]) {
        let expected = Truth.Row(satellite: "SAT-A", station: "甲站01", orbit: "100",
                                 start: "2032-04-12 08:00:00", end: "2032-04-12 08:05:00", emergency: true)
        let rules = [PassPlan.OperatorRule(name: "甲", prefixes: ["甲站"]),
                     PassPlan.OperatorRule(name: "乙", prefixes: ["乙站"])]
        let layout = PassPlan.Layout(slots: [
            .init(label: "卫星ID", column: .satelliteID, x: 0.1),
            .init(label: "地面站", column: .station, x: 0.2),
            .init(label: "圈号", column: .orbit, x: 0.3),
            .init(label: "数传开始时间", column: .start, x: 0.4),
            .init(label: "数传结束时间", column: .end, x: 0.5),
            .init(label: "状态", column: .status, x: 0.6),
            .init(label: "是否应急", column: nil, x: 0.7),
        ])
        let row = PassPlanRow(orbit: expected.orbit, satelliteID: expected.satellite, satellite: "合成示例A星",
                              station: expected.station, start: expected.start, end: expected.end,
                              status: "等待数传", cells: [expected.satellite, expected.station, expected.orbit,
                                                      expected.start, expected.end, "等待数传", "是"])
        let truth = Truth(kind: "test", rules: ["甲": ["甲站"], "乙": ["乙站"]], rows: [expected])
        return (truth, PassPlan.Reading(rows: [row], layout: layout), rules)
    }

    func testDispatchMetricsAcceptFullyCorrectPlan() {
        let fixture = dispatchMetricFixture()
        let measured = accuracy(fixture.reading, fixture.truth, fixture.rules)
        XCTAssertEqual(measured.matched, 1)
        XCTAssertEqual(measured.eligible, 1)
        XCTAssertEqual(measured.eligiblePaired, 1)
        XCTAssertEqual(measured.reviewRequired, 0)
        XCTAssertEqual(measured.excluded, 0)
        XCTAssertEqual(measured.unsafeEligibleRows, 0)
        XCTAssertTrue(measured.criticalErrors.isEmpty)
    }

    func testDispatchMetricsRejectValidButWrongCriticalFields() {
        func check(_ field: String, change: (inout PassPlanRow) -> Void) {
            var fixture = dispatchMetricFixture()
            change(&fixture.reading.rows[0])
            let measured = accuracy(fixture.reading, fixture.truth, fixture.rules)
            XCTAssertEqual(measured.eligible, 1, field)
            XCTAssertEqual(measured.reviewRequired, 0, field)
            XCTAssertEqual(measured.eligiblePaired, 1, field)
            XCTAssertEqual(measured.eligibleWrongCriticalRows, 1, field)
            XCTAssertEqual(measured.eligibleUnmatched, 0, field)
            XCTAssertEqual(measured.unsafeEligibleRows, 1, field)
            XCTAssertEqual(measured.criticalErrors[field], 1, field)
        }
        check("identifier") { $0.satelliteID = "SAT-B"; $0.satellite = "SAT-A" }
        check("station") { $0.station = "甲站02" }
        check("operator") { $0.station = "乙站02" }
        check("orbit") { $0.orbit = "101" }
        check("start") { $0.start = "2032-04-12 08:00:01" }
        check("end") { $0.end = "2032-04-12 08:05:01" }
        check("emergency") { $0.cells[6] = "不是" }
    }

    func testDispatchMetricsReportInvalidAndConflictingRowsAsReview() {
        let changes: [(inout PassPlanRow) -> Void] = [
            { $0.start = "2032-04-12 08:00:XX" },
            { $0.end = "2032-04-12 08:05:XX" },
            { $0.orbit = "10O" },
            { $0.station = "未知站" },
            { $0.cells[6] = "" },
            { $0.satelliteID = "SAT-B"; $0.recognitionIssues = ["卫星ID多次识别不一致，请核对原图"] },
            { $0.start = "2032-04-12 08:00:01"; $0.recognitionIssues = ["开始时间多次识别不一致，请核对原图"] },
        ]
        for change in changes {
            var fixture = dispatchMetricFixture()
            change(&fixture.reading.rows[0])
            let measured = accuracy(fixture.reading, fixture.truth, fixture.rules)
            XCTAssertEqual(measured.eligible, 0)
            XCTAssertEqual(measured.reviewRequired, 1)
            XCTAssertEqual(measured.excluded, 0)
            XCTAssertEqual(measured.unsafeEligibleRows, 0, "保护门槛通过仍须报告这一条待核对")
            XCTAssertTrue(measured.criticalErrors.isEmpty)
            let line = report("test", "test", fixture.reading, fixture.truth, fixture.rules, seconds: 0)
            XCTAssertTrue(line.contains("可发送 0/1|待核对 1/1"))
        }
    }

    func testDispatchMetricsRejectUnpairedAndDuplicateEligibleRows() {
        var unknown = dispatchMetricFixture()
        unknown.reading.rows[0].satelliteID = "SAT-B"
        unknown.reading.rows[0].orbit = "101"
        let unmatched = accuracy(unknown.reading, unknown.truth, unknown.rules)
        XCTAssertEqual(unmatched.eligible, 1)
        XCTAssertEqual(unmatched.eligiblePaired, 0)
        XCTAssertEqual(unmatched.eligibleUnmatched, 1)
        XCTAssertEqual(unmatched.unsafeEligibleRows, 1)

        var duplicateRows = dispatchMetricFixture()
        duplicateRows.reading.rows.append(duplicateRows.reading.rows[0])
        let duplicateActual = accuracy(duplicateRows.reading, duplicateRows.truth, duplicateRows.rules)
        XCTAssertEqual(duplicateActual.eligible, 2)
        XCTAssertEqual(duplicateActual.eligibleUnmatched, 2, "两条结果不能共用一条真值")
        XCTAssertEqual(duplicateActual.unsafeEligibleRows, 2)

        let duplicateTruth = dispatchMetricFixture()
        let truth = Truth(kind: "test", rules: duplicateTruth.truth.rules,
                          rows: [duplicateTruth.truth.rows[0], duplicateTruth.truth.rows[0]])
        let ambiguous = accuracy(duplicateTruth.reading, truth, duplicateTruth.rules)
        XCTAssertEqual(ambiguous.eligible, 1)
        XCTAssertEqual(ambiguous.eligibleUnmatched, 1, "一条结果不能对应两条相同真值")
        XCTAssertEqual(ambiguous.unsafeEligibleRows, 1)
    }

    func testDispatchMetricsAcceptIdentifierFallbackAndAbsentOptionalColumns() {
        let fixture = dispatchMetricFixture()
        let base = fixture.truth.rows[0]
        let expected = Truth.Row(satellite: base.satellite, station: base.station, orbit: base.orbit,
                                 start: base.start, end: "", emergency: nil)
        let truth = Truth(kind: "excel", rules: fixture.truth.rules, rows: [expected])
        let layout = PassPlan.Layout(slots: [
            .init(label: "卫星", column: .satellite, x: 0.1),
            .init(label: "地面站", column: .station, x: 0.3),
            .init(label: "圈次", column: .orbit, x: 0.5),
            .init(label: "数传开始", column: .start, x: 0.7),
        ])
        let row = PassPlanRow(orbit: expected.orbit, satellite: expected.satellite,
                              station: expected.station, start: expected.start)
        let measured = accuracy(PassPlan.Reading(rows: [row], layout: layout), truth, fixture.rules)
        XCTAssertEqual(measured.eligible, 1)
        XCTAssertEqual(measured.eligiblePaired, 1)
        XCTAssertEqual(measured.reviewRequired, 0)
        XCTAssertEqual(measured.unsafeEligibleRows, 0, "原表未提供的结束时间/应急不能作为错误")
    }

    func testDispatchMetricsSeparateTestExclusionReviewAndEligibleRows() {
        var fixture = dispatchMetricFixture()
        var review = fixture.reading.rows[0]
        review.orbit = "101"
        review.recognitionIssues = ["圈号多次识别不一致，请核对原图"]
        var excluded = fixture.reading.rows[0]
        excluded.status = "test"
        excluded.satelliteID = "SAT-B"
        excluded.orbit = "102"
        fixture.reading.rows += [review, excluded]
        let measured = accuracy(fixture.reading, fixture.truth, fixture.rules)
        XCTAssertEqual(measured.eligible, 1)
        XCTAssertEqual(measured.eligiblePaired, 1)
        XCTAssertEqual(measured.reviewRequired, 1)
        XCTAssertEqual(measured.excluded, 1)
        XCTAssertEqual(measured.unsafeEligibleRows, 0)
        let line = report("test", "test", fixture.reading, fixture.truth, fixture.rules, seconds: 0)
        XCTAssertTrue(line.contains("可发送 1/2|待核对 1/2|test排除 1"))
    }

    private struct BadgeTruth: Decodable {
        struct Row: Decodable {
            var start: String
            var emergency: Bool
            var excluded: Bool
        }
        var pages: [String]
        var rules: [String: [String]]
        var rows: [Row]
    }

    /// 完全虚构的两页网页：左侧无表头应急、右侧 test、红背景但无标签、信息列里的 test，
    /// 以及重叠页第二次漏掉应急标签。真的走生产 OCR 和跨页合并，不用模拟读数代替。
    func testHeaderlessEmergencyAndTestStatusAcrossPages() async throws {
        let bundle = Bundle(for: Self.self)
        let truthURL = try XCTUnwrap(bundle.url(forResource: "badge_overlap", withExtension: "json"))
        let truth = try JSONDecoder().decode(BadgeTruth.self, from: Data(contentsOf: truthURL))
        let images = try truth.pages.map { name -> UIImage in
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "jpg"))
            return try XCTUnwrap(UIImage(contentsOfFile: url.path))
        }
        let rules = truth.rules.sorted { $0.key < $1.key }.map { PassPlan.OperatorRule(name: $0.key, prefixes: $0.value) }
        let reading = try await PlanReader.read(pages: images, rules: rules)
        XCTAssertNil(reading.layout?.emergencyIndex, "样图的应急是无表头侧边标签")
        XCTAssertEqual(reading.rows.count, truth.rows.count, "跨页重叠应合并，test 原行保留供核对")
        for expected in truth.rows {
            let matches = reading.rows.filter { $0.start == expected.start }
            XCTAssertEqual(matches.count, 1, "合成计划应唯一对应：\(expected.start)")
            let row = try XCTUnwrap(matches.first)
            if expected.emergency {
                XCTAssertEqual(PassPlan.emergency(row, layout: reading.layout), true, "漏了左侧应急标签")
            } else {
                XCTAssertNotEqual(PassPlan.emergency(row, layout: reading.layout), true,
                                  "红背景或信息列的应急文字不能变成左侧应急标签")
            }
            XCTAssertEqual(PassPlan.isExcludedFromSending(row), expected.excluded,
                           "只有状态列 test 排除，信息列里的 test 不能误排")
        }
        let sendable = PassPlan.sendableRows(reading.rows)
        XCTAssertEqual(sendable.count, truth.rows.filter { !$0.excluded }.count)
        XCTAssertEqual(PassPlan.table(reading.rows, layout: reading.layout).cells.count, sendable.count)
        XCTAssertFalse(PassPlan.grouped(reading.rows, rules: rules).flatMap(\.rows).contains(where: PassPlan.isExcludedFromSending))
        let message = PassPlan.message(name: "合成演示", rows: reading.rows, layout: reading.layout)
        for excluded in truth.rows where excluded.excluded {
            XCTAssertFalse(message.contains(excluded.start), "文字出口不能带出 test 计划")
        }
        await dumpOriginal("badge_overlap", reading, rules)
    }

    private var statusRereadLayout: PassPlan.Layout {
        .init(slots: [
            .init(label: "卫星名称", column: .satellite, x: 0.13),
            .init(label: "地面站", column: .station, x: 0.35),
            .init(label: "数传信息", column: .info, x: 0.54),
            .init(label: "状态", column: .status, x: 0.83),
        ])
    }

    private func statusRereadRow(_ index: Int, status: String = "", retainedTest: Bool = false) -> PassPlanRow {
        let name = "演示卫星\(index + 1)"
        let station = "演示甲站-01"
        return PassPlanRow(orbit: "\(100 + index)", satelliteID: "SAMPLE-C\(index + 1)",
                           satellite: name, station: station,
                           start: String(format: "2032-04-12 %02d:00:00", 8 + index),
                           end: String(format: "2032-04-12 %02d:05:00", 8 + index),
                           info: "test", status: status, cells: [name, station, "test", status],
                           region: .init(y0: Double(70 + index * 100) / 840, slope: 0,
                                         height: 80.0 / 840, left: 0, right: 1),
                           testStatusDetected: retainedTest ? true : nil)
    }

    /// 状态实际绘制为像素，补读必须经过 Vision；信息列放 test 干扰词，不能跨列取值。
    private func statusRereadSource(_ statuses: [String]) async throws -> CGImage {
        try await MainActor.run {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 840), format: format).image { output in
                UIColor.white.setFill()
                output.cgContext.fill(CGRect(x: 0, y: 0, width: 1400, height: 840))
                let font = UIFont.systemFont(ofSize: 36, weight: .medium)
                for (index, status) in statuses.enumerated() {
                    let centerY = CGFloat(70 + index * 100)
                    func text(_ value: String, centerX: CGFloat, color: UIColor) {
                        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                        let size = (value as NSString).size(withAttributes: attributes)
                        (value as NSString).draw(at: CGPoint(x: centerX - size.width / 2,
                                                             y: centerY - size.height / 2),
                                                withAttributes: attributes)
                    }
                    text("test", centerX: 1400 * 0.54, color: .black)
                    text(status, centerX: 1400 * 0.83,
                         color: UIColor(red: 0.12, green: 0.42, blue: 0.24, alpha: 1))
                }
            }
            return try XCTUnwrap(image.cgImage)
        }
    }

    func testStatusRereadRecognizesNormalTextAndPreservesTestEvidence() async throws {
        let source = try await statusRereadSource([
            "等待数传", "已发送站", "test", "等待数传", "已发送站", "等待数传", "",
        ])
        let rows = [
            statusRereadRow(0),
            statusRereadRow(1),
            statusRereadRow(2, status: "等待数传"),
            statusRereadRow(3, status: "test"),
            statusRereadRow(4, status: "等待数传"),
            statusRereadRow(5, status: "等待数传", retainedTest: true),
            statusRereadRow(6),
        ]
        let result = await PlanReader.rereadRowMarkers(rows, layout: statusRereadLayout, in: source, settings: .standard)
        XCTAssertEqual(result.count, rows.count)
        guard result.count == rows.count else { return }
        for index in rows.indices {
            XCTAssertEqual(result[index].satelliteID, rows[index].satelliteID, "状态补读不能改编号")
            XCTAssertEqual(result[index].station, rows[index].station)
            XCTAssertEqual(result[index].start, rows[index].start)
            XCTAssertEqual(result[index].region, rows[index].region)
        }
        XCTAssertEqual(result[0].status, "等待数传", "不能因为全都待核对而绕过实际状态恢复")
        XCTAssertEqual(result[1].status, "已发送站")
        XCTAssertEqual(result[0].cells.last, "等待数传", "整理表格的原始状态格同步更新")
        XCTAssertEqual(result[1].cells.last, "已发送站")
        XCTAssertFalse(PassPlan.isExcludedFromSending(result[0]), "信息列里的 test 不是状态")
        XCTAssertFalse(PassPlan.isExcludedFromSending(result[1]))
        XCTAssertEqual(result[2].testStatusDetected, true, "右栏独立读到 test 必须保留")
        XCTAssertTrue(PassPlan.isExcludedFromSending(result[2]))
        XCTAssertEqual(result[3].status, "test", "普通补读不能覆盖原有 test")
        XCTAssertTrue(PassPlan.isExcludedFromSending(result[3]))
        XCTAssertEqual(result[4].status, "等待数传", "不同普通状态不能静默替换原值")
        XCTAssertTrue(result[4].recognitionIssues?.contains(where: { $0.contains("状态") && $0.contains("不一致") }) == true)
        XCTAssertEqual(result[5].testStatusDetected, true, "历史 test 证据不被普通补读清除")
        XCTAssertTrue(PassPlan.isExcludedFromSending(result[5]))
        XCTAssertTrue(result[6].status.isEmpty, "空状态不能从相邻行或信息列借来")
        XCTAssertFalse(PassPlan.isExcludedFromSending(result[6]))
    }

    func testStatusRereadKeepsAmbiguousRowsUnresolved() async throws {
        let source = try await statusRereadSource(["等待数传", "已发送站"])
        let first = statusRereadRow(0)
        var overlap = statusRereadRow(2)
        overlap.region = first.region
        let rows = [first, overlap, statusRereadRow(1)]
        let result = await PlanReader.rereadRowMarkers(rows, layout: statusRereadLayout, in: source, settings: .standard)
        XCTAssertEqual(result.count, rows.count)
        guard result.count == rows.count else { return }
        for row in result.prefix(2) {
            XCTAssertTrue(row.status.isEmpty, "同一段文字不能同时填给两个身份不同的计划")
            XCTAssertTrue(row.recognitionIssues?.contains(where: { $0.contains("状态") && $0.contains("行位置对应不清") }) == true)
            XCTAssertFalse(PassPlan.problems(row, rules: [], layout: statusRereadLayout).isEmpty)
        }
        XCTAssertEqual(result[2].status, "已发送站", "无歧义的行应实际识别成功，不能整批跳过")
    }

    func testStatusRereadWithoutStatusHeaderDoesNotReadInfoColumn() async throws {
        let source = try await statusRereadSource(["等待数传", "test"])
        var layout = statusRereadLayout
        layout.slots[2].column = nil
        layout.slots[3] = .init(label: "数传信息", column: .info, x: 0.83)
        let rows = [statusRereadRow(0), statusRereadRow(1)]
        let result = await PlanReader.rereadRowMarkers(rows, layout: layout, in: source, settings: .standard)
        XCTAssertEqual(result, rows, "没有状态表头时不把最右侧信息当成状态补读")
    }

    func testOriginalImageOmitsTestRowsEvenWithoutTheirStrips() async throws {
        try await MainActor.run {
            @MainActor func tile(_ color: UIColor) throws -> Data {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 44), format: format).image { context in
                    color.setFill()
                    context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 44))
                }
                return try XCTUnwrap(image.pngData())
            }
            let header = PassPlan.Region(y0: 0.1, slope: 0, height: 0.1, left: 0, right: 1)
            let normalRegion = PassPlan.Region(y0: 0.3, slope: 0, height: 0.1, left: 0, right: 1)
            let testRegion = PassPlan.Region(y0: 0.5, slope: 0, height: 0.1, left: 0, right: 1)
            let normal = PassPlanRow(satellite: "演示A", station: "演示甲-01", start: "2032-04-12 08:00:00",
                                     status: "等待数传", region: normalRegion)
            let excluded = PassPlanRow(satellite: "演示B", station: "演示甲-02", start: "2032-04-12 09:00:00",
                                       status: " test ", region: testRegion)
            // test 故意没有切片；过滤必须发生在读取每条切片之前。
            let strips = [header: try tile(.lightGray), normalRegion: try tile(.cyan)]
            let baseline = try XCTUnwrap(PassPlanOriginal.image(name: "演示甲", rows: [normal], header: header,
                                                               strips: strips, caption: "合成测试"))
            let mixed = try XCTUnwrap(PassPlanOriginal.image(name: "演示甲", rows: [normal, excluded], header: header,
                                                            strips: strips, caption: "合成测试"))
            XCTAssertEqual(try XCTUnwrap(mixed.pngData()), try XCTUnwrap(baseline.pngData()))
            XCTAssertNil(PassPlanOriginal.image(name: "演示甲", rows: [excluded], header: header,
                                                strips: strips, caption: "合成测试"))
        }
    }

    func testIdentifierColumnUsesExplicitIDAndKeepsNamesOutOfEnglishReview() {
        let explicit = PassPlan.Layout(slots: [
            .init(label: "卫星", column: .satellite, x: 0.1),
            .init(label: "卫星ID", column: .satelliteID, x: 0.3),
            .init(label: "地面站", column: .station, x: 0.5),
        ])
        XCTAssertEqual(PlanReader.identifierColumn(for: PassPlanRow(satelliteID: "XA101C", satellite: "高分GF05星"),
                                                   layout: explicit), 1)
        XCTAssertEqual(PlanReader.identifierColumn(for: PassPlanRow(satellite: "XA101C"), layout: explicit), 1,
                       "显式编号列存在时，不改选名称列；缺编号由字段检查拦下")
        let excel = PassPlan.Layout(slots: [
            .init(label: " 卫 星 ", column: .satellite, x: 0.1),
            .init(label: "地面站", column: .station, x: 0.3),
        ])
        for code in ["XA101C", "xa101c", " XA1GF 05B ", "XA1GF（5B"] {
            XCTAssertEqual(PlanReader.identifierColumn(for: PassPlanRow(satellite: code), layout: excel), 0, code)
        }
        for name in ["", "12345", "ABCDE", "试验01星", "高分GF05星", "ＡＢC12"] {
            XCTAssertNil(PlanReader.identifierColumn(for: PassPlanRow(satellite: name), layout: excel), name)
        }
        let names = PassPlan.Layout(slots: [.init(label: "卫星名称", column: .satellite, x: 0.1)])
        XCTAssertNil(PlanReader.identifierColumn(for: PassPlanRow(satellite: "XA101C"), layout: names))
        XCTAssertNil(PlanReader.identifierColumn(for: PassPlanRow(satellite: "XA101C"), layout: .init(slots: [])))
    }

    func testIdentifierCellRegionExcludesOuterRowNumberAndKeepsTiltedRow() throws {
        let layout = PassPlan.Layout(slots: [
            .init(label: "卫星", column: .satellite, x: 0.16),
            .init(label: "地面站", column: .station, x: 0.40),
            .init(label: "数传开始", column: .start, x: 0.72),
        ])
        for slope in [-0.2, 0, 0.2] {
            let row = PassPlan.Region(page: 3, y0: 0.5 - slope * 0.5, slope: slope,
                                      height: 0.1, left: 0, right: 1)
            let ordinary = try XCTUnwrap(PlanReader.boundedCellRegion(column: 0, of: row, layout: layout))
            let first = try XCTUnwrap(PlanReader.identifierCellRegion(column: 0, of: row, layout: layout))
            let last = try XCTUnwrap(PlanReader.identifierCellRegion(column: 2, of: row, layout: layout))
            XCTAssertEqual(first.left, 0.04, accuracy: 1e-12, "Excel 行号区不能带进编号格")
            XCTAssertEqual(first.right, 0.28, accuracy: 1e-12)
            XCTAssertGreaterThan(first.left, ordinary.left)
            XCTAssertEqual(last.left, 0.56, accuracy: 1e-12)
            XCTAssertEqual(last.right, 0.88, accuracy: 1e-12)
            for cell in [first, last] {
                XCTAssertEqual(cell.page, row.page)
                XCTAssertEqual(cell.y0, row.y0)
                XCTAssertEqual(cell.slope, row.slope)
                XCTAssertGreaterThan(cell.height, 0)
                XCTAssertLessThanOrEqual(cell.height, row.height)
                for x in [cell.left, cell.right] {
                    let center = row.y0 + row.slope * x
                    XCTAssertGreaterThanOrEqual(cell.y0 + cell.slope * x - cell.height / 2,
                                               center - row.height / 2 - 1e-12)
                    XCTAssertLessThanOrEqual(cell.y0 + cell.slope * x + cell.height / 2,
                                            center + row.height / 2 + 1e-12)
                }
            }
            let middle = PlanReader.identifierCellRegion(column: 1, of: row, layout: layout)
            XCTAssertEqual(middle, PlanReader.boundedCellRegion(column: 1, of: row, layout: layout),
                           "已有两侧相邻表头的内列保持原几何")
        }
    }

    func testIdentifierCellRegionHonorsClippedPageEdgesAndInvalidGeometry() throws {
        let layout = PassPlan.Layout(slots: [
            .init(label: "卫星ID", column: .satelliteID, x: 0.16),
            .init(label: "地面站", column: .station, x: 0.40),
            .init(label: "数传开始", column: .start, x: 0.72),
        ])
        let rows = [
            PassPlan.Region(y0: 0.01, slope: 0.03, height: 0.2, left: 0.1, right: 0.8),
            PassPlan.Region(y0: 0.99, slope: -0.03, height: 0.2, left: 0.1, right: 0.8),
        ]
        for row in rows {
            for index in layout.slots.indices {
                let cell = try XCTUnwrap(PlanReader.identifierCellRegion(column: index, of: row, layout: layout))
                XCTAssertGreaterThanOrEqual(cell.left, row.left)
                XCTAssertLessThanOrEqual(cell.right, row.right)
                for x in [cell.left, cell.right] {
                    let center = cell.y0 + cell.slope * x
                    XCTAssertGreaterThanOrEqual(center - cell.height / 2, -1e-12)
                    XCTAssertLessThanOrEqual(center + cell.height / 2, 1 + 1e-12)
                }
            }
        }
        XCTAssertNil(PlanReader.identifierCellRegion(column: -1, of: rows[0], layout: layout))
        XCTAssertNil(PlanReader.identifierCellRegion(column: 3, of: rows[0], layout: layout))
        XCTAssertNil(PlanReader.identifierCellRegion(column: 0, of: rows[0], layout: .init(slots: [])))
        var invalid = rows[0]
        invalid.height = 0
        XCTAssertNil(PlanReader.identifierCellRegion(column: 0, of: invalid, layout: layout))
        invalid = rows[0]
        invalid.slope = .nan
        XCTAssertNil(PlanReader.identifierCellRegion(column: 0, of: invalid, layout: layout))
    }

    func testCellRereadRegionStaysInsideItsRowAndImage() throws {
        let layout = PassPlan.Layout(slots: [
            .init(label: "卫星", column: .satellite, x: 0.1),
            .init(label: "地面站", column: .station, x: 0.5),
            .init(label: "是否应急", column: nil, x: 0.9),
        ])
        let regions = [
            PassPlan.Region(y0: 0.5, slope: 0, height: 0.1, left: 0.05, right: 0.95),
            PassPlan.Region(y0: 0.4, slope: 0.2, height: 0.15, left: 0.05, right: 0.95),
            PassPlan.Region(y0: 0.6, slope: -0.2, height: 0.15, left: 0.05, right: 0.95),
            PassPlan.Region(y0: 0.01, slope: 0.03, height: 0.2, left: 0, right: 1),
            PassPlan.Region(y0: 0.99, slope: -0.03, height: 0.2, left: 0, right: 1),
        ]
        for region in regions {
            for column in layout.slots.indices {
                let cell = try XCTUnwrap(PlanReader.boundedCellRegion(column: column, of: region, layout: layout))
                XCTAssertGreaterThan(cell.height, 0)
                XCTAssertLessThanOrEqual(cell.height, region.height)
                XCTAssertGreaterThanOrEqual(cell.left, region.left)
                XCTAssertLessThanOrEqual(cell.right, region.right)
                for x in [cell.left, cell.right] {
                    let rowCenter = region.y0 + region.slope * x
                    let cellCenter = cell.y0 + cell.slope * x
                    let top = cellCenter - cell.height / 2
                    let bottom = cellCenter + cell.height / 2
                    XCTAssertGreaterThanOrEqual(top, rowCenter - region.height / 2 - 1e-12)
                    XCTAssertLessThanOrEqual(bottom, rowCenter + region.height / 2 + 1e-12)
                    XCTAssertGreaterThanOrEqual(top, -1e-12)
                    XCTAssertLessThanOrEqual(bottom, 1 + 1e-12)
                }
            }
        }
        let empty = PassPlan.Region(y0: 0.5, slope: 0, height: 0, left: 0, right: 1)
        XCTAssertNil(PlanReader.boundedCellRegion(column: 1, of: empty, layout: layout))
        XCTAssertNil(PlanReader.boundedCellRegion(column: 3, of: regions[0], layout: layout))
    }

    /// 走整格复识实际使用的裁法：青色是本格，洋红是邻行，黄色是同一行的相邻列。
    func testCellRereadCropExcludesNeighborPixelsWhenRowsAreTilted() async throws {
        let layout = PassPlan.Layout(slots: [
            .init(label: "卫星", column: .satellite, x: 0.1),
            .init(label: "地面站", column: .station, x: 0.5),
            .init(label: "是否应急", column: nil, x: 0.9),
        ])
        for slope in [-0.16, 0, 0.16] {
            let y0 = 0.5 - slope * 0.5
            let source = try await MainActor.run {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 300), format: format).image { output in
                    UIColor.magenta.setFill()
                    output.cgContext.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
                    func band(left: Double, right: Double, color: UIColor) {
                        func point(_ x: Double, _ dy: Double) -> CGPoint {
                            CGPoint(x: x * 600, y: (y0 + slope * x + dy) * 300)
                        }
                        let path = CGMutablePath()
                        path.move(to: point(left, -0.05))
                        path.addLine(to: point(right, -0.05))
                        path.addLine(to: point(right, 0.05))
                        path.addLine(to: point(left, 0.05))
                        path.closeSubpath()
                        output.cgContext.addPath(path)
                        color.setFill()
                        output.cgContext.fillPath()
                    }
                    band(left: 0, right: 1, color: .yellow)
                    band(left: 0.3, right: 0.7, color: .cyan)
                }
                return try XCTUnwrap(image.cgImage)
            }
            let rows = [-0.1, 0, 0.1].map { offset in
                PassPlanRow(region: .init(y0: y0 + offset, slope: slope, height: 0.3, left: 0, right: 1))
            }
            let region = try XCTUnwrap(PassPlan.boundedRegions(rows)[1].region)
            let crop = try XCTUnwrap(PlanReader.cropCell(column: 1, of: region, layout: layout,
                                                       from: source, context: CIContext()))
            let context = try XCTUnwrap(CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                                 bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var cyan = 0, neighbor = 0
            for pixel in 0..<(crop.width * crop.height) {
                let i = pixel * 4
                if bytes[i] < 80, bytes[i + 1] > 150, bytes[i + 2] > 150 { cyan += 1 }
                let magenta = bytes[i] > 150 && bytes[i + 1] < 80 && bytes[i + 2] > 150
                let yellow = bytes[i] > 150 && bytes[i + 1] > 150 && bytes[i + 2] < 80
                if magenta || yellow { neighbor += 1 }
            }
            XCTAssertGreaterThan(cyan, crop.width * crop.height * 9 / 10, "目标格必须保留，slope=\(slope)")
            XCTAssertEqual(neighbor, 0, "整格补读不得带入邻行或相邻列像素，slope=\(slope)")
        }
    }

    /// 中间洋红色条带代表不发送的 test 行；它仍参与正常行的裁切边界计算。
    func testBoundedOriginalCropDoesNotIncludeNeighboringTestBand() async throws {
        let source = try await MainActor.run {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 240), format: format).image { context in
                UIColor.white.setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 400, height: 240))
                UIColor.magenta.setFill()
                context.cgContext.fill(CGRect(x: 0, y: 100, width: 400, height: 40))
            }
            return try XCTUnwrap(image.cgImage)
        }
        let rows = [
            PassPlanRow(status: "等待数传", region: .init(y0: 80.0 / 240, slope: 0, height: 0.5, left: 0, right: 1)),
            PassPlanRow(status: "test", region: .init(y0: 120.0 / 240, slope: 0, height: 0.3, left: 0, right: 1)),
            PassPlanRow(status: "等待数传", region: .init(y0: 180.0 / 240, slope: 0, height: 0.4, left: 0, right: 1)),
        ]
        let bounded = PassPlan.boundedRegions(rows)
        let region = try XCTUnwrap(bounded[0].region)
        XCTAssertLessThan(region.height, rows[0].region!.height)
        let strips = await PlanReader.cut(bounded.compactMap(\.region), from: source)
        let data = try XCTUnwrap(strips[region])
        let decoder = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let magenta = (0..<(image.width * image.height)).filter { pixel in
            let i = pixel * 4
            return bytes[i] > 130 && bytes[i + 1] < 100 && bytes[i + 2] > 130
        }.count
        XCTAssertEqual(magenta, 0, "正常行原图不得带入相邻 test 行的色带或文字")
    }
}
