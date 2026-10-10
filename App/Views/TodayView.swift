import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: DayKey?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let today = DayKey(date: context.date, calendar: .app)
                ScrollView {
                    VStack(spacing: 16) {
                        Text(context.date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day().weekday(.wide)))
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let days = SigningInfo.daysLeft, days <= 2 {
                            Label("签名还有 \(days) 天到期：打开 LocalDevVPN，再到 SideStore 点「Refresh All」续签",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                        }
                        if store.schedule.isEmpty {
                            EmptyScheduleHint()
                        }
                        ShiftCard(label: "今天", day: today, large: true,
                                  reminder: store.settings.morningEnabled ? "每天 \(store.settings.morning.text) 提醒" : nil)
                            .onTapGesture { editing = today }
                        ShiftCard(label: "明天", day: today.adding(days: 1), large: false,
                                  reminder: store.settings.eveningEnabled ? "前一天 \(store.settings.evening.text) 提醒" : nil)
                            .onTapGesture { editing = today.adding(days: 1) }
                        UpcomingList(from: today.adding(days: 2), count: 12) { editing = $0 }
                        SyncStatus()
                    }
                    .padding()
                }
            }
            .refreshable { await store.sync() }
            .navigationTitle("值班提醒")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { searching = true } label: {
                        Label("搜索成员", systemImage: "magnifyingglass")
                    }
                }
            }
            .sheet(item: $editing) { DayEditor(day: $0) }
            .sheet(isPresented: $searching) { MemberSearchView() }
        }
    }
}

struct ShiftCard: View {
    @EnvironmentObject private var store: AppStore
    let label: String
    let day: DayKey
    let large: Bool
    let reminder: String?

    var body: some View {
        let display = ShiftDisplay(raw: store.shift(on: day), matcher: store.matcher)
        HStack(spacing: 16) {
            Text(display?.emoji ?? "📅")
                .font(.system(size: large ? 56 : 36))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(label) · \(day.dateText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(display?.name ?? (store.isCovered(day) ? "未排班" : "暂无数据"))
                    .font(large ? .largeTitle.bold() : .title2.bold())
                    .foregroundStyle(display == nil ? Color.secondary : Color.primary)
                // 这个组要干什么（电脑版网页上的说明，或自己在设置里填写的）
                ForEach(store.notes(for: store.shift(on: day)), id: \.group) { item in
                    Text(store.notes(for: store.shift(on: day)).count > 1 ? "\(item.group)：\(item.note)" : item.note)
                        .font(large ? .subheadline : .footnote)
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reminder {
                    Label(reminder, systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(large ? 24 : 16)
        .background((display?.color ?? .gray).opacity(0.18), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke((display?.color ?? .gray).opacity(0.5), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

private struct UpcomingList: View {
    @EnvironmentObject private var store: AppStore
    let from: DayKey
    let count: Int
    let onTap: (DayKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("接下来")
                .font(.headline)
                .padding(.bottom, 8)
            ForEach(0..<count, id: \.self) { i in
                let day = from.adding(days: i)
                let display = ShiftDisplay(raw: store.shift(on: day), matcher: store.matcher)
                Button { onTap(day) } label: {
                    HStack {
                        Text(day.dateText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let display {
                            Text("\(display.emoji) \(display.name)")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(display.color.opacity(0.18), in: Capsule())
                        } else if store.isCovered(day) {
                            Text("未排班")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.18), in: Capsule())
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                if i < count - 1 { Divider() }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct EmptyScheduleHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("还没有排班数据", systemImage: "tray")
                .font(.headline)
            Text("到「设置」里填写排班网址自动同步，或者导入/粘贴排班表；也可以在「日历」里逐天点选。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SyncStatus: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 4) {
            if store.isSyncing {
                ProgressView("正在同步…")
            } else if store.canSync {
                if let message = store.settings.lastSyncMessage {
                    Text(message)
                }
                if let last = store.settings.lastSync {
                    Text("上次成功同步：\(last.formatted(date: .abbreviated, time: .shortened))")
                }
                Text("下拉可刷新")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
