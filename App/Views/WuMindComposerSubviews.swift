import SwiftUI
import UIKit

// MARK: - Workstream 2: Decomposed Lightweight Composer Subviews (Fixes Release AttributeGraph/Layout Bloat)

/// Isolated child view for composer context chips, uploaded attachments, shared materials,
/// pre-flight cost estimate, and voice dictation banner.
struct WuMindComposerAttachmentsStrip: View {
    @ObservedObject var store: WuMindStore
    @ObservedObject var dictation: WuMindDictationController
    let importingAttachment: Bool
    let isTemporaryChat: Bool
    let cleanedDraft: String
    let liveEstimatedTokens: Int
    let onOpenProjects: () -> Void
    let onOpenSkills: () -> Void
    let onOpenGitHub: () -> Void
    let onOpenSharedMaterials: () -> Void

    private var hasChipRow: Bool {
        store.activeProject != nil
            || !store.pendingAttachments.isEmpty
            || importingAttachment
            || store.activeSkill != nil
            || store.attachedGitHubContext != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasChipRow {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        if let proj = store.activeProject {
                            projectChip(proj)
                        }
                        if importingAttachment {
                            importingChip
                        }
                        ForEach(store.pendingAttachments) { item in
                            attachmentChip(item)
                        }
                        if let skill = store.activeSkill {
                            skillChip(skill)
                        }
                        if let gh = store.attachedGitHubContext {
                            githubChip(gh)
                        }
                    }
                }

                if !store.pendingAttachments.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.teal)
                        Text("待发送 \(store.pendingAttachments.count) 份文件/图片 → 发往：\(store.activeDataDestinationLabel)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                }
            }

            if !isTemporaryChat,
               let shared = store.activeConversation?.sharedMaterials,
               !shared.isEmpty {
                Button(action: onOpenSharedMaterials) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(DS.Font.caption.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                        Text("已共享 \(shared.count) 份资料")
                            .font(DS.Font.callout)
                            .foregroundStyle(DS.Palette.accent)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("管理")
                            .font(DS.Font.caption.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    .padding(.horizontal, 9)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .background(Color.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.sharedMaterials.pill")
            }

            if !cleanedDraft.isEmpty || !store.pendingAttachments.isEmpty || store.agentModeEnabled {
                let preFlight = store.preFlightEstimate(draftText: cleanedDraft, historyTokens: liveEstimatedTokens)
                if preFlight.isHighCost {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(preFlight.bannerText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("wumind.preflight.estimate")
                }
            }

            if dictation.isListening || dictation.statusMessage != nil {
                HStack(spacing: 7) {
                    Circle()
                        .fill(dictation.isListening ? Color.red : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(dictation.statusMessage ?? "正在语音听写…")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(dictation.isListening ? .red : .secondary)
                        .lineLimit(1)
                    Spacer()
                    if dictation.isListening {
                        Button("停止听写") {
                            Haptics.tap()
                            dictation.stop()
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((dictation.isListening ? Color.red : Color.secondary).opacity(0.09), in: Capsule())
            }
        }
    }

    private func projectChip(_ proj: WuMindProject) -> some View {
        let projColor = WuMindTintPalette.color(for: proj.colorKey)
        return HStack(spacing: 5) {
            Button(action: onOpenProjects) {
                HStack(spacing: 4) {
                    Image(systemName: proj.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("项目：\(proj.name)")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(projColor)
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                store.selectProject(nil, startFreshChat: false)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(projColor.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(projColor.opacity(0.12), in: Capsule())
    }

    private var importingChip: some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.mini)
            Text("解析附件中…")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func attachmentChip(_ item: WuMindAttachment) -> some View {
        HStack(spacing: 6) {
            if let jpeg = item.document.imageJPEGData, let thumb = UIImage(data: jpeg) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: item.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.tintColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.document.filename)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)
                HStack(spacing: 4) {
                    Text(item.document.summaryBadge)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if item.document.hasNativeImage {
                        let visionOK = store.activeSupportsNativeVision
                        Text(visionOK ? "视觉直传" : "OCR")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(visionOK ? .teal : .orange)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background((visionOK ? Color.teal : Color.orange).opacity(0.15), in: Capsule())
                    }
                }
            }
            Button {
                Haptics.tap()
                store.removeAttachment(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除附件 \(item.document.filename)")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(item.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(item.tintColor.opacity(0.25), lineWidth: 0.8)
        )
    }

    private func skillChip(_ skill: WuMindSkill) -> some View {
        HStack(spacing: 5) {
            Button(action: onOpenSkills) {
                HStack(spacing: 4) {
                    Image(systemName: skill.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(skill.name)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.indigo)
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                store.selectSkill(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo.opacity(0.65))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消 Skill")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.indigo.opacity(0.12), in: Capsule())
    }

    private func githubChip(_ gh: WuMindGitHubClient.RepoContext) -> some View {
        HStack(spacing: 5) {
            Button(action: onOpenGitHub) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(gh.attachedFiles.isEmpty
                         ? gh.repo.fullName
                         : "\(gh.repo.fullName) +\(gh.attachedFiles.count) 文件")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.teal)
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                store.attachedGitHubContext = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.teal.opacity(0.65))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("断开 GitHub 仓库")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.teal.opacity(0.13), in: Capsule())
    }
}

/// Isolated lightweight child view for the multi-line composer TextField.
struct WuMindComposerTextInput: View {
    let placeholder: String
    @Binding var draft: String
    let generating: Bool
    var composerFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField(placeholder, text: $draft, axis: .vertical)
            .lineLimit(2...7)
            .font(.system(size: 16))
            .frame(minHeight: 54, alignment: .topLeading)
            .focused(composerFocused)
            .disabled(generating)
            .contentShape(Rectangle())
            .onTapGesture {
                if !generating {
                    composerFocused.wrappedValue = true
                }
            }
            .accessibilityIdentifier("deepSeek.chat.composer")
    }
}

/// Isolated child view for composer mode toggles and primary action buttons (+ / model / voice / send / stop).
struct WuMindComposerActionButtons: View {
    @ObservedObject var store: WuMindStore
    let activeAccentColor: Color
    let generating: Bool
    let importingAttachment: Bool
    let isFocused: Bool
    let isOverLimit: Bool
    let canSend: Bool
    let canManualCompact: Bool
    let liveUsageRatio: Double
    let liveEstimatedTokens: Int
    let compactModelTitle: String
    let headerModelTitle: String
    let canOfferBuild: Bool
    let selectedBuild: WuMindChatBuild?
    let onSelectBuild: (WuMindChatBuild?) -> Void
    let onOpenSkills: () -> Void
    let onOpenConnectors: () -> Void
    let onOpenModelHub: () -> Void
    let onManualCompact: () -> Void
    let onDismissKeyboard: () -> Void
    let onOpenVoiceInput: () -> Void
    let onOpenRealtimeVoice: () -> Void
    let onStop: () -> Void
    let onSend: () -> Void

    @State private var expandedOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if expandedOptions && !generating {
                modeStripRow
            } else if let selectedBuild, !generating {
                Button { onSelectBuild(nil) } label: {
                    Label(selectedBuild.title, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.chat.buildPicker")
                .accessibilityLabel(selectedBuild.title)
                .accessibilityHint("取消构建，返回普通对话")
            }
            primaryActionRow
        }
        .onChange(of: generating) { active in
            if active { expandedOptions = false }
        }
    }

    private var modeStripRow: some View {
        HStack(spacing: 5) {
            if canOfferBuild {
                Menu {
                    ForEach(WuMindChatBuild.allCases) { tool in
                        Button { onSelectBuild(tool) } label: { Label(tool.title, systemImage: tool.icon) }
                    }
                    if selectedBuild != nil {
                        Button("返回普通对话") { onSelectBuild(nil) }
                    }
                } label: {
                    Image(systemName: selectedBuild?.icon ?? "hammer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedBuild == nil ? Color.secondary : Color.primary)
                        .frame(minWidth: 36, minHeight: 34)
                        .background(Color.primary.opacity(selectedBuild == nil ? 0.07 : 0.17), in: Capsule())
                }
                .disabled(generating)
                .accessibilityLabel(selectedBuild?.title ?? "选择构建任务")
                .accessibilityIdentifier("wumind.chat.buildPicker")
            }
            Button {
                Haptics.select()
                store.webSearchEnabled.toggle()
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "globe")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("联网")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(store.webSearchEnabled ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
                .background(
                    store.webSearchEnabled ? Color.primary.opacity(0.16) : Color.secondary.opacity(0.08),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(generating)
            .accessibilityLabel(store.webSearchEnabled ? "联网搜索已开启" : "开启实时联网搜索")
            .accessibilityIdentifier("wumind.webSearch.toggle")

            if store.activeSupportsDeepThinking {
                Button {
                    Haptics.select()
                    store.toggleDeepThinking()
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("思考")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(store.deepThinking ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)
                    .background(
                        store.deepThinking ? Color.primary.opacity(0.16) : Color.secondary.opacity(0.08),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(generating)
                .accessibilityLabel(store.deepThinking ? "深度思考已开启" : "深度思考已关闭")
                .accessibilityIdentifier("deepSeek.chat.thinking")
            }

            Button {
                Haptics.select()
                store.toggleAgentMode()
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("智能体")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(store.agentModeEnabled ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
                .background(
                    store.agentModeEnabled ? Color.primary.opacity(0.16) : Color.secondary.opacity(0.08),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(generating)
            .accessibilityLabel(store.agentModeEnabled ? "智能体模式已开启" : "开启多步骤智能体模式")
            .accessibilityIdentifier("wumind.agent.toggle")

            Button(action: onOpenSkills) {
                HStack(spacing: 3.5) {
                    Image(systemName: store.activeSkill?.icon ?? "puzzlepiece.extension.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(store.activeSkill != nil ? "定制✓" : "定制")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(store.activeSkill != nil ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
                .background(
                    store.activeSkill != nil ? Color.indigo : Color.secondary.opacity(0.11),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(generating)
            .accessibilityLabel("WUMIND 定制与 Skills 中心")
            .accessibilityIdentifier("wumind.skills.open")

            contextWindowMenu

            Menu {
                Button(action: onOpenModelHub) { Label("切换模型", systemImage: "slider.horizontal.3") }
                Button(action: onOpenConnectors) { Label("GitHub 与连接器", systemImage: "chevron.left.forwardslash.chevron.right") }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 26, minHeight: 32)
            }
            .accessibilityLabel("模型与连接器")
            .accessibilityIdentifier("wumind.composer.connections")
        }
    }

    private var contextWindowMenu: some View {
        let tint: Color = {
            if store.compactingContext || generating { return .indigo }
            return liveUsageRatio >= 0.80 ? .orange : (store.autoCompactContext ? .indigo : .secondary)
        }()
        return Menu {
            if !generating {
                let pct = Int((liveUsageRatio * 100).rounded())
                Text("当前上下文：\(WuMindAccountStatus.formatTokens(liveEstimatedTokens)) / \(store.maxContextLabel) Tokens（\(pct)%）")
                Divider()
            }
            Button {
                Haptics.select()
                store.setAutoCompactContext(!store.autoCompactContext)
            } label: {
                Label(
                    store.autoCompactContext ? "自动压缩上下文（已开启 · 80% 触发）" : "开启自动压缩上下文（Claude 模式）",
                    systemImage: store.autoCompactContext ? "checkmark.circle.fill" : "circle"
                )
            }
            Menu {
                ForEach([1_000_000, 512_000, 256_000, 128_000], id: \.self) { cap in
                    let label = cap >= 1_000_000 ? "1M Tokens（旗舰超长上下文）" : "\(cap / 1_000)K Tokens"
                    Button {
                        Haptics.select()
                        store.setMaxContextTokens(cap)
                    } label: {
                        if store.maxContextTokens == cap {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                Label("上下文窗口上限：\(store.maxContextLabel)", systemImage: "slider.horizontal.3")
            }
            if canManualCompact {
                Divider()
                Button(action: onManualCompact) {
                    Label("立即压缩当前上下文（/compact）", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: store.compactingContext ? "arrow.triangle.2.circlepath" : "memorychip")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(store.compactingContext ? "压缩中" : store.maxContextLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
        }
        .disabled(generating || store.compactingContext)
        .accessibilityLabel("上下文窗口与自动压缩")
        .accessibilityIdentifier("wumind.context.menu")
    }

    private var primaryActionRow: some View {
        HStack(spacing: 7) {
            Button(action: onOpenConnectors) {
                HStack(spacing: 4) {
                    Image(systemName: store.pendingAttachments.isEmpty ? "plus" : "paperclip")
                        .font(.system(size: 14, weight: .semibold))
                    if !store.pendingAttachments.isEmpty {
                        Text("\(store.pendingAttachments.count)")
                            .font(.caption2.weight(.bold))
                    }
                }
                .foregroundStyle(store.pendingAttachments.isEmpty ? Color.primary : Color.white)
                .frame(minWidth: 34, minHeight: 34)
                .padding(.horizontal, store.pendingAttachments.isEmpty ? 2 : 8)
                .background(
                    store.pendingAttachments.isEmpty ? Color.secondary.opacity(0.13) : activeAccentColor,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(generating || importingAttachment)
            .accessibilityLabel("聊天内连接器、插件与文件上传")
            .accessibilityIdentifier("wumind.attach.open")

            if !generating {
                Button { expandedOptions.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("对话选项")
                .accessibilityValue(expandedOptions ? "已展开" : "已收起")
                .accessibilityIdentifier("wumind.composer.options")
            }

            Spacer(minLength: 4)

            if isOverLimit {
                Text("过长")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Palette.danger)
            }

            if isFocused && !generating {
                Button(action: onDismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.13), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起键盘")
                .accessibilityIdentifier("wumind.composer.dismissKeyboard")
            }

            if !generating {
                Button(action: onOpenVoiceInput) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("语音输入")
                .accessibilityIdentifier("wumind.composer.mic")

                Button(action: onOpenRealtimeVoice) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 38, height: 38)
                        .background(Color.primary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("开始实时语音通话")
                .accessibilityIdentifier("wumind.composer.dictate")
            }

            if generating {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(DS.Palette.danger, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("停止生成")
                .accessibilityIdentifier("deepseek.chat.stop")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? .white : .secondary)
                        .frame(width: 38, height: 38)
                        .background(
                            canSend ? activeAccentColor : Color.secondary.opacity(0.20),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("发送消息")
                .accessibilityIdentifier("deepseek.chat.send")
            }
        }
    }
}

// MARK: - Workstream 6: Reference-Recording Shared Inline Status & Citations Components

/// Single shared inline live status row directly under the assistant intro lead.
/// Left: small animated status icon. Right: low-contrast wrapping text updated in-place
/// from real Gateway SSE events (`正在搜索：{真实搜索词}` / `正在阅读：{来源名}` / `正在调用：{智能体名称}`).
struct WuMindInlineStatusRow: View {
    let introLead: String?
    let kind: WuMindStreamBuffer.InlineStatusKind?
    let text: String?
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var iconName: String {
        switch kind ?? .searching {
        case .searching: return "globe"
        case .reading: return "doc.text.magnifyingglass"
        case .agent: return "cpu.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var iconTint: Color {
        switch kind ?? .searching {
        case .searching, .reading, .agent: return .secondary
        case .warning: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let introLead, !introLead.isEmpty {
                Text(introLead)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let text, !text.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconTint.opacity(isActive && pulse ? 0.55 : 0.95))
                        .scaleEffect(isActive && pulse ? 0.92 : 1.0)
                        .animation(
                            isActive && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : nil,
                            value: pulse
                        )
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("wumind.inline.statusRow")
                .onAppear { pulse = isActive }
                .onChange(of: isActive) { active in pulse = active }
            }
        }
    }
}

/// Persisted structured web citations, visually separate agent citations (`引用了 {智能体名称}` ONLY if succeeded),
/// and honest tool failure banners with retry button. Survives reopening the chat.
struct WuMindTurnCitationsSection: View {
    let webCitations: [WuMindWebCitation]
    let agentCitations: [WuMindAgentCitation]
    let failureNotices: [WuMindToolFailureNotice]
    let elevatedSurface: Color
    let subtleBorder: Color
    let onRetry: (() -> Void)?

    @State private var sourcesExpanded = false
    @State private var expandedAgentID: String? = nil

    private var succeededAgents: [WuMindAgentCitation] {
        WuMindToolTruthfulnessPolicy.visibleAgentCitations(from: agentCitations)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Explicit failure banner when search or agent failed (never hidden or disguised!)
            if !failureNotices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(failureNotices) { notice in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                let label = notice.toolKind == "web_search"
                                    ? "联网搜索未完成（\(notice.targetName)）"
                                    : "工具/智能体调用未完成（\(notice.targetName)）"
                                Text(label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(notice.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            if let onRetry {
                                Button("重试", action: onRetry)
                                    .font(.caption2.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.8))
                .accessibilityIdentifier("wumind.turn.toolFailureBanner")
            }

            // 2. Separate Agent Citation Pills (`引用了 {智能体名称}` ONLY when succeeded == true!)
            if !succeededAgents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(succeededAgents) { ag in
                            Button {
                                withAnimation(DS.Motion.snappy) {
                                    expandedAgentID = (expandedAgentID == ag.id) ? nil : ag.id
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "circle.hexagongrid")
                                        .font(.caption)
                                    Text("引用了 \(ag.agentName)")
                                        .font(.caption)
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 11)
                                .frame(minHeight: 32)
                                .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wumind.turn.agentCitation")
                        }
                    }
                }

                if let openID = expandedAgentID,
                   let selected = succeededAgents.first(where: { $0.id == openID }),
                   !selected.summary.isEmpty {
                    Text("\(selected.agentName)：\(selected.summary)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            // 3. Expandable Web Sources (visually separate from agent citations)
            if !webCitations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(DS.Motion.snappy) {
                            sourcesExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.blue)
                            Text("来源（\(webCitations.count)）")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(webCitations.prefix(3).map(\.domain).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: sourcesExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(subtleBorder, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wumind.turn.webSources")

                    if sourcesExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(webCitations) { src in
                                if let url = URL(string: src.url) {
                                    Link(destination: url) {
                                        sourceRow(src)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    sourceRow(src)
                                }
                            }
                        }
                        .padding(8)
                        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(subtleBorder, lineWidth: 0.8))
                    }
                }
            }
        }
    }

    private func sourceRow(_ src: WuMindWebCitation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(src.domain)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                if src.verifiedRead {
                    Text("已读原文")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.teal.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(src.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if !src.snippet.isEmpty {
                Text(src.snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}
