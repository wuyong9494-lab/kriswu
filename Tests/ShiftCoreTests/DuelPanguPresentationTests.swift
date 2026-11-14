import XCTest
@testable import ShiftCore

/// Synthetic geometry validates observation of the real Fight. It does not
/// supply retail Pangu art, skill parameters, or an alternate simulation.
final class DuelPanguPresentationTests: XCTestCase {
    private typealias F = DuelPanguFightFixture
    private typealias P = DuelPanguPresentation

    private func releases(_ fight: DuelWeaponFight) -> [P.Volume] {
        fight.panguPresentationEvents.compactMap {
            if case .attackReleased(let value) = $0.kind { return value }; return nil
        }
    }
    private func contacts(_ fight: DuelWeaponFight) -> [P.Contact] {
        fight.panguPresentationEvents.compactMap {
            if case .contact(let value) = $0.kind { return value }; return nil
        }
    }

    func testGeometryPreservesProjectileOriginGroundAnchorAndMovingMeleeOrigin() throws {
        let cases: [(DuelPanguRules.Delivery, DuelGame.Box, DuelGame.Box)] = [
            (.projectile, .init(minX: 2960, maxX: 3040, minY: 700, maxY: 1300),
                          .init(minX: 2960, maxX: 3040, minY: 700, maxY: 1300)),
            (.windBlade, .init(minX: 2960, maxX: 3040, minY: 700, maxY: 1300),
                         .init(minX: 2960, maxX: 3040, minY: 700, maxY: 1300)),
            (.ground, .init(minX: 2300, maxX: 3000, minY: 201, maxY: 800),
                      .init(minX: 2300, maxX: 3000, minY: 201, maxY: 800)),
            (.melee, .init(minX: 2300, maxX: 3000, minY: 701, maxY: 1300),
                     .init(minX: 2400, maxX: 3100, minY: 1701, maxY: 2300)),
            (.landingShock, .init(minX: 2300, maxX: 3700, minY: 201, maxY: 800),
                            .init(minX: 2300, maxX: 3700, minY: 201, maxY: 800))
        ]
        for (delivery, initialBounds, movedBounds) in cases {
            var rules = DuelPanguTestFixture.rules(level: 2)
            F.changingAttack(&rules, .shard) {
                $0.delivery = delivery; $0.rangeMillimeters = 700
                $0.hitboxBottomMillimeters = 201; $0.hitboxTopMillimeters = 800
                $0.radiusMillimeters = 40
            }
            var state = try XCTUnwrap(DuelPanguState(rules: rules, seed: 4))
            var effects = state.start(.shard)
            for _ in 0..<2 { effects += state.step() }
            let attack = try XCTUnwrap(effects.compactMap { effect -> DuelPanguState.Attack? in
                if case .attack(let value) = effect { return value }; return nil
            }.first)
            var owner = DuelGame.Fighter(hero: .liu, x: 3000, facing: -1)
            owner.y = 500
            let target = DuelGame.Fighter(hero: .ember, x: 5000, facing: -1)
            let hurts = [DuelGame.Box(minX: 2700, maxX: 3300, minY: 680, maxY: 2160),
                         .init(minX: 4700, maxX: 5300, minY: 180, maxY: 1660)]
            var space = DuelPanguSpatialState(); space.tick = 7
            space.spawn(attack, owner: 0, fighter: owner, activeTicks: 3, frame: space.tick)
            let untouched = space
            let initial = P(space: space, fighters: [owner, target], hurts: hurts, states: [state, nil])
            let volume = try XCTUnwrap(initial.volumes.first)
            XCTAssertEqual(volume.bounds, initialBounds, delivery.rawValue)
            XCTAssertEqual(volume.owner, 0); XCTAssertEqual(volume.attackID, attack.id)
            XCTAssertEqual(volume.direction, -1)
            XCTAssertEqual(volume.center.x, Double(initialBounds.minX + initialBounds.maxX) / 2000)
            XCTAssertEqual(volume.center.y, Double(initialBounds.minY + initialBounds.maxY) / 2000)
            owner.x += 100; owner.y += 1000
            let moved = P(space: space, fighters: [owner, target], hurts: hurts, states: [state, nil])
            XCTAssertEqual(moved.volumes.first?.bounds, movedBounds, delivery.rawValue)
            XCTAssertEqual(space, untouched, "Reading presentation must not advance a projectile")
        }
    }

    func testSameTickContactSurvivesVolumeRemovalAndHitStopDoesNotReplayFeedback() throws {
        for facing in [1, -1] {
            var rules = DuelPanguTestFixture.rules(level: 2)
            F.changingAttack(&rules, .shard) { $0.projectileSpeedMillimetersPerTick = 2000 }
            var fight = try F.fight(rules: rules, facing: facing)
            fight.step(.init(move: facing, weaponCommand: .shadow), opponent: .neutral)
            XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
            let release = try XCTUnwrap(releases(fight).first)
            let contact = try XCTUnwrap(contacts(fight).first)
            XCTAssertTrue(fight.panguPresentation.volumes.isEmpty,
                          "The fast projectile has already been consumed by its contact")
            XCTAssertEqual(contact.attackID, release.attackID)
            XCTAssertEqual(contact.ability, .shard); XCTAssertEqual(contact.delivery, .projectile)
            XCTAssertEqual(contact.damageKind, .shadow); XCTAssertEqual(contact.kind, .hit)
            XCTAssertFalse(contact.generated); XCTAssertFalse(contact.empowered)
            XCTAssertEqual(contact.direction, facing)
            XCTAssertEqual(contact.position, fight.contacts.first?.position)
            XCTAssertEqual(Set(fight.panguPresentationEvents.map(\.id)).count, fight.panguPresentationEvents.count)
            let frozen = fight.panguPresentation
            let bytes = try DuelReplayStateEncoding.encode(fight)
            for _ in 0..<10 {
                XCTAssertEqual(fight.panguPresentation, frozen)
                XCTAssertEqual(contacts(fight).first, contact)
            }
            XCTAssertEqual(try DuelReplayStateEncoding.encode(fight), bytes)
            XCTAssertGreaterThan(fight.hitStop, 0)
            let pause = fight.hitStop
            for _ in 0..<pause {
                fight.step(.neutral, opponent: .neutral)
                XCTAssertEqual(fight.panguPresentation, frozen)
                XCTAssertTrue(fight.panguPresentationEvents.isEmpty)
                XCTAssertEqual(fight.landedHits[0], 1)
            }
        }
    }

    func testPetrificationFeedbackRequiresActualRangeAndInvulnerabilityAcceptance() throws {
        for (distance, invulnerable, accepted) in [(800, 0, true), (1800, 0, false), (800, 50, false)] {
            var rules = DuelPanguTestFixture.rules(level: 2)
            F.changingAttack(&rules, .heavenfall) { $0.rangeMillimeters = 1000 }
            let catalog = try F.catalog(rules: rules)
            var target = DuelGame.Fighter(hero: .ember, x: 3500 + distance, facing: -1)
            target.invulnerable = invulnerable
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .liu, x: 3500, facing: 1), target],
                mode: .practice, difficulty: .learning, catalog: catalog, seed: 4))
            fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
            let applied = fight.panguPresentationEvents.compactMap { event -> P.Control? in
                if case .controlApplied(let control) = event.kind, control.kind == .petrify { return control }
                return nil
            }
            XCTAssertEqual(applied.count, accepted ? 1 : 0)
            XCTAssertEqual(fight.panguPresentation.controls.contains { $0.kind == .petrify }, accepted)
            if accepted {
                XCTAssertEqual(applied.first?.target, 1)
                XCTAssertEqual(applied.first?.bounds, fight.hurtBox(1))
            }
        }
    }

    func testPillarAndLandingFeedbackUsePhysicalHeightRatherThanRequestedPhaseAlone() throws {
        var fight = try F.fight(rules: DuelPanguTestFixture.rules(level: 2), distance: 1800)
        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        var riseCount = 0, fallCount = 0, landedCount = 0
        var sawRaisedPillar = false
        for _ in 0..<40 {
            for pillar in fight.panguPresentation.pillars {
                XCTAssertEqual(pillar.heightMillimeters, fight.fighters[pillar.owner].y)
                sawRaisedPillar = sawRaisedPillar || pillar.heightMillimeters > 0
            }
            for event in fight.panguPresentationEvents {
                switch event.kind {
                case .pillarStarted(let pillar):
                    riseCount += 1; XCTAssertEqual(pillar.heightMillimeters, fight.fighters[pillar.owner].y)
                    XCTAssertFalse(pillar.isDescending)
                case .descentStarted(let pillar):
                    fallCount += 1; XCTAssertGreaterThan(pillar.heightMillimeters, 0)
                    XCTAssertTrue(pillar.isDescending)
                case .landed(let owner, let position):
                    landedCount += 1; XCTAssertEqual(fight.fighters[owner].y, 0); XCTAssertEqual(position.y, 0)
                case .attackReleased(let attack) where attack.ability == .heavenfall:
                    XCTAssertEqual(fight.fighters[attack.owner].y, 0)
                    XCTAssertEqual(attack.bounds.minY, 200, "Ground attack uses its configured floor-relative height")
                default: break
                }
            }
            fight.step(.neutral, opponent: .neutral)
        }
        XCTAssertTrue(sawRaisedPillar)
        XCTAssertEqual(riseCount, 1); XCTAssertEqual(fallCount, 1); XCTAssertEqual(landedCount, 1)
        XCTAssertTrue(fight.panguPresentation.pillars.isEmpty)
    }

    func testStormGateFeedbackUsesOnlyAcceptedActualTeleport() throws {
        for wallBlocked in [false, true] {
            let rules = DuelPanguTestFixture.rules(level: 4)
            let catalog = try F.catalog(rules: rules)
            let startX = wallBlocked ? 8000 : 3500
            let targetX = wallBlocked ? DuelGame.rightWall : 4300
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
                .init(hero: .liu, x: startX, facing: 1), .init(hero: .ember, x: targetX, facing: -1)
            ], mode: .practice, difficulty: .learning, catalog: catalog, seed: 4))
            fight.step(.init(move: -1, weaponCommand: .shadow), opponent: .neutral)
            XCTAssertTrue(F.until(&fight, limit: 12) { $0.panguState(0)?.activeCast == nil })
            XCTAssertTrue(fight.canUsePangu(.stormGate, index: 0))
            let from = fight.fighters[0].x
            fight.step(.init(move: -fight.fighters[0].facing, weaponCommand: .shadow), opponent: .neutral)
            var teleports: [(DuelWeaponPoint, DuelWeaponPoint)] = []
            for _ in 0..<8 {
                for event in fight.panguPresentationEvents {
                    if case .teleported(let owner, let old, let new) = event.kind {
                        XCTAssertEqual(owner, 0)
                        XCTAssertEqual(new.x, Double(fight.fighters[0].x) / 1000)
                        teleports.append((old, new))
                    }
                }
                fight.step(.neutral, opponent: .neutral)
            }
            XCTAssertEqual(teleports.count, wallBlocked ? 0 : 1)
            if wallBlocked { XCTAssertEqual(fight.fighters[0].x, from) }
            else { XCTAssertEqual(teleports.first?.0.x, Double(from) / 1000) }
        }
    }

    func testFeedbackCapacityCannotLimitReleasedAttacksOrTheirDamage() throws {
        var rules = DuelPanguTestFixture.rules(level: 3)
        rules.combo.affectedKinds = []
        rules.combo.allAttackWindThreshold = 1
        rules.policies.thresholdsUseComboBeforeContact = false
        rules.heavyWindCount = 16
        rules.windBlade.damage = 1
        rules.windBlade.projectileSpeedMillimetersPerTick = 4000
        rules.windBlade.hitStopTicks = 0
        rules.windBlade.impact = .init(distanceMillimeters: 0, durationTicks: 1)
        let source = try F.catalog(rules: rules, ordinaryDamage: 0, ordinaryHitStop: 0)
        let catalog = try DuelWeaponTestFixtures.changing(source) { profiles in
            guard let panguIndex = profiles.firstIndex(where: { $0["id"] as? String == "liu_pangu" }),
                  var combat = profiles[panguIndex]["combatRules"] as? [String: Any],
                  var attacks = combat["attacks"] as? [[String: Any]] else { return XCTFail("Missing synthetic rules") }
            for index in attacks.indices where attacks[index]["command"] as? String == "weapon" {
                guard let template = (attacks[index]["strikes"] as? [[String: Any]])?.first else {
                    return XCTFail("Missing synthetic strike")
                }
                attacks[index]["strikes"] = (0..<32).map { id -> [String: Any] in
                    var strike = template; strike["id"] = id; return strike
                }
            }
            combat["attacks"] = attacks; profiles[panguIndex]["combatRules"] = combat
        }
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .liu, x: 3500, facing: 1), .init(hero: .ember, x: 4300, facing: -1)
        ], mode: .practice, difficulty: .learning, catalog: catalog, seed: 4))
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.landedHits[0] >= 32 })
        XCTAssertEqual(fight.landedHits[0], 32)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.panguPresentationEvents.count, P.maximumEventsPerStep)
        XCTAssertEqual(Set(fight.panguPresentationEvents.map(\.id)).count, P.maximumEventsPerStep)
        XCTAssertEqual(fight.landedHits[0], 32 + 32 * 16)
        XCTAssertEqual(fight.damageDealt[0], 32 * 16)
        XCTAssertEqual(fight.fighters[1].health, 1000 - 32 * 16)
    }

    func testTerminalAndRoundResetClearPresentationWithoutReusingEventKeys() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        F.changingAttack(&rules, .shard) {
            $0.damage = 1000; $0.projectileSpeedMillimetersPerTick = 2000
        }
        var fight = try F.fight(rules: rules, mode: .versus)
        fight.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.wins[0] == 1 })
        let previousIDs = Set(fight.panguPresentationEvents.map(\.id))
        XCTAssertFalse(previousIDs.isEmpty)
        XCTAssertTrue(fight.panguPresentation.volumes.isEmpty)
        XCTAssertTrue(fight.panguPresentation.controls.isEmpty)
        XCTAssertTrue(fight.panguPresentation.casts.isEmpty)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertTrue(fight.panguPresentationEvents.isEmpty)
        XCTAssertTrue(F.until(&fight, limit: 160) { $0.phase == .fighting })
        XCTAssertTrue(fight.panguPresentationEvents.isEmpty)
        XCTAssertTrue(fight.panguPresentation.volumes.isEmpty)
        fight.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertFalse(fight.panguPresentationEvents.isEmpty)
        XCTAssertTrue(previousIDs.isDisjoint(with: Set(fight.panguPresentationEvents.map(\.id))))
    }

    func testObservingPresentationKeepsLegacyAndPanguCanonicalReplaysIdentical() throws {
        for catalog in [DuelWeaponTestFixtures.catalog(), try F.catalog(rules: DuelPanguTestFixture.rules(level: 4))] {
            var observed = DuelGame(hero: .liu, mode: .practice, weaponCatalog: catalog)
            var untouched = observed
            for tick in 0..<80 {
                let input: DuelGame.Input = tick == 0 ? .init(move: 1, weaponCommand: .shadow) : .neutral
                observed.step(input, opponent: .neutral); untouched.step(input, opponent: .neutral)
                for _ in 0..<4 {
                    _ = observed.weaponFight?.panguPresentation
                    _ = observed.weaponFight?.panguPresentationEvents
                }
                XCTAssertEqual(try DuelReplayStateEncoding.encode(observed), try DuelReplayStateEncoding.encode(untouched))
                if catalog.profile(for: .liu)?.isPangu != true {
                    XCTAssertTrue(observed.weaponFight?.panguPresentation.volumes.isEmpty == true)
                    XCTAssertTrue(observed.weaponFight?.panguPresentationEvents.isEmpty == true)
                }
            }
        }
    }
}
