import XCTest

/// Exercises the WUMIND multi-model workspace, bottom Games tab, streamlined Duty Workbench,
/// PassPlan review, AI Toolbox (including Realtime voice), and Tender Draft navigation without real API keys.
final class DeepSeekChatNavigationTests: XCTestCase {
    func testOpenChatFromHomeAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        // Verify Games tab sits directly in bottom tab bar and home entry is renamed WUMIND
        let gamesTab = app.buttons["app.tab.游戏"]
        XCTAssertTrue(gamesTab.waitForExistence(timeout: 15), "底部导航栏缺少游戏标签")
        XCTAssertLessThanOrEqual(
            app.frame.maxY - gamesTab.frame.maxY,
            46,
            "底部导航栏应紧贴屏幕最底部安全区，不应悬浮抬高"
        )
        let entry = app.buttons["today.deepSeekChat"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "首页左上角缺少 WUMIND 入口")
        XCTAssertTrue(entry.isHittable)
        let homeShot = XCTAttachment(screenshot: app.screenshot())
        homeShot.name = "Today-streamlined"
        homeShot.lifetime = .keepAlways
        add(homeShot)

        entry.tap()

        // Verify WUMIND opens full-screen with ZERO bottom tab bar visible or hittable!
        let composer = app.descendants(matching: .any)
            .matching(identifier: "deepSeek.chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "WUMIND 输入框未显示")
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "打开 WUMIND 时不应显示底部导航栏")
        XCTAssertFalse(app.buttons["app.tab.游戏"].isHittable, "打开 WUMIND 时底部游戏栏不应可见")
        XCTAssertTrue(app.buttons["wumind.model.picker"].exists, "缺少顶部模型切换胶囊")
        XCTAssertTrue(app.buttons["wumind.sidebar.open"].exists, "缺少历史对话侧边栏按钮")
        XCTAssertTrue(app.buttons["wumind.tempChat.toggle"].exists, "缺少临时聊天模式切换按钮")
        XCTAssertTrue(app.buttons["deepSeek.chat.thinking"].exists, "缺少深度思考切换胶囊")
        XCTAssertTrue(app.buttons["wumind.quick.image"].exists, "首页缺少文字生图快捷入口")
        XCTAssertTrue(app.buttons["wumind.quick.video"].exists, "首页缺少 AI 生视频快捷入口")
        XCTAssertTrue(app.buttons["wumind.quick.ppt"].exists, "首页缺少 AI 写 PPT 快捷入口")
        XCTAssertTrue(app.buttons["deepSeek.chat.tender"].exists, "首页缺少写投标书快捷入口")
        XCTAssertTrue(app.buttons["wumind.quick.plugins"].exists, "首页缺少插件与连接快捷入口")
        XCTAssertTrue(app.buttons["wumind.quick.research"].exists, "首页缺少深度调研快捷入口")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.attach.open").firstMatch.exists,
                      "对话框下方缺少聊天内连接与上传按钮")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.composer.model").firstMatch.exists,
                      "对话框下方缺少模型切换按钮")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.context.menu").firstMatch.exists,
                      "对话框下方缺少 1M 上下文与自动压缩控制按钮")
        XCTAssertTrue(app.buttons["wumind.agent.toggle"].exists, "对话框下方缺少智能体模式开关")
        XCTAssertTrue(app.buttons["wumind.composer.dictate"].exists, "对话框下方缺少独立语音对话入口按钮")

        let skillsBtn = app.buttons["wumind.skills.open"]
        XCTAssertTrue(skillsBtn.exists && skillsBtn.isHittable, "定制按钮应直接在屏幕内可见，无需左右滑动")
        let githubBtn = app.buttons["wumind.github.open"]
        XCTAssertTrue(githubBtn.exists && githubBtn.isHittable, "GitHub 按钮应直接在屏幕内可见，无需左右滑动")
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

        // Open Dedicated Full-Screen Gemini Live Voice Overlay from bottom-right voice orb!
        let voiceBtn = app.buttons["wumind.composer.dictate"]
        XCTAssertTrue(voiceBtn.waitForExistence(timeout: 6) && voiceBtn.isHittable)
        voiceBtn.tap()
        let voiceOrb = app.buttons["wumind.voice.orb"]
        XCTAssertTrue(voiceOrb.waitForExistence(timeout: 8), "独立全屏 Gemini 语音对话页面未打开")
        let voiceShot = XCTAttachment(screenshot: app.screenshot())
        voiceShot.name = "WuMind-gemini-voice"
        voiceShot.lifetime = .keepAlways
        add(voiceShot)
        let voiceClose = app.buttons["wumind.voice.close"]
        XCTAssertTrue(voiceClose.waitForExistence(timeout: 5))
        voiceClose.tap()
        usleep(300_000)

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

        // Switch to WUMIND Managed channel, verify Wallet + StoreKit 2 IAP grid + TestFlight compliance
        let managedBtn = app.buttons["wumind.channel.managed"]
        if managedBtn.waitForExistence(timeout: 5) && managedBtn.isHittable {
            managedBtn.tap()
            let walletBtn = app.buttons["wumind.wallet.open"]
            XCTAssertTrue(walletBtn.waitForExistence(timeout: 8), "切换到内置付费通道后缺少充值/价目表入口")
            walletBtn.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.wallet.balance").firstMatch.waitForExistence(timeout: 8),
                          "WUMIND 钱包缺少余额显示")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.wallet.usageGrid").firstMatch.exists,
                          "WUMIND 钱包缺少用量统计面板")
            let complianceBanner = app.descendants(matching: .any).matching(identifier: "wumind.wallet.testFlightComplianceBanner").firstMatch
            XCTAssertTrue(complianceBanner.waitForExistence(timeout: 6), "TestFlight / 沙盒钱包必须展示合规不收费保护提示")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.wallet.iapGrid").firstMatch.waitForExistence(timeout: 6),
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
            let ownBtn = app.buttons["wumind.channel.ownAPI"]
            if ownBtn.exists && ownBtn.isHittable {
                ownBtn.tap()
                usleep(200_000)
            }
        }

        // Open & close sidebar drawer
        app.buttons["wumind.sidebar.open"].tap()
        usleep(350_000)
        let drawerShot = XCTAttachment(screenshot: app.screenshot())
        drawerShot.name = "WuMind-drawer"
        drawerShot.lifetime = .keepAlways
        add(drawerShot)

        // Close WUMIND and return to Today
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        usleep(300_000)
        let closeBtn = app.buttons["wumind.close"]
        XCTAssertTrue(closeBtn.waitForExistence(timeout: 8))
        closeBtn.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
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
        app.launchArguments = ["-demo", "-screen", "today"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        let home = app.buttons["today.deepSeekChat"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        home.tap()

        // 1. Open Flagship Full-Height Model & Capability Center from bottom composer pill (zero truncation!)
        let composerModel = app.buttons["wumind.composer.model"]
        XCTAssertTrue(composerModel.waitForExistence(timeout: 8) && composerModel.isHittable)
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

        // 2. Open Flagship AI Capability Workshop (AI 工具箱) — zero redundant third-party AI chat rows!
        let switcher = app.buttons["ai.providers.open"]
        _ = switcher.waitForExistence(timeout: 6)
        for _ in 0..<4 where !switcher.isHittable {
            app.swipeUp()
            usleep(250_000)
        }
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(switcher.frame.maxX, app.frame.maxX + 1, "全部工坊按钮不应超出屏幕右边界")
        switcher.tap()

        for id in ["spatial3d", "image", "video", "ppt", "live", "speech", "code", "work"] {
            let btn = app.buttons["ai.tools." + id]
            if !btn.exists {
                app.swipeUp()
                usleep(200_000)
            }
            XCTAssertTrue(btn.waitForExistence(timeout: 6), "Missing tool " + id)
        }
        XCTAssertFalse(app.buttons["ai.provider.gemini"].exists, "AI 工具箱不应再出现多余的第三方对话入口（首页即可切换模型）")
        app.swipeDown()
        usleep(250_000)
        app.swipeDown()
        usleep(250_000)
        let toolboxShot = XCTAttachment(screenshot: app.screenshot())
        toolboxShot.name = "WuMind-toolbox"
        toolboxShot.lifetime = .keepAlways
        add(toolboxShot)

        // 2b. Flagship AI 3D Spatial Studio (Palace Complex: 3 DeepSeek GIF Angles + Snowy Weather)
        let spatialTool = app.buttons["ai.tools.spatial3d"]
        XCTAssertTrue(spatialTool.waitForExistence(timeout: 6) && spatialTool.isHittable)
        spatialTool.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.spatial3d.viewport").firstMatch.waitForExistence(timeout: 8),
                      "AI 3D 空间工坊 3D 视图未显示")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.spatial3d.perfHud").firstMatch.exists,
                      "AI 3D 空间工坊缺少实时 FPS/性能 HUD")
        usleep(600_000)
        let palaceAerial = XCTAttachment(screenshot: app.screenshot())
        palaceAerial.name = "WuMind-3d-palace-aerial"
        palaceAerial.lifetime = .keepAlways
        add(palaceAerial)

        let roadCam = app.buttons["ai.spatial3d.camera.road_walkthrough"]
        if roadCam.waitForExistence(timeout: 4) && roadCam.isHittable {
            roadCam.tap()
            usleep(950_000)
            let palaceRoad = XCTAttachment(screenshot: app.screenshot())
            palaceRoad.name = "WuMind-3d-palace-road"
            palaceRoad.lifetime = .keepAlways
            add(palaceRoad)
        }

        let gateCam = app.buttons["ai.spatial3d.camera.gate_closeup"]
        if gateCam.waitForExistence(timeout: 4) && gateCam.isHittable {
            gateCam.tap()
            usleep(950_000)
            let palaceGate = XCTAttachment(screenshot: app.screenshot())
            palaceGate.name = "WuMind-3d-palace-gate"
            palaceGate.lifetime = .keepAlways
            add(palaceGate)
        }

        let snowBtn = app.buttons["ai.spatial3d.weather.snowy"]
        if snowBtn.waitForExistence(timeout: 4) && snowBtn.isHittable {
            snowBtn.tap()
            if let aerialBtn = app.buttons["ai.spatial3d.camera.aerial_overview"].exists ? app.buttons["ai.spatial3d.camera.aerial_overview"] : nil,
               aerialBtn.isHittable {
                aerialBtn.tap()
            }
            usleep(950_000)
            let palaceSnow = XCTAttachment(screenshot: app.screenshot())
            palaceSnow.name = "WuMind-3d-palace-snow"
            palaceSnow.lifetime = .keepAlways
            add(palaceSnow)
        }

        app.navigationBars["AI 3D 空间工坊"].buttons.element(boundBy: 0).tap()
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
        let videoShot = XCTAttachment(screenshot: app.screenshot())
        videoShot.name = "WuMind-video-studio"
        videoShot.lifetime = .keepAlways
        add(videoShot)
        app.navigationBars["AI 生视频工坊"].buttons.element(boundBy: 0).tap()
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
        let webToggle = app.buttons["ai.ppt.webSearch"]
        XCTAssertTrue(webToggle.exists && webToggle.frame.maxX <= app.frame.maxX + 1, "PPT 工坊联网开关不应超出屏幕右边界")
        let pptShot = XCTAttachment(screenshot: app.screenshot())
        pptShot.name = "WuMind-ppt-studio"
        pptShot.lifetime = .keepAlways
        add(pptShot)
        app.navigationBars["AI 写 PPT 工坊"].buttons.element(boundBy: 0).tap()
        usleep(300_000)

        // 5. Flagship WUMIND Image Studio (Grok / GPT studio layout + keyboard non-occlusion)
        let imageTool = app.buttons["ai.tools.image"]
        XCTAssertTrue(imageTool.waitForExistence(timeout: 8) && imageTool.isHittable)
        imageTool.tap()

        let promptField = app.descendants(matching: .any).matching(identifier: "ai.image.prompt").firstMatch
        XCTAssertTrue(promptField.waitForExistence(timeout: 10), "WUMIND 画室输入框未显示")
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "文字生图画室不应显示底部导航栏")

        let speedPill = app.descendants(matching: .any).matching(identifier: "ai.image.speed").firstMatch
        let aspectPill = app.descendants(matching: .any).matching(identifier: "ai.image.aspect").firstMatch
        let countPill = app.descendants(matching: .any).matching(identifier: "ai.image.count").firstMatch
        let settingsPill = app.descendants(matching: .any).matching(identifier: "ai.image.settings").firstMatch
        XCTAssertTrue(speedPill.waitForExistence(timeout: 6), "画室缺少极速/超清切换胶囊")
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

        let imageBack = app.navigationBars["WUMIND 画室"].buttons.element(boundBy: 0)
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
        XCUIDevice.shared.orientation = .portrait
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

        let wumind = app.buttons["today.deepSeekChat"]
        XCTAssertTrue(wumind.waitForExistence(timeout: 10))
        wumind.tap()

        let tenderBtn = app.buttons["deepSeek.chat.tender"]
        XCTAssertTrue(tenderBtn.waitForExistence(timeout: 10), "WUMIND 页面缺少生成投标书草稿入口")
        tenderBtn.tap()

        let importBtn = app.buttons["deepSeek.tender.import"]
        XCTAssertTrue(importBtn.waitForExistence(timeout: 10), "投标书草稿页未正常打开")
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "投标书草稿页不应显示底部导航栏")
        let shotTender = XCTAttachment(screenshot: app.screenshot())
        shotTender.name = "duty-tender-draft"
        shotTender.lifetime = .keepAlways
        add(shotTender)
    }

    func testPassPlanSequentialSendAndManualEdit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "passPlan"]
        XCUIDevice.shared.orientation = .portrait
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

        // Tap the visible editable row card via exact identifier (avoids slow predicate tree scan)
        let editRow = app.buttons.matching(identifier: "passplan.row.edit").firstMatch
        if !editRow.waitForExistence(timeout: 5) || !editRow.isHittable || editRow.frame.maxY > app.frame.height - 80 {
            app.swipeUp()
        }
        XCTAssertTrue(editRow.waitForExistence(timeout: 8), "值班计划页缺少可点击修改的行卡片")
        editRow.tap()
        XCTAssertTrue(app.navigationBars["手动修改计划"].waitForExistence(timeout: 8), "点击计划行应打开手动修改界面")
        let editorShot = XCTAttachment(screenshot: app.screenshot())
        editorShot.name = "duty-passplan-editor"
        editorShot.lifetime = .keepAlways
        add(editorShot)
    }

    func testHideDutyToFullScreenWuMindAndRestore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        XCUIDevice.shared.orientation = .portrait
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

        // 1. Verify upgraded Settings secondary menu UI + hide-duty toggle
        let settingsTab = app.buttons["app.tab.设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 12), "未找到底部设置标签")
        settingsTab.tap()
        usleep(400_000)
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "duty-settings-upgraded"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)

        // 2. Return to Today tab & tap 1-tap Hide Duty UI button -> pure full-screen WUMIND
        app.buttons["app.tab.今天"].tap()
        let hideDutyBtn = app.buttons["today.hideDutyMode"]
        XCTAssertTrue(hideDutyBtn.waitForExistence(timeout: 10), "今天页顶部缺少一键隐藏值班界面按钮")
        hideDutyBtn.tap()

        // Confirm ALL Duty tabs disappeared and WUMIND is full-screen without close button
        let sidebarBtn = app.buttons["wumind.sidebar.open"]
        XCTAssertTrue(sidebarBtn.waitForExistence(timeout: 10), "隐藏值班后未进入全屏 WUMIND 界面")
        XCTAssertFalse(app.buttons["app.tab.今天"].exists, "隐藏值班模式下不应再显示值班底部标签栏")
        XCTAssertFalse(app.buttons["wumind.close"].exists, "纯享全屏 WUMIND 模式下不应显示退出回值班的关闭按钮")

        let standaloneShot = XCTAttachment(screenshot: app.screenshot())
        standaloneShot.name = "wumind-standalone-fullscreen"
        standaloneShot.lifetime = .keepAlways
        add(standaloneShot)

        // 3. Open WUMIND sidebar drawer and restore Duty UI cleanly
        sidebarBtn.tap()
        let restoreBtn = app.buttons["wumind.restoreDutyMode"]
        XCTAssertTrue(restoreBtn.waitForExistence(timeout: 8), "WUMIND 侧边栏缺少恢复值班界面按钮")
        restoreBtn.tap()

        XCTAssertTrue(app.buttons["app.tab.今天"].waitForExistence(timeout: 10), "点击恢复后未回到值班主界面")
    }

    func testWuMindDutyIntranetQueryAndUnifiedAgentOS() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        let wumind = app.buttons["today.deepSeekChat"]
        XCTAssertTrue(wumind.waitForExistence(timeout: 15))
        wumind.tap()

        // 1. Live end-to-end regression for Duty intranet query inside WUMIND chat (no API key or Chinese IME needed!)
        let dutyStarter = app.buttons["wumind.starter.dutyToday"]
        XCTAssertTrue(dutyStarter.waitForExistence(timeout: 10), "内部用户 WUMIND 首页缺少今日值班快捷提问卡")
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

        // 2. Navigate to Unified Project & Agent OS Workspace and run chained monitor -> partial revision
        let backHome = app.buttons["wumind.chat.backHome"]
        if backHome.waitForExistence(timeout: 4), backHome.isHittable { backHome.tap() }
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
}
