import SwiftUI
import UIKit

struct AIProviderListView: View {
    var body: some View {
        List {
            Section("AI 工具箱") {
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
        .navigationTitle("AI 工具箱")
    }
}

private struct ProviderChatView: View {
    let provider: AIProvider
    @State private var models: [AIProviderModel] = []
    @State private var modelID: String? = nil
    @State private var showingKey = false
    @State private var showingModels = false
    @State private var showingSend = false
    @State private var showingReset = false
    @State private var hasKey = false
    @State private var refreshID: UUID? = nil
    @State private var requestID: UUID? = nil
    @State private var operation: Task<Void, Never>? = nil
    @State private var catalogError: String? = nil
    @State private var transcript: [Turn] = []
    @State private var draft = ""
    @State private var permissionGranted = false

    private struct Turn: Identifiable {
        var id: UUID
        var question: String
        var model: String
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
            Label("消息发给\(provider.displayName) · 不读取值班资料", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
            controls
            Divider()
            messages
            Divider()
            composer
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingKey = true } label: { Label("管理 API Key", systemImage: "key") }
                    Button { showingReset = true } label: { Label("清空对话", systemImage: "square.and.pencil") }
                        .disabled(transcript.isEmpty && draft.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(busy)
                .accessibilityLabel("聊天设置")
            }
        }
        .onAppear { hasKey = Keychain.providerChatAPIKey(provider) != nil }
        .onDisappear(perform: stopOperation)
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
        .alert("把对话发给\(provider.displayName)？", isPresented: $showingSend) {
            Button("确认发送") {
                permissionGranted = true
                send()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只发送你输入的文字和此页必要的聊天上下文，使用该服务商的 API 额度。不会读取 DeepSeek 对话或值班资料。请勿输入内部、涉密或未经许可外发的内容。")
        }
        .confirmationDialog("清空当前对话？", isPresented: $showingReset, titleVisibility: .visible) {
            Button("清空", role: .destructive, action: reset)
        }
        .accessibilityIdentifier("ai.provider.chat")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !hasKey {
                Button { showingKey = true } label: { Label("填写 API Key", systemImage: "key") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("ai.key.open")
            } else {
                HStack {
                    if !chatModels.isEmpty {
                        Button { showingModels = true } label: {
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
                    Text(catalogError).font(.footnote).foregroundStyle(DS.Palette.danger)
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
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: transcript.last?.id) { _ in proxy.scrollTo("ai.chat.end", anchor: .bottom) }
            .onChange(of: transcript.last?.answer) { _ in proxy.scrollTo("ai.chat.end", anchor: .bottom) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("发消息", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(10)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .disabled(requestID != nil)
                .accessibilityIdentifier("ai.chat.composer")
            if requestID != nil {
                Button(action: stopOperation) {
                    Image(systemName: "stop.circle.fill").font(.title)
                }
                .accessibilityLabel("停止等待")
            } else {
                Button {
                    if permissionGranted { send() } else { showingSend = true }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(!validQuestion || selected == nil || busy)
                .accessibilityLabel("发送消息")
                .accessibilityIdentifier("ai.chat.send")
            }
        }
        .padding(10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func refresh() {
        guard !busy else { return }
        guard let key = Keychain.providerChatAPIKey(provider) else { showingKey = true; return }
        let id = UUID()
        refreshID = id
        catalogError = nil
        operation = Task { @MainActor in
            defer {
                if refreshID == id { refreshID = nil; operation = nil }
            }
            do {
                let fetched = try await MultiProviderAIClient().listModels(provider: provider, apiKey: key)
                guard refreshID == id, !Task.isCancelled else { return }
                models = fetched
                if selected == nil { modelID = nil }
                if chatModels.isEmpty { catalogError = "服务商未返回可选的文字聊天模型。" }
            } catch {
                guard refreshID == id, !Task.isCancelled else { return }
                models = []
                modelID = nil
                catalogError = (error as? LocalizedError)?.errorDescription ?? "未能获取模型列表。"
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
                let answer = try await MultiProviderAIClient().send(provider: provider, model: model, apiKey: key, messages: messages)
                guard !Task.isCancelled else { return }
                finish(id, answer: answer, note: nil)
            } catch {
                guard !Task.isCancelled else { return }
                finish(id, answer: nil, note: (error as? LocalizedError)?.errorDescription ?? "未收到回复。")
            }
        }
    }

    private func finish(_ id: UUID, answer: String?, note: String?) {
        guard requestID == id, let index = transcript.indices.last, transcript[index].id == id else { return }
        transcript[index].answer = answer
        transcript[index].note = note
        requestID = nil
        operation = nil
    }

    private func stopOperation() {
        operation?.cancel()
        if let id = requestID { finish(id, answer: nil, note: "已停止等待。已发出的请求可能仍产生 API 用量。") }
        refreshID = nil
        operation = nil
    }

    private func reset() {
        transcript = []
        draft = ""
        permissionGranted = false
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
    @Environment(\.dismiss) private var dismiss
    @State private var stored = false
    @State private var draft = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(stored ? "已存，输入新 Key 可替换" : "粘贴 API Key", text: $draft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("ai.key.input")
                    Button("保存到本机") { save(remove: false) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if stored {
                        Button("移除本机 Key", role: .destructive) { save(remove: true) }
                    }
                    if let error {
                        Text(error).foregroundStyle(DS.Palette.danger)
                    }
                } footer: {
                    Text("只填自己的 API Key，不填账号密码。密钥存在本机系统钥匙串，不会同步。保存不会联网。测试、刷新与问答都不会把密钥交给其他服务商。")
                }
            }
            .navigationTitle("\(provider.displayName) API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { stored = Keychain.providerChatAPIKey(provider) != nil }
        }
    }

    private func save(remove: Bool) {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard remove || (!value.isEmpty && value.utf8.count <= 512 && value.utf8.allSatisfy { (33...126).contains($0) }) else {
            error = "Key 格式不正确。请勿粘贴空格、换行或账号密码。"
            return
        }
        guard Keychain.setProviderChatAPIKey(remove ? "" : value, provider: provider) else {
            error = "未能更新 Key，请解锁设备后重试。"
            return
        }
        draft = ""
        changed(!remove)
        dismiss()
    }
}
