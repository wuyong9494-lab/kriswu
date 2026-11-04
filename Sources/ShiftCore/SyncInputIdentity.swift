import Foundation

/// 一轮排班同步实际使用的输入。成功时间、提示文字等记账字段不会让本轮失效。
public struct SyncInputIdentity: Equatable, Sendable {
    public let aliases: [String]
    public let sourceURL: String
    public let sourceUsername: String
    public let syncViaWeb: Bool

    public init(aliases: [String], sourceURL: String, sourceUsername: String, syncViaWeb: Bool) {
        self.aliases = aliases
        self.sourceURL = sourceURL
        self.sourceUsername = sourceUsername
        self.syncViaWeb = syncViaWeb
    }

    /// 每次异步等待回来后，旧结果只有在输入没变、任务没取消时才能继续提交。
    public func canCommit(current: Self, isCancelled: Bool) -> Bool {
        !isCancelled && self == current
    }

    /// 等待中的调用方是否还需要一次新同步。已取消的任务即使输入相同也不能吞掉新请求。
    public func requiresNewRun(after previous: Self?, previousCancelled: Bool,
                               userInitiated: Bool, previousUserInitiated: Bool) -> Bool {
        previousCancelled || previous != self || (userInitiated && !previousUserInitiated)
    }
}
