import SwiftUI
import UIKit

/// One-shot drafts. No app records, files, or prior conversations are read automatically.
@MainActor
struct AICodeWorkToolsView: View {
    enum Kind {
        case code, work
        var title: String { self == .code ? "编程" : "办公" }
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
        var actionTitle: String {
            switch self {
            case .generateCode: return "生成代码"
            case .explainCode: return "解释代码"
            case .reviewCode: return "审阅代码"
            case .draft: return "生成文档草稿"
            case .summary: return "整理要点"
            case .handover: return "生成交班草稿"
            }
        }

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
        ScrollViewReader { proxy in
            draftForm.onChange(of: output.isEmpty) { empty in
                if !empty { proxy.scrollTo("generated-draft", anchor: .top) }
            }
        }
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

    private var draftForm: some View {
        Form {
            if !output.isEmpty {
                Section {
                    Text(output)
                        .font(kind == .code ? .system(.body, design: .monospaced) : DS.Font.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("generated-draft")
                    Button {
                        UIPasteboard.general.setItems([["public.utf8-plain-text": output]], options: [.localOnly: true])
                        Haptics.success()
                    } label: { Label("复制草稿", systemImage: "doc.on.doc") }
                    ShareLink(item: output) { Label("分享草稿", systemImage: "square.and.arrow.up") }
                } header: {
                    Text("生成草稿")
                } footer: {
                    Text("使用前请核对生成内容。")
                }
            }

            Section {
                Picker("模板", selection: $template) {
                    ForEach(kind.templates) { item in Text(item.rawValue).tag(item) }
                }
                .disabled(busy)
                .onChange(of: template) { _ in Haptics.select() }

                TextField(kind == .code ? "输入需求或粘贴代码" : "粘贴会议纪要或工作素材",
                          text: $source, axis: .vertical)
                    .font(kind == .code ? .system(.body, design: .monospaced) : DS.Font.body)
                    .lineLimit(5...14)
                    .disabled(busy)
                    .accessibilityLabel(kind == .code ? "代码或需求" : "工作素材")
                LabeledContent("素材大小", value: "\(trimmedSource.utf8.count) / \(sourceLimit) 字节")
                    .font(DS.Font.caption)
                    .foregroundStyle(trimmedSource.utf8.count > sourceLimit ? DS.Palette.danger : .secondary)
            } header: {
                Text(kind == .code ? "代码与需求" : "工作素材")
            } footer: {
                Text(kind == .code ? "只发送所选模板与输入内容。请勿粘贴密钥。" : "只发送所选模板与输入内容。请确认素材可对外发送。")
            }

            Section("调用通道") {
                if managed {
                    LabeledContent("通道", value: "WuMind 内置")
                    if !store.hasGatewayURL || store.activeManagedModel == nil {
                        Label("内置通道暂不可用，请联系管理员。", systemImage: "info.circle")
                            .font(DS.Font.caption)
                    } else if store.managedSessionToken == nil {
                        Label("请先登录 WuMind 账号。", systemImage: "person.crop.circle")
                            .font(DS.Font.caption)
                    }
                } else {
                    LabeledContent("服务商") {
                        Menu(store.selectedProvider.displayName) {
                            ForEach(WuMindProvider.allCases) { provider in
                                Button(provider.displayName) { store.selectProvider(provider) }
                            }
                        }
                        .disabled(busy)
                    }
                    if !hasKey { Button("配置 API Key") { showingKey = true } }
                }
                modelControls
            }

            Section {
                if busy {
                    ProgressView(fetchingModels ? "正在刷新模型…" : "正在生成草稿…")
                    Button("停止", role: .cancel, action: stop)
                } else {
                    AppPrimaryCTA(title: template.actionTitle, icon: "sparkles",
                                  isDisabled: !readyToSend || trimmedSource.isEmpty || trimmedSource.utf8.count > sourceLimit) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        prepare()
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.danger)
                }
            }

            if kind == .work {
                Section("专项工具") {
                    NavigationLink { PassPlanView() } label: { Label("数传计划复核", systemImage: "tablecells") }
                    NavigationLink { DeepSeekTenderView() } label: { Label("投标书草稿", systemImage: "doc.text") }
                }
                .disabled(busy)
            }
        }
        .appList()
    }

    @ViewBuilder private var modelControls: some View {
        LabeledContent("模型") {
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
        }

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
