import Foundation
import XCTest
@testable import ShiftCore

/// Real private inputs and original compressed-motion FK are required. These
/// tests do not manufacture a Liu hammer profile that merely says "serpent".
final class DuelSerpentBottlePresentationTests: XCTestCase {
    private struct Oracle: Decodable {
        struct Sample: Decodable { let tick: Int; let root, left, right: [Double] }
        let schema, modelSHA256, profileSHA256: String
        let samples: [Sample]
    }
    private func data(_ key: String) throws -> Data {
        guard let path = ProcessInfo.processInfo.environment[key] else {
            throw XCTSkip("Authenticated D13 source input required: \(key)")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
    private func profile(_ key: String = "SERPENT_MATCH_PROFILE") throws -> DuelWeaponProfile {
        try JSONDecoder().decode(DuelWeaponProfile.self, from: data(key))
    }
    private func runtime(_ profile: DuelWeaponProfile) throws -> DuelSerpentRainRuntime {
        let binding = try XCTUnwrap(profile.serpentBinding)
        try binding.validate(profile: profile)
        var value = try DuelSerpentRainRuntime(binding: .init(profile: profile), bottleMotion: binding.bottle,
            level: binding.level, raidDamageAmplifier: binding.raidDamageAmplifier,
            rangedUsagesLeft: binding.rangedUsages, cloudMotion: binding.cloud)
        value.beginRound()
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1))
        return value
    }
    private func scene(owner: Double = 350, direction: Int = 1, repulsion: Double = 0) -> DuelSerpentRainRuntime.Scene {
        .init(ownerPelvisX: owner, ownerCOMX: owner, targetCOMX: 550,
              direction: direction, bottleRepulsionX: repulsion)
    }
    private func encoded(_ value: DuelSerpentRainRuntime) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 3)
        try value.appendReplayState(to: &writer)
        return writer.data
    }
    private func assertPoint(_ value: DuelWeaponPoint, _ expected: DuelWeaponPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value.x, expected.x, accuracy: 0.00002, file: file, line: line)
        XCTAssertEqual(value.y, expected.y, accuracy: 0.00002, file: file, line: line)
        XCTAssertEqual(value.z, expected.z, accuracy: 0.00002, file: file, line: line)
    }

    func testOriginalCompressedMotionFKProjectsIntoExistingArenaBothDirectionsWithoutDoubleRoot() throws {
        let profile = try profile()
        let oracle = try JSONDecoder().decode(Oracle.self, from: data("SERPENT_BOTTLE_PRESENTATION_ORACLE"))
        XCTAssertEqual(oracle.schema, "d13-bottle-presentation-source-oracle-v1")
        XCTAssertEqual(oracle.modelSHA256, DuelSerpentBottlePresentation.fileSHA256)
        XCTAssertEqual(oracle.profileSHA256, "ca44aec355d6c70487df550a818112172a897bc64a0bbaa143748045a8284e53")
        XCTAssertEqual(oracle.samples.count, 49)
        for direction in [-1, 1] {
            var value = try runtime(profile)
            for tick in 1..<56 {
                _ = try XCTUnwrap(value.step(liveTick: tick, scene: scene(direction: direction), targetInvincible: false))
                guard tick >= 8 else {
                    XCTAssertNil(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: value)); continue
                }
                let frame = try XCTUnwrap(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: value))
                XCTAssertEqual(frame.motionTick, tick - 8)
                XCTAssertEqual(frame.animationTime, Double(tick - 8) / 60)
                let original = oracle.samples[tick - 8]
                XCTAssertEqual(original.tick, frame.motionTick)
                let runtimeSample = try XCTUnwrap(value.bottleSample())
                for (source, bound) in [(original.root, runtimeSample.root), (original.left, runtimeSample.left),
                                       (original.right, runtimeSample.right)] {
                    let expected = try XCTUnwrap(value.bottleWorldPoint(bound))
                    assertPoint(frame.worldPoint(sourceMeters: .init(x: source[0], y: source[1], z: source[2])),
                        .init(x: expected.x * 0.0092, y: expected.y * 0.0092, z: expected.z * 0.0092))
                }
                if tick == 8 {
                    let root = original.root
                    XCTAssertEqual(frame.worldPoint(sourceMeters: .init(x: root[0], y: root[1], z: root[2])).x,
                                   350 * 0.0092, accuracy: 0.00002)
                }
            }
            _ = try XCTUnwrap(value.step(liveTick: 56, scene: scene(direction: direction), targetInvincible: false))
            XCTAssertNotNil(value.pendingCloud)
            XCTAssertNil(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: value),
                         "The source end tick requests a cloud and removes the bottle before drawing")
        }
    }

    func testBornBottleDoesNotFollowLaterOwnerMovementOrFacingButKeepsSourceRepulsion() throws {
        let profile = try profile()
        var value = try runtime(profile)
        for tick in 1...8 { _ = try XCTUnwrap(value.step(liveTick: tick, scene: scene(), targetInvincible: false)) }
        let first = try XCTUnwrap(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: value))
        for tick in 9...20 {
            _ = try XCTUnwrap(value.step(liveTick: tick,
                scene: scene(owner: -1200, direction: -1, repulsion: tick == 12 ? 5 : 0), targetInvincible: false))
            let frame = try XCTUnwrap(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: value))
            XCTAssertEqual(frame.direction, 1)
            XCTAssertEqual(frame.origin.x, first.origin.x + (tick >= 12 ? 5 * 0.0092 : 0), accuracy: 1e-12)
            XCTAssertEqual(frame.id, first.id)
        }
    }

    func testDisplayReadsCannotAdvanceModelsConsumeUsesMutateDamageOrChangeReplay() throws {
        let profile = try profile()
        var value = try runtime(profile)
        for tick in 1...31 { _ = try XCTUnwrap(value.step(liveTick: tick, scene: scene(), targetInvincible: false)) }
        let before = try encoded(value)
        let first = try XCTUnwrap(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: value))
        for _ in 0..<120 {
            XCTAssertEqual(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: value), first)
        }
        XCTAssertEqual(try encoded(value), before)
        XCTAssertEqual(value.actions.rangedUsagesLeft, 0)
        XCTAssertNil(value.pendingCloud)
        XCTAssertNil(value.cloud)
    }

    func testInterruptionExplicitDeletionAndRoundEndUseAuthoritativeLifetime() throws {
        let profile = try profile()
        var early = try runtime(profile)
        for tick in 1...7 { _ = try XCTUnwrap(early.step(liveTick: tick, scene: scene(), targetInvincible: false)) }
        XCTAssertTrue(early.interrupt(playbackID: 1))
        _ = try XCTUnwrap(early.step(liveTick: 8, scene: scene(), targetInvincible: false))
        XCTAssertNil(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: early))
        var late = try runtime(profile)
        for tick in 1...8 { _ = try XCTUnwrap(late.step(liveTick: tick, scene: scene(), targetInvincible: false)) }
        XCTAssertTrue(late.interrupt(playbackID: 1))
        XCTAssertNotNil(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: late))
        var removed = late
        XCTAssertNotNil(removed.removeModel(.bottle, id: 1))
        XCTAssertNil(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: removed))
        XCTAssertNil(removed.pendingCloud)
        for tick in 9..<56 {
            _ = try XCTUnwrap(late.step(liveTick: tick, scene: scene(), targetInvincible: false))
            XCTAssertNotNil(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: late))
        }
        late.endRound()
        XCTAssertNil(DuelSerpentBottlePresentation.frame(owner: 0, profile: profile, runtime: late))
        XCTAssertNil(late.pendingCloud)
    }

    func testCorrectDisplayNameCannotAuthenticateLegacyOrMismatchedSourceEquipment() throws {
        let raw = try data("SERPENT_MATCH_PROFILE")
        let original = try JSONDecoder().decode(DuelWeaponProfile.self, from: raw)
        XCTAssertEqual(original.title, "刘泉纬")
        XCTAssertTrue(DuelSerpentBottlePresentation.accepts(original))
        for (key, changed) in [("id", "liu_hammers"), ("id", "liu_pangu"), ("hero", "ember"),
                               ("bodyID", "arm__str_03"), ("weaponID", "wpn__hammers_01_01"),
                               ("sha256", String(repeating: "0", count: 64))] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            object[key] = changed
            let fake = try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertFalse(DuelSerpentBottlePresentation.accepts(fake), "Changed \(key)")
        }
    }

    func testRealFightRangedInputDrawsOnlyAuthoritativeBottleAndLeavesReplayByteIdentical() throws {
        let liu = try profile(), wu = try profile("ERLANG_MATCH_PROFILE")
        let catalog = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            sourceFramesPerSecond: 60, profiles: [liu, wu])
        try catalog.validate()
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .liu, x: 3500, facing: 1), .init(hero: .wuYong, x: 5300, facing: -1)
        ], mode: .practice, difficulty: .learning, catalog: catalog, seed: 19))
        XCTAssertTrue(DuelSerpentBottlePresentation.frames(in: fight).isEmpty)
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        for tick in 1...56 {
            fight.step(.neutral, opponent: .neutral)
            let before = try [8, 31, 56].contains(tick) ? DuelReplayStateEncoding.encode(fight) : nil
            let expectedCount = (8..<56).contains(tick) ? 1 : 0
            for _ in 0..<3 {
                let frames = DuelSerpentBottlePresentation.frames(in: fight)
                XCTAssertEqual(frames.count, expectedCount)
                if let frame = frames.first {
                    XCTAssertEqual(frame.owner, 0)
                    XCTAssertEqual(frame.motionTick, tick - 8)
                }
            }
            if let before { XCTAssertEqual(try DuelReplayStateEncoding.encode(fight), before) }
            XCTAssertEqual(fight.landedHits[0], 0)
        }
        XCTAssertTrue(DuelSerpentBottlePresentation.frames(in: fight).isEmpty)
    }
}
