import Foundation

/// Pure-Swift account-isolation scope for local WUMIND chat, projects, memories & attachments.
/// Ensures shared devices (e.g. office iPad) strictly separate every account's local database file
/// and detect account switches cleanly so User B can never read User A's conversations or files.
public enum WuMindAccountStorageScope: Sendable {
    public static func resolvedOwnerID(
        managedAccountID: String,
        externalWuMindUserID: String?,
        externalProfileID: String?
    ) -> String {
        let managed = managedAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !managed.isEmpty { return sanitize(managed) }
        if let wm = externalWuMindUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !wm.isEmpty {
            return sanitize(wm)
        }
        if let ext = externalProfileID?.trimmingCharacters(in: .whitespacesAndNewlines), !ext.isEmpty {
            return sanitize(ext)
        }
        return "local"
    }

    public static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(cleaned)
        return result.isEmpty ? "local" : String(result.prefix(64))
    }

    /// Relative subdirectory inside Application Support (`WuMindLocal/Accounts/<ownerID>`).
    public static func accountRelativePath(for ownerID: String) -> String {
        "Accounts/\(sanitize(ownerID))"
    }

    public static func conversationsFileURL(baseFolder: URL, ownerID: String) -> URL {
        baseFolder
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(sanitize(ownerID), isDirectory: true)
            .appendingPathComponent("conversations.json")
    }
}

/// Persistent per-account tombstone queue for cloud work deletions ("待同步删除").
/// Prevents a locally deleted work from resurrecting on the next cloud sync when the initial
/// `DELETE /v1/works/:id` call failed offline or timed out.
public struct WuMindPendingDeleteQueue: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var workID: String
        public var deletedAt: Date
        public var lastError: String?
        public var retryCount: Int

        public init(workID: String, deletedAt: Date = Date(), lastError: String? = nil, retryCount: Int = 0) {
            self.workID = workID
            self.deletedAt = deletedAt
            self.lastError = lastError
            self.retryCount = retryCount
        }
    }

    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }
    public var allPendingIDs: [String] { entries.keys.sorted() }

    public func isTombstoned(_ workID: String) -> Bool {
        entries[workID] != nil
    }

    public mutating func enqueue(_ workID: String, at date: Date = Date()) {
        if var existing = entries[workID] {
            existing.deletedAt = date
            entries[workID] = existing
        } else {
            entries[workID] = Entry(workID: workID, deletedAt: date)
        }
    }

    public mutating func recordFailure(_ workID: String, error: String) {
        var entry = entries[workID] ?? Entry(workID: workID)
        entry.lastError = error
        entry.retryCount += 1
        entries[workID] = entry
    }

    public mutating func confirmDeleted(_ workID: String) {
        entries.removeValue(forKey: workID)
    }

    /// Filters remote work IDs so any locally tombstoned work is strictly excluded from re-appearing.
    public func shouldSkipRemoteWork(_ workID: String) -> Bool {
        entries[workID] != nil
    }
}

/// Distinguishes video generation submission errors from post-submit status-polling errors.
/// Once the server has accepted a job and returned `upstreamJobID`, transient network/timeout errors
/// during polling or download MUST NEVER mark the work as `"failed"` (which risks duplicate submission
/// and double billing); instead they transition to `"status_unknown"` ("暂时无法确认") and resume
/// polling with the exact same job ID.
public enum WuMindVideoFailureClassification: String, Equatable, Sendable {
    /// Failed BEFORE the server returned a job ID — safe to show failed & offer fresh retry.
    case submissionFailed
    /// Server ALREADY accepted the job (`upstreamJobID` exists), but polling/download hit a
    /// network/timeout/transient error. Server may still be rendering! Show "暂时无法确认" and
    /// resume polling with the original job ID (NO resubmission).
    case pollStatusUnconfirmed
    /// Upstream explicitly confirmed terminal failure (`status == "failed"`). Safe to show failed & retry.
    case upstreamConfirmedFailed
}

public enum WuMindVideoJobFailureClassifier: Sendable {
    public static func classify(
        upstreamJobID: String?,
        upstreamConfirmedFailed: Bool
    ) -> WuMindVideoFailureClassification {
        if upstreamConfirmedFailed {
            return .upstreamConfirmedFailed
        }
        let cleanID = upstreamJobID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanID.isEmpty {
            return .pollStatusUnconfirmed
        }
        return .submissionFailed
    }
}

/// Structured persisted web citation attached to an assistant turn.
public struct WuMindWebCitation: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var domain: String
    public var url: String
    public var snippet: String
    public var verifiedRead: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        domain: String,
        url: String,
        snippet: String = "",
        verifiedRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.domain = domain
        self.url = url
        self.snippet = snippet
        self.verifiedRead = verifiedRead
    }
}

/// Structured persisted agent citation attached to an assistant turn.
/// Only rendered as `"引用了 {agentName}"` when `succeeded == true`.
public struct WuMindAgentCitation: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var agentID: String
    public var agentName: String
    public var summary: String
    public var succeeded: Bool
    public var errorMessage: String?

    public init(
        id: String = UUID().uuidString,
        agentID: String,
        agentName: String,
        summary: String = "",
        succeeded: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.agentName = agentName
        self.summary = summary
        self.succeeded = succeeded
        self.errorMessage = errorMessage
    }
}

/// Structured persisted tool failure notice attached to an assistant turn.
public struct WuMindToolFailureNotice: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var toolKind: String      // "web_search" | "agent" | "web_fetch"
    public var targetName: String    // query or agent name
    public var message: String

    public init(
        id: String = UUID().uuidString,
        toolKind: String,
        targetName: String,
        message: String
    ) {
        self.id = id
        self.toolKind = toolKind
        self.targetName = targetName
        self.message = message
    }
}

/// Enforces strict failure honesty for assistant turns with web search / agent tool calls:
/// - If ANY web search or agent call failed during the turn (even when the main answer still generated),
///   the turn MUST NOT be stamped as `"能力已验证"`, MUST NOT show `"引用了 {agentName}"` for the failed agent,
///   and MUST surface the explicit failure notice + retry trigger.
public enum WuMindToolTruthfulnessPolicy: Sendable {
    public static func visibleAgentCitations(from citations: [WuMindAgentCitation]) -> [WuMindAgentCitation] {
        citations.filter(\.succeeded)
    }

    public static func hasAnyToolFailure(
        agentCitations: [WuMindAgentCitation],
        failureNotices: [WuMindToolFailureNotice]
    ) -> Bool {
        if !failureNotices.isEmpty { return true }
        return agentCitations.contains(where: { !$0.succeeded })
    }

    public static func canShowCapabilityVerifiedBadge(
        baseBadge: String?,
        agentCitations: [WuMindAgentCitation],
        failureNotices: [WuMindToolFailureNotice]
    ) -> Bool {
        guard let badge = baseBadge?.trimmingCharacters(in: .whitespacesAndNewlines), !badge.isEmpty else {
            return false
        }
        return !hasAnyToolFailure(agentCitations: agentCitations, failureNotices: failureNotices)
    }
}


/// Persisted with the accepted job, independently of the currently selected connection.
public struct WuMindVideoJobOrigin: Codable, Equatable, Sendable {
    public let gateway: String
    public let accountID: String
    public let jobID: String

    public init?(gateway: String, accountID: String, jobID: String) {
        guard let address = try? WuMindGatewayConfiguration.address(gateway),
              !accountID.isEmpty, !jobID.isEmpty else { return nil }
        self.gateway = address
        self.accountID = accountID
        self.jobID = jobID
    }

    public func matches(gateway: String, accountID: String, jobID: String) -> Bool {
        self == Self(gateway: gateway, accountID: accountID, jobID: jobID)
    }
}

/// An original managed video job can be reconciled read-only after iOS suspension.
public enum WuMindBackgroundVideoRecovery {
    public static func fetchOriginalStatus(
        origin: WuMindVideoJobOrigin?, gateway: String, accountID: String, jobID: String,
        token: String, client: WuMindGatewayClient
    ) async throws -> WuMindManagedVideoJob? {
        guard let origin, origin.matches(gateway: gateway, accountID: accountID, jobID: jobID) else { return nil }
        return try await client.fetchManagedVideoStatus(gatewayURL: origin.gateway, userToken: token, jobID: origin.jobID)
    }

    public static func canQuery(jobID: String?, channel: String?, hasLocalAsset: Bool, status: String) -> Bool {
        guard let jobID, jobID.hasPrefix("VID-"), jobID.count > 4,
              channel != "own_api", !hasLocalAsset else { return false }
        return ["queued", "pending", "processing", "running", "in_progress", "status_unknown", "completed"].contains(status)
    }
}
