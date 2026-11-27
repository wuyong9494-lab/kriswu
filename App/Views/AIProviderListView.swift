import SwiftUI
import UIKit

/// The workbench and tool directory share the same ten existing destinations.
struct WuMindStudioLink: Identifiable {
    let destination: WuMindWorkspaceView.ToolboxDestination
    let title: String
    let icon: String
    let keywords: String
    let workbenchID: String
    var id: String { destination.rawValue }

    static let all: [Self] = [
        .init(destination: .image, title: "生图", icon: "photo", keywords: "图片 局部编辑 画室 image", workbenchID: "wumind.quick.image"),
        .init(destination: .video, title: "视频", icon: "video", keywords: "生成 短剧 分镜 剪辑 video", workbenchID: "wumind.quick.video"),
        .init(destination: .ppt, title: "PPT", icon: "rectangle.on.rectangle.angled", keywords: "演示 幻灯片 汇报", workbenchID: "wumind.quick.ppt"),
        .init(destination: .spatial3d, title: "3D 空间", icon: "cube", keywords: "建模 人物 建筑 CAD", workbenchID: "wumind.quick.spatial3d"),
        .init(destination: .tender, title: "标书", icon: "doc.text", keywords: "投标 招标 PDF Word", workbenchID: "deepSeek.chat.tender"),
        .init(destination: .code, title: "编程", icon: "chevron.left.forwardslash.chevron.right", keywords: "代码 工程 code", workbenchID: "wumind.quick.code"),
        .init(destination: .live, title: "实时语音", icon: "phone", keywords: "语音 通话 对讲", workbenchID: "wumind.quick.live"),
        .init(destination: .speech, title: "语音合成与转写", icon: "waveform", keywords: "音频 朗读 转文字 TTS STT", workbenchID: "wumind.quick.speech"),
        .init(destination: .work, title: "办公助手", icon: "briefcase", keywords: "值班 公文 交班", workbenchID: "wumind.quick.work"),
        .init(destination: .agentOS, title: "项目与智能体", icon: "square.stack.3d.up", keywords: "工具 项目空间 智能体", workbenchID: "wumind.quick.agentOS")
    ]
}

extension WuMindWorkspaceView.ToolboxDestination {
    @MainActor @ViewBuilder
    var page: some View {
        switch self {
        case .hub: AIProviderListView()
        case .live: AILiveCallView()
        case .image: AIImageToolView()
        case .video: AIVideoToolView()
        case .spatial3d: WuMindSpatial3DStudioView()
        case .agentOS: WuMindAgentWorkspaceView()
        case .ppt: WuMindPPTStudioView()
        case .speech: AISpeechToolView()
        case .code: AICodeWorkToolsView(kind: .code)
        case .work: AICodeWorkToolsView(kind: .work)
        case .tender: DeepSeekTenderView()
        }
    }
}

@MainActor
struct AIProviderListView: View {
    var body: some View {
        List(WuMindStudioLink.all) { studio in
            NavigationLink { studio.destination.page } label: {
                Label(studio.title, systemImage: studio.icon)
                    .font(DS.Font.body)
                    .padding(.vertical, DS.Space.xxs)
            }
            .accessibilityIdentifier("ai.tools." + studio.id)
        }
        .appList()
        .navigationTitle("工具")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Flagship Provider API Key & Custom Relay Config Sheet

@MainActor
struct ProviderKeyView: View {
    let provider: AIProvider
    var initialService: AICompatibleChatService? = nil
    let changed: (Bool) -> Void
    @ObservedObject private var wumind = WuMindStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var stored = false
    @State private var draft = ""
    @State private var baseURLDraft = ""
    @State private var advancedExpanded = false
    @State private var customService = false
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

    private var previewTargetHost: String {
        let trimmed = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return provider.resolvedHost(baseURL: trimmed.isEmpty ? nil : trimmed)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let wmProvider {
                        let activeScope = try? provider.personalConnectionID(baseURL: AIProviderEndpoints.baseURL(for: provider))
                        let draftScope = try? provider.personalConnectionID(baseURL: baseURLDraft)
                        let service = provider == .openAI ? AICompatibleChatService.matching(baseURLDraft) : nil
                        let current = wumind.selectedProvider == wmProvider && activeScope == draftScope
                            ? wumind.selectedModelName : (service?.model ?? provider.defaultChatModel).displayName
                        Text("\(current) · \(previewTargetHost)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if provider == .openAI {
                        Picker("服务商", selection: Binding(
                            get: { customService ? nil : AICompatibleChatService.matching(baseURLDraft) },
                            set: { service in
                                customService = service == nil
                                draft = ""
                                error = nil
                                testSuccess = nil
                                if let service {
                                    baseURLDraft = service.baseURL ?? ""
                                    advancedExpanded = false
                                } else {
                                    advancedExpanded = true
                                }
                            }
                        )) {
                            ForEach(AICompatibleChatService.allCases) { service in
                                Text(service.displayName).tag(Optional(service))
                            }
                            Text("自定义").tag(Optional<AICompatibleChatService>.none)
                        }
                        .disabled(testing)
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

                    DisclosureGroup("高级设置", isExpanded: $advancedExpanded) {
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

                            if !baseURLDraft.isEmpty {
                                Button("恢复官方地址") {
                                    baseURLDraft = ""
                                    customService = false
                                }
                                .font(.caption.weight(.semibold))
                            }

                            Text("官方 Key 请让此处留空；中转站 Key 必须填写发 Key 服务商提供的 HTTPS 地址，否则会返回 HTTP 401。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    // Action Buttons Card
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            saveOnly(remove: false)
                        } label: {
                            HStack(spacing: 8) {
                                if testing { ProgressView().controlSize(.small).tint(.white) }
                                Text("保存 Key")
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
                        .accessibilityIdentifier("ai.key.save")

                        HStack(spacing: 10) {
                            Button {
                                saveAndVerify()
                            } label: {
                                Text(testing ? "正在读取目录…" : "读取可用模型（可选）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(testing || (!hasKeyToSave && !stored))
                            .accessibilityIdentifier("ai.key.verify")

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
            .onChange(of: baseURLDraft) { url in
                stored = Keychain.providerChatAPIKey(provider, baseURL: url) != nil
            }
            .onAppear {
                if let initialService {
                    baseURLDraft = initialService.baseURL ?? ""
                } else {
                    baseURLDraft = AIProviderEndpoints.baseURL(for: provider) ?? ""
                }
                stored = Keychain.providerChatAPIKey(provider, baseURL: baseURLDraft) != nil
                customService = provider == .openAI && AICompatibleChatService.matching(baseURLDraft) == nil
                advancedExpanded = !baseURLDraft.isEmpty && (customService || provider != .openAI)
            }
        }
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
        let finalEndpoint = cleanedEndpoint.isEmpty ? nil : cleanedEndpoint
        if !cleanedKey.isEmpty {
            guard cleanedKey.utf8.count <= 512, cleanedKey.utf8.allSatisfy({ (33...126).contains($0) }) else {
                error = "Key 格式不正确。请粘贴纯 API Key，勿包含中文、空格或账号密码。"
                return nil
            }
            guard Keychain.setProviderChatAPIKey(cleanedKey, provider: provider, baseURL: finalEndpoint) else {
                error = "未能更新 Key，请解锁设备后重试。"
                return nil
            }
            activeKey = cleanedKey
            stored = true
        } else if let existing = Keychain.providerChatAPIKey(provider, baseURL: finalEndpoint) {
            activeKey = existing
        } else {
            error = "请先填写 API Key。"
            return nil
        }

        let changedConnection = (try? provider.personalConnectionID(baseURL: finalEndpoint))
            != (try? provider.personalConnectionID(baseURL: AIProviderEndpoints.baseURL(for: provider)))
        wumind.activateOwnEndpoint(finalEndpoint, for: provider)
        draft = ""
        if let wmProvider, changedConnection || !cleanedKey.isEmpty {
            wumind.markProviderSaved(wmProvider)
        }
        return (activeKey, finalEndpoint)
    }

    private func saveOnly(remove: Bool) {
        error = nil
        testSuccess = nil
        if remove {
            guard Keychain.setProviderChatAPIKey("", provider: provider, baseURL: baseURLDraft) else {
                error = "未能移除 Key，请解锁设备后重试。"
                return
            }
            let removesActive = (try? provider.personalConnectionID(baseURL: baseURLDraft)) == (try? provider.personalConnectionID(baseURL: AIProviderEndpoints.baseURL(for: provider)))
            if let wmProvider, removesActive {
                wumind.markProviderRemoved(wmProvider)
            }
            draft = ""
            baseURLDraft = ""
            stored = false
            changed(Keychain.providerChatAPIKey(provider) != nil)
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

// MARK: - Decoupled AIHubMix Connection Config Sheet (Own API)

@MainActor
struct AIHubMixConnectionSheet: View {
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var baseURLDraft: String = "https://aihubmix.com/v1"
    @State private var keyDraft: String = ""
    @State private var hasDedicatedKey: Bool = false
    @State private var reusedOpenAIHost: String? = nil
    @State private var testing: Bool = false
    @State private var statusMessage: String? = nil
    @State private var errorMessage: String? = nil

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
    private let accent = Color(red: 0.44, green: 0.26, blue: 0.86)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WuMindHubHeroBanner(
                        title: "AIHubMix 统一生图连接",
                        subtitle: "保存一套 AIHubMix Base URL 与 Key，画室即可按协议分别调用 GPT Image 与 Nano Banana 2，不影响现有 GPT 聊天配置且不扣 WuMind 余额。",
                        icon: "network.badge.shield.half.filled",
                        colors: [accent, Color(red: 0.24, green: 0.48, blue: 0.92)],
                        chips: [
                            ("连接来源", hasDedicatedKey ? "AIHubMix 独立连接" : (reusedOpenAIHost != nil ? "已自动复用 GPT 栏" : "未配置")),
                            ("计费归属", "AIHubMix 账户")
                        ]
                    )

                    if let reusedOpenAIHost, !hasDedicatedKey {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("已检测到 GPT 栏中的 AIHubMix 连接（\(reusedOpenAIHost)）")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text("画室已自动复用这套 Base URL 与 Key 调用 GPT Image 与 Nano Banana 2，无需重复粘贴。如需与 GPT 聊天分开计费，也可在下方保存独立 AIHubMix Key。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(13)
                        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.green.opacity(0.28), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("AIHubMix API Key（仅存本机钥匙串）")
                            .font(.subheadline.weight(.bold))

                        SecureField(
                            hasDedicatedKey ? "已存独立 Key，输入新 Key 可替换" : "粘贴 sk-... 格式的 AIHubMix Key",
                            text: $keyDraft
                        )
                        .font(.subheadline)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("ai.aihubmix.key")

                        DisclosureGroup("高级设置") {
                            Text("Base URL（仅允许 AIHubMix / Inferera 域名）")
                                .font(.subheadline.weight(.bold))
                                .padding(.top, 4)

                            TextField("https://aihubmix.com/v1", text: $baseURLDraft)
                                .font(.subheadline)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityIdentifier("ai.aihubmix.baseURL")

                            HStack(spacing: 8) {
                                quickHostChip("aihubmix.com/v1", url: "https://aihubmix.com/v1")
                                quickHostChip("api.inferera.com/v1", url: "https://api.inferera.com/v1")
                            }

                            Text("安全域名隔离：AIHubMix 密钥只会发往已验证的聚合域名，绝不会发往 api.openai.com 或 generativelanguage.googleapis.com。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            saveAndVerify()
                        } label: {
                            HStack(spacing: 8) {
                                if testing { ProgressView().controlSize(.small).tint(.white) }
                                Text(testing ? "正在校验 AIHubMix 连通性…" : "保存并校验 AIHubMix 连接")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                (testing || (!hasDedicatedKey && MultiProviderAIClient.sanitizePastedKey(keyDraft).isEmpty))
                                    ? Color.secondary.opacity(0.35) : accent,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(testing || (!hasDedicatedKey && MultiProviderAIClient.sanitizePastedKey(keyDraft).isEmpty))
                        .accessibilityIdentifier("ai.aihubmix.save")

                        HStack(spacing: 10) {
                            Button {
                                if persistInputs() != nil {
                                    AIProviderEndpoints.imageStudioOwnConnectionPreference = .aihubmix
                                    onChanged()
                                    dismiss()
                                }
                            } label: {
                                Text("仅保存本机")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(testing || (!hasDedicatedKey && MultiProviderAIClient.sanitizePastedKey(keyDraft).isEmpty))

                            if hasDedicatedKey {
                                Button(role: .destructive) {
                                    _ = Keychain.setAIHubMixAPIKey("")
                                    AIProviderEndpoints.setAIHubMixBaseURL(nil)
                                    hasDedicatedKey = false
                                    keyDraft = ""
                                    baseURLDraft = "https://aihubmix.com/v1"
                                    onChanged()
                                    dismiss()
                                } label: {
                                    Text("移除独立连接")
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

                        if let statusMessage {
                            Label(statusMessage, systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.danger)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DS.Palette.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .padding(14)
            }
            .background(pageBg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("AIHubMix 连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                hasDedicatedKey = Keychain.aihubmixAPIKey != nil
                if let savedURL = AIProviderEndpoints.aihubmixBaseURL {
                    baseURLDraft = savedURL
                }
                if let conn = AIProviderEndpoints.resolvedAIHubMixConnection(),
                   conn.sourceSlot == .reusedOpenAISlot {
                    reusedOpenAIHost = conn.resolvedHost
                } else {
                    reusedOpenAIHost = nil
                }
            }
        }
    }

    private func quickHostChip(_ title: String, url: String) -> some View {
        let active = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines) == url
        return Button(title) {
            baseURLDraft = url
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? accent : Color.secondary.opacity(0.14), in: Capsule())
        .foregroundStyle(active ? .white : .primary)
        .buttonStyle(.plain)
    }

    private func persistInputs() -> (key: String, baseURL: String)? {
        errorMessage = nil
        statusMessage = nil
        let cleanedURL = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveURL = cleanedURL.isEmpty ? "https://aihubmix.com/v1" : cleanedURL
        guard AIProviderToolHTTP.isOpenAICompatibleRelay(effectiveURL),
              !AIProviderToolHTTP.isOfficialVendorHost(effectiveURL) else {
            errorMessage = "地址必须为受支持的 AIHubMix / Inferera HTTPS 域名（如 https://aihubmix.com/v1），禁止填写官方 OpenAI/Google 域名。"
            return nil
        }

        let cleanedKey = MultiProviderAIClient.sanitizePastedKey(keyDraft)
        let activeKey: String
        if !cleanedKey.isEmpty {
            guard cleanedKey.utf8.count <= 512, cleanedKey.utf8.allSatisfy({ (33...126).contains($0) }) else {
                errorMessage = "Key 格式不正确，请粘贴纯 API Key（勿包含空格或中文）。"
                return nil
            }
            guard Keychain.setAIHubMixAPIKey(cleanedKey, baseURL: effectiveURL) else {
                errorMessage = "无法写入钥匙串，请解锁设备后重试。"
                return nil
            }
            activeKey = cleanedKey
            hasDedicatedKey = true
        } else if let existing = Keychain.aiHubMixAPIKey(baseURL: effectiveURL) {
            activeKey = existing
        } else {
            errorMessage = "请先粘贴 AIHubMix API Key。"
            return nil
        }

        AIProviderEndpoints.setAIHubMixBaseURL(effectiveURL)
        AIProviderEndpoints.imageStudioOwnConnectionPreference = .aihubmix
        keyDraft = ""
        return (activeKey, effectiveURL)
    }

    private func saveAndVerify() {
        guard !testing, let saved = persistInputs() else { return }
        testing = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            defer { testing = false }
            do {
                let probe = try await MultiProviderAIClient().probeAndListModels(
                    provider: .openAI,
                    apiKey: saved.key,
                    baseURL: saved.baseURL
                )
                statusMessage = "AIHubMix 连接可用（\(probe.host)），返回 \(probe.models.count) 个目录项。画室现在可直接调用 GPT Image 与 Nano Banana 2。"
                onChanged()
            } catch let diag as AIProviderDiagnosticError {
                errorMessage = diag.errorDescription
                onChanged()
            } catch {
                errorMessage = "校验失败：\((error as? LocalizedError)?.errorDescription ?? "网络异常")"
                onChanged()
            }
        }
    }
}
