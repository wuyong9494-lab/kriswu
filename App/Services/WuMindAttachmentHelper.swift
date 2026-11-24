import Foundation
import UIKit
import Vision

/// On-device helpers for WUMIND multimodal attachments (Vision OCR for uploaded photos)
/// and Admin payment QR code Base64 compression/decoding.
enum WuMindAttachmentHelper {
    /// Extracts Chinese & English text via Vision OCR AND produces a bounded compressed JPEG
    /// (<= 1280px longest side) for native Vision multimodal passthrough to GPT / Gemini / Claude / Grok.
    static func extractImageAttachment(data: Data, filename: String) async throws -> WuMindAttachmentParser.ExtractedDocument {
        let processed = try await Task.detached(priority: .userInitiated) { () throws -> (Int, Int, String, Data?) in
            guard let image = UIImage(data: data), let cgImage = image.cgImage else {
                throw WuMindAttachmentParser.ParseError.unreadableContent
            }
            let width = Int(image.size.width * image.scale)
            let height = Int(image.size.height * image.scale)

            // Compress image cleanly for Vision APIs (<= 1280px longest edge, JPEG 0.78)
            let maxEdge: CGFloat = 1280
            let pixelW = max(1, CGFloat(width))
            let pixelH = max(1, CGFloat(height))
            let ratio = min(1, maxEdge / max(pixelW, pixelH))
            let targetSize = CGSize(width: max(1, (pixelW * ratio).rounded()), height: max(1, (pixelH * ratio).rounded()))
            let rendererFormat = UIGraphicsImageRendererFormat()
            rendererFormat.scale = 1
            let scaled = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat).image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            var jpeg = scaled.jpegData(compressionQuality: 0.78)
            if let j = jpeg, j.count > 650_000 {
                jpeg = scaled.jpegData(compressionQuality: 0.58)
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return (width, height, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), jpeg)
        }.value

        let (width, height, recognized, jpegData) = processed

        let body: String
        let badge: String
        if recognized.isEmpty {
            body = "[图片尺寸：\(width)×\(height) px · 支持多模态视觉直传；未检测到额外印刷文字]"
            badge = "视觉原图 · \(width)×\(height)"
        } else {
            body = "[图片尺寸：\(width)×\(height) px · 支持多模态视觉直传 + 本机 OCR 备用]\n\(String(recognized.prefix(WuMindAttachmentParser.maxExtractedChars)))"
            badge = "视觉 + OCR · \(recognized.count) 字"
        }
        return WuMindAttachmentParser.ExtractedDocument(
            filename: filename,
            kind: .image,
            byteCount: data.count,
            extractedText: body,
            summaryBadge: badge,
            imageJPEGData: jpegData,
            imageMimeType: jpegData != nil ? "image/jpeg" : nil
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
