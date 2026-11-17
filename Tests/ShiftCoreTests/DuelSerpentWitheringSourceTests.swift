import Foundation
import XCTest
@testable import ShiftCore

/// Local resource acceptance: the oracle is produced by the bounded original
/// lock reader, independently of this Swift runtime. Kept out of source-only CI.
final class DuelSerpentWitheringSourceTests: XCTestCase {
    private struct Oracle: Decodable {
        struct Factor: Decodable { let stacks: Int; let multiplier: Double }
        struct Range: Decodable { let distance: Double; let gains, decays: Bool }
        let schema, sourceSHA256: String
        let auraThreshold, distanceSourceUnits: Double
        let gainPeriod, decayPeriod, maximumStacks: Int
        let factorCases: [Factor]
        let rangeCases: [Range]
        let sourceDamageChannels: [String]
        let genericTriggerInterpreter: Bool
    }

    func testOriginalLockOracleAgreesWithAllLayerFactorsAndExactRangeBranches() throws {
        guard let path = ProcessInfo.processInfo.environment["SERPENT_WITHERING_ORACLE"] else {
            throw XCTSkip("Authenticated lock 1396 Withering oracle required")
        }
        let oracle = try JSONDecoder().decode(Oracle.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(oracle.schema, "d13-withering-source-oracle-v1")
        XCTAssertEqual(oracle.sourceSHA256, "941b17f2617d37d6bb0a252332d547c1aa740e61aa45f91b0705a646fbf4f354")
        XCTAssertFalse(oracle.genericTriggerInterpreter)
        XCTAssertEqual(oracle.sourceDamageChannels,
            ["Factor_WeaponDamage", "Factor_UnarmedDamage", "Factor_RangedDamage", "Factor_MagicPower"])
        XCTAssertEqual(oracle.factorCases.count, oracle.maximumStacks + 1)
        XCTAssertEqual(oracle.rangeCases.count, 5)
        var state = DuelSerpentWitheringState()
        state.observeBloom(oracle.auraThreshold, level: 4)
        for expected in oracle.factorCases {
            let end = expected.stacks * oracle.gainPeriod
            while state.liveTick < end {
                XCTAssertTrue(state.advance(liveTick: state.liveTick + 1, ownerCOMX: 0, targetCOMX: 0))
            }
            XCTAssertEqual(state.targetStacks, expected.stacks)
            for kind in [DuelTriadRules.DamageKind.weapon, .unarmed, .shadow] {
                XCTAssertEqual(state.targetDamageFactor(kind), expected.multiplier, accuracy: 1e-12)
            }
            XCTAssertEqual(state.targetDamageFactor(.trueDamage), 1)
            XCTAssertEqual(state.suppressesTargetCritical, expected.stacks > 0)
        }
        for expected in oracle.rangeCases {
            var gain = DuelSerpentWitheringState()
            gain.observeBloom(oracle.auraThreshold, level: 4)
            for tick in 1...oracle.gainPeriod {
                XCTAssertTrue(gain.advance(liveTick: tick, ownerCOMX: 0, targetCOMX: expected.distance))
            }
            XCTAssertEqual(gain.targetStacks, expected.gains ? 1 : 0)
            var decay = DuelSerpentWitheringState()
            decay.observeBloom(oracle.auraThreshold, level: 4)
            for tick in 1...oracle.gainPeriod {
                XCTAssertTrue(decay.advance(liveTick: tick, ownerCOMX: 0, targetCOMX: 0))
            }
            for tick in (oracle.gainPeriod + 1)...(oracle.gainPeriod + oracle.decayPeriod) {
                XCTAssertTrue(decay.advance(liveTick: tick, ownerCOMX: 0, targetCOMX: -expected.distance))
            }
            XCTAssertEqual(decay.targetStacks, expected.decays ? 0 : 1)
        }
    }
}
