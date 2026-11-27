import Foundation

/// Explicit user-selected task. A normal conversation never starts artifact generation by matching a keyword.
public enum WuMindChatBuild: String, CaseIterable, Identifiable, Sendable {
    case image, video, code, ppt, spatial3d, tender

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .image: return "生成图片"
        case .video: return "生成视频"
        case .code: return "构建网页"
        case .ppt: return "制作 PPT"
        case .spatial3d: return "创建 3D 空间"
        case .tender: return "起草标书"
        }
    }

    public var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .ppt: return "rectangle.on.rectangle.angled"
        case .spatial3d: return "cube"
        case .tender: return "doc.text"
        }
    }

    public var promptPlaceholder: String {
        switch self {
        case .image: return "描述想生成的图片…"
        case .video: return "描述想生成的视频…"
        case .code: return "描述要构建的网页或交互原型…"
        case .ppt: return "输入主题、受众和期望页数…"
        case .spatial3d: return "描述空间、尺寸和你想要的风格…"
        case .tender: return "上传招标文件，说明要起草的部分…"
        }
    }

    public var workType: WuMindWorkType {
        switch self {
        case .image: return .image
        case .video: return .video
        case .code: return .code
        case .ppt: return .ppt
        case .spatial3d: return .scene3d
        case .tender: return .document
        }
    }

    /// Reject model commentary or code fragments masquerading as a downloadable page.
    /// HTML is exported as a file; it is never executed inside WuMind.
    public static func standaloneHTML(_ value: String) -> String? {
        var clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("```html"), clean.hasSuffix("```"),
           let newline = clean.firstIndex(of: "\n") {
            clean = String(clean[clean.index(after: newline)...].dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lower = clean.lowercased()
        guard lower.hasPrefix("<!doctype html>"), lower.contains("<html"),
              lower.contains("<body"), lower.hasSuffix("</html>"),
              clean.utf8.count <= 1_000_000 else { return nil }
        return clean
    }
}
