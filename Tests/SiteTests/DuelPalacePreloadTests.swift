import CryptoKit
import SceneKit
import UIKit
import XCTest
@testable import ShiftReminder

final class DuelPalacePreloadTests: XCTestCase {
    @MainActor
    func testExactPalacePreparedAndSynchronousMountHaveSameStageAndTextureReadback() async throws {
        let url = try XCTUnwrap(DuelStageAsset.bundledURL,
                                "The exact Palace GLB must be included in this qualification fixture")
        let start = ProcessInfo.processInfo.systemUptime
        let prepared = try await DuelStageAsset.preparePalace(url: url)
        let prepMs = elapsed(since: start)
        XCTAssertGreaterThan(prepared.opaqueTextureCount, 0, "The preload must actually decode opaque textures")
        XCTAssertGreaterThan(prepared.decodedPixelBytes, 0)
        XCTAssertLessThanOrEqual(prepared.decodedPixelBytes, DuelStageAsset.palaceOpaquePixelBudget)
        let oldStart = ProcessInfo.processInfo.systemUptime
        let old = try DuelStageAsset(url: url).makeRoot()
        let synchronousMs = elapsed(since: oldStart)
        let preparedStart = ProcessInfo.processInfo.systemUptime
        let staged = try DuelStageAsset(preparedPalace: prepared).makeRoot()
        let preparedMountMs = elapsed(since: preparedStart)
        XCTAssertEqual(old.name, "duel.stage.palace")
        XCTAssertEqual(staged.name, old.name)
        XCTAssertNotNil(staged.childNode(withName: "palace_exterior_raid", recursively: true))
        XCTAssertNotNil(staged.childNode(withName: "SF3_Stage_Meters", recursively: true))
        let baseline = readback(old)
        XCTAssertGreaterThan(baseline.textureCount, 0)
        XCTAssertEqual(readback(staged), baseline)
        // Same-process diagnostic only, not a cold-start benchmark or FPS proof.
        print("RIFT_PALACE_PRELOAD prepareMs=\(prepMs) synchronousMountMs=\(synchronousMs) preparedMountMs=\(preparedMountMs) opaqueTextures=\(prepared.opaqueTextureCount) opaqueBytes=\(prepared.decodedPixelBytes)")
    }

    @MainActor
    func testSameSizeUnverifiedGLBDoesNotCreatePreparedPalace() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".glb")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(count: 9_292_540).write(to: file)
        do {
            _ = try await DuelStageAsset.preparePalace(url: file)
            XCTFail("Size alone must not authorize a stage")
        } catch DuelStageAsset.AssetError.integrity {
            // Same legacy integrity failure, before material or SceneKit work.
        }
        let fallback = await DuelStageAsset.prepareOptionalPalace(url: file)
        XCTAssertNil(fallback)
        XCTAssertThrowsError(try DuelStageAsset(url: file))
    }

    @MainActor
    func testCancelledStagePreparationDoesNotPublishBytes() async throws {
        let url = try XCTUnwrap(DuelStageAsset.bundledURL)
        let task = Task { try await DuelStageAsset.preparePalace(url: url) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled preparation must not return unused stage data")
        } catch is CancellationError {
            // Cancellation is not reported as a failed asset or procedural fallback.
        }
    }

    private func elapsed(since start: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
    }

    private struct Readback: Equatable {
        let nodes: [String]
        let textureCount: Int
    }

    @MainActor
    private func readback(_ root: SCNNode) -> Readback {
        var nodes: [String] = []
        // Instantiated materials may be shared across geometry holders. Hash
        // each occurrence identity once, but compare its value at every holder.
        var images: [ObjectIdentifier: String] = [:]
        func texture(_ value: Any?) -> String {
            guard let image = value as? UIImage, let cg = image.cgImage,
                  let bytes = cg.dataProvider?.data else { return "none" }
            let id = ObjectIdentifier(image)
            if let existing = images[id] { return existing }
            let hex = SHA256.hash(data: bytes as Data).map { String(format: "%02x", $0) }.joined()
            let fingerprint = "\(cg.width):\(cg.height):\(cg.bytesPerRow):\(hex)"
            images[id] = fingerprint
            return fingerprint
        }
        root.enumerateChildNodes { node, _ in
            let materials = (node.geometry?.materials ?? []).map { material in
                let diffuse = material.diffuse, multiply = material.multiply
                return "\(material.name ?? "")/\(material.isDoubleSided)/\(material.cullMode.rawValue)/\(diffuse.mipFilter.rawValue)/\(multiply.mipFilter.rawValue)/\(texture(diffuse.contents))/\(texture(multiply.contents))"
            }.joined(separator: ";")
            nodes.append("\(node.name ?? "")|\(node.geometry?.elementCount ?? 0)|\(node.castsShadow)|\(materials)")
        }
        // Texture identity count is distinct payloads by value, not allocation count.
        return Readback(nodes: nodes, textureCount: Set(images.values).count)
    }
}
