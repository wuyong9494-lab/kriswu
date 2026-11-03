import XCTest
import Foundation
import CoreGraphics
import ImageIO
import Vision
@testable import ShiftReminder

/// Isolated diagnosis of first raw production strips; uses only public synthetic fixtures.
/// Enable XCTest timeouts when running this class. A timeout fails one method and restarts the
/// runner for the remaining methods; this file does not change any production or accuracy test.
final class PlanReaderPrimaryProbeTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        executionTimeAllowance = 180
    }

    func testTextRecognitionAlone() async throws {
        let result = try await Self.runProbe(.text)
        XCTAssertGreaterThan(result.textObservations, 0)
    }

    func testTextRectanglesAlone() async throws {
        let result = try await Self.runProbe(.rectangles)
        XCTAssertGreaterThan(result.textRectangles, 0)
        XCTAssertGreaterThan(result.characterBoxes, 0)
    }

    func testTextRecognitionAndRectanglesTogether() async throws {
        let result = try await Self.runProbe(.combined)
        XCTAssertGreaterThan(result.textObservations, 0)
        XCTAssertGreaterThan(result.textRectangles, 0)
        XCTAssertGreaterThan(result.characterBoxes, 0)
    }

    func testExcelPhotoFirstStripFields() async throws {
        try await Self.productionFirstStripFields(.excelPhoto)
    }

    func testWebPhotoFirstStripFields() async throws {
        try await Self.productionFirstStripFields(.webPhoto)
    }

    func testLongTableFirstStripFields() async throws {
        try await Self.productionFirstStripFields(.longTable)
    }

    /// This closed whitelist is the only source accepted by the field logger. Never use user photos
    /// or call the diagnostic logger from production code.
    private enum FieldFixture: String, Sendable {
        case excelPhoto = "excel_photo"
        case webPhoto = "web_photo"
        case longTable = "long_table"

        var width: Int { self == .longTable ? 1170 : 4032 }
        var height: Int { self == .longTable ? 7536 : 3024 }
        var firstStripHeight: Int { self == .longTable ? 1638 : 600 }
        var stripCount: Int { self == .longTable ? 6 : 7 }
        var firstStripBudget: Int { self == .longTable ? 23 : 20 }
    }

    private static func productionFirstStripFields(_ sample: FieldFixture) async throws {
        let bundle = Bundle(for: PlanReaderPrimaryProbeTests.self)
        let imageURL = try XCTUnwrap(bundle.url(forResource: sample.rawValue, withExtension: "jpg"))
        let rulesURL = try XCTUnwrap(bundle.url(forResource: sample.rawValue, withExtension: "json"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, sample.width)
        XCTAssertEqual(image.height, sample.height)
        let strips = PassPlan.strips(width: image.width, height: image.height)
        let strip = try XCTUnwrap(strips.first)
        XCTAssertEqual(strips.count, sample.stripCount)
        XCTAssertEqual(strip.top, 0)
        XCTAssertEqual(strip.height, sample.firstStripHeight)
        let settings = PlanReader.Settings.standard
        let stripCounts = settings.passes.map { $0.split ? strips.count : 1 }
        let budgets = PlanReader.splitRereadBudgets(total: 400, stripCounts: stripCounts)
        let quota = try XCTUnwrap(budgets.first?.first)
        XCTAssertEqual(quota, sample.firstStripBudget)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: strip.top, width: image.width, height: strip.height)))
        let fixture = try JSONDecoder().decode(RuleFixture.self, from: Data(contentsOf: rulesURL))
        let rules = fixture.rules.sorted { $0.key < $1.key }.map {
            PassPlan.OperatorRule(name: $0.key, prefixes: $0.value)
        }
        let words = PassPlan.vocabulary(rules)
        XCTAssertEqual(words.count, 42)
        let began = ProcessInfo.processInfo.systemUptime
        try logFixtureFields(sample, [
            "kind": "start", "width": crop.width, "height": crop.height,
            "photoWidth": image.width, "photoHeight": image.height,
            "stripTop": strip.top, "stripCount": strips.count,
            "coordinateSpace": "strip-normalized-top-left", "customWords": words.count,
            "splitBudget": quota, "firstPassBudgets": budgets.first ?? [],
        ])
        let pass = PlanReader.Settings.Pass(split: false, smooth: false)
        let boxes = try await PlanReader.textBoxes(in: crop, words: words, settings: settings,
                                                  pass: pass, splitBudgets: [quota], diagnosticID: "\(sample.rawValue).fields")
        for (index, box) in boxes.enumerated() {
            try logFixtureFields(sample, [
                "kind": "box", "index": index, "text": box.text,
                "x": box.x, "y": box.y, "w": box.width, "h": box.height,
            ])
        }
        let reading = PassPlan.read(boxes)
        let slots: [[String: Any]] = (reading.layout?.slots ?? []).enumerated().map { index, slot in
            ["index": index, "label": slot.label, "column": Self.jsonValue(slot.column?.rawValue), "x": slot.x]
        }
        try logFixtureFields(sample, [
            "kind": "layout", "present": reading.layout != nil, "slots": slots,
            "header": Self.regionFields(reading.header),
            "emergencyIndex": Self.jsonValue(reading.layout?.emergencyIndex),
        ])
        for (index, row) in reading.rows.enumerated() {
            try logFixtureFields(sample, [
                "kind": "row", "index": index, "satellite": row.satellite,
                "satelliteID": row.satelliteID, "station": row.station, "orbit": row.orbit,
                "start": row.start, "end": row.end, "cells": row.cells,
                "recognitionIssues": Self.jsonValue(row.recognitionIssues),
                "emergency": Self.jsonValue(PassPlan.emergency(row, layout: reading.layout)),
                "emergencyBadge": Self.jsonValue(row.emergencyBadge),
                "region": Self.regionFields(row.region),
            ])
        }
        try logFixtureFields(sample, [
            "kind": "summary", "boxes": boxes.count, "rows": reading.rows.count,
            "seconds": ProcessInfo.processInfo.systemUptime - began,
        ])
        XCTAssertFalse(boxes.isEmpty)
        XCTAssertNotNil(reading.layout)
        XCTAssertFalse(reading.rows.isEmpty)
    }

    private static func jsonValue<T>(_ value: T?) -> Any {
        if let value { return value }
        return NSNull()
    }

    private static func regionFields(_ region: PassPlan.Region?) -> Any {
        guard let region else { return NSNull() }
        return ["page": region.page, "y0": region.y0, "slope": region.slope,
                "height": region.height, "left": region.left, "right": region.right] as [String: Any]
    }

    private static func logFixtureFields(_ sample: FieldFixture, _ values: [String: Any]) throws {
        var object = values
        object["fixture"] = sample.rawValue
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        NSLog("OCRFIELD|%@", String(decoding: data, as: UTF8.self))
    }

    private enum Mode: String, Sendable {
        case text, rectangles, combined
    }

    private struct ProbeResult: Sendable {
        let textObservations: Int
        let textRectangles: Int
        let characterBoxes: Int
    }

    private struct RuleFixture: Decodable {
        let rules: [String: [String]]
    }

    /// Immutable captures only. Vision may invoke the callbacks on different queues.
    /// NSLog writes immediately; never log recognized strings, candidate text, or error descriptions.
    private struct Trace: Sendable {
        let mode: String
        let began: TimeInterval

        init(_ mode: Mode) {
            self.mode = mode.rawValue
            began = ProcessInfo.processInfo.systemUptime
        }

        func event(_ name: String, _ details: String = "") {
            let seconds = String(format: "%.3f", ProcessInfo.processInfo.systemUptime - began)
            NSLog("OCRPRIMARY|%@|%@|seconds=%@|%@", mode, name, seconds, details)
        }
    }

    private static func runProbe(_ mode: Mode) async throws -> ProbeResult {
        let work: Task<ProbeResult, Error> = Task.detached(priority: .userInitiated) {
            try performProbe(mode)
        }
        return try await work.value
    }

    private static func performProbe(_ mode: Mode) throws -> ProbeResult {
        let trace = Trace(mode)
        trace.event("start", "allowance=180")
        defer { trace.event("end") }

        let bundle = Bundle(for: PlanReaderPrimaryProbeTests.self)
        let imageURL = try XCTUnwrap(bundle.url(forResource: "excel_photo", withExtension: "jpg"))
        let rulesURL = try XCTUnwrap(bundle.url(forResource: "excel_photo", withExtension: "json"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let strip = try XCTUnwrap(PassPlan.strips(width: image.width, height: image.height).first)
        XCTAssertEqual(image.width, 4032)
        XCTAssertEqual(image.height, 3024)
        XCTAssertEqual(strip.top, 0)
        XCTAssertEqual(strip.height, 600)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: 4032, height: 600)))

        let fixture = try JSONDecoder().decode(RuleFixture.self, from: Data(contentsOf: rulesURL))
        let rules = fixture.rules.sorted { $0.key < $1.key }.map {
            PassPlan.OperatorRule(name: $0.key, prefixes: $0.value)
        }
        let words = PassPlan.vocabulary(rules)
        let settings = PlanReader.Settings.standard

        let text = VNRecognizeTextRequest { request, error in
            trace.event("text.completion", "observations=\(request.results?.count ?? 0)|error=\(error == nil ? 0 : 1)")
        }
        text.recognitionLevel = .accurate
        text.recognitionLanguages = ["zh-Hans", "en-US"]
        text.usesLanguageCorrection = settings.languageCorrection
        if settings.languageCorrection { text.customWords = words }
        // Same formula as PlanReader.minimumTextHeight; the first raw pass needs no preprocessing.
        if settings.smallText {
            text.minimumTextHeight = Float(max(10 / Double(max(crop.height, 1)), 0.002))
        }
        text.progressHandler = { request, fraction, error in
            let indeterminate = (request as? VNRecognizeTextRequest)?.indeterminate ?? true
            let progress = indeterminate ? "unknown" : String(format: "%.3f", fraction)
            trace.event("text.progress", "fraction=\(progress)|indeterminate=\(indeterminate)|error=\(error == nil ? 0 : 1)")
        }

        let rectangles = VNDetectTextRectanglesRequest { request, error in
            trace.event("rectangles.completion", "observations=\(request.results?.count ?? 0)|error=\(error == nil ? 0 : 1)")
        }
        rectangles.reportCharacterBoxes = true
        let requests: [VNRequest]
        switch mode {
        case .text: requests = [text]
        case .rectangles: requests = [rectangles]
        case .combined: requests = [text, rectangles]
        }
        trace.event("perform.start", "size=\(crop.width)x\(crop.height)|requests=\(requests.count)|customWords=\(words.count)|minimumTextHeight=\(text.minimumTextHeight)")
        do {
            try VNImageRequestHandler(cgImage: crop, orientation: .up).perform(requests)
        } catch {
            trace.event("perform.error", "code=\((error as NSError).code)")
            throw error
        }
        let result = ProbeResult(textObservations: text.results?.count ?? 0,
                                 textRectangles: rectangles.results?.count ?? 0,
                                 characterBoxes: (rectangles.results ?? []).reduce(0) { $0 + ($1.characterBoxes?.count ?? 0) })
        trace.event("perform.end", "textObservations=\(result.textObservations)|textRectangles=\(result.textRectangles)|characterBoxes=\(result.characterBoxes)")
        if mode == .text {
            // Reuse this completed request for the fixed public excel_photo fixture; no extra OCR.
            for (index, observation) in (text.results ?? []).enumerated() {
                let candidate = observation.topCandidates(1).first
                let box = observation.boundingBox
                try logFixtureFields(.excelPhoto, [
                    "kind": "rawCandidate", "index": index,
                    "text": jsonValue(candidate?.string), "confidence": jsonValue(candidate?.confidence),
                    "x": box.minX, "y": 1 - box.maxY, "w": box.width, "h": box.height,
                    "coordinateSpace": "strip-normalized-top-left",
                ])
            }
        }
        return result
    }
}
