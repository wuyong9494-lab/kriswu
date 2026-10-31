import SceneKit

/// The catalog keeps source shader/variables for future adaptation. Only these
/// declared blend intentions are mapped here; this is not the native uber shader.
struct ArenaImportedMaterialOverride: Decodable {
    let name: String
    let sourceBlendMode: Int
    let diffusePremultiplication: String?
    let requiresNonstandardRuntimeBlend: Bool?
}

@MainActor
enum ArenaImportedMaterialAdapter {
    @discardableResult
    static func apply(_ records: [ArenaImportedMaterialOverride], to materials: [SCNMaterial]) -> Set<String> {
        var pending = Set<String>()
        for record in records {
            let matched = materials.filter { $0.name == record.name }
            if matched.isEmpty { pending.insert(record.name); continue }
            for material in matched {
                switch record.sourceBlendMode {
                case 0, 4, 5:
                    // Mode 0 has already crossed the premultiplied-to-straight
                    // boundary in the converter. Mode 5 keeps its source input.
                    material.blendMode = .alpha
                case 1: material.blendMode = .add
                case 2: material.blendMode = .multiply
                case 3: material.blendMode = .screen
                default:
                    // In particular ALPHA_ADDITIVE's native factors are not
                    // established. Keep it visible with an explicit pending flag.
                    pending.insert(record.name)
                }
                if record.sourceBlendMode != 4 { material.writesToDepthBuffer = false }
                if record.requiresNonstandardRuntimeBlend == true { pending.insert(record.name) }
            }
        }
        return pending
    }
}
