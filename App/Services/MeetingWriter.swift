import Foundation

/// 把 App 里改的周会问题写回金山文档：调用放在周会表格里的 AirScript 脚本（金山文档的「脚本令牌」+ 脚本 webhook）。
/// 要有这份文档的编辑权限才能放脚本；脚本按 App 发来的格子改，改之前核对格子里还是 App 导入时看到的内容
enum MeetingWriter {
    /// 放进周会表格的脚本（「复制脚本」复制的就是它）
    static let script = #"""
    /* 值班提醒 · 周会问题写回。放在周会表格的 AirScript 脚本编辑器里（不是 JS 宏），整段粘贴后保存。 */
    /* App 发来要改的格子：先按这一行原来的内容找到这一行，格子里还是 App 导入时看到的内容才改；有一个格子被别人改过，这次一个都不改。 */
    /* 在编辑器里直接点「运行」只会在日志里列出工作表的名字，不改表格。 */
    function norm(v) {
      if (v === null || v === undefined) { return ""; }
      return String(v).replace(/\r\n?/g, "\n").replace(/^\s+|\s+$/g, "");
    }
    function allSheets() {
      var list = [];
      var count = Application.Sheets.Count;
      for (var i = 1; i <= count; i++) { list.push(Application.Sheets.Item(i)); }
      return list;
    }
    function locate(w, sheets) {
      for (var i = 0; i < sheets.length; i++) {
        if (norm(sheets[i].Cells.Item(w.anchorRow, w.anchorColumn).Value2) === norm(w.anchorText)) {
          return { sheet: sheets[i], dr: 0, dc: 0 };
        }
      }
      for (var j = 0; j < sheets.length; j++) {
        var used = sheets[j].UsedRange;
        var rows = used.Rows.Count;
        var cols = used.Columns.Count;
        for (var r = 1; r <= rows; r++) {
          for (var c = 1; c <= cols; c++) {
            var cell = used.Cells.Item(r, c);
            if (norm(cell.Value2) === norm(w.anchorText)) {
              return { sheet: sheets[j], dr: cell.Row - w.anchorRow, dc: cell.Column - w.anchorColumn };
            }
          }
        }
      }
      return null;
    }
    function run(args) {
      var sheets = allSheets();
      if (!args || !args.writes) {
        var names = [];
        for (var i = 0; i < sheets.length; i++) { names.push(sheets[i].Name); }
        return { ok: true, sheets: names };
      }
      var ready = [];
      var problems = [];
      for (var k = 0; k < args.writes.length; k++) {
        var w = args.writes[k];
        var at = locate(w, sheets);
        if (!at) { problems.push({ index: k, reason: "notFound" }); continue; }
        var cell = at.sheet.Cells.Item(w.row + at.dr, w.column + at.dc);
        var now = norm(cell.Value2);
        if (now === norm(w.value)) { continue; }
        if (now !== norm(w.expect)) { problems.push({ index: k, reason: "changed" }); continue; }
        ready.push({ cell: cell, value: w.value });
      }
      if (problems.length > 0) { return { ok: false, problems: problems }; }
      for (var m = 0; m < ready.length; m++) { ready[m].cell.Value2 = ready[m].value; }
      return { ok: true, written: ready.length };
    }
    var shiftResult = run(typeof Context !== "undefined" ? Context.argv : null);
    console.log("SHIFT_RESULT " + JSON.stringify(shiftResult));
    """#

    /// 脚本存成文本文件，分享到电脑上（微信、QQ 发文字常把换行变成 <br/>，发文件不会）
    static var scriptFile: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("周会写回脚本.txt")
        try? script.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    struct Reply {
        var ok: Bool
        var message: String
    }

    /// 是金山文档（WPS）脚本的 webhook 链接。文档里的脚本是 …/api/v3/ide/file/…/script/…/sync_task；
    /// 「我的脚本」的链接可能长得不一样，只认网址是金山文档、WPS 的
    static func isScriptURL(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host?.lowercased(), url.path.count > 1 else { return false }
        return host == "kdocs.cn" || host.hasSuffix(".kdocs.cn") || host == "wps.cn" || host.hasSuffix(".wps.cn")
    }

    /// 测试连接：脚本回工作表的名字
    static func ping(url: URL, token: String) async -> Reply {
        let raw = await call(["ping": true], url: url, token: token)
        if let problem = raw.problem { return Reply(ok: false, message: problem) }
        if let sheets = raw.result?["sheets"] as? [String] {
            return Reply(ok: true, message: "连上了：脚本看到的工作表是「\(sheets.joined(separator: "」「"))」")
        }
        return Reply(ok: true, message: "连上了，但脚本没回结果：确认放进去的是刚复制的那份脚本")
    }

    static func write(_ writes: [MeetingWriteback.CellWrite], url: URL, token: String) async -> Reply {
        let list: [[String: Any]] = writes.map { w in
            ["anchorRow": w.anchorRow, "anchorColumn": w.anchorColumn, "anchorText": w.anchorText,
             "row": w.row, "column": w.column, "expect": w.expect, "value": w.value]
        }
        let raw = await call(["writes": list], url: url, token: token)
        if let problem = raw.problem { return Reply(ok: false, message: problem + "，没写进去") }
        guard let result = raw.result else {
            return Reply(ok: true, message: "发过去了，但脚本没回结果：打开金山文档看一下改上没有")
        }
        if result["ok"] as? Bool == true {
            let count = (result["written"] as? Int) ?? writes.count
            return Reply(ok: true, message: count == 0 ? "金山文档里本来就是这样，没有要改的" : "写进金山文档了：改了 \(count) 个格子")
        }
        let problems = (result["problems"] as? [[String: Any]]) ?? []
        let lines: [String] = problems.compactMap { p in
            guard let i = p["index"] as? Int, writes.indices.contains(i) else { return nil }
            let place = writes[i].summary.components(separatedBy: "：").first ?? ""
            return place + ((p["reason"] as? String) == "notFound" ? "找不到了（表格大改过）" : "刚被别人改过")
        }
        return Reply(ok: false, message: "一个格子都没改：" + (lines.isEmpty ? "文档里的内容和手机上的对不上" : lines.joined(separator: "；"))
            + "。先在「导入」里下载最新一版，再改一次")
    }

    private static func call(_ argv: [String: Any], url: URL, token: String) async -> (result: [String: Any]?, problem: String?) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "AirScript-Token")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["Context": ["argv": argv]])
        guard let reply = try? await URLSession.shared.data(for: request) else { return (nil, "连不上金山文档") }
        let data = reply.0
        let status = (reply.1 as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            return (nil, "脚本令牌不对或过期了：在脚本编辑器里重新生成「脚本令牌」，粘贴到 App 里")
        }
        guard (200..<300).contains(status) else { return (nil, "金山文档回了 HTTP \(status)（\(DocDownload.brief(data))）") }
        let json = try? JSONSerialization.jsonObject(with: data)
        if let dict = json as? [String: Any], let error = dict["error"] as? String, !error.isEmpty {
            return (nil, "脚本出错：\(error.prefix(120))")
        }
        return (MeetingWriteback.scriptResult(in: json), nil)
    }
}
