import XCTest
@testable import ShiftReminder

@MainActor
final class ArenaDiagnosticsTests: XCTestCase {
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
        XCTAssertEqual(frames.first?.count, 11)
        XCTAssertEqual(frames.first?[1] ?? 0, 1000.0 / 60, accuracy: 0.001)
    }
}
