import XCTest
@testable import ShiftReminder

/// Tiny author-owned gzip fixtures cover framing, integrity and output bounds.
final class DuelBoundedGzipTests: XCTestCase {
    private let short = Data(base64Encoded: "H4sIAAAAAAACA8svykzPzEvMUUjLrCgpLUoFACVtFfYQAAAA")!
    private let large = Data(base64Encoded: "H4sIAAAAAAACA+3BMQEAAADCoGzrX8oSnkABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAG8DuIbFq3ARAQA=")!

    func testOneAuthenticatedMemberDecodesAtItsExactOutputCeiling() throws {
        XCTAssertEqual(try DuelBoundedGzip.decode(short, maximum: 16), Data("original fixture".utf8))
        XCTAssertThrowsError(try DuelBoundedGzip.decode(short, maximum: 15)) { error in
            guard case DuelBoundedGzip.Failure.limit = error else { return XCTFail("Expected output ceiling failure") }
        }
    }

    func testCompressionBombIsBoundedAcrossMultipleInflateChunks() throws {
        XCTAssertEqual(try DuelBoundedGzip.decode(large, maximum: 70_000), Data(repeating: 65, count: 70_000))
        for cap in [1, 65_535, 65_536, 69_999] {
            XCTAssertThrowsError(try DuelBoundedGzip.decode(large, maximum: cap)) { error in
                guard case DuelBoundedGzip.Failure.limit = error else { return XCTFail("Expected bounded expansion") }
            }
        }
    }

    func testOriginalCRCAndUncompressedLengthCannotBeTampered() {
        for offset in [short.count - 8, short.count - 4, 12] {
            var corrupt = short; corrupt[offset] ^= 1
            XCTAssertThrowsError(try DuelBoundedGzip.decode(corrupt, maximum: 100))
        }
    }

    @MainActor
    func testTriadManifestPreparationRejectsChangedBytesAndCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "FixtureEffects.json"
        let data = Data(#"{"version":1,"profileID":"sun","characterSHA256":"synthetic","sourceConfigurationSHA256":"synthetic","evidence":[],"sampleRate":60,"worldUnitsPerSourceUnit":0.01,"files":[],"effects":{},"bindings":[],"markers":[],"materials":{}}"#.utf8)
        let file = DuelFighterAssetRelease.File(name: name, bytes: data.count, sha256: DuelNetworkContentRecord.digest(data))
        try data.write(to: directory.appendingPathComponent(name))
        _ = try await DuelTriadEffectAssets.prepareManifest(directory: directory, file: file)
        let cancelled = Task { @MainActor in try await DuelTriadEffectAssets.prepareManifest(directory: directory, file: file) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled preparation returned a document")
        } catch is CancellationError {}
        var changed = data
        changed[0] ^= 1
        try changed.write(to: directory.appendingPathComponent(name))
        do {
            _ = try await DuelTriadEffectAssets.prepareManifest(directory: directory, file: file)
            XCTFail("Changed effects passed the pinned digest")
        } catch DuelFighterAssetReleaseLoader.Failure.integrity(let path) {
            XCTAssertEqual(path, name)
        }
    }

    func testTruncatedInvalidHeaderAndInvalidLimitsAreRejected() {
        for remove in [1, 7, 15] { XCTAssertThrowsError(try DuelBoundedGzip.decode(Data(short.dropLast(remove)), maximum: 100)) }
        for input in [Data(), Data(repeating: 0, count: 20), Data("not a gzip member at all".utf8)] {
            XCTAssertThrowsError(try DuelBoundedGzip.decode(input, maximum: 100))
        }
        for maximum in [0, -1, 256_000_001] { XCTAssertThrowsError(try DuelBoundedGzip.decode(short, maximum: maximum)) }
    }

    func testExtraMembersTrailingBytesAndEmptyOutputCannotChangeManifestMeaning() {
        XCTAssertThrowsError(try DuelBoundedGzip.decode(short + short, maximum: 100))
        XCTAssertThrowsError(try DuelBoundedGzip.decode(short + Data([0]), maximum: 100))
        let empty = Data(base64Encoded: "H4sIAAAAAAACAwMAAAAAAAAAAAA=")!
        XCTAssertThrowsError(try DuelBoundedGzip.decode(empty, maximum: 100))
    }
}
