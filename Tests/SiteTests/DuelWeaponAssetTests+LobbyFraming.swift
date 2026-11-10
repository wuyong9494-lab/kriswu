import XCTest
import SceneKit
import UIKit
import SwiftUI
import simd
@testable import ShiftReminder

@MainActor
extension DuelWeaponAssetTests {
    func testRealSourceIdleVerticesRemainAboveRailThroughRotationAndHeroSwitch() async throws {
        let assets = try DuelWeaponAssets() // Missing / corrupt real assets must fail, not skip.
        let lobby = DuelLobbySceneView(hero: .ember)
        defer { lobby.shutdown() }
        var sampleCount = 0
        for hero in [DuelGame.Hero.ember, .liu, .ember] {
            autoreleasepool { lobby.select(hero) }
            XCTAssertEqual(lobby.selectedHero, hero)
            let root = try XCTUnwrap(lobby.scene?.rootNode.childNode(
                withName: "duel.lobby.character.\(hero.rawValue)", recursively: false))
            // Only timing metadata is needed here. The lobby itself authenticates
            // and loads the real meshes; do not retain a duplicate model cache.
            let idle = try XCTUnwrap(assets.catalog.profile(for: hero)?.clip(role: "idle"))
            for size in [CGSize(width: 956, height: 440), CGSize(width: 844, height: 390)] {
                lobby.frame = CGRect(origin: .zero, size: size)
                let normalized = CGRect(x: 0.3, y: 0, width: 0.4, height: 0.74)
                lobby.setVisibleRegion(normalized)
                lobby.layoutSubviews()
                autoreleasepool { _ = lobby.snapshot() }
                let clear = CGRect(x: size.width * 0.3 + 2, y: 2,
                                   width: size.width * 0.4 - 4, height: size.height * 0.74 - 4)
                for yaw in [Float.pi, 0, Float.pi / 2, -Float.pi / 2] {
                    lobby.rotatePreview(by: yaw - lobby.yaw)
                    for tick in [0, idle.ticks / 2, idle.ticks - 1] {
                        // Keep one deterministic pose/assertion together, then drain
                        // SceneKit/Foundation temporaries before the next sample.
                        try autoreleasepool {
                            lobby.renderIdle(at: tick)
                            let points = try lobbyWorldVertices(root)
                            XCTAssertGreaterThan(points.count, 100,
                                                 "The assertion must cover the actual meshes, not only bones")
                            var bounds = CGRect.null
                            var clippedDepth = 0
                            for point in points {
                                let native = lobby.projectPoint(SCNVector3(point.x, point.y, point.z))
                                if !native.z.isFinite || native.z <= 0 || native.z >= 1 { clippedDepth += 1 }
                                let location = CGPoint(x: CGFloat(native.x), y: CGFloat(native.y))
                                bounds = bounds.union(CGRect(origin: location, size: CGSize(width: 0.001, height: 0.001)))
                            }
                            XCTAssertEqual(clippedDepth, 0)
                            XCTAssertGreaterThanOrEqual(bounds.minX, clear.minX, "\(hero), yaw \(yaw), tick \(tick)")
                            XCTAssertLessThanOrEqual(bounds.maxX, clear.maxX)
                            XCTAssertGreaterThanOrEqual(bounds.minY, clear.minY)
                            XCTAssertLessThanOrEqual(bounds.maxY, clear.maxY,
                                                     "Actual body, personal head, armor, soles and weapons must clear the rail")
                        }
                        sampleCount += 1
                        print("[lobby-framing] checked sample \(sampleCount)/72 hero=\(hero.rawValue) size=\(Int(size.width))x\(Int(size.height)) yaw=\(yaw) tick=\(tick)")
                        // This view is not in a window, so no idle display link runs.
                        // Suspension services the hosted app without changing the pose.
                        try await Task.sleep(nanoseconds: 1_000_000)
                    }
                }
            }
        }
        XCTAssertEqual(sampleCount, 72, "Every hero/size/facing/idle sample must execute")
    }

    func testRealNavigatedLobbyUsesExactStageCenterAndRailGeometry() async throws {
        _ = try DuelWeaponAssets()
        XCTAssertNotNil(DuelStageAsset.bundledURL(for: .autumnLobby))
        let observed = LobbyFramingObservation()
        // Start at a pushed destination, as the games screen does. This includes
        // real navigation chrome and its safe-area adjustment, not a bare lobby.
        let host = UIHostingController(rootView: NavigatedLobbyFramingFixture(observed: observed))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        window.rootViewController = host
        host.view.frame = window.bounds
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        var preview: DuelLobbySceneView?
        var previous: [DuelLobbyLayoutRegion: CGRect] = [:]
        var stableMeasurements = 0
        // Preference propagation is asynchronous. Observe a settled production
        // layout, rather than injecting the rectangle under test into the view.
        for _ in 0..<80 {
            host.view.layoutIfNeeded()
            preview = lobbyDescendant(DuelLobbySceneView.self, in: host.view)
            stableMeasurements = observed.frames == previous ? stableMeasurements + 1 : 0
            previous = observed.frames
            if stableMeasurements >= 2, preview?.framing != nil,
               observed.frames[.stage] != nil, observed.frames[.center] != nil,
               observed.frames[.rail] != nil { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let navigation = try XCTUnwrap(lobbyDescendant(UINavigationBar.self, in: host.view))
        XCTAssertFalse(navigation.isHidden)
        XCTAssertGreaterThan(navigation.bounds.height, 0)
        let view = try XCTUnwrap(preview)
        defer { view.shutdown() }
        let stage = try XCTUnwrap(observed.frames[.stage])
        let center = try XCTUnwrap(observed.frames[.center])
        let rail = try XCTUnwrap(observed.frames[.rail])
        let region = try XCTUnwrap(view.visibleRegion)
        let fit = try XCTUnwrap(view.framing)
        XCTAssertGreaterThanOrEqual(stableMeasurements, 2)
        XCTAssertEqual(stage.width, view.bounds.width, accuracy: 0.5,
                       "SwiftUI must measure the actual full-screen SceneKit width")
        XCTAssertEqual(stage.height, view.bounds.height, accuracy: 0.5,
                       "Navigation safe-area expansion must agree with the actual SceneKit height")
        XCTAssertGreaterThan(stage.width, 900)
        XCTAssertGreaterThan(stage.height, 350)
        XCTAssertGreaterThan(center.width, 32)
        XCTAssertGreaterThan(center.minY, stage.minY,
                             "The visible center must extend above the side-panel row")
        XCTAssertEqual(rail.minY - center.maxY, 10, accuracy: 0.5,
                       "The opening must stop at the real center/rail layout gap")
        XCTAssertLessThanOrEqual(rail.minX, center.minX)
        XCTAssertGreaterThanOrEqual(rail.maxX, center.maxX)
        XCTAssertLessThanOrEqual(rail.maxY, stage.maxY + 0.5)

        // Map the SceneKit input back into the preference coordinate space. All
        // four edges must match the real center and stage, not broad fractions.
        let opening = CGRect(x: stage.minX + region.minX * view.bounds.width,
                             y: stage.minY + region.minY * view.bounds.height,
                             width: region.width * view.bounds.width,
                             height: region.height * view.bounds.height)
        XCTAssertEqual(opening.minX, center.minX, accuracy: 0.5)
        XCTAssertEqual(opening.maxX, center.maxX, accuracy: 0.5)
        XCTAssertEqual(opening.minY, stage.minY, accuracy: 0.5)
        XCTAssertEqual(opening.maxY, center.maxY, accuracy: 0.5)
        XCTAssertEqual(opening.maxY, rail.minY - 10, accuracy: 0.5)
        let fittedBottom = stage.minY + fit.visibleRegion.maxY * view.bounds.height
        XCTAssertEqual(fittedBottom, rail.minY - 18, accuracy: 0.5,
                       "The camera adds its 8-point margin above the 10-point rail gap")

        _ = view.snapshot()
        for point in DuelLobbyFraming.envelope {
            let native = view.projectPoint(SCNVector3(Float(point.x), Float(point.y), Float(point.z)))
            let nativeInLayout = CGPoint(x: stage.minX + CGFloat(native.x),
                                         y: stage.minY + CGFloat(native.y))
            XCTAssertTrue(opening.insetBy(dx: 7.9, dy: 7.9).contains(nativeInLayout),
                          "Native body/pedestal allowance must clear the actual navigated controls")
            XCTAssertLessThan(nativeInLayout.y, rail.minY)
        }
        // Also project the real selected actor into this measured opening, so
        // manually supplied regions in the rotation test are not the only gate.
        let selected = try XCTUnwrap(view.selectedHero)
        let root = try XCTUnwrap(view.scene?.rootNode.childNode(
            withName: "duel.lobby.character.\(selected.rawValue)", recursively: false))
        let vertices = try lobbyWorldVertices(root)
        XCTAssertGreaterThan(vertices.count, 100)
        var actorBounds = CGRect.null
        for point in vertices {
            let native = view.projectPoint(SCNVector3(point.x, point.y, point.z))
            let inLayout = CGPoint(x: stage.minX + CGFloat(native.x), y: stage.minY + CGFloat(native.y))
            actorBounds = actorBounds.union(CGRect(origin: inLayout, size: CGSize(width: 0.001, height: 0.001)))
        }
        XCTAssertTrue(opening.insetBy(dx: 2, dy: 2).contains(actorBounds),
                      "The real selected actor must clear the actual navigation/rail layout")
    }

    private func lobbyDescendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let found = view as? T { return found }
        return view.subviews.lazy.compactMap { self.lobbyDescendant(type, in: $0) }.first
    }

    /// Evaluate every original skinned vertex using the imported inverse binds.
    /// Static personal meshes are transformed by their real node hierarchy.
    /// This is independent of the authored fit envelope and the core projection.
    private func lobbyWorldVertices(_ root: SCNNode) throws -> [SIMD3<Float>] {
        var holders: [SCNNode] = []
        root.enumerateChildNodes { node, _ in
            if node.geometry != nil, !node.isHidden { holders.append(node) }
        }
        var points: [SIMD3<Float>] = []
        for node in holders {
            let geometry = node.skinner?.baseGeometry ?? node.geometry
            guard let positions = geometry?.sources(for: .vertex).first else { continue }
            XCTAssertTrue(positions.usesFloatComponents)
            XCTAssertEqual(positions.bytesPerComponent, 4)
            let positionData = positions.data
            let positionOffset = positions.dataOffset, positionStride = positions.dataStride
            let vertexCount = positions.vectorCount
            points.reserveCapacity(points.count + vertexCount)
            if let skin = node.skinner {
                let inverse = try XCTUnwrap(skin.boneInverseBindTransforms)
                XCTAssertEqual(skin.bones.count, inverse.count)
                // These transforms are deliberately recomputed for every pose.
                let matrices = zip(skin.bones, inverse).map { bone, value -> simd_float4x4 in
                    let m = value.scnMatrix4Value
                    let bind = simd_float4x4(columns: (SIMD4(m.m11, m.m12, m.m13, m.m14),
                        SIMD4(m.m21, m.m22, m.m23, m.m24), SIMD4(m.m31, m.m32, m.m33, m.m34),
                        SIMD4(m.m41, m.m42, m.m43, m.m44)))
                    return bone.simdWorldTransform * bind
                }
                let indices = skin.boneIndices, weights = skin.boneWeights
                XCTAssertEqual(indices.bytesPerComponent, 2)
                XCTAssertTrue(weights.usesFloatComponents)
                XCTAssertEqual(weights.bytesPerComponent, 4)
                let indexData = indices.data, weightData = weights.data
                let indexOffset = indices.dataOffset, indexStride = indices.dataStride
                let weightOffset = weights.dataOffset, weightStride = weights.dataStride
                let componentCount = weights.componentsPerVector
                // Obtain each Objective-C-backed data source once per mesh, not
                // once per vertex component. All byte pointers stay in scope.
                positionData.withUnsafeBytes { (positionBytes: UnsafeRawBufferPointer) in
                    indexData.withUnsafeBytes { (indexBytes: UnsafeRawBufferPointer) in
                        weightData.withUnsafeBytes { (weightBytes: UnsafeRawBufferPointer) in
                            for vertex in 0..<vertexCount {
                                let offset = positionOffset + vertex * positionStride
                                let local = SIMD4(lobbyFloat(positionBytes, offset),
                                    lobbyFloat(positionBytes, offset + 4), lobbyFloat(positionBytes, offset + 8), 1)
                                var world = SIMD4<Float>.zero
                                for component in 0..<componentCount {
                                    let index = Int(UInt16(littleEndian: indexBytes.loadUnaligned(
                                        fromByteOffset: indexOffset + vertex * indexStride + component * 2,
                                        as: UInt16.self)))
                                    guard matrices.indices.contains(index) else {
                                        XCTFail("Source joint index is outside the imported skeleton")
                                        continue
                                    }
                                    let weight = lobbyFloat(weightBytes, weightOffset + vertex * weightStride + component * 4)
                                    world += weight * (matrices[index] * local)
                                }
                                points.append(SIMD3(world.x, world.y, world.z))
                            }
                        }
                    }
                }
            } else {
                let transform = node.simdWorldTransform
                positionData.withUnsafeBytes { (positionBytes: UnsafeRawBufferPointer) in
                    for vertex in 0..<vertexCount {
                        let offset = positionOffset + vertex * positionStride
                        let world = transform * SIMD4(lobbyFloat(positionBytes, offset),
                            lobbyFloat(positionBytes, offset + 4), lobbyFloat(positionBytes, offset + 8), 1)
                        points.append(SIMD3(world.x, world.y, world.z))
                    }
                }
            }
        }
        return points
    }

    private func lobbyFloat(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> Float {
        Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
    }
}

@MainActor
private final class LobbyFramingObservation {
    var frames: [DuelLobbyLayoutRegion: CGRect] = [:]
}

@MainActor
private struct NavigatedLobbyFramingFixture: View {
    @State private var path = ["fighter"]
    let observed: LobbyFramingObservation

    var body: some View {
        NavigationStack(path: $path) {
            Text("游戏")
                .navigationTitle("游戏")
                .navigationDestination(for: String.self) { _ in
                    DuelHomeView()
                        .environment(\.dynamicTypeSize, .large)
                        .onPreferenceChange(DuelLobbyLayoutFrames.self) { frames in
                            Task { @MainActor in observed.frames = frames }
                        }
                }
        }
    }
}
