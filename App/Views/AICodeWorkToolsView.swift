import SwiftUI
import UIKit

/// One-shot drafts. No app records, files, or prior conversations are read automatically.
@MainActor
struct AICodeWorkToolsView: View {
    enum Kind {
        case code, work
        var title: String { self == .code ? "AI 代码" : "AI 工作" }
        var templates: [Template] {
            self == .code ? [.generateCode, .explainCode, .reviewCode] : [.draft, .summary, .handover]
        }
    }

    enum Template: String, Identifiable {
        case generateCode = "生成代码"
        case explainCode = "解释代码"
        case reviewCode = "代码审阅"
        case draft = "文档草稿"
        case summary = "总结要点"
        case handover = "交班草稿"
        var id: String { rawValue }
        var directions: String {
            switch self {
            case .generateCode:
                return "根据给定需求起草普通软件代码。说明语言、依赖、运行条件和假设，并给出最小测试示例。只提供文字，不声称已运行。"
            case .explainCode:
                return "解释所给代码的用途、输入输出、主要逻辑和边界条件。代码未提供的依赖或环境标为未知。"
            case .reviewCode:
                return "从正确性、可读性和防御性安全角度审阅所给代码。按优先级列出问题、影响和修正建议，不生成攻击利用代码，不声称已运行。"
            case .draft:
                return "根据用户贴入的素材起草工作文档。区分已有事实、建议和待确认项，不编造人员、时间、金额或完成状态。"
            case .summary:
                return "只总结来源中实际写明的事项。分别列出要点、待办、材料明确写出的负责人和时间；未提供的标为待确认。"
            case .handover:
                return "整理成值班交班草稿：已完成、未完成、下一班需跟进与待核实。来源没有明确的信息不得编造，也不声称已交班或已通知。"
            }
        }
    }

    private struct DraftRequest {
        let channel: WuMindChannel
        let destination: String
        let modelID: String
        let prompt: String
    }

    @ObservedObject private var store = WuMindStore.shared
    let kind: Kind
    @Environment(\.colorScheme) private var colorScheme
    @State private var template: Template
    @State private var hasKey = false
    @State private var showingKey = false
    @State private var source = ""
    @State private var output = ""
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var operationID: UUID?
    @State private var fetchingModels = false
    @State private var pending: DraftRequest?
    @State private var confirmingSend = false

    private let sourceLimit = 12_000
    private var busy: Bool { operationID != nil }
    private var trimmedSource: String { source.trimmingCharacters(in: .whitespacesAndNewlines) }
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
    private var accent: Color {
        kind == .code ? .orange : .blue
    }
    private var managed: Bool { store.channel == .managed }
    private var readyToSend: Bool {
        managed ? store.hasGatewayURL && store.managedSessionToken != nil && store.activeManagedModel != nil : hasKey
    }
    private var modelID: String { managed ? store.managedSelectedModelID : store.selectedModelID }

    init(kind: Kind) {
        self.kind = kind
        _template = State(initialValue: kind.templates[0])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WuMindHubHeroBanner(
                    title: kind == .code ? "WUMIND 代码工坊" : "WUMIND 办公与值班工坊",
                    subtitle: kind == .code
                        ? "需求代码生成、逻辑结构解释与防御性安全审阅，使用当前对话通道"
                        : "文档起草、要点纪要、交班草稿，并直连日常数传计划与标书工具",
                    icon: kind == .code ? "curlybraces" : "briefcase.fill",
                    colors: kind == .code
                        ? [Color(red: 0.80, green: 0.36, blue: 0.12), Color(red: 0.62, green: 0.22, blue: 0.42)]
                        : [Color(red: 0.16, green: 0.38, blue: 0.84), Color(red: 0.20, green: 0.54, blue: 0.72)],
                    chips: [
                        ("当前模式", template.rawValue),
                        ("模型通道", store.channel.title)
                    ]
                )

                if kind == .work {
                    HStack(spacing: 10) {
                        NavigationLink { PassPlanView() } label: {
                            HStack(spacing: 8) {
                                WuMindIconBadge(icon: "tablecells", color: .teal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("数传计划复核")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text("导入与校验")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(11)
                            .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        NavigationLink { DeepSeekTenderView() } label: {
                            HStack(spacing: 8) {
                                WuMindIconBadge(icon: "doc.text.fill", color: .indigo)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("投标书草稿")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text("DeepSeek 起草")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(11)
                            .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .disabled(busy)
                }

                // Full-width 3-Pill Template Switcher (Zero horizontal overflow)
                HStack(spacing: 6) {
                    ForEach(kind.templates) { item in
                        let active = template == item
                        Button {
                            Haptics.select()
                            template = item
                        } label: {
                            Text(item.rawValue)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(active ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(active ? accent : cardBg, in: Capsule())
                                .overlay(Capsule().strokeBorder(active ? Color.clear : cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                }

                // Provider & Model Glass Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("推理引擎")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        if !managed && !hasKey {
                            Button("配置 API Key") { showingKey = true }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        if managed {
                            if !store.hasGatewayURL || store.activeManagedModel == nil {
                                Text("内置通道暂不可用，请联系管理员。").font(.caption)
                            } else if store.managedSessionToken == nil {
                                Text("请先登录 WuMind 账号。").font(.caption)
                            }
                        } else {
                            Menu(store.selectedProvider.displayName) {
                                ForEach(WuMindProvider.allCases) { provider in
                                    Button(provider.displayName) { store.selectProvider(provider) }
                                }
                            }
                            .disabled(busy)
                        }

                        modelControls
                    }
                }
                .padding(14)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                // Glass Editor Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(kind == .code ? "粘贴代码或描述需求" : "粘贴已获准发送的工作素材")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Text("\(trimmedSource.utf8.count) / \(sourceLimit)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(trimmedSource.utf8.count > sourceLimit ? DS.Palette.danger : .secondary)
                    }

                    TextField(
                        kind == .code ? "输入需求说明或粘贴代码片段…" : "粘贴会议纪要、素材或待整理内容…",
                        text: $source,
                        axis: .vertical
                    )
                    .font(kind == .code ? .system(.footnote, design: .monospaced) : .body)
                    .lineLimit(6...14)
                    .disabled(busy)
                    .padding(12)
                    .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(kind == .code ? "代码或需求" : "工作素材")

                    if busy {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(fetchingModels ? "正在拉取模型目录…" : "正在生成草稿…")
                                .font(.footnote.weight(.medium))
                            Spacer()
                            Button("停止", role: .cancel, action: stop)
                                .font(.caption.weight(.bold))
                        }
                    } else {
                        let ready = readyToSend && !trimmedSource.isEmpty && trimmedSource.utf8.count <= sourceLimit
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            prepare()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("生成\(template.rawValue)")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(ready ? accent : Color.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!ready)
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(kind == .code
                         ? "仅生成、解释或审阅代码，不执行本机命令；请勿粘贴密钥。"
                         : "不自动读取排班、站名表或历史对话；请勿粘贴涉密内容。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                if !output.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("生成草稿 · 请人工核对", systemImage: "doc.text.magnifyingglass")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Button("复制") {
                                UIPasteboard.general.setItems([["public.utf8-plain-text": output]], options: [.localOnly: true])
                                Haptics.success()
                            }
                            .font(.caption.weight(.bold))
                            ShareLink(item: output) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption.weight(.bold))
                            }
                        }
                        Text(output)
                            .font(kind == .code ? .system(.footnote, design: .monospaced) : .body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent.opacity(0.28), lineWidth: 1))
                }
            }
            .padding(14)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(pageBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear(perform: syncKeyStatus)
        .task(id: managed) {
            syncKeyStatus()
            if managed && store.hasGatewayURL { try? await store.syncManagedGatewayConfig() }
        }
        .onChange(of: store.selectedProvider) { _ in syncKeyStatus() }
        .onDisappear(perform: stop)
        .sheet(isPresented: $showingKey, onDismiss: syncKeyStatus) {
            if let provider = store.selectedProvider.multiProvider {
                ProviderKeyView(provider: provider) { _ in syncKeyStatus() }
            } else {
                DeepSeekPlanKeyView()
            }
        }
        .alert("发送给 \(pending?.destination ?? store.activeDataDestinationLabel)？", isPresented: $confirmingSend) {
            Button("确认发送", action: send)
            Button("取消", role: .cancel) { pending = nil }
        } message: {
            Text("本次仅发送所选模板和你粘贴的文字，模型为 \(pending?.modelID ?? "未选择")。服务商可能计费。请确认素材可对外发送。")
        }
    }

    @ViewBuilder private var modelControls: some View {
        Menu(store.activeModelDisplayName) {
            if managed {
                ForEach(store.enabledManagedModels) { model in
                    Button(model.displayName) { store.selectManagedModel(model) }
                }
            } else {
                ForEach(store.models(for: store.selectedProvider).filter(\.supportsTextChat)) { model in
                    Button(model.displayName) { store.selectModel(model) }
                }
            }
        }
        .disabled(busy || (managed && store.activeManagedModel == nil))

        if !managed, let provider = store.selectedProvider.multiProvider {
            Button("刷新模型") { refresh(provider) }
                .font(.caption.weight(.semibold))
                .disabled(!hasKey || busy)
        }
    }

    private func syncKeyStatus() {
        hasKey = !managed && store.selectedProvider.hasKey
    }

    private func prepare() {
        guard !busy, readyToSend, !trimmedSource.isEmpty, trimmedSource.utf8.count <= sourceLimit else { return }
        pending = DraftRequest(channel: store.channel, destination: store.activeDataDestinationLabel, modelID: modelID,
                               prompt: "\(template.directions)\n\n用户提供的素材（可能需要核实）：\n\(trimmedSource)")
        confirmingSend = true
    }

    private func refresh(_ provider: AIProvider) {
        let selected = store.selectedProvider
        let baseURL = AIProviderEndpoints.baseURL(for: provider)
        guard !busy, !managed, selected.multiProvider == provider, let key = Keychain.providerChatAPIKey(provider, baseURL: baseURL) else { return }
        let id = UUID()
        operationID = id
        fetchingModels = true
        error = nil
        operation = Task { @MainActor in
            defer { finish(id) }
            do {
                let models = try await MultiProviderAIClient().listModels(
                    provider: provider,
                    apiKey: key,
                    baseURL: baseURL
                )
                    .filter(\.supportsTextChat)
                guard operationID == id, !Task.isCancelled else { return }
                store.updateCachedModels(models, for: selected)
                if models.isEmpty { error = "此服务商没有返回可用的文字模型。" }
            } catch {
                showError(error, for: id)
            }
        }
    }

    private func send() {
        guard !busy, let request = pending else { return }
        pending = nil
        let id = UUID()
        operationID = id
        fetchingModels = false
        output = ""
        error = nil
        operation = Task { @MainActor in
            defer { finish(id) }
            do {
                guard request.channel == store.channel, request.modelID == modelID,
                      request.destination == store.activeDataDestinationLabel else {
                    error = "调用通道或模型已改变，请重新确认。"
                    return
                }
                let result = try await store.runStatelessChat(
                    messages: [.init(role: .user, text: request.prompt)], systemPrompt: nil
                )
                let answer = result.answer
                guard operationID == id, !Task.isCancelled else { return }
                if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    error = "没有收到可显示的草稿，请检查素材后重试。"
                } else {
                    output = answer
                }
            } catch {
                showError(error, for: id)
            }
        }
    }

    private func showError(_ caught: Error, for id: UUID) {
        guard operationID == id, !Task.isCancelled else { return }
        if let error = caught as? DeepSeekChatClient.Failure { self.error = error.errorDescription }
        else if let error = caught as? MultiProviderAIError { self.error = error.errorDescription }
        else { self.error = (caught as? LocalizedError)?.errorDescription ?? "请求未完成，请稍后重试。" }
    }

    private func finish(_ id: UUID) {
        guard operationID == id else { return }
        operation = nil
        operationID = nil
        fetchingModels = false
    }

    private func stop() {
        operation?.cancel()
        if let id = operationID { finish(id) }
        pending = nil
    }
}
