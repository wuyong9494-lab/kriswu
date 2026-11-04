import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 发数传计划这一次的状态：读到的计划、哪几家已经发了。只在内存里（离开这一页再回来还在，关掉 App 就没了）
struct PassPlanSession: Equatable {
    /// 每次读取都是一批新原图；发出状态不参与图片是否过期的判断。
    var sourceID = UUID()
    var fromPhotos = false
    var rows: [PassPlanRow] = []
    /// 读到的那张表的列（发出去的表照它）；补的、演示的是 nil，用默认的列
    var layout: PassPlan.Layout?
    var sent: Set<String> = []
    /// 发原图用：表头那一条在照片里的位置，和每一条（表头、每一行）从照片上裁下来的图
    var header: PassPlan.Region?
    var strips: [PassPlan.Region: Data] = [:]
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
    @State private var entryState = PassPlanEntryState()
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
    @State private var renderedInput: RenderInput?
    @State private var clearing = false
    @State private var reviewRow: PassPlanRow?
    @State private var reviewMessage = ""
    @State private var showingReview = false

    private struct RenderInput: Equatable {
        var sourceID: UUID
        var rows: [PassPlanRow]
        var layout: PassPlan.Layout?
        var rules: [PassPlan.OperatorRule]
        var normalCaption: String
        var urgentCaption: String
        var original: Bool
        var skipped: [String]
    }

    private struct EditingRow: Identifiable {
        let id = UUID()
        var sourceID: UUID
        var index: Int?
        var row: PassPlanRow
        var sourceImage: UIImage?
        var sourceHeader: UIImage?
    }

    init(reading: PassPlan.Reading? = nil, autoScan: Bool = false) {
        initial = reading
        self.autoScan = autoScan
    }

    private var rows: [PassPlanRow] { store.passPlan.rows }
    private var layout: PassPlan.Layout? { store.passPlan.layout }
    /// 运营商对照表（没填名字的那行不算）
    private var rules: [PassPlan.OperatorRule] { store.settings.passPlanOperators.filter { !$0.name.isEmpty } }
    private var renderInput: RenderInput {
        RenderInput(sourceID: store.passPlan.sourceID, rows: rows, layout: layout, rules: rules,
                    normalCaption: store.settings.passPlanCaption, urgentCaption: store.settings.passPlanUrgentCaption,
                    original: store.settings.passPlanOriginal, skipped: store.settings.passPlanSkipped)
    }
    private var imagesAreCurrent: Bool { !reading && renderedInput == renderInput }
    /// 图下面那句话（这一家有应急计划就是「……应急计划优先推送」）
    private func caption(_ rows: [PassPlanRow]) -> String {
        PassPlan.caption(rows, layout: layout, normal: store.settings.passPlanCaption, urgent: store.settings.passPlanUrgentCaption)
    }

    /// 分得出是哪家、要发的（标了「不用发」的不算）
    private var sendable: [(name: String, rows: [PassPlanRow])] {
        let skipped = Set(store.settings.passPlanSkipped)
        return PassPlan.grouped(rows, rules: rules).filter { $0.name != PassPlan.unassigned && !skipped.contains($0.name) }
    }

    private typealias OperatorGroup = (name: String, rows: [PassPlanRow])

    private struct GroupedPlans {
        var all: [OperatorGroup]
        var sendable: [OperatorGroup]
        var resting: [OperatorGroup]
        var excluded: Int
        var doubtful: Int
        var idle: [String]
    }

    private var groupedPlans: GroupedPlans {
        let all = PassPlan.grouped(rows, rules: rules)
        let skipped = Set(store.settings.passPlanSkipped)
        let groups = all.filter { $0.name != PassPlan.unassigned && !skipped.contains($0.name) }
        // 标了「不用发」的几家（长春站这种）：收在最下面，不算在依次发、已发里。
        let resting = all.filter { skipped.contains($0.name) }
        let doubtful = all.filter { !skipped.contains($0.name) }.flatMap(\.rows)
            .filter { !PassPlan.problems($0, rules: rules, layout: layout).isEmpty }.count
        return GroupedPlans(all: all, sendable: groups, resting: resting,
                            excluded: rows.filter(PassPlan.isExcludedFromSending).count, doubtful: doubtful,
                            idle: PassPlan.idle(rows, rules: rules))
    }

    var body: some View {
        namingContent
            .onAppear(perform: prepareOnAppear)
            .onChange(of: initial) { _ in prepareOnAppear() }
            .onChange(of: autoScan) { _ in prepareOnAppear() }
            .task(id: renderInput) { renderImages() }
    }

    // MARK: - 页面分区

    private var planList: some View {
        let grouped = groupedPlans
        return List {
            scannerSection
            if !rows.isEmpty {
                summarySection(grouped)
                planSections(grouped)
                addPlanSection
            }
            settingsSection
        }
    }

    private var scannerSection: some View {
        Section {
            Button { if DocumentScanner.isSupported { scanning = true } else { showingCamera = true } } label: {
                Label("拍计划", systemImage: "doc.viewfinder").font(.headline)
            }
            .disabled(reading)
            PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                Label("从相册选（可以选几张）", systemImage: "photo.on.rectangle")
            }
            .disabled(reading)
            DisclosureGroup("其他方式") {
                Button { showingCamera = true } label: { Label("普通拍照", systemImage: "camera") }
                Button { importing = true } label: { Label("导入 Excel", systemImage: "tablecells") }
                Button { read { try PlanReader.readClipboard() } } label: {
                    Label("粘贴复制的表格", systemImage: "doc.on.clipboard")
                }
            }
            .disabled(reading)
            if reading {
                HStack(spacing: DS.Space.xs) { DSSpinner(size: 14); Text("正在认…").foregroundStyle(.secondary) }
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(DS.Palette.danger)
            }
        } footer: {
            Text("对着电脑屏幕拍，会自动框出屏幕、扶正；表头那一行要拍进去，计划长就往下翻着连拍几张，会合成一份。照片和计划不存、不上传。")
        }
    }

    private func summarySection(_ grouped: GroupedPlans) -> some View {
        let groups = grouped.sendable
        let lostCount = grouped.all.first { $0.name == PassPlan.unassigned }?.rows.count ?? 0
        return Section {
            LabeledContent("一共", value: "\(rows.count) 条，\(groups.count) 家")
            LabeledContent("已经发了", value: "\(groups.filter { store.passPlan.sent.contains($0.name) }.count) / \(groups.count) 家")
            if grouped.excluded > 0 {
                Label("已排除 \(grouped.excluded) 条 test，不发送给任何一家", systemImage: "nosign")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if grouped.doubtful > 0 {
                Label("有 \(grouped.doubtful) 条可能认错了（标黄的），点开核对一下", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(DS.Palette.warning)
            }
            if lostCount > 0 {
                Label("有 \(lostCount) 条分不出是哪家（在下面最上面），点「分给哪家」记下来，记一次以后自动分",
                      systemImage: "questionmark.circle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(DS.Palette.warning)
            }
            if rules.isEmpty {
                Text("还没填运营商对照表，现在先按站名「-」前面的名字分。到下面「运营商对照表」里粘贴导入一次就准了。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !grouped.idle.isEmpty {
                Text("没有可发送计划：\(grouped.idle.joined(separator: "、"))").font(.footnote).foregroundStyle(.secondary)
            }
            chainShareButton(groups)
        } footer: {
            Text("依次发：点一下从第一家开始，发完一家自动弹出下一家，面板最上面写着第几家、发给谁、该选哪个群；都发完了按钮还在，能再发一遍。每家在面板里点：微信 → 发送给朋友 → 选群 → 发送。微信不让别的 App 替你选群、替你发，这几下省不掉；面板里用不上的隔空投送、信息、邮件已经拿掉，微信在前面，每次点同一个位置。")
        }
    }

    @ViewBuilder
    private func chainShareButton(_ groups: [OperatorGroup]) -> some View {
        // 一直在：都发了就是「再依次发一遍」。
        let names = groups.map(\.name)
        let unsent = names.filter { !store.passPlan.sent.contains($0) }
        if !names.isEmpty {
            Button { sendInTurn(unsent.isEmpty ? names : unsent) } label: {
                Label(chainTitle(names), systemImage: unsent.isEmpty ? "arrow.clockwise" : "paperplane.fill")
                    .font(.headline)
            }
            .disabled(!imagesAreCurrent || groups.contains { images[$0.name] == nil })
        }
    }

    @ViewBuilder
    private func planSections(_ grouped: GroupedPlans) -> some View {
        // 分不出是哪家的放最上面：先分好再发。
        if let lost = grouped.all.first(where: { $0.name == PassPlan.unassigned }) {
            unassignedSection(lost.rows, known: grouped.sendable.map(\.name))
        }
        ForEach(grouped.sendable, id: \.name) { group in
            operatorSection(group)
        }
        if !grouped.resting.isEmpty {
            restingSection(grouped.resting)
        }
        if grouped.excluded > 0 {
            excludedSection
        }
    }

    private func operatorSection(_ group: OperatorGroup) -> some View {
        Section {
            ForEach(indexedRows(for: group.name), id: \.offset) { item in
                rowButton(item.element, at: item.offset)
            }
            outputDescription(for: group.rows)
            sendButtons(group.name, rows: group.rows)
        } header: {
            header(group.name, count: group.rows.count,
                   urgent: group.rows.contains { PassPlan.emergency($0, layout: layout) == true })
        }
    }

    private func restingSection(_ groups: [OperatorGroup]) -> some View {
        Section {
            ForEach(groups, id: \.name) { group in
                HStack {
                    Text("\(group.name) · \(group.rows.count) 条").foregroundStyle(.secondary)
                    Spacer()
                    Button("要发") { store.settings.passPlanSkipped.removeAll { $0 == group.name } }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("不用发的")
        } footer: {
            Text("这几家标了「不用发」：不算在依次发、已发里。点「要发」改回来。")
        }
    }

    private var excludedSection: some View {
        let excluded = rows.enumerated().filter { PassPlan.isExcludedFromSending($0.element) }
        return Section {
            DisclosureGroup("查看已排除的 \(excluded.count) 条") {
                ForEach(excluded, id: \.offset) { item in
                    rowButton(item.element, at: item.offset)
                }
            }
        } header: {
            Text("test · 不发送")
        } footer: {
            Text("状态为 test 的计划不进入任何一家的图片、文字或依次发送；即使标了应急也会排除。点开可对照原图核对状态。")
        }
    }

    private var addPlanSection: some View {
        Section {
            Button { editing = EditingRow(sourceID: store.passPlan.sourceID, index: nil, row: PassPlanRow()) } label: {
                Label("补一条", systemImage: "plus")
            }
            .disabled(reading)
        }
    }

    private var settingsSection: some View {
        Section {
            NavigationLink {
                PassPlanOperatorsView()
            } label: {
                LabeledContent("运营商对照表", value: rules.isEmpty ? "还没填" : "\(rules.count) 家")
            }
            Toggle(isOn: $store.settings.passPlanOriginal) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("发原图")
                    Text(store.settings.passPlanOriginal
                         ? "从照片上裁下表头和这一家的几行拼成一张，字和照片一模一样；认字只用来分家"
                         : "发重新画的表：字是认出来的，可能有认错的，发之前核对标黄的")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("图片下面那句话").font(.caption).foregroundStyle(.secondary)
                TextField("没有应急计划时", text: $store.settings.passPlanCaption)
                TextField("有应急计划时（左侧「应急」或「是否应急」为「是」）", text: $store.settings.passPlanUrgentCaption)
            }
            Toggle("每天提醒发计划", isOn: $store.settings.passPlanReminder)
            if store.settings.passPlanReminder {
                DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text("到点提醒一次，点提醒直接打开这一页；那天各家都发完了就不再提醒。也可以在「快捷指令」里把「拍数传计划」设成轻点两下手机背面（设置 › 辅助功能 › 触控 › 轻点背面），一下就进扫描。")
        }
    }

    // MARK: - 导航、弹窗与输入

    private var navigationContent: some View {
        planList
            .appList()
            .navigationTitle("发数传计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !rows.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("全部清掉", role: .destructive) { clearing = true }
                    }
                }
            }
    }

    private var reviewContent: some View {
        navigationContent
            .confirmationDialog("把读到的计划全部清掉？", isPresented: $clearing, titleVisibility: .visible) {
                Button("全部清掉", role: .destructive) { store.passPlan = PassPlanSession(); problem = nil }
            }
            .alert("先核对可能认错的计划", isPresented: $showingReview) {
                Button("核对这一条") { if let reviewRow { edit(reviewRow) } }
                Button("暂不发送", role: .cancel) {}
            } message: {
                Text(reviewMessage)
            }
    }

    private var captureContent: some View {
        reviewContent
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { pages in readCapturedPages(pages) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in readCapturedPages([image]) }
                    .ignoresSafeArea()
            }
            .onChange(of: photoItems) { items in readSelectedPhotos(items) }
    }

    private var editingContent: some View {
        captureContent
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data,
                                                .commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                readImportedFile(result)
            }
            .sheet(item: $editing) { target in editorView(target) }
    }

    private var namingContent: some View {
        editingContent
            .alert("新的一家运营商", isPresented: newOperatorPresented) {
                TextField("运营商名字", text: $newOperatorName)
                Button("好", action: saveOperatorName)
                Button("取消", role: .cancel) { newOperatorFor = nil }
            } message: {
                Text("「\(newOperatorFor.map(PassPlan.suggestedPrefix(of:)) ?? "")」开头的站以后都算这一家")
            }
            .alert("\(naming ?? "")的计划发到哪个群", isPresented: groupNamePresented) {
                TextField("群名（只是给自己看的提示）", text: $groupName)
                Button("好", action: saveGroupName)
                Button("取消", role: .cancel) { naming = nil }
            } message: {
                Text("微信不让别的 App 直接发到群里：点「发图片」以后在微信里选这个群。记下来按钮上就写着该发哪个群。")
            }
    }

    private var newOperatorPresented: Binding<Bool> {
        Binding(get: { newOperatorFor != nil }, set: { if !$0 { newOperatorFor = nil } })
    }

    private var groupNamePresented: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }

    private func editorView(_ target: EditingRow) -> some View {
        NavigationStack {
            PassPlanRowEditor(row: target.row, layout: layout, rules: rules, isNew: target.index == nil,
                              sourceImage: target.sourceImage, sourceHeader: target.sourceHeader,
                              sendsOriginal: store.settings.passPlanOriginal && store.passPlan.fromPhotos) { saved in
                saveEditedRow(saved, for: target)
            }
        }
    }

    private func saveEditedRow(_ saved: PassPlanRow?, for target: EditingRow) {
        guard target.sourceID == store.passPlan.sourceID else {
            ToastCenter.shared.show("计划已经更新，请重新打开要核对的那一条", style: .warning)
            return
        }
        if let i = target.index {
            guard store.passPlan.rows.indices.contains(i), store.passPlan.rows[i] == target.row else {
                ToastCenter.shared.show("这一条已经变化，请重新打开核对", style: .warning)
                return
            }
            let old = store.passPlan.rows[i]
            if let saved { store.passPlan.rows[i] = saved } else { store.passPlan.rows.remove(at: i) }
            if let name = PassPlan.operatorName(of: old.station, rules: rules) { store.passPlan.sent.remove(name) }
        } else if let saved {
            store.passPlan.rows.append(saved)
        }
        if let saved, let name = PassPlan.operatorName(of: saved.station, rules: rules) { store.passPlan.sent.remove(name) }
    }

    private func readCapturedPages(_ pages: [UIImage]) {
        read(fromPhotos: true) { try await PlanReader.read(pages: pages, rules: rules) }
    }

    private func readSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        read(fromPhotos: true) {
            var pages: [UIImage] = []
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    pages.append(image)
                }
            }
            return try await PlanReader.read(pages: pages, rules: rules)
        }
    }

    private func readImportedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        read { try PlanReader.read(file: url) }
    }

    private func saveOperatorName() {
        let name = newOperatorName.trimmingCharacters(in: .whitespaces)
        if let station = newOperatorFor, !name.isEmpty { assign(station, to: name) }
        newOperatorFor = nil
    }

    private func saveGroupName() {
        if let name = naming {
            let trimmed = groupName.trimmingCharacters(in: .whitespaces)
            store.settings.passPlanGroups[name] = trimmed.isEmpty ? nil : trimmed
        }
        naming = nil
    }

    private func prepareOnAppear() {
        let actions = entryState.consume(initial: initial, autoScan: autoScan)
        if let initial = actions.reading {
            store.passPlan = PassPlanSession(fromPhotos: initial.header != nil || initial.rows.contains { $0.region != nil },
                                            rows: initial.rows, layout: initial.layout, header: initial.header, strips: initial.strips)
        }
        if actions.autoScan {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if DocumentScanner.isSupported { scanning = true } else { showingCamera = true }
            }
        }
    }

    // MARK: - 一家的标题、一行

    /// 两条值完全相同的计划仍是两条记录；分组后保留它们在本批计划中的独立下标。
    private func indexedRows(for name: String) -> [(offset: Int, element: PassPlanRow)] {
        rows.enumerated().filter {
            !PassPlan.isExcludedFromSending($0.element)
                && (PassPlan.operatorName(of: $0.element.station, rules: rules) ?? PassPlan.unassigned) == name
        }
    }

    private func rowButton(_ row: PassPlanRow, at index: Int) -> some View {
        let sourceID = store.passPlan.sourceID
        return Button { edit(row, at: index, sourceID: sourceID) } label: { rowView(row) }
            .buttonStyle(.plain)
            .disabled(reading)
            // 可能认错的标黄
            .listRowBackground(PassPlan.isExcludedFromSending(row) || PassPlan.problems(row, rules: rules, layout: layout).isEmpty
                               ? nil : DS.Palette.warning.opacity(0.12))
            .swipeActions {
                Button("删掉", role: .destructive) { delete(row, at: index, sourceID: sourceID) }
                    .disabled(reading)
            }
    }

    /// 分不出是哪家的：每个站点一下「分给哪家」，记进对照表，以后自动分
    private func unassignedSection(_ rows: [PassPlanRow], known: [String]) -> some View {
        let stations = Array(Set(rows.map(\.station))).sorted()
        let names = (rules.map(\.name) + known).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return Section {
            ForEach(stations, id: \.self) { station in
                // 站名多半是认错了一个字（「驭星」认成「取星」）：最像的那家放第一个，点一下就分过去
                // 或者表按地面站排过序：上下挨着的都是同一家
                let similar = PassPlan.likelyOperator(of: station, rules: rules)
                let neighbor = PassPlan.neighborOperator(of: station, in: PassPlan.sendableRows(self.rows), rules: rules)
                let likely = similar ?? neighbor
                let reason = similar.map { " · 像是认错了字，最像「\($0)」" } ?? neighbor.map { " · 上下挨着的都是「\($0)」" } ?? ""
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station).font(.subheadline.weight(.medium))
                        Text("\(rows.filter { $0.station == station }.count) 条" + reason)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let likely {
                        Button("算\(likely)") { assign(station, to: likely) }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                    }
                    Menu {
                        ForEach(names, id: \.self) { name in
                            Button(name == likely ? "\(name)（最像）" : name) { assign(station, to: name) }
                        }
                        Button {
                            newOperatorName = ""
                            newOperatorFor = station
                        } label: {
                            Label("新的一家…", systemImage: "plus")
                        }
                    } label: {
                        Label(likely == nil ? "分给哪家" : "别的", systemImage: "arrow.turn.down.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
            ForEach(indexedRows(for: PassPlan.unassigned), id: \.offset) { item in
                rowButton(item.element, at: item.offset)
            }
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
            Button("不用发") { store.settings.passPlanSkipped.append(name) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
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
                if PassPlan.isExcludedFromSending(row) {
                    Text("test · 已排除").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(row.satellite.isEmpty ? row.satelliteID : row.satellite).font(.subheadline)
            }
            Text([row.station, row.orbit.isEmpty ? "" : "圈号 \(row.orbit)", row.satelliteID, row.info]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if !PassPlan.isExcludedFromSending(row), !problems.isEmpty {
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
            .disabled(!imagesAreCurrent || images[name] == nil)
            Button { share(PassPlan.message(name: name, rows: rows, layout: layout, caption: caption(rows)), name: name) } label: {
                Label("发文字", systemImage: "text.alignleft").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!imagesAreCurrent)
        }
        .font(.subheadline.weight(.medium))
        .padding(.vertical, DS.Space.xxs)
    }

    @ViewBuilder
    private func outputDescription(for rows: [PassPlanRow]) -> some View {
        if store.settings.passPlanOriginal && store.passPlan.fromPhotos {
            let missing = rows.filter { $0.region.flatMap { store.passPlan.strips[$0] } == nil }.count
            let hasHeader = store.passPlan.header.flatMap { store.passPlan.strips[$0] } != nil
            if missing > 0 || !hasHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Label(missing > 0 ? "这家有 \(missing) 条缺少原图，暂时不能拼成完整图片" : "没有裁出完整表头，暂时不能拼原图",
                          systemImage: "photo.badge.exclamationmark")
                    Text("可以重新拍摄；核对文字后，也可以改用重新绘制的表格。")
                    Button("改用文字绘制图片") { store.settings.passPlanOriginal = false }
                        .buttonStyle(.bordered)
                }
                .font(.caption).foregroundStyle(DS.Palette.warning)
            } else {
                Text("图片使用原照片；点开计划可对照原文。文字计划使用下面核对后的识别结果。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text(store.passPlan.fromPhotos ? "图片由识别文字重新绘制，请先核对标黄的计划。" : "图片根据导入或填写的表格生成。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 读、改、发

    private func read(fromPhotos: Bool = false, _ work: @escaping @MainActor () async throws -> PassPlan.Reading) {
        guard !reading else { return }
        let sourceID = store.passPlan.sourceID
        reading = true
        problem = nil
        Task {
            defer { reading = false }
            do {
                let result = try await work()
                // 清空或换了一批计划后，旧识别任务不能把结果重新写回来。
                guard store.passPlan.sourceID == sourceID else { return }
                let found = result.rows
                withAnimation {
                    store.passPlan = PassPlanSession(fromPhotos: fromPhotos, rows: found, layout: result.layout,
                                                    header: result.header, strips: result.strips)
                }
                let doubtful = PassPlan.sendableRows(found).filter { !PassPlan.problems($0, rules: rules, layout: result.layout).isEmpty }.count
                let excluded = found.filter(PassPlan.isExcludedFromSending).count
                let grouped = PassPlan.grouped(found, rules: rules)
                let lost = grouped.first { $0.name == PassPlan.unassigned }?.rows.count ?? 0
                let families = grouped.filter { $0.name != PassPlan.unassigned }.count
                var message = "认出 \(found.count) 条，分成 \(families) 家"
                if excluded > 0 { message += "；已排除 \(excluded) 条 test" }
                if lost > 0 { message += "；\(lost) 条分不出是哪家，在最上面" } else if doubtful > 0 { message += "，\(doubtful) 条要核对" }
                ToastCenter.shared.show(message, style: doubtful > 0 || lost > 0 ? .warning : .success)
            } catch {
                guard store.passPlan.sourceID == sourceID else { return }
                problem = error.localizedDescription
            }
        }
    }

    private func edit(_ row: PassPlanRow) {
        guard let index = rows.firstIndex(of: row) else { return }
        edit(row, at: index, sourceID: store.passPlan.sourceID)
    }

    private func edit(_ row: PassPlanRow, at index: Int, sourceID: UUID) {
        guard !reading else { return }
        guard sourceID == store.passPlan.sourceID, rows.indices.contains(index), rows[index] == row else {
            ToastCenter.shared.show("这一条已经变化，请重新打开核对", style: .warning)
            return
        }
        editing = EditingRow(sourceID: sourceID, index: index, row: row,
                             sourceImage: row.region.flatMap { store.passPlan.strips[$0] }.flatMap(UIImage.init(data:)),
                             sourceHeader: store.passPlan.header.flatMap { store.passPlan.strips[$0] }.flatMap(UIImage.init(data:)))
    }

    private func delete(_ row: PassPlanRow, at index: Int, sourceID: UUID) {
        guard !reading else { return }
        guard sourceID == store.passPlan.sourceID, rows.indices.contains(index), rows[index] == row else {
            ToastCenter.shared.show("这一条已经变化，请重新打开核对", style: .warning)
            return
        }
        store.passPlan.rows.remove(at: index)
        if let name = PassPlan.operatorName(of: row.station, rules: rules) { store.passPlan.sent.remove(name) }
    }

    /// 在微信等分享操作完成后标「已发」（系统不提供收件人送达回执）。
    /// progress：面板标题前面的「2/5」；then：是否完成了可记为已发的分享操作。
    private func share(_ item: Any, name: String, progress: String? = nil, then next: (@MainActor (Bool) -> Void)? = nil) {
        guard imagesAreCurrent, readyToSend([name]) else { return }
        let sharedInput = renderInput
        let step = progress.map { "\($0) · " } ?? ""
        let target = store.settings.passPlanGroups[name].map { " → 发到「\($0)」" } ?? ""
        let payload = SharePayload(item, title: "\(step)\(name)数传计划\(target)", preview: images[name])
        ActivityShare.present([payload], excluding: ActivityShare.chatOnly) { completed in
            // 从外部文件换了一批计划时，旧分享不能给新计划标「已发」或继续发下一家。
            guard sharedInput == renderInput else { return }
            if completed { markSent(name) }
            next?(completed)
        }
    }

    /// 只拦下实际存在的疑项；对照照片后保存，才清除多次识别的分歧。
    private func readyToSend(_ names: [String]) -> Bool {
        let selected = Set(names)
        let allowed = sendable.filter { selected.contains($0.name) }
        // 只剩 test、被标为不用发，或旧队列中的运营商，都没有发送入口。
        guard !selected.isEmpty, Set(allowed.map(\.name)) == selected else { return false }
        let doubtful = allowed.flatMap(\.rows)
            .filter { !PassPlan.problems($0, rules: rules, layout: layout).isEmpty }
        guard let first = doubtful.first else { return true }
        reviewRow = first
        reviewMessage = "有 \(doubtful.count) 条需要核对。\n\n\(first.satellite.isEmpty ? first.satelliteID : first.satellite) · \(first.station)\n"
            + PassPlan.problems(first, rules: rules, layout: layout).joined(separator: "；")
            + "\n\n请对照原图修改，确认后再发送。"
        showingReview = true
        return false
    }

    /// 「依次发」按钮上的字
    private func chainTitle(_ names: [String]) -> String {
        let unsent = names.filter { !store.passPlan.sent.contains($0) }
        if unsent.isEmpty { return "再依次发一遍（\(names.count) 家）" }
        return unsent.count == names.count ? "依次发给各家（\(names.count) 家）" : "接着发剩下的 \(unsent.count) 家"
    }

    /// 从第一家开始，发完一家弹下一家（上一个面板收完马上弹）；中途取消就停下，提示停在哪家
    private func sendInTurn(_ names: [String], step: Int = 1, total: Int? = nil) {
        guard imagesAreCurrent else { return }
        if step == 1, !readyToSend(names) { return }
        let total = total ?? names.count
        guard let name = names.first, let image = images[name] else { return }
        share(image, name: name, progress: total > 1 ? "\(step)/\(total)" : nil) { sent in
            let rest = Array(names.dropFirst())
            if sent {
                if !rest.isEmpty { sendInTurn(rest, step: step + 1, total: total) }
            } else if total > 1 {
                ToastCenter.shared.show("停在\(name)，这家尚未标为已发。要接着发，点「\(chainTitle(sendable.map(\.name)))」", style: .warning)
            }
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
        // 再发一遍的不算（不然每发一家都说一次「各家都发了」）
        guard store.passPlan.sent.insert(name).inserted else { return }
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
        let input = renderInput
        var made: [String: UIImage] = [:]
        for group in sendable {
            if store.settings.passPlanOriginal && store.passPlan.fromPhotos {
                // 原图缺行时不能悄悄换成 OCR 重绘图，把认错的字带出去。
                if let original = originalImage(name: group.name, rows: group.rows) { made[group.name] = original }
                continue
            }
            let renderer = ImageRenderer(content: PassPlanSheet(name: group.name, rows: group.rows, layout: layout,
                                                                caption: caption(group.rows)))
            renderer.scale = 3
            if let image = renderer.uiImage { made[group.name] = image }
        }
        images = made
        renderedInput = input
    }

    /// 发原图：表头那一条加上这一家每一行那一条（都是从照片上裁下来扶正的），上面标题、下面那句话。
    /// 任意一行没有原图就返回 nil，让页面说明缺图；不自动换成识别文字绘制的表。
    private func originalImage(name: String, rows: [PassPlanRow]) -> UIImage? {
        let session = store.passPlan
        return PassPlanOriginal.image(name: name, rows: rows, header: session.header, strips: session.strips,
                                      caption: caption(PassPlan.sendableRows(rows)))
    }
}

/// 发到群里的那张图：白底表格，深色模式下也是白底（群里大家看着一样）
struct PassPlanSheet: View {
    let name: String
    let rows: [PassPlanRow]
    var layout: PassPlan.Layout?
    /// 表下面那一行字（「麻烦确认一下数传计划」）
    var caption = ""

    /// 和网页上的表一样：同样的表头、列的先后、行的先后，时间写全；居中、每行一条细线
    var body: some View {
        let table = PassPlan.table(rows, layout: layout)
        let urgentColumn = table.headers.firstIndex { $0.contains("应急") }
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
                            let value = cell.filter { !$0.isWhitespace }
                            let urgent = c == urgentColumn && (value == "是" || value == "应急")
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
    @State private var emergencyConfirmed = false
    /// 读到的那张表的列：认不出含义的列（是否应急、创建时间……）也能改
    private let layout: PassPlan.Layout?
    private let rules: [PassPlan.OperatorRule]
    private let sourceImage: UIImage?
    private let sourceHeader: UIImage?
    private let sendsOriginal: Bool
    private let originalStatus: String
    private let originalTestStatusDetected: Bool?
    let isNew: Bool
    var onDone: (PassPlanRow?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(row: PassPlanRow, layout: PassPlan.Layout?, rules: [PassPlan.OperatorRule] = [], isNew: Bool,
         sourceImage: UIImage? = nil, sourceHeader: UIImage? = nil, sendsOriginal: Bool = false,
         onDone: @escaping (PassPlanRow?) -> Void) {
        var r = row
        if let layout, r.cells.count < layout.slots.count {
            r.cells += Array(repeating: "", count: layout.slots.count - r.cells.count)
        }
        _row = State(initialValue: r)
        self.layout = layout
        self.rules = rules
        self.sourceImage = sourceImage
        self.sourceHeader = sourceHeader
        self.sendsOriginal = sendsOriginal
        self.originalStatus = row.status
        self.originalTestStatusDetected = row.testStatusDetected
        self.isNew = isNew
        self.onDone = onDone
    }

    /// 只有原表里才有、App 认不出含义的那几列
    private var otherColumns: [Int] {
        guard let layout else { return [] }
        return layout.slots.indices.filter { layout.slots[$0].column == nil && $0 != layout.emergencyIndex }
    }

    private var statusBinding: Binding<String> {
        Binding(get: { row.status }, set: { value in
            row.status = value
            // 明确改过状态后，以核对的新值为准；仅改空格/大小写不能抹掉先前读到 test 的证据。
            let same = value.filter { !$0.isWhitespace }.lowercased() == originalStatus.filter { !$0.isWhitespace }.lowercased()
            row.testStatusDetected = same ? originalTestStatusDetected : nil
        })
    }

    private var emergencySelection: Binding<Int> {
        Binding(get: {
            if emergencyNeedsChoice { return -1 }
            if let value = PassPlan.emergency(row, layout: layout) { return value ? 1 : 0 }
            return layout?.emergencyIndex == nil ? 0 : -1
        }, set: { choice in
            emergencyConfirmed = choice >= 0
            row.emergencyBadge = choice < 0 ? nil : choice == 1
            if let index = layout?.emergencyIndex, row.cells.indices.contains(index) {
                row.cells[index] = choice < 0 ? "" : (choice == 1 ? "是" : "不是")
            }
        })
    }

    private var emergencyNeedsChoice: Bool {
        if emergencyConfirmed { return false }
        return (layout?.emergencyIndex != nil && PassPlan.emergency(row, layout: layout) == nil)
            || row.recognitionIssues?.contains(where: { $0.contains("应急") }) == true
    }

    private var sendingRulesSection: some View {
        Section {
            Picker("计划类型", selection: emergencySelection) {
                if emergencyNeedsChoice { Text("待核对").tag(-1) }
                Text("普通计划").tag(0)
                Text("应急计划").tag(1)
            }
            if emergencyNeedsChoice {
                Text("请对照原图，选择这条是否为应急计划。")
                    .font(.footnote).foregroundStyle(DS.Palette.warning)
            }
            if PassPlan.isExcludedFromSending(row) {
                Label("已排除：不发送给任何一家", systemImage: "nosign")
                    .foregroundStyle(.secondary)
                if row.testStatusDetected == true, row.status.filter({ !$0.isWhitespace }).lowercased() != "test" {
                    Text("有一次识别结果读到 test，请对照原图最右侧的状态列。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("已核对原图，状态不是 test") { row.testStatusDetected = nil }
                }
            }
        } header: {
            Text("应急与发送")
        } footer: {
            Text("最左侧标「应急」的按应急计划处理；最右侧状态为 test 的始终不发送，包括应急计划。")
        }
    }

    var body: some View {
        Form {
            if let sourceImage {
                Section {
                    let width = max(900, sourceImage.size.width)
                    let headerHeight = sourceHeader.map { width * $0.size.height / max($0.size.width, 1) } ?? 0
                    let rowHeight = width * sourceImage.size.height / max(sourceImage.size.width, 1)
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 2) {
                            if let sourceHeader {
                                Image(uiImage: sourceHeader).resizable().scaledToFit().frame(width: width)
                            }
                            Image(uiImage: sourceImage).resizable().scaledToFit().frame(width: width)
                        }
                    }
                    .frame(height: min(280, max(70, headerHeight + rowHeight + 4)))
                    .accessibilityLabel("这一条计划的原照片，左右滑动查看各列")
                } header: {
                    Text("对照原照片")
                } footer: {
                    Text(sendsOriginal
                         ? "左右滑动查看各列。当前发图片使用原照片；修改下面的识别结果会修正分家和文字计划，不会改写照片中的字。"
                         : "左右滑动查看各列，再核对下面的识别结果；发送的文字和重绘图片使用你确认后的内容。")
                }
            }
            let issues = PassPlan.problems(row, rules: rules, layout: layout)
            if !issues.isEmpty {
                Section("需要核对") {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(DS.Palette.warning)
                    }
                    Text("对照原文逐项核对，确认无误后点「保存并确认」。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
                TextField("状态", text: statusBinding)
            } footer: {
                Text("时间写成 2026-10-27 22:57:51 这样")
            }
            sendingRulesSection
            if let layout, !otherColumns.isEmpty {
                Section {
                    ForEach(otherColumns, id: \.self) { i in
                        TextField(layout.slots[i].label, text: $row.cells[i])
                    }
                } footer: {
                    Text("这里保留原表中的其他列，按原图核对。")
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
                Button("保存并确认") {
                    row.start = PassPlan.normalizedTime(row.start)
                    row.end = PassPlan.normalizedTime(row.end)
                    // 人工确认只清除识别提示；无效时间、缺少字段和 test 排除继续生效。
                    row = PassPlan.confirmedRecognitionReview(row)
                    onDone(row)
                    dismiss()
                }
                .disabled(row.station.isEmpty || (row.satellite.isEmpty && row.satelliteID.isEmpty) || emergencyNeedsChoice)
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

/// 发原图：把从照片上裁下来的几条（表头、这一家的每一行）上下拼成一张，上面标题、下面那句话
enum PassPlanOriginal {
    /// 所有原图出口共用过滤：test 行连原照片切片也不能带入任何一家的图片。
    @MainActor
    static func image(name: String, rows: [PassPlanRow], header: PassPlan.Region?,
                      strips: [PassPlan.Region: Data], caption: String) -> UIImage? {
        let included = PassPlan.sendableRows(rows)
        guard !included.isEmpty, let header, let top = strips[header].flatMap(UIImage.init(data:)) else { return nil }
        var pieces = [top]
        for row in included {
            guard let region = row.region, let strip = strips[region].flatMap(UIImage.init(data:)) else { return nil }
            pieces.append(strip)
        }
        return compose(title: PassPlan.title(name: name, rows: included), caption: caption, strips: pieces)
    }

    @MainActor
    static func compose(title: String, caption: String, strips: [UIImage]) -> UIImage? {
        let width = strips.map(\.size.width).max() ?? 0
        guard width > 0 else { return nil }
        let pad = (width / 50).rounded()
        let titleFont = UIFont.boldSystemFont(ofSize: max(28, width / 36))
        let captionFont = UIFont.systemFont(ofSize: max(26, width / 40), weight: .semibold)
        let heights = strips.map { ($0.size.height * width / max($0.size.width, 1)).rounded() }
        let titleHeight = ceil(titleFont.lineHeight)
        let captionBox = (caption as NSString).boundingRect(with: CGSize(width: width - pad * 2, height: .greatestFiniteMagnitude),
                                                            options: .usesLineFragmentOrigin,
                                                            attributes: [.font: captionFont], context: nil)
        let captionHeight = caption.isEmpty ? 0 : ceil(captionBox.height) + pad
        let total = pad + titleHeight + pad + heights.reduce(0, +) + captionHeight + pad
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: total), format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: total))
            (title as NSString).draw(at: CGPoint(x: pad, y: pad), withAttributes: [.font: titleFont, .foregroundColor: UIColor.black])
            var y = pad + titleHeight + pad
            for (strip, height) in zip(strips, heights) {
                strip.draw(in: CGRect(x: 0, y: y, width: width, height: height))
                y += height
            }
            if !caption.isEmpty {
                (caption as NSString).draw(with: CGRect(x: pad, y: y + pad, width: width - pad * 2, height: ceil(captionBox.height) + 2),
                                           options: .usesLineFragmentOrigin,
                                           attributes: [.font: captionFont, .foregroundColor: UIColor.black], context: nil)
            }
        }
    }
}
