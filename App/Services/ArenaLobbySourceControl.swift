import Foundation

/// Select a complete source button, including its label and background. The
/// application supplies the title and action; source placeholders are never used.
struct ArenaLobbySourceControl {
    enum Role: String, CaseIterable, Sendable {
        case shop, heroes, friends, quests, battle, team, invite, menu, coins, trophies, profile, season

        var export: String {
            switch self {
            case .shop, .heroes: return "mainscreen_hud_left"
            case .friends, .team: return "mainscreen_hud_right"
            case .quests, .season: return "mainscreen_hud_bottom_left"
            case .battle: return "mainscreen_hud_bottom_right"
            case .invite: return "mainscreen_center"
            case .menu, .coins: return "mainscreen_hud_top_right"
            case .trophies, .profile: return "mainscreen_hud_top_left"
            }
        }
        var idleLabel: String? {
            switch self {
            case .shop, .heroes: return "idle"
            case .friends, .battle, .team, .menu, .coins: return nil
            case .quests: return "default"
            case .invite: return "normal"
            case .trophies: return "trophy_road_inprogress"
            case .profile: return "no_fame"
            case .season: return "brawl_pass_inprogress"
            }
        }
        var instance: String {
            switch self {
            case .shop: return "button_navi_shop"
            case .heroes: return "button_navi_brawlers"
            case .friends: return "button_navi_friends"
            case .quests: return "button_quests"
            case .battle: return "brawl_container"
            case .team: return "button_navi_team"
            case .invite: return "button_invite_player_2"
            case .menu: return "button_hamburger"
            case .coins: return "top_resources_movable/header_craft_resource"
            case .trophies: return "button_trophy_road/trophy_container"
            case .profile: return "button_player_card"
            case .season: return "brawl_pass_container/button_brawl_pass"
            }
        }
        var title: String {
            switch self { case .shop: return "商店"; case .heroes: return "英雄"; case .friends: return "好友"; case .quests: return "任务"; case .battle: return "对战"; case .team: return "组队"; case .invite: return "邀请队友"; case .menu: return "设置"; case .coins: return "金币"; case .trophies: return "奖杯"; case .profile: return "玩家"; case .season: return "乱斗通行证" }
        }
        /// Icon-only source controls have no text field. Their native button
        /// still supplies an accessibility title, without inventing source text.
        var titlePath: String? {
            switch self {
            case .battle: return "brawl_button/txt"
            case .invite, .menu: return nil
            case .coins: return "value_txt"
            case .trophies: return "progress_txt"
            case .profile: return "player_name_txt"
            case .season: return "label_txt"
            default: return "txt"
            }
        }
    }

    struct Season: Equatable, Sendable {
        let tier: Int
        let points: Int
        let pointsPerTier: Int
        let hasReward: Bool
    }

    /// Only state used by this control belongs in its cache identity. Spending
    /// coins must not restart an unrelated shop or pass animation.
    struct Binding: Equatable, Sendable {
        let title: String
        let season: Season?
    }

    struct Values: Equatable, Sendable {
        let coins: Int
        let trophies: Int
        let playerName: String
        let season: Season?

        init(coins: Int, trophies: Int, playerName: String = "我", season: Season? = nil) {
            self.coins = coins; self.trophies = trophies
            self.playerName = playerName; self.season = season
        }

        func title(for role: Role) -> String? {
            switch role {
            case .coins: return String(coins)
            case .trophies: return String(trophies)
            case .profile: return playerName
            default: return nil
            }
        }

        func binding(for role: Role, localizedTitle: String) -> Binding {
            .init(title: title(for: role) ?? localizedTitle, season: role == .season ? season : nil)
        }
    }

    struct Request: Equatable {
        let revision: UUID
        let values: Values
    }

    let scene: ArenaLobbyTimelineScene
    /// Source coordinates, not an assumed full-screen reference resolution.
    let bounds: ArenaLobbyTimelineScene.Rect
    /// The stable button footprint, excluding idle particles outside it.
    let layoutBounds: ArenaLobbyTimelineScene.Rect
    let hitRegion: ArenaLobbyTimelineScene.Rect

    init(document: ArenaLobbyTimelineDocument, role: Role, title: String, season: Season? = nil) throws {
        let hidden: Set<String>
        var text: [String: String] = [:]
        var progress: [String: Double] = [:]
        var idleLabel = role.idleLabel
        switch role {
        case .profile:
            // Fame/prestige belongs to the original online account, not the
            // local player's save. Keep the original default player badge.
            hidden = ["prestige"]
        case .season:
            guard let season, season.tier >= 0, season.pointsPerTier > 0,
                  (0...season.pointsPerTier).contains(season.points) else {
                throw ArenaLobbyTimelineError.invalid("Source pass requires current saved progression")
            }
            hidden = ["bp_discount", "icon_brawl_pass_plus", "brawl_pass_reward_icon", "notification", "new_season_txt"]
            idleLabel = season.hasReward ? "brawl_pass_ready" : "brawl_pass_inprogress"
            text = ["tier_number_txt": String(season.tier), "value_txt": "\(season.points)/\(season.pointsPerTier)"]
            let fraction = Double(season.points) / Double(season.pointsPerTier)
            progress = ["progress_bar": fraction, "progress_bar_ready": fraction]
        case .heroes: hidden = ["notification", "progress_bar", "rarity_icon", "fame_tier_ph"]
        case .team:
            // These source decorations depend on the original service's online
            // counts and XP state. The native party action has no such state.
            hidden = ["notification", "count_txt", "panel_player_online_ph_left",
                      "xp_multiplier", "TID_TEAM_UP_TITLE"]
        case .invite:
            hidden = ["panel_player_online", "button_invite_ranked"]
        case .coins:
            // The unnamed empty source text is an icon-placement placeholder,
            // not the balance. Retain its sibling coin artwork.
            hidden = ["button_coins/#0:"]
        case .trophies:
            // Native trophy totals are real; original-service reward states
            // and its progress thresholds are not supplied by this save.
            hidden = ["progress_bar", "icon_league_reward_big", "notification"]
        case .battle:
            // Reward counters and alternate paid/locked buttons have no native
            // state here. Retain only the actual ordinary-match action.
            hidden = ["party_mode_container", "button_random_reward_6", "button_random_reward_3",
                      "button_random_reward", "brawl_button_roguelite", "competitive_pass_points_button"]
        default: hidden = ["notification"]
        }
        try self.init(document: document, export: role.export, instance: role.instance, title: title,
                      idleLabel: idleLabel, hiddenChildren: hidden,
                      titlePath: role.titlePath,
                      layoutPath: role == .battle ? "brawl_button" : nil,
                      additionalText: text, progress: progress, includeAnimationBounds: role == .season)
    }

    init(document: ArenaLobbyTimelineDocument, export: String, instance: String,
         title: String, idleLabel: String?, hiddenChildren: Set<String>,
         titlePath: String? = "txt", layoutPath: String? = nil,
         additionalText: [String: String] = [:], progress: [String: Double] = [:],
         includeAnimationBounds: Bool = false) throws {
        guard !title.isEmpty, title.utf8.count <= 4096,
              let rootID = document.exports[export]?.objectID,
              !instance.isEmpty else {
            throw ArenaLobbyTimelineError.invalid("Source menu control is missing or ambiguous")
        }
        var text = titlePath.map { [instance + "/" + $0: title] } ?? [:]
        for (path, value) in additionalText { text[instance + "/" + path] = value }
        var state = ArenaLobbyInterfaceState(text: text, frameIndices: ["": 0])
        // Keep the selected instance's ancestor transforms, while hiding each
        // sibling along the path. Shared source objects must stay independent.
        let segments = instance.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var objectID = rootID, parent = ""
        for segment in segments {
            guard !segment.isEmpty, let children = document.objects[String(objectID)]?.children else {
                throw ArenaLobbyTimelineError.invalid("Source menu control path is missing")
            }
            let counts = Dictionary(grouping: children, by: \.name).mapValues(\.count)
            let names = children.enumerated().map { index, child in
                child.name.isEmpty || counts[child.name] != 1 ? "#\(index):\(child.name)" : child.name
            }
            guard let selected = names.firstIndex(of: segment) else {
                throw ArenaLobbyTimelineError.invalid("Source menu control path is missing or ambiguous")
            }
            for name in names where name != segment {
                state.hidden.insert(parent.isEmpty ? name : parent + "/" + name)
            }
            if !parent.isEmpty { state.frameIndices[parent] = 0 }
            parent = parent.isEmpty ? segment : parent + "/" + segment
            objectID = children[selected].objectID
        }
        for child in hiddenChildren { state.hidden.insert(instance + "/" + child) }
        if let idleLabel { state.frames[instance] = idleLabel }
        for (path, fraction) in progress {
            guard fraction.isFinite, (0...1).contains(fraction), !path.isEmpty else {
                throw ArenaLobbyTimelineError.invalid("Invalid source progress fraction")
            }
            var progressID = objectID
            for segment in path.split(separator: "/", omittingEmptySubsequences: false) {
                guard !segment.isEmpty,
                      let children = document.objects[String(progressID)]?.children,
                      children.filter({ $0.name == segment }).count == 1,
                      let child = children.first(where: { $0.name == segment }) else {
                    throw ArenaLobbyTimelineError.invalid("Source progress path is missing or ambiguous")
                }
                progressID = child.objectID
            }
            guard let count = document.objects[String(progressID)]?.frameCount, count > 0 else {
                throw ArenaLobbyTimelineError.invalid("Source progress has no frames")
            }
            state.frameIndices[instance + "/" + path] = Int((fraction * Double(count - 1)).rounded(.down))
        }

        let measured = try ArenaLobbyTimelineScene(document: document, exportName: export, interfaceState: state)
        let frame = try measured.frame(time: 0)
        guard let visual = frame.operations.map(\.bounds).reduce(nil as ArenaLobbyTimelineScene.Rect?, { a,b in
            a.map { $0.union(b) } ?? b
        }) else { throw ArenaLobbyTimelineError.invalid("Source menu control has no visible content") }
        let layoutInstance = layoutPath.map { instance + "/" + $0 } ?? instance
        let declared = frame.layoutRegions[layoutInstance + "/bounds"]
        let hit = frame.layoutRegions[layoutInstance + "/hit_area"] ?? declared ?? visual
        let layout = visual.union(declared ?? visual).union(hit)
        let extent = includeAnimationBounds ? layout.union(try measured.completeContentBounds() ?? layout) : layout
        // Preserve the full source silhouette and antialiasing. No extra native
        // border, rotation or shadow is added on top of the original artwork.
        let crop = ArenaLobbyTimelineScene.Rect([floor(extent.minX)-2, floor(extent.minY)-2,
                                                ceil(extent.maxX)+2, ceil(extent.maxY)+2])
        guard crop.width <= 512, crop.height <= 512 else {
            throw ArenaLobbyTimelineError.invalid("Source menu control exceeds its layout budget")
        }
        scene = try ArenaLobbyTimelineScene(document: document, exportName: export,
                                            sourceRect: crop.values, interfaceState: state)
        bounds = crop
        layoutBounds = ArenaLobbyTimelineScene.Rect([floor(layout.minX)-2, floor(layout.minY)-2,
                                                     ceil(layout.maxX)+2, ceil(layout.maxY)+2])
        hitRegion = hit
    }
}
