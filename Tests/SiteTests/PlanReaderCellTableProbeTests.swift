import XCTest
import Foundation
import CoreGraphics
import CoreImage
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Vision
@testable import ShiftReminder

/// Probe 6: 32 serial cell requests and one existing-vocabulary system-table baseline.
/// This freezes a production-style crop copy, not the complete production OCR path.
/// Geometry comes from the public generator, not Build 495 OCR boxes or status truth.
final class PlanReaderCellTableProbeTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        executionTimeAllowance = 180
    }

    func testCells01And04() async throws { try await Self.runCells([1, 4]) }
    func testCells07And10() async throws { try await Self.runCells([7, 10]) }
    func testCells13And16() async throws { try await Self.runCells([13, 16]) }
    func testCells19And22() async throws { try await Self.runCells([19, 22]) }

    func testSystemTableWithProductionVocabulary() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("System-table probe requires iOS 26") }
        // All image and Vision objects stay inside this task. No parallel OCR requests.
        let work: Task<Void, Error> = Task.detached(priority: .userInitiated) {
            try await Self.performSystemTable()
        }
        try await work.value
    }

    private enum Fixture {
        static let name = "status_probe_web_photo"
        static let sourceCommit = "f2fd46fee3295cc4cb06b930ea2e74b047d7c753"
        static let sourcePath = "Tests/SiteTests/OCRSamples/web_photo.jpg"
        static let sha256 = "d6c7d3c30672244ae5b8713061d3cb7d4fff4996f27e193c58eabb128434ffba"
        static let width = 4032
        static let height = 3024
        static let geometryName = "status_cell_probe_geometry"
        static let geometrySHA256 = "d2107acbde65dc3a0446debea2097efd836c53c13608929d1f79b8d783254a37"
        static let rulesSHA256 = "428404cb06e8cb4410000b6112da8161a60572ce5f057b0941250e3fe6737785"
        static let probeBaseCommit = "81df9e891fa02dc9910e9d608919154bf3fcadbb"
        static let selectedRows = [1, 4, 7, 10, 13, 16, 19, 22]
        static let scales = [1, 3]
    }

    private enum Geometry: String, CaseIterable {
        case production, headerCapped
    }

    private struct GeometryRecording: Decodable {
        struct Photo: Decodable {
            let name, sourceCommit, sourcePath, sha256: String
            let width, height: Int
        }
        struct Layout: Decodable {
            struct Slot: Decodable {
                let label, column: String
                let x: Double
            }
            let slots: [Slot]
        }
        struct Row: Decodable {
            struct Crop: Decodable {
                let region: PassPlan.Region
                let cornersTopLeft: [[Double]]
            }
            let row: Int
            // After bounding against all 22 rows, before boundedCellRegion.
            let region: PassPlan.Region
            let crops: [String: Crop]
        }
        let schemaVersion: Int
        let recording: String
        let photo: Photo
        let layout: Layout
        let statusColumnIndex: Int
        let variants: [String]
        let scales, selectedRows: [Int]
        let rows: [Row]
    }

    /// Only the existing public synthetic operator rules are decoded. No truth rows are decoded.
    private struct RulesOnly: Decodable {
        let rules: [String: [String]]
    }

    private struct PreparedPNG: Sendable {
        let name: String
        let data: Data
    }

    private enum ProbeError: Error {
        case invalidInput(String)
    }

    private static func runCells(_ rowNumbers: [Int]) async throws {
        let work: Task<[PreparedPNG], Error> = Task.detached(priority: .userInitiated) {
            try performCells(rowNumbers)
        }
        let images = try await work.value
        // XCTContext.runActivity is main-actor isolated in Xcode 26.
        await MainActor.run {
            for image in images {
                XCTContext.runActivity(named: image.name) { activity in
                    let attachment = XCTAttachment(data: image.data, uniformTypeIdentifier: UTType.png.identifier)
                    attachment.name = image.name
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
            }
        }
        try log(["kind": "attachmentsSaved", "family": "cell", "rows": rowNumbers, "count": images.count])
    }

    private static func performCells(_ rowNumbers: [Int]) throws -> [PreparedPNG] {
        let image = try loadPhoto()
        let recording = try loadGeometry()
        let slots = try recording.layout.slots.map { slot -> PassPlan.Layout.Slot in
            let column = try XCTUnwrap(PassPlan.Column(rawValue: slot.column))
            return PassPlan.Layout.Slot(label: slot.label, column: column, x: slot.x)
        }
        let layout = PassPlan.Layout(slots: slots)
        try require(rowNumbers.count == 2 && rowNumbers.allSatisfy(Fixture.selectedRows.contains),
                    "Each cell method must use two preselected rows")
        try log([
            "kind": "methodStart", "family": "cell", "rows": rowNumbers,
            "fixture": Fixture.name, "sourceSHA256": Fixture.sha256,
            "productionSource": Fixture.sourceCommit, "sourcePath": Fixture.sourcePath,
            "probeBaseCommit": Fixture.probeBaseCommit, "runtimeCommit": runtimeCommit(),
            "geometrySHA256": Fixture.geometrySHA256, "geometryProvenance": recording.recording,
            "geometryScope": "production-style-copy: boundedCellRegion + cropCell perspective correction",
            "requestScope": "frozen local diagnostic settings; not current production function invocation",
            "photoSize": [image.width, image.height], "variants": recording.variants,
            "scales": Fixture.scales, "expectedRequests": 8, "totalProbeRequests": 33,
            "allowanceSeconds": 180, "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ])
        // The production crop uses default Core Image color management.
        let context = CIContext()
        let source = CIImage(cgImage: image)
        var images: [PreparedPNG] = []
        var completedRequests = 0
        for rowNumber in rowNumbers {
            let row = try XCTUnwrap(recording.rows.first { $0.row == rowNumber })
            for geometry in Geometry.allCases {
                var inputRegion = row.region
                if geometry == .headerCapped {
                    let xs = layout.slots.map(\.x)
                    let last = xs.count - 1
                    inputRegion.right = min(inputRegion.right, xs[last] + (xs[last] - xs[last - 1]) / 2)
                }
                let region = try XCTUnwrap(boundedCellRegion(
                    column: recording.statusColumnIndex, of: inputRegion, layout: layout))
                let expected = try XCTUnwrap(row.crops[geometry.rawValue])
                let corners = sourceCorners(region, width: image.width, height: image.height)
                try validate(region, corners: corners, against: expected)
                let began = ProcessInfo.processInfo.systemUptime
                let straight = try XCTUnwrap(straightened(region, source: source,
                    width: Double(image.width), height: Double(image.height)))
                try require(straight.extent.width > 2 && straight.extent.height > 2, "Invalid rectified extent")
                let base = try XCTUnwrap(context.createCGImage(straight, from: straight.extent))
                let normalizedMinHeight = Float(10.0 / Double(base.height))
                try log([
                    "kind": "baseCrop", "family": "cell", "row": rowNumber, "geometry": geometry.rawValue,
                    "regionBeforeCellBounding": regionJSON(inputRegion), "cellRegion": regionJSON(region),
                    "sourceCorners": corners, "sourceCornerOrder": ["topLeft", "topRight", "bottomRight", "bottomLeft"],
                    "sourceCoordinates": "source-pixels-top-left", "rectifiedExtent": boundsJSON(straight.extent),
                    "rectifiedExtentCoordinates": "CoreImage-pixels-bottom-left",
                    "baseCropSize": [base.width, base.height], "normalizedMinHeight": Double(normalizedMinHeight),
                    "minimumHeightPolicy": "10/baseCrop.height; identical normalized value for both scales",
                    "colorManagement": "CoreImage-default", "seconds": ProcessInfo.processInfo.systemUptime - began,
                ])
                for scale in Fixture.scales {
                    // Both scales derive from this exact same, already rectified CGImage.
                    let prepared: CGImage
                    if scale == 1 {
                        prepared = base
                    } else {
                        let sized = CIImage(cgImage: base).transformed(by: CGAffineTransform(
                            scaleX: CGFloat(scale), y: CGFloat(scale)))
                        prepared = try XCTUnwrap(context.createCGImage(sized, from: sized.extent))
                    }
                    try require(prepared.width == base.width * scale && prepared.height == base.height * scale,
                                "Fixed scale changed the expected dimensions")
                    let requestID = "row-\(rowNumber)-\(geometry.rawValue)-\(scale)x"
                    let pixels = try XCTUnwrap(prepared.dataProvider?.data)
                    let png = try makePNG(prepared, name: "probe6-\(requestID).png")
                    images.append(png)
                    try log([
                        "kind": "prepared", "family": "cell", "requestID": requestID,
                        "row": rowNumber, "geometry": geometry.rawValue, "scale": scale,
                        "baseCropSize": [base.width, base.height], "size": [prepared.width, prepared.height],
                        "processing": "perspective-corrected CGImage; optional fixed affine scale; no added blur or color filters",
                        "bitsPerPixel": prepared.bitsPerPixel, "bytesPerRow": prepared.bytesPerRow,
                        "pixelSHA256": sha256(pixels as Data), "pixelHashScope": "CGImage-dataProvider-bytes",
                        "pngName": png.name, "pngSHA256": sha256(png.data), "pngBytes": png.data.count,
                    ])
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["zh-Hans", "en-US"]
                    request.usesLanguageCorrection = false
                    request.customWords = []
                    request.minimumTextHeight = normalizedMinHeight
                    try log([
                        "kind": "requestStart", "family": "cell", "requestID": requestID,
                        "level": "accurate", "languages": request.recognitionLanguages,
                        "languageCorrection": false, "customWords": [String](),
                        "normalizedMinHeight": Double(request.minimumTextHeight),
                        "effectiveMinPixels": Double(request.minimumTextHeight) * Double(prepared.height),
                        "requestRevision": request.revision, "orientation": "up", "topCandidates": 3,
                    ])
                    let requestBegan = ProcessInfo.processInfo.systemUptime
                    try VNImageRequestHandler(cgImage: prepared, orientation: .up).perform([request])
                    let seconds = ProcessInfo.processInfo.systemUptime - requestBegan
                    let observations = request.results ?? []
                    var candidateCount = 0
                    for (index, observation) in observations.enumerated() {
                        let candidates = observation.topCandidates(3)
                        try log([
                            "kind": "observation", "family": "cell", "requestID": requestID, "index": index,
                            "box": boundsJSON(observation.boundingBox), "coordinates": "prepared-normalized-bottom-left",
                            "candidates": candidates.count,
                        ])
                        for (rank, candidate) in candidates.enumerated() {
                            try log([
                                "kind": "candidate", "family": "cell", "requestID": requestID,
                                "observation": index, "rank": rank + 1,
                                "raw": candidate.string, "confidence": Double(candidate.confidence),
                            ])
                            candidateCount += 1
                        }
                        if let top = candidates.first {
                            try logCharacterBounds(top, requestID: requestID, observation: index)
                        }
                    }
                    completedRequests += 1
                    try log([
                        "kind": "requestEnd", "family": "cell", "requestID": requestID,
                        "observations": observations.count, "candidates": candidateCount, "seconds": seconds,
                    ])
                }
            }
        }
        try require(completedRequests == 8, "All eight fixed cell requests must complete")
        try log(["kind": "methodEnd", "family": "cell", "rows": rowNumbers, "requests": completedRequests])
        return images
    }

    /// Frozen verbatim algorithm from PlanReader at f2fd46f. This does not invoke the product helper.
    private static func boundedCellRegion(column s: Int, of region: PassPlan.Region,
                                          layout: PassPlan.Layout) -> PassPlan.Region? {
        let xs = layout.slots.map(\.x)
        guard xs.indices.contains(s), xs.allSatisfy(\.isFinite),
              region.y0.isFinite, region.slope.isFinite, region.height.isFinite, region.height > 0,
              region.left.isFinite, region.right.isFinite else { return nil }
        let left = max(max(0, region.left), s > 0 ? (xs[s - 1] + xs[s]) / 2 : region.left)
        let right = min(min(1, region.right), s < xs.count - 1 ? (xs[s] + xs[s + 1]) / 2 : region.right)
        guard right > left else { return nil }
        let leftY = region.y0 + region.slope * left
        let rightY = region.y0 + region.slope * right
        let imageMargin = min(min(leftY, rightY), min(1 - leftY, 1 - rightY))
        let halfHeight = min(region.height * 0.45, imageMargin)
        guard halfHeight > 0 else { return nil }
        return PassPlan.Region(page: region.page, y0: region.y0, slope: region.slope, height: halfHeight * 2,
                               left: left, right: right)
    }

    /// Frozen production-style perspective correction, without JPEG conversion or added padding.
    private static func straightened(_ region: PassPlan.Region, source: CIImage,
                                     width: Double, height: Double) -> CIImage? {
        func corner(_ x: Double, _ dy: Double) -> CIVector {
            CIVector(x: x * width, y: height - (region.y0 + region.slope * x + dy) * height)
        }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(corner(region.left, -region.height / 2), forKey: "inputTopLeft")
        filter.setValue(corner(region.right, -region.height / 2), forKey: "inputTopRight")
        filter.setValue(corner(region.right, region.height / 2), forKey: "inputBottomRight")
        filter.setValue(corner(region.left, region.height / 2), forKey: "inputBottomLeft")
        return filter.outputImage
    }

    private static func logCharacterBounds(_ candidate: VNRecognizedText, requestID: String,
                                            observation: Int) throws {
        let text = candidate.string
        // Keep whitespace and missing/shared boxes. These boxes do not imply usable segmentation.
        for (offset, index) in text.indices.prefix(64).enumerated() {
            var record: [String: Any] = [
                "kind": "characterBounds", "family": "cell", "requestID": requestID,
                "observation": observation, "rank": 1, "characterIndex": offset,
                "raw": String(text[index]), "unit": "Swift-Character",
                "coordinates": "prepared-normalized-bottom-left", "box": NSNull(),
            ]
            do {
                if let box = try candidate.boundingBox(for: index..<text.index(after: index)) {
                    record["box"] = boundsJSON(box.boundingBox)
                    record["result"] = "returned"
                } else {
                    record["result"] = "missing"
                }
            } catch {
                record["result"] = "error"
                record["error"] = String(describing: error)
            }
            try log(record)
        }
        try log([
            "kind": "characterBoundsEnd", "family": "cell", "requestID": requestID,
            "observation": observation, "rank": 1, "characters": text.count,
            "logged": min(text.count, 64), "limit": 64, "truncated": text.count > 64,
        ])
    }

    @available(iOS 26.0, *)
    private static func performSystemTable() async throws {
        let image = try loadPhoto()
        let bundle = Bundle(for: PlanReaderCellTableProbeTests.self)
        let rulesURL = try XCTUnwrap(bundle.url(forResource: "web_photo", withExtension: "json"))
        let rulesData = try Data(contentsOf: rulesURL)
        try require(sha256(rulesData) == Fixture.rulesSHA256, "Existing public rules source changed")
        let rulesOnly = try JSONDecoder().decode(RulesOnly.self, from: rulesData)
        let rules = rulesOnly.rules.sorted { $0.key < $1.key }
            .map { PassPlan.OperatorRule(name: $0.key, prefixes: $0.value) }
        let words = PassPlan.vocabulary(rules)
        try require(rules.count == 8 && words.count == 42, "Existing Build 495 vocabulary changed")
        try log([
            "kind": "methodStart", "family": "systemTable", "fixture": Fixture.name,
            "sourceSHA256": Fixture.sha256, "productionSource": Fixture.sourceCommit,
            "probeBaseCommit": Fixture.probeBaseCommit, "runtimeCommit": runtimeCommit(),
            "photoSize": [image.width, image.height], "expectedRequests": 1, "totalProbeRequests": 33,
            "allowanceSeconds": 180, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "requestScope": "Build 495 existing-vocabulary baseline; not independent or vocabulary-free confirmation",
            "parserScope": "readTable + layout + row + normalizedTime; not the complete product pipeline",
        ])
        try log([
            "kind": "vocabulary", "family": "systemTable", "customWords": words,
            "customWordsCount": words.count, "provenance": "PassPlan.vocabulary(sorted existing synthetic web_photo rules)",
            "rulesSource": "Tests/SiteTests/OCRSamples/web_photo.json", "rulesSourceSHA256": Fixture.rulesSHA256,
            "decodedKeys": ["rules"], "truthRowsDecoded": false,
            "rules": rules.map { ["name": $0.name, "prefixes": $0.prefixes] as [String: Any] },
            "preexistingStatusWord": "等待数传", "statusWordAddedForThisProbe": false,
        ])
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"),
                                                               Locale.Language(identifier: "en-US")]
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.customWords = words
        let minHeight = Float(max(10.0 / Double(image.height), 0.002))
        request.textRecognitionOptions.minimumTextHeightFraction = minHeight
        try log([
            "kind": "requestStart", "family": "systemTable", "requestID": "system-table",
            "languages": ["zh-Hans", "en-US"], "languageCorrection": true, "customWordsCount": words.count,
            "normalizedMinHeight": Double(minHeight), "effectiveMinPixels": Double(minHeight) * Double(image.height),
            "orientation": "up", "otherOptions": "RecognizeDocumentsRequest defaults",
        ])
        let began = ProcessInfo.processInfo.systemUptime
        let observations = try await request.perform(on: image, orientation: .up)
        let seconds = ProcessInfo.processInfo.systemUptime - began
        let tables = observations.flatMap(\.document.tables)
        let tableOrigins = observations.enumerated().flatMap { observation in
            observation.element.document.tables.enumerated().map {
                (observationIndex: observation.offset, tableWithinObservationIndex: $0.offset)
            }
        }
        try log([
            "kind": "requestEnd", "family": "systemTable", "requestID": "system-table",
            "observations": observations.count, "tables": tables.count, "seconds": seconds,
        ])

        // Preserve every raw transcript and inclusive range before any grid conversion or parsing.
        for (tableIndex, table) in tables.enumerated() {
            try log([
                "kind": "rawTable", "family": "systemTable", "table": tableIndex, "rows": table.rows.count,
                "observationIndex": tableOrigins[tableIndex].observationIndex,
                "tableWithinObservationIndex": tableOrigins[tableIndex].tableWithinObservationIndex,
                "bounds": boundsJSON(table.boundingRegion.normalizedPath.boundingBoxOfPath),
                "coordinates": "Vision-normalized-bottom-left", "boundsOrder": ["x", "y", "width", "height"],
            ])
            for (rowIndex, row) in table.rows.enumerated() {
                try log(["kind": "rawRow", "family": "systemTable", "table": tableIndex,
                         "row": rowIndex, "cells": row.count])
                for (cellIndex, cell) in row.enumerated() {
                    try log([
                        "kind": "rawCell", "family": "systemTable", "table": tableIndex,
                        "row": rowIndex, "cell": cellIndex, "raw": cell.content.text.transcript,
                        "rowRange": [cell.rowRange.lowerBound, cell.rowRange.upperBound],
                        "columnRange": [cell.columnRange.lowerBound, cell.columnRange.upperBound],
                        "rangeEndpoints": "inclusive",
                        "contentBounds": boundsJSON(cell.content.boundingRegion.normalizedPath.boundingBoxOfPath),
                        "coordinates": "Vision-normalized-bottom-left",
                        "boundsMeaning": "axis-aligned content path bounds; not a physical grid cell",
                    ])
                }
            }
        }

        // This conversion preserves the product's ordering, empty padding and overlap skipping.
        var grids: [[[String]]] = []
        for (tableIndex, table) in tables.enumerated() {
            var grid: [[String]] = []
            for (rowIndex, row) in table.rows.enumerated() {
                var cells: [String] = []
                for (sortedIndex, cell) in row.sorted(by: { $0.columnRange.lowerBound < $1.columnRange.lowerBound }).enumerated() {
                    while cells.count < cell.columnRange.lowerBound { cells.append("") }
                    guard cells.count == cell.columnRange.lowerBound else {
                        try log([
                            "kind": "gridCellSkipped", "family": "systemTable", "table": tableIndex,
                            "row": rowIndex, "sortedCell": sortedIndex, "gridCount": cells.count,
                            "columnRange": [cell.columnRange.lowerBound, cell.columnRange.upperBound],
                            "raw": cell.content.text.transcript,
                        ])
                        continue
                    }
                    cells.append(cell.content.text.transcript.replacingOccurrences(of: "\n", with: " "))
                }
                grid.append(cells)
                try log(["kind": "gridRow", "family": "systemTable", "table": tableIndex,
                         "row": rowIndex, "cells": cells])
            }
            grids.append(grid)
        }
        let readings = grids.map(PassPlan.readTable)
        for (tableIndex, reading) in readings.enumerated() {
            let layout: Any = reading.layout.map { layout -> Any in
                layout.slots.map { ["label": $0.label, "column": nullable($0.column?.rawValue), "x": $0.x] }
            } ?? NSNull()
            try log(["kind": "parsedLayout", "family": "systemTable", "table": tableIndex,
                     "layout": layout, "rows": reading.rows.count, "xMeaning": "grid-column-index"])
            for (rowIndex, row) in reading.rows.enumerated() {
                try log([
                    "kind": "parsedRow", "family": "systemTable", "table": tableIndex, "row": rowIndex,
                    "orbit": row.orbit, "satelliteID": row.satelliteID, "satellite": row.satellite,
                    "station": row.station, "start": row.start, "end": row.end,
                    "info": row.info, "status": row.status, "cells": row.cells,
                    "emergencyBadge": nullable(row.emergencyBadge), "testStatusDetected": nullable(row.testStatusDetected),
                    "recognitionIssues": nullable(row.recognitionIssues),
                ])
            }
        }
        let selected = readings.enumerated().max { $0.element.rows.count < $1.element.rows.count }
        try log([
            "kind": "methodEnd", "family": "systemTable", "requests": 1,
            "tables": tables.count, "selectedTable": nullable(selected?.offset),
            "selectedRows": selected?.element.rows.count ?? 0,
            "selection": "max parsed row count, matching product tableReading",
        ])
    }

    private static func loadPhoto() throws -> CGImage {
        let bundle = Bundle(for: PlanReaderCellTableProbeTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: Fixture.name, withExtension: "jpg"))
        let data = try Data(contentsOf: url)
        try require(sha256(data) == Fixture.sha256, "Frozen public image bytes changed")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        try require(image.width == Fixture.width && image.height == Fixture.height, "Source dimensions changed")
        return image
    }

    private static func loadGeometry() throws -> GeometryRecording {
        let bundle = Bundle(for: PlanReaderCellTableProbeTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: Fixture.geometryName, withExtension: "json"))
        let data = try Data(contentsOf: url)
        try require(sha256(data) == Fixture.geometrySHA256, "Frozen geometry recording changed")
        let recording = try JSONDecoder().decode(GeometryRecording.self, from: data)
        try require(recording.schemaVersion == 1 && recording.photo.name == Fixture.name
                    && recording.photo.sha256 == Fixture.sha256 && recording.photo.width == Fixture.width
                    && recording.photo.height == Fixture.height && recording.photo.sourceCommit == Fixture.sourceCommit
                    && recording.photo.sourcePath == Fixture.sourcePath, "Geometry source metadata changed")
        try require(recording.selectedRows == Fixture.selectedRows && recording.rows.map(\.row) == Fixture.selectedRows
                    && recording.scales == Fixture.scales && recording.variants == Geometry.allCases.map(\.rawValue),
                    "Frozen request selection changed")
        try require(recording.statusColumnIndex == recording.layout.slots.count - 1
                    && recording.layout.slots.count > 1
                    && recording.layout.slots.last?.column == "status", "Expected rightmost status column")
        return recording
    }

    private static func sourceCorners(_ region: PassPlan.Region, width: Int, height: Int) -> [[Double]] {
        let pairs = [(region.left, -0.5), (region.right, -0.5), (region.right, 0.5), (region.left, 0.5)]
        return pairs.map { x, dy in
            [x * Double(width), (region.y0 + region.slope * x + dy * region.height) * Double(height)]
        }
    }

    private static func validate(_ region: PassPlan.Region, corners: [[Double]],
                                 against expected: GeometryRecording.Row.Crop) throws {
        let values = [region.y0, region.slope, region.height, region.left, region.right]
        let target = [expected.region.y0, expected.region.slope, expected.region.height,
                      expected.region.left, expected.region.right]
        try require(region.page == expected.region.page && zip(values, target).allSatisfy { abs($0 - $1) < 1e-12 },
                    "Frozen crop region does not match production-style formula")
        try require(expected.cornersTopLeft.count == 4 && expected.cornersTopLeft.allSatisfy { $0.count == 2 }
                    && zip(corners.flatMap { $0 }, expected.cornersTopLeft.flatMap { $0 })
                        .allSatisfy { abs($0 - $1) < 1e-7 }, "Source corner recording mismatch")
    }

    private static func regionJSON(_ region: PassPlan.Region) -> [String: Any] {
        ["page": region.page, "y0": region.y0, "slope": region.slope,
         "height": region.height, "left": region.left, "right": region.right]
    }

    private static func boundsJSON(_ rect: CGRect) -> Any {
        guard !rect.isNull, !rect.isInfinite,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { return NSNull() }
        return [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
    }

    private static func makePNG(_ image: CGImage, name: String) throws -> PreparedPNG {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return PreparedPNG(name: name, data: data as Data)
    }

    private static func nullable<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }

    private static func runtimeCommit() -> String {
        Bundle.main.object(forInfoDictionaryKey: "ArenaCommitSHA") as? String ?? "unknown"
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw ProbeError.invalidInput(message) }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
    }

    private static func log(_ values: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        print("OCRPROBE6|\(String(decoding: data, as: UTF8.self))")
    }
}
