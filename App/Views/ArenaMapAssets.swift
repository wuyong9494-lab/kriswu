import SceneKit
import UIKit
import simd

/// Each playable arena has a deliberate selection from the existing source packs.
/// These choices change presentation only; ArenaMap remains the collision authority.
enum ArenaMapAssets {
    struct Palette: Sendable {
        let id: String
        let crates: [String]
        let barrels: [String]
        let stones: [String]
        let landmarks: [String]
        let edging: [String]
        let details: [String]
        let paving: String
        var pavingIsWood = false

        var files: Set<String> {
            Set(crates + barrels + stones + landmarks + edging + details + [paving])
        }

        func wall(_ kind: ArenaArt.Wall, variant: Int) -> String {
            let choices: [String]
            switch kind {
            // Legacy sand/meadow/dusk selectors generated only wooden walls.
            // A deterministic accent makes their configured rock/stone assets
            // appear in actual solid cells as well, without adding obstacles.
            case .crate: choices = variant.isMultiple(of: 3) ? stones : crates
            case .barrel: choices = barrels
            case .stone: choices = stones
            }
            return choices[variant % choices.count]
        }
    }

    static let wallLimit = 24
    static let borderLimit = 10
    static let detailLimit = 16

    // Names are unique bundle resources; glTF dependencies are embedded in these GLBs.
    private static let crate = "vendor_crates.glb"
    private static let barrel = "vendor_barrel.glb"
    private static let barrelStack = "vendor_barrel_stack.glb"
    private static let stone = "vendor_stone_block.glb"
    private static let sandstone = "vendor_sandstone_block.glb"
    private static let rubble = "vendor_rubble.glb"
    private static let log = "vendor_log_stack.glb"
    private static let stump = "vendor_stump.glb"
    private static let flatRock = "vendor_flat_rock.glb"
    private static let flowerYellow = "vendor_flower_yellow.glb"
    private static let flowerPurple = "vendor_flower_purple.glb"
    private static let leaves = "vendor_ground_leaves.glb"
    private static let mushroom = "vendor_mushrooms.glb"
    private static let path = "vendor_stone_path.glb"
    private static let circlePath = "vendor_stone_circle.glb"
    private static let paving = "vendor_floor_stone.glb"
    private static let brokenPaving = "vendor_floor_broken.glb"
    private static let woodPaving = "vendor_floor_wood.glb"

    private static func make(_ id: String, stones: [String], landmarks: [String],
                             edging: [String], details: [String], paving: String,
                             wood: Bool = false, stacked: Bool = false) -> Palette {
        Palette(id: id, crates: [crate], barrels: stacked ? [barrel, barrelStack] : [barrel],
                stones: stones, landmarks: landmarks, edging: edging,
                details: details, paving: paving, pavingIsWood: wood)
    }

    /// Expanded layouts inherit their parent arena's material identity.
    static let palettes: [String: Palette] = [
        "canyon": make("canyon", stones: [sandstone],
            landmarks: ["vendor_cactus_tall.glb", "vendor_cactus_short.glb"],
            edging: ["vendor_desert_rock.glb", flatRock], details: [flatRock], paving: path),
        "crossroads": make("crossroads", stones: [stone, rubble],
            landmarks: ["vendor_tree_autumn.glb", "vendor_tree_dark.glb"],
            edging: [log, stump], details: [leaves, mushroom], paving: brokenPaving),
        "fortress": make("fortress", stones: [stone],
            landmarks: ["vendor_pillar.glb", "vendor_column_ruin.glb"],
            edging: [rubble, "vendor_rock.glb"], details: [flatRock], paving: paving),
        "garden": make("garden", stones: [stone],
            landmarks: ["vendor_tree.glb", "vendor_tree_autumn.glb"],
            edging: ["vendor_bush.glb", flowerYellow],
            details: [flowerYellow, flowerPurple], paving: circlePath),
        "plaza": make("plaza", stones: [sandstone],
            landmarks: ["vendor_palm.glb", "vendor_cactus_short.glb"],
            edging: [flatRock, "vendor_rock.glb"], details: [flatRock], paving: paving, stacked: true),
        "ruins": make("ruins", stones: [stone, rubble],
            landmarks: ["vendor_column_ruin.glb", "vendor_obelisk.glb"],
            edging: [rubble, stump], details: [leaves, flatRock], paving: brokenPaving),
        "grove": make("grove", stones: [stone],
            landmarks: ["vendor_pine.glb", "vendor_tree_dark.glb"],
            edging: [log, stump], details: [mushroom, leaves], paving: path),
        "pitch": make("pitch", stones: [stone],
            landmarks: ["vendor_tree.glb", "vendor_pine.glb"],
            edging: ["vendor_bush.glb", flowerYellow], details: [flowerYellow, leaves], paving: circlePath),
        "sandPitch": make("sandPitch", stones: [sandstone],
            landmarks: ["vendor_palm.glb", "vendor_cactus_tall.glb"],
            edging: [flatRock, "vendor_desert_rock.glb"], details: [flatRock], paving: path),
        "vault": make("vault", stones: [stone],
            landmarks: ["vendor_pillar.glb", "vendor_obelisk.glb"],
            edging: [barrelStack, "vendor_rock.glb"], details: [flatRock], paving: paving, stacked: true),
        "cove": make("cove", stones: [sandstone],
            landmarks: ["vendor_palm.glb", "vendor_palm.glb"],
            edging: [barrelStack, log], details: [flatRock, leaves], paving: woodPaving, wood: true, stacked: true),
        "ring": make("ring", stones: [stone],
            landmarks: ["vendor_tree_autumn.glb", "vendor_pillar.glb"],
            edging: [rubble, log], details: [leaves, flatRock], paving: paving),
        "glade": make("glade", stones: [stone],
            landmarks: ["vendor_tree.glb", "vendor_pine.glb"],
            edging: [stump, "vendor_bush.glb"], details: [flowerPurple, mushroom], paving: circlePath),
        "lair": make("lair", stones: [stone, rubble],
            landmarks: ["vendor_obelisk.glb", "vendor_column_ruin.glb"],
            edging: [rubble, "vendor_tree_dark.glb"], details: [mushroom, flatRock], paving: brokenPaving),
        "twin_gates_sample_v1": make("twin_gates_sample_v1", stones: [stone],
            landmarks: ["vendor_palm.glb", "vendor_pillar.glb"],
            edging: [barrelStack, log], details: [leaves, flatRock], paving: woodPaving, wood: true, stacked: true),
    ]

    static func baseID(_ id: String) -> String {
        let suffix = "_expanded_v2"
        return id.hasSuffix(suffix) ? String(id.dropLast(suffix.count)) : id
    }

    static func palette(for map: ArenaMap) -> Palette {
        if let configured = palettes[baseID(map.id)] { return configured }
        // Custom/editor arenas receive a complete palette without changing their tile data.
        let fallback: String
        switch map.theme {
        case .sand: fallback = "canyon"
        case .meadow: fallback = "garden"
        case .stone: fallback = "fortress"
        case .dusk: fallback = "crossroads"
        }
        return palettes[fallback]!
    }

    static let propFiles: [String] = Array(palettes.values.reduce(into: Set<String>()) {
        $0.formUnion($1.files)
    }).sorted()

    struct DetailPlacement: Sendable {
        let x: Int
        let y: Int
        let dx: Float
        let dz: Float
        let paving: Bool
    }

    /// Low decoration stays on ordinary floor next to existing walls. It never
    /// replaces concealment grass, a spawn, a goal, a chest or the central objective.
    static func detailPlacements(in map: ArenaMap) -> [DetailPlacement] {
        guard map.width > 4, map.height > 4 else { return [] }
        let spawns = map.spawns.flatMap { $0 }
        let objectives = [map.center] + map.chestSpots.map(\.center) + map.goalCenters.compactMap { $0 }
        var eligible: [(x: Int, y: Int, dx: Float, dz: Float)] = []
        for y in 2..<(map.height - 2) {
            for x in 2..<(map.width - 2) where map.tile(x, y) == .floor {
                let point = V2(Double(x) + 0.5, Double(y) + 0.5)
                guard !spawns.contains(where: { ($0 - point).length < 2.5 }),
                      !objectives.contains(where: { ($0 - point).length < 2.5 }) else { continue }
                let adjacent = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                guard let edge = adjacent.first(where: {
                    map.tile(x + $0.0, y + $0.1) == .wall && !map.isChest(x + $0.0, y + $0.1)
                }) else { continue }
                eligible.append((x, y, Float(edge.0) * 0.28, Float(edge.1) * 0.28))
            }
        }
        let count = min(detailLimit, eligible.count)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let cell = eligible[index * eligible.count / count]
            let paving = index.isMultiple(of: 2)
            return DetailPlacement(x: cell.x, y: cell.y, dx: paving ? 0 : cell.dx,
                                   dz: paving ? 0 : cell.dz, paving: paving)
        }
    }

    static func woodPavingCells(in map: ArenaMap) -> Set<Int> {
        guard palette(for: map).pavingIsWood else { return [] }
        return Set(detailPlacements(in: map).filter(\.paving).map { $0.y * map.width + $0.x })
    }

    @MainActor static func scenery(_ map: ArenaMap) -> SCNNode {
        let palette = palette(for: map)
        let root = border(palette, width: Float(map.width), height: Float(map.height))
        root.name = "vendor-map-scenery-" + palette.id
        let placements = detailPlacements(in: map)
        let slab = ArenaVendorAssets.prop(palette.paving, width: 0.88, height: 0.012, flatten: true)
        let details = palette.details.compactMap { ArenaVendorAssets.prop($0, width: 0.30, height: 0.16) }
        for (index, place) in placements.enumerated() {
            let template = place.paving ? slab : (details.isEmpty ? nil : details[(index / 2) % details.count])
            guard let template else { continue }
            let node = template.clone()
            node.name = (place.paving ? "vendor-paving-" : "vendor-ground-detail-") + "\(place.x)-\(place.y)"
            node.simdPosition = SIMD3(Float(place.x) + 0.5 + place.dx, 0.004,
                                     Float(place.y) + 0.5 + place.dz)
            // Right-angle rotations preserve the cell envelope.
            node.simdEulerAngles.y = Float((place.x * 7 + place.y * 3) % 4) * .pi / 2
            node.castsShadow = false
            root.addChildNode(node)
        }
        return root
    }

    @MainActor private static func border(_ palette: Palette, width: Float, height: Float) -> SCNNode {
        let root = SCNNode()
        let trees = palette.landmarks.compactMap { ArenaVendorAssets.prop($0, width: 1.1, height: 1.8) }
        let edging = palette.edging.compactMap { ArenaVendorAssets.prop($0, width: 0.8, height: 0.7) }
        if !trees.isEmpty {
            for (index, x) in [Float(2), width / 2, width - 2].enumerated() {
                for z in [Float(-1.5), height + 1.5] {
                    let node = trees[index % trees.count].clone()
                    node.simdPosition = SIMD3(x, 0, z)
                    root.addChildNode(node)
                }
            }
        }
        if !edging.isEmpty {
            for x in [Float(-0.9), width + 0.9] {
                for (index, z) in [height * 0.25, height * 0.75].enumerated() {
                    let node = edging[index % edging.count].clone()
                    node.simdPosition = SIMD3(x, 0, z)
                    root.addChildNode(node)
                }
            }
        }
        return root
    }
}
