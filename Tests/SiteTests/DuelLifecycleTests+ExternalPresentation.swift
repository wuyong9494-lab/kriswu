import XCTest
import Combine
import UIKit
@testable import ShiftReminder

#if DEBUG
/// Synthetic presentation fixtures are not verified assets or a multiplayer UI.
/// Kept in the existing native lifecycle suite selected by fighter CI.
extension DuelLifecycleTests {
    private func presentationGame(host: DuelGame.Hero = .ember, equipped: Bool = false) -> DuelGame {
        DuelGame(hero: host, difficulty: .learning, mode: .versus, seed: 73,
                 opponentHero: host == .ember ? .liu : .ember,
                 weaponCatalog: equipped ? presentationCatalog() : nil)
    }

    private func presentationCatalog() -> DuelWeaponCatalog {
        let profiles: [DuelWeaponProfile] = [DuelGame.Hero.ember, .liu].map { hero in
            let katana = hero == .ember, prefix = katana ? "katana" : "hammers"
            let zero = Array(repeating: DuelWeaponPoint(), count: 17)
            func clip(_ name: String) -> DuelWeaponClip {
                let base = (0..<17).map { DuelWeaponPoint(x: 0.2 + Double($0) / 20, y: 1) }
                let tip = (0..<17).map { DuelWeaponPoint(x: 0.7 + Double($0) / 20, y: 1) }
                let lift = (0..<17).map { name == "jump" ? sin(.pi * Double($0) / 16) * 0.8 : 0 }
                return .init(name: prefix + "_" + name, frames: 9, sha256: String(repeating: "c", count: 64),
                             bundle: "synthetic-presentation-test", tracks: .init(
                                samplesPerSourceFrame: 2, root: zero, handL: zero, handR: zero,
                                footL: zero, footR: zero, weaponBaseL: katana ? [] : base,
                                weaponTipL: katana ? [] : tip, weaponBaseR: base, weaponTipR: tip, groundLift: lift))
            }
            let roles = ["idle", "walkForward", "walkBackward", "guard", "hit", "knockdown", "getUp",
                         "jump", "weapon1", "heavy", "kick"]
            return .init(id: katana ? "sun_katana" : "liu_hammers", hero: hero,
                         faction: prefix, resourceName: "Synthetic_" + prefix, bytes: 128,
                         sha256: String(repeating: katana ? "a" : "b", count: 64),
                         bodyID: "body_" + prefix, weaponID: "weapon_" + prefix,
                         activeWeaponSides: katana ? ["right"] : ["left", "right"],
                         roles: Dictionary(uniqueKeysWithValues: roles.map { ($0, prefix + "_" + $0) }),
                         clips: roles.map(clip), comboLinks: nil)
        }
        return .init(schemaVersion: 1, previewFramesPerSecond: 30, sourceFramesPerSecond: nil, profiles: profiles)
    }

    private func bufferedPresentationGame() throws -> DuelGame {
        var game = presentationGame(equipped: true)
        game.step(.init(weaponCommand: .weapon), opponent: .init(weaponCommand: .weapon))
        game.step(.init(weaponCommand: .heavy), opponent: .init(weaponCommand: .heavy))
        var cleared = game; cleared.cancelBufferedInputs()
        XCTAssertNotEqual(game, cleared, "Fixture must contain canonical pending attacks")
        return game
    }

    func testExternalPresentationValidatesSeatsAndPreservesHostFirstRoster() throws {
        for host in [DuelGame.Hero.ember, .liu] {
            let game = presentationGame(host: host)
            for seat in [0, 1] {
                let state = try DuelSession(presentationFixture: game, localFighterIndex: seat)
                defer { state.shutdown() }
                XCTAssertEqual(state.driver, .externalAuthoritative)
                XCTAssertEqual(state.localFighterIndex, seat)
                XCTAssertEqual(state.opponentFighterIndex, 1 - seat)
                XCTAssertEqual(state.localFighter.hero, game.fighters[seat].hero)
                XCTAssertEqual(state.setup.hero, game.fighters[seat].hero)
                XCTAssertEqual(state.game, game)
                XCTAssertTrue(state.paused)
                XCTAssertFalse(state.allowsLocalRestart)
                XCTAssertNil(state.committedConfiguration)
            }
            for seat in [-1, 2, Int.max] {
                XCTAssertThrowsError(try DuelSession(presentationFixture: game, localFighterIndex: seat)) {
                    XCTAssertEqual($0 as? DuelSession.PresentationFailure, .invalidLocalFighterIndex)
                }
            }
        }
    }

    func testExternalClockNeverAdvancesAIOrDrainsPhysicalEdges() throws {
        let initial = presentationGame()
        let state = try DuelSession(presentationFixture: initial, localFighterIndex: 1)
        defer { state.shutdown() }
        var callbacks = 0
        state.didSimulateStep = { _, _ in callbacks += 1 }
        state.resume(); state.restart()
        XCTAssertTrue(state.paused)
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: initial, tick: 0))
        try state.startAuthoritativePresentation()
        state.input("right", down: true)
        state.input("light", down: true); state.input("light", down: false)
        for _ in 0..<600 { state.advance() }
        XCTAssertEqual(state.game, initial)
        XCTAssertEqual(state.animationTick, 0)
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(state.consumeLocalInput(), .init(move: 1, taps: .light))
        XCTAssertEqual(state.consumeLocalInput(), .init(move: 1))
        XCTAssertEqual(state.game, initial)
    }

    func testExternalStartRejectsNestedStartFromInputReset() throws {
        let state = try DuelSession(presentationFixture: presentationGame(), localFighterIndex: 1)
        defer { state.inputReset = nil; state.shutdown() }
        var resets = 0, starts = 0
        state.renderPause = { if !$0 { starts += 1 } }
        state.inputReset = {
            resets += 1
            XCTAssertThrowsError(try state.startAuthoritativePresentation()) {
                XCTAssertEqual($0 as? DuelSession.PresentationFailure, .notAwaitingStart)
            }
        }
        try state.startAuthoritativePresentation()
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(state.paused)
        XCTAssertEqual(state.nextPresentationTick, 0)
    }

    func testExternalStartCannotReviveAfterInputResetStopsOrShutsDown() throws {
        for action in ["pause", "shutdown", "cancel"] {
            let initial = presentationGame()
            let state = try DuelSession(presentationFixture: initial, localFighterIndex: 1)
            defer { state.inputReset = nil; state.shutdown() }
            var resets = 0, stops = 0, renderStarts = 0
            state.didRequestAuthoritativeStop = { stops += 1 }
            state.renderPause = { if !$0 { renderStarts += 1 } }
            state.inputReset = {
                resets += 1
                switch action {
                case "pause": state.pause()
                case "shutdown": state.shutdown()
                default: XCTAssertNoThrow(try state.publishAuthoritativeCancellation(trustedGame: initial))
                }
            }
            XCTAssertThrowsError(try state.startAuthoritativePresentation()) {
                XCTAssertEqual($0 as? DuelSession.PresentationFailure, .closed)
            }
            XCTAssertEqual(resets, 1, "Nested clear must not recursively call the reset hook")
            XCTAssertEqual(renderStarts, 0)
            XCTAssertEqual(stops, action == "cancel" ? 0 : 1)
            XCTAssertTrue(state.paused)
            XCTAssertEqual(state.game, initial)
            XCTAssertEqual(state.nextPresentationTick, 0)
            XCTAssertThrowsError(try state.startAuthoritativePresentation())
            state.resume(); state.restart()
            XCTAssertTrue(state.paused)
        }
    }

    func testExternalStartCannotReviveAfterRendererCallbackStops() throws {
        for shutdown in [false, true] {
            let state = try DuelSession(presentationFixture: presentationGame(), localFighterIndex: 1)
            defer { state.shutdown() }
            var callbacks: [Bool] = [], stops = 0
            state.didRequestAuthoritativeStop = { stops += 1 }
            state.renderPause = { paused in
                callbacks.append(paused)
                if !paused {
                    if shutdown { state.shutdown() } else { state.pause() }
                }
            }
            XCTAssertThrowsError(try state.startAuthoritativePresentation()) {
                XCTAssertEqual($0 as? DuelSession.PresentationFailure, .closed)
            }
            XCTAssertEqual(callbacks, [false, true])
            XCTAssertEqual(stops, 1)
            XCTAssertTrue(state.paused)
            XCTAssertThrowsError(try state.startAuthoritativePresentation())
        }
    }

    func testExternalStartCannotReviveAfterPublishedObserverStops() throws {
        let state = try DuelSession(presentationFixture: presentationGame(), localFighterIndex: 1)
        var stops = 0, renderStarts = 0
        state.didRequestAuthoritativeStop = { stops += 1 }
        state.renderPause = { if !$0 { renderStarts += 1 } }
        // Published sends before replacing its value. The outer false write
        // must not survive a synchronous terminal transition by an observer.
        let subscription = state.objectWillChange.sink { state.pause() }
        defer { subscription.cancel(); state.shutdown() }
        XCTAssertThrowsError(try state.startAuthoritativePresentation())
        XCTAssertTrue(state.paused)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(renderStarts, 0)
        XCTAssertThrowsError(try state.startAuthoritativePresentation())
    }

    private func presentationHitSteps() -> (DuelGame, DuelGame, DuelGame) {
        var before = DuelGame(hero: .ember, difficulty: .learning, mode: .versus, opponentHero: .gale)
        for tick in 0..<32 { before.step(.neutral, opponent: .init(taps: tick == 0 ? .skill1 : [])) }
        var hit = before; hit.step(.neutral, opponent: .neutral)
        XCTAssertTrue(hit.events.contains(.hit(attacker: 1, damage: 135)))
        var after = hit; after.step(.neutral, opponent: .neutral)
        XCTAssertTrue(after.events.isEmpty)
        return (before, hit, after)
    }

    func testExternalStepRejectsNestedPublicationAndPresentsEachEventOnce() throws {
        let (before, hit, after) = presentationHitSteps()
        let state = try DuelSession(presentationFixture: before, localFighterIndex: 1)
        defer { state.shutdown() }
        try state.startAuthoritativePresentation()
        var frames: [Int] = []
        state.didSimulateStep = { game, _ in
            frames.append(game.frame)
            if game.frame == hit.frame {
                XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: after, tick: 1)) {
                    XCTAssertEqual($0 as? DuelSession.PresentationFailure, .reentrantPublication)
                }
            }
        }
        try state.publishAuthoritativeStep(trustedGame: hit, tick: 0)
        XCTAssertEqual(state.game, hit)
        XCTAssertEqual(state.nextPresentationTick, 1)
        XCTAssertEqual(state.feedback, "命中 −135")
        XCTAssertEqual(frames, [hit.frame])
        // A rejected nested call consumes nothing; the same next step succeeds
        // after the previous publication (including its feedback) has returned.
        try state.publishAuthoritativeStep(trustedGame: after, tick: 1)
        XCTAssertEqual(state.game, after)
        XCTAssertEqual(state.nextPresentationTick, 2)
        XCTAssertEqual(frames, [hit.frame, after.frame])
        XCTAssertEqual(state.feedback, "命中 −135")
    }

    func testExternalStepStopsFeedbackAfterCallbackPauseShutdownOrCancellation() throws {
        let (before, hit, _) = presentationHitSteps()
        for action in ["pause", "shutdown", "cancel"] {
            let state = try DuelSession(presentationFixture: before, localFighterIndex: 1)
            defer { state.shutdown() }
            try state.startAuthoritativePresentation()
            let originalFeedback = state.feedback
            var cancelled = hit; cancelled.cancelBufferedInputs()
            var callbacks = 0
            state.didSimulateStep = { _, _ in
                callbacks += 1
                switch action {
                case "pause": state.pause()
                case "shutdown": state.shutdown()
                default: XCTAssertNoThrow(try state.publishAuthoritativeCancellation(trustedGame: cancelled))
                }
            }
            try state.publishAuthoritativeStep(trustedGame: hit, tick: 0)
            XCTAssertEqual(callbacks, 1)
            XCTAssertEqual(state.feedback, originalFeedback, "Stopped callback must not emit stale hit feedback")
            XCTAssertEqual(state.game, action == "cancel" ? cancelled : hit)
            XCTAssertEqual(state.nextPresentationTick, 1)
            XCTAssertEqual(state.animationTick, 1)
            XCTAssertTrue(state.paused)
            XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: hit, tick: 1))
            XCTAssertThrowsError(try state.startAuthoritativePresentation())
        }
    }

    func testExternalWeaponInputUsesLocalFacingWithoutMirroringWorldMovement() throws {
        for host in [DuelGame.Hero.ember, .liu] {
            for seat in [0, 1] {
                let state = try DuelSession(presentationFixture: presentationGame(host: host, equipped: true),
                                            localFighterIndex: seat)
                defer { state.shutdown() }
                XCTAssertNotNil(state.game.weaponFight)
                try state.startAuthoritativePresentation()
                state.weaponDirection(x: 1, y: 0); state.weaponAction(.weapon, down: true)
                let sample = state.consumeLocalInput()
                XCTAssertEqual(sample.move, 1)
                XCTAssertEqual(sample.weaponCommand, seat == 0 ? .weaponForward : .weaponBack)
                XCTAssertNil(state.consumeLocalInput().weaponCommand)
                state.clearInput()
                state.weaponDirection(x: -1, y: 0); state.weaponAction(.kick, down: true)
                XCTAssertEqual(state.consumeLocalInput().weaponCommand, seat == 0 ? .kickBack : .kickForward)
                XCTAssertEqual(state.game.frame, 0)
            }
        }
    }

    func testExternalWeaponInputUsesGuestAirborneState() throws {
        var game = presentationGame(equipped: true)
        game.step(.neutral, opponent: .init(taps: .jump))
        for _ in 0..<4 { game.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(game.weaponFight?.isAirborne(0), false)
        XCTAssertEqual(game.weaponFight?.isAirborne(1), true)
        let host = try DuelSession(presentationFixture: game, localFighterIndex: 0)
        let guest = try DuelSession(presentationFixture: game, localFighterIndex: 1)
        defer { host.shutdown(); guest.shutdown() }
        try host.startAuthoritativePresentation(); try guest.startAuthoritativePresentation()
        host.weaponAction(.weapon, down: true); guest.weaponAction(.weapon, down: true)
        XCTAssertNil(host.consumeLocalInput().weaponCommand, "Grounded neutral press waits for release/hold")
        XCTAssertEqual(guest.consumeLocalInput().weaponCommand, .weapon, "Airborne local press resolves immediately")
    }

    func testExternalPhysicalClearPauseAndShutdownPreserveCanonicalBuffers() throws {
        let buffered = try bufferedPresentationGame()
        for operation in ["clear", "cancel", "pause", "shutdown"] {
            let state = try DuelSession(presentationFixture: buffered, localFighterIndex: 1)
            try state.startAuthoritativePresentation()
            state.input("right", down: true); state.weaponAction(.weapon, down: true)
            var stops = 0
            state.didRequestAuthoritativeStop = { stops += 1 }
            switch operation {
            case "clear": state.clearInput()
            case "cancel": state.cancelWeaponInput(); state.clearInput()
            case "pause": state.pause(); state.pause()
            default: state.shutdown(); state.shutdown()
            }
            XCTAssertEqual(state.game, buffered, operation)
            XCTAssertEqual(try DuelReplayStateEncoding.encode(state.game), try DuelReplayStateEncoding.encode(buffered))
            XCTAssertTrue(state.held.isEmpty)
            XCTAssertEqual(stops, operation == "pause" || operation == "shutdown" ? 1 : 0)
            state.shutdown()
        }
    }

    func testExternalWorldTeardownPreservesCanonicalBuffersAndRequestsStopOnce() throws {
        // Unarmed fixture avoids requiring private assets in ordinary CI.
        var game = presentationGame()
        for _ in 0..<40 { game.step(.init(move: 1), opponent: .neutral) }
        game.step(.init(taps: .light), opponent: .neutral)
        for _ in 0..<20 { if game.hitStop == 0 { game.step(.neutral, opponent: .neutral) } }
        XCTAssertGreaterThan(game.hitStop, 0)
        game.step(.init(taps: .light), opponent: .init(taps: .heavy))
        var cleared = game; cleared.cancelBufferedInputs()
        XCTAssertNotEqual(game, cleared)
        let state = try DuelSession(presentationFixture: game, localFighterIndex: 1)
        let world = DuelWorldView(session: state, characterSource: .procedural)
        defer { world.shutdown(); state.shutdown() }
        try state.startAuthoritativePresentation()
        var stops = 0; state.didRequestAuthoritativeStop = { stops += 1 }
        world.shutdown(); world.shutdown()
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(state.game, game)
        XCTAssertTrue(state.paused)
        XCTAssertNil(world.scene)
    }

    func testExternalCancellationIsExplicitTerminalAndDoesNotReplayFeedback() throws {
        let game = try bufferedPresentationGame()
        let state = try DuelSession(presentationFixture: game, localFighterIndex: 1)
        defer { state.shutdown() }
        try state.startAuthoritativePresentation()
        var callbacks = 0; state.didSimulateStep = { _, _ in callbacks += 1 }
        state.pause()
        state.resume(); state.restart()
        XCTAssertEqual(state.game, game)
        XCTAssertTrue(state.paused)
        XCTAssertThrowsError(try state.startAuthoritativePresentation())
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: game, tick: 0))
        var cancelled = game; cancelled.cancelBufferedInputs()
        try state.publishAuthoritativeCancellation(trustedGame: cancelled)
        XCTAssertEqual(state.game, cancelled)
        XCTAssertEqual(state.nextPresentationTick, 0)
        XCTAssertEqual(state.animationTick, 0)
        XCTAssertEqual(callbacks, 0)
        XCTAssertThrowsError(try state.publishAuthoritativeCancellation(trustedGame: cancelled))
        state.resume(); state.restart()
        XCTAssertTrue(state.paused)
        XCTAssertEqual(state.game, cancelled)
    }

    func testExternalPublicationRejectsDuplicateGapRosterChangeAndLateWork() throws {
        var game = presentationGame()
        let state = try DuelSession(presentationFixture: game, localFighterIndex: 1)
        defer { state.shutdown() }
        try state.startAuthoritativePresentation()
        game.step(.neutral, opponent: .init(move: -1))
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: game, tick: 1))
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: game, tick: UInt64.max))
        XCTAssertEqual(state.nextPresentationTick, 0)
        try state.publishAuthoritativeStep(trustedGame: game, tick: 0)
        XCTAssertEqual(state.game, game)
        XCTAssertEqual(state.animationTick, 1)
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: game, tick: 0))
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: presentationGame(host: .liu), tick: 1))
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: presentationGame(equipped: true), tick: 1))
        XCTAssertEqual(state.nextPresentationTick, 1)
        XCTAssertEqual(state.game, game)
        state.shutdown()
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: game, tick: 1))
        XCTAssertThrowsError(try state.publishAuthoritativeCancellation(trustedGame: game))
        XCTAssertThrowsError(try state.startAuthoritativePresentation())
    }

    func testExternalAnimationFreezeUsesPreviousAuthoritativeHitStop() throws {
        var game = presentationGame()
        for _ in 0..<40 { game.step(.init(move: 1), opponent: .neutral) }
        game.step(.init(taps: .light), opponent: .neutral)
        for _ in 0..<20 { if game.hitStop == 0 { game.step(.neutral, opponent: .neutral) } }
        XCTAssertGreaterThan(game.hitStop, 0)
        let state = try DuelSession(presentationFixture: game, localFighterIndex: 1)
        defer { state.shutdown() }
        try state.startAuthoritativePresentation()
        var tick: UInt64 = 0
        while game.hitStop > 0 {
            game.step(.neutral, opponent: .neutral)
            try state.publishAuthoritativeStep(trustedGame: game, tick: tick); tick += 1
            XCTAssertEqual(state.animationTick, 0)
        }
        game.step(.neutral, opponent: .neutral)
        try state.publishAuthoritativeStep(trustedGame: game, tick: tick)
        XCTAssertEqual(state.animationTick, 1)
    }

    func testExternalFinishedGameCannotReplayItsRetainedFinalEvents() throws {
        var game = presentationGame(), previous = game
        for _ in 0..<4_000 {
            if case .matchOver = game.phase { break }
            previous = game
            game.step(.init(move: 1, taps: .light), opponent: .neutral)
        }
        guard case .matchOver = game.phase else { return XCTFail("Fixture must finish the match") }
        let state = try DuelSession(presentationFixture: previous, localFighterIndex: 1)
        defer { state.shutdown() }
        try state.startAuthoritativePresentation()
        var callbacks = 0; state.didSimulateStep = { _, _ in callbacks += 1 }
        try state.publishAuthoritativeStep(trustedGame: game, tick: 0)
        let finalAnimationTick = state.animationTick, finalFeedback = state.feedback
        // DuelGame retains its final events when another host inbox tick calls
        // step after match-over. Presentation must not play those events again.
        game.step(.neutral, opponent: .neutral)
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: game, tick: 1))
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(state.nextPresentationTick, 1)
        XCTAssertEqual(state.animationTick, finalAnimationTick)
        XCTAssertEqual(state.feedback, finalFeedback)
    }

    func testExternalFeedbackCountersAndUltimateReadinessFollowGuestSeat() throws {
        var game = DuelGame(hero: .ember, difficulty: .learning, mode: .versus, opponentHero: .gale)
        let host = try DuelSession(presentationFixture: game, localFighterIndex: 0)
        let guest = try DuelSession(presentationFixture: game, localFighterIndex: 1)
        defer { host.shutdown(); guest.shutdown() }
        try host.startAuthoritativePresentation(); try guest.startAuthoritativePresentation()
        for tick in UInt64(0)..<33 {
            game.step(.neutral, opponent: .init(taps: tick == 0 ? .skill1 : []))
            try host.publishAuthoritativeStep(trustedGame: game, tick: tick)
            try guest.publishAuthoritativeStep(trustedGame: game, tick: tick)
        }
        XCTAssertEqual(game.landedHits, [0, 1])
        XCTAssertEqual(host.localLandedHits, 0); XCTAssertEqual(guest.localLandedHits, 1)
        XCTAssertEqual(guest.localDamageDealt, 135)
        XCTAssertEqual(host.feedback, "受到攻击 −135")
        XCTAssertEqual(guest.feedback, "命中 −135")
        XCTAssertTrue(host.ultimateReady)
        XCTAssertFalse(guest.ultimateReady)
    }

    func testExternalWeaponReadinessUsesLocalEquippedProfileAndAttack() throws {
        var game = presentationGame(equipped: true)
        game.step(.neutral, opponent: .init(weaponCommand: .weapon))
        for seat in [0, 1] {
            let state = try DuelSession(presentationFixture: game, localFighterIndex: seat)
            defer { state.shutdown() }
            try state.startAuthoritativePresentation()
            let view = DuelSourceControlsView(images: [:])
            DuelWeaponControls(session: state).updateReadiness(view)
            let weapon = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }
                .first { $0.accessibilityIdentifier == "duel.control.weapon" })
            XCTAssertEqual(weapon.accessibilityLabel, seat == 0 ? "武士刀攻击" : "双锤攻击")
            XCTAssertEqual(view.state(for: .weapon).description, seat == 0 ? "可施放" : "收招中")
            XCTAssertEqual(view.state(for: .weapon).ready, seat == 0)
            XCTAssertEqual(state.localFighter.attack == nil, seat == 0)
        }
    }

    func testExternalPresentationAcceptsRealHostAndValidatedReplayOneTickAtATime() throws {
        let catalog = presentationCatalog()
        try catalog.validate()
        for swapped in [false, true] {
            let sessionID = "presentation-session", hostID = "z-host", guestID = "a-guest"
            let compatibility = DuelNetworkStartBarrier.Compatibility(
                rulesFingerprint: String(repeating: "a", count: 64),
                catalogFingerprint: String(repeating: "b", count: 64))
            var selection = try DuelMultiplayerSelection(sessionID: sessionID, hostID: hostID, guestID: guestID)
            let commands: [(String, UInt64, DuelMultiplayerSelection.Command)] = [
                (hostID, 1, .select(swapped ? .liu : .sun)), (guestID, 1, .select(swapped ? .sun : .liu)),
                (hostID, 2, .ready(true, selectionRevision: 2)), (guestID, 2, .ready(true, selectionRevision: 2)),
                (hostID, 3, .start(selectionRevision: 2))
            ]
            for (sender, sequence, command) in commands {
                XCTAssertEqual(selection.apply(.init(sessionID: sessionID, sequence: sequence, command: command),
                                                authenticatedSenderID: sender, localPlayerID: hostID), .applied)
            }
            var hostBarrier = try DuelNetworkStartBarrier(started: selection.snapshot, sessionID: sessionID,
                hostID: hostID, guestID: guestID, localPlayerID: hostID, compatibility: compatibility)
            var guestBarrier = try DuelNetworkStartBarrier(started: selection.snapshot, sessionID: sessionID,
                hostID: hostID, guestID: guestID, localPlayerID: guestID, compatibility: compatibility)
            let offer = try hostBarrier.makeOffer(startID: "presentation-start", seed: 73, sequence: 1)
            XCTAssertEqual(guestBarrier.receive(try offer.encoded(), authenticatedSenderID: hostID), .applied)
            let configuration = try XCTUnwrap(hostBarrier.offeredConfiguration)
            let hostLoaded = try hostBarrier.confirmLoaded(configuration: configuration,
                loadedCompatibility: compatibility, catalog: catalog, sequence: 2)
            let guestLoaded = try guestBarrier.confirmLoaded(configuration: configuration,
                loadedCompatibility: compatibility, catalog: catalog, sequence: 1)
            XCTAssertEqual(hostBarrier.receive(try guestLoaded.encoded(), authenticatedSenderID: guestID), .applied)
            XCTAssertEqual(guestBarrier.receive(try hostLoaded.encoded(), authenticatedSenderID: hostID), .applied)
            XCTAssertEqual(guestBarrier.receive(try hostBarrier.commit(sequence: 3).encoded(), authenticatedSenderID: hostID), .applied)
            var host = try DuelNetworkCombatHost(committed: hostBarrier, started: selection.snapshot,
                                                 loadedCompatibility: compatibility, catalog: catalog)
            var replay = try DuelNetworkReplay(committed: guestBarrier, loadedCompatibility: compatibility, catalog: catalog)
            let hostView = try DuelSession(presentationFixture: host.game, localFighterIndex: 0)
            let guestView = try DuelSession(presentationFixture: replay.game, localFighterIndex: 1)
            defer { hostView.shutdown(); guestView.shutdown() }
            try hostView.startAuthoritativePresentation(); try guestView.startAuthoritativePresentation()
            var hostSteps = 0, guestSteps = 0
            hostView.didSimulateStep = { _, _ in hostSteps += 1 }
            guestView.didSimulateStep = { _, _ in guestSteps += 1 }
            for tick in UInt64(0)..<60 {
                XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: tick + 1, tick: tick,
                    move: tick < 20 ? -1 : 0), authenticatedSenderID: guestID), .applied)
                let message = try host.advance(frameCount: 1)
                XCTAssertEqual(replay.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
                try hostView.publishAuthoritativeStep(trustedGame: host.game, tick: tick)
                try guestView.publishAuthoritativeStep(trustedGame: replay.game, tick: tick)
                hostView.advance(); guestView.advance()
                XCTAssertEqual(hostView.game, host.game)
                XCTAssertEqual(guestView.game, replay.game)
                XCTAssertEqual(hostView.game, guestView.game)
                XCTAssertEqual(hostView.animationTick, guestView.animationTick)
                XCTAssertEqual(hostView.game.fighters[0].x, 3500, "Missing host control is explicit neutral, never AI")
            }
            XCTAssertEqual(hostSteps, 60); XCTAssertEqual(guestSteps, 60)
            let cancellation = try host.makeCancellation()
            XCTAssertEqual(replay.receive(try cancellation.encoded(), authenticatedSenderID: hostID), .applied)
            try hostView.publishAuthoritativeCancellation(trustedGame: host.game)
            try guestView.publishAuthoritativeCancellation(trustedGame: replay.game)
            XCTAssertEqual(hostView.game, guestView.game)
            XCTAssertTrue(hostView.paused); XCTAssertTrue(guestView.paused)
            XCTAssertEqual(hostSteps, 60); XCTAssertEqual(guestSteps, 60)
        }
    }

    func testOfflineDriverRemainsIndependentAndRejectsExternalPublication() throws {
        let state = DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice))
        defer { state.shutdown() }
        XCTAssertEqual(state.driver, .offline)
        XCTAssertEqual(state.localFighterIndex, 0)
        XCTAssertTrue(state.allowsLocalRestart)
        XCTAssertThrowsError(try state.startAuthoritativePresentation())
        XCTAssertThrowsError(try state.publishAuthoritativeStep(trustedGame: state.game, tick: 0))
        XCTAssertThrowsError(try state.publishAuthoritativeCancellation(trustedGame: state.game))
        state.input("right", down: true); state.advance()
        XCTAssertEqual(state.game.frame, 1)
        XCTAssertGreaterThan(state.localFighter.x, 3500)
        state.pause(); let paused = state.game; state.advance()
        XCTAssertEqual(state.game, paused)
        state.resume(); state.advance(); XCTAssertEqual(state.game.frame, 2)
        state.restart(); XCTAssertEqual(state.game.frame, 0)
        XCTAssertFalse(state.paused); XCTAssertTrue(state.held.isEmpty)
    }
}
#endif
