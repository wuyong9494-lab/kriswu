import UIKit
import XCTest

/// Uses the public workbench, the bundled storyboard and the local report builder.
final class WuMindStudioNavigationTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-demo"]
        app.launch()
        if app.frame.width > app.frame.height { XCUIDevice.shared.orientation = .portrait }
        tap(app.buttons["workspace.home.wumind"])
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testImageConnectionAdvancedSettingsAndDiagnostics() {
        openTool("image", title: "画室")
        let route = app.buttons["ai.image.routeBadge"]
        reveal(route)
        route.tap()
        let hub = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "自有 API · AIHubMix")).firstMatch
        tap(hub)
        tap(app.buttons["ai.image.keyConfig"])
        let connection = navigationBar("AIHubMix 连接")
        XCTAssertTrue(app.secureTextFields["ai.aihubmix.key"].exists)

        let address = app.textFields["ai.aihubmix.baseURL"]
        XCTAssertFalse(address.isHittable)
        tap(app.buttons.matching(identifier: "高级设置").firstMatch)
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        connection.buttons["完成"].tap()

        tap(app.buttons["ai.image.diagnostics"])
        let diagnostics = navigationBar("画室脱敏诊断")
        XCTAssertTrue(app.staticTexts["本次画室会话尚无生图请求记录。"].exists)
        capture("Image-Diagnostics")
        diagnostics.buttons["关闭"].tap()
        _ = navigationBar("画室")
    }

    func testShortDramaSampleAPIAndPublishSettings() {
        tap(app.buttons["wumind.model.picker"])
        tap(app.buttons["wumind.channel.ownAPI"])
        navigationBar("WUMIND 模型与能力中心").buttons["完成"].tap()
        openTool("video", title: "视频")
        tap(app.buttons["ai.video.mode.shortDrama"])
        let sample = app.buttons["ai.drama.loadSample"]
        reveal(sample)
        sample.tap()
        let loaded = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已载入 6 镜 36 秒")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout: 5))

        let configure = app.buttons["ai.drama.apiConfig"]
        reveal(configure)
        configure.tap()
        let api = navigationBar("短剧官方视频接口")
        XCTAssertTrue(app.secureTextFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "Ark API Key")).firstMatch.exists)
        let advanced = app.buttons.matching(identifier: "高级设置").firstMatch
        tap(advanced)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "模型或接入点 ID")).firstMatch.exists)
        api.buttons["完成"].tap()

        let publish = app.buttons["ai.drama.multiPublish"]
        reveal(publish)
        publish.tap()
        let platforms = navigationBar("分平台发布")
        XCTAssertTrue(app.buttons["按分镜重置"].exists)
        tap(app.buttons["ai.publish.douyinAuth"])
        let auth = navigationBar("抖音官方接口授权")
        XCTAssertTrue(app.textFields["发布账号昵称"].exists)
        XCTAssertTrue(app.secureTextFields["授权 open_id"].exists)
        XCTAssertTrue(app.secureTextFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "授权 access_token")).firstMatch.exists)
        capture("ShortDrama-PublishAuthorization")
        auth.buttons["完成"].tap()
        platforms.buttons["关闭"].tap()
        _ = navigationBar("视频")
    }

    func testLocalPPTSlideEditUpdatesPreview() throws {
        let titles = try buildAndEditLocalDeck()
        let firstTitle = app.staticTexts["ai.ppt.previewTitle.1"]
        reveal(firstTitle, down: true)
        XCTAssertEqual(firstTitle.label, titles.edited)
        capture("PPT-SavedPreview")
        XCTAssertTrue(app.buttons["ai.ppt.sharePptx"].exists)
    }

    func testImageAndVideoKeyboardActionsStayAboveTheKeyboard() {
        tap(app.buttons["wumind.tab.workbench"])
        for (studio, title) in [("image", "画室"), ("video", "视频")] {
            let entry = app.buttons["wumind.quick." + studio]
            reveal(entry)
            tap(entry)
            let bar = navigationBar(title)
            if studio == "video" { tap(app.buttons["ai.video.mode.singleClip"]) }
            let prefix = "ai." + studio
            let prompt = app.descendants(matching: .any).matching(identifier: prefix + ".prompt").firstMatch
            reveal(prompt)
            prompt.tap()
            prompt.typeText("A quiet morning by the lake")
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 12))
            let dismiss = app.buttons[prefix + ".dismissKeyboard"]
            let generate = app.buttons[prefix + ".generate"]
            XCTAssertTrue(dismiss.isHittable)
            XCTAssertTrue(generate.exists)
            XCTAssertLessThanOrEqual(dismiss.frame.maxY, keyboard.frame.minY + 1)
            XCTAssertLessThanOrEqual(generate.frame.maxY, keyboard.frame.minY + 1)
            capture("StudioKeyboard-" + studio)
            dismiss.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
            bar.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.scrollViews["wumind.workbench.scroll"].waitForExistence(timeout: 8))
        }
    }

    func testReportEmptyCoverAndSystemShareFromWorkbench() {
        openTool("ppt", title: "幻灯片")
        prepareEmptyPresentation()
        let build = app.buttons["ai.ppt.buildExecutiveReport"]
        let generate = app.buttons["ai.ppt.generate"]
        XCTAssertTrue(generate.isHittable && !generate.isEnabled)
        XCTAssertTrue(app.buttons["ai.ppt.openMaterials"].isHittable)
        XCTAssertTrue(build.isHittable)
        capture("StudioReport-Empty")

        let settings = app.buttons["ai.ppt.settings"]
        tap(settings)
        let settingsPage = navigationBar("文稿设置")
        XCTAssertTrue(app.buttons["ai.ppt.uploadFile"].exists)
        tap(settingsPage.buttons["完成"])
        tap(build)
        let cover = app.staticTexts["ai.ppt.previewTitle.1"]
        XCTAssertTrue(cover.waitForExistence(timeout: 12))
        XCTAssertEqual(cover.label, "季度经营汇报与下阶段决策建议")
        XCTAssertTrue(app.buttons["下一页"].isHittable)
        let powerpoint = app.buttons["ai.ppt.sharePptx"]
        XCTAssertTrue(powerpoint.isHittable)
        XCTAssertGreaterThanOrEqual(powerpoint.frame.height, 44)
        capture("StudioReport-Cover")
        // The original iPad screenshot shows Apple's PDF share popover on this same local report.
        openAdditionalDocumentActions()
        let pdf = app.buttons["ai.ppt.sharePdf"]
        reveal(pdf)
        tap(pdf)
        XCTAssertTrue(app.cells.matching(identifier: "shareCell").firstMatch.waitForExistence(timeout: 15))
        capture("StudioReport-PDFShare")
    }

    func testLargeTextWorkbenchAndReportActions() {
        app.terminate()
        app.launchArguments = ["-demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap(app.buttons["workspace.home.wumind"])
        let tab = app.buttons["wumind.tab.workbench"]
        tap(tab)
        let image = app.buttons["wumind.quick.image"]
        let video = app.buttons["wumind.quick.video"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(video.frame.minY, image.frame.maxY)
        XCTAssertEqual(video.frame.midX, image.frame.midX, accuracy: 2)
        let ppt = app.buttons["wumind.quick.ppt"]
        let scroll = app.scrollViews["wumind.workbench.scroll"]
        for _ in 0..<6 where !ppt.isHittable || ppt.frame.maxY > tab.frame.minY {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(ppt.isHittable)
        XCTAssertLessThanOrEqual(ppt.frame.maxY, tab.frame.minY)
        capture("StudioReport-LargeText-Workbench")
        tap(ppt)
        _ = navigationBar("幻灯片")
        prepareEmptyPresentation()
        let build = app.buttons["ai.ppt.buildExecutiveReport"]
        reveal(build)
        tap(build)
        let cover = app.staticTexts["ai.ppt.previewTitle.1"]
        XCTAssertTrue(cover.waitForExistence(timeout: 12))
        capture("StudioReport-LargeText-Cover")
        let edit = app.buttons["ai.ppt.editSlide"]
        reveal(edit)
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        tap(edit)
        let editor = navigationBar("编辑第 1 页")
        XCTAssertTrue(editor.buttons["form.toolbar.save"].isHittable)
        capture("StudioReport-LargeText-Editor")
    }

    func testShareLocalPDFToTenderInboxFromWorkbench() {
        openTool("ppt", title: "幻灯片")
        prepareEmptyPresentation()
        let build = app.buttons["ai.ppt.buildExecutiveReport"]
        reveal(build)
        build.tap()
        openAdditionalDocumentActions()
        let pdf = app.buttons["ai.ppt.sharePdf"]
        reveal(pdf)
        pdf.tap()

        let ownExtension = NSPredicate(
            format: "label IN %@ OR label CONTAINS[c] %@ OR label CONTAINS %@",
            ["值班提醒", "ShiftReminder"], "Tender Import", "导入标书"
        )
        let shareTarget = app.cells.matching(identifier: "shareCell").matching(ownExtension).firstMatch
        if shareTarget.waitForExistence(timeout: 6), shareTarget.isHittable {
            shareTarget.tap()
        } else {
            let more = app.cells.matching(NSPredicate(format: "label IN %@", ["More", "更多"])).firstMatch
            tap(more)
            let chooser = app.otherElements["ShareSheet.EditAppsView"]
            let visibleAppName = chooser.staticTexts.matching(identifier: "activityTitleLabel")
                .matching(ownExtension).firstMatch
            tap(visibleAppName)
        }
        let save = app.buttons["保存到收件箱"]
        XCTAssertTrue(save.waitForExistence(timeout: 12) && save.isEnabled)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        capture("Tender-ShareExtension-Ready")
        save.tap()
        XCTAssertTrue(app.staticTexts["已接收到本机收件箱"].waitForExistence(timeout: 10))
        let receipt = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] %@", ".pdf")).firstMatch
        XCTAssertTrue(receipt.exists)
        let filename = receipt.label
        capture("Tender-ShareExtension-Saved")
        tap(app.buttons["完成"])
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Confirm the shared PDF survives a fresh launch, as it must when the sender was another app.
            app.terminate()
            app.launchArguments = ["-demo"]
            app.launch()
            tap(app.buttons["workspace.home.wumind"])
            tap(app.buttons["wumind.tab.workbench"])
        } else {
            navigationBar("幻灯片").buttons.element(boundBy: 0).tap()
        }
        let tender = app.buttons["deepSeek.chat.tender"]
        reveal(tender)
        tender.tap()
        let savedDocument = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", filename)).firstMatch
        reveal(savedDocument)
        savedDocument.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", filename)).firstMatch.exists
                      || savedDocument.label.contains("已选中"))
    }

    func testWorksReopensOriginalPPTAndExportsEditedVersion() throws {
        let titles = try buildAndEditLocalDeck()
        navigationBar("幻灯片").buttons.element(boundBy: 0).tap()
        tap(app.buttons["wumind.tab.works"])

        // Each local report starts a distinct lineage. The most recently edited work appears first.
        let edited = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wumind.works.open.WRK-V2-")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 8))
        let workID = String(edited.identifier.dropFirst("wumind.works.open.".count))
        tap(edited)
        _ = navigationBar("作品详情 v2")
        let versionOne = app.buttons["wumind.work.version.1"]
        tap(versionOne)
        _ = navigationBar("作品详情 v1")
        XCTAssertTrue(versionOne.isSelected)
        tap(app.buttons["在 PPT 工坊继续编辑（将存为新版本）"])
        _ = navigationBar("幻灯片")
        let original = app.staticTexts["ai.ppt.previewTitle.1"]
        reveal(original)
        XCTAssertEqual(original.label, titles.original)
        capture("Works-OriginalVersionPreview")

        navigationBar("幻灯片").buttons.element(boundBy: 0).tap()
        let sameWork = app.buttons["wumind.works.open." + workID]
        tap(sameWork)
        _ = navigationBar("作品详情 v2")
        XCTAssertTrue(app.buttons["wumind.work.version.2"].isSelected)
        capture("Works-EditedVersion")
        let share = app.buttons["导出 / 分享原文件"]
        reveal(share)
        share.tap()
        let saveToFiles = app.descendants(matching: .any).matching(NSPredicate(
            format: "(elementType == %d OR elementType == %d) AND label IN %@",
            XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.button.rawValue,
            ["Save to Files", "存储到“文件”", "存储到「文件」", "存储到文件", "保存到文件"]
        )).firstMatch
        if !saveToFiles.waitForExistence(timeout: 4) || !saveToFiles.isHittable {
            app.swipeUp()
        }
        tap(saveToFiles)
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "存储", "储存", "保存"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        capture("Works-SystemFilesPicker")
        // The system file picker identifies the exact edited file being handed off.
        let name = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", workID, workID
        )).firstMatch
        XCTAssertTrue(name.exists)

        let deviceFolders = ["On My iPhone", "On My iPad", "我的 iPhone", "我的 iPad"]
        let deviceLocation = NSPredicate(format: "label IN %@", deviceFolders)
        let localBar = app.navigationBars.matching(deviceLocation).firstMatch
        if !localBar.exists {
            let folder = app.descendants(matching: .any).matching(deviceLocation).firstMatch
            if !folder.isHittable {
                let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "浏览", "Back", "返回"])).firstMatch
                tap(browse)
            }
            tap(folder)
        }
        XCTAssertTrue(save.isEnabled)
        capture("Works-EditedPowerPointExport")
        save.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        XCTAssertTrue(share.isHittable)
    }

    func testSpatialSavedProjectRegistryAndTripoSettings() {
        openTool("spatial3d", title: "3D 空间")
        let menu = app.buttons["ai.spatial3d.moreToolsMenu"]
        tap(menu)
        tap(app.buttons["ai.spatial3d.projectsAction"])
        _ = navigationBar("工程库")
        let projects = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ai.spatial3d.project."))
        let project = projects.firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 6))
        let projectID = project.identifier
        project.tap()
        _ = navigationBar("3D 空间")

        tap(menu)
        tap(app.buttons["ai.spatial3d.projectsAction"])
        let library = navigationBar("工程库")
        let reopened = app.buttons[projectID]
        XCTAssertEqual(reopened.value as? String, "当前")
        library.buttons["完成"].tap()

        tap(app.buttons["ai.spatial3d.openTechLibraryToolbar"])
        let registry = navigationBar("3D 技术库")
        let research = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "研究候选")).firstMatch
        tap(research)
        XCTAssertTrue(research.isSelected)
        capture("Spatial-Registry")
        registry.buttons["完成"].tap()

        tap(menu)
        tap(app.buttons["ai.spatial3d.tripoAction"])
        let tripo = navigationBar("Tripo 自由造型道具接口")
        XCTAssertTrue(app.secureTextFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "Tripo API Key")).firstMatch.exists)
        XCTAssertTrue(app.buttons["保存 Tripo Key"].exists)
        tripo.buttons["完成"].tap()
        _ = navigationBar("3D 空间")
    }

    func testTranscriptionImportCancelKeepsInputEmpty() {
        openTool("speech", title: "语音合成与转写")
        tap(app.buttons["录音转文字"])
        let importAudio = app.buttons["ai.speech.import"]
        XCTAssertTrue(app.buttons["开始录音"].exists)
        XCTAssertFalse(app.buttons["OpenAI 转文字"].exists)
        tap(importAudio)
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消", "Close", "关闭"])).firstMatch
        tap(cancel)
        XCTAssertTrue(importAudio.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["OpenAI 转文字"].exists)
        XCTAssertFalse(app.staticTexts["转写结果"].exists)
        XCTAssertFalse(app.staticTexts["未能打开文件选择，请重试。"].exists)
        capture("Speech-EmptyAfterImportCancel")
        tap(app.buttons["文字转语音"])
        XCTAssertTrue(app.descendants(matching: .any)["ai.speech.script"].exists)
    }

    private func prepareEmptyPresentation() {
        let build = app.buttons["ai.ppt.buildExecutiveReport"]
        // A previous work is intentionally restored on launch. Use the visible new-document action.
        if !build.waitForExistence(timeout: 2) {
            openAdditionalDocumentActions()
            let newDocument = app.buttons["ai.ppt.newDocument"]
            reveal(newDocument)
            tap(newDocument)
        }
        XCTAssertTrue(build.waitForExistence(timeout: 8))
    }

    private func openAdditionalDocumentActions() {
        let more = app.buttons["ai.ppt.moreActions"]
        reveal(more)
        if more.value as? String != "已展开" { more.tap() }
    }

    private func buildAndEditLocalDeck() throws -> (original: String, edited: String) {
        openTool("ppt", title: "幻灯片")
        prepareEmptyPresentation()
        let build = app.buttons["ai.ppt.buildExecutiveReport"]
        reveal(build)
        build.tap()

        let edit = app.buttons["ai.ppt.editSlide"]
        reveal(edit)
        edit.tap()
        let editor = navigationBar("编辑第 1 页")
        let field = app.textFields["本页标题"]
        let original = try XCTUnwrap(field.value as? String)
        tap(field)
        field.typeText(" QA")
        let updated = try XCTUnwrap(field.value as? String)
        XCTAssertTrue(updated.contains("QA"))
        editor.buttons["form.toolbar.save"].tap()
        _ = navigationBar("幻灯片")

        return (original, updated.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func openTool(_ id: String, title: String) {
        tap(app.buttons["wumind.tab.workbench"])
        let entry = app.buttons["wumind.quick." + id]
        reveal(entry)
        entry.tap()
        _ = navigationBar(title)
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 12), file: file, line: line)
        element.tap()
    }

    private func navigationBar(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 12), title, file: file, line: line)
        return bar
    }

    private func reveal(_ element: XCUIElement, down: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 where !element.isHittable {
            if down { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
