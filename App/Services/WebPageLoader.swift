import WebKit

/// 用一个看不见的网页浏览器打开值班网站并取回渲染后的页面。
/// 和「网页登录」共用同一份 Cookie，所以只要在 App 里登录过，这里就是登录状态；
/// 用 JavaScript 动态加载的排班页面也能拿到内容。
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?
    private let username: String
    private let password: String

    private init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    static func html(url: URL, username: String, password: String) async throws -> String {
        let loader = WebPageLoader(username: username, password: password)
        return try await loader.load(url)
    }

    private func load(_ url: URL) async throws -> String {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        defer { self.webView = nil }

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        }

        var html = try await settledHTML(webView)

        // 打开的是登录页：用设置里的账号密码自动登录，再回到排班页面
        if HTMLText.looksLikeLoginPage(html), !username.isEmpty, !password.isEmpty {
            let submitted = (try? await webView.callAsyncJavaScript(
                Self.autoLoginScript, arguments: ["u": username, "p": password], in: nil, in: .page)) as? Bool ?? false
            if submitted {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                _ = try? await webView.callAsyncJavaScript(
                    "location.assign(target); return true;", arguments: ["target": url.absoluteString], in: nil, in: .page)
                try await Task.sleep(nanoseconds: 1_000_000_000)
                html = try await settledHTML(webView)
            }
        }
        return html
    }

    /// 等页面里的脚本把内容画出来：连续两次内容不变就认为加载完成，最多等 15 秒。
    private func settledHTML(_ webView: WKWebView) async throws -> String {
        var last = ""
        for _ in 0..<15 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let html = (try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String) ?? ""
            if !html.isEmpty && html == last { break }
            last = html
        }
        return last
    }

    /// 在登录页填入账号密码并点「登录」。用原生 setter + input 事件，Vue / React 做的页面也能收到输入。
    /// 有图形验证码的网站没法自动登录，会照常提示需要手动登录。
    static let autoLoginScript = """
    const visible = e => e.offsetParent !== null;
    const setValue = (el, v) => {
      const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set;
      setter.call(el, v);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };
    const pwds = [...document.querySelectorAll('input[type=password]')];
    const pwd = pwds.find(visible) || pwds[0];
    if (!pwd) return false;
    const skip = ['hidden', 'password', 'checkbox', 'radio', 'submit', 'button', 'file'];
    const inputs = [...document.querySelectorAll('input')].filter(e => visible(e) && !skip.includes((e.type || '').toLowerCase()));
    // 账号框 = 密码框前面最近的一个输入框
    let user = null;
    for (const e of inputs) if (e.compareDocumentPosition(pwd) & Node.DOCUMENT_POSITION_FOLLOWING) user = e;
    if (user || inputs[0]) setValue(user || inputs[0], u);
    setValue(pwd, p);
    await new Promise(r => setTimeout(r, 300));
    const isLogin = e => /^\\s*(登\\s*录|登\\s*入|立即登录|login|log\\s*in|sign\\s*in|确\\s*定)\\s*$/i.test(e.innerText || e.value || '');
    const buttons = [...document.querySelectorAll('button, input[type=submit], input[type=button], [role=button]')].filter(visible);
    let btn = buttons.find(isLogin) || buttons.find(e => e.matches('button[type=submit], input[type=submit]'));
    if (!btn) {
      const any = [...document.querySelectorAll('a, span, div')].filter(e => visible(e) && isLogin(e));
      btn = any[any.length - 1];  // 取最里层的元素，点击会冒泡到外层按钮
    }
    if (btn) btn.click();
    else if (pwd.form) (pwd.form.requestSubmit ? pwd.form.requestSubmit() : pwd.form.submit());
    else pwd.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', keyCode: 13, bubbles: true }));
    return true;
    """

    private func finish(_ error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    // 网站用浏览器弹窗式的账号密码（HTTP 认证）时，自动填入设置里的用户名密码
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        if (method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest),
           !username.isEmpty, challenge.previousFailureCount == 0 {
            completionHandler(.useCredential, URLCredential(user: username, password: password, persistence: .forSession))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
