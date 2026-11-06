import SwiftUI

/// Keep the verified still visible until Metal presents its first complete
/// frame. Hide the still then, so translucent source edges aren't drawn twice.
@MainActor
struct ArenaSourceControlVisual: View {
    let control: ArenaImportedSourceControls.Control
    let live: Bool
    @State private var animatedFrameReady = false
    @State private var playAnimation: Bool
    @ObservedObject private var store = ArenaResourcePackStore.shared

    init(control: ArenaImportedSourceControls.Control, live: Bool) {
        self.control = control; self.live = live
        let once = control.liveSource?.state.oneShotRestFrames.isEmpty == false
        _playAnimation = State(initialValue: !once || !control.playback.started)
    }

    var body: some View {
        GeometryReader { geo in
            let size = control.image.size
            let layout = control.layoutRegion
            let scale = min(geo.size.width / (size.width * layout.width),
                            geo.size.height / (size.height * layout.height))
            ZStack {
                Image(uiImage: control.image).resizable()
                    .opacity(animatedFrameReady ? 0 : 1)
                if let source = control.liveSource, playAnimation {
                    ArenaImportedLobbySceneView(sceneURL: source.sceneURL, exportName: source.exportName,
                        sourceRect: source.sourceRect, sceneSHA256: source.sceneSHA256, live: live,
                        interfaceState: source.state, resourceURL: store.url(for:),
                        onFirstFrame: { control.playback.started = true; animatedFrameReady = true },
                        onPlaybackFinished: { playAnimation = false; animatedFrameReady = false },
                        onFailure: { _ in
                            // Rendering can report a failure during a view update.
                            Task { @MainActor in animatedFrameReady = false }
                        })
                }
            }.frame(width: size.width * scale, height: size.height * scale)
                .position(x: geo.size.width/2 + (0.5-layout.midX)*size.width*scale,
                          y: geo.size.height/2 + (0.5-layout.midY)*size.height*scale)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
