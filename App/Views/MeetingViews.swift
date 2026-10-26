import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// 周会问题按状态分三栏看
private enum MeetingFilter: String, CaseIterable {
    case open = "没解决", quiet = "待确认", resolved = "已解决"

    var status: MeetingIssue.Status {
        switch self {
        case .open: return .open
        case .quiet: return .quiet
        case .resolved: return .resolved
        }
    }
}

/// 排序：没解决的挂得久的在前；没再提的、解决了的最近的在前
private func meetingOrder(_ a: MeetingIssue, _ b: MeetingIssue) -> Bool {
    switch a.status {
    case .open:
        return (a.firstWeek, a.text) < (b.firstWeek, b.text)
    case .quiet:
        return a.lastWeek != b.lastWeek ? a.lastWeek > b.lastWeek : a.text < b.text
    case .resolved:
        let x = a.resolvedWeek ?? a.lastWeek, y = b.resolvedWeek ?? b.lastWeek
        return x != y ? x > y : a.text < b.text
    }
}

/// 挂了几周的颜色：两周起变橙，四周起变红
private func ageColor(_ weeks: Int) -> Color {
    weeks >= 4 ? DS.Palette.danger : weeks >= 2 ? DS.Palette.warning : DS.Palette.accent
}

/// 今天页：还有几个没解决、各组几个、挂得最久的三条；没设置时是导入入口
struct MeetingCard: View {
    @EnvironmentObject private var store: AppStore
    let today: DayKey

    var body: some View {
        let issues = store.settings.meetingIssues
        let week = MeetingTracker.monday(of: today)
        let open = issues.filter { $0.status == .open }.sorted(by: meetingOrder)
        let quiet = issues.filter { $0.status == .quiet }.count
        let groups = Dictionary(grouping: open, by: \.group).map { ($0.key, $0.value.count) }
            .sorted { ($1.1, $0.0) < ($0.1, $1.0) }
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
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.xxs) {
                        Text("\(open.count)").font(DS.Font.number)
                            .foregroundStyle(open.isEmpty ? DS.Palette.success : DS.Palette.warning)
                        Text("个没解决").font(DS.Font.headline).foregroundStyle(.primary)
                        if quiet > 0 {
                            Text("· \(quiet) 个待确认").font(DS.Font.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !groups.isEmpty {
                        Text(groups.map { "\($0.0) \($0.1)" }.joined(separator: " · "))
                            .font(DS.Font.caption).foregroundStyle(.secondary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    ForEach(open.prefix(3)) { issue in
                        let weeks = issue.weeks(through: week)
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                            Circle().fill(ageColor(weeks)).frame(width: 6, height: 6)
                            Text(issue.text).font(DS.Font.caption).foregroundStyle(.primary).lineLimit(1)
                            Spacer(minLength: 0)
                            if weeks >= 2 {
                                Text("第 \(weeks) 周").font(DS.Font.caption).foregroundStyle(ageColor(weeks))
                            } else if let owner = issue.owners.first {
                                Text(owner).font(DS.Font.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let date = store.settings.meetingLastImport {
                        Text("文档 \(date.formatted(.dateTime.month().day())) 更新")
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

/// 周会问题：上面三格切「没解决 / 待确认 / 已解决」，一排组名筛组，每条两行（点一下展开）。
/// 导入、文档链接在右上角
struct MeetingIssuesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filter: MeetingFilter = .open
    @State private var group: String?
    @State private var byOwner = false
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var showingSource = false
    /// 正在编辑的组（一次编辑一个组）
    @State private var editingGroup: String?
    @State private var drafts: [String: MeetingWriteback.Draft] = [:]
    @State private var additions: [NewIssue] = []
    @State private var confirming: PendingMeetingWrite?
    @State private var askSetup: PendingMeetingWrite?

    private var week: DayKey { MeetingTracker.monday(of: .today) }

    /// 编辑时新加的一条
    private struct NewIssue: Identifiable {
        let id = UUID()
        var draft = MeetingWriteback.Draft()
    }

    private struct IssueSection {
        let title: String
        let items: [MeetingIssue]
    }

    var body: some View {
        let issues = store.settings.meetingIssues
        let matching = issues.filter(matchesQuery)
        let shown = matching.filter { $0.status == filter.status && (group == nil || $0.group == group) }
        let hasHistory = issues.contains { $0.firstWeek < week }
        List {
            if issues.isEmpty {
                emptyState
            } else if let g = editingGroup {
                editSections(g, issues: issues)
            } else {
                overview(issues: issues, matching: matching)
                if shown.isEmpty {
                    Section {
                        Text(emptyText).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(sections(shown, issues: issues), id: \.title) { section in
                    Section {
                        ForEach(section.items) { row($0, showGroup: byOwner, hasHistory: hasHistory) }
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text("\(section.items.count) 条").monospacedDigit()
                            if !byOwner {
                                Button { startEditing(section.title) } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.borderless)
                                .padding(.leading, DS.Space.xs)
                            }
                        }
                    }
                }
            }
        }
        .appList()
        .navigationTitle("周会问题")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜问题、负责人")
        .navigationBarBackButtonHidden(editingGroup != nil)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let g = editingGroup {
                    Button("保存") { save(g) }.bold()
                } else {
                    toolbarButtons
                }
            }
        }
        .sheet(item: $confirming) { pending in
            NavigationStack {
                MeetingWriteConfirmView(pending: pending) { stopEditing() }
            }
        }
        .confirmationDialog("还没设置写回金山文档", isPresented: Binding(get: { askSetup != nil }, set: { if !$0 { askSetup = nil } }),
                            titleVisibility: .visible, presenting: askSetup) { pending in
            Button("只存在手机上") {
                store.saveMeetingEdits(drafts: pending.drafts, plan: pending.plan, group: pending.group, written: false)
                ToastCenter.shared.show("存在手机上了，金山文档里没改", style: .success)
                stopEditing()
            }
            Button("去设置写回") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showingSource = true }
            }
        } message: { _ in
            Text("设置好以后，保存时会把改动写进金山文档的周会表格。")
        }
        .sheet(isPresented: $showingSource) {
            NavigationStack { MeetingSourceView() }
        }
        .onAppear {
            // 没有没解决的、只剩待确认的：直接看待确认
            if filter == .open, !issues.contains(where: { $0.status == .open }), issues.contains(where: { $0.status == .quiet }) {
                filter = .quiet
            }
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        Menu {
            Picker("怎么分", selection: $byOwner) {
                Label("按组分", systemImage: "square.grid.2x2").tag(false)
                Label("按负责人分", systemImage: "person.2").tag(true)
            }
        } label: {
            Image(systemName: byOwner ? "person.2" : "square.grid.2x2").accessibilityLabel("按组分还是按负责人分")
        }
        Button { showingSource = true } label: {
            Image(systemName: "square.and.arrow.down").accessibilityLabel("导入周会文档")
        }
    }

    // MARK: - 编辑一个组

    private func startEditing(_ group: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            drafts = [:]
            additions = []
            expanded = []
            editingGroup = group
        }
    }

    private func stopEditing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            editingGroup = nil
            drafts = [:]
            additions = []
        }
    }

    /// 保存：算出要改表格里哪几格。设置好写回的先给看要改什么，确认了才写；没设置的问只存手机上还是去设置
    private func save(_ group: String) {
        let plan = MeetingWriteback.plan(issues: store.settings.meetingIssues, drafts: drafts,
                                         additions: additions.map(\.draft), group: group)
        guard plan.hasChanges else { stopEditing(); return }
        let pending = PendingMeetingWrite(group: group, plan: plan, drafts: drafts)
        if plan.writes.isEmpty {
            store.saveMeetingEdits(drafts: drafts, plan: plan, group: group, written: false)
            ToastCenter.shared.show(plan.skipped.first ?? "存在手机上了", style: .success)
            stopEditing()
        } else if store.meetingWritebackReady {
            confirming = pending
        } else {
            askSetup = pending
        }
    }

    /// 按表格里的先后排（第几行、一格里第几条）
    private func documentOrder(_ a: MeetingIssue, _ b: MeetingIssue) -> Bool {
        let x = (a.source?.row ?? .max, a.source?.number ?? 0), y = (b.source?.row ?? .max, b.source?.number ?? 0)
        return x != y ? x < y : (a.firstWeek, a.text) < (b.firstWeek, b.text)
    }

    @ViewBuilder
    private func editSections(_ group: String, issues: [MeetingIssue]) -> some View {
        let items = issues.filter { $0.group == group }.sorted(by: documentOrder)
        Section {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(store.meetingWritebackReady
                     ? "改完点右上角「保存」：先给你看要改金山文档里哪几格，确认了才写进去。"
                     : "改完点右上角「保存」。还没设置写回金山文档，保存时可以只存在手机上，或者先去设置。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("不改了", role: .cancel) { stopEditing() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        Section {
            ForEach(items) { editRow($0) }
            ForEach($additions) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: DS.Space.xs) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(DS.Palette.accent).font(.subheadline)
                        TextField("新的问题", text: $item.draft.text, axis: .vertical).font(.subheadline)
                    }
                    TextField("进展（可以不填）", text: $item.draft.progress, axis: .vertical)
                        .font(.caption)
                        .padding(.leading, 24)
                }
                .padding(.vertical, 2)
            }
            .onDelete { additions.remove(atOffsets: $0) }
            Button {
                additions.append(NewIssue())
            } label: {
                Label("加一条问题", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("编辑「\(group)」")
                Spacer()
                Text("\(items.count + additions.count) 条").monospacedDigit()
            }
        } footer: {
            Text("同一行的几条共用一个负责人格子，改了负责人整行都跟着改。新加的接在这个组「本周问题」那一行的最后。")
        }
    }

    private func draft(_ issue: MeetingIssue) -> Binding<MeetingWriteback.Draft> {
        Binding(get: { drafts[issue.id] ?? MeetingWriteback.Draft(issue) },
                set: { drafts[issue.id] = $0 })
    }

    /// 勾「解决了」时进展跟着写成「完成」，取消勾写成「进行中」
    private func resolved(_ issue: MeetingIssue) -> Binding<Bool> {
        Binding(get: { (drafts[issue.id] ?? MeetingWriteback.Draft(issue)).resolved },
                set: { on in
                    var d = drafts[issue.id] ?? MeetingWriteback.Draft(issue)
                    d.resolved = on
                    d.progress = MeetingWriteback.progress(afterToggling: on, current: d.progress)
                    drafts[issue.id] = d
                })
    }

    private func editRow(_ issue: MeetingIssue) -> some View {
        let d = draft(issue)
        let changed = drafts[issue.id].map { $0 != MeetingWriteback.Draft(issue) } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: DS.Space.xs) {
                Circle().fill(changed ? DS.Palette.accent : Color.clear)
                    .overlay(Circle().strokeBorder(DS.Palette.hairline))
                    .frame(width: 7, height: 7).padding(.top, 6)
                TextField("问题", text: d.text, axis: .vertical).font(.subheadline)
                Toggle("解决了", isOn: resolved(issue))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .font(.caption)
                    .tint(DS.Palette.success)
            }
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "person").font(.caption).foregroundStyle(.secondary).frame(width: 16)
                TextField("负责人", text: d.owner).font(.caption)
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Image(systemName: "text.bubble").font(.caption).foregroundStyle(.secondary).frame(width: 16)
                TextField("进展（写进「完成情况」那一列）", text: d.progress, axis: .vertical).font(.caption)
            }
            if issue.source == nil {
                Text("这条是从文字导入的，表格里找不到它的位置，只能改手机上的")
                    .font(.caption2).foregroundStyle(DS.Palette.warning)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 上面：三格 + 组名

    private func overview(issues: [MeetingIssue], matching: [MeetingIssue]) -> some View {
        let inGroup = matching.filter { group == nil || $0.group == group }
        let ofStatus = matching.filter { $0.status == filter.status }
        let groups = groupOrder(issues)
        return Section {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(MeetingFilter.allCases, id: \.self) { f in
                        filterTile(f, count: inGroup.filter { $0.status == f.status }.count)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        groupChip(nil, count: ofStatus.count)
                        ForEach(groups, id: \.self) { name in
                            groupChip(name, count: ofStatus.filter { $0.group == name }.count)
                        }
                    }
                }
                if let date = store.settings.meetingLastImport {
                    Text("文档 \(date.formatted(.dateTime.month().day())) 更新 · 点一条看详情，左滑标解决")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, DS.Space.xxs)
        }
    }

    private func tint(_ f: MeetingFilter) -> Color {
        switch f {
        case .open: return DS.Palette.warning
        case .quiet: return DS.Palette.info
        case .resolved: return DS.Palette.success
        }
    }

    private func filterTile(_ f: MeetingFilter, count: Int) -> some View {
        let selected = filter == f
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { filter = f }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)").font(DS.Font.number).foregroundStyle(count == 0 ? Color.secondary : tint(f))
                Text(f.rawValue).font(DS.Font.caption).foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Space.xs)
            .padding(.horizontal, DS.Space.s)
            .background(selected ? tint(f).opacity(0.16) : DS.Palette.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? tint(f).opacity(0.5) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func groupChip(_ name: String?, count: Int) -> some View {
        let selected = group == name
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { group = name }
        } label: {
            HStack(spacing: 4) {
                Text(name ?? "全部")
                Text("\(count)").monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? DS.Palette.accent : DS.Palette.surfaceSunken, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 列表

    /// 组按文档里的先后（第一次导入时的顺序）
    private func groupOrder(_ issues: [MeetingIssue]) -> [String] {
        var seen = Set<String>()
        return issues.map(\.group).filter { seen.insert($0).inserted }
    }

    private func sections(_ shown: [MeetingIssue], issues: [MeetingIssue]) -> [IssueSection] {
        if byOwner {
            let none = "没写负责人"
            var map: [String: [MeetingIssue]] = [:]
            for issue in shown {
                let names = issue.owners.isEmpty ? [none] : issue.owners
                for name in names { map[name, default: []].append(issue) }
            }
            // 事多的人在前，没写负责人的放最后
            func key(_ section: IssueSection) -> (Int, Int, String) {
                (section.title == none ? 1 : 0, -section.items.count, section.title)
            }
            return map.map { IssueSection(title: $0.key, items: $0.value.sorted(by: meetingOrder)) }
                .sorted { key($0) < key($1) }
        }
        let order = Dictionary(uniqueKeysWithValues: groupOrder(issues).enumerated().map { ($1, $0) })
        return Dictionary(grouping: shown, by: \.group)
            .map { IssueSection(title: $0.key, items: $0.value.sorted(by: meetingOrder)) }
            .sorted { (order[$0.title] ?? .max, $0.title) < (order[$1.title] ?? .max, $1.title) }
    }

    private func matchesQuery(_ issue: MeetingIssue) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [issue.text, issue.group, issue.detail ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    private var emptyText: String {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return "没搜到「\(q)」" }
        switch filter {
        case .open: return "没有没解决的问题"
        case .quiet: return "没有要确认的：上周提的这周都还在文档里"
        case .resolved: return "还没有解决的问题"
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("还没有导入周会文档").font(.headline)
                Text("导入后按组列出各组提的问题。每周和上一周对比：还在提的是没解决，写了完成、上线的是解决了，这周没再提的标出来等你确认。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { showingSource = true } label: {
                    Label("导入周会文档", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, DS.Space.xxs)
        }
    }

    // MARK: - 一条

    /// 第二行的小字：组（按人分时）· 负责人 · 挂了几周 / 本周新提 · 进展
    private func metaLine(_ issue: MeetingIssue, weeks: Int, showGroup: Bool, hasHistory: Bool, compact: Bool) -> Text? {
        var parts: [Text] = []
        if showGroup { parts.append(Text(issue.group).foregroundColor(DS.Palette.accent)) }
        if !issue.owners.isEmpty { parts.append(Text(issue.owners.joined(separator: "、"))) }
        switch issue.status {
        case .open:
            if weeks >= 2 {
                parts.append(Text("第 \(weeks) 周").foregroundColor(ageColor(weeks)))
            } else if hasHistory, issue.firstWeek == week {
                parts.append(Text("本周新提").foregroundColor(DS.Palette.info))
            }
        case .quiet:
            parts.append(Text("这周没再提").foregroundColor(DS.Palette.warning))
        case .resolved:
            if let w = issue.resolvedWeek { parts.append(Text("\(w.month)/\(w.day) 那周解决").foregroundColor(DS.Palette.success)) }
        }
        if compact, let progress = issue.progress { parts.append(Text("进展：" + progress)) }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(" · ") + $1 }
    }

    private func dotColor(_ issue: MeetingIssue, weeks: Int) -> Color {
        switch issue.status {
        case .open: return ageColor(weeks)
        case .quiet: return DS.Palette.info
        case .resolved: return DS.Palette.success
        }
    }

    @ViewBuilder
    private func row(_ issue: MeetingIssue, showGroup: Bool, hasHistory: Bool) -> some View {
        let isExpanded = expanded.contains(issue.id)
        let weeks = issue.weeks(through: week)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: DS.Space.xs) {
                Circle().fill(dotColor(issue, weeks: weeks)).frame(width: 7, height: 7).padding(.top, 6)
                Text(issue.text)
                    .font(.subheadline)
                    .lineLimit(isExpanded ? nil : 2)
                    .strikethrough(issue.status == .resolved)
                    .foregroundStyle(issue.status == .resolved ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Group {
                if let meta = metaLine(issue, weeks: weeks, showGroup: showGroup, hasHistory: hasHistory, compact: !isExpanded) {
                    meta.font(.caption).foregroundColor(.secondary).lineLimit(isExpanded ? nil : 1)
                }
                if isExpanded {
                    details(issue, weeks: weeks)
                } else if issue.status == .quiet {
                    actions(issue)
                }
            }
            .padding(.leading, 15)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded { expanded.remove(issue.id) } else { expanded.insert(issue.id) }
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

    /// 展开后：文档里属于哪一项、进展、什么时候提的，和改状态的按钮
    private func details(_ issue: MeetingIssue, weeks: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let topic = issue.topic { info("文档里", topic) }
            if let progress = issue.progress { info("进展", progress) }
            info("时间", timeline(issue, weeks: weeks))
            actions(issue)
        }
        .padding(.top, 2)
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Text(label).foregroundStyle(.tertiary).frame(width: 40, alignment: .leading)
            Text(value).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }

    private func actions(_ issue: MeetingIssue) -> some View {
        HStack(spacing: DS.Space.xs) {
            switch issue.status {
            case .open:
                Button("标成已解决") { store.setMeetingIssue(issue.id, status: .resolved) }
            case .quiet:
                Button("已解决") { store.setMeetingIssue(issue.id, status: .resolved) }
                Button("还没解决") { store.setMeetingIssue(issue.id, status: .open) }
            case .resolved:
                Button("其实没解决") { store.setMeetingIssue(issue.id, status: .open) }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
    }

    private func timeline(_ issue: MeetingIssue, weeks: Int) -> String {
        let since = "\(issue.firstWeek.month)/\(issue.firstWeek.day) 那周提出"
        let mark = issue.manual ? "（自己标的）" : ""
        switch issue.status {
        case .open:
            return since + "，第 \(weeks) 周还没解决" + mark
        case .quiet:
            return since + "，这周文档里没再提，可能解决了"
        case .resolved:
            let at = issue.resolvedWeek.map { "\($0.month)/\($0.day) 那周解决" } ?? "已解决"
            return since + "，" + at + "，用了 \(weeks) 周" + mark
        }
    }
}

/// 编辑完要写回金山文档的改动
struct PendingMeetingWrite: Identifiable {
    let id = UUID()
    let group: String
    let plan: MeetingWriteback.Plan
    let drafts: [String: MeetingWriteback.Draft]
}

/// 写进金山文档之前给人看：要改哪几格、改成什么
struct MeetingWriteConfirmView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let pending: PendingMeetingWrite
    /// 存好了（写进去了，或者选了只存手机上）
    let saved: () -> Void
    @State private var writing = false
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                ForEach(Array(pending.plan.writes.enumerated()), id: \.offset) { _, write in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(write.summary).font(.subheadline)
                        Text(write.value.isEmpty ? "（清空）" : write.value)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(8)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("要改金山文档里这 \(pending.plan.writes.count) 个格子")
            } footer: {
                Text("写之前会核对：这几格要是有人刚改过，一个都不改，提醒你先下载最新一版。")
            }
            if !pending.plan.skipped.isEmpty {
                Section("只改手机上的") {
                    ForEach(pending.plan.skipped, id: \.self) { Text($0).font(.footnote) }
                }
            }
            if let problem {
                Section {
                    Text(problem).font(.footnote).foregroundStyle(DS.Palette.danger)
                }
            }
            Section {
                Button("不写金山文档，只存在手机上") {
                    store.saveMeetingEdits(drafts: pending.drafts, plan: pending.plan, group: pending.group, written: false)
                    ToastCenter.shared.show("存在手机上了，金山文档里没改", style: .success)
                    saved()
                    dismiss()
                }
                .disabled(writing)
            }
        }
        .appList()
        .navigationTitle("写回金山文档")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(writing)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("返回修改") { dismiss() }.disabled(writing)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(writing ? "写入中…" : "写入") {
                    writing = true
                    problem = nil
                    Task {
                        let result = await store.writeMeeting(plan: pending.plan, drafts: pending.drafts, group: pending.group)
                        writing = false
                        if result.ok {
                            ToastCenter.shared.show(result.message, style: .success)
                            saved()
                            dismiss()
                        } else {
                            problem = result.message
                        }
                    }
                }
                .bold()
                .disabled(writing)
            }
        }
    }
}

/// 导入周会文档：文档链接、登录、自动下载，和手动导入（剪贴板、文件、粘贴）
struct MeetingSourceView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var browsing = false
    @State private var pasting = false
    @State private var pasteText = ""
    @State private var pickingFile = false
    @State private var downloading = false
    @State private var tokenDraft = ""
    @State private var hasToken = false
    @State private var testing = false

    var body: some View {
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
                        finish(result.message)
                    }
                } label: {
                    HStack {
                        Label("现在下载最新一版", systemImage: "arrow.down.circle")
                        if downloading { Spacer(); ProgressView() }
                    }
                }
                .disabled(downloading || !(URL(string: store.settings.meetingDocURL).map(DocDownload.isSupported) ?? false))
            } header: {
                Text("自动下载")
            } footer: {
                Text("第一次点「打开文档」，在里面登录你自己的金山文档账号。之后每周一 App 自己下载这份表格的 Excel 读一遍，读到新的一版就通知你。文档设了禁止下载就下载不了。")
            }

            Section {
                Button {
                    finish(store.importMeetingFromClipboard())
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
            } header: {
                Text("手动导入")
            } footer: {
                Text("在金山文档 App 里全选表格复制，回来点「从剪贴板导入」；或导出成 Excel，用「分享 → 值班提醒」打开。按「分组」一列分组，「完成进展」里 1. 2. 3. 每条算一个问题，「完成情况」写了完成、上线、已解决的算解决了。文档内容只存在这台手机上。")
            }

            writebackSection

            if store.settings.meetingMessage != nil || !store.settings.meetingDownloadLog.isEmpty || store.meetingPageText != nil {
                Section("上次导入") {
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
                }
            }
        }
        .appList()
        .navigationTitle("导入周会文档")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
        .fullScreenCover(isPresented: $browsing) { MeetingDocBrowser() }
        .fileImporter(isPresented: $pickingFile,
                      allowedContentTypes: [UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
                                            .commaSeparatedText, .tabSeparatedText]) { result in
            guard case .success(let url) = result else { return }
            finish(store.importMeetingFile(url))
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
                                pasting = false
                                ToastCenter.shared.show(result, style: AppStore.meetingImportFailed(result) ? .error : .success)
                            }
                            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
        }
    }

    /// 在 App 里改了组里的问题，保存时写进金山文档：周会表格里放一个脚本，App 带着脚本令牌调用它
    private var writebackSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = MeetingWriter.script
                ToastCenter.shared.show("脚本复制好了，去金山文档的脚本编辑器里粘贴", style: .success)
            } label: {
                Label("复制脚本", systemImage: "doc.on.doc")
            }
            DraftTextField("脚本的 webhook 链接", value: store.settings.meetingScriptURL) {
                store.settings.meetingScriptURL = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            SecureField(hasToken ? "脚本令牌（已保存，粘贴新的可替换）" : "脚本令牌", text: $tokenDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(saveToken)
            Button {
                saveToken()
                testing = true
                Task {
                    let result = await store.testMeetingScript()
                    testing = false
                    ToastCenter.shared.show(result.message, style: result.ok ? .success : .error)
                }
            } label: {
                HStack {
                    Label("测试连接", systemImage: "bolt.horizontal")
                    if testing { Spacer(); ProgressView() }
                }
            }
            .disabled(testing || store.settings.meetingScriptURL.isEmpty)
            if hasToken {
                Button("删除脚本令牌", role: .destructive) {
                    Keychain.set("", for: .kdocsScriptToken)
                    hasToken = false
                }
            }
            if !store.settings.meetingWriteLog.isEmpty {
                NavigationLink("查看写回记录") {
                    List(Array(store.settings.meetingWriteLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.footnote).textSelection(.enabled)
                    }
                    .appList()
                    .navigationTitle("写回记录")
                }
            }
        } header: {
            Text("写回金山文档")
        } footer: {
            Text("在「周会问题」里点组名旁边的「编辑」，改完保存就写进周会表格。要有这份表格的编辑权限，第一次用电脑设置：\n1. 点「复制脚本」，发到电脑上。\n2. 电脑上用金山文档打开周会表格，菜单「效率 → 高级开发 → AirScript 脚本编辑器」，新建一个脚本，把复制的内容整段粘贴进去，保存。\n3. 在这个脚本的「…」菜单里复制「webhook 链接」，填到上面。\n4. 在脚本编辑器里点「脚本令牌」生成一个，填到上面，点「测试连接」。\n脚本存在这份表格里，能编辑表格的人都看得到；令牌只存在这台手机的钥匙串里。菜单的名字以金山文档为准。")
        }
        .onAppear { hasToken = !(Keychain.get(.kdocsScriptToken) ?? "").isEmpty }
    }

    private func saveToken() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        Keychain.set(token, for: .kdocsScriptToken)
        tokenDraft = ""
        hasToken = true
    }

    /// 导入成功就回到问题列表看结果
    private func finish(_ message: String) {
        let failed = AppStore.meetingImportFailed(message)
        ToastCenter.shared.show(message, style: failed ? .error : .success)
        if !failed { dismiss() }
    }
}

/// App 里打开周会文档（第一次在这里登录金山文档），点「读取文档」导入
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
