import XCTest
import WebKit
@testable import ShiftReminder

/// 用模拟器里真正的 WKWebView，对着仿值班网站（Tests/MockSite/server.py）跑一遍同步流程：
/// 自动登录、认出数据接口、翻「值班查看」、电脑版页面、往前翻周读全员排班、各组说明。
/// 网站数据是虚构的，/api/expected 给出标准答案。
@MainActor
final class SiteTests: XCTestCase {
    let base = "http://127.0.0.1:8765/"
    let matcher = ShiftMatcher(types: ShiftType.defaults)

    override func setUp() async throws {
        // 每个测试都从未登录开始
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                      modifiedSince: .distantPast)
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }

    private struct Expected: Decodable {
        let mine: String
        let roster: [String: String]
    }

    private func expected(_ day: DayKey) async throws -> Expected {
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + "api/expected?date=\(day)")!)
        return try JSONDecoder().decode(Expected.self, from: data)
    }

    func testDesktopModeGetsDesktopLayout() async throws {
        let url = URL(string: base + "#/duty")!
        let mobile = try await WebPageLoader.load(url: url, username: "zhangsan", password: "pw123", replay: { _ in [] })
        XCTAssertTrue(mobile.html.contains("data-layout=\"mobile\""), String(mobile.html.prefix(300)))

        let desktop = try await WebPageLoader.load(url: url, username: "zhangsan", password: "pw123",
                                                   desktop: true, replay: { _ in [] })
        XCTAssertTrue(desktop.html.contains("data-layout=\"desktop\""), String(desktop.html.prefix(300)))
        XCTAssertTrue(desktop.html.contains("当前周"), "电脑版自动登录后应进入值班查看")
    }

    func testMobileSyncReadsMyScheduleAndRoster() async throws {
        let outcome = try await SyncService.fetchSchedule(
            urlString: base + "#/mine", username: "zhangsan", password: "pw123", viaWeb: true, includeRoster: true,
            parser: ScheduleParser(aliases: [], reference: .today), aliases: [], matcher: matcher, preferredAPI: nil)
        XCTAssertEqual(outcome.result.format, .api)
        XCTAssertNotNil(outcome.apiSignature)

        let today = DayKey.today
        for offset in [0, 1, 6, 20] {
            let day = today.adding(days: offset)
            let e = try await expected(day)
            let want = e.mine == "休息" ? "无分工" : e.mine
            XCTAssertEqual(outcome.result.entries[day].map(matcher.displayName), want, "我的分工 \(day)")
        }
        let e = try await expected(today)
        for (name, post) in e.roster {
            XCTAssertEqual(outcome.roster[name]?[today], post, "全员排班 \(name) \(today)")
        }
        // 翻页 / 接口应该拿到前一周和后几周
        let lastWeek = today.adding(days: -7)
        let e2 = try await expected(lastWeek)
        for (name, post) in e2.roster {
            XCTAssertEqual(outcome.roster[name]?[lastWeek], post, "全员排班 \(name) \(lastWeek)")
        }
    }

    func testDesktopPagerGoesBackWeekByWeek() async throws {
        let page = try await WebPageLoader.load(url: URL(string: base + "#/duty")!, username: "zhangsan", password: "pw123",
                                                extraTabs: [""], pager: [(label: "上一周", steps: 3)],
                                                desktop: true, replay: { _ in [] })
        let weeks = Set(([page.html] + page.extraHTML).compactMap { html -> String? in
            guard let r = html.range(of: #"当前周：\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
            return String(html[r])
        })
        XCTAssertEqual(weeks.count, 4, "本周加往前 3 周：\(weeks)")
        var roster: Roster = [:]
        for html in page.extraHTML {
            RosterExtractor.merge(RosterExtractor.fromDesktopHTML(html, reference: .today, matcher: matcher), into: &roster)
        }
        let day = DayKey.today.adding(days: -14)
        let e = try await expected(day)
        for (name, post) in e.roster {
            XCTAssertEqual(roster[name]?[day], post, "电脑版周表 \(name) \(day)")
        }
    }

    func testDesktopNotesAndHistory() async throws {
        let result = await SyncService.fetchDesktopGroupNotes(
            urlString: base + "#/mine", overrideURL: "", username: "zhangsan", password: "pw123",
            reference: .today, matcher: matcher)
        XCTAssertNil(result.reason, result.pageText)
        XCTAssertEqual(Set(result.notes.keys), ["组A", "组B", "组C", "组D", "组E"])
        let a = result.notes["组A"] ?? ""
        XCTAssertTrue(a.contains("一号星") && a.contains("1.所有星做备份数传"), a)
        XCTAssertFalse(a.contains("二号星"), "删除线的内容要去掉：\(a)")
        XCTAssertFalse((result.notes["组B"] ?? "").contains("三号星"))
        XCTAssertTrue((result.notes["组A"] ?? "").contains("\n"), "保留换行")

        // 两个月前的全员排班
        for back in [30, 60] {
            let day = DayKey.today.adding(days: -back)
            let e = try await expected(day)
            for (name, post) in e.roster {
                XCTAssertEqual(result.roster[name]?[day], post, "\(back) 天前 \(name)")
            }
        }
        // 说明里的「9月20日」不能读成某个人的排班
        XCTAssertNil(result.roster["下午可做"])
        let everyone = Set(try await expected(.today).roster.keys)
        XCTAssertEqual(Set(result.roster.keys), everyone)
    }
}
