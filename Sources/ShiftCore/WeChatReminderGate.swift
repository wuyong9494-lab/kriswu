import Foundation

/// 早、晚和下周预告的内存发送占位。请求完成前不写持久化的「已发」日期。
public struct WeChatReminderGate: Sendable {
    public enum Kind: Hashable, Sendable { case morning, evening, week }

    /// 只在内存里比较；recipientToken 不写日志、不编码或持久化。
    public struct Identity: Hashable, Sendable {
        public let aliases: [String]
        public let sourceURL: String
        public let sourceUsername: String
        public let recipientToken: String

        public init(aliases: [String], sourceURL: String, sourceUsername: String, recipientToken: String) {
            self.aliases = aliases
            self.sourceURL = sourceURL
            self.sourceUsername = sourceUsername
            self.recipientToken = recipientToken
        }
    }

    public struct SentDates: Equatable, Sendable {
        public var morning: DayKey?
        public var evening: DayKey?
        public var week: DayKey?

        public init(morning: DayKey? = nil, evening: DayKey? = nil, week: DayKey? = nil) {
            self.morning = morning
            self.evening = evening
            self.week = week
        }

        public func contains(_ kind: Kind, on day: DayKey) -> Bool {
            switch kind {
            case .morning: return morning == day
            case .evening: return evening == day
            case .week: return week == day
            }
        }
    }

    fileprivate struct Key: Hashable, Sendable {
        let kind: Kind
        let day: DayKey
        let identity: Identity
    }

    public struct Request: Sendable {
        fileprivate let key: Key
        fileprivate let id: UUID
    }

    private var inFlight: [Key: UUID] = [:]

    public init() {}

    public mutating func begin(_ kind: Kind, on day: DayKey, identity: Identity, sent: SentDates) -> Request? {
        let key = Key(kind: kind, day: day, identity: identity)
        guard !sent.contains(kind, on: day), inFlight[key] == nil else { return nil }
        let request = Request(key: key, id: UUID())
        inFlight[key] = request.id
        return request
    }

    /// 只释放自己的请求；旧回调不能释放同一键后来开始的新请求。
    public mutating func abandon(_ request: Request) {
        guard inFlight[request.key] == request.id else { return }
        inFlight.removeValue(forKey: request.key)
    }

    /// 只有成功、有排班、身份和日期仍相同且未取消，才返回应提交的已发日期。
    /// sent 必须是完成时的最新值，失败不返回旧快照，避免回滚其它请求已经成功的日期。
    public mutating func finish(_ request: Request, succeeded: Bool, hasData: Bool, cancelled: Bool,
                                currentIdentity: Identity, currentDay: DayKey, sent: SentDates) -> SentDates? {
        guard inFlight[request.key] == request.id else { return nil }
        abandon(request)
        guard succeeded, hasData, !cancelled,
              currentIdentity == request.key.identity, currentDay == request.key.day else { return nil }
        var updated = sent
        switch request.key.kind {
        case .morning:
            updated.morning = request.key.day
        case .evening:
            updated.evening = request.key.day
            // 保留既有规则：晚提醒成功后，当天不再补发早提醒。
            updated.morning = request.key.day
        case .week:
            updated.week = request.key.day
        }
        return updated
    }
}
