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
                    LabeledContent("本地对话", value: "\(store.conversations.count) 条")
                    LabeledContent("云端版本", value: store.cloudSyncVersion > 0 ? "v\(store.cloudSyncVersion)" : "未同步")
                    SecureField("加密口令（至少 4 位）", text: $passphrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wumind.sync.passphrase")
                } footer: {
                    Text("上传和离线导出前会先在本机加密。还原数据时需要相同的口令。")
                }
                if let statusBanner { Section { Text(statusBanner).font(DS.Font.callout) } }
                cloudVaultSection
                cronPullSection
                multiDevicePairSection
                offlineEncryptedBackupSection
            }
            .appList()
            .scrollDismissesKeyboard(.interactively)
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
            Button {
                runCloudPush()
            } label: {
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Label("上传加密备份", systemImage: "icloud.and.arrow.up.fill")
                }
            }
            .disabled(busy || !store.hasGatewayURL || passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            .accessibilityIdentifier("wumind.sync.push")

            Button {
                runCloudPull()
            } label: {
                Label("从云端合并到本机", systemImage: "icloud.and.arrow.down.fill")
            }
            .disabled(busy || !store.hasGatewayURL || passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            .accessibilityIdentifier("wumind.sync.pull")

        } header: {
            Text("云端备份")
        } footer: {
            Text("包含对话、项目、长期记忆、技能和定时任务。")
        }
    }

    private var cronPullSection: some View {
        Section {
            Button {
                runCronPull()
            } label: {
                Label("获取任务结果", systemImage: "clock.arrow.circlepath")
            }
            .disabled(busy || !store.hasGatewayURL)
        } header: {
            Text("定时任务")
        } footer: {
            Text("已完成的云端任务会同步到本机对话列表。")
        }
    }

    private var multiDevicePairSection: some View {
        Section {
            Button {
                runCreatePairCode()
            } label: {
                Label("生成设备配对码", systemImage: "link.badge.plus")
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
            Text("设备配对")
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
                Label("复制加密备份", systemImage: "lock.doc.fill")
            }
            .disabled(passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)

            TextField("粘贴加密备份内容", text: $offlineEnvelopeDraft)
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
                Label("解密并合并", systemImage: "lock.open.fill")
            }
            .disabled(passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count < 4
                      || offlineEnvelopeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("离线备份")
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
