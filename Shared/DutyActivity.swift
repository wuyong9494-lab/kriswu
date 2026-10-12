import ActivityKit
import Foundation

/// 值遥测时锁屏、灵动岛上显示的倒计时（实时活动）。App 和小组件共用。
struct DutyAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 开始、下班时间
        var start: Date
        var end: Date
        /// 下班后的安排，如「之后调休：10月16日、10月17日」
        var after: String
    }

    /// 值班那天（yyyy-MM-dd），用来认出是哪一次
    var day: String
    var post: String
}
