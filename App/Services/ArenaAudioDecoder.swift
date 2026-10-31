import AVFoundation
import AudioToolbox
import Foundation

/// Shared by both effect mixers and the resource decoder verification target.
/// Returns the same PCM buffer used by the live engine.
@MainActor
enum ArenaAudioDecoder {
    static func decode(_ url: URL, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        // Extended Audio File performs synchronous decode/resampling into caller-owned
        // PCM. No @Sendable input callback captures a mutable AVAudioPCMBuffer.
        var handle: ExtAudioFileRef?
        try check(ExtAudioFileOpenURL(url as CFURL, &handle))
        guard let file = handle else { throw NSError(domain: "ArenaPCM", code: 1) }
        defer { ExtAudioFileDispose(file) }
        var sourceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &formatSize, &sourceFormat))
        var frames: Int64 = 0
        var frameSize = UInt32(MemoryLayout<Int64>.size)
        try check(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &frameSize, &frames))
        guard sourceFormat.mSampleRate > 0, frames > 0 else { throw NSError(domain: "ArenaPCM", code: 2) }
        var clientFormat = format.streamDescription.pointee
        try check(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat))
        let capacity = AVAudioFrameCount(ceil(Double(frames) * format.sampleRate / sourceFormat.mSampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NSError(domain: "ArenaPCM", code: 3)
        }
        // AVAudioPCMBuffer starts with frameLength=0, so its AudioBufferList
        // advertises zero writable bytes until frameLength is set.
        output.frameLength = capacity
        var decoded = capacity
        try check(ExtAudioFileRead(file, &decoded, output.mutableAudioBufferList))
        guard decoded > 0 else { throw NSError(domain: "ArenaPCM", code: 4) }
        output.frameLength = decoded
        return output
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
