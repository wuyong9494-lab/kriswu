import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangStaticModelReleaseTests: XCTestCase {
    private func catalog() throws -> DuelWeaponCatalog {
        let env = ProcessInfo.processInfo.environment
        guard let actor = env["ERLANG_RUNTIME_PROFILE"], let opponents = env["ERLANG_OPPONENT_CATALOG"] else {
            throw XCTSkip("Authenticated D15 actor and model tracks are not staged")
        }
        let decoder = JSONDecoder()
        let profile = try decoder.decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: actor)))
        let prior = try decoder.decode(DuelWeaponCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: opponents)))
        return .init(schemaVersion: 1, previewFramesPerSecond: 30,
                     profiles: [profile, try XCTUnwrap(prior.profile(for: .ember))])
    }
    private func avatar(_ catalog: DuelWeaponCatalog, direction: Int, invulnerable: Bool) throws -> DuelWeaponFight {
        let ownerX = direction == 1 ? 3000 : 9000
        var enemy = DuelGame.Fighter(hero: .ember, x: ownerX + direction * 6000, facing: -direction)
        if invulnerable { enemy.invulnerable = 100_000 }
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .wuYong, x: ownerX, facing: direction), enemy],
            mode: .practice, difficulty: .learning, catalog: catalog, seed: 42))
        for _ in 0..<1000 where fight.sourceIntroActive { fight.step(.neutral, opponent: .neutral) }
        for _ in 0..<2400 where fight.erlangState(0)?.light != 10_000 {
            let start = fight.canUseErlang(.meditate, index: 0)
            fight.step(.init(weaponCommand: start ? .ranged : nil, rangedHeld: true), opponent: .neutral)
        }
        for _ in 0..<400 where fight.erlangState(0)?.cast != nil { fight.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(fight.canUseErlang(.ascend, index: 0))
        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        for _ in 0..<400 where fight.erlangState(0)?.cast != nil { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.erlangState(0)?.form, .avatar)
        return fight
    }
    func testStateChangeRetainsModelIdentityButRestartsTheSourceAnimationClock() throws {
        var space = DuelErlangSpatialState()
        let id = try XCTUnwrap(space.spawn(owner: 0, ability: .swords, role: "erlangSummon_swordBirth1",
            direction: 1, origin: .init(x: 3, y: 1.7, z: 0.5), swordSlot: 1))
        for _ in 0..<92 { space.advance() }
        space.models[0].acceptedAttackIDs = ["old_animation_contact"]
        space.transition(id: id, role: "erlangSummon_swordIdle")
        XCTAssertEqual(space.models[0].id, id); XCTAssertEqual(space.models[0].bornAt, 0)
        XCTAssertEqual(space.models[0].stateStartedAt, 92)
        XCTAssertEqual(space.models[0].motionTick(at: space.liveTick), 0)
        XCTAssertEqual(space.models[0].swordSlot, 1); XCTAssertTrue(space.models[0].acceptedAttackIDs.isEmpty)
        space.advance(); space.transition(id: id, role: "erlangSummon_sword", direction: -1)
        XCTAssertEqual(space.models[0].origin.z, 0.5, "A source direction change does not flip the slot's world-depth shift")
        XCTAssertEqual(space.models[0].bornAt, 0); XCTAssertEqual(space.models[0].motionTick(at: space.liveTick), 0)
        space.advance(); XCTAssertEqual(space.models[0].motionTick(at: space.liveTick), 1)
    }
    func testActualStaticReleasesUseEnemyPelvisHeadAndUnclampedTwentyMetreSourceOffset() throws {
        let catalog = try catalog(), profile = catalog.profiles[0], rules = try XCTUnwrap(profile.erlangRules)
        XCTAssertEqual(rules.swordSlots?.map(\.slot), Array(1...6))
        for direction in [1, -1] {
            var fight = try avatar(catalog, direction: direction, invulnerable: true)
            let cases: [(DuelErlangFightState.Ability, DuelGame.Input, String)] = [
                (.stomp, .init(vertical: -1, weaponCommand: .shadow), "erlangSummon_stomp"),
                (.eye, .init(move: -direction, weaponCommand: .shadow), "erlangSummon_eye"),
                (.earth, .init(vertical: 1, weaponCommand: .shadow), "erlangSummon_earth"),
                (.axe, .init(move: direction, weaponCommand: .shadow), "erlangSummon_aftershock")]
            for (ability, input, role) in cases {
                XCTAssertTrue(fight.canUseErlang(ability, index: 0))
                fight.step(input, opponent: .neutral)
                for _ in 0..<400 where !fight.erlangModels.contains(where: { $0.role == role }) {
                    fight.step(.neutral, opponent: .neutral)
                }
                let model = try XCTUnwrap(fight.erlangModels.first { $0.role == role }, role)
                let release = try XCTUnwrap(rules.releases.first { $0.modelRole == role })
                let cast = try XCTUnwrap(fight.erlangState(0)?.cast)
                XCTAssertEqual(cast.tick, release.atTick)
                XCTAssertEqual(model.motionTick(at: fight.erlangLiveTick), 0)
                let clip = try XCTUnwrap(profile.clip(role: release.ownerRole))
                let anchorX: Double
                if release.anchor == "enemy.pelvis.x" { anchorX = try XCTUnwrap(fight.sourcePelvis(1)).x }
                else {
                    let samples = try XCTUnwrap(release.anchor == "head.x" ? clip.tracks.head : clip.tracks.pelvis)
                    let phase = clip.phase(at: cast.tick)
                    let raw = clip.tracks.sample(samples, phase: phase)
                    let pelvis = clip.tracks.sample(try XCTUnwrap(clip.tracks.pelvis), phase: phase)
                    let scale = Double(try XCTUnwrap(fight.fighters[0].weaponPose).pelvisScale)
                    anchorX = Double(fight.fighters[0].x) / 1000 +
                        (pelvis.x + (raw.x - pelvis.x) * scale) * Double(direction)
                }
                XCTAssertEqual(model.origin.x, anchorX + release.offset.x * Double(direction), accuracy: 1e-8)
                XCTAssertEqual(model.origin.y, Double(fight.fighters[0].y) / 1000, accuracy: 1e-8)
                XCTAssertEqual(model.origin.z, 0)
                if ability == .earth || ability == .axe {
                    XCTAssertEqual(abs(model.origin.x - anchorX), 20, accuracy: 1e-8)
                }
                for _ in 0..<400 where fight.erlangState(0)?.cast != nil { fight.step(.neutral, opponent: .neutral) }
            }
        }
    }
    func testActualStompCapsulesReachTheDistantEnemyInsteadOfTheOwner() throws {
        let catalog = try catalog()
        var fight = try avatar(catalog, direction: 1, invulnerable: false)
        let before = fight.landedHits[0]
        XCTAssertGreaterThan(abs(fight.fighters[0].x - fight.fighters[1].x), 4000)
        fight.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        for _ in 0..<100 where fight.landedHits[0] == before { fight.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(fight.landedHits[0], before)
        XCTAssertGreaterThan(fight.damageDealt[0], 0)
        XCTAssertTrue(fight.erlangModels.contains { $0.role == "erlangSummon_stomp" && !$0.acceptedAttackIDs.isEmpty })
    }
}
