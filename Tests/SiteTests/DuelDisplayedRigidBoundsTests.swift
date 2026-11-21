import Foundation
import XCTest
import SceneKit
import simd
@testable import ShiftReminder

/// Isolated geometry-math regressions. These tiny test triangles are never
/// represented as recovered characters, source motions or private acceptance.
@MainActor
final class DuelDisplayedRigidBoundsTests: XCTestCase {
    private let vertices = [SCNVector3(-0.4, -0.3, -0.2), SCNVector3(0.6, -0.3, 0.5),
                            SCNVector3(0.6, 0.7, 0.5), SCNVector3(-0.4, 0.7, -0.2)]

    private func geometry(_ points: [SCNVector3]? = nil) -> SCNGeometry {
        SCNGeometry(sources: [SCNGeometrySource(vertices: points ?? vertices)],
            elements: [SCNGeometryElement(indices: [UInt16(0), 1, 2, 0, 2, 3], primitiveType: .triangles)])
    }

    private func assertRigidEnvelope(_ points: [SIMD3<Float>], holder: SCNNode, camera: SCNNode,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(points.count, 16, file: file, line: line)
        guard points.count == 16 else { return }
        for index in 0..<8 {
            let corner = SCNVector3(index & 1 == 0 ? -0.4 : 0.6,
                index & 2 == 0 ? -0.3 : 0.7, index & 4 == 0 ? -0.2 : 0.5)
            // Use SceneKit's own coordinate conversion, independently of the
            // cache's SIMD matrix path, after nested scale/rotation/translation.
            let native = holder.convertPosition(corner, to: camera)
            for endpoint in 0..<2 {
                let actual = points[index * 2 + endpoint]
                XCTAssertEqual(actual.x, native.x, accuracy: 0.00001, file: file, line: line)
                XCTAssertEqual(actual.y, native.y, accuracy: 0.00001, file: file, line: line)
                XCTAssertEqual(actual.z, native.z, accuracy: 0.00001, file: file, line: line)
            }
        }
    }

    func testRigidHeadEnvelopeFollowsNestedTransformsAndVisibility() throws {
        let root = SCNNode(), headBone = SCNNode(), holder = SCNNode(geometry: geometry()), camera = SCNNode()
        root.addChildNode(headBone); headBone.addChildNode(holder)
        root.simdPosition = SIMD3(1, -0.2, 0.3)
        root.simdScale = SIMD3(1.2, 0.8, 1.1)
        headBone.simdPosition = SIMD3(0, 2.1, 0)
        headBone.simdOrientation = simd_quatf(angle: 0.37, axis: SIMD3(0, 1, 0))
        holder.simdPosition = SIMD3(-0.1, 0.2, 0.05)
        camera.simdPosition = SIMD3(-0.6, 0.4, 9)
        camera.simdOrientation = simd_quatf(angle: -0.12, axis: SIMD3(0, 1, 0))
        let originalGeometry = try XCTUnwrap(holder.geometry)
        let bounds = try DuelDisplayedSkinBounds(root: root)
        let initial = try bounds.cameraPoints(camera: camera)
        assertRigidEnvelope(initial, holder: holder, camera: camera)
        headBone.simdOrientation = simd_quatf(angle: -0.63, axis: simd_normalize(SIMD3(1, 1, 0)))
        headBone.position.y += 0.7
        camera.position.x += 0.4
        let moved = try bounds.cameraPoints(camera: camera)
        assertRigidEnvelope(moved, holder: holder, camera: camera)
        XCTAssertNotEqual(initial, moved)
        XCTAssertTrue(holder.geometry === originalGeometry)
        XCTAssertNil(holder.skinner)
        headBone.isHidden = true
        XCTAssertTrue(try bounds.cameraPoints(camera: camera).isEmpty)
        headBone.isHidden = false
        root.opacity = 0
        XCTAssertTrue(try bounds.cameraPoints(camera: camera).isEmpty)
        root.opacity = 0.5
        assertRigidEnvelope(try bounds.cameraPoints(camera: camera), holder: holder, camera: camera)
    }

    func testTwoActorsAppendInOrderAndClearHiddenPreviousFramePoints() throws {
        let camera = SCNNode()
        camera.position.z = 8
        let first = SCNNode(geometry: geometry()), second = SCNNode(geometry: geometry())
        first.position.x = -1
        second.position.x = 2
        let a = try DuelDisplayedSkinBounds(root: first), b = try DuelDisplayedSkinBounds(root: second)
        var points: [SIMD3<Float>] = []
        func collect() throws {
            points.removeAll(keepingCapacity: true)
            let view = simd_inverse(camera.simdWorldTransform)
            try a.appendCameraPoints(view: view, to: &points)
            try b.appendCameraPoints(view: view, to: &points)
        }
        try collect()
        XCTAssertEqual(points.count, 32)
        assertRigidEnvelope(Array(points.prefix(16)), holder: first, camera: camera)
        assertRigidEnvelope(Array(points.suffix(16)), holder: second, camera: camera)
        first.isHidden = true
        camera.position.x = -2
        try collect()
        assertRigidEnvelope(points, holder: second, camera: camera)
    }

    func testRigidHeadAndSkinnedBodyKeepSeparateCompleteEnvelopes() throws {
        let root = SCNNode(), bone = SCNNode(), camera = SCNNode()
        let bodyGeometry = geometry(), body = SCNNode(geometry: bodyGeometry)
        let head = SCNNode(geometry: geometry())
        root.addChildNode(bone); root.addChildNode(body); bone.addChildNode(head)
        head.position.y = 4
        camera.position.z = 10
        let weights: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        let indices = [UInt16](repeating: 0, count: 16)
        let weightSource = SCNGeometrySource(data: weights.withUnsafeBytes { Data($0) }, semantic: .boneWeights,
            vectorCount: 4, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
            dataOffset: 0, dataStride: 16)
        let indexSource = SCNGeometrySource(data: indices.withUnsafeBytes { Data($0) }, semantic: .boneIndices,
            vectorCount: 4, usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 2,
            dataOffset: 0, dataStride: 8)
        GLTFModel.installSkinner(on: body, geometry: bodyGeometry, bones: [bone],
            inverseBinds: [NSValue(scnMatrix4: SCNMatrix4Identity)], weights: weightSource,
            indices: indexSource, skeleton: bone)
        let originalSkin = try XCTUnwrap(body.skinner)
        let bounds = try DuelDisplayedSkinBounds(root: root)
        let complete = try bounds.cameraPoints(camera: camera)
        XCTAssertEqual(complete.count, 32)
        XCTAssertEqual(DuelDisplayedSkinBounds.artworkRectangles(points: complete,
            size: CGSize(width: 960, height: 480), verticalFieldOfView: 70).count, 2)
        let completeFOV = try DuelDisplayedSkinBounds.verticalFOV(points: complete, aspect: 2, minimum: 1, near: 0.1)
        head.isHidden = true
        let bodyOnly = try bounds.cameraPoints(camera: camera)
        XCTAssertEqual(bodyOnly.count, 16)
        let bodyFOV = try DuelDisplayedSkinBounds.verticalFOV(points: bodyOnly, aspect: 2, minimum: 1, near: 0.1)
        XCTAssertGreaterThan(completeFOV, bodyFOV + 20,
                             "The camera must include the real head above the body")
        head.isHidden = false
        bone.position.x += 0.3
        let shifted = try bounds.cameraPoints(camera: camera)
        XCTAssertEqual(shifted.count, complete.count)
        for (before, after) in zip(complete, shifted) {
            XCTAssertEqual(after.x - before.x, 0.3, accuracy: 0.00001)
            XCTAssertEqual(after.y, before.y, accuracy: 0.00001)
            XCTAssertEqual(after.z, before.z, accuracy: 0.00001)
        }
        XCTAssertTrue(body.skinner === originalSkin)
        XCTAssertNil(head.skinner)
    }

    func testRigidCacheRejectsChangedGeometryMorphersAndInvalidVertices() throws {
        let original = geometry(), holder = SCNNode(geometry: original), camera = SCNNode()
        camera.position.z = 10
        // A geometry-bearing root must be covered as well as descendants.
        let bounds = try DuelDisplayedSkinBounds(root: holder)
        XCTAssertEqual(try bounds.cameraPoints(camera: camera).count, 16)
        holder.geometry = geometry()
        XCTAssertThrowsError(try bounds.cameraPoints(camera: camera)) {
            XCTAssertEqual($0 as? DuelDisplayedSkinBounds.Failure, .unsupportedGeometry)
        }
        holder.geometry = original
        let morpher = SCNMorpher()
        var changed = vertices
        changed[2].y += 3
        morpher.targets = [geometry(changed)]
        morpher.setWeight(1, forTargetAt: 0)
        holder.morpher = morpher
        XCTAssertThrowsError(try bounds.cameraPoints(camera: camera)) {
            XCTAssertEqual($0 as? DuelDisplayedSkinBounds.Failure, .unsupportedGeometry)
        }
        XCTAssertThrowsError(try DuelDisplayedSkinBounds(root: holder)) {
            XCTAssertEqual($0 as? DuelDisplayedSkinBounds.Failure, .unsupportedGeometry)
        }
        holder.morpher = nil
        assertRigidEnvelope(try bounds.cameraPoints(camera: camera), holder: holder, camera: camera)
        holder.pivot = SCNMatrix4MakeTranslation(0, 2, 0)
        XCTAssertThrowsError(try bounds.cameraPoints(camera: camera)) {
            XCTAssertEqual($0 as? DuelDisplayedSkinBounds.Failure, .unsupportedGeometry)
        }
        XCTAssertThrowsError(try DuelDisplayedSkinBounds(root: holder)) {
            XCTAssertEqual($0 as? DuelDisplayedSkinBounds.Failure, .unsupportedGeometry)
        }
        holder.pivot = SCNMatrix4Identity
        var invalid = vertices
        invalid[0].x = .nan
        let invalidHolder = SCNNode(geometry: geometry(invalid))
        XCTAssertThrowsError(try DuelDisplayedSkinBounds(root: invalidHolder)) {
            XCTAssertEqual($0 as? DuelDisplayedSkinBounds.Failure, .invalidTransform)
        }
    }
}
