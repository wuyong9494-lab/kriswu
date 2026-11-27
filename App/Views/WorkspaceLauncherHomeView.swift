import SwiftUI

struct WorkspaceLauncherHomeView: View {
    let onSelectDuty: () -> Void
    let onSelectWuMind: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    entry("值班", asset: "WorkspaceOnDutyIcon", id: "workspace.home.onDuty", action: onSelectDuty)
                    entry("WuMind", asset: "WorkspaceWuMindIcon", id: "workspace.home.wumind", action: onSelectWuMind)
                }
                .frame(maxWidth: 540)
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(AppBackground())
        .accessibilityIdentifier("workspace.home.root")
    }

    private func entry(_ title: String, asset: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                HStack(alignment: .top) {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(DS.Font.headline)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(DS.Font.display)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: DS.Space.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}
