import SwiftUI

/// 地面站与运营商对照表及发送顺序管理：
/// - 支持独立「添加地面站 / 运营商」与「编辑地面站 / 运营商」表单页，右上角统一提供「保存」按钮（键盘弹出时同样可见可点）。
/// - 完整保留原有精确站名匹配、最长前缀匹配、发送先后顺序、剪贴板批量导入/备份与重启持久化。
struct PassPlanOperatorsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editMode: EditMode = .inactive
    @State private var confirmingPaste = false
    @State private var pasted: [PassPlan.OperatorRule] = []
    @State private var activeEditorRoute: EditorRoute = .add
    @State private var isPresentingEditor: Bool = false

    enum EditorRoute: Identifiable, Hashable {
        case add
        case edit(index: Int)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let index): return "edit-\(index)"
            }
        }
    }

    private func openEditor(_ route: EditorRoute) {
        activeEditorRoute = route
        isPresentingEditor = true
    }

    var body: some View {
        List {
            Section {
                if store.settings.passPlanOperators.isEmpty {
                    AppEmptyStateCard(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "还没有配置地面站 / 运营商",
                        message: "添加第一条规则以设置站名匹配和发送顺序。",
                        actionTitle: "添加地面站 / 运营商",
                        action: { openEditor(.add) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(store.settings.passPlanOperators.enumerated()), id: \.offset) { i, rule in
                        stationRuleRow(rule, index: i)
                    }
                    .onDelete { offsets in
                        store.settings.passPlanOperators.remove(atOffsets: offsets)
                        store.flushSave(wait: false)
                    }
                    .onMove { from, to in
                        store.settings.passPlanOperators.move(fromOffsets: from, toOffset: to)
                        store.flushSave(wait: false)
                    }

                    Button {
                        Haptics.tap()
                        openEditor(.add)
                    } label: {
                        Label("添加地面站 / 运营商", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    .accessibilityIdentifier("groundStation.list.addRow")
                }
            } header: {
                Text("地面站与运营商（共 \(store.settings.passPlanOperators.count) 项 · 按此顺序发送）")
            } footer: {
                Text("先匹配完整站名，再匹配最长的唯一前缀。排序决定发送顺序。")
            }

            Section {
                HStack {
                    Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                        .font(.subheadline)
                    Spacer()
                    PasteButton(payloadType: String.self) { strings in
                        let found = PassPlan.parseRules(strings.joined(separator: "\n"))
                        Task { @MainActor in
                            if found.isEmpty {
                                ToastCenter.shared.show("剪贴板里没有对照表：一行一家，写成「名字：前缀、=完整站名」", style: .error)
                            } else {
                                pasted = found
                                confirmingPaste = true
                            }
                        }
                    }
                    .labelStyle(.titleAndIcon)
                }
                Button {
                    UIPasteboard.general.string = PassPlan.rulesText(store.settings.passPlanOperators)
                    ToastCenter.shared.show("对照表已复制", style: .success)
                } label: {
                    Label("复制为文字备份", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .disabled(store.settings.passPlanOperators.isEmpty)
            } header: {
                Text("批量导入与备份")
            } footer: {
                Text("一行一家，例如「甲站：甲光、=北区接收站 01」。带「=」只匹配完整站名。")
            }
        }
        .environment(\.editMode, $editMode)
        .appList()
        .hidesFloatingTabBar()
        .navigationTitle("地面站与运营商")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !store.settings.passPlanOperators.isEmpty {
                    Button(editMode == .active ? "完成" : "排序") {
                        withAnimation(DS.Motion.snappy) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .accessibilityIdentifier("groundStation.list.sort")
                }
                Button {
                    Haptics.tap()
                    openEditor(.add)
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .accessibilityIdentifier("groundStation.list.add")
            }
        }
        .navigationDestination(isPresented: $isPresentingEditor) {
            switch activeEditorRoute {
            case .add:
                GroundStationRuleEditorView(editingIndex: nil)
                    .id(activeEditorRoute.id)
            case .edit(let idx):
                GroundStationRuleEditorView(editingIndex: idx)
                    .id(activeEditorRoute.id)
            }
        }
        .confirmationDialog("读到 \(pasted.count) 家运营商", isPresented: $confirmingPaste, titleVisibility: .visible) {
            Button("替换现有列表") {
                store.settings.passPlanOperators = pasted
                store.flushSave(wait: false)
            }
            Button("合并进去（保留原有规则）") {
                store.settings.passPlanOperators = merged(pasted)
                store.flushSave(wait: false)
            }
        } message: {
            Text(pasted.map(\.name).joined(separator: "、"))
        }
    }

    private func stationRuleRow(_ rule: PassPlan.OperatorRule, index i: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                openEditor(.edit(index: i))
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text("#\(i + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(DS.Palette.accentSoft, in: Capsule())
                        .foregroundStyle(DS.Palette.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.name.isEmpty ? "未命名条目" : rule.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if !rule.prefixes.isEmpty {
                            Text("前缀：\(rule.prefixes.joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let exact = rule.exactStations, !exact.isEmpty {
                            Text("完整站：\(exact.joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if rule.prefixes.isEmpty && (rule.exactStations?.isEmpty ?? true) {
                            Text("点击补全地面站前缀或完整站名")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("groundStation.row.\(i)")

            if editMode == .inactive {
                VStack(spacing: 4) {
                    Button {
                        moveRule(from: i, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("上移\(rule.name)")
                    .disabled(i == 0)

                    Button {
                        moveRule(from: i, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下移\(rule.name)")
                    .disabled(i >= store.settings.passPlanOperators.count - 1)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func moveRule(from index: Int, offset: Int) {
        let target = index + offset
        guard store.settings.passPlanOperators.indices.contains(index),
              store.settings.passPlanOperators.indices.contains(target) else { return }
        withAnimation(DS.Motion.snappy) {
            store.settings.passPlanOperators.swapAt(index, target)
        }
        store.flushSave(wait: false)
    }

    private func merged(_ new: [PassPlan.OperatorRule]) -> [PassPlan.OperatorRule] {
        PassPlan.parseRules(PassPlan.rulesText(store.settings.passPlanOperators) + "\n" + PassPlan.rulesText(new))
    }
}

/// 统一的「添加 / 编辑地面站」表单页：
/// - 顶部导航栏右上角固定提供「保存」按钮（编辑与添加位置完全一致，打开键盘时始终可见可点）。
/// - 必填项校验不通过时留在当前页并保留全部输入，明确提示缺项；保存成功后立即持久化并返回更新后的列表。
/// - 内置防连点锁，连续点击不会重复创建两条。
struct GroundStationRuleEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let editingIndex: Int?

    @State private var name: String = ""
    @State private var prefixesText: String = ""
    @State private var exactStationsText: String = ""
    @State private var attemptedSave = false
    @State private var isSaving: Bool = false
    @State private var loadedInitial: Bool = false

    private enum Field: Hashable { case name, prefixes, exact }
    @FocusState private var focusedField: Field?

    private var isEditing: Bool { editingIndex != nil }

    var body: some View {
        Form {
            if attemptedSave, !isSaving, let issue = validationIssue(for: draftRule) {
                Section {
                    AppErrorBannerCard(message: issue.message)
                        .accessibilityIdentifier("groundStation.editor.validation")
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 3) {
                        Text("地面站 / 运营商名称")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("*")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    TextField("例如：喀什站 / 甲运营商", text: $name)
                        .font(.body)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .prefixes }
                        .accessibilityIdentifier("groundStation.field.name")
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("地面站名前缀（多个用顿号、逗号隔开）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如：喀什、喀站", text: $prefixesText)
                        .font(.body)
                        .focused($focusedField, equals: .prefixes)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .exact }
                        .accessibilityIdentifier("groundStation.field.prefixes")
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("完整地面站名（每行一个，精确匹配优先）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如：喀什接收站 01", text: $exactStationsText, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .exact)
                        .accessibilityIdentifier("groundStation.field.exactStations")
                }
                .padding(.vertical, 2)
            } header: {
                Text("地面站匹配规则")
            } footer: {
                Text("前缀和完整站名至少填写一项。")
            }

            if isEditing, let idx = editingIndex, store.settings.passPlanOperators.indices.contains(idx) {
                Section {
                    Button(role: .destructive) {
                        store.settings.passPlanOperators.remove(at: idx)
                        store.flushSave(wait: true)
                        ToastCenter.shared.show("已删除地面站规则", style: .info)
                        dismiss()
                    } label: {
                        Label("删除此地面站规则", systemImage: "trash")
                    }
                    .accessibilityIdentifier("groundStation.editor.delete")
                }
            }
        }
        .appList()
        .scrollDismissesKeyboard(.interactively)
        .hidesFloatingTabBar()
        .navigationTitle(isEditing ? "编辑地面站" : "添加地面站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AppSaveToolbarButton(
                    title: "保存",
                    isSaving: isSaving,
                    accessibilityID: "groundStation.editor.save",
                    action: saveRule
                )
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { focusedField = nil }
                    .font(.subheadline.weight(.medium))
            }
        }
        .onAppear {
            guard !loadedInitial else { return }
            loadedInitial = true
            if let idx = editingIndex, store.settings.passPlanOperators.indices.contains(idx) {
                let existing = store.settings.passPlanOperators[idx]
                name = existing.name
                prefixesText = existing.prefixes.joined(separator: "、")
                exactStationsText = (existing.exactStations ?? []).joined(separator: "\n")
            } else {
                focusedField = .name
            }
        }
    }

    private var draftRule: PassPlan.OperatorRule {
        let prefixes = prefixesText
            .split(whereSeparator: { "、,，;；/ ".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let stations = exactStationsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return PassPlan.OperatorRule(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                     prefixes: prefixes, exactStations: stations.isEmpty ? nil : stations)
    }

    private func validationIssue(for rule: PassPlan.OperatorRule) -> (message: String, field: Field)? {
        if rule.name.isEmpty {
            return ("请填写必填项：地面站 / 运营商名称。", .name)
        }
        if rule.prefixes.isEmpty && (rule.exactStations ?? []).isEmpty {
            return ("请至少填写一项：地面站名前缀或完整地面站名。", .prefixes)
        }
        if store.settings.passPlanOperators.enumerated().contains(where: { index, existing in
            index != editingIndex && existing.name.trimmingCharacters(in: .whitespacesAndNewlines) == rule.name
        }) {
            return ("已存在名为「\(rule.name)」的地面站规则，请修改名称或返回列表直接编辑原条目。", .name)
        }
        return nil
    }

    private func saveRule() {
        guard !isSaving else { return }
        attemptedSave = true
        let newRule = draftRule
        if let issue = validationIssue(for: newRule) {
            focusedField = issue.field
            Haptics.warning()
            return
        }

        isSaving = true
        if let idx = editingIndex, store.settings.passPlanOperators.indices.contains(idx) {
            store.settings.passPlanOperators[idx] = newRule
        } else {
            store.settings.passPlanOperators.append(newRule)
        }
        // Flush immediately to disk so restarting the app strictly preserves the saved station
        store.flushSave(wait: true)
        focusedField = nil
        Haptics.success()
        ToastCenter.shared.show(isEditing ? "已更新「\(newRule.name)」" : "已添加「\(newRule.name)」", style: .success)
        dismiss()
    }
}
