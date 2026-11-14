import Foundation
import XCTest
@testable import ShiftReminder

/// Synthetic containers exercise the release boundary. No fixture is a
/// recovered character, texture, motion, or proof of original-game fidelity.
@MainActor
final class DuelFighterCharacterContainerTests: XCTestCase {
    private typealias Object = [String: Any]
    private let jsonType: UInt32 = 0x4E4F534A
    private let binType: UInt32 = 0x004E4942

    private func word(_ value: UInt32) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    private func replacingWord(_ value: UInt32, at offset: Int, in original: Data) -> Data {
        var data = original
        data.replaceSubrange(offset..<(offset + 4), with: word(value))
        return data
    }
    private func json(_ object: Object) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        while !data.count.isMultiple(of: 4) { data.append(0x20) }
        return data
    }
    private func container(_ chunks: [(UInt32, Data)], version: UInt32 = 2) -> Data {
        var body = Data()
        for (type, bytes) in chunks {
            body.append(word(UInt32(bytes.count))); body.append(word(type)); body.append(bytes)
        }
        var data = Data("glTF".utf8)
        data.append(word(version)); data.append(word(UInt32(body.count + 12))); data.append(body)
        return data
    }
    private func document(bufferLength: Int = 4) -> Object {
        ["asset": ["version": "2.0"], "buffers": [["byteLength": bufferLength]],
         "bufferViews": [["buffer": 0, "byteLength": bufferLength]],
         "images": [["bufferView": 0, "mimeType": "image/png"]],
         "textures": [["source": 0]]]
    }
    private func fixture(_ object: Object, binary: Data = Data([1, 2, 3, 4])) throws -> Data {
        container([(jsonType, try json(object)), (binType, binary)])
    }
    private func reject(_ data: Data, _ message: String = "",
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(data), message,
                             file: file, line: line) { error in
            XCTAssertEqual(error as? DuelFighterAssetReleaseLoader.Failure, .integrity("character-glb"),
                           message, file: file, line: line)
        }
    }

    func testEmbeddedBufferImageAndTextureReferencesAreAccepted() throws {
        let data = try fixture(document())
        XCTAssertNoThrow(try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(data))
        // Bytes beyond declared buffer length remain unavailable to buffer views.
        let padded = try fixture(document(bufferLength: 3))
        XCTAssertNoThrow(try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(padded))
        let jsonOnly = container([(jsonType, try json(["asset": ["version": "2.0"]]))])
        XCTAssertNoThrow(try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(jsonOnly))
    }

    func testEveryBufferAndImageURIIsRejectedIncludingDataAndNull() throws {
        let uris: [Any] = ["sidecar.bin", "texture.png", "../outside.bin", "/tmp/outside.png",
                           "https://example.invalid/texture.png", "data:image/png;base64,AAAA", "", NSNull(), 3]
        for key in ["buffers", "images"] {
            for uri in uris {
                var object = document()
                var values = try XCTUnwrap(object[key] as? [Object])
                values[0]["uri"] = uri; object[key] = values
                reject(try fixture(object), "\(key):\(uri)")
            }
        }
    }

    func testPinnedContainerCannotAuthorizeMutableSidecarBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fighter-container-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (key, name) in [("buffers", "Synthetic_external.bin"), ("images", "Synthetic_external.png")] {
            var object = document()
            var values = try XCTUnwrap(object[key] as? [Object])
            values[0]["uri"] = name; object[key] = values
            let bytes = try fixture(object), originalDigest = DuelNetworkContentRecord.digest(bytes)
            let modelURL = directory.appendingPathComponent("Synthetic_Target.glb")
            let sidecarURL = directory.appendingPathComponent(name)
            try bytes.write(to: modelURL)
            for sample in [UInt8(11), UInt8(29)] {
                try Data(repeating: sample, count: 4).write(to: sidecarURL)
                let unchanged = try Data(contentsOf: modelURL)
                XCTAssertEqual(DuelNetworkContentRecord.digest(unchanged), originalDigest)
                reject(unchanged, "Changing the sidecar cannot authorize a correctly pinned container")
            }
            try FileManager.default.removeItem(at: sidecarURL)
            reject(try Data(contentsOf: modelURL), "Missing sidecars are rejected at the same boundary")
        }
    }

    func testHeaderAndDeclaredLengthCannotBeForgedOrTruncated() throws {
        let data = try fixture(document())
        reject(Data()); reject(Data(data.prefix(11)))
        reject(replacingWord(0, at: 0, in: data))
        for version in [UInt32(0), UInt32(1), UInt32(3), UInt32.max] {
            reject(replacingWord(version, at: 4, in: data))
        }
        for length in [UInt32(data.count - 4), UInt32(data.count + 4), UInt32.max] {
            reject(replacingWord(length, at: 8, in: data))
        }
        reject(Data(data.dropLast()))
        var trailing = data; trailing.append(contentsOf: [0, 0, 0, 0])
        reject(trailing)
        trailing = replacingWord(UInt32(trailing.count), at: 8, in: trailing)
        reject(trailing, "A partial chunk header cannot be ignored")
    }

    func testChunkBoundsAlignmentAndOrderingAreValidated() throws {
        let content = try json(document()), binary = Data([1, 2, 3, 4])
        reject(container([(binType, binary), (jsonType, content)]))
        reject(container([(jsonType, content), (jsonType, content), (binType, binary)]))
        reject(container([(jsonType, content), (binType, binary), (binType, binary)]))
        reject(container([(jsonType, Data([0x7B, 0x7D, 0x20]))]), "Chunks must be four-byte aligned")
        let data = container([(jsonType, content), (binType, binary)])
        reject(replacingWord(UInt32.max, at: 12, in: data))
        reject(replacingWord(UInt32(content.count + binary.count + 12), at: 12, in: data))
        let opaqueType: UInt32 = 0x12345678
        reject(container([(jsonType, content), (opaqueType, binary), (binType, binary)]),
               "A BIN chunk must be second, even with opaque chunks")
        let opaque = container([(jsonType, content), (binType, binary), (opaqueType, binary)])
        XCTAssertNoThrow(try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(opaque))
    }

    func testAssetVersionAndRequiredExtensionSupportAreExplicit() throws {
        let invalidAssets: [Object] = [[:], ["version": "1.0"], ["version": "2.1"], ["version": 2],
                                       ["version": "2.0", "minVersion": "2.1"], ["version": "2.0", "minVersion": NSNull()]]
        for asset in invalidAssets {
            var object = document(); object["asset"] = asset
            reject(try fixture(object))
        }
        var object = document()
        object["extensionsUsed"] = ["KHR_materials_unlit"]
        object["extensionsRequired"] = ["KHR_materials_unlit"]
        XCTAssertNoThrow(try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(fixture(object)))
        for extensions in [["KHR_draco_mesh_compression"], ["EXT_meshopt_compression"],
                           ["KHR_texture_basisu"], ["KHR_materials_unlit", "KHR_materials_unlit"]] {
            object["extensionsUsed"] = extensions; object["extensionsRequired"] = extensions
            reject(try fixture(object))
        }
        object["extensionsUsed"] = []; object["extensionsRequired"] = ["KHR_materials_unlit"]
        reject(try fixture(object), "Required extensions must also appear in extensionsUsed")
    }

    func testBinaryChunkAndDeclaredBufferMustAgree() throws {
        let object = document(), content = try json(object)
        reject(container([(jsonType, content)]), "An internal buffer requires a BIN chunk")
        reject(try fixture(["asset": ["version": "2.0"]]), "An undeclared BIN is rejected")
        for length in [0, -1, 5, 4.5, true, "4", NSNull(), UInt64.max] as [Any] {
            var changed = object; changed["buffers"] = [["byteLength": length]]
            reject(try fixture(changed))
        }
        var changed = object
        changed["buffers"] = [["byteLength": 4], ["byteLength": 4]]
        reject(try fixture(changed), "Only buffer zero can refer to the single BIN chunk")
    }

    func testEveryBufferViewMustStayWithinTheDeclaredBuffer() throws {
        let invalidViews: [Object] = [
            ["buffer": 1, "byteLength": 4], ["buffer": -1, "byteLength": 4],
            ["buffer": false, "byteLength": 4], ["byteLength": 4],
            ["buffer": 0, "byteLength": 0], ["buffer": 0, "byteLength": 5],
            ["buffer": 0, "byteOffset": -1, "byteLength": 1],
            ["buffer": 0, "byteOffset": 3, "byteLength": 2],
            ["buffer": 0, "byteOffset": UInt64.max, "byteLength": 1],
            ["buffer": 0, "byteOffset": NSNull(), "byteLength": 1]
        ]
        for view in invalidViews {
            var object = document(); object["bufferViews"] = [view]
            reject(try fixture(object))
        }
        var padded = document(bufferLength: 3)
        padded["bufferViews"] = [["buffer": 0, "byteOffset": 3, "byteLength": 1]]
        reject(try fixture(padded), "BIN padding is not part of the declared buffer")
    }

    func testEmbeddedImagesAndTextureSourcesCannotUseMissingReferences() throws {
        let invalidImages: [Object] = [["bufferView": 1, "mimeType": "image/png"],
                                       ["bufferView": -1, "mimeType": "image/png"],
                                       ["bufferView": false, "mimeType": "image/png"],
                                       ["mimeType": "image/png"], ["bufferView": 0],
                                       ["bufferView": 0, "mimeType": "image/webp"]]
        for image in invalidImages {
            var object = document(); object["images"] = [image]
            reject(try fixture(object))
        }
        let invalidTextures: [Object] = [[:], ["source": 1], ["source": -1], ["source": false], ["source": "0"]]
        for texture in invalidTextures {
            var object = document(); object["textures"] = [texture]
            reject(try fixture(object))
        }
    }

    func testMalformedArraysCannotSilentlyBecomeEmptyCollections() throws {
        for key in ["buffers", "bufferViews", "images", "textures", "extensionsUsed", "extensionsRequired"] {
            for value in [NSNull(), true, "", [1], ["invalid": "object"]] as [Any] {
                var object = document(); object[key] = value
                reject(try fixture(object), key)
            }
        }
        reject(container([(jsonType, Data("null".utf8))]))
        reject(container([(jsonType, Data("{bad".utf8))]))
    }
}
