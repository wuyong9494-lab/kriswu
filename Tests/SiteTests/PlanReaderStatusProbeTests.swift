import XCTest
import Foundation
import CoreGraphics
import CoreImage
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Probe 5: twelve fixed requests on a public synthetic fixture, independent of production parsing.
/// No truth file, status vocabulary, identifier recordings, or product OCR helper is loaded.
final class PlanReaderStatusProbeTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        executionTimeAllowance = 180
    }

    func testStatusSegment1() async throws { try await Self.run(.first) }
    func testStatusSegment3() async throws { try await Self.run(.third) }
    func testStatusSegment5() async throws { try await Self.run(.fifth) }

    private enum Fixture {
        static let name = "status_probe_web_photo"
        static let sourceCommit = "f2fd46fee3295cc4cb06b930ea2e74b047d7c753"
        static let sourcePath = "Tests/SiteTests/OCRSamples/web_photo.jpg"
        static let sha256 = "d6c7d3c30672244ae5b8713061d3cb7d4fff4996f27e193c58eabb128434ffba"
        static let width = 4032
        static let height = 3024
    }

    /// These are the actual Build 495 status-band crops, selected before this probe runs.
    /// Full band: top-left pixel rect (3394, 395, 638, 2403); segment numbers are one-based.
    private enum Segment: Int, Sendable {
        case first = 1, third = 3, fifth = 5

        var top: Int {
            switch self {
            case .first: return 395
            case .third: return 1355
            case .fifth: return 2315
            }
        }

        var height: Int { self == .fifth ? 483 : 600 }
        var rect: CGRect { CGRect(x: 3394, y: top, width: 638, height: height) }
    }

    private enum Variant: String, CaseIterable, Sendable {
        case original, gaussian08, gaussian12, blueGaussian08

        var sigma: Double {
            switch self {
            case .original: return 0
            case .gaussian08, .blueGaussian08: return 0.8
            case .gaussian12: return 1.2
            }
        }

        var blueOnly: Bool { self == .blueGaussian08 }
    }

    private struct PreparedPNG: Sendable {
        let name: String
        let data: Data
    }

    /// CGImage, CIContext and Vision objects are created and consumed inside this task.
    private static func run(_ segment: Segment) async throws {
        let work: Task<[PreparedPNG], Error> = Task.detached(priority: .userInitiated) {
            try perform(segment)
        }
        let preparedPNGs = try await work.value
        // Only immutable PNG Data crosses to XCTest's main-actor attachment API.
        await MainActor.run {
            for prepared in preparedPNGs {
                XCTContext.runActivity(named: prepared.name) { activity in
                    let attachment = XCTAttachment(data: prepared.data, uniformTypeIdentifier: UTType.png.identifier)
                    attachment.name = prepared.name
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
            }
        }
        try log(segment, ["kind": "attachmentsSaved", "count": preparedPNGs.count])
    }

    private static func perform(_ segment: Segment) throws -> [PreparedPNG] {
        let bundle = Bundle(for: PlanReaderStatusProbeTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: Fixture.name, withExtension: "jpg"))
        let imageData = try Data(contentsOf: url)
        guard sha256(imageData) == Fixture.sha256 else {
            XCTFail("Status probe requires the frozen public image from \(Fixture.sourceCommit)")
            return []
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        guard image.width == Fixture.width, image.height == Fixture.height else {
            XCTFail("Status probe source dimensions changed")
            return []
        }
        let crop = try XCTUnwrap(image.cropping(to: segment.rect))
        XCTAssertEqual(crop.width, 638)
        XCTAssertEqual(crop.height, segment.height)
        try log(segment, [
            "kind": "segmentStart", "fixture": Fixture.name,
            "sourceCommit": Fixture.sourceCommit, "sourcePath": Fixture.sourcePath,
            "sourceSHA256": Fixture.sha256, "photoSize": [image.width, image.height],
            "bandRect": [3394, 395, 638, 2403],
            "cropRect": [3394, segment.top, crop.width, crop.height],
            "cropCoordinates": "source-pixels-top-left",
            "variants": Variant.allCases.map(\.rawValue), "expectedRequests": 4,
            "allowanceSeconds": 180,
        ])

        // Disable input, working and output conversions so blue means the decoded image's B channel.
        // The unprocessed baseline never goes through Core Image or a bitmap redraw.
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var requests = 0
        var preparedPNGs: [PreparedPNG] = []
        for variant in Variant.allCases {
            let preprocessingBegan = ProcessInfo.processInfo.systemUptime
            let prepared = try prepare(crop, variant: variant, context: context)
            let preprocessingSeconds = ProcessInfo.processInfo.systemUptime - preprocessingBegan
            XCTAssertEqual(prepared.width, crop.width)
            XCTAssertEqual(prepared.height, crop.height)
            let pixels = try XCTUnwrap(prepared.dataProvider?.data)
            try log(segment, [
                "kind": "prepared", "variant": variant.rawValue, "sigma": variant.sigma,
                "rgbFromBlue": variant.blueOnly, "colorManagement": "disabled-for-CoreImage",
                "width": prepared.width, "height": prepared.height,
                "bitsPerPixel": prepared.bitsPerPixel, "bytesPerRow": prepared.bytesPerRow,
                "pixelSHA256": sha256(pixels as Data), "pixelHashScope": "CGImage-dataProvider-bytes",
                "seconds": preprocessingSeconds,
            ])
            preparedPNGs.append(try png(prepared, segment: segment, variant: variant))

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            request.customWords = []
            request.minimumTextHeight = Float(10.0 / Double(prepared.height))
            try log(segment, [
                "kind": "requestStart", "variant": variant.rawValue,
                "level": "accurate", "languages": request.recognitionLanguages,
                "languageCorrection": false, "customWords": 0,
                "minimumTextHeight": Double(request.minimumTextHeight),
                "requestRevision": request.revision,
            ])
            let began = ProcessInfo.processInfo.systemUptime
            try VNImageRequestHandler(cgImage: prepared, orientation: .up).perform([request])
            let seconds = ProcessInfo.processInfo.systemUptime - began
            let observations = request.results ?? []
            var candidateCount = 0
            for (index, observation) in observations.enumerated() {
                let box = observation.boundingBox
                let candidates = observation.topCandidates(3)
                try log(segment, [
                    "kind": "observation", "variant": variant.rawValue, "index": index,
                    "box": [Double(box.minX), Double(box.minY), Double(box.width), Double(box.height)],
                    "coordinates": "prepared-crop-normalized-bottom-left", "candidates": candidates.count,
                ])
                for (rank, candidate) in candidates.enumerated() {
                    // Each raw candidate gets its own compact record; no trimming or normalization.
                    try log(segment, [
                        "kind": "candidate", "variant": variant.rawValue, "observation": index,
                        "rank": rank + 1, "raw": candidate.string, "confidence": Double(candidate.confidence),
                    ])
                    candidateCount += 1
                }
            }
            requests += 1
            try log(segment, [
                "kind": "requestEnd", "variant": variant.rawValue, "observations": observations.count,
                "candidates": candidateCount, "seconds": seconds,
            ])
        }
        XCTAssertEqual(requests, 4, "All fixed variants must complete, even when there are no observations")
        try log(segment, ["kind": "segmentEnd", "requests": requests])
        return preparedPNGs
    }

    private static func prepare(_ image: CGImage, variant: Variant, context: CIContext) throws -> CGImage {
        if variant == .original { return image }
        let input = CIImage(cgImage: image, options: [.colorSpace: NSNull()])
        let extent = input.extent
        XCTAssertEqual(extent, CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let channels: CIImage
        if variant.blueOnly {
            // R' = B, G' = B, B' = B, A' = A, with no color-space conversion or extra normalization.
            let blue = CIVector(x: 0, y: 0, z: 1, w: 0)
            channels = input.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": blue, "inputGVector": blue, "inputBVector": blue,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ])
        } else {
            channels = input
        }
        // Clamp before blurring to avoid transparent edge contamination, then restore the exact extent.
        let output = channels.clampedToExtent().applyingGaussianBlur(sigma: variant.sigma).cropped(to: extent)
        XCTAssertEqual(output.extent, extent)
        return try XCTUnwrap(context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: nil))
    }

    private static func png(_ image: CGImage, segment: Segment, variant: Variant) throws -> PreparedPNG {
        let png = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            png as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = "status-segment-\(segment.rawValue)-\(variant.rawValue).png"
        try log(segment, [
            "kind": "preparedPNG", "variant": variant.rawValue, "name": name,
            "pngSHA256": sha256(png as Data), "bytes": png.length,
        ])
        return PreparedPNG(name: name, data: png as Data)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
    }

    private static func log(_ segment: Segment, _ values: [String: Any]) throws {
        var object = values
        object["segment"] = segment.rawValue
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        print("OCRSTATUSPROBE|\(String(decoding: data, as: UTF8.self))")
    }
}
