import XCTest
import Metal
import SceneKit
import simd
@testable import ShiftReminder

@MainActor
final class DuelTriadMetalRendererTests: XCTestCase {
    private func depth(_ projection: simd_float4x4, _ z: Float) -> Float {
        let point = projection * SIMD4<Float>(0, 0, -z, 1); return point.z / point.w
    }
    private func perspective(near: Float = 0.1, far: Float = 100) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, -(far + near) / (far - near), -1), SIMD4(0, 0, -2 * far * near / (far - near), 0)))
    }

    func testOpenGLDepthIsConvertedOnceAndAlreadyMetalDepthRemainsUnchanged() throws {
        let original = perspective()
        let metal = try DuelTriadMetalRenderer.metalProjection(original, near: 0.1, far: 100)
        XCTAssertEqual(depth(metal, 0.1), 0, accuracy: 1e-5)
        XCTAssertEqual(depth(metal, 100), 1, accuracy: 1e-5)
        let repeated = try DuelTriadMetalRenderer.metalProjection(metal, near: 0.1, far: 100)
        for column in 0..<4 { XCTAssertEqual(repeated[column], metal[column]) }
    }

    func testActualCameraProjectionPreservesFieldOfViewAxisAspectAndOrthographicScale() throws {
        let camera = SCNCamera(); camera.zNear = 0.1; camera.zFar = 100
        camera.fieldOfView = 60; camera.automaticallyAdjustsZRange = false
        let viewport = CGSize(width: 320, height: 180)
        for direction in [SCNCameraProjectionDirection.horizontal, .vertical] {
            camera.projectionDirection = direction
            for orthographic in [false, true] {
                camera.usesOrthographicProjection = orthographic; camera.orthographicScale = 3.6
                let original = simd_float4x4(camera.projectionTransform(withViewportSize: viewport))
                let metal = try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: viewport)
                // The native matrix remains authoritative for FOV and scale.
                for column in 0..<4 {
                    XCTAssertEqual(metal[column].x, original[column].x, accuracy: 1e-6)
                    XCTAssertEqual(metal[column].y, original[column].y, accuracy: 1e-6)
                }
                XCTAssertEqual(metal[1].y / metal[0].x, Float(320.0 / 180), accuracy: 1e-4)
                XCTAssertEqual(depth(metal, 0.1), 0, accuracy: 1e-4)
                XCTAssertEqual(depth(metal, 100), 1, accuracy: 1e-4)
                let repeated = try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: viewport)
                for column in 0..<4 { XCTAssertEqual(repeated[column], metal[column]) }
            }
        }
    }

    func testReverseDepthCustomUnknownProjectionAndAutomaticRangeFailClosed() throws {
        var reverse = try DuelTriadMetalRenderer.metalProjection(perspective(), near: 0.1, far: 100)
        for column in 0..<4 { reverse[column].z = reverse[column].w - reverse[column].z }
        XCTAssertThrowsError(try DuelTriadMetalRenderer.metalProjection(reverse, near: 0.1, far: 100))
        XCTAssertThrowsError(try DuelTriadMetalRenderer.metalProjection(matrix_identity_float4x4, near: 0.1, far: 100))
        let camera = SCNCamera(); camera.automaticallyAdjustsZRange = true
        XCTAssertThrowsError(try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: CGSize(width: 320, height: 180)))
        camera.automaticallyAdjustsZRange = false
        XCTAssertThrowsError(try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: .zero))
    }

    func testControlledSurfaceUsesPublicFormatsAndCannotDrawAfterPauseOrShutdown() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Native acceptance requires Metal")
        let originalView = SCNView(frame: CGRect(x: 0, y: 0, width: 32, height: 32), options: [
            .preferredRenderingAPI: SCNRenderingAPI.metal.rawValue])
        originalView.usesReverseZ = false
        let formats = try DuelTriadRenderSurface.formats(device: device)
        let packets = try DuelTriadMetalRenderer(device: device, formats: formats)
        let surface = try DuelTriadRenderSurface(device: device, scene: SCNScene(), pointOfView: nil, packets: packets)
        defer { surface.shutdown(); packets.shutdown() }
        XCTAssertEqual(formats.map(\.samples), [1, DuelTriadRenderSurface.multisampleCount])
        XCTAssertTrue(formats.allSatisfy { $0.color == .bgra8Unorm && $0.depth == .depth32Float_stencil8 && $0.stencil == .depth32Float_stencil8 })
        XCTAssertEqual(surface.colorPixelFormat, .bgra8Unorm)
        XCTAssertEqual(surface.sampleCount, 1); XCTAssertTrue(surface.isPaused)
        XCTAssertFalse(surface.enableSetNeedsDisplay); XCTAssertFalse(surface.sceneRenderer.usesReverseZ)
        XCTAssertNil(surface.sceneRenderer.delegate)
        let data = try JSONSerialization.data(withJSONObject: [
            "device": device.name, "originalSCNViewColorPixelFormat": originalView.colorPixelFormat.rawValue,
            "surfaceDrawableFormat": surface.colorPixelFormat.rawValue,
            "sceneOffscreenFormat": MTLPixelFormat.bgra8Unorm_srgb.rawValue,
            "sourceGammaFormat": MTLPixelFormat.bgra8Unorm.rawValue,
            "depthStencilFormat": MTLPixelFormat.depth32Float_stencil8.rawValue,
            "sampleCounts": formats.map(\.samples), "usesReverseZ": false,
            "presentation": "SceneKit sRGB pass; shared unorm view; original Gamma blend; unorm drawable"], options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "native-scenekit-metal-formats"; attachment.lifetime = .keepAlways; add(attachment)
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        description.storageMode = .shared; description.usage = .renderTarget
        let target = try XCTUnwrap(device.makeTexture(descriptor: description))
        let command = try XCTUnwrap(try XCTUnwrap(device.makeCommandQueue()).makeCommandBuffer())
        surface.setPaused(true)
        XCTAssertThrowsError(try surface.encodeFrame(to: target, atTick: 0, samples: 1, commandBuffer: command))
        XCTAssertNil(surface.lastSubmittedTick); XCTAssertEqual(surface.submittedFrames, 0)
        surface.setPaused(false)
        XCTAssertThrowsError(try surface.encodeFrame(to: target, atTick: -1, samples: 1, commandBuffer: command))
        XCTAssertThrowsError(try surface.encodeFrame(to: target, atTick: 0, samples: 3, commandBuffer: command))
        surface.shutdown()
        XCTAssertThrowsError(try surface.encodeFrame(to: target, atTick: 0, samples: 1, commandBuffer: command))
        XCTAssertThrowsError(try DuelTriadRenderSurface(device: nil, scene: SCNScene(), pointOfView: nil, packets: packets))
    }

    func testSubmissionClearAndShutdownCannotRestartRendering() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Native acceptance requires Metal")
        let format = DuelTriadSourceMaterial.Format(color: .rgba8Unorm, depth: .depth32Float, stencil: .invalid, samples: 1)
        let renderer = try DuelTriadMetalRenderer(device: device, formats: [format])
        try renderer.submit(.init(format: format, draws: [])); renderer.clear()
        XCTAssertEqual(renderer.submittedPacketCount, 0); XCTAssertNil(renderer.lastFailure)
        XCTAssertThrowsError(try renderer.submit(.init(format: .init(color: .bgra8Unorm, depth: .depth32Float, stencil: .invalid, samples: 1), draws: [])))
        renderer.shutdown(); XCTAssertThrowsError(try renderer.submit(.init(format: format, draws: [])))
        XCTAssertThrowsError(try DuelTriadMetalRenderer(device: nil, formats: [format]))
    }
}
