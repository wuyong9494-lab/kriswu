import XCTest

final class DutyDeepLinkReviewTests: XCTestCase {
    func testNoteAndCalendarLinksFromWuMind() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("系统 URL 自动化需要 iOS 16.4 或更高版本") }
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["wumind.backToHome"].waitForExistence(timeout: 10))
        app.open(try XCTUnwrap(URL(string: "shiftreminder://capture/note")))
        let note = app.navigationBars["记一笔"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["worklog.note.save"].exists)
        note.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["app.tab.今天"].waitForExistence(timeout: 10))
        for host in ["day", "managed-calendar"] {
            app.open(try XCTUnwrap(URL(string: "shiftreminder://" + host + "/2026-11-27")))
            let close = app.navigationBars["11月27日 周五"].buttons["关闭"]
            XCTAssertTrue(close.waitForExistence(timeout: 8))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "duty-deeplink-" + host
            screenshot.lifetime = .keepAlways
            add(screenshot)
            close.tap()
            XCTAssertTrue(app.buttons["app.tab.今天"].waitForExistence(timeout: 8))
        }
    }
}
