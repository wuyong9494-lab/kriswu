import SwiftUI

struct WorkspaceLauncherHomeView: View {
    let onSelectDuty: () -> Void
    let onSelectWuMind: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760 && !typeSize.isAccessibilitySize
            let layout = wide
                ? AnyLayout(HStackLayout(spacing: DS.Space.xl))
                : AnyLayout(VStackLayout(spacing: DS.Space.l))
            ScrollView {
                layout {
                    entry("值班", asset: "WorkspaceOnDutyIcon", id: "workspace.home.onDuty", wide: wide, action: onSelectDuty)
                    entry("WuMind", asset: "WorkspaceWuMindIcon", id: "workspace.home.wumind", wide: wide, action: onSelectWuMind)
                }
                .frame(maxWidth: wide ? 860 : 520)
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(AppBackground())
        .accessibilityIdentifier("workspace.home.root")
    }

    private func entry(_ title: String, asset: String, id: String, wide: Bool,
                       action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            let layout = wide || typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.xl))
                : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.m))
            layout {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: wide ? 76 : 58, height: wide ? 76 : 58)
                    .accessibilityHidden(true)
                HStack(spacing: DS.Space.s) {
                    Text(title)
                        .font(DS.Font.display)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
            .padding(.vertical, DS.Space.l)
            .padding(.horizontal, DS.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}
