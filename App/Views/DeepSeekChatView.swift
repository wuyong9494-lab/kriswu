import SwiftUI

/// Compatibility wrapper directing all legacy DeepSeek chat entries to the unified WUMIND workspace.
struct DeepSeekChatView: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        WuMindWorkspaceView(onClose: onClose)
    }
}
