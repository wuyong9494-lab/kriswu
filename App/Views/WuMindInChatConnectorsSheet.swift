import SwiftUI

/// ChatGPT-Style Half-Height In-Chat Connectors, Plugins & Attachment Sheet.
/// Pops smoothly directly over the active chat (`.medium` / `.large`) so users can
/// connect GitHub repositories, toggle MCP/plugins, upload files/photos, or jump into
/// Image / Video / PPT / Tender studios without leaving the chat flow.
@MainActor
struct WuMindInChatConnectorsSheet: View {
    @ObservedObject var store: WuMindStore
    let onPickPhoto: () -> Void
    let onTakePhoto: () -> Void
    let onPickFile: () -> Void
    let onOpenFullGitHub: () -> Void
    let onOpenCustomizations: () -> Void
    let onOpenTool: (WuMindWorkspaceView.ToolboxDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var quickRepoInput = ""
    @State private var connectingRepo = false
    @State private var inlineError: String?
    @State private var inlineSuccess: String?

    private var isDark: Bool { colorScheme == .dark }
    private var sheetBg: Color {
        isDark ? Color(red: 0.055, green: 0.062, blue: 0.09) : Color(red: 0.96, green: 0.965, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.11, green: 0.12, blue: 0.16) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Quick Upload & Camera Row (3 equal-width tiles, zero horizontal scroll)
                    HStack(spacing: 10) {
                        uploadTile(icon: "camera.fill", tint: .indigo, title: "拍照识图", subtitle: "实时拍图提问") {
                            dismiss()
                            onTakePhoto()
                        }
                        uploadTile(icon: "photo.on.rectangle.angled", tint: .purple, title: "相册图片", subtitle: store.activeSupportsNativeVision ? "视觉直传" : "OCR 识字") {
                            dismiss()
                            onPickPhoto()
                        }
                        uploadTile(icon: "doc.badge.plus", tint: .blue, title: "上传文件", subtitle: "PDF / Word / Excel") {
                            dismiss()
                            onPickFile()
                        }
                    }

                    // 2. ChatGPT-Style In-Chat GitHub Connector Card
                    githubInlineCard

                    // 3. In-Chat Plugin & Connector Switches
                    pluginsInlineSection

                    // 4. Direct Creation Studios Strip (2x2 Grid)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("在对话中构建")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("全部插件与 Skills") {
                                dismiss()
                                onOpenCustomizations()
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.indigo)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 2)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            studioMiniButton(icon: "photo.on.rectangle.angled", tint: .purple, title: "文字生图") {
                                dismiss()
                                onOpenTool(.image)
                            }
                            studioMiniButton(icon: "video.badge.waveform.fill", tint: .pink, title: "AI 生视频") {
                                dismiss()
                                onOpenTool(.video)
                            }
                            studioMiniButton(icon: "rectangle.on.rectangle.angled", tint: .orange, title: "AI 写 PPT") {
                                dismiss()
                                onOpenTool(.ppt)
                            }
                            studioMiniButton(icon: "cube", tint: .blue, title: "创建 3D 空间") {
                                dismiss()
                                onOpenTool(.spatial3d)
                            }
                            studioMiniButton(icon: "chevron.left.forwardslash.chevron.right", tint: .teal, title: "构建网页") {
                                dismiss()
                                onOpenTool(.code)
                            }
                            studioMiniButton(icon: "doc.text.fill", tint: .blue, title: "写投标书") {
                                dismiss()
                                onOpenTool(.tender)
                            }
                        }
                    }
                }
                .padding(14)
            }
            .background(sheetBg.ignoresSafeArea())
            .navigationTitle("聊天内连接与插件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func uploadTile(icon: String, tint: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var githubInlineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.teal.opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.teal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("GitHub 代码仓库连接")
                            .font(.subheadline.weight(.bold))
                        if store.attachedGitHubContext != nil {
                            Text("已连接")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(store.attachedGitHubContext?.repo.fullName ?? "在当前对话直接接入公开或私有 GitHub 仓库上下文")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    dismiss()
                    onOpenFullGitHub()
                } label: {
                    Text(store.attachedGitHubContext != nil ? "管理文件" : "令牌/仓库")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.teal.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.inchat.github.manage")
            }

            if let gh = store.attachedGitHubContext {
                HStack(spacing: 8) {
                    Label("分支：\(gh.repo.defaultBranch) · 已挂载 \(gh.attachedFiles.count) 个文件", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                    Spacer()
                    Button("断开") {
                        Haptics.tap()
                        store.attachedGitHubContext = nil
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("输入 owner/repo（如 apple/swift）", text: $quickRepoInput)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("wumind.inchat.github.input")

                    Button {
                        connectQuickRepo()
                    } label: {
                        Group {
                            if connectingRepo {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Text("直连")
                                    .font(.caption.weight(.bold))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.teal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(connectingRepo || quickRepoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("wumind.inchat.github.connect")
                }
            }

            if let inlineSuccess {
                Text(inlineSuccess)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            if let inlineError {
                Text(inlineError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(13)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private var pluginsInlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("对话插件与连接器（实时生效）")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("已启 \(store.installedConnectorIDs.count) 项")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.indigo)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                let items = Array(WuMindConnectorSpec.marketplaceCatalog.prefix(6))
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, spec in
                    let isOn = store.installedConnectorIDs.contains(spec.id)
                    let tint = WuMindTintPalette.color(for: spec.tintKey)
                    HStack(spacing: 11) {
                        Image(systemName: spec.iconName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tint)
                            .frame(width: 32, height: 32)
                            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(spec.name)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(spec.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { isOn },
                            set: { _ in
                                Haptics.select()
                                store.toggleConnector(spec.id)
                            }
                        ))
                        .labelsHidden()
                        .tint(tint)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)

                    if idx < items.count - 1 {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
        }
    }

    private func studioMiniButton(icon: String, tint: Color, title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func connectQuickRepo() {
        let raw = quickRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        connectingRepo = true
        inlineError = nil
        inlineSuccess = nil
        Task { @MainActor in
            defer { connectingRepo = false }
            do {
                let ctx = try await WuMindGitHubClient().fetchRepoContext(
                    fullName: raw,
                    token: Keychain.githubToken
                )
                store.attachedGitHubContext = ctx
                inlineSuccess = "已将 \(ctx.repo.fullName) 接入当前对话上下文。"
                quickRepoInput = ""
                Haptics.success()
            } catch {
                inlineError = (error as? LocalizedError)?.errorDescription ?? "无法连接该仓库，私有库请先在「令牌/仓库」填入 GitHub PAT。"
            }
        }
    }
}
