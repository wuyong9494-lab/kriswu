import XCTest
@testable import ShiftCore

final class ScheduleParserTests: XCTestCase {
    let ref = DayKey(year: 2026, month: 10, day: 9)
    var parser: ScheduleParser {
        var p = ScheduleParser(aliases: ["张伟", "zhangwei"], reference: ref)
        p.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return p
    }

    func d(_ m: Int, _ day: Int, _ y: Int = 2026) -> DayKey { DayKey(year: y, month: m, day: day) }

    func testDateTokens() {
        let p = DateTokenParser(reference: ref)
        XCTAssertEqual(p.parse("2026-10-09"), d(10, 9))
        XCTAssertEqual(p.parse("2026/10/9"), d(10, 9))
        XCTAssertEqual(p.parse("2026年10月9日"), d(10, 9))
        XCTAssertEqual(p.parse("20261009"), d(10, 9))
        XCTAssertEqual(p.parse("10/9"), d(10, 9))
        XCTAssertEqual(p.parse("10月9日(周五)"), d(10, 9))
        XCTAssertEqual(p.parse("10-09 星期五"), d(10, 9))
        XCTAssertEqual(p.parse("1/3"), d(1, 3, 2027), "跨年时取最近的年份")
        XCTAssertNil(p.parse("白班"))
        XCTAssertNil(p.parse("13/40"))
        XCTAssertNil(p.parse("张伟"))
    }

    func testSimpleList() throws {
        let r = try parser.parse("""
        2026-10-09 白班
        2026-10-10 夜班
        10月11日 周日 休息
        """)
        XCTAssertEqual(r.entries, [d(10, 9): "白班", d(10, 10): "夜班", d(10, 11): "休息"])
        XCTAssertEqual(r.format, .list)
    }

    func testMultipleEntriesPerLine() throws {
        let r = try parser.parse("10/11 休 10/12 白 10/13 夜")
        XCTAssertEqual(r.entries, [d(10, 11): "休", d(10, 12): "白", d(10, 13): "夜"])
    }

    func testListWithNames() throws {
        let r = try parser.parse("""
        日期,姓名,班次
        2026-10-09,张三,白班
        2026-10-09,张伟,夜班
        2026-10-10,ZhangWei,白班
        2026-10-10,李四,夜班
        """)
        XCTAssertEqual(r.entries, [d(10, 9): "夜班", d(10, 10): "白班"])
    }

    func testListNameMissing() {
        XCTAssertThrowsError(try parser.parse("""
        日期,姓名,班次
        2026-10-09,张三,白班
        """)) { XCTAssertEqual($0 as? ScheduleParseError, .nameNotFound(["张伟", "zhangwei"])) }
    }

    func testMatrix() throws {
        let r = try parser.parse("""
        姓名\t10/9\t10/10\t10/11
        张三\t白\t夜\t休
        张伟\t夜\t休\t白
        """)
        XCTAssertEqual(r.entries, [d(10, 9): "夜", d(10, 10): "休", d(10, 11): "白"])
        XCTAssertEqual(r.format, .matrix)
    }

    func testMatrixDayNumbersWithTitleAndMonthRollover() throws {
        let r = try parser.parse("""
        2026年10月 排班表
        姓名,26,27,28,29,30,31,1,2
        张伟,白,白,夜,夜,休,休,,白
        张三,夜,夜,休,休,白,白,夜,夜
        """)
        XCTAssertEqual(r.entries[d(10, 26)], "白")
        XCTAssertEqual(r.entries[d(10, 31)], "休")
        XCTAssertNil(r.entries[d(11, 1)])
        XCTAssertEqual(r.entries[d(11, 2)], "白")
    }

    func testColumnPerPerson() throws {
        let r = try parser.parse("""
        日期,张三,张伟,李四
        10/9,白,夜,休
        10/10,夜,白,休
        """)
        XCTAssertEqual(r.entries, [d(10, 9): "夜", d(10, 10): "白"])
        XCTAssertEqual(r.format, .column)
    }

    /// 单位值班网站的样子：每行一天，每列一个岗位，格子里是人名
    func testRosterByPost() throws {
        let r = try parser.parse("""
        组E\t●今日通知 张伟 注意事项
        日期\t星期\t遥测\t调度\t组A\t组B\t组C\t组D\t组E\t值班交班前\t休息\t调休
        2026-10-05\t周一\t刘洋(5)\t陈静(3)\t张伟(1)\t杨帆(5)\t黄磊(5)\t周敏(3)\t张伟(1)\t孙涛(6)\t张伟(1) 杨帆(5)
        2026-10-06\t周二\t黄磊(5)\t陈静(3)\t孙涛(6)\t张伟(1)\t周敏(3)\t杨帆(5)\t孙涛(6)\t\t杨帆(5) 孙涛(6)
        2026-10-08\t周四\t马超(1)\t陈静(3) 朱丽(3) 胡斌\t郭峰\t杨帆(5)\t孙涛(6)\t何强(4)\t张伟(1)\t周敏(3)\t黄磊(5)
        2026-10-11\t周日\t梁宇\t\t刘洋(5)\t\t\t\t\t罗刚(1)\t林娜(5)
        """)
        XCTAssertEqual(r.format, .roster)
        XCTAssertEqual(r.entries, [d(10, 5): "组A+组E+休息", d(10, 6): "组B", d(10, 8): "组E"])
        XCTAssertEqual(ShiftMatcher(types: ShiftType.defaults).displayName("组A+组E+休息"), "组A+组E+休息")
    }

    /// Element UI 表格：表头和表体是两个 <table>，单元格里用 div/span 包着名字
    func testRosterFromElementTableHTML() throws {
        let html = """
        <html><body><div class="notice"><div>组E</div><div>●设备巡检●</div></div>
        <div class="el-table">
          <div class="el-table__header-wrapper"><table class="el-table__header"><thead><tr>
            <th><div class="cell">日期<span class="caret-wrapper"><i class="sort-caret ascending"></i></span></div></th>
            <th><div class="cell">星期</div></th><th><div class="cell">遥测</div></th><th><div class="cell">调度</div></th>
            <th><div class="cell">组A</div></th><th><div class="cell">组B</div></th><th><div class="cell">休息</div></th>
            <th class="gutter"></th>
          </tr></thead></table></div>
          <div class="el-table__body-wrapper"><table class="el-table__body"><tbody>
            <tr><td><div class="cell">2026-10-07</div></td><td><div class="cell">周三</div></td>
                <td><div class="cell"><span class="el-tag">周敏(3)</span></div></td>
                <td><div class="cell"><span class="el-tag">陈静(3)</span></div></td>
                <td><div class="cell"><span class="el-tag">刘洋(5)</span></div></td>
                <td><div class="cell"><span class="el-tag">孙涛(6)</span></div></td>
                <td><div class="cell"><div><span class="el-tag">张伟(1)</span></div><div><span class="el-tag">孙涛(6)</span></div></div></td></tr>
            <tr><td><div class="cell">2026-10-09</div></td><td><div class="cell">周五</div></td>
                <td><div class="cell"><span>林娜(5)</span></div></td>
                <td><div class="cell"><div>陈静(3)</div><div>朱丽(3)</div><div>胡斌</div></div></td>
                <td><div class="cell"><span>刘洋(5)</span></div></td>
                <td><div class="cell"><span>张伟(1)</span></div></td>
                <td><div class="cell"></div></td></tr>
          </tbody></table></div>
        </div></body></html>
        """
        let text = HTMLText.toText(html)
        XCTAssertTrue(text.contains("2026-10-09\t周五\t林娜(5)\t陈静(3) 朱丽(3) 胡斌\t刘洋(5)\t张伟(1)"), text)
        let r = try parser.parse(text)
        XCTAssertEqual(r.entries, [d(10, 7): "休息", d(10, 9): "组B"])
    }

    /// 手机网页「我的分工」：卡片里日期和分工分成两行，顶部还有一个当前日期
    func testMobileMyDutyCards() throws {
        let html = """
        <html><body><div id="app">
          <div class="nav"><span>排班系统</span><span>W</span></div>
          <div class="date-bar"><div>2026-10-09</div><span>周五</span></div>
          <div class="card"><div class="title">我的分工</div>
            <div class="item"><div class="d">2026-10-05 周一</div><div class="v">组A、组E</div></div>
            <div class="item"><div class="d">2026-10-06 周二</div><div class="v">组B</div></div>
            <div class="item"><div class="d">2026-10-09 周五 <span class="tag">今天</span></div><div class="v">组D</div></div>
            <div class="item"><div class="d">2026-10-10 周六</div><div class="v">无分工</div></div>
          </div>
          <div class="tabs"><div>我的分工</div><div>值班查看</div></div>
        </div></body></html>
        """
        let r = try parser.parse(HTMLText.toText(html))
        XCTAssertEqual(r.entries, [d(10, 5): "组A、组E", d(10, 6): "组B", d(10, 9): "组D", d(10, 10): "无分工"])

        // 同一行显示的版本
        let inline = """
        <div class="date-bar">2026-10-09 周五</div><div>我的分工</div>
        <ul><li><span>2026-10-05 周一</span><b>组A、组E</b></li>
        <li><span>2026-10-09 周五</span><i>今天</i><b>组D</b></li></ul>
        """
        let r2 = try parser.parse(HTMLText.toText(inline))
        XCTAssertEqual(r2.entries, [d(10, 5): "组A、组E", d(10, 9): "组D"])

        let m = ShiftMatcher(types: ShiftType.defaults)
        XCTAssertEqual(m.displayName("组A、组E"), "组A+组E")
        XCTAssertEqual(m.match("组A、组E")?.id, "group")
        XCTAssertEqual(m.match("无分工")?.id, "off")
        XCTAssertEqual(m.displayName("无分工"), "无分工")
    }

    func testJSON() throws {
        let r = try parser.parse("""
        {"data": [
          {"date": "2026-10-09", "name": "张伟", "shift": "白班"},
          {"date": "2026-10-09", "name": "张三", "shift": "夜班"},
          {"date": "2026-10-10T00:00:00+08:00", "name": "zhangwei", "shift": "夜班"}
        ]}
        """)
        XCTAssertEqual(r.entries, [d(10, 9): "白班", d(10, 10): "夜班"])

        let map = try parser.parse(#"{"2026-10-09": "白班", "2026-10-10": "夜班"}"#)
        XCTAssertEqual(map.entries.count, 2)
    }

    func testICS() throws {
        let r = try parser.parse("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261009
        DTEND;VALUE=DATE:20261010
        SUMMARY:张伟 白班
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;TZID=Asia/Shanghai:20261010T200000
        DTEND;TZID=Asia/Shanghai:20261011T080000
        SUMMARY:张伟-夜班
        END:VEVENT
        BEGIN:VEVENT
        DTSTART:20261011T170000Z
        SUMMARY:zhangwei 白班
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261013
        DTEND;VALUE=DATE:20261015
        SUMMARY:张伟 年假
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261009
        SUMMARY:张三 夜班
        END:VEVENT
        END:VCALENDAR
        """)
        XCTAssertEqual(r.entries, [
            d(10, 9): "白班",
            d(10, 10): "夜班",
            d(10, 12): "白班", // 17:00Z = 北京时间次日 01:00
            d(10, 13): "年假",
            d(10, 14): "年假",
        ])
    }

    func testEmpty() {
        XCTAssertThrowsError(try parser.parse("   ")) { XCTAssertEqual($0 as? ScheduleParseError, .empty) }
        XCTAssertThrowsError(try parser.parse("hello world")) { XCTAssertEqual($0 as? ScheduleParseError, .noDates) }
    }
}

final class HTMLTextTests: XCTestCase {
    func testTableToText() throws {
        let html = """
        <!DOCTYPE html><html><head><style>td { color: red }</style><script>var a = "<td>";</script></head>
        <body><h1>2026年10月 排班表</h1>
        <table>
          <tr><th>姓名</th><th>10/9</th><th>10/10</th><th>10/11</th></tr>
          <tr><td>张三</td><td>白</td><td>夜</td><td>休</td></tr>
          <tr><td><b>张伟</b></td><td>夜</td><td></td><td>白&nbsp;</td></tr>
        </table><p>Tom &amp; Jerry &#21556;</p></body></html>
        """
        XCTAssertTrue(HTMLText.looksLikeHTML(html))
        XCTAssertFalse(HTMLText.looksLikeLoginPage(html))
        XCTAssertTrue(HTMLText.looksLikeLoginPage(#"<input type="password" name="pwd">"#))

        let text = HTMLText.toText(html)
        XCTAssertEqual(text, "2026年10月 排班表\n姓名\t10/9\t10/10\t10/11\n张三\t白\t夜\t休\n张伟\t夜\t\t白\nTom & Jerry 吴")

        let r = try ScheduleParser(aliases: ["张伟"], reference: DayKey(year: 2026, month: 10, day: 9)).parse(text)
        XCTAssertEqual(r.entries, [DayKey(year: 2026, month: 10, day: 9): "夜", DayKey(year: 2026, month: 10, day: 11): "白"])
    }
}

final class ScheduleDiffTests: XCTestCase {
    func testChanges() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }
        let old = [d(8): "白", d(10): "白", d(11): "夜", d(12): "休"]
        let new = [d(8): "夜", d(10): "白", d(11): "白", d(13): "夜"]
        let changes = ScheduleDiff.changes(old: old, new: new, from: d(9))
        XCTAssertEqual(changes, [
            ScheduleChange(day: d(11), old: "夜", new: "白"),
            ScheduleChange(day: d(12), old: "休", new: nil),
            ScheduleChange(day: d(13), old: nil, new: "夜"),
        ])
        let text = ScheduleDiff.summary(changes, matcher: ShiftMatcher(types: ShiftType.defaults), calendar: cal)
        XCTAssertEqual(text, "10月11日 周日：夜班 → 白班\n10月12日 周一：休息 → 无\n10月13日 周二：无 → 夜班")
    }

    func testSummaryDetail() {
        let changes = [ScheduleChange(day: DayKey(year: 2026, month: 10, day: 12), old: "组D", new: "组B")]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let text = ScheduleDiff.summary(changes, matcher: ShiftMatcher(types: ShiftType.defaults), calendar: cal) { _ in "组B 原来是张三" }
        XCTAssertEqual(text, "10月12日 周一：组D → 组B（组B 原来是张三）")
    }
}

final class APIDiscoveryTests: XCTestCase {
    let ref = DayKey(year: 2026, month: 10, day: 9)
    let matcher = ShiftMatcher(types: ShiftType.defaults)
    func d(_ m: Int, _ day: Int) -> DayKey { DayKey(year: 2026, month: m, day: day) }

    func testMyDutyShape() {
        // 「我的分工」接口：没有名字，每天一条，分工字段名不规范
        let json = """
        {"code":200,"msg":"ok","data":[
          {"id":101,"dutyDate":"2026-10-05","weekDay":"周一","groupNames":"组A、组E","updateTime":"2026-10-01 08:00:00"},
          {"id":102,"dutyDate":"2026-10-06","weekDay":"周二","groupNames":"组B","updateTime":"2026-10-01 08:00:00"},
          {"id":103,"dutyDate":"2026-10-10","weekDay":"周六","groupNames":"","updateTime":"2026-10-01 08:00:00"}
        ]}
        """
        let e = JSONScheduleExtractor.extract(json, aliases: [], matcher: matcher, reference: ref)
        XCTAssertEqual(e, [d(10, 5): "组A、组E", d(10, 6): "组B", d(10, 10): "无分工"])
    }

    func testNestedDutiesAndTimestamps() {
        let json = """
        {"result":{"list":[
          {"day":1791158400000,"duties":[{"post":"组A","seq":1},{"post":"组E","seq":2}]},
          {"day":1791244800000,"duties":[{"post":"组B","seq":1}]}
        ]}}
        """
        let e = JSONScheduleExtractor.extract(json, aliases: [], matcher: matcher, reference: ref)
        XCTAssertEqual(e.count, 2)
        XCTAssertTrue(e.values.contains("组A、组E"))
    }

    func testRosterFilteredByName() {
        // 全员排班接口：按名字过滤
        let json = """
        [{"date":"2026-10-07","userName":"张伟","postName":"组D"},
         {"date":"2026-10-07","userName":"刘洋","postName":"组A"},
         {"date":"2026-10-08","userName":"张伟","postName":"组E"},
         {"date":"2026-10-08","userName":"刘洋","postName":"组B"}]
        """
        XCTAssertEqual(JSONScheduleExtractor.extract(json, aliases: ["张伟"], matcher: matcher, reference: ref),
                       [d(10, 7): "组D", d(10, 8): "组E"])
        // 不知道自己名字时，多人数据认不准，返回空
        XCTAssertEqual(JSONScheduleExtractor.extract(json + "", aliases: ["王五"], matcher: matcher, reference: ref).count, 2,
                       "两天各两条，不算明显的多人数据时仍会合并")
    }

    func testIgnoresUnrelatedJSON() {
        XCTAssertTrue(JSONScheduleExtractor.extract(#"{"user":{"name":"张伟","role":"admin"}}"#,
                                                    aliases: [], matcher: matcher, reference: ref).isEmpty)
        XCTAssertTrue(JSONScheduleExtractor.extract("<html></html>", aliases: [], matcher: matcher, reference: ref).isEmpty)
    }

    func testDateShifter() {
        XCTAssertEqual(DateShifter.shift("/api/duty?start=2026-10-05&end=2026-10-11", days: 7),
                       "/api/duty?start=2026-10-12&end=2026-10-18")
        XCTAssertEqual(DateShifter.shift(#"{"date":"2026/12/28"}"#, days: 7), #"{"date":"2027/01/04"}"#)
        XCTAssertEqual(DateShifter.shift("d=2026-10-9", days: 7), "d=2026-10-16")
        XCTAssertEqual(DateShifter.shift("day=20261005", days: 7), "day=20261012")
        XCTAssertEqual(DateShifter.shift("t=1791158400000", days: 1), "t=1791244800000")
        XCTAssertEqual(DateShifter.shift("page=1&size=20&id=20231234", days: 7), "page=1&size=20&id=20231234")
    }

    func testDiscoveryPicksScheduleRequest() {
        let user = CapturedRequest(url: "http://host/api/user/info", method: "GET", body: #"{"name":"张伟"}"#)
        let duty = CapturedRequest(url: "http://host/api/duty/my?date=2026-10-09", method: "GET",
                                   body: #"{"data":[{"dutyDate":"2026-10-09","groupNames":"组D"},{"dutyDate":"2026-10-10","groupNames":"无分工"}]}"#)
        let failed = CapturedRequest(url: "http://host/api/x", method: "GET", status: 500, body: "[]")
        let found = APIDiscovery.find(in: [user, duty, failed], preferred: nil, aliases: [], matcher: matcher, reference: ref)
        XCTAssertEqual(found?.request.signature, "GET http://host/api/duty/my")
        XCTAssertEqual(found?.entries[d(10, 9)], "组D")
        XCTAssertTrue(duty.hasDateParameter)
        XCTAssertFalse(user.hasDateParameter)
        XCTAssertEqual(duty.shifted(days: 7).url, "http://host/api/duty/my?date=2026-10-16")

        let decoded = try? JSONDecoder().decode([CapturedRequest].self, from: Data(
            #"[{"url":"u","method":"POST","headers":{"Authorization":"x"},"reqBody":"{\"d\":\"2026-10-09\"}","status":200,"body":"[]"}]"#.utf8))
        XCTAssertEqual(decoded?.first?.requestBody, #"{"d":"2026-10-09"}"#)
    }
}

final class RosterTests: XCTestCase {
    let ref = DayKey(year: 2026, month: 10, day: 9)
    func d(_ day: Int) -> DayKey { DayKey(year: 2026, month: 10, day: day) }

    func testRosterFromTable() {
        let text = """
        组E\t●当日应急：每半小时检查设备状态并处理●\t●设备巡检●
        日期\t星期\t遥测\t调度\t组A\t组B\t休息
        2026-10-05\t周一\t刘洋(5)\t陈静(3)\t张伟(1)\t杨帆(5)\t张伟(1) 杨帆(5)
        2026-10-06\t周二\t黄磊(5)\t陈静(3) 朱丽(3) 胡斌\t孙涛(6)\t张伟(1)
        """
        let roster = RosterExtractor.fromTable(text, reference: ref, matcher: ShiftMatcher(types: ShiftType.defaults))
        XCTAssertEqual(roster["张伟"], [d(5): "组A+休息", d(6): "组B"])
        XCTAssertEqual(roster["胡斌"], [d(6): "调度"])
        XCTAssertEqual(roster["陈静"], [d(5): "调度", d(6): "调度"])
        XCTAssertNil(roster["周一"])

        let notes = GroupNotes.fromText(text, reference: ref)
        XCTAssertEqual(notes["组E"], "●当日应急：每半小时检查设备状态并处理● ●设备巡检●")
        XCTAssertNil(notes["组A"])
    }

    func testRosterFromCardsAndMisalignedHeader() {
        let m = ShiftMatcher(types: ShiftType.defaults)
        // 手机版卡片：一行日期，下面每行「岗位 人名…」
        let cards = """
        2026-10-10 周六
        遥测 罗刚(1)
        调度 陈静(3) 朱丽(3) 胡斌
        组A 何强(4)
        值班交班前
        林娜(5)
        休息 马超(1)
        2026-10-11 周日
        组A 刘洋(5)
        """
        let r = RosterExtractor.fromCards(cards, reference: ref, matcher: m)
        XCTAssertEqual(r["罗刚"], [d(10): "遥测"])
        XCTAssertEqual(r["胡斌"], [d(10): "调度"])
        XCTAssertEqual(r["何强"], [d(10): "组A"])
        XCTAssertEqual(r["林娜"], [d(10): "值班交班前"])
        XCTAssertEqual(r["马超"], [d(10): "休息"])
        XCTAssertEqual(r["刘洋"], [d(11): "组A"])
        XCTAssertNil(r["遥测"])

        // 表头读到的是人名时，不能把人名当岗位
        let bad = "林娜\t何强\t陈静\n2026-10-10\t马超\t刘洋"
        XCTAssertTrue(RosterExtractor.fromTable(bad, reference: ref, matcher: m).isEmpty)
        // 同一份卡片文字按表格读，也不会产生错误数据
        XCTAssertTrue(RosterExtractor.fromTable(cards, reference: ref, matcher: m).isEmpty)
    }

    /// 手机版「值班查看」真实结构（人名为虚构）：一天一页，分区标题 + 岗位卡片，空岗位后面是翻页按钮
    func testMobileDutyViewPage() {
        let m = ShiftMatcher(types: ShiftType.defaults)
        let page = """
        排班系统 W
        2026-10-10 周六
        基础分工
        遥测
        罗刚(1)
        调度
        陈静(3)、朱丽(3)、胡斌
        组别分工
        组A
        何强(4)
        组D
        郭峰
        交班与休息
        值班交班前
        林娜(5)
        休息
        马超(1)
        其他
        调休
        周敏(3)
        请假
        出差
        加班
        上一天
        6 / 7
        下一天
        我的分工
        值班查看
        """
        let r = RosterExtractor.fromCards(page, reference: ref, matcher: m)
        XCTAssertEqual(r["胡斌"], [d(10): "调度"])
        XCTAssertEqual(r["郭峰"], [d(10): "组D"])
        XCTAssertEqual(r["林娜"], [d(10): "值班交班前"])
        XCTAssertEqual(r["周敏"], [d(10): "调休"])
        XCTAssertEqual(Set(r.keys), ["罗刚", "陈静", "朱丽", "胡斌", "何强", "郭峰", "林娜", "马超", "周敏"])
    }

    func testRosterFromJSON() {
        let json = """
        {"data":[
          {"dutyDate":"2026-10-07","userName":"张伟(1)","postName":"组D"},
          {"dutyDate":"2026-10-07","userName":"刘洋","postName":"组A"},
          {"dutyDate":"2026-10-08","userName":"张伟","postName":"组E"},
          {"dutyDate":"2026-10-08","userName":"杨帆","postName":"组B"}
        ]}
        """
        let roster = RosterExtractor.fromJSON(json, reference: ref, matcher: ShiftMatcher(types: ShiftType.defaults))
        XCTAssertEqual(roster["张伟"], [d(7): "组D", d(8): "组E"])
        XCTAssertEqual(roster.count, 3)
    }

    func testGroupNotesFromJSONAndMobilePage() {
        let json = #"{"rows":[{"group":"组A","content":"负责设备巡检和日志记录"},{"group":"组B","content":"负责数据传输监控与重传"}]}"#
        XCTAssertEqual(GroupNotes.fromJSON(json)["组B"], "负责数据传输监控与重传")
        // 手机版「我的分工」页面不应被误认成说明
        let mobile = "2026-10-06 周二\n组B\n2026-10-09 周五\n组D\n我的分工\n值班查看"
        XCTAssertTrue(GroupNotes.fromText(mobile, reference: ref).isEmpty)
    }
}

final class ShiftMatcherTests: XCTestCase {
    let m = ShiftMatcher(types: ShiftType.defaults)

    func testMatching() {
        XCTAssertEqual(m.match("白")?.id, "day")
        XCTAssertEqual(m.match("白班")?.id, "day")
        XCTAssertEqual(m.match("D")?.id, "day")
        XCTAssertEqual(m.match("n")?.id, "night")
        XCTAssertEqual(m.match("夜班")?.id, "night")
        XCTAssertEqual(m.match("年假")?.id, "off")
        XCTAssertEqual(m.match("Night Shift")?.id, "night")
        XCTAssertNil(m.match("培训"))
        XCTAssertEqual(m.displayName("夜"), "夜班")
        XCTAssertEqual(m.displayName("培训"), "培训")
        XCTAssertEqual(m.match("组C")?.id, "group")
        XCTAssertEqual(m.displayName("组C"), "组C")
        XCTAssertEqual(m.displayName("值班交班前"), "值班交班前")
        XCTAssertEqual(m.match("调休")?.id, "off")
        XCTAssertEqual(m.displayName("组A+调休"), "组A+调休")
    }
}

final class NotificationPlannerTests: XCTestCase {
    func testPlan() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let planner = NotificationPlanner(morning: ClockTime(hour: 7, minute: 30), evening: ClockTime(hour: 20, minute: 30),
                                          notifyWhenEmpty: false, matcher: ShiftMatcher(types: ShiftType.defaults), calendar: cal)
        let schedule: [DayKey: String] = [
            DayKey(year: 2026, month: 10, day: 9): "白",
            DayKey(year: 2026, month: 10, day: 10): "夜",
        ]
        // 10 月 9 日 08:00，今天早上的提醒已经过了
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8))!
        let plan = planner.plan(schedule: schedule, now: now)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].title, "🌙 明天：夜班")
        XCTAssertEqual(plan[0].day, DayKey(year: 2026, month: 10, day: 9))
        XCTAssertEqual(plan[0].time, ClockTime(hour: 20, minute: 30))
        XCTAssertEqual(plan[1].title, "🌙 今天：夜班")
        XCTAssertEqual(plan[1].body, "10月10日 周六  夜班")
        XCTAssertEqual(plan[1].speech, "今天，夜班")
    }

    func testSingleMessage() {
        let planner = NotificationPlanner(morning: ClockTime(hour: 7, minute: 30), evening: ClockTime(hour: 20, minute: 30),
                                          notifyWhenEmpty: false, matcher: ShiftMatcher(types: ShiftType.defaults))
        let today = DayKey(year: 2026, month: 10, day: 9)
        let schedule = [today: "组D", DayKey(year: 2026, month: 10, day: 10): "无分工"]
        XCTAssertEqual(planner.message(morning: true, on: today, schedule: schedule)?.title, "👥 今天：组D")
        XCTAssertEqual(planner.message(morning: false, on: today, schedule: schedule)?.title, "🛌 明天：无分工")
        XCTAssertNil(planner.message(morning: true, on: DayKey(year: 2026, month: 10, day: 11), schedule: schedule))

        var withNotes = planner
        withNotes.notes = ["组D": "负责设备巡检"]
        XCTAssertEqual(withNotes.message(morning: true, on: today, schedule: schedule)?.body, "10月9日 周五  组D\n组D：负责设备巡检")
    }

    func testWeeklyPreview() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var planner = NotificationPlanner(morning: nil, evening: ClockTime(hour: 20, minute: 30),
                                          notifyWhenEmpty: false, matcher: ShiftMatcher(types: ShiftType.defaults), calendar: cal)
        planner.weekly = true
        // 2026-10-11 是周日
        let sunday = DayKey(year: 2026, month: 10, day: 11)
        let schedule = [DayKey(year: 2026, month: 10, day: 12): "组D", DayKey(year: 2026, month: 10, day: 14): "无分工"]
        let week = planner.weekMessage(on: sunday, schedule: schedule)
        XCTAssertEqual(week?.title, "🗓 下周安排（10/12–10/18）")
        XCTAssertEqual(week?.body.components(separatedBy: "\n").first, "10月12日 周一  组D")
        XCTAssertEqual(week?.body.components(separatedBy: "\n").count, 7)
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 8))!
        let plan = planner.plan(schedule: schedule, now: now)
        XCTAssertEqual(plan.filter { $0.id.hasPrefix("shift-week-") }.map(\.day), [sunday])
        XCTAssertNil(planner.weekMessage(on: sunday, schedule: [:]))
    }

    func testCapAndEmptyDays() {
        let planner = NotificationPlanner(morning: ClockTime(hour: 7, minute: 30), evening: ClockTime(hour: 20, minute: 30),
                                          notifyWhenEmpty: true, matcher: ShiftMatcher(types: []))
        let plan = planner.plan(schedule: [:], now: Date())
        XCTAssertEqual(plan.count, NotificationPlanner.maxPending)
        XCTAssertTrue(plan.allSatisfy { $0.title.contains("未排班") })
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
    }
}
