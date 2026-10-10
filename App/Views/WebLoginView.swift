import SwiftUI
import WebKit

/// 在 App 内打开值班系统网页：登录、找到排班页面，然后「抓取本页」导入，
/// 或者「设为同步地址」让 App 以后自动用这个登录状态下载。
struct WebLoginView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WebModel()
    @State private var address = ""
    @State private var captured: CapturedPage?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("值班系统网址", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { model.load(address) }
                    Button("前往") { model.load(address) }
                }
                .padding(8)
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                WebView(webView: model.webView)
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
            .navigationTitle("网页登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        Task {
                            await model.shareCookies()
                            dismiss()
                        }
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { model.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    Spacer()
                    Button("设为同步地址") {
                        Task {
                            await model.shareCookies()
                            if let url = model.webView.url?.absoluteString {
                                store.settings.sourceURL = url
                                store.settings.syncViaWeb = true
                                toast = "已设为自动同步地址，正在同步…"
                                let ok = await store.sync(userInitiated: true)
                                toast = store.settings.lastSyncMessage ?? (ok ? "同步成功" : "同步失败")
                            }
                        }
                    }
                    Button("抓取本页") {
                        Task {
                            await model.shareCookies()
                            if let html = await model.html() {
                                captured = CapturedPage(text: HTMLText.toText(html))
                            }
                        }
                    }
                    .bold()
                }
            }
            .sheet(item: $captured) { page in
                NavigationStack {
                    ImportView(initialText: page.text) { toast = "已导入" }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("取消") { captured = nil }
                            }
                        }
                }
            }
            .onAppear {
                model.credentials = (store.settings.sourceUsername, Keychain.get(.sourcePassword) ?? "")
                address = store.settings.sourceURL
                if !address.isEmpty { model.load(address) }
            }
            .onReceive(model.$currentURL) { url in
                if let url { address = url }
            }
        }
    }
}

private struct CapturedPage: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class WebModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var isLoading = false
    @Published var currentURL: String?
    /// 设置里的账号密码；打开登录页时自动填好并点「登录」
    var credentials: (user: String, password: String)?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ address: String) {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.lowercased().hasPrefix("http") {
            // 直接写 IP 的网站（如 192.168.1.10）一般只有 http
            let isIP = s.prefix(while: { $0 != "/" && $0 != ":" }).allSatisfy { $0.isNumber || $0 == "." }
            s = (isIP ? "http://" : "https://") + s
        }
        if let url = URL(string: s) { webView.load(URLRequest(url: url)) }
    }

    func html() async -> String? {
        try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
    }

    /// 把网页里的登录 Cookie 复制给 App 的网络请求，这样同步时也是已登录状态。
    func shareCookies() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        if let c = credentials, !c.user.isEmpty, !c.password.isEmpty {
            Task {
                // 等前端把登录表单画出来
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                _ = try? await webView.callAsyncJavaScript(
                    WebPageLoader.autoLoginScript, arguments: ["u": c.user, "p": c.password], in: nil, contentWorld: .page)
            }
        }
        currentURL = webView.url?.absoluteString
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
