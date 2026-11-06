import Combine
import CryptoKit
import Metal
import UIKit

/// Cache the complete idle controls once per verified pack/language. Rendering
/// sequentially releases the large source atlas between controls; the lobby
/// retains small images; only a control with a changing idle timeline needs a
/// live canvas. The supplied shop clip animates even without a notification.
@MainActor
final class ArenaImportedSourceControls: ObservableObject {
    typealias Role = ArenaLobbySourceControl.Role
    struct Control {
        let id = UUID()
        struct LiveSource {
            let sceneURL: URL
            let sceneSHA256: String
            let exportName: String
            let sourceRect: CGRect
            let state: ArenaLobbyInterfaceState
        }
        let image: UIImage
        let binding: ArenaLobbySourceControl.Binding
        var title: String { binding.title }
        /// Normalized within image, before SwiftUI's aspect-fit placement.
        let hitRegion: CGRect
        /// Fit the button to its native layout while allowing its original
        /// particles to extend outside that footprint without shrinking it.
        let layoutRegion: CGRect
        let liveSource: LiveSource?
    }
    static let shared = ArenaImportedSourceControls()
    @Published private(set) var controls: [Role: Control] = [:]
    private var generation = UUID()
    private var loadedRevision: UUID?

    func load(store: ArenaResourcePackStore = .shared, localization: ArenaImportedLocalization = .shared,
              values: ArenaLobbySourceControl.Values) async {
        let token = UUID()
        generation = token
        if loadedRevision != store.contentRevision || !store.enabled {
            controls = [:]
            loadedRevision = store.contentRevision
        }
        let bindings = Dictionary(uniqueKeysWithValues: Role.allCases.map {
            ($0, values.binding(for: $0, localizedTitle: localization.menuTitle($0.title)))
        })
        // A balance update redraws only changed counters. Keep the verified
        // static controls and shop canvas in place throughout the async load.
        let roles = Role.allCases.filter { controls[$0]?.binding != bindings[$0] }
        guard !roles.isEmpty else { return }
        guard store.enabled, let pack = store.manifest,
              let scenePath = pack.interfaceSceneFile, let bindingsPath = pack.interfaceBindingsFile,
              let sceneFile = pack.files.first(where: { $0.path == scenePath && $0.kind == .data }),
              let bindingsFile = pack.files.first(where: { $0.path == bindingsPath && $0.kind == .data }),
              sceneFile.bytes <= 64 * 1024 * 1024, bindingsFile.bytes <= 32 * 1024 * 1024,
              let sceneURL = store.url(for: scenePath), let bindingsURL = store.url(for: bindingsPath) else { return }
        let worker = Task.detached(priority: .utility) {
            func read(_ url: URL, count: Int, sha256: String) throws -> Data {
                try Task.checkCancellation()
                let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard info.isRegularFile == true, info.fileSize == count else { throw CocoaError(.fileReadCorruptFile) }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count == count, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return data
            }
            struct BindingIdentity: Decodable { let schemaVersion: Int; let sourceSCSHA256: String }
            let document = try JSONDecoder().decode(ArenaLobbyTimelineDocument.self,
                from: read(sceneURL, count: sceneFile.bytes, sha256: sceneFile.sha256))
            let bindings = try JSONDecoder().decode(BindingIdentity.self,
                from: read(bindingsURL, count: bindingsFile.bytes, sha256: bindingsFile.sha256))
            guard bindings.schemaVersion == 1, bindings.sourceSCSHA256 == document.sourceSCSHA256 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try Task.checkCancellation()
            return document
        }
        do {
            let document = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            guard generation == token, !Task.isCancelled, store.enabled else { return }
            var urls: [String: URL] = [:]
            for entry in document.textures {
                guard pack.files.contains(where: { $0.path == entry.file && $0.kind == .image && $0.sha256 == entry.sha256 }),
                      let url = store.url(for: entry.file) else { throw CocoaError(.fileReadCorruptFile) }
                urls[entry.file] = url
            }
            let approvedURLs = urls
            let atlasWorker = Task.detached(priority: .utility) {
                try ArenaLobbyTimelineRenderer.loadAtlases(document: document) { approvedURLs[$0] }
            }
            let atlases = try await withTaskCancellationHandler {
                try await atlasWorker.value
            } onCancel: { atlasWorker.cancel() }
            guard generation == token, !Task.isCancelled, store.enabled,
                  let device = MTLCreateSystemDefaultDevice() else { return }
            var result = controls
            for role in roles {
                try Task.checkCancellation()
                guard generation == token, store.enabled else { return }
                // A missing or incompatible control keeps its own native button;
                // it must not prevent other independently verified controls loading.
                result[role] = try? Self.render(document: document, atlases: atlases,
                    device: device, role: role, binding: bindings[role]!,
                    sceneURL: sceneURL, sceneSHA256: sceneFile.sha256)
                await Task.yield()
            }
            guard generation == token, !Task.isCancelled, store.enabled else { return }
            controls = result
        } catch {
            // No partially rendered source UI replaces a usable native button.
        }
    }

    private static func render(document: ArenaLobbyTimelineDocument, atlases: [ArenaLobbyTimelineRenderer.Atlas],
                               device: MTLDevice, role: Role, binding: ArenaLobbySourceControl.Binding,
                               sceneURL: URL, sceneSHA256: String) throws -> Control {
        let source = try ArenaLobbySourceControl(document: document, role: role, title: binding.title, season: binding.season)
        let renderer = try ArenaLobbyTimelineRenderer(device: device, scene: source.scene, atlases: atlases)
        let scale = min(3.0, max(1.0, Double(UIScreen.main.scale)))
        let width = Int(ceil(source.bounds.width * scale)), height = Int(ceil(source.bounds.height * scale))
        let pixels = try renderer.snapshot(time: 0, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    .union(.byteOrder32Big), provider: provider, decode: nil, shouldInterpolate: true,
                  intent: .defaultIntent) else { throw CocoaError(.fileReadCorruptFile) }
        let r = source.hitRegion, b = source.bounds, layout = source.layoutBounds
        return Control(image: UIImage(cgImage: cg, scale: scale, orientation: .up),
                       binding: binding,
                       hitRegion: CGRect(x: (r.minX-b.minX)/b.width, y: (r.minY-b.minY)/b.height,
                                         width: r.width/b.width, height: r.height/b.height),
                       layoutRegion: CGRect(x: (layout.minX-b.minX)/b.width, y: (layout.minY-b.minY)/b.height,
                                            width: layout.width/b.width, height: layout.height/b.height),
                       liveSource: role == .shop || role == .season ? .init(sceneURL: sceneURL, sceneSHA256: sceneSHA256,
                           exportName: role.export, sourceRect: CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height),
                           state: source.scene.interfaceState!) : nil)
    }
}
