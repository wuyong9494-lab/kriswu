import Foundation
import XCTest
@testable import ShiftCore

/// Encoding diagnostics use small declared fixtures. They do not certify
/// private asset provenance, source animation parity, or native rendering.
final class DuelErlangReplayStateTests: XCTestCase {
    private func fields(_ value: Any, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Mirror(reflecting: value).children.compactMap(\.label).sorted(), expected.sorted(),
            "Review every stored field against the canonical encoder.", file: file, line: line)
    }
    private func encode(_ state: DuelErlangFightState) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try state.appendReplayState(to: &writer); return writer.data
    }
    private func encode(_ space: DuelErlangSpatialState) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try space.appendReplayState(to: &writer); return writer.data
    }
    private func rules() -> DuelErlangCombatRules {
        let digest = String(repeating: "a", count: 64)
        let attack = DuelErlangCombatRules.Attack(id: "diagnostic_attack", ability: .hound,
            role: "erlangHound", modelRole: "erlangSummon_hound", sourceConfigurationSHA256: digest,
            sourceRecordIndex: 99, startTick: 2, endTick: 5, parts: ["Common"], damageKind: .weapon,
            baseDamageBps: 1500, unblockable: false, knocksDown: false,
            impact: .init(distanceMillimeters: 200, durationTicks: 10), hitStopTicks: 2, hitTags: ["dog_hit"])
        let release = DuelErlangCombatRules.Release(id: "diagnostic_release", ability: .hound,
            ownerRole: "erlangHound", atTick: 1, modelRole: "erlangSummon_hound", anchor: "pelvis.x",
            offset: .init(x: 0.25), minimumLevel: 2)
        let control = DuelErlangCombatRules.Control(role: "erlangHound", kind: .uninterrupt,
            startTick: 0, endTick: 5, sourceConfigurationSHA256: digest, sourceRecordIndex: 99)
        return .init(schemaVersion: 1, sourceVersion: DuelErlangFightState.sourceVersion, sourceSHA256: digest,
            maximumHealth: 2000, normalizedWeaponPower: 1000, normalizedUnarmedPower: 1000,
            normalizedMagicPower: 1000, normalizedRangedPower: 1000,
            attacks: [attack], releases: [release], controls: [control])
    }
    func testEveryStoredErlangRuleStateAndModelFieldHasAnEncodingInventory() throws {
        let rules = rules()
        fields(rules, ["schemaVersion", "sourceVersion", "sourceSHA256", "maximumHealth", "normalizedWeaponPower",
            "normalizedUnarmedPower", "normalizedMagicPower", "normalizedRangedPower", "attacks", "releases", "controls", "swordSlots"])
        fields(try XCTUnwrap(rules.attacks.first), ["id", "ability", "role", "modelRole", "sourceConfigurationSHA256",
            "sourceRecordIndex", "startTick", "endTick", "parts", "damageKind", "baseDamageBps", "unblockable",
            "knocksDown", "impact", "hitStopTicks", "hitTags"])
        fields(try XCTUnwrap(rules.releases.first), ["id", "ability", "ownerRole", "atTick", "modelRole", "anchor", "offset", "minimumLevel"])
        fields(try XCTUnwrap(rules.controls?.first), ["role", "kind", "startTick", "endTick", "sourceConfigurationSHA256", "sourceRecordIndex"])
        var state = DuelErlangFightState(seed: 7)
        fields(state, ["level", "form", "light", "liveTick", "cast", "cooldowns", "meditationUnits", "meditationPulse",
            "meditationReleaseRequested", "meditationRechargeStarted", "swords", "pendingSwords", "swordReleaseTicks",
            "swordSpawnSlots", "swordAttackPending", "swordConsumeTicks", "swordConsumePending", "wrathTicks", "wrathRefillTicks",
            "lightDrainTicks", "meditationStacks", "meditationStackTicks", "explosionStacksHalf", "explosionStackTicks",
            "explosionCooldownTicks", "holiness", "holinessTicks", "avatarSwordSummonsPending", "avatarSwordSummonTicks",
            "lethalProtectionSpent", "normalizedHealth", "immortalActive", "criticalHealTicks", "immortalDisableTicks",
            "returnToHumanPending", "random", "nextEmissionID"])
        XCTAssertTrue(state.start(.hound, duration: 20, direction: -1, x: 3500))
        fields(try XCTUnwrap(state.cast), ["ability", "role", "tick", "duration", "direction", "originX", "released", "spentSwords", "acceptedContact"])
        var space = DuelErlangSpatialState()
        fields(space, ["liveTick", "models", "bodyContactIDs", "releasedModelIDs", "dogDebuffTicks", "nextID"])
        space.spawn(owner: 0, ability: .hound, role: "erlangSummon_hound", direction: 1, origin: .init(x: 3.5))
        fields(try XCTUnwrap(space.models.first), ["id", "owner", "ability", "role", "bornAt", "stateStartedAt", "swordSlot",
            "direction", "origin", "previousOrigin", "swordMotion", "acceptedAttackIDs"])
        fields(DuelErlangSwordMotion(headDistance: 0.75, birthY: 1.7),
            ["headDistance", "birthY", "moveCentimetersPerTick", "hidden"])
        fields(DuelErlangCombatRules.SwordSlot(slot: 1, birthRole: "erlangSummon_swordBirth1",
            offset: .init(x: -0.75, y: 1.7, z: 0.5), sourceRecordIndex: 111),
            ["slot", "birthRole", "offset", "sourceRecordIndex"])
        let track = DuelSummonMotionTrack(role: "diagnostic", clip: "diagnostic", frames: 2,
            sourceSHA256: String(repeating: "a", count: 64), sourceBundle: "diagnostic.bin",
            root: Array(repeating: .init(), count: 3), groundLift: [0, 0, 0], sourceEndEventTick: 2, sourceDeleteEventTick: 1)
        fields(track, ["role", "clip", "frames", "sourceSHA256", "sourceBundle", "sourceEndEventTick", "sourceDeleteEventTick",
            "root", "groundLift", "boneConfigurationSHA256", "collisionEdges", "hurtCapsules", "attackParts"])
    }
    func testSubDisplayHealthRngAndAcceptedIntervalLatchesCannotDisappearFromBytes() throws {
        let pristine = DuelErlangFightState(seed: 7)
        XCTAssertNotEqual(try encode(pristine), try encode(DuelErlangFightState(seed: 8)))
        var fraction = pristine
        fraction.receiveDamage(1, maximumHealth: 1_000_000)
        XCTAssertEqual(fraction.displayedHealth(maximum: 2000), pristine.displayedHealth(maximum: 2000))
        XCTAssertNotEqual(fraction.normalizedHealth, pristine.normalizedHealth)
        XCTAssertNotEqual(try encode(fraction), try encode(pristine), "Equal HUD bars do not imply equal future damage")
        var space = DuelErlangSpatialState()
        space.spawn(owner: 0, ability: .hound, role: "erlangSummon_hound", direction: -1, origin: .init(x: 4))
        let active = try encode(space)
        space.models[0].acceptedAttackIDs = ["original_interval_1"]
        XCTAssertNotEqual(try encode(space), active, "A retained model cannot hit the same source interval twice after a checkpoint")
        let accepted = try encode(space)
        space.releasedModelIDs[0] = ["original_create_model"]
        XCTAssertNotEqual(try encode(space), accepted)

        space.models[0].swordMotion = .init(headDistance: 0.75, birthY: 1.7)
        let initialSword = try encode(space)
        space.models[0].swordMotion?.moveCentimetersPerTick = 0.0001
        XCTAssertNotEqual(try encode(space), initialSword, "Sub-display source velocity still changes the next contact")
        let movingSword = try encode(space)
        space.models[0].previousOrigin.x -= 0.25
        XCTAssertNotEqual(try encode(space), movingSword, "Swept contact must retain the previous source origin")
    }
    func testRuleAndSourceTrackChangesRemainVisibleWithUnchangedAssetIdentity() throws {
        let original = rules()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        func bytes(_ value: [String: Any]) throws -> Data {
            let rules = try JSONDecoder().decode(DuelErlangCombatRules.self, from: JSONSerialization.data(withJSONObject: value))
            var writer = try DuelReplayStateWriter(kind: 3)
            try rules.appendReplayState(to: &writer); return writer.data
        }
        let baseline = try bytes(object)
        var altered = object; altered["normalizedMagicPower"] = 1001
        XCTAssertNotEqual(try bytes(altered), baseline)
        altered = object
        var attacks = try XCTUnwrap(object["attacks"] as? [[String: Any]])
        attacks[0]["hitTags"] = ["different_source_hit"]
        altered["attacks"] = attacks; XCTAssertNotEqual(try bytes(altered), baseline)
        altered = object
        var releases = try XCTUnwrap(object["releases"] as? [[String: Any]])
        releases[0]["anchor"] = "head.x"
        altered["releases"] = releases; XCTAssertNotEqual(try bytes(altered), baseline)
        altered = object
        var controls = try XCTUnwrap(object["controls"] as? [[String: Any]])
        controls[0]["endTick"] = 4
        altered["controls"] = controls; XCTAssertNotEqual(try bytes(altered), baseline)

        func trackBytes(end: Int?, delete: Int?) throws -> Data {
            let track = DuelSummonMotionTrack(role: "diagnostic", clip: "diagnostic", frames: 2,
                sourceSHA256: String(repeating: "a", count: 64), sourceBundle: "diagnostic.bin",
                root: Array(repeating: .init(), count: 3), groundLift: [0, 0, 0],
                sourceEndEventTick: end, sourceDeleteEventTick: delete)
            var writer = try DuelReplayStateWriter(kind: 3)
            try track.appendReplayState(to: &writer); return writer.data
        }
        XCTAssertNotEqual(try trackBytes(end: nil, delete: nil), try trackBytes(end: 2, delete: nil))
        XCTAssertNotEqual(try trackBytes(end: 2, delete: nil), try trackBytes(end: 2, delete: 1))
    }
}
