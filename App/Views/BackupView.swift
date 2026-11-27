import SwiftUI
import UniformTypeIdentifiers

/// 备份与恢复：把设置、排班、全员排班导出成一个文件，存到「文件」App 或发给自己；换手机或重装后再导入。
struct BackupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var backupURL: URL?
    @State private var backupError: String?
    @State private var backupAttempt = 0
    /// 选文件夹（自动备份）还是选备份文件（恢复）
    @State private var pickFolder = false
    @State private var showImporter = false
    @State private var confirmRestore: Data?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("导出备份文件", systemImage: "square.and.arrow.up")
                    }
                } else if let backupError {
                    AppErrorBannerCard(message: backupError, retryTitle: "重试") { backupAttempt += 1 }
                } else {
                    ProgressView("正在准备备份…")
                }
            } header: {
                Text("手动导出")
            } footer: {
                Text("备份包含设置、个人与全员排班、组别说明和收藏。网站密码及推送凭据留在系统钥匙串。")
            }
            Section {
                Button {
                    pickFolder = true
                    showImporter = true
                } label: {
                    Label(store.settings.backupFolderBookmark == nil ? "选择自动备份的文件夹" : "换一个文件夹",
                          systemImage: "folder.badge.gearshape")
                }
                if store.settings.backupFolderBookmark != nil {
                    if let message = store.settings.autoBackupMessage {
                        Text(message).font(.footnote)
                    }
                    if let last = store.settings.lastAutoBackup {
                        LabeledContent("上次自动备份", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("现在备份一次") { store.autoBackupIfNeeded(force: true) }
                    Button("停止自动备份", role: .destructive) {
                        store.settings.backupFolderBookmark = nil
                        store.settings.backupFolderName = nil
                        store.settings.autoBackupMessage = nil
                    }
                }
            } header: {
                Text("自动备份")
            } footer: {
                Text("选择文件夹后，每天打开 App 或同步时会自动备份，保留最近 8 份。可选 iCloud 云盘以跨设备访问。")
            }
            Section {
                Button {
                    pickFolder = false
                    showImporter = true
                } label: {
                    Label("从备份文件恢复", systemImage: "square.and.arrow.down")
                }
                .disabled(!store.canEdit)
                ReadOnlyNotice()
            } header: {
                Text("恢复排班与设置")
            } footer: {
                Text("会用备份里的内容替换现在的设置和排班。")
            }
            if let message {
                Section { Text(message) }
            }
        }
        .appList()
        .navigationTitle("备份与恢复")
        .task(id: backupAttempt) {
            backupError = nil
            do { backupURL = try store.backupFileURL() }
            catch { backupError = "无法生成备份：\(error.localizedDescription)" }
        }
        // 一个页面只能有一个 fileImporter：选文件夹和选备份文件共用，看是哪个按钮打开的
        .fileImporter(isPresented: $showImporter, allowedContentTypes: pickFolder ? [.folder] : [.json, .data]) { result in
            if pickFolder {
                if case .success(let url) = result { store.setBackupFolder(url) }
                return
            }
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
                    backupURL = nil
                    backupAttempt += 1
                    message = "已恢复 \(days) 天排班，正在重新同步。换了新手机的话，到「账号与同步」填网站密码，到「微信推送」填 token。"
                        + (Keychain.get(.sourcePassword) == nil ? "\n（这台手机上没有保存的密码，需要重新填）" : "")
                } catch {
                    message = "这不是值班提醒的备份文件，或文件已损坏"
                }
                confirmRestore = nil
            }
        }
    }
}
