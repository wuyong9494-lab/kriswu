import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 发数传计划：拍一张计划（或导入导出的 Excel、粘贴复制的表格），按运营商（地面站「-」前面的名字）分开，
/// 每家生成一张清楚的表格图 / 一段文字，点一下发到那家的微信群。读出来的东西只在这一页，不存、不上传
struct PassPlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var rows: [PassPlanRow]
    @State private var reading = false
    @State private var problem: String?
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var editing: EditingRow?
    @State private var naming: String?
    @State private var groupName = ""
    /// 每家的图（读完、改完重新画）
    @State private var images: [String: Image] = [:]

    private struct EditingRow: Identifiable {
        let id = UUID()
        var index: Int?
        var row: PassPlanRow
    }

    init(rows: [PassPlanRow] = []) {
        _rows = State(initialValue: rows)
    }

    var body: some View {
        let groups = PassPlan.grouped(rows)
        List {
            Section {
                Button { showingCamera = true } label: {
                    Label("拍计划", systemImage: "camera.viewfinder")
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("从相册选一张", systemImage: "photo.on.rectangle")
                }
                Button { importing = true } label: {
                    Label("导入导出的 Excel", systemImage: "tablecells")
                }
                Button { read { try PlanReader.rowsFromClipboard() } } label: {
                    Label("粘贴复制的表格", systemImage: "doc.on.clipboard")
                }
                if reading {
                    HStack(spacing: DS.Space.xs) { DSSpinner(size: 14); Text("正在认…").foregroundStyle(.secondary) }
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(DS.Palette.danger)
                }
            } footer: {
                Text("对着电脑屏幕拍，表头那一行要拍进去。按地面站「-」前面的名字分到各家；读出来的先核对一下，认错的点一行改。照片和计划只在这一页，不存、不上传。")
            }
            if !rows.isEmpty {
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.rows, id: \.self) { row in
                            Button { edit(row) } label: { rowView(row) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("删掉", role: .destructive) { rows.removeAll { $0 == row } }
                                }
                        }
                        sendButtons(group.name, rows: group.rows)
                    } header: {
                        HStack {
                            Text("\(group.name) · \(group.rows.count) 条")
                            Spacer()
                            Button {
                                groupName = store.settings.passPlanGroups[group.name] ?? ""
                                naming = group.name
                            } label: {
                                Label(store.settings.passPlanGroups[group.name].map { "发到：\($0)" } ?? "记一下发哪个群",
                                      systemImage: "person.3")
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Section {
                    Button { editing = EditingRow(index: nil, row: PassPlanRow()) } label: {
                        Label("补一条", systemImage: "plus")
                    }
                    Button("全部清掉", role: .destructive) { rows = []; problem = nil }
                }
            }
        }
        .appList()
        .navigationTitle("发数传计划")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in read { try await PlanReader.rows(in: image) } }
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            photoItem = nil
            read {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    throw PlanReader.Failure.noText
                }
                return try await PlanReader.rows(in: image)
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
                    if let i = target.index, rows.indices.contains(i) {
                        if let saved { rows[i] = saved } else { rows.remove(at: i) }
                    } else if let saved {
                        rows.append(saved)
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
        .task(id: rows) { await renderImages() }
    }

    // MARK: - 一行

    private func rowView(_ row: PassPlanRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text([PassPlan.shortTime(row.start), PassPlan.shortTime(row.end)].filter { !$0.isEmpty }.joined(separator: "–"))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Spacer()
                Text(row.satellite.isEmpty ? row.satelliteID : row.satellite).font(.subheadline)
            }
            Text([row.station, row.orbit.isEmpty ? "" : "圈号 \(row.orbit)", row.satelliteID, row.info]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func sendButtons(_ name: String, rows: [PassPlanRow]) -> some View {
        let text = PassPlan.message(name: name, rows: rows)
        let target = store.settings.passPlanGroups[name]
        return HStack(spacing: DS.Space.s) {
            if let image = images[name] {
                ShareLink(item: image, preview: SharePreview("\(name)数传计划", image: image)) {
                    Label(target.map { "发图片到\($0)" } ?? "发图片", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            ShareLink(item: text) {
                Label("发文字", systemImage: "text.alignleft").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline.weight(.medium))
        .padding(.vertical, DS.Space.xxs)
    }

    // MARK: - 读、改

    private func read(_ work: @escaping @MainActor () async throws -> [PassPlanRow]) {
        reading = true
        problem = nil
        Task {
            do {
                let found = try await work()
                withAnimation { rows = found }
                ToastCenter.shared.show("认出 \(found.count) 条，分成 \(PassPlan.grouped(found).count) 家，先核对一下", style: .success)
            } catch {
                problem = error.localizedDescription
            }
            reading = false
        }
    }

    private func edit(_ row: PassPlanRow) {
        editing = EditingRow(index: rows.firstIndex(of: row), row: row)
    }

    @MainActor
    private func renderImages() async {
        var made: [String: Image] = [:]
        for group in PassPlan.grouped(rows) {
            let renderer = ImageRenderer(content: PassPlanSheet(name: group.name, rows: group.rows))
            renderer.scale = 3
            if let image = renderer.uiImage { made[group.name] = Image(uiImage: image) }
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
