import SwiftUI

/// 值班表：某一天所有岗位各是谁，和网页版「值班查看」一样；支持卡片化展示、左右滑动切日与本人高亮。
struct DayRosterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var day: DayKey

    init(day: DayKey = .today) {
        _day = State(initialValue: day)
    }

    private var date: Binding<Date> {
        Binding(get: { day.date(calendar: .app, hour: 12) },
                set: { day = DayKey(date: $0, calendar: .app) })
    }

    var body: some View {
        let rows = store.dayRoster(day)
        let totalPeople = Set(rows.flatMap(\.names)).count
        ScrollView {
            LazyVStack(spacing: DS.Space.m) {
                // 顶部日期切换大卡
                VStack(spacing: DS.Space.s) {
                    HStack(spacing: DS.Space.s) {
                        Button {
                            Haptics.tap()
                            day = day.adding(days: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 36, height: 36)
                                .background(DS.Palette.surfaceSunken, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("前一天")

                        Spacer()

                        DatePicker("日期", selection: date, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "zh_CN"))

                        Spacer()

                        Button {
                            Haptics.tap()
                            day = day.adding(days: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 36, height: 36)
                                .background(DS.Palette.surfaceSunken, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("后一天")
                    }

                    Divider()

                    HStack(spacing: DS.Space.xs) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.dateText)
                                .font(DS.Font.headline)
                            Text(rows.isEmpty ? "暂无全员排班" : "\(rows.count) 个岗位 · \(totalPeople) 位值班人员")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if day != .today {
                            Button {
                                Haptics.tap()
                                day = .today
                            } label: {
                                Text("回到今天")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(DS.Palette.accentSoft, in: Capsule())
                                    .foregroundStyle(DS.Palette.accent)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Chip(text: "今天", color: DS.Palette.accent, icon: "sun.max.fill")
                        }
                    }
                }
                .card()

                if rows.isEmpty {
                    EmptyState(
                        icon: "tablecells",
                        title: store.roster.isEmpty ? "暂无全员排班数据" : "这一天暂无排班",
                        message: store.roster.isEmpty
                            ? "同步时 App 会读取「值班查看」全员排班；回到「今天」页下拉刷新一次即可。"
                            : "只能查看值班网站上已发布排班的日期，可左右滑切换其他日期。"
                    )
                    .card()
                } else {
                    ForEach(rows, id: \.post) { row in
                        let display = ShiftDisplay(raw: row.post, matcher: store.matcher)
                        let tint = display?.color ?? DS.Palette.accent
                        let note = store.groupNotes[row.post.filter { !$0.isWhitespace }.uppercased()]
                        let hasMe = row.names.contains { store.isMe($0) }

                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            HStack(spacing: DS.Space.xs) {
                                IconBadge(icon: display?.symbol ?? "pin.fill", color: tint, size: 32)
                                Text(row.post)
                                    .font(DS.Font.headline)
                                if hasMe {
                                    Chip(text: "我在本岗", color: DS.Palette.accent)
                                }
                                Spacer()
                                Text("\(row.names.count) 人")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            // 人员徽章网格（自动多列排布，本人加粗高亮）
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(row.names, id: \.self) { person in
                                    let isMe = store.isMe(person)
                                    NavigationLink {
                                        MemberScheduleView(name: person)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Avatar(name: person, size: 22)
                                            Text(person)
                                                .font(.subheadline.weight(isMe ? .bold : .medium))
                                                .foregroundStyle(isMe ? .white : .primary)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            isMe ? DS.Palette.accent : DS.Palette.surfaceSunken,
                                            in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if let note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            }
                        }
                        .card(tint: hasMe ? DS.Palette.accent : nil)
                    }
                }
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xl)
            .frame(maxWidth: DS.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle("值班表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    WorkloadView()
                } label: {
                    Label("工作量", systemImage: "chart.bar")
                }
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
            if value.translation.width < -60 { day = day.adding(days: 1) }
            if value.translation.width > 60 { day = day.adding(days: -1) }
        })
    }
}
