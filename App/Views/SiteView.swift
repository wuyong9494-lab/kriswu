import SwiftUI
import WebKit

/// 「网站」标签页：直接显示值班网站的手机版，用保存的账号自动登录。网页上有的内容在这里都能看到。
struct SiteView: View {
    @EnvironmentObject private var store: AppStore
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
                    WebView(webView: model.webView)
                }
            }
            .overlay(alignment: .top) {
                if model.isLoading { ProgressView().padding(6) }
            }
            .navigationTitle("值班网站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { model.webView.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!model.webView.canGoBack)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { model.load(store.settings.sourceURL) } label: { Image(systemName: "house") }
                    Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .onAppear {
                guard !loaded, !store.settings.sourceURL.isEmpty else { return }
                model.credentials = (store.settings.sourceUsername, Keychain.get(.sourcePassword) ?? "")
                model.load(store.settings.sourceURL)
                loaded = true
            }
        }
    }
}
