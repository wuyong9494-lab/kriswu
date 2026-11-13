import XCTest
@testable import ShiftCore

/// Synthetic source-time continuations, not recovered SF3 contact events.
/// Every stage deliberately offers multiple separated geometric re-entries so
/// a missed earlier stage cannot hide a cumulative damage-budget regression.
final class DuelWeaponComboTests: XCTestCase {
    private typealias Fixture = DuelWeaponTestFixtures

    func testMissedOpeningStrikeCannotBankAnExtraHitForTheSecondStage() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for direction in [1, -1] {
                var fight = try makeFight(hero: hero, direction: direction)
                let first = try XCTUnwrap(fight.profiles[0].clip(command: .weapon))
                let link = try XCTUnwrap(fight.profiles[0].combo(from: first.name))
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                let observed = run(&fight)
                XCTAssertEqual(observed.firstContinuationTick, link.sourceFrame * 2)
                XCTAssertEqual(observed.contacts.count, 1, "\(hero)/\(direction): a whiff is not stored damage")
                XCTAssertEqual(observed.contacts.first?.clip, link.to)
                XCTAssertEqual(fight.landedHits, [1, 0])
                XCTAssertEqual(fight.damageDealt[0], hero == .ember ? 80 : 105)
                XCTAssertEqual(1000 - fight.fighters[1].health, fight.damageDealt[0])
            }
        }
    }

    func testSuccessfulOpeningStrikeStillAllowsOneDistinctContinuationHit() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for direction in [1, -1] {
                var fight = try makeFight(hero: hero, direction: direction, openingPeaks: [8])
                let first = try XCTUnwrap(fight.profiles[0].clip(command: .weapon))
                let next = try XCTUnwrap(fight.profiles[0].combo(from: first.name)?.to)
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                let observed = run(&fight)
                XCTAssertEqual(observed.contacts.map(\.clip), [first.name, next])
                XCTAssertEqual(observed.firstContinuationTick, 8)
                XCTAssertGreaterThan(observed.contacts.last?.tick ?? 0, 12,
                                     "The shared contact at the anchor must not hit again")
                XCTAssertEqual(fight.landedHits, [2, 0])
                XCTAssertEqual(fight.damageDealt[0], 2 * (hero == .ember ? 80 : 105))
            }
        }
    }

    func testTwoMissedStagesCannotBankExtraHitsForTheThirdStage() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for direction in [1, -1] {
                var fight = try makeFight(hero: hero, direction: direction, thirdStage: true)
                let first = try XCTUnwrap(fight.profiles[0].clip(command: .weapon))
                let second = try XCTUnwrap(fight.profiles[0].combo(from: first.name)?.to)
                let third = try XCTUnwrap(fight.profiles[0].combo(from: second))
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                var queuedThird = false
                var thirdTicks: [Int] = []
                var contacts = 0
                for _ in 0..<100 {
                    let queue = !queuedThird && fight.fighters[0].weaponPose?.clip == second
                    fight.step(.init(weaponCommand: queue ? .weapon : nil), opponent: .neutral)
                    if queue { queuedThird = true }
                    if fight.fighters[0].weaponPose?.clip == third.to {
                        thirdTicks.append(fight.fighters[0].weaponPose!.tick)
                    }
                    contacts += fight.contacts.count
                }
                XCTAssertTrue(queuedThird)
                XCTAssertEqual(thirdTicks.first, third.sourceFrame * 2)
                XCTAssertEqual(contacts, 1, "Only the entered third stage may spend its own hit opportunity")
                XCTAssertEqual(fight.landedHits, [1, 0])
            }
        }
    }

    func testGuardConsumesTheStageOpportunityWithoutExtraChipOrEnergy() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            var fight = try makeFight(hero: hero, initialEnergy: 40)
            let startingEnergy = fight.fighters.map(\.energy)
            fight.step(.init(weaponCommand: .weapon), opponent: .init(guardHeld: true))
            fight.step(.init(weaponCommand: .weapon), opponent: .init(guardHeld: true))
            let observed = run(&fight, guarding: true)
            XCTAssertEqual(observed.contacts.count, 1)
            XCTAssertEqual(observed.contacts.first?.kind, .block)
            XCTAssertEqual(fight.landedHits, [0, 0])
            XCTAssertEqual(fight.damageDealt, [0, 0])
            XCTAssertEqual(fight.fighters[1].health, 1000 - (hero == .ember ? 80 : 105) / 12)
            XCTAssertEqual(fight.fighters.map(\.energy), [startingEnergy[0] + 8, startingEnergy[1] + 10])
        }
    }

    func testHitStopAtTheAnchorAcceptsOneFollowUpWithoutReplayingTheContact() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            var fight = try makeFight(hero: hero, openingPeaks: [10])
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            for _ in 0..<20 where fight.hitStop == 0 { fight.step(.neutral, opponent: .neutral) }
            let pose = try XCTUnwrap(fight.fighters[0].weaponPose)
            XCTAssertEqual(pose.tick, 8)
            XCTAssertGreaterThan(fight.hitStop, 0)
            XCTAssertEqual(fight.landedHits, [1, 0])
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            XCTAssertEqual(fight.fighters[0].weaponPose, pose, "Buffering must not advance the frozen source pose")
            let observed = run(&fight)
            XCTAssertEqual(observed.firstContinuationTick, 9,
                           "A hit-stop press consumes the existing anchor before the next simulation step")
            XCTAssertEqual(observed.contacts.count, 1)
            XCTAssertGreaterThan(observed.contacts.first?.tick ?? 0, 12)
            XCTAssertEqual(fight.landedHits, [2, 0])
        }
    }

    func testPauseCancellationAtTheAnchorCannotReviveTheQueuedStage() throws {
        var fight = try makeFight(openingPeaks: [10])
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<20 where fight.hitStop == 0 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(fight.hitStop, 0)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        var uncancelled = fight
        fight.cancelBufferedInputs()
        XCTAssertEqual(fight.fighters, uncancelled.fighters)
        XCTAssertNotEqual(try DuelReplayStateEncoding.encode(fight), try DuelReplayStateEncoding.encode(uncancelled))
        let cancelled = run(&fight)
        let continued = run(&uncancelled)
        XCTAssertNil(cancelled.firstContinuationTick)
        XCTAssertTrue(cancelled.contacts.isEmpty)
        XCTAssertEqual(fight.landedHits, [1, 0])
        XCTAssertEqual(continued.contacts.count, 1)
        XCTAssertEqual(uncancelled.landedHits, [2, 0])
    }

    func testChainedStageBudgetsReplayIdenticallyThroughWhiffsBlocksAndHitStop() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for direction in [1, -1] {
                for guardHeld in [false, true] {
                    var a = try makeFight(hero: hero, direction: direction, openingPeaks: [8])
                    var b = a
                    for tick in 0..<100 {
                        let input = DuelGame.Input(weaponCommand: tick <= 1 ? .weapon : nil)
                        let opponent = DuelGame.Input(guardHeld: guardHeld)
                        a.step(input, opponent: opponent); b.step(input, opponent: opponent)
                        XCTAssertEqual(a, b)
                        XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b))
                    }
                    XCTAssertEqual(a.landedHits[0], guardHeld ? 0 : 2)
                }
            }
        }
    }

    private struct Observation {
        struct Contact { let clip: String; let tick: Int; let kind: DuelWeaponFight.Contact.Kind }
        var contacts: [Contact] = []
        var firstContinuationTick: Int?
    }

    private func run(_ fight: inout DuelWeaponFight, guarding: Bool = false) -> Observation {
        let first = fight.profiles[0].clip(command: .weapon)!.name
        let next = fight.profiles[0].combo(from: first)!.to
        var result = Observation()
        for _ in 0..<100 {
            fight.step(.neutral, opponent: .init(guardHeld: guarding))
            if let pose = fight.fighters[0].weaponPose {
                if pose.clip == next && result.firstContinuationTick == nil { result.firstContinuationTick = pose.tick }
                for contact in fight.contacts {
                    result.contacts.append(.init(clip: pose.clip, tick: pose.tick, kind: contact.kind))
                }
            }
        }
        return result
    }

    private func makeFight(hero: DuelGame.Hero = .ember, direction: Int = 1,
                           openingPeaks: [Int] = [], thirdStage: Bool = false,
                           initialEnergy: Int = 100) throws -> DuelWeaponFight {
        let profiles = Fixture.catalog().profiles.map { profile -> DuelWeaponProfile in
            let first = profile.clip(command: .weapon)!, second = profile.clip(role: "weapon2")!
            let thirdName = first.name + "3"
            func attack(_ name: String, peaks: [Int]) -> DuelWeaponClip {
                let frames = 25, count = 2 * frames - 1
                let zero = Array(repeating: DuelWeaponPoint(), count: count)
                let tips = (0..<count).map { tick -> DuelWeaponPoint in
                    let reach = peaks.map { max(0, 1 - Double(abs(tick - $0)) / 3) }.max() ?? 0
                    return .init(x: 0.5 + 1.1 * reach, y: 1)
                }
                let bases = tips.map { DuelWeaponPoint(x: $0.x - 0.4, y: 1) }
                let left = profile.activeWeaponSides.contains("left"), right = profile.activeWeaponSides.contains("right")
                let tracks = DuelWeaponTracks(samplesPerSourceFrame: 2, root: zero, handL: zero, handR: zero,
                    footL: zero, footR: zero, weaponBaseL: left ? bases : [], weaponTipL: left ? tips : [],
                    weaponBaseR: right ? bases : [], weaponTipR: right ? tips : [],
                    groundLift: Array(repeating: 0, count: count))
                return .init(name: name, frames: frames, sha256: first.sha256, bundle: "synthetic-combo-test-only", tracks: tracks)
            }
            var clips = profile.clips.filter { $0.name != first.name && $0.name != second.name }
            clips.append(attack(first.name, peaks: openingPeaks))
            clips.append(attack(second.name, peaks: openingPeaks + (thirdStage ? [] : [16, 28])))
            var links = [DuelWeaponComboLink(from: first.name, to: second.name, sourceFrame: 4)]
            if thirdStage {
                clips.append(attack(thirdName, peaks: openingPeaks + [26, 35]))
                links.append(.init(from: second.name, to: thirdName, sourceFrame: 10))
            }
            return .init(id: profile.id, hero: profile.hero, faction: profile.faction,
                         resourceName: profile.resourceName, bytes: profile.bytes, sha256: profile.sha256,
                         bodyID: profile.bodyID, weaponID: profile.weaponID, activeWeaponSides: profile.activeWeaponSides,
                         roles: profile.roles, clips: clips, comboLinks: links)
        }
        let catalog = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
                                        sourceFramesPerSecond: nil, profiles: profiles)
        let other: DuelGame.Hero = hero == .ember ? .liu : .ember
        var first = DuelGame.Fighter(hero: hero, x: 5000 - direction * 600, facing: direction)
        var second = DuelGame.Fighter(hero: other, x: 5000 + direction * 600, facing: -direction)
        first.energy = initialEnergy; second.energy = initialEnergy
        return try XCTUnwrap(DuelWeaponFight(
            fighters: [first, second],
            mode: .practice, difficulty: .learning, catalog: catalog, seed: 7))
    }
}
