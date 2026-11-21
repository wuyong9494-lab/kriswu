import XCTest
@testable import ShiftCore

/// Synthetic collision and response values exercise the actual soul-contact
/// route. These are interpreter regressions, not original balance/visual data.
final class DuelTriadStunImpactTests: XCTestCase {
    private typealias F = DuelTriadFightFixture

    private func rules(launch: Int) -> DuelTriadRules {
        var rules = F.rules(level: 2)
        let soul = rules.abilities.firstIndex { $0.ability == .legionary }!
        rules.abilities[soul].startupTicks = 2
        rules.abilities[soul].attack!.impact = .init(distanceMillimeters: 60, durationTicks: 6,
            launchVelocityMillimetersPerTick: launch, gravityMillimetersPerTickSquared: 10)
        rules.abilities[soul].attack!.stunTicks = 8
        rules.abilities[soul].attack!.hitStopTicks = 2
        rules.branches.holdTicks = 45
        rules.branches.entangledHoldReductionTicks = 0
        return rules
    }

    private func fight(launch: Int, swapped: Bool, panguTarget: Bool = false,
                       mode: DuelGame.Mode = .practice, targetHealth: Int = 1000) throws -> DuelWeaponFight {
        let catalog = try F.catalog(rules: rules(launch: launch),
            pangu: panguTarget ? DuelPanguTestFixture.rules(level: 2) : nil)
        let sun = DuelGame.Fighter(hero: .ember, x: swapped ? 5300 : 3500, facing: swapped ? -1 : 1)
        var liu = DuelGame.Fighter(hero: .liu, x: swapped ? 3500 : 5300, facing: swapped ? 1 : -1)
        liu.health = targetHealth
        return try XCTUnwrap(DuelWeaponFight(fighters: swapped ? [liu, sun] : [sun, liu],
            mode: mode, difficulty: .learning, catalog: catalog, seed: 53))
    }

    private func step(_ fight: inout DuelWeaponFight, owner: Int,
                      caster: DuelGame.Input = .neutral, target: DuelGame.Input = .neutral) {
        fight.step(owner == 0 ? caster : target, opponent: owner == 0 ? target : caster)
    }

    private func reachSoulContact(_ fight: inout DuelWeaponFight, owner: Int, jumping: Bool = false) throws {
        step(&fight, owner: owner, caster: .init(vertical: -1, weaponCommand: .shadow),
             target: jumping ? .init(taps: .jump) : .neutral)
        XCTAssertTrue(F.until(&fight, limit: 20) { $0.landedHits[owner] == 1 })
        XCTAssertTrue(fight.triadPresentation.controls.contains { $0.target == 1 - owner && $0.kind == .stun })
        XCTAssertGreaterThan(fight.hitStop, 0)
    }

    private func consumeHitStop(_ fight: inout DuelWeaponFight) {
        let bodies = fight.fighters
        let liveTick = fight.triadPresentation.liveTick
        let controls = fight.triadPresentation.controls
        for _ in 0..<fight.hitStop {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertEqual(fight.fighters, bodies)
            XCTAssertEqual(fight.triadPresentation.liveTick, liveTick)
            XCTAssertEqual(fight.triadPresentation.controls, controls)
        }
    }

    func testSoulLaunchKeepsVerticalVelocityDuringStunForBothPlayerSlotsAndTargetProfiles() throws {
        for swapped in [false, true] {
            for panguTarget in [false, true] {
                let owner = swapped ? 1 : 0, target = 1 - owner
                var fight = try fight(launch: 90, swapped: swapped, panguTarget: panguTarget)
                try reachSoulContact(&fight, owner: owner)
                XCTAssertEqual(fight.fighters[target].y, 0, "Contact schedules the launch before hit-stop")
                XCTAssertEqual(fight.fighters[target].velocityY, 90)
                XCTAssertEqual(fight.profiles[target].isPangu, panguTarget)
                consumeHitStop(&fight)
                let casterX = fight.fighters[owner].x
                for (height, velocity) in [(90, 80), (170, 70), (240, 60)] {
                    step(&fight, owner: owner, target: .init(move: 1, guardHeld: true, taps: .jump, weaponCommand: .weapon))
                    XCTAssertEqual(fight.fighters[target].y, height)
                    XCTAssertEqual(fight.fighters[target].velocityY, velocity,
                        "A stun consumes inputs; it must not cancel an existing launch or gravity")
                    XCTAssertFalse(fight.fighters[target].guarding)
                    XCTAssertNil(fight.fighters[target].attack)
                    XCTAssertEqual(fight.fighters[owner].x, casterX)
                    XCTAssertEqual(fight.fighters[owner].y, 0)
                    XCTAssertEqual(fight.fighters[owner].velocityY, 0)
                }
                XCTAssertEqual(fight.landedHits[owner], 1)
            }
        }
    }

    func testZeroLaunchSoulHitLetsAnAlreadyAirborneVictimFallDuringStun() throws {
        for swapped in [false, true] {
            let owner = swapped ? 1 : 0, target = 1 - owner
            var fight = try fight(launch: 0, swapped: swapped)
            try reachSoulContact(&fight, owner: owner, jumping: true)
            let height = fight.fighters[target].y
            XCTAssertGreaterThan(height, 30, "The soul must hit the source jump above the floor")
            XCTAssertEqual(fight.fighters[target].velocityY, 0)
            consumeHitStop(&fight)
            for (drop, velocity) in [(0, -10), (10, -20), (30, -30)] {
                fight.step(.neutral, opponent: .neutral)
                XCTAssertEqual(fight.fighters[target].y, height - drop)
                XCTAssertEqual(fight.fighters[target].velocityY, velocity)
                XCTAssertTrue(fight.triadPresentation.controls.contains { $0.target == target && $0.kind == .stun })
            }
        }
    }

    func testRootStillCancelsMotionWhenAStunningSoulHitsTheBoundVictim() throws {
        for swapped in [false, true] {
            let owner = swapped ? 1 : 0, target = 1 - owner
            var fight = try fight(launch: 90, swapped: swapped)
            step(&fight, owner: owner, caster: .init(weaponCommand: .shadow))
            XCTAssertTrue(F.until(&fight, limit: 40) {
                $0.triadPresentation.controls.contains { $0.target == target && $0.kind == .root }
            })
            let position = fight.fighters[target].x
            try reachSoulContact(&fight, owner: owner)
            consumeHitStop(&fight)
            for _ in 0..<5 {
                step(&fight, owner: owner, target: .init(move: 1, taps: .jump))
                XCTAssertTrue(fight.triadPresentation.controls.contains { $0.target == target && $0.kind == .root })
                XCTAssertEqual(fight.fighters[target].x, position)
                XCTAssertEqual(fight.fighters[target].y, 0)
                XCTAssertEqual(fight.fighters[target].velocityY, 0)
            }
        }
    }

    func testLethalStunningSoulContactClearsMotionAndControlsBeforeNextRound() throws {
        for swapped in [false, true] {
            let owner = swapped ? 1 : 0, target = 1 - owner
            var fight = try fight(launch: 90, swapped: swapped, mode: .versus, targetHealth: 1)
            step(&fight, owner: owner, caster: .init(vertical: -1, weaponCommand: .shadow))
            XCTAssertTrue(F.until(&fight, limit: 20) { $0.phase != .fighting })
            XCTAssertEqual(fight.wins[owner], 1)
            XCTAssertEqual(fight.fighters[target].y, 0)
            XCTAssertEqual(fight.fighters[target].velocityY, 0)
            XCTAssertTrue(fight.triadPresentation.controls.isEmpty)
            XCTAssertTrue(F.until(&fight, limit: 160) { $0.roundNumber == 2 })
            XCTAssertEqual(fight.fighters[target].stun, 0)
            XCTAssertEqual(fight.fighters[target].velocityY, 0)
            XCTAssertTrue(fight.triadPresentation.controls.isEmpty)
            step(&fight, owner: owner, target: .init(taps: .jump))
            XCTAssertEqual(fight.fighters[target].weaponPose?.clip, fight.profiles[target].roles["jump"])
        }
    }

    func testStunPhysicsUsesCurrentReplaySchemaAndRules() throws {
        var fight = try fight(launch: 90, swapped: false)
        try reachSoulContact(&fight, owner: 0)
        XCTAssertEqual(fight.fighters[1].velocityY, 90)
        let bytes = try DuelReplayStateEncoding.encode(fight)
        guard bytes.count >= 13 else { return XCTFail("Missing weapon-fight replay header") }
        XCTAssertEqual(Array(bytes.prefix(8)), Array("DUELSTAT".utf8))
        XCTAssertEqual(UInt16(bytes[8]) | (UInt16(bytes[9]) << 8), DuelReplayStateEncoding.schemaVersion)
        XCTAssertEqual(UInt16(bytes[10]) | (UInt16(bytes[11]) << 8), DuelReplayStateEncoding.rulesVersion)
        XCTAssertEqual(bytes[12], 2)
        var fighterWriter = try DuelReplayStateWriter(kind: 2)
        let headerLength = fighterWriter.data.count
        try fighterWriter.fighter(fight.fighters[1])
        XCTAssertNotNil(bytes.range(of: fighterWriter.data.dropFirst(headerLength)),
                        "The launched fighter must be present in the canonical weapon-fight state")
    }
}
