import SwiftUI

struct WuMindInlineBuildCard: View {
    let workID: String
    let onPreview: (WuMindLocalWork) -> Void
    @ObservedObject private var works = WuMindWorksStore.shared

    var body: some View {
        if let work = works.works.first(where: { $0.id == workID }), work.isCompleted {
            HStack(spacing: 10) {
                Button {
                    onPreview(work)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(work.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(work.workType.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.chat.buildResult")
                if let url = works.localAssetURL(for: work) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("分享作品文件")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
