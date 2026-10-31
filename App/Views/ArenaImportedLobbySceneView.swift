import CryptoKit
import MetalKit
import SwiftUI
import UIKit

/// An optional transparent layer above the approved static preview. It becomes
/// visible only after a successful Metal frame; load/render failures leave the
/// underlying preview visible and are reported through onFailure.
@MainActor
struct ArenaImportedLobbySceneView: UIViewRepresentable {
    let sceneURL: URL
    let exportName: String
    let sourceRect: CGRect?
    let sceneSHA256: String?
    let live: Bool
    let resourceURL: (String) -> URL?
    let onFailure: ((String) -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(sceneURL: URL, exportName: String, sourceRect: CGRect? = nil,
         sceneSHA256: String? = nil, live: Bool = true,
         resourceURL: @escaping (String) -> URL?, onFailure: ((String) -> Void)? = nil) {
        self.sceneURL = sceneURL
        self.exportName = exportName
        self.sourceRect = sourceRect
        self.sceneSHA256 = sceneSHA256
        self.live = live
        self.resourceURL = resourceURL
        self.onFailure = onFailure
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ArenaLobbyMetalView {
        let view = ArenaLobbyMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0,0,0,0)
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.alpha = 0
        view.stateChanged = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.applyPlayback(to: view)
        }
        return view
    }

    func updateUIView(_ view: ArenaLobbyMetalView, context: Context) {
        let rect = sourceRect.map { [Double($0.minX), Double($0.minY), Double($0.maxX), Double($0.maxY)] }
        context.coordinator.update(view, request: Coordinator.Request(url: sceneURL,
            sha256: sceneSHA256, export: exportName, rect: rect),
            live: live, active: scenePhase == .active, reduceMotion: reduceMotion,
            resourceURL: resourceURL, onFailure: onFailure)
    }

    static func dismantleUIView(_ view: ArenaLobbyMetalView, coordinator: Coordinator) {
        coordinator.cancel(view)
        view.stateChanged = nil
    }

    @MainActor
    final class Coordinator {
        struct Request: Equatable, Sendable {
            let url: URL
            let sha256: String?
            let export: String
            let rect: [Double]?
        }
        private var request: Request?
        private var generation = UUID()
        private var loading: Task<Void, Never>?
        private var renderer: ArenaLobbyTimelineRenderer?
        private var live = true
        private var active = true
        private var reduceMotion = false
        private var ready = false
        private var initialFrameSubmitted = false
        private var submittingInitialFrame = false
        private var onFailure: ((String) -> Void)?

        func update(_ view: ArenaLobbyMetalView, request next: Request,
                    live: Bool, active: Bool, reduceMotion: Bool,
                    resourceURL: @escaping (String) -> URL?, onFailure: ((String) -> Void)?) {
            self.live = live; self.active = active; self.reduceMotion = reduceMotion
            self.onFailure = onFailure
            guard request != next else { applyPlayback(to: view); return }
            cancel(view)
            request = next
            generation = UUID()
            let token = generation
            loading = Task { [weak self, weak view] in
                do {
                    let documentTask = Task.detached(priority: .utility) {
                        try Self.readDocument(next)
                    }
                    let document = try await withTaskCancellationHandler {
                        try await documentTask.value
                    } onCancel: { documentTask.cancel() }
                    try Task.checkCancellation()
                    guard let self, let view, self.generation == token else { return }

                    // The resource resolver may be backed by a MainActor store.
                    // Only this actor calls it; the worker receives URL values.
                    var urls: [String: URL] = [:]
                    for texture in document.textures {
                        guard let url = resourceURL(texture.file) else {
                            throw ArenaLobbyTimelineError.invalid("Lobby texture is not registered by the active pack")
                        }
                        urls[texture.file] = url
                    }
                    let approvedURLs = urls
                    let atlasTask = Task.detached(priority: .utility) {
                        try Task.checkCancellation()
                        return try ArenaLobbyTimelineRenderer.loadAtlases(document: document) { approvedURLs[$0] }
                    }
                    let atlases = try await withTaskCancellationHandler {
                        try await atlasTask.value
                    } onCancel: { atlasTask.cancel() }
                    try Task.checkCancellation()
                    guard self.generation == token, self.request == next else { return }
                    guard let device = view.device else { throw ArenaLobbyTimelineError.invalid("Metal is unavailable on this device") }
                    let scene = try ArenaLobbyTimelineScene(document: document, exportName: next.export, sourceRect: next.rect)
                    let renderer = try ArenaLobbyTimelineRenderer(device: device, scene: scene, atlases: atlases)
                    renderer.onFirstFrame = { [weak self, weak view] in
                        guard let self, let view, self.generation == token else { return }
                        self.ready = true
                        view.alpha = 1
                        self.applyPlayback(to: view)
                    }
                    renderer.onFailure = { [weak self, weak view] reason in
                        guard let self, let view, self.generation == token else { return }
                        view.alpha = 0
                        view.isPaused = true
                        self.onFailure?(reason)
                    }
                    self.renderer = renderer
                    view.delegate = renderer
                    self.applyPlayback(to: view)
                } catch is CancellationError {
                    // A replacement theme/pack owns the next visible frame.
                } catch {
                    guard let self, let view, self.generation == token else { return }
                    view.alpha = 0
                    view.isPaused = true
                    self.onFailure?(error.localizedDescription)
                }
            }
        }

        func applyPlayback(to view: ArenaLobbyMetalView) {
            guard let renderer else { return }
            let visible = active && view.window != nil && view.drawableSize.width > 0 && view.drawableSize.height > 0
            guard visible else { view.isPaused = true; renderer.suspend(); return }
            if !ready {
                guard !initialFrameSubmitted, !submittingInitialFrame else { return }
                submittingInitialFrame = true
                renderer.resume()
                view.isPaused = true
                view.draw()
                initialFrameSubmitted = renderer.lastStatistics != nil
                renderer.suspend()
                submittingInitialFrame = false
            } else if live && !reduceMotion {
                renderer.resume()
                view.isPaused = false
            } else {
                renderer.suspend()
                view.isPaused = true
            }
        }

        func cancel(_ view: ArenaLobbyMetalView) {
            generation = UUID()
            loading?.cancel(); loading = nil
            renderer?.suspend()
            view.isPaused = true
            view.delegate = nil
            view.alpha = 0
            renderer = nil
            ready = false
            initialFrameSubmitted = false
            submittingInitialFrame = false
        }

        nonisolated private static func readDocument(_ request: Request) throws -> ArenaLobbyTimelineDocument {
            try Task.checkCancellation()
            guard request.url.isFileURL else { throw ArenaLobbyTimelineError.invalid("Lobby scene must be a local approved resource") }
            let info = try request.url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true, let count = info.fileSize, count > 0, count <= 64*1024*1024 else {
                throw ArenaLobbyTimelineError.invalid("Lobby scene exceeds its reading limit")
            }
            let data = try Data(contentsOf: request.url, options: .mappedIfSafe)
            if let expected = request.sha256 {
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard expected == hash else { throw ArenaLobbyTimelineError.invalid("Lobby scene hash differs from the active pack") }
            }
            try Task.checkCancellation()
            let document = try JSONDecoder().decode(ArenaLobbyTimelineDocument.self, from: data)
            try Task.checkCancellation()
            return document
        }
    }
}

@MainActor
final class ArenaLobbyMetalView: MTKView {
    var stateChanged: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); stateChanged?() }
    override func layoutSubviews() { super.layoutSubviews(); stateChanged?() }
}
