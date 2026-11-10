import SwiftUI
import UIKit
import AVFoundation
import Combine

struct DuelSetup: Identifiable {
    let id = UUID()
    let hero: DuelGame.Hero
    let difficulty: DuelGame.Difficulty
    let mode: DuelGame.Mode
    let originalWeapons: Bool
    init(hero: DuelGame.Hero, difficulty: DuelGame.Difficulty, mode: DuelGame.Mode, originalWeapons: Bool = false) {
        self.hero = hero; self.difficulty = difficulty; self.mode = mode; self.originalWeapons = originalWeapons
    }
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
    private var publishingAuthoritativeStep = false
    private var networkMountOwner: UUID?
    private var pendingNetworkPreparation: (owner: UUID, invalidated: () -> Void)?
    private(set) var game: DuelGame
    private(set) var held = Set<String>()
    private var taps: DuelGame.Buttons = []
    private var weaponInput = DuelWeaponInput()
    private(set) var weaponAssets: DuelWeaponAssets?
    private(set) var preparedResources: DuelNetworkPreparedResources?
    private var preparedSessionClaim: UUID?
    /// Remains true after release so a closed full-path session cannot fall back
    /// to a Bundle.main load when UIKit delivers a late view construction.
    private(set) var usesVerifiedPreparedResources = false
    @Published private(set) var loadError: String?
    @Published private(set) var paused = false
    @Published var showBoxes = false
    @Published private(set) var feedback = "保持距离，观察出手"
    @Published private(set) var tutorialStep = 0
    @Published private(set) var report = ""
    var renderPause: ((Bool) -> Void)?
    var inputReset: (() -> Void)?
    var didSimulateStep: ((DuelGame, Int) -> Void)?
    var didReset: (() -> Void)?
    /// A local interruption requests coordinator teardown. It is not permission
    /// to modify authoritative buffers or to resume this protocol-1 match.
    var didRequestAuthoritativeStop: (() -> Void)?
    private var feedbackUntil = 75
    private var serial = 0
    private var ended = false
    private(set) var animationTick = 0
    private(set) var characterStatus = ""
    private var practicedJump = false
    private var practicedSkills = Set<DuelGame.Move>()
    private let interruptions = DuelInterruptionObserver()
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    init(_ setup: DuelSetup) {
        self.setup = setup
        driver = .offline; localFighterIndex = 0; committedConfiguration = nil
        var assets: DuelWeaponAssets?
        var failure: String?
        if setup.originalWeapons {
            do { assets = try DuelWeaponAssets() }
            catch { failure = "人物资源无法载入，请返回后重试。" }
        }
        weaponAssets = assets
        game = DuelGame(hero: setup.hero, difficulty: setup.difficulty, mode: setup.mode,
                        opponentHero: setup.hero == .liu ? .ember : setup.hero == .ember ? .liu : nil,
                        weaponCatalog: assets?.catalog)
        if setup.originalWeapons && game.weaponFight == nil { failure = "人物资源无法载入，请返回后重试。" }
        loadError = failure; paused = failure != nil
        observeInterruptions()
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
        // The old seam may not adopt the manager of a retained verifier owner.
        // Otherwise its independent teardown could erase a live full-path match.
        guard !assets.belongsToVerifiedPreparation else { throw PresentationFailure.invalidAssets }
        let configuration = try DuelNetworkCombatProtocol.configuration(
            from: barrier, host: barrier.localPlayerID == barrier.hostID,
            loadedCompatibility: identity.compatibility, catalog: assets.catalog)
        guard identity.catalog == assets.catalog else { throw PresentationFailure.invalidAssets }
        for hero in [configuration.host.choice.hero, configuration.guest.choice.hero] {
            _ = try assets.character(for: hero)
        }
        let game = DuelGame(hero: configuration.host.choice.hero, difficulty: configuration.difficulty,
                            mode: configuration.mode, seed: configuration.seed,
                            opponentHero: configuration.guest.choice.hero, weaponCatalog: assets.catalog)
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
            let configuration = try DuelNetworkCombatProtocol.configuration(
                from: barrier, host: barrier.localPlayerID == barrier.hostID,
                loadedCompatibility: prepared.identity.compatibility, catalog: assets.catalog)
            guard prepared.hasExactResources, prepared.identity.catalog == assets.catalog else {
                throw PresentationFailure.invalidAssets
            }
            for choice in [configuration.host.choice, configuration.guest.choice] {
                guard let character = prepared.loadedCharacter(for: choice.hero),
                      character.profile == assets.catalog.profile(for: choice.hero),
                      character.profile.id == choice.weapon.rawValue else { throw PresentationFailure.invalidAssets }
            }
            let game = DuelGame(hero: configuration.host.choice.hero, difficulty: configuration.difficulty,
                mode: configuration.mode, seed: configuration.seed,
                opponentHero: configuration.guest.choice.hero, weaponCatalog: assets.catalog)
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
              assets.catalog == preparedResources.identity.catalog,
              let fight = game.weaponFight, fight.profiles.count == 2 else { return false }
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
        return preparedResources.claimWorld(world, session: preparedSessionClaim, owner: networkMountOwner)
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

    private func observeInterruptions() {
        interruptions.token = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pause() }
            }
    }
    var tutorial: String {
        if setup.originalWeapons {
            return ["推动左侧摇杆靠近对手", "点击右侧武器按钮，观察刀或锤的攻击距离", "向上推动摇杆跳跃，站定时自动防御", "配合方向攻击，并尝试踢击与长按武器重击", "已完成：继续练习，或返回挑战电脑"][min(4, tutorialStep)]
        }
        return ["按住左侧方向，靠近对手", "方向与普攻可同时按：命中后再点普攻", "先点击跳跃，落地后再按住防御", "分别使出两种技能，注意能量消耗", "已完成：继续练习，或返回挑战电脑"][min(4, tutorialStep)]
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
    var ultimateReady: Bool { localFighter.energy == 100 && game.grapple == nil }
    func input(_ name: String, down: Bool) {
        guard !paused else { return }
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
    func weaponDirection(x: Int, y: Int) { guard !paused else { return }; weaponInput.direction(x: x, y: y) }
    func weaponAction(_ action: DuelWeaponInput.Action, down: Bool) { guard !paused else { return }; weaponInput.action(action, down: down) }
    func cancelWeaponAction(_ action: DuelWeaponInput.Action) { weaponInput.cancel(action: action) }
    func cancelWeaponInput() {
        weaponInput.cancelAll()
        if driver == .offline { game.cancelBufferedInputs() }
    }
    func clearInput() {
        held.removeAll(); taps = []; weaponInput.cancelAll()
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
            clearInput(); paused = true; renderPause?(true)
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
    func resume() {
        guard driver == .offline, !ended, loadError == nil else { return }
        clearInput(); paused = false; renderPause?(false)
    }
    func restart() {
        guard allowsLocalRestart, !ended else { return }
        clearInput(); game = DuelGame(hero: setup.hero, difficulty: setup.difficulty, mode: setup.mode,
                        opponentHero: setup.hero == .liu ? .ember : setup.hero == .ember ? .liu : nil,
                        weaponCatalog: weaponAssets?.catalog)
        feedback = "保持距离，观察出手"; tutorialStep = 0; serial = 0; animationTick = 0; feedbackUntil = 75
        practicedJump = false; practicedSkills.removeAll(); didReset?(); resume()
        didSimulateStep?(game, 0); objectWillChange.send()
    }

    /// One physical-input sample, in world coordinates, resolved against the
    /// local seat's current authoritative facing and airborne state. Consumes
    /// edges exactly once but never advances the simulation or clears its buffers.
    func consumeLocalInput() -> DuelGame.Input {
        guard !ended, !paused else { return .neutral }
        let input = setup.originalWeapons ? weaponInput.consume(facing: localFighter.facing,
                    airborne: game.weaponFight?.isAirborne(localFighterIndex) ?? false) :
            DuelGame.Input(move: (held.contains("right") ? 1 : 0) - (held.contains("left") ? 1 : 0),
                           guardHeld: held.contains("guard"), taps: taps)
        taps = []
        return input
    }

    /// Existing display-link entry point. External presentation has no local
    /// clock authority, AI fallback or input drain while waiting for host frames.
    func advance() {
        guard driver == .offline, !ended, !paused else { return }
        if case .matchOver = game.phase { return }
        let input = consumeLocalInput()
        let frozen = game.hitStop > 0 && game.grapple == nil
        game.step(input)
        presentStep(input: input, frozen: frozen)
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
        for event in presentedGame.events {
            guard canPresentStep else { return }
            switch event {
            case .hit(let attacker, let damage): feedback = attacker == localFighterIndex ? "命中 −\(damage)" : "受到攻击 −\(damage)"
            case .blocked(let defender): feedback = defender == localFighterIndex ? "防御成功" : "对手防御成功"
            case .guardBreak(let defender): feedback = defender == localFighterIndex ? "防御被击破" : "击破对手防御"
            case .whiff(let attacker): if attacker == localFighterIndex { feedback = "未命中 · 留意距离与前摇" }
            case .jumped: break
            case .grappleStarted(let attacker): feedback = attacker == localFighterIndex ? "擒拿成功 · 抓肩摔倒" : "被对手擒拿 · 抓肩摔倒"
            case .grappleSlam(let attacker): feedback = attacker == localFighterIndex ? "锁臂压制 · 3 秒" : "被锁臂压制 · 3 秒"; if canPresentStep { impact.impactOccurred(intensity: 0.6) }
            case .grappleReleased(let attacker): feedback = attacker == localFighterIndex ? "震地击退" : "被震地击退"; if canPresentStep { impact.impactOccurred(intensity: 0.9) }
            case .grappleClash: feedback = "双方抓取相抵 · 拉开距离"
            case .roundEnded(let winner): feedback = winner == nil ? "平局 · 重赛" : winner == localFighterIndex ? "拿下一局" : "对手拿下一局"
            }
            guard canPresentStep else { return }
            feedbackUntil = presentedGame.frame + 75
        }
        guard canPresentStep else { return }
        if presentedGame.frame > feedbackUntil && !feedback.isEmpty { feedback = "" }
        if serial % 6 == 0 || !presentedGame.events.isEmpty { objectWillChange.send() }
    }
    func metrics(_ value: String) { report = value }
    func characterLoaded(_ status: String) { characterStatus = status }
    func characterFailed() { loadError = "人物资源无法载入，请返回后重试。"; pause() }
    func shutdown() {
        guard !ended else { return }
        ended = true
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
    var token: NSObjectProtocol?
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
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
    init(setup: DuelSetup) { self.setup = setup; preparation = nil; onExit = nil }
    init(external preparation: DuelNetworkMatchPreparation, onExit: @escaping () -> Void) {
        setup = nil; self.preparation = preparation; self.onExit = onExit
    }
    @ViewBuilder var body: some View {
        if let preparation, let onExit {
            DuelNetworkMatchContent(preparation: preparation, onExit: onExit).id(preparation.id)
        } else if let setup {
            DuelOfflineMatchContent(setup: setup)
        }
    }
}

private struct DuelOfflineMatchContent: View {
    @StateObject private var session: DuelSession
    init(setup: DuelSetup) { _session = StateObject(wrappedValue: DuelSession(setup)) }
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
                DuelControls(session: session, ultimateReady: session.ultimateReady).ignoresSafeArea(edges: .bottom)
            }
            VStack {
                hud
                if session.setup.mode == .tutorial {
                    Text(session.tutorial).font(.caption.bold()).padding(8).background(.black.opacity(0.65), in: Capsule())
                }
                Text(session.feedback).font(.headline.bold()).foregroundStyle(.yellow).frame(height: 24)
                Text(session.grappleStatus).font(.caption.monospacedDigit().bold()).frame(height: 20)
                    .accessibilityIdentifier("duel.grapple")
                if session.setup.mode != .versus {
                    Text("累计命中 \(session.localLandedHits) 次 · 伤害 \(session.localDamageDealt)")
                        .font(.caption.monospacedDigit()).accessibilityIdentifier("duel.hits")
                }
                Spacer()
            }.padding(.horizontal, 22).padding(.top, 8).allowsHitTesting(false)
            VStack {
                HStack {
                    Button { if preparation != nil { exitMatch() } else { session.pause() } } label: { Image(systemName: "pause.fill").padding(12) }
                        .accessibilityLabel("暂停").accessibilityIdentifier("duel.pause")
                    Spacer()
                    Button { session.showBoxes.toggle() } label: { Image(systemName: "viewfinder").padding(12) }
                        .accessibilityLabel("显示判定框").accessibilityIdentifier("duel.boxes")
                }.padding(.horizontal, 12)
                Spacer()
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
        .onChange(of: scenePhase) {
            if $0 != .active {
                if preparation != nil { exitMatch() } else { session.pause() }
            }
        }
        .onDisappear { if preparation != nil { exitMatch() } else { session.shutdown() } }
    }
    private var hud: some View {
        HStack(alignment: .top, spacing: 18) {
            fighterHUD(0)
            VStack(spacing: 3) {
                Text(session.setup.mode == .versus ? "\((session.game.remainingTicks + 59) / 60)" : "练习")
                    .font(.title2.monospacedDigit().bold())
                Text("\(session.game.wins[0])  :  \(session.game.wins[1])").font(.caption.bold())
            }.frame(width: 65)
            fighterHUD(1)
        }.padding(.horizontal, 50)
    }
    private func fighterHUD(_ i: Int) -> some View {
        let f = session.game.fighters[i]
        return VStack(alignment: i == 0 ? .leading : .trailing, spacing: 3) {
            Text("\(f.hero.name) · \(session.game.weaponFight?.profiles[i].weaponTitle ?? (i == session.localFighterIndex ? "你" : "对手"))").font(.caption.bold())
                .accessibilityIdentifier("duel.name.\(i)")
            ProgressView(value: Double(f.health), total: 1000).tint(i == 0 ? .orange : .cyan)
            Text("生命 \(f.health) · 防御 \(f.guardMeter / 10) · 能量 \(f.energy)")
                .font(.system(size: 10, design: .monospaced))
                .accessibilityIdentifier("duel.stats.\(i)")
                .accessibilityValue("生命 \(f.health)，位置 \(f.x)，高度 \(f.y)")
        }.frame(maxWidth: .infinity)
    }
    private func exitMatch() {
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
                Button("继续对决") { session.resume() }.accessibilityIdentifier("duel.resume")
                Button("重新挑战") { session.restart() }.accessibilityIdentifier("duel.restart")
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
                Button("重新挑战") { session.restart() }.accessibilityIdentifier("duel.rematch")
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
    let session: DuelSession
    func makeUIView(context: Context) -> DuelSourceControlsView {
        let view = DuelSourceControlsView(assetDirectory: session.weaponAssets?.directory)
        bind(view)
        if !view.sourceArtAvailable { session.characterFailed() }
        updateUIView(view, context: context)
        return view
    }
    func bind(_ view: DuelSourceControlsView) {
        view.onDirection = { [weak session] x, y in session?.weaponDirection(x: x, y: y) }
        view.onAction = { [weak session] action, down in
            guard let command = DuelWeaponInput.Action(rawValue: action.rawValue) else { return }
            session?.weaponAction(command, down: down)
        }
        view.onActionCancelled = { [weak session] action in
            guard let command = DuelWeaponInput.Action(rawValue: action.rawValue) else { return }
            session?.cancelWeaponAction(command)
        }
        view.onInputCancelled = { [weak session] in session?.cancelWeaponInput() }
        session.inputReset = { [weak view] in view?.cancelAll(notify: false) }
    }
    func updateUIView(_ view: DuelSourceControlsView, context: Context) { updateReadiness(view) }
    func updateReadiness(_ view: DuelSourceControlsView) {
        view.inputEnabled = !session.paused && session.loadError == nil
        view.opponentProne = session.game.fighters[session.opponentFighterIndex].knockdown > 0
        guard let fight = session.game.weaponFight else { view.inputEnabled = false; return }
        let index = session.localFighterIndex
        let profile = fight.profiles[index], fighter = session.localFighter
        for action in DuelSourceControlsView.Action.allCases {
            guard let command = DuelWeaponCommand(rawValue: action.rawValue) else { continue }
            let equipped = fight.supports(command, index: index)
            let enough = command != .shadow || fighter.energy >= 100
            let label = action == .weapon ? profile.weaponTitle + "攻击" : nil
            let readiness = !equipped ? (profile.clip(command: command) == nil ? "未装备" : "暂不可用") : !enough ? "需要 100 能量" : fighter.stun > 0 ? "受击中" : fighter.attack != nil ? "收招中" : "可施放"
            view.setState(.init(enabled: equipped, ready: enough && fighter.attack == nil && fighter.stun == 0,
                                description: readiness,
                                accessibilityLabel: label), for: action)
        }
    }
    static func dismantleUIView(_ view: DuelSourceControlsView, coordinator: ()) { view.cancelAll() }
}

struct DuelNetworkControls: UIViewRepresentable {
    let preparation: DuelNetworkMatchPreparation
    func makeUIView(context: Context) -> DuelNetworkControlsView {
        #if DEBUG
        if preparation.permitsFixture {
            return DuelNetworkControlsView(testing: preparation, controls: DuelSourceControlsView(images: [:]),
                                           acceptsFixtureArt: true)
        }
        #endif
        return DuelNetworkControlsView(preparation: preparation)
    }
    func updateUIView(_ view: DuelNetworkControlsView, context: Context) { view.refreshReadiness() }
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

    init(preparation: DuelNetworkMatchPreparation) {
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
         acceptsFixtureArt: Bool = false) {
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
        refreshReadiness()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !ended else { return }
        if window == nil, wasMounted { detach(); return }
        if window != nil { wasMounted = true }
        refreshReadiness()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !ended else { return }
        controls.frame = bounds
        controls.setNeedsLayout(); controls.layoutIfNeeded()
        refreshReadiness()
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !ended && controls.point(inside: convert(point, to: controls), with: event)
    }
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
            controls.onDirection != nil && controls.onAction != nil &&
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
        controls.onDirection = nil; controls.onAction = nil
        controls.onActionCancelled = nil; controls.onInputCancelled = nil
        controls.removeFromSuperview()
    }
}

struct DuelControls: UIViewRepresentable {
    let session: DuelSession
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
        if session.localFighter.hero == .liu { controls.append(("ultimate", "大招")) }
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
        guard let button = buttons.first(where: { $0.0 == "ultimate" })?.1 else { return }
        button.backgroundColor = ready ? UIColor.systemOrange.withAlphaComponent(0.85) : UIColor(white: 0.16, alpha: 0.78)
        button.accessibilityLabel = "擒拿震地大招"
        button.accessibilityValue = ready ? "可施放，消耗 100 能量" : "需要 100 能量"
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
