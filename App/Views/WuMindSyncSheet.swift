import SwiftUI
import UIKit

/// Zero-Knowledge End-to-End Encrypted Cross-Device Sync, iPhone ↔ iPad Account Pairing,
/// and Cloudflare Cron Results Pull sheet for WUMIND.
struct WuMindSyncSheet: View {
    @ObservedObject var store: WuMindStore
    @Environment(\.dismiss) private var dismiss

    @State private var passphrase = ""
    @State private var pairingCodeDraft = ""
    @State private var generatedPairCode: WuMindSyncPairingCode? = nil
    @State private var offlineEnvelopeDraft = ""
    @State private var statusBanner: String? = nil
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WuMindHubHeroBanner(
                        title: "零知识端到端加密同步",
                        subtitle: "本机 AES-256-GCM 加密后再上传，服务器绝不接触明文；支持 iPhone ↔ iPad 多设备互通与无网关离线迁移",
                        icon: "lock.shield.fill",
                        colors: [Color(red: 0.08, green: 0.44, blue: 0.56), Color(red: 0.24, green: 0.28, blue: 0.78)],
                        chips: [
                            ("加密标准", "AES-256-GCM"),
                            ("云端版本", store.cloudSyncVersion > 0 ? "v\(store.cloudSyncVersion)" : "未同步"),
                            ("本地对话", "\(store.conversations.count) 条")
                        ]
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                cloudVaultSection
                cronPullSection
                multiDevicePairSection
                offlineEncryptedBackupSection
            }
            .navigationTitle("跨设备加密同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("wumind.sync.sheet")
    }

    private var cloudVaultSection: some View {
        Section {
            if let last = store.lastCloudSyncAt {
                HStack {
                    Label("最近同步", systemImage: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("v\(store.cloudSyncVersion) · \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            SecureField("端到端加密口令（至少 4 位，仅在本机加解密）", text: $passphrase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("wumind.sync.passphrase")

            Button {
                runCloudPush()
            } label: {
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Label("加密上传对话、项目、记忆与定时任务至云端", systemImage: "icloud.and.arrow.up.fill")
                }
            }
            .disabled(busy || !store.hasGatewayURL || passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            .accessibilityIdentifier("wumind.sync.push")

            Button {
                runCloudPull()
            } label: {
                Label("从云端拉取并无损合并至本机", systemImage: "icloud.and.arrow.down.fill")
            }
            .disabled(busy || !store.hasGatewayURL || passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            .accessibilityIdentifier("wumind.sync.pull")

            if let msg = statusBanner {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.indigo)
            }
        } header: {
            Text("AES-256-GCM 零知识云端同步（D1）")
        } footer: {
            Text("所有对话、项目空间知识库、长期记忆与自定义 Skills 均先在当前设备以 AES-256-GCM 加密，再上传至你的 WUMIND Cloudflare D1 数据库；服务器绝不接触明文或口令。")
        }
    }

    private var cronPullSection: some View {
        Section {
            Button {
                runCronPull()
            } label: {
                Label("立即拉取 Cloudflare 云端定时任务执行结果", systemImage: "clock.arrow.circlepath")
            }
            .disabled(busy || !store.hasGatewayURL)
        } header: {
            Text("云端定时任务回拉")
        } footer: {
            Text("手机锁屏或离线期间由 Cloudflare Cron 准点执行的 AI 定时任务结果，会自动同步回本机对话列表并标注消耗费用。")
        }
    }

    private var multiDevicePairSection: some View {
        Section {
            Button {
                runCreatePairCode()
            } label: {
                Label("生成 10 分钟设备配对码（绑定另一台 iPhone / iPad）", systemImage: "link.badge.plus")
            }
            .disabled(busy || !store.hasGatewayURL)

            if let pair = generatedPairCode {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pair.code)
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(.indigo)
                        Text("10 分钟内有效，在另一台设备下方输入即可共享余额与加密同步库")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("复制") {
                        UIPasteboard.general.setItems([["public.utf8-plain-text": pair.code]], options: [.localOnly: true])
                        ToastCenter.shared.show("已复制配对码", style: .success)
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 8) {
                TextField("输入配对码（如 SYNC-XXXX-XXXX）", text: $pairingCodeDraft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("绑定") {
                    runClaimPairCode()
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(busy || !store.hasGatewayURL || pairingCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("多设备账号互通（iPhone ↔ iPad）")
        } footer: {
            Text("绑定后两台设备各自持有独立令牌，互不踢下线，共享同一个 WUMIND 账户余额、账单与云端加密同步库。")
        }
    }

    private var offlineEncryptedBackupSection: some View {
        Section {
            Button {
                do {
                    let envelope = try store.exportEncryptedBackupEnvelope(passphrase: passphrase)
                    UIPasteboard.general.setItems([["public.utf8-plain-text": envelope]], options: [.localOnly: true])
                    statusBanner = "已生成 AES-256-GCM 离线加密备份包并复制到剪贴板（无需网关也可跨设备转移）。"
                    ToastCenter.shared.show("已复制加密备份包", style: .success)
                } catch {
                    statusBanner = error.localizedDescription
                }
            } label: {
                Label("导出离线加密备份包（复制密文）", systemImage: "lock.doc.fill")
            }
            .disabled(passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)

            TextField("粘贴 WME1:... 加密备份密文进行无损合并恢复", text: $offlineEnvelopeDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                do {
                    let count = try store.importEncryptedBackupEnvelope(offlineEnvelopeDraft, passphrase: passphrase)
                    offlineEnvelopeDraft = ""
                    statusBanner = "离线解密成功，已无损合并 \(count) 项数据。"
                    ToastCenter.shared.show("已合并 \(count) 项数据", style: .success)
                } catch {
                    statusBanner = error.localizedDescription
                }
            } label: {
                Label("解密并合并离线备份包", systemImage: "lock.open.fill")
            }
            .disabled(passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count < 4
                      || offlineEnvelopeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("无网关离线端到端加密迁移")
        } footer: {
            Text("即使尚未部署 Cloudflare 网关，也可用上方同一口令在 iPhone 与 iPad 之间通过隔空投送/备忘录安全迁移全套对话、项目与长期记忆。")
        }
    }

    private func runCloudPush() {
        busy = true
        statusBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let ack = try await store.pushEncryptedCloudSync(passphrase: passphrase)
                statusBanner = "云端加密上传成功（版本 v\(ack.version)）。"
                ToastCenter.shared.show("已加密上传至云端", style: .success)
            } catch {
                statusBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func runCloudPull() {
        busy = true
        statusBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let merged = try await store.pullEncryptedCloudSync(passphrase: passphrase)
                statusBanner = merged > 0
                    ? "云端解密合并完成，新增/更新 \(merged) 项内容。"
                    : "云端与本机已是最新一致，或云端暂无备份。"
                ToastCenter.shared.show("云端同步完成", style: .success)
            } catch {
                statusBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func runCronPull() {
        busy = true
        statusBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let count = try await store.pullCloudCronResults()
                statusBanner = count > 0
                    ? "已同步 \(count) 条 Cloudflare 云端定时任务执行结果到对话列表。"
                    : "当前暂无新的云端定时执行结果。"
            } catch {
                statusBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func runCreatePairCode() {
        busy = true
        statusBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                generatedPairCode = try await store.createDevicePairingCode()
                statusBanner = "已生成 10 分钟设备配对码，请在另一台设备输入绑定。"
            } catch {
                statusBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func runClaimPairCode() {
        busy = true
        statusBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let reg = try await store.claimDevicePairingCode(pairingCodeDraft)
                pairingCodeDraft = ""
                statusBanner = String(format: "绑定成功！当前账号 %@，共享余额 ¥%.2f。", reg.userID, reg.balanceYuan)
                ToastCenter.shared.show("已绑定账号 \(reg.userID)", style: .success)
            } catch {
                statusBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
