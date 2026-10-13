import SwiftUI
import WebKit

/// 设置 › 查找网页排班代码：在手机上打开值班网站，把网页脚本里和排班有关的片段找出来。
/// 只在这台手机上找，不上传；要不要发给别人由用户决定（代码属于单位，先问过写系统的人）。
struct SiteCodeFinderView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = WebModel(userAgent: WebPageLoader.desktopUserAgent)
    @State private var searching = false
    @State private var scanned: (scripts: Int, snippets: [ScriptScanner.Snippet])?
    @State private var showResults = false

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
            WebView(webView: model.webView)
            VStack(alignment: .leading, spacing: 6) {
                Text("登录后打开「值班查看」或有「自动排班」按钮的页面，再点「查找」。只能找到在网页里排班的代码；网站在服务器上排班的话，这里找不到。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await search() }
                } label: {
                    Label(searching ? "正在查找…" : "查找排班代码", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DSButtonStyle(kind: .primary))
                .disabled(searching)
            }
            .padding(10)
            .background(.thinMaterial)
        }
        // 底部的悬浮标签栏会挡住「查找」按钮：留出位置
        .appBackground()
        .navigationTitle("查找网页排班代码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.webView.goBack() } label: { Image(systemName: "chevron.left").accessibilityLabel("后退") }
                    .disabled(!model.canGoBack)
                Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise").accessibilityLabel("刷新") }
            }
        }
        .sheet(isPresented: $showResults) {
            if let scanned { SiteCodeResultsView(scripts: scanned.scripts, snippets: scanned.snippets) }
        }
        .onAppear {
            model.credentials = (store.settings.sourceUsername, Keychain.get(.sourcePassword) ?? "")
            let custom = store.settings.desktopNotesURL
            if !custom.isEmpty {
                model.load(custom)
            } else if let url = SyncService.desktopDutyURL(from: store.settings.sourceURL) {
                model.load(url.absoluteString)
            } else {
                model.load(store.settings.sourceURL)
            }
        }
    }

    private func search() async {
        searching = true
        defer { searching = false }
        let json = (try? await model.webView.callAsyncJavaScript(ScriptScanner.collectScriptsJS, arguments: [:],
                                                                in: nil, contentWorld: .page)) as? String ?? "[]"
        // 几 MB 的脚本放到后台找，不卡界面
        let result = await Task.detached(priority: .userInitiated) { () -> (Int, [ScriptScanner.Snippet]) in
            let scripts = ScriptScanner.scripts(fromJSON: json)
            return (scripts.count, ScriptScanner.scan(scripts))
        }.value
        scanned = (result.0, result.1)
        showResults = true
    }
}

private struct SiteCodeResultsView: View {
    @Environment(\.dismiss) private var dismiss
    let scripts: Int
    let snippets: [ScriptScanner.Snippet]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(snippets.isEmpty
                         ? "看了 \(scripts) 个网页脚本，没找到和排班有关的代码：网站多半是在服务器上排班的。可以问写系统的人要排班那一段代码或需求说明。"
                         : "看了 \(scripts) 个网页脚本，找到 \(snippets.count) 段可能和排班有关的代码，按相关程度排序。代码属于单位，发给别人前先问过写系统的人；里面要是有密码、密钥，先删掉。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(snippets.enumerated()), id: \.offset) { index, snippet in
                    Section {
                        Text(ScriptScanner.readable(snippet.text))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("第 \(index + 1) 段 · 关键词：\(snippet.keywords.joined(separator: "、"))")
                            Text(fileName(snippet.source)).font(.caption2)
                        }
                    }
                }
            }
            .appList()
            .navigationTitle("找到的代码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: exportText) { Image(systemName: "square.and.arrow.up") }
                        .disabled(snippets.isEmpty)
                }
            }
        }
    }

    /// 只显示文件名，不显示网站地址
    private func fileName(_ source: String) -> String {
        URL(string: source)?.lastPathComponent ?? source
    }

    private var exportText: String {
        snippets.enumerated().map { i, s in
            "// 第 \(i + 1) 段（\(fileName(s.source))，关键词：\(s.keywords.joined(separator: "、"))）\n" + ScriptScanner.readable(s.text)
        }.joined(separator: "\n\n")
    }
}
