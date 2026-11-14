import Foundation
import XCTest
@testable import ShiftCore

/// Source configuration identity is independent of the synthetic geometry and
/// application HP scales used here. These tests do not load original media.
final class DuelFighterRuntimeProvenanceTests: XCTestCase {
    private let sourceDigest = "02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a"

    private func panguRules(level: Int = 6) throws -> DuelPanguRules {
        try .d19HeavenlyKing(level: level, maximumHealth: 1000,
            weaponPower: 1000, unarmedPower: 1000, magicPower: 1000, rangedPower: 1000,
            spatialTemplate: DuelPanguTestFixture.rules())
    }

    func testBothRecoveredRuntimesRejectAWellFormedButDifferentConfigurationDigest() throws {
        for digest in [String(repeating: "0", count: 64), String(repeating: "d", count: 64),
                       String(sourceDigest.dropLast()) + "b"] {
            var sun = try DuelTriadTestFixture.runtimeRules()
            sun.runtime?.configurationSHA256 = digest
            XCTAssertThrowsError(try sun.validate()) {
                XCTAssertEqual($0 as? DuelTriadRules.ValidationError, .provenance)
            }
            XCTAssertNil(DuelTriadState(rules: sun, seed: 31),
                         "Reject a mixed source revision before it can silently lose its original stance")

            var liu = try panguRules()
            liu.runtime?.configurationSHA256 = digest
            XCTAssertThrowsError(try liu.validate()) {
                XCTAssertEqual($0 as? DuelPanguRules.ValidationError, .provenance)
            }
            XCTAssertNil(DuelPanguState(rules: liu, seed: 31))
        }
    }

    func testCorrectSharedConfigurationDoesNotMakeTheTwoCharacterVersionsInterchangeable() throws {
        let sun = try DuelTriadTestFixture.runtimeRules(), liu = try panguRules()
        XCTAssertEqual(sun.runtime?.configurationSHA256, sourceDigest)
        XCTAssertEqual(liu.runtime?.configurationSHA256, sourceDigest)
        var wrongSun = sun, wrongLiu = liu
        wrongSun.runtime?.evidence.version = try XCTUnwrap(liu.runtime?.version)
        wrongLiu.runtime?.version = try XCTUnwrap(sun.runtime?.evidence.version)
        XCTAssertThrowsError(try wrongSun.validate())
        XCTAssertThrowsError(try wrongLiu.validate())
        XCTAssertNil(DuelTriadState(rules: wrongSun, seed: 31))
        XCTAssertNil(DuelPanguState(rules: wrongLiu, seed: 31))
    }

    func testReviewedFactoriesRemainLoadableAfterJSONRoundTripAtEverySupportedLevel() throws {
        for level in 1...6 {
            let sun = try JSONDecoder().decode(DuelTriadRules.self,
                from: JSONEncoder().encode(DuelTriadTestFixture.runtimeRules(level: level)))
            let liu = try JSONDecoder().decode(DuelPanguRules.self,
                from: JSONEncoder().encode(panguRules(level: level)))
            try sun.validate(); try liu.validate()
            XCTAssertNotNil(DuelTriadState(rules: sun, seed: 31))
            XCTAssertNotNil(DuelPanguState(rules: liu, seed: 31))
            XCTAssertEqual(sun.runtime?.configurationSHA256, sourceDigest)
            XCTAssertEqual(liu.runtime?.configurationSHA256, sourceDigest)
        }
    }

    func testExplicitApplicationProfilesWithoutRecoveredRuntimeStillLoad() throws {
        let sun = DuelTriadTestFixture.rules(), liu = DuelPanguTestFixture.rules()
        XCTAssertNil(sun.runtime); XCTAssertNil(liu.runtime)
        try sun.validate(); try liu.validate()
        XCTAssertNotNil(DuelTriadState(rules: sun, seed: 31))
        XCTAssertNotNil(DuelPanguState(rules: liu, seed: 31))
    }
}
