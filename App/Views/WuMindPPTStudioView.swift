import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Persistent, background-resilient autonomous PPT workflow store.
/// Runs one-click full PowerPoint generation (read materials -> optional opt-in web search ->
/// plan & write slides/tables/charts/notes -> automated quality self-repair -> native editable `.pptx` + PDF),
/// survives tab switching & backgrounding without losing progress, and supports single-slide regeneration & editing.
@MainActor
final class WuMindPPTWorkflowStore: ObservableObject {
    static let shared = WuMindPPTWorkflowStore()

    private struct PersistedSnapshot: Codable {
        let topicPrompt: String
        let theme: WuMindPPTTheme
        let slideCount: Int
        let audience: WuMindPPTAudience
        let webSearchEnabled: Bool
        let deck: WuMindPPTDeck
        let savedAt: Date
    }

    @Published var topicPrompt: String = ""
    @Published var theme: WuMindPPTTheme = .midnightTech
    @Published var slideCount: Int = 8
    @Published var audience: WuMindPPTAudience = .general
    @Published var webSearchEnabled: Bool = false
    @Published var sourceAttachments: [WuMindAttachment] = []
    @Published var importingAttachment: Bool = false
    @Published var companyLogoBase64: String? = nil
    @Published var rawExcelData: Data? = nil
    @Published var rawExcelFilename: String? = nil

    @Published private(set) var generating: Bool = false
    @Published private(set) var regeneratingSlideID: Int? = nil
    @Published private(set) var stageLabel: String = ""
    @Published private(set) var liveStreamingChars: Int = 0
    @Published private(set) var deck: WuMindPPTDeck? = nil
    @Published var selectedSlideIndex: Int = 0
    @Published private(set) var exportedPPTXURL: URL? = nil
    @Published private(set) var exportedPDFURL: URL? = nil
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var savedAt: Date? = nil
    @Published private(set) var restoredFromDisk: Bool = false
    @Published private(set) var lastWebSourcesSummary: String? = nil
    @Published private(set) var lastSurgicalEditSummary: String? = nil
    @Published private(set) var currentWorkID: String? = nil

    private var generateTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {
        restoreLastDeckIfAvailable()
    }

    func addAttachment(_ doc: WuMindAttachmentParser.ExtractedDocument, rawData: Data? = nil) {
        if sourceAttachments.count >= 6 {
            sourceAttachments.removeFirst()
        }
        sourceAttachments.append(WuMindAttachment(document: doc))
        if doc.kind == .excel, let rawData, !rawData.isEmpty {
            rawExcelData = rawData
            rawExcelFilename = doc.filename
        }
    }

    func removeAttachment(_ id: UUID) {
        sourceAttachments.removeAll { $0.id == id }
    }

    func loadExternalDeck(_ loaded: WuMindPPTDeck, workID: String? = nil) {
        currentWorkID = workID
        theme = loaded.theme
        slideCount = loaded.slides.count
        if let aud = loaded.audience { audience = aud }
        if let logo = loaded.logoDataBase64 { companyLogoBase64 = logo }
        selectedSlideIndex = 0
        lastSurgicalEditSummary = nil
        commitDeck(loaded, restored: true)
    }

    /// Deterministically builds a 10-slide executive Chinese report (8-min pacing, conclusion-first,
    /// >= 2 real Excel-backed editable charts, company logo embedded) directly from uploaded Word/Excel/Logo.
    func buildExecutiveReportFromMaterials() {
        let wordText = sourceAttachments
            .filter { $0.document.kind == .word || $0.document.kind == .pdf || $0.document.kind == .text }
            .map(\.document.extractedText)
            .joined(separator: "\n")
        let titleText = topicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "季度经营汇报与下阶段决策建议"
            : topicPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let built = WuMindPPTEngine.buildExecutiveReportDeck(
            title: titleText,
            subtitle: "面向管理层 · 8 分钟核心经营汇报",
            wordText: wordText,
            excelData: rawExcelData,
            excelFilename: rawExcelFilename ?? "季度经营数据.xlsx",
            logoDataBase64: companyLogoBase64,
            theme: theme,
            targetSlideCount: 10,
            targetDurationMinutes: 8
        )
        selectedSlideIndex = 0
        lastSurgicalEditSummary = nil
        currentWorkID = nil
        commitDeck(built, restored: false, asNewVersion: false)
    }

    /// Surgically edits ONE target slide (e.g. "第 5 页改为季度趋势折线图，沿用原数据和配色")
    /// keeping all other slides bit-for-bit identical, and saves as a NEW version in 「我的作品」!
    @discardableResult
    func applySurgicalEdit(instruction: String) -> String? {
        guard let current = deck else { return nil }
        guard let res = WuMindPPTEngine.applySurgicalSlideEdit(
            instruction: instruction,
            to: current,
            fallbackSlideIndex: selectedSlideIndex
        ) else {
            return nil
        }
        selectedSlideIndex = res.modifiedSlideIndex
        lastSurgicalEditSummary = res.summary
        commitDeck(res.deck, restored: false, asNewVersion: true)
        return res.summary
    }

    func clearDeckAndReset() {
        cancelGeneration()
        deck = nil
        selectedSlideIndex = 0
        exportedPPTXURL = nil
        exportedPDFURL = nil
        errorMessage = nil
        savedAt = nil
        restoredFromDisk = false
        lastWebSourcesSummary = nil
        lastSurgicalEditSummary = nil
        currentWorkID = nil
        if let url = Self.snapshotURL(create: false) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func applyTheme(_ newTheme: WuMindPPTTheme) {
        theme = newTheme
        guard var updated = deck else { return }
        updated.theme = newTheme
        commitDeck(updated, restored: false, asNewVersion: true)
    }

    func updateSlide(at index: Int, mutated: WuMindPPTDeck.Slide) {
        guard var current = deck, current.slides.indices.contains(index) else { return }
        current.slides[index] = mutated
        let checked = WuMindPPTEngine.inspectAndRepair(
            current,
            expectedSlideCount: nil,
            hasSourceMaterials: !(current.sourceFiles ?? []).isEmpty || !sourceAttachments.isEmpty,
            webSearchUsed: current.webSearchUsed ?? false
        )
        commitDeck(checked, restored: false, asNewVersion: true)
    }

    func cancelGeneration() {
        generateTask?.cancel()
        generateTask = nil
        generating = false
        regeneratingSlideID = nil
        stageLabel = ""
        endBackgroundProtection()
    }

    /// One-click autonomous end-to-end PPT generation (never stops on an outline confirmation screen).
    func startAutonomousGeneration(using store: WuMindStore) {
        let trimmed = topicPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !sourceAttachments.isEmpty else { return }

        let effectiveTopic = trimmed.isEmpty
            ? "基于已上传资料的汇报演示（\(sourceAttachments.map(\.document.filename).joined(separator: "、"))）"
            : trimmed
        let resolvedSlideCount = WuMindPPTEngine.extractRequestedSlideCount(from: effectiveTopic, fallback: slideCount)
        slideCount = resolvedSlideCount

        let chosenTheme = theme
        let chosenAudience = audience
        let allowWeb = webSearchEnabled
        let stagedAttachments = sourceAttachments
        let hasSources = !stagedAttachments.isEmpty

        errorMessage = nil
        generating = true
        regeneratingSlideID = nil
        liveStreamingChars = 0
        lastWebSourcesSummary = nil
        stageLabel = hasSources
            ? "1/4 正在读取 \(stagedAttachments.count) 份资料、提炼要点与表格数据…"
            : "1/4 正在规划 \(resolvedSlideCount) 页结构与版面…"

        beginBackgroundProtection()
        generateTask?.cancel()
        generateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.generating = false
                self.stageLabel = ""
                self.endBackgroundProtection()
            }
            do {
                var promptBlocks: [String] = [
                    "【用户需求】\n\(effectiveTopic)",
                    "【参数约束】页数：\(resolvedSlideCount) 页；视觉主题：\(chosenTheme.title)；目标受众：\(chosenAudience.title)（\(chosenAudience.guidance)）。"
                ]

                var visionImages: [AIProviderMessage.ImageAttachment] = []
                var uploadedRawImages: [String] = []

                if hasSources {
                    var materialSections: [String] = []
                    for item in stagedAttachments {
                        let doc = item.document
                        if let img = doc.makeAIImageAttachment() {
                            visionImages.append(img)
                            uploadedRawImages.append(img.base64Data)
                        }
                        let snippet = String(doc.extractedText.prefix(12_000))
                        materialSections.append("【原始资料：\(doc.filename)（\(doc.summaryBadge)）】\n\(snippet)")
                    }
                    promptBlocks.append(materialSections.joined(separator: "\n\n---\n\n"))
                }

                var actuallyUsedWeb = false
                if allowWeb {
                    self.stageLabel = "2/4 正在按需联网补充公开参考资料并记录来源…"
                    let webResult = await Self.performOptInWebSearch(query: String(effectiveTopic.prefix(80)), store: store)
                    try Task.checkCancellation()
                    if webResult.succeeded && !webResult.observationText.isEmpty {
                        actuallyUsedWeb = true
                        self.lastWebSourcesSummary = webResult.summary
                        promptBlocks.append("【已开启联网检索参考资料（请在对应页 citations 中标注来源）】\n\(String(webResult.observationText.prefix(6_000)))")
                    } else {
                        self.lastWebSourcesSummary = "联网检索未返回有效结果，仅基于本机需求与资料生成"
                    }
                }

                self.stageLabel = "3/4 正在撰写逐页内容、表格/图表数据与演讲备注（切后台不会中断）…"
                let sys = WuMindPPTEngine.systemPrompt(
                    slideCount: resolvedSlideCount,
                    theme: chosenTheme,
                    audience: chosenAudience,
                    hasSourceMaterials: hasSources,
                    webSearchEnabled: actuallyUsedWeb
                )
                let userMessage = AIProviderMessage(
                    role: .user,
                    text: promptBlocks.joined(separator: "\n\n"),
                    images: store.activeProviderForDisplay != .deepSeek ? visionImages : []
                )

                let res = try await store.runStatelessChat(
                    messages: [userMessage],
                    systemPrompt: sys,
                    deepThinking: false,
                    onAnswerDelta: { partial in
                        self.liveStreamingChars = partial.count
                    }
                )
                try Task.checkCancellation()

                self.stageLabel = "4/4 正在自动体检（防溢出/防遮挡/数据核验）并生成可编辑 .pptx 与 PDF…"
                var parsed = WuMindPPTEngine.parseDeck(
                    from: res.answer,
                    fallbackTopic: String(effectiveTopic.prefix(24)),
                    theme: chosenTheme
                )
                parsed.audience = chosenAudience
                parsed.sourceFiles = stagedAttachments.map(\.document.filename)

                // Attach uploaded user images cleanly to visual-friendly slides (without colliding with charts/tables)
                if !uploadedRawImages.isEmpty {
                    var imgCursor = 0
                    for idx in parsed.slides.indices where idx > 0 && imgCursor < uploadedRawImages.count {
                        if parsed.slides[idx].table == nil && parsed.slides[idx].chart == nil
                            && parsed.slides[idx].layout != .metrics && parsed.slides[idx].layout != .twoColumn {
                            parsed.slides[idx].imageDataBase64 = uploadedRawImages[imgCursor]
                            imgCursor += 1
                        }
                    }
                }

                let inspected = WuMindPPTEngine.inspectAndRepair(
                    parsed,
                    expectedSlideCount: resolvedSlideCount,
                    hasSourceMaterials: hasSources,
                    webSearchUsed: actuallyUsedWeb
                )
                self.selectedSlideIndex = 0
                self.commitDeck(inspected, restored: false)
                Haptics.success()
            } catch is CancellationError {
                // Cleanly cancelled; any previously saved deck remains intact.
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.warning()
            }
        }
    }

    /// Regenerates ONE specific slide in place, re-runs quality inspection, and refreshes `.pptx` + PDF.
    func regenerateSingleSlide(at index: Int, instruction: String, using store: WuMindStore) {
        guard let currentDeck = deck, currentDeck.slides.indices.contains(index), !generating, regeneratingSlideID == nil else { return }
        let targetSlide = currentDeck.slides[index]
        let hasSources = !(currentDeck.sourceFiles ?? []).isEmpty || !sourceAttachments.isEmpty
        let stagedAttachments = sourceAttachments

        errorMessage = nil
        regeneratingSlideID = targetSlide.id
        stageLabel = "正在单页重做第 \(targetSlide.id) 页…"
        beginBackgroundProtection()

        generateTask?.cancel()
        generateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.regeneratingSlideID = nil
                self.stageLabel = ""
                self.endBackgroundProtection()
            }
            do {
                let sys = WuMindPPTEngine.singleSlideRegeneratePrompt(
                    deck: currentDeck,
                    slideIndex: index,
                    instruction: instruction,
                    hasSourceMaterials: hasSources
                )
                var userText = "请重做第 \(targetSlide.id) 页（原标题：\(targetSlide.title)）。"
                if !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    userText += "\n修改要求：\(instruction)"
                }
                if !stagedAttachments.isEmpty {
                    let excerpts = stagedAttachments.map {
                        "【资料：\($0.document.filename)】\n\(String($0.document.extractedText.prefix(4_000)))"
                    }.joined(separator: "\n\n")
                    userText += "\n\n参考资料：\n\(excerpts)"
                }

                let res = try await store.runStatelessChat(
                    messages: [AIProviderMessage(role: .user, text: userText)],
                    systemPrompt: sys,
                    deepThinking: false,
                    onAnswerDelta: { _ in }
                )
                try Task.checkCancellation()

                var updatedDeck = currentDeck
                let rebuiltSlide = WuMindPPTEngine.parseSingleSlide(from: res.answer, fallback: targetSlide)
                updatedDeck.slides[index] = rebuiltSlide
                let inspected = WuMindPPTEngine.inspectAndRepair(
                    updatedDeck,
                    expectedSlideCount: nil,
                    hasSourceMaterials: hasSources,
                    webSearchUsed: currentDeck.webSearchUsed ?? false
                )
                self.commitDeck(inspected, restored: false)
                Haptics.success()
                ToastCenter.shared.show("第 \(targetSlide.id) 页已重做并更新 .pptx", style: .success)
            } catch is CancellationError {
                // Cancelled cleanly
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.warning()
            }
        }
    }

    private func commitDeck(_ newDeck: WuMindPPTDeck, restored: Bool, asNewVersion: Bool = false) {
        var finalDeck = newDeck
        if finalDeck.logoDataBase64 == nil, let logo = companyLogoBase64 {
            finalDeck.logoDataBase64 = logo
        }
        deck = finalDeck
        let now = restored ? (savedAt ?? finalDeck.createdAt) : Date()
        savedAt = now
        restoredFromDisk = restored
        let pptxURL = Self.writePPTXFile(deck: finalDeck)
        exportedPPTXURL = pptxURL
        exportedPDFURL = WuMindPPTPDFRenderer.renderPDF(deck: finalDeck)
        if !restored {
            persistSnapshot(
                PersistedSnapshot(
                    topicPrompt: topicPrompt,
                    theme: finalDeck.theme,
                    slideCount: finalDeck.slides.count,
                    audience: finalDeck.audience ?? audience,
                    webSearchEnabled: webSearchEnabled,
                    deck: finalDeck,
                    savedAt: now
                )
            )
            // Persist real deliverable `.pptx` + editable deck JSON into private 「我的作品」
            let pptxData = pptxURL.flatMap { try? Data(contentsOf: $0) }
            let projectJSON = (try? JSONEncoder().encode(finalDeck)).flatMap { String(data: $0, encoding: .utf8) }
            if asNewVersion, let existingWorkID = currentWorkID {
                if let saved = WuMindWorksStore.shared.saveEditedVersion(
                    from: existingWorkID,
                    title: finalDeck.title,
                    prompt: topicPrompt.isEmpty ? finalDeck.subtitle : topicPrompt,
                    assetData: pptxData,
                    assetMime: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                    assetExtension: "pptx",
                    projectJSON: projectJSON
                ) {
                    currentWorkID = saved.id
                }
            } else {
                let work = WuMindWorksStore.shared.recordSubmittedTask(
                    workType: .ppt,
                    title: finalDeck.title,
                    prompt: topicPrompt.isEmpty ? finalDeck.subtitle : topicPrompt,
                    modelID: WuMindStore.shared.activeModelDisplayName,
                    params: [
                        "slides": "\(finalDeck.slides.count)",
                        "theme": finalDeck.theme.rawValue,
                        "audience": (finalDeck.audience ?? audience).rawValue,
                    ],
                    status: "in_progress",
                    progress: 80
                )
                if let done = WuMindWorksStore.shared.completeWork(
                    id: work.id,
                    title: finalDeck.title,
                    assetData: pptxData,
                    assetMime: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                    assetExtension: "pptx",
                    projectJSON: projectJSON
                ) {
                    currentWorkID = done.id
                }
            }
        }
    }

    private func persistSnapshot(_ snapshot: PersistedSnapshot) {
        guard let url = Self.snapshotURL(create: true),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func restoreLastDeckIfAvailable() {
        guard let url = Self.snapshotURL(create: false),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(PersistedSnapshot.self, from: data) else { return }
        topicPrompt = snapshot.topicPrompt
        theme = snapshot.theme
        slideCount = snapshot.slideCount
        audience = snapshot.audience
        webSearchEnabled = snapshot.webSearchEnabled
        savedAt = snapshot.savedAt
        commitDeck(snapshot.deck, restored: true)
    }

    private func beginBackgroundProtection() {
        endBackgroundProtection()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "WuMindPPTGeneration") { [weak self] in
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

    private static func snapshotURL(create: Bool) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = dir.appendingPathComponent("WuMindPPT", isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("last_deck.json")
    }

    private static func writePPTXFile(deck: WuMindPPTDeck) -> URL? {
        guard let data = try? WuMindPPTXExporter.make(deck: deck) else { return nil }
        let safe = sanitizedFilename(deck.title)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("wumind-pptx-\(deck.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("\(safe).pptx")
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return fileURL
        } catch {
            return nil
        }
    }

    static func sanitizedFilename(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let clean = raw.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "WUMIND_PPT" }
        return String(clean.prefix(32))
    }

    private static func performOptInWebSearch(query: String, store: WuMindStore) async -> WuMindAgentTools.ToolResult {
        if store.channel == .managed,
           store.hasGatewayURL,
           let token = Keychain.wumindGatewayUserToken {
            do {
                let res = try await WuMindGatewayClient().webSearch(
                    gatewayURL: store.gatewayBaseURL,
                    userToken: token,
                    query: query,
                    maxResults: 5,
                    depth: "basic"
                )
                let obs = WuMindAgentTools.formatSearchObservation(
                    query: query,
                    provider: "WUMIND · \(res.provider)",
                    results: res.results
                )
                return WuMindAgentTools.ToolResult(
                    succeeded: !res.results.isEmpty,
                    summary: "\(res.provider) 检索 \(res.results.count) 条公开资料",
                    observationText: obs,
                    extraCostYuan: res.costYuan
                )
            } catch {
                // Fall back to direct public search below
            }
        }
        let rawKey = Keychain.connectorToken(for: "dev.websearch")
        let tavilyKey = (rawKey?.hasPrefix("tvly-") == true) ? rawKey : nil
        let braveKey = (rawKey != nil && tavilyKey == nil) ? rawKey : nil
        return await WuMindAgentTools.directWebSearch(
            query: query,
            maxResults: 5,
            depth: "basic",
            tavilyKey: tavilyKey,
            braveKey: braveKey
        )
    }
}

/// Flagship WUMIND Autonomous AI PPT Studio:
/// One-click autonomous PowerPoint generation from a single sentence OR uploaded Word/PDF/Excel/Images,
/// native editable `.pptx` export (text + tables + live Excel-backed charts + speaker notes),
/// 1920×1080 PDF export, automated quality self-check, single-slide regeneration, inline editing,
/// and 1-tap iOS Share Sheet directly to WeChat / PowerPoint / WPS.
@MainActor
struct WuMindPPTStudioView: View {
    private struct TemplateStarter: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let prompt: String
        let icon: String
        let accent: Color
    }

    private static let starters: [TemplateStarter] = [
        .init(
            title: "8 页年终总结",
            subtitle: "一句话直出 · 不虚构数字",
            prompt: "做一份 8 页年终工作总结",
            icon: "person.text.rectangle.fill",
            accent: .teal
        ),
        .init(
            title: "季度经营复盘",
            subtitle: "可上传 Excel / PDF 出图表",
            prompt: "做一份 8 页季度经营复盘与下季度增长规划汇报，包含核心指标、问题拆解与行动计划",
            icon: "chart.bar.xaxis",
            accent: .blue
        ),
        .init(
            title: "技术架构汇报",
            subtitle: "痛点 · 对比表 · 演进路线",
            prompt: "做一份 10 页高可用架构升级方案汇报，面向技术与管理层，含现状痛点、对比表与分阶段路线图",
            icon: "cpu.fill",
            accent: .indigo
        ),
        .init(
            title: "招投标述标",
            subtitle: "亮点 · 交付保障 · 售后承诺",
            prompt: "做一份 10 页项目述标演示 PPT，面向客户评审，突出核心方案、交付排期与服务 SLA",
            icon: "doc.richtext.fill",
            accent: .purple
        ),
    ]

    private static let allowedUploadTypes: [UTType] = {
        var list: [UTType] = [.pdf, .commaSeparatedText, .plainText, .image]
        if let docx = UTType(filenameExtension: "docx") { list.append(docx) }
        if let xlsx = UTType(filenameExtension: "xlsx") { list.append(xlsx) }
        if let xls = UTType(filenameExtension: "xls") { list.append(xls) }
        if let md = UTType(filenameExtension: "md") { list.append(md) }
        return list
    }()

    @ObservedObject private var store = WuMindStore.shared
    @ObservedObject private var workflow = WuMindPPTWorkflowStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingFileImporter = false
    @State private var showingPhotoPicker = false
    @State private var showingLogoPicker = false
    @State private var showingHistory = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var pickedLogoItem: PhotosPickerItem?
    @State private var surgicalEditDraft = ""
    @State private var showingRegenSheet = false
    @State private var regenInstruction = ""
    @State private var editingSlideIndex: Int? = nil
    @State private var showQualityDetails = false
    @FocusState private var promptFocused: Bool

    private var isDark: Bool { colorScheme == .dark }
    private var canvasBg: Color {
        isDark ? Color(red: 0.03, green: 0.035, blue: 0.055) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.095, green: 0.105, blue: 0.142) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    private var activeModelLabel: String {
        store.channel == .managed ? store.managedSelectedModelID : store.selectedModelName
    }
    private var canTriggerGenerate: Bool {
        !workflow.generating
            && workflow.regeneratingSlideID == nil
            && (!workflow.topicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !workflow.sourceAttachments.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                controlStrip
                materialsCard
                executiveReportQuickBar

                if let errorMessage = workflow.errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(errorMessage).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if workflow.generating || workflow.regeneratingSlideID != nil {
                    generatingCard
                }

                if let currentDeck = workflow.deck {
                    surgicalSingleSlideEditCard
                    deckPreviewSection(currentDeck)
                } else if !workflow.generating {
                    starterSection
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(canvasBg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingComposer
        }
        .navigationTitle("AI 写 PPT 工坊")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Haptics.tap()
                    showingHistory = true
                } label: {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("ai.ppt.history")
            }
        }
        .sheet(isPresented: $showingHistory) {
            WuMindWorksView(initialFilter: .ppt, onReopenPPT: { reopened, workID in
                workflow.loadExternalDeck(reopened, workID: workID)
            })
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: Self.allowedUploadTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        .background(
            Color.clear
                .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedPhotoItem, matching: .images)
        )
        .background(
            Color.clear
                .photosPicker(isPresented: $showingLogoPicker, selection: $pickedLogoItem, matching: .images)
        )
        .onChange(of: pickedPhotoItem) { item in
            guard let item else { return }
            handlePickedPhoto(item)
        }
        .onChange(of: pickedLogoItem) { item in
            guard let item else { return }
            handlePickedLogo(item)
        }
        .sheet(isPresented: $showingRegenSheet) {
            singleSlideRegenSheet
                .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(
            get: { editingSlideIndex != nil },
            set: { if !$0 { editingSlideIndex = nil } }
        )) {
            if let idx = editingSlideIndex, let currentDeck = workflow.deck, currentDeck.slides.indices.contains(idx) {
                WuMindPPTSlideEditorSheet(slide: currentDeck.slides[idx]) { updated in
                    workflow.updateSlide(at: idx, mutated: updated)
                    editingSlideIndex = nil
                    ToastCenter.shared.show("已保存本页修改并同步更新 .pptx", style: .success)
                }
            }
        }
    }

    // MARK: - Top Control Strip (Zero Horizontal Overflow)

    private var controlStrip: some View {
        VStack(spacing: 8) {
            // Row 1: Model + Page Count + Audience (3 clean equal/compact items)
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.indigo)
                    Text(activeModelLabel)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                Menu {
                    ForEach([6, 8, 10, 12, 15], id: \.self) { count in
                        Button("\(count) 页") { workflow.slideCount = count }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(workflow.slideCount) 页")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .tint(.primary)

                Menu {
                    ForEach(WuMindPPTAudience.allCases) { aud in
                        Button("\(aud.title) · \(aud.guidance)") { workflow.audience = aud }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 10, weight: .bold))
                        Text(workflow.audience.title)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .tint(.primary)
            }

            // Row 2: 4-Theme Full-Width Switcher
            HStack(spacing: 6) {
                ForEach(WuMindPPTTheme.allCases) { item in
                    let selected = workflow.theme == item
                    Button {
                        Haptics.tap()
                        workflow.applyTheme(item)
                    } label: {
                        Text(item.title)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selected ? themeAccent(item).opacity(0.20) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .foregroundStyle(selected ? themeAccent(item) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            .accessibilityIdentifier("ai.ppt.theme")
        }
    }

    // MARK: - Optional Source Materials (Word / PDF / Excel / Image) & Opt-In Web Search

    private var materialsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    showingFileImporter = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.badge.plus")
                            .font(.caption.weight(.bold))
                        Text("上传 Word / PDF / Excel")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.indigo.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(workflow.generating)
                .accessibilityIdentifier("ai.ppt.uploadFile")

                Button {
                    Haptics.tap()
                    showingPhotoPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.caption.weight(.bold))
                        Text("上传图片")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(workflow.generating)
                .accessibilityIdentifier("ai.ppt.uploadPhoto")

                Button {
                    Haptics.tap()
                    workflow.webSearchEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: workflow.webSearchEnabled ? "globe.badge.chevron.backward" : "globe")
                            .font(.caption2.weight(.bold))
                        Text(workflow.webSearchEnabled ? "联网开" : "联网关")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(workflow.webSearchEnabled ? .teal : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        (workflow.webSearchEnabled ? Color.teal : Color.secondary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(workflow.generating)
                .accessibilityIdentifier("ai.ppt.webSearch")
            }

            if workflow.importingAttachment {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("正在解析上传资料（正文/表格/OCR）…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !workflow.sourceAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(workflow.sourceAttachments) { item in
                            HStack(spacing: 5) {
                                Image(systemName: item.iconName)
                                    .font(.caption2)
                                    .foregroundStyle(item.tintColor)
                                Text(item.document.filename)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: 140, alignment: .leading)
                                Button {
                                    workflow.removeAttachment(item.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(item.tintColor.opacity(0.11), in: Capsule())
                        }
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(.teal)
                    Text("资料将发往：\(store.activeDataDestinationLabel) · 数字自动溯源，缺项标「待补」")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(10)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    // MARK: - Starters

    private var starterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                        .shadow(color: .orange.opacity(0.32), radius: 14, y: 6)
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                Text("一句话直出可编辑 PowerPoint (.pptx)")
                    .font(.headline.weight(.bold))
                Text("自动规划结构、撰写内容与演讲备注、生成可编辑表格与图表、体检防溢出防遮挡，一键导出 .pptx 与 PDF 分享微信")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            Text("一键快捷体验")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.starters) { starter in
                    Button {
                        Haptics.tap()
                        workflow.topicPrompt = starter.prompt
                        promptFocused = true
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Image(systemName: starter.icon)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(starter.accent)
                            Spacer(minLength: 4)
                            Text(starter.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(starter.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                        .padding(12)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Live Generation Card

    private var generatingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(workflow.stageLabel.isEmpty ? "正在全自动生成 \(workflow.slideCount) 页可编辑 PowerPoint…" : workflow.stageLabel)
                    .font(.caption.weight(.bold))
                Text("模型：\(activeModelLabel) · 已接收 \(workflow.liveStreamingChars) 字符 · 切后台不中断")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("停止") {
                workflow.cancelGeneration()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.red)
        }
        .padding(13)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Deck Preview, Quality Self-Check, Single-Slide Controls & Real .pptx / PDF Export

    private func deckPreviewSection(_ currentDeck: WuMindPPTDeck) -> some View {
        let safeIdx = max(0, min(currentDeck.slides.count - 1, workflow.selectedSlideIndex))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentDeck.title)
                        .font(.headline.weight(.bold))
                    HStack(spacing: 6) {
                        Text("\(currentDeck.slides.count) 页 · \(currentDeck.theme.title)")
                        if workflow.restoredFromDisk {
                            Text("· 已自动恢复进度")
                                .foregroundStyle(.teal)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(safeIdx + 1) / \(currentDeck.slides.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(cardBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(cardBorder, lineWidth: 1))
            }

            // Automated Quality Inspection Report Card
            if let report = currentDeck.qualityReport {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showQualityDetails.toggle() }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.teal)
                            Text(report.summaryBadge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: showQualityDetails ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if showQualityDetails {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("• 防溢出检查：修复 \(report.overflowFixedCount) 处 · 防遮挡：修复 \(report.overlapFixedCount) 处 · 空白页：修复 \(report.blankSlidesFixedCount) 处 · 数据一致性：修复 \(report.dataConsistencyFixedCount) 处")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(Array(report.fixesApplied.prefix(6).enumerated()), id: \.offset) { _, note in
                                Text("  - \(note)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let webSum = workflow.lastWebSourcesSummary {
                                Text("• 联网资料：\(webSum)")
                                    .font(.caption2)
                                    .foregroundStyle(.teal)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(10)
                .background(Color.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.teal.opacity(0.25), lineWidth: 1))
                .accessibilityIdentifier("ai.ppt.qualityReport")
            }

            // 16:9 Interactive Swipeable Slide Stage
            TabView(selection: $workflow.selectedSlideIndex) {
                ForEach(Array(currentDeck.slides.enumerated()), id: \.offset) { idx, slide in
                    slideCanvas(slide: slide, deck: currentDeck, index: idx + 1, total: currentDeck.slides.count)
                        .tag(idx)
                        .padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .shadow(color: .black.opacity(isDark ? 0.42 : 0.14), radius: 14, y: 6)

            // Primary Export CTA: Real Native Editable `.pptx` Share to WeChat / PowerPoint / WPS!
            if let pptxURL = workflow.exportedPPTXURL {
                ShareLink(item: pptxURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up.fill")
                        Text("导出可编辑 PowerPoint (.pptx) · 分享微信")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: .orange.opacity(0.28), radius: 10, y: 4)
                }
                .accessibilityIdentifier("ai.ppt.sharePptx")
            }

            // Secondary Row: PDF Export + Single-Slide Regenerate + Edit Slide + Copy Outline
            HStack(spacing: 8) {
                if let pdfURL = workflow.exportedPDFURL {
                    ShareLink(item: pdfURL) {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.fill")
                            Text("导出 PDF")
                                .font(.caption2.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                        .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("ai.ppt.sharePdf")
                }

                Button {
                    Haptics.tap()
                    regenInstruction = ""
                    showingRegenSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("重做本页")
                            .font(.caption2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .disabled(workflow.generating || workflow.regeneratingSlideID != nil)
                .accessibilityIdentifier("ai.ppt.regenSlide")

                Button {
                    Haptics.tap()
                    editingSlideIndex = safeIdx
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                        Text("编辑本页")
                            .font(.caption2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                    .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.ppt.editSlide")

                Button {
                    UIPasteboard.general.string = WuMindPPTEngine.exportMarkdownOutline(currentDeck)
                    Haptics.success()
                    ToastCenter.shared.show("已复制全部 PPT Markdown 大纲", style: .success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制大纲")
            }

            // Speaker Notes, Source Citations & Pending Items for active slide
            if currentDeck.slides.indices.contains(safeIdx) {
                let slide = currentDeck.slides[safeIdx]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("第 \(slide.id) 页演讲备注（已写入 .pptx 备注栏）", systemImage: "text.bubble.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        Spacer()
                        Text(slide.layout.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    Text(slide.speakerNotes.isEmpty ? "围绕本页核心要点展开说明即可。" : slide.speakerNotes)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let cites = slide.citations, !cites.isEmpty {
                        Label("原文/来源追溯：\(cites.joined(separator: " · "))", systemImage: "link")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let pending = slide.pendingItems, !pending.isEmpty {
                        Label("待补数据：\(pending.joined(separator: "；"))", systemImage: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            }

            // Subtle reset button
            Button("清空当前成品，新建另一套 PPT", role: .destructive) {
                workflow.clearDeckAndReset()
            }
            .font(.caption2.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
    }

    // MARK: - Live 16:9 Slide Canvas (Text + Native Table Preview + Live Chart Preview + Image)

    private func slideCanvas(slide: WuMindPPTDeck.Slide, deck: WuMindPPTDeck, index: Int, total: Int) -> some View {
        let palette = WuMindPPTPDFRenderer.palette(for: deck.theme)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [palette.bgStart, palette.bgEnd], startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 24, height: 4)
                    Spacer()
                    Text("\(index) / \(total)")
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.subText)
                }

                if slide.layout == .cover {
                    Spacer(minLength: 4)
                    Text(slide.title)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(2)
                    Text(deck.subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.subText)
                        .lineLimit(2)
                    if let aud = deck.audience {
                        Text("受众：\(aud.title)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    Spacer(minLength: 4)
                } else {
                    Text(slide.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)

                    if let chart = slide.chart {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(slide.bullets.prefix(3).enumerated()), id: \.offset) { _, b in
                                    Text("• \(b)")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(palette.primaryText.opacity(0.92))
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            miniChartPreview(chart: chart, palette: palette)
                                .frame(width: 165)
                        }
                    } else if let table = slide.table {
                        miniTablePreview(table: table, palette: palette)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            if let metric = slide.highlightMetric, !metric.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(metric)
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(palette.accent)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                    if let label = slide.highlightLabel, !label.isEmpty {
                                        Text(label)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(palette.subText)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(7)
                                .frame(width: 90, alignment: .leading)
                                .background(palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(slide.bullets.prefix(4).enumerated()), id: \.offset) { _, bullet in
                                    HStack(alignment: .top, spacing: 5) {
                                        Circle()
                                            .fill(palette.accent)
                                            .frame(width: 4.5, height: 4.5)
                                            .padding(.top, 4.5)
                                        Text(bullet)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(palette.primaryText.opacity(0.92))
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let b64 = slide.imageDataBase64,
                               let raw = Data(base64Encoded: b64),
                               let uiImg = UIImage(data: raw) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 82)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let cites = slide.citations, let first = cites.first {
                    Text("出处：\(first)")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(palette.accent.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.accent.opacity(0.28), lineWidth: 1))
    }

    private func miniTablePreview(table: WuMindPPTDeck.TableData, palette: WuMindPPTPDFRenderer.SlidePalette) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(Array(table.headers.prefix(4).enumerated()), id: \.offset) { _, h in
                    Text(h)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(palette.accent.opacity(0.75))
                }
            }
            ForEach(Array(table.rows.prefix(4).enumerated()), id: \.offset) { rIdx, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.prefix(4).enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 8))
                            .foregroundStyle(cell.contains("待补") ? palette.accent : palette.primaryText.opacity(0.9))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2.5)
                            .background(palette.primaryText.opacity(rIdx % 2 == 0 ? 0.06 : 0.11))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func miniChartPreview(chart: WuMindPPTDeck.ChartData, palette: WuMindPPTPDFRenderer.SlidePalette) -> some View {
        let firstSeriesObj = chart.series.first
        let firstSeries = firstSeriesObj?.values ?? []
        let isPct = firstSeriesObj?.isPercentage == true
        let maxVal = max(1.0, firstSeries.compactMap { $0.map { abs($0) } }.max() ?? 1.0)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chart.title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(chart.kind.title)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(palette.accent)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(zip(chart.categories.prefix(5), firstSeries.prefix(5)).enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: 2) {
                        if let v = pair.1 {
                            let ratio = CGFloat(max(0.08, abs(v) / maxVal))
                            Text(WuMindPPTEngine.formatChartValue(v, isPercentage: isPct))
                                .font(.system(size: 7).monospacedDigit())
                                .foregroundStyle(palette.subText)
                                .lineLimit(1)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(palette.accent)
                                .frame(height: max(8, 44 * ratio))
                        } else {
                            Text("—")
                                .font(.system(size: 7))
                                .foregroundStyle(palette.subText.opacity(0.6))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(palette.subText.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                                .frame(height: 8)
                        }
                        Text(pair.0)
                            .font(.system(size: 7))
                            .foregroundStyle(palette.subText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 68, alignment: .bottom)
        }
        .padding(7)
        .background(palette.primaryText.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Single Slide Regeneration Sheet

    private var singleSlideRegenSheet: some View {
        NavigationStack {
            Form {
                Section("单页精修要求（可选）") {
                    TextField("例如：改成柱状图 / 精简为 3 条要点 / 补充风险提示", text: $regenInstruction, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button {
                        let idx = max(0, min((workflow.deck?.slides.count ?? 1) - 1, workflow.selectedSlideIndex))
                        showingRegenSheet = false
                        workflow.regenerateSingleSlide(at: idx, instruction: regenInstruction, using: store)
                    } label: {
                        Label("立即重做第 \(workflow.selectedSlideIndex + 1) 页并刷新 .pptx", systemImage: "wand.and.stars")
                            .fontWeight(.semibold)
                    }
                } footer: {
                    Text("只重新生成当前这一页，保留整套其他页面，并自动重新体检与导出可编辑 .pptx。")
                }
            }
            .navigationTitle("单页重做")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingRegenSheet = false }
                }
            }
        }
    }

    // MARK: - Bottom Floating Prompt Bar

    private var floatingComposer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("一句话生成整套可编辑 PPT（如：做一份 8 页年终工作总结）…", text: $workflow.topicPrompt, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .focused($promptFocused)
                    .submitLabel(.done)
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    .accessibilityIdentifier("ai.ppt.prompt")

                Button {
                    promptFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    workflow.startAutonomousGeneration(using: store)
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                canTriggerGenerate
                                    ? LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.secondary.opacity(0.28), Color.secondary.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 38, height: 38)
                        if workflow.generating {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canTriggerGenerate)
                .accessibilityIdentifier("ai.ppt.generate")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.10), radius: 14, y: 4)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                colors: [canvasBg.opacity(0), canvasBg.opacity(0.92), canvasBg],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Attachment Ingestion (Word / PDF / Excel / Image)

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            if (err as NSError).code != NSUserCancelledError {
                ToastCenter.shared.show("未能读取所选文件", style: .error)
            }
        case .success(let urls):
            guard !urls.isEmpty else { return }
            workflow.importingAttachment = true
            Task { @MainActor in
                defer { workflow.importingAttachment = false }
                var added = 0
                var lastErr: String?
                for url in urls.prefix(4) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let ext = url.pathExtension.lowercased()
                        let doc: WuMindAttachmentParser.ExtractedDocument
                        if ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
                            doc = try await WuMindAttachmentHelper.extractImageAttachment(data: data, filename: url.lastPathComponent)
                        } else {
                            doc = try WuMindAttachmentParser.extract(data: data, filename: url.lastPathComponent)
                        }
                        workflow.addAttachment(doc, rawData: data)
                        added += 1
                    } catch {
                        lastErr = (error as? LocalizedError)?.errorDescription ?? "无法解析 \(url.lastPathComponent)"
                    }
                }
                if added > 0 {
                    ToastCenter.shared.show("已载入 \(added) 份资料，点下方即可直接生成可编辑 .pptx", style: .success)
                } else if let lastErr {
                    ToastCenter.shared.show(lastErr, style: .error)
                }
            }
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) {
        workflow.importingAttachment = true
        Task { @MainActor in
            defer {
                workflow.importingAttachment = false
                pickedPhotoItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    ToastCenter.shared.show("未能读取所选图片", style: .error)
                    return
                }
                let stamp = Int(Date().timeIntervalSince1970) % 10_000
                let doc = try await WuMindAttachmentHelper.extractImageAttachment(data: data, filename: "配图_\(stamp).jpg")
                workflow.addAttachment(doc)
                ToastCenter.shared.show("已添加图片素材，将自动配入幻灯片", style: .success)
            } catch {
                ToastCenter.shared.show((error as? LocalizedError)?.errorDescription ?? "图片解析失败", style: .error)
            }
        }
    }

    private func handlePickedLogo(_ item: PhotosPickerItem) {
        Task { @MainActor in
            defer { pickedLogoItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else {
                ToastCenter.shared.show("未能读取公司 Logo 图片", style: .error)
                return
            }
            let maxSide: CGFloat = 512
            let scale = min(1.0, maxSide / max(1, max(img.size.width, img.size.height)))
            let target = CGSize(width: max(1, img.size.width * scale), height: max(1, img.size.height * scale))
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1.0
            let scaled = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
                img.draw(in: CGRect(origin: .zero, size: target))
            }
            if let png = scaled.pngData() {
                workflow.companyLogoBase64 = png.base64EncodedString()
                ToastCenter.shared.show("已载入公司 Logo（导出 .pptx 将自动嵌入封面与页眉）", style: .success)
            }
        }
    }

    /// Quick bar for Brand Logo + One-Click 10-Slide Executive Report (8-min pacing, Excel-backed charts)
    private var executiveReportQuickBar: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                showingLogoPicker = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: workflow.companyLogoBase64 != nil ? "checkmark.seal.fill" : "building.2.crop.circle")
                        .font(.caption.weight(.bold))
                    Text(workflow.companyLogoBase64 != nil ? "已载入 Logo" : "公司 Logo")
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(workflow.companyLogoBase64 != nil ? .green : .teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background((workflow.companyLogoBase64 != nil ? Color.green : Color.teal).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ai.ppt.uploadLogo")

            Button {
                Haptics.tap()
                workflow.buildExecutiveReportFromMaterials()
                ToastCenter.shared.show("已按 10 页 / 8 分钟管理层框架生成可编辑 .pptx", style: .success)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.caption.weight(.bold))
                    Text("直出 10 页管理层经营报告（8 分钟）")
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(workflow.generating)
            .accessibilityIdentifier("ai.ppt.buildExecutiveReport")
        }
    }

    /// Surgical single-slide editor card: mutates ONLY target slide while preserving all other slides untouched!
    private var surgicalSingleSlideEditCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("单页精准修改（不动其他页）", systemImage: "wand.and.rays")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
                Spacer()
                Button("示例：第 5 页改折线图") {
                    surgicalEditDraft = "第 5 页改为季度趋势折线图，沿用原数据和配色"
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.indigo)
            }

            HStack(spacing: 8) {
                TextField("如：第 5 页改为季度趋势折线图，沿用原数据和配色", text: $surgicalEditDraft)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("ai.ppt.surgicalInput")
                Button("精准修改") {
                    let cmd = surgicalEditDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cmd.isEmpty else { return }
                    if let summary = workflow.applySurgicalEdit(instruction: cmd) {
                        surgicalEditDraft = ""
                        Haptics.success()
                        ToastCenter.shared.show(summary, style: .success)
                    }
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(surgicalEditDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("ai.ppt.surgicalApply")
            }

            if let summary = workflow.lastSurgicalEditSummary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("ai.ppt.surgicalSummary")
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.indigo.opacity(0.28), lineWidth: 1))
    }

    private func themeAccent(_ t: WuMindPPTTheme) -> Color {
        switch t {
        case .midnightTech: return .cyan
        case .executiveBlue: return .blue
        case .minimalIvory: return .indigo
        case .easternInk: return .teal
        }
    }
}

// MARK: - Inline Slide Editor Sheet (Text + Notes + Editable Chart Values)

private struct WuMindPPTSlideEditorSheet: View {
    let original: WuMindPPTDeck.Slide
    let onSave: (WuMindPPTDeck.Slide) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var bulletsText: String
    @State private var speakerNotes: String
    @State private var chartSeriesValues: [[String]]

    init(slide: WuMindPPTDeck.Slide, onSave: @escaping (WuMindPPTDeck.Slide) -> Void) {
        self.original = slide
        self.onSave = onSave
        _title = State(initialValue: slide.title)
        _bulletsText = State(initialValue: slide.bullets.joined(separator: "\n"))
        _speakerNotes = State(initialValue: slide.speakerNotes)
        let rows = (slide.chart?.series ?? []).map { ser in
            ser.values.map { val -> String in
                guard let val else { return "" }
                return WuMindPPTEngine.formatChartNumber(val)
            }
        }
        _chartSeriesValues = State(initialValue: rows)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题与正文要点（每行一条）") {
                    TextField("本页标题", text: $title)
                    TextEditor(text: $bulletsText)
                        .frame(minHeight: 110)
                }

                if let chart = original.chart {
                    Section("可编辑图表数据（\(chart.title)）") {
                        ForEach(Array(chart.series.enumerated()), id: \.offset) { sIdx, ser in
                            Text(ser.name)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.indigo)
                            ForEach(Array(chart.categories.enumerated()), id: \.offset) { cIdx, cat in
                                HStack {
                                    Text(cat).font(.caption)
                                    Spacer()
                                    if chartSeriesValues.indices.contains(sIdx),
                                       chartSeriesValues[sIdx].indices.contains(cIdx) {
                                        TextField("留空表示缺失", text: $chartSeriesValues[sIdx][cIdx])
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 110)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("演讲备注（同步写入 .pptx Notes）") {
                    TextEditor(text: $speakerNotes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("编辑第 \(original.id) 页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = original
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.bullets = bulletsText
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        updated.speakerNotes = speakerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                        if var ch = updated.chart {
                            for sIdx in ch.series.indices where chartSeriesValues.indices.contains(sIdx) {
                                for cIdx in ch.series[sIdx].values.indices where chartSeriesValues[sIdx].indices.contains(cIdx) {
                                    let raw = chartSeriesValues[sIdx][cIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                                    if raw.isEmpty {
                                        ch.series[sIdx].values[cIdx] = nil
                                    } else if let v = Double(raw.replacingOccurrences(of: ",", with: "")) {
                                        ch.series[sIdx].values[cIdx] = v
                                    }
                                }
                            }
                            updated.chart = ch
                        }
                        onSave(updated)
                    }
                }
            }
        }
    }
}

// MARK: - 1920×1080 Native PDF Renderer (Retained Alongside Real `.pptx`)

@MainActor
enum WuMindPPTPDFRenderer {
    struct SlidePalette {
        let bgStart: Color
        let bgEnd: Color
        let primaryText: Color
        let subText: Color
        let accent: Color
        let uiBgStart: UIColor
        let uiBgEnd: UIColor
        let uiText: UIColor
        let uiSubText: UIColor
        let uiAccent: UIColor
    }

    static func palette(for t: WuMindPPTTheme) -> SlidePalette {
        switch t {
        case .midnightTech:
            return .init(
                bgStart: Color(red: 0.05, green: 0.07, blue: 0.14),
                bgEnd: Color(red: 0.11, green: 0.12, blue: 0.25),
                primaryText: .white,
                subText: Color.white.opacity(0.70),
                accent: Color(red: 0.25, green: 0.80, blue: 0.98),
                uiBgStart: UIColor(red: 0.05, green: 0.07, blue: 0.14, alpha: 1),
                uiBgEnd: UIColor(red: 0.11, green: 0.12, blue: 0.25, alpha: 1),
                uiText: .white,
                uiSubText: UIColor.white.withAlphaComponent(0.72),
                uiAccent: UIColor(red: 0.25, green: 0.80, blue: 0.98, alpha: 1)
            )
        case .executiveBlue:
            return .init(
                bgStart: Color(red: 0.06, green: 0.14, blue: 0.30),
                bgEnd: Color(red: 0.10, green: 0.24, blue: 0.48),
                primaryText: .white,
                subText: Color.white.opacity(0.75),
                accent: Color(red: 0.98, green: 0.74, blue: 0.26),
                uiBgStart: UIColor(red: 0.06, green: 0.14, blue: 0.30, alpha: 1),
                uiBgEnd: UIColor(red: 0.10, green: 0.24, blue: 0.48, alpha: 1),
                uiText: .white,
                uiSubText: UIColor.white.withAlphaComponent(0.75),
                uiAccent: UIColor(red: 0.98, green: 0.74, blue: 0.26, alpha: 1)
            )
        case .minimalIvory:
            return .init(
                bgStart: Color(red: 0.985, green: 0.985, blue: 0.975),
                bgEnd: Color(red: 0.94, green: 0.95, blue: 0.97),
                primaryText: Color(red: 0.10, green: 0.12, blue: 0.18),
                subText: Color(red: 0.36, green: 0.40, blue: 0.48),
                accent: Color(red: 0.26, green: 0.36, blue: 0.88),
                uiBgStart: UIColor(red: 0.985, green: 0.985, blue: 0.975, alpha: 1),
                uiBgEnd: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1),
                uiText: UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1),
                uiSubText: UIColor(red: 0.36, green: 0.40, blue: 0.48, alpha: 1),
                uiAccent: UIColor(red: 0.26, green: 0.36, blue: 0.88, alpha: 1)
            )
        case .easternInk:
            return .init(
                bgStart: Color(red: 0.08, green: 0.13, blue: 0.13),
                bgEnd: Color(red: 0.14, green: 0.22, blue: 0.20),
                primaryText: Color(red: 0.96, green: 0.95, blue: 0.91),
                subText: Color(red: 0.76, green: 0.82, blue: 0.78),
                accent: Color(red: 0.40, green: 0.82, blue: 0.68),
                uiBgStart: UIColor(red: 0.08, green: 0.13, blue: 0.13, alpha: 1),
                uiBgEnd: UIColor(red: 0.14, green: 0.22, blue: 0.20, alpha: 1),
                uiText: UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1),
                uiSubText: UIColor(red: 0.76, green: 0.82, blue: 0.78, alpha: 1),
                uiAccent: UIColor(red: 0.40, green: 0.82, blue: 0.68, alpha: 1)
            )
        }
    }

    static func renderPDF(deck: WuMindPPTDeck) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let palette = palette(for: deck.theme)

        let data = renderer.pdfData { ctx in
            let total = deck.slides.count
            for (idx, slide) in deck.slides.enumerated() {
                ctx.beginPage()
                let cg = ctx.cgContext

                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: [palette.uiBgStart.cgColor, palette.uiBgEnd.cgColor] as CFArray,
                    locations: [0, 1]
                ) {
                    cg.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: 0),
                        end: CGPoint(x: pageRect.width, y: pageRect.height),
                        options: []
                    )
                }

                palette.uiAccent.setFill()
                UIBezierPath(roundedRect: CGRect(x: 110, y: 74, width: 120, height: 12), cornerRadius: 6).fill()

                let pageNumAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold),
                    .foregroundColor: palette.uiSubText,
                ]
                ("\(idx + 1) / \(total)" as NSString).draw(at: CGPoint(x: 1710, y: 66), withAttributes: pageNumAttrs)

                if slide.layout == .cover {
                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 80, weight: .heavy),
                        .foregroundColor: palette.uiText,
                    ]
                    (slide.title as NSString).draw(in: CGRect(x: 110, y: 300, width: 1700, height: 240), withAttributes: titleAttrs)
                    let subAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 38, weight: .medium),
                        .foregroundColor: palette.uiSubText,
                    ]
                    (deck.subtitle as NSString).draw(in: CGRect(x: 110, y: 550, width: 1620, height: 140), withAttributes: subAttrs)
                } else {
                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                        .foregroundColor: palette.uiText,
                    ]
                    (slide.title as NSString).draw(in: CGRect(x: 110, y: 115, width: 1700, height: 100), withAttributes: titleAttrs)

                    if let chart = slide.chart {
                        drawPDFBullets(slide.bullets.prefix(4), in: CGRect(x: 110, y: 255, width: 640, height: 640), palette: palette)
                        drawPDFChart(chart, in: CGRect(x: 790, y: 255, width: 1020, height: 640), palette: palette)
                    } else if let table = slide.table {
                        drawPDFTable(table, in: CGRect(x: 110, y: 260, width: 1700, height: 620), palette: palette)
                    } else {
                        var bulletLeftX: CGFloat = 110
                        var bulletWidth: CGFloat = 1700
                        if let metric = slide.highlightMetric, !metric.isEmpty {
                            let cardRect = CGRect(x: 110, y: 260, width: 440, height: 320)
                            palette.uiAccent.withAlphaComponent(0.15).setFill()
                            UIBezierPath(roundedRect: cardRect, cornerRadius: 28).fill()
                            let mAttrs: [NSAttributedString.Key: Any] = [
                                .font: UIFont.systemFont(ofSize: 80, weight: .black),
                                .foregroundColor: palette.uiAccent,
                            ]
                            (metric as NSString).draw(in: CGRect(x: 142, y: 310, width: 376, height: 120), withAttributes: mAttrs)
                            if let label = slide.highlightLabel, !label.isEmpty {
                                let lAttrs: [NSAttributedString.Key: Any] = [
                                    .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                                    .foregroundColor: palette.uiSubText,
                                ]
                                (label as NSString).draw(in: CGRect(x: 142, y: 450, width: 376, height: 100), withAttributes: lAttrs)
                            }
                            bulletLeftX = 590
                            bulletWidth = 1220
                        } else if let b64 = slide.imageDataBase64,
                                  let raw = Data(base64Encoded: b64),
                                  let img = UIImage(data: raw) {
                            bulletWidth = 960
                            let imgRect = CGRect(x: 1120, y: 260, width: 690, height: 560)
                            UIBezierPath(roundedRect: imgRect, cornerRadius: 24).addClip()
                            img.draw(in: imgRect)
                            cg.resetClip()
                        }
                        drawPDFBullets(slide.bullets.prefix(5), in: CGRect(x: bulletLeftX, y: 265, width: bulletWidth, height: 630), palette: palette)
                    }
                }

                if let cites = slide.citations, !cites.isEmpty {
                    let citeAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                        .foregroundColor: palette.uiAccent,
                    ]
                    ("出处：\(cites.prefix(2).joined(separator: " | "))" as NSString).draw(
                        in: CGRect(x: 110, y: 940, width: 1700, height: 42),
                        withAttributes: citeAttrs
                    )
                }

                let footAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                    .foregroundColor: palette.uiSubText.withAlphaComponent(0.65),
                ]
                ("WUMIND AI PPT Studio · \(deck.title)" as NSString).draw(at: CGPoint(x: 110, y: 1005), withAttributes: footAttrs)
            }
        }

        let safe = WuMindPPTWorkflowStore.sanitizedFilename(deck.title)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("wumind-pdf-\(deck.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("\(safe).pdf")
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return fileURL
        } catch {
            return nil
        }
    }

    private static func drawPDFBullets(_ bullets: ArraySlice<String>, in rect: CGRect, palette: SlidePalette) {
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 34, weight: .medium),
            .foregroundColor: palette.uiText.withAlphaComponent(0.94),
        ]
        var y = rect.minY
        let step = min(115, rect.height / CGFloat(max(1, bullets.count)))
        for b in bullets {
            palette.uiAccent.setFill()
            UIBezierPath(ovalIn: CGRect(x: rect.minX, y: y + 14, width: 14, height: 14)).fill()
            (b as NSString).draw(
                in: CGRect(x: rect.minX + 34, y: y, width: rect.width - 34, height: step - 10),
                withAttributes: bulletAttrs
            )
            y += step
        }
    }

    private static func drawPDFTable(_ table: WuMindPPTDeck.TableData, in rect: CGRect, palette: SlidePalette) {
        let cols = max(1, table.headers.count)
        let rows = 1 + table.rows.count
        let colW = rect.width / CGFloat(cols)
        let rowH = min(92, rect.height / CGFloat(max(1, rows)))

        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let cellAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: palette.uiText,
        ]

        for c in 0..<cols {
            let cellRect = CGRect(x: rect.minX + CGFloat(c) * colW, y: rect.minY, width: colW - 4, height: rowH - 4)
            palette.uiAccent.withAlphaComponent(0.75).setFill()
            UIBezierPath(roundedRect: cellRect, cornerRadius: 8).fill()
            (table.headers[c] as NSString).draw(in: cellRect.insetBy(dx: 14, dy: 16), withAttributes: headAttrs)
        }
        for (rIdx, row) in table.rows.prefix(6).enumerated() {
            let y = rect.minY + CGFloat(rIdx + 1) * rowH
            for c in 0..<cols {
                let text = c < row.count ? row[c] : "【待补】"
                let cellRect = CGRect(x: rect.minX + CGFloat(c) * colW, y: y, width: colW - 4, height: rowH - 4)
                palette.uiText.withAlphaComponent(rIdx % 2 == 0 ? 0.07 : 0.13).setFill()
                UIBezierPath(roundedRect: cellRect, cornerRadius: 6).fill()
                (text as NSString).draw(in: cellRect.insetBy(dx: 14, dy: 16), withAttributes: cellAttrs)
            }
        }
    }

    private static func drawPDFChart(_ chart: WuMindPPTDeck.ChartData, in rect: CGRect, palette: SlidePalette) {
        palette.uiText.withAlphaComponent(0.06).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 24).fill()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: palette.uiText,
        ]
        let titleText = chart.unit.map { "\(chart.title)（\($0)）" } ?? chart.title
        (titleText as NSString).draw(in: CGRect(x: rect.minX + 36, y: rect.minY + 28, width: rect.width - 72, height: 48), withAttributes: titleAttrs)

        let firstSeriesObj = chart.series.first
        let series = firstSeriesObj?.values ?? []
        let isPct = firstSeriesObj?.isPercentage == true
        let count = min(chart.categories.count, series.count)
        guard count > 0 else { return }
        let maxVal = max(1.0, series.prefix(count).compactMap { $0.map { abs($0) } }.max() ?? 1.0)
        let plotRect = CGRect(x: rect.minX + 50, y: rect.minY + 110, width: rect.width - 100, height: rect.height - 200)
        let slotW = plotRect.width / CGFloat(count)
        let barW = min(90, slotW * 0.56)

        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: palette.uiSubText,
        ]
        for i in 0..<count {
            let x = plotRect.minX + CGFloat(i) * slotW + (slotW - barW) / 2
            if let v = series[i] {
                let ratio = CGFloat(max(0.05, abs(v) / maxVal))
                let barH = plotRect.height * ratio
                let barRect = CGRect(x: x, y: plotRect.maxY - barH, width: barW, height: barH)
                palette.uiAccent.setFill()
                UIBezierPath(roundedRect: barRect, cornerRadius: 10).fill()

                let valStr = WuMindPPTEngine.formatChartValue(v, isPercentage: isPct) as NSString
                valStr.draw(in: CGRect(x: x - 12, y: barRect.minY - 34, width: barW + 24, height: 30), withAttributes: lblAttrs)
            } else {
                ("—" as NSString).draw(in: CGRect(x: x - 12, y: plotRect.maxY - 36, width: barW + 24, height: 30), withAttributes: lblAttrs)
            }
            (chart.categories[i] as NSString).draw(in: CGRect(x: x - 16, y: plotRect.maxY + 14, width: barW + 32, height: 34), withAttributes: lblAttrs)
        }
    }
}
