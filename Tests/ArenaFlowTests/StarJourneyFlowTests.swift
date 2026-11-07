import XCTest

/// Published J1 witness paths, played through real controls; no engine or save injection.
final class StarJourneyFlowTests: XCTestCase {
    private enum Step { case pick(Int), move(Int,Int) }
    private let chapters:[[Step]] = [
        [.pick(19),.pick(4),.pick(18),.pick(23),.pick(6),.move(0,1),.move(0,0),.pick(21),.pick(5),.pick(9),.pick(20),.pick(7),.pick(14),.pick(22),.pick(8),.pick(11),.pick(12),.pick(0),.pick(1),.pick(2),.pick(3),.pick(10),.pick(13),.pick(15),.pick(16),.pick(17)],
        [.pick(22),.pick(25),.pick(23),.pick(3),.pick(14),.move(1,1),.pick(26),.pick(20),.pick(7),.pick(24),.pick(21),.pick(12),.pick(0),.pick(1),.pick(2),.pick(4),.pick(9),.pick(10),.pick(5),.pick(6),.pick(19),.move(0,2),.pick(15)],
        [.pick(20),.pick(16),.pick(21),.pick(23),.pick(7),.pick(18),.pick(13),.pick(24),.move(1,1),.pick(11),.pick(12),.move(1,0),.move(0,1),.move(0,0),.pick(25),.pick(26),.pick(19),.pick(22),.pick(5),.pick(0),.pick(1),.pick(2),.pick(3),.pick(15),.pick(17),.pick(4),.pick(9),.pick(14),.pick(6),.pick(8),.pick(10)]
    ]
    override func setUpWithError() throws { continueAfterFailure=false }
    override func tearDownWithError() throws { capture("journey-final");XCUIApplication().terminate() }

    func testThreeChapterJourneyRestoresRouteAndCollectsRewardThroughRealActions() {
        let app=XCUIApplication()
        app.launchArguments=["-demo","-screen","tiles","-rails.testDomain",UUID().uuidString]
        XCUIDevice.shared.orientation = .portrait;app.launch()
        XCTAssertTrue(app.buttons["tiles.journeyContinue"].waitForExistence(timeout:20))
        XCTAssertFalse(app.buttons["tiles.trials"].exists,"Additional modes should be inside the library")
        tap("tiles.journeyContinue",app);tap("journey.ability.navigator",app);tap("journey.start",app)
        tap("rails.preview.0",app);XCTAssertFalse(app.buttons["rails.move"].isEnabled)
        tap("rails.preview.cancel",app)
        tap("rails.card.19",app);tap("rails.undo",app)
        XCTAssertTrue(app.buttons["rails.card.19"].isEnabled)
        for step in chapters[0].prefix(4) { play(step,app) }
        XCUIDevice.shared.press(.home);app.activate()
        tap("rails.close",app);tap("journey.close",app)
        app.terminate();app.launch();tap("tiles.journeyContinue",app)
        XCTAssertTrue(app.buttons["rails.preview.0"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["rails.card.19"].exists)
        for step in chapters[0].dropFirst(4) { play(step,app) }
        XCTAssertEqual(app.staticTexts["rails.result"].label,"航线完成")
        tap("journey.advance",app);tap("journey.route.signal",app)
        XCTAssertFalse(app.buttons["rails.card.27"].isEnabled,"Star core is cargo, never a normal collectible")
        tap("rails.preview.0",app);XCTAssertFalse(app.buttons["rails.move"].isEnabled)
        capture("journey-locked-gate-preview");tap("rails.preview.cancel",app)
        for step in chapters[1] { play(step,app) }
        XCTAssertEqual(app.staticTexts["rails.result"].label,"航线完成")
        tap("journey.advance",app)
        app.terminate();app.launch();tap("tiles.journeyContinue",app)
        XCTAssertTrue(app.buttons["journey.next"].waitForExistence(timeout:10),"Intermission and chosen route must survive relaunch")
        tap("journey.next",app)
        capture("journey-limited-return-start")
        for step in chapters[2] { play(step,app) }
        XCTAssertEqual(app.staticTexts["rails.result"].label,"航线完成")
        tap("journey.advance",app)
        XCTAssertTrue(app.staticTexts["journey.reward.stars"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["journey.reward.stars"].label,"本次新获 10 枚星章")
        capture("journey-restored-star-map")
        tap("journey.unlock.sky.dawn",app);XCTAssertFalse(app.buttons["journey.unlock.sky.dawn"].isEnabled)
        tap("journey.unlock.back.orbit",app);XCTAssertFalse(app.buttons["journey.unlock.back.orbit"].isEnabled)
        tap("journey.reward.done",app)
        XCTAssertTrue(app.buttons["journey.start"].waitForExistence(timeout:5))
        tap("journey.close",app);app.terminate();app.launch();tap("tiles.journeyContinue",app)
        XCTAssertFalse(app.staticTexts["journey.reward.stars"].exists,"Acknowledged reward must not reappear")
        XCTAssertTrue(app.buttons["journey.start"].exists)
    }
    func testPulseSelectionChargePreviewAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "tiles", "-rails.testDomain", UUID().uuidString]
        XCUIDevice.shared.orientation = .portrait; app.launch()
        tap("tiles.journeyContinue",app); tap("journey.ability.pulse",app); tap("journey.start",app)
        for id in 0...2 { tap("rails.card.\(id)",app) }
        XCTAssertTrue(app.staticTexts["journey.pulse"].label.contains("脉冲 1/2"))
        tap("rails.preview.0",app)
        XCTAssertTrue(app.staticTexts["journey.pulse"].label.contains("脉冲 1/2"))
        tap("rails.preview.cancel",app)
        tap("rails.close",app); tap("journey.close",app)
        app.terminate(); app.launch(); tap("tiles.journeyContinue",app)
        XCTAssertTrue(app.staticTexts["journey.pulse"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["journey.pulse"].label.contains("脉冲 1/2"))
        tap("rails.undo",app)
        XCTAssertTrue(app.staticTexts["journey.pulse"].label.contains("脉冲 0/2"))
        capture("journey-pulse-restored-and-undone")
    }
    private func play(_ step:Step,_ app:XCUIApplication) {
        switch step {
        case .pick(let id):tap("rails.card.\(id)",app)
        case .move(let rail,let stop):
            tap("rails.preview.\(rail)",app)
            let destination="rails.stop.\(rail).\(stop)"
            if app.buttons[destination].exists { tap(destination,app) }
            tap("rails.move",app)
        }
    }
    private func tap(_ id:String,_ app:XCUIApplication,file:StaticString=#filePath,line:UInt=#line) {
        let button=app.buttons[id]
        if !id.hasPrefix("rails.") {
            for _ in 0..<5 { if button.waitForExistence(timeout:1) && button.isHittable { break };app.swipeUp() }
            if !button.isHittable { for _ in 0..<5 { if button.isHittable { break };app.swipeDown() } }
        }
        XCTAssertTrue(button.waitForExistence(timeout:10),id,file:file,line:line)
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true AND hittable == true"),object:button)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed,id,file:file,line:line)
        button.tap()
    }
    private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        let tree=XCTAttachment(string:XCUIApplication().debugDescription);tree.name=name+"-accessibility";tree.lifetime = .keepAlways;add(tree)
    }
}
