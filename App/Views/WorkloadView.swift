import SwiftUI

/// 每个人一个月的工作量：上班天数、各组各几天、休息几天（数据来自同步读到的全员排班）。
struct WorkloadView: View {
    @EnvironmentObject private var store: AppStore
    @State private var year = DayKey.today.year
    @State private var month = DayKey.today.month

    var body: some View {
        let report = store.workload(year: year, month: month)
        List {
            Section {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(verbatim: "\(year)年\(month)月").font(.headline)
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)
            } footer: {
                Text(report.days.isEmpty
                     ? "这个月还没有全员排班数据。在「今天」页下拉刷新会读取网站「值班查看」。"
                     : "统计范围：已读到全员排班的 \(report.days.count) 天（\(report.days.first!.dateText) – \(report.days.last!.dateText)）。网站上能看到的日子才算得进来。")
            }
            ForEach(report.people, id: \.name) { person in
                Section {
                    HStack {
                        Text(person.name)
                            .font(.headline)
                            .foregroundStyle(store.isMe(person.name) ? Color.accentColor : Color.primary)
                        Spacer()
                        Text("上班 \(person.workDays) 天").bold()
                        if person.offDays > 0 {
                            Text("· 休 \(person.offDays)").foregroundStyle(.secondary)
                        }
                    }
                    FlowChips(items: person.posts.map { (text: "\($0.post) ×\($0.count)", raw: $0.post) })
                }
            }
        }
        .navigationTitle("工作量统计")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: report.text) { Label("分享", systemImage: "square.and.arrow.up") }
            }
        }
    }

    private func move(_ delta: Int) {
        var m = month + delta, y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        month = m; year = y
    }
}

/// 一行放不下自动换行的小标签。
private struct FlowChips: View {
    @EnvironmentObject private var store: AppStore
    let items: [(text: String, raw: String)]

    var body: some View {
        // iOS 16 没有现成的流式布局：每行最多 4 个
        let rows = stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.text) { item in
                        let display = ShiftDisplay(raw: item.raw, matcher: store.matcher)
                        Text(item.text)
                            .font(.footnote)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((display?.color ?? .gray).opacity(0.18), in: Capsule())
                    }
                }
            }
        }
    }
}
