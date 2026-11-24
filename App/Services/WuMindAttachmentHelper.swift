import Foundation
import UIKit
import Vision

/// On-device helpers for WUMIND multimodal attachments (Vision OCR for uploaded photos)
/// and Admin payment QR code Base64 compression/decoding.
enum WuMindAttachmentHelper {
    /// Extracts Chinese & English text from an uploaded image on-device via Vision OCR.
    static func extractImageAttachment(data: Data, filename: String) async throws -> WuMindAttachmentParser.ExtractedDocument {
        let ocrResult = try await Task.detached(priority: .userInitiated) { () throws -> (Int, Int, String) in
            guard let image = UIImage(data: data), let cgImage = image.cgImage else {
                throw WuMindAttachmentParser.ParseError.unreadableContent
            }
            let width = Int(image.size.width * image.scale)
            let height = Int(image.size.height * image.scale)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return (width, height, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }.value

        let (width, height, recognized) = ocrResult

        let body: String
        let badge: String
        if recognized.isEmpty {
            body = "[图片尺寸：\(width)×\(height) px，未检测到清晰文字内容]"
            badge = "图片 · \(width)×\(height)"
        } else {
            body = "[图片尺寸：\(width)×\(height) px · 本机 OCR 识别内容]\n\(String(recognized.prefix(WuMindAttachmentParser.maxExtractedChars)))"
            badge = "图片 OCR · \(recognized.count) 字"
        }
        return WuMindAttachmentParser.ExtractedDocument(
            filename: filename,
            kind: .image,
            byteCount: data.count,
            extractedText: body,
            summaryBadge: badge
        )
    }

    /// Resizes & encodes an Admin payment QR code image cleanly into Base64 JPEG (<= ~120 KB) for cloud sync.
    @MainActor
    static func encodeQRCodeImage(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 520
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let targetSize = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.82), jpeg.count <= 320_000 else { return nil }
        return jpeg.base64EncodedString()
    }

    static func decodeBase64Image(_ raw: String?) -> UIImage? {
        guard let raw, !raw.isEmpty else { return nil }
        let cleaned: String
        if let comma = raw.firstIndex(of: ","), raw.hasPrefix("data:image") {
            cleaned = String(raw[raw.index(after: comma)...])
        } else {
            cleaned = raw
        }
        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}
