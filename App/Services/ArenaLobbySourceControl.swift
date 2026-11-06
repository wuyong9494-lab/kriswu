import Foundation

/// Select a complete source button, including its label and background. The
/// application supplies the title and action; source placeholders are never used.
struct ArenaLobbySourceControl {
    enum Role: String, CaseIterable, Sendable {
        case shop, heroes, friends, quests, battle, team, invite, menu, coins, trophies

        var export: String {
            switch self {
            case .shop, .heroes: return "mainscreen_hud_left"
            case .friends, .team: return "mainscreen_hud_right"
            case .quests: return "mainscreen_hud_bottom_left"
            case .battle: return "mainscreen_hud_bottom_right"
            case .invite: return "mainscreen_center"
            case .menu, .coins: return "mainscreen_hud_top_right"
            case .trophies: return "mainscreen_hud_top_left"
            }
        }
        var idleLabel: String? {
            switch self {
            case .shop, .heroes: return "idle"
            case .friends, .battle, .team, .menu, .coins: return nil
            case .quests: return "default"
            case .invite: return "normal"
            case .trophies: return "trophy_road_inprogress"
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
            }
        }
        var title: String {
            switch self { case .shop: return "商店"; case .heroes: return "英雄"; case .friends: return "好友"; case .quests: return "任务"; case .battle: return "对战"; case .team: return "组队"; case .invite: return "邀请队友"; case .menu: return "设置"; case .coins: return "金币"; case .trophies: return "奖杯" }
        }
        /// Icon-only source controls have no text field. Their native button
        /// still supplies an accessibility title, without inventing source text.
        var titlePath: String? {
            switch self {
            case .battle: return "brawl_button/txt"
            case .invite, .menu: return nil
            case .coins: return "value_txt"
            case .trophies: return "progress_txt"
            default: return "txt"
            }
        }
    }

    struct Values: Equatable, Sendable {
        let coins: Int
        let trophies: Int

        func title(for role: Role) -> String? {
            switch role {
            case .coins: return String(coins)
            case .trophies: return String(trophies)
            default: return nil
            }
        }
    }

    struct Request: Equatable {
        let revision: UUID
        let values: Values
    }

    let scene: ArenaLobbyTimelineScene
    /// Source coordinates, not an assumed full-screen reference resolution.
    let bounds: ArenaLobbyTimelineScene.Rect
    let hitRegion: ArenaLobbyTimelineScene.Rect

    init(document: ArenaLobbyTimelineDocument, role: Role, title: String) throws {
        let hidden: Set<String>
        switch role {
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
                      idleLabel: role.idleLabel, hiddenChildren: hidden,
                      titlePath: role.titlePath,
                      layoutPath: role == .battle ? "brawl_button" : nil)
    }

    init(document: ArenaLobbyTimelineDocument, export: String, instance: String,
         title: String, idleLabel: String?, hiddenChildren: Set<String>,
         titlePath: String? = "txt", layoutPath: String? = nil) throws {
        guard !title.isEmpty, title.utf8.count <= 4096,
              let rootID = document.exports[export]?.objectID,
              !instance.isEmpty else {
            throw ArenaLobbyTimelineError.invalid("Source menu control is missing or ambiguous")
        }
        let text = titlePath.map { [instance + "/" + $0: title] } ?? [:]
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

        let measured = try ArenaLobbyTimelineScene(document: document, exportName: export, interfaceState: state)
        let frame = try measured.frame(time: 0)
        guard let visual = frame.operations.map(\.bounds).reduce(nil as ArenaLobbyTimelineScene.Rect?, { a,b in
            a.map { $0.union(b) } ?? b
        }) else { throw ArenaLobbyTimelineError.invalid("Source menu control has no visible content") }
        let layoutInstance = layoutPath.map { instance + "/" + $0 } ?? instance
        let declared = frame.layoutRegions[layoutInstance + "/bounds"]
        let hit = frame.layoutRegions[layoutInstance + "/hit_area"] ?? declared ?? visual
        let extent = visual.union(declared ?? visual).union(hit)
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
        hitRegion = hit
    }
}
