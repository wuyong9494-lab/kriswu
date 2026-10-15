import SwiftUI

/// 组别说明：要做的事一条一行（网站上用「●」隔开的、「1. 2. 3.」编号的都拆开），
/// 电脑版表格右边那列的注意事项单独一块；太长时先显示前几条，点「展开全部」看完。
struct GroupNoteView: View {
    /// 一天几个组时写上是哪个组
    let group: String?
    let note: String
    /// 注意事项那一块的底色（今天页的彩色卡片上用半透明白色）
    var cautionBackground: Color = Color.secondary.opacity(0.12)
    @State private var expanded = false

    private static let workPreview = 4
    private static let cautionPreview = 2

    var body: some View {
        let parts = GroupNotes.split(note)
        let work = GroupNotes.displayLines(parts.work)
        let caution = parts.caution.map(GroupNotes.displayLines) ?? []
        let long = work.count > Self.workPreview || caution.count > Self.cautionPreview
        let shownWork = expanded ? work : Array(work.prefix(Self.workPreview))
        let shownCaution = expanded ? caution : Array(caution.prefix(Self.cautionPreview))
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if let group { Text(group).font(DS.Font.headline) }
            if !shownWork.isEmpty { lines(shownWork) }
            if !shownCaution.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label("注意事项", systemImage: "exclamationmark.triangle.fill")
                        .font(DS.Font.caption.weight(.semibold))
                    lines(shownCaution)
                }
                .padding(DS.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cautionBackground, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
            }
            if long {
                Button(expanded ? "收起" : "展开全部（\(work.count + caution.count) 条）") {
                    withAnimation(DS.Motion.spring) { expanded.toggle() }
                }
                .font(DS.Font.caption.weight(.semibold))
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lines(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(DS.Font.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
