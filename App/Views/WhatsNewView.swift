import SwiftUI

/// 「这次更新了什么」：更新后第一次打开弹出来，设置里也能再看。新版本加了功能就改 id 和 items。
enum WhatsNew {
    /// 换成新的 id，所有人下次打开都会再弹一次
    static let id = "1.1"
    static let seenKey = "whatsNewSeen"

    struct Item: Identifiable {
        var id: String { title }
        let icon: String
        let title: String
        let detail: String
    }

    static let items: [Item] = [
        Item(icon: "calendar.badge.plus", title: "新排班出来会通知",
             detail: "网站排出新一周时马上告诉你这几天的班，有遥测的直接写在标题里。"),
        Item(icon: "checkmark.shield", title: "更稳、更省电",
             detail: "同步失败可以直接重新登录或重试；后台不会再误报失败；数据存得更安全，页面更流畅。"),
        Item(icon: "alarm", title: "接遥测前提醒",
             detail: "设置 › 提醒 里可以设遥测接班时间，接班前 30 分钟、1 小时、2 小时或前一天晚上提醒你。"),
        Item(icon: "calendar", title: "日历里看谁值遥测",
             detail: "日历每天格子下面写着当天值遥测的人；点年月可以直接跳到任意一天。"),
        Item(icon: "arrow.left.arrow.right.square", title: "一键交接小结",
             detail: "今天页「工作留痕」里点「生成交接小结」，清单和当天的记录自动整理成一段话。"),
        Item(icon: "doc.plaintext", title: "每周一的一周小结",
             detail: "上周上了几天、遥测几次、待休多少、这周的班和下次遥测，周一发给你。"),
        Item(icon: "square.and.arrow.up", title: "更多分享",
             detail: "请假规划一键生成请假说明；排班可以导出成日历文件发给家人；留痕可以整天一起分享。"),
        Item(icon: "pin", title: "网站公告有更新会通知",
             detail: "公告出现新内容马上通知，今天页也会显示；设置 › 网站公告 可以看全部。"),
        Item(icon: "antenna.radiowaves.left.and.right", title: "快轮到你值遥测会提前说",
             detail: "网站还没排、按顺序推算一周内轮到你时，提前通知一次（只是推算，可在 设置 › 提醒 关掉）。"),
        Item(icon: "arrow.left.arrow.right", title: "换班一键发请求",
             detail: "找人换班里，每个候选人都能直接复制或发送换班请求，能换回来的日子也写好了。"),
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
