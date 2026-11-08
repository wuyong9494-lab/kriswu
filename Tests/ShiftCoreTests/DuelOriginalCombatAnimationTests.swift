import XCTest
@testable import ShiftCore

final class DuelOriginalCombatAnimationTests: XCTestCase {
    func testAllCombatWindowsStayInsideSourceClipsAndMeetRuleBoundaries() {
        for move in [DuelGame.Move.jab, .cross, .finisher, .heavy, .skill1, .skill2, .ultimate] {
            let window = DuelOriginalCombatAnimation.window(move)
            let timing = DuelGame.data(move, hero: .liu)
            XCTAssertGreaterThanOrEqual(window.first, 0)
            XCTAssertLessThan(window.first, window.contact)
            XCTAssertLessThanOrEqual(window.contact, window.recovery)
            XCTAssertLessThanOrEqual(window.recovery, window.last)
            XCTAssertLessThan(window.last, window.clip.frameCount)
            XCTAssertEqual(window.frame(age: timing.startup, timing: timing), Double(window.contact))
            XCTAssertEqual(window.frame(age: timing.startup + timing.active, timing: timing), Double(window.recovery))
            XCTAssertEqual(window.frame(age: timing.duration, timing: timing), Double(window.last))
            var previous = Double(window.first)
            for age in 0...timing.duration {
                let frame = window.frame(age: age, timing: timing)
                XCTAssertGreaterThanOrEqual(frame, previous)
                XCTAssertLessThanOrEqual(frame, Double(window.last)); previous = frame
            }
        }
        // A combo continuation must not show the opening punch a second time.
        XCTAssertGreaterThan(DuelOriginalCombatAnimation.window(.cross).first,
                             DuelOriginalCombatAnimation.window(.jab).contact)
        XCTAssertGreaterThan(DuelOriginalCombatAnimation.window(.finisher).first,
                             DuelOriginalCombatAnimation.window(.cross).contact)
    }

    func testContactsIgnorePreviousPosesAndConsecutiveAttacksHaveDistinctKeys() {
        var fighter = DuelGame(hero: .liu).fighters[0]
        for move in [DuelGame.Move.jab, .cross, .finisher, .heavy, .skill1, .skill2] {
            let timing = DuelGame.data(move, hero: .liu)
            fighter.attack = .init(move: move, age: timing.startup)
            let sample = DuelOriginalCombatAnimation.sample(fighter, animationTick: 100, grapple: nil, index: 0, phase: .fighting)
            XCTAssertEqual(sample.transitionTicks, 0)
            XCTAssertNil(sample.secondary)
            XCTAssertNotEqual(sample.key, DuelOriginalCombatAnimation.sample(fighter, animationTick: 200, grapple: nil, index: 0, phase: .fighting).key)
            fighter.attack?.age += 1
            XCTAssertEqual(sample.key, DuelOriginalCombatAnimation.sample(fighter, animationTick: 101, grapple: nil, index: 0, phase: .fighting).key)
        }
    }

    func testMovementDirectionSelectsForwardOrBackStepAndClearsOnStop() {
        var game = DuelGame(hero: .liu, mode: .practice)
        game.step(.init(move: -1))
        var f = game.fighters[0]
        XCTAssertEqual(f.movementDirection, -1)
        XCTAssertEqual(DuelOriginalCombatAnimation.sample(f, animationTick: 1, grapple: nil, index: 0, phase: .fighting).selection.clip, .backStep)
        game.step(.neutral); XCTAssertEqual(game.fighters[0].movementDirection, 0)
        var raw = DuelGame.Input(); raw.move = Int.min
        game.step(raw); XCTAssertEqual(game.fighters[0].movementDirection, -1)
        f.facing = -1
        XCTAssertEqual(DuelOriginalCombatAnimation.sample(f, animationTick: 1, grapple: nil, index: 0, phase: .fighting).selection.clip, .walk)
    }

    func testExistingHoldHasStableSourcePosesAndDoesNotChangeRuleDamage() {
        var game = DuelGame(hero: .liu, mode: .practice)
        for _ in 0..<42 { game.step(.init(move: 1)) }
        game.step(.init(taps: .ultimate))
        for _ in 0..<35 { if game.grapple == nil { game.step(.neutral) } }
        XCTAssertNotNil(game.grapple)
        var held: DuelOriginalCombatAnimation?
        while let hold = game.grapple {
            let pose = DuelOriginalCombatAnimation.sample(game.fighters[0], animationTick: game.frame, grapple: hold, index: 0, phase: game.phase)
            if hold.stage == .hold {
                if let held { XCTAssertEqual(pose, held) } else { held = pose }
            }
            game.step(.neutral)
        }
        XCTAssertNotNil(held)
        XCTAssertEqual(game.damageDealt[0], 280)
    }

    func testJumpAdvancesContinuouslyWithPhysicsAndReturnsToIdle() {
        var game = DuelGame(hero: .liu, mode: .practice)
        game.step(.init(taps: .jump))
        var phases: [Double] = []
        for _ in 0..<40 {
            let f = game.fighters[0]
            let sample = DuelOriginalCombatAnimation.sample(f, animationTick: game.frame, grapple: nil, index: 0, phase: game.phase)
            if f.y > 0 || f.velocityY > 0 {
                XCTAssertEqual(sample.selection.clip, .jump)
                phases.append(sample.selection.phase)
            }
            game.step(.neutral)
        }
        XCTAssertGreaterThan(Set(phases).count, 20)
        XCTAssertEqual(phases, phases.sorted())
        XCTAssertEqual(game.fighters[0].y, 0)
        XCTAssertEqual(DuelOriginalCombatAnimation.sample(game.fighters[0], animationTick: game.frame,
            grapple: nil, index: 0, phase: game.phase).selection.clip, .idle)
    }
}
