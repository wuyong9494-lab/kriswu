import AVKit
import PhotosUI
import SwiftUI
import UIKit

/// Flagship WUMIND Short-Drama Studio v1 (短剧工坊):
/// 30–60s 9:16 vertical storyboard + rough cut + selective single-shot reshoot
/// ("这一镜不好，只重拍这一镜") with official Volcengine Ark Seedance & Kling APIs,
/// per-character reference portraits & voices, independent subtitle/voiceover tracks, and real MP4 export.
@MainActor
struct WuMindShortDramaView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var dramaStore = WuMindShortDramaStore.shared
    @ObservedObject private var chatStore = WuMindStore.shared

    @Binding var showingAPIConfig: Bool

    @State private var premiseInput = ""
    @State private var selectedGenre: WuMindDramaGenre = .suspense
    @State private var targetDuration = 36
    @State private var inspectingShotID: UUID?
    @State private var expandedTrimShotID: UUID?
    @State private var showingMultiPlatformPublish = false
    @State private var roughCutPlayer: AVPlayer?
    @FocusState private var premiseFocused: Bool

    private var isDark: Bool { colorScheme == .dark }
    private var cardBg: Color { DS.Palette.cardSurface }
    private var cardBorder: Color { DS.Palette.hairline }

    private var totalTrimmedDuration: Double {
        WuMindShortDramaEngine.totalTrimmedDuration(for: dramaStore.project)
    }

    private var renderedCount: Int {
        WuMindShortDramaEngine.renderedShotCount(for: dramaStore.project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            premiseComposerCard
            telemetryBar

            if let notice = dramaStore.lastNotice {
                statusBanner(text: notice, isError: false)
            }
            if let error = dramaStore.lastError {
                statusBanner(text: error, isError: true)
            }
            if dramaStore.isGeneratingStoryboard {
                progressCard(title: dramaStore.storyboardStatus, subtitle: "正在编排角色、景别与台词")
            }
            if let activeID = dramaStore.activeShotGenerationID,
               let idx = dramaStore.project.shots.firstIndex(where: { $0.id == activeID }) {
                progressCard(
                    title: "第 \(idx + 1) 镜单镜渲染中：\(dramaStore.activeShotProgress?.stage ?? "请稍候…")",
                    subtitle: "其余 \(max(0, dramaStore.project.shots.count - 1)) 个镜头时间线保持不动 · 已耗时 \(Int(dramaStore.activeShotProgress?.elapsedSeconds ?? 0))s",
                    percent: dramaStore.activeShotProgress?.percent
                )
            }

            characterReferenceSection
            multiTrackExportCard

            if let mp4URL = dramaStore.exportedMP4URL {
                exportedMP4Card(url: mp4URL)
            }

            timelineSection
        }
        .sheet(isPresented: Binding(
            get: { inspectingShotID != nil },
            set: { if !$0 { inspectingShotID = nil } }
        )) {
            if let sid = inspectingShotID {
                WuMindShotReshootSheet(shotID: sid, showingAPIConfig: $showingAPIConfig)
            }
        }
        .sheet(isPresented: $showingMultiPlatformPublish) {
            WuMindMultiPlatformPublishSheet()
        }
        .onChange(of: dramaStore.exportedMP4URL) { newURL in
            roughCutPlayer?.pause()
            if let newURL {
                roughCutPlayer = AVPlayer(url: newURL)
            } else {
                roughCutPlayer = nil
            }
        }
        .onDisappear {
            roughCutPlayer?.pause()
        }
    }

    // MARK: - 1. Telemetry Bar (Steps / Reshoots / Cost Transparency)

    private var telemetryBar: some View {
        let project = dramaStore.project
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
        ) {
            metricTile(
                title: "成片时长",
                value: String(format: "%.1fs", totalTrimmedDuration),
                sub: "9:16 竖屏",
                accent: .purple
            )
            metricTile(
                title: "已生成镜头",
                value: "\(renderedCount)/\(project.shots.count)",
                sub: "支持逐镜生成",
                accent: .blue
            )
            metricTile(
                title: "单镜重拍",
                value: "\(project.singleShotReshoots) 次",
                sub: "免全剧重跑",
                accent: .teal
            )
            metricTile(
                title: "本集花费",
                value: String(format: "¥%.2f", project.estimatedTotalCostYuan),
                sub: "估算参考",
                accent: .orange
            )
        }
    }

    private func metricTile(title: String, value: String, sub: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    // MARK: - 2. Storyboard Premise Composer

    private var premiseComposerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clapperboard.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 1) {
                    Text("故事梗概")
                        .font(.subheadline.weight(.bold))
                    Text("生成分镜后，选择一个镜头重拍或对比版本。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TextField(
                "输入一句话短剧创意（30–60 秒 9:16 竖屏）…",
                text: $premiseInput,
                axis: .vertical
            )
            .lineLimit(2...4)
            .font(.subheadline)
            .focused($premiseFocused)
            .padding(10)
            .background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("ai.video.prompt")

            HStack(spacing: 8) {
                Menu {
                    ForEach(WuMindDramaGenre.allCases) { genre in
                        Button(genre.rawValue) { selectedGenre = genre }
                    }
                } label: {
                    compactBadge(icon: "theatermasks", text: selectedGenre.rawValue)
                }
                .tint(.primary)

                Menu {
                    ForEach([30, 36, 45, 60], id: \.self) { sec in
                        Button("\(sec) 秒") { targetDuration = sec }
                    }
                } label: {
                    compactBadge(icon: "timer", text: "\(targetDuration)秒")
                }
                .tint(.primary)

                Button {
                    premiseFocused = false
                    dramaStore.loadSampleDrama()
                    Haptics.tap()
                } label: {
                    compactBadge(icon: "sparkles", text: "样板剧")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.drama.loadSample")

                Spacer(minLength: 2)

                Button {
                    premiseFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    let seed = premiseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? dramaStore.project.premise
                        : premiseInput
                    dramaStore.generateStoryboard(
                        premise: seed,
                        genre: selectedGenre,
                        targetDurationSeconds: targetDuration,
                        using: chatStore
                    )
                } label: {
                    HStack(spacing: 5) {
                        if dramaStore.isGeneratingStoryboard {
                            ProgressView().tint(.white).controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.caption.weight(.bold))
                        }
                        Text("生成分镜")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(dramaStore.isGeneratingStoryboard)
                .accessibilityIdentifier("ai.video.generate")
            }
        }
        .padding(13)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    // MARK: - 3. Character Reference Portrait & Voice Strip

    private var characterReferenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("角色参考图与专属音色")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if chatStore.channel == .ownAPI {
                    Button {
                        showingAPIConfig = true
                    } label: {
                        let configuredCount = WuMindDramaVideoEngine.allCases.filter { dramaStore.isEngineConfigured($0) }.count
                        Label("官方接口 (\(configuredCount)/\(WuMindDramaVideoEngine.allCases.count))", systemImage: "key.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(configuredCount > 0 ? .green : .orange)
                    }
                    .accessibilityIdentifier("ai.drama.apiConfig")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(dramaStore.project.characters) { char in
                        characterCard(char)
                    }
                }
            }

            Text("每镜自动附带角色参考图（即梦/可灵图生视频）与固定音色；若对不同镜头切换视频引擎，无法保证跨引擎人物脸部完全一致。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func characterCard(_ char: WuMindDramaCharacter) -> some View {
        HStack(spacing: 10) {
            CharacterPortraitPickerButton(referenceImageBase64: char.referenceImageBase64) { b64 in
                dramaStore.updateCharacterReferenceImage(characterID: char.id, jpegBase64: b64)
                Haptics.success()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(char.name)
                        .font(.caption.weight(.bold))
                    Text(char.roleSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Menu {
                    ForEach(WuMindDramaVoicePreset.allCases) { preset in
                        Button {
                            dramaStore.updateCharacterVoice(characterID: char.id, voice: preset)
                        } label: {
                            Label(preset.displayName, systemImage: preset == char.voicePreset ? "checkmark" : "waveform")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.teal)
                        Text(char.voicePreset.displayName)
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.teal.opacity(0.13), in: Capsule())
                }
                .tint(.primary)
            }
        }
        .padding(10)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    // MARK: - 4. Independent Tracks & Export 9:16 MP4

    private var multiTrackExportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                trackTogglePill(
                    title: "独立字幕轨",
                    icon: "captions.bubble.fill",
                    isOn: dramaStore.project.globalSubtitlesEnabled,
                    accent: .indigo
                ) {
                    dramaStore.setGlobalSubtitles(!dramaStore.project.globalSubtitlesEnabled)
                }

                trackTogglePill(
                    title: "独立配音轨",
                    icon: "waveform.circle.fill",
                    isOn: dramaStore.project.globalVoiceoverEnabled,
                    accent: .teal
                ) {
                    dramaStore.setGlobalVoiceover(!dramaStore.project.globalVoiceoverEnabled)
                }

                Spacer(minLength: 0)
            }

            Button {
                dramaStore.exportRoughCutMP4()
            } label: {
                HStack(spacing: 8) {
                    if dramaStore.isExportingMP4 {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "film.stack.fill")
                            .font(.subheadline.weight(.bold))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        let exportKind = WuMindShortDramaEngine.exportKind(for: dramaStore.project)
                        Text(dramaStore.isExportingMP4 ? dramaStore.exportStatus : exportKind.buttonTitle)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                        Text(renderedCount == dramaStore.project.shots.count
                             ? "全剧 \(renderedCount) 镜均已生成，直接封装成片 MP4 发微信"
                             : "当前已生成镜头 \(renderedCount)/\(dramaStore.project.shots.count)，未生成镜头先以动态分镜占位，导出为「粗剪预览」")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.subheadline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.42, green: 0.24, blue: 0.94), Color(red: 0.85, green: 0.22, blue: 0.56)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(dramaStore.isExportingMP4)
            .accessibilityIdentifier("ai.drama.exportMP4")

            Button {
                dramaStore.refreshMultiPlatformVariants(forceReset: false)
                showingMultiPlatformPublish = true
                Haptics.tap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("分平台发布")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("编辑各平台的封面、标题和版本，再确认发布。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isDark ? Color.pink.opacity(0.13) : Color.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.pink.opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ai.drama.multiPublish")
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private func trackTogglePill(
        title: String,
        icon: String,
        isOn: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(isOn ? "开" : "关")
                    .font(.system(size: 10, weight: .heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isOn ? accent.opacity(0.24) : Color.secondary.opacity(0.18), in: Capsule())
            }
            .foregroundStyle(isOn ? accent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isOn ? accent.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? accent.opacity(0.38) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func exportedMP4Card(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("已导出竖屏 MP4", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
                Spacer()
                ShareLink(item: url) {
                    Label("发微信 / 分享 MP4", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.green, in: Capsule())
                }
            }

            if let roughCutPlayer {
                VideoPlayer(player: roughCutPlayer)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.green.opacity(0.35), lineWidth: 1))
    }

    // MARK: - 5. Shot Timeline (Reorder + Trim + Selective Single-Shot Reshoot)

    private var timelineSection: some View {
        let shots = dramaStore.project.shots
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("《\(dramaStore.project.title)》分镜时间线")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("点任意镜头即可单镜重拍")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                shotTimelineCard(shot: shot, index: index, total: shots.count)
            }
        }
    }

    private func shotTimelineCard(shot: WuMindDramaShot, index: Int, total: Int) -> some View {
        let character = dramaStore.project.character(for: shot)
        let isRenderingThisShot = dramaStore.activeShotGenerationID == shot.id
        let isTrimExpanded = expandedTrimShotID == shot.id

        return VStack(alignment: .leading, spacing: 9) {
            // Header strip
            HStack(spacing: 7) {
                Text("#\(index + 1)")
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(shot.isRendered ? Color.green : Color.purple, in: Capsule())

                Text(shot.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Text(shot.cameraFraming.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.14), in: Capsule())

                Spacer(minLength: 4)

                if let take = shot.activeTake {
                    Text("Take \(take.takeNumber)/\(shot.takes.count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14), in: Capsule())
                } else {
                    Text("分镜待拍")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }
            }

            // Visual description + Dialogue
            Text(shot.visualPrompt)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(2)

            if !shot.dialogue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text(character?.name ?? "台词")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.teal.opacity(0.14), in: Capsule())
                    Text("「\(shot.dialogue)」")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Metadata & Actions Row
            HStack(spacing: 6) {
                Text(shot.preferredEngine.shortBadge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                Text(String(format: "%.1fs", shot.trimmedDuration))
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 2)

                // Reorder up/down
                Button {
                    dramaStore.moveShot(fromIndex: index, toIndex: index - 1)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.caption2.weight(.bold))
                        .padding(6)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .disabled(index == 0)
                .buttonStyle(.plain)

                Button {
                    dramaStore.moveShot(fromIndex: index, toIndex: index + 1)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.caption2.weight(.bold))
                        .padding(6)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .disabled(index == total - 1)
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedTrimShotID = isTrimExpanded ? nil : shot.id
                    }
                } label: {
                    Label("裁剪", systemImage: "scissors")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isTrimExpanded ? Color.purple.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(isTrimExpanded ? .purple : .primary)
                }
                .buttonStyle(.plain)

                Button {
                    inspectingShotID = shot.id
                } label: {
                    HStack(spacing: 4) {
                        if isRenderingThisShot {
                            ProgressView().tint(.white).controlSize(.mini)
                        } else {
                            Image(systemName: shot.isRendered ? "arrow.triangle.2.circlepath.camera" : "video.fill")
                                .font(.caption2.weight(.bold))
                        }
                        Text(shot.isRendered ? "只重拍这镜" : "生成本镜")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.drama.shot.\(index + 1).reshoot")
            }

            if isTrimExpanded {
                shotTrimEditor(shot: shot)
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isRenderingThisShot ? Color.pink.opacity(0.6) : cardBorder, lineWidth: isRenderingThisShot ? 1.5 : 1)
        )
    }

    private func shotTrimEditor(shot: WuMindDramaShot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text("入点 \(String(format: "%.1fs", shot.trimStartSeconds))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { shot.trimStartSeconds },
                        set: { dramaStore.updateTrim(shotID: shot.id, trimStart: $0, trimEnd: shot.trimEndSeconds) }
                    ),
                    in: 0...max(0.5, shot.durationSeconds - 1.0),
                    step: 0.2
                )
                .tint(.purple)
            }
            HStack {
                Text("出点 \(String(format: "%.1fs", shot.trimEndSeconds))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { shot.trimEndSeconds },
                        set: { dramaStore.updateTrim(shotID: shot.id, trimStart: shot.trimStartSeconds, trimEnd: $0) }
                    ),
                    in: min(shot.durationSeconds, shot.trimStartSeconds + 1.0)...shot.durationSeconds,
                    step: 0.2
                )
                .tint(.pink)
            }

            HStack(spacing: 12) {
                Toggle("本镜字幕", isOn: Binding(
                    get: { shot.subtitleEnabled },
                    set: { enabled in
                        var copy = shot
                        copy.subtitleEnabled = enabled
                        dramaStore.updateShot(copy)
                    }
                ))
                .font(.caption2.weight(.semibold))

                Toggle("本镜配音", isOn: Binding(
                    get: { shot.voiceoverEnabled },
                    set: { enabled in
                        var copy = shot
                        copy.voiceoverEnabled = enabled
                        dramaStore.updateShot(copy)
                    }
                ))
                .font(.caption2.weight(.semibold))
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func compactBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), in: Capsule())
    }

    private func statusBanner(text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background((isError ? Color.orange : Color.green).opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func progressCard(title: String, subtitle: String, percent: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().tint(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption.weight(.bold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("停止") {
                    dramaStore.cancelActiveTask()
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.14), in: Capsule())
            }
            if let percent {
                ProgressView(value: Double(max(0, min(100, percent))), total: 100)
                    .tint(.pink)
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.pink.opacity(0.35), lineWidth: 1))
    }

}

@MainActor
private struct CharacterPortraitPickerButton: View {
    let referenceImageBase64: String?
    let onPickedBase64: (String) -> Void

    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickedItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                if let b64 = referenceImageBase64,
                   let data = Data(base64Encoded: b64),
                   let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [.purple.opacity(0.35), .pink.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                        .overlay {
                            VStack(spacing: 2) {
                                Image(systemName: "person.crop.rectangle.badge.plus")
                                    .font(.caption.weight(.bold))
                                Text("参考图")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                        }
                }
                Image(systemName: "camera.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.purple, in: Circle())
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: pickedItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let b64 = Self.normalizedReferencePortraitBase64(from: data) {
                    onPickedBase64(b64)
                }
                pickedItem = nil
            }
        }
    }

    private static func normalizedReferencePortraitBase64(from rawData: Data) -> String? {
        guard let image = UIImage(data: rawData) else { return nil }
        let maxSide: CGFloat = 768
        let longest = max(image.size.width, image.size.height)
        let scaledImage: UIImage
        if longest > maxSide, longest > 0 {
            let ratio = maxSide / longest
            let newSize = CGSize(width: (image.size.width * ratio).rounded(), height: (image.size.height * ratio).rounded())
            let renderer = UIGraphicsImageRenderer(size: newSize)
            scaledImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaledImage = image
        }
        guard let jpeg = scaledImage.jpegData(compressionQuality: 0.78) else { return nil }
        return jpeg.base64EncodedString()
    }
}

// MARK: - Single-Shot Reshoot & A/B Take Comparison Sheet ("这一镜不好，只重拍这一镜")

@MainActor
struct WuMindShotReshootSheet: View {
    let shotID: UUID
    @Binding var showingAPIConfig: Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dramaStore = WuMindShortDramaStore.shared
    @ObservedObject private var chatStore = WuMindStore.shared

    @State private var reshootInstruction = ""
    @State private var keepDialogueAndVoice = true
    @State private var editedDialogue = ""
    @State private var selectedEngine: WuMindDramaVideoEngine = .seedance
    @State private var previewingTakeID: UUID?
    @State private var takePlayer: AVPlayer?
    @State private var showingDurationConfirm = false

    private static let quickPresets = [
        "换成近景，台词和声音不变",
        "推进人物眼神特写，情绪更紧绷",
        "改为冷蓝夜雨光影，运镜放慢",
        "切换低角度仰拍，增强压迫感",
    ]

    private var shotIndex: Int? {
        dramaStore.project.shots.firstIndex(where: { $0.id == shotID })
    }

    private var shot: WuMindDramaShot? {
        guard let idx = shotIndex else { return nil }
        return dramaStore.project.shots[idx]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let shot, let idx = shotIndex {
                    let character = dramaStore.project.character(for: shot)
                    let crossWarning = WuMindShortDramaEngine.crossEngineConsistencyWarning(
                        for: dramaStore.project,
                        shotID: shot.id,
                        targetEngine: selectedEngine
                    )
                    let isWorking = dramaStore.activeShotGenerationID == shot.id
                    let genPlan = dramaStore.generationPlan(for: shot, engine: selectedEngine)
                    let estShotCost = genPlan.estimatedCostYuan
                    let channelDesc = dramaStore.channelLabel(for: selectedEngine)
                    let isConfigured = dramaStore.isEngineConfigured(selectedEngine)

                    Form {
                        Section("第 \(idx + 1) 镜 · 仅改这一镜，其余时间线不动") {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(shot.title).font(.headline)
                                    Spacer()
                                    Text("时间线 \(String(format: "%.1f", shot.durationSeconds))s")
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.14), in: Capsule())
                                    Text(shot.cameraFraming.label)
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.indigo.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.indigo)
                                }
                                Text(shot.visualPrompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !shot.takes.isEmpty {
                            Section("历史版本 A/B 对比（旧版保留不覆盖）") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(shot.takes) { take in
                                            let isActive = shot.activeTake?.id == take.id
                                            let isPreviewing = (previewingTakeID ?? shot.activeTake?.id) == take.id
                                            Button {
                                                previewingTakeID = take.id
                                                loadTakePreview(take)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    HStack(spacing: 4) {
                                                        Text("Take \(take.takeNumber)")
                                                            .font(.caption.weight(.bold))
                                                        if isActive {
                                                            Text("当前采用")
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundStyle(.white)
                                                                .padding(.horizontal, 5)
                                                                .padding(.vertical, 2)
                                                                .background(Color.green, in: Capsule())
                                                        }
                                                    }
                                                    Text("\(take.engine.shortBadge) · \(Int(take.durationSeconds.rounded()))s")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                    Text(take.revisionNote)
                                                        .font(.system(size: 10))
                                                        .lineLimit(1)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(9)
                                                .frame(width: 142, alignment: .leading)
                                                .background(
                                                    isPreviewing ? Color.purple.opacity(0.14) : Color.secondary.opacity(0.08),
                                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .strokeBorder(isPreviewing ? Color.purple : Color.clear, lineWidth: 1.5)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }

                                if let chosenID = previewingTakeID ?? shot.activeTake?.id,
                                   let chosenTake = shot.takes.first(where: { $0.id == chosenID }) {
                                    if let takePlayer {
                                        VideoPlayer(player: takePlayer)
                                            .frame(height: 260)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    if shot.activeTake?.id != chosenTake.id {
                                        Button("时间线改用 Take \(chosenTake.takeNumber)（旧版回滚）") {
                                            dramaStore.switchActiveTake(shotID: shot.id, takeID: chosenTake.id)
                                        }
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.purple)
                                    }
                                }
                            }
                        }

                        Section("单镜修改指令") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Self.quickPresets, id: \.self) { preset in
                                        Button(preset) {
                                            reshootInstruction = preset
                                            if preset.contains("台词和声音不变") {
                                                keepDialogueAndVoice = true
                                            }
                                        }
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.purple)
                                    }
                                }
                            }

                            TextField("例如：换成近景，台词和声音不变", text: $reshootInstruction, axis: .vertical)
                                .lineLimit(2...4)

                            Toggle(isOn: $keepDialogueAndVoice) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("保持台词和声音不变")
                                        .font(.subheadline.weight(.semibold))
                                    Text("锁定「\(character?.name ?? "角色") · \(character?.voicePreset.displayName ?? "默认音色")」与原字幕，仅重生成画面")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.green)

                            if !keepDialogueAndVoice {
                                TextField("修改本镜台词与字幕", text: $editedDialogue, axis: .vertical)
                                    .lineLimit(2...3)
                            }
                        }

                        Section("本镜视频引擎与实时能力校验") {
                            Picker("视频引擎", selection: $selectedEngine) {
                                ForEach(WuMindDramaVideoEngine.allCases) { engine in
                                    let ready = dramaStore.isEngineConfigured(engine)
                                    Text("\(engine.displayName)\(ready ? "" : "（未配置）")").tag(engine)
                                }
                            }
                            .accessibilityIdentifier("ai.drama.reshoot.enginePicker")

                            // Immediate pre-submission capability check (duration, aspect ratio, reference image, channel)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Label("调用通道：\(channelDesc)", systemImage: isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(isConfigured ? .green : .orange)
                                    Spacer()
                                    Text("9:16 \(genPlan.aspectRatioSupported ? "支持" : "不支持")")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(genPlan.aspectRatioSupported ? .green : .red)
                                }

                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: genPlan.requiresUserConfirmation ? "scissors" : "clock.badge.checkmark")
                                        .foregroundStyle(genPlan.requiresUserConfirmation ? .orange : .green)
                                        .font(.caption)
                                    Text(genPlan.durationSummary)
                                        .font(.caption)
                                        .foregroundStyle(genPlan.requiresUserConfirmation ? .orange : .primary)
                                }

                                if let aspectWarning = genPlan.aspectRatioWarning {
                                    Label(aspectWarning, systemImage: "xmark.octagon.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                if let refWarning = genPlan.referenceImageWarning {
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                        Text(refWarning)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                } else if let char = character {
                                    Label(
                                        char.referenceImageBase64 != nil
                                            ? "已绑定「\(char.name)」角色参考图（当前引擎支持参考图锁脸）"
                                            : "未上传「\(char.name)」参考图（将按文字外观标签生成）",
                                        systemImage: char.referenceImageBase64 != nil ? "checkmark.circle.fill" : "person.crop.circle"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(char.referenceImageBase64 != nil ? .green : .secondary)
                                }
                            }
                            .padding(.vertical, 2)

                            if let crossWarning {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(crossWarning)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.vertical, 4)
                            }

                            if !isConfigured && chatStore.channel == .managed {
                                Text("内置通道暂无此引擎的可用模型，请联系管理员。")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else if !isConfigured {
                                Button("去配置「\(selectedEngine.shortBadge)」官方 API Key") {
                                    dismiss()
                                    showingAPIConfig = true
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                            }
                        }

                        Section {
                            Button {
                                if genPlan.requiresUserConfirmation {
                                    showingDurationConfirm = true
                                } else {
                                    submitCurrentShot(shot: shot)
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isWorking {
                                        ProgressView().tint(.white)
                                    } else {
                                        VStack(spacing: 2) {
                                            Text(shot.isRendered ? "仅重拍第 \(idx + 1) 镜（其余时间线不动）" : "生成第 \(idx + 1) 镜")
                                                .font(.subheadline.weight(.bold))
                                            Text(
                                                genPlan.needsTrimToTimeline
                                                    ? "生成 \(genPlan.generationDurationSeconds) 秒剪入 \(Int(shot.durationSeconds.rounded())) 秒 · 预计 ¥\(String(format: "%.2f", estShotCost)) · \(selectedEngine.shortBadge)"
                                                    : "本镜 \(genPlan.generationDurationSeconds) 秒 · 预计 ¥\(String(format: "%.2f", estShotCost)) · \(selectedEngine.shortBadge) · 不重跑其余 \(max(0, dramaStore.project.shots.count - 1)) 镜"
                                            )
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.88))
                                            .multilineTextAlignment(.center)
                                        }
                                    }
                                    Spacer()
                                }
                                .foregroundStyle(.white)
                                .padding(.vertical, 8)
                            }
                            .listRowBackground(
                                LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                            .disabled(isWorking || !isConfigured || !genPlan.canSubmit)
                            .accessibilityIdentifier("ai.drama.reshoot.submit")
                        }
                    }
                    .alert(
                        genPlan.confirmationTitle ?? "确认生成时长",
                        isPresented: $showingDurationConfirm
                    ) {
                        Button("取消", role: .cancel) {}
                        Button("确认按 \(genPlan.generationDurationSeconds) 秒生成（¥\(String(format: "%.2f", estShotCost))）") {
                            submitCurrentShot(shot: shot)
                        }
                    } message: {
                        Text(genPlan.confirmationMessage ?? genPlan.durationSummary)
                    }
                    .onAppear {
                        selectedEngine = shot.preferredEngine
                        editedDialogue = shot.dialogue
                        if let active = shot.activeTake {
                            previewingTakeID = active.id
                            loadTakePreview(active)
                        }
                    }
                    .onDisappear {
                        takePlayer?.pause()
                    }
                }
            }
            .navigationTitle("镜头版本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func submitCurrentShot(shot: WuMindDramaShot) {
        dramaStore.shootOrReshootSingleShot(
            shotID: shot.id,
            engine: selectedEngine,
            reshootInstruction: reshootInstruction,
            keepDialogueAndVoice: keepDialogueAndVoice,
            updatedDialogue: keepDialogueAndVoice ? nil : editedDialogue
        )
        dismiss()
    }

    private func loadTakePreview(_ take: WuMindShotTake) {
        takePlayer?.pause()
        if let url = dramaStore.mediaURL(for: take) {
            takePlayer = AVPlayer(url: url)
        } else {
            takePlayer = nil
        }
    }
}

// MARK: - Official Short-Drama Video API Credentials Sheet (Seedance / Kling / Grok / Sora / Veo)

@MainActor
struct WuMindShortDramaAPISheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dramaStore = WuMindShortDramaStore.shared

    @State private var arkKeyInput = Keychain.volcengineArkAPIKey ?? ""
    @State private var klingAKInput = Keychain.klingAccessKey ?? ""
    @State private var klingSKInput = Keychain.klingSecretKey ?? ""
    @State private var configuringProvider: AIProvider?
    @State private var savedBanner: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(.orange)
                        Text("使用火山方舟或可灵开放平台的 API 凭据。接口调用按所选平台计费。")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let savedBanner {
                    Section {
                        Label(savedBanner, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Section("火山方舟 · 即梦 Seedance 官方 API") {
                    SecureField("Ark API Key（火山方舟控制台获取）", text: $arkKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    DisclosureGroup("高级设置") {
                        TextField("模型或接入点 ID（如 doubao-seedance-1-0-pro-250528 / ep-...）", text: $dramaStore.arkModelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("自定义 HTTPS 地址（留空默认 ark.cn-beijing.volces.com）", text: $dramaStore.arkBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    HStack {
                        Button("保存方舟凭据") {
                            _ = Keychain.setVolcengineArkAPIKey(arkKeyInput)
                            savedBanner = arkKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "已清空火山方舟 API Key。"
                                : "已将火山方舟 Ark API Key 加密存入本机 Keychain。"
                            Haptics.success()
                        }
                        .font(.subheadline.weight(.bold))
                        Spacer()
                        if Keychain.volcengineArkAPIKey != nil {
                            Text("已配置").font(.caption.weight(.bold)).foregroundStyle(.green)
                        }
                    }
                }

                Section("可灵 AI 开放平台官方 API (HS256 JWT)") {
                    SecureField("AccessKey (AK)", text: $klingAKInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("SecretKey (SK)", text: $klingSKInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("可灵模型", selection: $dramaStore.klingModelName) {
                        Text("kling-v1-6（均衡图生/文生）").tag("kling-v1-6")
                        Text("kling-v2-master（大师电影感）").tag("kling-v2-master")
                        Text("kling-v2-1（高清运动）").tag("kling-v2-1")
                    }

                    Picker("画质档位", selection: $dramaStore.klingMode) {
                        Text("标准 std（成本更低）").tag("std")
                        Text("高品质 pro").tag("pro")
                    }

                    DisclosureGroup("高级设置") {
                        TextField("自定义 HTTPS 地址（留空默认 api.klingai.com）", text: $dramaStore.klingBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    HStack {
                        Button("保存可灵 AK/SK") {
                            _ = Keychain.setKlingAccessKey(klingAKInput)
                            _ = Keychain.setKlingSecretKey(klingSKInput)
                            savedBanner = (klingAKInput.isEmpty || klingSKInput.isEmpty)
                                ? "已清空可灵开放平台凭据。"
                                : "已将可灵 AK/SK 加密存入本机 Keychain（发请求时本地实时签发 HS256 JWT）。"
                            Haptics.success()
                        }
                        .font(.subheadline.weight(.bold))
                        Spacer()
                        if Keychain.klingAccessKey != nil && Keychain.klingSecretKey != nil {
                            Text("已配置").font(.caption.weight(.bold)).foregroundStyle(.green)
                        }
                    }
                }

                Section("已复用的国际视频引擎 Key") {
                    providerRow(title: "Grok Imagine Video (xAI)", provider: .grok)
                    providerRow(title: "OpenAI Sora 2", provider: .openAI)
                    providerRow(title: "Google Veo 3 (Gemini)", provider: .gemini)
                }
            }
            .appList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("短剧官方视频接口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $configuringProvider) { provider in
                ProviderKeyView(provider: provider) { _ in }
            }
        }
    }

    private func providerRow(title: String, provider: AIProvider) -> some View {
        let configured = Keychain.providerChatAPIKey(provider) != nil
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(configured ? "已配置本机 Key，可直接按镜头选用" : "未配置")
                    .font(.caption2)
                    .foregroundStyle(configured ? .green : .secondary)
            }
            Spacer()
            Button(configured ? "修改" : "去配置") {
                configuringProvider = provider
            }
            .font(.caption.weight(.bold))
        }
    }
}
