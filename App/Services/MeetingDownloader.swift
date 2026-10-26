import Foundation
import WebKit

/// 自己下载周会表格（金山文档的 Excel）：用在 App 里「打开文档」时登录的金山文档账号。
/// 照网页版的做法：分享链接 → 文件编号 → 下载地址 → Excel 文件。金山文档没公开这几个接口，
/// 每一步的结果都记下来（「周会问题」里能看），哪一步不对一眼就知道。文档设了禁止下载就下载不了，不绕开
@MainActor
enum MeetingDownloader {
    struct Outcome {
        var data: Data?
        var name: String?
        var log: [String]
        /// 没下载成功时给人看的一句话
        var problem: String?
    }

    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    static func download(_ link: URL) async -> Outcome {
        var log: [String] = []
        func fail(_ problem: String) -> Outcome {
            log.append("✗ " + problem)
            return Outcome(data: nil, name: nil, log: log, problem: problem)
        }
        guard DocDownload.isSupported(link), let sid = DocDownload.shareID(link) else {
            return fail("只有金山文档的分享链接（kdocs.cn/l/…）能自动下载")
        }
        let cookies = await kdocsCookies()
        let signedIn = cookies.contains { $0.name.lowercased().contains("sid") }
        log.append("金山文档的登录记录 \(cookies.count) 条" + (signedIn ? "" : "，没看到登录凭证"))
        guard !cookies.isEmpty else { return fail("还没在 App 里登录金山文档：点「打开文档」，在里面登录一次") }

        // 1. 分享链接 → 文件编号
        var file: DocDownload.FileRef?
        var loginRefused = false
        for api in DocDownload.linkInfoURLs(sid) {
            let label = "文档信息 \(api.host ?? "")\(api.path.replacingOccurrences(of: sid, with: "…"))"
            guard let r = await get(api, cookies: cookies, referer: link) else { log.append(label + "：连不上"); continue }
            if let found = DocDownload.file(inJSON: r.data) {
                file = found
                log.append(label + "：找到「\(found.name ?? "文件")」")
                break
            }
            if DocDownload.saysLogin(status: r.status, data: r.data) { loginRefused = true }
            log.append(label + "：HTTP \(r.status) \(DocDownload.brief(r.data))")
        }
        if file == nil {
            // 接口不对：打开文档页，从网页自己要到的内容里找
            let pieces = await pageCaptures(link)
            file = pieces.lazy.compactMap { DocDownload.file(inText: $0) }.first
            log.append(file.map { "从文档页里找到「\($0.name ?? "文件")」" } ?? "文档页里也没找到文件编号（抓到 \(pieces.count) 段）")
        }
        guard let file else {
            return fail(loginRefused ? "金山文档说没登录（可能过期了）：点「打开文档」重新登录一次"
                                     : "找不到这份文档的文件编号，金山文档可能改了做法")
        }

        // 2. 文件编号 → 下载地址 → 文件
        for api in DocDownload.downloadURLs(file) {
            let label = "下载 \(api.host ?? "")\(api.path.replacingOccurrences(of: file.group, with: "…").replacingOccurrences(of: file.id, with: "…"))"
            guard let r = await get(api, cookies: cookies, referer: link) else { log.append(label + "：连不上"); continue }
            if DocDownload.isZip(r.data) {
                log.append(label + "：拿到文件（\(r.data.count / 1024) KB）")
                return Outcome(data: r.data, name: file.name, log: log, problem: nil)
            }
            if let fileURL = DocDownload.fileURL(inJSON: r.data) {
                guard let d = await get(fileURL, cookies: cookies, referer: link) else { log.append(label + "：下载地址连不上"); continue }
                if DocDownload.isZip(d.data) {
                    log.append(label + "：拿到文件（\(d.data.count / 1024) KB）")
                    return Outcome(data: d.data, name: file.name, log: log, problem: nil)
                }
                log.append(label + "：下载到的不是 Excel（HTTP \(d.status) \(d.type)）")
                continue
            }
            if DocDownload.saysLogin(status: r.status, data: r.data) { loginRefused = true }
            log.append(label + "：HTTP \(r.status) \(DocDownload.brief(r.data))")
        }
        let name = file.name.map { "「\($0)」" } ?? ""
        return fail(loginRefused ? "金山文档说没登录（可能过期了）：点「打开文档」重新登录一次"
                                 : "找到了文档\(name)，但没拿到下载地址（可能设了禁止下载，或者不是 Excel 表格）")
    }

    /// App 里网页登录金山文档留下的登录记录
    private static func kdocsCookies() async -> [HTTPCookie] {
        let all: [HTTPCookie] = await withCheckedContinuation { done in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { done.resume(returning: $0) }
        }
        return all.filter { c in
            let d = c.domain.lowercased()
            return d.hasSuffix("kdocs.cn") || d.hasSuffix("wps.cn")
        }
    }

    /// 带上这个网址自己的登录记录去请求（别的网址一条都不带）
    private static func get(_ url: URL, cookies: [HTTPCookie], referer: URL) async -> (status: Int, data: Data, type: String)? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpShouldHandleCookies = false
        let host = url.host?.lowercased() ?? ""
        let matching = cookies.filter { c in
            let d = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == d || host.hasSuffix("." + d)
        }
        for (field, value) in HTTPCookie.requestHeaderFields(with: matching) { request.setValue(value, forHTTPHeaderField: field) }
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request) else { return nil }
        let http = result.1 as? HTTPURLResponse
        return (http?.statusCode ?? 0, result.0, http?.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    /// 网页每次向金山文档要到带「groupid」的内容，都记一份（文件编号就在里面）
    private static let hookScript = """
    (() => {
      let top = window;
      try { top = window.top; void top.document; } catch (e) { top = window; }
      try { if (!top.__shiftFound) top.__shiftFound = []; } catch (e) { top = window; top.__shiftFound = []; }
      if (window.__shiftHooked) return;
      window.__shiftHooked = true;
      const keep = (text) => {
        try {
          if (typeof text === 'string' && text.indexOf('groupid') >= 0 && top.__shiftFound.length < 40) top.__shiftFound.push(text.slice(0, 30000));
        } catch (e) {}
      };
      const fetch0 = window.fetch;
      if (fetch0) {
        window.fetch = function () {
          return fetch0.apply(this, arguments).then((r) => {
            try { r.clone().text().then(keep).catch(() => {}); } catch (e) {}
            return r;
          });
        };
      }
      const send0 = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        try {
          this.addEventListener('load', () => {
            try {
              if (this.responseType === '' || this.responseType === 'text') keep(this.responseText);
              else if (this.responseType === 'json') keep(JSON.stringify(this.response));
            } catch (e) {}
          });
        } catch (e) {}
        return send0.apply(this, arguments);
      };
    })();
    """

    /// 记下的内容，加上网页源码里「groupid」前后的几段
    private static let collectScript = """
    (() => {
      let found = [];
      try { found = (window.__shiftFound || []).slice(); } catch (e) {}
      const html = document.documentElement ? document.documentElement.innerHTML : '';
      let at = html.indexOf('groupid');
      for (let n = 0; at >= 0 && n < 20; n++) {
        found.push(html.slice(Math.max(0, at - 1500), at + 1500));
        at = html.indexOf('groupid', at + 1500);
      }
      return JSON.stringify(found);
    })()
    """

    /// 在看不见的网页里打开文档，最多等 seconds 秒
    private static func pageCaptures(_ url: URL, seconds: Double = 20) async -> [String] {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(WKUserScript(source: hookScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        let deadline = Date().addingTimeInterval(seconds)
        var found: [String] = []
        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let json = (try? await webView.evaluateJavaScript(collectScript) as? String) ?? "[]"
            found = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? found
            if found.contains(where: { DocDownload.file(inText: $0) != nil }) { break }
        }
        webView.stopLoading()
        return found
    }
}
