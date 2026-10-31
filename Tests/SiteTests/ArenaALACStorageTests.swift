import XCTest
import AVFoundation
#if ARENA_RESOURCE_RUNTIME_TESTS
@testable import ArenaResourceRuntime
#else
@testable import ShiftReminder
#endif

/// Only original synthetic PCM ramps are used by this decoder gate.
/// Compressed fixtures are synthetic; reference PCM is generated independently.
@MainActor
final class ArenaALACStorageTests: XCTestCase {
    func testALACPreservesPCMAndExistingHostDecodePath() throws {
        let fixtures: [(rate: Double, channels: AVAudioChannelCount)] = [
            (22_050, 1), (44_100, 1), (44_100, 2), (48_000, 1), (48_000, 2)
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        for fixture in fixtures {
            let name = "alac_pcm_\(Int(fixture.rate))_\(fixture.channels)"
            let pair = try ArenaALACStorageFixtures.write(rate: Int(fixture.rate), channels: Int(fixture.channels), directory: directory)
            let wavURL = pair.wav
            let alacURL = pair.alac
            let wav = try AVAudioFile(forReading: wavURL, commonFormat: .pcmFormatInt16, interleaved: true)
            let alac = try AVAudioFile(forReading: alacURL, commonFormat: .pcmFormatInt16, interleaved: true)
            XCTAssertEqual(alac.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatAppleLossless, name)
            for file in [wav, alac] {
                XCTAssertEqual(file.length, 5_003, name)
                XCTAssertEqual(file.processingFormat.sampleRate, fixture.rate, name)
                XCTAssertEqual(file.processingFormat.channelCount, fixture.channels, name)
            }
            func pcm(_ file: AVAudioFile) throws -> Data {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length)))
                try file.read(into: buffer)
                XCTAssertEqual(buffer.frameLength, 5_003, name)
                let pointer = try XCTUnwrap(buffer.int16ChannelData?[0])
                let count = Int(buffer.frameLength) * Int(buffer.format.channelCount)
                return Data(bytes: pointer, count: count * MemoryLayout<Int16>.size)
            }
            let reference = try pcm(wav)
            let decoded = try pcm(alac)
            XCTAssertEqual(reference, decoded, "Native PCM16 equality: " + name)
            XCTAssertTrue(reference.contains { $0 != 0 }, name)

            // Exercise exactly the production ExtAudioFileOpenURL/Read adapter,
            // including stereo downmix and 22.05/48 kHz to 44.1 kHz conversion.
            let referenceHost = try ArenaAudioDecoder.decode(wavURL, format: target)
            let decodedHost = try ArenaAudioDecoder.decode(alacURL, format: target)
            XCTAssertEqual(referenceHost.frameLength, decodedHost.frameLength, name)
            XCTAssertEqual(decodedHost.format.sampleRate, 44_100, name)
            XCTAssertEqual(decodedHost.format.channelCount, 1, name)
            let lhs = try XCTUnwrap(referenceHost.floatChannelData?[0])
            let rhs = try XCTUnwrap(decodedHost.floatChannelData?[0])
            let count = min(Int(referenceHost.frameLength), Int(decodedHost.frameLength))
            var maximumDifference: Float = 0
            for index in 0..<count {
                maximumDifference = max(maximumDifference, abs(lhs[index] - rhs[index]))
            }
            XCTAssertLessThanOrEqual(maximumDifference, 0.000001, "Host PCM comparison: " + name)
        }
    }
}
