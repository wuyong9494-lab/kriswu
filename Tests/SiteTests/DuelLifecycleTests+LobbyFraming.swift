import XCTest
import UIKit
import SceneKit
@testable import ShiftReminder

@MainActor
extension DuelLifecycleTests {
    func testShowroomPerspectiveProjectionClearsRailWithoutCroppingSceneView() throws {
        let lobby = DuelLobbySceneView(hero: .ember)
        defer { lobby.shutdown() }
        for size in [CGSize(width: 956, height: 440), CGSize(width: 844, height: 390),
                     CGSize(width: 1024, height: 768)] {
            lobby.frame = CGRect(origin: .zero, size: size)
            let opening = CGRect(x: 0.3, y: 0, width: 0.4, height: 0.74)
            lobby.setVisibleRegion(opening)
            lobby.layoutSubviews()
            _ = lobby.snapshot() // Resolve SceneKit's viewport, not an assumed projection matrix.
            let fit = try XCTUnwrap(lobby.framing)
            XCTAssertFalse(try XCTUnwrap(lobby.pointOfView?.camera).usesOrthographicProjection)
            XCTAssertEqual(lobby.pointOfView?.camera?.fieldOfView, 35)
            XCTAssertEqual(lobby.bounds.size, size, "The stage must remain full-size behind controls")
            let safe = CGRect(x: opening.minX * size.width + 7.9, y: 7.9,
                              width: opening.width * size.width - 15.8,
                              height: opening.height * size.height - 15.8)
            for point in DuelLobbyFraming.envelope {
                let native = lobby.projectPoint(SCNVector3(Float(point.x), Float(point.y), Float(point.z)))
                let expected = fit.project(point, size: size)
                // This specifically checks SceneKit's native perspective and
                // UIKit Y convention; mathematical self-consistency is not enough.
                XCTAssertEqual(Double(native.x), Double(expected.x), accuracy: 0.1)
                XCTAssertEqual(Double(native.y), Double(expected.y), accuracy: 0.1)
                XCTAssertTrue(safe.contains(CGPoint(x: CGFloat(native.x), y: CGFloat(native.y))))
                XCTAssertGreaterThan(native.z, 0)
                XCTAssertLessThan(native.z, 1)
            }
        }
    }

    func testShowroomLayoutPreservesGestureIntentAndShutdownOwnership() throws {
        let lobby = DuelLobbySceneView(hero: .liu)
        defer { lobby.shutdown() }
        lobby.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        lobby.setVisibleRegion(CGRect(x: 0.3, y: 0, width: 0.4, height: 0.74))
        lobby.rotatePreview(by: 0.4)
        lobby.scalePreview(by: 1.25)
        let yaw = lobby.yaw, zoom = lobby.zoom, count = lobby.showroomFrameCount
        let camera = try XCTUnwrap(lobby.pointOfView)
        let scene = try XCTUnwrap(lobby.scene)
        let childCount = scene.rootNode.childNodes.count
        for _ in 0..<10 {
            lobby.layoutSubviews()
            XCTAssertEqual(lobby.yaw, yaw)
            XCTAssertEqual(lobby.zoom, zoom)
            XCTAssertEqual(lobby.showroomFrameCount, count)
            XCTAssertTrue(lobby.pointOfView === camera)
            XCTAssertTrue(lobby.scene === scene)
            XCTAssertEqual(scene.rootNode.childNodes.count, childCount)
        }
        let validPosition = camera.position
        lobby.frame = .zero
        lobby.layoutSubviews()
        XCTAssertEqual(camera.position.x, validPosition.x)
        XCTAssertEqual(camera.position.y, validPosition.y)
        XCTAssertEqual(camera.position.z, validPosition.z)
        lobby.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        lobby.setVisibleRegion(CGRect(x: 0.31, y: 0, width: 0.38, height: 0.68))
        lobby.layoutSubviews()
        XCTAssertEqual(lobby.zoom, zoom)
        XCTAssertEqual(lobby.yaw, yaw)
        XCTAssertNotNil(lobby.framing)
        // Stacked / largest-text callers have no overlaid side columns or rail.
        lobby.setVisibleRegion(nil)
        XCTAssertNil(lobby.framing)
        XCTAssertEqual(camera.position.z, -0.35 + 5.15 * zoom, accuracy: 0.0001)
        lobby.shutdown()
        XCTAssertNil(lobby.scene)
        XCTAssertNil(lobby.pointOfView)
        XCTAssertNil(lobby.framing)
        lobby.layoutSubviews()
        lobby.setVisibleRegion(CGRect(x: 0.3, y: 0, width: 0.4, height: 0.74))
        XCTAssertNil(lobby.scene, "Late layout must not recreate a closed showroom")
    }
}
