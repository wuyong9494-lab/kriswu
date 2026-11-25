import SwiftUI
import UIKit

/// Flagship WUMIND AI Capability Workshop — dedicated entrances by modality
/// (Image Studio, Realtime Voice, Audio TTS/STT, Code, Work, Tender Draft).
/// Multi-provider text chat switching lives directly on the WUMIND home screen.
@MainActor
struct AIProviderListView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var pageBg: Color {
        isDark ? Color(red: 0.035, green: 0.04, blue: 0.06) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.095, green: 0.105, blue: 0.14) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WuMindHubHeroBanner(
                    title: "WUMIND 能力工坊",
                    subtitle: "多厂商文字对话直接在 WUMIND 首页一键切换；此处按生图、生视频、写 PPT、实时语音与标书分入口",
                    icon: "square.grid.2x2.fill",
                    colors: [Color(red: 0.20, green: 0.28, blue: 0.78), Color(red: 0.48, green: 0.24, blue: 0.80)],
                    chips: [
                        ("专项工坊", "8 大能力入口"),
                        ("协议分离", "聊天 / 生图 / 视频 / 语音独立")
                    ]
                )

                Text("多模态创作与实时交互")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                NavigationLink { AIImageToolView() } label: {
                    capabilityCard(
                        title: "文字生图画室",
                        subtitle: "GPT Image 2 · Grok Imagine 2.0 · Nano Banana 2 · 极速 JPEG 直出与一键超清",
                        badge: "极速并发",
                        icon: "photo.on.rectangle.angled",
                        accent: .purple
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.tools.image")

                NavigationLink { AIVideoToolView() } label: {
                    capabilityCard(
                        title: "AI 生视频工坊",
                        subtitle: "Grok Imagine Video · OpenAI Sora 2 · Google Veo 3 · 电影运镜与 MP4 成片导出",
                        badge: "Sora / Veo",
                        icon: "video.badge.waveform.fill",
                        accent: .pink
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.tools.video")

                NavigationLink { WuMindPPTStudioView() } label: {
                    capabilityCard(
                        title: "AI 写 PPT 工坊",
                        subtitle: "高管级 16:9 多页演示自动编排 · 4 套视觉主题 · 一键导出 1920×1080 演示 PDF",
                        badge: "16:9 PDF",
                        icon: "rectangle.on.rectangle.angled",
                        accent: .orange
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.tools.ppt")

                NavigationLink { AILiveCallView() } label: {
                    capabilityCard(
                        title: "实时语音通话",
                        subtitle: "OpenAI Realtime 全双工低延迟语音交互，独立 WebSocket 音频通道",
                        badge: "Realtime",
                        icon: "phone.waveform.fill",
                        accent: .teal
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.tools.live")

                NavigationLink { AISpeechToolView() } label: {
                    capabilityCard(
                        title: "语音合成与转写",
                        subtitle: "系统离线朗读 · xAI 拟真音色合成 · OpenAI 录音转文字",
                        badge: "TTS / STT",
                        icon: "waveform",
                        accent: .indigo
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.tools.speech")

                Text("专业代码与办公工坊")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                NavigationLink { AICodeWorkToolsView(kind: .code) } label: {
                    capabilityCard(
                        title: "代码助手",
                        subtitle: "代码生成、架构解释与防御性安全审阅，支持自定义中转站模型",
                        badge: "Code",
                        icon: "curlybraces",
                        accent: .orange
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.tools.code")

                NavigationLink { AICodeWorkToolsView(kind: .work) } label: {
                    capabilityCard(
                        title: "办公与值班助手",
                        subtitle: "公文草稿、要点纪要、交班汇总，并直连数传计划复核",
                        badge: "Work",
                        icon: "briefcase.fill",
                        accent: .blue
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.tools.work")

                NavigationLink { DeepSeekTenderView() } label: {
                    capabilityCard(
                        title: "投标书草稿工坊",
                        subtitle: "导入 PDF / Word 招标文件，DeepSeek Flash 提取要点 + V4 Pro 起草章节",
                        badge: "DeepSeek",
                        icon: "doc.text.fill",
                        accent: Color(red: 0.24, green: 0.44, blue: 0.96)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.tools.tender")
            }
            .padding(14)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(pageBg.ignoresSafeArea())
        .navigationTitle("AI 工具箱")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func capabilityCard(
        title: String,
        subtitle: String,
        badge: String,
        icon: String,
        accent: Color
    ) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.13), in: Capsule())
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isDark ? 0.28 : 0.05), radius: 8, y: 3)
    }
}

// MARK: - Flagship Provider API Key & Custom Relay Config Sheet

@MainActor
struct ProviderKeyView: View {
    let provider: AIProvider
    let changed: (Bool) -> Void
    @ObservedObject private var wumind = WuMindStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var stored = false
    @State private var draft = ""
    @State private var baseURLDraft = ""
    @State private var testing = false
    @State private var testSuccess: String? = nil
    @State private var error: String? = nil

    private var wmProvider: WuMindProvider? { WuMindProvider.from(provider) }
    private var isDark: Bool { colorScheme == .dark }
    private var pageBg: Color {
        isDark ? Color(red: 0.04, green: 0.045, blue: 0.065) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.10, green: 0.11, blue: 0.145) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }
    private var accent: Color {
        wmProvider?.brandColor ?? DS.Palette.accent
    }

    private var hasKeyToSave: Bool {
        !MultiProviderAIClient.sanitizePastedKey(draft).isEmpty
    }

    private var endpointChanged: Bool {
        let current = AIProviderEndpoints.baseURL(for: provider) ?? ""
        return baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines) != current
    }

    private var previewTargetHost: String {
        let trimmed = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return provider.resolvedHost(baseURL: trimmed.isEmpty ? nil : trimmed)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let wmProvider {
                        let state = wumind.verification(for: wmProvider)
                        let verifiedCount = wumind.verifiedModelCount(for: wmProvider)
                        WuMindHubHeroBanner(
                            title: "\(provider.displayName) 接口配置",
                            subtitle: "密钥仅存 iOS 本机钥匙串，绝不回显。先校验「目录可读」，再在模型中心点「试跑」检验单个模型。",
                            icon: wmProvider.iconName,
                            colors: [accent, accent.opacity(0.68)],
                            chips: [
                                ("连接状态", state?.badgeText ?? "未配置"),
                                ("已试跑可用", "\(verifiedCount) 个模型")
                            ]
                        )
                    }

                    // API Key Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("API Key（仅存本机钥匙串）")
                            .font(.subheadline.weight(.bold))

                        SecureField(stored ? "已存，输入新 Key 可替换（自动去除 Bearer 前缀）" : "粘贴 API Key", text: $draft)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("ai.key.input")
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    // Endpoint Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("自定义 API 接口地址（中转站 / 代理，选填）")
                            .font(.subheadline.weight(.bold))

                        TextField("留空使用官方：\(provider.defaultBaseURLString)", text: $baseURLDraft)
                            .font(.subheadline)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("ai.baseurl.input")

                        HStack(spacing: 6) {
                            Image(systemName: "network")
                                .font(.caption)
                                .foregroundStyle(accent)
                            Text("当前将请求域名：\(previewTargetHost)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        if provider == .openAI {
                            HStack(spacing: 8) {
                                endpointChip("官方默认", value: "")
                                endpointChip("OpenRouter", value: "https://openrouter.ai/api/v1")
                                endpointChip("硅基流动", value: "https://api.siliconflow.cn/v1")
                            }
                        } else if !baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("恢复官方默认地址") { baseURLDraft = "" }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)
                        }

                        Text("官方 Key 请让此处留空；中转站 Key 必须填写发 Key 服务商提供的 HTTPS 地址，否则会返回 HTTP 401。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    // Action Buttons Card
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            saveAndVerify()
                        } label: {
                            HStack(spacing: 8) {
                                if testing { ProgressView().controlSize(.small).tint(.white) }
                                Text(testing ? "正在校验目录可达性…" : "保存并拉取模型目录")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                (testing || (!hasKeyToSave && !stored))
                                    ? Color.secondary.opacity(0.35) : accent,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(testing || (!hasKeyToSave && !stored))
                        .accessibilityIdentifier("ai.key.verify")

                        HStack(spacing: 10) {
                            Button {
                                saveOnly(remove: false)
                            } label: {
                                Text("仅保存本机")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(testing || (!hasKeyToSave && !(stored && endpointChanged)))

                            if stored {
                                Button(role: .destructive) {
                                    saveOnly(remove: true)
                                } label: {
                                    Text("移除 Key")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(DS.Palette.danger)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(DS.Palette.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(testing)
                            }
                        }

                        if let testSuccess {
                            Label(testSuccess, systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }

                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.danger)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DS.Palette.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("拉取目录成功会标记蓝色「目录可读」；具体模型通过「试跑」或实际回答成功后才点亮绿色「已试跑可用」。报错仅展示目标域名与脱敏错误码，绝不暴露 Key。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .padding(14)
            }
            .background(pageBg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("\(provider.displayName) 配置")
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
            .onAppear {
                stored = Keychain.providerChatAPIKey(provider) != nil
                baseURLDraft = AIProviderEndpoints.baseURL(for: provider) ?? ""
            }
        }
    }

    private func endpointChip(_ title: String, value: String) -> some View {
        let active = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines) == value
        return Button(title) {
            baseURLDraft = value
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? accent : Color.secondary.opacity(0.14), in: Capsule())
        .foregroundStyle(active ? .white : .primary)
        .buttonStyle(.plain)
    }

    private func persistInputs() -> (key: String, endpoint: String?)? {
        error = nil
        testSuccess = nil
        let cleanedEndpoint = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try AIProvider.normalizedBaseURL(cleanedEndpoint.isEmpty ? nil : cleanedEndpoint)
        } catch {
            self.error = "接口地址格式不正确：必须以 https:// 开头，例如 https://openrouter.ai/api/v1。"
            return nil
        }

        let cleanedKey = MultiProviderAIClient.sanitizePastedKey(draft)
        let activeKey: String
        if !cleanedKey.isEmpty {
            guard cleanedKey.utf8.count <= 512, cleanedKey.utf8.allSatisfy({ (33...126).contains($0) }) else {
                error = "Key 格式不正确。请粘贴纯 API Key，勿包含中文、空格或账号密码。"
                return nil
            }
            guard Keychain.setProviderChatAPIKey(cleanedKey, provider: provider) else {
                error = "未能更新 Key，请解锁设备后重试。"
                return nil
            }
            activeKey = cleanedKey
            stored = true
        } else if let existing = Keychain.providerChatAPIKey(provider) {
            activeKey = existing
        } else {
            error = "请先填写 API Key。"
            return nil
        }

        let finalEndpoint = cleanedEndpoint.isEmpty ? nil : cleanedEndpoint
        AIProviderEndpoints.setBaseURL(finalEndpoint, for: provider)
        draft = ""
        if let wmProvider {
            wumind.markProviderSaved(wmProvider)
        }
        return (activeKey, finalEndpoint)
    }

    private func saveOnly(remove: Bool) {
        error = nil
        testSuccess = nil
        if remove {
            guard Keychain.setProviderChatAPIKey("", provider: provider) else {
                error = "未能移除 Key，请解锁设备后重试。"
                return
            }
            AIProviderEndpoints.setBaseURL(nil, for: provider)
            if let wmProvider {
                wumind.markProviderRemoved(wmProvider)
            }
            draft = ""
            baseURLDraft = ""
            stored = false
            changed(false)
            dismiss()
            return
        }

        guard persistInputs() != nil else { return }
        changed(true)
        dismiss()
    }

    private func saveAndVerify() {
        guard !testing, let saved = persistInputs() else { return }
        testing = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            defer { testing = false }
            do {
                let probe = try await MultiProviderAIClient().probeAndListModels(
                    provider: provider,
                    apiKey: saved.key,
                    baseURL: saved.endpoint
                )
                let chatCount = probe.models.filter(\.supportsTextChat).count
                if let wmProvider {
                    wumind.updateCachedModels(probe.models, for: wmProvider, verifiedHost: probe.host)
                }
                testSuccess = "目录读取成功（\(probe.host)），共列出 \(chatCount) 个聊天模型。请回到模型中心点击任意模型「试跑」验证真实对话权限。"
                changed(true)
            } catch let diag as AIProviderDiagnosticError {
                error = diag.errorDescription
                if let wmProvider {
                    wumind.markProviderFailed(wmProvider, host: diag.host, summary: diag.shortBadgeSummary)
                }
                changed(true)
            } catch {
                let host = provider.resolvedHost(baseURL: saved.endpoint)
                self.error = "测试失败（请求域名：\(host)）：\((error as? LocalizedError)?.errorDescription ?? "网络异常")"
                if let wmProvider {
                    wumind.markProviderFailed(wmProvider, host: host, summary: "\(host) · 连接失败")
                }
                changed(true)
            }
        }
    }
}
