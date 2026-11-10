import XCTest
@testable import ShiftCore

/// Reflection is test-only: additions to stored state must update both the
/// explicit production encoder and its source audit. Reflection never encodes.
final class DuelReplayStateAuditTests: XCTestCase {
    private func fields(_ value: Any, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Mirror(reflecting: value).children.compactMap(\.label).sorted(), expected.sorted(),
                       "Stored state changed. Review the replay encoder and coverage document.", file: file, line: line)
    }

    func testCompleteStoredPropertyInventoryIncludingPrivateFields() throws {
        let catalog = DuelWeaponTestFixtures.catalog()
        var game = DuelGame(weaponCatalog: catalog)
        game.step(.init(weaponCommand: .weapon), opponent: .neutral)
        let fight = try XCTUnwrap(game.weaponFight)
        fields(game, ["selectedHero", "difficulty", "mode", "fighters", "projectiles", "grapple", "phase",
                      "frame", "remainingTicks", "wins", "hitStop", "events", "landedHits", "damageDealt",
                      "weaponFight", "random", "nextProjectile", "botHeld", "buffered", "opponentHero", "weaponModeRequested"])
        fields(fight, ["profiles", "fighters", "phase", "frame", "remainingTicks", "wins", "hitStop", "landedHits",
                       "damageDealt", "events", "contacts", "swings", "mode", "difficulty", "actions", "queued",
                       "loopTicks", "loopRoles", "previousX", "random", "shadowCooldowns"])
        fields(game.fighters[0], ["hero", "x", "y", "velocityY", "facing", "health", "guardMeter", "energy", "stun",
                                 "knockdown", "invulnerable", "guarding", "attack", "flash", "walking",
                                 "movementDirection", "weaponPose"])
        fields(DuelGame.Input.neutral, ["move", "guardHeld", "taps", "vertical", "weaponCommand"])
        fields(DuelGame.Buttons.light, ["rawValue"])
        fields(try XCTUnwrap(game.fighters[0].attack), ["move", "age", "connected", "spawned", "comboQueued"])
        fields(DuelGame.Projectile(id: 1, owner: 0, x: 4000, direction: 1), ["id", "owner", "x", "direction", "lifetime"])
        fields(DuelGame.Grapple(attacker: 0, direction: 1), ["attacker", "direction", "age"])
        fields(try XCTUnwrap(game.fighters[0].weaponPose), ["clip", "tick", "duration", "groundLift", "reaction"])
        fields(DuelWeaponPoint(), ["x", "y", "z"])
        fields(DuelWeaponFight.Contact(kind: .hit, attacker: 0, position: .init(), direction: 1, heavy: false, usesWeapon: true),
               ["kind", "attacker", "position", "direction", "heavy", "usesWeapon"])
        fields(DuelWeaponFight.Swing(attacker: 0, heavy: false, usesWeapon: true), ["attacker", "heavy", "usesWeapon"])
        // Action intentionally stays private, including in test code.
        let actions = try XCTUnwrap(Mirror(reflecting: fight).children.first { $0.label == "actions" }?.value)
        let firstOptional = try XCTUnwrap(Mirror(reflecting: actions).children.first?.value)
        let action = try XCTUnwrap(Mirror(reflecting: firstOptional).children.first?.value)
        fields(action, ["name", "role", "command", "tick", "hits", "touching", "sounded", "reaction", "comboDepth", "soundAt", "shadowOriginX"])

        fields(catalog, ["schemaVersion", "previewFramesPerSecond", "sourceFramesPerSecond", "profiles"])
        fields(catalog.profiles[0], ["id", "hero", "faction", "resourceName", "bytes", "sha256", "bodyID", "weaponID",
                                     "activeWeaponSides", "roles", "clips", "comboLinks"])
        fields(catalog.profiles[0].clips[0], ["name", "frames", "sha256", "bundle", "tracks"])
        fields(catalog.profiles[0].clips[0].tracks, ["samplesPerSourceFrame", "root", "handL", "handR", "footL", "footR",
                                                   "weaponBaseL", "weaponTipL", "weaponBaseR", "weaponTipR", "groundLift"])
        fields(DuelWeaponComboLink(from: "a", to: "b", sourceFrame: 1), ["from", "to", "sourceFrame"])
    }
}
