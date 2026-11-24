import SwiftUI
import UIKit

struct AIProviderListView: View {
    var body: some View {
        List {
            Section("AI 工具箱") {
                NavigationLink { AILiveCallView() } label: {
                    Label("实时语音通话", systemImage: "phone.waveform")
                }
                .accessibilityIdentifier("ai.tools.live")
                NavigationLink { AIImageToolView() } label: {
                    Label("文字生成图片", systemImage: "photo.on.rectangle.angled")
                }
                .accessibilityIdentifier("ai.tools.image")
                NavigationLink { AISpeechToolView() } label: {
                    Label("语音合成与转写", systemImage: "waveform")
                }
                .accessibilityIdentifier("ai.tools.speech")
                NavigationLink { AICodeWorkToolsView(kind: .code) } label: {
                    Label("代码助手", systemImage: "curlybraces")
                }
                .accessibilityIdentifier("ai.tools.code")
                NavigationLink { AICodeWorkToolsView(kind: .work) } label: {
                    Label("工作助手", systemImage: "briefcase")
                }
                .accessibilityIdentifier("ai.tools.work")
            }
            Section {
                ForEach(AIProvider.allCases) { provider in
                    NavigationLink {
                        ProviderChatView(provider: provider)
                    } label: {
                        Label(provider.displayName, systemImage: "bubble.left.and.bubble.right")
                    }
                    .accessibilityIdentifier("ai.provider.\(provider.rawValue)")
                }
            } footer: {
                Text("各家 API Key 独立保存在本机。文字对话与 DeepSeek 分开，值班计划和标书功能不换服务商。")
            }
        }
        .modifier(AvoidTabBar())
        .navigationTitle("AI 工具箱")
    }
}

private struct ProviderChatView: View {
    let provider: AIProvider
    @State private var models: [AIProviderModel] = []
    @State private var modelID: String? = nil
    @State private var showingKey = false
    @State private var showingModels = false
    @State private var showingReset = false
    @State private var hasKey = false
    @State private var refreshID: UUID? = nil
    @State private var requestID: UUID? = nil
    @State private var operation: Task<Void, Never>? = nil
    @State private var catalogError: String? = nil
    @State private var transcript: [Turn] = []
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private func dismissKeyboard() {
        composerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private struct Turn: Identifiable {
        var id: UUID
        var question: String
        var model: String
        var reasoning: String?
        var answer: String?
        var note: String?
    }

    private var chatModels: [AIProviderModel] { models.filter(\.supportsTextChat) }
    private var otherModels: [AIProviderModel] { models.filter { !$0.supportsTextChat } }
    private var selected: AIProviderModel? { chatModels.first { $0.id == modelID } }
    private var question: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validQuestion: Bool { !question.isEmpty && question.utf8.count <= 8_000 }
    private var busy: Bool { requestID != nil || refreshID != nil }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            messages
            Divider()
            composer
        }
        .modifier(AvoidTabBar())
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        dismissKeyboard()
                        showingKey = true
                    } label: { Label("管理 API Key", systemImage: "key") }
                    Button {
                        dismissKeyboard()
                        showingReset = true
                    } label: { Label("清空对话", systemImage: "square.and.pencil") }
                        .disabled(transcript.isEmpty && draft.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(busy)
                .accessibilityLabel("聊天设置")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { dismissKeyboard() }
            }
        }
        .onAppear { hasKey = Keychain.providerChatAPIKey(provider) != nil }
        .onDisappear {
            dismissKeyboard()
            stopOperation()
        }
        .sheet(isPresented: $showingKey) {
            ProviderKeyView(provider: provider) { configured in
                stopOperation()
                hasKey = configured
                models = []
                modelID = nil
                catalogError = nil
                reset()
            }
        }
        .sheet(isPresented: $showingModels) {
            ProviderModelPicker(models: chatModels, selection: $modelID)
        }
        .confirmationDialog("清空当前对话？", isPresented: $showingReset, titleVisibility: .visible) {
            Button("清空", role: .destructive, action: reset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.provider.chat")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !hasKey {
                Button {
                    dismissKeyboard()
                    showingKey = true
                } label: { Label("填写 API Key", systemImage: "key") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("ai.key.open")
            } else {
                HStack {
                    if !chatModels.isEmpty {
                        Button {
                            dismissKeyboard()
                            showingModels = true
                        } label: {
                            Label(selected?.displayName ?? "选择模型", systemImage: "chevron.up.chevron.down")
                                .lineLimit(1)
                        }
                        .accessibilityIdentifier("ai.model.select")
                        .disabled(busy)
                    }
                    Spacer(minLength: 0)
                    if refreshID != nil { ProgressView().accessibilityLabel("正在刷新模型") }
                    Button(models.isEmpty ? "获取模型" : "刷新模型") { refresh() }
                        .disabled(busy)
                        .accessibilityIdentifier("ai.models.refresh")
                }
                if let catalogError {
                    HStack(spacing: 8) {
                        Text(catalogError).font(.footnote).foregroundStyle(DS.Palette.danger)
                        Spacer()
                        Button("检查 Key") {
                            dismissKeyboard()
                            showingKey = true
                        }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                    }
                } else if !models.isEmpty {
                    Text("实际调用权限以服务商为准。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !otherModels.isEmpty {
                    NavigationLink {
                        List(otherModels) { model in
                            Text(model.displayName)
                                .accessibilityHint("此模型未在当前文字聊天中启用")
                        }
                        .navigationTitle("其他 API 模型")
                    } label: {
                        Text("查看未启用聊天的模型（\(otherModels.count)）")
                            .font(.caption)
                    }
                    .disabled(busy)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if transcript.isEmpty {
                        Text("问问题、写代码、起草文字。切换服务商不会把这个对话发给另一家。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(transcript) { turn in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(turn.question).textSelection(.enabled).padding(10)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(turn.model).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if let reasoning = turn.reasoning, !reasoning.isEmpty {
                                DisclosureGroup("思考过程") {
                                    Text(reasoning)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            }
                            if let answer = turn.answer {
                                Text(answer).textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.setItems([["public.utf8-plain-text": answer]], options: [.localOnly: true])
                                    ToastCenter.shared.show("已复制", style: .success)
                                } label: { Label("复制回复", systemImage: "doc.on.doc") }
                                .font(.caption)
                            } else if let note = turn.note {
                                Text(note).font(.footnote).foregroundStyle(.secondary)
                                if transcript.last?.id == turn.id && draft.isEmpty {
                                    Button("放回输入框") { draft = turn.question }.font(.caption)
                                }
                            } else if requestID == turn.id {
                                ProgressView("等待回复…")
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("ai.chat.end")
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                if composerFocused { dismissKeyboard() }
            })
            .onChange(of: transcript.last?.id) { _ in proxy.scrollTo("ai.chat.end", anchor: .bottom) }
            .onChange(of: transcript.last?.answer) { _ in proxy.scrollTo("ai.chat.end", anchor: .bottom) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("发消息…", text: $draft, axis: .vertical)
                .lineLimit(2...6)
                .frame(minHeight: 44, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($composerFocused)
                .disabled(requestID != nil)
                .accessibilityIdentifier("ai.chat.composer")
            if composerFocused && requestID == nil {
                Button(action: dismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起键盘")
            }
            if requestID != nil {
                Button(action: stopOperation) {
                    Image(systemName: "stop.circle.fill").font(.title)
                }
                .accessibilityLabel("停止等待")
            } else {
                Button {
                    dismissKeyboard()
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(!validQuestion || selected == nil || busy)
                .accessibilityLabel("发送消息")
                .accessibilityIdentifier("ai.chat.send")
            }
        }
        .padding(12)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func refresh() {
        guard !busy else { return }
        guard let key = Keychain.providerChatAPIKey(provider) else { showingKey = true; return }
        let id = UUID()
        refreshID = id
        catalogError = nil
        let wmProvider = WuMindProvider.from(provider)
        operation = Task { @MainActor in
            defer {
                if refreshID == id { refreshID = nil; operation = nil }
            }
            do {
                let probe = try await MultiProviderAIClient().probeAndListModels(
                    provider: provider,
                    apiKey: key,
                    baseURL: AIProviderEndpoints.baseURL(for: provider)
                )
                guard refreshID == id, !Task.isCancelled else { return }
                models = probe.models
                if let wmProvider {
                    WuMindStore.shared.updateCachedModels(probe.models, for: wmProvider, verifiedHost: probe.host)
                }
                if selected == nil { modelID = nil }
                if chatModels.isEmpty { catalogError = "服务商（\(probe.host)）未返回可选的文字聊天模型。" }
            } catch let diag as AIProviderDiagnosticError {
                guard refreshID == id, !Task.isCancelled else { return }
                models = []
                modelID = nil
                catalogError = diag.errorDescription
                if let wmProvider {
                    WuMindStore.shared.markProviderFailed(wmProvider, host: diag.host, summary: diag.shortBadgeSummary)
                }
            } catch {
                guard refreshID == id, !Task.isCancelled else { return }
                models = []
                modelID = nil
                let host = provider.resolvedHost(baseURL: AIProviderEndpoints.baseURL(for: provider))
                let msg = (error as? LocalizedError)?.errorDescription ?? "未能获取模型列表。"
                catalogError = "\(msg)\n[请求域名：\(host)]"
                if let wmProvider {
                    WuMindStore.shared.markProviderFailed(wmProvider, host: host, summary: "\(host) · 连接失败")
                }
            }
        }
    }

    private func send() {
        guard !busy, validQuestion, let model = selected else { return }
        guard let key = Keychain.providerChatAPIKey(provider) else { showingKey = true; return }
        let prompt = question
        let id = UUID()
        var context: [AIProviderMessage] = []
        var budget = 40_000 - prompt.utf8.count
        for turn in transcript.lazy.reversed().filter({ $0.answer != nil }).prefix(7) {
            guard let answer = turn.answer else { continue }
            let size = turn.question.utf8.count + answer.utf8.count
            guard size <= budget else { break }
            budget -= size
            context.append(.init(role: .assistant, text: answer))
            context.append(.init(role: .user, text: turn.question))
        }
        let messages = Array(context.reversed()) + [AIProviderMessage(role: .user, text: prompt)]
        draft = ""
        requestID = id
        transcript.append(.init(id: id, question: prompt, model: model.displayName))
        operation = Task { @MainActor in
            do {
                let reply = try await MultiProviderAIClient().sendDetailed(
                    provider: provider,
                    model: model,
                    apiKey: key,
                    messages: messages,
                    deepThinking: true,
                    baseURL: AIProviderEndpoints.baseURL(for: provider)
                )
                guard !Task.isCancelled else { return }
                finish(id, answer: reply.answer, reasoning: reply.reasoning, note: nil)
            } catch {
                guard !Task.isCancelled else { return }
                finish(id, answer: nil, reasoning: nil, note: (error as? LocalizedError)?.errorDescription ?? "未收到回复。")
            }
        }
    }

    private func finish(_ id: UUID, answer: String?, reasoning: String?, note: String?) {
        guard requestID == id, let index = transcript.indices.last, transcript[index].id == id else { return }
        transcript[index].answer = answer
        transcript[index].reasoning = reasoning
        transcript[index].note = note
        requestID = nil
        operation = nil
    }

    private func stopOperation() {
        operation?.cancel()
        if let id = requestID { finish(id, answer: nil, reasoning: nil, note: "已停止等待。已发出的请求可能仍产生 API 用量。") }
        refreshID = nil
        operation = nil
    }

    private func reset() {
        transcript = []
        draft = ""
    }
}

private struct ProviderModelPicker: View {
    let models: [AIProviderModel]
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [AIProviderModel] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? models : models.filter {
            $0.id.localizedCaseInsensitiveContains(needle) || $0.displayName.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List(matches) { model in
                Button {
                    selection = model.id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            if model.displayName != model.id {
                                Text(model.id).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if model.id == selection { Image(systemName: "checkmark") }
                    }
                    .contentShape(Rectangle())
                }
            }
            .searchable(text: $query, prompt: "搜索模型名称或编号")
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct ProviderKeyView: View {
    let provider: AIProvider
    let changed: (Bool) -> Void
    @ObservedObject private var wumind = WuMindStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var stored = false
    @State private var draft = ""
    @State private var baseURLDraft = ""
    @State private var testing = false
    @State private var testSuccess: String? = nil
    @State private var error: String? = nil

    private var wmProvider: WuMindProvider? { WuMindProvider.from(provider) }

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
            Form {
                if let wmProvider {
                    connectionStatusSection(for: wmProvider)
                }

                Section {
                    SecureField(stored ? "已存，输入新 Key 可替换（自动去除 Bearer 前缀）" : "粘贴 API Key", text: $draft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("ai.key.input")
                } header: {
                    Text("API Key（仅存本机钥匙串，绝不回显）")
                }

                Section {
                    TextField("留空使用官方：\(provider.defaultBaseURLString)", text: $baseURLDraft)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("ai.baseurl.input")
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("当前将请求域名：\(previewTargetHost)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if provider == .openAI {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                endpointChip("官方默认", value: "")
                                endpointChip("OpenRouter", value: "https://openrouter.ai/api/v1")
                                endpointChip("硅基流动", value: "https://api.siliconflow.cn/v1")
                            }
                            .padding(.vertical, 2)
                        }
                    } else if !baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("恢复官方默认地址") { baseURLDraft = "" }
                            .font(.footnote)
                    }
                } header: {
                    Text("自定义 API 接口地址（中转站 / 代理，选填）")
                } footer: {
                    Text("请确保 Key 与接口地址配对：官方 Key 请点击「官方默认」让此处留空；中转站 / 聚合 API Key 必须填写该服务商提供的 HTTPS 地址，否则会返回 HTTP 401。")
                }

                Section {
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
                    .disabled(testing || (!hasKeyToSave && !stored))
                    .accessibilityIdentifier("ai.key.verify")

                    Button("仅保存到本机（不联网测试）") {
                        saveOnly(remove: false)
                    }
                    .disabled(testing || (!hasKeyToSave && !(stored && endpointChanged)))

                    if stored {
                        Button("移除本机 Key", role: .destructive) {
                            saveOnly(remove: true)
                        }
                        .disabled(testing)
                    }

                    if let testSuccess {
                        Label(testSuccess, systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } footer: {
                    Text("仅在联网测试拉取模型成功后才会显示绿色「已连接」；仅保存但未验证时显示琥珀色「已保存」。失败时仅展示目标域名与脱敏错误码，绝不暴露 API Key。")
                }
            }
            .scrollDismissesKeyboard(.immediately)
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

    @ViewBuilder
    private func connectionStatusSection(for wmProvider: WuMindProvider) -> some View {
        let state = wumind.verification(for: wmProvider)
        Section {
            HStack(spacing: 10) {
                Circle()
                    .fill(state?.dotColor ?? Color.secondary.opacity(0.45))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state?.badgeText ?? "未配置")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(state?.dotColor ?? .secondary)
                    Text(state?.summary ?? "尚未保存本机 API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("当前真实连接状态")
        }
    }

    private func endpointChip(_ title: String, value: String) -> some View {
        let active = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines) == value
        return Button(title) {
            baseURLDraft = value
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? DS.Palette.accent : Color.secondary.opacity(0.14), in: Capsule())
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
                testSuccess = "验证成功！已连接 \(probe.host)，可用对话模型 \(chatCount) 个。"
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
