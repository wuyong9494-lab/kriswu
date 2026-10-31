import SceneKit

/// Material modifiers shared by the App and its focused renderer checks.
@MainActor
enum ArenaColorGrade {
    static func grade(_ material: SCNMaterial, _ surface: String, fragment: String? = nil) {
        var modifiers = material.shaderModifiers ?? [:]
        let gradeMarker = "// Arena surface grade"
        if let existing = modifiers[.surface] {
            // Imported base-color factors/coverage must run before the style
            // grade; arbitrary existing surface shaders still own their look.
            guard existing.contains(GLTFModel.materialSurfaceMarker), !existing.contains(gradeMarker) else { return }
            modifiers[.surface] = GLTFModel.combiningShaderModifiers(existing, gradeMarker + "\n" + surface)
        } else {
            modifiers[.surface] = gradeMarker + "\n" + surface
        }
        if let fragment, modifiers[.fragment] == nil {
            modifiers[.fragment] = fragment
        }
        material.shaderModifiers = modifiers
    }

    // Screen-ray stipple discards the SAME samples in every mesh layer. Remaining
    // samples keep their material's original alpha/depth behavior. Imported
    // BLEND surfaces must not be forcibly changed into opaque geometry.
    static let concealmentFragment = """
        #pragma arguments
        float arenaConcealment;
        #pragma body
        if (arenaConcealment > 0.001) {
        float2 cell = floor((_surface.position.xy / max(abs(_surface.position.z), 0.001)) * 900.0);
        float pattern = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
        if (pattern < arenaConcealment * 0.58) { discard_fragment(); }
        _output.color.rgb = mix(_output.color.rgb, _output.color.rgb * float3(0.65, 0.88, 1.0), arenaConcealment * 0.65);
        }
        """
}
