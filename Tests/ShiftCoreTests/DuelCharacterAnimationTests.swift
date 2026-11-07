import XCTest
@testable import ShiftCore

final class DuelCharacterAnimationTests: XCTestCase {
    func testEveryPunchReachesContactAtItsOwnActiveWindow() {
        var fighter = DuelGame(hero: .liu).fighters[0]
        for move in [DuelGame.Move.jab, .cross, .finisher, .heavy, .skill1, .skill2] {
            let data = DuelGame.data(move, hero: .liu)
            var previous: Float = -1
            for age in 0...data.duration {
                fighter.attack = .init(move: move, age: age)
                let selection = DuelCharacterAnimation.sample(fighter, animationTick: age, grapple: nil, index: 0, phase: .fighting)
                XCTAssertGreaterThanOrEqual(selection.progress, previous)
                XCTAssertTrue((0...1).contains(selection.progress))
                if age == data.startup { XCTAssertEqual(selection.progress, Float(7) / 18, accuracy: 0.00001) }
                if age == data.duration { XCTAssertEqual(selection.progress, 1) }
                previous = selection.progress
            }
        }
    }
    func testGrappleUsesRuleStagesAndExactly180HoldSamples() {
        let fighter = DuelGame(hero: .liu).fighters[0]
        var samples = 0
        for age in 0..<DuelGame.Grapple.duration {
            let hold = DuelGame.Grapple(attacker: 0, direction: 1, age: age)
            let pose = DuelCharacterAnimation.sample(fighter, animationTick: age, grapple: hold, index: 0, phase: .fighting)
            switch hold.stage {
            case .takedown: XCTAssertEqual(pose.clip, .grab); XCTAssertEqual(pose.secondary, .sideLock)
            case .hold: XCTAssertEqual(pose.clip, .sideLock); samples += 1
            case .release: XCTAssertEqual(pose.clip, .release)
            }
            XCTAssertEqual(pose.transitionTicks, 0)
            XCTAssertTrue((0...1).contains(pose.progress))
            let defender = DuelCharacterAnimation.sample(fighter, animationTick: age, grapple: hold, index: 1, phase: .fighting)
            XCTAssertEqual(defender.key, "captured")
        }
        XCTAssertEqual(samples, 180)
    }
    func testPoseDependsOnSimulationTickAndResetsWithoutWallClock() {
        var fighter = DuelGame(hero: .liu).fighters[0]
        fighter.walking = true
        let first = DuelCharacterAnimation.sample(fighter, animationTick: 7, grapple: nil, index: 0, phase: .fighting)
        XCTAssertEqual(first, .sample(fighter, animationTick: 7, grapple: nil, index: 0, phase: .fighting))
        XCTAssertEqual(first.progress, Float(7) / 48)
        XCTAssertEqual(DuelCharacterAnimation.sample(fighter, animationTick: 0, grapple: nil, index: 0, phase: .fighting).progress, 0)
        fighter.knockdown = 20; fighter.attack = .init(move: .jab)
        XCTAssertEqual(DuelCharacterAnimation.sample(fighter, animationTick: 0, grapple: nil, index: 0, phase: .fighting).key, "down")
    }
    func testImpactCannotBlendBackToStandingPose() {
        var fighter = DuelGame(hero: .liu).fighters[0]
        for move in [DuelGame.Move.jab, .cross, .finisher, .heavy, .skill1, .skill2, .ultimate] {
            let data = DuelGame.data(move, hero: .liu)
            for age in data.startup..<(data.startup + data.active) {
                fighter.attack = .init(move: move, age: age)
                let pose = DuelCharacterAnimation.sample(fighter, animationTick: 100 + age,
                                                         grapple: nil, index: 0, phase: .fighting)
                XCTAssertEqual(pose.transitionTicks, 0, "Contact must be visible even on the first draw")
            }
        }
    }

    func testConsecutivePunchInstancesHaveDistinctStableKeys() {
        var fighter = DuelGame(hero: .liu).fighters[0]
        for move in [DuelGame.Move.jab, .cross, .finisher] {
            fighter.attack = .init(move: move, age: 1)
            let first = DuelCharacterAnimation.sample(fighter, animationTick: 101, grapple: nil, index: 0, phase: .fighting)
            fighter.attack?.age = 5
            let later = DuelCharacterAnimation.sample(fighter, animationTick: 105, grapple: nil, index: 0, phase: .fighting)
            XCTAssertEqual(first.key, later.key)
            XCTAssertEqual(later, .sample(fighter, animationTick: 105, grapple: nil, index: 0, phase: .fighting))
            fighter.attack?.age = 1
            let repeated = DuelCharacterAnimation.sample(fighter, animationTick: 201, grapple: nil, index: 0, phase: .fighting)
            XCTAssertNotEqual(first.key, repeated.key)
            XCTAssertEqual(first.progress, repeated.progress)
        }
    }

    func testHitStartsAtAuthoredImpactAndBlockStunKeepsGuard() {
        var fighter = DuelGame(hero: .liu).fighters[0]
        var previous: Float = 0
        for stun in stride(from: 17, through: 1, by: -1) {
            fighter.stun = stun
            let pose = DuelCharacterAnimation.sample(fighter, animationTick: 42, grapple: nil, index: 0, phase: .fighting)
            XCTAssertEqual(pose.clip, .hit)
            XCTAssertEqual(pose.transitionTicks, 0)
            if stun == 17 { XCTAssertEqual(pose.progress, 0.25) }
            XCTAssertGreaterThanOrEqual(pose.progress, previous)
            XCTAssertLessThan(pose.progress, 1)
            previous = pose.progress
        }
        fighter.guarding = true; fighter.stun = 10
        let blocked = DuelCharacterAnimation.sample(fighter, animationTick: 42, grapple: nil, index: 0, phase: .fighting)
        XCTAssertEqual(blocked.clip, .guardPose)
        XCTAssertEqual(blocked.transitionTicks, 0)
    }

}
