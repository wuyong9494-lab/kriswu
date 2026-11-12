import XCTest
import UIKit
import SwiftUI
import SceneKit
import Combine
@testable import ShiftReminder

#if DEBUG
/// Synthetic mount/GPU lifecycle checks only, never production asset acceptance.
@MainActor
extension DuelLifecycleTests {
    private func preparationSession() throws -> DuelSession {
        try DuelSession(presentationFixture: DuelGame(hero: .ember, difficulty: .learning,
            mode: .versus, opponentHero: .liu), localFighterIndex: 1)
    }
    private func preparationWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.frame = window.bounds
        window.makeKeyAndVisible()
        return window
    }
    private func preparationControls(_ owner: DuelNetworkMatchPreparation,
                                     validSource: Bool = true) -> DuelNetworkControlsView {
        DuelNetworkControlsView(testing: owner, controls: DuelSourceControlsView(images: [:]),
                                acceptsFixtureArt: validSource)
    }
    private func mountPreparation(_ views: [UIView], in window: UIWindow) {
        for view in views {
            view.frame = window.bounds
            window.rootViewController?.view.addSubview(view)
            view.setNeedsLayout(); view.layoutIfNeeded()
        }
    }

    func testSwiftUIAttachmentRetriesInitialUnmountedViewWithoutPublishingInsideLayout() async throws {
        let state = try preparationSession()
        let completed = expectation(description: "Deferred UIKit boundary still reaches prepared receipt")
        var successes = 0, inViewUpdate = false, publishedInsideUpdate = false
        let owner = try DuelNetworkMatchPreparation(testing: state) { result in
            if case .success = result { successes += 1 }
            completed.fulfill()
        }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        world.testingPrepare = { _, callback in callback(true) }
        let subscription = owner.objectWillChange.sink {
            if inViewUpdate { publishedInsideUpdate = true }
        }
        let controls = DuelNetworkControlsView(testing: owner,
            controls: DuelSourceControlsView(images: [:]), acceptsFixtureArt: true,
            deferReadinessUpdates: true)
        let window = preparationWindow()
        defer { subscription.cancel(); owner.cancel(); window.isHidden = true }
        inViewUpdate = true
        world.schedulePreparationAttachment(owner)
        inViewUpdate = false
        let drained = expectation(description: "Initial unmounted attachment attempt")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(owner.state, .waitingForMount)
        XCTAssertEqual(successes, 0)
        inViewUpdate = true
        mountPreparation([world, controls], in: window)
        world.removeFromSuperview() // Detach before the first queued attach can run.
        inViewUpdate = false
        let detachedDrain = expectation(description: "Unmounted queued world remains pending")
        DispatchQueue.main.async { detachedDrain.fulfill() }
        await fulfillment(of: [detachedDrain], timeout: 2)
        XCTAssertEqual(owner.state, .waitingForMount)
        XCTAssertEqual(successes, 0)
        inViewUpdate = true
        mountPreparation([world], in: window)
        inViewUpdate = false
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(successes, 1)
        XCTAssertFalse(publishedInsideUpdate)
        XCTAssertTrue(world.usedActualScenePreparation == false,
                      "This test covers scheduling only; the separate hosted test retains actual GPU preparation")
    }

    func testDeferredUIKitAttachmentDoesNotReviveShutdownWorldOrCancelledMount() async throws {
        for shutWorld in [false, true] {
            let state = try preparationSession()
            var delivered = 0
            let owner = try DuelNetworkMatchPreparation(testing: state) { _ in delivered += 1 }
            let world = DuelWorldView(session: state, characterSource: .presentationFixture)
            world.testingPrepare = { _, callback in XCTFail("Stale attachment must not prepare") }
            let window = preparationWindow()
            world.schedulePreparationAttachment(owner)
            if shutWorld { world.shutdown() } else { owner.cancel() }
            mountPreparation([world], in: window)
            let drained = expectation(description: "Stale deferred attachment drained")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 2)
            XCTAssertEqual(delivered, 0)
            XCTAssertNil(world.scene)
            if !shutWorld { XCTAssertEqual(owner.state, .cancelled) }
            owner.cancel(); world.shutdown(); window.isHidden = true
        }
    }

    func testQueuedControlsRepeatedLayoutPreparesOnceAndReplacementCancelsSynchronously() async throws {
        for replace in [false, true] {
            let state = try preparationSession()
            var successes = 0, failures = 0
            let settled = expectation(description: "Repeated or replaced deferred controls settle")
            let owner = try DuelNetworkMatchPreparation(testing: state) { result in
                switch result { case .success: successes += 1; case .failure: failures += 1 }
                settled.fulfill()
            }
            let world = DuelWorldView(session: state, characterSource: .presentationFixture)
            world.testingPrepare = { _, callback in callback(true) }
            let controls = DuelNetworkControlsView(testing: owner,
                controls: DuelSourceControlsView(images: [:]), acceptsFixtureArt: true,
                deferReadinessUpdates: true)
            let window = preparationWindow()
            world.schedulePreparationAttachment(owner)
            mountPreparation([world, controls], in: window)
            for _ in 0..<8 { controls.layoutSubviews(); controls.scheduleReadinessRefresh() }
            if replace {
                let replacement = DuelNetworkControlsView(testing: owner,
                    controls: DuelSourceControlsView(images: [:]), acceptsFixtureArt: true,
                    deferReadinessUpdates: true)
                XCTAssertEqual(owner.state, .failed(.replaced), "Conflicting ownership must fail synchronously")
                replacement.shutdown()
            }
            await fulfillment(of: [settled], timeout: 2)
            let drained = expectation(description: "Duplicate readiness callbacks drained")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 2)
            XCTAssertEqual(successes, replace ? 0 : 1)
            XCTAssertEqual(failures, replace ? 1 : 0)
            if replace { XCTAssertNil(world.scene) }
            owner.cancel(); world.shutdown(); window.isHidden = true
        }
    }

    func testQueuedControlsDetachedBeforeReadinessCannotPrepareAfterRemoval() async throws {
        let state = try preparationSession()
        var successes = 0, failures = 0
        let owner = try DuelNetworkMatchPreparation(testing: state) { result in
            switch result { case .success: successes += 1; case .failure: failures += 1 }
        }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        world.testingPrepare = { _, callback in callback(true) }
        let controls = DuelNetworkControlsView(testing: owner,
            controls: DuelSourceControlsView(images: [:]), acceptsFixtureArt: true,
            deferReadinessUpdates: true)
        let window = preparationWindow()
        defer { owner.cancel(); world.shutdown(); window.isHidden = true }
        world.schedulePreparationAttachment(owner)
        mountPreparation([world, controls], in: window)
        controls.removeFromSuperview()
        XCTAssertEqual(owner.state, .failed(.detached))
        XCTAssertEqual(failures, 1, "Detach invalidation remains synchronous")
        let drained = expectation(description: "Detached queued controls drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(successes, 0); XCTAssertEqual(failures, 1)
        XCTAssertNil(world.scene)
    }

    func testNetworkPreparationFixtureNeverLoadsBundledOriginalResources() throws {
        let state = try preparationSession()
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        defer { world.shutdown(); state.shutdown() }
        // This test also runs with the approved source pack installed. The
        // fixture must bypass lookup, not load/decode it and discard the result.
        XCTAssertTrue(state.isPresentationFixture)
        XCTAssertTrue(world.usesSyntheticPresentationResources)
        XCTAssertFalse(world.attemptedBundledStageLoad)
        XCTAssertNil(world.stageAsset); XCTAssertNil(world.verifiedStageRoot)
        XCTAssertNil(world.characterAsset)
        XCTAssertTrue(world.originalAssets.isEmpty); XCTAssertTrue(world.weaponAssets.isEmpty)
        XCTAssertNil(world.sourceEffects); XCTAssertNil(world.weaponEffects)
        XCTAssertNil(world.verifiedEffectsRoot)
        let fixtureStage = try XCTUnwrap(world.scene?.rootNode.childNode(
            withName: "duel.stage.presentation-fixture", recursively: false))
        XCTAssertFalse(fixtureStage.childNodes.isEmpty)
        XCTAssertNotNil(world.pointOfView?.camera)
        XCTAssertTrue(world.pointOfView?.camera?.usesOrthographicProjection == true)
        XCTAssertFalse(world.hasVerifiedResourceIdentity)
        XCTAssertEqual(state.game.frame, 0)
        XCTAssertTrue(state.paused)
    }

    func testNetworkPreparationFixtureRendererRejectsNonFixtureSession() {
        let state = DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice))
        var pauses = 0
        state.renderPause = { _ in pauses += 1 }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        defer { world.shutdown(); state.shutdown() }
        XCTAssertFalse(state.isPresentationFixture)
        XCTAssertFalse(world.usesSyntheticPresentationResources)
        XCTAssertFalse(world.attemptedBundledStageLoad)
        XCTAssertNil(world.scene)
        XCTAssertNil(state.loadError)
        XCTAssertFalse(state.paused)
        world.shutdown()
        XCTAssertNotNil(state.renderPause, "A rejected fixture renderer cannot clear the live session's callback")
        state.pause()
        XCTAssertEqual(pauses, 1)
    }

    func testNetworkPreparationNeedsWindowAndUsableLayoutBeforeScenePrepare() throws {
        let state = try preparationSession()
        let initial = state.game, clocks = DuelWorldView.activeClocks
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        defer { world.shutdown(); state.shutdown() }
        var prepares = 0, completions = 0
        var finish: (@MainActor (Bool) -> Void)?
        world.testingPrepare = { _, callback in prepares += 1; finish = callback }
        try world.prepareNetworkScene(owner: UUID()) { _ in completions += 1 }
        world.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        world.layoutIfNeeded()
        XCTAssertEqual(prepares, 0, "Scene construction/layout without a window is not readiness")
        let window = preparationWindow()
        defer { window.isHidden = true }
        world.frame = .zero
        window.rootViewController?.view.addSubview(world)
        world.layoutIfNeeded()
        XCTAssertEqual(prepares, 0, "A mounted zero-size renderer is not ready")
        world.frame = window.bounds; world.setNeedsLayout(); world.layoutIfNeeded()
        XCTAssertEqual(prepares, 1)
        XCTAssertEqual(completions, 0)
        finish?(true); finish?(true)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(state.game, initial)
        XCTAssertEqual(state.animationTick, 0)
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
        XCTAssertTrue(state.paused)
    }

    func testNetworkPreparationCombinesBoundControlsAndSceneOnceWithoutStarting() throws {
        let state = try preparationSession()
        let initial = state.game
        var receipts: [DuelNetworkMatchPreparation.Receipt] = []
        let owner = try DuelNetworkMatchPreparation(testing: state) { result in
            if case .success(let receipt) = result { receipts.append(receipt) }
        }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        try world.installPreparationEffectFixtures()
        var finish: (@MainActor (Bool) -> Void)?, objectCount = 0
        world.testingPrepare = { objects, callback in objectCount = objects.count; finish = callback }
        owner.attach(world)
        let controls = preparationControls(owner)
        let window = preparationWindow()
        defer { owner.cancel(); window.isHidden = true }
        mountPreparation([controls], in: window)
        XCTAssertTrue(receipts.isEmpty, "Controls alone cannot satisfy scene preparation")
        XCTAssertFalse(controls.controls.inputEnabled)
        XCTAssertNotNil(controls.controls.onDirection); XCTAssertNotNil(controls.controls.onAction)
        mountPreparation([world], in: window)
        XCTAssertGreaterThan(objectCount, 1, "Prepare includes detached runtime-effect templates")
        XCTAssertTrue(receipts.isEmpty)
        finish?(true); finish?(true)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertTrue(receipts[0].initialScenePrepared)
        XCTAssertTrue(receipts[0].runtimeEffectVariantsPrepared)
        XCTAssertTrue(receipts[0].controlsPrepared)
        XCTAssertFalse(receipts[0].verifiedResourceOwnershipComplete)
        XCTAssertTrue(owner.session === state)
        state.advance(); controls.refreshReadiness()
        XCTAssertEqual(state.game, initial)
        XCTAssertEqual(state.nextPresentationTick, 0)
        XCTAssertTrue(state.paused)
        XCTAssertFalse(controls.controls.inputEnabled)
        XCTAssertEqual(world.sourceEffects?.emittedHits, 0)
        XCTAssertEqual(world.sourceEffects?.playedSounds, 0)
        XCTAssertEqual(world.weaponEffects?.emittedSampleCount, 0)
    }

    func testNetworkPreparationSceneSuccessWaitsForControlsLayout() throws {
        let state = try preparationSession()
        var completed = 0
        let owner = try DuelNetworkMatchPreparation(testing: state) { _ in completed += 1 }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        world.testingPrepare = { _, callback in callback(true) }
        owner.attach(world)
        let controls = preparationControls(owner)
        let window = preparationWindow()
        defer { owner.cancel(); window.isHidden = true }
        mountPreparation([world], in: window)
        XCTAssertEqual(completed, 0)
        controls.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        window.rootViewController?.view.addSubview(controls)
        controls.setNeedsLayout(); controls.layoutIfNeeded()
        XCTAssertEqual(completed, 0, "Tiny or unusable controls cannot acknowledge readiness")
        controls.frame = window.bounds; controls.setNeedsLayout(); controls.layoutIfNeeded()
        XCTAssertEqual(completed, 1)
    }

    func testNetworkPreparationTerminalSessionFailsWithoutAnotherReadinessEvent() throws {
        for scenePrepared in [false, true] {
            for transition in ["pause", "shutdown", "cancellation", "loadFailure"] {
                let state = try preparationSession(), initial = state.game
                var successes = 0, failures: [DuelNetworkMatchPreparation.Failure] = []
                let owner = try DuelNetworkMatchPreparation(testing: state) { result in
                    switch result { case .success: successes += 1; case .failure(let error): failures.append(error) }
                }
                let world = DuelWorldView(session: state, characterSource: .presentationFixture)
                try world.installPreparationEffectFixtures()
                var finish: (@MainActor (Bool) -> Void)?
                world.testingPrepare = { _, callback in finish = callback }
                owner.attach(world)
                // Controls never mount or become ready. In particular, no
                // layout callback may be needed to observe the interruption.
                let controls = preparationControls(owner), window = preparationWindow()
                mountPreparation([world], in: window)
                if scenePrepared { finish?(true) }
                XCTAssertTrue(failures.isEmpty)
                XCTAssertEqual(successes, 0)
                XCTAssertNil(state.didRequestAuthoritativeStop, "The loader has not delivered a session yet")
                switch transition {
                case "pause": state.pause()
                case "shutdown": state.shutdown()
                case "cancellation": try state.publishAuthoritativeCancellation(trustedGame: initial)
                default: state.characterFailed()
                }
                XCTAssertEqual(failures, [.invalidSession], "\(transition), scenePrepared=\(scenePrepared)")
                XCTAssertEqual(owner.state, .failed(.invalidSession))
                XCTAssertNil(world.scene)
                XCTAssertNil(world.sourceEffects); XCTAssertNil(world.weaponEffects)
                XCTAssertNil(controls.controls.onDirection); XCTAssertNil(controls.controls.onAction)
                XCTAssertNil(state.inputReset); XCTAssertNil(state.renderPause)
                XCTAssertTrue(state.paused)
                XCTAssertEqual(state.game, initial)
                XCTAssertEqual(state.nextPresentationTick, 0)
                XCTAssertEqual(state.animationTick, 0)
                // Duplicates and a queued GPU callback cannot reopen the owner.
                state.pause(); state.shutdown(); finish?(true); finish?(false)
                XCTAssertEqual(failures, [.invalidSession]); XCTAssertEqual(successes, 0)
                owner.cancel(); window.isHidden = true
            }
        }
    }

    func testNetworkPreparationReleasesPendingHookBeforeSynchronousStart() throws {
        let state = try preparationSession()
        var receipts = 0, failures = 0, invalidations = 0, oldStops = 0, newStops = 0
        state.didRequestAuthoritativeStop = { oldStops += 1 }
        let owner = try DuelNetworkMatchPreparation(testing: state, invalidated: { _ in invalidations += 1 }) { result in
            switch result {
            case .failure: failures += 1
            case .success:
                receipts += 1
                state.didRequestAuthoritativeStop = { newStops += 1 }
                do { try state.startAuthoritativePresentation() }
                catch { XCTFail("A delivered preparation must allow coordinator start: \(error)") }
            }
        }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        world.testingPrepare = { _, callback in callback(true) }
        owner.attach(world)
        let controls = preparationControls(owner), window = preparationWindow()
        defer { owner.cancel(); window.isHidden = true }
        mountPreparation([world, controls], in: window)
        controls.refreshReadiness()
        world.setNeedsLayout(); world.layoutIfNeeded()
        XCTAssertEqual(receipts, 1); XCTAssertEqual(failures, 0)
        XCTAssertEqual(invalidations, 0)
        XCTAssertFalse(state.paused)
        state.advance()
        XCTAssertEqual(state.game.frame, 0)
        state.pause(); state.pause()
        XCTAssertEqual(newStops, 1); XCTAssertEqual(oldStops, 0)
        XCTAssertEqual(failures, 0); XCTAssertEqual(invalidations, 0)
        guard case .prepared = owner.state else { return XCTFail("Only the coordinator owns the delivered session stop") }
        XCTAssertNotNil(world.scene)
    }

    func testNetworkPreparationRejectsUnverifiedControlsAndUncommittedProductionMount() throws {
        let state = try preparationSession()
        XCTAssertThrowsError(try DuelNetworkMatchPreparation(session: state) { _ in })
        var failures: [DuelNetworkMatchPreparation.Failure] = []
        let owner = try DuelNetworkMatchPreparation(testing: state) { result in
            if case .failure(let error) = result { failures.append(error) }
        }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        owner.attach(world)
        let controls = preparationControls(owner, validSource: false)
        defer { owner.cancel() }
        XCTAssertEqual(failures, [.controlsUnavailable])
        XCTAssertNil(world.scene)
        XCTAssertNil(controls.controls.onDirection)
        XCTAssertTrue(controls.controls.subviews.count > 0, "Artwork ownership is local; callbacks are removed")
        XCTAssertTrue(state.paused)
    }

    func testNetworkPreparationFailureDisposesAndSuppressesDuplicateCompletion() throws {
        let state = try preparationSession()
        var outcomes = 0, failure: DuelNetworkMatchPreparation.Failure?
        let owner = try DuelNetworkMatchPreparation(testing: state) { result in
            outcomes += 1
            if case .failure(let error) = result { failure = error }
            else { XCTFail("Failed SceneKit preparation cannot become ready") }
        }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        var finish: (@MainActor (Bool) -> Void)?
        world.testingPrepare = { _, callback in finish = callback }
        owner.attach(world)
        let controls = preparationControls(owner), window = preparationWindow()
        defer { owner.cancel(); window.isHidden = true }
        mountPreparation([world, controls], in: window)
        finish?(false); finish?(true)
        XCTAssertEqual(outcomes, 1)
        XCTAssertEqual(failure, .rendererFailed)
        XCTAssertNil(world.scene)
        XCTAssertNil(controls.controls.onAction)
        XCTAssertTrue(state.paused)
    }

    func testNetworkPreparationCancellationAndDetachDiscardLateSceneSuccess() throws {
        for detach in [false, true] {
            let state = try preparationSession()
            var successes = 0, failures = 0
            let owner = try DuelNetworkMatchPreparation(testing: state) { result in
                switch result { case .success: successes += 1; case .failure: failures += 1 }
            }
            let world = DuelWorldView(session: state, characterSource: .presentationFixture)
            var finish: (@MainActor (Bool) -> Void)?
            world.testingPrepare = { _, callback in finish = callback }
            owner.attach(world)
            let controls = preparationControls(owner), window = preparationWindow()
            mountPreparation([world, controls], in: window)
            if detach { world.removeFromSuperview() } else { owner.cancel() }
            finish?(true); finish?(false)
            XCTAssertEqual(successes, 0)
            XCTAssertEqual(failures, detach ? 1 : 0)
            XCTAssertNil(world.scene)
            XCTAssertNil(controls.controls.onInputCancelled)
            XCTAssertTrue(state.paused)
            owner.cancel(); window.isHidden = true
        }
    }

    func testNetworkPreparationDetectsSceneReplacementAndControlsDetach() throws {
        for replaceScene in [false, true] {
            let state = try preparationSession()
            var successes = 0, failures = 0
            let owner = try DuelNetworkMatchPreparation(testing: state) { result in
                switch result { case .success: successes += 1; case .failure: failures += 1 }
            }
            let world = DuelWorldView(session: state, characterSource: .presentationFixture)
            var finish: (@MainActor (Bool) -> Void)?
            world.testingPrepare = { _, callback in finish = callback }
            owner.attach(world)
            let controls = preparationControls(owner), window = preparationWindow()
            mountPreparation([world, controls], in: window)
            if replaceScene { world.scene = SCNScene(); finish?(true) }
            else { controls.removeFromSuperview(); finish?(true) }
            XCTAssertEqual(successes, 0); XCTAssertEqual(failures, 1)
            XCTAssertNil(world.scene)
            owner.cancel(); window.isHidden = true
        }
    }

    func testNetworkPreparationRevalidatesControlsLayoutWhileSceneIsPending() throws {
        let state = try preparationSession()
        var completed = 0
        let owner = try DuelNetworkMatchPreparation(testing: state) { _ in completed += 1 }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        var finish: (@MainActor (Bool) -> Void)?
        world.testingPrepare = { _, callback in finish = callback }
        owner.attach(world)
        let controls = preparationControls(owner), window = preparationWindow()
        defer { owner.cancel(); window.isHidden = true }
        mountPreparation([controls, world], in: window)
        XCTAssertTrue(controls.currentPreparationReady)
        controls.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        controls.setNeedsLayout(); controls.layoutIfNeeded()
        finish?(true)
        XCTAssertEqual(completed, 0, "Earlier controls readiness must not survive an unusable layout")
        controls.frame = window.bounds; controls.setNeedsLayout(); controls.layoutIfNeeded()
        XCTAssertEqual(completed, 1)
    }

    func testNetworkPreparationRevalidatesPreparedSceneAndCurrentRendererBounds() throws {
        for replaceScene in [false, true] {
            let state = try preparationSession()
            var successes = 0, failures = 0
            let owner = try DuelNetworkMatchPreparation(testing: state) { result in
                switch result { case .success: successes += 1; case .failure: failures += 1 }
            }
            let world = DuelWorldView(session: state, characterSource: .presentationFixture)
            world.testingPrepare = { _, callback in callback(true) }
            owner.attach(world)
            let controls = preparationControls(owner), window = preparationWindow()
            mountPreparation([world], in: window)
            if replaceScene { world.scene = SCNScene() }
            else { world.frame = .zero }
            mountPreparation([controls], in: window)
            XCTAssertEqual(successes, 0)
            if replaceScene {
                XCTAssertEqual(failures, 1)
                XCTAssertNil(world.scene)
            } else {
                XCTAssertEqual(failures, 0)
                world.frame = window.bounds; world.setNeedsLayout(); world.layoutIfNeeded()
                XCTAssertEqual(successes, 1)
            }
            owner.cancel(); window.isHidden = true
        }
    }

    func testNetworkPreparationCannotReuseSessionOrCancelNewMount() throws {
        let first = try preparationSession()
        let old = try DuelNetworkMatchPreparation(testing: first) { _ in }
        XCTAssertThrowsError(try DuelNetworkMatchPreparation(testing: first) { _ in })
        let second = try preparationSession()
        var freshFailures = 0, freshStops = 0, freshResets = 0
        let fresh = try DuelNetworkMatchPreparation(testing: second) { result in
            if case .failure = result { freshFailures += 1 }
        }
        defer { old.cancel(); fresh.cancel() }
        let world = DuelWorldView(session: second, characterSource: .presentationFixture)
        fresh.attach(world)
        second.didRequestAuthoritativeStop = { freshStops += 1 }
        second.inputReset = { freshResets += 1 }
        old.cancel(); old.cancel()
        XCTAssertNotNil(world.scene)
        XCTAssertTrue(second.awaitingNetworkPreparation)
        XCTAssertFalse(first.awaitingNetworkPreparation)
        second.inputReset?()
        XCTAssertEqual(freshResets, 1)
        XCTAssertNotNil(second.didRequestAuthoritativeStop)
        second.pause()
        XCTAssertEqual(freshStops, 1, "Old mount cleanup cannot replace a newer session's stop hook")
        XCTAssertEqual(freshFailures, 1, "Old mount cleanup cannot remove the newer pending lifecycle hook")
    }

    func testNetworkPreparationReentrantCancelSuppressesPreparedCallback() throws {
        let state = try preparationSession()
        var delivered = 0
        let owner = try DuelNetworkMatchPreparation(testing: state) { _ in delivered += 1 }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        world.testingPrepare = { _, callback in callback(true) }
        owner.attach(world)
        let controls = preparationControls(owner), window = preparationWindow()
        let subscription = owner.objectWillChange.sink {
            if case .prepared = owner.state { owner.cancel() }
        }
        defer { subscription.cancel(); owner.cancel(); window.isHidden = true }
        mountPreparation([world, controls], in: window)
        XCTAssertEqual(delivered, 0)
        XCTAssertEqual(owner.state, .cancelled)
        XCTAssertNil(world.scene)
    }

    func testNetworkPreparationRevalidatesAfterSynchronousPreparedObservers() throws {
        for mutation in ["scene", "bounds", "controls", "start"] {
            let state = try preparationSession()
            var successes = 0, failures: [DuelNetworkMatchPreparation.Failure] = []
            let owner = try DuelNetworkMatchPreparation(testing: state) { result in
                switch result { case .success: successes += 1; case .failure(let error): failures.append(error) }
            }
            let world = DuelWorldView(session: state, characterSource: .presentationFixture)
            world.testingPrepare = { _, callback in callback(true) }
            owner.attach(world)
            let controls = preparationControls(owner), window = preparationWindow()
            let subscription = owner.objectWillChange.sink {
                guard case .prepared = owner.state else { return }
                switch mutation {
                case "scene": world.scene = SCNScene()
                case "bounds": world.frame = .zero
                case "controls": controls.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
                default:
                    do { try state.startAuthoritativePresentation() }
                    catch { XCTFail("Fixture observer start unexpectedly failed: \(error)") }
                }
            }
            mountPreparation([world, controls], in: window)
            XCTAssertEqual(successes, 0)
            XCTAssertEqual(failures, [mutation == "start" ? .invalidSession : .replaced])
            XCTAssertTrue(state.paused)
            XCTAssertNil(world.scene)
            subscription.cancel(); owner.cancel(); window.isHidden = true
        }
    }

    func testNetworkPreparationKeepsPostReceiptInvalidationAndExitOneShot() throws {
        let state = try preparationSession()
        var completed = 0, invalidations = 0, exits = 0
        let owner = try DuelNetworkMatchPreparation(testing: state, invalidated: { _ in invalidations += 1 }) {
            _ in completed += 1
        }
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        world.testingPrepare = { _, callback in callback(true) }
        owner.attach(world)
        let controls = preparationControls(owner), window = preparationWindow()
        defer { owner.cancel(); window.isHidden = true }
        mountPreparation([world, controls], in: window)
        XCTAssertEqual(completed, 1)
        controls.removeFromSuperview(); world.removeFromSuperview()
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(invalidations, 1)
        owner.requestExit { exits += 1 }; owner.requestExit { exits += 1 }
        XCTAssertEqual(exits, 1)
        XCTAssertNil(world.scene)
    }

    func testNetworkPreparationRealSceneKitPrepareIncludesSyntheticShaderVariants() async throws {
        let state = try preparationSession()
        let world = DuelWorldView(session: state, characterSource: .presentationFixture)
        try world.installPreparationEffectFixtures()
        let prepared = expectation(description: "Mounted SceneKit prepare completion")
        var receipt: DuelWorldView.PreparationReceipt?, failure: DuelWorldView.PreparationFailure?
        try world.prepareNetworkScene(owner: UUID()) { result in
            switch result { case .success(let value): receipt = value; case .failure(let error): failure = error }
            prepared.fulfill()
        }
        let window = preparationWindow()
        defer { world.shutdown(); state.shutdown(); window.isHidden = true }
        mountPreparation([world], in: window)
        await fulfillment(of: [prepared], timeout: 15)
        XCTAssertNil(failure)
        XCTAssertTrue(world.usedActualScenePreparation, "The fixture still exercises the real SceneKit completion")
        XCTAssertTrue(world.usesSyntheticPresentationResources)
        XCTAssertFalse(world.attemptedBundledStageLoad)
        XCTAssertNil(world.stageAsset)
        XCTAssertEqual(receipt?.initialScenePrepared, true)
        XCTAssertEqual(receipt?.runtimeEffectVariantsPrepared, true)
        XCTAssertEqual(state.game.frame, 0)
        XCTAssertTrue(state.paused)
        XCTAssertEqual(world.sourceEffects?.playedSounds, 0)
        XCTAssertEqual(world.sourceEffects?.activeBurstCount, 0)
        XCTAssertEqual(world.weaponEffects?.retainedTrailCount, 0)
    }

    func testNetworkPreparationSwiftUIMountExistsBeforeCoordinatorPresentation() throws {
        let state = try preparationSession()
        let owner = try DuelNetworkMatchPreparation(testing: state) { _ in }
        let view = DuelMatchView(external: owner, onExit: {})
        let controller = UIHostingController(rootView: view)
        let window = preparationWindow()
        defer { owner.cancel(); window.isHidden = true }
        window.rootViewController = controller
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }
        let worlds = allViews(controller.view).compactMap { $0 as? DuelWorldView }
        XCTAssertEqual(worlds.count, 1)
        XCTAssertTrue(worlds.first?.represents(state) == true)
        XCTAssertTrue(worlds.first?.usesSyntheticPresentationResources == true)
        XCTAssertTrue(worlds.first?.attemptedBundledStageLoad == false)
        XCTAssertNil(worlds.first?.stageAsset)
        XCTAssertTrue(state.paused)
        XCTAssertEqual(state.game.frame, 0)
    }

    func testNetworkEffectPreparationHasStableTemplatesAndNoRuntimeSideEffects() throws {
        let root = SCNNode()
        let source = DuelSourceEffects.preparationFixture(root: root)
        let weapon = DuelWeaponEffects.preparationFixture(root: root)
        let children = root.childNodes.count
        var objects = source.preparationObjects() + weapon.preparationObjects()
        let geometries = try objects.map { try XCTUnwrap($0 as? SCNGeometry) }
        XCTAssertEqual(geometries.count, 69)
        XCTAssertTrue(geometries.allSatisfy { $0.firstMaterial?.shaderModifiers?[.fragment] != nil })
        let identities = geometries.map(ObjectIdentifier.init)
        XCTAssertEqual((source.preparationObjects() + weapon.preparationObjects()).compactMap { $0 as? SCNGeometry }
            .map(ObjectIdentifier.init), identities)
        XCTAssertEqual(root.childNodes.count, children)
        XCTAssertEqual(source.emittedHits, 0); XCTAssertEqual(source.emittedBlocks, 0)
        XCTAssertEqual(source.playedSounds, 0); XCTAssertEqual(source.sourceAudioCount, 0)
        XCTAssertEqual(weapon.emittedSampleCount, 0); XCTAssertEqual(weapon.retainedTrailCount, 0)
        source.reset(); weapon.reset()
        XCTAssertEqual((source.preparationObjects() + weapon.preparationObjects()).compactMap { $0 as? SCNGeometry }
            .map(ObjectIdentifier.init), identities)
        source.shutdown(); weapon.shutdown(); objects.removeAll()
        XCTAssertTrue(source.preparationObjects().isEmpty)
        XCTAssertTrue(weapon.preparationObjects().isEmpty)
    }

    func testNetworkEffectRuntimeCopiesKeepPreparedMaterialUniformsIndependent() throws {
        let root = SCNNode()
        let source = DuelSourceEffects.preparationFixture(root: root)
        let weapon = DuelWeaponEffects.preparationFixture(root: root)
        defer { source.shutdown(); weapon.shutdown() }
        let sourceMaterials = source.preparationObjects().compactMap { ($0 as? SCNGeometry)?.firstMaterial }
        let weaponMaterials = weapon.preparationObjects().compactMap { ($0 as? SCNGeometry)?.firstMaterial }
        let sourceTransforms = sourceMaterials.map { $0.diffuse.contentsTransform }
        source.emit(kind: .hit, position: SCNVector3Zero, direction: 1, tick: 0)
        source.advance(to: 1)
        let burst = try XCTUnwrap(root.childNodes.first { $0.name == "duel.source-effect.hit.1" })
        let liveSource = burst.childNodes.compactMap { $0.geometry?.firstMaterial }
        XCTAssertFalse(liveSource.isEmpty)
        XCTAssertTrue(liveSource.allSatisfy { material in !sourceMaterials.contains { $0 === material } })
        for (material, transform) in zip(sourceMaterials, sourceTransforms) {
            XCTAssertTrue(SCNMatrix4EqualToMatrix4(material.diffuse.contentsTransform, transform))
        }
        let endpoints: [DuelWeaponEffects.Endpoints] = [.init(slot: 0, base: SCNVector3Zero, tip: SCNVector3(0, 1, 0))]
        weapon.consumeStep(poses: [.init(fighterID: 0, family: .katana, motionID: nil, isShadow: false, endpoints: endpoints)], animationTick: 0)
        weapon.consumeStep(poses: [.init(fighterID: 0, family: .katana, motionID: "fixture", isShadow: false, endpoints: endpoints)], animationTick: 1)
        let trail = try XCTUnwrap(root.childNode(withName: "duel.weapon-effects", recursively: false)?.childNodes.first)
        let liveWeapon = try XCTUnwrap(trail.childNodes.first?.geometry?.firstMaterial)
        XCTAssertFalse(weaponMaterials.contains { $0 === liveWeapon })
        XCTAssertTrue(weaponMaterials.allSatisfy { ($0.value(forKey: "sourceTime") as? NSNumber)?.doubleValue == 0 })
        XCTAssertGreaterThan((liveWeapon.value(forKey: "sourceTime") as? NSNumber)?.doubleValue ?? 0, 0)
        XCTAssertEqual(source.playedSounds, 0, "Synthetic runtime fixtures contain no audio players")
    }
}
#endif

