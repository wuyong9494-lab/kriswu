import SwiftUI
import UIKit

/// The selected local theme's static source frame. The lobby keeps its own live
/// controls and hero view above this non-interactive layer.
@MainActor
struct ArenaImportedLobbyBackground: View {
    @ObservedObject private var store: ArenaResourcePackStore
    @State private var image: UIImage?
    @State private var loadedRequest: ImageRequest?

    init(store: ArenaResourcePackStore = .shared) {
        self.store = store
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
}
