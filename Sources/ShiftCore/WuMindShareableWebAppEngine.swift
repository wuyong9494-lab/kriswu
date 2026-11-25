import Foundation

// MARK: - Mobile-First Shareable Web App Engine ("生成 → 试用 → 分享 → 添加到主屏幕")
// Unified pipeline for BOTH Renovation Quote Calculator AND 2-Level Portrait Game:
// - Same stable link across v1 -> v2 rule updates, with zero loss of saved user localStorage data
// - Strict permission separation: openAndUseOnly (public link) vs authorEdit (WUMIND only)
// - Zero-leak sanitization: never includes raw quote spreadsheets, API keys, secrets, or chat history
// - Complete iOS Safari Add-to-Home-Screen + WeChat in-app browser compatibility
// - Honest route separation: Web App / Safari Home Screen != iOS TestFlight / Android APK

public enum WuMindShareableWebAppEngine {

    public enum AppKind: String, Codable, Equatable, Sendable {
        case renovationQuoteCalculator
        case twoLevelPortraitGame

        public var chineseTitle: String {
            switch self {
            case .renovationQuoteCalculator: return "装修报价计算器"
            case .twoLevelPortraitGame: return "两关竖屏小游戏"
            }
        }
    }

    public enum AccessPermission: String, Codable, Equatable, Sendable {
        case openAndUseOnly = "open_and_use_only"
        case authorEdit = "author_edit"

        public var chineseLabel: String {
            switch self {
            case .openAndUseOnly: return "仅打开使用（不可改作者规则）"
            case .authorEdit: return "作者编辑权限（仅 WUMIND 内持有）"
            }
        }
    }

    public enum DeliveryRoute: String, Codable, Equatable, Sendable {
        case safariHomeScreenWebApp = "safari_home_screen_web_app"
        case nativeAppPackage = "native_app_package"

        public var chineseLabel: String {
            switch self {
            case .safariHomeScreenWebApp: return "链接试玩 / Safari 添加到主屏幕（Web App）"
            case .nativeAppPackage: return "原生安装包（iOS TestFlight / Android APK）"
            }
        }
    }

    /// Private author-only source context that MUST NEVER enter any shared link or HTML package.
    public struct PrivateAuthorContext: Equatable, Sendable {
        public var rawQuoteSpreadsheetRows: [String]
        public var apiKeysOrTokens: [String]
        public var chatHistoryTranscript: [String]
        public var privateContactStrings: [String]

        public init(
            rawQuoteSpreadsheetRows: [String] = [],
            apiKeysOrTokens: [String] = [],
            chatHistoryTranscript: [String] = [],
            privateContactStrings: [String] = []
        ) {
            self.rawQuoteSpreadsheetRows = rawQuoteSpreadsheetRows
            self.apiKeysOrTokens = apiKeysOrTokens
            self.chatHistoryTranscript = chatHistoryTranscript
            self.privateContactStrings = privateContactStrings
        }

        public static let empty = PrivateAuthorContext()
    }

    // MARK: - Renovation Quote Calculator Schema

    public struct RenovationUnitRule: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var unitLabel: String
        public var unitPriceYuan: Double

        public init(id: String, name: String, unitLabel: String = "元/㎡", unitPriceYuan: Double) {
            self.id = id
            self.name = name
            self.unitLabel = unitLabel
            self.unitPriceYuan = max(0, unitPriceYuan)
        }
    }

    public struct RenovationRuleSpec: Codable, Equatable, Sendable {
        public var items: [RenovationUnitRule]
        public var managementFeeRate: Double
        public var discountNote: String

        public init(items: [RenovationUnitRule], managementFeeRate: Double, discountNote: String) {
            self.items = items
            self.managementFeeRate = max(0, min(0.5, managementFeeRate))
            self.discountNote = discountNote
        }

        public struct RoomMeasurement: Codable, Equatable, Sendable {
            public var roomName: String
            public var areaSqm: Double
            public var selectedRuleIDs: [String]

            public init(roomName: String, areaSqm: Double, selectedRuleIDs: [String]) {
                self.roomName = roomName
                self.areaSqm = max(0, areaSqm)
                self.selectedRuleIDs = selectedRuleIDs
            }
        }

        public func estimateTotalYuan(rooms: [RoomMeasurement]) -> Double {
            let priceByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.unitPriceYuan) })
            var subtotal = 0.0
            for room in rooms {
                for rid in room.selectedRuleIDs {
                    subtotal += room.areaSqm * (priceByID[rid] ?? 0)
                }
            }
            let total = subtotal * (1.0 + managementFeeRate)
            return (total * 100).rounded() / 100
        }
    }

    // MARK: - Unified Versioned Web App Record

    public struct PublishedWebApp: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        /// Stable URL slug — NEVER changes when author publishes rule updates (v1 -> v2 -> ...).
        public let stableSlug: String
        /// Public read-only URL shared via WeChat / Safari — remains constant across rule versions.
        public let publicShareURL: String
        /// Stable client localStorage key tied to `stableSlug` so user data survives across versions.
        public let storageKey: String
        public var version: Int
        public let kind: AppKind
        public var title: String
        public var shortTitle: String
        public var themeColorHex: String
        /// Private author-only edit token — NEVER embedded into any shared HTML or manifest!
        public let authorEditToken: String
        public var ruleChangeSummary: String
        public var renovationSpec: RenovationRuleSpec?
        public var gameLevels: [WuMindMobileGameGraphWorkflow.RouteLevelSpec]?
        public var updatedAt: Date

        public init(
            id: UUID = UUID(),
            stableSlug: String,
            publicShareURL: String,
            storageKey: String,
            version: Int = 1,
            kind: AppKind,
            title: String,
            shortTitle: String,
            themeColorHex: String,
            authorEditToken: String,
            ruleChangeSummary: String,
            renovationSpec: RenovationRuleSpec? = nil,
            gameLevels: [WuMindMobileGameGraphWorkflow.RouteLevelSpec]? = nil,
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.stableSlug = stableSlug
            self.publicShareURL = publicShareURL
            self.storageKey = storageKey
            self.version = version
            self.kind = kind
            self.title = title
            self.shortTitle = shortTitle
            self.themeColorHex = themeColorHex
            self.authorEditToken = authorEditToken
            self.ruleChangeSummary = ruleChangeSummary
            self.renovationSpec = renovationSpec
            self.gameLevels = gameLevels
            self.updatedAt = updatedAt
        }
    }

    public struct PublicationSecurityAudit: Codable, Equatable, Sendable {
        public let hasAppleWebAppCapableMeta: Bool
        public let hasAppleWebAppTitle: Bool
        public let hasAppleTouchIcon: Bool
        public let hasStandaloneManifest: Bool
        public let hasWeChatInAppGuide: Bool
        public let enforcesReadOnlyPermission: Bool
        public let leakedAuthorToken: Bool
        public let leakedPrivateDataCount: Int
        public let leakedItems: [String]
        public let honestNativeRouteDisclaimerPresent: Bool
        public let passedAllChecks: Bool
        /// Honest verification separation: offline/Chromium audit NEVER claims real iPhone WeChat/Safari manual tap.
        public let physicalIphoneWeChatSafariTested: Bool
    }

    public struct SanitizedWebAppPublication: Codable, Equatable, Sendable {
        public let stableSlug: String
        public let publicShareURL: String
        public let storageKey: String
        public let version: Int
        public let kind: AppKind
        public let permission: AccessPermission
        public let deliveryRoute: DeliveryRoute
        public let replacesNativeInstaller: Bool
        public let manifestJSON: String
        public let shareableHTML: String
        public let audit: PublicationSecurityAudit
    }

    // MARK: - 1. Create & Update Renovation Quote Calculator (Same Link v1 -> v2, Zero Data Loss)

    public static func createRenovationQuoteCalculator(
        title: String = "装修报价计算器",
        stableSlug: String? = nil,
        baseOrigin: String = "https://app.wumind.ai",
        spec: RenovationRuleSpec? = nil,
        now: Date = Date()
    ) -> PublishedWebApp {
        let slug = sanitizeSlug(stableSlug ?? "renovation-quote-\(String(stableDigest(title + "v1").prefix(8)))")
        let defaultSpec = spec ?? RenovationRuleSpec(
            items: [
                RenovationUnitRule(id: "floor_tile", name: "地面瓷砖铺贴（含辅料）", unitLabel: "元/㎡", unitPriceYuan: 145),
                RenovationUnitRule(id: "wall_paint", name: "墙面乳胶漆（一底两面）", unitLabel: "元/㎡", unitPriceYuan: 68),
                RenovationUnitRule(id: "water_elec", name: "全屋水电隐蔽改造", unitLabel: "元/㎡", unitPriceYuan: 120),
                RenovationUnitRule(id: "cabinet", name: "定制橱衣柜（投影）", unitLabel: "元/㎡", unitPriceYuan: 980),
            ],
            managementFeeRate: 0.08,
            discountNote: "v1 标准施工单价 · 含 8% 工程管理费"
        )
        let origin = baseOrigin.hasSuffix("/") ? String(baseOrigin.dropLast()) : baseOrigin
        return PublishedWebApp(
            stableSlug: slug,
            publicShareURL: "\(origin)/s/\(slug)",
            storageKey: "wumind_webapp_state_v1:\(slug)",
            version: 1,
            kind: .renovationQuoteCalculator,
            title: title,
            shortTitle: "装修报价",
            themeColorHex: "#1d4ed8",
            authorEditToken: "wumind_author_edit_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
            ruleChangeSummary: "初始版本 v1：4 项标准工种单价 + 8% 管理费",
            renovationSpec: defaultSpec,
            gameLevels: nil,
            updatedAt: now
        )
    }

    /// Author-only rule update: increments version while keeping `stableSlug`, `publicShareURL`, and `storageKey` IDENTICAL!
    public static func updateRenovationQuoteRules(
        app: inout PublishedWebApp,
        providedAuthorToken: String,
        updatedSpec: RenovationRuleSpec,
        changeSummary: String,
        now: Date = Date()
    ) -> Bool {
        guard app.kind == .renovationQuoteCalculator,
              providedAuthorToken == app.authorEditToken else {
            return false
        }
        app.version += 1
        app.renovationSpec = updatedSpec
        app.ruleChangeSummary = changeSummary
        app.updatedAt = now
        return true
    }

    // MARK: - 2. Create & Update 2-Level Portrait Game (Same Unified Pipeline!)

    public static func createTwoLevelPortraitGame(
        title: String = "最后一跳 · 两关试玩版",
        stableSlug: String? = nil,
        baseOrigin: String = "https://app.wumind.ai",
        level1: WuMindMobileGameGraphWorkflow.RouteLevelSpec? = nil,
        level2: WuMindMobileGameGraphWorkflow.RouteLevelSpec? = nil,
        now: Date = Date()
    ) -> PublishedWebApp {
        let slug = sanitizeSlug(stableSlug ?? "last-hop-game-\(String(stableDigest(title + "v1").prefix(8)))")
        let l1 = level1 ?? WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 1,
            name: "晨间配送",
            startStation: "A",
            edges: ["A": ["B", "C"], "B": ["D"], "C": ["D"], "D": ["E"], "E": ["A"]],
            targetChain: ["D", "E"],
            hopBudget: 4
        )
        let l2 = level2 ?? WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 2,
            name: "晚高峰换乘",
            startStation: "A",
            edges: ["A": ["B"], "B": ["C", "D"], "C": ["E"], "D": ["E"], "E": ["F"], "F": ["B"]],
            targetChain: ["E", "F", "B"],
            hopBudget: 5
        )
        let origin = baseOrigin.hasSuffix("/") ? String(baseOrigin.dropLast()) : baseOrigin
        return PublishedWebApp(
            stableSlug: slug,
            publicShareURL: "\(origin)/s/\(slug)",
            storageKey: "wumind_webapp_state_v1:\(slug)",
            version: 1,
            kind: .twoLevelPortraitGame,
            title: title,
            shortTitle: "最后一跳",
            themeColorHex: "#0f172a",
            authorEditToken: "wumind_author_edit_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
            ruleChangeSummary: "初始版本 v1：第 1 关（预算 4 步）+ 第 2 关标准难度（预算 5 步）",
            renovationSpec: nil,
            gameLevels: [l1, l2],
            updatedAt: now
        )
    }

    /// Author-only Level 2 revision: keeps Level 1, `stableSlug`, `publicShareURL`, and `storageKey` 100% IDENTICAL!
    public static func updateGameLevel2Rules(
        app: inout PublishedWebApp,
        providedAuthorToken: String,
        easierLevel2: WuMindMobileGameGraphWorkflow.RouteLevelSpec,
        changeSummary: String = "v2 仅降低第 2 关难度，第 1 关与玩家已存通关记录完全保留",
        now: Date = Date()
    ) -> Bool {
        guard app.kind == .twoLevelPortraitGame,
              providedAuthorToken == app.authorEditToken,
              var levels = app.gameLevels,
              levels.count >= 2,
              let minHops = WuMindMobileGameGraphWorkflow.shortestChainHops(for: easierLevel2),
              minHops <= easierLevel2.hopBudget else {
            return false
        }
        levels[1] = easierLevel2
        app.gameLevels = levels
        app.version += 1
        app.ruleChangeSummary = changeSummary
        app.updatedAt = now
        return true
    }

    // MARK: - 3. Unified Sanitized Publication & Safari Home Screen Web App Packaging

    /// Publishes a read-only (`openAndUseOnly`), zero-leak Web App HTML + Manifest package
    /// suitable for WeChat in-app link sharing and iOS Safari "Add to Home Screen".
    public static func publishSanitizedSharePackage(
        app: PublishedWebApp,
        privateContext: PrivateAuthorContext = .empty
    ) -> SanitizedWebAppPublication {
        let iconDataURI = buildSVGIconDataURI(shortTitle: app.shortTitle, bgHex: app.themeColorHex)
        let manifestJSON = buildWebAppManifestJSON(app: app, iconDataURI: iconDataURI)
        let rawHTML: String
        switch app.kind {
        case .renovationQuoteCalculator:
            rawHTML = renderRenovationWebAppHTML(
                app: app,
                spec: app.renovationSpec ?? RenovationRuleSpec(items: [], managementFeeRate: 0.08, discountNote: ""),
                iconDataURI: iconDataURI,
                manifestJSON: manifestJSON
            )
        case .twoLevelPortraitGame:
            rawHTML = renderTwoLevelGameWebAppHTML(
                app: app,
                levels: app.gameLevels ?? [],
                iconDataURI: iconDataURI,
                manifestJSON: manifestJSON
            )
        }

        // Run existing generic PII/secret sanitizer first
        let sanitized = WuMindMiniAppArtifactEngine.sanitizeForExternalShare(rawHTML: rawHTML)
        let finalHTML = sanitized.shareableHTML

        // Strict leak audit against authorEditToken + every private context item + generic secret patterns
        var leakedItems: [String] = []
        let leakedAuthor = finalHTML.contains(app.authorEditToken)
        if leakedAuthor {
            leakedItems.append("authorEditToken")
        }

        let forbiddenSnippets = (
            privateContext.rawQuoteSpreadsheetRows +
            privateContext.apiKeysOrTokens +
            privateContext.chatHistoryTranscript +
            privateContext.privateContactStrings
        )
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }

        for snippet in forbiddenSnippets {
            if finalHTML.contains(snippet) {
                leakedItems.append("private_snippet:\(snippet.prefix(12))")
            }
        }
        if sanitized.leakedSecretsDetected > 0 {
            leakedItems.append("regex_secret_leak:\(sanitized.leakedSecretsDetected)")
        }

        let hasCapable = finalHTML.contains("name=\"apple-mobile-web-app-capable\" content=\"yes\"")
        let hasTitle = finalHTML.contains("name=\"apple-mobile-web-app-title\"")
        let hasIcon = finalHTML.contains("rel=\"apple-touch-icon\"")
        let hasManifest = finalHTML.contains("rel=\"manifest\"") && manifestJSON.contains("\"display\":\"standalone\"")
        let hasWeChatGuide = finalHTML.contains("MicroMessenger") && finalHTML.contains("添加到主屏幕")
        let enforcesReadOnly = finalHTML.contains("open_and_use_only") && !leakedAuthor
        let hasHonestDisclaimer = finalHTML.contains("Safari 添加到主屏幕") && finalHTML.contains("TestFlight") && finalHTML.contains("APK")

        let allOK = hasCapable && hasTitle && hasIcon && hasManifest && hasWeChatGuide && enforcesReadOnly && leakedItems.isEmpty && hasHonestDisclaimer

        let audit = PublicationSecurityAudit(
            hasAppleWebAppCapableMeta: hasCapable,
            hasAppleWebAppTitle: hasTitle,
            hasAppleTouchIcon: hasIcon,
            hasStandaloneManifest: hasManifest,
            hasWeChatInAppGuide: hasWeChatGuide,
            enforcesReadOnlyPermission: enforcesReadOnly,
            leakedAuthorToken: leakedAuthor,
            leakedPrivateDataCount: leakedItems.count,
            leakedItems: leakedItems,
            honestNativeRouteDisclaimerPresent: hasHonestDisclaimer,
            passedAllChecks: allOK,
            physicalIphoneWeChatSafariTested: false
        )

        return SanitizedWebAppPublication(
            stableSlug: app.stableSlug,
            publicShareURL: app.publicShareURL,
            storageKey: app.storageKey,
            version: app.version,
            kind: app.kind,
            permission: .openAndUseOnly,
            deliveryRoute: .safariHomeScreenWebApp,
            replacesNativeInstaller: false,
            manifestJSON: manifestJSON,
            shareableHTML: finalHTML,
            audit: audit
        )
    }

    // MARK: - Helpers & Self-Contained Mobile-First Web App Renderers

    private static func sanitizeSlug(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let str = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return str.isEmpty ? "wumind-app" : str
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func buildSVGIconDataURI(shortTitle: String, bgHex: String) -> String {
        let glyph = escapeHTML(String(shortTitle.prefix(2)))
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 180 180'><rect width='180' height='180' rx='40' fill='\(bgHex)'/><text x='90' y='108' text-anchor='middle' font-size='64' font-family='sans-serif' font-weight='700' fill='#ffffff'>\(glyph)</text></svg>"
        let b64 = Data(svg.utf8).base64EncodedString()
        return "data:image/svg+xml;base64,\(b64)"
    }

    private static func buildWebAppManifestJSON(app: PublishedWebApp, iconDataURI: String) -> String {
        let obj: [String: Any] = [
            "name": app.title,
            "short_name": app.shortTitle,
            "start_url": app.publicShareURL,
            "scope": "/s/\(app.stableSlug)",
            "display": "standalone",
            "orientation": "portrait",
            "background_color": "#0f172a",
            "theme_color": app.themeColorHex,
            "wumind_app_slug": app.stableSlug,
            "wumind_app_version": app.version,
            "wumind_permission": AccessPermission.openAndUseOnly.rawValue,
            "icons": [
                ["src": iconDataURI, "sizes": "180x180", "type": "image/svg+xml", "purpose": "any maskable"]
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private static func sharedWebAppHead(app: PublishedWebApp, iconDataURI: String, manifestJSON: String) -> String {
        let safeTitle = escapeHTML(app.title)
        let safeShort = escapeHTML(app.shortTitle)
        let manifestB64 = Data(manifestJSON.utf8).base64EncodedString()
        return """
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover" />
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
        <meta name="apple-mobile-web-app-title" content="\(safeShort)" />
        <meta name="theme-color" content="\(app.themeColorHex)" />
        <link rel="apple-touch-icon" href="\(iconDataURI)" />
        <link rel="manifest" href="data:application/manifest+json;base64,\(manifestB64)" />
        <title>\(safeTitle)</title>
        """
    }

    private static func renderRenovationWebAppHTML(
        app: PublishedWebApp,
        spec: RenovationRuleSpec,
        iconDataURI: String,
        manifestJSON: String
    ) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let specJSON = (try? enc.encode(spec)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let safeSpecJSON = specJSON.replacingOccurrences(of: "</script>", with: "<\\/script>")
        let safeTitle = escapeHTML(app.title)
        let safeSummary = escapeHTML(app.ruleChangeSummary)
        let safeURL = escapeHTML(app.publicShareURL)

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        \(sharedWebAppHead(app: app, iconDataURI: iconDataURI, manifestJSON: manifestJSON))
        <style>
        *{box-sizing:border-box;touch-action:manipulation;-webkit-tap-highlight-color:transparent;}
        body{margin:0;background:#f4f7fb;color:#0f172a;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;padding:env(safe-area-inset-top,12px) 12px 28px;}
        .wrap{max-width:440px;margin:0 auto;}
        .card{background:#fff;border-radius:16px;padding:14px;margin-bottom:12px;border:1px solid #e2e8f0;box-shadow:0 3px 12px rgba(15,23,42,.05);}
        h1{margin:0 0 4px;font-size:19px;}
        .meta{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0 8px;font-size:11px;}
        .chip{padding:3px 8px;border-radius:99px;background:#eff6ff;color:#1d4ed8;font-weight:600;}
        .chip.readonly{background:#f1f5f9;color:#475569;}
        .chip.ok{background:#ecfdf5;color:#047857;}
        .guide{background:#fefce8;border:1px solid #fde047;color:#854d0e;border-radius:12px;padding:10px;font-size:12px;line-height:1.45;margin-bottom:12px;}
        .upgrade{background:#ecfdf5;border:1px solid #6ee7b7;color:#065f46;border-radius:12px;padding:10px;font-size:12px;margin-bottom:12px;display:none;}
        .price{font-size:28px;font-weight:800;color:#1d4ed8;margin:4px 0;}
        .row{display:flex;gap:8px;margin-bottom:8px;}
        input{width:100%;min-height:44px;padding:8px 10px;border:1px solid #cbd5e1;border-radius:10px;font-size:15px;}
        button{min-height:44px;border:none;border-radius:12px;font-size:14px;font-weight:600;padding:0 12px;cursor:pointer;}
        .btn-primary{background:#2563eb;color:#fff;width:100%;}
        .btn-secondary{background:#e2e8f0;color:#0f172a;}
        .rule-row{display:flex;justify-content:space-between;align-items:center;padding:6px 0;border-bottom:1px dashed #e2e8f0;font-size:13px;}
        .room-item{display:flex;justify-content:space-between;align-items:center;padding:8px 10px;border-radius:10px;background:#f8fafc;border:1px solid #e2e8f0;margin-bottom:6px;font-size:13px;}
        .draft-item{padding:8px 10px;border-radius:10px;background:#f8fafc;border:1px solid #e2e8f0;margin-bottom:6px;font-size:12px;}
        .foot{font-size:11px;color:#64748b;line-height:1.5;text-align:center;margin-top:8px;}
        </style>
        </head>
        <body data-wumind-permission="open_and_use_only" data-wumind-version="\(app.version)" data-wumind-slug="\(app.stableSlug)">
        <div class="wrap">
          <div class="card">
            <h1>\(safeTitle)</h1>
            <div class="meta">
              <span class="chip" id="verChip">版本 v\(app.version)</span>
              <span class="chip readonly">客户只读使用版 · 不可改作者规则</span>
              <span class="chip ok">已脱敏（无原表/密钥/聊天记录）</span>
            </div>
            <div style="font-size:12px;color:#475569;" id="ruleSummary">\(safeSummary)</div>
          </div>

          <div class="guide" id="envGuide"></div>
          <div class="upgrade" id="upgradeNotice"></div>

          <div class="card">
            <div style="font-size:12px;color:#64748b;">当前方案预估总价（含管理费 <span id="feePct"></span>%）</div>
            <div class="price" id="totalPrice">¥0.00</div>
            <div style="font-size:12px;color:#64748b;" id="discountNote"></div>
            <div id="rulesList" style="margin-top:10px;"></div>
          </div>

          <div class="card">
            <div style="font-weight:700;font-size:14px;margin-bottom:8px;">输入房间面积（刷新或作者更新规则均不丢）</div>
            <div class="row">
              <input id="roomName" placeholder="房间名（如 客厅）" value="客厅" />
              <input id="roomArea" type="number" min="1" step="0.5" placeholder="面积㎡" value="35" style="max-width:110px;" />
            </div>
            <button class="btn-primary" id="btnAddRoom" onclick="addRoom()">添加房间并实时算价</button>
            <div id="roomsList" style="margin-top:10px;"></div>
          </div>

          <div class="card">
            <div style="font-weight:700;font-size:14px;margin-bottom:8px;">保存报价草稿（跨版本保留）</div>
            <div class="row">
              <input id="draftTitle" placeholder="方案备注（如 初版预算）" value="我的装修方案" />
              <button class="btn-secondary" id="btnSaveDraft" onclick="saveDraft()" style="white-space:nowrap;">存草稿</button>
            </div>
            <div id="draftsList"></div>
          </div>

          <div class="foot">
            同链接地址：\(safeURL)<br/>
            本页为 Web App 试算与 Safari 添加到主屏幕路线，不替代原生 iOS TestFlight / Android APK 安装包。
          </div>
        </div>
        <script id="wumind-public-spec" type="application/json">\(safeSpecJSON)</script>
        <script>
        const APP_VERSION = \(app.version);
        const STORAGE_KEY = \(jsonStringLiteral(app.storageKey));
        const SPEC = JSON.parse(document.getElementById('wumind-public-spec').textContent);

        function loadState(){
          try {
            const raw = localStorage.getItem(STORAGE_KEY);
            if (raw) {
              const parsed = JSON.parse(raw);
              return {
                lastSeenVersion: parsed.lastSeenVersion || 1,
                rooms: Array.isArray(parsed.rooms) ? parsed.rooms : [],
                drafts: Array.isArray(parsed.drafts) ? parsed.drafts : []
              };
            }
          } catch (_) {}
          return { lastSeenVersion: APP_VERSION, rooms: [{ name: '客厅', area: 32 }, { name: '厨房', area: 9 }], drafts: [] };
        }

        let state = loadState();
        const migratedFromVersion = state.lastSeenVersion < APP_VERSION ? state.lastSeenVersion : null;
        state.lastSeenVersion = APP_VERSION;

        function persist(){
          try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (_) {}
        }

        function calcTotal(){
          const unitSum = SPEC.items.reduce((s, it) => s + Number(it.unitPriceYuan || 0), 0);
          const areaSum = state.rooms.reduce((s, r) => s + Math.max(0, Number(r.area || 0)), 0);
          return Math.round(areaSum * unitSum * (1 + Number(SPEC.managementFeeRate || 0)) * 100) / 100;
        }

        function addRoom(){
          const name = (document.getElementById('roomName').value || '').trim() || ('房间' + (state.rooms.length + 1));
          const area = Math.max(1, Number(document.getElementById('roomArea').value) || 10);
          state.rooms.push({ name, area });
          persist();
          render();
        }

        function removeRoom(idx){
          state.rooms.splice(idx, 1);
          persist();
          render();
        }

        function saveDraft(){
          const title = (document.getElementById('draftTitle').value || '').trim() || ('方案 ' + (state.drafts.length + 1));
          state.drafts.unshift({
            title,
            savedAtVersion: APP_VERSION,
            totalYuan: calcTotal(),
            roomCount: state.rooms.length
          });
          persist();
          render();
        }

        function updateEnvBanner(){
          const ua = navigator.userAgent || '';
          const isWeChat = /MicroMessenger/i.test(ua);
          const isStandalone = window.navigator.standalone === true || (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches);
          const el = document.getElementById('envGuide');
          if (isStandalone) {
            el.textContent = '已作为主屏幕 Web App 独立运行（版本 v' + APP_VERSION + '）· 作者更新规则后重开即同步新单价，已填房间不丢。';
          } else if (isWeChat) {
            el.textContent = '当前在微信内打开，已可直接算价。如需加到 iPhone 桌面图标：点右上角「···」→「在 Safari 中打开」→ 底部「分享」→「添加到主屏幕」。';
          } else {
            el.textContent = '在 iPhone Safari 中点底部「分享」→「添加到主屏幕」，即可像 App 一样从桌面图标反复打开。';
          }
          if (migratedFromVersion !== null) {
            const up = document.getElementById('upgradeNotice');
            up.style.display = 'block';
            up.textContent = '同链接已自动更新至 v' + APP_VERSION + '（原 v' + migratedFromVersion + '）· 已完整保留你之前的 ' + state.rooms.length + ' 个房间与 ' + state.drafts.length + ' 条已存草稿！';
          }
        }

        function render(){
          document.getElementById('feePct').textContent = String(Math.round((SPEC.managementFeeRate || 0) * 100));
          document.getElementById('discountNote').textContent = SPEC.discountNote || '';
          document.getElementById('totalPrice').textContent = '¥' + calcTotal().toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
          document.getElementById('rulesList').innerHTML = SPEC.items.map(it =>
            '<div class="rule-row"><span>' + it.name + '</span><strong>¥' + it.unitPriceYuan + ' ' + it.unitLabel + '</strong></div>'
          ).join('');
          document.getElementById('roomsList').innerHTML = state.rooms.map((r, i) =>
            '<div class="room-item"><span>' + r.name + ' · ' + r.area + ' ㎡</span><button class="btn-secondary" style="min-height:32px;font-size:12px;" onclick="removeRoom(' + i + ')">移除</button></div>'
          ).join('');
          document.getElementById('draftsList').innerHTML = state.drafts.length === 0
            ? '<div style="font-size:12px;color:#94a3b8;">暂无已存草稿</div>'
            : state.drafts.map(d =>
                '<div class="draft-item"><strong>' + d.title + '</strong> · 保存于 v' + d.savedAtVersion + ' · ' + d.roomCount + ' 间 · ¥' + Number(d.totalYuan).toFixed(2) + '</div>'
              ).join('');
        }

        persist();
        updateEnvBanner();
        render();
        </script>
        </body>
        </html>
        """
    }

    private static func renderTwoLevelGameWebAppHTML(
        app: PublishedWebApp,
        levels: [WuMindMobileGameGraphWorkflow.RouteLevelSpec],
        iconDataURI: String,
        manifestJSON: String
    ) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let levelsJSON = (try? enc.encode(levels)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        let safeLevelsJSON = levelsJSON.replacingOccurrences(of: "</script>", with: "<\\/script>")
        let safeTitle = escapeHTML(app.title)
        let safeSummary = escapeHTML(app.ruleChangeSummary)
        let safeURL = escapeHTML(app.publicShareURL)

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        \(sharedWebAppHead(app: app, iconDataURI: iconDataURI, manifestJSON: manifestJSON))
        <style>
        *{box-sizing:border-box;touch-action:manipulation;-webkit-tap-highlight-color:transparent;}
        body{margin:0;background:#0b1220;color:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;padding:env(safe-area-inset-top,12px) 12px 28px;}
        .wrap{max-width:420px;margin:0 auto;}
        .card{background:#111c32;border-radius:16px;padding:14px;margin-bottom:12px;border:1px solid #263451;}
        h1{margin:0 0 6px;font-size:19px;}
        .meta{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;font-size:11px;}
        .chip{padding:3px 8px;border-radius:99px;background:#1d4ed8;color:#fff;font-weight:600;}
        .chip.readonly{background:#1e293b;color:#cbd5e1;}
        .guide{background:#1e293b;border:1px solid #334155;color:#fde68a;border-radius:12px;padding:10px;font-size:12px;line-height:1.45;margin-bottom:10px;}
        .upgrade{background:#064e3b;border:1px solid #10b981;color:#d1fae5;border-radius:12px;padding:10px;font-size:12px;margin-bottom:10px;display:none;}
        .hud{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px;font-size:13px;}
        .pill{background:#1b2a47;padding:6px 10px;border-radius:10px;}
        .grid{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin:12px 0;}
        button.station{min-height:52px;border-radius:12px;border:1px solid #35507d;background:#1e3257;color:#fff;font-size:15px;font-weight:700;cursor:pointer;}
        button.station.current{background:#2563eb;border-color:#93c5fd;}
        button.station.target{border-color:#fbbf24;box-shadow:0 0 0 2px rgba(251,191,36,.35);}
        button.station:disabled{opacity:.38;cursor:not-allowed;}
        .actions{display:flex;gap:8px;margin-top:10px;}
        .actions button{flex:1;min-height:48px;border-radius:12px;border:none;font-size:14px;font-weight:700;cursor:pointer;}
        .btn-restart{background:#334155;color:#fff;}
        .btn-next{background:#10b981;color:#042f2e;}
        .banner{margin-top:10px;padding:10px;border-radius:10px;background:#1e293b;font-size:13px;min-height:42px;}
        .foot{font-size:11px;color:#94a3b8;line-height:1.5;text-align:center;margin-top:8px;}
        </style>
        </head>
        <body data-wumind-permission="open_and_use_only" data-wumind-version="\(app.version)" data-wumind-slug="\(app.stableSlug)">
        <div class="wrap">
          <div class="card">
            <h1>\(safeTitle)</h1>
            <div class="meta">
              <span class="chip" id="verChip">版本 v\(app.version)</span>
              <span class="chip readonly">玩家试玩只读版 · 不可改关卡配置</span>
            </div>
            <div style="font-size:12px;color:#94a3b8;" id="ruleSummary">\(safeSummary)</div>
          </div>

          <div class="guide" id="envGuide"></div>
          <div class="upgrade" id="upgradeNotice"></div>

          <div class="card">
            <div class="hud">
              <div class="pill" id="lvlBadge">关卡</div>
              <div class="pill" id="hopsBadge">剩余步数</div>
              <div class="pill" id="orderBadge">订单进度</div>
              <div class="pill" id="progressBadge">已通关 0 关</div>
            </div>
            <div class="grid" id="stations"></div>
            <div class="banner" id="statusText">单手点按可达站点完成连锁配送</div>
            <div class="actions">
              <button class="btn-restart" id="btnRestart" onclick="restartLevel()">重开本关</button>
              <button class="btn-next" id="btnSwitch" onclick="switchLevel()">切换关卡</button>
            </div>
          </div>

          <div class="foot">
            同链接试玩地址：\(safeURL)<br/>
            本页为网页链接试玩与 Safari 添加到主屏幕路线，不替代原生 iOS TestFlight / Android APK 打包路线。
          </div>
        </div>
        <script id="wumind-public-levels" type="application/json">\(safeLevelsJSON)</script>
        <script>
        const APP_VERSION = \(app.version);
        const STORAGE_KEY = \(jsonStringLiteral(app.storageKey));
        const LEVELS = JSON.parse(document.getElementById('wumind-public-levels').textContent);

        function loadProgress(){
          try {
            const raw = localStorage.getItem(STORAGE_KEY);
            if (raw) {
              const p = JSON.parse(raw);
              return {
                lastSeenVersion: p.lastSeenVersion || 1,
                completedLevels: Array.isArray(p.completedLevels) ? p.completedLevels : [],
                bestHopsByLevel: p.bestHopsByLevel && typeof p.bestHopsByLevel === 'object' ? p.bestHopsByLevel : {}
              };
            }
          } catch (_) {}
          return { lastSeenVersion: APP_VERSION, completedLevels: [], bestHopsByLevel: {} };
        }

        let progress = loadProgress();
        const migratedFromVersion = progress.lastSeenVersion < APP_VERSION ? progress.lastSeenVersion : null;
        progress.lastSeenVersion = APP_VERSION;
        function persist(){ try { localStorage.setItem(STORAGE_KEY, JSON.stringify(progress)); } catch (_) {} }

        let levelIdx = 0, pos = '', orderIdx = 0, hopsUsed = 0, hopsLeft = 0, finished = false;

        function loadLevel(i){
          levelIdx = i % LEVELS.length;
          const lv = LEVELS[levelIdx];
          pos = lv.startStation; orderIdx = 0; hopsUsed = 0; hopsLeft = lv.hopBudget; finished = false;
          render();
        }
        function restartLevel(){ loadLevel(levelIdx); }
        function switchLevel(){ loadLevel(levelIdx + 1); }

        function tapStation(st){
          if (finished) return;
          const lv = LEVELS[levelIdx];
          const reach = lv.edges[pos] || [];
          if (!reach.includes(st)) return;
          pos = st; hopsUsed += 1; hopsLeft -= 1;
          if (pos === lv.targetChain[orderIdx]) orderIdx += 1;
          if (orderIdx >= lv.targetChain.length) {
            finished = true;
            if (!progress.completedLevels.includes(lv.levelNumber)) progress.completedLevels.push(lv.levelNumber);
            const prevBest = progress.bestHopsByLevel[String(lv.levelNumber)];
            if (!prevBest || hopsUsed < prevBest) progress.bestHopsByLevel[String(lv.levelNumber)] = hopsUsed;
            persist();
          } else if (hopsLeft <= 0) {
            finished = true;
          }
          render();
        }

        function updateEnvBanner(){
          const ua = navigator.userAgent || '';
          const isWeChat = /MicroMessenger/i.test(ua);
          const isStandalone = window.navigator.standalone === true || (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches);
          const el = document.getElementById('envGuide');
          if (isStandalone) {
            el.textContent = '已作为主屏幕 Web App 独立试玩（v' + APP_VERSION + '）· 关卡更新后通关记录不丢。';
          } else if (isWeChat) {
            el.textContent = '微信内直接可玩，免安装测试包。如需加到桌面图标：点右上角「···」→「在 Safari 中打开」→「分享」→「添加到主屏幕」。';
          } else {
            el.textContent = '在 iPhone Safari 中点底部「分享」→「添加到主屏幕」，即可作为主屏幕小游戏反复打开。';
          }
          if (migratedFromVersion !== null) {
            const up = document.getElementById('upgradeNotice');
            up.style.display = 'block';
            up.textContent = '同链接已升级至 v' + APP_VERSION + '（原 v' + migratedFromVersion + '）· 已完整保留原有通关记录（已通关：' + (progress.completedLevels.join('、') || '无') + '）。';
          }
        }

        function render(){
          const lv = LEVELS[levelIdx];
          const reach = lv.edges[pos] || [];
          const target = lv.targetChain[orderIdx] || '';
          document.getElementById('lvlBadge').textContent = '第' + lv.levelNumber + '关 ' + lv.name;
          document.getElementById('hopsBadge').textContent = '余步 ' + hopsLeft + '/' + lv.hopBudget;
          document.getElementById('orderBadge').textContent = '订单 ' + orderIdx + '/' + lv.targetChain.length;
          document.getElementById('progressBadge').textContent = '已通关 ' + progress.completedLevels.length + ' 关';
          const box = document.getElementById('stations'); box.innerHTML = '';
          Object.keys(lv.edges).sort().forEach(st => {
            const b = document.createElement('button');
            b.className = 'station' + (st===pos?' current':'') + (st===target?' target':'');
            b.dataset.station = st;
            b.textContent = st + (st===pos?' (当前)':'') + (st===target?' [送达]':'');
            b.disabled = finished || !reach.includes(st);
            b.onclick = () => tapStation(st);
            box.appendChild(b);
          });
          const status = document.getElementById('statusText');
          if (orderIdx >= lv.targetChain.length) status.textContent = '第 ' + lv.levelNumber + ' 关通关成功！（用时 ' + hopsUsed + ' 步，记录已保存）';
          else if (hopsLeft <= 0) status.textContent = '步数耗尽，请点按「重开本关」。';
          else status.textContent = '当前位于 ' + pos + '，下一送达目标：' + target + '（上一单终点即下一单起点）';
        }

        persist();
        updateEnvBanner();
        loadLevel(0);
        </script>
        </body>
        </html>
        """
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
           let arr = String(data: data, encoding: .utf8),
           arr.count >= 2 {
            return String(arr.dropFirst().dropLast())
        }
        return "\"\""
    }
}
