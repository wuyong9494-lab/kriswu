import SwiftUI
import WebKit

/// 「网站」标签页：直接显示值班网站的手机版，用保存的账号自动登录。网页上有的内容在这里都能看到。
struct SiteView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.floatingTabBarTop) private var tabBarTop
    @StateObject private var model = WebModel()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if store.settings.sourceURL.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "globe").font(.largeTitle).foregroundStyle(.secondary)
                        Text("还没有设置值班网站").font(.headline)
                        Text("到「设置 › 账号与同步」里登录值班网站，并点「设为同步地址」。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    // 网页停在悬浮标签栏上面：网页自己底部的按钮不被挡住
                    GeometryReader { g in
                        let overlap = tabBarTop.isFinite ? max(0, g.frame(in: .global).maxY - tabBarTop + 4) : 0
                        WebView(webView: model.webView)
                            .padding(.bottom, overlap)
                    }
                }
            }
            .overlay(alignment: .top) {
                if model.isLoading { ProgressView().padding(6) }
            }
            .appList()
            .navigationTitle("值班网站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { model.webView.goBack() } label: { Image(systemName: "chevron.left").accessibilityLabel("后退") }
                        .disabled(!model.canGoBack)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { model.load(store.settings.sourceURL) } label: { Image(systemName: "house").accessibilityLabel("回到排班页") }
                    Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise").accessibilityLabel("刷新") }
                }
            }
            .onAppear {
                // 每次进来都取最新的账号密码（可能刚在设置里改过）
                model.credentials = (store.settings.sourceUsername, Keychain.get(.sourcePassword) ?? "")
                guard !loaded, !store.settings.sourceURL.isEmpty else { return }
                model.load(store.settings.sourceURL)
                loaded = true
            }
            .onChange(of: store.settings.sourceUsername) { user in
                model.credentials = (user, Keychain.get(.sourcePassword) ?? "")
            }
            // 这一页切走后也一直留着（onAppear 不会再来）：设置里改了密码马上换上
            .onReceive(NotificationCenter.default.publisher(for: .keychainChanged)) { _ in
                model.credentials = (store.settings.sourceUsername, Keychain.get(.sourcePassword) ?? "")
            }
        }
    }
}
