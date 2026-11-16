import Foundation
import XCTest
@testable import ShiftCore

/// Actual recovered inputs are supplied locally; this is core validation, not
/// an installed App, shader, audio or physical-device acceptance result.
final class DuelRecoveredProfileTests: XCTestCase {
    private func profile(_ relativePath: String) throws -> DuelWeaponProfile {
        guard let root = ProcessInfo.processInfo.environment["FIGHTER_RECOVERED_PROFILE_ROOT"] else {
            throw XCTSkip("Actual recovered character profiles were not supplied")
        }
        let url = URL(fileURLWithPath: root).appendingPathComponent(relativePath)
        return try JSONDecoder().decode(DuelWeaponProfile.self, from: Data(contentsOf: url))
    }

    func testActualD15AbilityRulesBindEverySourceCapsuleAndSwordSlot() throws {
        let wu = try profile("erlang-runtime-v3/SF3_Erlang_Recovered_Runtime_Profile.json")
        XCTAssertEqual(wu.clips.count, 62)
        let rules = try XCTUnwrap(wu.erlangRules)
        XCTAssertEqual(rules.attacks.count, 36)
        XCTAssertEqual(rules.releases.count, 6)
        XCTAssertEqual(rules.controls?.count, 120)
        XCTAssertEqual(wu.summonTracks?.count, 15)
        try rules.validate(profile: wu)
        try XCTUnwrap(wu.combatRules).validate(for: wu)
        for track in wu.summonTracks ?? [] { try track.validate() }
        XCTAssertTrue(DuelErlangSwordMotion.matches(profile: wu))
        XCTAssertTrue(DuelSourceStunMotion.matches(profile: wu))
        XCTAssertEqual(rules.attacks.first { $0.id == "d15_axe_source_101" }?.startTick, 64)
        XCTAssertEqual(rules.attacks.first { $0.id == "d15_hound_source_93" }?.endTick, 67)
    }

    func testActualD13AndD15PairedRulesUseTheirOwnGeometry() throws {
        let liu = try profile("serpent-combat-v1/SF3_Serpent_Recovered_Combat_Profile.json")
        let wu = try profile("erlang-runtime-v3/SF3_Erlang_Recovered_Runtime_Profile.json")
        XCTAssertEqual(liu.id, "liu_serpent")
        XCTAssertEqual(liu.clips.count, 66)
        XCTAssertEqual(liu.weaponID, "wpn__shuangou_01_04")
        try XCTUnwrap(liu.ordinaryThrows).validate(for: liu, target: wu)
        try XCTUnwrap(wu.ordinaryThrows).validate(for: wu, target: liu)
        XCTAssertTrue(DuelSourceStunMotion.matches(profile: liu))
        let thrown = try XCTUnwrap(liu.clip(role: "ordinaryThrownForward"))
        XCTAssertEqual(thrown.sourceEndEventTick, 152)
        XCTAssertEqual(Set(thrown.tracks.collisionEdges?.map(\.id) ?? []),
            Set(["Shuangou_Attacking_Edge_l", "Shuangou_Attacking_Edge_r",
                 "Shuangou_Handle_Attacking_Edge_l", "Shuangou_Handle_Attacking_Edge_r"]))
        XCTAssertNotEqual(thrown.tracks.collisionEdges, wu.clip(role: "ordinaryThrownForward")?.tracks.collisionEdges)
    }

    func testRemovedSummonCannotPassTheExistingNativeRuleGate() throws {
        let wu = try profile("erlang-runtime-v3/SF3_Erlang_Recovered_Runtime_Profile.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wu)) as? [String: Any])
        var tracks = object["summonTracks"] as! [[String: Any]]
        tracks.removeAll { $0["role"] as? String == "erlangSummon_eye" }
        object["summonTracks"] = tracks
        let missing = try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try XCTUnwrap(missing.erlangRules).validate(profile: missing))
    }

    func testActualD13PhysicalWindowsCoverAllEightOriginalComboLinks() throws {
        let liu = try profile("serpent-physical-v1/SF3_Serpent_Physical_Combat_Profile.json")
        let rules = try XCTUnwrap(liu.combatRules)
        try rules.validate(for: liu)
        XCTAssertEqual(rules.attacks.count, 24)
        XCTAssertEqual(rules.attacks.reduce(0) { $0 + $1.strikes.count }, 48)
        XCTAssertEqual(liu.comboLinks?.map(\.sourceFrame), [14, 24, 33, 45, 21, 22, 41, 62])
        for command: DuelWeaponCommand in [.weapon, .weaponDown, .weaponForward] {
            var clip = try XCTUnwrap(liu.clip(command: command))
            var stages = 1
            while let link = liu.combo(from: clip.name) {
                clip = try XCTUnwrap(liu.clip(named: link.to))
                XCTAssertNotNil(rules.rule(command: command, clipName: clip.name))
                stages += 1
            }
            XCTAssertEqual(stages, command == .weapon ? 5 : command == .weaponDown ? 2 : 4)
        }
        XCTAssertNil(liu.clip(role: "shadow"), "Generic legacy skills must not impersonate D13 poison")
        XCTAssertNil(liu.clip(role: "ranged"))
        XCTAssertNotNil(liu.clip(role: "serpentPoison"))
        XCTAssertNotNil(liu.clip(role: "serpentBottle"))
    }
}
