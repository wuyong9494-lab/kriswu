import Foundation
import CryptoKit
import SceneKit

/// Self-consistent build metadata, NOT a signature or proof of the
/// compiler's output. Sources are not shipped, so runtime cannot rehash sources.
struct DuelNetworkRulesManifest {
    static let resourceName = "FighterNetworkRules"
    static let recipe = "fighter-network-rules-v1"
    static let maximumBytes = 262_144
    static let helperPaths: Set<String> = [
        "project.yml", "App/Info.plist", "Shared/CaptureIntents.swift", "Shared/DutyActivity.swift", "Shared/WidgetShared.swift",
        "Sources/ShiftCore/BoneSampler.swift", "App/Services/GLTFModel.swift",
        "App/Services/ArenaOpaquePNG.swift", "App/Services/GameRoom.swift",
        "App/Services/GameRoomDirectIdentity.swift"
    ]
    static let requiredPaths: Set<String> = helperPaths.union([
        "Sources/ShiftCore/DuelGame.swift",
        "Sources/ShiftCore/DuelWeaponMotion.swift",
        "Sources/ShiftCore/DuelWeaponFight.swift",
        "Sources/ShiftCore/DuelWeaponThrow.swift",
        "Sources/ShiftCore/DuelFighterAssetRelease.swift",
        "Sources/ShiftCore/DuelCombatRules.swift",
        "Sources/ShiftCore/DuelImpactMotion.swift",
        "Sources/ShiftCore/DuelPanguRules.swift",
        "Sources/ShiftCore/DuelPanguState.swift",
        "Sources/ShiftCore/DuelPanguSpatialState.swift",
        "Sources/ShiftCore/DuelPanguPresentation.swift",
        "Sources/ShiftCore/DuelWeaponInput.swift",
        "Sources/ShiftCore/DuelMultiplayerSelection.swift",
        "Sources/ShiftCore/DuelMultiplayerReplica.swift",
        "Sources/ShiftCore/DuelNetworkStartBarrier.swift",
        "Sources/ShiftCore/DuelNetworkInputs.swift",
        "Sources/ShiftCore/DuelNetworkCombatProtocol.swift",
        "Sources/ShiftCore/DuelNetworkCombatState.swift",
        "Sources/ShiftCore/DuelNetworkCombatWire.swift",
        "Sources/ShiftCore/DuelNetworkHostSimulation.swift",
        "Sources/ShiftCore/DuelNetworkReplay.swift",
        "Sources/ShiftCore/DuelReplayState.swift",
        "App/Services/DuelNetworkCompatibilityIdentity.swift",
        "App/Services/DuelNetworkLobby.swift",
        "App/Services/DuelNetworkMessageRouter.swift",
        "App/Services/DuelWeaponAssets.swift",
        "App/Services/DuelFighterAssetReleaseLoader.swift",
        "App/Services/DuelSourceEffects.swift",
        "App/Services/DuelWeaponEffects.swift",
        "App/Services/DuelPanguDiagnostics.swift",
        "App/Services/DuelSourceWeaponTrails.swift",
        "App/Services/DuelStage.swift",
        "App/Views/DuelSourceControls.swift",
        "App/Views/DuelNetworkSelectionModel.swift",
        "App/Views/DuelNetworkRoomView.swift",
        "App/Views/DuelView.swift",
        "App/Views/DuelPanguHUD.swift",
        "App/Views/DuelWorld.swift"
    ])
    static let buildKeys: Set<String> = [
        "mode", "TARGET_NAME", "CONFIGURATION", "PLATFORM_NAME", "SDK_VERSION", "SWIFT_VERSION",
        "XCODE_VERSION_ACTUAL", "IPHONEOS_DEPLOYMENT_TARGET", "SWIFT_OPTIMIZATION_LEVEL",
        "SWIFT_COMPILATION_MODE", "ENABLE_TESTABILITY", "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
        "FIGHTER_ASSET_RELEASE_SHA256"
    ]
    enum Failure: Error, Equatable { case malformed, unsupported, invalidBuild, invalidFiles, fingerprintMismatch }
    private struct Document: Decodable {
        let schemaVersion: Int
        let recipe: String
        let files: [DuelNetworkContentRecord]
        let build: [String: String]
        let fingerprint: String
    }
    let files: [DuelNetworkContentRecord]
    let build: [String: String]
    let fingerprint: String

    init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["schemaVersion", "recipe", "build", "files", "fingerprint"]),
              let rawFiles = object["files"] as? [[String: Any]],
              rawFiles.allSatisfy({ Set($0.keys) == Set(["path", "bytes", "sha256"]) }),
              let decoded = try? JSONDecoder().decode(Document.self, from: data) else {
            throw Failure.malformed
        }
        guard decoded.schemaVersion == 1, decoded.recipe == Self.recipe else { throw Failure.unsupported }
        guard Set(decoded.build.keys) == Self.buildKeys, decoded.build["mode"] == "xcode",
              decoded.build["TARGET_NAME"] == "ShiftReminder",
              ["CONFIGURATION", "PLATFORM_NAME", "SDK_VERSION", "SWIFT_VERSION", "XCODE_VERSION_ACTUAL",
               "IPHONEOS_DEPLOYMENT_TARGET"].allSatisfy({ decoded.build[$0]?.isEmpty == false }),
              decoded.build["FIGHTER_ASSET_RELEASE_SHA256"].map({ $0.isEmpty || DuelNetworkContentRecord.validDigest($0) }) == true,
              decoded.build.values.allSatisfy({ $0.utf8.count <= 256 &&
                  $0.range(of: "^[A-Za-z0-9_.+ =()$-]*\\z", options: .regularExpression) != nil }) else {
            throw Failure.invalidBuild
        }
        let paths = decoded.files.map(\.path)
        guard (1...1024).contains(decoded.files.count), paths == paths.sorted(),
              Set(paths).count == paths.count, Self.requiredPaths.isSubset(of: Set(paths)),
              decoded.files.allSatisfy({ Self.allowedPath($0.path) && (1...8_000_000).contains($0.bytes) &&
                  DuelNetworkContentRecord.validDigest($0.sha256) }) else { throw Failure.invalidFiles }
        let computed = DuelNetworkContentRecord.fingerprint(decoded.files, recipe: Self.recipe, context: decoded.build)
        guard DuelNetworkContentRecord.validDigest(decoded.fingerprint), computed == decoded.fingerprint else {
            throw Failure.fingerprintMismatch
        }
        files = decoded.files; build = decoded.build; fingerprint = computed
    }

    private static func allowedPath(_ path: String) -> Bool {
        if helperPaths.contains(path) { return true }
        return !path.contains("..") && path.range(
            of: "^(Sources/ShiftCore|App|Shared)/([A-Za-z0-9_+.-]+/)*[A-Za-z0-9_+.-]+\\.swift\\z",
            options: .regularExpression) != nil
    }
}

/// Logical names, not installation paths. The content recipe includes exact file
/// bytes through SHA-256, including every catalog field and manifest reference.
struct DuelNetworkContentRecord: Codable, Equatable {
    let path: String
    let bytes: Int
    let sha256: String

    static func validDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// Each UTF-8 field is decimal-byte-length + ':' + field. The recipe plus
    /// newline is the domain separator; record count and sorted order are bound.
    static func fingerprint(_ files: [Self], recipe: String, context: [String: String] = [:]) -> String {
        var data = Data((recipe + "\n").utf8)
        func append(_ value: String) {
            data.append(contentsOf: "\(value.utf8.count):\(value)".utf8)
        }
        append(String(context.count))
        for key in context.keys.sorted() { append(key); append(context[key]!) }
        append(String(files.count))
        for file in files {
            append(file.path); append(String(file.bytes)); append(file.sha256)
        }
        return digest(data)
    }
}

/// Independently verified installed content identity. It owns no live resources.
/// Use prepare to retain the exact verified objects for a single network session;
/// neither API creates a session, confirms a barrier, or starts combat.
@MainActor
struct DuelNetworkCompatibilityIdentity {
    static let contentRecipe = "fighter-network-content-v1"
    enum Failure: Error, Equatable {
        case missingRules, missingCatalog, missingStage, invalidResource(String), controlsUnavailable
    }
    let compatibility: DuelNetworkStartBarrier.Compatibility
    let catalog: DuelWeaponCatalog
    let verifiedFiles: [DuelNetworkContentRecord]

    private init(rules: DuelNetworkRulesManifest, catalog: DuelWeaponCatalog,
                 records: [DuelNetworkContentRecord]) {
        self.catalog = catalog
        verifiedFiles = records.sorted { $0.path < $1.path }
        compatibility = .init(rulesFingerprint: rules.fingerprint,
                              catalogFingerprint: DuelNetworkContentRecord.fingerprint(
                                verifiedFiles, recipe: Self.contentRecipe))
    }

    /// Use only trusted installed app resources, never manifests received from a
    /// peer. No fallback to procedural/legacy assets, profile names or semver.
    static func verify(bundle: Bundle = .main) throws -> Self {
        let prepared = try prepare(bundle: bundle)
        defer { prepared.release() }
        return prepared.identity
    }

    /// Synchronous MainActor preflight. Run before a future room/start deadline;
    /// this is not an asynchronous/cancellable GLTF loader or GPU-ready receipt.
    static func prepare(bundle: Bundle = .main) throws -> DuelNetworkPreparedResources {
        guard let rulesURL = bundle.url(forResource: DuelNetworkRulesManifest.resourceName,
                                        withExtension: "json") else { throw Failure.missingRules }
        let rulesData = try read(rulesURL, maximum: DuelNetworkRulesManifest.maximumBytes)
        // Validate build metadata before touching potentially expensive private assets.
        let rules = try DuelNetworkRulesManifest(data: rulesData)
        guard let catalogURL = DuelWeaponAssets.catalogURL(bundle: bundle) else { throw Failure.missingCatalog }
        let stageURL = bundle.url(forResource: "SF3_Palace_Exterior", withExtension: "glb") ??
            bundle.url(forResource: "SF3_Palace_Exterior", withExtension: "glb", subdirectory: "FighterPrivate")
        guard let stageURL else { throw Failure.missingStage }
        return try prepare(rules: rules, directory: catalogURL.deletingLastPathComponent(), stageURL: stageURL, bundle: bundle)
    }

    /// Explicit-directory seam for native tests / already installed resources.
    /// Pins cannot be overridden. The directory is authoritative for the catalog,
    /// characters, controls and effects, matching the equipped offline renderer.
    static func verify(rules: DuelNetworkRulesManifest, directory: URL, stageURL: URL) throws -> Self {
        let prepared = try prepare(rules: rules, directory: directory, stageURL: stageURL)
        defer { prepared.release() }
        return prepared.identity
    }

    static func prepare(rules: DuelNetworkRulesManifest, directory: URL,
                        stageURL: URL, bundle: Bundle = .main) throws -> DuelNetworkPreparedResources {
        let directory = directory.resolvingSymlinksInPath().standardizedFileURL
        var records: [DuelNetworkContentRecord] = []
        var observed: [(URL, DuelNetworkContentRecord)] = []
        var totalBytes = 0
        func record(_ url: URL, path: String, maximum: Int, bytes: Int? = nil, hash: String? = nil) throws -> Data {
            let data = try read(url, maximum: maximum)
            let digest = DuelNetworkContentRecord.digest(data)
            guard bytes.map({ $0 == data.count }) ?? true, hash.map({ $0 == digest }) ?? true else {
                throw Failure.invalidResource(path)
            }
            if let existing = observed.first(where: { $0.1.path == path }) {
                guard existing.0.standardizedFileURL == url.standardizedFileURL,
                      existing.1.bytes == data.count, existing.1.sha256 == digest else { throw Failure.invalidResource(path) }
                return data
            }
            guard totalBytes <= 256_000_000 - data.count else { throw Failure.invalidResource(path) }
            totalBytes += data.count
            let entry = DuelNetworkContentRecord(path: path, bytes: data.count, sha256: digest)
            records.append(entry); observed.append((url, entry))
            return data
        }
        let assets = try DuelWeaponAssets(directory: directory, bundle: bundle)
        let assetPin = assets.release?.files.first(where: { $0.path.hasPrefix("asset-release/") })?.sha256 ?? ""
        guard rules.build["FIGHTER_ASSET_RELEASE_SHA256"] == assetPin else {
            throw Failure.invalidResource("asset-release-build-pin")
        }
        let catalogURL = directory.appendingPathComponent("SF3_DistinctFighters.json")
        _ = try record(catalogURL, path: "catalog/SF3_DistinctFighters.json", maximum: 32_000_000,
                       hash: assets.release?.definition.catalog.sha256 ?? DuelWeaponAssets.catalogSHA256)
        if let release = assets.release {
            for file in release.files where file.path.hasPrefix("asset-release/") {
                _ = try record(directory.appendingPathComponent(DuelFighterAssetRelease.fileName),
                    path: file.path, maximum: DuelFighterAssetRelease.maximumBytes, bytes: file.bytes, hash: file.sha256)
            }
            var bindings = [("weapon-effects/", assets.sourceTrails?.verifiedFiles ?? [])]
            if release.definition.panguAudio != nil { bindings.append(("pangu-audio/", assets.panguAudio?.verifiedFiles ?? [])) }
            if release.definition.triadAudio != nil { bindings.append(("triad-audio/", assets.triadAudio?.verifiedFiles ?? [])) }
            if release.definition.triadSummons != nil { bindings.append(("triad-souls/", assets.triadSummons?.verifiedFiles ?? [])) }
            if release.definition.triadEffects != nil { bindings.append(("triad-effects/", assets.triadEffects?.verifiedFiles ?? [])) }
            for (prefix, files) in bindings {
                guard !files.isEmpty else { throw Failure.invalidResource(prefix) }
                for file in files {
                    _ = try record(directory.appendingPathComponent(file.path), path: prefix + file.path,
                                   maximum: file.bytes, bytes: file.bytes, hash: file.sha256)
                }
            }
        } else {
            let sourceTrailURL = directory.appendingPathComponent(DuelSourceWeaponTrails.fileName)
            if FileManager.default.fileExists(atPath: sourceTrailURL.path) {
                _ = try record(sourceTrailURL, path: "weapon-effects/" + DuelSourceWeaponTrails.fileName,
                               maximum: 100_000, hash: DuelSourceWeaponTrails.sha256)
            }
        }
        var transferred = false
        var retainedControls: DuelSourceControlsView?
        var retainedSourceEffects: DuelSourceEffects?
        var retainedWeaponEffects: DuelWeaponEffects?
        let root = SCNNode()
        root.name = "duel.verified-effects"
        defer {
            if !transferred {
                retainedControls?.cancelAll(notify: false)
                retainedControls?.inputEnabled = false
                retainedSourceEffects?.shutdown(); retainedWeaponEffects?.shutdown()
                root.removeFromParentNode()
                assets.releaseCharacters()
            }
        }
        for profile in assets.catalog.profiles {
            let name = profile.resourceName + ".glb"
            _ = try record(directory.appendingPathComponent(name), path: "characters/" + name,
                           maximum: 128_000_000, bytes: profile.bytes, hash: profile.sha256)
            // Retain exactly the loader objects whose skin/nodes/clip timing
            // were verified. Later network presentation may only read this cache.
            _ = try assets.character(for: profile.hero)
        }

        // Do not copy the controls' private pin table. Its authoritative loader
        // verifies every required original PNG and rejects image-injection fallback.
        let controlNames: Set<String> = ["fist", "foot", "shadow", "shuriken_button", "stick_arrow", "stick_arrow_small", "stick_circle"]
        for name in controlNames.sorted() {
            let prefixed = directory.appendingPathComponent("SF3UI_\(name).png")
            let url = FileManager.default.fileExists(atPath: prefixed.path)
                ? prefixed : directory.appendingPathComponent("\(name).png")
            _ = try record(url, path: "controls/SF3UI_\(name).png", maximum: 131_072)
        }
        let controls = DuelSourceControlsView(assetDirectory: directory)
        retainedControls = controls
        controls.inputEnabled = false
        guard controls.sourceArtAvailable, controls.loadedSpriteNames == controlNames else { throw Failure.controlsUnavailable }

        struct EffectFiles: Decodable {
            struct File: Decodable { let name: String; let bytes: Int; let sha256: String }
            let files: [File]
        }
        for (name, hash, prefix, count) in [
            (DuelSourceEffects.manifestName, DuelSourceEffects.manifestSHA256, "SF3FX_", 38),
            (DuelWeaponEffects.manifestName, DuelWeaponEffects.manifestSHA256, "SF3WE_", 11)
        ] {
            let group = prefix == "SF3FX_" ? "source-effects/" : "weapon-effects/"
            let data = try record(directory.appendingPathComponent(name), path: group + name,
                                  maximum: 2_000_000, hash: hash)
            let files = try JSONDecoder().decode(EffectFiles.self, from: data).files
            guard files.count == count, Set(files.map(\.name)).count == count else { throw Failure.invalidResource(name) }
            for file in files {
                guard file.name.hasPrefix(prefix), !file.name.contains("/"), !file.name.contains("\\"),
                      !file.name.contains(".."), (1...4_000_000).contains(file.bytes),
                      DuelNetworkContentRecord.validDigest(file.sha256) else { throw Failure.invalidResource(name) }
                _ = try record(directory.appendingPathComponent(file.name), path: group + file.name,
                               maximum: 4_000_000, bytes: file.bytes, hash: file.sha256)
            }
        }
        // Existing loaders check image/audio decoding, sampled curves, material
        // references and complete effect schemas. No emit/play/step call is made.
        let sourceEffects = try DuelSourceEffects(root: root, directory: directory,
            panguAudio: assets.panguAudio, triadAudio: assets.triadAudio)
        retainedSourceEffects = sourceEffects
        let weaponEffects = try DuelWeaponEffects(root: root, directory: directory)
        retainedWeaponEffects = weaponEffects
        _ = try record(stageURL, path: "stage/SF3_Palace_Exterior.glb", maximum: 32_000_000,
                       hash: DuelStageAsset.digest)
        let stage = try DuelStageAsset(url: stageURL, kind: .palace)

        // Detect ordinary replacement during verification. Installed signed
        // bundle immutability is the trust boundary, not an adversarial file store.
        for (url, entry) in observed {
            let bytes = try read(url, maximum: entry.bytes)
            guard bytes.count == entry.bytes, DuelNetworkContentRecord.digest(bytes) == entry.sha256 else {
                throw Failure.invalidResource(entry.path)
            }
        }
        let legacyFileCount = 62 + (assets.sourceTrails == nil ? 0 : 1)
        guard (assets.release != nil || records.count == legacyFileCount), assets.catalog.profiles.count == 2 else {
            throw Failure.invalidResource("complete-content")
        }
        let identity = Self(rules: rules, catalog: assets.catalog, records: records)
        let prepared = DuelNetworkPreparedResources(identity: identity, assets: assets, stage: stage,
            controls: controls, sourceEffects: sourceEffects, weaponEffects: weaponEffects, effectsRoot: root)
        transferred = true
        return prepared
    }

    private static func read(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let count = values.fileSize, count > 0, count <= maximum else {
            throw Failure.invalidResource(url.lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        guard data.count == count else { throw Failure.invalidResource(url.lastPathComponent) }
        return data
    }
}

/// Only the verifier in this file can create a production owner. Its optional
/// payload is discarded at release even when a coordinator retains this token.
/// All access, including lifecycle reservations, is confined to MainActor.
@MainActor
final class DuelNetworkPreparedResources {
    enum Failure: Error, Equatable { case released, alreadyClaimed, invalidResources }
    private struct Payload {
        let assets: DuelWeaponAssets
        let characters: [DuelGame.Hero: DuelWeaponCharacterAsset]
        let stage: DuelStageAsset
        let controls: DuelSourceControlsView
        let sourceEffects: DuelSourceEffects
        let weaponEffects: DuelWeaponEffects
        let effectsRoot: SCNNode
    }
    let identity: DuelNetworkCompatibilityIdentity
    private var payload: Payload?
    private var sessionClaim: UUID?
    private var mountClaim: UUID?
    private var worldClaimed = false
    private var controlsClaimed = false
    private weak var mountedWorld: DuelWorldView?
    private weak var mountedControls: DuelNetworkControlsView?
    private var sessionInvalidated: (() -> Void)?
    private var mountInvalidated: (() -> Void)?

    fileprivate init(identity: DuelNetworkCompatibilityIdentity, assets: DuelWeaponAssets,
                     stage: DuelStageAsset, controls: DuelSourceControlsView,
                     sourceEffects: DuelSourceEffects, weaponEffects: DuelWeaponEffects,
                     effectsRoot: SCNNode) {
        self.identity = identity
        assets.bindVerifiedPreparation()
        var characters: [DuelGame.Hero: DuelWeaponCharacterAsset] = [:]
        for profile in identity.catalog.profiles {
            characters[profile.hero] = assets.loadedCharacter(for: profile.hero)
        }
        payload = Payload(assets: assets, characters: characters, stage: stage, controls: controls,
                          sourceEffects: sourceEffects, weaponEffects: weaponEffects, effectsRoot: effectsRoot)
    }
    var isReleased: Bool { payload == nil }
    var assets: DuelWeaponAssets? { payload?.assets }
    var stage: DuelStageAsset? { payload?.stage }
    var controls: DuelSourceControlsView? { payload?.controls }
    var sourceEffects: DuelSourceEffects? { payload?.sourceEffects }
    var weaponEffects: DuelWeaponEffects? { payload?.weaponEffects }
    var effectsRoot: SCNNode? { payload?.effectsRoot }
    func loadedCharacter(for hero: DuelGame.Hero) -> DuelWeaponCharacterAsset? {
        guard let payload, let character = payload.characters[hero],
              payload.assets.loadedCharacter(for: hero) === character else { return nil }
        return character
    }
    var hasExactResources: Bool {
        guard let payload, payload.assets.catalog == identity.catalog,
              payload.characters.count == 2, payload.stage.kind == .palace,
              payload.controls.sourceArtAvailable,
              !payload.sourceEffects.preparationObjects().isEmpty,
              !payload.weaponEffects.preparationObjects().isEmpty else { return false }
        return identity.catalog.profiles.allSatisfy { profile in
            guard let character = loadedCharacter(for: profile.hero) else { return false }
            return character.profile == profile
        }
    }
    /// Reserve before constructing any session that could release these assets.
    /// A rejected duplicate must never construct/shut down a second session.
    func reserveSession() throws -> UUID {
        guard payload != nil else { throw Failure.released }
        guard sessionClaim == nil else { throw Failure.alreadyClaimed }
        guard hasExactResources else { release(); throw Failure.invalidResources }
        let token = UUID(); sessionClaim = token
        return token
    }
    func bindSession(_ token: UUID, invalidated: @escaping () -> Void) -> Bool {
        guard isLiveSession(token), sessionInvalidated == nil else { return false }
        sessionInvalidated = invalidated
        return true
    }
    func isLiveSession(_ token: UUID) -> Bool { payload != nil && sessionClaim == token }
    func claimMount(session token: UUID, owner: UUID, invalidated: @escaping () -> Void) -> Bool {
        guard isLiveSession(token), hasExactResources, mountClaim == nil else { return false }
        mountClaim = owner; mountInvalidated = invalidated
        return true
    }
    func isLiveMount(session token: UUID, owner: UUID) -> Bool {
        isLiveSession(token) && mountClaim == owner && hasExactResources
    }
    func claimWorld(_ world: DuelWorldView, session token: UUID, owner: UUID) -> Bool {
        guard isLiveMount(session: token, owner: owner), !worldClaimed,
              payload?.effectsRoot.parent == nil else { return false }
        worldClaimed = true; mountedWorld = world
        return true
    }
    var canClaimControls: Bool {
        payload != nil && mountClaim != nil && !controlsClaimed && payload?.controls.superview == nil
    }
    func claimControls(_ view: DuelNetworkControlsView, session token: UUID, owner: UUID) -> Bool {
        guard isLiveMount(session: token, owner: owner), canClaimControls,
              view.controls === payload?.controls else { return false }
        controlsClaimed = true; mountedControls = view
        return true
    }
    func owns(world: DuelWorldView, controls: DuelNetworkControlsView,
              session token: UUID, owner: UUID) -> Bool {
        isLiveMount(session: token, owner: owner) && mountedWorld === world && mountedControls === controls &&
            controls.controls === payload?.controls
    }
    func release() {
        guard payload != nil else { return }
        // Invalidate every claim and detach the payload before any reentrant
        // UIKit, observer, session or preparation teardown callback can run.
        var old = payload
        payload = nil
        let world = mountedWorld, controlsView = mountedControls
        let invalidateMount = mountInvalidated, invalidateSession = sessionInvalidated
        mountedWorld = nil; mountedControls = nil
        mountInvalidated = nil; sessionInvalidated = nil
        old?.controls.onDirection = nil; old?.controls.onAction = nil; old?.controls.onGuard = nil
        old?.controls.onActionCancelled = nil; old?.controls.onInputCancelled = nil
        old?.controls.cancelAll(notify: false); old?.controls.inputEnabled = false
        controlsView?.shutdown()
        old?.sourceEffects.shutdown(); old?.weaponEffects.shutdown()
        old?.effectsRoot.removeFromParentNode()
        old?.assets.releaseCharacters()
        old?.controls.removeFromSuperview()
        // The world drops its own character/stage references before reporting
        // failure. Do not keep another payload copy alive across that callback.
        old = nil
        world?.shutdown()
        invalidateMount?(); invalidateSession?()
    }
}
