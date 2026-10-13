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
        /// 这天的清单：做了几件、一共几件、下一件没做的（没有清单时为空；旧版本开始的实时活动也没有）
        var tasksDone: Int?
        var tasksTotal: Int?
        var nextTask: String?

        /// 「清单 2/5 · 下一项：巡检机房」「清单 5/5 全部做完」
        var tasksLine: String? {
            guard let total = tasksTotal, total > 0 else { return nil }
            let done = tasksDone ?? 0
            if done >= total { return "清单 \(total)/\(total) 全部做完" }
            return "清单 \(done)/\(total)" + (nextTask.map { " · 下一项：\($0)" } ?? "")
        }
    }

    /// 值班那天（yyyy-MM-dd），用来认出是哪一次
    var day: String
    var post: String
}
