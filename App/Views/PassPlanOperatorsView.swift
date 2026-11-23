import SwiftUI

/// 运营商对照表：可登记精确站名，也可明确设置一组站的共同前缀。
struct PassPlanOperatorsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmingPaste = false
    @State private var pasted: [PassPlan.OperatorRule] = []

    var body: some View {
        List {
            Section {
                // 按位置编辑（按内容做标识的话，每打一个字这一行就变成「另一行」，输入框会丢焦点）
                ForEach(Array(store.settings.passPlanOperators.indices), id: \.self) { i in
                    let rule = binding(i)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("运营商名字", text: rule.name)
                            .font(.subheadline.weight(.semibold))
                        TextField("地面站名开头，几种用顿号隔开", text: prefixes(rule))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ExactStationField(stations: rule.exactStations)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { store.settings.passPlanOperators.remove(atOffsets: $0) }
                .onMove { store.settings.passPlanOperators.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    store.settings.passPlanOperators.append(PassPlan.OperatorRule(name: "", prefixes: []))
                } label: {
                    Label("加一家", systemImage: "plus")
                }
            } header: {
                Text("\(store.settings.passPlanOperators.count) 家（发的时候按这个顺序）")
            } footer: {
                Text("先查完整站名；同一个完整站名登记给多家时不会自动分。没有精确匹配时，只有最长前缀唯一指向一家才自动分。启用对照表后，未匹配的站不会再按「-」自行归类。")
            }
            Section {
                // 系统的粘贴按钮：不会弹「是否允许粘贴」
                HStack {
                    Text("粘贴导入")
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
                    ToastCenter.shared.show("复制好了", style: .success)
                } label: {
                    Label("复制成文字", systemImage: "doc.on.doc")
                }
                .disabled(store.settings.passPlanOperators.isEmpty)
            } footer: {
                Text("一行一家，例如「甲：甲光、=北区接收站 01」。带「=」的只匹配完整站名，不会匹配相似名字；只写运营商名表示以它为前缀。")
            }
        }
        .environment(\.editMode, .constant(.active))
        .appList()
        .navigationTitle("运营商对照表")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("读到 \(pasted.count) 家", isPresented: $confirmingPaste, titleVisibility: .visible) {
            Button("替换现在的表") { store.settings.passPlanOperators = pasted }
            Button("合并进去（保留原有站名和前缀）") { store.settings.passPlanOperators = merged(pasted) }
        } message: {
            Text(pasted.map(\.name).joined(separator: "、"))
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
        TextField("完整地面站名（每行一个）", text: $draft, axis: .vertical)
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
