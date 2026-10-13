import SwiftUI

/// 「这次更新了什么」：更新后第一次打开弹出来，设置里也能再看。新版本加了功能就改 id 和 items。
enum WhatsNew {
    /// 换成新的 id，所有人下次打开都会再弹一次
    static let id = "2026-10-13"
    static let seenKey = "whatsNewSeen"

    struct Item: Identifiable {
        var id: String { title }
        let icon: String
        let title: String
        let detail: String
    }

    static let items: [Item] = [
        Item(icon: "sparkles.rectangle.stack", title: "排班预演",
             detail: "网站还没排的日子，先推演谁值遥测、谁在休息；网站排出来后自动对比猜中了多少。在「统计 › 排班预演」。"),
        Item(icon: "antenna.radiowaves.left.and.right", title: "遥测推算更准",
             detail: "研发岗、生产岗两条线分开轮，按网站人员表里各人能值的星期几推算。"),
        Item(icon: "flag", title: "节假日值班预测",
             detail: "按网站公告的规则排出下个节假日的预留名单；法定节假日每年自动更新，不用手动录入。"),
        Item(icon: "bed.double", title: "休息统一不算工作量",
             detail: "休息、调休、请假、值班交接前都算休息；假期里值完遥测第二天的休息算上班天数和节假日上班。"),
        Item(icon: "person.2", title: "休息那列几个人都能读",
             detail: "一格里不管写了几个人、怎么隔开，都能全部读到。"),
        Item(icon: "exclamationmark.triangle", title: "该休没休提醒",
             detail: "网站标了你该休没休，会马上提醒你；待休天数直接用网站上的数。"),
        Item(icon: "globe", title: "装好就能用",
             detail: "值班网站地址已经内置，输入自己的账号密码同步一次，App 会自动认出你是谁。"),
        Item(icon: "bell.badge", title: "点通知看详情",
             detail: "全员排班变动的通知，点开直接看是谁、哪天、从什么班改成什么班。"),
        Item(icon: "scope", title: "组别显示负责的星",
             detail: "今天卡片上的组别说明，最前面写着这组负责哪几颗星。"),
    ]
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WhatsNew.items) { item in
                        HStack(alignment: .top, spacing: DS.Space.m) {
                            IconBadge(icon: item.icon, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(DS.Font.headline)
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("这次更新了什么")
                }
            }
            .appList()
            .navigationTitle("新功能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("知道了") { dismiss() }
                }
            }
        }
        .onDisappear { UserDefaults.standard.set(WhatsNew.id, forKey: WhatsNew.seenKey) }
    }
}
