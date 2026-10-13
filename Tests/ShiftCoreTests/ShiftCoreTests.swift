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

    func testSwapExplainer() {
        let day = DayKey(year: 2026, month: 10, day: 12)
        let m = ShiftMatcher(types: ShiftType.defaults)
        let isMe = { (n: String) in n == "我" }
        let before: Roster = ["我": [day: "组D"], "李四": [day: "组B"], "王五": [day: "组C"]]
        let change = ScheduleChange(day: day, old: "组D", new: "组B")
        // 对换
        let swapped: Roster = ["我": [day: "组B"], "李四": [day: "组D"], "王五": [day: "组C"]]
        XCTAssertEqual(SwapExplainer.describe(change, before: before, after: swapped, fresh: true, matcher: m, isMe: isMe),
                       "和李四对换：李四原来是组B，现在是组D")
        // 这次没读到全员排班：只能说原来是谁
        XCTAssertEqual(SwapExplainer.describe(change, before: before, after: before, fresh: false, matcher: m, isMe: isMe),
                       "组B原来是李四，可能是和李四换的")
        // 三个人转着换：李四去了组C，王五接了我的组D
        let rotated: Roster = ["我": [day: "组B"], "李四": [day: "组C"], "王五": [day: "组D"]]
        XCTAssertEqual(SwapExplainer.describe(change, before: before, after: rotated, fresh: true, matcher: m, isMe: isMe),
                       "组B原来是李四（李四现在是组C）；组D现在是王五（王五原来是组C）")
        // 我被换下来休息
        let off = ScheduleChange(day: day, old: "组D", new: "无分工")
        let replaced: Roster = ["我": [day: "休息"], "李四": [day: "组B"], "王五": [day: "组D"]]
        XCTAssertEqual(SwapExplainer.describe(off, before: before, after: replaced, fresh: true, matcher: m, isMe: isMe),
                       "组D现在是王五（王五原来是组C）")
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

    func testRosterFromDesktopWeekTable() {
        // 仿电脑版「值班查看」：上面是各组说明（里面也有日期），下面是 Element 表格（表头、表体是两个 table）
        let html = """
        <div class="notes"><table><tr><td>组A</td><td>下午可做：一号星</td><td>谛听新星发射保障：9月20日发射</td></tr>
        <tr><td>组B</td><td>下午可做：二号星规划</td><td>注意检查</td></tr></table></div>
        <div class="el-table__header-wrapper"><table><thead><tr>
        <th><div class="cell">日期<span class="caret-wrapper"><i class="sort-caret"></i></span></div></th><th>星期</th>
        <th>遥测</th><th>调度</th><th>组A</th><th>组B</th><th>值班交班前</th><th>休息</th><th>调休</th><th>加班</th>
        </tr></thead></table></div>
        <div class="el-table__body-wrapper"><table><tbody>
        <tr><td><div class="cell">2026-10-05</div></td><td>周一</td><td><span class="el-tag">张三(5)</span></td>
        <td><span class="el-tag">李四(3)</span></td><td><span class="el-tag">王五(1)</span></td><td><span class="el-tag">赵六(5)</span></td>
        <td><span class="el-tag">钱七(6)</span></td><td><span class="el-tag">王五(1)</span><span class="el-tag">赵六(5)</span></td>
        <td></td><td><span class="el-tag">孙八(3)</span></td></tr>
        <tr><td>2026-10-06</td><td>周二</td><td>赵六(4)</td><td>李四(3)</td><td>钱七(6)</td><td>王五(1)</td><td></td><td></td><td></td><td></td></tr>
        </tbody></table></div>
        """
        let roster = RosterExtractor.fromDesktopHTML(html, reference: DayKey(year: 2026, month: 10, day: 10),
                                                     matcher: ShiftMatcher(types: ShiftType.defaults))
        let d5 = DayKey(year: 2026, month: 10, day: 5), d6 = DayKey(year: 2026, month: 10, day: 6)
        XCTAssertEqual(roster["张三"]?[d5], "遥测")
        XCTAssertEqual(roster["李四"]?[d5], "调度")
        XCTAssertEqual(roster["王五"]?[d5], "组A+休息")
        XCTAssertEqual(roster["钱七"]?[d5], "值班交班前")
        XCTAssertEqual(roster["孙八"]?[d5], "加班")
        XCTAssertEqual(roster["赵六"]?[d6], "遥测")
        XCTAssertEqual(roster["钱七"]?[d6], "组A")
        // 说明里的「9月20日」不能读成排班
        XCTAssertNil(roster.values.first { $0[DayKey(year: 2026, month: 9, day: 20)] != nil })
        XCTAssertEqual(Set(roster.keys), ["张三", "李四", "王五", "赵六", "钱七", "孙八"])
    }

    func testGroupNotesFromDesktopTable() {
        let html = """
        <table><tr><td>组A</td><td><div>下午可做：<span>GF03C02</span><del>GF03B06星</del></div>
        <div>发遥测：等每日自动生成log令的星</div></td><td>1.所有星进行备份数传</td></tr>
        <tr><td>组B</td><td>下午可做：<span style="text-decoration: line-through">KF01B</span>KF02B01星规划</td><td></td></tr></table>
        <table><tr><td>2026-10-05</td><td>周一</td><td>张三</td></tr></table>
        """
        let notes = GroupNotes.fromDesktopHTML(html)
        XCTAssertEqual(notes["组A"], "下午可做： GF03C02\n发遥测：等每日自动生成log令的星\n1.所有星进行备份数传")
        XCTAssertEqual(notes["组B"], "下午可做： KF02B01星规划")
        XCTAssertEqual(notes.count, 2)
    }

    func testGroupNotesFromDesktopBlocks() {
        let html = "<div>组A</div><div>负责一号星的规划</div><div>注意备份</div><div>组B</div><div>负责二号星规划工作</div><div>日期</div><div>组C</div>"
        let notes = GroupNotes.fromDesktopHTML(html)
        XCTAssertEqual(notes["组A"], "负责一号星的规划\n注意备份")
        XCTAssertEqual(notes["组B"], "负责二号星规划工作")
        XCTAssertNil(notes["组C"])
        XCTAssertEqual(GroupNotes.fromDesktopHTML("<div>组D：</div><div>负责平台星的数传工作</div>")["组D"], "负责平台星的数传工作")
    }

    func testGroupNotesFromPaste() {
        let text = """
        组A：下午可做：一号星
        注意备份数传
        组 b
        负责二号星规划
        组C:
        无关的行以外
        """
        let notes = GroupNotes.fromPaste(text)
        XCTAssertEqual(notes["组A"], "下午可做：一号星\n注意备份数传")
        XCTAssertEqual(notes["组B"], "负责二号星规划")
        XCTAssertEqual(notes["组C"], "无关的行以外")
        XCTAssertTrue(GroupNotes.fromPaste("随便一段话").isEmpty)
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

final class WorkloadTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func count(_ roster: Roster, _ days: [DayKey]) -> [String: PersonWorkload] {
        Dictionary(uniqueKeysWithValues: WorkloadCounter.count(
            roster: roster, days: days, matcher: ShiftMatcher(types: ShiftType.defaults), calendar: cal).map { ($0.name, $0) })
    }

    func testOrdinaryWeek() {
        // 10/12 周一 … 10/18 周日（不在假期里），下面的 5…11 对应周一到周日
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day + 7) }
        let roster: Roster = [
            // 平时：周一遥测，周二周三休息（值班换来的也算休息）；周四调度；周五没排；周六遥测；周日休息
            "张三": [d(5): "遥测", d(6): "休息", d(7): "休息", d(8): "调度", d(10): "遥测", d(11): "休息"],
            "李四": [d(5): "出差", d(6): "出差", d(8): "调休"],
            "王五": [d(9): "组C+休息", d(11): "组D"],
        ]
        let result = count(roster, (5...11).map(d))
        XCTAssertEqual(result["张三"]?.dutyDays, 2)
        XCTAssertEqual(result["张三"]?.dutyRestDays, 0)
        // 张三只是顶了一次调度、不轮组别：周五没排、没写休息是在做别的日常工作，算工作量
        XCTAssertEqual(result["张三"]?.regularDays, 2)
        XCTAssertEqual(result["张三"]?.attendanceDays, 0)
        XCTAssertEqual(result["张三"]?.unassignedDays, 0)
        XCTAssertEqual(result["张三"]?.workDays, 4)
        XCTAssertEqual(result["张三"]?.presentDays, 4)
        XCTAssertEqual(result["张三"]?.offDays, 3)
        // 李四：出差 2 天；和值班无关的调休 + 周末 2 天 = 休息 3 天；周三、周五日常
        XCTAssertEqual(result["李四"]?.tripDays, 2)
        XCTAssertEqual(result["李四"]?.offDays, 3)
        XCTAssertEqual(result["李四"]?.regularDays, 2)      // 不轮组别：周三、周五没排是日常工作
        XCTAssertEqual(result["李四"]?.attendanceDays, 0)
        XCTAssertEqual(result["李四"]?.dutyRestDays, 0)
        // 王五：周五组C（同时写了休息也算上班）、周日组D，周一到周四没排也没写休息 = 日常 6 天；周六休息
        XCTAssertEqual(result["王五"]?.regularDays, 2)      // 只算有岗位的周五组C、周日组D
        XCTAssertEqual(result["王五"]?.attendanceDays, 4)   // 轮组别的人：周一到周四没排、没写休息是正常上班，不算工作量
        XCTAssertEqual(result["王五"]?.unassignedDays, 0)
        XCTAssertEqual(result["王五"]?.offDays, 1)
        for p in result.values {
            XCTAssertEqual(p.workDays + p.attendanceDays + p.offDays + p.holidayDays + p.unassignedDays, 7, p.name)   // 出差已算在工作量里
        }
    }

    func testRotationMembers() {
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day + 7) }   // 10/12 周一 … 10/18 周日
        let roster: Roster = [
            "甲": [d(5): "组A", d(6): "遥测"],          // 设置里的轮班人员：周三到周五没排不算
            "乙": [d(-2): "调度", d(-1): "调度", d(0): "调度", d(5): "调度"],   // 最常排调度：只按排班算
            "己": [d(-2): "组A", d(-1): "组A", d(0): "组B", d(5): "调度"],    // 偶尔顶一次调度：照常算日常
            "丙": [d(5): "组B"],                        // 不在名单里：一直没有组别的日常班人员，没排的工作日算日常
        ]
        let m = ShiftMatcher(types: ShiftType.defaults)
        let result = Dictionary(uniqueKeysWithValues: WorkloadCounter.count(
            roster: roster, days: (5...11).map(d), matcher: m, members: ["甲"], calendar: cal).map { ($0.name, $0) })
        XCTAssertEqual(result["甲"]?.workDays, 2)
        XCTAssertEqual(result["甲"]?.unassignedDays, 3)
        XCTAssertEqual(result["乙"]?.workDays, 1)
        XCTAssertEqual(result["乙"]?.unassignedDays, 4)
        XCTAssertEqual(result["丙"]?.workDays, 1)
        XCTAssertEqual(result["丙"]?.attendanceDays, 4)
        XCTAssertEqual(result["丙"]?.unassignedDays, 0)
        XCTAssertEqual(result["己"]?.workDays, 1)
        XCTAssertEqual(result["己"]?.attendanceDays, 4)
        XCTAssertEqual(result["己"]?.unassignedDays, 0)

        // 没设置名单时自动判断：只值遥测、没有组别和调度任务的人，没排的工作日算日常
        let auto = Dictionary(uniqueKeysWithValues: WorkloadCounter.count(
            roster: ["丁": [d(5): "遥测"], "戊": [d(5): "组C"]], days: (5...11).map(d), matcher: m, calendar: cal)
            .map { ($0.name, $0) })
        XCTAssertEqual(auto["丁"]?.dutyDays, 1)
        XCTAssertEqual(auto["丁"]?.regularDays, 4)        // 不轮组别：遥测后没写休息的工作日是日常工作，算工作量
        XCTAssertEqual(auto["丁"]?.attendanceDays, 0)
        XCTAssertEqual(auto["丁"]?.unassignedDays, 0)
        XCTAssertEqual(auto["戊"]?.unassignedDays, 0)       // 轮组别的人没排的工作日也是正常上班
        XCTAssertEqual(auto["戊"]?.regularDays, 1)
        XCTAssertEqual(auto["戊"]?.attendanceDays, 4)
    }

    func testRestAfterWeekendDuty() {
        // 只值遥测的人：10/17 周六遥测，网站上 18、19、20 写了休息才算休息；21 日起没写的工作日是日常
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }
        let p = count(["丙": [d(17): "遥测", d(18): "休息", d(19): "休息", d(20): "休息"]], (17...23).map(d))["丙"]
        XCTAssertEqual(p?.dutyDays, 1)
        XCTAssertEqual(p?.offDays, 3)
        XCTAssertEqual(p?.regularDays, 3)
        XCTAssertEqual(p?.attendanceDays, 0)
        XCTAssertEqual(p?.workDays, 4)
        XCTAssertEqual(p?.presentDays, 4)
        // 网站上没写休息：说明没调休、在上班
        let q = count(["丙": [d(17): "遥测"]], (17...23).map(d))["丙"]
        XCTAssertEqual(q?.regularDays, 5)
        XCTAssertEqual(q?.offDays, 1)
    }

    func testHolidayRestAfterDutyOnly() {
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }
        defer { WorkloadCounter.rules = WorkloadRules() }
        // 国庆：1 日遥测，2 日休息（假期里值班后的休息：不算工作量，算上班和节假日上班），3 日调休、5 日休息是休息；
        // 7 日（假期最后一天）遥测，8 日已经上班了，8 日的休息就是普通休息
        let roster: Roster = ["甲": [d(1): "遥测", d(2): "休息", d(3): "调休", d(4): "组A", d(5): "休息",
                                    d(7): "遥测", d(8): "休息"]]
        let result = count(roster, (1...9).map(d))
        XCTAssertEqual(result["甲"]?.dutyRestDays, 0)
        XCTAssertEqual(result["甲"]?.offDays, 3)
        XCTAssertEqual(result["甲"]?.attendanceDays, 1)      // 2 日（9 日没排：甲不轮组别，算日常）
        XCTAssertEqual(result["甲"]?.workDays, 4)            // 1、7 日遥测，4 日组A，9 日日常
        XCTAssertEqual(result["甲"]?.dutyDays, 2)
        XCTAssertEqual(result["甲"]?.holidayWorkedDays, 4)   // 1、7 日遥测，2 日值班后休息，4 日组A
        // 别人：国庆 5 日遥测，6 日网站上没写（值班后休息：算上班不算工作量），7 日也没写（普通假期）
        let other = count(["乙": [d(5): "遥测", d(8): "组B"]], (5...8).map(d))["乙"]
        XCTAssertEqual(other?.dutyRestDays, 0)
        XCTAssertEqual(other?.attendanceDays, 1)
        XCTAssertEqual(other?.holidayDays, 1)
        XCTAssertEqual(other?.workDays, 2)
        XCTAssertEqual(other?.presentDays, 3)
        XCTAssertEqual(other?.holidayWorkedDays, 2)
        // 值班交接前那列也一样
        let handover = count(["丙": [d(2): "遥测", d(3): "值班交接前", d(8): "组B"]], (2...4).map(d))["丙"]
        XCTAssertEqual(handover?.attendanceDays, 1)
        XCTAssertEqual(handover?.workDays, 1)
        XCTAssertEqual(count(roster, (2...3).map(d))["甲"]?.dutyRestDays, 0)
        // 打开「写了休息也算」：统计范围从 2 日开始，1 日遥测，2、3 日的休息算值班调休
        WorkloadCounter.rules.holidayDutyRestCounts = true
        XCTAssertEqual(count(roster, (2...3).map(d))["甲"]?.dutyRestDays, 2)
        XCTAssertEqual(count(roster, (1...9).map(d))["甲"]?.offDays, 2)
    }

    func testNationalHoliday() {
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }
        // 2026 国庆：10/1–10/7 放假，10/10（周六）上班
        XCTAssertFalse(ChinaHolidays.isWorkday(d(1), calendar: cal))
        XCTAssertFalse(ChinaHolidays.isWorkday(d(7), calendar: cal))
        XCTAssertTrue(ChinaHolidays.isWorkday(d(8), calendar: cal))
        XCTAssertTrue(ChinaHolidays.isWorkday(d(10), calendar: cal))
        XCTAssertFalse(ChinaHolidays.isWorkday(d(11), calendar: cal))
        XCTAssertTrue(ChinaHolidays.isHoliday(d(3)))
        XCTAssertFalse(ChinaHolidays.isHoliday(d(11)))
        XCTAssertTrue(ChinaHolidays.isHoliday(DayKey(year: 2026, month: 9, day: 25)))   // 中秋
        // 张三 10/2 遥测、10/3 写了休息（不算工作量），10/9 组A；李四 10/5 休息
        let roster: Roster = ["张三": [d(2): "遥测", d(3): "休息", d(9): "组A"], "李四": [d(5): "休息"]]
        let result = count(roster, (1...11).map(d))
        XCTAssertEqual(result["张三"]?.dutyDays, 1)
        XCTAssertEqual(result["张三"]?.dutyRestDays, 0)
        XCTAssertEqual(result["张三"]?.regularDays, 1)        // 9 日组A
        XCTAssertEqual(result["张三"]?.attendanceDays, 3)     // 3 日假期里值班后休息 + 8、10 日没排、没写休息：上班，不算工作量
        XCTAssertEqual(result["张三"]?.unassignedDays, 0)
        XCTAssertEqual(result["张三"]?.workDays, 2)
        XCTAssertEqual(result["张三"]?.holidayDays, 5)        // 1、4、5、6、7 日
        XCTAssertEqual(result["张三"]?.holidayWorkedDays, 2)   // 2 日遥测 + 3 日值班后休息
        XCTAssertEqual(result["张三"]?.offDays, 1)            // 11 日周日（3 日是假期里值班后的休息，算上班）
        XCTAssertEqual(result["李四"]?.workDays, 3)      // 不轮组别：8–10 日没排是日常工作
        XCTAssertEqual(result["李四"]?.presentDays, 3)
        XCTAssertEqual(result["李四"]?.holidayDays, 6)
        XCTAssertEqual(result["李四"]?.offDays, 2)
    }
}

final class BalanceTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    let m = ShiftMatcher(types: ShiftType.defaults)

    func testRestBalancesFromText() {
        let text = "2026-10-12\t周一\t李家宝(5)\t高梦瑶(3)\t吴庸（1）\t组A(2)\n2026-10-13\t周二\t李家宝(4)"
        let rest = RosterExtractor.restBalances(text, matcher: m)
        XCTAssertEqual(rest["李家宝"], 5)        // 取第一次出现的
        XCTAssertEqual(rest["高梦瑶"], 3)
        XCTAssertEqual(rest["吴庸"], 1)
        XCTAssertNil(rest["组A"])
    }

    func testWeekBalance() {
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }   // 10/12 周一 … 10/18 周日
        let days = (12...18).map(d)
        // 甲乙丙都有组别；丁只有调度（不参与比较）
        let roster: Roster = [
            "甲": [d(12): "组A", d(13): "组B", d(14): "组A", d(15): "组C", d(17): "遥测"],   // 4 天组别 + 周六遥测 = 5（周五没排：上班不算工作量）
            "乙": [d(12): "组B", d(13): "休息", d(14): "休息", d(15): "休息"],               // 1
            "丙": [d(12): "组C", d(13): "组D", d(14): "组E"],                                // 3
            "丁": [d(12): "调度"],
        ]
        let r = WorkloadBalance.analyze(roster: roster, days: days, matcher: m, tolerance: 2, calendar: cal)
        XCTAssertEqual(r.rows.map(\.name), ["甲", "丙", "乙"])
        XCTAssertEqual(r.rows.map(\.workload.workDays), [5, 3, 1])
        XCTAssertEqual(r.average, 3.0, accuracy: 0.01)
        XCTAssertEqual(r.spread, 4)
        XCTAssertEqual(r.verdict, "不均衡")
        XCTAssertEqual(r.rows.first { $0.name == "乙" }?.level, .less)
        XCTAssertEqual(r.rows.first { $0.name == "甲" }?.level, .more)     // 多 2 天
        XCTAssertEqual(r.rows.first { $0.name == "丙" }?.level, .normal)
        XCTAssertEqual(r.rows.first { $0.name == "甲" }?.groupDays, 4)
        XCTAssertEqual(r.rows.first { $0.name == "丙" }?.workload.unassignedDays, 0)
        // 乙：周二到周四休息 3 天，加上周末 2 天
        XCTAssertTrue(r.findings.contains { $0.contains("乙干得少") && $0.contains("休息 5 天") }, r.findings.joined(separator: "\n"))

        // 差不多的一周：均衡
        let even: Roster = ["甲": [d(12): "组A"], "乙": [d(13): "组B"], "丙": [d(14): "组C"]]
        XCTAssertEqual(WorkloadBalance.analyze(roster: even, days: days, matcher: m, tolerance: 2, calendar: cal).verdict, "均衡")
    }
}

final class RegressionTests: XCTestCase {
    let ref = DayKey(year: 2026, month: 10, day: 9)
    let m = ShiftMatcher(types: ShiftType.defaults)

    func testLongerColleagueNameIsNotMe() {
        let p = ScheduleParser(aliases: ["张伟"], reference: ref)
        XCTAssertTrue(p.isMe("张伟"))
        XCTAssertTrue(p.isMe("张伟(3)"))
        XCTAssertTrue(p.isMe("张伟-夜班"))
        XCTAssertTrue(p.isMe("李四 张伟"))
        XCTAssertFalse(p.isMe("张伟东"))
        XCTAssertFalse(p.isMe("张伟东(2)"))
        XCTAssertTrue(p.isMe("张伟东 张伟"))
        XCTAssertTrue(p.isMe("张伟 白班"))
        XCTAssertTrue(p.isMe("张 伟"))
        XCTAssertTrue(p.isMe("张 伟(3)"))
        XCTAssertTrue(p.isMe("张伟夜班"))
        XCTAssertFalse(p.isMe("张伟东 夜班"))
        let q = ScheduleParser(aliases: ["zhangwei"], reference: ref)
        XCTAssertTrue(q.isMe("zhangwei"))
        XCTAssertTrue(q.isMe("ZhangWei(3)"))
        XCTAssertFalse(q.isMe("zhangweidong"))
        XCTAssertFalse(q.isMe("zhangwei2"))
    }

    func testNamesContainingWeekdayWords() {
        XCTAssertTrue(RosterExtractor.looksLikeName("周天宇"))
        XCTAssertTrue(RosterExtractor.looksLikeName("周一鸣"))
        XCTAssertFalse(RosterExtractor.looksLikeName("周一"))
        XCTAssertFalse(RosterExtractor.looksLikeName("今天"))
        XCTAssertEqual(RosterExtractor.restBalances("2026-10-12\t周天宇(4)", matcher: m)["周天宇"], 4)
    }

    func testDateInsideSentenceIsNotAnEntry() throws {
        let p = ScheduleParser(aliases: [], reference: ref)
        let r = try p.parse("""
        请大家 10月20日 前提交 值班表
        10月12日 白班
        """)
        XCTAssertEqual(r.entries, [DayKey(year: 2026, month: 10, day: 12): "白班"])
        // 「2026年9月20日发射」不是日期格子
        XCTAssertNil(DateTokenParser(reference: ref).parse("2026年9月20日发射"))
        XCTAssertEqual(DateTokenParser(reference: ref).parse("2026-09-20T08:00:00"), DayKey(year: 2026, month: 9, day: 20))
        XCTAssertEqual(DateTokenParser(reference: ref).parse("2026-09-20 周日"), DayKey(year: 2026, month: 9, day: 20))
    }

    func testMissingWeekIsNotReplaced() {
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }
        // 取到了 12–18 和 26–31，19–25 那一周没取到：不应该被替换
        let covered = ParseResult.days(in: d(12)...d(18)).union(ParseResult.days(in: d(26)...d(31)))
        let r = ParseResult(entries: [d(12): "组A", d(31): "组B"], format: .api, coveredDays: covered)
        XCTAssertFalse(r.replacedDays().contains(d(20)))
        XCTAssertTrue(r.replacedDays().contains(d(15)))
        // 没给 coveredDays 时还是首尾之间
        XCTAssertTrue(ParseResult(entries: [d(12): "组A", d(31): "组B"], format: .list).replacedDays().contains(d(20)))
    }

    func testRequestDateWindow() {
        let r = CapturedRequest(url: "http://h/api/mine?start=2026-10-05&end=2026-10-11", method: "GET")
        XCTAssertEqual(r.dateWindow, DayKey(year: 2026, month: 10, day: 5)...DayKey(year: 2026, month: 10, day: 11))
        let body = CapturedRequest(url: "http://h/api", method: "POST", requestBody: #"{"from":"20261012","to":"20261018"}"#)
        XCTAssertEqual(body.dateWindow?.upperBound, DayKey(year: 2026, month: 10, day: 18))
        XCTAssertNil(CapturedRequest(url: "http://h/api/user?id=1760000000000", method: "GET").dateWindow)
        // 版本号之类的第三个日期：看不出范围，不用
        XCTAssertNil(CapturedRequest(url: "http://h/api?v=20261001&start=2026-10-12&end=2026-10-18", method: "GET").dateWindow)
    }

    func testRound6Parsing() {
        let m = ShiftMatcher(types: ShiftType.defaults)
        // 名字里有「中」「白」不是岗位
        XCTAssertTrue(RosterExtractor.names(inCell: "王建中(3)、李四", matcher: m).contains("王建中"))
        XCTAssertFalse(RosterExtractor.isPost("王建中", matcher: m))
        XCTAssertTrue(RosterExtractor.isPost("值班交班前", matcher: m))
        XCTAssertTrue(RosterExtractor.isPost("组A", matcher: m))
        for post in ["年假", "补休", "早班", "白", "夜", "休息", "出差"] { XCTAssertTrue(RosterExtractor.isPost(post, matcher: m), post) }
        XCTAssertTrue(m.isStrictMatch("组E"))
        // 一行里两个组的标签
        let r = try? ScheduleParser(aliases: [], reference: ref).parse("2026-10-12 组A 组E")
        XCTAssertEqual(r?.entries[DayKey(year: 2026, month: 10, day: 12)], "组A+组E")
        // 「王　五」合回一个名字；带间隔号的名字
        XCTAssertEqual(RosterExtractor.names(inCell: "王　五", matcher: m), ["王五"])
        XCTAssertTrue(RosterExtractor.looksLikeName("阿依古丽·买买提"))
        // 王建 不等于 王建中
        XCTAssertFalse(ScheduleParser(aliases: ["王建"], reference: ref).isMe("王建中(3)"))
        // 组A,组E 拆开
        var roster: Roster = [:]
        RosterExtractor.add("组A,组E", for: "张三", on: ref, to: &roster)
        XCTAssertEqual(roster["张三"]?[ref], "组A+组E")
        // UTC 时间换算成本地日期（测试时区按系统）
        let local = JSONScheduleExtractor.zonedDay("2026-10-04T16:00:00.000+0000")
        let expected = DayKey(date: Date(timeIntervalSince1970: 1_791_129_600), calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(local, expected)
    }

    func testHTMLEntitiesDecodedOnce() {
        XCTAssertEqual(HTMLText.decodeEntities("&amp;lt;b&amp;gt; &#X4E00; &#x4e00;"), "&lt;b&gt; 一 一")
    }

    func testWorkloadSkipsPeopleNotAround() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let roster: Roster = [
            "在岗": [DayKey(year: 2026, month: 10, day: 13): "组A"],
            "调走": [DayKey(year: 2026, month: 8, day: 3): "组B"],
        ]
        let days = (12...16).map { DayKey(year: 2026, month: 10, day: $0) }
        let names = WorkloadCounter.count(roster: roster, days: days, matcher: m, calendar: cal).map(\.name)
        XCTAssertEqual(names, ["在岗"])
    }
}


final class UpgradeTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    let m = ShiftMatcher(types: ShiftType.defaults)
    let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }

    func testLedgerDetectsSwaps() {
        let isMe = { (n: String) in n == "我" }
        // 15 日：我组A → 休息，乙接了组A（乙原来没排）→ 我欠乙
        let before: Roster = ["我": [d(15): "组A"], "乙": [d(14): "组B"], "丙": [d(15): "组C"]]
        let after: Roster = ["我": [d(15): "休息"], "乙": [d(14): "组B", d(15): "组A"], "丙": [d(15): "组C"]]
        let r = SwapLedger.detect(ScheduleChange(day: d(15), old: "组A", new: "休息"), before: before, after: after,
                                  fresh: true, matcher: m, isMe: isMe)
        XCTAssertEqual(r.map(\.person), ["乙"])
        XCTAssertEqual(r.first?.effect, -1)
        // 当天对换：我组A ↔ 丙组C
        let after2: Roster = ["我": [d(15): "组C"], "乙": [d(14): "组B"], "丙": [d(15): "组A"]]
        let r2 = SwapLedger.detect(ScheduleChange(day: d(15), old: "组A", new: "组C"), before: before, after: after2,
                                   fresh: true, matcher: m, isMe: isMe)
        XCTAssertEqual(r2.map(\.person), ["丙"])
        XCTAssertEqual(r2.first?.effect, 0)
        // 我替丙上了组C（我原来没排）→ 丙欠我
        let before3: Roster = ["我": [:], "丙": [d(16): "组C"]]
        let after3: Roster = ["我": [d(16): "组C"], "丙": [d(16): "休息"]]
        let r3 = SwapLedger.detect(ScheduleChange(day: d(16), old: nil, new: "组C"), before: before3, after: after3,
                                   fresh: true, matcher: m, isMe: isMe)
        XCTAssertEqual(r3.first?.effect, 1)
        XCTAssertTrue(SwapLedger.detect(ScheduleChange(day: d(16), old: nil, new: "组C"), before: before3, after: after3,
                                        fresh: false, matcher: m, isMe: isMe).isEmpty)
        var records: [SwapRecord] = []
        SwapLedger.merge(r + r3, into: &records)
        SwapLedger.merge(r, into: &records)   // 重复的不再记
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(SwapLedger.balances(records), ["乙": -1, "丙": 1])
        records[0].settled = true
        XCTAssertEqual(SwapLedger.balances(records).values.reduce(0, +), records[1].effect)
    }

    func testSwapFinder() {
        let isMe = { (n: String) in n == "我" }
        // 15 日（周四）我遥测，想换出去
        let roster: Roster = [
            "我": [d(15): "遥测"],
            "甲": [d(10): "遥测", d(15): "休息"],                 // 有空、值过遥测
            "乙": [d(12): "遥测", d(15): "组A"],                  // 那天有班
            "丙": [d(14): "遥测"],                                // 前一天遥测，在调休
            "丁": [d(15): "休息", d(13): "组B"],                  // 没值过遥测
            "戊": [d(11): "遥测", d(16): "组C"],                  // 第二天有班
            "己": [d(9): "遥测", d(17): "组D"],                   // 有空，欠我一天，17 日有班我没班 → 可以换回来
        ]
        let records = [SwapRecord(day: d(1), person: "己", myOld: "", myNew: "组A", effect: 1)]
        let c = SwapFinder.candidates(day: d(15), myPost: "遥测", mine: [d(15): "遥测"], roster: roster,
                                      records: records, matcher: m, isMe: isMe, calendar: cal)
        XCTAssertEqual(c.map(\.name), ["己", "甲"])
        XCTAssertEqual(c.first?.returnDays, [d(17)])
        XCTAssertTrue(c.first?.reasons.contains("欠你 1 天") ?? false)
    }

    func testDutyForecast() {
        let roster: Roster = [
            "甲": [d(1): "遥测", d(7): "遥测", d(13): "遥测"],   // 每 6 天，下次 19 日
            "乙": [d(5): "遥测", d(20): "遥测"],                 // 已排好 20 日
            "丙": [d(3): "组A"],
        ]
        let f = DutyForecaster.forecast(roster: roster, today: d(14), matcher: m, calendar: cal)
        XCTAssertEqual(f.map(\.name), ["甲", "乙"])
        XCTAssertEqual(f[0].predicted, d(19))
        XCTAssertEqual(f[0].interval, 6)
        XCTAssertEqual(f[1].scheduled, d(20))
        XCTAssertEqual(f[1].last, d(5))
    }

    func testHolidayInputAndCustom() {
        let r = HolidayInput.parse("""
        2027-01-01 至 2027-01-03 元旦放假
        2月6日至12日 春节
        2027年2月14日（周日）上班
        随便写的一行
        """, reference: DayKey(year: 2027, month: 7, day: 1), calendar: cal)
        XCTAssertEqual(r.off.count, 3 + 7)
        XCTAssertEqual(r.off.first, DayKey(year: 2027, month: 1, day: 1))
        XCTAssertEqual(r.off.last, DayKey(year: 2027, month: 2, day: 12))
        XCTAssertEqual(r.work, [DayKey(year: 2027, month: 2, day: 14)])
        XCTAssertEqual(r.skipped, ["随便写的一行"])

        // 国务院通知的写法：一行里放假、上班都有，括号里写星期，一句里两个上班日，跨年
        let notice = HolidayInput.parse("""
        一、元旦：1月1日（周五）至3日（周日）放假调休，共3天。1月4日（周一）上班。
        二、春节：2月14日（周日）、2月20日（周六）上班
        12月31日至1月2日放假
        """, reference: DayKey(year: 2027, month: 7, day: 1), calendar: cal)
        XCTAssertEqual(notice.off.map(\.description), ["2027-01-01", "2027-01-02", "2027-01-03",
                                                       "2027-12-31", "2028-01-01", "2028-01-02"])
        XCTAssertEqual(notice.work.map(\.description), ["2027-01-04", "2027-02-14", "2027-02-20"])
        XCTAssertTrue(notice.skipped.isEmpty)

        XCTAssertFalse(ChinaHolidays.knownYears.contains(2027))
        ChinaHolidays.customOff = Set(r.off.map(\.description))
        ChinaHolidays.customWork = Set(r.work.map(\.description))
        defer { ChinaHolidays.customOff = []; ChinaHolidays.customWork = [] }
        XCTAssertTrue(ChinaHolidays.knownYears.contains(2027))
        XCTAssertTrue(ChinaHolidays.isHoliday(DayKey(year: 2027, month: 2, day: 8)))
        XCTAssertFalse(ChinaHolidays.isWorkday(DayKey(year: 2027, month: 2, day: 8), calendar: cal))
        XCTAssertTrue(ChinaHolidays.isWorkday(DayKey(year: 2027, month: 2, day: 14), calendar: cal))
    }

    func testCSV() {
        var p = PersonWorkload(name: "张,三", dutyDays: 2, dutyRestDays: 0, regularDays: 3, offDays: 1, holidayDays: 0,
                               tripDays: 1, holidayWorkedDays: 0, posts: ["遥测": 2, "组A": 3])
        p.unassignedDays = 1
        let csv = WorkloadCSV.make([p], restBalance: ["张,三": 4])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasPrefix("\"张,三\",6,6,2,0,3,1,0,1,0,1,0,4,"), String(lines[1]))
    }

    func testHolidayDutyStats() {
        // 国庆 10/1–10/7；10/9 不是假期
        let roster: Roster = ["甲": [d(1): "遥测", d(3): "组A", d(9): "遥测"], "乙": [d(2): "休息"], "丙": [d(4): "遥测"]]
        let s = HolidayDutyStats.count(roster: roster, days: Set((1...11).map(d)), matcher: m)
        XCTAssertEqual(s.map(\.name), ["甲", "丙"])
        XCTAssertEqual(s[0].dutyDays, 1)
        XCTAssertEqual(s[0].workDays, 3)      // 1 日遥测、2 日值班后休息、3 日组A
        XCTAssertEqual(s[1].workDays, 2)      // 4 日遥测、5 日值班后休息
        XCTAssertEqual(s[0].dutyDates, [d(1)])
    }

    func testLeavePlan() {
        // 10/12 周一 … 10/18 周日；网站排到 15 日
        let mine: [DayKey: String] = [d(12): "组A", d(13): "休息", d(14): "遥测"]
        let published = Set((12...15).map(d))
        let p = LeavePlanner.plan(from: d(12), to: d(18), mine: mine, published: published, matcher: m, calendar: cal)
        XCTAssertEqual(p.needDays, [d(12), d(14), d(16)])
        XCTAssertEqual(p.dutyDays, [d(14)])
        XCTAssertEqual(p.unknownDays, [d(16)])
        XCTAssertEqual(p.freeDays, [d(13), d(15), d(17), d(18)])
    }

    func testTaskList() {
        XCTAssertEqual(TaskList.items(from: "1、巡检机房；2、填写日志\n3. 交接班"), ["巡检机房", "填写日志", "交接班"])
        XCTAssertEqual(TaskList.items(from: "负责数据处理。"), ["负责数据处理"])
    }

    func testRulesAndOverrides() {
        let roster: Roster = ["甲": [d(12): "组A", d(14): "休息"]]      // 10/12 周一
        let days = (12...16).map(d)
        func c() -> PersonWorkload? { WorkloadCounter.count(roster: roster, days: days, matcher: m, calendar: cal).first }
        defer { WorkloadCounter.rules = WorkloadRules(); WorkloadCounter.overrides = [:] }
        XCTAssertEqual(c()?.workDays, 1)
        XCTAssertEqual(c()?.presentDays, 4)        // 13、15、16 日没排：上班，不算工作量
        // 关掉「没排没写休息算上班」
        WorkloadCounter.rules.blankWorkdayIsWork = false
        XCTAssertEqual(c()?.workDays, 1)
        XCTAssertEqual(c()?.unassignedDays, 3)
        WorkloadCounter.rules = WorkloadRules()
        // 手动纠正：13 日其实休息，15 日不算
        WorkloadCounter.overrides = ["甲": [d(13): "休息", d(15): WorkloadCounter.excluded]]
        XCTAssertEqual(c()?.workDays, 1)
        XCTAssertEqual(c()?.presentDays, 2)
        XCTAssertEqual(c()?.offDays, 2)
        // 规则从 JSON 读：缺的字段用默认
        let rules = try? JSONDecoder().decode(WorkloadRules.self, from: Data(#"{"blankWorkdayIsWork":false}"#.utf8))
        XCTAssertEqual(rules?.blankWorkdayIsWork, false)
        XCTAssertEqual(rules?.holidayDutyRestCounts, false)
        // 旧版本存的「值班后休息算工作量」打开：升级后关掉（写了休息就不算）；新版本存的照原样
        let old = try? JSONDecoder().decode(WorkloadRules.self, from: Data(#"{"holidayDutyRestCounts":true}"#.utf8))
        XCTAssertEqual(old?.holidayDutyRestCounts, false)
        // 版本 3 起节假日值班后没写的那天也不算：旧设置里打开的都关掉
        let v2 = try? JSONDecoder().decode(WorkloadRules.self, from: Data(#"{"holidayDutyRestCounts":true,"blankHolidayAfterDutyIsRest":true,"version":2}"#.utf8))
        XCTAssertEqual(v2?.holidayDutyRestCounts, false)
        XCTAssertEqual(v2?.blankHolidayAfterDutyIsRest, false)
        let new = try? JSONDecoder().decode(WorkloadRules.self, from: Data(#"{"holidayDutyRestCounts":true,"version":3}"#.utf8))
        XCTAssertEqual(new?.holidayDutyRestCounts, true)
        let saved = try? JSONDecoder().decode(WorkloadRules.self, from: JSONEncoder().encode(WorkloadRules()))
        XCTAssertEqual(saved, WorkloadRules())
    }

    func testMergeKeepsLeaveWhenSourceHasNoRestColumn() {
        // 之前读电脑版：甲 15 日休息、乙 15 日组A、丙 16 日请假
        let old: Roster = ["甲": [d(15): "休息"], "乙": [d(15): "组A"], "丙": [d(16): "请假"], "丁": [d(15): "组C"]]
        // 这次的读取不带休息列：15 日只有乙组B
        let a = RosterExtractor.replacingDays(of: old, with: ["乙": [d(15): "组B"]], matcher: m)
        XCTAssertEqual(a["甲"]?[d(15)], "休息")          // 休息保留
        XCTAssertEqual(a["乙"]?[d(15)], "组B")           // 岗位以新的为准
        XCTAssertNil(a["丁"]?[d(15)])                    // 没读到的岗位照常去掉
        XCTAssertEqual(a["丙"]?[d(16)], "请假")          // 没读到的日子不动
        // 这次读到的 15 日有休息列（戊休息）：整天以新的为准，甲的休息取消了
        let b = RosterExtractor.replacingDays(of: old, with: ["乙": [d(15): "组B"], "戊": [d(15): "休息"]], matcher: m)
        XCTAssertNil(b["甲"]?[d(15)])
        XCTAssertEqual(b["戊"]?[d(15)], "休息")
        // 这次读到的别的日子有休息列（16 日戊请假）：说明带休息列，15 日甲的休息没了就是取消了
        let c = RosterExtractor.replacingDays(of: old, with: ["乙": [d(15): "组B"], "戊": [d(16): "请假"]], matcher: m)
        XCTAssertNil(c["甲"]?[d(15)])
    }

    func testRestBalanceHistory() {
        let text = "日期\t星期\t遥测\t休息\n2026-10-12\t周一\t张三(5)\t李四(3) 王五（２）\n2026-10-13\t周二\t张三(4)\t组A(1)"
        let byDay = RestBalanceHistory.fromTable(text, reference: d(12), matcher: m)
        XCTAssertEqual(byDay["张三"], [d(12): 5, d(13): 4])
        XCTAssertEqual(byDay["李四"], [d(12): 3])
        XCTAssertEqual(byDay["王五"], [d(12): 2])
        XCTAssertNil(byDay["组A"])

        // 合并：按日期排好，只留数字变了的点；表上读的不覆盖当场读到的
        let merged = RestBalanceHistory.merge([(d(1), 2, true), (d(5), 3, true)], [d(3): 2, d(5): 4, d(8): 4, d(12): 2], live: false)
        XCTAssertEqual(merged.map { $0.day }, [d(1), d(5), d(8), d(12)])
        XCTAssertEqual(merged.map { $0.value }, [2, 3, 4, 2])
        // 当场读到的覆盖同一天表上读的
        let live = RestBalanceHistory.merge(merged, [d(12): 5], live: true)
        XCTAssertEqual(live.last?.value, 5)
        XCTAssertEqual(live.last?.live, true)
        // 以前几周每个人的数字都一样：是现在的数字，不当历史
        let flat: [String: [DayKey: Int]] = ["甲": [d(1): 3, d(20): 3], "乙": [d(1): 1, d(20): 1], "丙": [d(2): 0, d(18): 0]]
        XCTAssertTrue(RestBalanceHistory.looksLikeSnapshot(flat))
        XCTAssertFalse(RestBalanceHistory.looksLikeSnapshot(flat.merging(["丁": [d(1): 2, d(20): 4]]) { a, _ in a }))

        // 说明：5 日 2→3（前面 3 日国庆遥测），12 日 3→2（9 日调休）；最新的在前
        let steps = RestBalanceHistory.steps(points: [(d(1), 2, true), (d(5), 3, false), (d(12), 2, true)],
                                             history: [d(3): "遥测", d(9): "调休", d(10): "组A"], matcher: m, calendar: cal)
        XCTAssertEqual(steps.map(\.day), [d(12), d(5)])
        XCTAssertEqual(steps.map(\.delta), [-1, 1])
        XCTAssertTrue(steps[1].events.contains { $0.day == d(3) && $0.post == "遥测" && $0.tag == "节假日" })
        XCTAssertTrue(steps[0].events.contains { $0.day == d(9) && $0.post == "调休" })
        XCTAssertFalse(steps[0].events.contains { $0.post == "组A" })
    }

    func testNamesGluedTogetherInCell() {
        XCTAssertEqual(RosterExtractor.names(inCell: "张三(5)李四(3)王小五（2）", matcher: m), ["张三", "李四", "王小五"])
    }

    func testRestColumnWithTwoPeople() {
        // 休息一格里两个人：换行、竖线、冒号隔开都要读到
        XCTAssertEqual(RosterExtractor.names(inCell: "张三(5)\n李四(3)", matcher: m), ["张三", "李四"])
        XCTAssertEqual(RosterExtractor.names(inCell: "休息：张三|李四", matcher: m), ["张三", "李四"])
        XCTAssertEqual(RosterExtractor.names(inCell: "张三\u{00A0}李四", matcher: m), ["张三", "李四"])
        // 接口里一条记录两个人
        let json = """
        {"data":[
          {"dutyDate":"2026-10-07","userName":"张伟","postName":"组D"},
          {"dutyDate":"2026-10-07","userName":"刘洋","postName":"组A"},
          {"dutyDate":"2026-10-07","userName":"杨帆、王芳","postName":"休息"},
          {"dutyDate":"2026-10-08","userName":"杨帆","postName":"组B"},
          {"dutyDate":"2026-10-08","userName":"王芳","postName":"组C"}
        ]}
        """
        let roster = RosterExtractor.fromJSON(json, reference: DayKey(year: 2026, month: 10, day: 9), matcher: m)
        XCTAssertEqual(roster["杨帆"]?[d(7)], "休息")
        XCTAssertEqual(roster["王芳"]?[d(7)], "休息")
        // 两个名字挨在一起没隔开：两半都是认识的人就拆开
        let glued: Roster = ["张三李四": [d(7): "休息"], "张三": [d(8): "组A"], "李四": [d(8): "组B"]]
        let split = RosterExtractor.splitJoinedNames(glued)
        XCTAssertNil(split["张三李四"])
        XCTAssertEqual(split["张三"], [d(7): "休息", d(8): "组A"])
        XCTAssertEqual(split["李四"], [d(7): "休息", d(8): "组B"])
        // 三四个人挨在一起也能拆开；拆不开的一长串（一句话）不当成人
        XCTAssertEqual(RosterExtractor.names(inCell: "张三李四王小五", matcher: m), ["张三李四王小五"])
        let many: Roster = ["张三李四王小五赵六": [d(7): "休息"], "张三": [d(8): "组A"], "李四": [d(8): "组B"],
                            "王小五": [d(8): "组C"], "赵六": [d(8): "组D"], "负责数据传输监控": [d(7): "组A"]]
        let parts = RosterExtractor.splitJoinedNames(many)
        XCTAssertEqual(Set(parts.keys), ["张三", "李四", "王小五", "赵六"])
        for name in ["张三", "李四", "王小五", "赵六"] { XCTAssertEqual(parts[name]?[d(7)], "休息", name) }
        // 表格一格里四个人，用什么隔开都行
        XCTAssertEqual(RosterExtractor.names(inCell: "张三(5) 李四(3)\n王小五、赵六", matcher: m), ["张三", "李四", "王小五", "赵六"])
        // 真的四个字的名字不拆
        XCTAssertEqual(RosterExtractor.splitJoinedNames(["欧阳建国": [d(7): "组A"], "张三": [d(8): "组B"]]).count, 2)
    }

    func testTeamChanges() {
        let before: Roster = ["甲": [d(15): "组A"], "乙": [d(15): "组B"], "丙": [d(15): "休息"], "丁": [d(16): "休息"]]
        let after: Roster = ["甲": [d(15): "组B"], "乙": [d(15): "组A"], "丙": [d(15): "休息"],
                             "丁": [d(16): "遥测"], "戊": [d(17): "组C"]]
        let c = RosterDiff.changes(before: before, after: after, days: [d(15), d(16), d(17)], matcher: m)
        XCTAssertEqual(c.map(\.summary), ["组A：甲 → 乙", "组B：乙 → 甲"])   // 16 日之前没人有岗位，17 日之前没数据：不算
        XCTAssertTrue(c[0].involves("甲"))
    }

    func testDataCheck() {
        // 甲 10/12 周一遥测，13 日网站上什么都没写；10/12–10/16 每天都有 6 人
        var roster: Roster = ["甲": [d(12): "遥测", d(14): "组A"], "乙": [d(12): "测控岗"]]
        for i in 0..<6 { roster["人\(i)"] = Dictionary(uniqueKeysWithValues: (12...16).map { (d($0), "组B") }) }
        roster["人0"]?[d(16)] = nil
        for i in 1..<6 { roster["人\(i)"]?[d(16)] = nil }   // 16 日只剩甲乙以外 0 人
        roster["人0"]?[d(17)] = "遥测"      // 周六只有值班的人：不算人数偏少
        let issues = DataCheck.issues(roster: roster, published: Set((12...17).map(d)), matcher: m, members: nil,
                                      today: d(17), calendar: cal)
        XCTAssertFalse(issues.contains { $0.kind == .thinDay && $0.day == d(17) })
        XCTAssertTrue(issues.contains { $0.kind == .noRestAfterDuty && $0.name == "甲" && $0.day == d(13) }, "\(issues)")
        XCTAssertTrue(issues.contains { $0.kind == .unknownPost && $0.text.contains("测控岗") })
        XCTAssertTrue(issues.contains { $0.kind == .thinDay && $0.day == d(16) })
    }
}

final class PatternTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    let m = ShiftMatcher(types: ShiftType.defaults)
    /// d(1) = 2026-11-02 周一
    let d = { (i: Int) in DayKey(year: 2026, month: 11, day: i + 1) }

    func testDutyRotationWithDeferralAndException() {
        // 甲乙丙丁按顺序轮；6 日乙请假，丙先值、乙第二天补上；11 日本该乙，丁指定日期
        let order = ["甲", "乙", "丙", "丁", "甲", "丙", "乙", "丁", "甲", "丙", "丁", "乙"]
        var roster: Roster = [:]
        for (i, name) in order.enumerated() { roster[name, default: [:]][d(i + 1)] = "遥测" }
        roster["乙"]?[d(6)] = "请假"
        let r = SchedulePatterns.rotation(post: "遥测", roster: roster, days: (1...12).map(d), matcher: m, forecastDays: 4, calendar: cal)
        XCTAssertEqual(r?.slots, 12)
        XCTAssertEqual(r?.matched, 11)
        XCTAssertEqual(r?.strictMatched, 10)                 // 不管请假的话 6 日也猜错
        XCTAssertEqual(r?.deferrals, [SchedulePatterns.Deferral(day: d(6), name: "乙", reason: "请假")])
        XCTAssertEqual(r?.exceptions, [SchedulePatterns.Exception(day: d(11), actual: "丁", expected: "乙")])
        XCTAssertEqual(r?.order, ["甲", "丙", "丁", "乙"])
        XCTAssertEqual(r?.forecast.map(\.name), ["甲", "丙", "丁", "乙"])
        XCTAssertEqual(r?.forecast.first?.day, d(13))
    }

    func testDutyRotationFixedOrder() {
        // 8 人按固定顺序一轮一轮值；第二轮辛指定日期提前值了，这一轮后面就不再轮到他，下一轮照原来的顺序
        let base = DayKey(year: 2026, month: 11, day: 2)
        let e = { (i: Int) in base.adding(days: i - 1, calendar: self.cal) }
        let people = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛"]
        let round2 = ["甲", "乙", "辛", "丙", "丁", "戊", "己", "庚"]
        let order = people + round2 + people + people
        var roster: Roster = [:]
        for (i, name) in order.enumerated() { roster[name, default: [:]][e(i + 1)] = "遥测" }
        let r = SchedulePatterns.rotation(post: "遥测", roster: roster, days: (1...32).map(e), matcher: m,
                                          forecastDays: 3, calendar: cal)
        XCTAssertEqual(r?.slots, 32)
        XCTAssertEqual(r?.matched, 31)                    // 只猜错辛提前的那天
        XCTAssertTrue(r?.model.contains("固定顺序") == true)
        XCTAssertEqual(r?.exceptions, [SchedulePatterns.Exception(day: e(11), actual: "辛", expected: "丙")])
        XCTAssertEqual(r?.order, people)
        XCTAssertEqual(r?.forecast.map(\.name), ["甲", "乙", "丙"])
        XCTAssertEqual(r?.forecast.first?.day, e(33))
    }

    func testSiteAPIWeekly() {
        // 仿网站接口：每周排班（一格几个人）、人员表、公告（名字都是编的）
        let weekly = """
        {"data":[
          {"date":"2026-11-02","weekday":"周一","telemetry":"张甲","rest":"李乙、王丙","beforeHandover":"赵丁","timeOff":"钱戊",
           "assignments":{"组A":"孙己","组B":"-"},"fixedAssignments":{"telemetry":0},"noRestFlags":{"rest":{"active":0}}},
          {"date":"2026-11-03","weekday":"周二","telemetry":"李乙","rest":"-","beforeHandover":"张甲","leave":"周庚","businessTrip":"吴辛",
           "assignments":{"组A":"王丙","组B":"赵丁"},"fixedAssignments":{"telemetry":1}}
        ]}
        """
        let persons = """
        [{"name":"张甲","onDuty":1,"telemetryWeekdays":"1、3、5","unrestDays":2},{"name":"李乙","onDuty":0,"telemetryWeekdays":"2"}]
        """
        let notice = #"{"rows":[{"text":"未来如有请假、出差、调休的同事，请在值班系统提前申请日期","hidden":0}]}"#
        let r = SiteAPI.parse([weekly, persons, notice], reference: d(1), matcher: m)
        XCTAssertEqual(r.roster["张甲"]?[d(1)], "遥测")
        XCTAssertEqual(r.roster["李乙"]?[d(1)], "休息")
        XCTAssertEqual(r.roster["王丙"]?[d(1)], "休息")                 // 一格两个人都读到
        XCTAssertEqual(r.roster["赵丁"]?[d(1)], "值班交接前")
        XCTAssertEqual(r.roster["钱戊"]?[d(1)], "调休")
        XCTAssertEqual(r.roster["孙己"]?[d(1)], "组A")
        XCTAssertEqual(r.roster["周庚"]?[d(2)], "请假")
        XCTAssertEqual(r.roster["吴辛"]?[d(2)], "出差")
        XCTAssertEqual(r.fixedTelemetryDays, [d(2)])
        XCTAssertEqual(r.people["张甲"]?.telemetryWeekdays, [1, 3, 5])
        XCTAssertEqual(r.people["张甲"]?.unrestDays, 2)
        XCTAssertEqual(r.people["李乙"]?.onDuty, false)
        XCTAssertEqual(r.notices.count, 1)
        // 打码：一格几个人每个都打码
        XCTAssertEqual(APIFieldInspector.mask("王小明、李四"), "王**、李*")
    }

    func testSiteAPIExtras() {
        // 该休没休的标记、各组负责的星（编号换成名字）
        let weekly = """
        [{"date":"2026-11-02","telemetry":"张甲","rest":"李乙","noRestFlags":{"rest":{"active":1,"persons":["王丙","赵丁"]},
          "beforeHandover":{"active":0,"person":""}}},
         {"date":"2026-11-03","telemetry":"李乙","rest":"张甲","noRestFlags":{"rest":{"active":0}}}]
        """
        let groups = #"[{"groupName":"组A","order":1,"satellites":["S1","S2"]},{"groupName":"组B","order":2,"satellites":["S3"]}]"#
        let sats = #"[{"satelliteId":"S1","satelliteName":"一号星"},{"satelliteId":"S2","satelliteName":"二号星"}]"#
        let r = SiteAPI.parse([weekly, groups, sats], reference: d(1), matcher: m)
        XCTAssertEqual(Set(r.noRest), [SiteAPI.NoRest(day: d(1), name: "王丙", column: "休息"),
                                       SiteAPI.NoRest(day: d(1), name: "赵丁", column: "休息")])
        XCTAssertEqual(r.groupSatellites["组A"], "一号星、二号星")
        XCTAssertEqual(r.groupSatellites["组B"], "S3")
        // 节假日公开数据
        let feed = #"{"year":2027,"days":[{"name":"元旦","date":"2027-01-01","isOffDay":true},{"name":"春节","date":"2027-02-07","isOffDay":false}]}"#
        let parsed = HolidayFeed.parse(Data(feed.utf8))
        XCTAssertEqual(parsed?.off, ["2027-01-01"])
        XCTAssertEqual(parsed?.work, ["2027-02-07"])
        defer { ChinaHolidays.downloadedOff = []; ChinaHolidays.downloadedWork = [] }
        ChinaHolidays.downloadedOff = Set(parsed?.off ?? [])
        ChinaHolidays.downloadedWork = Set(parsed?.work ?? [])
        XCTAssertTrue(ChinaHolidays.isHoliday(DayKey(year: 2027, month: 1, day: 1)))
        XCTAssertTrue(ChinaHolidays.isWorkday(DayKey(year: 2027, month: 2, day: 7), calendar: cal))   // 周日调休上班
        XCTAssertTrue(ChinaHolidays.knownYears.contains(2027))
        // 认出「我是谁」：我的分工和全员排班里张甲的一致
        var mine: [DayKey: String] = [:]
        var roster: Roster = ["李乙": [:]]
        for i in 1...6 {
            mine[d(i)] = i % 2 == 0 ? "遥测" : "组A"
            roster["张甲", default: [:]][d(i)] = mine[d(i)]
            roster["李乙"]?[d(i)] = "组B"
        }
        XCTAssertEqual(RosterExtractor.identify(mine: mine, roster: roster, matcher: m), "张甲")
        XCTAssertNil(RosterExtractor.identify(mine: [d(1): "组A"], roster: roster, matcher: m))   // 太少，不认
    }

    func testDutyRotationTwoLines() {
        // 工作日生产岗丙丁戊轮，周末研发岗甲乙轮（网站两份轮转名单）
        let base = DayKey(year: 2026, month: 11, day: 2)      // 周一
        let e = { (i: Int) in base.adding(days: i - 1, calendar: self.cal) }
        var roster: Roster = [:]
        var p = 0, q = 0
        for i in 1...21 {
            let weekend = SiteAPI.siteWeekday(e(i), calendar: cal) >= 6
            let name = weekend ? ["甲", "乙"][q % 2] : ["丙", "丁", "戊"][p % 3]
            if weekend { q += 1 } else { p += 1 }
            roster[name, default: [:]][e(i)] = "遥测"
        }
        let people = ["甲": SiteAPI.Person(category: "研发岗"), "乙": SiteAPI.Person(category: "研发岗"),
                      "丙": SiteAPI.Person(category: "生产岗"), "丁": SiteAPI.Person(category: "生产岗"),
                      "戊": SiteAPI.Person(category: "生产岗")]
        let plain = SchedulePatterns.rotation(post: "遥测", roster: roster, days: (1...21).map(e), matcher: m, calendar: cal)
        let r = SchedulePatterns.rotation(post: "遥测", roster: roster, days: (1...21).map(e), matcher: m,
                                          forecastDays: 7, calendar: cal, people: people)
        XCTAssertEqual(r?.slots, 21)
        XCTAssertEqual(r?.matched, 21)
        XCTAssertLessThan(plain?.matched ?? 0, 21)
        XCTAssertTrue(r?.model.contains("两条线") == true)
        // 往后推：周末是研发岗，工作日是生产岗
        for f in r?.forecast ?? [] {
            let weekend = SiteAPI.siteWeekday(f.day, calendar: cal) >= 6
            XCTAssertEqual(people[f.name]?.category, weekend ? "研发岗" : "生产岗", "\(f.day)")
        }
    }

    func testRosterPreview() {
        // 5 人轮流值了 10 天；网站排到第 10 天。预演第 11 天起：甲值，前一天戊值完在休息；丙已经申请了请假
        let base = DayKey(year: 2026, month: 11, day: 2)      // 周一
        let e = { (i: Int) in base.adding(days: i - 1, calendar: self.cal) }
        var roster: Roster = [:]
        for (i, name) in ["甲", "乙", "丙", "丁", "戊", "甲", "乙", "丙", "丁", "戊"].enumerated() {
            roster[name, default: [:]][e(i + 1)] = "遥测"
        }
        roster["丙"]?[e(12)] = "请假"
        let published = Set((1...10).map(e))
        let r = SchedulePatterns.rotation(post: "遥测", roster: roster, days: published.sorted(), matcher: m,
                                          forecastDays: 5, calendar: cal)!
        let preview = RosterPreview.build(rotation: r, roster: roster, published: published, from: e(1), days: 3,
                                          matcher: m, calendar: cal)
        XCTAssertEqual(preview.map(\.day), [e(11), e(12), e(13)])
        XCTAssertEqual(preview[0].telemetry, "甲")
        XCTAssertTrue(preview[0].resting.contains("戊"))           // 10 号（周三）值完，11、12 号休
        XCTAssertEqual(preview[1].away, ["丙（请假）"])
        XCTAssertNotEqual(preview[1].telemetry, "丙")               // 请假的跳过
    }

    func testRotationRespectsSiteWeekdays() {
        // 5 人轮流值；网站人员表里甲只能周一、周六值遥测：下一个本该是甲的周四，跳过甲
        let base = DayKey(year: 2026, month: 11, day: 2)      // 周一
        let e = { (i: Int) in base.adding(days: i - 1, calendar: self.cal) }
        var roster: Roster = [:]
        let order = ["甲", "乙", "丙", "丁", "戊", "甲", "乙", "丙", "丁", "戊"]
        for (i, name) in order.enumerated() { roster[name, default: [:]][e(i + 1)] = "遥测" }
        let plain = SchedulePatterns.rotation(post: "遥测", roster: roster, days: (1...10).map(e), matcher: m,
                                              forecastDays: 1, calendar: cal)
        XCTAssertEqual(plain?.forecast.first?.name, "甲")
        let people = ["甲": SiteAPI.Person(onDuty: true, telemetryWeekdays: [1, 6])]
        let r = SchedulePatterns.rotation(post: "遥测", roster: roster, days: (1...10).map(e), matcher: m,
                                          forecastDays: 1, calendar: cal, people: people)
        XCTAssertEqual(r?.usesSiteSettings, true)
        XCTAssertEqual(r?.slots, 10)
        XCTAssertEqual(r?.forecast.first?.day, e(11))          // 周四
        XCTAssertEqual(r?.forecast.first?.name, "乙")
    }

    func testHolidayDutyPlanner() {
        // 端午 6/19–21 甲值过遥测；下一个节假日是中秋 9/25–27（3 天）。乙丙丁端午没值；丙平时值得最少
        let d = { (m: Int, day: Int) in DayKey(year: 2026, month: m, day: day) }
        let roster: Roster = [
            "甲": [d(6, 20): "遥测", d(7, 5): "遥测"],
            "乙": [d(7, 12): "遥测", d(7, 20): "遥测", d(8, 1): "遥测"],
            "丙": [d(7, 13): "遥测"],
            "丁": [d(7, 14): "遥测", d(8, 2): "遥测"],
        ]
        let plan = HolidayDutyPlanner.plan(roster: roster, today: d(9, 1), matcher: m, calendar: cal)
        XCTAssertEqual(plan?.days, [d(9, 25), d(9, 26), d(9, 27)])
        XCTAssertEqual(plan?.lastHoliday, [d(6, 19), d(6, 20), d(6, 21)])
        XCTAssertEqual(plan?.listDate, d(9, 11))
        XCTAssertEqual(plan?.reserve.map(\.name), ["丙", "丁", "乙"])     // 没值端午的、值得少的先
        XCTAssertEqual(plan?.others.map(\.name), ["甲"])
        XCTAssertEqual(plan?.others.first?.servedLastHoliday, true)
    }

    func testMatcherPostsAndIndex() {
        var matcher = ShiftMatcher(types: ShiftType.defaults)
        XCTAssertEqual(matcher.posts("组A+遥测"), ["组A", "遥测"])
        XCTAssertEqual(matcher.posts("组A、组E / 调度"), ["组A", "组E", "调度"])
        XCTAssertEqual(matcher.match("遥测")?.id, "telemetry")
        // 改了班次类型后，预先整理的关键词跟着更新
        matcher.types.append(ShiftType(id: "x", name: "测控", emoji: "🛰️", colorHex: "#000000", keywords: ["测控"]))
        XCTAssertEqual(matcher.match("测控岗")?.id, "x")
    }

    func testScriptScanner() {
        let app = "var a=1;function next(){/* 遥测按顺序轮，请假顺延 */return list.sort((x,y)=>x.lastDuty-y.lastDuty)[0]};" + String(repeating: "x", count: 2000) + "var shift=1;"
        let vendor = "function sort(){/* 排班 */}"
        let snippets = ScriptScanner.scan([ScriptScanner.Script(source: "https://example.com/js/app.123.js", text: app),
                                           ScriptScanner.Script(source: "https://example.com/js/chunk-vendors.js", text: vendor)])
        XCTAssertEqual(snippets.count, 1)                      // 第三方库跳过；单独一个 shift 不算
        XCTAssertTrue(snippets[0].keywords.contains("遥测"))
        XCTAssertTrue(snippets[0].keywords.contains("顺延"))
        XCTAssertTrue(snippets[0].text.contains("lastDuty"))
        XCTAssertEqual(ScriptScanner.readable("a=1;if(b){c=\"x;y\"}"), "a=1;\nif(b){\nc=\"x;y\"}")
        let parsed = ScriptScanner.scripts(fromJSON: #"[{"s":"a.js","t":"var x=1"}]"#)
        XCTAssertEqual(parsed, [ScriptScanner.Script(source: "a.js", text: "var x=1")])
    }

    func testAPIFieldInspector() {
        let body = """
        {"code":0,"data":{"list":[
          {"dutyDate":"2026-11-02","userName":"张伟","postName":"遥测","sortNo":3,"phone":"13812345678"},
          {"dutyDate":"2026-11-03","userName":"刘洋","postName":"遥测","sortNo":4,"phone":"13987654321"}
        ]}}
        """
        let tables = APIFieldInspector.summarize([CapturedRequest(url: "https://example.com/api/duty/list?d=1", method: "GET", body: body)])
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables.first?.path, "/api/duty/list")
        XCTAssertEqual(tables.first?.rows, 2)
        let fields = Dictionary(uniqueKeysWithValues: (tables.first?.fields ?? []).map { ($0.name, $0) })
        XCTAssertEqual(fields["userName"]?.samples, ["张*", "刘*"])          // 人名只留姓
        XCTAssertEqual(fields["phone"]?.samples.first, "138********")       // 长数字只留前三位
        XCTAssertEqual(fields["sortNo"]?.looksLikeOrder, true)
        XCTAssertEqual(fields["postName"]?.looksLikeOrder, false)
        XCTAssertTrue(APIFieldInspector.text(tables).contains("★ sortNo"))
    }

    func testRestAfterDutyRule() {
        // 规则：周一值休二三，周五值休六日一，周六值休日一二，周日值休一二三
        XCTAssertEqual(SchedulePatterns.expectedRest(after: d(1), calendar: cal), [d(2), d(3)])
        XCTAssertEqual(SchedulePatterns.expectedRest(after: d(5), calendar: cal), [d(6), d(7), d(8)])
        XCTAssertEqual(SchedulePatterns.expectedRest(after: d(6), calendar: cal), [d(7), d(8), d(9)])
        XCTAssertEqual(SchedulePatterns.expectedRest(after: d(7), calendar: cal), [d(8), d(9), d(10)])
        // 甲周五值，周一写了休息，周二回来：符合；乙周一值，只休了周二，周三就上组A：不符合
        let roster: Roster = ["甲": [d(5): "遥测", d(8): "休息"], "乙": [d(1): "遥测", d(2): "休息", d(3): "组A"]]
        let rule = SchedulePatterns.restRule(roster: roster, days: (1...12).map(d), published: Set((1...14).map(d)),
                                             matcher: m, calendar: cal)
        XCTAssertEqual(rule.duties, 2)
        XCTAssertEqual(rule.matched, 1)
        let friday = rule.rows.first { $0.weekday == 6 }
        XCTAssertEqual(friday?.expected, "六日一")
        XCTAssertEqual(friday?.typical, "六日一")
        XCTAssertEqual(rule.exceptions, [SchedulePatterns.RestException(day: d(1), name: "乙", expected: "二三", actual: "二")])
    }

    func testDutyAndTelemetryAreTheSame() {
        XCTAssertTrue(WorkloadCounter.isDuty("遥测"))
        XCTAssertTrue(WorkloadCounter.isDuty("值班"))
        XCTAssertFalse(WorkloadCounter.isDuty("值班交班前"))
        XCTAssertFalse(WorkloadCounter.isDuty("值班交接前"))
        XCTAssertEqual(WorkloadCounter.effective("值班交接前", matcher: m), WorkloadCounter.handoverRest)
        XCTAssertTrue(WorkloadCounter.isDuty(m.displayName("值")))
        // 网站上有的写遥测、有的写值班：都在同一个轮转里
        var roster: Roster = [:]
        for (i, name) in ["甲", "乙", "丙", "甲", "乙", "丙"].enumerated() {
            roster[name, default: [:]][d(i + 1)] = i % 2 == 0 ? "遥测" : "值班"
        }
        let r = SchedulePatterns.rotation(post: "遥测", roster: roster, days: (1...6).map(d), matcher: m, calendar: cal)
        XCTAssertEqual(r?.slots, 6)
        XCTAssertEqual(r?.matched, 6)

        // 「值班交接前」这一列的人前一天值了遥测，今天算休息
        XCTAssertEqual(WorkloadCounter.effective("值班交班前", matcher: m), WorkloadCounter.handoverRest)
        XCTAssertEqual(WorkloadCounter.effective("组A+值班交班前", matcher: m), "组A+" + WorkloadCounter.handoverRest)
        XCTAssertTrue(RosterExtractor.isLeave("值班交接前", matcher: m))
        // 周二在交接前一列：休息，不算工作量也不算上班
        let handover = WorkloadCounter.count(roster: ["丁": [d(1): "遥测", d(2): "值班交接前", d(3): "休息"]],
                                             days: (1...5).map(d), matcher: m, calendar: cal).first
        XCTAssertEqual(handover?.dutyDays, 1)
        XCTAssertEqual(handover?.offDays, 2)
        XCTAssertEqual(handover?.presentDays, 3)     // 周一遥测 + 周四、周五没排（不轮组别：日常）
        let w = WorkloadCounter.count(roster: ["乙": [d(1): "组A", d(6): "值班交班前"]], days: (1...7).map(d), matcher: m, calendar: cal).first
        XCTAssertEqual(w?.regularDays, 1)
        XCTAssertEqual(w?.attendanceDays, 4)   // 周六只有值班交班前：不算上班
        XCTAssertEqual(w?.offDays, 2)
        XCTAssertNil(w?.posts["值班交班前"])
        // 值完遥测第二天只写了值班交班前：不算回来上班
        let rule = SchedulePatterns.restRule(roster: ["丙": [d(1): "遥测", d(2): "值班交班前+休息", d(3): "休息"]],
                                             days: (1...7).map(d), published: Set((1...7).map(d)), matcher: m, calendar: cal)
        XCTAssertEqual(rule.matched, 1)
    }

    func testGroupMembersVersusDailyStaff() {
        // 10/12 周一 … 10/16 周五：甲轮组别，乙不轮组别（只值遥测、出差），丙是调度
        let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }
        let roster: Roster = [
            "甲": [d(12): "组A", d(13): "组B"],
            "乙": [d(12): "遥测", d(13): "出差"],
            "丙": [d(5): "调度", d(6): "调度", d(9): "调度", d(12): "调度"],
        ]
        XCTAssertTrue(WorkloadCounter.isGroupMember(history: roster["甲"]!, matcher: m))
        XCTAssertFalse(WorkloadCounter.isGroupMember(history: roster["乙"]!, matcher: m))
        let r = Dictionary(uniqueKeysWithValues: WorkloadCounter.count(roster: roster, days: (12...16).map(d), matcher: m, calendar: cal)
            .map { ($0.name, $0) })
        XCTAssertEqual(r["甲"]?.workDays, 2)          // 14–16 日没排：上班，不算工作量
        XCTAssertEqual(r["甲"]?.attendanceDays, 3)
        XCTAssertEqual(r["乙"]?.workDays, 5)          // 14–16 日没排：做别的日常工作，算工作量
        XCTAssertEqual(r["乙"]?.attendanceDays, 0)
        XCTAssertEqual(r["丙"]?.workDays, 1)          // 调度：没排的不算
        XCTAssertEqual(r["丙"]?.unassignedDays, 4)
    }

    func testSyncHealth() {
        let ok = SyncHealth.Metrics(people: 30, days: 28, leaves: 40, groups: 100)
        let history = [ok, ok, SyncHealth.Metrics(people: 29, days: 28, leaves: 35, groups: 98)]
        XCTAssertTrue(SyncHealth.problems(ok, history: history).isEmpty)
        // 改版后休息列读不到了
        let noLeave = SyncHealth.Metrics(people: 30, days: 28, leaves: 0, groups: 100)
        XCTAssertEqual(SyncHealth.problems(noLeave, history: history).count, 1)
        XCTAssertTrue(SyncHealth.problems(noLeave, history: history)[0].contains("休息"))
        // 人数掉了一大半、组别也没了
        let broken = SyncHealth.Metrics(people: 9, days: 28, leaves: 10, groups: 0)
        XCTAssertEqual(SyncHealth.problems(broken, history: history).count, 2)
        // 记录不到 3 次：先不判断
        XCTAssertTrue(SyncHealth.problems(broken, history: [ok]).isEmpty)
        // 从全员排班算
        let roster: Roster = ["甲": [d(1): "组A", d(2): "休息"], "乙": [d(1): "遥测"]]
        XCTAssertEqual(SyncHealth.metrics(roster, matcher: m), SyncHealth.Metrics(people: 2, days: 2, leaves: 1, groups: 1))
    }

    func testRestWarnings() {
        // 甲周五遥测，周一应该休却排了组A；乙周一遥测，周三网站上没写休息
        let roster: Roster = ["甲": [d(5): "遥测", d(8): "组A"], "乙": [d(1): "遥测", d(2): "休息"]]
        let published = Set((1...14).map(d))
        let a = SchedulePatterns.restWarnings(name: "甲", roster: roster, published: published, from: d(1), matcher: m, calendar: cal)
        XCTAssertEqual(a.map(\.day), [d(8)])
        XCTAssertEqual(a.first?.kind, .assigned)
        XCTAssertTrue(a.first?.text.contains("应休六日一") == true, a.first?.text ?? "")
        XCTAssertTrue(a.first?.text.contains("组A") == true)
        let b = SchedulePatterns.restWarnings(name: "乙", roster: roster, published: published, from: d(1), matcher: m, calendar: cal)
        XCTAssertEqual(b.map(\.day), [d(3)])
        XCTAssertEqual(b.first?.kind, .unmarked)
        // 已经过去很久的不提醒
        XCTAssertTrue(SchedulePatterns.restWarnings(name: "甲", roster: roster, published: published, from: d(12), matcher: m, calendar: cal).isEmpty)
    }

    func testRestBalanceAuditFindsRule() {
        // 真实规则：周五到周日值遥测 +1，调休 −1，平时遥测和休息不变
        let roster: Roster = [
            "甲": [d(6): "遥测"],
            "乙": [d(9): "调休"],
            "丙": [d(2): "遥测", d(3): "休息", d(4): "休息"],
            "丁": [d(7): "遥测", d(12): "遥测"],
            "戊": [d(6): "遥测"],                      // 网站上没加：对不上
        ]
        let p = { [d] (a: Int, b: Int) -> [RestBalanceHistory.Point] in [(d(1), a, true), (d(25), b, true)] }
        let points = ["甲": p(2, 3), "乙": p(5, 4), "丙": p(1, 1), "丁": p(0, 2), "戊": p(3, 3)]
        let r = RestBalanceAudit.analyze(points: points, roster: roster, matcher: m, calendar: cal)
        XCTAssertEqual(r?.rule, RestBalanceAudit.Rule(longDuty: 1, shortDuty: 0, overtime: 0, compRest: -1, rest: 0, leave: 0))
        XCTAssertEqual(r?.rule.text, "周五到周日、节假日值遥测 +1，调休 −1")
        XCTAssertEqual(r?.matched, 4)
        XCTAssertEqual(r?.rows.first?.name, "戊")
        XCTAssertEqual(r?.rows.first?.diff, -1)
    }

    func testGroupRotationAndResumeAfterLeave() {
        let groups = ["组A", "组B", "组C"]
        let workdays = [1, 2, 3, 4, 5, 8, 9, 10, 11, 12].map(d)   // 两周的周一到周五
        var roster: Roster = [:]
        for p in 0..<3 {
            let name = ["甲", "乙", "丙"][p]
            var step = p
            for day in workdays {
                // 甲周三请假，回来接着上次的组往下排
                if p == 0 && day == d(3) { roster[name, default: [:]][day] = "请假"; continue }
                roster[name, default: [:]][day] = groups[step % 3]
                step += 1
            }
        }
        roster["乙"]?[d(12)] = "组A"   // 手动调整
        let g = SchedulePatterns.groupPattern(roster: roster, days: (1...12).map(d), matcher: m, calendar: cal)
        XCTAssertEqual(g?.groups, groups)
        XCTAssertTrue(g?.best?.title.hasPrefix("每个上班日往后挪一组") == true, g?.best?.title ?? "")
        XCTAssertEqual(g?.resumeTotal, 1)
        XCTAssertEqual(g?.resumeHits, 1)
        XCTAssertEqual(g?.calendarHits, 0)
        XCTAssertEqual(g?.adjustments.map(\.day), [d(12)])
        XCTAssertEqual(g?.adjustments.first?.name, "乙")
    }
}

final class SystemLogicTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    let m = ShiftMatcher(types: ShiftType.defaults)
    /// 10/12 周一 … 10/18 周日
    let d = { (day: Int) in DayKey(year: 2026, month: 10, day: day) }

    override func tearDown() {
        WorkloadCounter.profiles = [:]
        WorkloadCounter.ruleHistory = []
        WorkloadCounter.rules = WorkloadRules()
        WorkloadCounter.overrides = [:]
    }

    private func count(_ roster: Roster) -> [String: PersonWorkload] {
        Dictionary(uniqueKeysWithValues: WorkloadCounter.count(roster: roster, days: (12...18).map(d), matcher: m, calendar: cal)
            .map { ($0.name, $0) })
    }

    func testProfileOverridesAutomaticRole() {
        // 乙只值遥测：自动判断是不轮组别（没排的工作日算工作量）
        let roster: Roster = ["乙": [d(12): "遥测"]]
        XCTAssertEqual(count(roster)["乙"]?.regularDays, 4)
        // 档案里写成轮组别：没排的工作日只算上班
        WorkloadCounter.profiles = ["乙": PersonProfile(name: "乙", spans: [RoleSpan(from: nil, role: .group)])]
        XCTAssertEqual(count(roster)["乙"]?.regularDays, 0)
        XCTAssertEqual(count(roster)["乙"]?.attendanceDays, 4)
        // 从 15 日起改成调度：15、16 日没排就不算
        var p = WorkloadCounter.profiles["乙"]!
        p.setRole(.dispatch, from: d(15))
        WorkloadCounter.profiles["乙"] = p
        XCTAssertEqual(count(roster)["乙"]?.attendanceDays, 2)
        XCTAssertEqual(count(roster)["乙"]?.unassignedDays, 2)
        // 领导不统计
        WorkloadCounter.profiles["乙"] = PersonProfile(name: "乙", spans: [RoleSpan(from: nil, role: .leader)])
        XCTAssertNil(count(roster)["乙"])
        // 来走日期：14 日才来
        WorkloadCounter.profiles["乙"] = PersonProfile(name: "乙", spans: [RoleSpan(from: nil, role: .daily)], joined: d(14))
        XCTAssertEqual(count(roster)["乙"]?.dutyDays, 0)
        XCTAssertEqual(count(roster)["乙"]?.regularDays, 3)
        // 自动判断建议
        XCTAssertEqual(PersonDirectory.suggest(name: "乙", history: roster["乙"]!, matcher: m), .daily)
    }

    func testExplanationsSayWhy() {
        let e = WorkloadCounter.explained(of: [d(12): "组A", d(14): "休息"], days: (12...18).map(d), matcher: m,
                                          rotating: false, name: "甲", calendar: cal)
        XCTAssertEqual(e[d(12)]?.kind, .regular)
        XCTAssertTrue(e[d(12)]?.reason.contains("组A") == true)
        XCTAssertTrue(e[d(13)]?.reason.contains("轮组别") == true, e[d(13)]?.reason ?? "")
        XCTAssertTrue(e[d(13)]?.reason.contains("自动判断") == true)
        XCTAssertTrue(e[d(14)]?.reason.contains("休息") == true)
        XCTAssertTrue(e[d(17)]?.reason.contains("周末") == true)
        WorkloadCounter.overrides = ["甲": [d(13): "休息"]]
        let f = WorkloadCounter.explained(of: [d(12): "组A"], days: [d(13)], matcher: m, rotating: false, name: "甲", calendar: cal)
        XCTAssertTrue(f[d(13)]?.reason.contains("手动") == true)
    }

    func testRulesWithEffectiveDate() {
        // 不轮组别的乙：16 日起「没排岗位算上班」关掉
        let roster: Roster = ["乙": [d(12): "遥测"]]
        var newRules = WorkloadRules()
        newRules.blankWorkdayIsWork = false
        WorkloadCounter.ruleHistory = RuleVersion.adding([], current: WorkloadCounter.rules, changeFrom: d(16))
        WorkloadCounter.rules = newRules
        let p = count(roster)["乙"]
        XCTAssertEqual(p?.regularDays, 3)        // 13–15 日按旧规则
        XCTAssertEqual(p?.unassignedDays, 1)     // 16 日按新规则
        XCTAssertEqual(WorkloadCounter.rules(on: d(15)).blankWorkdayIsWork, true)
        XCTAssertEqual(WorkloadCounter.rules(on: d(16)).blankWorkdayIsWork, false)
    }

    func testMergerKeepsSourcesAndRecordsEdits() {
        let t0 = Date(timeIntervalSince1970: 1_000), t1 = Date(timeIntervalSince1970: 2_000)
        let first = RosterMerger.merge(old: [:], oldSources: [:], new: ["甲": [d(15): "休息"], "乙": [d(15): "组A"]],
                                       source: "desktop", at: t0, carriesLeave: true, matcher: m)
        XCTAssertTrue(first.edits.isEmpty)                       // 第一次读到的不算变动
        XCTAssertEqual(first.sources["甲"]?[d(15)]?.source, "desktop")
        // 不带休息列的同步：甲的休息保留、来源还是电脑版；乙换成组B 记一条变动
        let second = RosterMerger.merge(old: first.roster, oldSources: first.sources, new: ["乙": [d(15): "组B"]],
                                        source: "sync", at: t1, carriesLeave: false, matcher: m)
        XCTAssertEqual(second.roster["甲"]?[d(15)], "休息")
        XCTAssertEqual(second.sources["甲"]?[d(15)]?.source, "desktop")
        XCTAssertEqual(second.sources["乙"]?[d(15)], Provenance(source: "sync", at: t1))
        XCTAssertEqual(second.edits, [RosterEdit(at: t1, day: d(15), name: "乙", old: "组A", new: "组B", source: "sync")])
        // 带休息列的读取：甲的休息没了就是取消了
        let third = RosterMerger.merge(old: second.roster, oldSources: second.sources, new: ["乙": [d(15): "组B"]],
                                       source: "desktop", at: t1, carriesLeave: true, matcher: m)
        XCTAssertNil(third.roster["甲"]?[d(15)])
        XCTAssertEqual(third.edits.map(\.name), ["甲"])
    }

    func testPublishPattern() {
        // 网站一般周五 15 点前后排下周（2026-10-16、10-23 是周五）
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let times = ["2026-10-02 15:10", "2026-10-09 14:40", "2026-10-16 15:20", "2026-10-07 09:00"].compactMap { f.date(from: $0) }
        let hot = PublishPattern.hotSlots(times, calendar: cal)
        XCTAssertEqual(hot.first?.slot.weekday, 6)
        XCTAssertTrue(PublishPattern.isHot(f.date(from: "2026-10-23 15:00")!, times: times, calendar: cal))
        XCTAssertFalse(PublishPattern.isHot(f.date(from: "2026-10-21 15:00")!, times: times, calendar: cal))
        let next = PublishPattern.nextHot(after: f.date(from: "2026-10-20 10:00")!, times: times, calendar: cal)
        XCTAssertEqual(next.map { cal.component(.weekday, from: $0) }, 6)
        XCTAssertNotNil(PublishPattern.describe(times, calendar: cal))
    }

    func testRestLedgerExpectedChange() {
        let rule = RestBalanceAudit.Rule(longDuty: 1, shortDuty: 0, overtime: 0, compRest: -1, rest: 0, leave: 0)
        // 17 日周六遥测 +1，19 日调休 −1
        let history: [DayKey: String] = [d(17): "遥测", d(19): "调休"]
        XCTAssertEqual(RestBalanceAudit.expectedChange(history, from: d(12), to: d(18), rule: rule, matcher: m, calendar: cal), 1)
        XCTAssertEqual(RestBalanceAudit.expectedChange(history, from: d(12), to: d(20), rule: rule, matcher: m, calendar: cal), 0)
    }
}
