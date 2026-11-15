import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangSwordRuntimeTests: XCTestCase {
    private func catalog() throws -> DuelWeaponCatalog {
        let env = ProcessInfo.processInfo.environment
        guard let actor = env["ERLANG_RUNTIME_PROFILE"], let opponents = env["ERLANG_OPPONENT_CATALOG"] else {
            throw XCTSkip("Authenticated source sword and own-rig actor tracks are not staged")
        }
        let decoder = JSONDecoder()
        let wu = try decoder.decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: actor)))
        let prior = try decoder.decode(DuelWeaponCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: opponents)))
        return .init(schemaVersion: 1, previewFramesPerSecond: 30, profiles: [wu, try XCTUnwrap(prior.profile(for: .ember))])
    }
    private func ready(_ catalog: DuelWeaponCatalog, direction: Int, avatar: Bool) throws -> DuelWeaponFight {
        let x = direction == 1 ? 3000 : 9000
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .wuYong, x: x, facing: direction),
            .init(hero: .ember, x: x + 2500 * direction, facing: -direction)],
            mode: .practice, difficulty: .learning, catalog: catalog, seed: 42))
        for _ in 0..<1000 where fight.sourceIntroActive { fight.step(.neutral, opponent: .neutral) }
        if avatar {
            for _ in 0..<2400 where fight.erlangState(0)?.light != 10_000 {
                fight.step(.init(weaponCommand: fight.canUseErlang(.meditate, index: 0) ? .ranged : nil,
                                 rangedHeld: true), opponent: .neutral)
            }
            for _ in 0..<400 where fight.erlangState(0)?.cast != nil { fight.step(.neutral, opponent: .neutral) }
            fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
            for _ in 0..<400 where fight.erlangState(0)?.cast != nil { fight.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(fight.erlangState(0)?.form, .avatar)
        }
        return fight
    }
    func testHumanTimerSurvivesReactionAndAvatarUsesFormInsteadOfUltimateBuff() {
        var value = DuelErlangFightState(seed: 42)
        for _ in 0..<60 { value.acceptedPhysicalContact(kind: .weapon, imperialSpear: true,
            generated: false, targetHasDogDebuff: false) }
        XCTAssertEqual(value.swords, 6); XCTAssertEqual(value.takeSwordSpawnSlots(), Array(1...6))
        XCTAssertTrue(value.requestSwords()); XCTAssertNil(value.cast)
        XCTAssertEqual(value.swordReleaseTicks, 140); XCTAssertEqual(value.swords, 6)
        for _ in 0..<100 { value.advance() }
        value.interrupt(); XCTAssertEqual(value.swordReleaseTicks, 40)
        for _ in 0..<39 { value.advance() }; XCTAssertFalse(value.takeSwordAttackEvent())
        value.advance(); XCTAssertTrue(value.takeSwordAttackEvent()); XCTAssertFalse(value.takeSwordAttackEvent())
        XCTAssertTrue(value.start(.ascend, duration: 1, direction: 1, x: 3000))
        _ = value.release(); value.completeCast()
        XCTAssertEqual(value.wrathTicks, 0); XCTAssertTrue(value.requestSwords())
        XCTAssertEqual(value.swordReleaseTicks, 30); XCTAssertNil(value.cast)
        value.resetRound(seed: 43)
        XCTAssertEqual(value.swords, 0); XCTAssertEqual(value.swordReleaseTicks, 0)
        XCTAssertTrue(value.takeSwordSpawnSlots().isEmpty); XCTAssertFalse(value.takeSwordAttackEvent())
    }
    func testActualSlotsKeepDepthBirthIdentityAndNativeEarlyLoopAndRotate() throws {
        let profile = try catalog().profiles[0], slots = try XCTUnwrap(profile.erlangRules?.swordSlots)
        XCTAssertTrue(DuelErlangSwordMotion.matches(profile: profile))
        for direction in [1, -1] {
            var space = DuelErlangSpatialState()
            let owner = DuelErlangSpatialState.SwordOwnerPose(head: .init(x: 5, y: 1.5),
                pelvis: .init(x: 5, y: 1), direction: direction)
            for slot in slots { space.spawnSword(owner: 0, slot: slot, pose: owner, hidden: false) }
            XCTAssertEqual(space.models.map { $0.origin.z }, [0.5, -0.5, 0.5, -0.5, 0.15, 0.15])
            XCTAssertEqual(space.models.map { $0.origin.y }, [1.7, 1.7, 1.95, 1.95, 2.05, 2.25])
            let ids = space.models.map(\.id)
            for _ in 0..<91 { space.advance(); _ = space.updateSwords(owner: 0, pose: owner, attack: false, hidden: false) }
            XCTAssertEqual(space.models[0].role, slots[0].birthRole)
            space.advance(); _ = space.updateSwords(owner: 0, pose: owner, attack: false, hidden: false)
            XCTAssertTrue(space.models.allSatisfy { $0.role == DuelErlangSwordMotion.idleRole && $0.motionTick(at: space.liveTick) == 0 })
            for _ in 0..<93 { space.advance(); _ = space.updateSwords(owner: 0, pose: owner, attack: false, hidden: false) }
            XCTAssertEqual(space.models[0].motionTick(at: space.liveTick), 0)
            XCTAssertEqual(space.models.map(\.id), ids); XCTAssertTrue(space.models.allSatisfy { $0.bornAt == 0 })
            let crossed = DuelErlangSpatialState.SwordOwnerPose(head: .init(x: 5, y: 1.5), pelvis: .init(x: 5), direction: -direction)
            for _ in 0..<8 { space.advance(); _ = space.updateSwords(owner: 0, pose: crossed, attack: false, hidden: false) }
            XCTAssertEqual(space.models[0].role, DuelErlangSwordMotion.rotateRole)
            XCTAssertEqual(space.models[0].motionTick(at: space.liveTick), 0)
            space.advance(); _ = space.updateSwords(owner: 0, pose: crossed, attack: false, hidden: false)
            XCTAssertEqual(space.models[0].role, DuelErlangSwordMotion.idleRole)
            XCTAssertEqual(space.models.map(\.id), ids)
            XCTAssertEqual(space.models.map { $0.origin.z }, [0.5, -0.5, 0.5, -0.5, 0.15, 0.15])
        }
    }
    func testSourceMoveAppliesCentimetresPerTickAndAttackRetainsItsMovingOrigin() throws {
        let slot = try XCTUnwrap(try catalog().profiles[0].erlangRules?.swordSlots?.first)
        var space = DuelErlangSpatialState()
        let initial = DuelErlangSpatialState.SwordOwnerPose(head: .init(x: 3), pelvis: .init(x: 3), direction: 1)
        space.spawnSword(owner: 0, slot: slot, pose: initial, hidden: false)
        let moved = DuelErlangSpatialState.SwordOwnerPose(head: .init(x: 5), pelvis: .init(x: 5), direction: 1)
        for _ in 0..<7 { space.advance(); _ = space.updateSwords(owner: 0, pose: moved, attack: false, hidden: false) }
        XCTAssertEqual(space.models[0].origin.x, 2.25)
        space.advance(); _ = space.updateSwords(owner: 0, pose: moved, attack: false, hidden: false)
        XCTAssertEqual(space.models[0].swordMotion?.moveCentimetersPerTick, 5)
        XCTAssertEqual(space.models[0].origin.x, 2.30, accuracy: 1e-12)
        XCTAssertEqual(space.models[0].previousOrigin.x, 2.25)
        let id = space.models[0].id
        space.advance(); _ = space.updateSwords(owner: 0, pose: moved, attack: true, hidden: false)
        XCTAssertEqual(space.models[0].id, id); XCTAssertEqual(space.models[0].motionTick(at: space.liveTick), 0)
        XCTAssertEqual(space.models[0].origin.x, 2.71, accuracy: 1e-12)
        XCTAssertEqual(space.models[0].origin.y, 1.60, accuracy: 1e-12)
        for _ in 0..<70 { space.advance(); XCTAssertFalse(space.updateSwords(owner: 0, pose: moved, attack: false, hidden: false)) }
        XCTAssertEqual(space.models.count, 1)
        space.advance(); XCTAssertTrue(space.updateSwords(owner: 0, pose: moved, attack: false, hidden: false))
        XCTAssertTrue(space.models.isEmpty)
    }
    func testActualFightLaunchMovesTheExistingSixSwordsAndHitsThroughSourceCapsules() throws {
        let catalog = try catalog()
        for direction in [1, -1] {
            var fight = try ready(catalog, direction: direction, avatar: true)
            let ids = fight.erlangModels.filter { $0.swordMotion != nil }.map(\.id)
            XCTAssertEqual(ids.count, 6); XCTAssertTrue(fight.canUseErlang(.swords, index: 0))
            let before = fight.landedHits[0]
            fight.step(.init(move: -direction, weaponCommand: .ranged), opponent: .neutral)
            XCTAssertNil(fight.erlangState(0)?.cast)
            XCTAssertEqual(fight.erlangState(0)?.swordReleaseTicks, 30)
            XCTAssertTrue(fight.fighters[0].walking, "Sword scheduling must leave normal movement available")
            for _ in 0..<29 { fight.step(.neutral, opponent: .neutral) }
            XCTAssertFalse(fight.erlangModels.contains { $0.role == DuelErlangSwordMotion.attackRole })
            fight.step(.neutral, opponent: .neutral)
            XCTAssertEqual(fight.erlangModels.filter { $0.role == DuelErlangSwordMotion.attackRole }.map(\.id), ids)
            for _ in 0..<65 where fight.landedHits[0] == before { fight.step(.neutral, opponent: .neutral) }
            XCTAssertGreaterThan(fight.landedHits[0], before)
            XCTAssertTrue(fight.erlangModels.contains { $0.role == DuelErlangSwordMotion.attackRole && !$0.acceptedAttackIDs.isEmpty })
        }
    }
}
