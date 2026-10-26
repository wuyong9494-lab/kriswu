import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// 今天页：周会文档里各组提的问题还有几个没解决；没设置时是导入入口
struct MeetingCard: View {
    @EnvironmentObject private var store: AppStore
    let today: DayKey

    var body: some View {
        let issues = store.settings.meetingIssues
        let week = MeetingTracker.monday(of: today)
        let open = issues.filter { $0.status == .open }.sorted { ($0.firstWeek, $0.group) < ($1.firstWeek, $1.group) }
        let quiet = issues.filter { $0.status == .quiet }.count
        NavigationLink { MeetingIssuesView() } label: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Label("周会问题", systemImage: "doc.text.magnifyingglass")
                        .font(DS.Font.overline).kerning(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if store.settings.meetingDocURL.isEmpty && issues.isEmpty {
                    Text("导入每周一更新的周会文档，跟进各组提的问题有没有解决")
                        .font(DS.Font.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("还有 \(open.count) 个没解决" + (quiet > 0 ? " · \(quiet) 个这周没再提，待确认" : ""))
                        .font(DS.Font.headline)
                        .foregroundStyle(.primary)
                    ForEach(open.prefix(3)) { issue in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                            Text(issue.group).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.accent)
                            Text(issue.text).font(DS.Font.caption).foregroundStyle(.primary).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Text("第 \(issue.weeks(through: week)) 周").font(DS.Font.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let date = store.settings.meetingLastImport {
                        Text("文档上次更新 \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(PressableStyle())
    }
}

/// 周会问题：文档链接、导入，按组列出没解决 / 没再提 / 已解决的问题
struct MeetingIssuesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var browsing = false
    @State private var pasting = false
    @State private var pasteText = ""
    @State private var showResolved = false
    @State private var pickingFile = false
    @State private var downloading = false

    private var week: DayKey { MeetingTracker.monday(of: .today) }

    var body: some View {
        let issues = store.settings.meetingIssues
        let groups = Array(Set(issues.map(\.group))).sorted()
        List {
            Section {
                DraftTextField("粘贴周会文档的分享链接（金山文档、腾讯文档）", value: store.settings.meetingDocURL) {
                    store.settings.meetingDocURL = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button {
                    browsing = true
                } label: {
                    Label("打开文档（在这里登录金山文档）", systemImage: "safari")
                }
                .disabled(store.settings.meetingDocURL.isEmpty)
                Button {
                    guard let url = URL(string: store.settings.meetingDocURL) else { return }
                    downloading = true
                    Task {
                        let result = await store.downloadMeeting(link: url)
                        downloading = false
                        ToastCenter.shared.show(result.message, style: result.ok ? .success : .error)
                    }
                } label: {
                    HStack {
                        Label("现在下载最新一版", systemImage: "arrow.down.circle")
                        if downloading { Spacer(); ProgressView() }
                    }
                }
                .disabled(downloading || !(URL(string: store.settings.meetingDocURL).map(DocDownload.isSupported) ?? false))
                Button {
                    let result = store.importMeetingFromClipboard()
                    ToastCenter.shared.show(result, style: AppStore.meetingImportFailed(result) ? .error : .success)
                } label: {
                    Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                }
                Button {
                    pickingFile = true
                } label: {
                    Label("从文件导入（Excel / CSV）", systemImage: "tablecells")
                }
                Button {
                    pasteText = ""
                    pasting = true
                } label: {
                    Label("粘贴文字导入", systemImage: "text.badge.plus")
                }
                if let message = store.settings.meetingMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if !store.settings.meetingDownloadLog.isEmpty {
                    NavigationLink("查看上次自动下载的过程") {
                        List(Array(store.settings.meetingDownloadLog.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote).textSelection(.enabled)
                        }
                        .appList()
                        .navigationTitle("下载过程")
                    }
                }
                if let text = store.meetingPageText {
                    NavigationLink("查看上次读到的内容") {
                        ScrollView {
                            Text(text).font(.footnote.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding()
                        }
                        .appList()
                        .navigationTitle("读到的内容")
                    }
                }
            } header: {
                Text("周会文档")
            } footer: {
                Text("第一次点「打开文档」，在里面登录你自己的金山文档账号。之后每周一 App 自己下载这份表格的 Excel 读一遍，读到新的一版就通知你，不用再手动导。文档设了禁止下载就下载不了；下载不成功时会提醒你，点「查看上次自动下载的过程」能看卡在哪一步。\n\n手动导入：在金山文档 App 里全选表格复制，回来点「从剪贴板导入」；或导出成 Excel，用「分享 → 值班提醒」打开。\n\n按「分组」一列分组，「完成进展」里 1. 2. 3. 每条算一个问题，「完成情况」写了完成、上线、已解决的算解决了。文档内容只存在这台手机上。")
            }

            if issues.isEmpty {
                Section {
                    Text("还没有导入过。导入后按组列出提的问题，每周和上一周对比：还在提的是没解决，写了「已解决」的是解决了，这周没再提的标出来等你确认。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            ForEach(groups, id: \.self) { group in
                let items = pending(issues, group: group)
                if !items.isEmpty {
                    Section(group) {
                        ForEach(items) { row($0) }
                    }
                }
            }

            let resolved = issues.filter { $0.status == .resolved }
                .sorted { ($0.resolvedWeek ?? $0.lastWeek) > ($1.resolvedWeek ?? $1.lastWeek) }
            if !resolved.isEmpty {
                Section {
                    DisclosureGroup("已解决 \(resolved.count) 个", isExpanded: $showResolved) {
                        ForEach(resolved) { row($0) }
                    }
                }
            }
        }
        .appList()
        .navigationTitle("周会问题")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $browsing) { MeetingDocBrowser() }
        .fileImporter(isPresented: $pickingFile,
                      allowedContentTypes: [UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
                                            .commaSeparatedText, .tabSeparatedText]) { result in
            guard case .success(let url) = result else { return }
            let message = store.importMeetingFile(url)
            ToastCenter.shared.show(message, style: AppStore.meetingImportFailed(message) ? .error : .success)
        }
        .sheet(isPresented: $pasting) {
            NavigationStack {
                TextEditor(text: $pasteText)
                    .padding(.horizontal)
                    .navigationTitle("粘贴周会内容")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { pasting = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                let result = store.importMeeting(text: pasteText, source: "粘贴")
                                ToastCenter.shared.show(result, style: AppStore.meetingImportFailed(result) ? .error : .success)
                                pasting = false
                            }
                            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
        }
    }

    /// 这个组没解决的在前（先提的在前），没再提的在后
    private func pending(_ issues: [MeetingIssue], group: String) -> [MeetingIssue] {
        let list = issues.filter { $0.group == group && $0.status != .resolved }
        let open = list.filter { $0.status == .open }.sorted { $0.firstWeek < $1.firstWeek }
        let quiet = list.filter { $0.status == .quiet }.sorted { $0.firstWeek < $1.firstWeek }
        return open + quiet
    }

    @ViewBuilder
    private func row(_ issue: MeetingIssue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if issue.status == .resolved {
                    Text(issue.group).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(issue.text).font(.subheadline)
                    .strikethrough(issue.status == .resolved)
                    .foregroundStyle(issue.status == .resolved ? Color.secondary : Color.primary)
            }
            if let detail = issue.detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Text(caption(issue)).font(.caption)
                .foregroundStyle(issue.status == .quiet ? Color.orange : Color.secondary)
            if issue.status == .quiet {
                HStack {
                    Button("已解决") { store.setMeetingIssue(issue.id, status: .resolved) }
                    Button("还没解决") { store.setMeetingIssue(issue.id, status: .open) }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .swipeActions {
            if issue.status == .resolved {
                Button("没解决") { store.setMeetingIssue(issue.id, status: .open) }.tint(.orange)
            } else {
                Button("已解决") { store.setMeetingIssue(issue.id, status: .resolved) }.tint(.green)
            }
            Button("删除", role: .destructive) { store.deleteMeetingIssue(issue.id) }
        }
    }

    private func caption(_ issue: MeetingIssue) -> String {
        let since = "\(issue.firstWeek.month)/\(issue.firstWeek.day) 那周提出"
        switch issue.status {
        case .open:
            return since + " · 第 \(issue.weeks(through: week)) 周还没解决" + (issue.manual ? "（自己标的）" : "")
        case .quiet:
            return since + " · 这周文档里没再提，可能解决了"
        case .resolved:
            let at = issue.resolvedWeek.map { "\($0.month)/\($0.day) 那周解决" } ?? "已解决"
            return since + " · " + at + "，用了 \(issue.weeks(through: week)) 周" + (issue.manual ? "（自己标的）" : "")
        }
    }
}

/// App 里打开周会文档（第一次可能要登录），点「读取本页」导入
struct MeetingDocBrowser: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WebModel()
    @State private var toast: String?
    @State private var reading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
                WebView(webView: model.webView)
                Text(toast ?? "第一次先在这里登录金山文档；文档显示出来后点「读取文档」")
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
            .appList()
            .navigationTitle("周会文档")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { model.webView.goBack() } label: { Image(systemName: "chevron.left").accessibilityLabel("后退") }
                    Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise").accessibilityLabel("刷新") }
                    Spacer()
                    Button(reading ? "读取中…" : "读取文档") {
                        reading = true
                        toast = "正在用你登录的账号下载这份表格…"
                        Task {
                            defer { reading = false }
                            // 先用刚登录的账号下载 Excel；不是金山文档或下载不了，再读这一页上的字
                            var problem: String?
                            if let url = URL(string: store.settings.meetingDocURL), DocDownload.isSupported(url) {
                                let result = await store.downloadMeeting(link: url)
                                if result.ok {
                                    ToastCenter.shared.show(result.message, style: .success)
                                    dismiss()
                                    return
                                }
                                problem = result.message
                            }
                            let text = (try? await model.webView.evaluateJavaScript(DocTextLoader.textScript) as? String) ?? ""
                            if MeetingNotes.parse(text).isEmpty {
                                toast = (problem.map { $0 + "。" } ?? "这一页读不出表格里的字。")
                                    + "可以在金山文档里全选复制，用「从剪贴板导入」"
                            } else {
                                ToastCenter.shared.show(store.importMeeting(text: text, source: "打开文档"), style: .success)
                                dismiss()
                            }
                        }
                    }
                    .bold()
                    .disabled(reading)
                }
            }
            .onAppear { model.load(store.settings.meetingDocURL) }
        }
    }
}
