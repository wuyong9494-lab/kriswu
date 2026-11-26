import Foundation

/// Pure, platform-independent conversation archive & cross-device sync policy for WUMIND.
/// Guarantees:
/// 1. Archiving/unarchiving NEVER mutates `updatedAt`, `createdAt`, message count, or attachments.
/// 2. Default history search excludes archived conversations unless `includeArchived == true`.
/// 3. Cross-device merge resolves content by `(updatedAt, turnCount)` and archive state independently
///    by `archiveStateUpdatedAt`, preventing stale unarchived copies from reviving archived threads
///    and preventing duplicate thread creation.
public struct WuMindConversationArchiveState: Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var searchableText: String
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var turnCount: Int
    public var attachmentCount: Int
    public var isArchived: Bool
    public var archivedAt: Date?
    public var archiveStateUpdatedAt: Date?

    public init(
        id: UUID,
        title: String,
        searchableText: String = "",
        isPinned: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        turnCount: Int,
        attachmentCount: Int = 0,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        archiveStateUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.searchableText = searchableText
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.turnCount = turnCount
        self.attachmentCount = attachmentCount
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.archiveStateUpdatedAt = archiveStateUpdatedAt
    }

    public var effectiveArchiveClock: Date {
        archiveStateUpdatedAt ?? archivedAt ?? .distantPast
    }
}

public enum WuMindConversationArchivePolicy {
    /// Returns a copy marked archived without altering `createdAt`, `updatedAt`, `turnCount`, or `attachmentCount`.
    public static func archive(_ state: WuMindConversationArchiveState, at now: Date = Date()) -> WuMindConversationArchiveState {
        var copy = state
        copy.isArchived = true
        copy.archivedAt = now
        copy.archiveStateUpdatedAt = now
        return copy
    }

    /// Returns a copy restored to active list without altering `createdAt`, `updatedAt`, `turnCount`, or `attachmentCount`.
    public static func unarchive(_ state: WuMindConversationArchiveState, at now: Date = Date()) -> WuMindConversationArchiveState {
        var copy = state
        copy.isArchived = false
        copy.archivedAt = nil
        copy.archiveStateUpdatedAt = now
        return copy
    }

    /// Standard main-list sort: pinned first, then newest `updatedAt` descending.
    public static func sortActive(_ items: [WuMindConversationArchiveState]) -> [WuMindConversationArchiveState] {
        items
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Standard archived-list sort: newest `archivedAt` (fallback `updatedAt`) descending.
    public static func sortArchived(_ items: [WuMindConversationArchiveState]) -> [WuMindConversationArchiveState] {
        items
            .filter(\.isArchived)
            .sorted { lhs, rhs in
                let lDate = lhs.archivedAt ?? lhs.updatedAt
                let rDate = rhs.archivedAt ?? rhs.updatedAt
                if lDate != rDate { return lDate > rDate }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// Filters conversations by query; archived conversations are excluded by default unless `includeArchived == true`.
    public static func filter(
        _ items: [WuMindConversationArchiveState],
        query: String,
        includeArchived: Bool
    ) -> [WuMindConversationArchiveState] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = includeArchived ? items : items.filter { !$0.isArchived }
        let matched: [WuMindConversationArchiveState]
        if trimmed.isEmpty {
            matched = pool
        } else {
            matched = pool.filter { item in
                item.title.localizedCaseInsensitiveContains(trimmed)
                    || item.searchableText.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return matched.sorted { lhs, rhs in
            if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Non-destructive cross-device merge decision for two versions of the same conversation ID.
    public struct MergeResolution: Equatable, Sendable {
        public let preferIncomingContent: Bool
        public let isArchived: Bool
        public let archivedAt: Date?
        public let archiveStateUpdatedAt: Date?
    }

    public static func resolveMerge(
        localUpdatedAt: Date,
        localTurnCount: Int,
        localIsArchived: Bool,
        localArchivedAt: Date?,
        localArchiveStateUpdatedAt: Date?,
        incomingUpdatedAt: Date,
        incomingTurnCount: Int,
        incomingIsArchived: Bool,
        incomingArchivedAt: Date?,
        incomingArchiveStateUpdatedAt: Date?
    ) -> MergeResolution {
        let preferIncomingContent = incomingUpdatedAt > localUpdatedAt || incomingTurnCount > localTurnCount
        let localClock = localArchiveStateUpdatedAt ?? localArchivedAt ?? .distantPast
        let incomingClock = incomingArchiveStateUpdatedAt ?? incomingArchivedAt ?? .distantPast

        if incomingClock > localClock {
            return MergeResolution(
                preferIncomingContent: preferIncomingContent,
                isArchived: incomingIsArchived,
                archivedAt: incomingArchivedAt,
                archiveStateUpdatedAt: incomingArchiveStateUpdatedAt ?? incomingArchivedAt
            )
        } else if localClock > incomingClock {
            return MergeResolution(
                preferIncomingContent: preferIncomingContent,
                isArchived: localIsArchived,
                archivedAt: localArchivedAt,
                archiveStateUpdatedAt: localArchiveStateUpdatedAt ?? localArchivedAt
            )
        } else {
            // Equal archive clock (e.g. both legacy payloads without archive timestamps): preserve archived if either set.
            let archived = localIsArchived || incomingIsArchived
            return MergeResolution(
                preferIncomingContent: preferIncomingContent,
                isArchived: archived,
                archivedAt: archived ? (incomingArchivedAt ?? localArchivedAt) : nil,
                archiveStateUpdatedAt: incomingArchiveStateUpdatedAt ?? localArchiveStateUpdatedAt
            )
        }
    }
}
