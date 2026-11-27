import Foundation
import UIKit

@MainActor
enum WuMindChatBuildService {
    struct Artifact {
        let title: String
        let bytes: Data
        let mime: String
        let fileExtension: String
        var projectJSON: String? = nil
        var remoteWorkID: String? = nil
        let detail: String
    }

    enum BuildError: LocalizedError {
        case invalidArtifact
        case unavailable(String)
        case providerFailed(String)
        var errorDescription: String? {
            switch self {
            case .invalidArtifact: return "模型没有返回完整的作品。这次没有生成可下载文件。"
            case .unavailable(let message), .providerFailed(let message): return message
            }
        }
    }

    enum MediaRoute {
        case directImage(AIImageTool.Model, String?)
        case directVideo(AIVideoTool.Model, String?, Int)
        case managedImage(WuMindCatalogModel, String)
        case managedVideo(WuMindCatalogModel, String, Int, String)

        var id: String {
            switch self {
            case .directImage(let m, _): return m.id
            case .directVideo(let m, _, _): return m.id
            case .managedImage(let m, _), .managedVideo(let m, _, _, _): return m.id
            }
        }

        var confirmation: String {
            switch self {
            case .directImage(let m, _): return "自带 API · \(m.displayName) · 1 张"
            case .directVideo(let m, _, let seconds): return "自带 API · \(m.displayName) · \(seconds) 秒"
            case .managedImage(let m, _): return "内置网关 · \(m.displayName) · 1 张"
            case .managedVideo(let m, _, let seconds, _): return "内置网关 · \(m.displayName) · \(seconds) 秒"
            }
        }
    }

    static func mediaRoute(for tool: WuMindChatBuild, using store: WuMindStore, hasReference: Bool, prompt: String) throws -> MediaRoute? {
        guard tool == .image || tool == .video else { return nil }
        if tool == .video && hasReference {
            throw BuildError.unavailable("对话内视频目前支持文生视频。需要参考图时，从高级编辑打开视频工坊。")
        }
        if store.channel == .managed {
            let gateway = store.gatewayBaseURL
            guard store.hasGatewayURL, Keychain.wumindGatewayUserToken != nil else {
                throw BuildError.unavailable("请先连接并登录 WuMind 网关。")
            }
            if tool == .image {
                let models = hasReference ? store.enabledManagedImageEditModels : store.enabledManagedImageModels.filter(\.supportsTextToImage)
                guard let model = models.first else { throw BuildError.unavailable("内置目录没有开通相应生图模型。") }
                return .managedImage(model, gateway)
            }
            guard let model = store.enabledManagedVideoModels.first else { throw BuildError.unavailable("内置目录没有开通视频模型。") }
            let params = model.supportedParams
            let seconds = WuMindChatBuild.supportedVideoSeconds(
                requested: WuMindChatBuild.requestedVideoSeconds(in: prompt),
                allowed: params?.seconds ?? [],
                fallback: params?.defaultSeconds ?? params?.seconds?.first ?? 5
            )
            let size = params?.defaultSize ?? params?.sizes?.first ?? "1280x720"
            return .managedVideo(model, gateway, seconds, size)
        }
        let provider = store.activeProviderForDisplay.multiProvider
        let configured: (AIProvider) -> Bool = { Keychain.providerChatAPIKey($0)?.isEmpty == false }
        if tool == .image {
            let models = AIImageTool.models.filter { configured($0.provider) && (!hasReference || $0.supportsReferenceImage) }
            guard let model = models.first(where: { $0.provider == provider }) ?? models.first else {
                throw BuildError.unavailable("当前没有配置支持这项生图能力的 API。")
            }
            return .directImage(model, AIProviderEndpoints.baseURL(for: model.provider))
        }
        let relay = AIProviderToolHTTP.isOpenAICompatibleRelay(AIProviderEndpoints.baseURL(for: .openAI))
        let models = AIVideoTool.availableBuiltInModels(openAIUsesRelay: relay).filter { configured($0.provider) }
        guard let model = models.first(where: { $0.provider == provider }) ?? models.first else {
            throw BuildError.unavailable("当前没有配置支持视频生成的 API。")
        }
        let seconds = WuMindChatBuild.supportedVideoSeconds(
            requested: WuMindChatBuild.requestedVideoSeconds(in: prompt), allowed: model.supportedDurations, fallback: model.defaultDuration
        )
        return .directVideo(model, AIProviderEndpoints.baseURL(for: model.provider), seconds)
    }

    static func generateMedia(
        _ route: MediaRoute, prompt: String, attachments: [WuMindAttachment], idempotency: String,
        jobAccepted: @escaping @MainActor @Sendable (String) -> Void, status: (String) -> Void
    ) async throws -> Artifact {
        let title = String(prompt.prefix(42))
        let reference: AIImageTool.ReferenceImage? = attachments.first.flatMap { item in
            guard let image = item.document.makeAIImageAttachment(), let bytes = Data(base64Encoded: image.base64Data) else { return nil }
            return .init(data: bytes, mimeType: image.mimeType, filename: item.document.filename)
        }
        func imageArtifact(_ data: Data, remote: String? = nil) throws -> Artifact {
            guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else { throw BuildError.invalidArtifact }
            return Artifact(title: title, bytes: jpeg, mime: "image/jpeg", fileExtension: "jpg", remoteWorkID: remote,
                            detail: "图片已生成，可以在对话中打开或分享。")
        }
        switch route {
        case .directImage(let model, let base):
            guard let key = Keychain.providerChatAPIKey(model.provider) else { throw BuildError.unavailable("生图连接已失效。") }
            let data = try await AIImageTool().generate(
                model: model, apiKey: key, prompt: prompt, referenceImage: reference, options: .init(customBaseURL: base)
            )
            return try imageArtifact(data)
        case .directVideo(let model, let base, let seconds):
            guard let key = Keychain.providerChatAPIKey(model.provider) else { throw BuildError.unavailable("视频连接已失效。") }
            let data = try await AIVideoTool().generate(
                model: model, apiKey: key, prompt: prompt,
                options: .init(durationSeconds: seconds, customBaseURL: base)
            ) { update in
                if let id = update.jobID, !id.isEmpty { await jobAccepted(id) }
            }
            return Artifact(title: title, bytes: data, mime: "video/mp4", fileExtension: "mp4", detail: "视频已生成，可以在对话中打开或分享。")
        case .managedImage(let model, let gateway):
            guard let token = Keychain.wumindGatewayUserToken else { throw BuildError.unavailable("请重新登录网关。") }
            let response = try await WuMindGatewayClient().generateManagedImages(
                gatewayURL: gateway, userToken: token, modelID: model.id, prompt: prompt, quality: "low",
                referenceImage: reference, idempotencyKey: idempotency
            )
            guard let first = response.data.first, let data = Data(base64Encoded: first.b64_json) else { throw BuildError.invalidArtifact }
            return try imageArtifact(data, remote: response.workID)
        case .managedVideo(let model, let gateway, let seconds, let size):
            guard let token = Keychain.wumindGatewayUserToken else { throw BuildError.unavailable("请重新登录网关。") }
            let client = WuMindGatewayClient()
            var job = try await client.submitManagedVideo(gatewayURL: gateway, userToken: token, modelID: model.id,
                                                           prompt: prompt, seconds: seconds, size: size, idempotencyKey: idempotency)
            jobAccepted(job.id)
            for _ in 0..<48 {
                try Task.checkCancellation()
                if job.isCompleted {
                    let data = try await client.downloadManagedVideoContent(gatewayURL: gateway, userToken: token, jobID: job.id)
                    guard AIVideoTool.isValidMP4(data) else { throw BuildError.invalidArtifact }
                    return Artifact(title: title, bytes: data, mime: "video/mp4", fileExtension: "mp4", remoteWorkID: job.workID,
                                    detail: "视频已生成，可以在对话中打开或分享。")
                }
                if job.isFailed || ["cancelled", "canceled", "expired"].contains(job.status) {
                    throw BuildError.providerFailed(job.error ?? "视频服务商明确返回任务未完成。")
                }
                status("视频正在渲染")
                try await Task.sleep(nanoseconds: 5_000_000_000)
                job = try await client.fetchManagedVideoStatus(gatewayURL: gateway, userToken: token, jobID: job.id)
            }
            throw BuildError.unavailable("视频仍在处理。请到「作品」查看原任务，不要重复提交。")
        }
    }

    static func generate(
        _ tool: WuMindChatBuild, question: String, prompt: String, attachments: [WuMindAttachment],
        using store: WuMindStore, status: (String) -> Void
    ) async throws -> Artifact {
        let names = attachments.map(\.document.filename)
        let label = String(question.prefix(42))
        let slideCount = WuMindPPTEngine.extractRequestedSlideCount(from: question, fallback: 8)
        let pptProfile = WuMindPPTEngine.chatDesignProfile(for: question)
        let type: WuMindSpatialSceneType = {
            if question.contains("游戏") || question.contains("地图") || question.contains("漫游") { return .gameScene }
            if question.contains("室内") || question.contains("户型") { return .interiorSpace }
            if question.contains("故宫") || question.contains("宫殿") { return .imperialComplex }
            if question.contains("别墅") || question.contains("建筑") { return .villaBuilding }
            return .modernPavilion
        }()
        let mode: WuMindSpatialCreationMode = names.isEmpty ? .textDescription : .uploadAndText
        let systemPrompt: String
        switch tool {
        case .image, .video:
            throw BuildError.unavailable("未选中可用的媒体连接。")
        case .code:
            systemPrompt = """
            创建可独立下载的单文件网页。只返回从 <!doctype html> 到 </html> 的完整 HTML。
            CSS 与交互脚本写在页面里，离线可用，不引入外部依赖，不请求密钥、不上传任何数据。
            示例数据明确标为示例，不编造实时来源。不要声称已经运行、验证或发布。
            """
        case .ppt:
            systemPrompt = WuMindPPTEngine.systemPrompt(
                slideCount: slideCount, theme: pptProfile.theme, audience: pptProfile.audience,
                hasSourceMaterials: !names.isEmpty, webSearchEnabled: false
            ) + """

            先确定希望受众记住的结论，再按“结论、依据、行动”组织内容。每页写一个具体信息，不重复同样的要点。
            中间页要按内容改变版式，比较用双栏、决策与计划用表格，有可追溯数值才用图表。不要用通用话术或空白页凑满页数。
            若资料没有可靠数值，不要为了满足图表数量而虚构数字，改用定性对比或行动表。
            """
        case .spatial3d:
            systemPrompt = WuMindSpatial3DEngine.sceneGenerationSystemPrompt(
                prompt: question, sceneType: type, creationMode: mode,
                hasReferenceImages: attachments.contains { $0.document.makeAIImageAttachment() != nil },
                extractedDrawingText: nil
            )
        case .tender:
            systemPrompt = """
            按所附招标要求写可编辑的中文 Markdown 标书草案，列出响应项和源文定位。
            对未提供的资质、金额、证明文件或业绩只标「待补」，不要伪造。
            没有招标文件时明确按模板起草，不能声称已逐条响应真实要求。
            """
        }
        status(tool == .ppt ? "正在设计演示文稿" : "正在构建\(tool.title.replacingOccurrences(of: "创建", with: ""))")
        let nativeImages = store.activeModelCapabilities.visionAttachments
            ? attachments.compactMap { $0.document.makeAIImageAttachment() } : []
        let (reasoning, answer) = try await store.runStatelessChat(
            messages: [.init(role: .user, text: prompt, images: nativeImages)],
            systemPrompt: systemPrompt, deepThinking: false
        )
        _ = reasoning
        try Task.checkCancellation()
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BuildError.invalidArtifact }
        status("正在整理文件")
        switch tool {
        case .image, .video:
            throw BuildError.invalidArtifact
        case .code:
            guard let html = WuMindChatBuild.standaloneHTML(answer) else { throw BuildError.invalidArtifact }
            return Artifact(title: label, bytes: Data(html.utf8), mime: "text/html", fileExtension: "html",
                            detail: "已生成 HTML 文件。可导出在浏览器打开，WuMind 内不会执行生成的脚本。")
        case .ppt:
            status("正在检查页数、重复内容和排版")
            guard let deck = WuMindPPTEngine.validatedChatDeck(
                from: answer, fallbackTopic: label, theme: pptProfile.theme, expectedSlideCount: slideCount,
                audience: pptProfile.audience, sourceFiles: names
            ) else {
                throw BuildError.unavailable("模型没有返回足够的可用页面，这次未导出 PPT，也没有自动重试。")
            }
            let project = String(data: try JSONEncoder().encode(deck), encoding: .utf8)
            var summary = deck.slides.count == slideCount
                ? "已生成 \(slideCount) 页可编辑 PPTX。"
                : "已生成 \(deck.slides.count)/\(slideCount) 页可编辑草稿，未用占位页凑数。"
            if let quality = deck.qualityReport { summary += "\n\(quality.summaryBadge)" }
            return Artifact(title: deck.title, bytes: try WuMindPPTXExporter.make(deck: deck),
                            mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                            fileExtension: "pptx", projectJSON: project, detail: summary)
        case .spatial3d:
            let scene = WuMindSpatial3DEngine.parseOrSynthesizeScene(
                rawLLMOutput: answer, sourcePrompt: question, preferredType: type,
                creationMode: mode, referenceFilenames: names
            )
            let project = String(data: try WuMindSpatial3DEngine.encodeProjectJSON(scene), encoding: .utf8)
            return Artifact(title: scene.title, bytes: try WuMindSpatialGLBExporter.exportGLB(scene: scene),
                            mime: "model/gltf-binary", fileExtension: "glb", projectJSON: project,
                            detail: "已生成概念 3D 场景和 GLB；尺寸仍需按图纸核对。")
        case .tender:
            return Artifact(title: label, bytes: Data(answer.utf8), mime: "text/markdown", fileExtension: "md",
                            detail: "已生成标书草案，资质、报价和响应项需人工核对。")
        }
    }
}
