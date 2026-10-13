import SwiftUI

/// 「这次更新了什么」：更新后第一次打开弹出来，设置里也能再看。新版本加了功能就改 id 和 items。
enum WhatsNew {
    /// 换成新的 id，所有人下次打开都会再弹一次
    static let id = "1.2"
    static let seenKey = "whatsNewSeen"

    struct Item: Identifiable {
        var id: String { title }
        let icon: String
        let title: String
        let detail: String
    }

    static let items: [Item] = [
        Item(icon: "checklist", title: "清单记进工作留痕",
             detail: "勾过的清单每天存一份：工作留痕里按天看做了几件、哪件没做；分享当天留痕、生成交接小结时也会带上。"),
        Item(icon: "timer", title: "值班倒计时带上清单",
             detail: "值遥测时锁屏和灵动岛上的倒计时会显示清单做了几件、下一件是什么，点一下直接打开这一天。"),
        Item(icon: "text.bubble", title: "说法更好懂",
             detail: "「猜中」「模型」「自动判断」这类说法换成了大白话；同步出错时直接告诉你该怎么办。"),
        Item(icon: "bolt", title: "打开更快",
             detail: "「下次遥测」改在后台算好再显示，打开今天页不再卡一下。"),
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
