import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 发数传计划这一次的状态：读到的计划、哪几家已经发了。只在内存里（离开这一页再回来还在，关掉 App 就没了）
struct PassPlanSession: Equatable {
    var rows: [PassPlanRow] = []
    var sent: Set<String> = []
}

/// 发数传计划：对着电脑屏幕拍计划（系统文档扫描自动框出屏幕、扶正，长的可以连拍几张），
/// 按运营商（地面站「-」前面的名字）分开，每家生成一张清楚的表格图 / 一段文字，发到那家的微信群。
/// 读出来的东西不存、不上传
struct PassPlanView: View {
    @EnvironmentObject private var store: AppStore
    /// 打开时带进来的计划（分享过来的 Excel、截图演示）
    private let initialRows: [PassPlanRow]
    /// 从快捷指令「拍数传计划」打开：直接进扫描
    private let autoScan: Bool
    @State private var reading = false
    @State private var problem: String?
    @State private var scanning = false
    @State private var showingCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var editing: EditingRow?
    @State private var naming: String?
    @State private var groupName = ""
    /// 给这个站新建一家运营商
    @State private var newOperatorFor: String?
    @State private var newOperatorName = ""
    /// 每家的图（读完、改完重新画）
    @State private var images: [String: UIImage] = [:]

    private struct EditingRow: Identifiable {
        let id = UUID()
        var index: Int?
        var row: PassPlanRow
    }

    init(rows: [PassPlanRow] = [], autoScan: Bool = false) {
        initialRows = rows
        self.autoScan = autoScan
    }

    private var rows: [PassPlanRow] { store.passPlan.rows }
    /// 运营商对照表（没填名字的那行不算）
    private var rules: [PassPlan.OperatorRule] { store.settings.passPlanOperators.filter { !$0.name.isEmpty } }
    /// 分得出是哪家的（能发的）
    private var sendable: [(name: String, rows: [PassPlanRow])] {
        PassPlan.grouped(rows, rules: rules).filter { $0.name != PassPlan.unassigned }
    }

    var body: some View {
        let all = PassPlan.grouped(rows, rules: rules)
        let groups = all.filter { $0.name != PassPlan.unassigned }
        let doubtful = rows.filter { !PassPlan.problems($0, rules: rules).isEmpty }.count
        let idle = PassPlan.idle(rows, rules: rules)
        List {
            Section {
                Button { if DocumentScanner.isSupported { scanning = true } else { showingCamera = true } } label: {
                    Label("拍计划", systemImage: "doc.viewfinder").font(.headline)
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                    Label("从相册选（可以选几张）", systemImage: "photo.on.rectangle")
                }
                DisclosureGroup("其他方式") {
                    Button { showingCamera = true } label: { Label("普通拍照", systemImage: "camera") }
                    Button { importing = true } label: { Label("导入 Excel", systemImage: "tablecells") }
                    Button { read { try PlanReader.rowsFromClipboard() } } label: {
                        Label("粘贴复制的表格", systemImage: "doc.on.clipboard")
                    }
                }
                if reading {
                    HStack(spacing: DS.Space.xs) { DSSpinner(size: 14); Text("正在认…").foregroundStyle(.secondary) }
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(DS.Palette.danger)
                }
            } footer: {
                Text("对着电脑屏幕拍，会自动框出屏幕、扶正；表头那一行要拍进去，计划长就往下翻着连拍几张，会合成一份。照片和计划不存、不上传。")
            }
            if !rows.isEmpty {
                Section {
                    LabeledContent("一共", value: "\(rows.count) 条，\(groups.count) 家")
                    LabeledContent("已经发了", value: "\(groups.filter { store.passPlan.sent.contains($0.name) }.count) / \(groups.count) 家")
                    if doubtful > 0 {
                        Label("有 \(doubtful) 条可能认错了（标黄的），点开核对一下", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(DS.Palette.warning)
                    }
                    let lostCount = all.first { $0.name == PassPlan.unassigned }?.rows.count ?? 0
                    if lostCount > 0 {
                        Label("有 \(lostCount) 条分不出是哪家（在下面最上面），点「分给哪家」记下来，记一次以后自动分",
                              systemImage: "questionmark.circle.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(DS.Palette.warning)
                    }
                    if rules.isEmpty {
                        Text("还没填运营商对照表，现在先按站名「-」前面的名字分。到下面「运营商对照表」里粘贴导入一次就准了。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !idle.isEmpty {
                        Text("今天没有计划：\(idle.joined(separator: "、"))").font(.footnote).foregroundStyle(.secondary)
                    }
                    let unsent = groups.map(\.name).filter { !store.passPlan.sent.contains($0) }
                    if !unsent.isEmpty {
                        Button { sendInTurn(unsent) } label: {
                            Label(unsent.count == groups.count ? "依次发给各家（\(unsent.count) 家）" : "接着发剩下的 \(unsent.count) 家",
                                  systemImage: "paperplane.fill")
                                .font(.headline)
                        }
                        .disabled(images.count < groups.count)
                    }
                } footer: {
                    Text("依次发：发完一家自动弹出下一家，分享面板最上面写着这次发给谁、该选哪个群。")
                }
                // 分不出是哪家的放最上面：先分好再发
                if let lost = all.first(where: { $0.name == PassPlan.unassigned }) {
                    unassignedSection(lost.rows, known: groups.map(\.name))
                }
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.rows, id: \.self) { row in
                            rowButton(row)
                        }
                        sendButtons(group.name, rows: group.rows)
                    } header: {
                        header(group.name, count: group.rows.count)
                    }
                }
                Section {
                    Button { editing = EditingRow(index: nil, row: PassPlanRow()) } label: {
                        Label("补一条", systemImage: "plus")
                    }
                    Button("全部清掉", role: .destructive) { store.passPlan = PassPlanSession(); problem = nil }
                }
            }
            Section {
                NavigationLink {
                    PassPlanOperatorsView()
                } label: {
                    LabeledContent("运营商对照表", value: rules.isEmpty ? "还没填" : "\(rules.count) 家")
                }
                Toggle("每天提醒发计划", isOn: $store.settings.passPlanReminder)
                if store.settings.passPlanReminder {
                    DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("到点提醒一次，点提醒直接打开这一页；那天各家都发完了就不再提醒。也可以在「快捷指令」里把「拍数传计划」设成轻点两下手机背面（设置 › 辅助功能 › 触控 › 轻点背面），一下就进扫描。")
            }
        }
        .appList()
        .navigationTitle("发数传计划")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { pages in read { try await PlanReader.rows(inPages: pages) } }
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in read { try await PlanReader.rows(inPages: [image]) } }
                .ignoresSafeArea()
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            photoItems = []
            read {
                var pages: [UIImage] = []
                for item in items {
                    if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        pages.append(image)
                    }
                }
                return try await PlanReader.rows(inPages: pages)
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data, .commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            read { try PlanReader.rows(inFile: url) }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                PassPlanRowEditor(row: target.row, isNew: target.index == nil) { saved in
                    if let i = target.index, store.passPlan.rows.indices.contains(i) {
                        if let saved { store.passPlan.rows[i] = saved } else { store.passPlan.rows.remove(at: i) }
                    } else if let saved {
                        store.passPlan.rows.append(saved)
                    }
                }
            }
        }
        .alert("新的一家运营商", isPresented: Binding(get: { newOperatorFor != nil }, set: { if !$0 { newOperatorFor = nil } })) {
            TextField("运营商名字", text: $newOperatorName)
            Button("好") {
                let name = newOperatorName.trimmingCharacters(in: .whitespaces)
                if let station = newOperatorFor, !name.isEmpty { assign(station, to: name) }
                newOperatorFor = nil
            }
            Button("取消", role: .cancel) { newOperatorFor = nil }
        } message: {
            Text("「\(newOperatorFor.map(PassPlan.suggestedPrefix(of:)) ?? "")」开头的站以后都算这一家")
        }
        .alert("\(naming ?? "")的计划发到哪个群", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("群名（只是给自己看的提示）", text: $groupName)
            Button("好") {
                if let name = naming {
                    let trimmed = groupName.trimmingCharacters(in: .whitespaces)
                    store.settings.passPlanGroups[name] = trimmed.isEmpty ? nil : trimmed
                }
                naming = nil
            }
            Button("取消", role: .cancel) { naming = nil }
        } message: {
            Text("微信不让别的 App 直接发到群里：点「发图片」以后在微信里选这个群。记下来按钮上就写着该发哪个群。")
        }
        .onAppear {
            if !initialRows.isEmpty { store.passPlan = PassPlanSession(rows: initialRows) }
            if autoScan {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if DocumentScanner.isSupported { scanning = true } else { showingCamera = true }
                }
            }
        }
        .task(id: "\(rows.hashValue)-\(rules.hashValue)") { renderImages() }
    }

    // MARK: - 一家的标题、一行

    private func rowButton(_ row: PassPlanRow) -> some View {
        Button { edit(row) } label: { rowView(row) }
            .buttonStyle(.plain)
            // 可能认错的标黄
            .listRowBackground(PassPlan.problems(row, rules: rules).isEmpty ? nil : DS.Palette.warning.opacity(0.12))
            .swipeActions {
                Button("删掉", role: .destructive) { store.passPlan.rows.removeAll { $0 == row } }
            }
    }

    /// 分不出是哪家的：每个站点一下「分给哪家」，记进对照表，以后自动分
    private func unassignedSection(_ rows: [PassPlanRow], known: [String]) -> some View {
        let stations = Array(Set(rows.map(\.station))).sorted()
        let names = (rules.map(\.name) + known).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return Section {
            ForEach(stations, id: \.self) { station in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station).font(.subheadline.weight(.medium))
                        Text("\(rows.filter { $0.station == station }.count) 条").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(names, id: \.self) { name in
                            Button(name) { assign(station, to: name) }
                        }
                        Button {
                            newOperatorName = ""
                            newOperatorFor = station
                        } label: {
                            Label("新的一家…", systemImage: "plus")
                        }
                    } label: {
                        Label("分给哪家", systemImage: "arrow.turn.down.right")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            ForEach(rows, id: \.self) { row in rowButton(row) }
        } header: {
            Label("\(PassPlan.unassigned) · \(rows.count) 条", systemImage: "questionmark.circle.fill")
                .foregroundStyle(DS.Palette.warning)
        } footer: {
            Text("运营商对照表里没有这些站，没法发。点「分给哪家」记下来（记的是站名开头，比如「\(PassPlan.suggestedPrefix(of: stations.first ?? ""))」），以后同样开头的站自动分过去；记错了到「运营商对照表」里改。也可能是站名认错了字：点下面那一行改。")
        }
    }

    private func header(_ name: String, count: Int) -> some View {
        HStack {
            Text("\(name) · \(count) 条")
            if store.passPlan.sent.contains(name) {
                Label("已发", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(DS.Palette.success)
            }
            Spacer()
            Button {
                groupName = store.settings.passPlanGroups[name] ?? ""
                naming = name
            } label: {
                Label(store.settings.passPlanGroups[name].map { "发到：\($0)" } ?? "记一下发哪个群", systemImage: "person.3")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
    }

    private func rowView(_ row: PassPlanRow) -> some View {
        let problems = PassPlan.problems(row, rules: rules)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text([PassPlan.shortTime(row.start), PassPlan.shortTime(row.end)].filter { !$0.isEmpty }.joined(separator: "–"))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Spacer()
                Text(row.satellite.isEmpty ? row.satelliteID : row.satellite).font(.subheadline)
            }
            Text([row.station, row.orbit.isEmpty ? "" : "圈号 \(row.orbit)", row.satelliteID, row.info]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if !problems.isEmpty {
                Label(problems.joined(separator: "；"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(DS.Palette.warning)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func sendButtons(_ name: String, rows: [PassPlanRow]) -> some View {
        let target = store.settings.passPlanGroups[name]
        let sent = store.passPlan.sent.contains(name)
        return HStack(spacing: DS.Space.s) {
            Button {
                guard let image = images[name] else { return }
                share(image, name: name)
            } label: {
                Label(sent ? "再发一次图片" : (target.map { "发图片到\($0)" } ?? "发图片"), systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(sent ? DS.Palette.success : DS.Palette.accent)
            .disabled(images[name] == nil)
            Button { share(PassPlan.message(name: name, rows: rows), name: name) } label: {
                Label("发文字", systemImage: "text.alignleft").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline.weight(.medium))
        .padding(.vertical, DS.Space.xxs)
    }

    // MARK: - 读、改、发

    private func read(_ work: @escaping @MainActor () async throws -> [PassPlanRow]) {
        reading = true
        problem = nil
        Task {
            do {
                let found = try await work()
                withAnimation { store.passPlan = PassPlanSession(rows: found) }
                let doubtful = found.filter { !PassPlan.problems($0, rules: rules).isEmpty }.count
                let grouped = PassPlan.grouped(found, rules: rules)
                let lost = grouped.first { $0.name == PassPlan.unassigned }?.rows.count ?? 0
                let families = grouped.filter { $0.name != PassPlan.unassigned }.count
                var message = "认出 \(found.count) 条，分成 \(families) 家"
                if lost > 0 { message += "；\(lost) 条分不出是哪家，在最上面" } else if doubtful > 0 { message += "，\(doubtful) 条要核对" }
                ToastCenter.shared.show(message, style: doubtful > 0 || lost > 0 ? .warning : .success)
            } catch {
                problem = error.localizedDescription
            }
            reading = false
        }
    }

    private func edit(_ row: PassPlanRow) {
        editing = EditingRow(index: rows.firstIndex(of: row), row: row)
    }

    /// 发出去（在微信里选群）；真的发了就标「已发」。then：发出去以后接着做（依次发下一家）
    private func share(_ item: Any, name: String, then next: (@MainActor () -> Void)? = nil) {
        let target = store.settings.passPlanGroups[name].map { " → 发到「\($0)」" } ?? ""
        let payload = SharePayload(item, title: "\(name)数传计划\(target)", preview: images[name])
        ActivityShare.present([payload]) { completed in
            guard completed else { return }
            markSent(name)
            next?()
        }
    }

    /// 从第一家开始，发完一家弹下一家；中途取消就停下
    private func sendInTurn(_ names: [String]) {
        guard let name = names.first, let image = images[name] else { return }
        share(image, name: name) {
            let rest = Array(names.dropFirst())
            guard !rest.isEmpty else { return }
            // 等上一个分享面板收起来
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { sendInTurn(rest) }
        }
    }

    /// 这个站（的开头）记到某一家的对照表里
    private func assign(_ station: String, to name: String) {
        let prefix = PassPlan.suggestedPrefix(of: station)
        if let i = store.settings.passPlanOperators.firstIndex(where: { $0.name == name }) {
            if !store.settings.passPlanOperators[i].prefixes.contains(prefix) {
                store.settings.passPlanOperators[i].prefixes.append(prefix)
            }
        } else {
            store.settings.passPlanOperators.append(PassPlan.OperatorRule(name: name, prefixes: [prefix]))
        }
        ToastCenter.shared.show("以后「\(prefix)」开头的站都算\(name)", style: .success)
    }

    private func markSent(_ name: String) {
        store.passPlan.sent.insert(name)
        let all = Set(sendable.map(\.name))
        guard !all.isEmpty, all.isSubset(of: store.passPlan.sent) else { return }
        // 各家都发了：今天不再提醒
        ToastCenter.shared.show("各家都发了", style: .success)
        store.settings.passPlanSentDay = .today
        Task { await store.schedulePlanReminder() }
    }

    /// 提醒时间（DatePicker 用 Date）
    private var reminderTime: Binding<Date> {
        Binding(get: {
            let t = store.settings.passPlanReminderTime
            return DayKey.today.date(calendar: .current, hour: t.hour, minute: t.minute)
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.settings.passPlanReminderTime = ClockTime(hour: c.hour ?? 15, minute: c.minute ?? 0)
        })
    }

    private func renderImages() {
        var made: [String: UIImage] = [:]
        for group in sendable {
            let renderer = ImageRenderer(content: PassPlanSheet(name: group.name, rows: group.rows))
            renderer.scale = 3
            if let image = renderer.uiImage { made[group.name] = image }
        }
        images = made
    }
}

/// 发到群里的那张图：白底表格，深色模式下也是白底（群里大家看着一样）
struct PassPlanSheet: View {
    let name: String
    let rows: [PassPlanRow]

    var body: some View {
        let title = PassPlan.message(name: name, rows: rows).components(separatedBy: "\n").first ?? name
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 20, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    ForEach(["序号", "开始", "结束", "卫星", "圈号", "地面站", "数传信息"], id: \.self) {
                        Text($0).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.4))
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        Text("\(i + 1)")
                        Text(PassPlan.shortTime(row.start)).monospacedDigit().fontWeight(.semibold)
                        Text(PassPlan.shortTime(row.end)).monospacedDigit()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.satellite.isEmpty ? row.satelliteID : row.satellite)
                            if !row.satellite.isEmpty, !row.satelliteID.isEmpty {
                                Text(row.satelliteID).font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                            }
                        }
                        Text(row.orbit).monospacedDigit()
                        Text(row.station)
                        Text(row.info).font(.system(size: 12))
                    }
                    .font(.system(size: 14))
                }
            }
        }
        .foregroundStyle(Color.black)
        .padding(20)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// 改一条（认错的字、漏的一条）
struct PassPlanRowEditor: View {
    @State var row: PassPlanRow
    let isNew: Bool
    var onDone: (PassPlanRow?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("卫星名称", text: $row.satellite)
                TextField("卫星 ID", text: $row.satelliteID)
                TextField("圈号", text: $row.orbit).keyboardType(.numberPad)
                TextField("地面站（运营商-站名）", text: $row.station)
            }
            Section {
                TextField("开始时间", text: $row.start)
                TextField("结束时间", text: $row.end)
                TextField("数传信息", text: $row.info)
                TextField("状态", text: $row.status)
            } footer: {
                Text("时间写成 2026-10-27 22:57:51 这样")
            }
            if !isNew {
                Section {
                    Button("删掉这一条", role: .destructive) { onDone(nil); dismiss() }
                }
            }
        }
        .navigationTitle(isNew ? "补一条" : "改这一条")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("好") {
                    row.start = PassPlan.normalizedTime(row.start)
                    row.end = PassPlan.normalizedTime(row.end)
                    onDone(row)
                    dismiss()
                }
                .disabled(row.station.isEmpty || (row.satellite.isEmpty && row.satelliteID.isEmpty))
            }
        }
    }
}

extension PassPlanView {
    /// 截图、演示用（虚构）
    static var demoRows: [PassPlanRow] {
        let day = DayKey.today.description
        return [
            PassPlanRow(orbit: "1201", satelliteID: "SAT-A1", satellite: "试验一号", station: "甲站-北区01",
                        start: "\(day) 08:12:30", end: "\(day) 08:20:05", info: "通道1：900M", status: "等待数传"),
            PassPlanRow(orbit: "1202", satelliteID: "SAT-A1", satellite: "试验一号", station: "乙站-东区02",
                        start: "\(day) 09:48:10", end: "\(day) 09:55:42", info: "通道1：900M，通道2：900M", status: "等待数传"),
            PassPlanRow(orbit: "873", satelliteID: "SAT-B2", satellite: "试验二号", station: "甲站-北区05",
                        start: "\(day) 13:05:51", end: "\(day) 13:13:03", info: "通道2：900M", status: "等待数传"),
            PassPlanRow(orbit: "874", satelliteID: "SAT-B2", satellite: "试验二号", station: "丙站-西区01",
                        start: "\(day) 20:31:27", end: "\(day) 20:39:03", info: "通道1：900M", status: "等待数传"),
            PassPlanRow(orbit: "875", satelliteID: "SAT-B2", satellite: "试验二号", station: "丁光北区02",
                        start: "\(day) 22:04:27", end: "\(day) 22:11:21", info: "通道1：900M", status: "等待数传"),
        ]
    }
}
