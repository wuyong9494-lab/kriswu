import XCTest
@testable import ShiftReminder

/// 设置存档：字段分类整理过，存档格式没变——旧存档照样能读，写出去再读回来不丢东西
@MainActor
final class SettingsTests: XCTestCase {
    private func roundTrip(_ s: AppSettings) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    }

    func testRoundTripKeepsEveryCategory() throws {
        var s = AppSettings()
        // 用户偏好
        s.aliases = ["张三"]
        s.morning = ClockTime(hour: 6, minute: 45)
        s.liveActivity = false
        // 自己记的
        s.dayMemos = ["2026-10-13": "体检"]
        s.taskHistory = ["2026-10-13": TaskDayRecord(shift: "组A", done: ["巡检机房"], todo: ["交接班"])]
        // 管理员规则
        s.scheduleOnlyMembers = ["李四"]
        s.workloadOverrides = ["李四": ["2026-10-12": "不算"]]
        // 同步得到的数据
        s.restBalance = ["张三": 3]
        s.fixedTelemetryDays = ["2026-10-01"]
        // 同步状态
        s.syncState = .anomaly
        s.syncFailureCount = 2
        // 通知去重
        s.weChatWeekSent = DayKey(year: 2026, month: 10, day: 11)
        s.warnedRestKeys = ["2026-10-12|遥测"]
        // 设备本地
        s.backupFolderName = "iCloud 云盘"
        XCTAssertEqual(try roundTrip(s), s)
    }

    func testOldArchiveStillReads() throws {
        // 早期版本的存档：只有一部分字段，其中一项格式不对
        let json = #"{"aliases":["张三"],"morningEnabled":false,"restBalance":{"张三":4},"syncFailureCount":"坏的"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.aliases, ["张三"])
        XCTAssertFalse(s.morningEnabled)
        XCTAssertEqual(s.restBalance["张三"], 4)
        XCTAssertEqual(s.syncFailureCount, 0)               // 格式不对的这一项用默认值，别的照读
        XCTAssertEqual(s.evening, AppSettings().evening)    // 没有的字段用默认值
        XCTAssertTrue(s.taskHistory.isEmpty)
    }

    func testFieldGroups() {
        let base = AppSettings()
        // 勾清单、同步记录：不用重排提醒，也不用重算统计
        var s = base
        s.taskChecks = ["2026-10-13|组A": ["0.巡检机房"]]
        s.syncLog = [SyncLogEntry(date: Date(), source: "测试", ok: true, message: "", seconds: 1)]
        XCTAssertTrue(s.onlyBookkeepingChanged(from: base))
        XCTAssertTrue(s.sameData(as: base))
        // 改提醒时间：要重排提醒
        s.morning = ClockTime(hour: 6, minute: 0)
        XCTAssertFalse(s.onlyBookkeepingChanged(from: base))
        // 管理员规则：影响统计；非管理员改了会被换回原样
        var r = base
        r.scheduleOnlyMembers = ["李四"]
        XCTAssertFalse(r.sameData(as: base))
        XCTAssertEqual(r.keepingAdminFields(of: base), base)
        // 普通设置不受管理员限制
        var p = base
        p.aliases = ["张三"]
        XCTAssertEqual(p.keepingAdminFields(of: p), p)
        XCTAssertEqual(p.keepingAdminFields(of: base), p)
    }
}
