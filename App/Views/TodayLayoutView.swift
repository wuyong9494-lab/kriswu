import SwiftUI

/// 今天页日期、今天的班、提醒横幅下面那些卡片
enum TodayCard: String, CaseIterable, Identifiable {
    case week, workLog, dutyInsight, tasks, changes, meeting, stats, favorites, upcoming, syncStatus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "接下来 7 天"
        case .workLog: return "工作留痕"
        case .dutyInsight: return "下次遥测、排班预警"
        case .tasks: return "今天的清单"
        case .changes: return "最近的排班变动"
        case .meeting: return "周会问题"
        case .stats: return "本月数字、常用功能"
        case .favorites: return "收藏的同事"
        case .upcoming: return "再往后两周"
        case .syncStatus: return "同步状态"
        }
    }

    var icon: String {
        switch self {
        case .week: return "calendar.day.timeline.left"
        case .workLog: return "camera"
        case .dutyInsight: return "antenna.radiowaves.left.and.right"
        case .tasks: return "checklist"
        case .changes: return "arrow.triangle.2.circlepath"
        case .meeting: return "doc.text.magnifyingglass"
        case .stats: return "chart.bar"
        case .favorites: return "star"
        case .upcoming: return "list.bullet"
        case .syncStatus: return "icloud"
        }
    }
}

extension AppSettings {
    /// 今天页卡片按自己排的顺序（新加的卡片按默认位置插进去）
    var todayCards: [TodayCard] {
        CardOrder.resolve(stored: todayCardOrder, defaults: TodayCard.allCases.map(\.rawValue)).compactMap(TodayCard.init)
    }
}

/// 今天页的卡片：拖着调顺序，关掉用不着的
struct TodayLayoutView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            Section {
                ForEach(store.settings.todayCards) { card in
                    let shown = !store.settings.hiddenTodayCards.contains(card.rawValue)
                    Toggle(isOn: binding(card)) {
                        Label {
                            Text(card.title).foregroundStyle(shown ? Color.primary : Color.secondary)
                        } icon: {
                            Image(systemName: card.icon).foregroundStyle(shown ? DS.Palette.accent : Color.secondary)
                        }
                    }
                }
                .onMove { from, to in
                    var order = store.settings.todayCards.map(\.rawValue)
                    order.move(fromOffsets: from, toOffset: to)
                    store.settings.todayCardOrder = order
                }
            } footer: {
                Text("按住右边的三道杠拖动调顺序，关掉的卡片不在今天页显示。日期、今天的班和各种提醒横幅总在最上面。")
            }
            if !store.settings.todayCardOrder.isEmpty || !store.settings.hiddenTodayCards.isEmpty {
                Section {
                    Button("恢复默认顺序、全部显示") {
                        store.settings.todayCardOrder = []
                        store.settings.hiddenTodayCards = []
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .appList()
        .navigationTitle("今天页的卡片")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(_ card: TodayCard) -> Binding<Bool> {
        Binding(get: { !store.settings.hiddenTodayCards.contains(card.rawValue) }, set: { on in
            var hidden = store.settings.hiddenTodayCards.filter { $0 != card.rawValue }
            if !on { hidden.append(card.rawValue) }
            store.settings.hiddenTodayCards = hidden
        })
    }
}
