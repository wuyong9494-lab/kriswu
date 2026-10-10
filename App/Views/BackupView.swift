import SwiftUI
import UniformTypeIdentifiers

/// 备份与恢复：把设置、排班、全员排班导出成一个文件，存到「文件」App 或发给自己；换手机或重装后再导入。
struct BackupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var confirmRestore: Data?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("导出备份文件", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Text("正在准备备份…").foregroundStyle(.secondary)
                }
            } footer: {
                Text("包含设置、你的排班、全员排班、组别说明和收藏的同事。可以选「存储到“文件”」，或发到微信「文件传输助手」。\n网站密码和 PushPlus token 不在备份里，恢复后要重新填一次。")
            }
            Section {
                Button {
                    importing = true
                } label: {
                    Label("从备份文件恢复", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("会用备份里的内容替换现在的设置和排班。")
            }
            if let message {
                Section { Text(message) }
            }
        }
        .navigationTitle("备份与恢复")
        .task { backupURL = try? store.backupFileURL() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    confirmRestore = try Data(contentsOf: url)
                } catch {
                    message = "读取文件失败：\(error.localizedDescription)"
                }
            case .failure(let error):
                message = "打开文件失败：\(error.localizedDescription)"
            }
        }
        .confirmationDialog("用这个备份替换现在的设置和排班吗？",
                            isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }),
                            titleVisibility: .visible) {
            Button("恢复", role: .destructive) {
                guard let data = confirmRestore else { return }
                do {
                    let days = try store.restore(from: data)
                    message = "已恢复 \(days) 天排班。记得到「账号与同步」重新填网站密码，到「微信推送」重新填 token。"
                } catch {
                    message = "这不是值班提醒的备份文件，或文件已损坏"
                }
                confirmRestore = nil
            }
        }
    }
}
