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

    var isCompleted: Bool { status == "completed" }
    var isFailed: Bool { status == "failed" }
    var isInProgress: Bool { status == "queued" || status == "in_progress" }

    var statusLabel: String {
        switch status {
        case "completed": return "已完成"
        case "failed": return "失败"
        case "in_progress": return progress > 0 ? "生成中 \(progress)%" : "生成中"
        default: return "排队中"
        }
    }
}

/// Unified private 「我的作品」 & Per-Studio 「历史」 manager.
/// - Strictly partitioned per registered WUMIND account (`WM-XXXXXX` or local device owner).
/// - Saves immediately on task submit so closing the sheet, leaving the app, or switching devices never loses results.
/// - Reopening / refreshing queries status read-only (NEVER resubmits or double-charges).
/// - Edits create new versions (`versionNumber + 1`) preserving the original work untouched.
@MainActor
final class WuMindWorksStore: ObservableObject {
    static let shared = WuMindWorksStore()

    @Published private(set) var works: [WuMindLocalWork] = []
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncError: String? = nil
    @Published private(set) var activeOwnerID: String = "local"

    private let fm = FileManager.default
    private var migratedOwners: Set<String> = []

    private init() {
        reloadForCurrentAccount()
    }

    var currentOwnerID: String {
        let managed = WuMindStore.shared.managedAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !managed.isEmpty { return managed }
        if let ext = AppAccountManager.shared.externalProfile?.userID, !ext.isEmpty { return ext }
        return "local"
    }

    func works(of type: WuMindWorkType?) -> [WuMindLocalWork] {
        guard let type else { return works }
        return works.filter { $0.workType == type }
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
        works = loadIndex(for: owner).sorted { $0.updatedAt > $1.updatedAt }
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
        idempotencyKey: String? = nil
    ) -> WuMindLocalWork {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        let now = Date()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let work = WuMindLocalWork(
            id: id,
            ownerID: owner,
            workType: workType,
            title: cleanTitle.isEmpty ? String(prompt.prefix(40)) : String(cleanTitle.prefix(80)),
            prompt: prompt,
            modelID: modelID,
            params: params,
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
        Task { await pushCreateOrUpdateToCloud(work, assetData: nil, previewBase64: nil, projectJSON: nil, createNewVersion: false) }
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
        remoteWorkID: String? = nil
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

        works[idx] = item
        works.sort { $0.updatedAt > $1.updatedAt }
        saveIndex(for: owner)

        let uploadAsset = (assetData != nil && (assetData?.count ?? 0) <= 3_200_000) ? assetData : nil
        Task {
            await pushCreateOrUpdateToCloud(
                item,
                assetData: uploadAsset,
                previewBase64: previewB64,
                projectJSON: projectJSON,
                createNewVersion: false
            )
        }
        return item
    }

    func updateProgress(id: String, status: String, progress: Int, upstreamJobID: String? = nil) {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        guard let idx = works.firstIndex(where: { $0.id == id }) else { return }
        works[idx].status = status
        works[idx].progress = max(0, min(100, progress))
        if let upstreamJobID, !upstreamJobID.isEmpty {
            works[idx].upstreamJobID = upstreamJobID
        }
        works[idx].updatedAt = Date()
        saveIndex(for: owner)
    }

    func failWork(id: String, errorMessage: String) {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        guard let idx = works.firstIndex(where: { $0.id == id }) else { return }
        works[idx].status = "failed"
        works[idx].progress = 0
        works[idx].errorMessage = String(errorMessage.prefix(400))
        works[idx].updatedAt = Date()
        let snapshot = works[idx]
        saveIndex(for: owner)
        Task { await pushCreateOrUpdateToCloud(snapshot, assetData: nil, previewBase64: nil, projectJSON: nil, createNewVersion: false) }
    }

    /// Saves an edited revision as a NEW version (v2, v3, ...) while keeping the original version completely intact!
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

        let newID = "WRK-\(UUID().uuidString.prefix(12).uppercased())"
        let now = Date()
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
            idempotencyKey: nil,
            errorMessage: nil,
            thumbnailFileName: parent.thumbnailFileName,
            assetFileName: nil,
            assetMime: assetMime ?? parent.assetMime,
            projectFileName: nil,
            hasRemoteAsset: false,
            hasRemoteProject: projectJSON != nil,
            timing: nil,
            versionNumber: maxVer + 1,
            parentWorkID: rootID,
            createdAt: now,
            updatedAt: now,
            syncedToCloud: false
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
        let uploadAsset = (assetData != nil && (assetData?.count ?? 0) <= 3_200_000) ? assetData : nil
        Task {
            await pushVersionToCloud(
                parentID: parent.id,
                localChild: child,
                assetData: uploadAsset,
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
        if WuMindStore.shared.hasGatewayURL, let token = Keychain.wumindGatewayUserToken, !token.isEmpty {
            Task {
                try? await WuMindGatewayClient().deleteWork(gatewayURL: gw, userToken: token, workID: id)
            }
        }
    }

    // MARK: - Read-Only Cloud Sync & On-Demand Full Asset Fetch (Zero Resubmit / Zero Double Charge)

    func syncFromCloud(type: WuMindWorkType? = nil) async {
        let owner = currentOwnerID
        ensureOwnerLoaded(owner)
        let wmStore = WuMindStore.shared
        guard wmStore.hasGatewayURL,
              let token = Keychain.wumindGatewayUserToken, !token.isEmpty else {
            return
        }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            let remote = try await WuMindGatewayClient().listWorks(
                gatewayURL: wmStore.gatewayBaseURL,
                userToken: token,
                type: type,
                limit: 80
            )
            for rw in remote {
                mergeRemoteWork(rw, owner: owner)
            }
            works.sort { $0.updatedAt > $1.updatedAt }
            saveIndex(for: owner)
        } catch {
            lastSyncError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Read-only status poll for an in-progress video work (never resubmits or double-charges).
    func refreshInProgressVideoWork(_ work: WuMindLocalWork) async -> WuMindLocalWork? {
        guard work.workType == .video, let jobID = work.upstreamJobID, !jobID.isEmpty else { return work }
        let wmStore = WuMindStore.shared
        guard wmStore.hasGatewayURL, let token = Keychain.wumindGatewayUserToken, !token.isEmpty else { return work }
        do {
            let st = try await WuMindGatewayClient().fetchManagedVideoStatus(
                gatewayURL: wmStore.gatewayBaseURL,
                userToken: token,
                jobID: jobID
            )
            if st.isCompleted {
                if let mp4 = try? await WuMindGatewayClient().downloadManagedVideoContent(
                    gatewayURL: wmStore.gatewayBaseURL,
                    userToken: token,
                    jobID: jobID
                ) {
                    return completeWork(id: work.id, assetData: mp4, assetMime: "video/mp4", assetExtension: "mp4")
                } else {
                    updateProgress(id: work.id, status: "completed", progress: 100)
                }
            } else if st.isFailed {
                failWork(id: work.id, errorMessage: st.error ?? "视频生成失败")
            } else {
                updateProgress(id: work.id, status: st.status, progress: st.progress ?? work.progress)
            }
        } catch {
            // Read-only poll failure keeps current state intact without charging or duplicating
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
        guard wmStore.hasGatewayURL, let token = Keychain.wumindGatewayUserToken, !token.isEmpty else {
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
            let detail = try await WuMindGatewayClient().fetchWorkDetail(
                gatewayURL: wmStore.gatewayBaseURL,
                userToken: token,
                workID: work.id
            )
            if let proj = detail.projectJSON, !proj.isEmpty {
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

    // MARK: - Private Cloud Helpers & Local File IO

    private func pushCreateOrUpdateToCloud(
        _ work: WuMindLocalWork,
        assetData: Data?,
        previewBase64: String?,
        projectJSON: String?,
        createNewVersion: Bool
    ) async {
        let wmStore = WuMindStore.shared
        guard wmStore.hasGatewayURL, let token = Keychain.wumindGatewayUserToken, !token.isEmpty else { return }
        do {
            _ = try await WuMindGatewayClient().createWork(
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
                assetBase64: assetData?.base64EncodedString(),
                projectJSON: projectJSON,
                timing: work.timing
            )
            if let idx = works.firstIndex(where: { $0.id == work.id }) {
                works[idx].syncedToCloud = true
                if assetData != nil { works[idx].hasRemoteAsset = true }
                if projectJSON != nil { works[idx].hasRemoteProject = true }
                saveIndex(for: work.ownerID)
            }
        } catch {
            // Keep local copy safe even when offline
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
        guard wmStore.hasGatewayURL, let token = Keychain.wumindGatewayUserToken, !token.isEmpty else { return }
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
                assetBase64: assetData?.base64EncodedString(),
                projectJSON: projectJSON,
                createNewVersion: true
            )
            if let idx = works.firstIndex(where: { $0.id == localChild.id }) {
                works[idx].syncedToCloud = true
                works[idx].versionNumber = remoteCreated.versionNumber
                saveIndex(for: localChild.ownerID)
            }
        } catch {
            // Fallback: upload as standalone synced work if parent wasn't synced yet
            await pushCreateOrUpdateToCloud(localChild, assetData: assetData, previewBase64: previewBase64, projectJSON: projectJSON, createNewVersion: false)
        }
    }

    private func mergeRemoteWork(_ rw: WuMindCloudWork, owner: String) {
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

        if let idx = works.firstIndex(where: { $0.id == rw.id }) {
            works[idx].title = rw.title.isEmpty ? works[idx].title : rw.title
            works[idx].status = rw.status
            works[idx].progress = rw.progress
            works[idx].errorMessage = rw.errorMessage
            works[idx].upstreamJobID = rw.upstreamJobID ?? works[idx].upstreamJobID
            works[idx].hasRemoteAsset = rw.hasAsset ?? works[idx].hasRemoteAsset
            works[idx].hasRemoteProject = rw.hasProject ?? works[idx].hasRemoteProject
            works[idx].timing = rw.timing ?? works[idx].timing
            works[idx].versionNumber = rw.versionNumber
            works[idx].parentWorkID = rw.parentWorkID ?? works[idx].parentWorkID
            if let thumbName { works[idx].thumbnailFileName = thumbName }
            works[idx].updatedAt = max(works[idx].updatedAt, updated)
            works[idx].syncedToCloud = true
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
                hasRemoteAsset: rw.hasAsset ?? false,
                hasRemoteProject: rw.hasProject ?? false,
                timing: rw.timing,
                versionNumber: rw.versionNumber,
                parentWorkID: rw.parentWorkID,
                createdAt: created,
                updatedAt: updated,
                syncedToCloud: true
            )
            works.append(item)
        }
    }

    private func ensureOwnerLoaded(_ owner: String) {
        if activeOwnerID != owner {
            activeOwnerID = owner
            works = loadIndex(for: owner).sorted { $0.updatedAt > $1.updatedAt }
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
        let safeOwner = owner.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = docs.appendingPathComponent("WuMindWorks", isDirectory: true)
            .appendingPathComponent(safeOwner.isEmpty ? "local" : safeOwner, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func indexURL(for owner: String) -> URL {
        ownerDirectory(owner).appendingPathComponent("index.json")
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
        let trimmed = Array(works.prefix(200))
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
        switch type {
        case .image: return "jpg"
        case .video: return "mp4"
        case .ppt: return "pptx"
        case .scene3d: return "glb"
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
