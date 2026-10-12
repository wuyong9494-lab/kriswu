import SwiftUI
import UniformTypeIdentifiers

/// 备份与恢复：把设置、排班、全员排班导出成一个文件，存到「文件」App 或发给自己；换手机或重装后再导入。
struct BackupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var choosingFolder = false
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
                Text("包含设置、你的排班、全员排班、组别说明和收藏的同事。可以选「存储到“文件”」，或发到微信「文件传输助手」。\n网站密码和 PushPlus token 不在备份里：同一台手机删掉重装时手机还记着，换新手机要重新填一次。")
            }
            Section {
                Button {
                    choosingFolder = true
                } label: {
                    Label(store.settings.backupFolderBookmark == nil ? "选择自动备份的文件夹" : "换一个文件夹",
                          systemImage: "folder.badge.gearshape")
                }
                .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result { store.setBackupFolder(url) }
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
                Text("建议选「iCloud 云盘」里新建的文件夹：之后每天打开 App 或同步时自动存一份（只留最近 8 份），删掉 App、换手机都还在。恢复时点下面的「从备份文件恢复」，选最新的一份。")
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
                    backupURL = try? store.backupFileURL()
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
