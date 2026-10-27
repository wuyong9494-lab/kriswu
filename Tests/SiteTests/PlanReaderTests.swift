import XCTest
@testable import ShiftReminder

/// 数传计划的文字识别准确率：合成的「拍屏幕」照片（scripts/make_ocr_samples.py 生成，虚构数据）在模拟器里真的认一遍，
/// 和标准答案比。结果打印成 OCR| 开头的行（CI 里变成注解，方便对比几种认法）。
/// 只报告、不卡：模拟器和真机的识别会有出入
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
        let variants: [(String, PlanReader.Settings)] = [
            ("改之前", .original),
            ("只放开小字", PlanReader.Settings(smallText: true, split: false, languageCorrection: false)),
            ("不纠错", PlanReader.Settings(smallText: true, split: true, languageCorrection: false)),
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
            // 认出的每一块字和拼出的每一行打到日志里（虚构数据），对不上时拿来查是哪一步出的错
            if let picture = image.cgImage {
                let boxes = try await PlanReader.textBoxes(in: picture, words: PassPlan.vocabulary(rules))
                // 最上面几十块（表头附近）
                for b in boxes.sorted(by: { $0.y < $1.y }).prefix(45) {
                    print(String(format: "OCRBOX|%@|%@|%.3f|%.3f|%.3f|%.4f", name, b.text, b.x, b.y, b.width, b.height))
                }
                let reading = PassPlan.read(boxes)
                print("OCRLAYOUT|\(name)|" + (reading.layout?.slots.map { "\($0.label)@\(String(format: "%.3f", $0.x))" } ?? []).joined(separator: " "))
                for row in reading.rows {
                    print("OCRROW|\(name)|" + [row.satellite, row.satelliteID, row.station, row.orbit, row.start, row.end].joined(separator: "|"))
                }
            }
            for (label, settings) in variants {
                let began = Date()
                do {
                    let reading = try await PlanReader.read(pages: [image], rules: rules, settings: settings)
                    print(report(name, label, reading, truth, rules, seconds: Date().timeIntervalSince(began)))
                } catch {
                    print("OCR|\(name)|\(label)|认不出：\(error.localizedDescription)")
                }
            }
        }
    }

    private func report(_ name: String, _ label: String, _ reading: PassPlan.Reading, _ truth: Truth,
                        _ rules: [PassPlan.OperatorRule], seconds: Double) -> String {
        var byStart: [String: PassPlanRow] = [:]
        for row in reading.rows where byStart[row.start] == nil { byStart[row.start] = row }
        var found = 0, station = 0, satellite = 0, orbit = 0, family = 0, emergency = 0, emergencyTotal = 0
        for expected in truth.rows {
            guard let row = byStart[expected.start] else { continue }
            found += 1
            if row.station == expected.station { station += 1 }
            if row.satellite == expected.satellite || row.satelliteID == expected.satellite { satellite += 1 }
            if row.orbit == expected.orbit { orbit += 1 }
            if PassPlan.operatorName(of: row.station, rules: rules) == PassPlan.operatorName(of: expected.station, rules: rules) {
                family += 1
            }
            if let want = expected.emergency {
                emergencyTotal += 1
                if (PassPlan.emergency(row, layout: reading.layout) ?? false) == want { emergency += 1 }
            }
        }
        func pct(_ n: Int, _ of: Int) -> String { of == 0 ? "-" : "\(n * 100 / of)%" }
        return ["OCR", name, label,
                "行 \(found)/\(truth.rows.count)",
                "站名 \(pct(station, found))", "分家 \(pct(family, found))", "卫星 \(pct(satellite, found))",
                "圈号 \(pct(orbit, found))", "应急 \(pct(emergency, emergencyTotal))",
                "多出 \(reading.rows.count - found)", String(format: "%.1f 秒", seconds)].joined(separator: "|")
    }
}
