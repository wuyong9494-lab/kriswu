import XCTest

/// Render states using the app's existing ScreenCatalog fixtures. These routes do not authenticate a user.
final class OfflineStateReviewTests: XCTestCase {
    func testDutyConfigurationAndMeetingSamples() {
        for (route, title) in [
            ("swap", "找人换班"), ("patterns", "排班规律"), ("rules", "工作量规则"),
            ("holidays", "法定节假日"), ("profiles", "人员档案"), ("meetingSource", "导入周会文档")
        ] {
            review(route) { $0.navigationBars[title].firstMatch }
        }
    }

    func testArenaRoomsAndResultSamples() {
        review("arenaDiagnostics") { $0.staticTexts["持续性能诊断"].firstMatch }
        review("arenaSampleMapReview") { $0.staticTexts["双闸交汇 · 作战指南"].firstMatch }
        review("arenaStory") { $0.staticTexts["冒险"].firstMatch }
        review("arenaRoomWaiting") { $0.staticTexts["等待队友"].firstMatch }
        review("arenaRoomReady") {
            $0.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "选择角色")).firstMatch
        }
        review("arenaResult") { $0.buttons["arena.result.lobby"].firstMatch }
    }

    private func review(_ route: String, destination: (XCUIApplication) -> XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", route]
        app.launch()
        defer { app.terminate() }
        let visible = destination(app).waitForExistence(timeout: 15)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = (visible ? "catalog-" : "unconfirmed-") + route
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(visible, route)
    }
}
