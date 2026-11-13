import Foundation
import CryptoKit
import Combine

/// Pin the two decoded original clips by bytes, not by a user-editable manifest.
/// Source bundle membership is verified, but the temple-fall clip is NOT bound
/// to the displayed dojo_autumn_lobby scene. Original chapter/faction dispatch,
/// crossfades, gain and loop points have not been recovered. The low-resolution
/// temple-fall record decodes to identical bytes, so only one copy is bundled.
@MainActor
enum DuelSourceMusic {
    struct Track {
        /// Nil preserves a verified source clip without inventing an app scene binding.
        let scene: DuelMusic.Scene?
        let name: String
        let bytes: Int
        let sha256: String
        let sourcePath: String
    }
    enum Failure: Error, Equatable { case missing(String), byteCount(String), digest(String) }
    struct Result {
        var tracks: [DuelMusic.Scene: URL] = [:]
        var verifiedClips: [String: URL] = [:]
        var failures: [Failure] = []
    }
    static let records: [Track] = [
        // The current lobby GLB is dojo_autumn_lobby, a different source bundle.
        // Similar names are not proof that its original dispatcher chose this clip.
        Track(scene: nil, name: "SF3Music_Autumn_Lobby", bytes: 23_040_044,
              sha256: "0a90ffdd2c641202fb67c798e6c678fe6fcf32cb80dd6537ba164ef93dfb486f",
              sourcePath: "assets/gamedata/resources/content/lobbylocations/dojo_temple_fall_lobby/soundtrack_dojo.ogg"),
        Track(scene: .battle, name: "SF3Music_Palace_Battle", bytes: 11_288_516,
              sha256: "3494fd3137bf361355d04b0d83f7d5c9c3552288b5df7a1005dc227f988ec169",
              sourcePath: "assets/gamedata/resources/content/locations/palace_exterior_raid/soundtrack_battle.ogg")
    ]

    /// Explicit product fallback, not recovered original Autumn scene dispatch.
    /// Only the hash-verified private clip may fill the otherwise silent lobby.
    static let temporaryLobbyTrackName = "SF3Music_Autumn_Lobby"
    static let temporaryLobbyNotice = "大厅音乐：Temple Fall（临时配乐）"
    static func playbackTracks(from result: Result) -> [DuelMusic.Scene: URL] {
        var tracks = result.tracks
        if tracks[.lobby] == nil {
            tracks[.lobby] = result.verifiedClips[temporaryLobbyTrackName]
        }
        return tracks
    }

    static func load(bundle: Bundle = .main) -> Result {
        load { record in
            bundle.url(forResource: record.name, withExtension: "wav") ??
            bundle.url(forResource: record.name, withExtension: "wav", subdirectory: "FighterPrivate") ??
            bundle.url(forResource: record.name, withExtension: "wav", subdirectory: "Resources/FighterPrivate")
        }
    }

    static func load(resolve: (Track) -> URL?) -> Result {
        var result = Result()
        for record in records {
            guard let url = resolve(record), url.isFileURL,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                result.failures.append(.missing(record.name)); continue
            }
            do {
                try validate(data, record: record)
                result.verifiedClips[record.name] = url
                if let scene = record.scene { result.tracks[scene] = url }
            } catch let error as Failure { result.failures.append(error) }
            catch { result.failures.append(.digest(record.name)) }
        }
        return result
    }

    static func validate(_ data: Data, record: Track) throws {
        guard data.count == record.bytes else { throw Failure.byteCount(record.name) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == record.sha256 else { throw Failure.digest(record.name) }
    }
}

/// One audio player owner across covers. A newer view of the same kind revokes
/// the previous token permanently; its delayed appear/pause/disappear callbacks
/// cannot reclaim or stop the new view's music. Battle ownership outranks lobby
/// even when UIKit sends overlapping visibility callbacks during a transition.
@MainActor
final class DuelMusicOwnership {
    static let shared = DuelMusicOwnership()
    private struct Claim {
        let id: UUID
        var visible: Bool
        var paused: Bool
        var permitsPlayback: @MainActor () -> Bool
    }
    private var claims: [DuelMusic.Scene: Claim] = [:]
    private var selected: UUID?
    private var selectedPaused: Bool?
    private var player: DuelMusic?
    private(set) var sourceFailures: [DuelSourceMusic.Failure] = []
    private let makeMusic: @MainActor () -> (DuelMusic, [DuelSourceMusic.Failure])

    init(music: DuelMusic? = nil) {
        makeMusic = {
            if let music { return (music, []) }
            let loaded = DuelSourceMusic.load()
            return (DuelMusic(tracks: DuelSourceMusic.playbackTracks(from: loaded)), loaded.failures)
        }
    }

    func claim(_ id: UUID, scene: DuelMusic.Scene, paused: Bool,
               permitsPlayback: @escaping @MainActor () -> Bool) {
        claims[scene] = Claim(id: id, visible: true, paused: paused, permitsPlayback: permitsPlayback)
        reconcile()
    }
    func update(_ id: UUID, scene: DuelMusic.Scene, visible: Bool, paused: Bool,
                permitsPlayback: @escaping @MainActor () -> Bool) {
        guard claims[scene]?.id == id else { return }
        claims[scene]?.visible = visible; claims[scene]?.paused = paused
        claims[scene]?.permitsPlayback = permitsPlayback
        reconcile()
    }
    func release(_ id: UUID, scene: DuelMusic.Scene) {
        guard claims[scene]?.id == id else { return }
        claims.removeValue(forKey: scene); reconcile()
    }
    func resumeAfterUserAction(_ id: UUID, scene: DuelMusic.Scene, sessionInterruptionEnded: Bool = false) {
        guard selected == id, let claim = claims[scene], claim.id == id,
              claim.visible, !claim.paused, claim.permitsPlayback() else { return }
        player?.resumeAfterUserAction(sessionInterruptionEnded: sessionInterruptionEnded)
    }
    private func playbackPermitted() -> Bool {
        guard let selected, let claim = claims.values.first(where: { $0.id == selected }),
              claim.visible, !claim.paused else { return false }
        return claim.permitsPlayback()
    }
    private func reconcile() {
        let scene: DuelMusic.Scene? = claims[.battle]?.visible == true ? .battle :
            claims[.lobby]?.visible == true ? .lobby : nil
        guard let scene, let claim = claims[scene] else {
            player?.setScene(nil); selected = nil; selectedPaused = nil; return
        }
        if player == nil {
            let loaded = makeMusic(); player = loaded.0; sourceFailures = loaded.1
            player?.setPlaybackPermission { [weak self] in self?.playbackPermitted() == true }
        }
        if selected != claim.id || selectedPaused != claim.paused {
            selected = claim.id; selectedPaused = claim.paused
            player?.setScene(scene, paused: claim.paused)
        } else {
            // Readiness can change without a new owner or pause-state transition.
            player?.refreshPlaybackPermission()
        }
    }
}

/// SwiftUI-owned lease. Lobby visibility can resume after a cover, but a closed
/// match is terminal. Superseded leases remain revoked on subsequent callbacks.
@MainActor
final class DuelMusicLease: ObservableObject {
    private let id = UUID()
    private let scene: DuelMusic.Scene
    private let ownership: DuelMusicOwnership
    private var registered = false
    private var closed = false
    init(scene: DuelMusic.Scene, ownership: DuelMusicOwnership? = nil) {
        self.scene = scene; self.ownership = ownership ?? .shared
    }
    func update(visible: Bool, paused: Bool = false,
                permitsPlayback: @escaping @MainActor () -> Bool = { true }) {
        guard !closed else { return }
        if !registered {
            guard visible else { return }
            registered = true
            ownership.claim(id, scene: scene, paused: paused, permitsPlayback: permitsPlayback)
        } else {
            ownership.update(id, scene: scene, visible: visible, paused: paused, permitsPlayback: permitsPlayback)
        }
    }
    func resumeAfterUserAction(sessionInterruptionEnded: Bool = false) {
        guard !closed, registered else { return }
        ownership.resumeAfterUserAction(id, scene: scene, sessionInterruptionEnded: sessionInterruptionEnded)
    }
    func close() {
        guard !closed else { return }
        closed = true; ownership.release(id, scene: scene)
    }
    deinit {
        // SwiftUI can discard an owner without an onDisappear callback. The
        // token check makes deferred release harmless after a replacement.
        let ownership = ownership, id = id, scene = scene
        Task { @MainActor in ownership.release(id, scene: scene) }
    }
}
