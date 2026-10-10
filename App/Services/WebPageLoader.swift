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

    struct Page {
        var html: String
        /// 网页加载时向服务器取数据的请求（只在内存里，不保存）
        var captured: [CapturedRequest]
        /// replay 里要求重新发出的请求的返回内容
        var replies: [String]
        /// 额外打开的页面（如「值班查看」）的内容
        var extraHTML: [String]
        /// 打开额外页面后，afterTabs 要求重新发出的请求的返回内容（如其它几周的全员排班）
        var extraReplies: [String]
        /// 最后停在的网址
        var url: String? = nil
    }

    /// 打开网页（必要时自动登录），记录网页取数据的请求；
    /// replay 根据记录挑出要再发一次的请求（比如把日期改成下一周），在同一个页面里用同样的登录状态发出。
    /// pager：打开额外页面后依次点这些翻页按钮（如「上一天」最多 7 次、「下一天」最多 21 次），
    /// 每翻一页记下内容；页面不再变化就换下一个按钮。
    static func load(url: URL, username: String, password: String, extraTabs: [String] = [],
                     pager: [(label: String, steps: Int)] = [],
                     afterTabs: ([CapturedRequest]) -> [CapturedRequest] = { _ in [] },
                     desktop: Bool = false,
                     replay: ([CapturedRequest]) -> [CapturedRequest]) async throws -> Page {
        let loader = WebPageLoader(username: username, password: password)
        return try await loader.load(url, extraTabs: extraTabs, pager: pager, afterTabs: afterTabs, desktop: desktop, replay: replay)
    }

    /// 电脑浏览器的标识：网站据此显示电脑版页面（电脑版「值班查看」上有各组工作内容）。
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private func load(_ url: URL, extraTabs: [String], pager: [(label: String, steps: Int)],
                      afterTabs: ([CapturedRequest]) -> [CapturedRequest],
                      desktop: Bool,
                      replay: ([CapturedRequest]) -> [CapturedRequest]) async throws -> Page {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.spyScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: desktop ? 1440 : 390, height: desktop ? 900 : 844),
                                configuration: config)
        if desktop { webView.customUserAgent = Self.desktopUserAgent }
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
                Self.autoLoginScript, arguments: ["u": username, "p": password], in: nil, contentWorld: .page)) as? Bool ?? false
            if submitted {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                _ = try? await webView.callAsyncJavaScript(
                    "location.assign(target); return true;", arguments: ["target": url.absoluteString], in: nil, contentWorld: .page)
                try await Task.sleep(nanoseconds: 1_000_000_000)
                html = try await settledHTML(webView)
            }
        }

        let captured = await capturedRequests(webView)
        let replies = await send(replay(captured), in: webView)

        // 再点开其它标签页（如「值班查看」），拿全员排班和各组说明
        var extraHTML: [String] = []
        for tab in extraTabs {
            let clicked = (try? await webView.callAsyncJavaScript(
                Self.clickTabScript, arguments: ["label": tab], in: nil, contentWorld: .page)) as? Bool ?? false
            guard clicked else { continue }
            var last = try await settledHTML(webView)
            extraHTML.append(last)
            for (label, steps) in pager {
                for _ in 0..<steps {
                    let pressed = (try? await webView.callAsyncJavaScript(
                        Self.clickTabScript, arguments: ["label": label], in: nil, contentWorld: .page)) as? Bool ?? false
                    guard pressed, let html = try await changedHTML(webView, from: last) else { break }
                    extraHTML.append(html)
                    last = html
                }
            }
        }
        let allCaptured = extraHTML.isEmpty ? captured : await capturedRequests(webView)
        let extraReplies = await send(afterTabs(allCaptured), in: webView)
        return Page(html: html, captured: allCaptured, replies: replies, extraHTML: extraHTML, extraReplies: extraReplies,
                    url: webView.url?.absoluteString)
    }

    /// 在页面里用同样的请求头和登录状态逐个发出请求，返回各自的内容。
    private func send(_ requests: [CapturedRequest], in webView: WKWebView) async -> [String] {
        var replies: [String] = []
        for request in requests {
            let reply = try? await webView.callAsyncJavaScript(
                Self.replayScript,
                arguments: ["url": request.url, "method": request.method, "headers": request.headers,
                            "body": request.requestBody ?? NSNull()],
                in: nil, contentWorld: .page)
            if let text = reply as? String { replies.append(text) }
        }
        return replies
    }

    /// 点按钮后等页面变化（最多 4 秒）；没变化说明已经翻到头了，返回 nil。
    private func changedHTML(_ webView: WKWebView, from old: String) async throws -> String? {
        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: 330_000_000)
            let html = (try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String) ?? ""
            if !html.isEmpty && html != old {
                // 再等一下让内容画完整
                try await Task.sleep(nanoseconds: 400_000_000)
                return (try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String) ?? html
            }
        }
        return nil
    }

    private func capturedRequests(_ webView: WKWebView) async -> [CapturedRequest] {
        let json = (try? await webView.evaluateJavaScript("JSON.stringify(window.__shiftSpy || [])")) as? String ?? "[]"
        return (try? JSONDecoder().decode([CapturedRequest].self, from: Data(json.utf8))) ?? []
    }

    /// 点击文字正好是 label 的标签（取最里层的元素，点击会冒泡到外层）。
    private static let clickTabScript = """
    const els = [...document.querySelectorAll('a, button, span, div, li, p, [role=tab]')]
      .filter(e => e.offsetParent !== null && (e.innerText || '').trim() === label);
    const el = els[els.length - 1];
    if (!el) return false;
    el.click();
    return true;
    """

    /// 在网页最开始注入：包装 fetch 和 XMLHttpRequest，记下返回 JSON 的请求（最多 50 条，存在页面内存里）。
    private static let spyScript = """
    (function () {
      if (window.__shiftSpy) return;
      const log = window.__shiftSpy = [];
      const keep = e => {
        try {
          if (typeof e.body === 'string' && e.body.length < 500000 && /^\\s*[\\[{]/.test(e.body)) {
            log.push(e);
            if (log.length > 50) log.shift();
          }
        } catch (_) {}
      };
      const abs = u => { try { return new URL(u, location.href).href; } catch (_) { return String(u); } };
      const origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function (input, init) {
          const url = abs(typeof input === 'string' ? input : (input && input.url) || input);
          const method = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
          const headers = {};
          try { new Headers((init && init.headers) || (input && input.headers) || {}).forEach((v, k) => headers[k] = v); } catch (_) {}
          const reqBody = init && typeof init.body === 'string' ? init.body : null;
          return origFetch.apply(this, arguments).then(res => {
            try { res.clone().text().then(t => keep({ url, method, headers, reqBody, status: res.status, body: t })); } catch (_) {}
            return res;
          });
        };
      }
      const P = XMLHttpRequest.prototype, open = P.open, send = P.send, setHeader = P.setRequestHeader;
      P.open = function (m, u) { this.__spy = { method: String(m).toUpperCase(), url: abs(u), headers: {} }; return open.apply(this, arguments); };
      P.setRequestHeader = function (k, v) { if (this.__spy) this.__spy.headers[k] = v; return setHeader.apply(this, arguments); };
      P.send = function (b) {
        const s = this.__spy;
        if (s) {
          s.reqBody = typeof b === 'string' ? b : null;
          this.addEventListener('load', () => {
            try {
              const t = (this.responseType === '' || this.responseType === 'text') ? this.responseText
                      : (this.responseType === 'json' ? JSON.stringify(this.response) : '');
              keep(Object.assign({}, s, { status: this.status, body: t }));
            } catch (_) {}
          });
        }
        return send.apply(this, arguments);
      };
    })();
    """

    /// 用记录下来的请求头和内容再发一次请求（同一个页面、同一个登录状态）。
    private static let replayScript = """
    const init = { method, headers, credentials: 'include' };
    if (body !== null && method !== 'GET' && method !== 'HEAD') init.body = body;
    const r = await fetch(url, init);
    return await r.text();
    """

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
