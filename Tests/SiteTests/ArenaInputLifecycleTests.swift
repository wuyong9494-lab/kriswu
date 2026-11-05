import XCTest
@testable import ShiftReminder

@MainActor
final class ArenaInputLifecycleTests: XCTestCase {
    private func make(mode: ArenaGame.Mode = .teamFight,
                      scenario: ArenaDiagnosticScenario = .manualTraversal) -> ArenaController {
        ArenaController(setup: .init(mode: mode, brawler: .ranger, name: "Input regression", level: 3,
            loadout: .basic(.ranger, level: 3), benchmark: true, diagnosticScenario: scenario))
    }

    private func enterMatch(_ controller: ArenaController) {
        controller.advance(ArenaController.introLength + 0.1)
        XCTAssertFalse(controller.showingIntro)
        _ = controller.takeEvents()
    }

    private func queueControls(_ controller: ArenaController) {
        controller.setMovement(V2(1, 0))
        controller.setAim(V2(1, 0))
        controller.setAim(V2(1, 0), special: true)
        controller.fire(V2(1, 0))
        controller.fireSpecial(V2(1, 0))
        controller.fireGadget()
        controller.emote(0)
    }

    private func actionEvents(_ controller: ArenaController) -> [ArenaGame.Event] {
        controller.takeEvents().filter {
            switch $0 {
            case .attack(let id), .special(let id), .gadget(let id), .hyper(let id): return id == controller.me
            case .emote(let id, _): return id == controller.me
            default: return false
            }
        }
    }

    func testIntroRejectsCommandsAndClearsHeldMovementBeforeCombat() {
        let controller = make()
        let position = controller.mine.pos, ammo = controller.mine.ammo
        let uses = controller.mine.gadgetUses
        queueControls(controller)
        enterMatch(controller)
        controller.advance(ArenaController.step)
        XCTAssertEqual(controller.mine.pos, position)
        XCTAssertEqual(controller.mine.ammo, ammo)
        XCTAssertEqual(controller.mine.gadgetUses, uses)
        XCTAssertTrue(actionEvents(controller).isEmpty)

        controller.fire(V2(1, 0))
        controller.advance(ArenaController.step)
        XCTAssertLessThan(controller.mine.ammo, ammo)
        XCTAssertTrue(actionEvents(controller).contains(.attack(fighter: controller.me)))
    }

    func testDialogDropsAlreadyQueuedAttackGadgetAndEmote() {
        let controller = make()
        enterMatch(controller)
        let position = controller.mine.pos, ammo = controller.mine.ammo
        let uses = controller.mine.gadgetUses
        XCTAssertGreaterThan(uses, 0)
        queueControls(controller)
        controller.setInputPaused(true, for: .dialog)
        XCTAssertEqual(controller.move, .zero)
        XCTAssertNil(controller.aiming)
        XCTAssertNil(controller.superAiming)
        controller.advance(ArenaController.step)
        XCTAssertEqual(controller.mine.pos, position)
        XCTAssertEqual(controller.mine.ammo, ammo)
        XCTAssertEqual(controller.mine.gadgetUses, uses)
        XCTAssertTrue(actionEvents(controller).isEmpty)
        controller.setInputPaused(false, for: .dialog)
        controller.advance(ArenaController.step)
        XCTAssertTrue(actionEvents(controller).isEmpty)
        XCTAssertEqual(controller.mine.gadgetUses, uses)
    }

    func testLateGestureCallbacksCannotReplayAfterDialogCloses() {
        let controller = make()
        enterMatch(controller)
        let position = controller.mine.pos, ammo = controller.mine.ammo
        controller.setInputPaused(true, for: .dialog)
        queueControls(controller) // stale SwiftUI closure after its stick was removed
        controller.advance(ArenaController.step)
        XCTAssertEqual(controller.mine.pos, position)
        XCTAssertEqual(controller.mine.ammo, ammo)
        XCTAssertTrue(actionEvents(controller).isEmpty)
        queueControls(controller) // another callback immediately before dismissal
        controller.setInputPaused(false, for: .dialog)
        controller.advance(ArenaController.step)
        XCTAssertEqual(controller.move, .zero)
        XCTAssertNil(controller.aiming)
        XCTAssertNil(controller.superAiming)
        XCTAssertEqual(controller.mine.pos, position)
        XCTAssertTrue(actionEvents(controller).isEmpty)

        controller.move = V2(1, 0)
        controller.fire(V2(1, 0)); controller.emote(0)
        controller.advance(ArenaController.step)
        XCTAssertNotEqual(controller.mine.pos, position)
        let events = actionEvents(controller)
        XCTAssertTrue(events.contains(.attack(fighter: controller.me)))
        XCTAssertTrue(events.contains(.emote(fighter: controller.me, emote: 0)))
    }

    func testDialogAndRendererPausesMustBothClearInEitherOrder() {
        for first in [ArenaController.InputPause.dialog, .renderer] {
            let second: ArenaController.InputPause = first == .dialog ? .renderer : .dialog
            let controller = make()
            enterMatch(controller)
            let position = controller.mine.pos, ammo = controller.mine.ammo
            controller.setInputPaused(true, for: first)
            controller.setInputPaused(true, for: second)
            controller.setInputPaused(false, for: first)
            queueControls(controller)
            controller.advance(ArenaController.step)
            XCTAssertEqual(controller.mine.pos, position)
            XCTAssertEqual(controller.mine.ammo, ammo)
            XCTAssertTrue(actionEvents(controller).isEmpty)
            controller.setInputPaused(false, for: second)
            controller.advance(ArenaController.step)
            XCTAssertEqual(controller.mine.pos, position)
            XCTAssertTrue(actionEvents(controller).isEmpty)
            controller.fire(V2(1, 0))
            controller.advance(ArenaController.step)
            XCTAssertTrue(actionEvents(controller).contains(.attack(fighter: controller.me)))
        }
    }

    func testResultFromActualRulesClearsInputAndCannotBePlayedThrough() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(ArenaProgressStore.shared.progress)
        // A one-participant diagnostic showdown ends through the normal survivor
        // rule, without injecting a result or advancing the save.
        let controller = make(mode: .showdown)
        enterMatch(controller)
        XCTAssertNil(controller.hud.result)
        controller.move = V2(1, 0); controller.aiming = V2(1, 0)
        controller.advance(ArenaController.step)
        XCTAssertEqual(controller.game.result, .survivor(controller.me))
        XCTAssertEqual(controller.hud.result, controller.game.result)
        XCTAssertEqual(controller.move, .zero)
        XCTAssertNil(controller.aiming)
        _ = controller.takeEvents()
        let position = controller.mine.pos, ammo = controller.mine.ammo
        queueControls(controller)
        for _ in 0..<10 { controller.advance(ArenaController.step) }
        XCTAssertEqual(controller.move, .zero)
        XCTAssertNil(controller.aiming)
        XCTAssertNil(controller.superAiming)
        XCTAssertEqual(controller.mine.pos, position)
        XCTAssertEqual(controller.mine.ammo, ammo)
        XCTAssertTrue(actionEvents(controller).isEmpty)
        XCTAssertNil(controller.reward)
        XCTAssertEqual(try encoder.encode(ArenaProgressStore.shared.progress), before)
    }

    func testInputDialogDoesNotStopOtherFightersOrTheMatchClock() {
        let controller = make(scenario: .crowdWalk)
        enterMatch(controller)
        let position = controller.mine.pos
        let others = Array(controller.game.fighters.dropFirst().map(\.pos))
        controller.setInputPaused(true, for: .dialog)
        controller.move = V2(1, 0)
        for _ in 0..<60 { controller.advance(ArenaController.step) }
        XCTAssertEqual(controller.mine.pos, position)
        XCTAssertGreaterThan(controller.game.time, 0.9)
        XCTAssertNotEqual(Array(controller.game.fighters.dropFirst().map(\.pos)), others)
        XCTAssertNil(controller.hud.result)
        XCTAssertTrue(actionEvents(controller).isEmpty)
    }

    func testQueuedUltimateIsDiscardedWithoutSpendingEarnedCharge() {
        let controller = make(scenario: .crowdWalk)
        enterMatch(controller)
        // Earn charge through real hits in the deterministic crowd fixture.
        // Do not inject charge or relax the normal ultimate readiness gate.
        for _ in 0..<1_500 where controller.mine.superCharge < 1 {
            controller.fire(.zero)
            controller.advance(ArenaController.step)
        }
        XCTAssertGreaterThanOrEqual(controller.mine.superCharge, 1)
        _ = controller.takeEvents()
        controller.fireSpecial(.zero)
        controller.setInputPaused(true, for: .dialog)
        controller.advance(ArenaController.step)
        controller.setInputPaused(false, for: .dialog)
        controller.advance(ArenaController.step)
        XCTAssertGreaterThanOrEqual(controller.mine.superCharge, 1)
        XCTAssertFalse(actionEvents(controller).contains(.special(fighter: controller.me)))
        controller.fireSpecial(.zero)
        controller.advance(ArenaController.step)
        XCTAssertLessThan(controller.mine.superCharge, 1)
        XCTAssertTrue(actionEvents(controller).contains(.special(fighter: controller.me)))
    }
}
