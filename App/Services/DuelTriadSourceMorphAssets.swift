import Foundation
import Metal

/// Independently authenticated source HideModel/Morph bindings. The source
/// owner and the affected enemy are different profiles; no filename heuristic
/// or owner's material defaults can select the target's equipment.
@MainActor
final class DuelTriadSourceMorphAssets {
    enum Failure: Error { case identity, manifest, materials }
    struct Trigger: Decodable {
        let clip: String
        let sourceClipSHA256: String
        let sourceFrame: Int
        let triggerTick: Int
        let transitionTicks: Int
        let normalRenderBoundaries: Int
    }
    private struct Document: Decodable {
        let version: Int
        let ownerProfileID: String
        let ownerCharacterSHA256: String
        let targetProfileID: String
        let targetCharacterSHA256: String
        let sourceConfigurationSHA256: String
        let evidence: [String]
        let trigger: Trigger
        let mask: DuelTriadSourceMorph.Mask
        let materials: [DuelTriadSourceMorph.MaterialBinding]
    }

    let ownerProfileID: String
    let targetProfileID: String
    let targetCharacterSHA256: String
    let trigger: Trigger
    let mask: DuelTriadSourceMorph.Mask
    let materials: [DuelTriadSourceMorph.MaterialBinding]
    let verifiedFiles: [DuelNetworkContentRecord]
    private let maskData: Data

    init(directory: URL, manifestName: String, expectedSHA256: String,
         owner: DuelWeaponProfile, target: DuelWeaponProfile) throws {
        let documentData = try DuelFighterAssetReleaseLoader.read(directory: directory,
            name: manifestName, maximum: 256_000, hash: expectedSHA256)
        let document = try JSONDecoder().decode(Document.self, from: documentData)
        guard document.version == 1, owner.isTriad, target.id == "liu_hammers",
              owner.hero == .ember, target.hero == .liu,
              document.ownerProfileID == owner.id, document.ownerCharacterSHA256 == owner.sha256,
              document.targetProfileID == target.id, document.targetCharacterSHA256 == target.sha256,
              target.sha256 == "f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472",
              target.bodyID == "arm__str_03", target.weaponID == "wpn__hammers_01_01",
              document.sourceConfigurationSHA256 == "02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a",
              owner.triadRules?.runtime?.configurationSHA256 == document.sourceConfigurationSHA256,
              DuelTriadStanceState.accepts(owner) else { throw Failure.identity }
        let trigger = document.trigger
        guard manifestName.hasSuffix(".json"),
              (1...32).contains(document.evidence.count),
              document.evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              trigger.clip == DuelTriadStanceState.Motion.win.clip,
              trigger.sourceClipSHA256 == DuelTriadStanceState.Motion.win.sourceSHA256,
              trigger.sourceFrame == 36, trigger.triggerTick == 70,
              trigger.transitionTicks == 140, trigger.normalRenderBoundaries == 1 else {
            throw Failure.manifest
        }
        let mask = document.mask
        guard mask.file == "SF3_H17_MorphMask.texture", mask.bytes == 32_768,
              mask.sha256 == "f5572cfbbe87bd2feb2e9aa93843815b0acdf1b71c0dd7ab584df24ce3ede514",
              mask.width == 256, mask.height == 256, mask.sourceTextureFormat == 45,
              mask.sourceColorSpace == 0, mask.mip == 1, mask.filter == 1,
              mask.wrapS == 0, mask.wrapT == 0 else { throw Failure.manifest }

        let expectedNames: Set<String> = ["mat_arm__str_03_base", "mat_wpn__hammers_01_01_base",
            "Liu_Neck_Skin", "tripo_mat_c4757646"]
        guard document.materials.count == expectedNames.count,
              Set(document.materials.map(\.name)) == expectedNames else { throw Failure.materials }
        func equal(_ actual: [Float], _ expected: [Float]) -> Bool {
            actual.count == expected.count && zip(actual, expected).allSatisfy { pair in
                pair.0.isFinite && abs(pair.0 - pair.1) <= 0.0000001
            }
        }
        for material in document.materials {
            let weapon = material.name == "mat_wpn__hammers_01_01_base"
            let base = material.name == "Liu_Neck_Skin" || material.name == "tripo_mat_c4757646"
            guard material.actorBaseGeometry == base,
                  material.sourceItemType == (base ? nil : weapon ? 3 : 2),
                  material.tile.isFinite, abs(material.tile - (weapon ? 0.1 : 0.2)) <= 0.0000001,
                  material.edgeSize.isFinite, abs(material.edgeSize - 0.1) <= 0.0000001,
                  equal(material.edgeStart, weapon ? [0, 26.0 / 255, 146.0 / 255, 1] : [0, 0, 0, 1]),
                  equal(material.edgeEnd, weapon ? [0, 237.0 / 255, 244.0 / 255, 1] : [0, 87.0 / 255, 96.0 / 255, 1]) else {
                throw Failure.materials
            }
        }
        // a154 also visits the actor's base models after a non-Weapon filter.
        // The accepted personal replacement geometry follows that base-model
        // branch; it is not assigned a fictional source equipment ItemType.
        let data = try DuelFighterAssetReleaseLoader.read(directory: directory, name: mask.file,
            maximum: mask.bytes, bytes: mask.bytes, hash: mask.sha256)
        ownerProfileID = document.ownerProfileID; targetProfileID = document.targetProfileID
        targetCharacterSHA256 = document.targetCharacterSHA256; self.trigger = trigger
        self.mask = mask; materials = document.materials; maskData = data
        verifiedFiles = [
            .init(path: manifestName, bytes: documentData.count, sha256: expectedSHA256),
            .init(path: mask.file, bytes: data.count, sha256: mask.sha256)
        ]
    }

    func prepare(device: MTLDevice?) throws -> DuelTriadSourceMorph.Prepared {
        guard let device else { throw Failure.manifest }
        return try DuelTriadSourceMorph.prepare(mask: mask, data: maskData, device: device)
    }
}
