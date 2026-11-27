import XCTest

final class DutyDetailReviewTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testHandoffChecklistAndMemberScheduleFromToday() {
        let app = launchDuty(extraArguments: ["-demoHandoffChecklist"])
        defer { app.terminate() }

        let handoff = app.buttons["today.workbench.handoff"]
        scrollToDutyControl(handoff, in: app)
        handoff.tap()
        let card = app.navigationBars["交班卡"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        capture("交班卡", in: app)
        let openChecklist = app.buttons["duty.handoff.checklist"]
        scrollToDutyControl(openChecklist, in: app)
        openChecklist.tap()
        let checklist = app.navigationBars["组别任务清单"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 8))
        let task = app.buttons.matching(identifier: "duty.checklist.task").firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 6))
        let original = task.value as? String
        XCTAssertTrue(["已完成", "未完成"].contains(original ?? ""))
        task.tap()
        XCTAssertEqual(task.value as? String, original == "已完成" ? "未完成" : "已完成")
        capture("清单勾选", in: app)
        task.tap()
        XCTAssertEqual(task.value as? String, original)
        back(from: checklist)
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        back(from: card)

        let search = app.buttons["today.toolbar.memberSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 6) && search.isHittable)
        search.tap()
        let searchPage = app.navigationBars["搜索成员"]
        XCTAssertTrue(searchPage.waitForExistence(timeout: 6))
        let member = app.buttons.matching(NSPredicate(format: "identifier == 'duty.member.row' AND label CONTAINS '林夏'")).firstMatch
        scrollToDutyControl(member, in: app)
        member.tap()
        let person = app.navigationBars["林夏"]
        XCTAssertTrue(person.waitForExistence(timeout: 6))
        capture("成员个人排班", in: app)
        let nextDay = app.buttons.matching(identifier: "duty.member.day").firstMatch
        scrollToDutyControl(nextDay, in: app)
        nextDay.tap()
        let day = app.navigationBars["值班表"]
        XCTAssertTrue(day.waitForExistence(timeout: 6))
        capture("成员单日分工", in: app)
        back(from: day)
        XCTAssertTrue(person.waitForExistence(timeout: 6))
        back(from: person)
        XCTAssertTrue(searchPage.waitForExistence(timeout: 6))
        searchPage.buttons["完成"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 6) && search.isHittable)
    }

    func testManualSwapProfileAndImportPreviewFromDirectory() {
        let app = launchDuty()
        defer { app.terminate() }
        app.buttons["app.tab.设置"].tap()
        let directoryEntry = app.buttons["settings.duty.directory"]
        scrollToDutyControl(directoryEntry, in: app)
        directoryEntry.tap()
        let directory = app.navigationBars["全部功能"]
        XCTAssertTrue(directory.waitForExistence(timeout: 6))

        openFeature("换班账本", in: app)
        let ledger = app.navigationBars["换班账本"]
        XCTAssertTrue(ledger.waitForExistence(timeout: 6))
        app.buttons["duty.swap.add"].tap()
        let save = app.buttons["duty.swap.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 6))
        XCTAssertFalse(save.isEnabled)
        let name = "Swap" + String(UUID().uuidString.prefix(6))
        let colleague = app.textFields["duty.swap.person"]
        colleague.tap()
        colleague.typeText(name)
        XCTAssertTrue(save.isEnabled && save.isHittable)
        capture("手动换班保存", in: app)
        save.tap()
        XCTAssertTrue(ledger.waitForExistence(timeout: 8))
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        capture("换班账本新增结果", in: app)
        back(from: ledger)
        XCTAssertTrue(directory.waitForExistence(timeout: 6))

        openFeature("人员档案", in: app)
        let profiles = app.navigationBars["人员档案"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 6))
        let person = app.buttons.matching(NSPredicate(format: "identifier == 'duty.profile.row' AND label CONTAINS '林夏'")).firstMatch
        scrollToDutyControl(person, in: app)
        person.tap()
        let editor = app.navigationBars["林夏"]
        XCTAssertTrue(editor.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["保存角色"].exists)
        capture("管理员人员档案编辑", in: app)
        back(from: editor)
        XCTAssertTrue(profiles.waitForExistence(timeout: 6))
        back(from: profiles)
        XCTAssertTrue(directory.waitForExistence(timeout: 6))

        openFeature("导入排班表", in: app)
        let importPage = app.navigationBars["导入排班"]
        XCTAssertTrue(importPage.waitForExistence(timeout: 6))
        let input = app.textViews["duty.import.text"]
        XCTAssertTrue(input.waitForExistence(timeout: 6))
        input.tap()
        input.typeText("date,shift\n2030-10-09,Day\n2030-10-10,Night")
        if app.keyboards.firstMatch.exists { app.buttons["duty.import.dismissKeyboard"].tap() }
        let confirm = app.buttons["duty.import.confirm"]
        scrollToDutyControl(confirm, in: app)
        XCTAssertTrue(confirm.label.contains("2 天"))
        let range = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '替换' AND label CONTAINS '10月9日' AND label CONTAINS '10月10日'")).firstMatch
        XCTAssertTrue(range.exists)
        capture("排班导入两天预览", in: app)
        back(from: importPage)
        XCTAssertTrue(directory.waitForExistence(timeout: 6))
    }

    private func launchDuty(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + extraArguments
        app.launch()
        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 14))
        duty.tap()
        XCTAssertTrue(app.buttons["app.tab.今天"].waitForExistence(timeout: 8))
        return app
    }

    private func openFeature(_ title: String, in app: XCUIApplication) {
        let button = app.buttons["duty.feature." + title]
        scrollToDutyControl(button, in: app)
        button.tap()
    }



    private func back(from page: XCUIElement) {
        let button = page.buttons["BackButton"]
        XCTAssertTrue(button.exists && button.isHittable, page.description)
        button.tap()
    }

    private func capture(_ title: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "duty-detail-" + title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
