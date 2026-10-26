import SwiftUI
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
                    Label("打开文档读取", systemImage: "safari")
                }
                .disabled(store.settings.meetingDocURL.isEmpty)
                Button {
                    let text = UIPasteboard.general.string ?? ""
                    let result = text.isEmpty ? "剪贴板里没有文字" : store.importMeeting(text: text, source: "剪贴板")
                    ToastCenter.shared.show(result, style: text.isEmpty ? .error : .success)
                } label: {
                    Label("从剪贴板导入", systemImage: "doc.on.clipboard")
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
                Text("文档每周一更新：每周第一次打开 App 时自动去读，读到新的一版就通知你。第一次先点「打开文档读取」，要登录就在里面登录一下。自动读不到时，在金山文档里全选复制，回来点「从剪贴板导入」。文档内容只存在这台手机上。")
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
                                ToastCenter.shared.show(result, style: .success)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
                WebView(webView: model.webView)
                Text(toast ?? "文档显示出来后点「读取本页」；要登录就先在这里登录")
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
                    Button("读取本页") {
                        Task {
                            let text = (try? await model.webView.evaluateJavaScript(DocTextLoader.textScript) as? String) ?? ""
                            let result = store.importMeeting(text: text, source: "打开文档")
                            if MeetingNotes.parse(text).isEmpty {
                                toast = "这一页上没认出各组的内容。文档还没显示完就等一下再点；一直不行就在金山文档里全选复制，用「从剪贴板导入」"
                            } else {
                                ToastCenter.shared.show(result, style: .success)
                                dismiss()
                            }
                        }
                    }
                    .bold()
                }
            }
            .onAppear { model.load(store.settings.meetingDocURL) }
        }
    }
}
