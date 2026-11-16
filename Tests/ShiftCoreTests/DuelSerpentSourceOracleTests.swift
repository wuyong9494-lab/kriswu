import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentSourceOracleTests: XCTestCase {
    private struct Oracle: Decodable {
        struct Row: Decodable {
            let level: Int
            let amplifier: Double
            let channel: String
            let damage: Double
            let poison: Double
            let duration: Int
            let bloom: Double
            let cooldown: Int
            let explosion: Double
        }
        let schema: String
        let receiptSHA256: String
        let cases: [Row]
    }
    func testActualOriginalRPNMatchesFourChannelsAcrossLevelsAndRaidAmplifiers() throws {
        guard let path = ProcessInfo.processInfo.environment["SERPENT_STATE_ORACLE"] else {
            throw XCTSkip("Authenticated original D13 arithmetic oracle not supplied")
        }
        let oracle = try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(oracle.schema, "d13-state-source-oracle-v1")
        XCTAssertEqual(oracle.receiptSHA256, "d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37")
        XCTAssertEqual(oracle.cases.count, 64)
        for row in oracle.cases {
            let channel = try XCTUnwrap(DuelSerpentState.Channel(rawValue: row.channel))
            var state = try XCTUnwrap(DuelSerpentState(level: row.level, raidDamageAmplifier: row.amplifier))
            state.beginRound()
            for _ in 0..<2 {
                state.outgoingContact(channel: channel, sourceDamage: row.damage,
                    perks: .init(poison: 0.02, cobraDance: 0.03, venomousLimbs: 0.04, secretRitual: 0.05))
            }
            XCTAssertEqual(state.poison(channel).amount, row.poison, accuracy: 1e-12)
            XCTAssertEqual(state.poison(channel).remainingTicks, row.duration)
            XCTAssertEqual(state.bloom, row.bloom, accuracy: 1e-12)
            XCTAssertEqual(state.poisonAbilityCooldownTicks, row.cooldown)
            XCTAssertEqual(state.poisonExplosionDamage(targetInvincible: false), row.explosion, accuracy: 1e-12)
        }
    }
}
