import Foundation
import XCTest
@testable import ShiftCore

final class WuMindShareableWebAppEngineTests: XCTestCase {

    // MARK: - 1. Renovation Quote Calculator: Generate -> Author v1->v2 -> Same Link + Zero Data Loss + Zero Leak + Read-Only Split

    func testRenovationQuoteCalculatorSameLinkRuleUpdateZeroLeakAndPermissionSplit() throws {
        var calc = WuMindShareableWebAppEngine.createRenovationQuoteCalculator(
            title: "现代全案装修报价计算器",
            stableSlug: "reno-quote-acceptance"
        )
        XCTAssertEqual(calc.version, 1)
        XCTAssertEqual(calc.publicShareURL, "https://app.wumind.ai/s/reno-quote-acceptance")
        XCTAssertEqual(calc.storageKey, "wumind_webapp_state_v1:reno-quote-acceptance")

        let sampleRooms: [WuMindShareableWebAppEngine.RenovationRuleSpec.RoomMeasurement] = [
            .init(roomName: "客厅", areaSqm: 38, selectedRuleIDs: ["floor_tile", "wall_paint"]),
            .init(roomName: "厨房", areaSqm: 12, selectedRuleIDs: ["floor_tile", "water_elec", "cabinet"]),
        ]
        let totalV1 = try XCTUnwrap(calc.renovationSpec?.estimateTotalYuan(rooms: sampleRooms))
        XCTAssertGreaterThan(totalV1, 0)

        let privateContext = WuMindShareableWebAppEngine.PrivateAuthorContext(
            rawQuoteSpreadsheetRows: [
                "内部底价表:瓷砖进货成本62元/㎡,工长返点18%",
                "供应商老王底价单_2026Q4.xlsx",
            ],
            apiKeysOrTokens: [
                "sk-live-secret998877665544332211",
                "Bearer super_secret_relay_token_987654",
            ],
            chatHistoryTranscript: [
                "用户原话：千万别把底价表和毛利率发给客户看",
                "内部聊天记录：张三客户报价上浮15%",
            ],
            privateContactStrings: [
                "13912345678",
                "boss_internal@company-secret.cn",
            ]
        )

        let pubV1 = WuMindShareableWebAppEngine.publishSanitizedSharePackage(
            app: calc,
            privateContext: privateContext
        )
        XCTAssertTrue(pubV1.audit.passedAllChecks, "v1 分享包安全与 Safari 主屏幕体检必须全部通过：\(pubV1.audit.leakedItems)")
        XCTAssertEqual(pubV1.permission, .openAndUseOnly, "外发链接必须严格限制为仅打开使用权限")
        XCTAssertEqual(pubV1.deliveryRoute, .safariHomeScreenWebApp)
        XCTAssertFalse(pubV1.replacesNativeInstaller, "Web App 路线不得宣称替代原生安装包")
        XCTAssertFalse(pubV1.audit.leakedAuthorToken, "作者编辑令牌绝不能写入分享页面")
        XCTAssertEqual(pubV1.audit.leakedPrivateDataCount, 0, "原报价表、密钥、聊天记录和手机号必须 0 泄漏")
        XCTAssertFalse(pubV1.shareableHTML.contains("进货成本62"))
        XCTAssertFalse(pubV1.shareableHTML.contains("sk-live-secret"))
        XCTAssertFalse(pubV1.shareableHTML.contains("底价表和毛利率"))
        XCTAssertFalse(pubV1.audit.physicalIphoneWeChatSafariTested, "离线单测不得冒充真机微信/Safari实测")

        // Unauthorized external recipient MUST NOT be able to mutate author rules
        let updatedSpec = WuMindShareableWebAppEngine.RenovationRuleSpec(
            items: [
                .init(id: "floor_tile", name: "地面瓷砖铺贴（含辅料）", unitPriceYuan: 160),
                .init(id: "wall_paint", name: "墙面乳胶漆（一底两面）", unitPriceYuan: 58),
                .init(id: "water_elec", name: "全屋水电隐蔽改造", unitPriceYuan: 120),
                .init(id: "cabinet", name: "定制橱衣柜（投影）", unitPriceYuan: 920),
            ],
            managementFeeRate: 0.06,
            discountNote: "v2 促销新规：乳胶漆/橱柜下调，管理费 6%"
        )
        let denied = WuMindShareableWebAppEngine.updateRenovationQuoteRules(
            app: &calc,
            providedAuthorToken: "wrong_recipient_token",
            updatedSpec: updatedSpec,
            changeSummary: "未授权篡改"
        )
        XCTAssertFalse(denied, "仅持有打开链接的收件人绝不能修改作者规则")
        XCTAssertEqual(calc.version, 1)

        // Authorized author updates rules -> version 1 -> 2 on the EXACT SAME URL & storageKey!
        let allowed = WuMindShareableWebAppEngine.updateRenovationQuoteRules(
            app: &calc,
            providedAuthorToken: calc.authorEditToken,
            updatedSpec: updatedSpec,
            changeSummary: "作者调价至 v2：瓷砖 160、乳胶漆 58、管理费降至 6%"
        )
        XCTAssertTrue(allowed)
        XCTAssertEqual(calc.version, 2)

        let totalV2 = try XCTUnwrap(calc.renovationSpec?.estimateTotalYuan(rooms: sampleRooms))
        XCTAssertNotEqual(totalV1, totalV2, "更新单价与管理费规则后报价必须实时变化")

        let pubV2 = WuMindShareableWebAppEngine.publishSanitizedSharePackage(
            app: calc,
            privateContext: privateContext
        )
        XCTAssertTrue(pubV2.audit.passedAllChecks)
        XCTAssertEqual(pubV2.publicShareURL, pubV1.publicShareURL, "作者改规则后必须保持同一个分享链接")
        XCTAssertEqual(pubV2.storageKey, pubV1.storageKey, "localStorage Key 必须保持不变以确保旧房间与草稿不丢")
        XCTAssertEqual(pubV2.version, 2)
        XCTAssertTrue(pubV2.shareableHTML.contains("data-wumind-version=\"2\""))
    }

    // MARK: - 2. 2-Level Portrait Game on the EXACT Same Unified Pipeline

    func testTwoLevelPortraitGameSharesUnifiedWebAppPipelineAndPreservesLevel1AndSaveKey() throws {
        var game = WuMindShareableWebAppEngine.createTwoLevelPortraitGame(
            title: "最后一跳 · 链接试玩版",
            stableSlug: "last-hop-acceptance"
        )
        let level1Before = try XCTUnwrap(game.gameLevels?.first)
        let pubV1 = WuMindShareableWebAppEngine.publishSanitizedSharePackage(
            app: game,
            privateContext: .init(
                apiKeysOrTokens: ["sk-game-builder-secret-1122334455"],
                chatHistoryTranscript: ["用户提示词：做两关竖屏解谜不要泄露我的 API Key"]
            )
        )
        XCTAssertTrue(pubV1.audit.passedAllChecks)
        XCTAssertEqual(pubV1.permission, .openAndUseOnly)
        XCTAssertFalse(pubV1.replacesNativeInstaller)
        XCTAssertEqual(pubV1.audit.leakedPrivateDataCount, 0)

        // Reject an unsolvable Level 2 edit
        let unsolvableL2 = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 2,
            name: "断路坏关",
            startStation: "A",
            edges: ["A": ["B"], "B": ["A"], "Z": []],
            targetChain: ["Z"],
            hopBudget: 5
        )
        XCTAssertFalse(
            WuMindShareableWebAppEngine.updateGameLevel2Rules(
                app: &game,
                providedAuthorToken: game.authorEditToken,
                easierLevel2: unsolvableL2
            ),
            "无解关卡不得发布至分享链接"
        )
        XCTAssertEqual(game.version, 1)

        // Author lowers Level 2 difficulty -> same link, same storageKey, Level 1 byte-identical!
        let easierL2 = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 2,
            name: "晚高峰换乘（降难版）",
            startStation: "A",
            edges: ["A": ["B", "D"], "B": ["C", "D"], "C": ["E"], "D": ["E"], "E": ["F"], "F": ["B"]],
            targetChain: ["E", "F", "B"],
            hopBudget: 7
        )
        XCTAssertTrue(
            WuMindShareableWebAppEngine.updateGameLevel2Rules(
                app: &game,
                providedAuthorToken: game.authorEditToken,
                easierLevel2: easierL2
            )
        )
        XCTAssertEqual(game.version, 2)
        XCTAssertEqual(game.gameLevels?.first, level1Before, "修改第 2 关后第 1 关必须完全不变")

        let pubV2 = WuMindShareableWebAppEngine.publishSanitizedSharePackage(app: game)
        XCTAssertTrue(pubV2.audit.passedAllChecks)
        XCTAssertEqual(pubV2.publicShareURL, pubV1.publicShareURL, "小游戏升级版本后保持同一个试玩链接")
        XCTAssertEqual(pubV2.storageKey, pubV1.storageKey, "小游戏升级版本后保留玩家既有通关记录 Key")
        XCTAssertEqual(pubV2.version, 2)
    }

    // MARK: - 3. Unified Safari Home Screen Manifest & WeChat Fallback Parity Across Calculator + Game

    func testSafariHomeScreenManifestAndWeChatGuideParityAcrossBothApps() throws {
        let apps = [
            WuMindShareableWebAppEngine.createRenovationQuoteCalculator(stableSlug: "calc-parity"),
            WuMindShareableWebAppEngine.createTwoLevelPortraitGame(stableSlug: "game-parity"),
        ]
        for app in apps {
            let pub = WuMindShareableWebAppEngine.publishSanitizedSharePackage(app: app)
            XCTAssertTrue(pub.audit.hasAppleWebAppCapableMeta)
            XCTAssertTrue(pub.audit.hasAppleWebAppTitle)
            XCTAssertTrue(pub.audit.hasAppleTouchIcon)
            XCTAssertTrue(pub.audit.hasStandaloneManifest)
            XCTAssertTrue(pub.audit.hasWeChatInAppGuide)
            XCTAssertTrue(pub.audit.honestNativeRouteDisclaimerPresent)

            let manifestData = Data(pub.manifestJSON.utf8)
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            XCTAssertEqual(obj["display"] as? String, "standalone")
            XCTAssertEqual(obj["start_url"] as? String, pub.publicShareURL)
            XCTAssertEqual(obj["wumind_permission"] as? String, "open_and_use_only")
            XCTAssertEqual(obj["wumind_app_version"] as? Int, 1)
            let icons = try XCTUnwrap(obj["icons"] as? [[String: Any]])
            XCTAssertFalse(icons.isEmpty)
        }
    }
}
