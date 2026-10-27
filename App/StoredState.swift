import Foundation

/// 周会问题跟进：单独存在 meeting.json（以前在设置里）。改周会不用重写设置，也不会让提醒重排
struct MeetingState: Codable, Equatable {
    var docURL = ""
    var issues: [MeetingIssue] = []
    var fingerprint: String?
    var lastImport: Date?
    var week: DayKey?
    var lastAttempt: Date?
    var message: String?
    /// 自动读不到（文档是在线表格）时，这一周已经提醒过去复制导入
    var nudgedWeek: DayKey?
    /// 上次自动下载周会表格每一步的结果（没下载成功时看卡在哪一步）
    var downloadLog: [String] = []
    /// 周会表格里写回脚本的 webhook 链接（令牌在钥匙串里）
    var scriptURL = ""
    /// 写回金山文档的记录（新的在前）
    var writeLog: [String] = []
}

/// 会越攒越多的记录：同步记录、「排班有更新」、清单历史。单独存在 records.json（以前在设置里）
struct RecordsState: Codable, Equatable {
    /// 最近的同步记录（诊断页看后台同步有没有在跑）
    var syncLog: [SyncLogEntry] = []
    /// 今天页「排班有更新」
    var changeLog: [ChangeLogEntry] = []
    /// 清单历史：日期 → 那天的清单做了哪些（保留一年）
    var taskHistory: [String: TaskDayRecord] = [:]
}

/// 以前存在设置里、现在搬到单独文件的字段：旧名 → 新名
enum LegacySettings {
    static let meeting = [
        "meetingDocURL": "docURL", "meetingIssues": "issues", "meetingFingerprint": "fingerprint",
        "meetingLastImport": "lastImport", "meetingWeek": "week", "meetingLastAttempt": "lastAttempt",
        "meetingMessage": "message", "meetingNudgedWeek": "nudgedWeek", "meetingDownloadLog": "downloadLog",
        "meetingScriptURL": "scriptURL", "meetingWriteLog": "writeLog",
    ]
    static let records = ["syncLog": "syncLog", "changeLog": "changeLog", "taskHistory": "taskHistory"]

    /// 从旧的设置存档（字典）里取出这些字段，换成新名；一个都没有返回 nil
    static func extract(_ names: [String: String], from settings: Any?) -> [String: Any]? {
        guard let settings = settings as? [String: Any] else { return nil }
        var out: [String: Any] = [:]
        for (old, new) in names { if let value = settings[old] { out[new] = value } }
        return out.isEmpty ? nil : out
    }
}
