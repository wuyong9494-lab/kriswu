import AVFoundation
import UIKit

/// Lifetime follows the chat attachment and any export that still uses it.
final class WuMindFootageSource: Sendable {
    let url: URL
    let filename: String

    init(copying original: URL) throws {
        filename = original.lastPathComponent
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(original.pathExtension)
        try FileManager.default.copyItem(at: original, to: url)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

@MainActor
enum WuMindFootageEditor {
    static func render(source: WuMindFootageSource, edit: WuMindFootageEdit) async throws -> Data {
        let asset = AVURLAsset(url: source.url)
        let duration = try await asset.load(.duration)
        let ranges = edit.retainedRanges(duration: duration.seconds)
        guard !ranges.isEmpty else { throw WuMindChatBuildService.BuildError.unavailable("删除区间超出片长或覆盖了整段素材。") }
        let composition = AVMutableComposition()
        let videos = try await asset.loadTracks(withMediaType: .video)
        guard let video = videos.first else { throw WuMindChatBuildService.BuildError.unavailable("素材没有视频轨道。") }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        for track in [video] + audio {
            guard let dest = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw WuMindChatBuildService.BuildError.invalidArtifact }
            let span = try await track.load(.timeRange)
            let transform = try await track.load(.preferredTransform)
            dest.preferredTransform = transform
            var cursor = CMTime.zero
            for range in ranges {
                let start = CMTime(seconds: range.lowerBound, preferredTimescale: 60_000)
                let end = CMTime(seconds: range.upperBound, preferredTimescale: 60_000)
                let overlap = CMTimeRange(start: start, end: end).intersection(span)
                if overlap.isValid, !overlap.isEmpty {
                    try dest.insertTimeRange(overlap, of: track, at: cursor + (overlap.start - start))
                }
                cursor = cursor + (end - start)
            }
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw WuMindChatBuildService.BuildError.invalidArtifact }
        if let subtitle = edit.subtitle {
            let size = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            let width = max(1, abs(size.applying(transform).width))
            let font = UIFont.boldSystemFont(ofSize: max(12, width / 28))
            let bounds = CGSize(width: width, height: font.lineHeight * 3)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let label = UIGraphicsImageRenderer(size: bounds, format: format).image { _ in
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                (subtitle as NSString).draw(in: CGRect(origin: .zero, size: bounds), withAttributes: [
                    .font: font, .foregroundColor: UIColor.white, .backgroundColor: UIColor.black.withAlphaComponent(0.7),
                    .paragraphStyle: paragraph
                ])
            }
            guard let cg = label.cgImage else { throw WuMindChatBuildService.BuildError.invalidArtifact }
            let overlay = CIImage(cgImage: cg)
            exporter.videoComposition = AVVideoComposition(asset: composition) { request in
                let input = request.sourceImage
                let placed = overlay.transformed(by: CGAffineTransform(translationX: input.extent.minX,
                                                                        y: input.extent.minY + input.extent.height * 0.04))
                request.finish(with: placed.composited(over: input).cropped(to: input.extent), context: nil)
            }
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        try Task.checkCancellation()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        try Task.checkCancellation()
        guard exporter.status == .completed else {
            throw WuMindChatBuildService.BuildError.unavailable(exporter.error?.localizedDescription ?? "本地 MP4 导出失败。")
        }
        return try Data(contentsOf: output, options: .mappedIfSafe)
    }
}
