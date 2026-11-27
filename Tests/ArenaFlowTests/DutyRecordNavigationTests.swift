import XCTest

final class DutyRecordNavigationTests: XCTestCase {
    func testCreateEditAndReopenNoteFromWorkspace() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        defer { app.terminate() }

        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 15))
        duty.tap()

        let openLog = app.buttons["today.workLog.open"]
        for _ in 0..<12 where !openLog.isHittable { app.swipeUp() }
        XCTAssertTrue(openLog.isHittable)
        openLog.tap()

        let list = app.navigationBars["工作留痕"]
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        let addRecord = app.buttons["worklog.add"]
        addRecord.tap()
        let newRecording = app.buttons.matching(NSPredicate(format: "identifier == 'worklog.add.recording' OR label == '新建录音'")).firstMatch
        XCTAssertTrue(newRecording.waitForExistence(timeout: 6))
        newRecording.tap()
        XCTAssertTrue(app.buttons["开始录音"].waitForExistence(timeout: 6))
        app.buttons["取消"].tap()
        XCTAssertTrue(addRecord.waitForExistence(timeout: 6) && addRecord.isHittable)
        addRecord.tap()
        let newNote = app.buttons.matching(NSPredicate(format: "identifier == 'worklog.add.note' OR label == '记一笔'")).firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: 6))
        newNote.tap()

        let initial = "DutyNote" + String(UUID().uuidString.prefix(8))
        let editor = app.descendants(matching: .any).matching(identifier: "worklog.note.text").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 6))
        editor.tap()
        editor.typeText(initial)
        let save = app.buttons["worklog.note.save"]
        XCTAssertTrue(save.isEnabled && save.isHittable)
        save.tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", initial)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let detail = app.descendants(matching: .any).matching(identifier: "worklog.detail.note").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 6))
        XCTAssertEqual(detail.value as? String, initial)
        detail.tap()
        detail.typeText("Edited")
        let detailSave = app.buttons["worklog.detail.save"]
        XCTAssertTrue(detailSave.isEnabled && detailSave.isHittable)
        detailSave.tap()

        let revised = initial + "Edited"
        let updated = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", revised)).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 8))
        updated.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 6))
        XCTAssertEqual(detail.value as? String, revised)
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Duty-work-log-reopened-note"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(list.waitForExistence(timeout: 6) && updated.isHittable)
        list.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["today.toolbar.plan"].waitForExistence(timeout: 6))
    }
}
