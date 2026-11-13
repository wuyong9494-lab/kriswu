import XCTest
import UIKit
import SceneKit
import Combine
@testable import ShiftReminder

#if DEBUG
/// These production-path cases require the approved installed originals. There
/// is deliberately no synthetic identity/payload factory or hash-pin override.
@MainActor
extension DuelLifecycleTests {
    private func verifiedResources() throws -> DuelNetworkPreparedResources {
        guard DuelWeaponAssets.catalogURL() != nil else {
            throw XCTSkip("Approved original fighter resources are not installed")
        }
        return try DuelNetworkCompatibilityIdentity.prepare()
    }
    private func verifiedBarrier(_ prepared: DuelNetworkPreparedResources, guest: Bool = false,
                                 incompatible: Bool = false) throws -> DuelNetworkStartBarrier {
        let sessionID = "verified-preparation", hostID = "z-host", guestID = "a-guest"
        let compatibility = incompatible ? DuelNetworkStartBarrier.Compatibility(
            rulesFingerprint: String(repeating: "0", count: 64),
            catalogFingerprint: prepared.identity.compatibility.catalogFingerprint) : prepared.identity.compatibility
        var selection = try DuelMultiplayerSelection(sessionID: sessionID, hostID: hostID, guestID: guestID)
        let commands: [(String, UInt64, DuelMultiplayerSelection.Command)] = [
            (hostID, 1, .select(.sun)), (guestID, 1, .select(.liu)),
            (hostID, 2, .ready(true, selectionRevision: 2)), (guestID, 2, .ready(true, selectionRevision: 2)),
            (hostID, 3, .start(selectionRevision: 2))
        ]
        for (sender, sequence, command) in commands {
            XCTAssertEqual(selection.apply(.init(sessionID: sessionID, sequence: sequence, command: command),
                authenticatedSenderID: sender, localPlayerID: hostID), .applied)
        }
        var host = try DuelNetworkStartBarrier(started: selection.snapshot, sessionID: sessionID,
            hostID: hostID, guestID: guestID, localPlayerID: hostID, compatibility: compatibility)
        var peer = try DuelNetworkStartBarrier(started: selection.snapshot, sessionID: sessionID,
            hostID: hostID, guestID: guestID, localPlayerID: guestID, compatibility: compatibility)
        let offer = try host.makeOffer(startID: "verified-start", seed: 73, sequence: 1)
        XCTAssertEqual(peer.receive(try offer.encoded(), authenticatedSenderID: hostID), .applied)
        let configuration = try XCTUnwrap(host.offeredConfiguration)
        let hostLoaded = try host.confirmLoaded(configuration: configuration,
            loadedCompatibility: compatibility, catalog: prepared.identity.catalog, sequence: 2)
        let peerLoaded = try peer.confirmLoaded(configuration: configuration,
            loadedCompatibility: compatibility, catalog: prepared.identity.catalog, sequence: 1)
        XCTAssertEqual(host.receive(try peerLoaded.encoded(), authenticatedSenderID: guestID), .applied)
        XCTAssertEqual(peer.receive(try hostLoaded.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(peer.receive(try host.commit(sequence: 3).encoded(), authenticatedSenderID: hostID), .applied)
        return guest ? peer : host
    }
    private func verifiedWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.frame = window.bounds
        window.makeKeyAndVisible()
        return window
    }
    private func mountVerified(_ views: [UIView], in window: UIWindow) {
        for view in views {
            view.frame = window.bounds
            window.rootViewController?.view.addSubview(view)
            view.setNeedsLayout(); view.layoutIfNeeded()
        }
    }

    func testVerifiedPreparationRetainsAllOriginalObjectsAndReleasesPayloadOnce() throws {
        let clocks = DuelWorldView.activeClocks
        let prepared = try verifiedResources()
        let identity = prepared.identity
        weak var manager = prepared.assets
        weak var ember = prepared.loadedCharacter(for: .ember)
        weak var liu = prepared.loadedCharacter(for: .liu)
        weak var stage = prepared.stage
        weak var effects = prepared.sourceEffects
        weak var trails = prepared.weaponEffects
        XCTAssertEqual(identity.verifiedFiles.count, 62)
        XCTAssertEqual(identity.catalog.profiles.count, 2)
        XCTAssertTrue(prepared.hasExactResources)
        XCTAssertNotNil(ember); XCTAssertNotNil(liu)
        XCTAssertTrue(ember === prepared.assets?.loadedCharacter(for: .ember))
        XCTAssertTrue(liu === prepared.assets?.loadedCharacter(for: .liu))
        XCTAssertNil(prepared.effectsRoot?.parent)
        XCTAssertFalse(try XCTUnwrap(prepared.controls).inputEnabled)
        XCTAssertEqual(prepared.sourceEffects?.playedSounds, 0)
        XCTAssertEqual(prepared.weaponEffects?.emittedSampleCount, 0)
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
        prepared.release(); prepared.release()
        XCTAssertTrue(prepared.isReleased)
        XCTAssertFalse(prepared.hasExactResources)
        XCTAssertNil(prepared.assets); XCTAssertNil(prepared.controls); XCTAssertNil(prepared.stage)
        XCTAssertNil(prepared.effectsRoot); XCTAssertNil(prepared.sourceEffects); XCTAssertNil(prepared.weaponEffects)
        XCTAssertNil(manager); XCTAssertNil(ember); XCTAssertNil(liu); XCTAssertNil(stage)
        XCTAssertNil(effects); XCTAssertNil(trails)
        XCTAssertEqual(prepared.identity.compatibility, identity.compatibility)
        XCTAssertEqual(prepared.identity.verifiedFiles, identity.verifiedFiles)
        XCTAssertThrowsError(try prepared.reserveSession())
    }

    func testVerifiedPreparationReservesBeforeSecondSessionAndRejectsSecondMount() throws {
        let prepared = try verifiedResources()
        defer { prepared.release() }
        let barrier = try verifiedBarrier(prepared)
        let state = try DuelSession.networkPresentation(committed: barrier, prepared: prepared)
        let assets = try XCTUnwrap(state.weaponAssets)
        let ember = try XCTUnwrap(assets.loadedCharacter(for: .ember))
        XCTAssertThrowsError(try DuelSession.networkPresentation(committed: barrier, prepared: prepared))
        XCTAssertThrowsError(try DuelSession.networkPresentation(committed: barrier,
            verified: prepared.identity, assets: assets), "Legacy teardown may not adopt this manager")
        XCTAssertTrue(state.hasLiveVerifiedResources)
        XCTAssertTrue(assets.loadedCharacter(for: .ember) === ember)
        XCTAssertTrue(state.awaitingNetworkPreparation)
        let owner = try DuelNetworkMatchPreparation(session: state, prepared: prepared) { _ in }
        defer { owner.cancel() }
        XCTAssertThrowsError(try DuelNetworkMatchPreparation(session: state, prepared: prepared) { _ in })
        XCTAssertThrowsError(try DuelNetworkMatchPreparation(session: state) { _ in })
        XCTAssertThrowsError(try DuelNetworkMatchPreparation(testing: state) { _ in })
        let world = DuelWorldView(session: state)
        owner.attach(world)
        let root = try XCTUnwrap(prepared.effectsRoot)
        let duplicate = DuelWorldView(session: state)
        XCTAssertNil(duplicate.scene)
        duplicate.shutdown()
        XCTAssertNotNil(world.scene)
        XCTAssertTrue(root.parent === world.scene?.rootNode)
        XCTAssertTrue(state.hasLiveVerifiedResources)
        XCTAssertTrue(world.hasVerifiedResourceIdentity)
    }

    func testVerifiedPreparationRejectsIncompatibleFactoryAndDropsReservedResources() throws {
        let prepared = try verifiedResources()
        let barrier = try verifiedBarrier(prepared, incompatible: true)
        XCTAssertThrowsError(try DuelSession.networkPresentation(committed: barrier, prepared: prepared))
        XCTAssertTrue(prepared.isReleased)
        XCTAssertNil(prepared.assets)
        XCTAssertThrowsError(try prepared.reserveSession())
    }

    func testVerifiedPreparationCacheMissDoesNotReloadInstalledCharacter() throws {
        let prepared = try verifiedResources()
        defer { prepared.release() }
        let barrier = try verifiedBarrier(prepared)
        let state = try DuelSession.networkPresentation(committed: barrier, prepared: prepared)
        let owner = try DuelNetworkMatchPreparation(session: state, prepared: prepared) { _ in }
        defer { owner.cancel() }
        let manager = try XCTUnwrap(prepared.assets)
        let profile = try XCTUnwrap(manager.catalog.profile(for: .ember))
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            manager.directory.appendingPathComponent(profile.resourceName + ".glb").path))
        manager.releaseCharacter(for: .ember)
        XCTAssertNil(manager.loadedCharacter(for: .ember))
        XCTAssertNil(prepared.loadedCharacter(for: .ember))
        XCTAssertFalse(state.hasLiveVerifiedResources)
        let world = DuelWorldView(session: state)
        XCTAssertNil(world.scene)
        XCTAssertNil(manager.loadedCharacter(for: .ember), "Full-path world must not reload even when original file exists")
        owner.attach(world)
        XCTAssertTrue(prepared.isReleased)
        XCTAssertTrue(state.paused)
    }

    func testVerifiedPreparationReleaseWhileRendererPendingDiscardsLateCallbacks() throws {
        let prepared = try verifiedResources()
        weak var releasedCharacter = prepared.loadedCharacter(for: .ember)
        weak var releasedStage = prepared.stage
        let state = try DuelSession.networkPresentation(committed: verifiedBarrier(prepared), prepared: prepared)
        var successes = 0, failures = 0
        let owner = try DuelNetworkMatchPreparation(session: state, prepared: prepared) { result in
            switch result {
            case .success: successes += 1
            case .failure:
                failures += 1
                XCTAssertTrue(prepared.isReleased)
                XCTAssertNil(releasedCharacter, "Failure callbacks must not retain the old payload's characters")
                XCTAssertNil(releasedStage)
                prepared.release()
            }
        }
        let world = DuelWorldView(session: state)
        var finish: (@MainActor (Bool) -> Void)?
        world.testingPrepare = { _, callback in finish = callback }
        owner.attach(world)
        let controls = DuelNetworkControlsView(preparation: owner), window = verifiedWindow()
        defer { owner.cancel(); window.isHidden = true }
        XCTAssertTrue(controls.controls === prepared.controls)
        mountVerified([world, controls], in: window)
        XCTAssertNotNil(finish)
        state.inputReset = { prepared.release() }
        prepared.release(); prepared.release(); finish?(true); finish?(false)
        XCTAssertEqual(successes, 0); XCTAssertEqual(failures, 1)
        XCTAssertTrue(prepared.isReleased)
        XCTAssertNil(world.scene); XCTAssertNil(world.stageAsset); XCTAssertNil(world.verifiedEffectsRoot)
        XCTAssertNil(state.weaponAssets); XCTAssertNil(state.preparedResources)
        XCTAssertNil(controls.controls.onAction)
        XCTAssertNil(controls.controls.onGuard)
        XCTAssertTrue(state.paused)
        let lateWorld = DuelWorldView(session: state)
        XCTAssertNil(lateWorld.scene, "Released session must not reopen Bundle.main")
    }

    func testVerifiedPreparationRealSceneKitAndOriginalControlsCompleteSameOwner() async throws {
        let prepared = try verifiedResources()
        let state = try DuelSession.networkPresentation(committed: verifiedBarrier(prepared, guest: true), prepared: prepared)
        let completed = expectation(description: "Original verified scene/control preparation")
        var receipt: DuelNetworkMatchPreparation.Receipt?, failure: DuelNetworkMatchPreparation.Failure?
        let owner = try DuelNetworkMatchPreparation(session: state, prepared: prepared) { result in
            switch result { case .success(let value): receipt = value; case .failure(let value): failure = value }
            completed.fulfill()
        }
        let world = DuelWorldView(session: state)
        owner.attach(world)
        let controls = DuelNetworkControlsView(preparation: owner), window = verifiedWindow()
        defer { owner.cancel(); window.isHidden = true }
        mountVerified([world, controls], in: window)
        await fulfillment(of: [completed], timeout: 30)
        XCTAssertNil(failure)
        XCTAssertEqual(receipt?.verifiedResourceOwnershipComplete, true)
        XCTAssertEqual(receipt?.initialScenePrepared, true)
        XCTAssertEqual(receipt?.runtimeEffectVariantsPrepared, true)
        XCTAssertEqual(receipt?.controlsPrepared, true)
        XCTAssertTrue(world.usedActualScenePreparation)
        XCTAssertTrue(world.stageAsset === prepared.stage)
        XCTAssertTrue(world.sourceEffects === prepared.sourceEffects)
        XCTAssertTrue(world.weaponEffects === prepared.weaponEffects)
        XCTAssertTrue(controls.controls === prepared.controls)
        XCTAssertTrue(prepared.effectsRoot?.parent === world.scene?.rootNode)
        for hero in [DuelGame.Hero.ember, .liu] {
            XCTAssertTrue(world.weaponAssets[hero] === prepared.loadedCharacter(for: hero))
        }
        XCTAssertEqual(state.localFighterIndex, 1)
        XCTAssertTrue(state.hasLiveVerifiedResources)
        XCTAssertTrue(state.paused)
        XCTAssertEqual(state.nextPresentationTick, 0)
        XCTAssertEqual(state.game.frame, 0)
        XCTAssertEqual(prepared.sourceEffects?.playedSounds, 0)
        XCTAssertEqual(prepared.weaponEffects?.emittedSampleCount, 0)
        owner.cancel()
        XCTAssertTrue(prepared.isReleased)
        XCTAssertNil(world.scene); XCTAssertNil(state.preparedResources)
    }

    func testVerifiedPreparationRechecksRootAndLiveClaimAfterPreparedObservers() async throws {
        for mutation in ["root", "release", "weaponContainer"] {
            let prepared = try verifiedResources()
            let state = try DuelSession.networkPresentation(committed: verifiedBarrier(prepared), prepared: prepared)
            let completed = expectation(description: "Reentrant original-owner invalidation")
            var successes = 0, failures = 0
            let owner = try DuelNetworkMatchPreparation(session: state, prepared: prepared) { result in
                switch result { case .success: successes += 1; case .failure: failures += 1 }
                completed.fulfill()
            }
            let world = DuelWorldView(session: state)
            owner.attach(world)
            let controls = DuelNetworkControlsView(preparation: owner), window = verifiedWindow()
            let subscription = owner.objectWillChange.sink {
                guard case .prepared = owner.state else { return }
                switch mutation {
                case "release": prepared.release()
                case "weaponContainer":
                    guard let root = prepared.effectsRoot,
                          let container = root.childNode(withName: "duel.weapon-effects", recursively: false) else {
                        XCTFail("Missing verified weapon container before observer mutation")
                        return
                    }
                    container.removeFromParentNode()
                    let impostor = SCNNode(); impostor.name = container.name
                    root.addChildNode(impostor)
                    XCTAssertEqual(prepared.weaponEffects?.hasLiveContainer(attachedTo: root), false)
                default: prepared.effectsRoot?.removeFromParentNode()
                }
            }
            mountVerified([world, controls], in: window)
            await fulfillment(of: [completed], timeout: 30)
            XCTAssertEqual(successes, 0); XCTAssertEqual(failures, 1)
            XCTAssertTrue(prepared.isReleased)
            XCTAssertNil(world.scene)
            XCTAssertTrue(state.paused)
            subscription.cancel(); owner.cancel(); window.isHidden = true
        }
    }

    func testVerifiedWeaponContainerChecksExactLiveParentNotNodeName() throws {
        let root = SCNNode(), other = SCNNode()
        let effects = DuelWeaponEffects.preparationFixture(root: root)
        defer { effects.shutdown() }
        let container = try XCTUnwrap(root.childNode(withName: "duel.weapon-effects", recursively: false))
        XCTAssertTrue(effects.hasLiveContainer(attachedTo: root))
        container.removeFromParentNode()
        let impostor = SCNNode(); impostor.name = container.name
        root.addChildNode(impostor)
        XCTAssertFalse(effects.hasLiveContainer(attachedTo: root))
        other.addChildNode(container)
        XCTAssertFalse(effects.hasLiveContainer(attachedTo: root))
        XCTAssertTrue(effects.hasLiveContainer(attachedTo: other))
        effects.shutdown()
        root.addChildNode(container)
        XCTAssertFalse(effects.hasLiveContainer(attachedTo: root), "A closed owner cannot regain readiness")
    }

    func testVerifiedPreparationMockRendererCannotIssueFullOwnershipReceipt() throws {
        let prepared = try verifiedResources()
        let state = try DuelSession.networkPresentation(committed: verifiedBarrier(prepared), prepared: prepared)
        var successes = 0, failures = 0
        let owner = try DuelNetworkMatchPreparation(session: state, prepared: prepared) { result in
            switch result { case .success: successes += 1; case .failure: failures += 1 }
        }
        let world = DuelWorldView(session: state)
        world.testingPrepare = { _, callback in callback(true) }
        owner.attach(world)
        let controls = DuelNetworkControlsView(preparation: owner), window = verifiedWindow()
        defer { owner.cancel(); window.isHidden = true }
        mountVerified([world, controls], in: window)
        XCTAssertEqual(successes, 0); XCTAssertEqual(failures, 1)
        XCTAssertTrue(prepared.isReleased)
    }
}
#endif
