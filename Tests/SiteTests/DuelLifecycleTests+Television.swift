import XCTest
import UIKit
import GameController
@testable import ShiftReminder

#if DEBUG
extension DuelLifecycleTests {
    func testSceneConfigurationLeavesPhoneLifecycleWithSwiftUI() {
        let phone = AppDelegate.sceneConfiguration(for: .windowApplication)
        XCTAssertEqual(phone.role, .windowApplication)
        XCTAssertNil(phone.delegateClass)
        XCTAssertNil(phone.storyboard)
        let television = AppDelegate.sceneConfiguration(for: .windowExternalDisplayNonInteractive)
        XCTAssertEqual(television.role, .windowExternalDisplayNonInteractive)
        XCTAssertTrue(television.delegateClass === DuelTelevisionSceneDelegate.self)
        XCTAssertNil(television.storyboard)
    }

    private func televisionFixture() throws -> (DuelSession, DuelWorldView) {
        let game = DuelGame(hero: .ember, difficulty: .learning, mode: .versus, seed: 93, opponentHero: .liu)
        let session = try DuelSession(presentationFixture: game, localFighterIndex: 0)
        return (session, DuelWorldView(session: session, characterSource: .presentationFixture))
    }
    private func televisionWindow(_ view: UIView, size: CGSize) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false // Deliberately not key.
        view.frame = window.bounds
        controller.view.addSubview(view)
        return window
    }
    func testTelevisionTransferPreservesSceneAndAuthoritativeState() throws {
        let (session, world) = try televisionFixture()
        defer { world.shutdown(); session.shutdown() }
        let source = UIView(), target = UIView()
        let phone = televisionWindow(source, size: .init(width: 844, height: 390))
        let tv = televisionWindow(target, size: .init(width: 1920, height: 1080))
        defer { phone.isHidden = true; tv.isHidden = true }
        source.addSubview(world)
        let scene = world.scene, before = session.game, tick = session.nextPresentationTick
        let clocks = DuelWorldView.activeClocks
        for _ in 0..<10 {
            XCTAssertTrue(world.relocateDisplay(to: target))
            XCTAssertTrue(world.scene === scene)
            XCTAssertEqual(world.bounds.size, target.bounds.size)
            XCTAssertTrue(world.relocateDisplay(to: source))
        }
        XCTAssertEqual(session.game, before)
        XCTAssertEqual(session.nextPresentationTick, tick)
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
    }
    func testTelevisionRejectsUnmountedOrClosedDestinations() throws {
        let (session, world) = try televisionFixture()
        defer { session.shutdown() }
        let target = UIView(frame: .init(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertFalse(world.relocateDisplay(to: target))
        let tv = televisionWindow(target, size: target.bounds.size)
        defer { tv.isHidden = true }
        world.shutdown()
        XCTAssertFalse(world.relocateDisplay(to: target))
        XCTAssertNil(world.superview)
    }
    func testTelevisionDisconnectReturnsExistingRendererToPhone() throws {
        let (session, world) = try televisionFixture()
        let router = DuelTelevisionRouter()
        let host = DuelTelevisionHostView(world: world, session: session, router: router)
        let phone = televisionWindow(host, size: .init(width: 844, height: 390))
        let controller = DuelTelevisionViewController(router: router)
        let tv = UIWindow(frame: .init(x: 0, y: 0, width: 1920, height: 1080))
        tv.rootViewController = controller; tv.isHidden = false
        controller.view.layoutIfNeeded()
        defer { host.shutdown(); session.shutdown(); phone.isHidden = true; tv.isHidden = true }
        router.mount(host); router.connect(controller)
        XCTAssertTrue(world.superview === controller.surface)
        XCTAssertFalse(host.message.isHidden)
        router.disconnect(controller)
        XCTAssertTrue(world.superview === host)
        XCTAssertTrue(host.message.isHidden)
        XCTAssertNotNil(world.scene)
    }
    func testTelevisionStaleDisplayCannotStealOrDisconnectActiveDisplay() throws {
        let (session, world) = try televisionFixture()
        let router = DuelTelevisionRouter()
        let host = DuelTelevisionHostView(world: world, session: session, router: router)
        let phone = televisionWindow(host, size: .init(width: 844, height: 390))
        let active = DuelTelevisionViewController(router: router)
        let tv = UIWindow(frame: .init(x: 0, y: 0, width: 1920, height: 1080))
        tv.rootViewController = active; tv.isHidden = false; active.view.layoutIfNeeded()
        defer { host.shutdown(); session.shutdown(); phone.isHidden = true; tv.isHidden = true }
        router.mount(host); router.connect(active)
        let stale = DuelTelevisionViewController(router: router)
        router.connect(stale); router.disconnect(stale)
        XCTAssertTrue(world.superview === active.surface)
        host.shutdown(); router.route()
        XCTAssertNil(world.scene)
        XCTAssertNil(world.superview)
    }
    func testTelevisionTransferRearmsHeldControllerOnlyAfterNeutral() throws {
        let (session, world) = try televisionFixture()
        let pad = GCController.withExtendedGamepad()
        let buttons = try XCTUnwrap(pad.extendedGamepad)
        let adapter = DuelPeripheralInput(controllers: { [pad] }, keyboard: { nil }, applicationIsActive: { true })
        var accepted: [DuelPhysicalInput.State] = []
        adapter.canAccept = { true }
        adapter.onState = { _, state, cancelled in if !cancelled { accepted.append(state) } }
        adapter.start()
        session.inputReset = { adapter.reset() }
        let source = UIView(), target = UIView()
        let phone = televisionWindow(source, size: .init(width: 844, height: 390))
        let tv = televisionWindow(target, size: .init(width: 1920, height: 1080))
        source.addSubview(world)
        defer { adapter.stop(); world.shutdown(); session.shutdown(); phone.isHidden = true; tv.isHidden = true }
        buttons.buttonX.setValue(1); adapter.refreshReadiness()
        accepted.removeAll()
        XCTAssertTrue(world.relocateDisplay(to: target))
        adapter.refreshReadiness()
        XCTAssertTrue(accepted.isEmpty, "A held button must not become a new attack after screen migration")
        buttons.buttonX.setValue(0); adapter.refreshReadiness()
        buttons.buttonX.setValue(1); adapter.refreshReadiness()
        XCTAssertTrue(accepted.last?.actions.contains(.weapon) == true)
    }

    func testTelevisionRepeatedRoutingDoesNotRepeatedlyCancelPhoneControls() throws {
        let (session, world) = try televisionFixture()
        let source = UIView(), target = UIView()
        let phone = televisionWindow(source, size: .init(width: 844, height: 390))
        let tv = televisionWindow(target, size: .init(width: 1920, height: 1080))
        source.addSubview(world)
        defer { world.shutdown(); session.shutdown(); phone.isHidden = true; tv.isHidden = true }
        var resets = 0
        session.inputReset = { resets += 1 }
        XCTAssertTrue(world.relocateDisplay(to: target))
        XCTAssertEqual(resets, 1)
        for _ in 0..<20 { XCTAssertTrue(world.relocateDisplay(to: target)) }
        XCTAssertEqual(resets, 1, "Layout refreshes on the TV must not cancel ongoing phone input")
        XCTAssertTrue(world.relocateDisplay(to: source))
        XCTAssertEqual(resets, 2)
    }

}
#endif
