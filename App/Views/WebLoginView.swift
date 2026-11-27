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
    @FocusState private var editingAddress: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("值班系统网址", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($editingAddress)
                        .submitLabel(.go)
                        .onSubmit { openAddress() }
                    Button("前往") { openAddress() }
                        .frame(minHeight: 44)
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, DS.Space.m)
                if model.navigationFailed {
                    AppErrorBannerCard(message: "网页未能打开。请核对网址和网络连接。", retryTitle: "重试", onRetry: openAddress)
                        .padding(DS.Space.m)
                        .frame(maxWidth: DS.readableWidth)
                    Spacer()
                } else {
                    WebView(webView: model.webView)
                        .accessibilityHidden(!model.hasLoadedPage)
                        .overlay(alignment: .top) {
                            if model.isLoading { ProgressView("正在打开网页").padding(DS.Space.s) }
                        }
                        .overlay {
                            if !model.isLoading && !model.hasLoadedPage {
                                ZStack {
                                    Color(uiColor: .systemBackground)
                                    AppEmptyStateCard(icon: "globe", title: "输入值班网站的网址", message: "")
                                        .padding(DS.Space.m)
                                        .frame(maxWidth: DS.readableWidth)
                                }
                            }
                        }
                }
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
            .appBackground()
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
                    Button { model.webView.goBack() } label: { Image(systemName: "chevron.left").accessibilityLabel("后退") }
                        .disabled(!model.canGoBack)
                    Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise").accessibilityLabel("刷新") }
                        .disabled(!model.hasLoadedPage)
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
                    .disabled(!model.hasLoadedPage)
                    Button("抓取本页") {
                        Task {
                            await model.shareCookies()
                            if let html = await model.html() {
                                captured = CapturedPage(text: HTMLText.toText(html))
                            } else {
                                toast = "无法读取本页，请刷新后重试。"
                            }
                        }
                    }
                    .bold()
                    .disabled(!model.hasLoadedPage)
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
                if let url, !editingAddress { address = url }
            }
        }
    }

    private func openAddress() {
        editingAddress = false
        toast = nil
        model.load(address)
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
    @Published private(set) var navigationFailed = false
    @Published private(set) var hasLoadedPage = false
    @Published var currentURL: String?
    /// 单页网站（#/mine → #/duty）换页不会触发加载回调，用 KVO 跟踪能不能后退、当前地址
    @Published var canGoBack = false
    private var observers: [NSKeyValueObservation] = []
    /// 设置里的账号密码；打开登录页时自动填好并点「登录」
    var credentials: (user: String, password: String)? {
        didSet {
            // 换了账号密码：允许再自动登录一次
            if credentials?.user != oldValue?.user || credentials?.password != oldValue?.password { autoLoginTried = false }
        }
    }
    private var autoLoginTried = false
    private var hasRequestedPage = false

    /// userAgent：传入电脑浏览器标识时，网站显示电脑版页面
    init(userAgent: String? = nil) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        if userAgent != nil { WebPageLoader.applyDesktopMode(to: config) }
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = userAgent
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observers = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.canGoBack = value }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, change in
                guard let url = change.newValue ?? nil,
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host?.isEmpty == false else { return }
                Task { @MainActor in self?.currentURL = url.absoluteString }
            },
        ]
    }

    func load(_ address: String) {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.lowercased().hasPrefix("http") {
            // 直接写 IP 的网站（如 192.168.1.10）一般只有 http
            let isIP = s.prefix(while: { $0 != "/" && $0 != ":" }).allSatisfy { $0.isNumber || $0 == "." }
            s = (isIP ? "http://" : "https://") + s
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host?.isEmpty == false else {
            hasLoadedPage = false
            isLoading = false
            navigationFailed = true
            return
        }
        hasRequestedPage = true
        hasLoadedPage = false
        navigationFailed = false
        isLoading = true
        webView.load(URLRequest(url: url))
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
        hasLoadedPage = false
        navigationFailed = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        // WebKit can finish about:blank after rejecting a navigation without a network response.
        guard let url = webView.url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else {
            hasLoadedPage = false
            navigationFailed = hasRequestedPage
            return
        }
        hasLoadedPage = true
        navigationFailed = false
        // 只在登录页、而且只自动填一次：密码错了不会每次刷新都再提交，免得账号被锁
        if let c = credentials, !c.user.isEmpty, !c.password.isEmpty {
            Task {
                // 等前端把登录表单画出来
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String else { return }
                // 登进去了：以后登录过期还能再自动登录一次
                guard HTMLText.looksLikeLoginPage(html) else { autoLoginTried = false; return }
                guard !autoLoginTried else { return }
                autoLoginTried = true
                _ = try? await webView.callAsyncJavaScript(
                    WebPageLoader.autoLoginScript, arguments: ["u": c.user, "p": c.password], in: nil, contentWorld: .page)
            }
        }
        currentURL = url.absoluteString
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        navigationFailed = true
        hasLoadedPage = false
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        navigationFailed = true
        hasLoadedPage = false
        isLoading = false
    }
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
