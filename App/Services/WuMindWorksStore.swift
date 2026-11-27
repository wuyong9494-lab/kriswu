import Foundation
import UIKit

/// Account-scoped, cloud-synced persistent work record for WUMIND 「我的作品」
/// across Image, Video, PPT, and 3D studios.
/// Stores real deliverable assets + editable project JSON (never temporary expiring URLs!).
struct WuMindLocalWork: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var ownerID: String
    var workType: WuMindWorkType
    var title: String
    var prompt: String
    var modelID: String
    var params: [String: String]
    var status: String              // queued | in_progress | completed | failed
    var progress: Int               // 0...100
    var videoJobOrigin: WuMindVideoJobOrigin? = nil
    var upstreamJobID: String?
    var idempotencyKey: String?
    var errorMessage: String?
    var thumbnailFileName: String?
    var assetFileName: String?
    var assetMime: String?
    var projectFileName: String?
    var hasRemoteAsset: Bool
    var hasRemoteProject: Bool
    var timing: WuMindCloudWorkTiming?
    var versionNumber: Int
    var parentWorkID: String?
    var createdAt: Date
    var updatedAt: Date
    var syncedToCloud: Bool
    var assetSyncState: WuMindAssetSyncState? = nil
    var assetSizeBytes: Int? = nil
    var assetSHA256: String? = nil
    var lastAssetUploadError: String? = nil

    var isCompleted: Bool { status == "completed" }
    var isFailed: Bool { status == "failed" }
    var isStatusUnknown: Bool { status == "status_unknown" }
    var isInProgress: Bool { status == "queued" || status == "in_progress" || status == "status_unknown" }
    var taskChainID: String? { params["taskChainID"] }

    var resolvedAssetSyncState: WuMindAssetSyncState {
        if let explicit = assetSyncState { return explicit }
        if hasRemoteAsset && syncedToCloud { return .synced }
        return .localOnly
    }

    var formattedAssetSize: String? {
        guard let bytes = assetSizeBytes, bytes > 0 else { return nil }
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
        if bytes >= 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024.0)
        }
        return "\(bytes) B"
    }

    var statusLabel: String {
        switch status {
        case "completed": return "已完成"
        case "failed": return "失败"
        case "status_unknown": return "暂时无法确认"
        case "in_progress": return progress > 0 ? "生成中 \(progress)%" : "生成中"
        default: return "排队中"
        }
    }
}

/// Unified private 「我的作品」 & Per-Studio 「历史」 manager.
/// - Strictly partitioned per registered WUMIND account (`WM-XXXXXX` or local device owner).
/// - Saves immediately on task submit so closing the sheet, leaving the app, or switching devices never loses results.
/// - Reopening / refreshing queries status read-only (NEVER resubmits or double-charges).
/// - Edits create new versions (`versionNumber + 1`) with isolated R2 upload state (`pending_upload` -> `synced`).
/// - Local deletes persist in a per-account pending-delete tombstone queue until cloud DELETE is confirmed.
@MainActor
final class WuMindWorksStore: ObservableObject {
    static let shared = WuMindWorksStore()

    @Published private(set) var works: [WuMindLocalWork] = []
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncError: String? = nil
    @Published private(set) var pendingDeleteCount: Int = 0
    @Published private(set) var pendingDeleteError: String? = nil
    @Published private(set) var activeOwnerID: String = "local"

    private let fm = FileManager.default
    private var migratedOwners: Set<String> = []
    private var pendingDeletes = WuMindPendingDeleteQueue()

    private init() {
        reloadForCurrentAccount()
    }

    var currentOwnerID: String {
        WuMindAccountStorageScope.resolvedOwnerID(
            managedAccountID: WuMindStore.shared.managedAccountID,
            externalWuMindUserID: AppAccountManager.shared.externalProfile?.wumindUserID,
            externalProfileID: AppAccountManager.shared.externalProfile?.id
        )
    }

    func works(of type: WuMindWorkType?) -> [WuMindLocalWork] {
        guard let type else { return works }
        return works.filter { $0.workType == type }
    }

    func works(inTaskChain chainID: String) -> [WuMindLocalWork] {
        works.filter { $0.taskChainID == chainID }
    }

    func versions(for work: WuMindLocalWork) -> [WuMindLocalWork] {
        let rootID = work.parentWorkID ?? work.id
        return works
            .filter { $0.id == rootID || $0.parentWorkID == rootID }
            .sorted { $0.versionNumber > $1.versionNumber }
    }

    func reloadForCurrentAccount() {
        let owner = currentOwnerID
        activeOwnerID = owner
        pendingDeletes = loadPendingDeletes(for: owner)
        pendingDeleteCount = pendingDeletes.count
        pendingDeleteError = pendingDeletes.isEmpty ? nil : "有 \(pendingDeletes.count) 项删除待同步到云端，联网后将自动补发。"
        works = loadIndex(for: owner)
            .filter { !pendingDeletes.shouldSkipRemoteWork($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
        if !migratedOwners.contains(owner) {
            migratedOwners.insert(owner)
            migrateLegacyLocalWorksIfNeeded(owner: owner)
        }
    }

    // MARK: - Immediate Persistence on Task Submit / Completion / Failure

    @discardableResult
    func recordSubmittedTask(
        id: String = "WRK-\(UUID().uuidString.prefix(12).uppercased())",
        workType: WuMindWorkType,
        title: String,
        prompt: String,
        modelID: String,
        params: [String: String] = [:],
        status: String = "in_progress",
        progress: Int = 10,
        upstreamJobID: String? = nil,
        idempotencyKey: String? = nil,
        syncToCloud: Bool = true
    ) -> WuMindLocalWork {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        let now = Date()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var enrichedParams = params
        if enrichedParams["taskChainID"] == nil {
            if let activeConvo = WuMindStore.shared.activeConversationID {
                enrichedParams["taskChainID"] = "chat-\(activeConvo.uuidString)"
            } else {
                enrichedParams["taskChainID"] = "work-\(id)"
            }
        }
        let work = WuMindLocalWork(
            id: id,
            ownerID: owner,
            workType: workType,
            title: cleanTitle.isEmpty ? String(prompt.prefix(40)) : String(cleanTitle.prefix(80)),
            prompt: prompt,
            modelID: modelID,
            params: enrichedParams,
            status: status,
            progress: progress,
            upstreamJobID: upstreamJobID,
            idempotencyKey: idempotencyKey,
            errorMessage: nil,
            thumbnailFileName: nil,
            assetFileName: nil,
            assetMime: nil,
            projectFileName: nil,
            hasRemoteAsset: false,
            hasRemoteProject: false,
            timing: nil,
            versionNumber: 1,
            parentWorkID: nil,
            createdAt: now,
            updatedAt: now,
            syncedToCloud: false
        )
        upsertLocal(work)
        if syncToCloud {
            Task { await pushCreateOrUpdateToCloud(work, assetData: nil, previewBase64: nil, projectJSON: nil, createNewVersion: false) }
        }
        return work
    }

    @discardableResult
    func completeWork(
        id: String,
        title: String? = nil,
        assetData: Data? = nil,
        assetMime: String? = nil,
        assetExtension: String? = nil,
        previewImageData: Data? = nil,
        projectJSON: String? = nil,
        timing: WuMindCloudWorkTiming? = nil,
        remoteWorkID: String? = nil,
        syncToCloud: Bool = true
    ) -> WuMindLocalWork? {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        guard let idx = works.firstIndex(where: { $0.id == id || (remoteWorkID != nil && $0.id == remoteWorkID) }) else {
            return nil
        }

        var item = works[idx]
        if let remoteWorkID, !remoteWorkID.isEmpty, item.id != remoteWorkID {
            item.id = remoteWorkID
        }
        if let title, !title.isEmpty { item.title = String(title.prefix(80)) }
        item.status = "completed"
        item.progress = 100
        item.errorMessage = nil
        if let assetMime { item.assetMime = assetMime }
        if let timing { item.timing = timing }
        item.updatedAt = Date()

        var previewB64: String? = nil
        if let rawAsset = assetData, !rawAsset.isEmpty {
            let ext = assetExtension ?? fileExtension(forMime: assetMime, type: item.workType)
            let fname = "\(item.id).\(ext)"
            if writeFile(rawAsset, name: fname, owner: owner) {
                item.assetFileName = fname
                item.assetSizeBytes = rawAsset.count
            }
            if previewImageData == nil && item.workType == .image {
                if let thumb = makeThumbnailJPEG(from: rawAsset, maxDimension: 480) {
                    let tname = "\(item.id)_thumb.jpg"
                    if writeFile(thumb, name: tname, owner: owner) {
                        item.thumbnailFileName = tname
                    }
                    previewB64 = thumb.base64EncodedString()
                }
            }
        }
        if let previewImageData, !previewImageData.isEmpty {
            let thumb = makeThumbnailJPEG(from: previewImageData, maxDimension: 480) ?? previewImageData
            let tname = "\(item.id)_thumb.jpg"
            if writeFile(thumb, name: tname, owner: owner) {
                item.thumbnailFileName = tname
            }
            previewB64 = thumb.base64EncodedString()
        }
        if let projectJSON, !projectJSON.isEmpty {
            let pname = "\(item.id)_project.json"
            if writeFile(Data(projectJSON.utf8), name: pname, owner: owner) {
                item.projectFileName = pname
            }
        }

        let hasBinaryToUpload = (assetData?.isEmpty == false)
        let canSyncCloud = syncToCloud && WuMindStore.shared.hasGatewayURL && (WuMindStore.shared.managedSessionToken?.isEmpty == false)
        item.assetSyncState = hasBinaryToUpload ? (canSyncCloud ? .uploading : .localOnly) : .localOnly
        item.lastAssetUploadError = nil
        item.syncedToCloud = false

        works[idx] = item
        works.sort { $0.updatedAt > $1.updatedAt }
        saveIndex(for: owner)

        if syncToCloud {
            Task {
                await pushCreateOrUpdateToCloud(
                    item,
                    assetData: assetData,
                    previewBase64: previewB64,
                    projectJSON: projectJSON,
                    createNewVersion: false
                )
            }
        }
        return item
    }

    func updateProgress(id: String, status: String, progress: Int, upstreamJobID: String? = nil, videoJobOrigin: WuMindVideoJobOrigin? = nil) {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        guard let idx = works.firstIndex(where: { $0.id == id }) else { return }
        if works[idx].isStatusUnknown && status != "status_unknown" { works[idx].errorMessage = nil }
        works[idx].status = status
        works[idx].progress = max(0, min(100, progress))
        if let upstreamJobID, !upstreamJobID.isEmpty {
            works[idx].upstreamJobID = upstreamJobID
            if let videoJobOrigin, videoJobOrigin.jobID == upstreamJobID { works[idx].videoJobOrigin = videoJobOrigin }
        }
        works[idx].updatedAt = Date()
        saveIndex(for: owner)
    }

    func failWork(id: String, errorMessage: String, syncToCloud: Bool = true) {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        guard let idx = works.firstIndex(where: { $0.id == id }) else { return }
        works[idx].status = "failed"
        works[idx].progress = 0
        works[idx].errorMessage = String(errorMessage.prefix(400))
        works[idx].updatedAt = Date()
        let snapshot = works[idx]
        saveIndex(for: owner)
        if syncToCloud {
            Task { await pushCreateOrUpdateToCloud(snapshot, assetData: nil, previewBase64: nil, projectJSON: nil, createNewVersion: false) }
        }
    }

    /// Marks an already-submitted remote video job as `status_unknown` ("暂时无法确认") when status polling
    /// hits a network/timeout error — NEVER marks it failed and preserves the original `upstreamJobID` for
    /// zero-duplicate, zero-double-charge status recovery.
    func markStatusUnconfirmed(id: String, upstreamJobID: String?, message: String) {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        guard let idx = works.firstIndex(where: { $0.id == id }) else { return }
        works[idx].status = "status_unknown"
        if let upstreamJobID, !upstreamJobID.isEmpty {
            works[idx].upstreamJobID = upstreamJobID
        }
        works[idx].errorMessage = String(message.prefix(400))
        works[idx].updatedAt = Date()
        saveIndex(for: owner)
    }

    /// Saves an edited revision as a NEW version (v2, v3, ...) while keeping the original version completely intact!
    /// Uses a deterministic fixed versionWorkID & idempotencyKey and marks `assetSyncState = .pendingUpload` ("待同步")
    /// until its own R2 upload finishes — NEVER inheriting parent v1's remote asset!
    @discardableResult
    func saveEditedVersion(
        from parentWorkID: String,
        title: String? = nil,
        prompt: String? = nil,
        assetData: Data? = nil,
        assetMime: String? = nil,
        assetExtension: String? = nil,
        previewImageData: Data? = nil,
        projectJSON: String? = nil
    ) -> WuMindLocalWork? {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        guard let parent = works.first(where: { $0.id == parentWorkID }) else { return nil }
        let rootID = parent.parentWorkID ?? parent.id
        let maxVer = works
            .filter { $0.id == rootID || $0.parentWorkID == rootID }
            .map(\.versionNumber)
            .max() ?? parent.versionNumber

        let newID = "WRK-V\(maxVer + 1)-\(UUID().uuidString.prefix(10).uppercased())"
        let versionIdemKey = "ver-\(newID)"
        let now = Date()
        let canSyncCloud = WuMindStore.shared.hasGatewayURL && (WuMindStore.shared.managedSessionToken?.isEmpty == false)
        let hasBinary = (assetData?.isEmpty == false)
        var child = WuMindLocalWork(
            id: newID,
            ownerID: owner,
            workType: parent.workType,
            title: title ?? parent.title,
            prompt: prompt ?? parent.prompt,
            modelID: parent.modelID,
            params: parent.params,
            status: "completed",
            progress: 100,
            upstreamJobID: nil,
            idempotencyKey: versionIdemKey,
            errorMessage: nil,
            thumbnailFileName: parent.thumbnailFileName,
            assetFileName: nil,
            assetMime: assetMime ?? parent.assetMime,
            projectFileName: nil,
            hasRemoteAsset: false,
            hasRemoteProject: false,
            timing: nil,
            versionNumber: maxVer + 1,
            parentWorkID: rootID,
            createdAt: now,
            updatedAt: now,
            syncedToCloud: false,
            assetSyncState: hasBinary ? (canSyncCloud ? .pendingUpload : .localOnly) : .localOnly,
            assetSizeBytes: assetData?.count
        )

        var previewB64: String? = nil
        if let raw = assetData, !raw.isEmpty {
            let ext = assetExtension ?? fileExtension(forMime: child.assetMime, type: child.workType)
            let fname = "\(newID).\(ext)"
            if writeFile(raw, name: fname, owner: owner) {
                child.assetFileName = fname
            }
        }
        if let prev = previewImageData, !prev.isEmpty {
            let thumb = makeThumbnailJPEG(from: prev, maxDimension: 480) ?? prev
            let tname = "\(newID)_thumb.jpg"
            if writeFile(thumb, name: tname, owner: owner) {
                child.thumbnailFileName = tname
            }
            previewB64 = thumb.base64EncodedString()
        }
        if let projectJSON, !projectJSON.isEmpty {
            let pname = "\(newID)_project.json"
            if writeFile(Data(projectJSON.utf8), name: pname, owner: owner) {
                child.projectFileName = pname
            }
        }

        upsertLocal(child)
        Task {
            await pushVersionToCloud(
                parentID: parent.id,
                localChild: child,
                assetData: assetData,
                previewBase64: previewB64,
                projectJSON: projectJSON
            )
        }
        return child
    }

    func deleteWork(id: String) {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        if let removed = works.first(where: { $0.id == id }) {
            removeFileIfExists(removed.thumbnailFileName, owner: owner)
            removeFileIfExists(removed.assetFileName, owner: owner)
            removeFileIfExists(removed.projectFileName, owner: owner)
        }
        works.removeAll { $0.id == id }
        saveIndex(for: owner)

        let gw = WuMindStore.shared.gatewayBaseURL
        let hasCloudAuth = WuMindStore.shared.hasGatewayURL && (WuMindStore.shared.managedSessionToken?.isEmpty == false)
        // Persist a pending-delete tombstone immediately so cloud sync NEVER resurrects this work
        // if the DELETE request fails offline or times out.
        if hasCloudAuth {
            pendingDeletes.enqueue(id)
            savePendingDeletes(for: owner)
            Task {
                await self.attemptCloudDelete(workID: id, owner: owner, gatewayURL: gw)
            }
        }
    }

    /// Retries all queued pending-delete tombstones until the gateway confirms each deletion (200/204/404).
    func flushPendingDeletes() async {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        let gw = WuMindStore.shared.gatewayBaseURL
        guard WuMindStore.shared.hasGatewayURL,
              let token = WuMindStore.shared.managedSessionToken, !token.isEmpty else {
            return
        }
        let ids = pendingDeletes.allPendingIDs
        guard !ids.isEmpty else { return }
        for workID in ids {
            await attemptCloudDelete(workID: workID, owner: owner, gatewayURL: gw, tokenOverride: token)
        }
    }

    private func attemptCloudDelete(
        workID: String,
        owner: String,
        gatewayURL: String,
        tokenOverride: String? = nil
    ) async {
        guard let token = tokenOverride ?? WuMindStore.shared.managedSessionToken, !token.isEmpty else { return }
        do {
            try await WuMindGatewayClient().deleteWork(gatewayURL: gatewayURL, userToken: token, workID: workID)
            if activeOwnerID == owner {
                pendingDeletes.confirmDeleted(workID)
                savePendingDeletes(for: owner)
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if activeOwnerID == owner {
                pendingDeletes.recordFailure(workID, error: msg)
                savePendingDeletes(for: owner)
                pendingDeleteError = "云端删除待同步（\(pendingDeletes.count) 项）：\(msg)，恢复联网后会自动补发。"
            }
        }
    }

    // MARK: - Read-Only Cloud Sync & On-Demand Full Asset Fetch (Zero Resubmit / Zero Double Charge)

    func syncFromCloud(type: WuMindWorkType? = nil) async {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        let wmStore = WuMindStore.shared
        guard wmStore.hasGatewayURL,
              let token = WuMindStore.shared.managedSessionToken, !token.isEmpty else {
            return
        }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        // 1. Always flush pending-delete tombstones FIRST so deleted works are purged on server & never reappear!
        await flushPendingDeletes()

        // 2. Paginate through ALL pages (limit=80 per page, up to 15 pages = 1,200 works) so >80 works sync completely!
        do {
            let client = WuMindGatewayClient()
            var offset = 0
            let pageLimit = 80
            let maxPages = 15
            for _ in 0..<maxPages {
                let page = try await client.listWorksPage(
                    gatewayURL: wmStore.gatewayBaseURL,
                    userToken: token,
                    type: type,
                    limit: pageLimit,
                    offset: offset
                )
                guard !Task.isCancelled, currentOwnerID == owner, activeOwnerID == owner else { return }
                for rw in page.works {
                    if pendingDeletes.shouldSkipRemoteWork(rw.id) { continue }
                    mergeRemoteWork(rw, owner: owner)
                }
                let hasMore = page.hasMore ?? (page.works.count >= pageLimit)
                guard hasMore, !page.works.isEmpty else { break }
                offset = page.nextOffset ?? (offset + page.works.count)
            }
            works.removeAll { pendingDeletes.shouldSkipRemoteWork($0.id) }
            works.sort { $0.updatedAt > $1.updatedAt }
            saveIndex(for: owner)
        } catch {
            lastSyncError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var recoveringVideoJobs: Set<String> = []

    /// Only original gateway-assigned jobs may be recovered. No submission or new billing request.
    func reconcileBackgroundVideos(preferredWorkIDs: [String] = []) async {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        let preferred = Set(preferredWorkIDs)
        let studio = AIVideoStudioSessionStore.shared
        let studioJob = studio.isGenerating ? studio.activeJobID : nil
        let candidates = works.filter {
            if let studioJob, $0.upstreamJobID == studioJob { return false }
            return WuMindBackgroundVideoRecovery.canQuery(
                jobID: $0.upstreamJobID, channel: $0.params["channel"],
                hasLocalAsset: localAssetURL(for: $0) != nil, status: $0.status
            ) && $0.workType == .video
        }
        let ordered = preferred.isEmpty
            ? candidates.filter { $0.isInProgress || !$0.hasRemoteAsset }
            : candidates.filter { preferred.contains($0.id) }
        var next = Array(ordered.prefix(3))
        // A bounded foreground follow-up keeps a recently resumed task moving without a permanent timer.
        for delay in [0, 5, 15] {
            guard !next.isEmpty, !Task.isCancelled, currentOwnerID == owner else { return }
            if delay > 0 {
                do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000) }
                catch { return }
            }
            var pending: [WuMindLocalWork] = []
            for work in next {
                guard !Task.isCancelled, currentOwnerID == owner else { return }
                if let updated = await refreshInProgressVideoWork(work), updated.isInProgress, !updated.isStatusUnknown {
                    pending.append(updated)
                }
            }
            next = pending
        }
    }

    /// Recover by GET against the original job ID, including after returning from lock screen.
    func refreshInProgressVideoWork(
        _ work: WuMindLocalWork, client: WuMindGatewayClient = .init(),
        sessionToken: @MainActor () -> String? = { WuMindStore.shared.managedSessionToken }
    ) async -> WuMindLocalWork? {
        guard let work = works.first(where: { $0.id == work.id }) else { return nil }
        guard work.workType == .video, let jobID = work.upstreamJobID,
              WuMindBackgroundVideoRecovery.canQuery(
                jobID: jobID, channel: work.params["channel"],
                hasLocalAsset: localAssetURL(for: work) != nil, status: work.status
              ) else { return work }
        let wmStore = WuMindStore.shared
        let owner = work.ownerID
        let gateway = wmStore.gatewayBaseURL
        guard currentOwnerID == owner, activeOwnerID == owner else { return nil }
        guard let origin = work.videoJobOrigin,
              origin.matches(gateway: gateway, accountID: wmStore.managedAccountID, jobID: jobID) else {
            let reason = work.videoJobOrigin == nil
                ? "此记录缺少原网关或账号标识，无法安全查询。"
                : "请切回提交视频时使用的网关和账号，再查询原任务。"
            if work.errorMessage != reason {
                markStatusUnconfirmed(id: work.id, upstreamJobID: jobID, message: reason)
            }
            return works.first { $0.id == work.id }
        }
        guard wmStore.hasGatewayURL, let token = sessionToken(), !token.isEmpty,
              recoveringVideoJobs.insert(jobID).inserted else { return work }
        defer { recoveringVideoJobs.remove(jobID) }
        func requestStillCurrent() -> Bool {
            !Task.isCancelled && currentOwnerID == owner && activeOwnerID == owner
                && origin.matches(gateway: wmStore.gatewayBaseURL, accountID: wmStore.managedAccountID, jobID: jobID)
                && sessionToken() == token
                && works.contains { $0.id == work.id && $0.upstreamJobID == jobID && localAssetURL(for: $0) == nil }
        }
        do {
            guard let st = try await WuMindBackgroundVideoRecovery.fetchOriginalStatus(
                origin: origin, gateway: gateway, accountID: wmStore.managedAccountID,
                jobID: jobID, token: token, client: client
            ), requestStillCurrent(), st.id == jobID else { return nil }
            if st.isCompleted {
                let mp4 = try await client.downloadManagedVideoContent(gatewayURL: gateway, userToken: token, jobID: jobID)
                guard requestStillCurrent() else { return nil }
                if AIVideoTool.isValidMP4(mp4),
                   let saved = completeWork(id: work.id, assetData: mp4, assetMime: "video/mp4", assetExtension: "mp4", syncToCloud: false),
                   localAssetURL(for: saved) != nil {
                    return saved
                }
                markStatusUnconfirmed(id: work.id, upstreamJobID: jobID, message: "视频已生成，但尚未保存到本机。请重新查询原任务。")
            } else if st.isFailed {
                failWork(id: work.id, errorMessage: st.error ?? "视频生成失败", syncToCloud: false)
            } else {
                updateProgress(id: work.id, status: "in_progress", progress: st.progress ?? work.progress, upstreamJobID: jobID)
            }
        } catch {
            guard requestStillCurrent() else { return nil }
            markStatusUnconfirmed(id: work.id, upstreamJobID: jobID,
                                  message: "暂时无法确认云端进度，请稍后恢复查询。不会重新提交任务。")
        }
        return works.first(where: { $0.id == work.id })
    }

    /// Loads cached local thumbnail first (instant UI); returns nil if none yet.
    func loadThumbnailImage(for work: WuMindLocalWork) -> UIImage? {
        if let name = work.thumbnailFileName, let data = readFile(name: name, owner: work.ownerID), let img = UIImage(data: data) {
            return img
        }
        if work.workType == .image, let name = work.assetFileName, let data = readFile(name: name, owner: work.ownerID), let img = UIImage(data: data) {
            return img
        }
        return nil
    }

    func localAssetURL(for work: WuMindLocalWork) -> URL? {
        guard let name = work.assetFileName else { return nil }
        let url = ownerDirectory(work.ownerID).appendingPathComponent(name)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func loadLocalAssetData(for work: WuMindLocalWork) -> Data? {
        guard let name = work.assetFileName else { return nil }
        return readFile(name: name, owner: work.ownerID)
    }

    func loadLocalProjectJSON(for work: WuMindLocalWork) -> String? {
        guard let name = work.projectFileName,
              let data = readFile(name: name, owner: work.ownerID) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// On-demand download of full original asset or editable project JSON from cloud when opening from another device.
    func fetchFullOriginalIfNeeded(for work: WuMindLocalWork) async throws -> (assetURL: URL?, projectJSON: String?) {
        let existingAsset = localAssetURL(for: work)
        let existingProj = loadLocalProjectJSON(for: work)
        if existingAsset != nil && (!work.hasRemoteProject || existingProj != nil) {
            return (existingAsset, existingProj)
        }

        let wmStore = WuMindStore.shared
        guard wmStore.hasGatewayURL, let token = WuMindStore.shared.managedSessionToken, !token.isEmpty else {
            return (existingAsset, existingProj)
        }

        var finalAssetURL = existingAsset
        var finalProject = existingProj

        if finalAssetURL == nil && work.hasRemoteAsset {
            let downloaded = try await WuMindGatewayClient().downloadWorkAsset(
                gatewayURL: wmStore.gatewayBaseURL,
                userToken: token,
                workID: work.id
            )
            let ext = fileExtension(forMime: downloaded.mimeType, type: work.workType)
            let fname = "\(work.id).\(ext)"
            if writeFile(downloaded.data, name: fname, owner: work.ownerID) {
                if let idx = works.firstIndex(where: { $0.id == work.id }) {
                    works[idx].assetFileName = fname
                    works[idx].assetMime = downloaded.mimeType
                    saveIndex(for: work.ownerID)
                }
                finalAssetURL = ownerDirectory(work.ownerID).appendingPathComponent(fname)
            }
        }

        if finalProject == nil && work.hasRemoteProject {
            var fetchedProject: String? = nil
            if let detail = try? await WuMindGatewayClient().fetchWorkDetail(
                gatewayURL: wmStore.gatewayBaseURL,
                userToken: token,
                workID: work.id
            ), let proj = detail.projectJSON, !proj.isEmpty {
                fetchedProject = proj
            } else if let downloadedProj = try? await WuMindGatewayClient().downloadWorkAsset(
                gatewayURL: wmStore.gatewayBaseURL,
                userToken: token,
                workID: work.id,
                kind: "project"
            ), let projText = String(data: downloadedProj.data, encoding: .utf8), !projText.isEmpty {
                fetchedProject = projText
            }
            if let proj = fetchedProject, !proj.isEmpty {
                let pname = "\(work.id)_project.json"
                if writeFile(Data(proj.utf8), name: pname, owner: work.ownerID) {
                    if let idx = works.firstIndex(where: { $0.id == work.id }) {
                        works[idx].projectFileName = pname
                        saveIndex(for: work.ownerID)
                    }
                }
                finalProject = proj
            }
        }

        return (finalAssetURL, finalProject)
    }

    /// Manually retries uploading a local work's metadata & full binary asset to private Cloudflare R2.
    /// For edited versions (`parentWorkID != nil`), resumes with the exact same fixed `versionWorkID` &
    /// `idempotencyKey` so reconnecting never creates duplicate v2 records.
    func retryAssetUpload(id: String) async {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        guard let item = works.first(where: { $0.id == id }) else { return }
        let assetData = loadLocalAssetData(for: item)
        let projectJSON = loadLocalProjectJSON(for: item)
        let previewB64: String? = item.thumbnailFileName.flatMap { readFile(name: $0, owner: item.ownerID)?.base64EncodedString() }
        if let idx = works.firstIndex(where: { $0.id == id }) {
            works[idx].assetSyncState = .uploading
            works[idx].lastAssetUploadError = nil
            saveIndex(for: item.ownerID)
        }
        if let parentID = item.parentWorkID, !parentID.isEmpty {
            await pushVersionToCloud(
                parentID: parentID,
                localChild: item,
                assetData: assetData,
                previewBase64: previewB64,
                projectJSON: projectJSON
            )
        } else {
            await pushCreateOrUpdateToCloud(
                item,
                assetData: assetData,
                previewBase64: previewB64,
                projectJSON: projectJSON,
                createNewVersion: false
            )
        }
    }

    // MARK: - Private Cloud Helpers & Local File IO

    private func defaultMime(for workType: WuMindWorkType, explicit: String?) -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        switch workType {
        case .image: return "image/jpeg"
        case .video: return "video/mp4"
        case .ppt: return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case .scene3d: return "model/gltf-binary"
        case .document: return "text/markdown"
        case .code: return "text/plain"
        }
    }

    private func uploadBinaryAssetsToR2(
        localID: String,
        remoteWorkID: String,
        ownerID: String,
        workType: WuMindWorkType,
        assetData: Data?,
        assetMime: String?,
        largeProjectJSON: String?
    ) async {
        let wmStore = WuMindStore.shared
        guard wmStore.hasGatewayURL, let token = WuMindStore.shared.managedSessionToken, !token.isEmpty else {
            if let idx = works.firstIndex(where: { $0.id == localID }) {
                works[idx].assetSyncState = .localOnly
                works[idx].syncedToCloud = false
                saveIndex(for: ownerID)
            }
            return
        }

        let client = WuMindGatewayClient()

        if let rawAsset = assetData, !rawAsset.isEmpty {
            if let idx = works.firstIndex(where: { $0.id == localID }) {
                works[idx].assetSyncState = .uploading
                works[idx].assetSizeBytes = rawAsset.count
                works[idx].lastAssetUploadError = nil
                saveIndex(for: ownerID)
            }
            do {
                let uploaded = try await client.uploadWorkAssetBinary(
                    gatewayURL: wmStore.gatewayBaseURL,
                    userToken: token,
                    workID: remoteWorkID,
                    data: rawAsset,
                    mimeType: defaultMime(for: workType, explicit: assetMime),
                    kind: "asset"
                )
                if let idx = works.firstIndex(where: { $0.id == localID }) {
                    works[idx].hasRemoteAsset = true
                    works[idx].assetSyncState = .synced
                    works[idx].assetSizeBytes = uploaded.sizeBytes ?? rawAsset.count
                    works[idx].assetSHA256 = uploaded.sha256
                    works[idx].lastAssetUploadError = nil
                    works[idx].syncedToCloud = true
                    saveIndex(for: ownerID)
                }
            } catch let gwErr as WuMindGatewayClient.GatewayError {
                if let idx = works.firstIndex(where: { $0.id == localID }) {
                    if case .objectStorageUnconfigured(let msg) = gwErr {
                        works[idx].assetSyncState = .storageUnconfigured
                        works[idx].lastAssetUploadError = msg
                    } else {
                        works[idx].assetSyncState = .failed
                        works[idx].lastAssetUploadError = gwErr.errorDescription
                    }
                    works[idx].hasRemoteAsset = false
                    works[idx].syncedToCloud = false
                    saveIndex(for: ownerID)
                }
                return
            } catch {
                if let idx = works.firstIndex(where: { $0.id == localID }) {
                    works[idx].assetSyncState = .failed
                    works[idx].hasRemoteAsset = false
                    works[idx].syncedToCloud = false
                    works[idx].lastAssetUploadError = error.localizedDescription
                    saveIndex(for: ownerID)
                }
                return
            }
        }

        if let largeProjectJSON, !largeProjectJSON.isEmpty {
            do {
                _ = try await client.uploadWorkAssetBinary(
                    gatewayURL: wmStore.gatewayBaseURL,
                    userToken: token,
                    workID: remoteWorkID,
                    data: Data(largeProjectJSON.utf8),
                    mimeType: "application/json",
                    kind: "project"
                )
                if let idx = works.firstIndex(where: { $0.id == localID }) {
                    works[idx].hasRemoteProject = true
                    saveIndex(for: ownerID)
                }
            } catch {
                // Keep local project JSON intact even if remote R2 project upload failed
            }
        }
    }

    private func pushCreateOrUpdateToCloud(
        _ work: WuMindLocalWork,
        assetData: Data?,
        previewBase64: String?,
        projectJSON: String?,
        createNewVersion: Bool
    ) async {
        let wmStore = WuMindStore.shared
        guard wmStore.hasGatewayURL, let token = WuMindStore.shared.managedSessionToken, !token.isEmpty else {
            if let idx = works.firstIndex(where: { $0.id == work.id }) {
                works[idx].assetSyncState = .localOnly
                works[idx].syncedToCloud = false
                saveIndex(for: work.ownerID)
            }
            return
        }
        let inlineProject = (projectJSON != nil && (projectJSON?.utf8.count ?? 0) <= 180_000) ? projectJSON : nil
        let r2Project = (projectJSON != nil && inlineProject == nil) ? projectJSON : nil
        let hasBinaryAsset = (assetData?.isEmpty == false)

        do {
            let remote = try await WuMindGatewayClient().createWork(
                gatewayURL: wmStore.gatewayBaseURL,
                userToken: token,
                id: work.id,
                workType: work.workType,
                title: work.title,
                prompt: work.prompt,
                modelID: work.modelID,
                params: work.params,
                status: work.status,
                progress: work.progress,
                upstreamJobID: work.upstreamJobID,
                idempotencyKey: work.idempotencyKey,
                errorMessage: work.errorMessage,
                previewBase64: previewBase64,
                assetMime: work.assetMime,
                assetBase64: nil,
                projectJSON: inlineProject,
                timing: work.timing
            )
            if let idx = works.firstIndex(where: { $0.id == work.id }) {
                if inlineProject != nil { works[idx].hasRemoteProject = true }
                // Only mark synced immediately if there is NO binary asset waiting for R2 upload!
                if !hasBinaryAsset {
                    works[idx].syncedToCloud = true
                    works[idx].assetSyncState = WuMindAssetSyncState(rawValue: remote.assetSyncState ?? "") ?? works[idx].assetSyncState
                }
                saveIndex(for: work.ownerID)
            }
            if hasBinaryAsset || r2Project != nil {
                await uploadBinaryAssetsToR2(
                    localID: work.id,
                    remoteWorkID: remote.id,
                    ownerID: work.ownerID,
                    workType: work.workType,
                    assetData: assetData,
                    assetMime: work.assetMime,
                    largeProjectJSON: r2Project
                )
            }
        } catch {
            if let idx = works.firstIndex(where: { $0.id == work.id }) {
                works[idx].syncedToCloud = false
                if hasBinaryAsset {
                    works[idx].assetSyncState = .failed
                    works[idx].lastAssetUploadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                saveIndex(for: work.ownerID)
            }
        }
    }

    private func pushVersionToCloud(
        parentID: String,
        localChild: WuMindLocalWork,
        assetData: Data?,
        previewBase64: String?,
        projectJSON: String?
    ) async {
        let wmStore = WuMindStore.shared
        guard wmStore.hasGatewayURL, let token = WuMindStore.shared.managedSessionToken, !token.isEmpty else {
            if let idx = works.firstIndex(where: { $0.id == localChild.id }) {
                works[idx].assetSyncState = .localOnly
                works[idx].syncedToCloud = false
                saveIndex(for: localChild.ownerID)
            }
            return
        }
        let inlineProject = (projectJSON != nil && (projectJSON?.utf8.count ?? 0) <= 180_000) ? projectJSON : nil
        let r2Project = (projectJSON != nil && inlineProject == nil) ? projectJSON : nil
        let hasBinaryAsset = (assetData?.isEmpty == false)
        let fixedIdem = localChild.idempotencyKey ?? "ver-\(localChild.id)"

        do {
            let remoteCreated = try await WuMindGatewayClient().updateWork(
                gatewayURL: wmStore.gatewayBaseURL,
                userToken: token,
                workID: parentID,
                title: localChild.title,
                prompt: localChild.prompt,
                status: localChild.status,
                progress: localChild.progress,
                previewBase64: previewBase64,
                assetMime: localChild.assetMime,
                assetBase64: nil,
                projectJSON: inlineProject,
                createNewVersion: true,
                versionWorkID: localChild.id,
                idempotencyKey: fixedIdem,
                pendingAssetUpload: hasBinaryAsset,
                pendingProjectUpload: r2Project != nil
            )
            if let idx = works.firstIndex(where: { $0.id == localChild.id }) {
                works[idx].versionNumber = remoteCreated.versionNumber
                works[idx].idempotencyKey = fixedIdem
                if inlineProject != nil { works[idx].hasRemoteProject = true }
                if hasBinaryAsset {
                    // Explicitly keep pending_upload until PUT /v1/works/:id/asset succeeds!
                    works[idx].hasRemoteAsset = false
                    works[idx].assetSyncState = .pendingUpload
                    works[idx].syncedToCloud = false
                } else {
                    works[idx].syncedToCloud = true
                    works[idx].assetSyncState = WuMindAssetSyncState(rawValue: remoteCreated.assetSyncState ?? "") ?? works[idx].assetSyncState
                }
                saveIndex(for: localChild.ownerID)
            }
            if hasBinaryAsset || r2Project != nil {
                await uploadBinaryAssetsToR2(
                    localID: localChild.id,
                    remoteWorkID: remoteCreated.id,
                    ownerID: localChild.ownerID,
                    workType: localChild.workType,
                    assetData: assetData,
                    assetMime: localChild.assetMime,
                    largeProjectJSON: r2Project
                )
            }
        } catch {
            if let idx = works.firstIndex(where: { $0.id == localChild.id }) {
                works[idx].syncedToCloud = false
                works[idx].assetSyncState = hasBinaryAsset ? .pendingUpload : .localOnly
                works[idx].lastAssetUploadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                saveIndex(for: localChild.ownerID)
            }
        }
    }

    private func mergeRemoteWork(_ rw: WuMindCloudWork, owner: String) {
        if pendingDeletes.shouldSkipRemoteWork(rw.id) { return }
        let type = WuMindWorkType(rawValue: rw.workType) ?? .image
        let created = parseISO(rw.createdAt) ?? Date()
        let updated = parseISO(rw.updatedAt) ?? created

        var thumbName: String? = nil
        if let prevB64 = rw.previewBase64, let raw = Data(base64Encoded: prevB64), !raw.isEmpty {
            let name = "\(rw.id)_thumb.jpg"
            if writeFile(raw, name: name, owner: owner) {
                thumbName = name
            }
        }

        let remoteSyncState = rw.assetSyncState.flatMap(WuMindAssetSyncState.init(rawValue:))
        let remoteAssetSynced = (remoteSyncState == .synced) || (rw.hasAsset == true && remoteSyncState != .pendingUpload)

        if let idx = works.firstIndex(where: { $0.id == rw.id }) {
            works[idx].title = rw.title.isEmpty ? works[idx].title : rw.title
            works[idx].status = rw.status
            works[idx].progress = rw.progress
            works[idx].errorMessage = rw.errorMessage
            works[idx].upstreamJobID = works[idx].videoJobOrigin?.jobID ?? rw.upstreamJobID ?? works[idx].upstreamJobID
            works[idx].hasRemoteAsset = (remoteSyncState == .pendingUpload) ? false : (rw.hasAsset ?? works[idx].hasRemoteAsset)
            works[idx].hasRemoteProject = rw.hasProject ?? works[idx].hasRemoteProject
            works[idx].timing = rw.timing ?? works[idx].timing
            works[idx].versionNumber = rw.versionNumber
            works[idx].parentWorkID = rw.parentWorkID ?? works[idx].parentWorkID
            if let remoteSyncState {
                works[idx].assetSyncState = remoteSyncState
            }
            if let sz = rw.assetSizeBytes, sz > 0 {
                works[idx].assetSizeBytes = sz
            }
            if let sha = rw.assetSHA256, !sha.isEmpty {
                works[idx].assetSHA256 = sha
            }
            if let thumbName { works[idx].thumbnailFileName = thumbName }
            works[idx].updatedAt = max(works[idx].updatedAt, updated)
            works[idx].syncedToCloud = remoteAssetSynced || (rw.status != "completed" && remoteSyncState != .pendingUpload)
        } else {
            let item = WuMindLocalWork(
                id: rw.id,
                ownerID: owner,
                workType: type,
                title: rw.title.isEmpty ? String(rw.prompt.prefix(40)) : rw.title,
                prompt: rw.prompt,
                modelID: rw.modelID,
                params: rw.params ?? [:],
                status: rw.status,
                progress: rw.progress,
                upstreamJobID: rw.upstreamJobID,
                idempotencyKey: rw.idempotencyKey,
                errorMessage: rw.errorMessage,
                thumbnailFileName: thumbName,
                assetFileName: nil,
                assetMime: rw.assetMime,
                projectFileName: nil,
                hasRemoteAsset: (remoteSyncState == .pendingUpload) ? false : (rw.hasAsset ?? false),
                hasRemoteProject: rw.hasProject ?? false,
                timing: rw.timing,
                versionNumber: rw.versionNumber,
                parentWorkID: rw.parentWorkID,
                createdAt: created,
                updatedAt: updated,
                syncedToCloud: remoteAssetSynced || (rw.status != "completed" && remoteSyncState != .pendingUpload),
                assetSyncState: remoteSyncState ?? ((rw.hasAsset == true) ? .synced : .localOnly),
                assetSizeBytes: rw.assetSizeBytes,
                assetSHA256: rw.assetSHA256
            )
            works.append(item)
        }
    }

    private func ensureOwnerLoaded(_ owner: String) {
        if activeOwnerID != owner {
            activeOwnerID = owner
            pendingDeletes = loadPendingDeletes(for: owner)
            pendingDeleteCount = pendingDeletes.count
            pendingDeleteError = pendingDeletes.isEmpty ? nil : "有 \(pendingDeletes.count) 项删除待同步到云端，联网后将自动补发。"
            works = loadIndex(for: owner)
                .filter { !pendingDeletes.shouldSkipRemoteWork($0.id) }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func upsertLocal(_ item: WuMindLocalWork) {
        if let idx = works.firstIndex(where: { $0.id == item.id }) {
            works[idx] = item
        } else {
            works.insert(item, at: 0)
        }
        works.sort { $0.updatedAt > $1.updatedAt }
        saveIndex(for: item.ownerID)
    }

    private func ownerDirectory(_ owner: String) -> URL {
        let safeOwner = WuMindAccountStorageScope.sanitize(owner)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = docs.appendingPathComponent("WuMindWorks", isDirectory: true)
            .appendingPathComponent(safeOwner, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func indexURL(for owner: String) -> URL {
        ownerDirectory(owner).appendingPathComponent("index.json")
    }

    private func pendingDeletesURL(for owner: String) -> URL {
        ownerDirectory(owner).appendingPathComponent("pending_deletes.json")
    }

    private func loadPendingDeletes(for owner: String) -> WuMindPendingDeleteQueue {
        let url = pendingDeletesURL(for: owner)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WuMindPendingDeleteQueue.self, from: data) else {
            return WuMindPendingDeleteQueue()
        }
        return decoded
    }

    private func savePendingDeletes(for owner: String) {
        pendingDeleteCount = pendingDeletes.count
        if pendingDeletes.isEmpty {
            pendingDeleteError = nil
            try? fm.removeItem(at: pendingDeletesURL(for: owner))
            return
        }
        if let data = try? JSONEncoder().encode(pendingDeletes) {
            try? data.write(to: pendingDeletesURL(for: owner), options: .atomic)
        }
    }

    private func loadIndex(for owner: String) -> [WuMindLocalWork] {
        let url = indexURL(for: owner)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WuMindLocalWork].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveIndex(for owner: String) {
        let trimmed = Array(works.prefix(1000))
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: indexURL(for: owner), options: .atomic)
        }
    }

    private func writeFile(_ data: Data, name: String, owner: String) -> Bool {
        let url = ownerDirectory(owner).appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func readFile(name: String, owner: String) -> Data? {
        try? Data(contentsOf: ownerDirectory(owner).appendingPathComponent(name))
    }

    private func removeFileIfExists(_ name: String?, owner: String) {
        guard let name else { return }
        try? fm.removeItem(at: ownerDirectory(owner).appendingPathComponent(name))
    }

    private func makeThumbnailJPEG(from data: Data, maxDimension: CGFloat) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let size = img.size
        guard size.width > 0 && size.height > 0 else { return nil }
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.72)
    }

    private func fileExtension(forMime mime: String?, type: WuMindWorkType) -> String {
        let m = (mime ?? "").lowercased()
        if m.contains("png") { return "png" }
        if m.contains("jpeg") || m.contains("jpg") { return "jpg" }
        if m.contains("mp4") { return "mp4" }
        if m.contains("presentation") || m.contains("pptx") { return "pptx" }
        if m.contains("gltf") || m.contains("glb") { return "glb" }
        if m.contains("pdf") { return "pdf" }
        if m.contains("word") || m.contains("docx") { return "docx" }
        if m.contains("markdown") { return "md" }
        if m.contains("html") { return "html" }
        if m.contains("json") { return "json" }
        switch type {
        case .image: return "jpg"
        case .video: return "mp4"
        case .ppt: return "pptx"
        case .scene3d: return "glb"
        case .document: return "md"
        case .code: return "txt"
        }
    }

    private func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: raw)
    }

    /// One-time safe migration for recoverable legacy local PPT/3D/image/video artifacts in Documents.
    private func migrateLegacyLocalWorksIfNeeded(owner: String) {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docs,
              let entries = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return
        }
        var added = 0
        for fileURL in entries {
            let ext = fileURL.pathExtension.lowercased()
            let mappedType: WuMindWorkType?
            let mime: String
            switch ext {
            case "pptx": mappedType = .ppt; mime = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            case "glb": mappedType = .scene3d; mime = "model/gltf-binary"
            default: mappedType = nil; mime = ""
            }
            guard let wtype = mappedType else { continue }
            let legacyID = "LEG-\(abs(fileURL.lastPathComponent.hashValue))"
            if works.contains(where: { $0.id == legacyID }) { continue }
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty, data.count <= 25_000_000 else { continue }
            let fname = "\(legacyID).\(ext)"
            guard writeFile(data, name: fname, owner: owner) else { continue }
            let attrs = try? fileURL.resourceValues(forKeys: [.creationDateKey])
            let created = attrs?.creationDate ?? Date()
            works.append(WuMindLocalWork(
                id: legacyID,
                ownerID: owner,
                workType: wtype,
                title: fileURL.deletingPathExtension().lastPathComponent,
                prompt: "从本地历史自动迁移",
                modelID: "legacy-local",
                params: ["migratedFrom": fileURL.lastPathComponent],
                status: "completed",
                progress: 100,
                upstreamJobID: nil,
                idempotencyKey: nil,
                errorMessage: nil,
                thumbnailFileName: nil,
                assetFileName: fname,
                assetMime: mime,
                projectFileName: nil,
                hasRemoteAsset: false,
                hasRemoteProject: false,
                timing: nil,
                versionNumber: 1,
                parentWorkID: nil,
                createdAt: created,
                updatedAt: created,
                syncedToCloud: false
            ))
            added += 1
        }
        if added > 0 {
            works.sort { $0.updatedAt > $1.updatedAt }
            saveIndex(for: owner)
        }
    }
}
