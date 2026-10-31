import SwiftUI
import UIKit

/// The selected source timeline, with its verified still as a loading fallback.
/// Controls and the hero remain independent interactive layers.
@MainActor
struct ArenaImportedLobbyBackground: View {
    @ObservedObject private var store: ArenaResourcePackStore
    @State private var image: UIImage?
    @State private var loadedRequest: ImageRequest?
    private let live: Bool

    init(store: ArenaResourcePackStore = .shared, live: Bool = true) {
        self.store = store
        self.live = live
    }

    var body: some View {
        let request = imageRequest
        return GeometryReader { geometry in
            ZStack {
                // Clear while a pack is disabled, unavailable, or changing so
                // the existing lobby background below can remain the fallback.
                Color.clear
                if let image, loadedRequest == request {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                if let scene = sceneRequest {
                    ArenaImportedLobbySceneView(sceneURL: scene.url, exportName: scene.exportName,
                        sourceRect: scene.rect, sceneSHA256: scene.sha256, live: live, resourceURL: store.url(for:),
                        onFailure: { _ in store.reportLobbySceneFailure(themeID: scene.themeID) })
                        .id(scene)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: request) {
            image = nil
            loadedRequest = nil
            guard let request, !Task.isCancelled,
                  let decoded = UIImage(contentsOfFile: request.url.path) else { return }
            image = decoded
            loadedRequest = request
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The hash also invalidates the decoded image when a replacement pack
    /// keeps a theme's relative filename but changes its content.
    private var imageRequest: ImageRequest? {
        guard let theme = store.currentTheme,
              let url = store.url(for: theme.backgroundFile),
              let file = store.manifest?.files.first(where: { $0.path == theme.backgroundFile }) else { return nil }
        return ImageRequest(url: url, sha256: file.sha256)
    }

    private struct ImageRequest: Equatable {
        let url: URL
        let sha256: String
    }

    private var sceneRequest: SceneRequest? {
        guard let theme = store.currentTheme, let path = theme.sceneFile, let name = theme.sceneExport,
              let url = store.url(for: path),
              let file = store.manifest?.files.first(where: { $0.path == path && $0.kind == .data }) else { return nil }
        return SceneRequest(url: url, sha256: file.sha256, exportName: name, sourceRect: theme.sceneSourceRect,
                            themeID: theme.id, reload: store.lobbySceneReload)
    }

    private struct SceneRequest: Hashable {
        let url: URL
        let sha256: String
        let exportName: String
        let sourceRect: [Double]?
        let themeID: String
        let reload: Int
        var rect: CGRect? {
            guard let values = sourceRect, values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1])
        }
    }
}
