import XCTest
@testable import ShiftReminder

#if DEBUG
/// Real installed descriptor validation. These checks do not compile Metal,
/// certify rendered effects or establish an unrecovered scene's global setters.
@MainActor
final class DuelTriadRuntimeUniformTests: XCTestCase {
    private typealias Source = DuelTriadSourceMaterial
    private enum Failure: Error { case unapprovedInstalledRevision }
    private struct Materials: Decodable {
        let materials: [String: Source.Descriptor]
    }

    private func installedMaterials() throws -> [String: Source.Descriptor] {
        let releaseSHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
        let effectsSHA = "ce7350283846c370e00df073d2c04146687301c095a1be4b6f19aece982f2435"
        let pin = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String)
        XCTAssertEqual(pin, releaseSHA)
        guard pin == releaseSHA else { throw Failure.unapprovedInstalledRevision }
        let directory = try XCTUnwrap(DuelWeaponAssets.catalogURL()).deletingLastPathComponent()
        let release = try DuelFighterAssetReleaseLoader(directory: directory, expectedSHA256: releaseSHA)
        let file = try XCTUnwrap(release.definition.triadEffects)
        XCTAssertEqual(release.definition.id, "h17-shared-root-floorfall-20261115-v2")
        XCTAssertEqual(file.name, "SF3_H17_Effects.json.gz")
        XCTAssertEqual(file.sha256, effectsSHA)
        guard file.name == "SF3_H17_Effects.json.gz", file.sha256 == effectsSHA else {
            throw Failure.unapprovedInstalledRevision
        }
        let compressed = try DuelFighterAssetReleaseLoader.read(directory: directory, name: file.name,
            maximum: 32_000_000, bytes: file.bytes, hash: effectsSHA)
        let json = try DuelBoundedGzip.decode(compressed, maximum: 256_000_000)
        return try JSONDecoder().decode(Materials.self, from: json).materials
    }

    func testInstalledSourceMaterialsResolveOnlyReviewedUnassignedCustomPosition() throws {
        let materials = try installedMaterials()
        XCTAssertEqual(materials.count, 62)
        var affected = 0
        var shaders = Set<String>()
        for (id, material) in materials.sorted(by: { $0.key < $1.key }) {
            try material.validate()
            let values = try material.materialUniforms()
            XCTAssertEqual(values.count, material.program.uniforms.count, id)
            for (index, uniform) in material.program.uniforms.enumerated() {
                guard uniform.name == "_CustomPos" else { continue }
                affected += 1
                shaders.insert(material.shaderPathID + ":" + material.sourceShaderSHA256)
                XCTAssertEqual(uniform.width, 1, id)
                XCTAssertNil(uniform.defaultValue, id)
                XCTAssertNil(material.floats[uniform.name], id)
                XCTAssertNil(material.colors[uniform.name], id)
                XCTAssertEqual(values[index], SIMD4<Float>.zero, id)
            }
        }
        XCTAssertEqual(affected, 17, "The reviewed installed manifest has 17 unassigned runtime scalars")
        XCTAssertEqual(shaders.count, 7)
    }

    func testUnreviewedMissingUniformsRemainRejectedAndExplicitValuesKeepPriority() throws {
        let materials = try installedMaterials()
        let affected = materials.values.filter { $0.program.uniforms.contains { $0.name == "_CustomPos" } }
        XCTAssertEqual(affected.count, 17)
        for material in affected {
            let changedSHA = String(repeating: "0", count: 64)
            let custom = try XCTUnwrap(material.program.uniforms.first { $0.name == "_CustomPos" })
            let scalar = [Source.Uniform(name: "_CustomPos", width: 1, defaultValue: nil)]
            // Replacing only the uniform list isolates binding from unrelated
            // shader constants while preserving the actual source identity.
            let base = replacing(material, uniforms: scalar, floats: [:], colors: [:])
            XCTAssertThrowsError(try replacing(base, shaderSHA: changedSHA).validate())
            XCTAssertThrowsError(try replacing(base, shaderID: "0").validate())
            XCTAssertThrowsError(try replacing(base, uniforms: [
                .init(name: custom.name, width: 2, defaultValue: nil)
            ]).validate())
            XCTAssertThrowsError(try replacing(base, uniforms: [
                .init(name: "_UnreviewedRuntimeInput", width: 1, defaultValue: nil)
            ]).validate())

            let savedFloat = replacing(base, floats: ["_CustomPos": 2.5],
                colors: ["_CustomPos": [3, 4, 5, 6]])
            try savedFloat.validate()
            XCTAssertEqual(try savedFloat.materialUniforms(), [SIMD4<Float>(2.5, 0, 0, 0)])
            let savedColor = replacing(base, colors: ["_CustomPos": [3, 4, 5, 6]])
            try savedColor.validate()
            XCTAssertEqual(try savedColor.materialUniforms(), [SIMD4<Float>(3, 4, 5, 6)])
            let declared = replacing(base, uniforms: [
                .init(name: "_CustomPos", width: 1, defaultValue: [7, 8, 9, 10])
            ])
            try declared.validate()
            XCTAssertEqual(try declared.materialUniforms(), [SIMD4<Float>(7, 8, 9, 10)])

            // A genuine saved scalar must still fail if both its material
            // value and declared ShaderLab default are removed.
            let original = try XCTUnwrap(material.program.uniforms.first {
                $0.name != "_CustomPos" && $0.width == 1 && material.floats[$0.name] != nil
            })
            XCTAssertThrowsError(try replacing(base, uniforms: [
                .init(name: original.name, width: 1, defaultValue: nil)
            ]).validate())
        }
    }

    private func replacing(_ source: Source.Descriptor, shaderID: String? = nil, shaderSHA: String? = nil,
                           uniforms: [Source.Uniform]? = nil, floats: [String: Float]? = nil,
                           colors: [String: [Float]]? = nil) -> Source.Descriptor {
        .init(sourceName: source.sourceName, shaderPathID: shaderID ?? source.shaderPathID,
            sourceShaderSHA256: shaderSHA ?? source.sourceShaderSHA256, variantSHA256: source.variantSHA256,
            projectColorSpace: source.projectColorSpace, projectAnisotropicFiltering: source.projectAnisotropicFiltering,
            keywords: source.keywords, floats: floats ?? source.floats, colors: colors ?? source.colors,
            textures: source.textures,
            program: .init(file: source.program.file, bytes: source.program.bytes, sha256: source.program.sha256,
                vertexFunction: source.program.vertexFunction, fragmentFunction: source.program.fragmentFunction,
                uniforms: uniforms ?? source.program.uniforms, textures: source.program.textures,
                layoutVersion: source.program.layoutVersion), raster: source.raster)
    }
}
#endif
