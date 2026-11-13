import Foundation
import SceneKit
import UIKit
import AVFoundation
import CryptoKit

@MainActor
protocol DuelEffectPlayback: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func pause()
    func stop()
}

extension AVAudioPlayer: DuelEffectPlayback {}

/// Source hit/block artwork and sound, driven by the application's simulation clock.
///
/// The private manifest contains sampled source ParticleSystem curves, not executable
/// Unity code. Source combat event timing, RNG, billboard projection and GPU color
/// space are not claimed to be identical to the original game. No wall-clock action
/// or autonomous SceneKit particle system can advance an interrupted fight.
@MainActor
final class DuelSourceEffects: NSObject {
    enum Kind: String { case hit, block }
    /// Weapon-family labels are verified source audio directories. They do
    /// not claim recovered original event IDs or heavy/light selection rules.
    enum SoundFamily { case unarmed, katana, dualHammers }
    enum Failure: Error { case missing, manifest, resource(String), audioPreparation(String) }

    struct Contact {
        let kind: Kind
        let position: SCNVector3
        let direction: Int
        let heavy: Bool
        let sound: SoundFamily

        init(kind: Kind, position: SCNVector3, direction: Int, heavy: Bool = false, sound: SoundFamily = .unarmed) {
            self.kind = kind; self.position = position; self.direction = direction; self.heavy = heavy
            self.sound = sound
        }
    }
    struct Swing {
        let heavy: Bool
        let sound: SoundFamily
        init(heavy: Bool = false, sound: SoundFamily = .unarmed) { self.heavy = heavy; self.sound = sound }
    }

    static let manifestName = "SF3FX_manifest.json"
    static let manifestSHA256 = "c4f66cb7f2805bbee6c8667ad9e4bb90f90f3e6d07c368b1dcb1da6699331e7f"
    private static let maximumBursts = 8

    private struct SourceFile: Decodable {
        let name: String
        let bytes: Int
        let sha256: String
    }
    private struct Manifest: Decodable {
        let version: Int
        let sampleRate: Int
        let worldUnitsPerSourceUnit: Float
        let files: [SourceFile]
        let effects: [String: Effect]
        let audio: [String: [String]]
        let limitations: [String]
    }
    private struct Effect: Decodable {
        let sourceName: String
        let duration: Double
        let tracks: [Track]
    }
    private struct Track: Decodable {
        let name: String
        let layer: Int
        let texture: String
        let blend: String
        let wrapS: Int
        let wrapT: Int
        let multiplyTextureAlpha: Bool
        let overlay: Bool
        let sortingOrder: Int
        let delay: Double
        let duration: Double
        /// t, source XYZ, width/height, angle, RGBA, UV offset XY and scale XY.
        let frames: [[Float]]

        func sample(at time: Double) -> [Float]? {
            let local = time - delay
            guard local >= 0, local < duration, let first = frames.first else { return nil }
            if local <= Double(first[0]) { return first }
            var low = 0, high = frames.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if Double(frames[middle][0]) <= local { low = middle } else { high = middle }
            }
            let a = frames[low], b = frames[high]
            let fraction = Float((local - Double(a[0])) / Double(b[0] - a[0]))
            var result = a
            // Atlas selection is discrete. Interpolating UV cells would smear
            // neighboring sprites during an otherwise paused source effect.
            for i in 0..<11 { result[i] = a[i] + (b[i] - a[i]) * fraction }
            return result
        }
    }
    private struct Particle {
        let track: Track
        let node: SCNNode
        let material: SCNMaterial
    }
    private struct Burst {
        let kind: Kind
        let tick: Int
        let direction: Float
        let root: SCNNode
        let duration: Double
        let particles: [Particle]
    }

    private let root: SCNNode
    private var manifest: Manifest?
    private var textures: [String: UIImage] = [:]
    // Manifest validation bounds this to 2 effects × 64 tracks; no global cache.
    private var preparationTemplates: [String: [SCNGeometry]] = [:]
    private var availableBursts: [String: [Burst]] = [:]
    private var players: [String: [DuelEffectPlayback]] = [:]
    // Owned copies of authenticated bytes, never URLs that can change after load.
    private var audioBytes: [String: [Data]] = [:]
    private let center: NotificationCenter
    private let makePlayer: (Data) throws -> DuelEffectPlayback
    private var mediaServicesAvailable = true
    private var audioInterrupted = false
    private var requiresUserAudioResume = false
    private var hasConsumedSoundEvent = false
    private var pendingUserAudioResume = false
    enum AudioStatus: Equatable { case ready, lost, needsRebuild, failed, stopped }
    private(set) var audioStatus: AudioStatus = .ready
    private(set) var audioFailure: String?
    private var soundCursor: [String: Int] = [:]
    private var pausedPlayers: Set<ObjectIdentifier> = []
    private var bursts: [Burst] = []
    private var sequence = 0
    private var lastTick: Int?
    private var lastLiuShadowTick: Int?
    private var paused = false
    private var ended = false
    private(set) var emittedHits = 0
    private(set) var emittedBlocks = 0
    private(set) var playedSounds = 0
    private(set) var playedSoundCategories: [String: Int] = [:]

    var activeBurstCount: Int { bursts.count }
    var activeParticleCount: Int { bursts.reduce(0) { $0 + $1.particles.filter { !$0.node.isHidden }.count } }
    var sourceTextureCount: Int { textures.count }
    /// Verified retained resources, independent of media-server player lifetime.
    var sourceAudioCount: Int { audioBytes.filter { $0.key != "liuShadow" }.values.reduce(0) { $0 + $1.count } }
    var hasLiuShadowVoice: Bool { audioBytes["liuShadow"]?.count == 1 }
    var allocatedAudioPlayerCount: Int { players.values.reduce(0) { $0 + $1.count } }
    var playingAudioPlayerCount: Int { players.values.reduce(0) { $0 + $1.filter(\.isPlaying).count } }
    var pausedAudioPlayerCount: Int { pausedPlayers.count }
    var limitations: [String] { manifest?.limitations ?? [] }

    /// A present invalid manifest must not silently pick another directory.
    static func manifestURL(directory: URL? = nil, bundle: Bundle = .main) -> URL? {
        let bases = directory.map { [$0] } ?? [bundle.resourceURL,
            bundle.resourceURL?.appendingPathComponent("FighterPrivate", isDirectory: true),
            bundle.resourceURL?.appendingPathComponent("FighterPrivate/SourceEffects", isDirectory: true)]
            .compactMap { $0 }
        return bases.map { $0.appendingPathComponent(manifestName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    init(root: SCNNode, directory: URL? = nil, bundle: Bundle = .main,
         center: NotificationCenter = .default,
         makePlayer: @escaping (Data) throws -> DuelEffectPlayback = { try AVAudioPlayer(data: $0) }) throws {
        self.root = root; self.center = center; self.makePlayer = makePlayer
        super.init()
        guard let url = Self.manifestURL(directory: directory, bundle: bundle) else { throw Failure.missing }
        let manifestData = try Data(contentsOf: url, options: .mappedIfSafe)
        guard manifestData.count <= 2_000_000,
              Self.digest(manifestData) == Self.manifestSHA256 else { throw Failure.manifest }
        let definition = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard definition.version == 2, definition.sampleRate == 240,
              definition.worldUnitsPerSourceUnit == 0.01,
              Set(definition.effects.keys) == Set(["hit", "block"]),
              definition.files.count == 38,
              Set(definition.files.map(\.name)).count == definition.files.count else { throw Failure.manifest }

        let base = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        var resources: [String: Data] = [:]
        var total = 0
        for file in definition.files {
            guard file.name.hasPrefix("SF3FX_"), !file.name.contains("/"), !file.name.contains("\\"),
                  !file.name.contains(".."), (1...4_000_000).contains(file.bytes) else { throw Failure.manifest }
            let path = base.appendingPathComponent(file.name)
            let attributes = try path.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard attributes.isSymbolicLink != true, attributes.isRegularFile == true else {
                throw Failure.resource(file.name)
            }
            let bytes = try Data(contentsOf: path, options: .mappedIfSafe)
            total += bytes.count
            guard total <= 8_000_000, bytes.count == file.bytes,
                  Self.digest(bytes) == file.sha256 else { throw Failure.resource(file.name) }
            resources[file.name] = bytes
            if file.name.hasSuffix(".png") {
                guard let image = UIImage(data: bytes), image.size.width <= 512,
                      image.size.height <= 512 else { throw Failure.resource(file.name) }
                textures[file.name] = image
            }
        }
        for (name, effect) in definition.effects {
            guard (0..<1.1).contains(effect.duration), !effect.tracks.isEmpty,
                  effect.tracks.count <= 64 else { throw Failure.manifest }
            let requiredLayers = name == "hit" ? 6 : 9
            guard Set(effect.tracks.map(\.layer)) == Set(0..<requiredLayers) else { throw Failure.manifest }
            for track in effect.tracks {
                guard textures[track.texture] != nil, ["add", "alpha"].contains(track.blend),
                      (0...1).contains(track.wrapS), (0...1).contains(track.wrapT),
                      track.delay >= 0, track.duration > 0, track.delay + track.duration <= 1.1,
                      (2...300).contains(track.frames.count), track.frames.first?.first == 0 else {
                    throw Failure.manifest
                }
                var previous: Float = -1
                for state in track.frames {
                    // These are signed source transform scales. The verified
                    // block prefab mirrors X on all 21 tracks; requiring a
                    // positive width rejects that intact source manifest.
                    guard state.count == 15, state.allSatisfy(\.isFinite), state[0] > previous,
                          abs(state[4]) < 1_000, abs(state[5]) < 1_000 else {
                        throw Failure.manifest
                    }
                    previous = state[0]
                }
                guard abs(Double(previous) - track.duration) < 0.00001 else { throw Failure.manifest }
            }
        }
        let audioCounts = ["hit": 3, "heavyHit": 3, "block": 3, "whoosh": 3, "heavyWhoosh": 3,
                           "katanaHit": 3, "katanaWhoosh": 3, "katanaBlock": 2,
                           "hammerHit": 3, "hammerBlock": 3]
        for (category, filenames) in definition.audio {
            guard let expectedCount = audioCounts[category], filenames.count == expectedCount else { throw Failure.manifest }
            audioBytes[category] = try filenames.map { name in
                guard name.hasSuffix(".wav"), let bytes = resources[name] else { throw Failure.resource(name) }
                // File-size validation above already requires at least one byte.
                // Keep the owned-copy boundary independently nonempty as well.
                return try bytes.withUnsafeBytes { buffer in
                    guard !buffer.isEmpty, let address = buffer.baseAddress else {
                        throw Failure.resource(name)
                    }
                    return Data(bytes: address, count: buffer.count)
                }
            }
        }
        guard textures.count == 9, audioBytes.count == 10,
              audioBytes.values.reduce(0, { $0 + $1.count }) == 29 else { throw Failure.manifest }
        // Independent, pre-produced callout. Missing older optional packs remain
        // distinguishable; a present altered WAV never becomes a silent fallback.
        if let callout = try DuelPresentationAssets.verifiedVoice(directory: base) {
            audioBytes["liuShadow"] = [callout]
        }
        players = try buildPlayers(requirePreparation: false)
        manifest = definition
        observeMediaServices()
    }

    deinit { center.removeObserver(self) }

    private func buildPlayers(requirePreparation: Bool = true) throws -> [String: [DuelEffectPlayback]] {
        var rebuilt: [String: [DuelEffectPlayback]] = [:]
        // Stable construction order also makes failure/recovery diagnostics repeatable.
        for category in audioBytes.keys.sorted() {
            rebuilt[category] = try audioBytes[category]!.map { bytes in
                let player = try makePlayer(bytes)
                guard player.duration > 0, player.duration < 2 else { throw Failure.resource(category) }
                if !player.prepareToPlay() {
                    // Initial loading historically accepts a decoded, verified
                    // clip even when the shared audio service cannot prepare it
                    // now. Do not turn a transient audio failure into a missing
                    // character/resource failure that blocks gameplay.
                    if requirePreparation { throw Failure.audioPreparation(category) }
                    audioStatus = .failed
                    audioFailure = "Initial effect preparation failed: \(category)"
                }
                return player
            }
        }
        return rebuilt
    }

    private func observeMediaServices() {
        center.addObserver(self, selector: #selector(audioInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(audioRouteChanged(_:)),
                           name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(mediaServicesLost),
                           name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
        center.addObserver(self, selector: #selector(mediaServicesReset),
                           name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    @objc private nonisolated func audioInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let began = type == .began
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.ended else { return }
            self.audioInterrupted = began
            if began {
                self.pendingUserAudioResume = false
                if self.hasConsumedSoundEvent { self.suspendAudioForUserResume() }
            } else if self.pendingUserAudioResume {
                self.pendingUserAudioResume = false
                if !self.paused, self.mediaServicesAvailable {
                    self.requiresUserAudioResume = false
                }
            }
            // Ending an interruption never replays a previous attack, even if
            // the OS allows soundtrack resumption. The match owns user consent.
        }
    }
    @objc private nonisolated func audioRouteChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hasConsumedSoundEvent else { return }
            self.suspendAudioForUserResume()
        }
    }

    /// Also invoked by the current session: neither observer registration order
    /// nor deferred SwiftUI pause publication may retain an old effect tail.
    func suspendAudioForUserResume() {
        guard !ended else { return }
        requiresUserAudioResume = true
        pendingUserAudioResume = false
        for group in players.values { for player in group { player.stop(); player.currentTime = 0 } }
        pausedPlayers.removeAll()
    }
    func resumeAudioAfterUserAction(sessionInterruptionEnded: Bool = false) {
        guard !ended, !paused, mediaServicesAvailable else { return }
        if audioInterrupted {
            // The session may already have consumed ended while this owner's
            // ended callback is still queued. Preserve that successful user
            // action, but never bypass the local interruption availability gate.
            // Only the session may supply this evidence; direct early resume
            // keeps its previous rejection behavior.
            if sessionInterruptionEnded { pendingUserAudioResume = true }
            return
        }
        pendingUserAudioResume = false
        requiresUserAudioResume = false
        // Do not play here. Only a subsequent live combat event may make sound.
    }

    @objc private nonisolated func mediaServicesLost() { enqueueMediaAvailability(false) }
    @objc private nonisolated func mediaServicesReset() { enqueueMediaAvailability(true) }
    private nonisolated func enqueueMediaAvailability(_ available: Bool) {
        // All posts, including main-thread posts, use the same FIFO queue.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.ended else { return }
            self.mediaServicesAvailable = available
            self.pendingUserAudioResume = false
            if available { self.audioInterrupted = false }
            for group in self.players.values { for player in group { player.stop() } }
            self.players.removeAll(); self.pausedPlayers.removeAll()
            self.audioStatus = available ? .needsRebuild : .lost
            // No reconstruction or playback here: only a future new event can
            // request sound. Paused/retained network resources stay dormant.
        }
    }

    #if DEBUG
    /// Synthetic test data only. Does not load or authenticate any source assets,
    /// construct audio players, or exercise the production initializer.
    static func preparationFixture(root: SCNNode) -> DuelSourceEffects {
        DuelSourceEffects(preparationFixtureRoot: root)
    }

    private init(preparationFixtureRoot root: SCNNode) {
        self.root = root; center = .default
        makePlayer = { try AVAudioPlayer(data: $0) }
        super.init()
        let texture = "synthetic-preparation"
        textures[texture] = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        var tracks: [Track] = []
        // Three fragment bodies, both depth modes and all sampler wrap modes.
        // Alpha includes both multiply flags to cover their equivalent handling.
        for blend in ["alpha", "add"] {
            for multiply in [false, true] {
                for overlay in [false, true] {
                    for wrapS in [0, 1] {
                        for wrapT in [0, 1] {
                            tracks.append(Track(name: "synthetic-track-\(tracks.count)", layer: tracks.count,
                                texture: texture, blend: blend, wrapS: wrapS, wrapT: wrapT,
                                multiplyTextureAlpha: multiply, overlay: overlay, sortingOrder: tracks.count,
                                delay: 0, duration: 0.5,
                                frames: [[0, 0, 0, 0, 10, 10, 0, 1, 1, 1, 1, 0, 0, 1, 1],
                                         [0.5, 0, 0, 0, 20, 20, 0, 0.5, 0.5, 0.5, 0.5, 0.5, 0, 0.5, 1]]))
                        }
                    }
                }
            }
        }
        manifest = Manifest(version: 0, sampleRate: 240, worldUnitsPerSourceUnit: 0.01,
            files: [], effects: ["hit": Effect(sourceName: "synthetic-hit", duration: 0.5, tracks: tracks),
                                "block": Effect(sourceName: "synthetic-block", duration: 0.5, tracks: tracks)],
            audio: [:], limitations: ["DEBUG synthetic preparation fixture; not authenticated source artwork or audio."])
    }
    #endif

    /// Prepare the actual bounded particle pool before entering combat. Each
    /// slot owns its mutable uniforms and atlas transforms; textures are shared.
    /// This removes SceneKit object construction from warm impact events, not
    /// all per-frame allocations or a guarantee of sustained frame performance.
    func preparationObjects() -> [Any] {
        guard !ended else { return [] }
        ensureBurstPool()
        let slots = availableBursts.keys.sorted().flatMap { availableBursts[$0]! } + bursts
        return slots.flatMap { $0.particles }.compactMap { $0.node.geometry }
    }

    private func ensureBurstPool() {
        guard availableBursts.isEmpty, !ended, let manifest else { return }
        ensurePreparationTemplates()
        for kind in [Kind.hit, .block] {
            guard let effect = manifest.effects[kind.rawValue],
                  let templates = preparationTemplates[kind.rawValue] else { continue }
            availableBursts[kind.rawValue] = (0..<Self.maximumBursts).map { _ in
                let holder = SCNNode()
                let billboard = SCNBillboardConstraint()
                billboard.freeAxes = .all
                holder.constraints = [billboard]
                let particles = effect.tracks.enumerated().map { index, track in
                    let plane = templates[index].copy() as! SCNGeometry
                    let material = templates[index].firstMaterial!.copy() as! SCNMaterial
                    plane.materials = [material]
                    let node = SCNNode(geometry: plane)
                    node.name = track.name; node.castsShadow = false; node.isHidden = true
                    node.renderingOrder = 100 + track.sortingOrder
                    holder.addChildNode(node)
                    return Particle(track: track, node: node, material: material)
                }
                return Burst(kind: kind, tick: 0, direction: 1, root: holder,
                             duration: effect.duration, particles: particles)
            }
        }
    }

    private func recycle(_ burst: Burst) {
        burst.root.removeFromParentNode()
        for particle in burst.particles { particle.node.isHidden = true }
        availableBursts[burst.kind.rawValue, default: []].append(burst)
    }

    private func ensurePreparationTemplates() {
        guard preparationTemplates.isEmpty, !ended, let manifest else { return }
        for (kind, effect) in manifest.effects {
            preparationTemplates[kind] = effect.tracks.map { track in
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = textures[track.texture]
                material.diffuse.wrapS = track.wrapS == 0 ? .repeat : .clamp
                material.diffuse.wrapT = track.wrapT == 0 ? .repeat : .clamp
                material.diffuse.minificationFilter = .linear; material.diffuse.magnificationFilter = .linear
                material.diffuse.mipFilter = .none
                material.isDoubleSided = true; material.writesToDepthBuffer = false
                material.readsFromDepthBuffer = !track.overlay
                material.transparencyMode = .aOne
                material.blendMode = track.blend == "add" ? .add : .alpha
                material.shaderModifiers = [.fragment: Self.fragment(track)]
                material.setValue(NSValue(scnVector4: SCNVector4(0, 0, 0, 0)), forKey: "sourceFXColor")
                let plane = SCNPlane(width: 1, height: 1)
                plane.materials = [material]
                return plane
            }
        }
    }

    /// Call once immediately after *every* simulation step, before its event
    /// queues are cleared by another step. Do not collect only the last step
    /// in a display callback: that would lose contacts at a lower render rate.
    ///
    /// `animationTick` is the post-step visual clock. It stays unchanged during
    /// hit-stop; empty steps still call this method to keep that contract clear.
    /// Contacts start one visual step earlier because the original source size
    /// curves start at zero. Their first displayed state is therefore visible
    /// before hit-stop freezes it. Events are never deduplicated by this clock:
    /// two contacts at the same tick must remain two effects.
    func consumeStep(contacts: [Contact], swings: [Swing], animationTick: Int, liuShadowTick: Int? = nil) {
        guard !ended, !paused, animationTick >= 0 else { return }
        if let lastTick, animationTick < lastTick { reset() }
        // A fixed-step action edge owns the shout. Repeated frame-zero draws,
        // hit-stop, or attaching a renderer halfway through a skill cannot replay it.
        if liuShadowTick == 0, lastLiuShadowTick != 0 { play("liuShadow") }
        if liuShadowTick == nil, lastLiuShadowTick != nil {
            for player in players["liuShadow"] ?? [] {
                player.stop(); player.currentTime = 0
                pausedPlayers.remove(ObjectIdentifier(player))
            }
        }
        lastLiuShadowTick = liuShadowTick
        for swing in swings { playWhoosh(heavy: swing.heavy, tick: animationTick, sound: swing.sound) }
        let birthTick = max(0, animationTick - 1)
        for contact in contacts {
            emit(kind: contact.kind, position: contact.position, direction: contact.direction,
                 tick: birthTick, heavy: contact.heavy, sound: contact.sound)
        }
        advance(to: animationTick)
    }

    /// Lower-level birth event. `tick` is the visual clock at the start of the
    /// step resolving contact. Call advance with its post-step clock before
    /// drawing, or use consumeStep to perform both operations together.
    /// Birth events do not rewind the clock; reset explicitly when restarting.
    func emit(kind: Kind, position: SCNVector3, direction: Int, tick: Int, heavy: Bool = false,
              sound: SoundFamily = .unarmed) {
        guard !ended, !paused, tick >= 0, let effect = manifest?.effects[kind.rawValue] else { return }
        ensureBurstPool()
        // Recycle before checkout so even eight simultaneous same-kind impacts
        // have a free slot. The oldest active effect remains the eviction policy.
        if bursts.count == Self.maximumBursts { recycle(bursts.removeFirst()) }
        guard let slot = availableBursts[kind.rawValue]?.popLast() else { return }
        sequence += 1
        slot.root.name = "duel.source-effect.\(kind.rawValue).\(sequence)"
        slot.root.position = position
        root.addChildNode(slot.root)
        bursts.append(Burst(kind: kind, tick: tick, direction: direction < 0 ? -1 : 1,
                            root: slot.root, duration: effect.duration, particles: slot.particles))
        if kind == .hit { emittedHits += 1 } else { emittedBlocks += 1 }
        switch sound {
        case .unarmed: play(kind == .block ? "block" : heavy ? "heavyHit" : "hit")
        case .katana: play(kind == .block ? "katanaBlock" : "katanaHit")
        case .dualHammers: play(kind == .block ? "hammerBlock" : "hammerHit")
        }
    }

    /// This is an application swing event; a recovered source animation event
    /// table is not available. A whiff must still play its swing sound.
    func playWhoosh(heavy: Bool, tick: Int, sound: SoundFamily = .unarmed) {
        guard !ended, !paused, tick >= 0 else { return }
        switch sound {
        case .unarmed: play(heavy ? "heavyWhoosh" : "whoosh")
        case .katana: play("katanaWhoosh")
        // No hammer-specific source whoosh was verified. Do not substitute a
        // fist sound or label a generic medium-weapon sound as original here.
        case .dualHammers: break
        }
    }

    func advance(to tick: Int) {
        guard !ended, !paused, let manifest else { return }
        if let lastTick, tick < lastTick { reset() }
        self.lastTick = tick
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        var surviving: [Burst] = []
        for burst in bursts {
            let time = Double(max(0, tick - burst.tick)) / Double(DuelGame.ticksPerSecond)
            if time >= burst.duration { recycle(burst); continue }
            for particle in burst.particles {
                guard let state = particle.track.sample(at: time) else { particle.node.isHidden = true; continue }
                // Preserve the source reflection in scale below. Only a
                // collapsed axis is invisible; a negative axis is mirrored.
                particle.node.isHidden = abs(state[4]) < 0.00001 || abs(state[5]) < 0.00001
                let unit = manifest.worldUnitsPerSourceUnit
                particle.node.position = SCNVector3(state[1] * unit * burst.direction, state[2] * unit, state[3] * unit)
                particle.node.scale = SCNVector3(state[4] * unit * burst.direction, state[5] * unit, 1)
                particle.node.eulerAngles.z = state[6] * burst.direction
                particle.material.setValue(NSValue(scnVector4: SCNVector4(state[7], state[8], state[9], state[10])),
                                           forKey: "sourceFXColor")
                var transform = SCNMatrix4Identity
                transform.m11 = state[13]; transform.m22 = state[14]
                transform.m41 = state[11]; transform.m42 = state[12]
                particle.material.diffuse.contentsTransform = transform
            }
            surviving.append(burst)
        }
        bursts = surviving
        SCNTransaction.commit()
    }

    func setPaused(_ value: Bool) {
        guard !ended, value != paused else { return }
        paused = value
        if value { pendingUserAudioResume = false }
        for group in players.values {
            for player in group {
                let identity = ObjectIdentifier(player)
                if value, player.isPlaying { pausedPlayers.insert(identity); player.pause() }
                else if !value, !audioInterrupted, !requiresUserAudioResume, mediaServicesAvailable,
                        pausedPlayers.contains(identity), !player.play() {
                    audioStatus = .failed; audioFailure = "Effect resume failed"
                }
            }
        }
        if !value { pausedPlayers.removeAll() }
    }

    func reset() {
        for burst in bursts { recycle(burst) }
        bursts.removeAll(); lastTick = nil; lastLiuShadowTick = nil; sequence = 0
        emittedHits = 0; emittedBlocks = 0; playedSounds = 0
        playedSoundCategories.removeAll()
        for group in players.values { for player in group { player.stop(); player.currentTime = 0 } }
        pausedPlayers.removeAll(); soundCursor.removeAll()
    }

    func shutdown() {
        guard !ended else { return }
        reset(); ended = true; center.removeObserver(self)
        audioStatus = .stopped
        preparationTemplates.removeAll(); availableBursts.removeAll()
        players.removeAll(); audioBytes.removeAll(); textures.removeAll(); manifest = nil
    }

    private func play(_ category: String) {
        guard !ended, !paused, let bytes = audioBytes[category], !bytes.isEmpty else { return }
        // Verified preparation can precede any session. An unused pool must not
        // carry an unrelated prior match's consent into a future network start.
        // Once used, keep this ownership history across round resets.
        hasConsumedSoundEvent = true
        let cursor = soundCursor[category, default: 0]
        // Consume each live event once, even during service loss/failure. Recovery
        // must not shift category rotation or queue an attack for later replay.
        soundCursor[category] = (cursor + 1) % bytes.count
        guard mediaServicesAvailable, !audioInterrupted, !requiresUserAudioResume else { return }
        if players.isEmpty {
            do {
                players = try buildPlayers()
                audioStatus = .ready; audioFailure = nil
            } catch {
                audioStatus = .failed; audioFailure = "Effect reconstruction failed: \(error)"
                return
            }
        }
        guard let group = players[category], group.count == bytes.count else {
            audioStatus = .failed; audioFailure = "Missing effect category: \(category)"
            return
        }
        let player = group[cursor % group.count]
        player.stop(); player.currentTime = 0
        if player.play() {
            audioStatus = .ready; audioFailure = nil
            playedSounds += 1
            playedSoundCategories[category, default: 0] += 1
        } else {
            audioStatus = .failed; audioFailure = "Effect playback failed: \(category)"
        }
    }

    private static func fragment(_ track: Track) -> String {
        // Additive output is explicitly multiplied by its source alpha before
        // blending. Its output alpha is one, so SceneKit cannot apply it twice.
        let expression: String
        if track.blend == "alpha" {
            expression = "_output.color = _surface.diffuse * sourceFXColor;"
        } else if track.multiplyTextureAlpha {
            expression = "float4 sourceFX = _surface.diffuse * sourceFXColor; _output.color = float4(sourceFX.rgb * sourceFX.a, 1.0);"
        } else {
            expression = "_output.color = float4(_surface.diffuse.rgb * sourceFXColor.rgb, 1.0);"
        }
        return "#pragma arguments\nfloat4 sourceFXColor;\n#pragma transparent\n#pragma body\n\(expression)"
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
