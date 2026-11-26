import Combine
import SwiftUI
import UIKit

// MARK: - Container-Level Floating Tab Bar Visibility Manager (Fixes Bottom Tab Bar Occlusion Everywhere)

/// Coordinates bottom `FloatingTabBar` visibility across all tabs and pushed NavigationStack destinations:
/// - Level-1 tab roots display the bottom tab bar with automatic dynamic safe-area insets.
/// - Pushing into ANY Level-2 / Level-3 detail or edit form automatically hides the bottom tab bar
///   and restores it cleanly upon popping back to the tab root.
/// - Opening the software keyboard automatically hides the bottom tab bar so form fields and "保存"
///   buttons are never occluded on iPhone or iPad.
@MainActor
final class AppTabBarVisibility: ObservableObject {
    static let shared = AppTabBarVisibility()

    @Published private(set) var activeTabKey: String = "today"
    @Published private(set) var pushedTabs: Set<String> = []
    @Published private(set) var explicitHideCount: Int = 0
    @Published private(set) var isKeyboardVisible: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isKeyboardVisible = true
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isKeyboardVisible = false
            }
            .store(in: &cancellables)
    }

    var shouldHideTabBar: Bool {
        isKeyboardVisible || explicitHideCount > 0 || pushedTabs.contains(activeTabKey)
    }

    func setActiveTab(_ tabKey: String) {
        if activeTabKey != tabKey {
            activeTabKey = tabKey
        }
    }

    func setTabPushed(_ pushed: Bool, for tabKey: String) {
        if pushed {
            if !pushedTabs.contains(tabKey) {
                pushedTabs.insert(tabKey)
            }
        } else {
            if pushedTabs.contains(tabKey) {
                pushedTabs.remove(tabKey)
            }
        }
    }

    func pushExplicitHide() {
        explicitHideCount += 1
    }

    func popExplicitHide() {
        explicitHideCount = max(0, explicitHideCount - 1)
    }
}

/// Non-invasive UIKit lifecycle spy placed inside each Level-1 tab's root view (inside its `NavigationStack`).
/// Automatically detects when a `NavigationLink` pushes a detail/edit view (`navigationController.viewControllers.count > 1`)
/// and restores visibility when popping back to root (`count <= 1`).
private struct TabRootNavigationDepthSpy: UIViewControllerRepresentable {
    let tabKey: String

    func makeUIViewController(context: Context) -> SpyViewController {
        SpyViewController(tabKey: tabKey)
    }

    func updateUIViewController(_ uiViewController: SpyViewController, context: Context) {
        uiViewController.tabKey = tabKey
        uiViewController.syncDepth()
    }

    @MainActor
    final class SpyViewController: UIViewController {
        var tabKey: String

        init(tabKey: String) {
            self.tabKey = tabKey
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            syncDepth()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            syncDepth()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            syncDepth()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            syncDepth()
        }

        func syncDepth() {
            let count = navigationController?.viewControllers.count ?? 1
            AppTabBarVisibility.shared.setTabPushed(count > 1, for: tabKey)
        }
    }
}

private struct ExplicitHideTabBarModifier: ViewModifier {
    @State private var active = false

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                guard !active else { return }
                active = true
                AppTabBarVisibility.shared.pushExplicitHide()
            }
            .onDisappear {
                guard active else { return }
                active = false
                AppTabBarVisibility.shared.popExplicitHide()
            }
    }
}

extension View {
    /// Attached to the root view inside each primary tab's `NavigationStack` so pushing any detail/edit
    /// destination automatically hides the global bottom `FloatingTabBar` and popping restores it.
    func observeTabRootNavigationDepth(tabID: String) -> some View {
        background(
            TabRootNavigationDepthSpy(tabKey: tabID)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }

    /// Explicitly hides the bottom `FloatingTabBar` for the lifetime of a detail, form, or full-focus screen.
    func hidesFloatingTabBar() -> some View {
        modifier(ExplicitHideTabBarModifier())
    }
}

// MARK: - Unified WUMIND / Duty App Design Components (Shared Across Settings, Billing, Workbench, PassPlan & Secondary Screens)

/// Unified section card container with consistent corner radius, padding, hairline border, and adaptive surface.
struct AppSectionCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let tint: Color?
    @ViewBuilder let content: () -> Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.08 : 0.24), lineWidth: 0.9)
        )
    }
}

/// Unified primary call-to-action button with built-in busy state and consistent corner radius.
struct AppPrimaryCTA: View {
    let title: String
    var icon: String? = nil
    var tint: Color = DS.Palette.accent
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            guard !isLoading && !isDisabled else { return }
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                (isDisabled || isLoading ? tint.opacity(0.42) : tint),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }
}

/// Unified top-right navigation bar `"保存"` button for all add/edit forms with double-tap guard.
struct AppSaveToolbarButton: View {
    let title: String
    var isSaving: Bool = false
    var isDisabled: Bool = false
    var accessibilityID: String = "form.toolbar.save"
    let action: () -> Void

    init(
        title: String = "保存",
        isSaving: Bool = false,
        isDisabled: Bool = false,
        accessibilityID: String = "form.toolbar.save",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSaving = isSaving
        self.isDisabled = isDisabled
        self.accessibilityID = accessibilityID
        self.action = action
    }

    var body: some View {
        Button {
            guard !isSaving && !isDisabled else { return }
            Haptics.tap()
            action()
        } label: {
            if isSaving {
                ProgressView().controlSize(.small)
            } else {
                Text(title)
                    .font(.body.weight(.semibold))
            }
        }
        .disabled(isSaving || isDisabled)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Unified empty state block.
struct AppEmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

/// Unified inline validation/error banner card.
struct AppErrorBannerCard: View {
    let message: String
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.top, 1)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.30), lineWidth: 0.9)
        )
    }
}
