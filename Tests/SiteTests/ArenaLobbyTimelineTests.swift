import Metal
import XCTest
#if ARENA_RESOURCE_RUNTIME_TESTS
@testable import ArenaResourceRuntime
#else
@testable import ShiftReminder
#endif

/// Synthetic source display lists only. These checks exercise the real Metal
/// backend without shipping or depending on any third-party client assets.
@MainActor
final class ArenaLobbyTimelineTests: XCTestCase {
    func testNestedClockAdvancesUnderSingleFrameRoot() throws {
        let child = clip(2, children: [(1,0)], frames: [
            [[0,-1,0]], [[0,-1,2]], [[0,-1,1]]], fps: 3)
        let root = clip(10, children: [(2,0)], frames: [[[0,-1,-1]]])
        let scene = try fixture(objects: [shape(1),child,root])
        XCTAssertEqual(try scene.frame(time: 0).clipFrames[2], 0)
        XCTAssertEqual(try scene.frame(time: 1.0/3).clipFrames[2], 1)
        XCTAssertEqual(try scene.frame(time: 2.0/3).clipFrames[2], 2)
        XCTAssertEqual(try scene.frame(time: 1).clipFrames[2], 0)
        let renderer = try makeRenderer(scene)
        assertPixel(try renderer.snapshot(time: 0, width: 4, height: 4), [255,0,0,255])
        assertPixel(try renderer.snapshot(time: 1.0/3, width: 4, height: 4), [0,255,0,255])
        assertPixel(try renderer.snapshot(time: 2.0/3, width: 4, height: 4), [0,0,255,255])
    }

    func testSoftMaskRetainsPartialAlpha() throws {
        let root = clip(10, children: [(1,0),(38,0),(1,0),(39,0),(1,0),(40,0)],
            frames: [[[0,-1,1],[1,-1,-1],[2,-1,3],[3,-1,-1],[4,-1,0],[5,-1,-1]]])
        let scene = try fixture(objects: [shape(1),modifier(38),modifier(39),modifier(40),root])
        let frame = try scene.frame(time: 0)
        XCTAssertEqual(frame.operations.count, 2)
        guard case .masked = frame.operations[1] else { return XCTFail("Mask directives were flattened away") }
        let image = try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4)
        assertPixel(image, [128,0,127,255])
    }

    func testNestedSoftMasksMultiplyInsteadOfBecomingBinaryStencil() throws {
        let inner = clip(2, children: [(38,0),(1,0),(39,0),(1,0),(40,0)],
            frames: [[[0,-1,-1],[1,-1,3],[2,-1,-1],[3,-1,0],[4,-1,-1]]])
        let root = clip(10, children: [(1,0),(38,0),(1,0),(39,0),(2,0),(40,0)],
            frames: [[[0,-1,1],[1,-1,-1],[2,-1,3],[3,-1,-1],[4,-1,-1],[5,-1,-1]]])
        let scene = try fixture(objects: [shape(1),modifier(38),modifier(39),modifier(40),inner,root])
        assertPixel(try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4), [64,0,191,255])
    }

    func testAdditiveChildCompositesItsOverlappingPartsBeforeAdding() throws {
        let child = clip(2, children: [(1,0),(1,0)], frames: [[[0,-1,5],[1,-1,4]]])
        let root = clip(10, children: [(1,0),(2,8)], frames: [[[0,-1,2],[1,-1,-1]]])
        let scene = try fixture(objects: [shape(1),child,root])
        let renderer = try makeRenderer(scene)
        // Blue then red source-over inside the child gives premultiplied
        // [128,0,64,192]. ADD applies once to the green destination.
        assertPixel(try renderer.snapshot(time: 0, width: 4, height: 4), [128,255,64,255])
        XCTAssertGreaterThan(try XCTUnwrap(renderer.lastStatistics).renderPasses, 1)
    }

    func testScreenUsesSourceColorForDestinationRGBFactor() throws {
        let root = clip(10, children: [(1,0),(1,4)], frames: [[[0,-1,1],[1,-1,4]]])
        let scene = try fixture(objects: [shape(1),root])
        assertPixel(try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4), [128,0,255,255])
    }

    func testTriangleStripSharedEdgeAndConstantUVDoNotDoubleAlpha() throws {
        let root = clip(10, children: [(1,0)], frames: [[[0,-1,4]]])
        let scene = try fixture(objects: [shape(1),root])
        let pixels = try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4)
        for pixel in 0..<16 { assertPixel(pixels, [128,0,0,128], pixel: pixel) }
    }

    func testParentMatrixAndColorComposeInSourceOrder() throws {
        let colors: [[Double]] = [[128,0,0,128,0,0,0],[128,255,255,128,0,64,0]]
        let child = clip(2, children: [(1,0)], frames: [[[0,-1,0]]])
        let root = clip(10, children: [(2,0)], frames: [[[0,0,1]]])
        let scene = try fixture(objects: [shape(1, extent: 2),child,root], colors: colors,
                                matrices: [[1,0,0,1,1,1]])
        let pixels = try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4)
        assertPixel(pixels, [0,0,0,0])
        assertPixel(pixels, [16,16,0,64], pixel: 5)
    }

    func testUnknownBlendAndUnboundHUDRejectPlayback() throws {
        let root = clip(10, children: [(1,64)], frames: [[[0,-1,-1]]])
        XCTAssertThrowsError(try fixture(objects: [shape(1),root]))
        let supported = clip(10, children: [(1,0)], frames: [[[0,-1,-1]]])
        XCTAssertThrowsError(try fixture(objects: [shape(1),supported], status: "requires_layout_text_and_state_bindings"))
    }

    func testExclusionIsReprovedAcrossEveryFrameAndExactViewport() throws {
        let valid = try exclusionFixture(returnsToViewport: false)
        XCTAssertTrue(try valid.frame(time: 0).operations.isEmpty)
        XCTAssertThrowsError(try exclusionFixture(returnsToViewport: true))
        XCTAssertThrowsError(try exclusionFixture(returnsToViewport: false, viewport: [0,0,20,20]))
    }

    func testMalformedMaskAndFrameRunRejectBeforePlayback() throws {
        let maskless = clip(10, children: [(39,0),(1,0),(40,0)], frames: [[[0,-1,-1],[1,-1,0],[2,-1,-1]]])
        XCTAssertThrowsError(try fixture(objects: [shape(1),modifier(39),modifier(40),maskless]))
        var mismatched = clip(10, children: [(1,0)], frames: [[[0,-1,-1]]])
        mismatched["frameCount"] = 2
        XCTAssertThrowsError(try fixture(objects: [shape(1),mismatched]))
    }

    func testClockBoundariesAndAspectFillKeepCorrectCrop() {
        XCTAssertEqual(ArenaLobbyTimelineScene.frameIndex(time: 600.0/60, fps: 60, count: 600), 0)
        XCTAssertEqual(ArenaLobbyTimelineScene.frameIndex(time: 600.0/60, fps: 60, count: 703), 600)
        let rect = ArenaLobbyTimelineRenderer.aspectFillRect(.init([-512,-288,512,288]), width: 100, height: 100)
        XCTAssertEqual(rect.values, [-288,-288,288,288])
    }

    private func makeRenderer(_ scene: ArenaLobbyTimelineScene) throws -> ArenaLobbyTimelineRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal device unavailable in this test environment") }
        return try ArenaLobbyTimelineRenderer(device: device, scene: scene,
            atlases: [.init(width: 1, height: 1, rgba: [255,255,255,255])])
    }

    private func shape(_ id: Int, extent: Double = 4) -> [String: Any] {
        ["id": id, "commands": [["textureIndex": 0, "vertices":
            [[0.0,0,0,0],[extent,0,0,0],[0,extent,0,0],[extent,extent,0,0]]]]]
    }
    private func modifier(_ id: Int) -> [String: Any] { ["id":id,"commands":[],"modifier":id] }
    private func clip(_ id: Int, children: [(Int,Int)], frames: [[[Int]]], fps: Double = 60) -> [String: Any] {
        ["id":id,"commands":[],"fps":fps,"frameCount":frames.count,
         "frameLabels":Array(repeating:"",count:frames.count),
         "children":children.map { ["objectID":$0.0,"blendMode":$0.1,"name":""] as [String:Any] },
         "frames":frames.map { ["repeat":1,"elements":$0] as [String:Any] }]
    }

    private func fixture(objects: [[String: Any]], colors: [[Double]]? = nil,
                         matrices: [[Double]] = [], status: String = "ready",
                         exclusions: [[String:Any]] = [], viewport: [Double]? = nil) throws -> ArenaLobbyTimelineScene {
        let palette = colors ?? [[255,0,0,255,0,0,0],[0,0,255,255,0,0,0],
                                 [0,255,0,255,0,0,0],[255,255,255,128,0,0,0],
                                 [255,0,0,128,0,0,0],[0,0,255,128,0,0,0]]
        let nodes = Dictionary(uniqueKeysWithValues: objects.map { (String($0["id"] as! Int),$0) })
        let value: [String: Any] = ["schemaVersion":1,"sourceSCMember":"synthetic.sc",
            "sourceSCSHA256":String(repeating:"0",count:64),"canvasSize":[4,4],"sourceRect":[0,0,4,4],
            "uvDivisor":65535,"primitiveMode":"triangle_strip","clockPolicy":"independent_absolute_clip_fps",
            "textures":[["file":"fixture.png","width":1,"height":1,"alphaEncoding":"straight",
                         "sha256":String(repeating:"0",count:64)]],
            "objects":nodes,"matrices":matrices,"colors":palette,
            "exports":["fixture":["objectID":10,"status":status]],"exclusions":exclusions]
        let document = try JSONDecoder().decode(ArenaLobbyTimelineDocument.self,
            from: JSONSerialization.data(withJSONObject:value))
        return try ArenaLobbyTimelineScene(document: document, exportName: "fixture", sourceRect: viewport)
    }

    private func exclusionFixture(returnsToViewport: Bool, viewport: [Double]? = nil) throws -> ArenaLobbyTimelineScene {
        let child = clip(2, children: [(1,0)], frames: [[[0,0,-1]],[[0,1,-1]]])
        var root = clip(10, children: [(2,64)], frames: [[[0,-1,-1]]])
        root["children"] = [["objectID":2,"blendMode":64,"name":"","excludedByProof":"outside"]]
        let proof: [String: Any] = ["id":"outside","kind":"complete_timeline_outside_viewport",
            "exportName":"fixture","sourceSCSHA256":String(repeating:"0",count:64),
            "parentObjectID":10,"childIndex":0,"objectID":2,"blendMode":64,
            "sourceRect":[0,0,4,4],"margin":2,"fps":60,"periodFrames":2]
        return try fixture(objects: [shape(1),child,root],
            matrices: [[1,0,0,1,10,0],[1,0,0,1,returnsToViewport ? 0 : 12,0]],
            exclusions: [proof], viewport: viewport)
    }

    private func assertPixel(_ actual: [UInt8], _ expected: [Int], pixel: Int = 0,
                             file: StaticString = #filePath, line: UInt = #line) {
        for component in 0..<4 {
            XCTAssertLessThanOrEqual(abs(Int(actual[pixel*4+component])-expected[component]), 2,
                                    file: file, line: line)
        }
    }
}
