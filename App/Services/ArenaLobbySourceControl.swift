import Foundation

/// Select a complete source button, including its label and background. The
/// application supplies the title and action; source placeholders are never used.
struct ArenaLobbySourceControl {
    enum Role: String, CaseIterable, Sendable {
        case shop, heroes, friends, quests, battle

        var export: String {
            switch self {
            case .shop, .heroes: return "mainscreen_hud_left"
            case .friends: return "mainscreen_hud_right"
            case .quests: return "mainscreen_hud_bottom_left"
            case .battle: return "mainscreen_hud_bottom_right"
            }
        }
        var idleLabel: String? {
            switch self { case .shop, .heroes: return "idle"; case .friends, .battle: return nil; case .quests: return "default" }
        }
        var instance: String {
            switch self {
            case .shop: return "button_navi_shop"
            case .heroes: return "button_navi_brawlers"
            case .friends: return "button_navi_friends"
            case .quests: return "button_quests"
            case .battle: return "brawl_container"
            }
        }
        var title: String {
            switch self { case .shop: return "商店"; case .heroes: return "英雄"; case .friends: return "好友"; case .quests: return "任务"; case .battle: return "对战" }
        }
    }

    let scene: ArenaLobbyTimelineScene
    /// Source coordinates, not an assumed full-screen reference resolution.
    let bounds: ArenaLobbyTimelineScene.Rect
    let hitRegion: ArenaLobbyTimelineScene.Rect

    init(document: ArenaLobbyTimelineDocument, role: Role, title: String) throws {
        let hidden: Set<String>
        switch role {
        case .heroes: hidden = ["notification", "progress_bar", "rarity_icon", "fame_tier_ph"]
        case .battle:
            // Reward counters and alternate paid/locked buttons have no native
            // state here. Retain only the actual ordinary-match action.
            hidden = ["party_mode_container", "button_random_reward_6", "button_random_reward_3",
                      "button_random_reward", "brawl_button_roguelite", "competitive_pass_points_button"]
        default: hidden = ["notification"]
        }
        try self.init(document: document, export: role.export, instance: role.instance, title: title,
                      idleLabel: role.idleLabel, hiddenChildren: hidden,
                      titlePath: role == .battle ? "brawl_button/txt" : "txt",
                      layoutPath: role == .battle ? "brawl_button" : nil)
    }

    init(document: ArenaLobbyTimelineDocument, export: String, instance: String,
         title: String, idleLabel: String?, hiddenChildren: Set<String>,
         titlePath: String = "txt", layoutPath: String? = nil) throws {
        guard !title.isEmpty, title.utf8.count <= 4096,
              let rootID = document.exports[export]?.objectID,
              let children = document.objects[String(rootID)]?.children,
              children.filter({ $0.name == instance }).count == 1,
              !instance.isEmpty else {
            throw ArenaLobbyTimelineError.invalid("Source menu control is missing or ambiguous")
        }
        let counts = Dictionary(grouping: children, by: \.name).mapValues(\.count)
        var state = ArenaLobbyInterfaceState(text: [instance + "/" + titlePath: title], frameIndices: ["": 0])
        for (index, child) in children.enumerated() where child.name != instance {
            state.hidden.insert(child.name.isEmpty || counts[child.name] != 1 ? "#\(index):\(child.name)" : child.name)
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
