import XCTest

/// Uses the public workbench, the bundled storyboard and the local report builder.
final class WuMindStudioNavigationTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-demo", "-screen", "wumind"]
        app.launch()
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
        openTool("ppt", title: "幻灯片")
        let build = app.buttons["ai.ppt.buildExecutiveReport"]
        reveal(build)
        build.tap()

        let edit = app.buttons["ai.ppt.editSlide"]
        reveal(edit)
        edit.tap()
        let editor = navigationBar("编辑第 1 页")
        let field = app.textFields["本页标题"]
        tap(field)
        field.typeText(" QA")
        let updated = try XCTUnwrap(field.value as? String)
        XCTAssertTrue(updated.contains("QA"))
        editor.buttons["form.toolbar.save"].tap()
        _ = navigationBar("幻灯片")

        let firstTitle = app.staticTexts["ai.ppt.previewTitle.1"]
        reveal(firstTitle, down: true)
        XCTAssertEqual(firstTitle.label, updated.trimmingCharacters(in: .whitespacesAndNewlines))
        capture("PPT-SavedPreview")
        XCTAssertTrue(app.buttons["ai.ppt.sharePptx"].exists)
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
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
