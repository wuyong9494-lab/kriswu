import SwiftUI

/// 用电脑版打开值班网站：自己找到「值班查看」页面，点「读取本页」把上面各组的说明存下来。
struct DesktopNotesBrowser: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WebModel(userAgent: WebPageLoader.desktopUserAgent)
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                WebView(webView: model.webView)
                Text(toast ?? "登录后打开「值班查看」，看到上面各组的说明后点「读取本页」")
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
            .navigationTitle("电脑版网页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { model.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    Spacer()
                    Button("读取本页") {
                        Task {
                            guard let html = await model.html() else { return }
                            // 顺便存下这一页周表里的全员排班
                            let weekRoster = RosterExtractor.fromDesktopHTML(html, reference: .today, matcher: store.matcher)
                            store.mergeRoster(weekRoster)
                            let notes = SyncService.groupNotes(fromHTML: html, reference: .today)
                            if notes.isEmpty {
                                toast = "这一页上没认出「组A」等说明" + (weekRoster.isEmpty ? "。换到「值班查看」页面再试"
                                    : "，但存下了 \(weekRoster.count) 人的本页排班")
                                store.desktopPageText = "网址：\(model.webView.url?.absoluteString ?? "")\n\n"
                                    + String(HTMLText.toText(html).prefix(6000))
                            } else {
                                // 记住这个地址，以后每天自动从这里读
                                store.settings.desktopNotesURL = model.webView.url?.absoluteString ?? store.settings.desktopNotesURL
                                await store.applyDesktopNotes(notes)
                                dismiss()
                            }
                        }
                    }
                    .bold()
                }
            }
            .onAppear {
                model.credentials = (store.settings.sourceUsername, Keychain.get(.sourcePassword) ?? "")
                let custom = store.settings.desktopNotesURL
                if !custom.isEmpty {
                    model.load(custom)
                } else if let url = SyncService.desktopDutyURL(from: store.settings.sourceURL) {
                    model.load(url.absoluteString)
                }
            }
        }
    }
}
