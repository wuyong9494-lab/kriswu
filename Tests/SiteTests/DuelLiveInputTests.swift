import XCTest
import UIKit
@testable import ShiftReminder

@MainActor
final class DuelLiveInputTests: XCTestCase {
    func testFreshWeaponTapStartsOnFirstPlayableFrameAgainstSun() throws {
        for hero in [DuelGame.Hero.liu, .wuYong] {
            let session = DuelSession(.init(hero: hero, difficulty: .learning, mode: .practice,
                                            originalWeapons: true, opponentHero: .ember))
            let controls = DuelSourceControlsView(images: [:])
            defer { controls.shutdown(); session.shutdown() }
            XCTAssertNil(session.loadError)
            XCTAssertEqual(session.game.weaponFight?.profiles[1].id, "sun_triad")
            controls.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
            controls.setNeedsLayout()
            controls.layoutIfNeeded()
            let binding = DuelWeaponControls(session: session)
            XCTAssertTrue(binding.bind(controls))
            binding.updateReadiness(controls)
            let button = try XCTUnwrap(controls.layoutSnapshot.actions[.weapon])
            func hitIdentifier(_ frame: CGRect, at fraction: CGFloat) -> String? {
                let point = CGPoint(x: frame.minX + fraction * frame.width, y: frame.midY)
                return controls.hitTest(point, with: nil)?.accessibilityIdentifier
            }
            XCTAssertEqual(hitIdentifier(button, at: 0.5), "duel.control.weapon")
            let stick = controls.layoutSnapshot.joystick
            XCTAssertEqual(hitIdentifier(stick, at: 0.14), "duel.control.joystick")
            XCTAssertEqual(hitIdentifier(stick, at: 0.86), "duel.control.joystick")
            func tapWeapon() {
                controls.beginPointers([.init(id: "finger", location: CGPoint(x: button.midX, y: button.midY))])
                controls.endPointers(["finger"])
            }
            tapWeapon()
            session.advance()
            XCTAssertNil(session.localFighter.attack, "An entrance tap cannot start or queue a move")
            for _ in 0..<392 { session.advance() }
            XCTAssertEqual(session.game.weaponFight?.sourceStance(1)?.motion, .startIdle)
            XCTAssertNil(session.localFighter.attack)
            tapWeapon()
            session.advance()
            let clip = try XCTUnwrap(session.game.weaponFight?.profiles[0].clip(command: .weapon))
            XCTAssertNotNil(session.localFighter.attack, "The first fresh tap after Sun's entrance must start this fighter's weapon")
            XCTAssertEqual(session.localFighter.weaponPose?.clip, clip.name)
        }
    }
}
