import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 发数传计划这一次的状态：读到的计划、哪几家已经发了。只在内存里（离开这一页再回来还在，关掉 App 就没了）
struct PassPlanSession: Equatable {
    var rows: [PassPlanRow] = []
    /// 读到的那张表的列（发出去的表照它）；补的、演示的是 nil，用默认的列
    var layout: PassPlan.Layout?
    var sent: Set<String> = []
}

/// 发数传计划：对着电脑屏幕拍计划（系统文档扫描自动框出屏幕、扶正，长的可以连拍几张），
/// 按运营商（地面站「-」前面的名字）分开，每家生成一张清楚的表格图 / 一段文字，发到那家的微信群。
/// 读出来的东西不存、不上传
struct PassPlanView: View {
    @EnvironmentObject private var store: AppStore
    /// 打开时带进来的计划（分享过来的 Excel、截图演示）
    private let initial: PassPlan.Reading?
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

    init(reading: PassPlan.Reading? = nil, autoScan: Bool = false) {
        initial = reading
        self.autoScan = autoScan
    }

    private var rows: [PassPlanRow] { store.passPlan.rows }
    private var layout: PassPlan.Layout? { store.passPlan.layout }
    /// 运营商对照表（没填名字的那行不算）
    private var rules: [PassPlan.OperatorRule] { store.settings.passPlanOperators.filter { !$0.name.isEmpty } }
    /// 图下面那句话（这一家有应急计划就是「……应急计划优先推送」）
    private func caption(_ rows: [PassPlanRow]) -> String {
        PassPlan.caption(rows, layout: layout, normal: store.settings.passPlanCaption, urgent: store.settings.passPlanUrgentCaption)
    }

    /// 分得出是哪家的（能发的）
    private var sendable: [(name: String, rows: [PassPlanRow])] {
        PassPlan.grouped(rows, rules: rules).filter { $0.name != PassPlan.unassigned }
    }

    var body: some View {
        let all = PassPlan.grouped(rows, rules: rules)
        let groups = all.filter { $0.name != PassPlan.unassigned }
        let doubtful = rows.filter { !PassPlan.problems($0, rules: rules, layout: layout).isEmpty }.count
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
                    Button { read { try PlanReader.readClipboard() } } label: {
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
                    Text("依次发：点一下从第一家开始，发完一家自动弹出下一家，面板最上面写着这次发给谁、该选哪个群。每家在面板里点：微信 → 发送给朋友 → 选群 → 发送。微信不让别的 App 替你选群、替你发，这几下省不掉；面板里用不上的隔空投送、信息、邮件已经拿掉，微信在前面，每次点同一个位置。")
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
                        header(group.name, count: group.rows.count,
                               urgent: group.rows.contains { PassPlan.emergency($0, layout: layout) == true })
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("图片下面那句话").font(.caption).foregroundStyle(.secondary)
                    TextField("没有应急计划时", text: $store.settings.passPlanCaption)
                    TextField("有应急计划时（「是否应急」认出「是」）", text: $store.settings.passPlanUrgentCaption)
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
            DocumentScanner { pages in read { try await PlanReader.read(pages: pages) } }
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in read { try await PlanReader.read(pages: [image]) } }
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
                return try await PlanReader.read(pages: pages)
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data, .commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            read { try PlanReader.read(file: url) }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                PassPlanRowEditor(row: target.row, layout: layout, isNew: target.index == nil) { saved in
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
            if let initial, !initial.rows.isEmpty { store.passPlan = PassPlanSession(rows: initial.rows, layout: initial.layout) }
            if autoScan {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if DocumentScanner.isSupported { scanning = true } else { showingCamera = true }
                }
            }
        }
        .task(id: "\(rows.hashValue)-\(rules.hashValue)-\(layout?.slots.map(\.label).joined() ?? "")-\(store.settings.passPlanCaption)-\(store.settings.passPlanUrgentCaption)") {
            renderImages()
        }
    }

    // MARK: - 一家的标题、一行

    private func rowButton(_ row: PassPlanRow) -> some View {
        Button { edit(row) } label: { rowView(row) }
            .buttonStyle(.plain)
            // 可能认错的标黄
            .listRowBackground(PassPlan.problems(row, rules: rules, layout: layout).isEmpty ? nil : DS.Palette.warning.opacity(0.12))
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

    private func header(_ name: String, count: Int, urgent: Bool = false) -> some View {
        HStack {
            Text("\(name) · \(count) 条")
            if urgent {
                Text("应急").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(DS.Palette.danger, in: Capsule())
            }
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
        let problems = PassPlan.problems(row, rules: rules, layout: layout)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text([PassPlan.shortTime(row.start), PassPlan.shortTime(row.end)].filter { !$0.isEmpty }.joined(separator: "–"))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                if PassPlan.emergency(row, layout: layout) == true {
                    Text("应急").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.danger)
                }
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
            Button { share(PassPlan.message(name: name, rows: rows, layout: layout, caption: caption(rows)), name: name) } label: {
                Label("发文字", systemImage: "text.alignleft").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline.weight(.medium))
        .padding(.vertical, DS.Space.xxs)
    }

    // MARK: - 读、改、发

    private func read(_ work: @escaping @MainActor () async throws -> PassPlan.Reading) {
        reading = true
        problem = nil
        Task {
            do {
                let result = try await work()
                let found = result.rows
                withAnimation { store.passPlan = PassPlanSession(rows: found, layout: result.layout) }
                let doubtful = found.filter { !PassPlan.problems($0, rules: rules, layout: result.layout).isEmpty }.count
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
        ActivityShare.present([payload], excluding: ActivityShare.chatOnly) { completed in
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
            let renderer = ImageRenderer(content: PassPlanSheet(name: group.name, rows: group.rows, layout: layout,
                                                                caption: caption(group.rows)))
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
    var layout: PassPlan.Layout?
    /// 表下面那一行字（「麻烦确认一下数传计划」）
    var caption = ""

    /// 「是否应急」在表里是第几列（前面多了一列 No.）
    private var urgentColumn: Int? {
        layout?.emergencyIndex.map { index in
            1 + (layout?.slots.prefix(index).filter { $0.column != .number }.count ?? 0)
        }
    }

    /// 和网页上的表一样：同样的表头、列的先后、行的先后，时间写全；居中、每行一条细线
    var body: some View {
        let table = PassPlan.table(rows, layout: layout)
        VStack(alignment: .leading, spacing: 12) {
            Text(PassPlan.title(name: name, rows: rows)).font(.system(size: 20, weight: .bold))
            Grid(alignment: .center, horizontalSpacing: 18, verticalSpacing: 0) {
                // 间距加在每一格上（GridRow 本身加修饰会打乱对齐）
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        Text(header).font(.system(size: 14, weight: .semibold)).padding(.vertical, 10)
                    }
                }
                ForEach(Array(table.cells.enumerated()), id: \.offset) { _, cells in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { c, cell in
                            // 「是否应急」是「是」的那一格标红
                            let urgent = c == urgentColumn && cell.filter { !$0.isWhitespace } == "是"
                            Text(cell).font(.system(size: 14, weight: urgent ? .bold : .regular)).monospacedDigit()
                                .foregroundStyle(urgent ? Color.red : Color.black)
                                .padding(.vertical, 10)
                        }
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
            }
            if !caption.isEmpty {
                Text(caption).font(.system(size: 18, weight: .semibold)).padding(.top, 4)
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
    @State private var row: PassPlanRow
    /// 读到的那张表的列：认不出含义的列（是否应急、创建时间……）也能改
    private let layout: PassPlan.Layout?
    let isNew: Bool
    var onDone: (PassPlanRow?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(row: PassPlanRow, layout: PassPlan.Layout?, isNew: Bool, onDone: @escaping (PassPlanRow?) -> Void) {
        var r = row
        if let layout, r.cells.count < layout.slots.count {
            r.cells += Array(repeating: "", count: layout.slots.count - r.cells.count)
        }
        _row = State(initialValue: r)
        self.layout = layout
        self.isNew = isNew
        self.onDone = onDone
    }

    /// 只有原表里才有、App 认不出含义的那几列
    private var otherColumns: [Int] {
        guard let layout else { return [] }
        return layout.slots.indices.filter { layout.slots[$0].column == nil }
    }

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
            if let layout, !otherColumns.isEmpty {
                Section {
                    ForEach(otherColumns, id: \.self) { i in
                        TextField(layout.slots[i].label, text: $row.cells[i])
                    }
                } footer: {
                    Text("「是否应急」写「是」或「不是」：哪家有「是」，图下面就写「应急计划优先推送」。")
                }
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
