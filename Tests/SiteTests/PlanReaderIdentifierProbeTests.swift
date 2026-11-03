import XCTest
import Foundation
import CoreGraphics
import CoreImage
import CryptoKit
import ImageIO
import Vision
@testable import ShiftReminder

/// Test-only recognition/preprocessing comparison on six fixed, public synthetic cells recorded by Probe2.
/// Recorded OCR boxes determine geometry; truth files and satellite dictionaries are never loaded.
final class PlanReaderIdentifierProbeTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        executionTimeAllowance = 180
    }

    func testExcelIdentifiersFromRecordedFirstStrip() async throws {
        try await Self.run(.excelPhoto)
    }

    func testWebIdentifierFromRecordedFirstStrip() async throws {
        try await Self.run(.webPhoto)
    }

    private enum Fixture: String, Sendable {
        case excelPhoto = "excel_photo"
        case webPhoto = "web_photo"

        var rowLimit: Int { self == .excelPhoto ? 5 : 1 }
        var boxCount: Int { self == .excelPhoto ? 73 : 21 }
        var column: PassPlan.Column { self == .excelPhoto ? .satellite : .satelliteID }
    }

    private enum Setting: String, CaseIterable, Sendable {
        // Keep the original English setting name so offline comparison can join the Probe3 baseline.
        case englishUncorrected, fastEnglishUncorrected, grayscaleContrastEnglishUncorrected

        var languages: [String] { ["en-US"] }
        var correction: Bool { false }
        var fast: Bool { self == .fastEnglishUncorrected }
        var grayscaleContrast: Bool { self == .grayscaleContrastEnglishUncorrected }
        var recognitionLevelName: String { fast ? "fast" : "accurate" }
        var preprocessing: String { grayscaleContrast ? "CIColorControls-grayscale-contrast" : "none" }

        // One fixed transform for every cell, selected before inspecting any new OCR outputs.
        static let contrast = 1.6
    }

    private struct Recordings: Decodable {
        var recording: String
        var fixtures: [RecordedFixture]
    }

    private struct RecordedFixture: Decodable {
        var fixture: String
        var photoWidth: Int
        var photoHeight: Int
        var stripTop: Int
        var stripHeight: Int
        var sha256: String
        var boxes: [RecordedBox]
    }

    private struct RecordedBox: Decodable {
        var index: Int
        var text: String
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    /// Images stay inside one detached task and are reused for all three request settings.
    private struct Cell {
        var row: Int
        var sourceRead: String
        var region: PassPlan.Region
        var rawWidth: Int
        var rawHeight: Int
        var scale: Double
        var image: CGImage
        var grayscaleContrastImage: CGImage
    }

    private static func run(_ fixture: Fixture) async throws {
        let work: Task<Void, Error> = Task.detached(priority: .userInitiated) {
            try perform(fixture)
        }
        try await work.value
    }

    private static func perform(_ fixture: Fixture) throws {
        let bundle = Bundle(for: PlanReaderIdentifierProbeTests.self)
        let recordsURL = try XCTUnwrap(bundle.url(forResource: "identifier_probe_boxes", withExtension: "json"))
        let records = try JSONDecoder().decode(Recordings.self, from: Data(contentsOf: recordsURL))
        let recorded = try XCTUnwrap(records.fixtures.first { $0.fixture == fixture.rawValue })
        let imageURL = try XCTUnwrap(bundle.url(forResource: fixture.rawValue, withExtension: "jpg"))
        let imageData = try Data(contentsOf: imageURL)
        let hash = SHA256.hash(data: imageData).map { String(format: "%02x", Int($0)) }.joined()
        guard hash == recorded.sha256 else {
            XCTFail("Recorded boxes require the original public fixture: \(fixture.rawValue)")
            return
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, recorded.photoWidth)
        XCTAssertEqual(image.height, recorded.photoHeight)
        XCTAssertEqual(recorded.boxes.count, fixture.boxCount)
        let strip = try XCTUnwrap(PassPlan.strips(width: image.width, height: image.height).first)
        XCTAssertEqual(strip.top, recorded.stripTop)
        XCTAssertEqual(strip.height, recorded.stripHeight)
        let boxes = recorded.boxes.sorted { $0.index < $1.index }.map {
            PassPlan.TextBox(text: $0.text, x: $0.x, y: $0.y, width: $0.w, height: $0.h)
        }
        let placed = PassPlan.place(boxes, in: strip, imageHeight: image.height)
        let reading = PassPlan.read(placed)
        let layout = try XCTUnwrap(reading.layout)
        let column = try XCTUnwrap(layout.slots.firstIndex { $0.column == fixture.column })
        let stripTop = Double(strip.top) / Double(image.height)
        let stripBottom = Double(strip.top + strip.height) / Double(image.height)
        let complete = reading.rows.enumerated().filter { _, row in
            guard let region = row.region else { return false }
            return [region.left, region.right].allSatisfy { x in
                let center = region.y0 + region.slope * x
                return center - region.height / 2 >= stripTop && center + region.height / 2 <= stripBottom
            }
        }.sorted { a, b in
            let lhs = a.element.region!, rhs = b.element.region!
            return lhs.y0 + lhs.slope * 0.5 < rhs.y0 + rhs.slope * 0.5
        }
        let selected = Array(complete.prefix(fixture.rowLimit))
        XCTAssertEqual(selected.count, fixture.rowLimit, "Do not invent additional row positions")
        let context = CIContext()
        var cells: [Cell] = []
        for (index, row) in selected {
            let rowRegion = try XCTUnwrap(row.region)
            let region = try XCTUnwrap(identifierRegion(column: column, row: rowRegion, layout: layout))
            let crop = try rectify(region, image: image, context: context)
            // Same enlargement as production local rereads, applied once and shared by all settings.
            let scale = min(4, max(1, (80 / Double(max(crop.height, 1))).rounded(.up)))
            let scaled = CIImage(cgImage: crop).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let prepared: CGImage
            if scale == 1 {
                prepared = crop
            } else {
                prepared = try XCTUnwrap(context.createCGImage(scaled, from: scaled.extent))
            }
            let sourceRead = fixture.column == .satelliteID ? row.satelliteID : row.satellite
            cells.append(Cell(row: index, sourceRead: sourceRead, region: region,
                              rawWidth: crop.width, rawHeight: crop.height, scale: scale, image: prepared,
                              grayscaleContrastImage: try grayscaleContrast(prepared, context: context)))
        }
        try log(fixture, [
            "kind": "identifierStart", "recording": records.recording,
            "sha256": hash, "placedBoxes": placed.count, "parsedRows": reading.rows.count,
            "completeRows": complete.count, "selectedRows": cells.count, "column": column,
            "columnLabel": layout.slots[column].label, "customWords": 0, "allowance": 180,
            "settings": Setting.allCases.map(\.rawValue),
            "baseline": Setting.englishUncorrected.rawValue,
            "geometryPolicy": "unchanged-Probe3-six-cells; shared-crop-and-enlargement",
            "normalizationPolicy": "format-check-only; no trimming or character substitution",
            "sourceReadScope": "Probe2 first strip after keep; not a complete multi-strip production result",
        ])
        var requests = 0
        for cell in cells {
            for setting in Setting.allCases {
                let input = setting.grayscaleContrast ? cell.grayscaleContrastImage : cell.image
                let pixels = try XCTUnwrap(input.dataProvider?.data)
                let pixelHash = SHA256.hash(data: pixels as Data).map { String(format: "%02x", Int($0)) }.joined()
                let began = ProcessInfo.processInfo.systemUptime
                try log(fixture, ["kind": "identifierRequestStart", "row": cell.row, "setting": setting.rawValue,
                                  "recognitionLevel": setting.recognitionLevelName, "preprocessing": setting.preprocessing])
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = setting.fast ? .fast : .accurate
                request.recognitionLanguages = setting.languages
                request.usesLanguageCorrection = setting.correction
                request.customWords = []
                try VNImageRequestHandler(cgImage: input, orientation: .up).perform([request])
                let observations = request.results ?? []
                let rawStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                let raw = rawStrings.joined(separator: " ")
                let tokenRange = raw.range(of: #"^[A-Za-z][A-Za-z0-9]*$"#, options: .regularExpression)
                let normalized = !raw.isEmpty && tokenRange == (raw.startIndex..<raw.endIndex)
                let alternatives: [[[String: Any]]] = observations.map { observation in
                    observation.topCandidates(3).map { ["text": $0.string, "confidence": Double($0.confidence)] }
                }
                let observationBoxes: [[String: Double]] = observations.map {
                    let box = $0.boundingBox
                    return ["x": Double(box.minX), "y": Double(box.minY),
                            "width": Double(box.width), "height": Double(box.height)]
                }
                try log(fixture, [
                    "kind": "identifierCandidate", "row": cell.row, "setting": setting.rawValue,
                    "languages": setting.languages, "languageCorrection": setting.correction,
                    "customWords": 0, "requestRevision": request.revision,
                    "recognitionLevel": setting.recognitionLevelName,
                    "minimumTextHeight": Double(request.minimumTextHeight),
                    "preprocessing": setting.preprocessing,
                    "saturation": setting.grayscaleContrast ? 0.0 : 1.0,
                    "contrast": setting.grayscaleContrast ? Setting.contrast : 1.0,
                    "brightness": 0.0,
                    "cropWidth": cell.rawWidth, "cropHeight": cell.rawHeight, "scale": cell.scale,
                    "ocrWidth": input.width, "ocrHeight": input.height,
                    "pixelSHA256": pixelHash, "bitsPerPixel": input.bitsPerPixel, "bytesPerRow": input.bytesPerRow,
                    "raw": raw, "rawStrings": rawStrings, "candidates": alternatives,
                    "observationBoxes": observationBoxes,
                    "observationCoordinateSpace": "prepared-crop-normalized-bottom-left",
                    "normalized": normalized, "normalizedMeaning": "raw-is-one-ASCII-alphanumeric-token",
                    "normalizationApplied": false, "sourceFirstStripRead": cell.sourceRead,
                    "region": regionFields(cell.region),
                    "seconds": ProcessInfo.processInfo.systemUptime - began,
                ])
                requests += 1
            }
        }
        try log(fixture, ["kind": "identifierSummary", "rows": cells.count, "requests": requests])
        XCTAssertEqual(requests, fixture.rowLimit * Setting.allCases.count)
    }

    /// A fixed grayscale/contrast transform only; no threshold search, morphology, or truth-derived parameters.
    /// The accurate and fast baselines both receive the unchanged prepared image above.
    private static func grayscaleContrast(_ image: CGImage, context: CIContext) throws -> CGImage {
        let input = CIImage(cgImage: image)
        let filter = try XCTUnwrap(CIFilter(name: "CIColorControls"))
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        filter.setValue(Setting.contrast, forKey: kCIInputContrastKey)
        filter.setValue(0.0, forKey: kCIInputBrightnessKey)
        let output = try XCTUnwrap(filter.outputImage)
        return try XCTUnwrap(context.createCGImage(output, from: input.extent))
    }

    /// Column geometry only. For the first Excel header, half-gap extrapolation excludes the row-number gutter.
    /// The recorded ID text is never used to choose crop bounds or a candidate.
    private static func identifierRegion(column s: Int, row: PassPlan.Region, layout: PassPlan.Layout) -> PassPlan.Region? {
        let xs = layout.slots.map(\.x)
        guard xs.indices.contains(s), xs.allSatisfy(\.isFinite), row.height > 0 else { return nil }
        let outerLeft = xs.count > 1 ? xs[0] - (xs[1] - xs[0]) / 2 : row.left
        let last = xs.count - 1
        let outerRight = xs.count > 1 ? xs[last] + (xs[last] - xs[last - 1]) / 2 : row.right
        let left = max(max(0, row.left), s > 0 ? (xs[s - 1] + xs[s]) / 2 : outerLeft)
        let right = min(min(1, row.right), s < last ? (xs[s] + xs[s + 1]) / 2 : outerRight)
        guard right > left else { return nil }
        let leftY = row.y0 + row.slope * left, rightY = row.y0 + row.slope * right
        let margin = min(min(leftY, rightY), min(1 - leftY, 1 - rightY))
        let halfHeight = min(row.height * 0.45, margin)
        guard halfHeight > 0 else { return nil }
        return PassPlan.Region(page: row.page, y0: row.y0, slope: row.slope, height: halfHeight * 2,
                               left: left, right: right)
    }

    private static func rectify(_ region: PassPlan.Region, image: CGImage, context: CIContext) throws -> CGImage {
        let w = Double(image.width), h = Double(image.height)
        func corner(_ x: Double, _ dy: Double) -> CIVector {
            CIVector(x: x * w, y: h - (region.y0 + region.slope * x + dy) * h)
        }
        let filter = try XCTUnwrap(CIFilter(name: "CIPerspectiveCorrection"))
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(corner(region.left, -region.height / 2), forKey: "inputTopLeft")
        filter.setValue(corner(region.right, -region.height / 2), forKey: "inputTopRight")
        filter.setValue(corner(region.right, region.height / 2), forKey: "inputBottomRight")
        filter.setValue(corner(region.left, region.height / 2), forKey: "inputBottomLeft")
        let result = try XCTUnwrap(filter.outputImage)
        return try XCTUnwrap(context.createCGImage(result, from: result.extent))
    }

    private static func regionFields(_ region: PassPlan.Region) -> [String: Any] {
        ["page": region.page, "y0": region.y0, "slope": region.slope,
         "height": region.height, "left": region.left, "right": region.right]
    }

    private static func log(_ fixture: Fixture, _ values: [String: Any]) throws {
        var object = values
        object["fixture"] = fixture.rawValue
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        print("OCRFIELD|\(String(decoding: data, as: UTF8.self))")
    }
}
