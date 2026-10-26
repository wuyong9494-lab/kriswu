import WebKit

/// 在看不见的网页里打开周会文档（金山文档、腾讯文档的分享链接），等正文显示出来后取出文字。
/// 用和 App 里浏览器同一份登录状态：在「周会问题」里打开过一次文档、登录过，之后就能自动读。
@MainActor
final class DocTextLoader: NSObject, WKNavigationDelegate {
    /// 把网页（包括同源的内嵌页）上的文字都取出来
    static let textScript = """
    (() => {
      const parts = [];
      const walk = (doc) => {
        try {
          if (doc && doc.body) parts.push(doc.body.innerText || '');
          for (const f of (doc ? doc.querySelectorAll('iframe') : [])) { try { walk(f.contentDocument); } catch (e) {} }
        } catch (e) {}
      };
      walk(document);
      return parts.join('\\n');
    })()
    """

    private var webView: WKWebView?

    /// 打开网页，最多等 seconds 秒，等文字不再变多了再取
    static func text(from url: URL, seconds: Double = 25) async -> String? {
        let loader = DocTextLoader()
        return await loader.load(url, seconds: seconds)
    }

    private func load(_ url: URL, seconds: Double) async -> String? {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        defer { self.webView = nil }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        let deadline = Date().addingTimeInterval(seconds)
        var last = ""
        var stable = 0
        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let text = (try? await webView.evaluateJavaScript(Self.textScript) as? String) ?? ""
            // 正文出来了、而且连着两秒没再变：读完了
            if text.count > 80, text == last { stable += 1 } else { stable = 0 }
            last = text
            if stable >= 2 { break }
        }
        return last.isEmpty ? nil : last
    }
}
