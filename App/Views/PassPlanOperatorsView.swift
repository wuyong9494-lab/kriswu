import SwiftUI

/// 运营商对照表与发送顺序管理：可登记完整站名或站名前缀，顺序即「按顺序发送」的先后顺序。
struct PassPlanOperatorsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editMode: EditMode = .inactive
    @State private var confirmingPaste = false
    @State private var pasted: [PassPlan.OperatorRule] = []

    var body: some View {
        List {
            Section {
                if store.settings.passPlanOperators.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("还没有配置运营商对照表", systemImage: "list.number")
                            .font(.subheadline.weight(.semibold))
                        Text("点击下方「新增一家运营商」或粘贴导入对照表；排列顺序就是「按顺序依次发送」时的先后顺序。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                // 按位置编辑（避免内容变化导致输入框失焦）
                ForEach(Array(store.settings.passPlanOperators.indices), id: \.self) { i in
                    let rule = binding(i)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("#\(i + 1)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(DS.Palette.accentSoft, in: Capsule())
                                .foregroundStyle(DS.Palette.accent)

                            TextField("运营商名称（如：甲站）", text: rule.name)
                                .font(.subheadline.weight(.semibold))

                            if editMode == .inactive {
                                HStack(spacing: 4) {
                                    Button {
                                        moveRule(from: i, offset: -1)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.caption.weight(.bold))
                                            .frame(width: 26, height: 26)
                                            .background(DS.Palette.surfaceSunken, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(i == 0)

                                    Button {
                                        moveRule(from: i, offset: 1)
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.caption.weight(.bold))
                                            .frame(width: 26, height: 26)
                                            .background(DS.Palette.surfaceSunken, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(i >= store.settings.passPlanOperators.count - 1)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("前缀")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .leading)
                            TextField("地面站名开头，多个用顿号隔开", text: prefixes(rule))
                                .font(.footnote)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text("完整站")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .leading)
                                .padding(.top, 2)
                            ExactStationField(stations: rule.exactStations)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { store.settings.passPlanOperators.remove(atOffsets: $0) }
                .onMove { store.settings.passPlanOperators.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    withAnimation(DS.Motion.snappy) {
                        store.settings.passPlanOperators.append(PassPlan.OperatorRule(name: "", prefixes: []))
                    }
                } label: {
                    Label("新增一家运营商", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                }
            } header: {
                Text("\(store.settings.passPlanOperators.count) 家（按此顺序依次发送）")
            } footer: {
                Text("先精确匹配完整站名；无精确匹配时按最长唯一前缀归类。点上下箭头或右上角「排序」可随时调整发送顺序。")
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
                Text("一行一家，例如「甲：甲光、=北区接收站 01」。带「=」只匹配完整站名；只写运营商名表示以它为前缀。")
            }
        }
        .environment(\.editMode, $editMode)
        .appList()
        .navigationTitle("运营商与发送顺序")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(editMode == .active ? "完成" : "排序/删除") {
                    withAnimation(DS.Motion.snappy) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
        }
        .confirmationDialog("读到 \(pasted.count) 家运营商", isPresented: $confirmingPaste, titleVisibility: .visible) {
            Button("替换现有列表") { store.settings.passPlanOperators = pasted }
            Button("合并进去（保留原有规则）") { store.settings.passPlanOperators = merged(pasted) }
        } message: {
            Text(pasted.map(\.name).joined(separator: "、"))
        }
    }

    private func moveRule(from index: Int, offset: Int) {
        let target = index + offset
        guard store.settings.passPlanOperators.indices.contains(index),
              store.settings.passPlanOperators.indices.contains(target) else { return }
        withAnimation(DS.Motion.snappy) {
            store.settings.passPlanOperators.swapAt(index, target)
        }
    }

    /// 第 i 家（删掉以后界面还没刷新时不会越界）
    private func binding(_ i: Int) -> Binding<PassPlan.OperatorRule> {
        Binding(get: {
            store.settings.passPlanOperators.indices.contains(i) ? store.settings.passPlanOperators[i] : PassPlan.OperatorRule(name: "", prefixes: [])
        }, set: { rule in
            if store.settings.passPlanOperators.indices.contains(i) { store.settings.passPlanOperators[i] = rule }
        })
    }

    /// 前缀写成「乙光、丁站」编辑
    private func prefixes(_ rule: Binding<PassPlan.OperatorRule>) -> Binding<String> {
        Binding(get: { rule.wrappedValue.prefixes.joined(separator: "、") }, set: { text in
            rule.wrappedValue.prefixes = text.split(whereSeparator: { "、,，;；/ ".contains($0) }).map(String.init)
        })
    }

    private func merged(_ new: [PassPlan.OperatorRule]) -> [PassPlan.OperatorRule] {
        PassPlan.parseRules(PassPlan.rulesText(store.settings.passPlanOperators) + "\n" + PassPlan.rulesText(new))
    }
}

private struct ExactStationField: View {
    @Binding var stations: [String]?
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        TextField("完整地面站名（每行一个，可选）", text: $draft, axis: .vertical)
            .font(.footnote)
            .lineLimit(1...4)
            .focused($editing)
            .onAppear { refresh() }
            .onChange(of: stations) { _ in if !editing { refresh() } }
            .onChange(of: draft) { text in
                guard editing else { return }
                let list = text.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                stations = list.isEmpty ? nil : list
            }
            .onChange(of: editing) { focused in if !focused { refresh() } }
    }

    private func refresh() { draft = (stations ?? []).joined(separator: "\n") }
}
