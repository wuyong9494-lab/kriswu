import SwiftUI
import UIKit

/// One-shot drafts. No app records, files, or prior conversations are read automatically.
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

    private enum Target: Hashable {
        case deepSeek
        case external(AIProvider)
        var title: String {
            switch self {
            case .deepSeek: return "DeepSeek"
            case .external(let provider): return provider.displayName
            }
        }
        var key: String? {
            switch self {
            case .deepSeek: return Keychain.get(.deepSeekPlanAPIKey)
            case .external(let provider): return Keychain.providerChatAPIKey(provider)
            }
        }
    }

    private enum SelectedModel {
        case deepSeek(DeepSeekChatClient.Model)
        case external(AIProvider, AIProviderModel)
        var title: String {
            switch self {
            case .deepSeek(let model): return model.rawValue
            case .external(_, let model): return model.id
            }
        }
    }

    private struct DraftRequest {
        let model: SelectedModel
        let target: Target
        let prompt: String
    }

    let kind: Kind
    @State private var template: Template
    @State private var target = Target.deepSeek
    @State private var deepSeekModel = DeepSeekChatClient.Model.pro
    @State private var availableModels: [AIProviderModel] = []
    @State private var selectedID = ""
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
    private var selectedModel: SelectedModel? {
        switch target {
        case .deepSeek: return .deepSeek(deepSeekModel)
        case .external(let provider):
            return availableModels.first(where: { $0.id == selectedID }).map { .external(provider, $0) }
        }
    }

    init(kind: Kind) {
        self.kind = kind
        _template = State(initialValue: kind.templates[0])
    }

    var body: some View {
        Form {
            if kind == .work {
                Section("日常值班工具") {
                    NavigationLink { PassPlanView() } label: {
                        Label("导入与复核数传计划", systemImage: "tablecells")
                    }
                    NavigationLink { DeepSeekTenderView() } label: {
                        Label("生成投标书草稿", systemImage: "doc.text")
                    }
                }
                .disabled(busy)
            }
            Section {
                Picker("用途", selection: $template) {
                    ForEach(kind.templates) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                Picker("服务商", selection: $target) {
                    Text("DeepSeek").tag(Target.deepSeek)
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(Target.external(provider))
                    }
                }
                modelControls
                if !hasKey {
                    Button("填写 API Key") { showingKey = true }
                }
            } footer: {
                Text(hasKey ? "使用本机已配置的 API Key。" : "此服务商尚未配置密钥，请先到 AI 服务商设置中填写自己的 Key。")
            }
            .disabled(busy)

            Section {
                TextEditor(text: $source)
                    .frame(minHeight: 150)
                    .accessibilityLabel(kind == .code ? "代码或需求" : "工作素材")
                if trimmedSource.utf8.count > sourceLimit {
                    Text("内容过长，请缩短后再发送。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(kind == .code ? "粘贴代码或描述需求" : "粘贴已获准发送的工作素材")
            } footer: {
                Text(kind == .code
                     ? "仅生成、解释或审阅文字与代码，不执行代码。请勿粘贴密钥。"
                     : "不自动读取排班、站名表、标书或历史对话。请勿粘贴内部、涉密或未经许可外发的内容。")
            }
            .disabled(busy)

            Section {
                if busy {
                    ProgressView(fetchingModels ? "获取模型…" : "等待回复…")
                    Button("停止等待", action: stop)
                } else {
                    Button("确认生成", action: prepare)
                        .disabled(!hasKey || selectedModel == nil || trimmedSource.isEmpty || trimmedSource.utf8.count > sourceLimit)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !output.isEmpty {
                Section("草稿 · 请人工核对") {
                    Text(output)
                        .font(kind == .code ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled)
                    Button("复制文字") {
                        UIPasteboard.general.setItems([["public.utf8-plain-text": output]], options: [.localOnly: true])
                    }
                    ShareLink(item: output) { Label("分享文字…", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .modifier(AvoidTabBar())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: syncKeyStatus)
        .onChange(of: target) { _ in
            stop()
            availableModels = []
            selectedID = ""
            error = nil
            syncKeyStatus()
        }
        .onDisappear(perform: stop)
        .sheet(isPresented: $showingKey, onDismiss: syncKeyStatus) {
            switch target {
            case .deepSeek: DeepSeekPlanKeyView()
            case .external(let provider):
                ProviderKeyView(provider: provider) { _ in
                    availableModels = []
                    selectedID = ""
                }
            }
        }
        .alert("发送给 \(pending?.target.title ?? target.title)？", isPresented: $confirmingSend) {
            Button("确认发送", action: send)
            Button("取消", role: .cancel) { pending = nil }
        } message: {
            Text("本次仅发送所选模板和你粘贴的文字，模型为 \(pending?.model.title ?? "未选择")。服务商可能计费。请确认素材可对外发送。")
        }
    }

    @ViewBuilder private var modelControls: some View {
        switch target {
        case .deepSeek:
            Picker("模型", selection: $deepSeekModel) {
                ForEach(DeepSeekChatClient.Model.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
        case .external(let provider):
            if !availableModels.isEmpty {
                Picker("模型", selection: $selectedID) {
                    Text("请选择").tag("")
                    ForEach(availableModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
            }
            Button(availableModels.isEmpty ? "获取模型" : "刷新模型") { refresh(provider) }
                .disabled(!hasKey)
        }
    }

    private func syncKeyStatus() {
        hasKey = !(target.key ?? "").isEmpty
    }

    private func prepare() {
        guard !busy, hasKey, let model = selectedModel, !trimmedSource.isEmpty,
              trimmedSource.utf8.count <= sourceLimit else { return }
        pending = DraftRequest(model: model, target: target,
                               prompt: "\(template.directions)\n\n用户提供的素材（可能需要核实）：\n\(trimmedSource)")
        confirmingSend = true
    }

    private func refresh(_ provider: AIProvider) {
        guard !busy, target == .external(provider), let key = target.key else { syncKeyStatus(); return }
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
                    baseURL: AIProviderEndpoints.baseURL(for: provider)
                )
                    .filter(\.supportsTextChat)
                guard operationID == id, !Task.isCancelled else { return }
                availableModels = models
                if !models.contains(where: { $0.id == selectedID }) { selectedID = "" }
                if models.isEmpty { error = "此服务商没有返回可用的文字模型。" }
            } catch {
                if operationID == id {
                    availableModels = []
                    selectedID = ""
                }
                showError(error, for: id)
            }
        }
    }

    private func send() {
        guard !busy, let request = pending else { return }
        pending = nil
        guard request.target == target, let key = request.target.key else {
            syncKeyStatus()
            error = "密钥或服务商已改变，请重新确认。"
            return
        }
        let id = UUID()
        operationID = id
        fetchingModels = false
        output = ""
        error = nil
        operation = Task { @MainActor in
            defer { finish(id) }
            do {
                let answer: String
                switch request.model {
                case .deepSeek(let model):
                    var draft = ""
                    for try await delta in DeepSeekChatClient.stream(messages: [.init(role: .user, content: request.prompt)],
                                                                      apiKey: key, model: model, thinking: .normal) {
                        try Task.checkCancellation()
                        draft += delta
                    }
                    answer = draft
                case .external(let provider, let model):
                    answer = try await MultiProviderAIClient().send(
                        provider: provider,
                        model: model,
                        apiKey: key,
                        messages: [.init(role: .user, text: request.prompt)],
                        baseURL: AIProviderEndpoints.baseURL(for: provider)
                    )
                }
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
        else { self.error = "请求未完成，请稍后重试。" }
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
