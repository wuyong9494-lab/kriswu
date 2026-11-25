import SwiftUI

/// 今天页日期、今天的班、提醒横幅下面那些卡片
enum TodayCard: String, CaseIterable, Identifiable {
    case week, workLog, dutyInsight, tasks, changes, meeting, stats, games, favorites, upcoming, syncStatus

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
        case .games: return "小游戏"
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
        case .games: return "gamecontroller"
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

/// 今天页的卡片：可自由开关显示、一键上下调整顺序或开启拖拽排序
struct TodayLayoutView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editMode: EditMode = .inactive

    private var cards: [TodayCard] {
        store.settings.todayCards.filter { $0 != .games }
    }

    var body: some View {
        List {
            Section {
                DutySecondaryBanner(
                    title: "定制今天页卡片",
                    subtitle: "按常用习惯排序或关闭不常用的卡片；日期与今日主班次始终置顶。",
                    icon: "rectangle.stack.fill",
                    color: DS.Palette.accent,
                    badge: "\(cards.count - store.settings.hiddenTodayCards.count)/\(cards.count) 显示"
                )
            }

            Section {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    let shown = !store.settings.hiddenTodayCards.contains(card.rawValue)
                    HStack(spacing: DS.Space.s) {
                        IconBadge(icon: card.icon, color: shown ? nil : .secondary, size: 32)
                        Text(card.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(shown ? Color.primary : Color.secondary)
                        Spacer(minLength: 4)
                        if editMode == .inactive {
                            HStack(spacing: 4) {
                                Button { moveCard(card, delta: -1) } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.caption2.weight(.bold))
                                        .frame(width: 24, height: 24)
                                        .background(DS.Palette.surfaceSunken, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                Button { moveCard(card, delta: 1) } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.bold))
                                        .frame(width: 24, height: 24)
                                        .background(DS.Palette.surfaceSunken, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(index >= cards.count - 1)
                            }
                            .foregroundStyle(.secondary)
                            Toggle("", isOn: binding(card))
                                .labelsHidden()
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    var order = store.settings.todayCards.map(\.rawValue)
                    order.move(fromOffsets: from, toOffset: to)
                    store.settings.todayCardOrder = order
                }
            } header: {
                Text("卡片顺序与开关")
            } footer: {
                Text("点上下箭头可微调顺序，或点右上角「拖拽排序」快速重排。")
            }

            if !store.settings.todayCardOrder.isEmpty || !store.settings.hiddenTodayCards.isEmpty {
                Section {
                    Button {
                        withAnimation(DS.Motion.snappy) {
                            store.settings.todayCardOrder = []
                            store.settings.hiddenTodayCards = []
                        }
                    } label: {
                        Label("恢复默认顺序并全部显示", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .appList()
        .navigationTitle("今天页的卡片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(editMode == .active ? "完成" : "拖拽排序") {
                    withAnimation(DS.Motion.snappy) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
        }
    }

    private func moveCard(_ card: TodayCard, delta: Int) {
        var order = store.settings.todayCards.map(\.rawValue)
        guard let i = order.firstIndex(of: card.rawValue) else { return }
        let target = i + delta
        guard order.indices.contains(target) else { return }
        withAnimation(DS.Motion.snappy) {
            order.swapAt(i, target)
            store.settings.todayCardOrder = order
        }
    }

    private func binding(_ card: TodayCard) -> Binding<Bool> {
        Binding(get: { !store.settings.hiddenTodayCards.contains(card.rawValue) }, set: { on in
            var hidden = store.settings.hiddenTodayCards.filter { $0 != card.rawValue }
            if !on { hidden.append(card.rawValue) }
            store.settings.hiddenTodayCards = hidden
        })
    }
}
