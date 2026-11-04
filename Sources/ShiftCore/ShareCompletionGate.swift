/// 系统分享操作的完成判定，不代表收件人已经收到。
/// 本机操作、取消、错误都不能标记为已发；同一次面板最多回调一次。
public struct ShareCompletionGate: Sendable {
    public enum Activity: Sendable {
        case local
        case externalOrUnknown
        case none
    }

    private var didComplete = false

    public init() {}

    /// nil 表示这个面板已经完成过，调用方不应再次更新状态或推进队列。
    public mutating func finish(activity: Activity, completed: Bool, hasError: Bool) -> Bool? {
        guard !didComplete else { return nil }
        didComplete = true
        guard completed, !hasError else { return false }
        switch activity {
        case .externalOrUnknown: return true
        case .local, .none: return false
        }
    }
}
