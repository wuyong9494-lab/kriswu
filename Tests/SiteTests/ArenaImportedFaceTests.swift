import XCTest
import UIKit
#if ARENA_RESOURCE_RUNTIME_TESTS
@testable import ArenaResourceRuntime
#else
@testable import ShiftReminder
#endif

/// Synthetic display lists only. No packaged third-party assets or gameplay.
@MainActor
final class ArenaImportedFaceTests: XCTestCase {
    func testIndependentNestedClocksDoNotFreezeAtSingleFrameParent() throws {
        let scene = try fixture(childFPS: 3, frames: [0, 1, 2])
        let red = try scene.render(root: 3, time: 0)[0]
        let green = try scene.render(root: 3, time: 1.0 / 3.0)[0]
        let blue = try scene.render(root: 3, time: 2.0 / 3.0)[0]
        assertPixel(red, equals: SIMD4(1, 0, 0, 1))
        assertPixel(green, equals: SIMD4(0, 1, 0, 1))
        assertPixel(blue, equals: SIMD4(0, 0, 1, 1))
        assertPixel(try scene.render(root: 3, time: 1)[0], equals: red)
        XCTAssertNotEqual(try scene.signature(root: 3, time: 0), try scene.signature(root: 3, time: 1.0 / 3.0))
    }

    func testParentMatricesAndColorTransformsComposeInSourceOrder() throws {
        let source: [[Double]] = [[128, 0, 0, 128, 0, 0, 0], [128, 255, 255, 128, 0, 64, 0]]
        let scene = try fixture(childFPS: 1, frames: [0], colors: source,
                                parentColor: 1, parentMatrix: [1, 0, 0, 1, 3, 4])
        let pixels = try scene.render(root: 3, time: 0)
        assertPixel(pixels[0], equals: .zero)
        let a: Float = 128.0 / 255.0
        assertPixel(pixels[4 * 512 + 3], equals: SIMD4(a * a * a * a, (64.0 / 255.0) * a * a, 0, a * a))
    }

    func testTriangleStripSharedEdgeDoesNotBlendAlphaTwiceAndConstantUVWorks() throws {
        let scene = try fixture(childFPS: 1, frames: [-1], atlas: [128, 0, 0, 128])
        let image = try scene.render(root: 3, time: 0)
        let a: Float = 128.0 / 255.0
        for p in [0, 1, 512, 513] { assertPixel(image[p], equals: SIMD4(a, 0, 0, a)) }
        assertPixel(image[2], equals: .zero)
    }

    func testFrameRunCountsAndUnknownBlendFailClosed() throws {
        let unknown = try fixture(childFPS: 1, frames: [0], blend: 99)
        XCTAssertThrowsError(try unknown.validate(root: 3))
        XCTAssertThrowsError(try unknown.render(root: 3, time: 0))
        XCTAssertThrowsError(try ArenaFaceScene.blend(source: .zero, destination: .zero, mode: 99))
        let invalidRuns = try fixture(childFPS: 1, frames: [0], declaredFrames: 2)
        XCTAssertThrowsError(try invalidRuns.validate(root: 3))
    }

    func testPremultipliedNormalAddAndScreenUseDeclaredBlendFactors() throws {
        let source = SIMD4<Float>(0.2, 0.1, 0, 0.4)
        let destination = SIMD4<Float>(0.1, 0.3, 0.2, 0.5)
        assertPixel(try ArenaFaceScene.blend(source: source, destination: destination, mode: 0),
                    equals: SIMD4(0.26, 0.28, 0.12, 0.7))
        assertPixel(try ArenaFaceScene.blend(source: source, destination: destination, mode: 8),
                    equals: SIMD4(0.3, 0.4, 0.2, 0.9))
        assertPixel(try ArenaFaceScene.blend(source: source, destination: destination, mode: 4),
                    equals: SIMD4(0.28, 0.37, 0.2, 0.7))
    }

    func testRGBAImageRoundTripRetainsTopAndBottomRows() throws {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                              0, 0, 255, 255, 128, 0, 128, 128]
        let input = ArenaFacePixels(width: 2, height: 2, rgba: bytes)
        let png = try XCTUnwrap(try input.image().pngData())
        let result = try ArenaFacePixels(data: png)
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
        for (a, b) in zip(result.rgba, bytes) { XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), 1) }
    }

    func testClockWrapsEachClipWithoutComputingCommonPeriod() {
        XCTAssertEqual(ArenaFaceScene.frame(time: 140.0 / 30.0, fps: 30, count: 140), 0)
        XCTAssertEqual(ArenaFaceScene.frame(time: 140.0 / 30.0, fps: 30, count: 183), 140)
        XCTAssertEqual(ArenaFaceScene.frame(time: 4_216_820.0 / 30.0, fps: 30, count: 445), 0)
    }

    func testPremultipliedAtlasCannotBeMisreadAsStraightPNG() {
        XCTAssertThrowsError(try fixture(childFPS: 1, frames: [0], alphaEncoding: "premultiplied"))
    }

    private func fixture(childFPS: Double, frames: [Int], colors: [[Double]]? = nil,
                         parentColor: Int = -1, parentMatrix: [Double] = [1, 0, 0, 1, 0, 0],
                         atlas: [UInt8] = [255, 255, 255, 255], blend: Int = 0,
                         declaredFrames: Int? = nil, alphaEncoding: String = "straight") throws -> ArenaFaceScene {
        let rgbaColors: [[Double]] = colors ?? [[255, 0, 0, 255, 0, 0, 0],
                                               [0, 255, 0, 255, 0, 0, 0],
                                               [0, 0, 255, 255, 0, 0, 0]]
        let shape: [String: Any] = ["id": 1, "commands": [["textureIndex": 0,
            "vertices": [[0.0, 0, 0, 0], [2.0, 0, 0, 0], [0.0, 2, 0, 0], [2.0, 2, 0, 0]]]]]
        let child: [String: Any] = ["id": 2, "commands": [], "fps": childFPS,
            "frameCount": declaredFrames ?? frames.count, "children": [["objectID": 1, "blendMode": blend]],
            "frames": frames.map { ["repeat": 1, "elements": [[0, -1, $0]]] as [String: Any] }]
        let root: [String: Any] = ["id": 3, "commands": [], "fps": 1, "frameCount": 1,
            "children": [["objectID": 2, "blendMode": 0]],
            "frames": [["repeat": 1, "elements": [[0, 0, parentColor]]]]]
        let value: [String: Any] = ["schemaVersion": 1, "canvasSize": [512, 512],
            "projection": [1.0, 0, 0, 1, 0, 0], "uvDivisor": 65535, "primitiveMode": "triangle_strip",
            "textures": [["file": "fixture.png", "width": 1, "height": 1, "alphaEncoding": alphaEncoding]],
            "objects": ["1": shape, "2": child, "3": root], "matrices": [parentMatrix],
            "colors": rgbaColors, "exports": ["fixture": ["objectID": 3, "status": "ready"]]]
        let data = try JSONSerialization.data(withJSONObject: value)
        return try ArenaFaceScene(JSONDecoder().decode(ArenaFaceScene.Document.self, from: data)) { _ in
            ArenaFacePixels(width: 1, height: 1, rgba: atlas)
        }
    }

    private func assertPixel(_ actual: SIMD4<Float>, equals expected: SIMD4<Float>, file: StaticString = #filePath, line: UInt = #line) {
        for i in 0..<4 { XCTAssertEqual(actual[i], expected[i], accuracy: 0.0001, file: file, line: line) }
    }
}
