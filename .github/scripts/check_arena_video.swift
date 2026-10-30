// Decode every video sample. This checks media integrity, not gameplay quality or FPS.
import Foundation
import AVFoundation
import CoreVideo

func reject(_ reason: String) -> Never {
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(1)
}
guard CommandLine.arguments.count == 2 else { reject("Usage: check_arena_video movie.mp4") }
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let tracks = try await asset.loadTracks(withMediaType: .video)
guard let track = tracks.first else { reject("Missing video track") }
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
output.alwaysCopiesSampleData = false
guard reader.canAdd(output) else { reject("Cannot decode video track") }
reader.add(output)
guard reader.startReading() else { reject("Video decoder could not start") }
var count = 0
var previous = -Double.infinity
var first: Double?
while let sample = output.copyNextSampleBuffer() {
    let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    guard time.isFinite, time > previous else { reject("Invalid or non-increasing video timestamp") }
    guard let image = CMSampleBufferGetImageBuffer(sample),
          CVPixelBufferGetWidth(image) >= 500, CVPixelBufferGetHeight(image) >= 500 else {
        reject("Missing or undersized decoded frame")
    }
    if first == nil { first = time }
    previous = time
    count += 1
}
guard reader.status == .completed else { reject("Video decode failed: \(String(describing: reader.error))") }
guard count >= 60, let first, previous - first >= 6 else { reject("Incomplete recording") }
print("Decoded \(count) frames, span \(previous - first)s. Content review and device performance remain separate.")
