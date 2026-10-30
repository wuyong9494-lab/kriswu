import XCTest
@testable import ShiftReminder

@MainActor
final class ArenaDiagnosticsTests: XCTestCase {
    func testQualitySampleUsesDeclaredMapWithoutBenchmarkOrRankedRules() {
        let controller = ArenaController(setup: .init(mode: .zone, brawler: .ranger,
            name: "样板", qualitySample: true), seed: 7)
        XCTAssertEqual(controller.game.map.id, ArenaMap.twinGates.id)
        XCTAssertFalse(controller.benchmark)
        XCTAssertFalse(controller.ranked)
        XCTAssertEqual(controller.game.fighters.count, 6)
        controller.advance(ArenaController.introLength + 0.1)
        controller.move = V2(0, -1)
        let start = controller.mine.pos
        for _ in 0..<30 { controller.advance(1.0 / 60) }
        XCTAssertNotEqual(controller.mine.pos, start)
        XCTAssertGreaterThan(controller.game.time, 0)
    }

    func testHarborCaptureUsesClearFixedPositionsAndPreservesCanyonComparison() {
        let harbor = ArenaController(setup: .init(mode: .zone, brawler: .ranger,
            name: "截图", benchmark: true, qualitySample: true, benchmarkTwinGates: true), seed: 7)
        XCTAssertEqual(harbor.game.map.id, ArenaMap.twinGates.id)
        XCTAssertTrue(harbor.benchmark)
        XCTAssertTrue(harbor.qualitySample)
        XCTAssertEqual(harbor.game.fighters.count, 6)
        for fighter in harbor.game.fighters {
            XCTAssertFalse(harbor.game.map.collides(fighter.pos, radius: ArenaGame.fighterRadius))
        }
        let repeatCapture = ArenaController(setup: .init(mode: .zone, brawler: .ranger,
            name: "截图", benchmark: true, qualitySample: true, benchmarkTwinGates: true), seed: 99)
        XCTAssertEqual(harbor.game.fighters.map(\.pos), repeatCapture.game.fighters.map(\.pos))
        let canyon = ArenaController(setup: .init(mode: .zone, brawler: .ranger,
            name: "对照", benchmark: true, qualitySample: true), seed: 7)
        XCTAssertEqual(canyon.game.map.id, ArenaMap.canyon.id)
    }

    func testAudioDiagnosticRetainsCombatSimulation() {
        let old = ArenaDiagnostics.shared.variant, enabled = ArenaDiagnostics.shared.enabled
        defer { ArenaDiagnostics.shared.configureCapture(old, enabled: enabled) }
        func simulate(_ variant: ArenaDiagnostics.Variant) -> ArenaController {
            ArenaDiagnostics.shared.configureCapture(variant)
            let controller = make(.combat)
            controller.advance(ArenaController.introLength + 0.1)
            for _ in 0..<180 { controller.advance(1.0 / 60) }
            return controller
        }
        let baseline = simulate(.baseline)
        let silent = simulate(.noEffectAudio)
        XCTAssertEqual(silent.game.fighters.map(\.pos), baseline.game.fighters.map(\.pos))
        XCTAssertEqual(silent.game.fighters.map(\.health), baseline.game.fighters.map(\.health))
        XCTAssertEqual(silent.game.projectiles.count, baseline.game.projectiles.count)
        XCTAssertEqual(silent.game.time, baseline.game.time)
    }

    func testPooledEffectsExpireAndReuseWithoutRendererCallbacks() {
        let old = ArenaDiagnostics.shared.variant, enabled = ArenaDiagnostics.shared.enabled
        defer { ArenaDiagnostics.shared.configureCapture(old, enabled: enabled) }
        ArenaDiagnostics.shared.configureCapture(.baseline)
        let view = ArenaWorldView(controller: make(.empty))
        // No display link or render queue is running. Pool ownership must still
        // expire deterministically, including repeated reuse of the same nodes.
        for _ in 0..<30 {
            view.emitDiagnosticPooledEffects()
            XCTAssertEqual(view.diagnosticBusyFXCount, 5)
            view.advanceDiagnosticEffects(by: 0.1)
            XCTAssertEqual(view.diagnosticBusyFXCount, 5)
            view.advanceDiagnosticEffects(by: 0.16)
            XCTAssertEqual(view.diagnosticBusyFXCount, 2)
            view.advanceDiagnosticEffects(by: 1)
            XCTAssertEqual(view.diagnosticBusyFXCount, 0)
        }
    }

    func testManualTraversalKeepsUserInputAndHasNoBots() {
        let controller = make(.manualTraversal)
        XCTAssertEqual(controller.game.fighters.count, 1)
        controller.advance(ArenaController.introLength + 0.1)
        let start = controller.mine.pos
        controller.move = V2(1, 0)
        for _ in 0..<30 { controller.advance(1.0 / 60) }
        XCTAssertNotEqual(controller.mine.pos, start)
        controller.move = .zero
        let stopped = controller.mine.pos
        for _ in 0..<30 { controller.advance(1.0 / 60) }
        XCTAssertEqual(controller.mine.pos, stopped)
        XCTAssertTrue(controller.game.projectiles.isEmpty)
    }

    private func make(_ scenario: ArenaDiagnosticScenario) -> ArenaController {
        ArenaController(setup: .init(mode: .zone, brawler: .ranger, name: "测试", level: 3,
            loadout: .basic(.ranger, level: 3), benchmark: true, diagnosticScenario: scenario))
    }
    func testNonCombatScenariosMoveWithoutFiring() {
        let old = ArenaDiagnostics.shared.variant, enabled = ArenaDiagnostics.shared.enabled
        defer { ArenaDiagnostics.shared.configureCapture(old, enabled: enabled) }
        ArenaDiagnostics.shared.configureCapture(.baseline)
        for scenario in [ArenaDiagnosticScenario.empty, .soloWalk, .crowdWalk] {
            let controller = make(scenario)
            let start = controller.mine.pos
            controller.advance(ArenaController.introLength + 0.1)
            for _ in 0..<90 {
                controller.advance(1.0 / 60)
                XCTAssertTrue(controller.game.projectiles.isEmpty)
            }
            if scenario == .soloWalk { XCTAssertNotEqual(controller.mine.pos, start) }
            if scenario == .empty { XCTAssertEqual(controller.mine.pos, start) }
        }
    }
    func testNoAILeavesCrowdStationaryWithoutChangingRoster() {
        let old = ArenaDiagnostics.shared.variant, enabled = ArenaDiagnostics.shared.enabled
        defer { ArenaDiagnostics.shared.configureCapture(old, enabled: enabled) }
        ArenaDiagnostics.shared.configureCapture(.noAI)
        let controller = make(.combat)
        let positions = controller.game.fighters.map(\.pos)
        XCTAssertEqual(positions.count, 6)
        controller.advance(ArenaController.introLength + 0.1)
        for _ in 0..<120 { controller.advance(1.0 / 60) }
        XCTAssertEqual(controller.game.fighters.map(\.pos), positions)
        XCTAssertTrue(controller.game.projectiles.isEmpty)
    }
    func testManualCaptureExportsInputAndCompletesOneCase() throws {
        let recorder = ArenaPerfRecorder.shared
        recorder.beginSuite(variant: .baseline, seconds: 10, expectedCases: 1)
        defer { recorder.stop() }
        recorder.beginCase(.manualTraversal)
        let controller = make(.manualTraversal)
        controller.move = V2(0.5, -0.25)
        for _ in 0..<850 {
            recorder.record(controller: controller, interval: 1.0 / 60, simulation: 0.001, scene: 0.003,
                            battleDrivers: 1, lobbyDrivers: 0)
        }
        let file = try recorder.export()
        defer { try? FileManager.default.removeItem(at: file) }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(object["complete"] as? Bool, true)
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1)
        let frames = try XCTUnwrap(results[0]["frames"] as? [[Double]])
        XCTAssertEqual(frames.first?[13], 0.5)
        XCTAssertEqual(frames.first?[14], -0.25)
        XCTAssertEqual(frames.first?[15], 1)
    }

    func testInterruptedCaptureExportsRawFramesAndUnmeasuredGPU() throws {
        let recorder = ArenaPerfRecorder.shared
        recorder.beginSuite(variant: .baseline, seconds: 10)
        defer { recorder.stop() }
        recorder.beginCase(.soloWalk)
        let controller = make(.soloWalk)
        for _ in 0..<240 {
            recorder.record(controller: controller, interval: 1.0 / 60, simulation: 0.001, scene: 0.003, battleDrivers: 1, lobbyDrivers: 0)
        }
        recorder.interrupt("test interruption")
        let file = try recorder.export()
        defer { try? FileManager.default.removeItem(at: file) }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(object["complete"] as? Bool, false)
        XCTAssertEqual(object["gpu_ms"] as? String, "unmeasured")
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        let frames = try XCTUnwrap(results.first?["frames"] as? [[Double]])
        XCTAssertGreaterThan(frames.count, 50)
        XCTAssertEqual(frames.first?.count, 16)
        XCTAssertEqual(object["schema"] as? Int, 2)
        XCTAssertEqual((object["frame_columns"] as? [String])?.count, 16)
        XCTAssertEqual(frames.first?[1] ?? 0, 1000.0 / 60, accuracy: 0.001)
    }
}
