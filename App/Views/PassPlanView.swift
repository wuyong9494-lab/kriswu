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
    @State private var reading = false
    @State private var problem: String?
    @State private var scanning = false
    @State private var showingCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var editing: EditingRow?
    @State private var naming: String?
    @State private var groupName = ""
    /// 每家的图（读完、改完重新画）
    @State private var images: [String: UIImage] = [:]

    private struct EditingRow: Identifiable {
        let id = UUID()
        var index: Int?
        var row: PassPlanRow
    }

    init(rows: [PassPlanRow] = []) {
        initialRows = rows
    }

    private var rows: [PassPlanRow] { store.passPlan.rows }

    var body: some View {
        let groups = PassPlan.grouped(rows)
        let doubtful = rows.filter { !PassPlan.problems($0).isEmpty }.count
        List {
            Section {
                Button { if DocumentScanner.isSupported { scanning = true } else { showingCamera = true } } label: {
                    Label("拍计划", systemImage: "doc.viewfinder").font(.headline)
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
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
                }
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.rows, id: \.self) { row in
                            Button { edit(row) } label: { rowView(row) }
                                .buttonStyle(.plain)
                                // 可能认错的标黄
                                .listRowBackground(PassPlan.problems(row).isEmpty ? nil : DS.Palette.warning.opacity(0.12))
                                .swipeActions {
                                    Button("删掉", role: .destructive) { store.passPlan.rows.removeAll { $0 == row } }
                                }
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
        }
        .task(id: rows) { renderImages() }
    }

    // MARK: - 一家的标题、一行

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
        let problems = PassPlan.problems(row)
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
                share([image], name: name)
            } label: {
                Label(sent ? "再发一次图片" : (target.map { "发图片到\($0)" } ?? "发图片"), systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(sent ? DS.Palette.success : DS.Palette.accent)
            .disabled(images[name] == nil)
            Button { share([PassPlan.message(name: name, rows: rows)], name: name) } label: {
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
                let doubtful = found.filter { !PassPlan.problems($0).isEmpty }.count
                ToastCenter.shared.show("认出 \(found.count) 条，分成 \(PassPlan.grouped(found).count) 家"
                                        + (doubtful > 0 ? "，\(doubtful) 条要核对" : ""), style: doubtful > 0 ? .warning : .success)
            } catch {
                problem = error.localizedDescription
            }
            reading = false
        }
    }

    private func edit(_ row: PassPlanRow) {
        editing = EditingRow(index: rows.firstIndex(of: row), row: row)
    }

    /// 发出去（在微信里选群）；真的发了就标「已发」
    private func share(_ items: [Any], name: String) {
        ActivityShare.present(items) { completed in
            if completed { store.passPlan.sent.insert(name) }
        }
    }

    private func renderImages() {
        var made: [String: UIImage] = [:]
        for group in PassPlan.grouped(rows) {
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
        ]
    }
}
