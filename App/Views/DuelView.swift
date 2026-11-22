import SwiftUI
import UIKit
import QuartzCore
import AVFoundation
import Combine

struct DuelSetup: Identifiable {
    let id = UUID()
    let hero: DuelGame.Hero
    let difficulty: DuelGame.Difficulty
    let mode: DuelGame.Mode
    let originalWeapons: Bool
    let opponentHero: DuelGame.Hero
    init(hero: DuelGame.Hero, difficulty: DuelGame.Difficulty, mode: DuelGame.Mode, originalWeapons: Bool = false, opponentHero: DuelGame.Hero? = nil) {
        self.opponentHero = opponentHero ?? (hero == .liu ? .ember : .liu)
        self.hero = hero; self.difficulty = difficulty; self.mode = mode; self.originalWeapons = originalWeapons
    }
}

struct DuelDamagePopup: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case normal, critical, headshot, shadow, chip }
    let id: Int
    let amount: Int
    let kind: Kind
}

/// Shared input mailbox and low-frequency HUD. SceneKit owns its own view lifetime.
@MainActor
final class DuelSession: ObservableObject {
    enum Driver { case offline, externalAuthoritative }
    enum PresentationFailure: Error, Equatable {
        case invalidLocalFighterIndex, invalidRoster, invalidAssets, configurationMismatch
        case notExternal, notAwaitingStart, notRunning, outOfOrderStep, reentrantPublication, closed
    }
    private enum ExternalState { case awaitingStart, starting, running, stopped }

    let setup: DuelSetup
    let driver: Driver
    /// Host remains 0 and guest remains 1 on both devices. Never reorder game arrays.
    let localFighterIndex: Int
    let committedConfiguration: DuelNetworkStartBarrier.Configuration?
    private var externalState = ExternalState.awaitingStart
    private(set) var nextPresentationTick: UInt64 = 0
    private var authoritativeCancellationPublished = false
    private var resettingPhysicalInput = false
    private var offlinePauseEpoch: UInt64 = 0
    private var audioInterrupted = false
    private var requiresUserAudioResume = false
    private var performingUserAudioResume = false
    private var pausingOffline = false
    private var resumingOffline = false
    private var restartingOffline = false
    private var stoppingOfflineRenderer = false
    private var publishingAuthoritativeStep = false
    private var networkMountOwner: UUID?
    private var pendingNetworkPreparation: (owner: UUID, invalidated: () -> Void)?
    private(set) var game: DuelGame
    private(set) var held = Set<String>()
    private var taps: DuelGame.Buttons = []
    private var weaponInput = DuelWeaponInput()
    private var physicalInput = DuelPhysicalInput()
    private(set) var weaponAssets: DuelWeaponAssets?
    private(set) var preparedResources: DuelNetworkPreparedResources?
    private var preparedLocalPalace: DuelStageAsset.PreparedPalace?
    private var preparedSessionClaim: UUID?
    /// Remains true after release so a closed full-path session cannot fall back
    /// to a Bundle.main load when UIKit delivers a late view construction.
    private(set) var usesVerifiedPreparedResources = false
    @Published private(set) var loadError: String?
    @Published private(set) var paused = false
    @Published var showBoxes = false
    @Published private(set) var feedback = "保持距离，观察出手"
    @Published private(set) var shortCallout = ""
    @Published private(set) var sideDamagePopups: [DuelDamagePopup?] = [nil, nil]
    @Published private(set) var tutorialStep = 0
    @Published private(set) var report = ""
    var renderPause: ((Bool) -> Void)?
    var inputReset: (() -> Void)?
    var didSimulateStep: ((DuelGame, Int) -> Void)?
    var didReset: (() -> Void)?
    private weak var offlineWorld: DuelWorldView?
    private weak var musicWorld: DuelWorldView?
    private var publishedSourceMusicReadiness = false

    /// A paused flag is not proof that the intended stage actually loaded.
    /// Read the current renderer every time; stale Published callbacks cannot
    /// preserve readiness after replacement, load failure or session closure.
    var sourceMusicReady: Bool {
        !ended && loadError == nil && musicWorld?.hasPreparedSourceMusicScene == true
    }
    func refreshSourceMusicReadiness(from world: DuelWorldView) {
        guard musicWorld === world else { return }
        publishSourceMusicReadinessIfChanged()
    }
    private func publishSourceMusicReadinessIfChanged() {
        let ready = sourceMusicReady
        guard publishedSourceMusicReadiness != ready else { return }
        publishedSourceMusicReadiness = ready
        objectWillChange.send()
    }
    func releaseSourceMusicWorld(_ world: DuelWorldView) {
        guard musicWorld === world else { return }
        artworkControls?.setCharacterOcclusion([])
        musicWorld = nil
        publishSourceMusicReadinessIfChanged()
    }
    private weak var offlineControls: DuelSourceControlsView?
    private weak var artworkControls: DuelSourceControlsView?

    func bindArtworkControls(_ controls: DuelSourceControlsView) {
        guard acceptsWeaponControls(controls) else { return }
        artworkControls?.setCharacterOcclusion([])
        artworkControls = controls
    }

    func updateCharacterOcclusion(_ rectangles: [CGRect], from world: DuelWorldView) {
        guard !ended, musicWorld === world, let controls = artworkControls,
              acceptsWeaponControls(controls) else { return }
        guard let window = world.window, controls.window === window else {
            controls.setCharacterOcclusion([])
            return
        }
        // With only translations between the views, overlap fractions are
        // identical in either coordinate space. Convert at most four buttons
        // instead of every projected bone envelope on each display callback.
        if !rectangles.isEmpty,
           Self.hasTranslationOnlyPath(from: world.layer, to: window.layer),
           Self.hasTranslationOnlyPath(from: controls.layer, to: window.layer) {
            controls.setCharacterOcclusion(rectangles) { controls.convert($0, to: world) }
        } else {
            controls.setCharacterOcclusion(rectangles.map { world.convert($0, to: controls) })
        }
    }

    private static func hasTranslationOnlyPath(from layer: CALayer, to window: CALayer) -> Bool {
        var current = layer
        while current !== window {
            guard let parent = current.superlayer, !current.isGeometryFlipped, !parent.isGeometryFlipped,
                  CATransform3DIsIdentity(current.transform),
                  CATransform3DIsIdentity(parent.sublayerTransform) else { return false }
            current = parent
        }
        return true
    }


    /// UIKit may mount the replacement controls before dismantling the old
    /// ones. Only the live owner may write or clear the shared input mailbox.
    func claimOfflineControls(_ controls: DuelSourceControlsView) -> Bool {
        guard driver == .offline, !ended, !controls.isShutdown else { return false }
        if offlineControls === controls { return true }
        let previous = offlineControls
        offlineControls = controls
        previous?.shutdown()
        guard acceptsWeaponControls(controls) else { return false }
        clearInput()
        // Reset callbacks can synchronously close the session or claim a newer
        // view. A superseded bind must not overwrite that owner's callbacks.
        return acceptsWeaponControls(controls)
    }

    func acceptsWeaponControls(_ controls: DuelSourceControlsView) -> Bool {
        !ended && !controls.isShutdown && (driver != .offline || offlineControls === controls)
    }

    func releaseOfflineControls(_ controls: DuelSourceControlsView) {
        guard offlineControls === controls else { return }
        offlineControls = nil
        inputReset = nil
        clearInput()
    }

    /// SwiftUI may construct the replacement before dismantling the old view.
    /// Retire its clock and callbacks before installing the new renderer's hooks.
    /// Verified network renderers have their own preparation ownership contract.
    func claimOfflineWorld(_ world: DuelWorldView) -> Bool {
        guard driver == .offline, !ended else { return false }
        if offlineWorld === world { return true }
        let previous = offlineWorld
        offlineWorld = world
        musicWorld = world
        previous?.shutdown()
        // Clearing physical input during shutdown can synchronously close this
        // session or construct another renderer. Do not overwrite that owner.
        if !ended && offlineWorld === world { refreshSourceMusicReadiness(from: world) }
        return !ended && offlineWorld === world
    }

    func releaseOfflineWorld(_ world: DuelWorldView) {
        if offlineWorld === world { offlineWorld = nil }
    }

    /// Consume the immutable preparation once, only for the claimed offline world.
    func takePreparedLocalPalace(for world: DuelWorldView) -> DuelStageAsset.PreparedPalace? {
        guard driver == .offline, !ended, offlineWorld === world else { return nil }
        defer { preparedLocalPalace = nil }
        return preparedLocalPalace
    }
    /// A local interruption requests coordinator teardown. It is not permission
    /// to modify authoritative buffers or to resume this protocol-1 match.
    var didRequestAuthoritativeStop: (() -> Void)?
    private var feedbackUntil = 75
    private var shortCalloutUntil = 0
    private var popupUntil = [0, 0]
    private var popupSerial = 0
    private var serial = 0
    private var ended = false
    private(set) var animationTick = 0
    private(set) var characterStatus = ""
    private var practicedJump = false
    private var practicedSkills = Set<DuelGame.Move>()
    private let interruptions = DuelInterruptionObserver()
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    init(_ setup: DuelSetup, installedAssets: DuelWeaponAssets? = nil,
         verifiedIndex: DuelWeaponAssetIndex? = nil,
         preparedLocalPalace: DuelStageAsset.PreparedPalace? = nil) {
        self.setup = setup
        driver = .offline; localFighterIndex = 0; committedConfiguration = nil
        self.preparedLocalPalace = preparedLocalPalace
        var assets: DuelWeaponAssets?
        var failure: String?
        if setup.originalWeapons {
            do {
                // An explicit installed-directory store enables native
                // acceptance without mutating the signed app bundle. It must
                // retain the same full combat gates and cannot borrow a live
                // network preparation or a showroom-only manager.
                if let installedAssets {
                    guard installedAssets.purpose == .combat,
                          !installedAssets.belongsToVerifiedPreparation else {
                        throw PresentationFailure.invalidAssets
                    }
                    assets = installedAssets
                } else {
                    let index = try verifiedIndex ?? DuelWeaponAssetIndex()
                    assets = try DuelWeaponAssets(verifiedIndex: index, purpose: .localMatch(setup.hero, setup.opponentHero))
                }
            }
            catch { failure = "人物资源无法载入，请返回后重试。" }
        }
        weaponAssets = assets
        game = Self.localGame(for: setup, assets: assets)
        if setup.originalWeapons && game.weaponFight == nil { failure = "人物资源无法载入，请返回后重试。" }
        loadError = failure; paused = failure != nil
        observeInterruptions()
    }

    private static func localGame(for setup: DuelSetup, assets: DuelWeaponAssets?) -> DuelGame {
        if let assets, let game = try? assets.localGame(for: setup) { return game }
        return DuelGame(hero: setup.hero, difficulty: setup.difficulty, mode: setup.mode,
                        opponentHero: setup.opponentHero, ruleset: .shadowArena)
    }

    private init(presentation game: DuelGame, localFighterIndex: Int,
                 assets: DuelWeaponAssets?, configuration: DuelNetworkStartBarrier.Configuration?,
                 prepared: DuelNetworkPreparedResources? = nil, claim: UUID? = nil) throws {
        guard (0...1).contains(localFighterIndex) else { throw PresentationFailure.invalidLocalFighterIndex }
        guard game.fighters.count == 2 else { throw PresentationFailure.invalidRoster }
        setup = .init(hero: game.fighters[localFighterIndex].hero, difficulty: game.difficulty,
                      mode: game.mode, originalWeapons: game.weaponFight != nil)
        driver = .externalAuthoritative; self.localFighterIndex = localFighterIndex
        committedConfiguration = configuration; self.game = game; weaponAssets = assets
        preparedResources = prepared; preparedSessionClaim = claim
        usesVerifiedPreparedResources = prepared != nil
        paused = true
        observeInterruptions()
    }

    /// Production construction is deliberately separate from asset-free test
    /// presentation. A decoded configuration or a matching hero name is not enough.
    /// The coordinator must own this locally committed barrier and keep its
    /// cancellation/transport lifecycle live after construction.
    static func networkPresentation(committed barrier: DuelNetworkStartBarrier,
                                    verified identity: DuelNetworkCompatibilityIdentity,
                                    assets: DuelWeaponAssets) throws -> DuelSession {
        let networkCatalog = try assets.requireNetworkCatalog()
        // The old seam may not adopt the manager of a retained verifier owner.
        // Otherwise its independent teardown could erase a live full-path match.
        guard !assets.belongsToVerifiedPreparation,
              DuelMultiplayerSelection.Choice.availableIntended(in: networkCatalog).count == 2 else {
            throw PresentationFailure.invalidAssets
        }
        let configuration = try DuelNetworkCombatProtocol.configuration(
            from: barrier, host: barrier.localPlayerID == barrier.hostID,
            loadedCompatibility: identity.compatibility, catalog: networkCatalog)
        guard identity.catalog == networkCatalog else { throw PresentationFailure.invalidAssets }
        for hero in [configuration.host.choice.hero, configuration.guest.choice.hero] {
            _ = try assets.character(for: hero)
        }
        let game = DuelGame(hero: configuration.host.choice.hero, difficulty: configuration.difficulty,
                            mode: configuration.mode, seed: configuration.seed,
                            opponentHero: configuration.guest.choice.hero, weaponCatalog: networkCatalog)
        guard game.weaponFight != nil else { throw PresentationFailure.invalidAssets }
        return try DuelSession(presentation: game, localFighterIndex: barrier.localPlayerID == barrier.hostID ? 0 : 1,
                               assets: assets, configuration: configuration)
    }

    /// Full production path: consume a single reservation of the verifier's
    /// live objects. There are no file loads or cache-miss reloads in this factory.
    static func networkPresentation(committed barrier: DuelNetworkStartBarrier,
                                    prepared: DuelNetworkPreparedResources) throws -> DuelSession {
        // A duplicate call throws here, before constructing a session whose
        // failure/teardown could otherwise release the first session's assets.
        let claim = try prepared.reserveSession()
        do {
            guard let assets = prepared.assets else { throw PresentationFailure.invalidAssets }
            let networkCatalog = try assets.requireNetworkCatalog()
            let configuration = try DuelNetworkCombatProtocol.configuration(
                from: barrier, host: barrier.localPlayerID == barrier.hostID,
                loadedCompatibility: prepared.identity.compatibility, catalog: networkCatalog)
            guard prepared.hasExactResources, prepared.identity.catalog == networkCatalog,
                  DuelMultiplayerSelection.Choice.availableIntended(in: networkCatalog).count == 2 else {
                throw PresentationFailure.invalidAssets
            }
            for choice in [configuration.host.choice, configuration.guest.choice] {
                guard let character = prepared.loadedCharacter(for: choice.hero),
                      character.profile == networkCatalog.profile(for: choice.hero),
                      character.profile.id == choice.weapon.rawValue else { throw PresentationFailure.invalidAssets }
            }
            let game = DuelGame(hero: configuration.host.choice.hero, difficulty: configuration.difficulty,
                mode: configuration.mode, seed: configuration.seed,
                opponentHero: configuration.guest.choice.hero, weaponCatalog: networkCatalog)
            guard game.weaponFight != nil else { throw PresentationFailure.invalidAssets }
            let session = try DuelSession(presentation: game,
                localFighterIndex: barrier.localPlayerID == barrier.hostID ? 0 : 1,
                assets: assets, configuration: configuration, prepared: prepared, claim: claim)
            guard prepared.bindSession(claim, invalidated: { [weak session] in session?.shutdown() }),
                  session.hasLiveVerifiedResources else {
                session.shutdown()
                throw PresentationFailure.invalidAssets
            }
            return session
        } catch {
            prepared.release()
            throw error
        }
    }

    var hasLiveVerifiedResources: Bool {
        guard !ended, let preparedResources, let preparedSessionClaim,
              preparedResources.isLiveSession(preparedSessionClaim), preparedResources.hasExactResources,
              let assets = weaponAssets, preparedResources.assets === assets,
              let configuration = committedConfiguration,
              configuration.compatibility == preparedResources.identity.compatibility,
              assets.networkCatalog == preparedResources.identity.catalog,
              let fight = game.weaponFight, fight.profiles.count == 2,
              fight.profiles.allSatisfy(\.isIntendedCharacter) else { return false }
        let choices = [configuration.host.choice, configuration.guest.choice]
        return choices.enumerated().allSatisfy { index, choice in
            guard let character = preparedResources.loadedCharacter(for: choice.hero) else { return false }
            return game.fighters[index].hero == choice.hero && character.profile == fight.profiles[index] &&
                character.profile.id == choice.weapon.rawValue
        }
    }
    func claimPreparedWorld(_ world: DuelWorldView) -> Bool {
        guard hasLiveVerifiedResources, let preparedResources, let preparedSessionClaim,
              let networkMountOwner else { return false }
        guard preparedResources.claimWorld(world, session: preparedSessionClaim, owner: networkMountOwner) else { return false }
        musicWorld = world
        return true
    }
    func claimPreparedControls(_ controls: DuelNetworkControlsView, owner: UUID) -> Bool {
        guard hasLiveVerifiedResources, let preparedResources, let preparedSessionClaim,
              networkMountOwner == owner else { return false }
        return preparedResources.claimControls(controls, session: preparedSessionClaim, owner: owner)
    }
    func ownsVerifiedMount(world: DuelWorldView, controls: DuelNetworkControlsView, owner: UUID) -> Bool {
        guard hasLiveVerifiedResources, let preparedResources, let preparedSessionClaim,
              networkMountOwner == owner else { return false }
        return preparedResources.owns(world: world, controls: controls, session: preparedSessionClaim, owner: owner)
    }

    #if DEBUG
    private(set) var isPresentationFixture = false
    /// Synthetic native-test seam only. Not a network factory, asset-loader
    /// fallback, or authorization to display a playable multiplayer match.
    convenience init(presentationFixture game: DuelGame, localFighterIndex: Int) throws {
        try self.init(presentation: game, localFighterIndex: localFighterIndex, assets: nil, configuration: nil)
        isPresentationFixture = true
    }
    #endif

    private enum AudioEvent: Sendable { case began, ended, routeRemoved, servicesReset }
    private func receiveAudioEvent(_ event: AudioEvent) {
        guard !ended else { return }
        switch event {
        case .ended, .servicesReset:
            audioInterrupted = false
        case .began, .routeRemoved:
            if case .began = event { audioInterrupted = true }
            requiresUserAudioResume = true
            musicWorld?.sourceEffects?.suspendAudioForUserResume()
            // Includes retained, verified effects before a world has mounted.
            preparedResources?.sourceEffects?.suspendAudioForUserResume()
            pause() // Authoritative sessions retain their terminal stop semantics.
        }
    }
    private func observeInterruptions() {
        let center = NotificationCenter.default
        interruptions.tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: nil) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                let event: AudioEvent = type == .began ? .began : .ended
                DispatchQueue.main.async { [weak self] in self?.receiveAudioEvent(event) }
            })
        interruptions.tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: nil) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                DispatchQueue.main.async { [weak self] in self?.receiveAudioEvent(.routeRemoved) }
            })
        interruptions.tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: nil) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.receiveAudioEvent(.servicesReset) }
            })
    }
    var tutorial: String {
        return ["推动左侧八方向摇杆靠近对手（不动或后拉自动防守）",
                "点击武器/踢击键，配合方向施放上撩爆头、下扫或贴身投技",
                "向上推动摇杆跳跃，长按武器键蓄力重击",
                "点击远程键释放英雄战术技，蓄满能量按暗影键爆发形态技",
                "已完成：继续练习，或返回挑战电脑"][min(4, tutorialStep)]
    }
    var grappleStatus: String {
        guard let hold = game.grapple else { return "" }
        switch hold.stage {
        case .takedown: return "擒拿 · 抓肩摔倒"
        case .hold: return String(format: "锁臂压制 · %.1f 秒", Double(hold.holdRemaining) / 60)
        case .release: return "震地击退"
        }
    }
    var awaitingNetworkPreparation: Bool {
        driver == .externalAuthoritative && !ended && externalState == .awaitingStart &&
            paused && loadError == nil && nextPresentationTick == 0
    }
    func claimNetworkMount(_ owner: UUID, invalidated: @escaping () -> Void) -> Bool {
        guard awaitingNetworkPreparation, networkMountOwner == nil else { return false }
        if usesVerifiedPreparedResources {
            guard hasLiveVerifiedResources, let preparedResources, let preparedSessionClaim,
                  preparedResources.claimMount(session: preparedSessionClaim, owner: owner,
                                                invalidated: invalidated) else { return false }
        }
        networkMountOwner = owner
        pendingNetworkPreparation = (owner, invalidated)
        return true
    }
    func releaseNetworkPreparation(_ owner: UUID) {
        guard pendingNetworkPreparation?.owner == owner else { return }
        pendingNetworkPreparation = nil
    }
    private func takePendingNetworkPreparationInvalidation() -> (() -> Void)? {
        // Separate from the coordinator's stop callback, which is not installed
        // until loading finishes. Consume before calling out: failure teardown
        // can synchronously pause/shut down this session again.
        let callback = pendingNetworkPreparation?.invalidated
        pendingNetworkPreparation = nil
        return callback
    }

    var localFighter: DuelGame.Fighter { game.fighters[localFighterIndex] }
    var opponentFighterIndex: Int { 1 - localFighterIndex }
    var localLandedHits: Int { game.landedHits[localFighterIndex] }
    var localDamageDealt: Int { game.damageDealt[localFighterIndex] }
    var allowsLocalRestart: Bool { driver == .offline }
    var ultimateReady: Bool {
        guard game.grapple == nil else { return false }
        if let shogun = game.shogunState(localFighterIndex) {
            return shogun.canUseShadowAbility
        }
        if let inq = game.inquisitorState(localFighterIndex) {
            return inq.canEnterFormOfLight
        }
        if let nonna = game.nonnaState(localFighterIndex) {
            return localFighter.energy == 100 || nonna.canEnterFlameForm
        }
        if let mid = game.midnightState(localFighterIndex) {
            return mid.canUseRemoval
        }
        return localFighter.energy == 100
    }
    private var acceptsPhysicalInput: Bool {
        !ended && !paused && (driver != .offline || (!pausingOffline && !resumingOffline && !restartingOffline))
    }
    func input(_ name: String, down: Bool) {
        guard acceptsPhysicalInput else { return }
        if down {
            guard held.insert(name).inserted else { return }
            switch name {
            case "jump": taps.insert(.jump)
            case "light": taps.insert(.light)
            case "heavy": taps.insert(.heavy)
            case "skill1": taps.insert(.skill1)
            case "skill2": taps.insert(.skill2)
            case "ultimate": taps.insert(.ultimate)
            default: break
            }
        } else { held.remove(name) }
    }
    func weaponDirection(x: Int, y: Int) {
        var state = physicalInput["touch"]; state.x = x; state.y = y
        updatePhysicalInput(state, source: "touch")
    }
    func weaponAction(_ action: DuelWeaponInput.Action, down: Bool) {
        var state = physicalInput["touch"]
        if down { state.actions.insert(action) } else { state.actions.remove(action) }
        updatePhysicalInput(state, source: "touch")
    }
    func weaponGuard(_ held: Bool) {
        guard !held || acceptsPhysicalInput else { return }
        var state = physicalInput["touch"]; state.guardHeld = held
        updatePhysicalInput(state, source: "touch", cancelled: !held && !acceptsPhysicalInput)
    }
    func cancelWeaponAction(_ action: DuelWeaponInput.Action) {
        var state = physicalInput["touch"]; state.actions.remove(action)
        updatePhysicalInput(state, source: "touch", cancelled: true)
    }
    func updatePhysicalInput(_ state: DuelPhysicalInput.State, source: String, cancelled: Bool = false) {
        guard acceptsPhysicalInput || cancelled else { return }
        let previousSource = physicalInput[source]
        guard previousSource != state else { return }
        let previous = physicalInput.combined
        physicalInput.set(state, source: source)
        let next = physicalInput.combined
        // Guard is owned by the union of touch and connected peripherals.
        weaponInput.setGuardHeld(next.guardHeld)
        // Cancellation must not become an attack-on-release.
        for action in DuelWeaponInput.Action.allCases where previous.actions.contains(action) && !next.actions.contains(action) {
            if cancelled { weaponInput.cancel(action: action) }
            else { weaponInput.action(action, down: false) }
        }
        let losesIntent = previous.x != next.x || previous.y != next.y ||
            !previous.actions.subtracting(next.actions).isEmpty
        if cancelled && losesIntent {
            weaponInput.cancelPendingMotion(x: next.x, y: next.y)
        } else if previous.x != next.x || previous.y != next.y {
            weaponInput.direction(x: next.x, y: next.y)
        }
        for action in DuelWeaponInput.Action.allCases where !previous.actions.contains(action) && next.actions.contains(action) {
            weaponInput.action(action, down: true)
        }
    }
    func cancelWeaponInput() {
        physicalInput.reset()
        weaponInput.cancelAll()
        if driver == .offline { game.cancelBufferedInputs() }
    }
    func clearInput() {
        held.removeAll(); taps = []; physicalInput.reset(); weaponInput.cancelAll()
        // Guest touch cancellation, view teardown and local interruptions may
        // never erase the host's already accepted combo/hit-stop buffers.
        if driver == .offline { game.cancelBufferedInputs() }
        // Reset hooks can synchronously pause/shut down and clear input again.
        guard !resettingPhysicalInput else { return }
        resettingPhysicalInput = true
        defer { resettingPhysicalInput = false }
        inputReset?()
    }
    func pause() {
        guard driver == .externalAuthoritative else {
            // Reserve before callbacks, including when paused's willSet still
            // exposes its old value. Any stop invalidates an outer resume.
            offlinePauseEpoch &+= 1
            guard !pausingOffline else { stopOfflineRenderer(); return }
            pausingOffline = true
            defer { pausingOffline = false }
            clearInput()
            if !paused { paused = true }
            stopOfflineRenderer()
            return
        }
        // Reserve the terminal transition before invoking ANY callback. Capture
        // the single stop notification so nested shutdown cannot erase it.
        let shouldNotify = externalState != .stopped
        let pauseRender = shouldNotify ? renderPause : nil
        let requestStop = shouldNotify ? didRequestAuthoritativeStop : nil
        externalState = .stopped
        // A nested pause may run inside Published's willSet while its old
        // value is still false. Only the owner of the transition writes it.
        if shouldNotify && !paused { paused = true }
        takePendingNetworkPreparationInvalidation()?()
        clearInput()
        pauseRender?(true)
        requestStop?()
    }
    private func stopOfflineRenderer() {
        // Nested shutdown must still stop the renderer before clearing its
        // callback, but a stop callback that pauses again must not recurse.
        guard !stoppingOfflineRenderer else { return }
        stoppingOfflineRenderer = true
        defer { stoppingOfflineRenderer = false }
        renderPause?(true)
    }
    func resume() {
        guard !restartingOffline else { return }
        resumeOffline()
    }
    /// Audio consent must follow a successful explicit UI action, not an
    /// automatic readiness change or an interrupted/reentrant resume attempt.
    func performUserResume(restarting: Bool = false) -> Bool {
        guard driver == .offline, !ended, loadError == nil,
              !pausingOffline, !resumingOffline, !restartingOffline, !audioInterrupted,
              (!requiresUserAudioResume || UIApplication.shared.applicationState == .active) else { return false }
        performingUserAudioResume = true
        defer { performingUserAudioResume = false }
        let epoch = offlinePauseEpoch
        if restarting { restart() } else { resume() }
        guard canCompleteOfflineTransition(epoch), !paused,
              !pausingOffline, !resumingOffline, !restartingOffline else { return false }
        requiresUserAudioResume = false
        musicWorld?.sourceEffects?.resumeAudioAfterUserAction(sessionInterruptionEnded: !audioInterrupted)
        return true
    }
    private func resumeOffline() {
        guard driver == .offline, !ended, loadError == nil, !pausingOffline, !resumingOffline else { return }
        resumingOffline = true
        defer { resumingOffline = false }
        let epoch = offlinePauseEpoch
        clearInput()
        guard canCompleteOfflineTransition(epoch) else { return }
        if paused { paused = false }
        // Published notifies synchronously before assigning false. A nested
        // pause/shutdown can otherwise be overwritten by that stale assignment.
        guard canCompleteOfflineTransition(epoch) else { pause(); return }
        renderPause?(false)
    }
    private func canCompleteOfflineTransition(_ epoch: UInt64) -> Bool {
        !ended && loadError == nil && offlinePauseEpoch == epoch && !audioInterrupted &&
            (!requiresUserAudioResume || performingUserAudioResume)
    }
    func restart() {
        guard allowsLocalRestart, !ended, !pausingOffline, !resumingOffline, !restartingOffline else { return }
        restartingOffline = true
        defer { restartingOffline = false }
        let epoch = offlinePauseEpoch
        clearInput()
        guard canCompleteOfflineTransition(epoch) else { return }
        let restartedGame = Self.localGame(for: setup, assets: weaponAssets)
        guard !setup.originalWeapons || restartedGame.weaponFight != nil else {
            // A character can be quarantined after the initial catalog was
            // accepted. Preserve the previous fight and stop; a nil catalog
            // must never turn Restart into a legacy/procedural match.
            characterFailed()
            return
        }
        feedback = "保持距离，观察出手"
        shortCallout = ""
        sideDamagePopups = [nil, nil]
        guard canCompleteOfflineTransition(epoch) else { return }
        tutorialStep = 0
        guard canCompleteOfflineTransition(epoch) else { return }
        // Install game and animation bookkeeping together, after the HUD's
        // reentrant publications. An interrupted HUD update must not leave a
        // fresh game paired with the previous round's animation/effect state.
        game = restartedGame
        serial = 0; animationTick = 0; feedbackUntil = 75; shortCalloutUntil = 0; popupUntil = [0, 0]
        practicedJump = false; practicedSkills.removeAll(); didReset?()
        guard canCompleteOfflineTransition(epoch) else { return }
        resumeOffline()
        guard canCompleteOfflineTransition(epoch), !paused else { return }
        didSimulateStep?(game, 0)
        guard canCompleteOfflineTransition(epoch), !paused else { return }
        objectWillChange.send()
    }

    /// One physical-input sample, in world coordinates, resolved against the
    /// local seat's current authoritative facing and airborne state. Consumes
    /// edges exactly once but never advances the simulation or clears its buffers.
    func weaponControlPreview(_ command: DuelWeaponCommand) -> DuelGame.Input {
        .init(move: weaponInput.x, vertical: weaponInput.y, weaponCommand: command)
    }
    func consumeLocalInput() -> DuelGame.Input {
        guard acceptsPhysicalInput else { return .neutral }
        let useWeaponInput = setup.originalWeapons || game.ruleset == .shadowArena
        var input: DuelGame.Input
        if useWeaponInput {
            let airborne = game.weaponFight?.isAirborne(localFighterIndex) ?? (localFighter.y > 0 || localFighter.velocityY > 0)
            input = weaponInput.consume(facing: localFighter.facing, airborne: airborne)
            input.heavyHeld = weaponInput.isPressed(.weapon)
            if !taps.isEmpty { input.taps.formUnion(taps) }
        } else {
            input = DuelGame.Input(move: (held.contains("right") ? 1 : 0) - (held.contains("left") ? 1 : 0),
                                   guardHeld: held.contains("guard"), taps: taps,
                                   heavyHeld: held.contains("heavy"))
        }
        if setup.originalWeapons, localFighter.hero == .wuYong { input.taps.formUnion(taps.intersection(.skill1)) }
        taps = []
        return input
    }

    /// Existing display-link entry point. External presentation has no local
    /// clock authority, AI fallback or input drain while waiting for host frames.
    func advance() {
        guard driver == .offline, acceptsPhysicalInput else { return }
        if case .matchOver = game.phase { return }
        let input = consumeLocalInput()
        let frozen = game.hitStop > 0 && game.grapple == nil
        // The engine drops entrance inputs and unlocks at this step's entry.
        // Inspect its resulting state only to suppress premature tutorial credit.
        game.step(input)
        let tutorialInput = game.weaponFight?.sourceIntroActive == true ? DuelGame.Input.neutral : input
        presentStep(input: tutorialInput, frozen: frozen)
    }

    /// Only the coordinator can enable initial input/rendering after its load
    /// and commit checks. An interruption is terminal; this cannot resume it.
    func startAuthoritativePresentation() throws {
        guard driver == .externalAuthoritative else { throw PresentationFailure.notExternal }
        guard !ended, loadError == nil else { throw PresentationFailure.closed }
        guard externalState == .awaitingStart else { throw PresentationFailure.notAwaitingStart }
        // Input-reset callbacks may stop, shut down, or try to start again.
        // Reserving start rejects nesting without reopening a terminal state.
        externalState = .starting
        clearInput()
        guard !ended, loadError == nil, externalState == .starting else { throw PresentationFailure.closed }
        externalState = .running
        paused = false
        // Published-property observers and the renderer callback are reentrant
        // too. A stop always wins, even if it happened inside paused's setter.
        guard canPresentStep else {
            if !paused { paused = true }
            throw PresentationFailure.closed
        }
        renderPause?(false)
        guard canPresentStep else { throw PresentationFailure.closed }
    }

    /// Publish ONE already validated host/replay step, in fixed host-first order.
    /// The caller owns wire validation and must supply every consumed tick, not
    /// just the last state of a multi-frame batch. This is not a wire-state API.
    func publishAuthoritativeStep(trustedGame: DuelGame, tick: UInt64) throws {
        guard driver == .externalAuthoritative else { throw PresentationFailure.notExternal }
        guard !ended else { throw PresentationFailure.closed }
        guard !publishingAuthoritativeStep else { throw PresentationFailure.reentrantPublication }
        guard externalState == .running else { throw PresentationFailure.notRunning }
        // Core wrappers may still consume inbox ticks after a finished game,
        // whose final event list is retained. Never re-emit that final hit/result.
        if case .matchOver = game.phase { throw PresentationFailure.notRunning }
        guard tick == nextPresentationTick, tick < UInt64.max else { throw PresentationFailure.outOfOrderStep }
        try validatePresentation(trustedGame)
        publishingAuthoritativeStep = true
        defer { publishingAuthoritativeStep = false }
        let frozen = game.hitStop > 0 && game.grapple == nil
        game = trustedGame; nextPresentationTick += 1
        presentStep(input: .neutral, frozen: frozen)
    }

    /// Canonical cancellation is supplied by the coordinator AFTER it cancels
    /// its host/replay wrapper. Local physical clear/pause never fabricates it.
    /// May arrive after a local stop request, but never after session teardown.
    func publishAuthoritativeCancellation(trustedGame: DuelGame) throws {
        guard driver == .externalAuthoritative else { throw PresentationFailure.notExternal }
        guard !ended, !authoritativeCancellationPublished else { throw PresentationFailure.closed }
        try validatePresentation(trustedGame)
        game = trustedGame; authoritativeCancellationPublished = true
        externalState = .stopped
        if !paused { paused = true }
        takePendingNetworkPreparationInvalidation()?()
        clearInput()
        guard !ended else { return }
        renderPause?(true)
        // Cancellation is not a simulation step: do not replay the last hit's
        // effects/haptics or increment the presentation/animation counters.
        objectWillChange.send()
    }

    private func validatePresentation(_ value: DuelGame) throws {
        guard value.fighters.map(\.hero) == game.fighters.map(\.hero),
              value.mode == game.mode, value.difficulty == game.difficulty,
              value.weaponFight?.profiles == game.weaponFight?.profiles else {
            throw PresentationFailure.configurationMismatch
        }
    }

    private var canPresentStep: Bool {
        !ended && (driver == .offline || (externalState == .running && !paused))
    }

    private func presentStep(input: DuelGame.Input, frozen: Bool) {
        // A renderer callback must never make this step read a newer or
        // cancelled game's event list. External nested publication is rejected;
        // explicit cancellation remains permitted and ends feedback immediately.
        let presentedGame = game
        serial += 1
        if !frozen { animationTick += 1 }
        didSimulateStep?(presentedGame, animationTick)
        guard canPresentStep else { return }
        if setup.mode == .tutorial {
            if tutorialStep == 0 && input.move != 0 { tutorialStep = 1 }
            if tutorialStep == 1 && presentedGame.landedHits[localFighterIndex] > 0 { tutorialStep = 2 }
            if tutorialStep == 2 {
                if presentedGame.events.contains(.jumped(player: localFighterIndex)) { practicedJump = true }
                if practicedJump && presentedGame.fighters[localFighterIndex].guarding { tutorialStep = 3 }
            }
            if tutorialStep == 3 && setup.originalWeapons, input.weaponCommand == .kick || input.weaponCommand == .shadow { tutorialStep = 4 }
            if tutorialStep == 3, let attack = presentedGame.fighters[localFighterIndex].attack,
               attack.move == .skill1 || attack.move == .skill2 {
                practicedSkills.insert(attack.move)
                if practicedSkills.count == 2 { tutorialStep = 4 }
            }
        }
        if presentedGame.weaponFight?.missedMeleeSeats.contains(localFighterIndex) == true {
            feedback = "未命中 · 留意距离与时机"
            feedbackUntil = presentedGame.frame + 75
        }
        func recordDamage(defender: Int, amount: Int, kind: DuelDamagePopup.Kind) {
            guard amount > 0, (0..<2).contains(defender) else { return }
            popupSerial &+= 1
            sideDamagePopups[defender] = DuelDamagePopup(id: popupSerial, amount: amount, kind: kind)
            popupUntil[defender] = presentedGame.frame + 54
        }
        func setMajorCallout(_ text: String) {
            shortCallout = text
            shortCalloutUntil = presentedGame.frame + 48
        }
        for event in presentedGame.events {
            guard canPresentStep else { return }
            switch event {
            case .hit(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "命中 −\(damage)" : "受到攻击 −\(damage)"
                let shadowHit = presentedGame.shogunState(attacker)?.isInShadow == true ||
                    presentedGame.midnightState(attacker)?.isInShadowForm == true
                recordDamage(defender: 1 - attacker, amount: damage, kind: shadowHit ? .shadow : .normal)
            case .blocked(let defender):
                feedback = defender == localFighterIndex ? "防御成功" : "对手防御成功"
            case .guardBreak(let defender):
                feedback = defender == localFighterIndex ? "防御被击破" : "击破对手防御"
                setMajorCallout("破防!")
            case .whiff(let attacker): if attacker == localFighterIndex { feedback = "未命中 · 留意距离与前摇" }
            case .jumped: break
            case .grappleStarted(let attacker):
                feedback = attacker == localFighterIndex ? "擒拿成功 · 抓肩摔倒" : "被对手擒拿 · 抓肩摔倒"
                setMajorCallout("擒拿!")
            case .grappleSlam(let attacker): feedback = attacker == localFighterIndex ? "锁臂压制 · 3 秒" : "被锁臂压制 · 3 秒"; if canPresentStep { impact.impactOccurred(intensity: 0.6) }
            case .grappleReleased(let attacker): feedback = attacker == localFighterIndex ? "震地击退" : "被震地击退"; if canPresentStep { impact.impactOccurred(intensity: 0.9) }
            case .grappleClash: feedback = "双方抓取相抵 · 拉开距离"
            case .shogunShadowForm(let fighter):
                feedback = fighter == localFighterIndex ? "暗影入体 · 暗影技就绪" : "对手进入暗影形态"
                setMajorCallout("暗影形态")
                if canPresentStep { impact.impactOccurred(intensity: 0.65) }
            case .shogunCataclysm(let fighter):
                feedback = fighter == localFighterIndex ? "暗影灾变爆发 · 决杀一击！" : "对手爆发暗影灾变！"
                setMajorCallout("暗影灾变")
                if canPresentStep { impact.impactOccurred(intensity: 1.0) }
            case .shogunCataclysmStrike(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "暗影决杀 −\(damage)!" : "遭到暗影决杀 −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .critical)
                setMajorCallout("暗影决杀!")
                if canPresentStep { impact.impactOccurred(intensity: 1.0) }
            case .shogunCompanionHit(let owner, let damage):
                feedback = owner == localFighterIndex ? "死士突袭眩晕 −\(damage)" : "被死士突袭眩晕 −\(damage)"
                recordDamage(defender: 1 - owner, amount: damage, kind: .shadow)
                setMajorCallout("死士突袭")
                if canPresentStep { impact.impactOccurred(intensity: 0.7) }
            case .shogunArmorAbsorbed(let defender):
                feedback = defender == localFighterIndex ? "霸体吸收攻击" : "对手霸体硬抗"
            case .shogunRevived(let fighter):
                feedback = fighter == localFighterIndex ? "压迫领主 · 死士代死重生！" : "对手死士代死重生！"
                setMajorCallout("死士代死")
                if canPresentStep { impact.impactOccurred(intensity: 0.95) }
            case .shogunCritical(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "暴击重创 −\(damage)!" : "遭受暴击重创 −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .critical)
                setMajorCallout("暴击!")
                if canPresentStep { impact.impactOccurred(intensity: 0.9) }
            case .inquisitorStigmataApplied(let defender):
                feedback = defender == localFighterIndex ? "身中圣痕 · 击中对方可驱散" : "圣痕烙印 · 圣光吸血燃能"
                if canPresentStep { impact.impactOccurred(intensity: 0.6) }
            case .inquisitorStigmataFlash(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "圣痕引爆浮空 −\(damage)!" : "圣痕爆发浮空 −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .critical)
                setMajorCallout("圣痕引爆!")
                if canPresentStep { impact.impactOccurred(intensity: 0.95) }
            case .inquisitorFormOfLight(let fighter):
                feedback = fighter == localFighterIndex ? "圣光形态降临 · 全攻击破防！" : "对手开启圣光形态！"
                setMajorCallout("圣光形态")
                if canPresentStep { impact.impactOccurred(intensity: 0.9) }
            case .nonnaFlameForm(let fighter):
                feedback = fighter == localFighterIndex ? "烈焰形态爆发 · 真身破防！" : "对手爆发烈焰形态！"
                setMajorCallout("烈焰形态")
                if canPresentStep { impact.impactOccurred(intensity: 0.9) }
            case .nonnaWolfHit(let owner, let damage):
                feedback = owner == localFighterIndex ? "花焰灵狼扑杀 −\(damage)" : "被花焰灵狼扑击 −\(damage)"
                recordDamage(defender: 1 - owner, amount: damage, kind: .normal)
                if canPresentStep { impact.impactOccurred(intensity: 0.7) }
            case .nonnaOwlHit(let owner, let damage, let returned):
                recordDamage(defender: 1 - owner, amount: damage, kind: returned ? .critical : .normal)
                if returned {
                    feedback = owner == localFighterIndex ? "灵枭召回定身 −\(damage)!" : "被灵枭回飞定身 −\(damage)!"
                    setMajorCallout("灵枭定身!")
                    if canPresentStep { impact.impactOccurred(intensity: 0.85) }
                } else {
                    feedback = owner == localFighterIndex ? "灵枭扑击 −\(damage) · 再按召回" : "被灵枭锁定 −\(damage)"
                    if canPresentStep { impact.impactOccurred(intensity: 0.55) }
                }
            case .nonnaTrueShapeExecute(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "弱肉强食 · 烈焰真身斩杀 −\(damage)!" : "遭到烈焰真身斩杀 −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .critical)
                setMajorCallout("真身斩杀!")
                if canPresentStep { impact.impactOccurred(intensity: 1.0) }
            case .midnightShadowShift(let fighter):
                feedback = fighter == localFighterIndex ? "影移虚化 · 闪避回影" : "对手影移虚化！"
                setMajorCallout("影移虚化")
                if canPresentStep { impact.impactOccurred(intensity: 0.45) }
            case .midnightBlinkCounter(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "瞬闪背刺反击 −\(damage) · 回血！" : "遭到瞬闪背刺反击 −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .shadow)
                setMajorCallout("瞬闪反击!")
                if canPresentStep { impact.impactOccurred(intensity: 0.95) }
            case .midnightRemovalStrike(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "暗影抹除 −\(damage) · 清空对手能量！" : "遭到暗影抹除 −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .shadow)
                setMajorCallout("暗影抹除!")
                if canPresentStep { impact.impactOccurred(intensity: 1.0) }
            case .headHit(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "爆头命中 −\(damage)!" : "遭到爆头重击 −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .headshot)
                setMajorCallout("爆头!")
                if canPresentStep { impact.impactOccurred(intensity: 0.85) }
            case .criticalHit(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "暴击击倒 −\(damage)!" : "遭受暴击击倒 −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .critical)
                setMajorCallout("暴击!")
                if canPresentStep { impact.impactOccurred(intensity: 0.95) }
            case .chipDamage(let attacker, let damage):
                feedback = attacker == localFighterIndex ? "对手自动格挡 · 穿透 −\(damage)" : "自动格挡 · 穿透 −\(damage)"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .chip)
                if canPresentStep { impact.impactOccurred(intensity: 0.35) }
            case .throwHit(let attacker, let damage, let backThrow):
                let kind = backThrow ? "过肩背投" : "近身前投"
                feedback = attacker == localFighterIndex ? "\(kind)破防 −\(damage)!" : "遭到\(kind) −\(damage)!"
                recordDamage(defender: 1 - attacker, amount: damage, kind: .critical)
                setMajorCallout(backThrow ? "背投!" : "破防投!")
                if canPresentStep { impact.impactOccurred(intensity: 0.90) }
            case .inquisitorSalvationEcho(let attacker, _, let damage):
                if damage > 0 {
                    feedback = attacker == localFighterIndex ? "圣光意志二段天罚 −\(damage)!" : "遭到圣光二段天罚 −\(damage)!"
                    recordDamage(defender: 1 - attacker, amount: damage, kind: .critical)
                    setMajorCallout("圣光天罚!")
                    if canPresentStep { impact.impactOccurred(intensity: 0.85) }
                }
            case .roundEnded(let winner):
                feedback = winner == nil ? "平局 · 重赛" : winner == localFighterIndex ? "拿下一局" : "对手拿下一局"
                shortCallout = ""
                sideDamagePopups = [nil, nil]
            }
            guard canPresentStep else { return }
            feedbackUntil = presentedGame.frame + 75
        }
        guard canPresentStep else { return }
        if presentedGame.frame > feedbackUntil && !feedback.isEmpty { feedback = "" }
        if presentedGame.frame > shortCalloutUntil && !shortCallout.isEmpty { shortCallout = "" }
        for side in 0..<2 where presentedGame.frame > popupUntil[side] && sideDamagePopups[side] != nil {
            sideDamagePopups[side] = nil
        }
        if serial % 6 == 0 || !presentedGame.events.isEmpty { objectWillChange.send() }
    }
    func metrics(_ value: String) { report = value }
    func characterLoaded(_ status: String) { characterStatus = status }
    func characterFailed() { loadError = "人物资源无法载入，请返回后重试。"; pause() }
    func shutdown() {
        guard !ended else { return }
        ended = true
        preparedLocalPalace = nil
        musicWorld = nil
        let controls = offlineControls; offlineControls = nil
        controls?.shutdown()
        // Delay this pending-only notification until shutdown releases assets.
        // Its failure callback may immediately start loading a fresh match.
        let preparationInvalidated = takePendingNetworkPreparationInvalidation()
        pause(); renderPause = nil; inputReset = nil; didSimulateStep = nil; didReset = nil
        didRequestAuthoritativeStop = nil
        if usesVerifiedPreparedResources {
            let prepared = preparedResources
            preparedResources = nil; preparedSessionClaim = nil
            prepared?.release()
        } else {
            weaponAssets?.releaseCharacters()
        }
        // UIKit can retain the closed SceneKit view and its session until a
        // later event. Release the resource owner at teardown, not at deinit.
        weaponAssets = nil
        preparationInvalidated?()
    }
}

// Own the non-Sendable observer in a nonisolated object, so its destruction does
// not read actor-isolated session state under Swift's complete concurrency checks.
private final class DuelInterruptionObserver {
    var tokens: [NSObjectProtocol] = []
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}

/// Retained before mounting, independently of coordinator.presentation. A
/// successful milestone is renderer/control preparation, not verified loading
/// or permission to start. The loader must retain this owner until teardown.
// The explicit publisher is actor-confined too. Xcode 26's Swift 6.2+
// isolated conformance keeps its ObservableObject witness on MainActor rather
// than exporting a non-Sendable publisher through a nonisolated requirement.
@MainActor
final class DuelNetworkMatchPreparation: @MainActor ObservableObject, Identifiable {
    enum Failure: Error, Equatable {
        case invalidSession, alreadyOwned, rendererFailed, controlsUnavailable, detached, replaced
    }
    struct Receipt: Equatable {
        let owner: UUID
        let initialScenePrepared: Bool
        let runtimeEffectVariantsPrepared: Bool
        let controlsPrepared: Bool
        /// True only for a live single-session verifier owner, exact retained
        /// objects and attached roots after actual scene/control preparation.
        let verifiedResourceOwnershipComplete: Bool
    }
    enum State: Equatable { case waitingForMount, preparing, prepared(Receipt), failed(Failure), cancelled }
    typealias Completion = @MainActor (Result<Receipt, Failure>) -> Void
    let objectWillChange = ObservableObjectPublisher()
    let id = UUID()
    let session: DuelSession
    private(set) var state = State.waitingForMount
    private var completion: Completion?
    private var invalidated: (@MainActor (Failure) -> Void)?
    private var exitRequested = false
    private weak var world: DuelWorldView?
    private weak var controls: DuelNetworkControlsView?
    private var sceneReceipt: DuelWorldView.PreparationReceipt?
    private var controlsPrepared = false
    private var completing = false
    private(set) var permitsFixture = false
    private var closed = false
    private let requiresVerifiedOwnership: Bool

    init(session: DuelSession, prepared: DuelNetworkPreparedResources,
         invalidated: (@MainActor (Failure) -> Void)? = nil,
         completion: @escaping Completion) throws {
        guard session.awaitingNetworkPreparation, session.preparedResources === prepared,
              session.hasLiveVerifiedResources else { throw Failure.invalidSession }
        self.session = session; self.completion = completion; self.invalidated = invalidated
        requiresVerifiedOwnership = true
        guard session.claimNetworkMount(id, invalidated: { [weak self] in self?.fail(.invalidSession) }) else {
            throw Failure.alreadyOwned
        }
    }

    /// Retained legacy seam. It can prepare a scene but never issue a full
    /// verified-resource receipt. Full-path sessions require the owner overload.
    init(session: DuelSession, invalidated: (@MainActor (Failure) -> Void)? = nil,
         completion: @escaping Completion) throws {
        guard session.awaitingNetworkPreparation, !session.usesVerifiedPreparedResources,
              session.committedConfiguration != nil, session.weaponAssets != nil,
              session.game.weaponFight != nil else { throw Failure.invalidSession }
        self.session = session; self.completion = completion; self.invalidated = invalidated
        requiresVerifiedOwnership = false
        guard session.claimNetworkMount(id, invalidated: { [weak self] in self?.fail(.invalidSession) }) else {
            throw Failure.alreadyOwned
        }
    }
    #if DEBUG
    init(testing session: DuelSession, invalidated: (@MainActor (Failure) -> Void)? = nil,
         completion: @escaping Completion) throws {
        guard session.isPresentationFixture, session.awaitingNetworkPreparation,
              !session.usesVerifiedPreparedResources else { throw Failure.invalidSession }
        self.session = session; self.completion = completion; self.invalidated = invalidated; permitsFixture = true
        requiresVerifiedOwnership = false
        guard session.claimNetworkMount(id, invalidated: { [weak self] in self?.fail(.invalidSession) }) else {
            throw Failure.alreadyOwned
        }
    }
    #endif

    #if DEBUG
    var preparationPhaseDescription: String {
        "state=\(state), closed=\(closed), sceneReceipt=\(sceneReceipt != nil), controlsPrepared=\(controlsPrepared), " +
        "world=[\(world?.preparationPhaseDescription ?? "not attached")], " +
        "controls=[\(controls?.preparationPhaseDescription ?? "not attached")]"
    }
    #endif
    var loadingText: String {
        switch state {
        case .waitingForMount: return "正在安装联机画面与操作界面"
        case .preparing: return "正在准备联机画面"
        case .prepared: return "画面已准备，等待资源确认与联机开始"
        case .failed: return "联机画面准备失败，请退出重试"
        case .cancelled: return "联机准备已结束"
        }
    }
    func attach(_ view: DuelWorldView) {
        guard view.represents(session) else { fail(.replaced); return }
        guard !closed, world == nil else { view.shutdown(); fail(.replaced); return }
        world = view
        state = .preparing; objectWillChange.send()
        guard !closed else { view.shutdown(); return }
        do {
            try view.prepareNetworkScene(owner: id, invalidated: { [weak self] failure in
                self?.fail(failure == .detached ? .detached : failure == .rendererFailed ? .rendererFailed : .replaced)
            }, changed: { [weak self] in self?.finishIfPrepared() }) { [weak self, weak view] result in
                guard let self, let view, !self.closed, self.world === view else { return }
                switch result {
                case .failure(let error): self.fail(error == .detached ? .detached : .rendererFailed)
                case .success(let receipt):
                    guard receipt.owner == self.id else { self.fail(.replaced); return }
                    self.sceneReceipt = receipt
                    self.finishIfPrepared()
                }
            }
        } catch { fail(.rendererFailed) }
    }
    func attach(_ view: DuelNetworkControlsView) -> Bool {
        guard !closed, controls == nil, view.ownerID == id else { fail(.replaced); return false }
        if requiresVerifiedOwnership, !session.claimPreparedControls(view, owner: id) {
            fail(.replaced); return false
        }
        controls = view
        return true
    }
    func controlsDidPrepare(_ view: DuelNetworkControlsView) {
        guard !closed, controls === view else { return }
        controlsPrepared = true
        finishIfPrepared()
    }
    func controlsDidFail(_ view: DuelNetworkControlsView, detached: Bool = false) {
        guard !closed, controls === view else { return }
        fail(detached ? .detached : .controlsUnavailable)
    }
    private func finishIfPrepared() {
        guard !closed, !completing, completion != nil else { return }
        guard session.awaitingNetworkPreparation else { fail(.invalidSession); return }
        guard controlsPrepared, let sceneReceipt, let world, let controls else { return }
        guard world.hasPreparedSceneIdentity(owner: id) else { fail(.replaced); return }
        guard world.hasUsableMountedBounds, controls.currentPreparationReady else { return }
        let verified = verifiedOwnership(world: world, controls: controls, sceneReceipt: sceneReceipt)
        guard !requiresVerifiedOwnership || verified else { fail(.replaced); return }
        // Reserve this completion before publishing. Observers may synchronously
        // mutate layout/scene/session or cancel; revalidate after they return.
        guard let callback = completion else { return }
        completing = true
        defer { completing = false }
        let receipt = Receipt(owner: id, initialScenePrepared: sceneReceipt.initialScenePrepared,
            runtimeEffectVariantsPrepared: sceneReceipt.runtimeEffectVariantsPrepared,
            controlsPrepared: true, verifiedResourceOwnershipComplete: verified)
        state = .prepared(receipt); objectWillChange.send()
        guard !closed else { return }
        guard session.awaitingNetworkPreparation else { fail(.invalidSession); return }
        guard world.hasPreparedSceneIdentity(owner: id), world.hasUsableMountedBounds,
              controls.currentPreparationReady,
              !requiresVerifiedOwnership || verifiedOwnership(world: world, controls: controls,
                                                               sceneReceipt: sceneReceipt) else {
            fail(.replaced); return
        }
        completion = nil
        // The completion may synchronously install the coordinator stop hook
        // and start the match. This pending-only hook must no longer own it.
        session.releaseNetworkPreparation(id)
        callback(.success(receipt))
    }
    private func verifiedOwnership(world: DuelWorldView, controls: DuelNetworkControlsView,
                                   sceneReceipt: DuelWorldView.PreparationReceipt) -> Bool {
        requiresVerifiedOwnership && !permitsFixture && sceneReceipt.initialScenePrepared &&
            sceneReceipt.runtimeEffectVariantsPrepared && world.usedActualScenePreparation &&
            session.ownsVerifiedMount(world: world, controls: controls, owner: id) &&
            world.hasVerifiedResourceIdentity && controls.hasVerifiedResourceIdentity
    }
    func fail(_ failure: Failure) {
        guard !closed else { return }
        closed = true
        let callback = completion, onInvalidated = invalidated
        completion = nil; invalidated = nil
        state = .failed(failure)
        dispose()
        objectWillChange.send()
        if let callback { callback(.failure(failure)) }
        else { onInvalidated?(failure) }
    }
    func requestExit(_ action: () -> Void) {
        guard !exitRequested else { return }
        exitRequested = true
        cancel(); action()
    }
    func cancel() {
        guard !closed else { return }
        closed = true; completion = nil; invalidated = nil; state = .cancelled
        dispose(); objectWillChange.send()
    }
    private func dispose() {
        // Invalidate before any UIKit/session callbacks. These objects belong
        // only to this mount; a new match must use a fresh session and owner.
        let oldWorld = world, oldControls = controls
        world = nil; controls = nil; sceneReceipt = nil
        session.releaseNetworkPreparation(id)
        oldControls?.shutdown(); oldWorld?.shutdown(); session.shutdown()
    }
}

struct DuelMatchView: View {
    private let setup: DuelSetup?
    private let preparation: DuelNetworkMatchPreparation?
    private let onExit: (() -> Void)?
    private let verifiedIndex: DuelWeaponAssetIndex?
    init(setup: DuelSetup, verifiedIndex: DuelWeaponAssetIndex? = nil) {
        self.setup = setup; self.verifiedIndex = verifiedIndex; preparation = nil; onExit = nil
    }
    init(external preparation: DuelNetworkMatchPreparation, onExit: @escaping () -> Void) {
        setup = nil; verifiedIndex = nil; self.preparation = preparation; self.onExit = onExit
    }
    @ViewBuilder var body: some View {
        if let preparation, let onExit {
            DuelNetworkMatchContent(preparation: preparation, onExit: onExit).id(preparation.id)
        } else if let setup {
            if setup.originalWeapons && (setup.hero == .ember || setup.opponentHero == .ember) {
                DuelPreparingLocalMatch(setup: setup, verifiedIndex: verifiedIndex).id(setup.id)
                    .modifier(ArenaLandscape())
            } else if !setup.originalWeapons {
                DuelPreparingOriginalMatch(setup: setup, verifiedIndex: verifiedIndex).id(setup.id)
            } else {
                DuelOfflineMatchContent(setup: setup, verifiedIndex: verifiedIndex)
            }
        }
    }
}

/// Ensures both Shadow Arena fighters, procedural VFX textures, and PCM SFX buffers are
/// warmed off the main thread before mounting `DuelWorld`. When the lobby already prewarmed
/// both fighters into memory, `ready` starts `true` so match entry is instant (0 extra frames).
@MainActor
private struct DuelPreparingOriginalMatch: View {
    let setup: DuelSetup
    let verifiedIndex: DuelWeaponAssetIndex?
    @State private var ready: Bool

    init(setup: DuelSetup, verifiedIndex: DuelWeaponAssetIndex?) {
        self.setup = setup
        self.verifiedIndex = verifiedIndex
        let heroes = Array(Set([setup.hero, setup.opponentHero]))
        let allCached = heroes.allSatisfy {
            DuelCascadeurCharacterAsset.bundledURL(for: $0) == nil ||
            DuelCascadeurCharacterAsset.cached(for: $0) != nil
        }
        _ready = State(initialValue: allCached)
    }

    var body: some View {
        if ready {
            DuelOfflineMatchContent(setup: setup, verifiedIndex: verifiedIndex)
        } else {
            VStack(spacing: 16) {
                ProgressView("正在准备武者…")
                    .tint(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(Color(red: 0.045, green: 0.055, blue: 0.10).ignoresSafeArea())
            .accessibilityIdentifier("duel.match.preparation")
            .task {
                DuelOriginalSound.shared.prewarmAsync()
                await DuelProceduralVFXAssets.prepareAsync()
                for hero in Array(Set([setup.hero, setup.opponentHero])) {
                    _ = await DuelCascadeurCharacterAsset.loadBundledAsync(for: hero)
                }
                if !Task.isCancelled {
                    ready = true
                }
            }
        }
    }
}

@MainActor
final class DuelLocalMatchPreparationGate {
    private var request: UUID?
    private var left = false

    func begin(active: Bool) -> UUID? {
        guard active, !left, !Task.isCancelled else { return nil }
        let id = UUID()
        request = id
        return id
    }

    func suspend() { request = nil }

    func leave() {
        left = true
        suspend()
    }

    func finish(_ id: UUID, active: Bool, _ publish: () -> Void) {
        guard active, !left, !Task.isCancelled, request == id else { return }
        request = nil
        publish()
    }
}

@MainActor
private struct DuelPreparingLocalMatch: View {
    let setup: DuelSetup
    let verifiedIndex: DuelWeaponAssetIndex?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: DuelSession?
    @State private var failed = false
    @State private var gate = DuelLocalMatchPreparationGate()

    var body: some View {
        if let session {
            DuelMatchContent(session: session)
        } else {
            VStack(spacing: 18) {
                if failed {
                    Text("人物资源无法载入，请返回后重试。")
                } else {
                    ProgressView("正在加载对局资源")
                }
                Button("返回大厅") {
                    gate.leave()
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .tint(.white)
            .background(Color.black.ignoresSafeArea())
            .accessibilityIdentifier("duel.match.preparation")
            .onDisappear { gate.suspend() }
            .onChange(of: scenePhase) { phase in
                if phase != .active { gate.suspend() }
            }
            .task(id: scenePhase) {
                guard !failed, let id = gate.begin(active: scenePhase == .active) else { return }
                do {
                    let palaceURL = DuelStageAsset.bundledURL
                    async let palace = DuelStageAsset.prepareOptionalPalace(url: palaceURL)
                    let index: DuelWeaponAssetIndex
                    if let verifiedIndex { index = verifiedIndex }
                    else { index = try await DuelWeaponAssetIndex.loadBundled() }
                    let prepared = try await index.preparingLocalEffects(player: setup.hero, opponent: setup.opponentHero)
                    let preparedPalace = await palace
                    try Task.checkCancellation()
                    gate.finish(id, active: scenePhase == .active) {
                        session = DuelSession(setup, verifiedIndex: prepared, preparedLocalPalace: preparedPalace)
                    }
                } catch {
                    gate.finish(id, active: scenePhase == .active) { failed = true }
                }
            }
        }
    }
}

private struct DuelOfflineMatchContent: View {
    @StateObject private var session: DuelSession
    init(setup: DuelSetup, verifiedIndex: DuelWeaponAssetIndex?) {
        _session = StateObject(wrappedValue: DuelSession(setup, verifiedIndex: verifiedIndex))
    }
    var body: some View { DuelMatchContent(session: session) }
}

private struct DuelNetworkMatchContent: View {
    @ObservedObject var preparation: DuelNetworkMatchPreparation
    let onExit: () -> Void
    var body: some View {
        DuelMatchContent(session: preparation.session, preparation: preparation,
                         loadingText: preparation.loadingText, onExit: onExit)
    }
}

private struct DuelMatchContent: View {
    @StateObject private var music = DuelMusicLease(scene: .battle)
    @State private var musicVisible = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var session: DuelSession
    var preparation: DuelNetworkMatchPreparation? = nil
    var loadingText: String? = nil
    var onExit: (() -> Void)? = nil
    var body: some View {
        ZStack {
            DuelWorld(session: session, preparation: preparation).ignoresSafeArea()
            if let preparation {
                DuelNetworkControls(preparation: preparation).ignoresSafeArea(edges: .bottom)
            } else if session.setup.originalWeapons {
                DuelWeaponControls(session: session).ignoresSafeArea(edges: .bottom)
            } else {
                DuelWeaponControls(session: session, requiresSourceArt: false).ignoresSafeArea(edges: .bottom)
            }
            VStack(spacing: 4) {
                hud
                if session.setup.mode == .tutorial {
                    Text(session.tutorial).font(.caption.bold()).padding(8).background(.black.opacity(0.65), in: Capsule())
                }
                if !session.setup.originalWeapons {
                    shadowArenaOverlayCallouts
                } else {
                    Group {
                        if let ticks = session.game.weaponFight?.sourceIntroRemainingTicks, ticks > 0 {
                            let intro = Text("孙登入场 · \((ticks + 59) / 60) 秒后可出招")
                                .font(.headline.bold()).foregroundStyle(.yellow)
                                .accessibilityIdentifier("duel.intro")
                            #if targetEnvironment(simulator)
                            // Read-only fixture observation; no input, clock or timing override.
                            if ProcessInfo.processInfo.arguments.contains("-rift-live-readiness-diagnostics") {
                                intro.accessibilityValue(Text(verbatim: String(ticks)))
                            } else {
                                intro
                            }
                            #else
                            intro
                            #endif
                        } else {
                            Text(session.feedback)
                        }
                    }.font(.headline.bold()).foregroundStyle(.yellow).frame(height: 24)
                }
                if !session.grappleStatus.isEmpty || session.setup.originalWeapons {
                    Text(session.grappleStatus).font(.caption.monospacedDigit().bold()).frame(height: 20)
                        .accessibilityIdentifier("duel.grapple")
                }
                if session.setup.mode != .versus {
                    Text("累计命中 \(session.localLandedHits) 次 · 伤害 \(session.localDamageDealt)")
                        .font(.caption.monospacedDigit()).accessibilityIdentifier("duel.hits")
                }
                Spacer()
            }.padding(.horizontal, 18).padding(.top, 8).allowsHitTesting(false)
            VStack {
                HStack {
                    Button { if preparation != nil { exitMatch() } else { session.pause() } } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(session.setup.originalWeapons ? 1.0 : 0.72))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(session.setup.originalWeapons ? 0.0 : 0.24)))
                            .overlay(Circle().stroke(Color.white.opacity(session.setup.originalWeapons ? 0.0 : 0.28), lineWidth: 0.9))
                            .padding(6)
                    }
                    .accessibilityLabel("暂停").accessibilityIdentifier("duel.pause")
                    Spacer()
                    Button { session.showBoxes.toggle() } label: {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(session.setup.originalWeapons ? 1.0 : (session.showBoxes ? 0.95 : 0.56)))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(session.setup.originalWeapons ? 0.0 : 0.20)))
                            .overlay(Circle().stroke(Color.white.opacity(session.setup.originalWeapons ? 0.0 : 0.24), lineWidth: 0.9))
                            .padding(6)
                    }
                    .accessibilityLabel("显示判定框").accessibilityIdentifier("duel.boxes")
                }.padding(.horizontal, 10)
                Spacer()
            }
            if preparation == nil, session.localFighter.hero == .wuYong,
               let fight = session.game.weaponFight, let state = fight.erlangState(session.localFighterIndex) {
                let ability: DuelErlangFightState.Ability = state.form == .avatar ? .judgement : .hound
                VStack {
                    Spacer()
                    Button {
                        session.input("skill1", down: true)
                        session.input("skill1", down: false)
                    } label: {
                        Text(ability.title).font(.callout.bold()).padding(.horizontal, 18).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent).tint(.brown)
                    .disabled(session.paused || !fight.canUseErlang(ability, index: session.localFighterIndex))
                    .accessibilityIdentifier("duel.erlang.additional")
                    .padding(.bottom, 14)
                }
            }
            if session.paused {
                if preparation != nil { loadingPanel } else { pausePanel }
            }
            if case .matchOver(let winner) = session.game.phase { resultPanel(winner) }
            if case .roundBreak(let winner, _) = session.game.phase {
                Text(winner == nil ? "平局 · 准备重赛" : winner == session.localFighterIndex ? "回合胜利" : "回合失利")
                    .font(.largeTitle.bold()).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .modifier(ArenaLandscape())
        .onAppear {
            musicVisible = true
            updateMusic()
        }
        .onChange(of: session.paused) { _ in updateMusic() }
        .onChange(of: session.sourceMusicReady) { _ in updateMusic() }
        .onChange(of: scenePhase) {
            if $0 != .active {
                if preparation != nil { exitMatch() } else { session.pause() }
            }
        }
        .onDisappear {
            musicVisible = false; music.close()
            if preparation != nil { exitMatch() } else { session.shutdown() }
        }
    }
    private var hud: some View {
        let isSF4 = !session.setup.originalWeapons
        return HStack(alignment: .top, spacing: isSF4 ? 12 : 18) {
            fighterHUD(0)
            if isSF4 {
                VStack(spacing: 4) {
                    Text(session.setup.mode == .versus ? "\((session.game.remainingTicks + 59) / 60)" : "练习")
                        .font(.system(size: 25, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(white: 0.98))
                        .shadow(color: Color.black.opacity(0.85), radius: 2, x: 0, y: 1.5)
                    HStack(spacing: 12) {
                        roundDiamonds(wins: session.game.wins[0], mirrored: false)
                        roundDiamonds(wins: session.game.wins[1], mirrored: true)
                    }
                }.frame(width: 72)
            } else {
                VStack(spacing: 3) {
                    Text(session.setup.mode == .versus ? "\((session.game.remainingTicks + 59) / 60)" : "练习")
                        .font(.title2.monospacedDigit().bold())
                    Text("\(session.game.wins[0])  :  \(session.game.wins[1])").font(.caption.bold())
                }.frame(width: 65)
            }
            fighterHUD(1)
        }.padding(.horizontal, isSF4 ? 48 : 50)
    }
    private func roundDiamonds(wins: Int, mirrored: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { idx in
                let filled = mirrored ? (idx < wins) : ((1 - idx) < wins)
                Rectangle()
                    .fill(filled ? Color(red: 0.96, green: 0.82, blue: 0.34) : Color.black.opacity(0.45))
                    .frame(width: 6.5, height: 6.5)
                    .overlay(
                        Rectangle()
                            .stroke(filled ? Color(red: 1.0, green: 0.94, blue: 0.66) : Color.white.opacity(0.55), lineWidth: 0.9)
                    )
                    .rotationEffect(.degrees(45))
                    .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 0.5)
            }
        }
    }
    private func statsSummaryString(for i: Int) -> String {
        let f = session.game.fighters[i]
        let maxHP = session.game.maximumHealth(i)
        return session.game.weaponFight?.triadState(i).map {
            "生命 \(f.health) · 雾气 \($0.mist)/\($0.rules.mist.maximum)"
        } ?? session.game.weaponFight?.panguState(i).map {
            "生命 \(f.health) · 光能 \($0.light)/\($0.rules.light.maximum) · 连击 \($0.combo)"
        } ?? session.game.shogunState(i).map { s in
            let phaseText = s.isCataclysm ? "灾变决杀" : s.isInShadow ? "暗影形态" : "蓄影"
            let allyText = s.companionPhase == .unconscious ? "死士昏迷" : s.agonyRemainingTicks > 0 ? "死士狂暴" : s.isCompanionAvailable ? "死士就绪" : "死士冷却"
            return "生命 \(f.health)/\(maxHP) · 暗影 \(s.shadowEnergy)/200 · \(phaseText) · \(allyText)"
        } ?? session.game.inquisitorState(i).map { inq in
            let formText = inq.isInFormOfLight ? "圣光形态" : inq.canEnterFormOfLight ? "圣光就绪" : "蓄光"
            let markText = inq.hasStigmataOnOpponent ? "圣痕 \((inq.stigmataTicks + 59) / 60)s" : "祝福 \(inq.blessings)"
            return "生命 \(f.health)/\(maxHP) · 圣光 \(inq.lightPower)/100 · \(formText) · \(markText)"
        } ?? session.game.nonnaState(i).map { nonna in
            let formText = nonna.isInFlameForm ? "烈焰形态" : nonna.empoweredStrikeReady ? "余烬破防" : nonna.canEnterFlameForm ? "烈焰就绪" : "蓄怒"
            let spiritText = nonna.wolfActive ? "灵狼出击" : nonna.owlPhase == .latched ? "灵枭待召" : nonna.owlPhase == .outbound || nonna.owlPhase == .returning ? "灵枭飞行" : "灵兽就绪"
            return "生命 \(f.health)/\(maxHP) · 怒火 \(nonna.flamePower)/100 · \(formText) · \(spiritText)"
        } ?? session.game.midnightState(i).map { mid in
            let phaseText = mid.isPhasedOut ? "影移虚化" : mid.isInBlinkStance ? "瞬闪防反" : mid.isInShadowForm ? "暗影暴击" : mid.canUseRemoval ? "抹除就绪" : "潜影"
            let corneredText = f.health <= (maxHP * DuelMidnightState.corneredBeastThresholdPermille) / 1000 ? " · 困兽+25%" : ""
            return "生命 \(f.health)/\(maxHP) · 影能 \(mid.shadowEnergy)/100 · \(phaseText)\(corneredText)"
        } ?? "生命 \(f.health)/\(maxHP) · 防御 \(f.guardMeter / 10) · 能量 \(f.energy)"
    }
    private func activeFormPill(for i: Int) -> (text: String, tint: Color)? {
        if let s = session.game.shogunState(i) {
            if s.isCataclysm { return ("灾变", Color(red: 1.0, green: 0.28, blue: 0.28)) }
            if s.isInShadow { return ("暗影", Color(red: 0.38, green: 0.88, blue: 1.0)) }
            if s.agonyRemainingTicks > 0 { return ("死士狂暴", Color(red: 1.0, green: 0.42, blue: 0.26)) }
        } else if let inq = session.game.inquisitorState(i) {
            if inq.isInFormOfLight { return ("圣光", Color(red: 1.0, green: 0.88, blue: 0.36)) }
            if inq.canEnterFormOfLight { return ("圣光就绪", Color(red: 1.0, green: 0.82, blue: 0.34)) }
        } else if let nonna = session.game.nonnaState(i) {
            if nonna.isInFlameForm { return ("烈焰", Color(red: 1.0, green: 0.46, blue: 0.16)) }
            if nonna.empoweredStrikeReady { return ("余烬", Color(red: 1.0, green: 0.68, blue: 0.24)) }
        } else if let mid = session.game.midnightState(i) {
            if mid.isPhasedOut { return ("影移", Color(red: 0.56, green: 0.90, blue: 1.0)) }
            if mid.isInShadowForm { return ("暗影", Color(red: 0.38, green: 0.88, blue: 1.0)) }
            if mid.isInBlinkStance { return ("瞬闪", Color(red: 0.46, green: 0.92, blue: 1.0)) }
        }
        return nil
    }
    private func fighterHUD(_ i: Int) -> some View {
        let f = session.game.fighters[i]
        let maxHP = session.game.maximumHealth(i)
        let statsSummary = statsSummaryString(for: i)
        let statsValue = "生命 \(f.health)，位置 \(f.x)，高度 \(f.y)，防御 \(f.guarding ? 1 : 0)"
        let isSF4 = !session.setup.originalWeapons
        if isSF4 {
            return AnyView(
                VStack(alignment: i == 0 ? .leading : .trailing, spacing: 2.5) {
                    HStack(spacing: 6) {
                        if i == 0 {
                            Text(f.hero.name)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: Color.black.opacity(0.85), radius: 1.5, x: 0, y: 1)
                                .accessibilityIdentifier("duel.name.\(i)")
                            if let pill = activeFormPill(for: i) {
                                Text(pill.text)
                                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(pill.tint)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.black.opacity(0.55)))
                                    .overlay(Capsule().stroke(pill.tint.opacity(0.75), lineWidth: 0.7))
                            }
                            Spacer(minLength: 4)
                            Text("\(f.health)")
                                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color(red: 0.98, green: 0.94, blue: 0.82, opacity: 0.90))
                                .shadow(color: Color.black.opacity(0.85), radius: 1.2, x: 0, y: 1)
                        } else {
                            Text("\(f.health)")
                                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color(red: 0.98, green: 0.94, blue: 0.82, opacity: 0.90))
                                .shadow(color: Color.black.opacity(0.85), radius: 1.2, x: 0, y: 1)
                            Spacer(minLength: 4)
                            if let pill = activeFormPill(for: i) {
                                Text(pill.text)
                                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(pill.tint)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.black.opacity(0.55)))
                                    .overlay(Capsule().stroke(pill.tint.opacity(0.75), lineWidth: 0.7))
                            }
                            Text(f.hero.name)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: Color.black.opacity(0.85), radius: 1.5, x: 0, y: 1)
                                .accessibilityIdentifier("duel.name.\(i)")
                        }
                    }
                    DuelDrainHealthBar(health: f.health, maximum: maxHP, mirrored: i == 1,
                                       tint: Color(red: 0.90, green: 0.72, blue: 0.22), slanted: true)
                        .frame(height: 12)
                    if let shogun = session.game.shogunState(i) {
                        DuelSlantedMeterBar(
                            value: shogun.shadowEnergy, maximum: DuelShogunState.maxShadowEnergy, mirrored: i == 1,
                            fillColor: shogun.isCataclysm ? Color(red: 1.0, green: 0.26, blue: 0.26) : Color(red: 0.30, green: 0.84, blue: 1.0),
                            readyGlow: shogun.isInShadow || shogun.isCataclysm || shogun.canUseShadowAbility
                        ).frame(height: 5.5)
                    } else if let inq = session.game.inquisitorState(i) {
                        DuelSlantedMeterBar(
                            value: inq.lightPower, maximum: DuelInquisitorState.maxLightPower, mirrored: i == 1,
                            fillColor: Color(red: 1.0, green: 0.86, blue: 0.34),
                            readyGlow: inq.isInFormOfLight || inq.canEnterFormOfLight
                        ).frame(height: 5.5)
                    } else if let nonna = session.game.nonnaState(i) {
                        DuelSlantedMeterBar(
                            value: nonna.flamePower, maximum: DuelNonnaState.maxFlamePower, mirrored: i == 1,
                            fillColor: nonna.isInFlameForm ? Color(red: 1.0, green: 0.32, blue: 0.14) : Color(red: 1.0, green: 0.56, blue: 0.16),
                            readyGlow: nonna.isInFlameForm || nonna.canEnterFlameForm
                        ).frame(height: 5.5)
                    } else if let mid = session.game.midnightState(i) {
                        DuelSlantedMeterBar(
                            value: mid.shadowEnergy, maximum: DuelMidnightState.maxShadowEnergy, mirrored: i == 1,
                            fillColor: Color(red: 0.34, green: 0.86, blue: 1.0),
                            readyGlow: mid.isInShadowForm || mid.canUseRemoval || mid.canUseBlink
                        ).frame(height: 5.5)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Invisible non-zero-opacity accessibility proxy preserving full XCUITest/VoiceOver stats telemetry with zero visual clutter.
                    Text(statsSummary)
                        .font(.system(size: 1))
                        .lineLimit(1)
                        .foregroundStyle(Color.white.opacity(0.015))
                        .frame(width: 2, height: 2)
                        .clipped()
                        .accessibilityIdentifier("duel.stats.\(i)")
                        .accessibilityLabel(statsSummary)
                        .accessibilityValue(statsValue)
                }
                .frame(maxWidth: .infinity)
            )
        }
        let combo = session.game.comboCount.indices.contains(i) ? session.game.comboCount[i] : 0
        return AnyView(
            VStack(alignment: i == 0 ? .leading : .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    if i == 1 && combo >= 2 {
                        comboBadge(combo)
                    }
                    Text(f.hero.name).font(.caption.bold())
                        .accessibilityIdentifier("duel.name.\(i)")
                    if i == 0 && combo >= 2 {
                        comboBadge(combo)
                    }
                }
                DuelDrainHealthBar(health: f.health, maximum: maxHP, mirrored: i == 1,
                                   tint: i == 0 ? .orange : .cyan)
                    .frame(height: 9)
                Text(statsSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .accessibilityIdentifier("duel.stats.\(i)")
                    .accessibilityValue(statsValue)
                if let state = session.game.weaponFight?.panguState(i) {
                    DuelPanguHUD(state: state,
                        isEscapingOrdinaryThrow: session.game.weaponFight?.ordinaryThrow(i)?.stage == .immune)
                }
                if let state = session.game.weaponFight?.triadState(i) { DuelTriadHUD(state: state) }
                if let fight = session.game.weaponFight {
                    DuelPanguControlHUD(controls: fight.panguPresentation.controls.filter { $0.target == i })
                    DuelTriadControlHUD(controls: fight.triadPresentation.controls.filter { $0.target == i })
                }
            }.frame(maxWidth: .infinity)
        )
    }
    /// SF4-style side-floating large slanted damage popups (`495`, `764`) + clean `xN 连击` + concise center major callout.
    private var shadowArenaOverlayCallouts: some View {
        let roundNumber = session.game.wins[0] + session.game.wins[1] + 1
        let showRoundStart = session.setup.mode == .versus && session.game.remainingTicks > 3545 && session.shortCallout.isEmpty
        let leftAttackerCombo = session.game.comboCount.indices.contains(0) ? session.game.comboCount[0] : 0
        let rightAttackerCombo = session.game.comboCount.indices.contains(1) ? session.game.comboCount[1] : 0
        return ZStack(alignment: .top) {
            HStack(alignment: .top) {
                // Left side: damage received by left fighter (0) + combo landed by right fighter (1)
                VStack(alignment: .leading, spacing: 2) {
                    if let popup = session.sideDamagePopups[0] {
                        sf4DamageNumberView(popup)
                    }
                    if rightAttackerCombo >= 2 {
                        sf4ComboText(rightAttackerCombo)
                    }
                }
                .padding(.leading, 48)
                Spacer()
                // Right side: damage received by right fighter (1) + combo landed by left fighter (0)
                VStack(alignment: .trailing, spacing: 2) {
                    if let popup = session.sideDamagePopups[1] {
                        sf4DamageNumberView(popup)
                    }
                    if leftAttackerCombo >= 2 {
                        sf4ComboText(leftAttackerCombo)
                    }
                }
                .padding(.trailing, 48)
            }
            .padding(.top, 4)

            if !session.shortCallout.isEmpty {
                combatCalloutBadge(session.shortCallout)
                    .padding(.top, 2)
            } else if showRoundStart {
                Text("第 \(roundNumber) 回合")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(Color(red: 0.98, green: 0.94, blue: 0.80))
                    .shadow(color: Color.black.opacity(0.85), radius: 3, x: 0, y: 1.5)
                    .padding(.top, 6)
            }
        }
        .frame(minHeight: 54, alignment: .top)
    }
    private func sf4DamageNumberView(_ popup: DuelDamagePopup) -> some View {
        let color: Color
        let size: CGFloat
        switch popup.kind {
        case .critical, .headshot:
            color = Color(red: 1.0, green: 0.82, blue: 0.28)
            size = 34
        case .shadow:
            color = Color(red: 0.56, green: 0.94, blue: 1.0)
            size = 32
        case .chip:
            color = Color(red: 0.82, green: 0.88, blue: 0.94, opacity: 0.86)
            size = 24
        case .normal:
            color = Color(red: 0.98, green: 0.96, blue: 0.90)
            size = 29
        }
        return Text("\(popup.amount)")
            .font(.system(size: size, weight: .black, design: .rounded).italic().monospacedDigit())
            .foregroundStyle(color)
            .shadow(color: Color.black.opacity(0.92), radius: 2, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.65), radius: 0.5, x: 1, y: 0)
            .id(popup.id)
    }
    private func sf4ComboText(_ count: Int) -> some View {
        Text("x\(count) 连击")
            .font(.system(size: 13, weight: .heavy, design: .rounded).italic())
            .foregroundStyle(count >= 4 ? Color(red: 1.0, green: 0.72, blue: 0.28) : Color(red: 0.98, green: 0.90, blue: 0.56))
            .shadow(color: Color.black.opacity(0.90), radius: 1.5, x: 0, y: 1)
    }
    private func comboBadge(_ count: Int) -> some View {
        let hot = count >= 4
        return Text("\(count) 连击!")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(hot ? Color(red: 1.0, green: 0.92, blue: 0.72) : Color(red: 1.0, green: 0.88, blue: 0.34))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                Capsule()
                    .fill(hot ? Color(red: 0.62, green: 0.10, blue: 0.08, opacity: 0.88)
                              : Color(red: 0.24, green: 0.14, blue: 0.04, opacity: 0.84))
            )
            .overlay(
                Capsule()
                    .stroke(hot ? Color(red: 1.0, green: 0.42, blue: 0.22) : Color(red: 0.98, green: 0.76, blue: 0.28),
                            lineWidth: 0.9)
            )
    }
    @ViewBuilder
    private func combatCalloutBadge(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Color.clear.frame(height: 22)
        } else {
            let isHeavyCallout = trimmed.contains("爆头") || trimmed.contains("暴击")
                || trimmed.contains("破防") || trimmed.contains("背投")
                || trimmed.contains("抹除") || trimmed.contains("灾变")
                || trimmed.contains("决杀") || trimmed.contains("斩杀")
                || trimmed.contains("天罚") || trimmed.contains("引爆")
            let isShadowCallout = !isHeavyCallout && (trimmed.contains("暗影")
                || trimmed.contains("虚化") || trimmed.contains("瞬闪") || trimmed.contains("死士"))
            let fg: Color = isHeavyCallout
                ? Color(red: 1.0, green: 0.88, blue: 0.38)
                : isShadowCallout
                    ? Color(red: 0.62, green: 0.94, blue: 1.0)
                    : Color(red: 0.98, green: 0.94, blue: 0.78)
            Text(trimmed)
                .font(.system(size: isHeavyCallout ? 17 : 14.5, weight: .black, design: .rounded).italic())
                .foregroundStyle(fg)
                .shadow(color: Color.black.opacity(0.92), radius: 2.5, x: 0, y: 1.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
        }
    }
    private func updateMusic() {
        // Keep the visible battle's claim even while loading, so an underlying
        // lobby cannot take over. Do not construct/play audio before readiness.
        music.update(visible: musicVisible, paused: session.paused || !session.sourceMusicReady) { [weak session] in
            guard let session else { return false }
            return !session.paused && session.sourceMusicReady
        }
    }
    private func resumeMatch(restarting: Bool = false) {
        let resumed = session.performUserResume(restarting: restarting)
        updateMusic()
        // A callback may have closed/paused/failed the session during the
        // attempt. Only the still-ready successful user action clears safety.
        guard resumed, !session.paused, session.sourceMusicReady else { return }
        music.resumeAfterUserAction(sessionInterruptionEnded: true)
    }
    private func exitMatch() {
        musicVisible = false; music.close()
        if let preparation { preparation.requestExit { onExit?() } }
        else { session.shutdown(); dismiss() }
    }
    private var loadingPanel: some View {
        panel {
            Text(loadingText ?? "正在准备联机画面").font(.headline)
                .accessibilityIdentifier("duel.network.preparing")
            if let error = session.loadError { Text(error).accessibilityIdentifier("duel.resourceError") }
            Button("退出联机") { exitMatch() }.accessibilityIdentifier("duel.network.exit")
        }
    }
    private var pausePanel: some View {
        panel {
            Text("已暂停").font(.title2.bold())
            if let error = session.loadError { Text(error).accessibilityIdentifier("duel.resourceError") }
            else if session.allowsLocalRestart {
                Button("继续对决") { resumeMatch() }.accessibilityIdentifier("duel.resume")
                Button("重新挑战") { resumeMatch(restarting: true) }.accessibilityIdentifier("duel.restart")
            }
            Button("返回角色选择") { exitMatch() }.accessibilityIdentifier("duel.exit")
            Text(session.characterStatus).font(.caption).accessibilityIdentifier("duel.characterStatus")
            Text(session.report).font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
    }
    private func resultPanel(_ winner: Int) -> some View {
        panel {
            Text(winner == session.localFighterIndex ? "对决胜利" : "这次惜败").font(.largeTitle.bold())
            Text("\(session.game.wins[0]) : \(session.game.wins[1]) · 命中 \(session.localLandedHits) 次")
            if session.allowsLocalRestart {
                Button("重新挑战") { resumeMatch(restarting: true) }.accessibilityIdentifier("duel.rematch")
            }
            Button("返回角色选择") { exitMatch() }.accessibilityIdentifier("duel.resultExit")
        }
    }
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14, content: content).buttonStyle(.borderedProminent)
                .padding(24).frame(maxWidth: 440).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct DuelWeaponControls: UIViewRepresentable {
    // Observe the session here as well as in the enclosing HUD. Its identity
    // stays unchanged across ticks, so a plain reference can leave UIKit's
    // readiness/accessibility state stale when SwiftUI skips this child.
    @ObservedObject var session: DuelSession
    var requiresSourceArt: Bool = true
    func makeUIView(context: Context) -> DuelSourceControlsView {
        let view = DuelSourceControlsView(assetDirectory: session.weaponAssets?.directory)
        guard bind(view) else { return view }
        if requiresSourceArt && !view.sourceArtAvailable { session.characterFailed() }
        updateUIView(view, context: context)
        return view
    }
    @discardableResult
    func bind(_ view: DuelSourceControlsView) -> Bool {
        if session.driver == .offline, !session.claimOfflineControls(view) {
            view.shutdown()
            return false
        }
        guard session.acceptsWeaponControls(view) else { view.shutdown(); return false }
        session.bindArtworkControls(view)
        view.peripheralInput.canAccept = { [weak session, weak view] in
            guard let session, let view else { return false }
            return session.acceptsWeaponControls(view) && !session.paused &&
                view.inputEnabled && view.window != nil && !view.isShutdown
        }
        view.peripheralInput.onState = { [weak session, weak view] source, state, cancelled in
            guard let session, let view, session.acceptsWeaponControls(view) else { return }
            var filtered = state
            filtered.actions = Set(state.actions.filter {
                guard let action = DuelSourceControlsView.Action(rawValue: $0.rawValue) else { return false }
                return view.state(for: action).enabled
            })
            session.updatePhysicalInput(filtered, source: source, cancelled: cancelled)
        }
        view.onDirection = { [weak session, weak view] x, y in
            guard let session, let view, session.acceptsWeaponControls(view) else { return }
            session.weaponDirection(x: x, y: y)
        }
        view.onAction = { [weak session, weak view] action, down in
            guard let session, let view, session.acceptsWeaponControls(view),
                  let command = DuelWeaponInput.Action(rawValue: action.rawValue) else { return }
            session.weaponAction(command, down: down)
        }
        view.onActionCancelled = { [weak session, weak view] action in
            guard let session, let view, session.acceptsWeaponControls(view),
                  let command = DuelWeaponInput.Action(rawValue: action.rawValue) else { return }
            session.cancelWeaponAction(command)
        }
        view.onGuard = { [weak session, weak view] held in
            guard let session, let view, session.acceptsWeaponControls(view) else { return }
            session.weaponGuard(held)
        }
        view.onInputCancelled = { [weak session, weak view] in
            guard let session, let view, session.acceptsWeaponControls(view) else { return }
            session.cancelWeaponInput()
        }
        if session.driver == .offline {
            view.onShutdown = { [weak session, weak view] in
                guard let view else { return }
                session?.releaseOfflineControls(view)
            }
        }
        session.inputReset = { [weak session, weak view] in
            guard let session, let view, session.acceptsWeaponControls(view) else { return }
            view.cancelAll(notify: false)
        }
        return true
    }
    func updateUIView(_ view: DuelSourceControlsView, context: Context) { updateReadiness(view) }
    func updateReadiness(_ view: DuelSourceControlsView) {
        guard session.acceptsWeaponControls(view) else { view.inputEnabled = false; return }
        view.inputEnabled = !session.paused && session.loadError == nil
        view.opponentProne = session.game.fighters[session.opponentFighterIndex].knockdown > 0
        let index = session.localFighterIndex
        let fighter = session.localFighter
        guard let fight = session.game.weaponFight else {
            guard !requiresSourceArt else { view.inputEnabled = false; return }
            updateShadowArenaReadiness(view, index: index, fighter: fighter)
            view.peripheralInput.refreshReadiness()
            return
        }
        let profile = fight.profiles[index]
        for action in DuelSourceControlsView.Action.allCases {
            guard let command = DuelWeaponCommand(rawValue: action.rawValue) else { continue }
            if let state = fight.erlangState(index), command == .shadow || command == .ranged {
                if let ability = fight.erlangAbility(for: session.weaponControlPreview(command), index: index) {
                    let ready = fight.canUseErlang(ability, index: index)
                    let cooldown = state.cooldown(ability)
                    let description = ready ? (ability == .meditate ? "按住冥想，松开结束" : "可施放") :
                        cooldown > 0 ? "冷却中 \((cooldown + 59) / 60) 秒" :
                        state.cast != nil ? "施放中" : ability == .ascend ? "需要充满光能" : "暂不可施放"
                    view.setState(.init(enabled: true, ready: ready, description: description,
                                        accessibilityLabel: ability.title), for: action)
                } else {
                    view.setState(.init(enabled: true, ready: false, description: "配合方向施放金身技能",
                                        accessibilityLabel: "金身技能"), for: action)
                }
                continue
            }
            if let state = fight.triadState(index), command == .shadow || command == .ranged,
               let ability = fight.triadAbility(for: session.weaponControlPreview(command), index: index),
               let rule = state.rules.ability(ability) {
                let unlocked = state.rules.level >= ability.minimumLevel
                let cooldown = max(state.cooldownRemaining(ability),
                    ability.soul == nil ? 0 : state.sharedSoulCooldownRemainingTicks)
                let continuing = ability == .mistOnslaught && state.canContinueOnslaught
                let ready = continuing || fight.canUseTriad(ability, index: index)
                let description = continuing ? "按住远程键续接雾潮" : !unlocked ? "套装等级不足" : cooldown > 0 ? "冷却中 \((cooldown + 59) / 60) 秒" :
                    state.mist < rule.mistCost ? "雾气不足" : ability == .mistOnslaught && state.onslaughtCharges == 0 ? "需要暴击补充雾潮" :
                    ability == .mistBlade && !state.mistBladeUnlocked ? "暴击后解锁雾刃" :
                    ability == .cryingDance && state.notches < state.rules.souls.notchCost ? "刻痕不足" :
                    ready ? "可施放" : state.activeCast != nil ? "施放中" : "暂不可施放"
                view.setState(.init(enabled: unlocked, ready: ready, description: description,
                    accessibilityLabel: ability.title), for: action)
                continue
            }
            if let state = fight.panguState(index), command == .shadow || command == .ranged,
               let ability = fight.panguAbility(for: session.weaponControlPreview(command), index: index),
               let rule = state.rules.ability(ability) {
                let unlocked = state.rules.level >= ability.minimumLevel
                let cooldown = state.cooldownRemaining(ability)
                let ready = fight.canUsePangu(ability, index: index)
                let description = !unlocked ? "套装等级不足" : cooldown > 0 ? "冷却中 \((cooldown + 59) / 60) 秒" :
                    state.light < rule.lightCost ? "光能不足" : ability == .spear && state.rangedCharges == 0 ? "长矛充能中" :
                    state.activeCast != nil ? "施放中" : ready ? "可施放" : "暂不可施放"
                view.setState(.init(enabled: unlocked, ready: ready, description: description,
                                    accessibilityLabel: ability.title), for: action)
                continue
            }
            let equipped = fight.supports(command, index: index)
            let enough = command != .shadow || fighter.energy >= 100
            let cooldown = command == .shadow ? fight.shadowCooldownRemaining(index) : 0
            let label = action == .weapon ? profile.weaponTitle + "攻击" : nil
            // The last displayed reaction frame still owns the input even after the stun counter reaches zero.
            let recoveringFromHit = fighter.stun > 0 || fighter.weaponPose?.reaction == true
            let ready = fight.canUse(command, index: index) && fighter.attack == nil && !recoveringFromHit
            let readiness = !equipped ? (profile.clip(command: command) == nil ? "未装备" : "暂不可用") : cooldown > 0 ? "冷却中 \((cooldown + 59) / 60) 秒" : !enough ? "需要 100 能量（当前 \(fighter.energy)）" : recoveringFromHit ? "受击中" : fighter.attack != nil ? "收招中" : ready ? "可施放" : "暂不可施放"
            view.setState(.init(enabled: equipped, ready: ready,
                                description: readiness,
                                accessibilityLabel: label), for: action)
        }
        view.peripheralInput.refreshReadiness()
    }

    private func updateShadowArenaReadiness(_ view: DuelSourceControlsView, index: Int, fighter: DuelGame.Fighter) {
        let canAct = fighter.stun == 0 && fighter.knockdown == 0
        let free = canAct && fighter.attack == nil
        let weaponTitle: String
        switch fighter.hero {
        case .wuYong: weaponTitle = "野太刀"
        case .gale: weaponTitle = "十字大剑"
        case .liu: weaponTitle = "双手巨斧"
        case .ember: weaponTitle = "双短忍刀"
        }
        view.setState(.init(
            enabled: true,
            ready: canAct && (fighter.attack == nil || fighter.attack?.move == .jab || fighter.attack?.move == .cross),
            description: free ? "可出招" : fighter.attack != nil ? "连招中" : "受击中",
            accessibilityLabel: weaponTitle + "攻击",
            accentColor: nil
        ), for: .weapon)

        let kickLabel = fighter.hero == .wuYong ? "踢击 / 前+踢无情突踢" : "八方向踢击"
        view.setState(.init(
            enabled: true,
            ready: free,
            description: free ? "可出招" : fighter.attack != nil ? "收招中" : "受击中",
            accessibilityLabel: kickLabel,
            accentColor: nil
        ), for: .kick)

        // Ranged button: hero signature tactical ability on dedicated SF4 Arena cooldowns
        if let shogun = session.game.shogunState(index) {
            let ready = shogun.isCompanionAvailable && fighter.health > 0 && fighter.knockdown == 0
            let desc = shogun.companionPhase == .unconscious ? "死士昏迷" :
                shogun.companionCooldown > 0 ? "死士冷却 \((shogun.companionCooldown + 59) / 60)s" :
                ready ? "死士突袭就绪" : "死士行动中"
            view.setState(.init(enabled: true, ready: ready, description: desc,
                                accessibilityLabel: "死士突袭",
                                accentColor: ready ? UIColor.systemPurple : nil), for: .ranged)
        } else if let nonna = session.game.nonnaState(index) {
            let recalling = nonna.owlPhase == .latched || nonna.owlPhase == .outbound
            let ready = recalling || (free && nonna.canLaunchOwl)
            let desc = recalling ? "再次点击召回定身！" :
                nonna.owlCooldown > 0 ? "灵枭冷却 \((nonna.owlCooldown + 59) / 60)s" :
                ready ? "灵枭扑击就绪" : "灵枭飞行中"
            view.setState(.init(enabled: true, ready: ready, description: desc,
                                accessibilityLabel: recalling ? "召回灵枭" : "灵枭扑击",
                                accentColor: ready ? UIColor.systemOrange : nil), for: .ranged)
        } else if let inq = session.game.inquisitorState(index) {
            let ready = free && inq.canCastSalvation
            let desc = inq.rangedCooldown > 0 ? "圣光冷却 \((inq.rangedCooldown + 59) / 60)s" :
                ready ? "救赎圣光就绪" : "收招中"
            view.setState(.init(enabled: true, ready: ready,
                                description: desc,
                                accessibilityLabel: "救赎圣光柱",
                                accentColor: ready ? UIColor.systemYellow : nil), for: .ranged)
        } else if let mid = session.game.midnightState(index) {
            let ready = free && mid.canCastKunai
            let desc = mid.rangedCooldown > 0 ? "苦无冷却 \((mid.rangedCooldown + 59) / 60)s" :
                ready ? "暗影苦无就绪" : "收招中"
            view.setState(.init(enabled: true, ready: ready,
                                description: desc,
                                accessibilityLabel: "暗影苦无",
                                accentColor: ready ? UIColor.systemIndigo : nil), for: .ranged)
        }

        // Shadow button: pure primary resource + directional 搓招 hints
        if let shogun = session.game.shogunState(index) {
            let ready = free && fighter.y == 0 && shogun.canUseShadowAbility
            let desc = shogun.isCataclysm ? "灾变决杀！" :
                shogun.shadowAbilityCooldown > 0 ? "暗影冷却 \((shogun.shadowAbilityCooldown + 59) / 60)s" :
                shogun.isInShadow ? "前报复 / 后暴政" : "暗影 \(shogun.shadowEnergy)/100"
            view.setState(.init(enabled: true, ready: ready, description: desc,
                                accessibilityLabel: shogun.isCataclysm ? "暗影灾变决杀" : "幕府暗影技",
                                accentColor: shogun.isCataclysm ? UIColor.systemRed : (ready ? UIColor.systemPurple : nil)), for: .shadow)
        } else if let inq = session.game.inquisitorState(index) {
            let ready = free && fighter.y == 0 && (inq.isInFormOfLight || inq.canEnterFormOfLight || inq.canCastDeliverance)
            let desc = inq.isInFormOfLight ? "高塔教条旋斩！" :
                inq.canEnterFormOfLight ? "开启圣光形态！" :
                inq.canCastDeliverance ? "圣裁破防 · 圣光 \(inq.lightPower)/100" :
                "圣裁冷却 \((inq.deliveranceCooldown + 59) / 60)s · 圣光 \(inq.lightPower)/100"
            view.setState(.init(enabled: true, ready: ready, description: desc,
                                accessibilityLabel: inq.isInFormOfLight ? "高塔教条" : inq.canEnterFormOfLight ? "圣光形态" : "圣裁破防斩",
                                accentColor: (inq.isInFormOfLight || inq.canEnterFormOfLight) ? UIColor.systemYellow : (ready ? UIColor.systemOrange : nil)), for: .shadow)
        } else if let nonna = session.game.nonnaState(index) {
            let canSummonWolf = nonna.isInFlameForm && !nonna.wolfActive
            let ready = free && fighter.y == 0 && (nonna.canEnterFlameForm || canSummonWolf)
            let desc = canSummonWolf ? "烈焰召狼！" :
                nonna.isInFlameForm ? "烈焰破防真身！" :
                nonna.canEnterFlameForm ? "烈焰形态就绪 (\(nonna.flamePower))!" :
                "怒火 \(nonna.flamePower)/30"
            view.setState(.init(enabled: true, ready: ready, description: desc,
                                accessibilityLabel: canSummonWolf ? "召唤花焰灵狼" : "烈焰形态",
                                accentColor: (nonna.isInFlameForm || nonna.canEnterFlameForm) ? UIColor.systemOrange : nil), for: .shadow)
        } else if let mid = session.game.midnightState(index) {
            let ready = free && fighter.y == 0 && (mid.canUseRemoval || mid.canUseBlink)
            let desc = mid.canUseRemoval ? "前抹除 / 后瞬闪" :
                mid.canUseBlink ? "后+暗影 瞬闪防反" :
                mid.blinkCooldown > 0 ? "瞬闪冷却 \((mid.blinkCooldown + 59) / 60)s · 影能 \(mid.shadowEnergy)/100" :
                "影能 \(mid.shadowEnergy)/50"
            view.setState(.init(enabled: true, ready: ready, description: desc,
                                accessibilityLabel: mid.canUseRemoval ? "暗影抹除 / 瞬闪" : "瞬闪防反",
                                accentColor: mid.canUseRemoval ? UIColor.systemPink : (ready ? UIColor.systemPurple : nil)), for: .shadow)
        } else {
            view.setState(.init(enabled: true, ready: free && fighter.energy == 100,
                                description: "能量 \(fighter.energy)/100",
                                accessibilityLabel: "暗影能力", accentColor: nil), for: .shadow)
        }
    }
    static func dismantleUIView(_ view: DuelSourceControlsView, coordinator: ()) { view.shutdown() }
}

struct DuelNetworkControls: UIViewRepresentable {
    let preparation: DuelNetworkMatchPreparation
    func makeUIView(context: Context) -> DuelNetworkControlsView {
        #if DEBUG
        if preparation.permitsFixture {
            return DuelNetworkControlsView(testing: preparation, controls: DuelSourceControlsView(images: [:]),
                                           acceptsFixtureArt: true, deferReadinessUpdates: true)
        }
        #endif
        return DuelNetworkControlsView(preparation: preparation, deferReadinessUpdates: true)
    }
    func updateUIView(_ view: DuelNetworkControlsView, context: Context) { view.scheduleReadinessRefresh() }
    static func dismantleUIView(_ view: DuelNetworkControlsView, coordinator: ()) { view.detach() }
}

/// Layout/mount observation belongs to this native container, not a timer or a
/// SwiftUI onAppear. Source controls remain physically disabled until start.
@MainActor
final class DuelNetworkControlsView: UIView {
    let ownerID: UUID
    let controls: DuelSourceControlsView
    private let session: DuelSession
    private weak var preparation: DuelNetworkMatchPreparation?
    private var wasMounted = false
    private var ended = false
    private var acceptsFixtureArt = false
    private let deferReadinessUpdates: Bool

    init(preparation: DuelNetworkMatchPreparation, deferReadinessUpdates: Bool = false) {
        self.deferReadinessUpdates = deferReadinessUpdates
        let state = preparation.session
        ownerID = preparation.id; session = state; self.preparation = preparation
        if state.usesVerifiedPreparedResources {
            // Never load again on a missing/claimed/released full-path owner.
            // Empty art is a fail-closed placeholder, not a production fallback.
            if let prepared = state.preparedResources, prepared.canClaimControls,
               let verifiedControls = prepared.controls {
                controls = verifiedControls
            } else { controls = DuelSourceControlsView(images: [:]) }
        } else {
            controls = DuelSourceControlsView(assetDirectory: state.weaponAssets?.directory)
        }
        super.init(frame: .zero)
        configure(preparation)
    }
    #if DEBUG
    init(testing preparation: DuelNetworkMatchPreparation, controls: DuelSourceControlsView,
         acceptsFixtureArt: Bool = false, deferReadinessUpdates: Bool = false) {
        self.deferReadinessUpdates = deferReadinessUpdates
        ownerID = preparation.id; session = preparation.session; self.preparation = preparation
        self.controls = controls
        self.acceptsFixtureArt = acceptsFixtureArt && preparation.permitsFixture
        super.init(frame: .zero)
        configure(preparation)
    }
    #endif
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func configure(_ owner: DuelNetworkMatchPreparation) {
        guard owner.attach(self) else { shutdown(); return }
        isOpaque = false; backgroundColor = .clear
        addSubview(controls)
        DuelWeaponControls(session: session).bind(controls)
        updateReadinessAtViewBoundary()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !ended else { return }
        if window == nil, wasMounted { detach(); return }
        if window != nil { wasMounted = true }
        updateReadinessAtViewBoundary()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !ended else { return }
        controls.frame = bounds
        controls.setNeedsLayout(); controls.layoutIfNeeded()
        updateReadinessAtViewBoundary()
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !ended && controls.point(inside: convert(point, to: controls), with: event)
    }
    private func updateReadinessAtViewBoundary() {
        if deferReadinessUpdates { scheduleReadinessRefresh() }
        else { refreshReadiness() }
    }
    private var readinessQueued = false
    func scheduleReadinessRefresh() {
        guard !ended, !readinessQueued else { return }
        readinessQueued = true
        let expectedOwner = ownerID
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readinessQueued = false
            guard !self.ended, self.ownerID == expectedOwner,
                  self.preparation?.id == expectedOwner else { return }
            self.refreshReadiness()
        }
    }
    #if DEBUG
    var preparationPhaseDescription: String {
        "window=\(window != nil), childWindow=\(controls.window != nil), layout=\(usableLayout), " +
        "ready=\(currentPreparationReady), art=\(controls.sourceArtAvailable), queued=\(readinessQueued)"
    }
    #endif
    func refreshReadiness() {
        guard !ended else { return }
        DuelWeaponControls(session: session).updateReadiness(controls)
        guard let preparation else { return }
        guard controls.sourceArtAvailable || acceptsFixtureArt else {
            preparation.controlsDidFail(self); return
        }
        guard currentPreparationReady else { return }
        preparation.controlsDidPrepare(self)
    }
    var hasVerifiedResourceIdentity: Bool {
        !ended && !acceptsFixtureArt && session.hasLiveVerifiedResources &&
            controls === session.preparedResources?.controls && controls.superview === self
    }
    var currentPreparationReady: Bool {
        !ended && window != nil && controls.window != nil && controls.superview === self && usableLayout &&
            (controls.sourceArtAvailable || acceptsFixtureArt) &&
            controls.onDirection != nil && controls.onAction != nil && controls.onGuard != nil &&
            controls.onActionCancelled != nil && controls.onInputCancelled != nil &&
            session.inputReset != nil && session.awaitingNetworkPreparation
    }
    private var usableLayout: Bool {
        let layout = controls.layoutSnapshot
        guard bounds.width.isFinite, bounds.height.isFinite, layout.scale.isFinite,
              layout.scale > 0, layout.joystick.width >= 44, layout.joystick.height >= 44,
              bounds.insetBy(dx: -0.5, dy: -0.5).contains(layout.joystick) else { return false }
        return DuelSourceControlsView.Action.allCases.allSatisfy { action in
            guard let frame = layout.actions[action], let touch = layout.actionTouch[action] else { return false }
            return frame.width >= 44 && frame.height >= 44 &&
                bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame) &&
                touch.width >= 44 && touch.height >= 44
        }
    }
    func detach() {
        guard !ended else { return }
        preparation?.controlsDidFail(self, detached: true)
        shutdown()
    }
    func shutdown() {
        guard !ended else { return }
        ended = true; preparation = nil
        controls.cancelAll(notify: false); controls.inputEnabled = false
        controls.onDirection = nil; controls.onAction = nil; controls.onGuard = nil
        controls.onActionCancelled = nil; controls.onInputCancelled = nil
        controls.removeFromSuperview()
    }
}

struct DuelControls: UIViewRepresentable {
    @ObservedObject var session: DuelSession
    let ultimateReady: Bool
    func makeUIView(context: Context) -> DuelInputView { DuelInputView(session: session) }
    func updateUIView(_ uiView: DuelInputView, context: Context) { uiView.updateReadiness(ready: ultimateReady) }
    static func dismantleUIView(_ uiView: DuelInputView, coordinator: ()) { uiView.cancelAll() }
}

/// Each touch owns its original button; dragging away or cancellation releases it.
/// Independent fingers can hold a direction while another presses attack or guard.
@MainActor
final class DuelInputView: UIView {
    private weak var session: DuelSession?
    private var active: [ObjectIdentifier: String] = [:]
    private var buttons: [(String, UIButton)] = []
    init(session: DuelSession) {
        self.session = session; super.init(frame: .zero); isMultipleTouchEnabled = true
        var controls = [("left", "◀"), ("right", "▶"), ("guard", "防御"), ("jump", "跳跃"),
                        ("light", "普攻"), ("heavy", "重击"), ("skill1", session.localFighter.hero.skill1Name),
                        ("skill2", session.localFighter.hero.skill2Name)]
        switch session.localFighter.hero {
        case .liu: controls.append(("ultimate", "大招"))
        case .wuYong: controls.append(("ultimate", "暗影技"))
        case .gale: controls.append(("ultimate", "圣光形态"))
        case .ember: controls.append(("ultimate", "抹除必杀"))
        }
        for (name, title) in controls {
            let button = UIButton(type: .custom)
            button.setTitle(title, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            button.titleLabel?.adjustsFontSizeToFitWidth = true; button.titleLabel?.minimumScaleFactor = 0.7
            button.backgroundColor = UIColor(white: 0.12, alpha: 0.72)
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor; button.layer.borderWidth = 1
            button.layer.cornerRadius = 24; button.isUserInteractionEnabled = false
            button.accessibilityIdentifier = "duel.control.\(name)"; button.accessibilityLabel = title
            button.isAccessibilityElement = true; addSubview(button); buttons.append((name, button))
        }
        session.inputReset = { [weak self] in self?.cancelAll(notify: false) }
        updateReadiness(ready: session.ultimateReady)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = bounds.width < 740 ? 48 : 58
        let inset = max(18, safeAreaInsets.left), floor = bounds.height - max(16, safeAreaInsets.bottom) - side
        let right = bounds.width - max(18, safeAreaInsets.right) - side
        let points: [CGPoint] = [CGPoint(x: inset, y: floor), CGPoint(x: inset + side + 10, y: floor),
            CGPoint(x: right - 2 * (side + 10), y: floor), CGPoint(x: inset + (side + 10) / 2, y: floor - side - 10),
            CGPoint(x: right - side - 10, y: floor), CGPoint(x: right, y: floor),
            CGPoint(x: right - side - 10, y: floor - side - 10), CGPoint(x: right, y: floor - side - 10),
            CGPoint(x: right - 2 * (side + 10), y: floor - side - 10)]
        for (index, pair) in buttons.enumerated() { pair.1.frame = CGRect(origin: points[index], size: CGSize(width: side, height: side)) }
    }
    func updateReadiness(ready: Bool) {
        guard let session, let button = buttons.first(where: { $0.0 == "ultimate" })?.1 else { return }
        let idx = session.localFighterIndex
        let skill1Button = buttons.first(where: { $0.0 == "skill1" })?.1
        let skill2Button = buttons.first(where: { $0.0 == "skill2" })?.1
        switch session.localFighter.hero {
        case .wuYong:
            let shogun = session.game.shogunState(idx)
            let cataclysm = shogun?.isCataclysm == true
            button.setTitle(cataclysm ? "灾变技" : "暗影技", for: .normal)
            button.backgroundColor = ready
                ? (cataclysm ? UIColor.systemRed.withAlphaComponent(0.9) : UIColor.systemPurple.withAlphaComponent(0.88))
                : UIColor(white: 0.16, alpha: 0.78)
            button.accessibilityLabel = cataclysm ? "暗影灾变绝技" : "暗影技"
            button.accessibilityValue = ready ? "可施放（前/中：猛烈报复；后拉：暴政牵引）" : "需要暗影形态（100 暗影能量）"
            if let shogun {
                skill2Button?.backgroundColor = shogun.isCompanionAvailable
                    ? UIColor.systemIndigo.withAlphaComponent(0.82)
                    : UIColor(white: 0.12, alpha: 0.55)
            }
        case .gale:
            let inq = session.game.inquisitorState(idx)
            let inLight = inq?.isInFormOfLight == true
            button.setTitle(inLight ? "圣光中" : "圣光形态", for: .normal)
            button.backgroundColor = inLight
                ? UIColor.systemYellow.withAlphaComponent(0.9)
                : ready ? UIColor.systemOrange.withAlphaComponent(0.9) : UIColor(white: 0.16, alpha: 0.78)
            button.accessibilityLabel = "圣光形态"
            button.accessibilityValue = inLight ? "圣光形态持续中（全攻击破防）" : ready ? "可开启圣光形态" : "需要 100 圣光"
            skill2Button?.setTitle(inLight ? "高塔回旋" : session.localFighter.hero.skill2Name, for: .normal)
            skill2Button?.backgroundColor = inLight
                ? UIColor.systemYellow.withAlphaComponent(0.84)
                : UIColor(white: 0.12, alpha: 0.72)
        case .liu:
            let nonna = session.game.nonnaState(idx)
            let owlOut = nonna?.owlPhase == .latched || nonna?.owlPhase == .outbound
            skill1Button?.setTitle(owlOut ? "召回灵枭" : session.localFighter.hero.skill1Name, for: .normal)
            skill1Button?.backgroundColor = owlOut
                ? UIColor.systemOrange.withAlphaComponent(0.88)
                : UIColor(white: 0.12, alpha: 0.72)
            let flameReady = nonna?.canEnterFlameForm == true
            let inFlame = nonna?.isInFlameForm == true
            skill2Button?.setTitle(inFlame ? "烈焰中" : "烈焰形态", for: .normal)
            skill2Button?.backgroundColor = inFlame
                ? UIColor.systemRed.withAlphaComponent(0.9)
                : flameReady ? UIColor.systemOrange.withAlphaComponent(0.88) : UIColor(white: 0.12, alpha: 0.72)
            button.backgroundColor = ready ? UIColor.systemOrange.withAlphaComponent(0.85) : UIColor(white: 0.16, alpha: 0.78)
            button.accessibilityLabel = "擒拿震地大招"
            button.accessibilityValue = ready ? "可施放（满能擒拿 / 怒火≥30 烈焰形态）" : "需要 100 能量或 30 怒火"
        case .ember:
            let mid = session.game.midnightState(idx)
            let inShadow = mid?.isInShadowForm == true
            button.setTitle(inShadow ? "暗影态" : "抹除必杀", for: .normal)
            button.backgroundColor = ready
                ? UIColor.systemPurple.withAlphaComponent(0.9)
                : inShadow ? UIColor.systemPink.withAlphaComponent(0.75) : UIColor(white: 0.16, alpha: 0.78)
            button.accessibilityLabel = "抹除必杀"
            button.accessibilityValue = ready ? "可施放抹除（瞬移斩杀并清空对手能量）" : "需要 100 影能"
            let blinkReady = (mid?.blinkCooldown ?? 1) == 0 && session.localFighter.energy >= 45
            skill2Button?.backgroundColor = mid?.isInBlinkStance == true
                ? UIColor.systemCyan.withAlphaComponent(0.88)
                : blinkReady ? UIColor.systemIndigo.withAlphaComponent(0.82) : UIColor(white: 0.12, alpha: 0.55)
        }
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        buttons.contains { $0.1.frame.contains(point) }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session?.paused == false else { return }
        for touch in touches {
            guard let button = buttons.first(where: { $0.1.frame.contains(touch.location(in: self)) }) else { continue }
            let wasHeld = active.values.contains(button.0)
            active[ObjectIdentifier(touch)] = button.0
            if !wasHeld { session?.input(button.0, down: true) }
            button.1.alpha = 0.6
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let name = active[ObjectIdentifier(touch)], let button = buttons.first(where: { $0.0 == name }),
               !button.1.frame.insetBy(dx: -12, dy: -12).contains(touch.location(in: self)) { release(touch) }
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach(release) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach(release) }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelAll() } }
    private func release(_ touch: UITouch) {
        guard let name = active.removeValue(forKey: ObjectIdentifier(touch)) else { return }
        if !active.values.contains(name) { session?.input(name, down: false); buttons.first(where: { $0.0 == name })?.1.alpha = 1 }
    }
    func cancelAll(notify: Bool = true) {
        let names = Set(active.values); active.removeAll()
        for pair in buttons { pair.1.alpha = 1 }
        if notify { for name in names { session?.input(name, down: false) } }
    }
}


