import SwiftUI
import WebKit

/// 「网站」标签页：直接显示值班网站的手机版，用保存的账号自动登录。网页上有的内容在这里都能看到。
struct SiteView: View {
    let isSelected: Bool
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = WebModel()
    @State private var lastOpenedAddress: String?
    @State private var showingWebLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if store.settings.sourceURL.isEmpty {
                    AppEmptyStateCard(
                        icon: "globe", title: "还没有设置值班网站",
                        message: "登录后打开排班页，再点「设为同步地址」。",
                        actionTitle: "打开网页登录", action: { showingWebLogin = true }
                    )
                    .padding(DS.Space.m)
                    .frame(maxWidth: DS.readableWidth)
                } else if model.navigationFailed {
                    AppErrorBannerCard(message: "值班网站加载失败。请检查网络连接后重试。", retryTitle: "重新加载") {
                        model.load(store.settings.sourceURL)
                    }
                    .padding(DS.Space.m)
                    .frame(maxWidth: DS.readableWidth)
                } else {
                    WebView(webView: model.webView)
                }
            }
            .overlay(alignment: .top) {
                if model.isLoading { ProgressView("正在加载值班网站").padding(DS.Space.s) }
            }
            .appBackground()
            .navigationTitle("值班网站")
            .observeTabRootNavigationDepth(tabID: "site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { model.webView.goBack() } label: { Image(systemName: "chevron.left").accessibilityLabel("后退") }
                        .disabled(!model.canGoBack)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { model.load(store.settings.sourceURL) } label: { Image(systemName: "house").accessibilityLabel("回到排班页") }
                        .disabled(store.settings.sourceURL.isEmpty)
                    Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise").accessibilityLabel("刷新") }
                        .disabled(!model.hasLoadedPage)
                }
            }
            .onAppear {
                // 每次进来都取最新的账号密码（可能刚在设置里改过）
                model.credentials = (store.settings.sourceUsername, Keychain.get(.sourcePassword) ?? "")
                openConfiguredSiteIfNeeded()
            }
            .onChange(of: isSelected) { _ in openConfiguredSiteIfNeeded() }
            .onChange(of: store.settings.sourceURL) { _ in openConfiguredSiteIfNeeded() }
            .fullScreenCover(isPresented: $showingWebLogin) { WebLoginView() }
            .onChange(of: store.settings.sourceUsername) { user in
                model.credentials = (user, Keychain.get(.sourcePassword) ?? "")
            }
            // 这一页切走后也一直留着（onAppear 不会再来）：设置里改了密码马上换上
            .onReceive(NotificationCenter.default.publisher(for: .keychainChanged)) { _ in
                model.credentials = (store.settings.sourceUsername, Keychain.get(.sourcePassword) ?? "")
            }
        }
    }

    private func openConfiguredSiteIfNeeded() {
        let address = store.settings.sourceURL
        guard isSelected, address != lastOpenedAddress else { return }
        lastOpenedAddress = address
        if !address.isEmpty { model.load(address) }
    }
}
