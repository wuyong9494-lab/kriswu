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
    @Environment(\.colorScheme) private var colorScheme
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WuMindHubHeroBanner(
                    title: kind == .code ? "WUMIND 代码工坊" : "WUMIND 办公与值班工坊",
                    subtitle: kind == .code
                        ? "需求代码生成、逻辑结构解释与防御性安全审阅，直连本机已配置全模型"
                        : "文档起草、要点纪要、交班草稿，并直连日常数传计划与标书工具",
                    icon: kind == .code ? "curlybraces" : "briefcase.fill",
                    colors: kind == .code
                        ? [Color(red: 0.80, green: 0.36, blue: 0.12), Color(red: 0.62, green: 0.22, blue: 0.42)]
                        : [Color(red: 0.16, green: 0.38, blue: 0.84), Color(red: 0.20, green: 0.54, blue: 0.72)],
                    chips: [
                        ("当前模式", template.rawValue),
                        ("模型通道", target.title)
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
                        if !hasKey {
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
                        Menu {
                            Button("DeepSeek") { target = .deepSeek }
                            ForEach(AIProvider.allCases) { provider in
                                Button(provider.displayName) { target = .external(provider) }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(target.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.11), in: Capsule())
                        }
                        .tint(.primary)
                        .disabled(busy)

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
                        let ready = hasKey && selectedModel != nil && !trimmedSource.isEmpty && trimmedSource.utf8.count <= sourceLimit
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
            Menu {
                ForEach(DeepSeekChatClient.Model.allCases) { model in
                    Button(model.title) { deepSeekModel = model }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(deepSeekModel.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(accent.opacity(0.13), in: Capsule())
            }
            .tint(.primary)
            .disabled(busy)
        case .external(let provider):
            if !availableModels.isEmpty {
                Menu {
                    ForEach(availableModels) { model in
                        Button(model.displayName) { selectedID = model.id }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(selectedModel?.title ?? "选择模型")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(accent.opacity(0.13), in: Capsule())
                }
                .tint(.primary)
                .disabled(busy)
            }
            Button(availableModels.isEmpty ? "拉取模型" : "刷新") { refresh(provider) }
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(accent.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
                .disabled(!hasKey || busy)
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
