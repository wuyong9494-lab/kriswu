import SwiftUI
import UIKit

struct DeepSeekPlanKeyView: View {
    @ObservedObject private var wumind = WuMindStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var configured = false
    @State private var testing = false
    @State private var successMsg: String?
    @State private var failure: String?

    private var trimmed: String { MultiProviderAIClient.sanitizePastedKey(draft) }

    var body: some View {
        NavigationStack {
            Form {
                let state = wumind.verification(for: .deepSeek)
                Section {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(state?.dotColor ?? Color.secondary.opacity(0.45))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state?.badgeText ?? "未配置")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(state?.dotColor ?? .secondary)
                            Text(state?.summary ?? "尚未保存本机 DeepSeek API Key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("当前真实连接状态（api.deepseek.com）")
                }

                Section {
                    SecureField(configured ? "已保存，输入新的可替换" : "输入 DeepSeek API Key", text: $draft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        saveAndVerify()
                    } label: {
                        HStack {
                            Spacer()
                            if testing { ProgressView().controlSize(.small) }
                            Text(testing ? "正在联网测试连接…" : "保存并立即测试连接")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(testing || (trimmed.isEmpty && !configured))

                    Button("仅保存到本机（不联网测试）") { saveOnly() }
                        .disabled(testing || trimmed.isEmpty)

                    if configured {
                        Button("移除本机 Key", role: .destructive) {
                            if Keychain.setDeepSeekPlanAPIKey("") {
                                configured = false
                                draft = ""
                                failure = nil
                                successMsg = nil
                                wumind.markProviderRemoved(.deepSeek)
                            } else {
                                failure = "未能移除 Key。请解锁设备后重试。"
                            }
                        }
                        .disabled(testing)
                    }
                    if let successMsg {
                        Label(successMsg, systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    if let failure {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } footer: {
                    Text("Key 仅保存在这台设备的系统钥匙串。只有通过联网验证或实际对话成功后才会显示绿色「已连接」。")
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("DeepSeek API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onAppear { configured = !(Keychain.get(.deepSeekPlanAPIKey) ?? "").isEmpty }
        }
    }

    private func persistKey() -> String? {
        failure = nil
        successMsg = nil
        let value = trimmed
        if !value.isEmpty {
            guard value.utf8.count <= 512, value.utf8.allSatisfy({ (33...126).contains($0) }) else {
                failure = "Key 格式不正确。请只粘贴 API Key，不要带换行或空格。"
                return nil
            }
            guard Keychain.setDeepSeekPlanAPIKey(value) else {
                failure = "未能保存 Key。请解锁设备后重试。"
                return nil
            }
            configured = true
            draft = ""
            wumind.markProviderSaved(.deepSeek)
            return value
        }
        return Keychain.get(.deepSeekPlanAPIKey)
    }

    private func saveOnly() {
        guard persistKey() != nil else { return }
        dismiss()
    }

    private func saveAndVerify() {
        guard !testing, let activeKey = persistKey() else { return }
        testing = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            defer { testing = false }
            do {
                let probe = try await MultiProviderAIClient().probeAndListModels(
                    provider: .openAI,
                    apiKey: activeKey,
                    baseURL: "https://api.deepseek.com/v1"
                )
                wumind.markProviderVerified(.deepSeek, host: "api.deepseek.com", modelCount: max(2, probe.models.count))
                successMsg = "验证成功！已连接 api.deepseek.com（DeepSeek V4 Pro / Flash 可用）。"
            } catch let diag as AIProviderDiagnosticError {
                failure = diag.errorDescription
                wumind.markProviderFailed(.deepSeek, host: "api.deepseek.com", summary: diag.shortBadgeSummary)
            } catch {
                failure = "连接 api.deepseek.com 失败，请检查网络或 API Key。"
                wumind.markProviderFailed(.deepSeek, host: "api.deepseek.com", summary: "api.deepseek.com · 连接失败")
            }
        }
    }
}

enum DeepSeekPlanPhoto {
    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "无法载入这张图，请重新选择清晰的计划截图或照片"
        }
    }

    /// Draw into a new buffer to apply EXIF orientation and exclude source metadata,
    /// including GPS coordinates. Keep readable photo dimensions with a memory ceiling.
    @MainActor
    static func jpegWithoutMetadata(_ image: UIImage) -> Data? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { return nil }
        let factor = min(1, 8_000 / max(width, height), sqrt(24_000_000 / (width * height)))
        let size = CGSize(width: max(1, (width * factor).rounded(.down)),
                          height: max(1, (height * factor).rounded(.down)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let rectangle = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.96) {
            $0.cgContext.setFillColor(UIColor.white.cgColor)
            $0.cgContext.fill(rectangle)
            image.draw(in: rectangle)
        }
    }
}
