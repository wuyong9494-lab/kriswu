import Foundation

// App 里的几条判断规则：同步结果要不要采用、自动同步隔多久、今天用哪个图标、微信什么时候发、小结怎么写。
// 放在这里是为了能单独测试；App 只把数据交进来，照结果去做。

// MARK: - 同步

public enum SyncPolicy {
    /// 自动同步连续失败后要等多久再试：2、4、8 分钟……最多 2 小时
    public static func retryWait(failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        return min(2 * 3600, 120 * pow(2, Double(min(failures, 10) - 1)))
    }

    /// 打开 App 时要不要自动同步：3 分钟内成功过就不同步；连续失败时按 retryWait 隔开。手动下拉不受影响。
    public static func shouldAutoSync(now: Date, lastSync: Date?, lastAttempt: Date?, failures: Int) -> Bool {
        if let lastSync, now.timeIntervalSince(lastSync) < 3 * 60 { return false }
        if failures > 0, let lastAttempt, now.timeIntervalSince(lastAttempt) < retryWait(failures: failures) { return false }
        return true
    }

    /// 已经知道的日子：今天及以后、这次读到的范围里、之前取到过的。
    /// 网站还没正式排班、只有请假调休记录的以后日子不算，不然网站第一次排出新一周时会被当成异常一直挡住。
    public static func knownDays(covered: Set<DayKey>, replaced: Set<DayKey>, today: DayKey,
                                 published: Set<DayKey>, rosterDays: Set<DayKey>) -> Set<DayKey> {
        covered.filter { day in
            guard day >= today, replaced.contains(day) else { return false }
            return published.isEmpty || day == today || published.contains(day) || !rosterDays.contains(day)
        }
    }

    /// 已经知道的日子里六成以上都变了（至少 5 天）：多半是网站改版读错了，自动同步先不采用
    public static func looksBroken(known: Int, changed: Int) -> Bool {
        known >= 5 && changed * 10 > known * 6
    }
}

// MARK: - 图标

public enum ShiftIcon {
    /// 今天该用哪个图标：遥测「遥」，组A–组E 用对应字母（一天多个组取第一个），调度「调」，出差「差」，
    /// 无分工、休息、调休、请假「休」，其它用默认的「值」（nil）。
    public static func name(for raw: String?, matcher: ShiftMatcher) -> String? {
        guard let raw else { return nil }
        let posts = matcher.posts(raw).map(matcher.displayName)
        if posts.contains(where: WorkloadCounter.isDuty) { return "IconDuty" }
        if let r = raw.range(of: #"组\s*[A-Ea-e]"#, options: .regularExpression), let letter = raw[r].last {
            return "Icon" + letter.uppercased()
        }
        if posts.contains(where: { $0.contains("调度") }) { return "IconDispatch" }
        if posts.contains(where: WorkloadCounter.isTrip) { return "IconTrip" }
        if posts.allSatisfy({ WorkloadCounter.isOff($0, matcher: matcher) }) || matcher.match(raw)?.id == "off" { return "IconRest" }
        return nil
    }
}

// MARK: - 微信什么时候发

public enum WeChatSchedule {
    public enum Daily: Equatable, Sendable { case morning, evening }

    /// 现在该补发哪条每天的微信（nil = 不用发）。
    /// 过了晚上提醒时间、今天还没发 → 晚上那条（说明天）；否则过了早上提醒时间、今天还没发 → 早上那条。
    /// 早上那条过了晚上提醒时间就不再补发。关掉的提醒传 nil。
    public static func dailyDue(now: Date, today: DayKey, morning: ClockTime?, evening: ClockTime?,
                                morningSent: DayKey?, eveningSent: DayKey?, calendar: Calendar) -> Daily? {
        func time(_ t: ClockTime) -> Date { today.date(calendar: calendar, hour: t.hour, minute: t.minute) }
        // 发晚上那条时早上那条也一起记成已发
        if let evening, now >= time(evening), eveningSent != today { return .evening }
        if let morning, now >= time(morning), morningSent != today { return .morning }
        return nil
    }

    /// 周日晚上的下周预告该不该发（晚上提醒关掉时按 20:00）
    public static func weekPreviewDue(now: Date, today: DayKey, evening: ClockTime?, sent: DayKey?, calendar: Calendar) -> Bool {
        let t = evening ?? ClockTime(hour: 20, minute: 0)
        return calendar.component(.weekday, from: now) == 1 && sent != today
            && now >= today.date(calendar: calendar, hour: t.hour, minute: t.minute)
    }

    /// 下一次该发微信的时间（请系统在那之后尽快唤醒 App）；没有要发的返回 nil
    public static func nextReminder(now: Date, today: DayKey, morning: ClockTime?, evening: ClockTime?,
                                    weeklyPreview: Bool, calendar: Calendar) -> Date? {
        let days = [today, today.adding(days: 1, calendar: calendar)]
        var candidates = days.flatMap { day in
            [morning, evening].compactMap { $0 }.map { day.date(calendar: calendar, hour: $0.hour, minute: $0.minute) }
        }
        if weeklyPreview {
            let t = evening ?? ClockTime(hour: 20, minute: 0)
            for day in days where calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12)) == 1 {
                candidates.append(day.date(calendar: calendar, hour: t.hour, minute: t.minute))
            }
        }
        return candidates.filter { $0 > now }.min()
    }

    /// 每周发一次的东西记「哪一周」用：周一算一周的开始，如「2026-W42」
    public static func weekKey(_ date: Date, calendar: Calendar) -> String {
        var cal = calendar
        cal.firstWeekday = 2
        return "\(cal.component(.yearForWeekOfYear, from: date))-W\(cal.component(.weekOfYear, from: date))"
    }
}

// MARK: - 小结文字

public enum DigestText {
    /// 每周一给自己的小结。week：这周每天「周一组A」；nextDuty：「10月20日（周二）」
    public static func personalWeekly(workDays: Int, dutyDays: Int, rest: Int?, week: [String],
                                      nextDuty: String?, nextDutyScheduled: Bool) -> String {
        var lines = ["上周上了 \(workDays) 天" + (dutyDays > 0 ? "，其中遥测 \(dutyDays) 次" : "") + "。"]
        if let rest, rest > 0 { lines.append("还有 \(rest) 天待休。") }
        if !week.isEmpty { lines.append("这周：" + week.joined(separator: "，") + "。") }
        if let nextDuty { lines.append((nextDutyScheduled ? "下次遥测：" : "下次遥测（推算）：约 ") + nextDuty + "。") }
        return lines.joined(separator: "\n")
    }

    /// 网站标的「该休没休」（「yyyy-MM-dd|名字|栏目」）：只要 from 那天及以后的，写成「张三 10/12（遥测）」
    public static func noRestLines(_ flags: [String], from: DayKey) -> [String] {
        let first = from.description
        return flags.filter { $0 >= first }.map { flag -> String in
            let parts = flag.split(separator: "|").map(String.init)
            guard parts.count == 3, let d = DayKey(string: parts[0]) else { return flag }
            return "\(parts[1]) \(d.month)/\(d.day)（\(parts[2])）"
        }
    }
}
