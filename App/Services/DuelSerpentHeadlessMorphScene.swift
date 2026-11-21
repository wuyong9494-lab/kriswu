import SceneKit
import UIKit

/// The authenticated D13 GLB has two complete head presentations. Its source
/// scene uses the closed helmet. The personalized scene exchanges that helmet
/// for Liu's supplied, skinned face and neck on the same skeleton.
@MainActor
enum DuelSerpentHeadlessMorphScene {
    struct Selection {
        let instance: GLTFModel.Instance
        let materials: [DuelTriadSourceMorph.MaterialBinding]
    }
    private static let commonMaterials: Set<String> = [
        "mat_arm__agl_41_base", "mat_arm__agl_41_tie_base", "mat_wpn__shuangou_01_04_base"]
    private static let helmetMaterial = "mat_helm__agl_41_base"
    private static let personalMaterials: Set<String> = ["Liu_Neck_Skin", "tripo_mat_c4757646"]

    private static func isReviewed(_ asset: DuelWeaponCharacterAsset, _ instance: GLTFModel.Instance) -> Bool {
        let tail = ["arm__agl_41_m", "arm__agl_41_m_tabard", "arm__agl_41_m_tie_down",
            "arm__agl_41_m_tie_up", "helm__agl_41_m", "wpn__shuangou_01_04__l", "wpn__shuangou_01_04__r",
            "Liu_Neck_Bridge", "Liu_Personal_Head", "SF3_Actor_Meters"]
        return asset.profile.isSerpent && asset.profile.id == "liu_serpent" &&
            asset.profile.sha256 == DuelSerpentAssetIdentity.characterSHA256 &&
            asset.profile.bytes == 15_561_412 && asset.profile.resourceName == "Liu_KingOfSerpents_D13_Recovered_Combat" &&
            asset.model.names.count == 90 && Array(asset.model.names.suffix(10)) == tail &&
            instance.nodes.count == 90 && instance.outlines.isEmpty &&
            instance.root.childNodes.count == 1 && instance.nodes[89].parent === instance.root
    }

    /// Check both skins before committing the swap. A missing/unsupported
    /// portrait leaves the complete source helmet visible, without overlapping meshes.
    static func showPersonalHead(asset: DuelWeaponCharacterAsset, instance: GLTFModel.Instance) -> Bool {
        guard isReviewed(asset, instance) else { return false }
        let outer = instance.nodes[89], helmet = instance.nodes[84]
        guard helmet.parent === outer, helmet.childNodes.first?.geometry != nil else { return false }
        for (index, name) in [(87, "Liu_Neck_Skin"), (88, "tripo_mat_c4757646")] {
            let node = instance.nodes[index]
            guard node.parent == nil, node.childNodes.count == 1, let holder = node.childNodes.first,
                  let skin = holder.skinner, skin.bones.count == 80, skin.skeleton != nil,
                  skin.baseGeometry != nil, skin.boneInverseBindTransforms?.count == skin.bones.count,
                  GLTFModel.skinSources(for: holder) != nil,
                  holder.geometry?.materials.count == 1, let material = holder.geometry?.firstMaterial,
                  material.name == name else { return false }
            if index == 88 && !(material.diffuse.contents is UIImage) { return false }
        }
        helmet.removeFromParentNode()
        outer.addChildNode(instance.nodes[87])
        outer.addChildNode(instance.nodes[88])
        return true
    }

    static func select(asset: DuelWeaponCharacterAsset, instance: GLTFModel.Instance,
                       materials: [DuelTriadSourceMorph.MaterialBinding]) throws -> Selection {
        guard asset.profile.isSerpent else { return Selection(instance: instance, materials: materials) }
        func require(_ condition: Bool) throws {
            guard condition else { throw DuelTriadSourceMorph.Failure.geometry }
        }
        try require(isReviewed(asset, instance))
        let allNames = commonMaterials.union(personalMaterials).union([helmetMaterial])
        try require(materials.count == 6 && Set(materials.map(\.name)) == allNames &&
            instance.materials.count == 6 && Set(instance.materials.compactMap(\.name)) == allNames &&
            Set(instance.materials.map(ObjectIdentifier.init)).count == 6)
        for material in materials {
            try material.validate()
            if personalMaterials.contains(material.name) {
                try require(material.actorBaseGeometry && material.sourceItemType == nil)
            }
        }

        let outer = instance.nodes[89], personal = instance.nodes[84].parent == nil
        let activeNames = personal ? commonMaterials.union(personalMaterials) : commonMaterials.union([helmetMaterial])
        var activeHolders: [SCNNode] = []
        for index in 80...88 {
            let node = instance.nodes[index]
            let active = index == 84 ? !personal : index < 87 || personal
            try require(active ? node.parent === outer : node.parent == nil)
            try require(node.childNodes.count == 1)
            let holder = node.childNodes[0]
            try require(holder.geometry != nil && holder.skinner != nil)
            if active { activeHolders.append(holder) }
        }
        var observed: [SCNNode] = []
        instance.root.enumerateChildNodes { node, _ in if node.geometry != nil { observed.append(node) } }
        try require(instance.root.geometry == nil && observed.count == activeHolders.count &&
            Set(observed.map(ObjectIdentifier.init)) == Set(activeHolders.map(ObjectIdentifier.init)))
        let active = activeHolders.flatMap { $0.geometry?.materials ?? [] }
        try require(active.count == activeHolders.count && Set(active.compactMap(\.name)) == activeNames)
        let activeIDs = Set(active.map(ObjectIdentifier.init))
        let selected = instance.materials.filter { activeIDs.contains(ObjectIdentifier($0)) }
        try require(selected.count == activeNames.count && Set(selected.compactMap(\.name)) == activeNames)
        return Selection(instance: .init(root: instance.root, nodes: instance.nodes,
                materials: selected, outlines: instance.outlines),
            materials: materials.filter { activeNames.contains($0.name) })
    }
}
