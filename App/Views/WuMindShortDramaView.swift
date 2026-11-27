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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                    title: "第 \(idx + 1) 镜 · \(dramaStore.activeShotProgress?.stage ?? "请稍候…")",
                    subtitle: "已用 \(Int(dramaStore.activeShotProgress?.elapsedSeconds ?? 0)) 秒",
                    percent: dramaStore.activeShotProgress?.percent
                )
            }

            if let mp4URL = dramaStore.exportedMP4URL {
                exportedMP4Card(url: mp4URL)
            }

            characterReferenceSection
            timelineSection
            multiTrackExportCard
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
        .onAppear {
            if roughCutPlayer == nil, let url = dramaStore.exportedMP4URL {
                roughCutPlayer = AVPlayer(url: url)
            }
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

    // MARK: - Timeline summary

    private var telemetryBar: some View {
        let project = dramaStore.project
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 170 : 132), spacing: 12, alignment: .leading)],
            alignment: .leading,
            spacing: 10
        ) {
            metricTile(title: "剪辑时长", value: String(format: "%.1f 秒", totalTrimmedDuration))
            metricTile(title: "已生成", value: "\(renderedCount)/\(project.shots.count) 镜")
            metricTile(title: "单镜重拍", value: "\(project.singleShotReshoots) 次")
            metricTile(title: "预计费用", value: String(format: "¥%.2f", project.estimatedTotalCostYuan))
        }
        .padding(12)
        .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Storyboard premise

    private var premiseComposerCard: some View {
        AppSectionCard {
            HStack {
                Text("故事梗概")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if premiseFocused {
                    Button("收起键盘") { premiseFocused = false }
                        .font(.footnote)
                        .frame(minHeight: 44)
                }
            }

            TextField(
                "写下主角、冲突或结局…",
                text: $premiseInput,
                axis: .vertical
            )
            .lineLimit(2...6)
            .font(.body)
            .focused($premiseFocused)
            .padding(10)
            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("故事梗概")
            .accessibilityIdentifier("ai.video.prompt")

            let parameterLayout = dynamicTypeSize >= .xxLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: 12))
            parameterLayout {
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
            }

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
                HStack {
                    if dramaStore.isGeneratingStoryboard {
                        ProgressView().controlSize(.small)
                    }
                    Text("生成分镜").font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Palette.accent)
            .disabled(dramaStore.isGeneratingStoryboard)
            .accessibilityIdentifier("ai.video.generate")
        }
    }

    // MARK: - Character references

    private var characterReferenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 12))
            headerLayout {
                Text("角色素材")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if chatStore.channel == .ownAPI {
                    Button {
                        showingAPIConfig = true
                    } label: {
                        let configuredCount = WuMindDramaVideoEngine.allCases.filter { dramaStore.isEngineConfigured($0) }.count
                        Label("官方接口 (\(configuredCount)/\(WuMindDramaVideoEngine.allCases.count))", systemImage: "key.fill")
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("ai.drama.apiConfig")
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { characterCards }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { characterCards }
                }
            }

            if !dramaStore.project.characters.isEmpty {
                Text("镜头沿用角色参考图与音色，切换视频引擎可能改变人物外观。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var characterCards: some View {
        ForEach(dramaStore.project.characters) { character in
            characterCard(character)
        }
    }

    private func characterCard(_ char: WuMindDramaCharacter) -> some View {
        HStack(spacing: 10) {
            CharacterPortraitPickerButton(referenceImageBase64: char.referenceImageBase64) { b64 in
                dramaStore.updateCharacterReferenceImage(characterID: char.id, jpegBase64: b64)
                Haptics.success()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(char.name).font(.subheadline.weight(.semibold))
                Text(char.roleSummary).font(.caption).foregroundStyle(.secondary)

                Menu {
                    ForEach(WuMindDramaVoicePreset.allCases) { preset in
                        Button {
                            dramaStore.updateCharacterVoice(characterID: char.id, voice: preset)
                        } label: {
                            Label(preset.displayName, systemImage: preset == char.voicePreset ? "checkmark" : "waveform")
                        }
                    }
                } label: {
                    Label(char.voicePreset.displayName, systemImage: "waveform")
                        .font(.footnote.weight(.medium))
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("为\(char.name)选择音色")
                .accessibilityValue(char.voicePreset.displayName)
                .tint(.primary)
            }
        }
        .padding(10)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    // MARK: - Tracks and export

    private var multiTrackExportCard: some View {
        let count = dramaStore.project.shots.count
        let exportKind = WuMindShortDramaEngine.exportKind(for: dramaStore.project)
        return AppSectionCard(title: "导出与发布") {
            Toggle("独立字幕轨", isOn: Binding(
                get: { dramaStore.project.globalSubtitlesEnabled },
                set: { dramaStore.setGlobalSubtitles($0) }
            ))
            Toggle("独立配音轨", isOn: Binding(
                get: { dramaStore.project.globalVoiceoverEnabled },
                set: { dramaStore.setGlobalVoiceover($0) }
            ))
            Divider()
            if count == 0 {
                Text("添加分镜后即可导出 9:16 竖屏视频。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if renderedCount < count {
                Text("已生成 \(renderedCount)/\(count) 镜，其余镜头在粗剪中以动态分镜显示。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                dramaStore.exportRoughCutMP4()
            } label: {
                HStack {
                    if dramaStore.isExportingMP4 { ProgressView().controlSize(.small) }
                    Label(dramaStore.isExportingMP4 ? dramaStore.exportStatus : exportKind.buttonTitle, systemImage: "film.stack")
                }
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.bordered)
            .disabled(dramaStore.isExportingMP4)
            .accessibilityIdentifier("ai.drama.exportMP4")

            Button {
                dramaStore.refreshMultiPlatformVariants(forceReset: false)
                showingMultiPlatformPublish = true
                Haptics.tap()
            } label: {
                HStack {
                    Label("分平台发布", systemImage: "paperplane")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ai.drama.multiPublish")
        }
        .tint(DS.Palette.accent)
    }

    private func exportedMP4Card(url: URL) -> some View {
        AppSectionCard(title: "已导出竖屏 MP4") {
            if let roughCutPlayer {
                VideoPlayer(player: roughCutPlayer)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
            }
            ShareLink(item: url) {
                Label("分享 MP4", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Shot timeline

    private var timelineSection: some View {
        let shots = dramaStore.project.shots
        return VStack(alignment: .leading, spacing: 10) {
            Text(dramaStore.project.title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Label("分镜时间线 · 9:16", systemImage: "film")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            telemetryBar

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
            Text("第 \(index + 1) 镜 · \(shot.title)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            let takeStatus = shot.activeTake.map { "版本 \($0.takeNumber)/\(shot.takes.count)" } ?? "分镜待拍"
            Text("\(shot.cameraFraming.label) · \(shot.preferredEngine.shortBadge) · \(String(format: "%.1f", shot.trimmedDuration)) 秒 · \(takeStatus)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(shot.visualPrompt).font(.subheadline)
            if !shot.dialogue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(character?.name ?? "台词")「\(shot.dialogue)」")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()
            let toolLayout = dynamicTypeSize >= .xxLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 6))
            toolLayout {
                HStack(spacing: 0) {
                    Button {
                        dramaStore.moveShot(fromIndex: index, toIndex: index - 1)
                    } label: {
                        Image(systemName: "arrow.up").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("上移第 \(index + 1) 镜")
                    .disabled(index == 0)

                    Button {
                        dramaStore.moveShot(fromIndex: index, toIndex: index + 1)
                    } label: {
                        Image(systemName: "arrow.down").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("下移第 \(index + 1) 镜")
                    .disabled(index == total - 1)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedTrimShotID = isTrimExpanded ? nil : shot.id
                    }
                } label: {
                    Label("裁剪", systemImage: "scissors")
                        .frame(minHeight: 44)
                }
                .accessibilityValue(isTrimExpanded ? "已展开" : "已收起")

                if dynamicTypeSize < .xxLarge { Spacer(minLength: 0) }
                Button {
                    inspectingShotID = shot.id
                } label: {
                    HStack(spacing: 5) {
                        if isRenderingThisShot { ProgressView().controlSize(.small) }
                        Label(shot.isRendered ? "重拍本镜" : "生成本镜", systemImage: "video")
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("ai.drama.shot.\(index + 1).reshoot")
            }
            .font(.footnote.weight(.semibold))
            .tint(DS.Palette.accent)

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
            let trimLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 12))
            trimLayout {
                Text("入点 \(String(format: "%.1fs", shot.trimStartSeconds))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Slider(
                    value: Binding(
                        get: { shot.trimStartSeconds },
                        set: { dramaStore.updateTrim(shotID: shot.id, trimStart: $0, trimEnd: shot.trimEndSeconds) }
                    ),
                    in: 0...max(0.5, shot.durationSeconds - 1.0),
                    step: 0.2
                )
                .accessibilityLabel("镜头入点")
                .tint(DS.Palette.accent)
            }
            trimLayout {
                Text("出点 \(String(format: "%.1fs", shot.trimEndSeconds))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Slider(
                    value: Binding(
                        get: { shot.trimEndSeconds },
                        set: { dramaStore.updateTrim(shotID: shot.id, trimStart: shot.trimStartSeconds, trimEnd: $0) }
                    ),
                    in: min(shot.durationSeconds, shot.trimStartSeconds + 1.0)...shot.durationSeconds,
                    step: 0.2
                )
                .accessibilityLabel("镜头出点")
                .tint(DS.Palette.accent)
            }

            trimLayout {
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
        Label(text, systemImage: icon)
            .font(.footnote.weight(.medium))
            .frame(minHeight: 44)
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
                        .fill(DS.Palette.surfaceSunken)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "person.crop.rectangle.badge.plus")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(referenceImageBase64 == nil ? "添加角色参考图" : "更换角色参考图")
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

    private enum EditingField: Hashable { case instruction, dialogue }
    @FocusState private var editingField: EditingField?
    @State private var reshootInstruction = ""
    @State private var keepDialogueAndVoice = true
    @State private var editedDialogue = ""
    @State private var selectedEngine: WuMindDramaVideoEngine = .seedance
    @State private var previewingTakeID: UUID?
    @State private var takePlayer: AVPlayer?
    @State private var showingDurationConfirm = false
    @ScaledMetric(relativeTo: .footnote) private var takeCardWidth: CGFloat = 154

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
                        Section("第 \(idx + 1) 镜") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(shot.title).font(.headline)
                                Text("\(shot.cameraFraming.label) · \(String(format: "%.1f", shot.durationSeconds)) 秒")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(shot.visualPrompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !shot.takes.isEmpty {
                            Section("历史版本") {
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
                                                    Text("版本 \(take.takeNumber)")
                                                        .font(.subheadline.weight(.semibold))
                                                    if isActive {
                                                        Label("当前采用", systemImage: "checkmark")
                                                            .font(.footnote.weight(.medium))
                                                    }
                                                    Text("\(take.engine.shortBadge) · \(Int(take.durationSeconds.rounded())) 秒")
                                                        .font(.footnote)
                                                        .foregroundStyle(.secondary)
                                                    Text(take.revisionNote)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(9)
                                                .frame(width: min(takeCardWidth, 240), alignment: .leading)
                                                .background(
                                                    isPreviewing ? DS.Palette.accent.opacity(0.12) : DS.Palette.surfaceSunken,
                                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .strokeBorder(isPreviewing ? DS.Palette.accent : Color.clear, lineWidth: 1.5)
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
                                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                                            .frame(maxWidth: 280)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    if shot.activeTake?.id != chosenTake.id {
                                        Button("时间线改用版本 \(chosenTake.takeNumber)") {
                                            dramaStore.switchActiveTake(shotID: shot.id, takeID: chosenTake.id)
                                        }
                                        .font(.caption.weight(.bold))
                                        .tint(DS.Palette.accent)
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
                                        .font(.footnote.weight(.medium))
                                        .buttonStyle(.bordered)
                                        .frame(minHeight: 44)
                                        .tint(DS.Palette.accent)
                                    }
                                }
                            }

                            TextField("例如：换成近景，台词和声音不变", text: $reshootInstruction, axis: .vertical)
                                .focused($editingField, equals: .instruction)
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
                                    .focused($editingField, equals: .dialogue)
                                    .lineLimit(2...3)
                            }
                        }

                        Section("视频引擎") {
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
                                        ProgressView()
                                    } else {
                                        VStack(spacing: 2) {
                                            Text(shot.isRendered ? "重拍第 \(idx + 1) 镜" : "生成第 \(idx + 1) 镜")
                                                .font(.subheadline.weight(.bold))
                                            Text(
                                                genPlan.needsTrimToTimeline
                                                    ? "生成 \(genPlan.generationDurationSeconds) 秒剪入 \(Int(shot.durationSeconds.rounded())) 秒 · 预计 ¥\(String(format: "%.2f", estShotCost)) · \(selectedEngine.shortBadge)"
                                                    : "本镜 \(genPlan.generationDurationSeconds) 秒 · 预计 ¥\(String(format: "%.2f", estShotCost)) · \(selectedEngine.shortBadge)"
                                            )
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                        }
                                    }
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                            }
                            .tint(DS.Palette.accent)
                            .disabled(isWorking || !isConfigured || !genPlan.canSubmit)
                            .accessibilityIdentifier("ai.drama.reshoot.submit")
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { editingField = nil }
                }
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
