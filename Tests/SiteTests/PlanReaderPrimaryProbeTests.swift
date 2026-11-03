import XCTest
import Foundation
import CoreGraphics
import ImageIO
import Vision
@testable import ShiftReminder

/// Isolated diagnosis of the first raw production strip; uses only the public synthetic fixture.
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
        return result
    }
}
