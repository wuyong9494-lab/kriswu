import SwiftUI
import UIKit

/// Multi-Platform Adaptation & Compliant Publishing Hub:
/// One finished short drama -> 5 platform-tailored versions (Douyin front-hook cut,
/// Xiaohongshu 3:4 high-CTR cover & editorial copy, Kuaishou twist & comment hook,
/// Bilibili full-pace cut & episode notes, WeChat Channels social-share package).
/// Strictly separates official direct API submit (Douyin, informed consent + moderation)
/// from package handoff (manual confirmation, never faking "published").
@MainActor
struct WuMindMultiPlatformPublishSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var dramaStore = WuMindShortDramaStore.shared
    @ObservedObject private var chatStore = WuMindStore.shared

    @State private var userInformedConsent = false
    @State private var showingDouyinAuth = false
    @State private var editingPlatform: WuMindPublishPlatform?
    @State private var copiedPlatform: WuMindPublishPlatform?

    private var isDark: Bool { colorScheme == .dark }
    private var pageBg: Color {
        isDark ? Color(red: 0.035, green: 0.04, blue: 0.06) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.095, green: 0.105, blue: 0.14) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    private var selectedCount: Int {
        dramaStore.publishVariants.filter(\.isSelected).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroHeaderCard

                    if let notice = dramaStore.publishNotice {
                        bannerCard(text: notice, isError: false)
                    }
                    if let error = dramaStore.publishError {
                        bannerCard(text: error, isError: true)
                    }
                    if dramaStore.isRunningPublishBatch {
                        batchProgressCard
                    }

                    ForEach(dramaStore.publishVariants) { variant in
                        platformCard(variant)
                    }

                    complianceConfirmationCard
                    honestDataBoundaryFooter

                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(pageBg.ignoresSafeArea())
            .navigationTitle("发布到多平台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingDouyinAuth = true
                    } label: {
                        Label(
                            dramaStore.isDouyinAuthorized ? "抖音已授权" : "抖音授权",
                            systemImage: dramaStore.isDouyinAuthorized ? "checkmark.shield.fill" : "key.fill"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(dramaStore.isDouyinAuthorized ? .green : .orange)
                    }
                    .accessibilityIdentifier("ai.publish.douyinAuth")
                }
            }
            .sheet(isPresented: $showingDouyinAuth) {
                WuMindDouyinAuthSheet()
            }
            .onAppear {
                dramaStore.refreshMultiPlatformVariants(forceReset: false)
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "paperplane.circle.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("一集改完，一次备齐 5 平台专属版本")
                        .font(.subheadline.weight(.bold))
                    Text("按平台重排剪辑节奏、重做封面比例与标题文案；首发支持「抖音授权真提交（提交后入审核）+ 快手/小红书/B站/视频号发布包」。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    dramaStore.polishMultiPlatformCopy(using: chatStore)
                } label: {
                    HStack(spacing: 5) {
                        if dramaStore.isPolishingPlatformCopy {
                            ProgressView().tint(.white).controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.caption2.weight(.bold))
                        }
                        Text("AI 差异化润色 5 平台标题")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(dramaStore.isPolishingPlatformCopy)

                Button {
                    dramaStore.refreshMultiPlatformVariants(forceReset: true)
                    Haptics.tap()
                } label: {
                    Label("按最新分镜重算", systemImage: "arrow.clockwise")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    // MARK: - Platform Card

    private func platformCard(_ variant: WuMindPlatformPublishVariant) -> some View {
        let isEditing = editingPlatform == variant.platform
        let mp4URL = dramaStore.packageFileURL(filename: variant.exportedMP4Filename)
        let coverURL = dramaStore.packageFileURL(filename: variant.exportedCoverPNGFilename)
        let accent = platformAccent(variant.platform)

        return VStack(alignment: .leading, spacing: 10) {
            // Top bar: Checkbox + Name + Capability Badge + Real Status Badge
            HStack(spacing: 8) {
                Button {
                    var copy = variant
                    copy.isSelected.toggle()
                    dramaStore.updatePublishVariant(copy)
                    Haptics.tap()
                } label: {
                    Image(systemName: variant.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(variant.isSelected ? accent : .secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: variant.platform.iconName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(variant.platform.displayName)
                            .font(.subheadline.weight(.bold))
                        Text(variant.platform.capabilityBadge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(variant.platform == .douyin ? .pink : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((variant.platform == .douyin ? Color.pink : Color.secondary).opacity(0.14), in: Capsule())
                    }
                    Text(variant.targetAccountLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                statusPill(variant.status)
            }

            // Cut strategy & cover preview row
            HStack(alignment: .top, spacing: 10) {
                miniCoverPreview(variant: variant, accent: accent)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(variant.platform.editStrategyHeadline)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                        Text(String(format: "%.1fs", variant.cutPlan.estimatedDurationSeconds))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(variant.cutPlan.strategySummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("标题：\(variant.title)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)

                    Text(variant.hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.indigo)
                        .lineLimit(2)
                }
            }

            // Honest capability + AI declaration disclosure
            VStack(alignment: .leading, spacing: 4) {
                Text(variant.platform.honestCapabilityDisclosure)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(variant.platform.aiDeclarationGuide)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let detail = variant.status.detailText, variant.status != .readyForConfirm {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: statusIcon(variant.status))
                        .font(.caption)
                        .foregroundStyle(statusColor(variant.status))
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Action strip: Edit Copy / Copy Bundle / Share MP4 / Share Cover / Mark Published
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        editingPlatform = isEditing ? nil : variant.platform
                    }
                } label: {
                    Label(isEditing ? "收起编辑" : "改标题封面", systemImage: "pencil")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.13), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = variant.formattedCopyBundle()
                    copiedPlatform = variant.platform
                    Haptics.tap()
                } label: {
                    Label(copiedPlatform == variant.platform ? "已复制文案" : "复制文案", systemImage: "doc.on.doc")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.14), in: Capsule())
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if variant.platform == .douyin && !dramaStore.isDouyinAuthorized {
                    Button("去授权直投") {
                        showingDouyinAuth = true
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                }
            }

            // Exported package handoff buttons (when files are ready)
            if mp4URL != nil || coverURL != nil {
                HStack(spacing: 8) {
                    if let mp4URL {
                        ShareLink(item: mp4URL) {
                            Label("带成片去发布", systemImage: "video.badge.checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(accent, in: Capsule())
                        }
                    }
                    if let coverURL {
                        ShareLink(item: coverURL) {
                            Label("封面 PNG", systemImage: "photo")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(accent)
                        }
                    }

                    Spacer(minLength: 0)

                    if case .pendingManualPublish = variant.status {
                        Button("我已在平台发完") {
                            dramaStore.markVariantManuallyPublished(platform: variant.platform)
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.green.opacity(0.14), in: Capsule())
                    } else if case .submittedForReview = variant.status {
                        Button("审核已过·标已发") {
                            dramaStore.markVariantManuallyPublished(platform: variant.platform)
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.green.opacity(0.14), in: Capsule())
                    }
                }
            }

            if isEditing {
                inlineEditor(for: variant)
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(variant.isSelected ? accent.opacity(0.45) : cardBorder, lineWidth: variant.isSelected ? 1.3 : 1)
        )
        .accessibilityIdentifier("ai.publish.platform.\(variant.platform.rawValue)")
    }

    private func miniCoverPreview(variant: WuMindPlatformPublishVariant, accent: Color) -> some View {
        let isLandscape = variant.platform == .bilibili
        let width: CGFloat = isLandscape ? 88 : 66
        let height: CGFloat = isLandscape ? 54 : (variant.platform == .xiaohongshu ? 88 : 104)

        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.75), Color.black.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: width, height: height)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variant.coverHeadline)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(variant.platform.coverDimensions.label)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                    .padding(5)
                }

            if variant.aiDisclosure.enabled {
                Text("AI生成")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(4)
            }
        }
    }

    private func inlineEditor(for variant: WuMindPlatformPublishVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            TextField(
                "封面主标题",
                text: Binding(
                    get: { variant.coverHeadline },
                    set: { val in
                        var copy = variant; copy.coverHeadline = val; dramaStore.updatePublishVariant(copy)
                    }
                )
            )
            .font(.caption)
            .padding(8)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            TextField(
                "平台发布标题",
                text: Binding(
                    get: { variant.title },
                    set: { val in
                        var copy = variant; copy.title = val; dramaStore.updatePublishVariant(copy)
                    }
                )
            )
            .font(.caption)
            .padding(8)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            TextField(
                "正文简介",
                text: Binding(
                    get: { variant.caption },
                    set: { val in
                        var copy = variant; copy.caption = val; dramaStore.updatePublishVariant(copy)
                    }
                ),
                axis: .vertical
            )
            .lineLimit(2...4)
            .font(.caption)
            .padding(8)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            Toggle(
                "保留显式/隐式 AI 生成标识（依《生成合成内容标识办法》默认开启）",
                isOn: Binding(
                    get: { variant.aiDisclosure.enabled },
                    set: { val in
                        var copy = variant; copy.aiDisclosure.enabled = val; dramaStore.updatePublishVariant(copy)
                    }
                )
            )
            .font(.caption2.weight(.semibold))
            .tint(.orange)
        }
        .padding(.top, 4)
    }

    // MARK: - Unified Confirmation & Compliance Section

    private var complianceConfirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("《人工智能生成合成内容标识办法》合规保障")
                        .font(.caption.weight(.bold))
                    Text("导出成片右上角与各平台封面默认保留「AI生成 · WUMIND」显式标识，并向 MP4 写入隐式标识元数据；抖音代发自动携带 #AI生成 并需经过平台审核。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: $userInformedConsent) {
                Text("我已核对以上各平台的剪辑版本、封面、标题与目标账号，明确知情抖音为代提交审核、其余平台为导出发布包手动确认，并同意保留 AI 内容标识。")
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(.pink)
            .accessibilityIdentifier("ai.publish.consentToggle")

            Button {
                dramaStore.executeMultiPlatformPublish(userInformedConsent: userInformedConsent)
            } label: {
                HStack(spacing: 8) {
                    if dramaStore.isRunningPublishBatch {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.subheadline.weight(.bold))
                    }
                    Text(dramaStore.isRunningPublishBatch
                         ? dramaStore.publishBatchStatus
                         : "确认并执行（\(selectedCount) 个平台：抖音真提交 + 其余平台发布包）")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(
                    (userInformedConsent && selectedCount > 0 && !dramaStore.isRunningPublishBatch)
                        ? LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.secondary.opacity(0.38), Color.secondary.opacity(0.38)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!userInformedConsent || selectedCount == 0 || dramaStore.isRunningPublishBatch)
            .accessibilityIdentifier("ai.publish.confirmBatch")
        }
        .padding(13)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.pink.opacity(0.35), lineWidth: 1))
    }

    private var honestDataBoundaryFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("效果复盘说明：播放量、完播率与互动统计仅在后续获批对应平台官方数据权限后开放，本版本绝不展示任何估算或模拟播放数据。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }

    private var batchProgressCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.pink)
            Text(dramaStore.publishBatchStatus)
                .font(.caption.weight(.semibold))
            Spacer()
            Button("停止") {
                dramaStore.cancelActiveTask()
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.red)
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.pink.opacity(0.35), lineWidth: 1))
    }

    private func bannerCard(text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background((isError ? Color.orange : Color.green).opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusPill(_ status: WuMindPublishStatus) -> some View {
        Text(status.displayLabel)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.14), in: Capsule())
    }

    private func statusColor(_ status: WuMindPublishStatus) -> Color {
        switch status {
        case .readyForConfirm: return .secondary
        case .pendingManualPublish: return .orange
        case .submittedForReview: return .blue
        case .published: return .green
        case .failed: return .red
        }
    }

    private func statusIcon(_ status: WuMindPublishStatus) -> String {
        switch status {
        case .readyForConfirm: return "clock"
        case .pendingManualPublish: return "hand.tap.fill"
        case .submittedForReview: return "hourglass.circle.fill"
        case .published: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func platformAccent(_ platform: WuMindPublishPlatform) -> Color {
        switch platform {
        case .douyin: return .pink
        case .xiaohongshu: return .red
        case .kuaishou: return .orange
        case .bilibili: return Color(red: 0.96, green: 0.42, blue: 0.60)
        case .wechatChannels: return .green
        }
    }
}

// MARK: - Douyin Official Open Platform Authorization Sheet

@MainActor
struct WuMindDouyinAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dramaStore = WuMindShortDramaStore.shared

    @State private var openIDInput = Keychain.douyinOpenID ?? ""
    @State private var accessTokenInput = Keychain.douyinAccessToken ?? ""
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.pink)
                        Text("抖音开放平台视频创建接口（video.create）需应用审核获批并完成用户本人 OAuth 授权。每次代提交均会在发布页二次确认，且提交后仍需经过抖音平台审核；凭据仅存于本机 Keychain。")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let savedMessage {
                    Section {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Section("抖音授权账号凭据") {
                    TextField("展示账号昵称（便于发布前核对目标账号）", text: $dramaStore.douyinAccountName)
                    SecureField("授权 open_id", text: $openIDInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("授权 access_token（含 video.create 权限）", text: $accessTokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Button("保存抖音授权凭据") {
                            _ = Keychain.setDouyinOpenID(openIDInput)
                            _ = Keychain.setDouyinAccessToken(accessTokenInput)
                            dramaStore.refreshMultiPlatformVariants(forceReset: false)
                            savedMessage = (openIDInput.isEmpty || accessTokenInput.isEmpty)
                                ? "已清空抖音授权凭据，后续将改为导出抖音专属发布包。"
                                : "已将抖音 open_id 与 access_token 加密存入本机 Keychain，可发起抖音官方代提交。"
                            Haptics.success()
                        }
                        .font(.subheadline.weight(.bold))
                        Spacer()
                        if dramaStore.isDouyinAuthorized {
                            Text("已授权").font(.caption.weight(.bold)).foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("抖音官方接口授权")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
