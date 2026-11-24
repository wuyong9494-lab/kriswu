import SwiftUI
import UIKit

/// Independent text chat. Neither the current duty plan nor any other app contents
/// are included automatically. Conversation state is held only by this screen.
struct DeepSeekChatView: View {
    private typealias Client = DeepSeekChatClient
    @State private var turns: [Turn] = []
    @State private var draft = ""
    @State private var model: Client.Model = .pro
    @State private var thinking: Client.Thinking = .deep
    @State private var request: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var following = true
    @State private var showingKey = false
    @State private var confirmingSend = false
    @State private var confirmingReset = false
    @State private var consented = false
    @State private var hasKey = false
    @FocusState private var composing: Bool

    private let bottom = "deepseek.chat.bottom"
    private let questionLimit = 8_000
    private let contextLimit = 64_000

    private struct Turn: Identifiable {
        enum State: Equatable { case generating, complete, stopped, failed(String) }
        let id: UUID
        let question: String
        let isDeepThinking: Bool
        var answer = ""
        var state = State.generating
    }

    private var generating: Bool { requestID != nil }
    private var cleanedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            cloudNotice
            providerEntry
            tenderEntry
            transcript
            Divider()
            composer
        }
        .navigationTitle("DeepSeek")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { actions }
        .sheet(isPresented: $showingKey, onDismiss: loadKeyStatus) { DeepSeekPlanKeyView() }
        .alert("把这条消息发给 DeepSeek？", isPresented: $confirmingSend) {
            Button("确认发送") {
                consented = true
                beginRequest()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会发送你输入的文字和本对话的必要上下文，并使用你的 API 额度。深度思考可能更慢、用量更大。不会自动读取值班记录、计划、联系人或相册。请勿输入内部、涉密或未经许可外发的内容。")
        }
        .confirmationDialog("清空本次对话，开始新聊天？", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("开始新聊天", role: .destructive) { reset() }
        }
        .onAppear(perform: loadKeyStatus)
        .onDisappear { stopRequest() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deepseek.chat")
    }

    private var providerEntry: some View {
        NavigationLink {
            AIProviderListView()
        } label: {
            HStack {
                Label("AI 工具箱 · 切换模型", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: 720)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .disabled(generating)
        .accessibilityIdentifier("ai.providers.open")
    }

    private var tenderEntry: some View {
        NavigationLink {
            DeepSeekTenderView()
        } label: {
            HStack {
                Label("生成投标书草稿", systemImage: "doc.text")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: 720)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .disabled(generating)
        .accessibilityIdentifier("deepSeek.chat.tender")
    }

    private var cloudNotice: some View {
        Label("对话发送至 DeepSeek · 不自动读取值班资料", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
    }

    private var transcript: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if turns.isEmpty { introduction }
                    ForEach(turns) { turn in turnView(turn) }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .frame(maxWidth: 720)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.last?.id) { _ in
                if following { scroller.scrollTo(bottom, anchor: .bottom) }
            }
            .onChange(of: turns.last?.answer.utf8.count) { _ in
                if following && generating { scroller.scrollTo(bottom, anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if generating {
                    Button {
                        following.toggle()
                        if following { scroller.scrollTo(bottom, anchor: .bottom) }
                    } label: {
                        Label(following ? "暂停跟随" : "回到最新",
                              systemImage: following ? "pause.circle" : "arrow.down.circle")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .padding(8)
                }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill").font(.title2).foregroundStyle(Color.accentColor)
            Text("你好，想问什么？").font(.title2.bold())
            Text("可以提问、解释概念、起草文字或生成代码。只发你主动输入的内容，对话不保存到历史。")
                .font(.subheadline).foregroundStyle(.secondary)
            if !hasKey {
                Button("先设置 DeepSeek API Key") { showingKey = true }.buttonStyle(.borderedProminent)
            }
            VStack(alignment: .leading, spacing: 8) {
                starter("解释一个我不懂的概念")
                starter("用 Swift 写一个日期格式化函数")
            }
        }
        .padding(.vertical)
    }

    private func starter(_ text: String) -> some View {
        Button {
            draft = text
            composing = true
        } label: {
            Text(text).multilineTextAlignment(.leading)
        }
        .buttonStyle(.bordered)
    }

    private func turnView(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(turn.question)
                .textSelection(.enabled)
                .padding(12)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(Text("你：\(turn.question)"))

            VStack(alignment: .leading, spacing: 8) {
                Text("DeepSeek").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if !turn.answer.isEmpty {
                    let blocks = Self.splitAnswer(turn.answer)
                    ForEach(blocks.indices, id: \.self) { i in answerBlock(blocks[i]) }
                }
                switch turn.state {
                case .generating:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(turn.answer.isEmpty ? (turn.isDeepThinking ? "正在深度思考…" : "等待回复…") : "正在生成…").font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                case .complete:
                    Button { copy(turn.answer) } label: {
                        Label("复制回复", systemImage: "doc.on.doc").font(.caption)
                    }
                    .buttonStyle(.borderless)
                case .stopped:
                    Text("已停止，这段未完成回复不会带入下一轮。")
                        .font(.footnote).foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message).font(.footnote).foregroundStyle(DS.Palette.danger)
                    if turn.id == turns.last?.id {
                        Button("把问题放回输入框") { draft = turn.question; composing = true }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func answerBlock(_ block: AnswerBlock) -> some View {
        if let language = block.language {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(language.isEmpty ? "代码" : language).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    Button { copy(block.text) } label: {
                        Label("复制代码", systemImage: "doc.on.doc").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(block.text.isEmpty)
                }
                ScrollView(.horizontal) {
                    Text(block.text).font(.callout.monospaced()).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Text(block.text).textSelection(.enabled).lineSpacing(3)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Picker("模型", selection: $model) {
                    Text("Flash").tag(Client.Model.flash)
                    Text("V4 Pro").tag(Client.Model.pro)
                }
                .pickerStyle(.menu)
                .disabled(generating)
                Picker("思考模式", selection: $thinking) {
                    ForEach(Client.Thinking.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(generating)
                .accessibilityIdentifier("deepSeek.chat.thinking")
                Spacer()
                if draft.utf8.count > questionLimit {
                    Text("消息过长，请缩短").font(.caption).foregroundStyle(DS.Palette.danger)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("发消息", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .focused($composing)
                    .disabled(generating)
                    .accessibilityIdentifier("deepSeek.chat.composer")
                if generating {
                    Button(action: stopRequest) {
                        Image(systemName: "stop.circle.fill").font(.title)
                    }
                    .accessibilityLabel("停止生成")
                    .accessibilityIdentifier("deepseek.chat.stop")
                } else {
                    Button(action: requestSend) {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                    }
                    .disabled(cleanedDraft.isEmpty || cleanedDraft.utf8.count > questionLimit)
                    .accessibilityLabel("发送消息")
                    .accessibilityIdentifier("deepseek.chat.send")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    if !turns.isEmpty || !draft.isEmpty { confirmingReset = true }
                } label: {
                    Label("新聊天", systemImage: "square.and.pencil")
                }
                .disabled(turns.isEmpty && draft.isEmpty)
                Button {
                    showingKey = true
                } label: {
                    Label(hasKey ? "管理 DeepSeek API Key" : "设置 DeepSeek API Key", systemImage: "key")
                }
                .disabled(generating)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("聊天选项")
        }
    }

    private func loadKeyStatus() { hasKey = !(Keychain.get(.deepSeekPlanAPIKey) ?? "").isEmpty }

    private func requestSend() {
        guard !generating, !cleanedDraft.isEmpty, cleanedDraft.utf8.count <= questionLimit else { return }
        loadKeyStatus()
        guard hasKey else { showingKey = true; return }
        composing = false
        if consented { beginRequest() } else { confirmingSend = true }
    }

    private func beginRequest() {
        let question = cleanedDraft
        guard !generating, !question.isEmpty, question.utf8.count <= questionLimit else { return }
        guard let key = Keychain.get(.deepSeekPlanAPIKey), !key.isEmpty else {
            loadKeyStatus()
            showingKey = true
            return
        }
        let id = UUID()
        let chosenModel = model
        let chosenThinking = thinking
        let messages = context(for: question)
        draft = ""
        following = true
        requestID = id
        turns.append(Turn(id: id, question: question, isDeepThinking: chosenThinking == .deep))
        request = Task { @MainActor in
            do {
                for try await delta in Client.stream(messages: messages, apiKey: key, model: chosenModel, thinking: chosenThinking) {
                    guard !Task.isCancelled, requestID == id, let i = turns.indices.last else { return }
                    turns[i].answer += delta
                }
                try Task.checkCancellation()
                complete(id, as: .complete)
            } catch is CancellationError {
                complete(id, as: .stopped)
            } catch {
                let explanation = (error as? Client.Failure)?.errorDescription ?? "未收到完整回复，请检查网络后重试。"
                complete(id, as: .failed(explanation))
            }
        }
    }

    private func context(for question: String) -> [Client.Message] {
        var remaining = contextLimit - question.utf8.count
        var context: [Client.Message] = []
        for turn in turns.lazy.reversed().filter({ $0.state == .complete }).prefix(7) {
            let length = turn.question.utf8.count + turn.answer.utf8.count
            guard !turn.answer.isEmpty, length <= remaining else { break }
            remaining -= length
            context.append(.init(role: .assistant, content: turn.answer))
            context.append(.init(role: .user, content: turn.question))
        }
        return Array(context.reversed()) + [.init(role: .user, content: question)]
    }

    private func complete(_ id: UUID, as state: Turn.State) {
        guard requestID == id, let i = turns.indices.last else { return }
        turns[i].state = state
        requestID = nil
        request = nil
    }

    private func stopRequest() {
        guard let id = requestID else { return }
        request?.cancel()
        complete(id, as: .stopped)
    }

    private func reset() {
        stopRequest()
        turns.removeAll()
        draft = ""
        consented = false
    }

    private func copy(_ text: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        ToastCenter.shared.show("已复制", style: .success)
    }
}

extension DeepSeekChatView {
    fileprivate struct AnswerBlock {
        let language: String?
        let text: String
    }

    fileprivate static func splitAnswer(_ answer: String) -> [AnswerBlock] {
        var result: [AnswerBlock] = []
        var language: String?
        var lines: [Substring] = []
        for line in answer.split(separator: "\n", omittingEmptySubsequences: false) {
            let marker = line.trimmingCharacters(in: .whitespaces)
            if language == nil, marker.hasPrefix("```"), !marker.dropFirst(3).contains("`") {
                if !lines.isEmpty { result.append(AnswerBlock(language: nil, text: lines.joined(separator: "\n"))) }
                lines.removeAll(keepingCapacity: true)
                language = String(marker.dropFirst(3).prefix(24)).trimmingCharacters(in: .whitespaces)
            } else if language != nil, marker == "```" {
                result.append(AnswerBlock(language: language, text: lines.joined(separator: "\n")))
                lines.removeAll(keepingCapacity: true)
                language = nil
            } else {
                lines.append(line)
            }
        }
        if !lines.isEmpty { result.append(AnswerBlock(language: language, text: lines.joined(separator: "\n"))) }
        return result
    }
}
