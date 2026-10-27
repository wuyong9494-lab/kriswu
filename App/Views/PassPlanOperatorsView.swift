import SwiftUI

/// 运营商对照表：每家的地面站名开头是什么。站名有「-」的（「甲站-北区01」）不用写，按「-」前面的名字分；
/// 站名和运营商叫法不一样的、一家有好几种站名的才要写。只存在这台手机上
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
                Text("比如「乙：乙光、丁站」：站名以「乙光」或「丁站」开头的都算乙。几个前缀都对得上时按最长的那个。站名带「-」的（「甲站-北区01」）表里没有也会按「-」前面的名字分。发计划时遇到对不上的站，在那一页点一下就能加进来。")
            }
            Section {
                Button {
                    pasted = PassPlan.parseRules(UIPasteboard.general.string ?? "")
                    if pasted.isEmpty {
                        ToastCenter.shared.show("剪贴板里没有对照表：一行一家，写成「名字：前缀、前缀」", style: .error)
                    } else {
                        confirmingPaste = true
                    }
                } label: {
                    Label("粘贴导入", systemImage: "doc.on.clipboard")
                }
                Button {
                    UIPasteboard.general.string = PassPlan.rulesText(store.settings.passPlanOperators)
                    ToastCenter.shared.show("复制好了", style: .success)
                } label: {
                    Label("复制成文字", systemImage: "doc.on.doc")
                }
                .disabled(store.settings.passPlanOperators.isEmpty)
            } footer: {
                Text("文字格式：一行一家，「名字：前缀、前缀」；只写名字的，前缀就是名字。")
            }
        }
        .environment(\.editMode, .constant(.active))
        .appList()
        .navigationTitle("运营商对照表")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("读到 \(pasted.count) 家", isPresented: $confirmingPaste, titleVisibility: .visible) {
            Button("替换现在的表") { store.settings.passPlanOperators = pasted }
            Button("合并进去（同名的加上新前缀）") { store.settings.passPlanOperators = merged(pasted) }
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
