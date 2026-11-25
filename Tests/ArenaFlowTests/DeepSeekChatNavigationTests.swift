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
        XCTAssertTrue(app.buttons["deepSeek.chat.thinking"].exists, "缺少深度思考切换胶囊")
        XCTAssertTrue(app.buttons["wumind.home.api.deepSeek"].exists, "首页缺少 DeepSeek API 快捷配置")
        XCTAssertTrue(app.buttons["wumind.home.api.openAI"].exists, "首页缺少 OpenAI API 快捷配置")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.attach.open").firstMatch.exists,
                      "对话框下方缺少文件/图片上传按钮")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.composer.model").firstMatch.exists,
                      "对话框下方缺少模型切换按钮")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.context.menu").firstMatch.exists,
                      "对话框下方缺少 1M 上下文与自动压缩控制按钮")
        XCTAssertTrue(app.buttons["wumind.agent.toggle"].exists, "对话框下方缺少智能体模式开关")
        XCTAssertTrue(app.buttons["wumind.composer.dictate"].exists, "对话框下方缺少实时语音听写按钮")
        XCTAssertTrue(app.buttons["wumind.quick.research"].exists, "AI 能力中心缺少深度调研快捷入口")

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

        // Open Customizations Marketplace (Marketplace/Installed) and capture proof screenshot
        let customDock = app.buttons["wumind.dock.custom"]
        if customDock.waitForExistence(timeout: 5) && customDock.isHittable {
            customDock.tap()
            XCTAssertTrue(app.buttons["wumind.custom.tab.市场"].waitForExistence(timeout: 8), "定制中心缺少市场/已安装切换")
            XCTAssertTrue(app.buttons["wumind.custom.tab.已安装"].exists)
            let customShot = XCTAttachment(screenshot: app.screenshot())
            customShot.name = "WuMind-customizations"
            customShot.lifetime = .keepAlways
            add(customShot)
            app.navigationBars.buttons["完成"].tap()
            usleep(300_000)
        }

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

        // Open WUMIND Independent Settings sheet, navigate to Cross-Device Encrypted Sync sheet & capture proof screenshots
        let settingsDock = app.buttons["wumind.dock.settings"]
        if settingsDock.waitForExistence(timeout: 5) && settingsDock.isHittable {
            settingsDock.tap()
            XCTAssertTrue(app.navigationBars["WUMIND 设置"].waitForExistence(timeout: 8), "WUMIND 独立设置中心未打开")
            let setShot = XCTAttachment(screenshot: app.screenshot())
            setShot.name = "WuMind-settings"
            setShot.lifetime = .keepAlways
            add(setShot)

            let syncRow = app.buttons["wumind.settings.sync"]
            for _ in 0..<5 where !syncRow.exists || !syncRow.isHittable {
                app.swipeUp()
                usleep(200_000)
            }
            if syncRow.waitForExistence(timeout: 4) && syncRow.isHittable {
                syncRow.tap()
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.sync.passphrase").firstMatch.waitForExistence(timeout: 8),
                              "跨设备加密同步面板未打开")
                let syncShot = XCTAttachment(screenshot: app.screenshot())
                syncShot.name = "WuMind-sync"
                syncShot.lifetime = .keepAlways
                add(syncShot)
                app.navigationBars["跨设备加密同步"].buttons["完成"].tap()
                usleep(300_000)
            } else {
                app.navigationBars["WUMIND 设置"].buttons["完成"].tap()
                usleep(300_000)
            }
        }

        // Switch to WUMIND Managed channel, verify Wallet + StoreKit 2 IAP grid + auto-credit recharge + guide
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
            let guideToolbarBtn = app.buttons["wumind.wallet.guideToolbar"]
            if guideToolbarBtn.waitForExistence(timeout: 4) && guideToolbarBtn.isHittable {
                guideToolbarBtn.tap()
                XCTAssertTrue(app.navigationBars["充值与计费教程"].waitForExistence(timeout: 6), "WUMIND 充值教程页未打开")
                let guideShot = XCTAttachment(screenshot: app.screenshot())
                guideShot.name = "WuMind-wallet-guide"
                guideShot.lifetime = .keepAlways
                add(guideShot)
                app.navigationBars["充值与计费教程"].buttons["我知道了"].tap()
                usleep(300_000)
            }
            app.navigationBars["WUMIND 钱包与计费"].buttons["完成"].tap()
            usleep(300_000)
            let ownBtn = app.buttons["wumind.channel.ownAPI"]
            if ownBtn.exists && ownBtn.isHittable {
                ownBtn.tap()
                usleep(200_000)
            }
        }

        // Open GitHub sheet directly (zero horizontal swipe required!) and capture proof screenshot
        XCTAssertTrue(githubBtn.isHittable, "GitHub 按钮无需滑动即可直接点击")
        githubBtn.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wumind.github.repoInput").firstMatch.waitForExistence(timeout: 8),
                      "GitHub 连接面板未打开")
        let ghShot = XCTAttachment(screenshot: app.screenshot())
        ghShot.name = "WuMind-github"
        ghShot.lifetime = .keepAlways
        add(ghShot)
        app.navigationBars.buttons["完成"].tap()
        usleep(300_000)

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
        XCTAssertLessThanOrEqual(switcher.frame.maxX, app.frame.maxX + 1, "全部工具按钮不应超出屏幕右边界")
        switcher.tap()

        for id in ["image", "live", "speech", "code", "work"] {
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
        let toolboxShot = XCTAttachment(screenshot: app.screenshot())
        toolboxShot.name = "WuMind-toolbox"
        toolboxShot.lifetime = .keepAlways
        add(toolboxShot)

        // 3. Flagship Realtime Voice Studio
        let live = app.buttons["ai.tools.live"]
        XCTAssertTrue(live.waitForExistence(timeout: 6) && live.isHittable)
        live.tap()
        XCTAssertTrue(app.staticTexts["ai.live.status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ai.live.start"].exists)
        XCTAssertFalse(app.buttons["ai.live.end"].exists)
        XCTAssertFalse(app.buttons["app.tab.今天"].isHittable, "实时语音通话页不应显示底部导航栏")
        let liveShot = XCTAttachment(screenshot: app.screenshot())
        liveShot.name = "WuMind-live-voice"
        liveShot.lifetime = .keepAlways
        add(liveShot)
        let liveBack = app.navigationBars["实时语音通话"].buttons.element(boundBy: 0)
        XCTAssertTrue(liveBack.waitForExistence(timeout: 6), "实时语音通话导航栏返回按钮未显示")
        liveBack.tap()

        XCTAssertTrue(app.buttons["ai.tools.image"].waitForExistence(timeout: 8))
        usleep(300_000)

        // 4. Flagship WUMIND Image Studio (Grok / GPT studio layout + keyboard non-occlusion)
        let imageTool = app.buttons["ai.tools.image"]
        XCTAssertTrue(imageTool.isHittable)
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

        XCTAssertTrue(app.buttons["ai.tools.speech"].waitForExistence(timeout: 8))
        usleep(300_000)

        // 5. Flagship Speech Studio
        let speechTool = app.buttons["ai.tools.speech"]
        if !speechTool.isHittable { app.swipeUp(); usleep(200_000) }
        speechTool.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ai.speech.script").firstMatch.waitForExistence(timeout: 8))
        let speechShot = XCTAttachment(screenshot: app.screenshot())
        speechShot.name = "WuMind-speech-studio"
        speechShot.lifetime = .keepAlways
        add(speechShot)
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
        _ = tenderBtn.waitForExistence(timeout: 6)
        for _ in 0..<2 where !tenderBtn.isHittable {
            let quickLive = app.buttons["wumind.quick.live"]
            if quickLive.exists { quickLive.swipeLeft() } else { break }
        }
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
}
