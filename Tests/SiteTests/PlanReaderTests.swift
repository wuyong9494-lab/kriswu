import XCTest
import CoreGraphics
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
                do {
                    let reading = try await PlanReader.read(pages: [image], rules: rules, settings: settings)
                    let measured = accuracy(reading, truth, rules)
                    print(report(name, label, reading, truth, rules, seconds: Date().timeIntervalSince(began)))
                    XCTAssertNotNil(reading.layout, "\(name)：缺少表头布局")
                    XCTAssertFalse(reading.rows.isEmpty, "\(name)：没有读出计划行")
                    XCTAssertGreaterThan(measured.matched, 0, "\(name)：没有一条能唯一对应标准答案")
                    if label == "现在" { await dumpOriginal(name, reading, rules) }
                } catch {
                    print("OCR|\(name)|\(label)|认不出：\(error.localizedDescription)")
                    XCTFail("\(name) / \(label) 识别失败：\(error.localizedDescription)")
                }
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
        return measured
    }

    private func report(_ name: String, _ label: String, _ reading: PassPlan.Reading, _ truth: Truth,
                        _ rules: [PassPlan.OperatorRule], seconds: Double) -> String {
        let measured = accuracy(reading, truth, rules)
        let total = truth.rows.count
        func pct(_ n: Int, _ of: Int) -> String { of == 0 ? "-" : "\(n * 100 / of)%（\(n)/\(of)）" }
        return ["OCR", name, label,
                "唯一对应行 \(measured.matched)/\(total)",
                "站名 \(pct(measured.station, total))", "分家 \(pct(measured.family, total))",
                "卫星 \(pct(measured.satellite, total))", "圈号 \(pct(measured.orbit, total))",
                "开始时间 \(pct(measured.start, total))", "结束时间 \(pct(measured.end, measured.endTotal))",
                "应急 \(pct(measured.emergency, measured.emergencyTotal))", "应急未知 \(measured.emergencyUnknown)",
                "漏行或无法对应 \(total - measured.matched)", "身份歧义 \(measured.ambiguous)",
                "多出或无法对应 \(reading.rows.count - measured.matched)",
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
