import XCTest
import UIKit
import SceneKit
@testable import ShiftReminder

// Extend the existing suite so both ordinary and actual-resource CI jobs run
// these checks through their existing -only-testing:SiteTests/DuelLifecycleTests.
@MainActor
extension DuelLifecycleTests {
    @objc func testShowroomPanDelegateUsesUIViewOverrideAndPreservesVerticalScrolling() throws {
        let lobby = DuelLobbySceneView(hero: .ember)
        defer { lobby.shutdown() }
        lobby.frame = CGRect(x: 0, y: 0, width: 400, height: 280)
        let pan = try XCTUnwrap(lobby.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first(where: { $0.delegate === lobby }))
        let delegate = try XCTUnwrap(pan.delegate)
        XCTAssertTrue((delegate as AnyObject) === lobby)
        XCTAssertEqual(pan.maximumNumberOfTouches, 1)

        // UIKit does not synthesize active touches when setTranslation is
        // called on an idle recognizer. Its translation(in:) remains zero,
        // so asserting delegate acceptance here produces false negatives.
        // Validate the direction policy directly and keep registration,
        // delegate ownership and vertical-scroll integration explicit.
        let view: UIView = lobby
        XCTAssertTrue(view.gestureRecognizerShouldBegin(pan) == false,
                      "An inactive pan without touches must not steal scrolling")
        for (movement, accepted) in [
            (CGPoint(x: 24, y: 2), true),
            (CGPoint(x: -24, y: 2), true),
            (CGPoint(x: 2, y: 24), false),
            (CGPoint(x: 2, y: -24), false),
            (CGPoint(x: 12, y: 12), false),
            (CGPoint(x: 0.5, y: 0), false),
            (CGPoint.zero, false)
        ] {
            XCTAssertEqual(DuelLobbySceneView.acceptsHorizontalPan(movement), accepted)
        }
    }

    @objc func testShowroomPinchStillBeginsAndShutdownRemovesGestureBindings() throws {
        let lobby = DuelLobbySceneView(hero: .liu)
        defer { lobby.shutdown() }
        let pinch = try XCTUnwrap(lobby.gestureRecognizers?.compactMap { $0 as? UIPinchGestureRecognizer }.first(where: { $0.delegate === lobby }))
        let delegate = try XCTUnwrap(pinch.delegate)
        XCTAssertTrue((delegate as AnyObject) === lobby)
        XCTAssertEqual(delegate.gestureRecognizerShouldBegin?(pinch), Optional(true),
                       "The directional pan gate must not disable two-finger zoom")
        let view: UIView = lobby
        XCTAssertTrue(view.gestureRecognizerShouldBegin(pinch))

        lobby.shutdown()
        XCTAssertNil(pinch.view, "Shutdown must detach the registered pinch recognizer")
        XCTAssertTrue(lobby.gestureRecognizers?.isEmpty ?? true)
        XCTAssertNil(lobby.scene)
        XCTAssertNil(lobby.pointOfView)
        let renderedFrames = lobby.showroomFrameCount
        lobby.renderIdle(at: 1)
        XCTAssertEqual(lobby.showroomFrameCount, renderedFrames,
                       "A closed showroom must not sample or render another idle frame")
    }
}
