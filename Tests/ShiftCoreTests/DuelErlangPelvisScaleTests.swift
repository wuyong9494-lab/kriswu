import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangPelvisScaleTests: XCTestCase {
    typealias State = DuelErlangPelvisScaleState
    typealias Motion = DuelErlangPelvisScaleMotion

    func testNativeWritePrecedesElapsedAndExplicitReplacementPreservesPartialValue() {
        var state = State(); state.replaceMotion(.transform4)
        for tick in 0...80 {
            if tick > 0 { state.advance(stride: 2) }
            state.sample(tick: tick)
            if tick == 70 || tick == 71 { XCTAssertEqual(state.scale, 1) }
            if tick == 72 { XCTAssertEqual(state.scale, 1.006, accuracy: 0.000001) }
        }
        XCTAssertEqual(state.scale, 1.054, accuracy: 0.000001)
        let partial = state.scale
        state.replaceMotion(nil)
        XCTAssertNil(state.tween)
        for _ in 0..<20 { state.advance(stride: 1) }
        XCTAssertEqual(state.scale.bitPattern, partial.bitPattern,
                       "Dual finish must not replace a partially applied scale with 1 or 1.12")
    }

    func testNaturalEndReverseDoesNotInventItsUnwrittenTerminalSample() {
        var state = State(); state.replaceMotion(.transform4)
        for tick in 0...169 {
            if tick > 0 { state.advance(stride: 2) }
            state.sample(tick: tick)
            if tick == 160 || tick == 168 {
                XCTAssertFalse(state.intervalEnded, "AnimationEnd/SelfEnd is not the null-ended interval's close")
                XCTAssertFalse(state.tween?.inOnly == true)
            }
        }
        XCTAssertEqual(state.scale, Motion.enlargedScale)
        XCTAssertEqual(state.tween?.duration, 5)
        XCTAssertTrue(state.tween?.inOnly == true)
        for _ in 0..<10 { state.advance(stride: 2) }
        XCTAssertNil(state.tween)
        XCTAssertEqual(state.scale, 1.012, accuracy: 0.000001,
                       "The native InOnly check follows increment; it does not add a final t=1 write")
    }

    func testSkippedIntervalEndForceBranchRemainsDistinctAndZeroFrameReturnUsesRealStep() {
        var force = State(); force.replaceMotion(.transform4)
        for tick in 0...90 {
            if tick > 0 { force.advance(stride: 2) }
            force.sample(tick: tick)
        }
        force.replaceMotion(nil, closeIntervalFirst: false)
        XCTAssertEqual(force.tween?.duration, 0)
        force.advance(stride: 2)
        XCTAssertEqual(force.scale, 1); XCTAssertNil(force.tween)

        var state = State(); state.replaceMotion(.stance)
        for tick in 0...25 {
            if tick > 0 { state.advance(stride: 2) }
            state.sample(tick: tick)
        }
        state.replaceMotion(.transformOut); state.sample(tick: 0)
        XCTAssertEqual(state.scale, Motion.enlargedScale, "IntervalStart itself does not write the bone")
        state.advance(stride: 2)
        XCTAssertEqual(state.scale, 1)
        state.replaceMotion(nil)
        XCTAssertEqual(state.scale, 1); XCTAssertNil(state.tween)
    }

    func testFloorActionsFlushAfterThePoseAndPhysicalOutEndNotAnimationEnd() {
        for motion in Motion.allCases where motion != .transformOut {
            var state = State(); state.replaceMotion(motion)
            state.sample(tick: motion.floorEventTick)
            XCTAssertEqual(state.floorOffsetCentimeters, 0, "IntervalStart queues the external setter")
            XCTAssertEqual(state.pendingFloorOffsetCentimeters, 14)
            state.flushFloorOffsetEvents()
            XCTAssertEqual(state.floorOffsetCentimeters, 14)
            state.sample(tick: motion.floorEventTick + 1)
            XCTAssertFalse(state.floorIntervalEnded, "One source frame spans two arena ticks")
            state.sample(tick: motion.floorEventTick + 2)
            XCTAssertTrue(state.floorIntervalEnded)
            state.flushFloorOffsetEvents()
            state.replaceMotion(nil); state.flushFloorOffsetEvents()
            XCTAssertEqual(state.floorOffsetCentimeters, 14, "Ordinary animation replacement keeps the actor value")

            state.replaceMotion(.transformOut); state.sample(tick: 0)
            state.flushFloorOffsetEvents()
            XCTAssertEqual(state.floorOffsetCentimeters, 14)
            XCTAssertFalse(state.floorIntervalEnded, "SelfEnd zero neither closes the interval nor clears the first pose")
            var natural = state
            natural.sample(tick: 1)
            XCTAssertEqual(natural.floorOffsetCentimeters, 14)
            XCTAssertEqual(natural.pendingFloorOffsetCentimeters, 0)
            natural.flushFloorOffsetEvents()
            XCTAssertEqual(natural.floorOffsetCentimeters, 0)

            state.replaceMotion(nil)
            XCTAssertEqual(state.floorOffsetCentimeters, 14, "The new pose is sampled before the queued Out action")
            XCTAssertEqual(state.pendingFloorOffsetCentimeters, 0)
            state.flushFloorOffsetEvents()
            XCTAssertEqual(state.floorOffsetCentimeters, 0)
            XCTAssertNil(state.pendingFloorOffsetCentimeters)
        }
    }

    private func catalog() throws -> DuelWeaponCatalog {
        let env = ProcessInfo.processInfo.environment
        guard let actor = env["ERLANG_RUNTIME_PROFILE"], let opponents = env["ERLANG_OPPONENT_CATALOG"] else {
            throw XCTSkip("Authenticated D15 body and own-rig opponent are not staged")
        }
        let decoder = JSONDecoder()
        let wu = try decoder.decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: actor)))
        let original = try decoder.decode(DuelWeaponCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: opponents)))
        return .init(schemaVersion: 1, previewFramesPerSecond: 30,
                     profiles: [wu, try XCTUnwrap(original.profile(for: .ember))])
    }

    func testAllFiveBindingsRequireTheirOriginalMotionAndTimeline() throws {
        let profile = try catalog().profiles[0]
        for motion in Motion.allCases {
            let clip = try XCTUnwrap(profile.clip(role: motion.role))
            XCTAssertEqual(Motion.binding(clip: clip, profile: profile), motion)
            let wrong = DuelWeaponClip(name: clip.name, frames: clip.frames, sha256: String(repeating: "0", count: 64),
                bundle: clip.bundle, tracks: clip.tracks, playbackTicks: clip.playbackTicks,
                sourceEndEventTick: clip.sourceEndEventTick)
            XCTAssertNil(Motion.binding(clip: wrong, profile: profile))
        }
        XCTAssertEqual(Motion.enlargedScale.bitPattern, 0x3f8f5c29)
        XCTAssertEqual(Motion.allCases.map(\.startTick), [0, 18, 70, 70, 0])
        XCTAssertEqual(Motion.allCases.map(\.floorEventTick), [2, 48, 48, 48, 0])
    }

    func testActualCastKeepsRenderedPoseHurtCapsulesAndPelvisAnchorConsistent() throws {
        let catalog = try catalog(), profile = catalog.profiles[0]
        for direction in [1, -1] {
            let x = direction == 1 ? 3000 : 9000
            var enemy = DuelGame.Fighter(hero: .ember, x: x + direction * 6000, facing: -direction)
            enemy.invulnerable = 100_000
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .wuYong, x: x, facing: direction), enemy],
                mode: .practice, difficulty: .learning, catalog: catalog, seed: 42))
            for _ in 0..<1000 where fight.sourceIntroActive { fight.step(.neutral, opponent: .neutral) }
            for _ in 0..<2400 where fight.erlangState(0)?.light != 10_000 {
                let start = fight.canUseErlang(.meditate, index: 0)
                fight.step(.init(weaponCommand: start ? .ranged : nil, rangedHeld: true), opponent: .neutral)
            }
            for _ in 0..<400 where fight.erlangState(0)?.cast != nil { fight.step(.neutral, opponent: .neutral) }
            XCTAssertTrue(fight.canUseErlang(.ascend, index: 0))
            fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
            for tick in 0...161 {
                if tick > 0 { fight.step(.neutral, opponent: .neutral) }
                let scale = try XCTUnwrap(fight.erlangPelvisScale(0))
                let pose = try XCTUnwrap(fight.fighters[0].weaponPose)
                XCTAssertEqual(pose.pelvisScale, scale.scale)
                if tick < 48 { XCTAssertEqual(pose.pelvisSourceYOffset, 0) }
                if tick == 48 {
                    XCTAssertEqual(pose.pelvisSourceYOffset, 0)
                    XCTAssertEqual(scale.floorOffsetCentimeters, 14, "Queued action flushed after the current pose and contacts")
                }
                if tick >= 49 { XCTAssertEqual(pose.pelvisSourceYOffset, 14) }
                XCTAssertNil(scale.pendingFloorOffsetCentimeters, "Completed authoritative steps have consumed their external actions")
                if tick == 70 || tick == 71 { XCTAssertEqual(scale.scale, 1) }
                if tick == 72 { XCTAssertEqual(scale.scale, 1.006, accuracy: 0.000001) }
                if tick >= 91 { XCTAssertEqual(scale.scale, Motion.enlargedScale) }
                if tick == 160 { XCTAssertFalse(scale.intervalEnded) }
                if tick == 120 {
                    let clip = try XCTUnwrap(profile.clip(named: pose.clip)), t = clip.tracks
                    let pelvis = t.sample(try XCTUnwrap(t.pelvis), phase: pose.phase)
                    let fighter = fight.fighters[0], sx = Double(fighter.x) / 1000
                    let sy = Double(fighter.y) / 1000 + pose.groundLift + Double(pose.pelvisSourceYOffset) * 0.0092
                    // Independent native-scale equation on authenticated raw FK.
                    let s = Double(Float(bitPattern: 0x3f8f5c29)), facing = Double(fighter.facing)
                    var minX = Double.infinity, maxX = -Double.infinity
                    var minY = Double.infinity, maxY = -Double.infinity
                    for capsule in try XCTUnwrap(t.hurtCapsules) {
                        let radius = Double(capsule.radiusMillimeters) / 1000
                        for track in [capsule.base, capsule.tip] {
                            let raw = t.sample(track, phase: pose.phase)
                            let x = sx + (pelvis.x + (raw.x - pelvis.x) * s) * facing
                            let y = sy + pelvis.y + (raw.y - pelvis.y) * s
                            minX = min(minX, x - radius); maxX = max(maxX, x + radius)
                            minY = min(minY, y - radius); maxY = max(maxY, y + radius)
                        }
                    }
                    let actual = fight.hurtBox(0)
                    XCTAssertEqual(actual.minX, Int(floor(minX * 1000)))
                    XCTAssertEqual(actual.maxX, Int(ceil(maxX * 1000)))
                    XCTAssertEqual(actual.minY, Int(floor(minY * 1000)))
                    XCTAssertEqual(actual.maxY, Int(ceil(maxY * 1000)))
                    XCTAssertEqual(try XCTUnwrap(fight.sourcePelvis(0)).x, sx + pelvis.x * facing, accuracy: 0.000001)
                    XCTAssertEqual(try XCTUnwrap(fight.sourcePelvis(0)).y, sy + pelvis.y, accuracy: 0.000001)
                }
            }
            XCTAssertNil(fight.erlangState(0)?.cast)
            XCTAssertNil(fight.erlangPelvisScale(0)?.tween)
            XCTAssertEqual(fight.erlangPelvisScale(0)?.scale, Motion.enlargedScale)
        }
    }
}
