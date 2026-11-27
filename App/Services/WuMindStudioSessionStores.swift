import AVKit
import Foundation
import SwiftUI
import UIKit

/// Persistent @MainActor session store for Image Studio (`AIImageToolView`).
/// Returning to Workspace Launcher Home or popping navigation NEVER cancels an in-progress generation
/// and NEVER clears drafts, sessions, or idempotency keys; ONLY explicit `stopGeneration()` stops a run.
@MainActor
final class AIImageStudioSessionStore: ObservableObject {
    static let shared = AIImageStudioSessionStore()

    struct StudioSlot: Identifiable {
        let id: UUID
        let index: Int
        var image: UIImage?
        var pixelSize: CGSize?
        var elapsedSeconds: Double?
        var failed: Bool = false
    }

    struct StudioSession: Identifiable {
        let id: UUID
        let rawPrompt: String
        let effectivePrompt: String
        let styleName: String?
        let model: AIImageTool.Model
        let modelDisplayOverride: String?
        let usedReferenceImage: Bool
        let quality: AIImageTool.Quality
        let aspectRatio: AIImageTool.AspectRatio
        let startedAt: Date
        var slots: [StudioSlot]
        var finishedAt: Date?
        var errorMessage: String?
        var stageTiming: WuMindCloudWorkTiming?

        var isGenerating: Bool { finishedAt == nil }
        var completedSlots: [StudioSlot] { slots.filter { $0.image != nil } }
        var fastestSeconds: Double? { completedSlots.compactMap(\.elapsedSeconds).min() }
    }

    @Published var prompt: String = ""
    @Published var referenceImage: AIImageTool.ReferenceImage? = nil
    @Published var referenceThumbnail: UIImage? = nil
    @Published var referencePrepNote: String? = nil
    @Published var referencePrepMs: Int = 0
    @Published var sessions: [StudioSession] = []
    @Published var activeRunID: UUID? = nil
    @Published var liveStageLabel: String? = nil
    @Published var failureMessage: String? = nil
    @Published var lastClassifiedError: AIImageClassifiedError? = nil
    @Published var diagnostics: [AIImageRequestDiagnostic] = []
    @Published var pendingRetrySignature: String? = nil
    @Published var pendingRetryIdempotencyKey: String? = nil

    var activeTask: Task<Void, Never>? = nil

    var isGenerating: Bool { activeRunID != nil }

    private init() {}

    func updateSlot(sessionID: UUID, slotIndex: Int, image: UIImage, pixelSize: CGSize, elapsed: Double) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[sIdx].slots.indices.contains(slotIndex) else { return }
        withAnimation(.easeOut(duration: 0.28)) {
            sessions[sIdx].slots[slotIndex].image = image
            sessions[sIdx].slots[slotIndex].pixelSize = pixelSize
            sessions[sIdx].slots[slotIndex].elapsedSeconds = elapsed
        }
    }

    func markSlotFailed(sessionID: UUID, slotIndex: Int) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[sIdx].slots.indices.contains(slotIndex) else { return }
        sessions[sIdx].slots[slotIndex].failed = true
    }

    func finalizeSession(sessionID: UUID, errorMessage: String?) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        for idx in sessions[sIdx].slots.indices where sessions[sIdx].slots[idx].image == nil {
            sessions[sIdx].slots[idx].failed = true
        }
        sessions[sIdx].finishedAt = Date()
        sessions[sIdx].errorMessage = errorMessage
    }

    func recordDiagnostic(_ entry: AIImageRequestDiagnostic) {
        diagnostics.insert(entry, at: 0)
        if diagnostics.count > 20 {
            diagnostics.removeLast(diagnostics.count - 20)
        }
    }

    func invalidatePendingRetryKey() {
        pendingRetrySignature = nil
        pendingRetryIdempotencyKey = nil
    }

    /// Explicit user-triggered stop only — NEVER called on view disappear or returning to Launcher Home!
    func stopGeneration() {
        if activeRunID != nil {
            activeRunID = nil
            if let first = sessions.first, first.isGenerating {
                finalizeSession(sessionID: first.id, errorMessage: "已停止等待（已发出的请求可能仍产生 API 用量）。")
            }
        }
        activeTask?.cancel()
        activeTask = nil
        liveStageLabel = nil
    }

    /// Account switch isolation ONLY — clears drafts, active runs, and cached previews when switching accounts.
    func resetForAccountSwitch() {
        activeTask?.cancel()
        activeTask = nil
        activeRunID = nil
        prompt = ""
        referenceImage = nil
        referenceThumbnail = nil
        referencePrepNote = nil
        referencePrepMs = 0
        sessions = []
        liveStageLabel = nil
        failureMessage = nil
        lastClassifiedError = nil
        diagnostics = []
        invalidatePendingRetryKey()
    }
}

/// Persistent @MainActor session store for Single-Clip Video Studio (`AIVideoToolView`).
/// Returning to Workspace Launcher Home NEVER cancels an in-flight video submission or polling task
/// and NEVER re-submits / double-charges; ONLY explicit `cancelGeneration()` stops the task.
@MainActor
final class AIVideoStudioSessionStore: ObservableObject {
    static let shared = AIVideoStudioSessionStore()

    struct GeneratedClip: Identifiable {
        let id = UUID()
        let prompt: String
        let modelName: String
        let aspect: AIVideoTool.AspectRatio
        let duration: Int
        let fileURL: URL
        let elapsedSeconds: Double
        let createdAt = Date()
    }

    struct UnconfirmedManagedVideoJob {
        let workID: String
        let jobID: String
        let remoteWorkID: String?
        let gatewayURL: String
        let prompt: String
        let modelName: String
        let aspect: AIVideoTool.AspectRatio
        let duration: Int
        let started: Date
    }

    @Published var prompt: String = ""
    @Published var isGenerating: Bool = false
    @Published var activeJobID: String? = nil
    @Published var unconfirmedJob: UnconfirmedManagedVideoJob? = nil
    @Published var progress: AIVideoTool.ProgressUpdate? = nil
    @Published var clips: [GeneratedClip] = []
    @Published var activeClipID: UUID? = nil
    @Published var errorMessage: String? = nil
    @Published var discoveredModels: [AIVideoTool.Model] = []
    @Published var managedSelectedVideoID: String = ""
    @Published var activePlayer: AVPlayer? = nil

    var generateTask: Task<Void, Never>? = nil

    private init() {}

    /// Explicit user-triggered stop ONLY — never called from `onDisappear`!
    func cancelGeneration() {
        generateTask?.cancel()
        generateTask = nil
        isGenerating = false
        progress = nil
        activeJobID = nil
    }

    /// Account switch isolation ONLY.
    func resetForAccountSwitch() {
        cancelGeneration()
        activePlayer?.pause()
        activePlayer = nil
        prompt = ""
        unconfirmedJob = nil
        clips = []
        activeClipID = nil
        errorMessage = nil
    }
}
