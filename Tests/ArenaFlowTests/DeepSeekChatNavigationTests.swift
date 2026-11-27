import XCTest

/// Exercises the WUMIND multi-model workspace, bottom Games tab, streamlined Duty Workbench,
/// PassPlan review, AI Toolbox (including Realtime voice), and Tender Draft navigation without real API keys.
final class DeepSeekChatNavigationTests: XCTestCase {
    private func ensurePortrait() {
        if XCUIDevice.shared.orientation != .portrait {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testPersonalKeySetupFromChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind"]
        app.launch()
        let picker = app.buttons["wumind.model.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 12))
        picker.tap()
        let own = app.buttons["wumind.channel.ownAPI"]
        XCTAssertTrue(own.waitForExistence(timeout: 8))
        own.tap()
        app.buttons["wumind.provider.menu"].tap()
        app.buttons["Anthropic Claude"].tap()
        XCTAssertTrue(app.secureTextFields["ai.key.input"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["ai.baseurl.input"].exists)
        XCTAssertTrue(app.buttons["ai.key.save"].exists)
    }

    func testStreamingScrollAndStopOnIdenticalOfflineInput() {
        for mode in ["batched", "immediate"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-screen", "wumind", "-wumind-stream-qa"]
            if mode == "batched" { app.launchArguments.append("-wumind-batched-baseline") }
            app.launch()
            let probe = app.buttons["wumind.qa.stream"]
            XCTAssertTrue(probe.waitForExistence(timeout: 12))
            probe.tap()
            let stop = app.buttons["deepseek.chat.stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            app.swipeUp()
            app.swipeDown()
            stop.tap()
            XCTAssertTrue(probe.label.contains("bytes="))
            XCTAssertFalse(probe.label.contains("firstBodyMs=-1"))
            print("WUMIND_STREAM mode=" + mode + " " + probe.label)
            app.terminate()
        }
    }

    func testChatCodePreviewRunsAndSavesAnEditableVersion() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind", "-wumind-code-preview-qa"]
        app.launch()
        defer { app.terminate() }
        let counter = app.webViews.buttons["计数 0"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 15))
        counter.tap()
        XCTAssertTrue(app.webViews.buttons["计数 1"].firstMatch.waitForExistence(timeout: 4))
        app.buttons["编辑源码"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 4))
        app.buttons["保存版本"].tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["分享原文件"].exists)
    }

    func testWuMindTranscriptDefaultsToFoldedAndCanScroll() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind", "-wumind-transcript-qa"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let thinking = app.buttons["wumind.thinking.toggle"]
        let answer = app.buttons["wumind.answer.toggle"]
        XCTAssertTrue(thinking.waitForExistence(timeout: 12))
        XCTAssertEqual(thinking.value as? String, "已收起")
        XCTAssertTrue(thinking.label.contains("思考结果"))
        XCTAssertTrue(app.buttons["wumind.composer.dictate"].isHittable, "输入区调整后实时语音仍可点击")
        XCTAssertEqual(answer.value as? String, "已收起")
        XCTAssertTrue(app.staticTexts["wumind.answer.preview"].exists)
        let modelPicker = app.buttons["wumind.model.picker"]
        let close = app.buttons["wumind.chat.backHome"]
        XCTAssertTrue(modelPicker.isHittable && close.isHittable)
        XCTAssertLessThanOrEqual(modelPicker.frame.height, 40, "临时对话有关闭按钮时，模型选择器也必须保持单行高度")
        XCTAssertLessThan(modelPicker.frame.maxX, close.frame.minX)
        let folded = XCTAttachment(screenshot: app.screenshot())
        folded.name = "WuMind-transcript-typography-folded"
        folded.lifetime = .keepAlways
        add(folded)
        thinking.tap()
        XCTAssertEqual(thinking.value as? String, "已展开")
        thinking.tap()
        XCTAssertEqual(thinking.value as? String, "已收起")
        answer.tap()
        XCTAssertEqual(answer.value as? String, "已展开")
        XCTAssertFalse(app.staticTexts["wumind.answer.preview"].exists)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "WuMind-transcript-typography-expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
        app.swipeUp()
        app.swipeDown()
        for _ in 0..<3 where !answer.isHittable { app.swipeDown() }
        XCTAssertTrue(answer.isHittable)
        answer.tap()
        XCTAssertEqual(answer.value as? String, "已收起")
    }

    func testWuMindVideoGenerationStageLayoutWithoutNetwork() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind", "-wumind-video-stage-qa"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let close = app.buttons["wumind.video.stage.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 12))
        let status = app.staticTexts["wumind.video.stage.status"]
        let prompt = app.staticTexts["wumind.video.stage.prompt"]
        let stop = app.buttons["wumind.video.stage.stop"]
        XCTAssertTrue(status.exists && prompt.exists && stop.isHittable)
        XCTAssertEqual(status.label, "≈15%")
        XCTAssertGreaterThan(status.frame.midY, app.frame.midY, "进度位于画布下方，不占中间预览区域")
        XCTAssertGreaterThan(prompt.frame.midY, status.frame.midY)
        XCTAssertFalse(app.buttons["播放成片"].isEnabled, "没有成片时禁用播放")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "WuMind-video-generation-stage"
        capture.lifetime = .keepAlways
        add(capture)

        stop.tap()
        let confirmation = app.alerts["停止等待视频？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["停止等待"].isHittable)
        let keepGenerating = confirmation.buttons["继续生成"]
        XCTAssertTrue(keepGenerating.isHittable)
        keepGenerating.tap()
        XCTAssertTrue(stop.isHittable)
        XCTAssertEqual(status.label, "≈15%", "关闭确认不会影响正在生成的任务")
        close.tap()
        XCTAssertTrue(app.staticTexts["wumind.chat.greeting"].waitForExistence(timeout: 5))
    }

    func testWuMindCleanLayoutAndToolSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let greeting = app.staticTexts["wumind.chat.greeting"]
        let chat = app.buttons["wumind.tab.chat"]
        let workbench = app.buttons["wumind.tab.workbench"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 15))
        XCTAssertTrue(chat.isHittable && workbench.isHittable)
        XCTAssertGreaterThan(chat.frame.midY, greeting.frame.midY)
        XCTAssertTrue(app.buttons["wumind.composer.dictate"].isHittable, "语音通话保留在对话首屏")
        XCTAssertTrue(app.buttons["wumind.attach.open"].isHittable)
        XCTAssertFalse(app.buttons["wumind.webSearch.toggle"].exists, "默认不应把整排工具铺在输入框下")
        XCTAssertTrue(app.buttons["wumind.composer.options"].isHittable)
        let chatShot = XCTAttachment(screenshot: app.screenshot())
        chatShot.name = "WuMind-clean-chat"
        chatShot.lifetime = .keepAlways
        add(chatShot)

        workbench.tap()
        let search = app.textFields["wumind.workbench.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        let image = app.buttons["wumind.quick.image"]
        let video = app.buttons["wumind.quick.video"]
        let ppt = app.buttons["wumind.quick.ppt"]
        XCTAssertTrue(image.isHittable && video.isHittable && ppt.isHittable)
        XCTAssertLessThan(image.frame.midX, video.frame.midX)
        XCTAssertEqual(image.frame.midY, video.frame.midY, accuracy: 4)
        XCTAssertLessThan(ppt.frame.midY, search.frame.midY)
        XCTAssertFalse(app.buttons["wumind.workbench.pipeline.ppt"].exists)
        let workbenchShot = XCTAttachment(screenshot: app.screenshot())
        workbenchShot.name = "WuMind-clean-workbench"
        workbenchShot.lifetime = .keepAlways
        add(workbenchShot)

        search.tap()
        search.typeText("PPT")
        XCTAssertTrue(ppt.isHittable)
        XCTAssertFalse(video.exists)
        let clear = app.buttons["wumind.workbench.clearSearch"]
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        ppt.tap()
        XCTAssertTrue(app.navigationBars["幻灯片"].waitForExistence(timeout: 8))
    }

    func testWorkbenchOpensOriginalTenToolsDirectly() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let workbench = app.buttons["wumind.tab.workbench"]
        XCTAssertTrue(workbench.waitForExistence(timeout: 15))
        workbench.tap()
        let tools = [
            ("wumind.quick.image", "画室"), ("wumind.quick.video", "视频"),
            ("wumind.quick.ppt", "幻灯片"), ("wumind.quick.spatial3d", "3D 空间"),
            ("deepSeek.chat.tender", "投标草稿"), ("wumind.quick.code", "编程"),
            ("wumind.quick.live", "实时语音通话"), ("wumind.quick.speech", "语音合成与转写"),
            ("wumind.quick.work", "办公"), ("wumind.quick.agentOS", "项目与智能体")
        ]
        for (id, title) in tools {
            let button = app.buttons[id]
            for _ in 0..<4 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable, "工作台缺少入口：" + title)
            let start = ProcessInfo.processInfo.systemUptime
            button.tap()
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 10), "一次点击应打开工具页面：" + title)
            print("WUMIND_OPEN tool=" + id + " elapsedMs=" + String(Int((ProcessInfo.processInfo.systemUptime - start) * 1000)))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Workbench-" + id
            shot.lifetime = .keepAlways
            add(shot)
            bar.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.textFields["wumind.workbench.search"].waitForExistence(timeout: 8))
        }
    }

    func testWorkspaceLauncherHomeColdStartRoundTripAndDraftPreservation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        // 1. Cold start lands cleanly on pure 2-card dark glass Launcher Home (NO bottom tab bar!)
        let homeRoot = app.descendants(matching: .any).matching(identifier: "workspace.home.root").firstMatch
        let dutyCard = app.buttons["workspace.home.onDuty"]
        let wumindCard = app.buttons["workspace.home.wumind"]
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 15), "冷启动应直接停留在双卡工作区选择首页")
        XCTAssertTrue(dutyCard.waitForExistence(timeout: 10) && dutyCard.isHittable, "首页缺少 On Duty 卡片")
        XCTAssertTrue(wumindCard.waitForExistence(timeout: 10) && wumindCard.isHittable, "首页缺少 WuMind 卡片")
        XCTAssertFalse(app.buttons["app.tab.今天"].exists, "工作区选择首页不得出现底部导航栏")
        XCTAssertFalse(app.buttons["app.tab.游戏"].exists, "工作区选择首页不得出现游戏标签栏")

        // Verify equal card sizes & crisp vertical stack inside screen bounds
        XCTAssertEqual(dutyCard.frame.width, wumindCard.frame.width, accuracy: 2.0, "两张入口卡片宽度必须一致")
        XCTAssertEqual(dutyCard.frame.height, wumindCard.frame.height, accuracy: 2.0, "两张入口卡片高度必须一致")
        XCTAssertGreaterThan(wumindCard.frame.minY, dutyCard.frame.maxY + 20, "WuMind 卡片应垂直排列在 On Duty 下方")
        XCTAssertLessThanOrEqual(dutyCard.frame.maxX, app.frame.maxX + 1)

        usleep(350_000)
        let launcherShot = XCTAttachment(screenshot: app.screenshot())
        launcherShot.name = "Workspace-launcher-home"
        launcherShot.lifetime = .keepAlways
        add(launcherShot)

        // 2. Enter On Duty -> verify top-left 返回首页 -> return cleanly to Launcher Home
        dutyCard.tap()
        let dutyBack = app.buttons["workspace.backToHome"]
        XCTAssertTrue(dutyBack.waitForExistence(timeout: 12) && dutyBack.isHittable, "On Duty 左上角缺少「返回首页」按钮")
        XCTAssertTrue(app.buttons["app.tab.今天"].waitForExistence(timeout: 8), "进入 On Duty 后底部标签栏应正常显示")
        dutyBack.tap()
        XCTAssertTrue(wumindCard.waitForExistence(timeout: 10), "从 On Duty 返回后应回到双卡首页")

        // 3. Enter WuMind -> type draft -> return to Home -> re-enter WuMind -> draft MUST be preserved!
        wumindCard.tap()
        let wumindBack = app.buttons["wumind.backToHome"]
        XCTAssertTrue(wumindBack.waitForExistence(timeout: 12) && wumindBack.isHittable, "WuMind 左上角缺少「首页」返回按钮")
        let composer = app.descendants(matching: .any).matching(identifier: "deepSeek.chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "WuMind 输入框未显示")
        composer.tap()
        composer.typeText("KeepDraftAcrossHome")
        usleep(250_000)
        let dismissKB = app.buttons["wumind.composer.dismissKeyboard"]
        if dismissKB.waitForExistence(timeout: 4) && dismissKB.isHittable {
            dismissKB.tap()
            usleep(250_000)
        }
        wumindBack.tap()
        XCTAssertTrue(wumindCard.waitForExistence(timeout: 10), "从 WuMind 返回后应回到双卡首页")

        // Re-enter WuMind and confirm draft was NOT destroyed!
        wumindCard.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        let preservedValue = (composer.value as? String) ?? composer.label
        XCTAssertTrue(preservedValue.contains("KeepDraftAcrossHome"), "返回工作区首页再回来时，WuMind 草稿不得丢失（实际：\(preservedValue)）")

        // 4. Verify History Sidebar Archive menu (`⋯ -> 已归档`) opens cleanly
        let sidebarBtn = app.buttons["wumind.sidebar.open"]
        XCTAssertTrue(sidebarBtn.waitForExistence(timeout: 8) && sidebarBtn.isHittable)
        sidebarBtn.tap()
        let moreMenu = app.buttons["wumind.history.moreMenu"]
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 8), "历史对话列表缺少「⋯」更多操作菜单（归档入口）")
        moreMenu.tap()
        let archivedEntry = app.buttons.matching(NSPredicate(format: "label CONTAINS '已归档'")).firstMatch
        XCTAssertTrue(archivedEntry.waitForExistence(timeout: 6), "「⋯」菜单中缺少「已归档」入口")
        archivedEntry.tap()
        XCTAssertTrue(app.navigationBars["已归档对话"].waitForExistence(timeout: 8), "点击「已归档」后未打开已归档对话列表")
        let archivedShot = XCTAttachment(screenshot: app.screenshot())
        archivedShot.name = "WuMind-archived-sheet"
        archivedShot.lifetime = .keepAlways
        add(archivedShot)
        app.navigationBars["已归档对话"].buttons["完成"].tap()
        usleep(250_000)
    }

    func testOpenChatFromHomeAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        // Verify Games tab sits directly in bottom tab bar and Duty top-left has 返回首页
        let gamesTab = app.buttons["app.tab.游戏"]
        XCTAssertTrue(gamesTab.waitForExistence(timeout: 15), "底部导航栏缺少游戏标签")
        XCTAssertLessThanOrEqual(
            app.frame.maxY - gamesTab.frame.maxY,
            46,
            "底部导航栏应紧贴屏幕最底部安全区，不应悬浮抬高"
        )
        let backHomeBtn = app.buttons["workspace.backToHome"]
        XCTAssertTrue(backHomeBtn.waitForExistence(timeout: 10), "值班页左上角缺少「返回首页」入口")
        XCTAssertTrue(backHomeBtn.isHittable)
        let homeShot = XCTAttachment(screenshot: app.screenshot())
        homeShot.name = "Today-streamlined"
        homeShot.lifetime = .keepAlways
        add(homeShot)

        // Return to Workspace Launcher Home and open WuMind
        backHomeBtn.tap()
        let wumindCard = app.buttons["workspace.home.wumind"]
        XCTAssertTrue(wumindCard.waitForExistence(timeout: 10), "返回首页后未显示 WuMind 入口卡片")
        wumindCard.tap()

        // Verify WUMIND opens full-screen with ZERO bottom tab bar visible or hittable!
        let composer = app.descendants(matching: .any)
            .matching(identifier: "deepSeek.chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "WUMIND 输入框未显示")
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "打开 WUMIND 时不应显示底部导航栏")
        XCTAssertFalse(app.buttons["app.tab.游戏"].isHittable, "打开 WUMIND 时底部游戏栏不应可见")
        XCTAssertTrue(app.buttons["wumind.model.picker"].exists, "缺少顶部模型切换胶囊")
        XCTAssertTrue(app.buttons["wumind.sidebar.open"].exists, "缺少历史对话侧边栏按钮")
        XCTAssertTrue(app.buttons["wumind.tempChat.toggle"].exists, "缺少临时聊天模式切换按钮")
        XCTAssertTrue(app.buttons["wumind.tab.chat"].exists, "缺少对话主标签")
        XCTAssertTrue(app.buttons["wumind.tab.workbench"].exists, "缺少工作台主标签")
        XCTAssertTrue(app.buttons["wumind.tab.works"].exists, "缺少作品主标签")
        XCTAssertTrue(app.staticTexts["wumind.chat.greeting"].exists, "空白聊天缺少居中问候")
        XCTAssertGreaterThan(app.buttons["wumind.tab.chat"].frame.midY, composer.frame.midY, "主标签应位于输入框下方")
        app.buttons["wumind.composer.options"].tap()
        XCTAssertTrue(app.buttons["wumind.webSearch.toggle"].exists, "对话选项中缺少联网搜索开关")
        XCTAssertTrue(app.buttons["deepSeek.chat.thinking"].exists, "缺少深度思考切换胶囊")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.attach.open").firstMatch.exists,
                      "对话框下方缺少聊天内连接与上传按钮")
        XCTAssertTrue(app.buttons["wumind.composer.connections"].exists,
                      "对话选项缺少模型与连接器")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.context.menu").firstMatch.exists,
                      "对话框下方缺少 1M 上下文与自动压缩控制按钮")
        XCTAssertTrue(app.buttons["wumind.agent.toggle"].exists, "对话框下方缺少智能体模式开关")
        XCTAssertTrue(app.buttons["wumind.composer.dictate"].exists, "对话框下方缺少独立语音对话入口按钮")

        let skillsBtn = app.buttons["wumind.skills.open"]
        XCTAssertTrue(skillsBtn.exists && skillsBtn.isHittable, "定制按钮应直接在屏幕内可见，无需左右滑动")
        let githubBtn = app.buttons["wumind.attach.open"]
        XCTAssertTrue(githubBtn.exists && githubBtn.isHittable, "从加号仍能打开 GitHub 连接器")
        let contextBtn = app.descendants(matching: .any).matching(identifier: "wumind.context.menu").firstMatch
        XCTAssertTrue(contextBtn.exists && contextBtn.frame.maxX <= app.frame.maxX + 1, "1M 上下文按钮不应超出屏幕右边界")

        let chatShot = XCTAttachment(screenshot: app.screenshot())
        chatShot.name = "WuMind-chat"
        chatShot.lifetime = .keepAlways
        add(chatShot)

        // Toggle Temporary Chat mode ON -> verify banner -> capture screenshot -> exit Temporary Chat
        let tempBtn = app.buttons["wumind.tempChat.toggle"]
        tempBtn.tap()
        let tempBanner = app.descendants(matching: .any).matching(identifier: "wumind.tempChat.banner").firstMatch
        XCTAssertTrue(tempBanner.waitForExistence(timeout: 6), "点击临时聊天按钮后应出现无痕临时聊天提示条")
        let tempShot = XCTAttachment(screenshot: app.screenshot())
        tempShot.name = "WuMind-temp-chat"
        tempShot.lifetime = .keepAlways
        add(tempShot)
        tempBtn.tap()
        usleep(250_000)

        // Open ChatGPT-Style Half-Height In-Chat Connectors & Plugins Sheet directly over chat!
        XCTAssertTrue(githubBtn.isHittable, "GitHub 连接按钮无需滑动即可直接点击")
        githubBtn.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.inchat.github.input").firstMatch.waitForExistence(timeout: 8),
                      "聊天内 GitHub 与插件半屏面板未打开")
        let inChatShot = XCTAttachment(screenshot: app.screenshot())
        inChatShot.name = "WuMind-inchat-connectors"
        inChatShot.lifetime = .keepAlways
        add(inChatShot)
        app.navigationBars["聊天内连接与插件"].buttons["完成"].tap()
        usleep(300_000)

        // 1) Verify Ordinary Voice Input button (Microphone -> WuMindGeminiVoiceView)
        let micBtn = app.buttons["wumind.composer.mic"]
        XCTAssertTrue(micBtn.waitForExistence(timeout: 6) && micBtn.isHittable, "首页输入栏缺少普通语音输入（麦克风）按钮")
        micBtn.tap()
        let voiceOrb = app.buttons["wumind.voice.orb"]
        XCTAssertTrue(voiceOrb.waitForExistence(timeout: 8), "普通语音输入页面未打开")
        let voiceShot = XCTAttachment(screenshot: app.screenshot())
        voiceShot.name = "WuMind-gemini-voice"
        voiceShot.lifetime = .keepAlways
        add(voiceShot)
        let voiceClose = app.buttons["wumind.voice.close"]
        XCTAssertTrue(voiceClose.waitForExistence(timeout: 5))
        voiceClose.tap()
        usleep(300_000)

        // 2) Verify Dedicated Real-Time Voice Call button (full live-call modal launch is tested in testWuMindColdStartComposerAttachmentsAndVoiceStability & testProviderChooserOpensWithoutContactingAI)
        let liveVoiceBtn = app.buttons["wumind.composer.dictate"]
        XCTAssertTrue(liveVoiceBtn.waitForExistence(timeout: 6) && liveVoiceBtn.isHittable, "首页输入栏缺少独立实时语音通话按钮")

        // Switch to Unified Workbench tab («工作台») and verify studios, pipelines, projects, schedules, and wallet!
        let workbenchTab = app.buttons["wumind.tab.workbench"]
        XCTAssertTrue(workbenchTab.waitForExistence(timeout: 6) && workbenchTab.isHittable)
        workbenchTab.tap()
        let workbenchSearch = app.textFields["wumind.workbench.search"]
        XCTAssertTrue(workbenchSearch.waitForExistence(timeout: 8), "工作台缺少底部搜索")
        XCTAssertTrue(app.buttons["wumind.workbench.settings"].isHittable, "工作台设置入口不可点击")
        XCTAssertTrue(app.buttons["wumind.quick.image"].exists, "工作台缺少生图入口")
        XCTAssertTrue(app.buttons["wumind.quick.video"].exists, "工作台缺少视频入口")
        XCTAssertTrue(app.buttons["wumind.quick.ppt"].exists, "工作台缺少 PPT 入口")
        XCTAssertTrue(app.buttons["deepSeek.chat.tender"].exists, "工作台缺少标书入口")
        XCTAssertFalse(app.buttons["wumind.workbench.pipeline.ppt"].exists, "低频续作不应挤占首屏")
        let workbenchShot = XCTAttachment(screenshot: app.screenshot())
        workbenchShot.name = "WuMind-workbench"
        workbenchShot.lifetime = .keepAlways
        add(workbenchShot)

        workbenchSearch.tap()
        workbenchSearch.typeText("PPT")
        XCTAssertTrue(app.buttons["wumind.quick.ppt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wumind.quick.video"].exists, "搜索应隐藏不匹配入口")
        let clearSearch = app.buttons["wumind.workbench.clearSearch"]
        XCTAssertTrue(clearSearch.waitForExistence(timeout: 5))
        clearSearch.tap()
        XCTAssertTrue(app.buttons["wumind.quick.video"].waitForExistence(timeout: 5))

        let resume = app.buttons["wumind.workbench.continue"]
        for _ in 0..<3 where !resume.isHittable { app.swipeUp() }
        XCTAssertTrue(resume.isHittable, "找不到继续编辑")
        resume.tap()
        let pptPipeline = app.buttons["wumind.workbench.pipeline.ppt"]
        for _ in 0..<2 where !pptPipeline.isHittable { app.swipeUp() }
        XCTAssertTrue(pptPipeline.isHittable, "展开后缺少 PPT 续作入口")
        let spatialPipeline = app.buttons["wumind.workbench.pipeline.3d"]
        for _ in 0..<2 where !spatialPipeline.isHittable { app.swipeUp() }
        XCTAssertTrue(spatialPipeline.isHittable, "展开后缺少 3D 续作入口")

        let manage = app.buttons["wumind.workbench.manage"]
        for _ in 0..<4 where !manage.isHittable { app.swipeUp() }
        XCTAssertTrue(manage.isHittable, "找不到空间与账户管理")
        manage.tap()
        let walletBtn = app.buttons["wumind.wallet.open"]
        for _ in 0..<3 where !walletBtn.isHittable { app.swipeUp() }
        XCTAssertTrue(walletBtn.isHittable, "展开后缺少钱包入口")

        // Open Projects Workspace sheet and capture proof screenshot
        let projectsDock = app.buttons["wumind.dock.projects"]
        if projectsDock.waitForExistence(timeout: 5) && projectsDock.isHittable {
            projectsDock.tap()
            XCTAssertTrue(app.buttons["wumind.projects.create"].waitForExistence(timeout: 8), "项目空间缺少新建入口")
            let projShot = XCTAttachment(screenshot: app.screenshot())
            projShot.name = "WuMind-projects"
            projShot.lifetime = .keepAlways
            add(projShot)
            app.navigationBars.buttons["完成"].tap()
            usleep(300_000)
        }

        // Open Scheduled Tasks sheet and verify Cloud Cron Pull button + capture proof screenshot
        let schedulesDock = app.buttons["wumind.dock.schedules"]
        if schedulesDock.waitForExistence(timeout: 5) && schedulesDock.isHittable {
            schedulesDock.tap()
            XCTAssertTrue(app.buttons["wumind.schedules.create"].waitForExistence(timeout: 8), "定时任务中心缺少新建入口")
            XCTAssertTrue(app.buttons["wumind.schedules.pullCloud"].exists, "定时任务中心缺少云端定时结果拉取按钮")
            let schedShot = XCTAttachment(screenshot: app.screenshot())
            schedShot.name = "WuMind-schedules"
            schedShot.lifetime = .keepAlways
            add(schedShot)
            app.navigationBars.buttons["完成"].tap()
            usleep(300_000)
        }

        // Verify Wallet + StoreKit 2 IAP grid + TestFlight compliance from Workbench
        if walletBtn.waitForExistence(timeout: 6) && walletBtn.isHittable {
            walletBtn.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.wallet.balance").firstMatch.waitForExistence(timeout: 8),
                          "WUMIND 钱包缺少余额显示")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.wallet.usageGrid").firstMatch.exists,
                          "WUMIND 钱包缺少用量统计面板")
            let complianceBanner = app.descendants(matching: .any).matching(identifier: "wumind.wallet.testFlightComplianceBanner").firstMatch
            for _ in 0..<2 where !complianceBanner.exists {
                app.swipeUp()
                usleep(200_000)
            }
            XCTAssertTrue(complianceBanner.waitForExistence(timeout: 6), "TestFlight / 沙盒钱包必须展示合规不收费保护提示")
            let iapGrid = app.descendants(matching: .any).matching(identifier: "wumind.wallet.iapGrid").firstMatch
            for _ in 0..<2 where !iapGrid.exists {
                app.swipeUp()
                usleep(200_000)
            }
            XCTAssertTrue(iapGrid.waitForExistence(timeout: 6),
                          "WUMIND 钱包缺少 Apple StoreKit 2 沙盒内购流量包")
            let walletShot = XCTAttachment(screenshot: app.screenshot())
            walletShot.name = "WuMind-wallet"
            walletShot.lifetime = .keepAlways
            add(walletShot)
            let voucherInput = app.textFields["wumind.wallet.voucherInput"]
            for _ in 0..<3 where !voucherInput.exists {
                app.swipeUp()
                usleep(200_000)
            }
            XCTAssertTrue(voucherInput.exists, "WUMIND 钱包缺少免费测试兑换码入口")
            XCTAssertFalse(app.buttons["wumind.wallet.createAutoOrder"].exists,
                           "依据 Apple TestFlight 条款，测试版本不得暴露真实收费外跳支付单按钮")
            app.navigationBars["WUMIND 钱包与计费"].buttons["完成"].tap()
            usleep(300_000)
        }

        // Switch to embedded «作品» tab and capture proof screenshot
        let worksTab = app.buttons["wumind.tab.works"]
        XCTAssertTrue(worksTab.waitForExistence(timeout: 6) && worksTab.isHittable)
        worksTab.tap()
        XCTAssertTrue(app.buttons["wumind.works.refresh"].waitForExistence(timeout: 8), "作品页缺少云端同步刷新按钮")
        let myWorksShot = XCTAttachment(screenshot: app.screenshot())
        myWorksShot.name = "WuMind-my-works"
        myWorksShot.lifetime = .keepAlways
        add(myWorksShot)

        // Return to «对话» tab, open & close sidebar drawer
        app.buttons["wumind.tab.chat"].tap()
        usleep(200_000)
        app.buttons["wumind.sidebar.open"].tap()
        usleep(350_000)
        let drawerShot = XCTAttachment(screenshot: app.screenshot())
        drawerShot.name = "WuMind-drawer"
        drawerShot.lifetime = .keepAlways
        add(drawerShot)

        // Return to Workspace Launcher Home and switch back to On Duty
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        usleep(300_000)
        let wumindBack = app.buttons["wumind.backToHome"]
        XCTAssertTrue(wumindBack.waitForExistence(timeout: 8), "WuMind 左上角缺少返回首页按钮")
        wumindBack.tap()
        let onDutyCard = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(onDutyCard.waitForExistence(timeout: 10), "从 WuMind 返回首页后缺少 On Duty 卡片")
        onDutyCard.tap()
        XCTAssertTrue(backHomeBtn.waitForExistence(timeout: 10))
        XCTAssertTrue(gamesTab.waitForExistence(timeout: 10))

        // Verify External User Registration & Viewing Boundary Sheet from Settings tab
        let settingsTab = app.buttons["app.tab.设置"]
        if settingsTab.waitForExistence(timeout: 5) && settingsTab.isHittable {
            settingsTab.tap()
            let extRow = app.buttons["settings.externalAuth"]
            XCTAssertTrue(extRow.waitForExistence(timeout: 8), "设置页缺少外部人员登录与查看界限入口")
            extRow.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "external.auth.phone").firstMatch.waitForExistence(timeout: 8),
                          "外部登录面板缺少手机号输入框")
            XCTAssertTrue(app.buttons["external.auth.guest"].exists, "外部登录面板缺少外部访客边界体验入口")
            let extShot = XCTAttachment(screenshot: app.screenshot())
            extShot.name = "WuMind-external-auth"
            extShot.lifetime = .keepAlways
            add(extShot)
            app.navigationBars["外部用户登录"].buttons["关闭"].tap()
        }
    }

    func testProviderChooserOpensWithoutContactingAI() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        // 1. Open the model and capability center using the header, without crowding the composer.
        let composerModel = app.buttons["wumind.model.picker"]
        XCTAssertTrue(composerModel.waitForExistence(timeout: 15) && composerModel.isHittable)
        composerModel.tap()
        XCTAssertTrue(app.buttons["wumind.models.tab.chat"].waitForExistence(timeout: 8), "模型中心缺少文字对话入口")
        XCTAssertTrue(app.buttons["wumind.models.tab.image"].exists, "模型中心缺少图像生成专用入口")
        XCTAssertTrue(app.buttons["wumind.models.tab.voice"].exists, "模型中心缺少实时语音专用入口")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.models.search").firstMatch.exists,
                      "模型中心缺少全量模型搜索框")
        let modelCenterShot = XCTAttachment(screenshot: app.screenshot())
        modelCenterShot.name = "WuMind-model-center"
        modelCenterShot.lifetime = .keepAlways
        add(modelCenterShot)
        app.navigationBars["WUMIND 模型与能力中心"].buttons["完成"].tap()
        usleep(300_000)

        // 2. Switch to Unified Workbench tab -> Open Flagship AI Capability Workshop (全部工坊)
        let workbenchTab = app.buttons["wumind.tab.workbench"]
        XCTAssertTrue(workbenchTab.waitForExistence(timeout: 8) && workbenchTab.isHittable, "缺少工作台主标签")
        workbenchTab.tap()
        usleep(250_000)

        let switcher = app.buttons["ai.providers.open"]
        for _ in 0..<4 where !switcher.isHittable {
            app.swipeUp()
            usleep(200_000)
        }
        XCTAssertTrue(switcher.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(switcher.frame.maxX, app.frame.maxX + 1, "全部工坊按钮不应超出屏幕右边界")
        switcher.tap()
        if !app.buttons["ai.tools.spatial3d"].waitForExistence(timeout: 4) && switcher.isHittable {
            switcher.tap()
        }

        for id in ["spatial3d", "image", "video", "ppt", "live", "speech", "code", "work"] {
            let btn = app.buttons["ai.tools." + id]
            if !btn.exists {
                app.swipeUp()
                usleep(150_000)
            }
            XCTAssertTrue(btn.exists || btn.waitForExistence(timeout: 4), "Missing tool " + id)
        }
        XCTAssertFalse(app.buttons["ai.provider.gemini"].exists, "AI 工具箱不应再出现多余的第三方对话入口（首页即可切换模型）")
        app.swipeDown()
        usleep(150_000)
        app.swipeDown()
        usleep(150_000)
        let toolboxShot = XCTAttachment(screenshot: app.screenshot())
        toolboxShot.name = "WuMind-toolbox"
        toolboxShot.lifetime = .keepAlways
        add(toolboxShot)

        // 2b. Flagship AI 3D Spatial Studio (Default camera is already redriver.aerial + 3D Tech Library Sheet)
        let spatialTool = app.buttons["ai.tools.spatial3d"]
        XCTAssertTrue(spatialTool.waitForExistence(timeout: 6) && spatialTool.isHittable)
        spatialTool.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.spatial3d.viewport").firstMatch.waitForExistence(timeout: 8),
                      "AI 3D 空间工坊 3D 视图未显示")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.spatial3d.perfHud").firstMatch.exists,
                      "AI 3D 空间工坊缺少实时 FPS/性能 HUD")
        usleep(500_000)
        let townMainShot = XCTAttachment(screenshot: app.screenshot())
        townMainShot.name = "WuMind-3d-redriver-main"
        townMainShot.lifetime = .keepAlways
        add(townMainShot)

        // Open the real toolbar action on both device families, not the in-page shortcut.
        let techLibraryToolbar = app.buttons["ai.spatial3d.openTechLibraryToolbar"]
        guard techLibraryToolbar.waitForExistence(timeout: 6), techLibraryToolbar.isHittable else {
            XCTFail("AI 3D 空间工坊工具栏缺少可点击的技术库按钮")
            return
        }
        techLibraryToolbar.tap()
        let techLibraryNavigationBar = app.navigationBars["3D 技术库"]
        let techLibraryDone = techLibraryNavigationBar.buttons["完成"]
        guard techLibraryDone.waitForExistence(timeout: 8), techLibraryDone.isHittable else {
            XCTFail("3D 技术库二级面板未打开，或无法关闭")
            return
        }
        let techLibShot = XCTAttachment(screenshot: app.screenshot())
        techLibShot.name = "WuMind-3d-tech-library"
        techLibShot.lifetime = .keepAlways
        add(techLibShot)
        techLibraryDone.tap()
        XCTAssertTrue(app.navigationBars["3D 空间"].waitForExistence(timeout: 5),
                      "关闭技术库后未返回 AI 3D 空间工坊")

        app.navigationBars["3D 空间"].buttons.element(boundBy: 0).tap()
        usleep(300_000)

        // 3. Flagship AI Video & Short-Drama Studio v1
        let videoTool = app.buttons["ai.tools.video"]
        for _ in 0..<3 where !videoTool.isHittable {
            app.swipeUp()
            usleep(200_000)
        }
        XCTAssertTrue(videoTool.waitForExistence(timeout: 6) && videoTool.isHittable)
        videoTool.tap()
        let shortDramaMode = app.buttons["ai.video.mode.shortDrama"]
        XCTAssertTrue(shortDramaMode.waitForExistence(timeout: 8), "短剧工坊模式切换未显示")
        XCTAssertTrue(app.buttons["ai.video.mode.singleClip"].exists, "单镜头直出模式切换未显示")
        XCTAssertLessThanOrEqual(app.buttons["ai.video.mode.singleClip"].frame.maxX, app.frame.maxX + 1, "视频工坊模式栏不应超出屏幕右边界")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.video.prompt").firstMatch.waitForExistence(timeout: 8),
                      "AI 生视频工坊提示词输入框未显示")
        XCTAssertTrue(app.buttons["ai.video.generate"].exists)
        XCTAssertTrue(app.buttons["ai.drama.apiConfig"].exists, "短剧工坊缺少官方接口配置入口")
        XCTAssertTrue(app.buttons["ai.drama.exportMP4"].exists, "短剧工坊缺少 9:16 MP4 导出入口")
        XCTAssertTrue(app.buttons["ai.drama.multiPublish"].exists, "短剧工坊缺少多平台适配发布入口")
        XCTAssertTrue(app.buttons["ai.video.history"].exists, "视频工坊缺少历史作品入口")
        let videoShot = XCTAttachment(screenshot: app.screenshot())
        videoShot.name = "WuMind-video-studio"
        videoShot.lifetime = .keepAlways
        add(videoShot)

        // Switch to Single Clip mode and verify Sora 2 valid duration picker (4/8/12s)
        let singleClipBtn = app.buttons["ai.video.mode.singleClip"]
        singleClipBtn.tap()
        usleep(300_000)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.video.duration").firstMatch.waitForExistence(timeout: 6), "单镜头直出缺少按模型动态匹配的时长选择器")
        let singleClipShot = XCTAttachment(screenshot: app.screenshot())
        singleClipShot.name = "WuMind-video-singleclip"
        singleClipShot.lifetime = .keepAlways
        add(singleClipShot)

        app.navigationBars["视频"].buttons.element(boundBy: 0).tap()
        usleep(300_000)

        // 4. Flagship AI PPT Studio
        let pptTool = app.buttons["ai.tools.ppt"]
        XCTAssertTrue(pptTool.waitForExistence(timeout: 6) && pptTool.isHittable)
        pptTool.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.ppt.prompt").firstMatch.waitForExistence(timeout: 8),
                      "AI 写 PPT 工坊输入框未显示")
        XCTAssertTrue(app.buttons["ai.ppt.generate"].exists)
        XCTAssertTrue(app.buttons["ai.ppt.uploadFile"].exists, "PPT 工坊缺少 Word/PDF/Excel 上传入口")
        XCTAssertTrue(app.buttons["ai.ppt.uploadPhoto"].exists, "PPT 工坊缺少图片上传入口")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.ppt.uploadLogo").firstMatch.exists, "PPT 工坊缺少公司 Logo 上传入口")
        XCTAssertTrue(app.buttons["ai.ppt.history"].exists, "PPT 工坊缺少历史作品入口")
        let webToggle = app.buttons["ai.ppt.webSearch"]
        XCTAssertTrue(webToggle.exists && webToggle.frame.maxX <= app.frame.maxX + 1, "PPT 工坊联网开关不应超出屏幕右边界")
        let pptShot = XCTAttachment(screenshot: app.screenshot())
        pptShot.name = "WuMind-ppt-studio"
        pptShot.lifetime = .keepAlways
        add(pptShot)
        app.navigationBars["幻灯片"].buttons.element(boundBy: 0).tap()
        usleep(300_000)

        // 5. Flagship WUMIND Image Studio (Grok / GPT studio layout + reference image + speed tiers + keyboard non-occlusion)
        let imageTool = app.buttons["ai.tools.image"]
        XCTAssertTrue(imageTool.waitForExistence(timeout: 8) && imageTool.isHittable)
        imageTool.tap()

        let promptField = app.descendants(matching: .any).matching(identifier: "ai.image.prompt").firstMatch
        XCTAssertTrue(promptField.waitForExistence(timeout: 10), "WUMIND 画室输入框未显示")
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "文字生图画室不应显示底部导航栏")

        let routeBadge = app.descendants(matching: .any).matching(identifier: "ai.image.routeBadge").firstMatch
        let speedPill = app.descendants(matching: .any).matching(identifier: "ai.image.speed").firstMatch
        let aspectPill = app.descendants(matching: .any).matching(identifier: "ai.image.aspect").firstMatch
        let countPill = app.descendants(matching: .any).matching(identifier: "ai.image.count").firstMatch
        let settingsPill = app.descendants(matching: .any).matching(identifier: "ai.image.settings").firstMatch
        let addRefBtn = app.descendants(matching: .any).matching(identifier: "ai.image.addReference").firstMatch
        XCTAssertTrue(routeBadge.waitForExistence(timeout: 6), "画室顶部缺少显式路由状态胶囊（WuMind 内置 / 自有 API · AIHubMix）")
        XCTAssertTrue(app.buttons["ai.image.diagnostics"].exists, "画室缺少脱敏诊断日志入口")
        XCTAssertTrue(speedPill.waitForExistence(timeout: 6), "画室缺少快速草稿/高清成品切换胶囊")
        XCTAssertTrue(addRefBtn.waitForExistence(timeout: 6), "画室缺少「添加参考图」入口")
        XCTAssertTrue(app.buttons["ai.image.history"].exists, "画室缺少历史作品入口")
        XCTAssertTrue(aspectPill.exists, "画室缺少画幅比例胶囊")
        XCTAssertTrue(countPill.exists, "画室缺少并发张数胶囊")
        XCTAssertTrue(settingsPill.exists, "画室缺少高级参数按钮")
        XCTAssertLessThanOrEqual(settingsPill.frame.maxX, app.frame.maxX + 1, "画室控制栏不应超出屏幕右边界")

        let studioIdleShot = XCTAttachment(screenshot: app.screenshot())
        studioIdleShot.name = "WuMind-image-studio"
        studioIdleShot.lifetime = .keepAlways
        add(studioIdleShot)

        let inspiration = app.buttons["ai.image.inspiration.wildlife"]
        if inspiration.waitForExistence(timeout: 4) && inspiration.isHittable {
            inspiration.tap()
            usleep(250_000)
            XCTAssertTrue(app.buttons["ai.image.generate"].isEnabled, "点击灵感模板后生成按钮应立即可用")
        }

        promptField.tap()
        usleep(350_000)
        let dismissKB = app.buttons["ai.image.dismissKeyboard"]
        XCTAssertTrue(dismissKB.waitForExistence(timeout: 5), "输入提示词时画室应展示一键收起键盘按钮")
        if app.keyboards.count > 0 && app.keyboards.firstMatch.frame.height > 40 {
            XCTAssertLessThanOrEqual(
                promptField.frame.maxY,
                app.keyboards.firstMatch.frame.minY + 6,
                "键盘不应遮挡画室底部输入胶囊"
            )
        }
        let studioFocusedShot = XCTAttachment(screenshot: app.screenshot())
        studioFocusedShot.name = "WuMind-image-studio-typing"
        studioFocusedShot.lifetime = .keepAlways
        add(studioFocusedShot)

        dismissKB.tap()
        usleep(300_000)

        let imageBack = app.navigationBars["画室"].buttons.element(boundBy: 0)
        XCTAssertTrue(imageBack.waitForExistence(timeout: 6), "WUMIND 画室返回按钮未显示")
        imageBack.tap()

        XCTAssertTrue(app.buttons["ai.tools.live"].waitForExistence(timeout: 8))
        usleep(300_000)

        // 6. Flagship Realtime Voice Studio
        let live = app.buttons["ai.tools.live"]
        if !live.isHittable { app.swipeUp(); usleep(200_000) }
        live.tap()
        XCTAssertTrue(app.staticTexts["ai.live.status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ai.live.start"].exists)
        XCTAssertFalse(app.buttons["ai.live.end"].exists)
        let liveShot = XCTAttachment(screenshot: app.screenshot())
        liveShot.name = "WuMind-live-voice"
        liveShot.lifetime = .keepAlways
        add(liveShot)
    }

    func testDutyWorkbenchPassPlanAndTenderNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let workbench = app.descendants(matching: .any)
            .matching(identifier: "today.dutyWorkbench").firstMatch
        XCTAssertTrue(workbench.waitForExistence(timeout: 15), "精简值班操作栏未显示")

        let planButton = app.buttons["today.workbench.plan"]
        let handoffButton = app.buttons["today.workbench.handoff"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 8) || handoffButton.exists, "值班操作栏缺少计划或交班入口")
        if planButton.exists && planButton.isHittable {
            planButton.tap()
            XCTAssertTrue(app.buttons["passplan.capture.camera"].waitForExistence(timeout: 10), "值班计划缺少原相机拍照入口")
            XCTAssertFalse(app.staticTexts["目标微信群"].exists, "值班计划不应要求填写目标群信息")
            let shotPlan = XCTAttachment(screenshot: app.screenshot())
            shotPlan.name = "duty-passplan-review"
            shotPlan.lifetime = .keepAlways
            add(shotPlan)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        let backToHome = app.buttons["workspace.backToHome"]
        XCTAssertTrue(backToHome.waitForExistence(timeout: 10), "值班页左上角缺少返回首页按钮")
        backToHome.tap()
        let wumindCard = app.buttons["workspace.home.wumind"]
        XCTAssertTrue(wumindCard.waitForExistence(timeout: 10), "首页缺少 WuMind 卡片")
        wumindCard.tap()

        let workbenchTab = app.buttons["wumind.tab.workbench"]
        XCTAssertTrue(workbenchTab.waitForExistence(timeout: 8), "WUMIND 缺少工作台标签")
        workbenchTab.tap()

        let tenderBtn = app.buttons["deepSeek.chat.tender"]
        XCTAssertTrue(tenderBtn.waitForExistence(timeout: 10), "WUMIND 工作台缺少生成投标书草稿入口")
        tenderBtn.tap()

        let picker = app.buttons["wumind.chat.buildPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "标书应该在对话内打开")
        XCTAssertEqual(picker.label, "起草标书")
        XCTAssertTrue(app.buttons["wumind.attach.open"].isHittable, "对话内标书仍需支持上传附件")
        XCTAssertFalse(app.buttons["deepSeek.tender.import"].exists, "不应跳到独立标书页")
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "WuMind 内不应显示值班导航栏")
        let shotTender = XCTAttachment(screenshot: app.screenshot())
        shotTender.name = "duty-tender-draft"
        shotTender.lifetime = .keepAlways
        add(shotTender)
    }

    func testPassPlanSequentialSendAndManualEdit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "passPlan"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let cameraBtn = app.buttons["passplan.capture.camera"]
        XCTAssertTrue(cameraBtn.waitForExistence(timeout: 15), "值班计划页缺少原相机拍照主入口")
        XCTAssertTrue(app.buttons["passplan.sequential.send"].waitForExistence(timeout: 10), "值班计划页缺少按顺序发送按钮")
        XCTAssertFalse(app.staticTexts["目标微信群"].exists, "不应展示目标微信群必填项")
        XCTAssertFalse(app.buttons["记一下发哪个群"].exists, "不应展示记一下发哪个群按钮")

        let populatedShot = XCTAttachment(screenshot: app.screenshot())
        populatedShot.name = "duty-passplan-populated"
        populatedShot.lifetime = .keepAlways
        add(populatedShot)

        // On compact-height screens (iPhone), gently drag the outer PassPlan scroll container up
        // so the first editable row card sits cleanly centered (zero-momentum drag avoids XCUITest snapshot stalls).
        if app.frame.height < 1000 {
            let scroll = app.scrollViews["passplan.scroll"].exists
                ? app.scrollViews["passplan.scroll"]
                : app.scrollViews.firstMatch
            if scroll.waitForExistence(timeout: 5) {
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                start.press(forDuration: 0.05, thenDragTo: end)
                usleep(350_000)
            }
        }

        let editRow = app.buttons.matching(identifier: "passplan.row.edit").firstMatch
        XCTAssertTrue(editRow.waitForExistence(timeout: 10), "值班计划页缺少可点击修改的行卡片")
        if editRow.isHittable {
            editRow.tap()
        } else {
            editRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.navigationBars["手动修改计划"].waitForExistence(timeout: 10), "点击计划行应打开手动修改界面")
        let editorShot = XCTAttachment(screenshot: app.screenshot())
        editorShot.name = "duty-passplan-editor"
        editorShot.lifetime = .keepAlways
        add(editorShot)
    }

    func testHideDutyToFullScreenWuMindAndRestore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        // 0. Verify upgraded DayRosterView card UI
        let rosterBtn = app.buttons["值班表"]
        if rosterBtn.waitForExistence(timeout: 8), rosterBtn.isHittable {
            rosterBtn.tap()
            usleep(400_000)
            let rosterShot = XCTAttachment(screenshot: app.screenshot())
            rosterShot.name = "duty-roster-upgraded"
            rosterShot.lifetime = .keepAlways
            add(rosterShot)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // 1. Verify upgraded Settings secondary menu UI
        let settingsTab = app.buttons["app.tab.设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 12), "未找到底部设置标签")
        settingsTab.tap()
        usleep(400_000)
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "duty-settings-upgraded"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)

        // 2. Return to Today tab -> Return to Workspace Launcher Home -> Enter full-screen WuMind
        app.buttons["app.tab.今天"].tap()
        let dutyBackBtn = app.buttons["workspace.backToHome"]
        XCTAssertTrue(dutyBackBtn.waitForExistence(timeout: 10), "今天页左上角缺少返回首页按钮")
        dutyBackBtn.tap()
        let wumindCard = app.buttons["workspace.home.wumind"]
        XCTAssertTrue(wumindCard.waitForExistence(timeout: 10), "返回首页后未看到 WuMind 入口卡片")
        wumindCard.tap()

        // Confirm ALL Duty tabs disappeared and WUMIND is full-screen with top-left 首页 button
        let sidebarBtn = app.buttons["wumind.sidebar.open"]
        XCTAssertTrue(sidebarBtn.waitForExistence(timeout: 10), "点击 WuMind 卡片后未进入全屏 WUMIND 界面")
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "全屏 WuMind 模式下不应显示可交互的值班底部标签栏")
        XCTAssertTrue(app.buttons["wumind.backToHome"].exists, "全屏 WuMind 左上角应展示「首页」返回按钮")

        let standaloneShot = XCTAttachment(screenshot: app.screenshot())
        standaloneShot.name = "wumind-standalone-fullscreen"
        standaloneShot.lifetime = .keepAlways
        add(standaloneShot)

        // 3. Return from WuMind via top-left 首页 -> re-enter On Duty cleanly
        app.buttons["wumind.backToHome"].tap()
        let onDutyCard = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(onDutyCard.waitForExistence(timeout: 8), "从 WuMind 返回首页后缺少 On Duty 卡片")
        onDutyCard.tap()

        XCTAssertTrue(app.buttons["app.tab.今天"].waitForExistence(timeout: 10), "重新进入 On Duty 后底部标签栏未正常显示")
    }

    func testWuMindDutyIntranetQueryAndUnifiedAgentOS() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        // 1. Live end-to-end regression for Duty intranet query inside WUMIND chat (no API key or Chinese IME needed!)
        let dutyStarter = app.buttons["wumind.starter.dutyToday"]
        XCTAssertTrue(dutyStarter.waitForExistence(timeout: 15), "内部用户 WUMIND 首页缺少今日值班快捷提问卡")
        dutyStarter.tap()
        let sendBtn = app.buttons["deepseek.chat.send"]
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 8), "未找到发送按钮")
        sendBtn.tap()

        // Verify deterministic local answer renders with actual query source & zero external leak badge
        let resultCheck = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '实际查询与核对记录' OR label CONTAINS '值班业务查询结果' OR label CONTAINS '本机内网直查'")).firstMatch
        XCTAssertTrue(resultCheck.waitForExistence(timeout: 10), "WUMIND 应通过本机内网直查直接给出值班排班与来源核对结果")
        let dutyQAShot = XCTAttachment(screenshot: app.screenshot())
        dutyQAShot.name = "WuMind-duty-intranet-qa"
        dutyQAShot.lifetime = .keepAlways
        add(dutyQAShot)

        // 2. Navigate to Unified Project & Agent OS Workspace via Workbench and run chained monitor -> partial revision
        let backHome = app.buttons["wumind.chat.backHome"]
        if backHome.waitForExistence(timeout: 4), backHome.isHittable { backHome.tap() }
        let workbenchTab = app.buttons["wumind.tab.workbench"]
        if workbenchTab.waitForExistence(timeout: 6), workbenchTab.isHittable {
            workbenchTab.tap()
            usleep(250_000)
        }
        let hubBtn = app.buttons["ai.providers.open"]
        if hubBtn.waitForExistence(timeout: 8), hubBtn.isHittable {
            hubBtn.tap()
            let agentOSBtn = app.buttons["ai.tools.agentOS"]
            if agentOSBtn.waitForExistence(timeout: 8), agentOSBtn.isHittable {
                agentOSBtn.tap()
                XCTAssertTrue(app.otherElements["wumind.agentOS.header"].waitForExistence(timeout: 8)
                              || app.staticTexts["WUMIND 项目与共享任务底座"].waitForExistence(timeout: 8),
                              "统一项目与智能体总控台未打开")
                let chainedBtn = app.buttons["agentOS.chainedMonitor.run"]
                if chainedBtn.waitForExistence(timeout: 6), chainedBtn.isHittable {
                    chainedBtn.tap()
                    usleep(500_000)
                }
                let osShot = XCTAttachment(screenshot: app.screenshot())
                osShot.name = "WuMind-agent-os"
                osShot.lifetime = .keepAlways
                add(osShot)

                // 3. Verify resumable Loops & Graphs DAG inside existing Tasks & Approvals tab (no new menu!)
                let tasksTab = app.buttons["任务与审批"]
                if tasksTab.waitForExistence(timeout: 6), tasksTab.isHittable {
                    tasksTab.tap()
                    let disconnectBtn = app.buttons["agentOS.graph.disconnectLeave"]
                    if disconnectBtn.waitForExistence(timeout: 6), disconnectBtn.isHittable {
                        disconnectBtn.tap()
                        usleep(400_000)
                    }
                    let resumeBtn = app.buttons["agentOS.graph.resumeLeave"]
                    if resumeBtn.waitForExistence(timeout: 6), resumeBtn.isHittable {
                        resumeBtn.tap()
                        usleep(400_000)
                    }
                    let graphShot = XCTAttachment(screenshot: app.screenshot())
                    graphShot.name = "WuMind-loops-graphs-resume"
                    graphShot.lifetime = .keepAlways
                    add(graphShot)
                }
            }
        }
    }

    func testWuMindAdminBillingNonOcclusion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumindAdminBilling"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let navBar = app.navigationBars["商业计费管理"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 12), "商业计费管理导航栏未显示")

        let upstreamCard = app.descendants(matching: .any).matching(identifier: "wumind.admin.card.upstreamBalance").firstMatch
        let todayCard = app.descendants(matching: .any).matching(identifier: "wumind.admin.card.todayUsage").firstMatch
        let rechargeCard = app.descendants(matching: .any).matching(identifier: "wumind.admin.card.rechargeStatus").firstMatch
        let anomalyCard = app.descendants(matching: .any).matching(identifier: "wumind.admin.card.anomalies").firstMatch
        XCTAssertTrue(upstreamCard.waitForExistence(timeout: 10), "商业计费管理首屏缺少「上游余额」状态卡片")
        XCTAssertTrue(todayCard.waitForExistence(timeout: 6), "商业计费管理首屏缺少「今日用量」状态卡片")
        XCTAssertTrue(rechargeCard.waitForExistence(timeout: 6), "商业计费管理首屏缺少「充值与入账状态」状态卡片")
        XCTAssertTrue(anomalyCard.waitForExistence(timeout: 6), "商业计费管理首屏缺少「异常提醒」状态卡片")

        XCTAssertGreaterThanOrEqual(
            upstreamCard.frame.minY,
            navBar.frame.maxY - 2,
            "首屏顶部「上游余额」卡片不得被导航栏遮挡（navBar.maxY=\(navBar.frame.maxY), card.minY=\(upstreamCard.frame.minY)）"
        )

        let userDir = app.descendants(matching: .any).matching(identifier: "wumind.admin.userDirectory").firstMatch
        let pricingEntry = app.descendants(matching: .any).matching(identifier: "wumind.admin.modelCatalog").firstMatch
        let paymentsEntry = app.descendants(matching: .any).matching(identifier: "wumind.admin.payments").firstMatch
        let gatewayEntry = app.descendants(matching: .any).matching(identifier: "wumind.admin.gateway").firstMatch
        XCTAssertTrue(userDir.waitForExistence(timeout: 6), "商业计费管理缺少「用户与账单」入口")
        XCTAssertTrue(pricingEntry.waitForExistence(timeout: 6), "商业计费管理缺少「模型定价」入口")
        XCTAssertTrue(paymentsEntry.waitForExistence(timeout: 6), "商业计费管理缺少「充值与支付」入口")
        XCTAssertTrue(gatewayEntry.waitForExistence(timeout: 6), "商业计费管理缺少「网关与诊断」入口")

        let adminTopShot = XCTAttachment(screenshot: app.screenshot())
        adminTopShot.name = "WuMind-admin-billing-top"
        adminTopShot.lifetime = .keepAlways
        add(adminTopShot)

        // Open Gateway & Diagnostics sub-page and verify AIHubMix balance / alert threshold / gateway config
        gatewayEntry.tap()
        let gatewayNav = app.navigationBars["网关与诊断"]
        XCTAssertTrue(gatewayNav.waitForExistence(timeout: 8), "网关与诊断子页面未打开")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "wumind.admin.aihubmixBalanceValue").firstMatch.waitForExistence(timeout: 8),
            "网关与诊断页缺少上游余额查询卡片"
        )
        XCTAssertTrue(app.buttons["wumind.admin.aihubmixRefresh"].exists, "缺少上游余额刷新按钮")
        XCTAssertTrue(app.buttons["wumind.admin.aihubmixTopUp"].exists, "缺少上游去充值按钮")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "wumind.admin.alertThresholdField").firstMatch.exists,
            "缺少低余额报警阈值输入框"
        )

        let adminDiagShot = XCTAttachment(screenshot: app.screenshot())
        adminDiagShot.name = "WuMind-admin-gateway-diagnostics"
        adminDiagShot.lifetime = .keepAlways
        add(adminDiagShot)
    }

    func testDutyLargeTextCalendarFromLauncher() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }
        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 15))
        duty.tap()
        let calendar = app.buttons["app.tab.日历"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        calendar.tap()
        let date = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar.day.'")).firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 10))
        for _ in 0..<3 where !date.isHittable { app.swipeUp() }
        XCTAssertTrue(date.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Duty-calendar-accessibility-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        date.tap()
        let close = app.buttons["关闭"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(calendar.waitForExistence(timeout: 8) && calendar.isHittable)
    }

    /// Regression test (iPhone + iPad): Ground Station List -> Add -> Save while keyboard open ->
    /// Back to list -> Tap to Re-Edit -> Save again, verifying top-right "保存" button visibility,
    /// required-field validation, and zero bottom-tab-bar occlusion.
    func testGroundStationAddSaveWithKeyboardOpenAndReEdit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 15))
        duty.tap()
        let plan = app.buttons["today.toolbar.plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        plan.tap()
        let openOperators = app.buttons["passplan.operators.open"]
        for _ in 0..<4 where !openOperators.isHittable { app.swipeUp() }
        XCTAssertTrue(openOperators.waitForExistence(timeout: 15), "发数传计划页缺少「运营商对照表」入口")
        openOperators.tap()

        XCTAssertTrue(app.navigationBars["地面站与运营商"].waitForExistence(timeout: 10), "地面站与运营商列表页未打开")
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "二级地面站列表页不得被底部导航栏遮挡")

        let addBtn = app.buttons["groundStation.list.add"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 8), "地面站列表右上角缺少添加按钮")
        addBtn.tap()

        XCTAssertTrue(app.navigationBars["添加地面站"].waitForExistence(timeout: 10), "添加地面站表单页未打开")
        let saveBtn = app.buttons["groundStation.editor.save"]
        XCTAssertTrue(saveBtn.waitForExistence(timeout: 8), "添加地面站表单右上角缺少「保存」按钮")
        XCTAssertTrue(saveBtn.isHittable, "添加地面站「保存」按钮必须可点击")

        // 1. Validate required field error keeps user on form
        saveBtn.tap()
        let requiredErr = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '必填项'")).firstMatch
        XCTAssertTrue(requiredErr.waitForExistence(timeout: 6), "必填项为空点保存时必须给出缺项提示并留在当前页")

        // 2. Fill name & prefix while keeping software keyboard open, then tap Save directly!
        let nameField = app.textFields["groundStation.field.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 6), "缺少地面站名称输入框")
        nameField.tap()
        let stationName = "UITest-" + String(UUID().uuidString.prefix(6))
        nameField.typeText(stationName)

        let prefixesField = app.textFields["groundStation.field.prefixes"]
        XCTAssertTrue(prefixesField.waitForExistence(timeout: 6), "缺少地面站前缀输入框")
        prefixesField.tap()
        prefixesField.typeText("KS01")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        // Top-right Save MUST remain visible and hittable while keyboard is open
        XCTAssertTrue(saveBtn.exists && saveBtn.isHittable, "键盘打开时右上角「保存」按钮必须始终可见可点")
        let addWithKBShot = XCTAttachment(screenshot: app.screenshot())
        addWithKBShot.name = "GroundStation-add-keyboard-save"
        addWithKBShot.lifetime = .keepAlways
        add(addWithKBShot)

        saveBtn.tap()

        // 3. Returned to list and newly saved station is visible
        XCTAssertTrue(app.navigationBars["地面站与运营商"].waitForExistence(timeout: 10), "保存后未返回地面站列表")
        let savedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", stationName)).firstMatch
        for _ in 0..<8 where !savedRow.isHittable { app.swipeUp() }
        XCTAssertTrue(savedRow.waitForExistence(timeout: 8), "新增地面站未出现在列表中")
        let listAfterAddShot = XCTAttachment(screenshot: app.screenshot())
        listAfterAddShot.name = "GroundStation-list-after-add"
        listAfterAddShot.lifetime = .keepAlways
        add(listAfterAddShot)

        // 4. Tap saved station to re-edit and verify identical top-right "保存" button works cleanly
        savedRow.tap()
        XCTAssertTrue(app.navigationBars["编辑地面站"].waitForExistence(timeout: 10), "点击列表项未进入编辑地面站页面")
        XCTAssertTrue(saveBtn.waitForExistence(timeout: 8) && saveBtn.isHittable, "编辑地面站右上角「保存」按钮位置应与添加页一致且可点")

        let editNameField = app.textFields["groundStation.field.name"]
        XCTAssertTrue(editNameField.waitForExistence(timeout: 6))
        XCTAssertEqual(editNameField.value as? String, stationName, "编辑地面站页应完整回显原有名称")
        editNameField.tap()
        editNameField.typeText("Edited")
        usleep(250_000)

        saveBtn.tap()

        XCTAssertTrue(app.navigationBars["地面站与运营商"].waitForExistence(timeout: 10), "二次编辑保存后未返回列表")
        let updatedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", stationName + "Edited")).firstMatch
        for _ in 0..<8 where !updatedRow.isHittable { app.swipeUp() }
        XCTAssertTrue(updatedRow.waitForExistence(timeout: 8), "二次编辑保存后的名称未刷新到列表")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'KS01'")).firstMatch.exists, "二次编辑保存后应保留原有前缀 KS01")
        let listAfterEditShot = XCTAttachment(screenshot: app.screenshot())
        listAfterEditShot.name = "GroundStation-list-after-edit"
        listAfterEditShot.lifetime = .keepAlways
        add(listAfterEditShot)
    }

    /// Regression test (iPhone + iPad): Pushing ANY Level-2/Level-3 screen from a primary tab
    /// automatically hides the bottom FloatingTabBar (zero occlusion), and popping restores it cleanly.
    func testDeepSubpageHidesBottomTabBarAndRestoresOnPop() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        ensurePortrait()
        app.launch()
        defer { app.terminate() }

        let settingsTab = app.buttons["app.tab.设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 15), "一级首页缺少底部「设置」标签")
        XCTAssertTrue(settingsTab.isHittable)
        settingsTab.tap()

        // L1 Settings still shows bottom tab bar
        XCTAssertTrue(app.buttons["app.tab.今天"].waitForExistence(timeout: 8) && app.buttons["app.tab.今天"].isHittable,
                      "一级「设置」页应正常显示底部导航栏")

        // Push L2: 商业计费管理
        let adminBillingRow = app.buttons["settings.wumindAdmin"]
        for _ in 0..<2 where !adminBillingRow.isHittable {
            app.swipeUp()
            usleep(200_000)
        }
        XCTAssertTrue(adminBillingRow.waitForExistence(timeout: 8), "设置页缺少「商业计费管理」入口")
        adminBillingRow.tap()

        XCTAssertTrue(app.navigationBars["商业计费管理"].waitForExistence(timeout: 10), "商业计费管理二级页未打开")
        usleep(350_000)
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "进入二级页「商业计费管理」后底部导航栏必须自动隐藏")
        XCTAssertFalse(app.buttons["app.tab.设置"].isHittable, "进入二级页后不得有可点击的底部导航栏遮挡内容")

        let subpageShot = XCTAttachment(screenshot: app.screenshot())
        subpageShot.name = "Subpage-tabbar-hidden"
        subpageShot.lifetime = .keepAlways
        add(subpageShot)

        // Pop back to L1 Settings -> bottom tab bar must restore cleanly
        app.navigationBars["商业计费管理"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["app.tab.今天"].waitForExistence(timeout: 10), "从二级页返回一级页后底部导航栏未恢复")
        XCTAssertTrue(app.buttons["app.tab.今天"].isHittable, "恢复后的底部导航栏必须正常可点")
    }

    /// Regression test (iPhone + iPad): Verifies decomposed WUMIND composer bar handles cold start,
    /// text focus/typing, attachment sheet open/close, and real-time voice launch/close without crashing.
    func testWuMindColdStartComposerAttachmentsAndVoiceStability() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind"]
        ensurePortrait()
        let launchStarted = Date()
        app.launch()
        defer { app.terminate() }

        let composer = app.descendants(matching: .any).matching(identifier: "deepSeek.chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15), "拆分后的 WUMIND 输入栏未显示")
        let coldStartToWuMindMs = max(1, Int(Date().timeIntervalSince(launchStarted) * 1000))

        composer.tap()
        let typingStarted = Date()
        composer.typeText("Hello WUMIND perf test 12345")
        let typingMs = max(1, Int(Date().timeIntervalSince(typingStarted) * 1000))
        usleep(250_000)

        let perfReport = XCTAttachment(string: "coldStartToWuMindMs=\(coldStartToWuMindMs)\nisolatedComposerTypingMs=\(typingMs)\n")
        perfReport.name = "WuMind-simulator-perf-metrics.txt"
        perfReport.lifetime = .keepAlways
        add(perfReport)

        let dismissKB = app.buttons["wumind.composer.dismissKeyboard"]
        if dismissKB.waitForExistence(timeout: 4) && dismissKB.isHittable {
            dismissKB.tap()
            usleep(250_000)
        }

        let attachBtn = app.descendants(matching: .any).matching(identifier: "wumind.attach.open").firstMatch
        XCTAssertTrue(attachBtn.waitForExistence(timeout: 6), "拆分后的输入栏缺少上传/工具入口")
        attachBtn.tap()
        let connectorsNav = app.navigationBars["聊天内连接与插件"]
        if connectorsNav.waitForExistence(timeout: 6) {
            connectorsNav.buttons["完成"].tap()
            usleep(250_000)
        }

        let liveVoice = app.buttons["wumind.composer.dictate"]
        XCTAssertTrue(liveVoice.waitForExistence(timeout: 6))
        liveVoice.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.live.phaseTitle").firstMatch.waitForExistence(timeout: 8))
        let closeLive = app.buttons["ai.live.close"]
        XCTAssertTrue(closeLive.waitForExistence(timeout: 5))
        closeLive.tap()
        usleep(250_000)

        XCTAssertTrue(composer.waitForExistence(timeout: 6), "关闭语音返回后 WUMIND 输入栏应保持稳定可见")
        let stableShot = XCTAttachment(screenshot: app.screenshot())
        stableShot.name = "WuMind-composer-decomposed-stable"
        stableShot.lifetime = .keepAlways
        add(stableShot)
    }
}

