import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import UIKit

/// Persistent @MainActor workflow store for WUMIND Short-Drama Studio v1 (短剧工坊).
/// Handles storyboard generation, selective single-shot generation/reshoot via official APIs
/// (Volcengine Ark Seedance · Kling Open Platform · Grok · Sora 2 · Veo 3),
/// per-character reference portraits & voices, multi-track timeline edits, and real 9:16 MP4 export.
@MainActor
final class WuMindShortDramaStore: ObservableObject {
    static let shared = WuMindShortDramaStore()

    private enum DefaultsKey {
        static let arkModelID = "wumind.drama.ark.modelID"
        static let arkBaseURL = "wumind.drama.ark.baseURL"
        static let klingModelName = "wumind.drama.kling.modelName"
        static let klingMode = "wumind.drama.kling.mode"
        static let klingBaseURL = "wumind.drama.kling.baseURL"
        static let douyinAccountName = "wumind.drama.douyin.accountName"
    }

    @Published var project: WuMindShortDramaProject
    @Published var publishVariants: [WuMindPlatformPublishVariant]
    @Published var isGeneratingStoryboard = false
    @Published var storyboardStatus = ""
    @Published var activeShotGenerationID: UUID?
    @Published var activeShotProgress: AIVideoTool.ProgressUpdate?
    @Published var isExportingMP4 = false
    @Published var exportStatus = ""
    @Published var exportedMP4URL: URL?
    @Published var isPolishingPlatformCopy = false
    @Published var isRunningPublishBatch = false
    @Published var publishBatchStatus = ""
    @Published var publishError: String?
    @Published var publishNotice: String?
    @Published var lastError: String?
    @Published var lastNotice: String?

    @Published var arkModelID: String {
        didSet { UserDefaults.standard.set(arkModelID, forKey: DefaultsKey.arkModelID) }
    }
    @Published var arkBaseURL: String {
        didSet { UserDefaults.standard.set(arkBaseURL, forKey: DefaultsKey.arkBaseURL) }
    }
    @Published var klingModelName: String {
        didSet { UserDefaults.standard.set(klingModelName, forKey: DefaultsKey.klingModelName) }
    }
    @Published var klingMode: String {
        didSet { UserDefaults.standard.set(klingMode, forKey: DefaultsKey.klingMode) }
    }
    @Published var klingBaseURL: String {
        didSet { UserDefaults.standard.set(klingBaseURL, forKey: DefaultsKey.klingBaseURL) }
    }
    @Published var douyinAccountName: String {
        didSet { UserDefaults.standard.set(douyinAccountName, forKey: DefaultsKey.douyinAccountName) }
    }

    var isDouyinAuthorized: Bool {
        Keychain.douyinOpenID != nil && Keychain.douyinAccessToken != nil
    }

    private var activeTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {
        let savedArkModel = UserDefaults.standard.string(forKey: DefaultsKey.arkModelID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.arkModelID = (savedArkModel?.isEmpty == false) ? savedArkModel! : VolcengineArkSeedanceClient.defaultModelID
        self.arkBaseURL = UserDefaults.standard.string(forKey: DefaultsKey.arkBaseURL) ?? ""

        let savedKlingModel = UserDefaults.standard.string(forKey: DefaultsKey.klingModelName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.klingModelName = (savedKlingModel?.isEmpty == false) ? savedKlingModel! : KlingOfficialVideoClient.defaultModelName
        let savedMode = UserDefaults.standard.string(forKey: DefaultsKey.klingMode)
        self.klingMode = (savedMode == "pro") ? "pro" : "std"
        self.klingBaseURL = UserDefaults.standard.string(forKey: DefaultsKey.klingBaseURL) ?? ""
        let savedDouyinName = UserDefaults.standard.string(forKey: DefaultsKey.douyinAccountName) ?? ""
        self.douyinAccountName = savedDouyinName

        let initialProject: WuMindShortDramaProject
        if let restored = Self.loadSavedProject() {
            initialProject = restored
        } else {
            initialProject = WuMindShortDramaEngine.sampleVerticalDrama(defaultEngine: Self.initialPreferredEngine())
        }
        self.project = initialProject

        let authorized = Keychain.douyinOpenID != nil && Keychain.douyinAccessToken != nil
        if let savedVariants = Self.loadSavedPublishVariants(projectID: initialProject.id),
           savedVariants.count == WuMindPublishPlatform.allCases.count {
            self.publishVariants = savedVariants
        } else {
            self.publishVariants = WuMindMultiPlatformPublishEngine.buildVariants(
                from: initialProject,
                douyinAccountName: savedDouyinName,
                douyinAuthorized: authorized
            )
        }
    }

    private static func initialPreferredEngine() -> WuMindDramaVideoEngine {
        if Keychain.volcengineArkAPIKey != nil { return .seedance }
        if Keychain.klingAccessKey != nil && Keychain.klingSecretKey != nil { return .kling }
        if Keychain.providerChatAPIKey(.grok) != nil { return .grok }
        if Keychain.providerChatAPIKey(.openAI) != nil { return .sora2 }
        if Keychain.providerChatAPIKey(.gemini) != nil { return .veo3 }
        return .seedance
    }

    func isEngineConfigured(_ engine: WuMindDramaVideoEngine) -> Bool {
        switch engine {
        case .seedance:
            return Keychain.volcengineArkAPIKey != nil
        case .kling:
            return Keychain.klingAccessKey != nil && Keychain.klingSecretKey != nil
        case .grok:
            return Keychain.providerChatAPIKey(.grok) != nil
        case .sora2:
            return Keychain.providerChatAPIKey(.openAI) != nil
        case .veo3:
            return Keychain.providerChatAPIKey(.gemini) != nil
        }
    }

    func preferredConfiguredEngine() -> WuMindDramaVideoEngine {
        for engine in WuMindDramaVideoEngine.allCases where isEngineConfigured(engine) {
            return engine
        }
        return .seedance
    }

    func mediaURL(for take: WuMindShotTake) -> URL? {
        let url = Self.projectMediaDir(projectID: project.id, create: false)
            .appendingPathComponent(take.videoFilename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func loadSampleDrama() {
        cancelActiveTask()
        exportedMP4URL = nil
        lastError = nil
        project = WuMindShortDramaEngine.sampleVerticalDrama(defaultEngine: preferredConfiguredEngine())
        lastNotice = "已载入 6 镜 36 秒竖屏悬疑样板，可直接试剪、配参考图或单镜重拍。"
        persistProject()
    }

    func generateStoryboard(
        premise: String,
        genre: WuMindDramaGenre,
        targetDurationSeconds: Int,
        using chatStore: WuMindStore
    ) {
        let cleanPremise = premise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPremise.isEmpty else {
            lastError = "请先输入一句话短剧创意，例如：暴雨夜值班室收到明天的告警短信。"
            return
        }

        cancelActiveTask()
        lastError = nil
        lastNotice = nil
        exportedMP4URL = nil
        isGeneratingStoryboard = true
        storyboardStatus = "正在用 WUMIND 编排 \(targetDurationSeconds) 秒 9:16 竖屏分镜与角色表…"
        beginBackgroundProtection(name: "WuMindShortDramaStoryboard")

        let preferredEngine = preferredConfiguredEngine()
        activeTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isGeneratingStoryboard = false
                    self?.storyboardStatus = ""
                    self?.endBackgroundProtection()
                }
            }
            do {
                let sys = WuMindShortDramaEngine.storyboardSystemPrompt(
                    premise: cleanPremise,
                    genre: genre,
                    targetDurationSeconds: targetDurationSeconds
                )
                let userMsg = AIProviderMessage(
                    role: .user,
                    text: "短剧创意：\(cleanPremise)\n目标时长：\(targetDurationSeconds) 秒\n题材风格：\(genre.rawValue)"
                )
                let result = try await chatStore.runStatelessChat(
                    messages: [userMsg],
                    systemPrompt: sys,
                    deepThinking: false,
                    onAnswerDelta: { [weak self] partial in
                        self?.storyboardStatus = "正在生成分镜与台词（已输出 \(partial.count) 字）…"
                    }
                )
                try Task.checkCancellation()
                guard let self else { return }
                let parsed = WuMindShortDramaEngine.parseStoryboard(
                    from: result.answer,
                    premise: cleanPremise,
                    genre: genre,
                    targetDurationSeconds: targetDurationSeconds,
                    defaultEngine: preferredEngine
                )
                self.project = parsed
                self.persistProject()
                self.lastNotice = "已生成《\(parsed.title)》共 \(parsed.shots.count) 镜分镜，可点任意镜头单独实拍或重拍。"
                Haptics.success()
            } catch is CancellationError {
                // Clean cancellation
            } catch {
                guard let self else { return }
                // Even if chat model isn't configured yet, let user keep working with structured draft cleanly
                let fallback = WuMindShortDramaEngine.parseStoryboard(
                    from: "",
                    premise: cleanPremise,
                    genre: genre,
                    targetDurationSeconds: targetDurationSeconds,
                    defaultEngine: preferredEngine
                )
                self.project = fallback
                self.persistProject()
                let errText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.lastError = "智能分镜调用未成功（\(errText)），已为你生成可编辑的 \(fallback.shots.count) 镜结构草稿。"
                Haptics.warning()
            }
        }
    }

    /// Generates or selectively reshoots ONLY the specified shot while keeping all previous takes & the rest of the timeline untouched.
    func shootOrReshootSingleShot(
        shotID: UUID,
        engine: WuMindDramaVideoEngine,
        reshootInstruction: String,
        keepDialogueAndVoice: Bool,
        updatedDialogue: String?
    ) {
        guard let shot = project.shots.first(where: { $0.id == shotID }) else { return }
        guard isEngineConfigured(engine) else {
            lastError = "尚未配置「\(engine.displayName)」官方接口凭据。请点击右上角钥匙图标配置官方 API Key（注意：消费端会员不可作为 API 权限）。"
            return
        }

        cancelActiveTask()
        lastError = nil
        lastNotice = nil
        activeShotGenerationID = shotID
        activeShotProgress = .init(stage: "正在准备单镜任务（其余时间线保持不变）…", percent: 5, elapsedSeconds: 0)
        beginBackgroundProtection(name: "WuMindShortDramaSingleShot")

        let currentProject = project
        let character = currentProject.character(for: shot)
        let cleanInstruction = reshootInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let isReshoot = !shot.takes.isEmpty || !cleanInstruction.isEmpty

        let plan: WuMindShortDramaEngine.ReshootPlan
        if isReshoot {
            plan = WuMindShortDramaEngine.composeReshootPrompt(
                shot: shot,
                instruction: cleanInstruction,
                keepDialogueAndVoice: keepDialogueAndVoice,
                character: character,
                project: currentProject
            )
        } else {
            let prompt = WuMindShortDramaEngine.composeGenerationPrompt(
                for: shot,
                character: character,
                project: currentProject
            )
            plan = WuMindShortDramaEngine.ReshootPlan(
                updatedFraming: shot.cameraFraming,
                updatedVisualPrompt: shot.visualPrompt,
                finalGenerationPrompt: prompt,
                preservedDialogue: shot.dialogue,
                preservedVoiceLabel: character?.voicePreset.displayName
            )
        }

        let referenceImage = character?.referenceImageBase64
        let durationInt = max(5, min(10, Int(shot.durationSeconds.rounded())))
        let nextTakeNumber = (shot.takes.map(\.takeNumber).max() ?? 0) + 1
        let projectID = currentProject.id
        let arkKey = Keychain.volcengineArkAPIKey ?? ""
        let arkModel = arkModelID
        let arkURL = arkBaseURL.isEmpty ? nil : arkBaseURL
        let klingAK = Keychain.klingAccessKey ?? ""
        let klingSK = Keychain.klingSecretKey ?? ""
        let klingModel = klingModelName
        let klingGenMode = klingMode
        let klingURL = klingBaseURL.isEmpty ? nil : klingBaseURL
        let grokKey = Keychain.providerChatAPIKey(.grok) ?? ""
        let grokBase = AIProviderEndpoints.baseURL(for: .grok)
        let openAIKey = Keychain.providerChatAPIKey(.openAI) ?? ""
        let openAIBase = AIProviderEndpoints.baseURL(for: .openAI)
        let geminiKey = Keychain.providerChatAPIKey(.gemini) ?? ""
        let geminiBase = AIProviderEndpoints.baseURL(for: .gemini)

        activeTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.activeShotGenerationID = nil
                    self?.activeShotProgress = nil
                    self?.endBackgroundProtection()
                }
            }
            do {
                let mp4Data: Data
                let resolvedModelID: String
                switch engine {
                case .seedance:
                    resolvedModelID = arkModel
                    mp4Data = try await VolcengineArkSeedanceClient().generate(
                        prompt: plan.finalGenerationPrompt,
                        aspectRatio: .portrait9x16,
                        durationSeconds: durationInt,
                        resolution: .hd720,
                        referenceImageBase64: referenceImage,
                        config: .init(apiKey: arkKey, modelID: arkModel, baseURL: arkURL)
                    ) { [weak self] update in
                        let store = self
                        await MainActor.run {
                            store?.activeShotProgress = update
                        }
                    }

                case .kling:
                    resolvedModelID = klingModel
                    mp4Data = try await KlingOfficialVideoClient().generate(
                        prompt: plan.finalGenerationPrompt,
                        aspectRatio: .portrait9x16,
                        durationSeconds: durationInt,
                        referenceImageBase64: referenceImage,
                        config: .init(
                            accessKey: klingAK,
                            secretKey: klingSK,
                            modelName: klingModel,
                            mode: klingGenMode,
                            baseURL: klingURL
                        )
                    ) { [weak self] update in
                        let store = self
                        await MainActor.run {
                            store?.activeShotProgress = update
                        }
                    }

                case .grok:
                    guard let model = AIVideoTool.models.first(where: { $0.provider == .grok }) else {
                        throw MultiProviderAIError.unsupportedModel
                    }
                    resolvedModelID = model.id
                    mp4Data = try await AIVideoTool().generate(
                        model: model,
                        apiKey: grokKey,
                        prompt: plan.finalGenerationPrompt,
                        options: .init(aspectRatio: .portrait9x16, durationSeconds: durationInt, resolution: .hd720, customBaseURL: grokBase)
                    ) { [weak self] update in
                        let store = self
                        await MainActor.run {
                            store?.activeShotProgress = update
                        }
                    }

                case .sora2:
                    guard let model = AIVideoTool.models.first(where: { $0.id == "sora-2" }) else {
                        throw MultiProviderAIError.unsupportedModel
                    }
                    resolvedModelID = model.id
                    mp4Data = try await AIVideoTool().generate(
                        model: model,
                        apiKey: openAIKey,
                        prompt: plan.finalGenerationPrompt,
                        options: .init(aspectRatio: .portrait9x16, durationSeconds: durationInt, resolution: .hd720, customBaseURL: openAIBase)
                    ) { [weak self] update in
                        let store = self
                        await MainActor.run {
                            store?.activeShotProgress = update
                        }
                    }

                case .veo3:
                    guard let model = AIVideoTool.models.first(where: { $0.id == "veo-3.0-fast-generate-001" }) else {
                        throw MultiProviderAIError.unsupportedModel
                    }
                    resolvedModelID = model.id
                    mp4Data = try await AIVideoTool().generate(
                        model: model,
                        apiKey: geminiKey,
                        prompt: plan.finalGenerationPrompt,
                        options: .init(aspectRatio: .portrait9x16, durationSeconds: durationInt, resolution: .hd720, customBaseURL: geminiBase)
                    ) { [weak self] update in
                        let store = self
                        await MainActor.run {
                            store?.activeShotProgress = update
                        }
                    }
                }

                try Task.checkCancellation()
                let filename = "shot_\(shotID.uuidString.prefix(8))_take\(nextTakeNumber).mp4"
                let dir = Self.projectMediaDir(projectID: projectID, create: true)
                let fileURL = dir.appendingPathComponent(filename)
                try mp4Data.write(to: fileURL, options: [.atomic, .completeFileProtection])

                let cost = ((engine.estimatedCostPer5SecYuan * max(1.0, Double(durationInt) / 5.0)) * 100).rounded() / 100
                let take = WuMindShotTake(
                    takeNumber: nextTakeNumber,
                    engine: engine,
                    modelID: resolvedModelID,
                    promptUsed: plan.finalGenerationPrompt,
                    revisionNote: cleanInstruction.isEmpty ? "首版实拍" : cleanInstruction,
                    videoFilename: filename,
                    durationSeconds: Double(durationInt),
                    estimatedCostYuan: cost,
                    usedReferenceImage: engine.supportsReferenceImage && (referenceImage?.isEmpty == false)
                )

                guard let self else { return }
                let beforeSnapshot = self.project
                self.project = WuMindShortDramaEngine.applySingleShotTake(
                    project: self.project,
                    shotID: shotID,
                    take: take,
                    updatedFraming: plan.updatedFraming,
                    updatedVisualPrompt: plan.updatedVisualPrompt,
                    updatedDialogue: updatedDialogue,
                    keepDialogueAndVoice: keepDialogueAndVoice
                )
                let audit = WuMindProjectRevisionEngine.auditShortDramaSingleShotReshoot(
                    before: beforeSnapshot,
                    after: self.project,
                    targetShotID: shotID
                )
                WuMindAgentCoordinator.shared.upsertTaskRun(audit.taskRun)
                self.exportedMP4URL = nil
                self.persistProject()
                self.lastNotice = "已完成本镜 Take \(nextTakeNumber)（\(engine.shortBadge)），旧版已保留用于对比，其余时间线未改动。"
                Haptics.success()
            } catch is CancellationError {
                // Clean cancellation
            } catch {
                guard let self else { return }
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.warning()
            }
        }
    }

    func switchActiveTake(shotID: UUID, takeID: UUID) {
        project = WuMindShortDramaEngine.switchActiveTake(project: project, shotID: shotID, takeID: takeID)
        exportedMP4URL = nil
        persistProject()
        Haptics.tap()
    }

    func moveShot(fromIndex: Int, toIndex: Int) {
        project = WuMindShortDramaEngine.moveShot(project: project, fromIndex: fromIndex, toIndex: toIndex)
        exportedMP4URL = nil
        persistProject()
        Haptics.tap()
    }

    func updateTrim(shotID: UUID, trimStart: Double, trimEnd: Double) {
        project = WuMindShortDramaEngine.updateTrim(project: project, shotID: shotID, trimStart: trimStart, trimEnd: trimEnd)
        exportedMP4URL = nil
        persistProject()
    }

    func updateShot(_ updated: WuMindDramaShot) {
        guard let idx = project.shots.firstIndex(where: { $0.id == updated.id }) else { return }
        project.shots[idx] = updated
        project.updatedAt = Date()
        exportedMP4URL = nil
        persistProject()
    }

    func updateCharacterVoice(characterID: UUID, voice: WuMindDramaVoicePreset) {
        guard let idx = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        project.characters[idx].voicePreset = voice
        project.updatedAt = Date()
        exportedMP4URL = nil
        persistProject()
    }

    func updateCharacterReferenceImage(characterID: UUID, jpegBase64: String?) {
        guard let idx = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        project.characters[idx].referenceImageBase64 = jpegBase64
        project.updatedAt = Date()
        persistProject()
    }

    func setGlobalSubtitles(_ enabled: Bool) {
        project.globalSubtitlesEnabled = enabled
        exportedMP4URL = nil
        persistProject()
    }

    func setGlobalVoiceover(_ enabled: Bool) {
        project.globalVoiceoverEnabled = enabled
        exportedMP4URL = nil
        persistProject()
    }

    /// Exports a real playable 9:16 MP4 combining rendered takes, storyboard animatic placeholders for unrendered shots,
    /// independent voiceover track, and burned-in vertical Chinese subtitles.
    func exportRoughCutMP4() {
        guard !isExportingMP4 else { return }
        cancelActiveTask()
        lastError = nil
        lastNotice = nil
        isExportingMP4 = true
        exportStatus = "正在拼接时间线、独立配音轨与竖屏字幕轨…"
        beginBackgroundProtection(name: "WuMindShortDramaExportMP4")

        let snapshot = project
        let mediaDir = Self.projectMediaDir(projectID: snapshot.id, create: true)

        activeTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isExportingMP4 = false
                    self?.exportStatus = ""
                    self?.endBackgroundProtection()
                }
            }
            do {
                let outputURL = try await WuMindShortDramaComposer.exportVerticalMP4(
                    project: snapshot,
                    mediaDirectory: mediaDir
                ) { [weak self] stage in
                    let store = self
                    await MainActor.run {
                        store?.exportStatus = stage
                    }
                }
                try Task.checkCancellation()
                guard let self else { return }
                self.exportedMP4URL = outputURL
                let rendered = WuMindShortDramaEngine.renderedShotCount(for: snapshot)
                let total = snapshot.shots.count
                if rendered == total {
                    self.lastNotice = "9:16 短剧成片 MP4 已导出，支持直接预览与一键发微信。"
                } else {
                    self.lastNotice = "9:16 粗剪 MP4 已导出（含 \(rendered)/\(total) 镜实拍 + 其余镜动态分镜占位、配音与字幕轨），可直接发微信试看节奏。"
                }
                Haptics.success()
            } catch is CancellationError {
                // Clean cancellation
            } catch {
                guard let self else { return }
                self.lastError = "导出 MP4 失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                Haptics.warning()
            }
        }
    }

    func cancelActiveTask() {
        activeTask?.cancel()
        activeTask = nil
        isGeneratingStoryboard = false
        activeShotGenerationID = nil
        activeShotProgress = nil
        isExportingMP4 = false
        endBackgroundProtection()
    }

    // MARK: - Persistence & Background Protection

    private func persistProject() {
        guard let url = Self.projectJSONURL(create: true),
              let data = try? JSONEncoder().encode(project) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func loadSavedProject() -> WuMindShortDramaProject? {
        guard let url = projectJSONURL(create: false),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WuMindShortDramaProject.self, from: data),
              !decoded.shots.isEmpty else {
            return nil
        }
        return decoded
    }

    private static func rootDir(create: Bool) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("WuMindShortDrama", isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func projectJSONURL(create: Bool) -> URL? {
        rootDir(create: create).appendingPathComponent("current_project.json")
    }

    private static func projectMediaDir(projectID: UUID, create: Bool) -> URL {
        let dir = rootDir(create: create)
            .appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Multi-Platform Adaptation & Compliant Publishing

    func refreshMultiPlatformVariants(forceReset: Bool = false) {
        let fresh = WuMindMultiPlatformPublishEngine.buildVariants(
            from: project,
            douyinAccountName: douyinAccountName,
            douyinAuthorized: isDouyinAuthorized
        )
        if forceReset || publishVariants.count != WuMindPublishPlatform.allCases.count {
            publishVariants = fresh
        } else {
            let existingByPlatform = Dictionary(uniqueKeysWithValues: publishVariants.map { ($0.platform, $0) })
            publishVariants = fresh.map { built in
                guard let old = existingByPlatform[built.platform] else { return built }
                var merged = built
                merged.isSelected = old.isSelected
                merged.title = old.title
                merged.caption = old.caption
                merged.coverHeadline = old.coverHeadline
                merged.coverSubheadline = old.coverSubheadline
                merged.hashtags = old.hashtags
                merged.pinnedCommentSuggestion = old.pinnedCommentSuggestion
                merged.aiDisclosure = old.aiDisclosure
                merged.status = old.status
                merged.exportedMP4Filename = old.exportedMP4Filename
                merged.exportedCoverPNGFilename = old.exportedCoverPNGFilename
                return merged
            }
        }
        persistPublishVariants()
    }

    func updatePublishVariant(_ updated: WuMindPlatformPublishVariant) {
        guard let idx = publishVariants.firstIndex(where: { $0.platform == updated.platform }) else { return }
        publishVariants[idx] = updated
        persistPublishVariants()
    }

    func markVariantManuallyPublished(platform: WuMindPublishPlatform) {
        guard let idx = publishVariants.firstIndex(where: { $0.platform == platform }) else { return }
        publishVariants[idx] = WuMindMultiPlatformPublishEngine.markManuallyPublished(variant: publishVariants[idx])
        persistPublishVariants()
        Haptics.success()
    }

    func packageFileURL(filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        let url = Self.publishPackageDir(projectID: project.id, create: false)
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func polishMultiPlatformCopy(using chatStore: WuMindStore) {
        guard !isPolishingPlatformCopy else { return }
        publishError = nil
        publishNotice = nil
        isPolishingPlatformCopy = true

        let snapshot = project
        let currentVariants = publishVariants
        Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isPolishingPlatformCopy = false
                }
            }
            do {
                let prompt = WuMindMultiPlatformPublishEngine.llmPolishPrompt(for: snapshot)
                let res = try await chatStore.runStatelessChat(
                    messages: [AIProviderMessage(role: .user, text: prompt)],
                    systemPrompt: "你是严谨的中文短剧多平台发行主编，只返回合法 JSON。",
                    deepThinking: false
                )
                guard let self else { return }
                self.publishVariants = WuMindMultiPlatformPublishEngine.applyPolishedCopy(
                    rawOutput: res.answer,
                    onto: currentVariants
                )
                self.persistPublishVariants()
                self.publishNotice = "已用 WUMIND 为 5 个平台分别重写封面主标题、发布标题与话题标签。"
                Haptics.success()
            } catch {
                guard let self else { return }
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.publishError = "AI 润色未完成（\(msg)），当前保留可直接使用的 5 平台默认适配文案。"
                Haptics.warning()
            }
        }
    }

    /// Executes the single-confirmation multi-platform publish batch:
    /// - Douyin: renders Douyin front-hook MP4 + cover, and if authorized submits via official Douyin OpenAPI
    ///   (transitioning strictly to `.submittedForReview(itemID:)` or `.failed`, NEVER faking `.published`!).
    /// - Other platforms (or unauthorized Douyin): renders each platform's tailored MP4 + cover PNG + copy bundle
    ///   and transitions strictly to `.pendingManualPublish` (NEVER faking `.published`!).
    func executeMultiPlatformPublish(userInformedConsent: Bool) {
        guard !isRunningPublishBatch else { return }
        publishError = nil
        publishNotice = nil

        do {
            try WuMindMultiPlatformPublishEngine.validateBatchConfirmation(
                variants: publishVariants,
                userAcknowledgedSubmissionAndAI: userInformedConsent
            )
        } catch {
            publishError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Haptics.warning()
            return
        }

        isRunningPublishBatch = true
        publishBatchStatus = "正在为所选平台逐一生成专属剪辑版与封面…"
        beginBackgroundProtection(name: "WuMindMultiPlatformPublish")

        let baseProject = project
        let selectedVariants = publishVariants.filter(\.isSelected)
        let mediaDir = Self.projectMediaDir(projectID: baseProject.id, create: true)
        let pkgDir = Self.publishPackageDir(projectID: baseProject.id, create: true)
        let dyOpenID = Keychain.douyinOpenID
        let dyAccessToken = Keychain.douyinAccessToken

        activeTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isRunningPublishBatch = false
                    self?.publishBatchStatus = ""
                    self?.endBackgroundProtection()
                }
            }

            var submittedCount = 0
            var manualCount = 0
            var failedCount = 0

            for (step, variant) in selectedVariants.enumerated() {
                if Task.isCancelled { break }
                let platformName = variant.platform.displayName
                await MainActor.run { [weak self] in
                    self?.publishBatchStatus = "(\(step + 1)/\(selectedVariants.count)) 正在生成「\(platformName)」专属剪辑 MP4 与封面…"
                }

                let adaptedProject = variant.cutPlan.adaptedProject(from: baseProject)
                let mp4Filename = "\(variant.platform.rawValue)_\(baseProject.id.uuidString.prefix(6)).mp4"
                let coverFilename = "\(variant.platform.rawValue)_cover_\(baseProject.id.uuidString.prefix(6)).png"
                let mp4Dest = pkgDir.appendingPathComponent(mp4Filename)
                let coverDest = pkgDir.appendingPathComponent(coverFilename)

                do {
                    // 1. Export platform-tailored MP4 with CAC explicit AI watermark & implicit metadata
                    let exportedTempURL = try await WuMindShortDramaComposer.exportVerticalMP4(
                        project: adaptedProject,
                        mediaDirectory: mediaDir,
                        aiDisclosure: variant.aiDisclosure,
                        filenamePrefix: variant.platform.rawValue
                    ) { [weak self] stage in
                        let store = self
                        await MainActor.run {
                            store?.publishBatchStatus = "「\(platformName)」\(stage)"
                        }
                    }
                    try? FileManager.default.removeItem(at: mp4Dest)
                    try FileManager.default.copyItem(at: exportedTempURL, to: mp4Dest)
                    try? FileManager.default.removeItem(at: exportedTempURL)

                    // 2. Render platform-tailored cover PNG (3:4 XHS / 16:9 Bilibili / 9:16 Douyin-KS-WeChat)
                    try WuMindShortDramaComposer.renderPlatformCoverPNG(
                        variant: variant,
                        project: baseProject,
                        to: coverDest
                    )

                    // 3. Branch honestly by verified platform capability
                    if variant.platform == .douyin,
                       let openID = dyOpenID, !openID.isEmpty,
                       let token = dyAccessToken, !token.isEmpty {
                        await MainActor.run { [weak self] in
                            self?.publishBatchStatus = "正在通过抖音官方接口提交审核（需用户知情授权）…"
                        }
                        let mp4Data = try Data(contentsOf: mp4Dest)
                        do {
                            let receipt = try await DouyinOfficialPublishClient().submitForReview(.init(
                                openID: openID,
                                accessToken: token,
                                mp4Data: mp4Data,
                                titleAndHashtagsText: "\(variant.title) " + variant.hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " "),
                                aiDisclosure: variant.aiDisclosure,
                                userInformedConsent: userInformedConsent
                            ))
                            var updated = WuMindMultiPlatformPublishEngine.applyDirectSubmitOutcome(
                                variant: variant,
                                itemID: receipt.itemID,
                                errorMessage: nil
                            )
                            updated.exportedMP4Filename = mp4Filename
                            updated.exportedCoverPNGFilename = coverFilename
                            await MainActor.run { [weak self] in
                                self?.updatePublishVariant(updated)
                            }
                            submittedCount += 1
                        } catch {
                            let errMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            var updated = WuMindMultiPlatformPublishEngine.applyDirectSubmitOutcome(
                                variant: variant,
                                itemID: nil,
                                errorMessage: errMsg
                            )
                            updated.exportedMP4Filename = mp4Filename
                            updated.exportedCoverPNGFilename = coverFilename
                            await MainActor.run { [weak self] in
                                self?.updatePublishVariant(updated)
                            }
                            failedCount += 1
                        }
                    } else {
                        let updated = WuMindMultiPlatformPublishEngine.applyPackageReadyOutcome(
                            variant: variant,
                            mp4Filename: mp4Filename,
                            coverPNGFilename: coverFilename
                        )
                        await MainActor.run { [weak self] in
                            self?.updatePublishVariant(updated)
                        }
                        manualCount += 1
                    }
                } catch {
                    let errMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    let updated = WuMindMultiPlatformPublishEngine.applyPackageReadyOutcome(
                        variant: variant,
                        mp4Filename: nil,
                        coverPNGFilename: nil,
                        errorMessage: errMsg
                    )
                    await MainActor.run { [weak self] in
                        self?.updatePublishVariant(updated)
                    }
                    failedCount += 1
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                var summaryParts: [String] = []
                if submittedCount > 0 { summaryParts.append("抖音已提交审核 \(submittedCount) 条") }
                if manualCount > 0 { summaryParts.append("待手动发布包 \(manualCount) 份已备齐") }
                if failedCount > 0 { summaryParts.append("失败 \(failedCount) 项（可看明细重试）") }
                self.publishNotice = summaryParts.isEmpty ? "批处理已完成。" : summaryParts.joined(separator: " · ")
                if failedCount > 0 { Haptics.warning() } else { Haptics.success() }
            }
        }
    }

    private func persistPublishVariants() {
        let url = Self.publishVariantsURL(projectID: project.id, create: true)
        guard let data = try? JSONEncoder().encode(publishVariants) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func loadSavedPublishVariants(projectID: UUID) -> [WuMindPlatformPublishVariant]? {
        let url = publishVariantsURL(projectID: projectID, create: false)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WuMindPlatformPublishVariant].self, from: data) else {
            return nil
        }
        return decoded
    }

    private static func publishVariantsURL(projectID: UUID, create: Bool) -> URL {
        publishPackageDir(projectID: projectID, create: create).appendingPathComponent("variants.json")
    }

    private static func publishPackageDir(projectID: UUID, create: Bool) -> URL {
        let dir = rootDir(create: create)
            .appendingPathComponent("PublishPackages", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func beginBackgroundProtection(name: String) {
        endBackgroundProtection()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundProtection()
            }
        }
    }

    private func endBackgroundProtection() {
        if backgroundTaskID != .invalid {
            let id = backgroundTaskID
            backgroundTaskID = .invalid
            UIApplication.shared.endBackgroundTask(id)
        }
    }
}

// MARK: - On-Device 9:16 Multi-Track MP4 Composer (Video + Voiceover + Burned-In Subtitles)

enum WuMindShortDramaComposer {
    private static let renderSize = CGSize(width: 720, height: 1280)

    enum ComposerError: LocalizedError {
        case emptyShots
        case exportSessionUnavailable
        case exportFailed(String)
        case placeholderRenderFailed

        var errorDescription: String? {
            switch self {
            case .emptyShots: return "当前没有可导出的镜头。"
            case .exportSessionUnavailable: return "系统未能初始化 MP4 导出器。"
            case .exportFailed(let detail): return detail
            case .placeholderRenderFailed: return "生成分镜粗剪占位画面失败。"
            }
        }
    }

    /// Exports a real 9:16 H.264 MP4 combining rendered takes, animatic placeholders, independent voiceover,
    /// burned-in subtitles, explicit AI-generated disclosure badge, and implicit MP4 metadata.
    @MainActor
    static func exportVerticalMP4(
        project: WuMindShortDramaProject,
        mediaDirectory: URL,
        aiDisclosure: WuMindAIGeneratedDisclosure = WuMindAIGeneratedDisclosure(),
        filenamePrefix: String? = nil,
        onProgress: @escaping @Sendable (String) async -> Void
    ) async throws -> URL {
        guard !project.shots.isEmpty else { throw ComposerError.emptyShots }

        let tempWorkDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wumind-drama-export-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: tempWorkDir, withIntermediateDirectories: true)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ComposerError.exportSessionUnavailable
        }
        let originalAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let voiceoverTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var layerInstructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero
        let totalCount = project.shots.count
        var hasOriginalAudio = false
        var hasVoiceoverAudio = false

        for (index, shot) in project.shots.enumerated() {
            try Task.checkCancellation()
            await onProgress("1/3 正在处理第 \(index + 1)/\(totalCount) 镜画面与裁剪窗口…")

            let character = project.character(for: shot)
            let clipURL: URL
            var useDirectTrim = true

            if let take = shot.activeTake {
                let candidate = mediaDirectory.appendingPathComponent(take.videoFilename)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    clipURL = candidate
                } else {
                    clipURL = tempWorkDir.appendingPathComponent("placeholder_\(index).mp4")
                    try await renderStoryboardPlaceholderMP4(
                        to: clipURL,
                        shotIndex: index,
                        totalShots: totalCount,
                        shot: shot,
                        character: character,
                        projectTitle: project.title,
                        durationSeconds: shot.trimmedDuration
                    )
                    useDirectTrim = false
                }
            } else {
                clipURL = tempWorkDir.appendingPathComponent("placeholder_\(index).mp4")
                try await renderStoryboardPlaceholderMP4(
                    to: clipURL,
                    shotIndex: index,
                    totalShots: totalCount,
                    shot: shot,
                    character: character,
                    projectTitle: project.title,
                    durationSeconds: shot.trimmedDuration
                )
                useDirectTrim = false
            }

            let asset = AVURLAsset(url: clipURL)
            let assetDuration = try await asset.load(.duration)
            let assetSeconds = max(0.5, CMTimeGetSeconds(assetDuration))
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let srcVideo = videoTracks.first else { continue }

            let startSec = useDirectTrim ? min(shot.trimStartSeconds, max(0, assetSeconds - 0.5)) : 0
            let desiredDur = min(shot.trimmedDuration, max(0.5, assetSeconds - startSec))
            let srcRange = CMTimeRange(
                start: CMTime(seconds: startSec, preferredTimescale: 600),
                duration: CMTime(seconds: desiredDur, preferredTimescale: 600)
            )
            try videoTrack.insertTimeRange(srcRange, of: srcVideo, at: cursor)

            // Preserve original video audio softly if present
            if let originalAudioTrack,
               let srcAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                if (try? originalAudioTrack.insertTimeRange(srcRange, of: srcAudio, at: cursor)) != nil {
                    hasOriginalAudio = true
                }
            }

            // Normalize transform so any aspect ratio fits cleanly inside 720x1280 9:16 frame
            let naturalSize = try await srcVideo.load(.naturalSize)
            let preferredTransform = try await srcVideo.load(.preferredTransform)
            let fitTransform = aspectFillTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                targetSize: renderSize
            )
            let layerInst = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInst.setTransform(fitTransform, at: cursor)
            let inst = AVMutableVideoCompositionInstruction()
            inst.timeRange = CMTimeRange(start: cursor, duration: srcRange.duration)
            inst.layerInstructions = [layerInst]
            layerInstructions.append(inst)

            // Synthesize independent voiceover audio track when enabled
            let cleanDialogue = shot.dialogue.trimmingCharacters(in: .whitespacesAndNewlines)
            if project.globalVoiceoverEnabled, shot.voiceoverEnabled, !cleanDialogue.isEmpty, let voiceoverTrack {
                await onProgress("2/3 正在合成第 \(index + 1)/\(totalCount) 镜独立配音轨…")
                let cafURL = tempWorkDir.appendingPathComponent("vo_\(index).caf")
                let preset = character?.voicePreset ?? .narrator
                if await synthesizeVoiceoverCAF(text: cleanDialogue, preset: preset, outputURL: cafURL) {
                    let voAsset = AVURLAsset(url: cafURL)
                    if let voTrack = try? await voAsset.loadTracks(withMediaType: .audio).first,
                       let voDur = try? await voAsset.load(.duration) {
                        let clippedDur = CMTimeMinimum(voDur, srcRange.duration)
                        if CMTimeGetSeconds(clippedDur) > 0.1 {
                            let voRange = CMTimeRange(start: .zero, duration: clippedDur)
                            if (try? voiceoverTrack.insertTimeRange(voRange, of: voTrack, at: cursor)) != nil {
                                hasVoiceoverAudio = true
                            }
                        }
                    }
                }
            }

            cursor = CMTimeAdd(cursor, srcRange.duration)
        }

        // Remove unused empty audio tracks cleanly so AVAssetExportSession never fails on empty tracks
        if let originalAudioTrack, !hasOriginalAudio {
            composition.removeTrack(originalAudioTrack)
        }
        if let voiceoverTrack, !hasVoiceoverAudio {
            composition.removeTrack(voiceoverTrack)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = layerInstructions

        // Burn in independent subtitle track & mandatory CAC AI disclosure watermark via CoreAnimation tool
        let cues = WuMindShortDramaEngine.subtitleCues(for: project)
        if !cues.isEmpty || aiDisclosure.enabled {
            let parentLayer = CALayer()
            parentLayer.frame = CGRect(origin: .zero, size: renderSize)
            let videoLayer = CALayer()
            videoLayer.frame = CGRect(origin: .zero, size: renderSize)
            parentLayer.addSublayer(videoLayer)

            if !cues.isEmpty {
                let overlayLayer = makeSubtitleOverlayLayer(cues: cues, canvasSize: renderSize)
                parentLayer.addSublayer(overlayLayer)
            }
            if aiDisclosure.enabled {
                let aiBadge = makeAIGeneratedBadgeLayer(text: aiDisclosure.visibleWatermarkText, canvasSize: renderSize)
                parentLayer.addSublayer(aiBadge)
            }
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
        }

        await onProgress("3/3 正在封装 9:16 H.264 MP4 并写入 AI 标识元数据…")
        let safeTitle = sanitizedFilename(project.title)
        let prefix = filenamePrefix.map { "\(sanitizedFilename($0))_" } ?? ""
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)\(safeTitle)_9x16_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ComposerError.exportSessionUnavailable
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition
        if aiDisclosure.enabled {
            exporter.metadata = makeImplicitAIMetadataItems(disclosure: aiDisclosure)
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously {
                cont.resume()
            }
        }

        try? FileManager.default.removeItem(at: tempWorkDir)

        guard exporter.status == .completed else {
            throw ComposerError.exportFailed(exporter.error?.localizedDescription ?? "MP4 编码器异常退出（status=\(exporter.status.rawValue)）。")
        }
        return outputURL
    }

    /// Renders a platform-proportioned cover PNG (3:4 Xiaohongshu / 16:9 Bilibili / 9:16 Douyin, Kuaishou, WeChat)
    /// with bold typography, optional character reference portrait, and explicit AI-generated disclosure badge.
    @MainActor
    static func renderPlatformCoverPNG(
        variant: WuMindPlatformPublishVariant,
        project: WuMindShortDramaProject,
        to outputURL: URL
    ) throws {
        let dims = variant.platform.coverDimensions
        let size = CGSize(width: dims.width, height: dims.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { ctx in
            let palette: (UIColor, UIColor, UIColor) = {
                switch variant.platform {
                case .douyin:
                    return (UIColor(red: 0.06, green: 0.06, blue: 0.11, alpha: 1), UIColor(red: 0.16, green: 0.05, blue: 0.18, alpha: 1), UIColor(red: 1.0, green: 0.22, blue: 0.44, alpha: 1))
                case .xiaohongshu:
                    return (UIColor(red: 0.14, green: 0.05, blue: 0.08, alpha: 1), UIColor(red: 0.28, green: 0.07, blue: 0.12, alpha: 1), UIColor(red: 1.0, green: 0.32, blue: 0.38, alpha: 1))
                case .kuaishou:
                    return (UIColor(red: 0.16, green: 0.08, blue: 0.04, alpha: 1), UIColor(red: 0.26, green: 0.12, blue: 0.05, alpha: 1), UIColor(red: 1.0, green: 0.48, blue: 0.12, alpha: 1))
                case .bilibili:
                    return (UIColor(red: 0.06, green: 0.11, blue: 0.20, alpha: 1), UIColor(red: 0.14, green: 0.09, blue: 0.24, alpha: 1), UIColor(red: 0.98, green: 0.45, blue: 0.62, alpha: 1))
                case .wechatChannels:
                    return (UIColor(red: 0.05, green: 0.14, blue: 0.11, alpha: 1), UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1), UIColor(red: 0.14, green: 0.78, blue: 0.48, alpha: 1))
                }
            }()

            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [palette.0.cgColor, palette.1.cgColor] as CFArray,
                locations: [0, 1]
            ) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            // Optional character reference photo backdrop vignette
            if let refB64 = project.characters.first(where: { $0.referenceImageBase64 != nil })?.referenceImageBase64,
               let data = Data(base64Encoded: refB64),
               let portrait = UIImage(data: data) {
                ctx.cgContext.saveGState()
                ctx.cgContext.setAlpha(0.32)
                let scale = max(size.width / max(1, portrait.size.width), size.height / max(1, portrait.size.height))
                let drawW = portrait.size.width * scale
                let drawH = portrait.size.height * scale
                portrait.draw(in: CGRect(x: (size.width - drawW) / 2, y: (size.height - drawH) / 2, width: drawW, height: drawH))
                ctx.cgContext.restoreGState()
            }

            let margin: CGFloat = size.width * 0.075
            let isLandscape = size.width > size.height

            // Platform tag pill top-left
            let tagRect = CGRect(x: margin, y: margin, width: 320, height: 56)
            let tagPath = UIBezierPath(roundedRect: tagRect, cornerRadius: 28)
            palette.2.withAlphaComponent(0.92).setFill()
            tagPath.fill()
            let tagStyle = NSMutableParagraphStyle()
            tagStyle.alignment = .center
            "\(variant.platform.displayName)专属版 · \(project.genre.rawValue)".draw(
                in: CGRect(x: tagRect.minX, y: tagRect.minY + 12, width: tagRect.width, height: 36),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: tagStyle,
                ]
            )

            // Mandatory explicit AI disclosure corner badge top-right
            if variant.aiDisclosure.enabled {
                let badgeW: CGFloat = 248
                let badgeRect = CGRect(x: size.width - margin - badgeW, y: margin, width: badgeW, height: 50)
                let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 16)
                UIColor.black.withAlphaComponent(0.58).setFill()
                badgePath.fill()
                UIColor.white.withAlphaComponent(0.35).setStroke()
                badgePath.lineWidth = 2
                badgePath.stroke()
                variant.aiDisclosure.visibleWatermarkText.draw(
                    in: CGRect(x: badgeRect.minX, y: badgeRect.minY + 10, width: badgeW, height: 32),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                        .foregroundColor: UIColor.white.withAlphaComponent(0.94),
                        .paragraphStyle: tagStyle,
                    ]
                )
            }

            // Bold headline + subheadline
            let headlineFontSize: CGFloat = isLandscape ? 92 : 84
            let headlineY: CGFloat = isLandscape ? size.height * 0.30 : size.height * 0.34
            variant.coverHeadline.draw(
                in: CGRect(x: margin, y: headlineY, width: size.width - margin * 2, height: headlineFontSize * 2.8),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: headlineFontSize, weight: .black),
                    .foregroundColor: UIColor.white,
                ]
            )

            let subY = headlineY + (isLandscape ? 250 : 280)
            variant.coverSubheadline.draw(
                in: CGRect(x: margin, y: subY, width: size.width - margin * 2, height: 110),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: isLandscape ? 42 : 40, weight: .bold),
                    .foregroundColor: palette.2,
                ]
            )

            // Footer hook quote
            let hookCardY = size.height - margin - (isLandscape ? 160 : 220)
            let hookRect = CGRect(x: margin, y: hookCardY, width: size.width - margin * 2, height: isLandscape ? 140 : 180)
            let hookPath = UIBezierPath(roundedRect: hookRect, cornerRadius: 28)
            UIColor.black.withAlphaComponent(0.46).setFill()
            hookPath.fill()
            variant.title.draw(
                in: hookRect.insetBy(dx: 30, dy: 24),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: isLandscape ? 32 : 34, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.94),
                ]
            )
        }

        guard let pngData = image.pngData() else {
            throw ComposerError.placeholderRenderFailed
        }
        try pngData.write(to: outputURL, options: [.atomic, .completeFileProtection])
    }

    @MainActor
    private static func makeAIGeneratedBadgeLayer(text: String, canvasSize: CGSize) -> CALayer {
        let badgeW: CGFloat = 204
        let badgeH: CGFloat = 38
        let pill = CALayer()
        // CoreAnimation bottom-left origin -> top-right safe corner
        pill.frame = CGRect(x: canvasSize.width - badgeW - 24, y: canvasSize.height - badgeH - 36, width: badgeW, height: badgeH)
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.56).cgColor
        pill.cornerRadius = 12
        pill.borderWidth = 1.0
        pill.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor

        let label = CATextLayer()
        label.string = text
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        label.fontSize = 18
        label.foregroundColor = UIColor.white.withAlphaComponent(0.92).cgColor
        label.alignmentMode = .center
        label.contentsScale = 2.0
        label.frame = CGRect(x: 8, y: 7, width: badgeW - 16, height: 24)
        pill.addSublayer(label)
        return pill
    }

    private static func makeImplicitAIMetadataItems(disclosure: WuMindAIGeneratedDisclosure) -> [AVMetadataItem] {
        func makeItem(key: AVMetadataKey, value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.keySpace = .common
            item.key = key as NSString
            item.value = value as NSString
            return item
        }
        return [
            makeItem(key: .commonKeyDescription, value: disclosure.implicitMetadataTag),
            makeItem(key: .commonKeyCreator, value: "WUMIND AI Short-Drama Studio"),
            makeItem(key: .commonKeySoftware, value: "WUMIND (AI-Generated Content Disclosure Enabled)"),
        ]
    }

    // MARK: - CoreAnimation Vertical Subtitle Layer

    @MainActor
    private static func makeSubtitleOverlayLayer(cues: [WuMindSubtitleCue], canvasSize: CGSize) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: canvasSize)
        container.isGeometryFlipped = false

        for cue in cues {
            let start = max(0.01, cue.startSeconds)
            let duration = max(0.2, cue.endSeconds - cue.startSeconds)

            let pill = CALayer()
            let boxWidth = canvasSize.width - 72
            let boxHeight: CGFloat = 128
            // CoreAnimation bottom-left origin in AVVideoCompositionCoreAnimationTool
            pill.frame = CGRect(x: 36, y: 118, width: boxWidth, height: boxHeight)
            pill.backgroundColor = UIColor.black.withAlphaComponent(0.66).cgColor
            pill.cornerRadius = 20
            pill.borderWidth = 1.5
            pill.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
            pill.opacity = 0

            let textLayer = CATextLayer()
            let displayLine = cue.speakerName.map { "\($0)：\(cue.text)" } ?? cue.text
            textLayer.string = displayLine
            textLayer.font = UIFont.systemFont(ofSize: 30, weight: .bold)
            textLayer.fontSize = 30
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.alignmentMode = .center
            textLayer.isWrapped = true
            textLayer.contentsScale = 2.0
            textLayer.frame = CGRect(x: 20, y: 18, width: boxWidth - 40, height: boxHeight - 36)
            pill.addSublayer(textLayer)

            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 0.0
            show.toValue = 1.0
            show.beginTime = AVCoreAnimationBeginTimeAtZero + start
            show.duration = 0.06
            show.fillMode = .forwards
            show.isRemovedOnCompletion = false
            pill.add(show, forKey: "show")

            let hide = CABasicAnimation(keyPath: "opacity")
            hide.fromValue = 1.0
            hide.toValue = 0.0
            hide.beginTime = AVCoreAnimationBeginTimeAtZero + start + max(0.1, duration - 0.06)
            hide.duration = 0.06
            hide.fillMode = .forwards
            hide.isRemovedOnCompletion = false
            pill.add(hide, forKey: "hide")

            container.addSublayer(pill)
        }
        return container
    }

    // MARK: - Transform Normalization (Aspect Fill into 720x1280 9:16)

    private static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        targetSize: CGSize
    ) -> CGAffineTransform {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        guard orientedSize.width > 1, orientedSize.height > 1 else {
            return preferredTransform
        }
        let scale = max(targetSize.width / orientedSize.width, targetSize.height / orientedSize.height)
        let scaledW = orientedSize.width * scale
        let scaledH = orientedSize.height * scale
        let tx = (targetSize.width - scaledW) / 2.0 - transformedRect.origin.x * scale
        let ty = (targetSize.height - scaledH) / 2.0 - transformedRect.origin.y * scale
        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    // MARK: - Storyboard Animatic Placeholder MP4 Generator (720x1280 H.264)

    @MainActor
    private static func renderStoryboardPlaceholderMP4(
        to outputURL: URL,
        shotIndex: Int,
        totalShots: Int,
        shot: WuMindDramaShot,
        character: WuMindDramaCharacter?,
        projectTitle: String,
        durationSeconds: Double
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        let width = Int(renderSize.width)
        let height = Int(renderSize.height)
        let fps: Int32 = 15
        let totalFrames = max(15, Int((durationSeconds * Double(fps)).rounded()))

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: adaptorAttrs
        )
        guard writer.canAdd(input) else { throw ComposerError.placeholderRenderFailed }
        writer.add(input)
        guard writer.startWriting() else { throw ComposerError.placeholderRenderFailed }
        writer.startSession(atSourceTime: .zero)

        let cardImage = renderStoryboardCardImage(
            size: renderSize,
            shotIndex: shotIndex,
            totalShots: totalShots,
            shot: shot,
            character: character,
            projectTitle: projectTitle
        )

        guard let cgImage = cardImage.cgImage else { throw ComposerError.placeholderRenderFailed }
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for frameIdx in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                [
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                ] as CFDictionary,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess, let pb = pixelBuffer else {
                throw ComposerError.placeholderRenderFailed
            }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(pb),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                // Subtle progress bar along the top edge so rough-cut timing is unmistakable
                let progress = CGFloat(frameIdx + 1) / CGFloat(totalFrames)
                ctx.setFillColor(UIColor(red: 0.52, green: 0.36, blue: 0.98, alpha: 0.95).cgColor)
                ctx.fill(CGRect(x: 0, y: CGFloat(height) - 10, width: CGFloat(width) * progress, height: 10))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            let pts = CMTime(value: CMTimeValue(frameIdx), timescale: fps)
            adaptor.append(pb, withPresentationTime: pts)
        }

        input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                cont.resume()
            }
        }
        guard writer.status == .completed else {
            throw ComposerError.placeholderRenderFailed
        }
    }

    @MainActor
    private static func renderStoryboardCardImage(
        size: CGSize,
        shotIndex: Int,
        totalShots: Int,
        shot: WuMindDramaShot,
        character: WuMindDramaCharacter?,
        projectTitle: String
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let palettes: [(UIColor, UIColor)] = [
                (UIColor(red: 0.07, green: 0.10, blue: 0.22, alpha: 1), UIColor(red: 0.18, green: 0.08, blue: 0.28, alpha: 1)),
                (UIColor(red: 0.06, green: 0.16, blue: 0.22, alpha: 1), UIColor(red: 0.10, green: 0.09, blue: 0.20, alpha: 1)),
                (UIColor(red: 0.16, green: 0.08, blue: 0.18, alpha: 1), UIColor(red: 0.06, green: 0.10, blue: 0.20, alpha: 1)),
            ]
            let pair = palettes[shotIndex % palettes.count]
            let colors = [pair.0.cgColor, pair.1.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            // Header badge
            let badgeText = "WUMIND 短剧粗剪占位 · 第 \(shotIndex + 1)/\(totalShots) 镜 · \(shot.cameraFraming.label)"
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor(white: 1.0, alpha: 0.85),
            ]
            badgeText.draw(in: CGRect(x: 48, y: 84, width: size.width - 96, height: 40), withAttributes: badgeAttrs)

            // Drama title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
                .foregroundColor: UIColor.white,
            ]
            "《\(projectTitle)》".draw(in: CGRect(x: 48, y: 148, width: size.width - 96, height: 64), withAttributes: titleAttrs)

            let shotTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor(red: 0.72, green: 0.64, blue: 1.0, alpha: 1),
            ]
            "\(shot.title) · \(shot.cameraMovement)".draw(
                in: CGRect(x: 48, y: 226, width: size.width - 96, height: 50),
                withAttributes: shotTitleAttrs
            )

            // Character portrait thumbnail if user uploaded one
            var bodyTopY: CGFloat = 310
            if let b64 = character?.referenceImageBase64,
               let rawData = Data(base64Encoded: b64),
               let portrait = UIImage(data: rawData) {
                let avatarRect = CGRect(x: 48, y: 300, width: 120, height: 120)
                UIBezierPath(roundedRect: avatarRect, cornerRadius: 24).addClip()
                portrait.draw(in: avatarRect)
                ctx.cgContext.resetClip()
                let charInfo = "\(character?.name ?? "角色") · \(character?.voicePreset.displayName ?? "")"
                charInfo.draw(
                    in: CGRect(x: 188, y: 340, width: size.width - 236, height: 48),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                        .foregroundColor: UIColor.white,
                    ]
                )
                bodyTopY = 456
            }

            // Storyboard prompt card
            let cardRect = CGRect(x: 48, y: bodyTopY, width: size.width - 96, height: 420)
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 28)
            UIColor.white.withAlphaComponent(0.08).setFill()
            cardPath.fill()
            UIColor.white.withAlphaComponent(0.18).setStroke()
            cardPath.lineWidth = 2
            cardPath.stroke()

            let promptAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: UIColor(white: 0.94, alpha: 1),
            ]
            let cardBody = "画面分镜：\n\(shot.visualPrompt)\n\n目标引擎：\(shot.preferredEngine.shortBadge)（点击该镜即可单独实拍替换）"
            cardBody.draw(in: cardRect.insetBy(dx: 28, dy: 28), withAttributes: promptAttrs)
        }
    }

    // MARK: - Independent Offline Voiceover Audio Track Synthesis (AVSpeechSynthesizer.write)

    @MainActor
    private static func synthesizeVoiceoverCAF(
        text: String,
        preset: WuMindDramaVoicePreset,
        outputURL: URL
    ) async -> Bool {
        try? FileManager.default.removeItem(at: outputURL)
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = preset.speechRate
        utterance.pitchMultiplier = preset.pitchMultiplier

        let sink = VoiceoverBufferSink(outputURL: outputURL)
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sink.attachContinuation(cont)
            // Guard against environments without downloaded TTS voice packs
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 4.0) {
                sink.finishIfNeeded()
            }
            synthesizer.write(utterance) { buffer in
                sink.consume(buffer)
            }
        }
        _ = synthesizer
        return ok
    }

    private static func sanitizedFilename(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t ")
        let clean = raw.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "WUMIND_Drama" : String(clean.prefix(24))
    }
}

/// Thread-safe bridge for `AVSpeechSynthesizer.write(_:toBufferCallback:)` so Swift 6 strict concurrency stays 0 warnings.
private final class VoiceoverBufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private let outputURL: URL
    private var audioFile: AVAudioFile?
    private var wroteFrames = false
    private var continuation: CheckedContinuation<Bool, Never>?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func attachContinuation(_ cont: CheckedContinuation<Bool, Never>) {
        lock.lock()
        continuation = cont
        lock.unlock()
    }

    func consume(_ buffer: AVAudioBuffer) {
        lock.lock()
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            lock.unlock()
            return
        }
        if pcm.frameLength == 0 {
            let cont = continuation
            continuation = nil
            audioFile = nil
            let success = wroteFrames
            lock.unlock()
            cont?.resume(returning: success)
            return
        }
        do {
            if audioFile == nil {
                audioFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: pcm.format.settings,
                    commonFormat: pcm.format.commonFormat,
                    interleaved: pcm.format.isInterleaved
                )
            }
            try audioFile?.write(from: pcm)
            wroteFrames = true
        } catch {
            // Skip corrupted frame cleanly
        }
        lock.unlock()
    }

    func finishIfNeeded() {
        lock.lock()
        let cont = continuation
        continuation = nil
        audioFile = nil
        let success = wroteFrames
        lock.unlock()
        cont?.resume(returning: success)
    }
}
