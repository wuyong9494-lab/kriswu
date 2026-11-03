import XCTest
import Foundation
import CoreGraphics
import CoreImage
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Vision
@testable import ShiftReminder

/// Probe 7: eight frozen Probe 6 header-capped crops, its 1x/3x preparation paths,
/// and two minimum-height settings. These 32 requests are an independent
/// diagnostic, not a call to the current product recognition pipeline.
final class PlanReaderStatusProbe7Tests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        executionTimeAllowance = 180
    }

    func testCells01And04() async throws { try await Self.runCells([1, 4]) }
    func testCells07And10() async throws { try await Self.runCells([7, 10]) }
    func testCells13And16() async throws { try await Self.runCells([13, 16]) }
    func testCells19And22() async throws { try await Self.runCells([19, 22]) }

    private enum Fixture {
        static let name = "status_probe_web_photo"
        static let sha256 = "d6c7d3c30672244ae5b8713061d3cb7d4fff4996f27e193c58eabb128434ffba"
        static let width = 4032
        static let height = 3024
        static let geometryName = "status_cell_probe_geometry"
        static let geometrySHA256 = "d2107acbde65dc3a0446debea2097efd836c53c13608929d1f79b8d783254a37"
        static let photoSourceCommit = "f2fd46fee3295cc4cb06b930ea2e74b047d7c753"
        static let photoSourcePath = "Tests/SiteTests/OCRSamples/web_photo.jpg"
        static let probeBaseCommit = "cbfa12a2bad062fbe209b410605bee0d97156974"
        static let rows = [1, 4, 7, 10, 13, 16, 19, 22]
        static let scales = [1, 3]
        static let revision = 3
    }

    private enum MinimumHeight: String, CaseIterable {
        case min10, min0

        func value(baseHeight: Int) -> Float {
            self == .min10 ? Float(10.0 / Double(baseHeight)) : 0
        }
    }

    private struct GeometryRecording: Decodable {
        struct Photo: Decodable {
            let name, sourceCommit, sourcePath, sha256: String
            let width, height: Int
        }
        struct Row: Decodable {
            struct Crop: Decodable {
                let region: PassPlan.Region
                let cornersTopLeft: [[Double]]
            }
            let row: Int
            let crops: [String: Crop]
        }
        let schemaVersion: Int
        let recording: String
        let photo: Photo
        let selectedRows: [Int]
        let rows: [Row]
    }

    private struct PreparedPNG: Sendable {
        let imageID, name: String
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
        try log(["kind": "attachmentsSaved", "rows": rowNumbers, "count": images.count,
                 "imageIDs": images.map(\.imageID), "pngNames": images.map(\.name)])
    }

    private static func performCells(_ rowNumbers: [Int]) throws -> [PreparedPNG] {
        let groups = [[1, 4], [7, 10], [13, 16], [19, 22]]
        try require(groups.contains(rowNumbers), "Unexpected fixed method row group")
        try require(VNRecognizeTextRequest.supportedRevisions.contains(Fixture.revision),
                    "This runtime does not support the frozen Vision revision")
        let image = try loadPhoto()
        let recording = try loadGeometry()
        try log([
            "kind": "methodStart", "rows": rowNumbers, "scope": "independent-diagnostic",
            "fixture": Fixture.name, "sourceSHA256": Fixture.sha256,
            "photoSourceCommit": Fixture.photoSourceCommit, "photoSourcePath": Fixture.photoSourcePath,
            "probeBaseCommit": Fixture.probeBaseCommit, "runtimeCommit": runtimeCommit(),
            "geometrySHA256": Fixture.geometrySHA256, "geometryProvenance": recording.recording,
            "geometry": "headerCapped", "scales": Fixture.scales,
            "geometryScope": "Frozen Probe6 recorded region and identical perspective correction",
            "baselineComparison": "Compare 16 prepared PNG hashes with Probe6 after native execution; byte equality is not assumed",
            "photoSize": [image.width, image.height],
            "minimumHeightModes": MinimumHeight.allCases.map(\.rawValue),
            "minimumHeightPolicy": "min10 is 10/baseCrop.height at both scales; min0 is the lowest-threshold experiment, not a guarantee against internal resizing",
            "expectedRequests": 8, "expectedPrepared": 4, "totalProbeRequests": 32, "totalPrepared": 16,
            "requestRevision": Fixture.revision,
            "supportedRevisions": Array(VNRecognizeTextRequest.supportedRevisions),
            "allowanceSeconds": 180, "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ])
        let context = CIContext()
        let source = CIImage(cgImage: image)
        var images: [PreparedPNG] = []
        var startedIDs: [String] = []
        var completedIDs: [String] = []
        for rowNumber in rowNumbers {
            let row = try XCTUnwrap(recording.rows.first { $0.row == rowNumber })
            let crop = try XCTUnwrap(row.crops["headerCapped"])
            let corners = sourceCorners(crop.region, width: image.width, height: image.height)
            try require(crop.cornersTopLeft.count == 4 && crop.cornersTopLeft.allSatisfy { $0.count == 2 }
                && zip(corners.flatMap { $0 }, crop.cornersTopLeft.flatMap { $0 })
                    .allSatisfy { abs($0 - $1) < 1e-7 }, "Frozen crop corner mismatch")
            let straight = try XCTUnwrap(straightened(crop.region, source: source,
                width: Double(image.width), height: Double(image.height)))
            try require(straight.extent.width > 2 && straight.extent.height > 2, "Invalid rectified extent")
            let base = try XCTUnwrap(context.createCGImage(straight, from: straight.extent))
            try log([
                "kind": "baseCrop", "row": rowNumber, "geometry": "headerCapped",
                "cellRegion": regionJSON(crop.region),
                "sourceCorners": corners, "sourceCoordinates": "source-pixels-top-left",
                "sourceCornerOrder": ["topLeft", "topRight", "bottomRight", "bottomLeft"],
                "rectifiedExtent": boundsJSON(straight.extent),
                "rectifiedExtentCoordinates": "CoreImage-pixels-bottom-left",
                "baseCropSize": [base.width, base.height], "colorManagement": "CoreImage-default",
            ])
            for scale in Fixture.scales {
                // Identical to Probe6: both scales derive from the same rectified CGImage.
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
                let imageID = "row-\(rowNumber)-headerCapped-\(scale)x"
                let pixels = try XCTUnwrap(prepared.dataProvider?.data)
                let pixelSHA = sha256(pixels as Data)
                let png = try makePNG(prepared, imageID: imageID)
                let pngSHA = sha256(png.data)
                images.append(png)
                try log([
                    "kind": "prepared", "imageID": imageID, "row": rowNumber,
                    "geometry": "headerCapped", "scale": scale,
                    "baseCropSize": [base.width, base.height], "size": [prepared.width, prepared.height],
                    "processing": "Probe6 perspective-corrected CGImage and fixed affine scale; no added blur, color filter, padding, or color-space normalization",
                    "bitsPerComponent": prepared.bitsPerComponent,
                    "bitsPerPixel": prepared.bitsPerPixel, "bytesPerRow": prepared.bytesPerRow,
                    "colorSpaceName": colorSpaceName(prepared),
                    "colorSpaceModel": prepared.colorSpace.map { Int($0.model.rawValue) as Any } ?? NSNull(),
                    "alphaInfo": prepared.alphaInfo.rawValue, "bitmapInfo": prepared.bitmapInfo.rawValue,
                    "pixelSHA256": pixelSHA, "pixelHashScope": "CGImage-dataProvider-bytes",
                    "pngName": png.name, "pngSHA256": pngSHA, "pngBytes": png.data.count,
                    "requestIDs": MinimumHeight.allCases.map { "\(imageID)-\($0.rawValue)" },
                ])
                for mode in MinimumHeight.allCases {
                    let requestID = "\(imageID)-\(mode.rawValue)"
                    let request = VNRecognizeTextRequest()
                    request.revision = Fixture.revision
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["zh-Hans", "en-US"]
                    // Preserve the API default, as Probe6 did; log the actual value below.
                    request.usesLanguageCorrection = false
                    request.customWords = []
                    let requestedMinHeight = mode.value(baseHeight: base.height)
                    request.minimumTextHeight = requestedMinHeight
                    let supportedLanguages = try request.supportedRecognitionLanguages()
                    try require(request.recognitionLanguages.allSatisfy(supportedLanguages.contains),
                                "Runtime language support does not match the frozen request")
                    try require(request.revision == Fixture.revision, "Vision revision changed")
                    try log([
                        "kind": "requestStart", "requestID": requestID, "imageID": imageID,
                        "row": rowNumber, "geometry": "headerCapped", "scale": scale,
                        "minimumHeightMode": mode.rawValue,
                        "baseCropSize": [base.width, base.height], "size": [prepared.width, prepared.height],
                        "level": "accurate", "languages": request.recognitionLanguages,
                        "supportedLanguages": supportedLanguages,
                        "automaticallyDetectsLanguage": request.automaticallyDetectsLanguage,
                        "automaticLanguagePolicy": "unchanged API default, matching Probe6 configuration",
                        "languageCorrection": false, "customWords": [String](),
                        "configuredMinHeight": Double(requestedMinHeight),
                        "normalizedMinHeight": Double(request.minimumTextHeight),
                        "effectiveMinPixels": Double(request.minimumTextHeight) * Double(prepared.height),
                        "requestRevision": request.revision, "orientation": "up", "topCandidates": 3,
                        "pixelSHA256": pixelSHA, "pngSHA256": pngSHA,
                    ])
                    startedIDs.append(requestID)
                    let began = ProcessInfo.processInfo.systemUptime
                    do {
                        try require(request.minimumTextHeight == requestedMinHeight,
                                    "Vision minimumTextHeight readback differs from the requested setting")
                        try VNImageRequestHandler(cgImage: prepared, orientation: .up).perform([request])
                    } catch {
                        try log(["kind": "requestError", "requestID": requestID, "imageID": imageID,
                                 "error": String(describing: error)])
                        throw error
                    }
                    let seconds = ProcessInfo.processInfo.systemUptime - began
                    let observations = request.results ?? []
                    var candidateCount = 0
                    for (index, observation) in observations.enumerated() {
                        let candidates = observation.topCandidates(3)
                        try log([
                            "kind": "observation", "requestID": requestID, "imageID": imageID, "index": index,
                            "box": boundsJSON(observation.boundingBox),
                            "coordinates": "prepared-normalized-bottom-left", "candidates": candidates.count,
                        ])
                        for (rank, candidate) in candidates.enumerated() {
                            try log([
                                "kind": "candidate", "requestID": requestID, "imageID": imageID,
                                "observation": index, "rank": rank + 1, "raw": candidate.string,
                                "confidence": Double(candidate.confidence),
                            ])
                            candidateCount += 1
                        }
                        if let top = candidates.first {
                            try logCharacterBounds(top, requestID: requestID, imageID: imageID, observation: index)
                        }
                    }
                    completedIDs.append(requestID)
                    try log([
                        "kind": "requestEnd", "requestID": requestID, "imageID": imageID,
                        "observations": observations.count, "candidates": candidateCount,
                        "seconds": seconds,
                    ])
                }
            }
        }
        let expectedImages = Set(rowNumbers.flatMap { row in Fixture.scales.map { "row-\(row)-headerCapped-\($0)x" } })
        let expectedRequests = Set(expectedImages.flatMap { id in MinimumHeight.allCases.map { "\(id)-\($0.rawValue)" } })
        try require(images.count == 4 && Set(images.map(\.imageID)) == expectedImages,
                    "All four fixed prepared images must be retained")
        try require(startedIDs.count == 8 && completedIDs.count == 8
                    && Set(startedIDs) == expectedRequests && Set(completedIDs) == expectedRequests,
                    "All eight fixed requests must start and complete exactly once")
        try log(["kind": "methodEnd", "rows": rowNumbers, "requests": completedIDs.count,
                 "prepared": images.count, "requestIDs": completedIDs.sorted(), "imageIDs": expectedImages.sorted()])
        return images
    }

    /// Identical to Probe 6 perspective correction; no new padding, blur, or scaling.
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
                                          imageID: String, observation: Int) throws {
        let text = candidate.string
        for (offset, index) in text.indices.prefix(64).enumerated() {
            var record: [String: Any] = [
                "kind": "characterBounds", "requestID": requestID, "imageID": imageID,
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
        try log(["kind": "characterBoundsEnd", "requestID": requestID, "imageID": imageID,
                 "observation": observation, "rank": 1, "characters": text.count,
                 "logged": min(text.count, 64), "limit": 64, "truncated": text.count > 64])
    }

    private static func loadPhoto() throws -> CGImage {
        let bundle = Bundle(for: PlanReaderStatusProbe7Tests.self)
        let url = try XCTUnwrap(bundle.url(forResource: Fixture.name, withExtension: "jpg"))
        let data = try Data(contentsOf: url)
        try require(sha256(data) == Fixture.sha256, "Frozen public photo bytes changed")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        try require(image.width == Fixture.width && image.height == Fixture.height, "Photo dimensions changed")
        return image
    }

    private static func loadGeometry() throws -> GeometryRecording {
        let bundle = Bundle(for: PlanReaderStatusProbe7Tests.self)
        let url = try XCTUnwrap(bundle.url(forResource: Fixture.geometryName, withExtension: "json"))
        let data = try Data(contentsOf: url)
        try require(sha256(data) == Fixture.geometrySHA256, "Frozen Probe6 geometry bytes changed")
        let value = try JSONDecoder().decode(GeometryRecording.self, from: data)
        try require(value.schemaVersion == 1 && value.photo.name == Fixture.name
                    && value.photo.sha256 == Fixture.sha256 && value.photo.width == Fixture.width
                    && value.photo.height == Fixture.height && value.photo.sourceCommit == Fixture.photoSourceCommit
                    && value.photo.sourcePath == Fixture.photoSourcePath
                    && value.selectedRows == Fixture.rows && value.rows.map(\.row) == Fixture.rows,
                    "Frozen geometry source or row selection changed")
        return value
    }

    private static func sourceCorners(_ region: PassPlan.Region, width: Int, height: Int) -> [[Double]] {
        [(region.left, -0.5), (region.right, -0.5), (region.right, 0.5), (region.left, 0.5)].map { x, dy in
            [x * Double(width), (region.y0 + region.slope * x + dy * region.height) * Double(height)]
        }
    }

    private static func boundsJSON(_ rect: CGRect) -> Any {
        guard !rect.isNull, !rect.isInfinite,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { return NSNull() }
        return [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
    }

    private static func regionJSON(_ region: PassPlan.Region) -> [String: Any] {
        ["page": region.page, "y0": region.y0, "slope": region.slope,
         "height": region.height, "left": region.left, "right": region.right]
    }

    private static func colorSpaceName(_ image: CGImage) -> Any {
        guard let name = image.colorSpace?.name else { return NSNull() }
        return name as String
    }

    private static func makePNG(_ image: CGImage, imageID: String) throws -> PreparedPNG {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return PreparedPNG(imageID: imageID, name: "probe7-\(imageID).png", data: data as Data)
    }

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
        print("OCRPROBE7|\(String(decoding: data, as: UTF8.self))")
    }
}
