import Foundation

/// A deliverable explicitly selected or requested in a chat.
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

    /// Suggest a build only for a direct creation request, not references, comparisons, or instructions.
    /// The UI still gates the selected route before sending, so classification never invokes a provider.
    public static func detectRequest(_ raw: String) -> Self? {
        let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !prompt.isEmpty, prompt.utf8.count <= 12_000,
              prompt.range(of: #"^(能不能|能否|可以|怎么|如何|为什么|是否|介绍|解释|比较|对比|不要|别|不用|无需|不需要|我想知道|how\b|what\b|why\b|can you explain\b)"#, options: .regularExpression) == nil,
              prompt.range(of: #"不要(生成|制作|做|创建)|不(用|必)(生成|制作|做|创建)|只(给|要)[^，。]{0,6}(提示词|教程|方法|说明)|(生成|制作|创建)[^，。]{0,22}(提示词|的方法|的教程)"#, options: .regularExpression) == nil,
              let action = prompt.range(of: #"^(?:(?:请|帮我|给我|替我|我想要|我想|用这张图|用这个文件|根据[^，,。]{1,24}[，, ]*)\s*)*(?:生成|制作|创建|构建|做|起草|写|绘制|produce\b|generate\b|create\b|build\b|make\b)\s*"#, options: .regularExpression)
        else { return nil }
        let target = String(prompt[action.upperBound...].prefix(180))
        let candidates: [(Self, String)] = [
            (.video, #"视频|短片|动图|\bvideo\b"#),
            (.ppt, #"pptx?\b|幻灯片|演示文稿|\b(slide deck|slides|presentation)\b"#),
            (.code, #"网页|网站|交互原型|\b(html|web page|website)\b"#),
            (.image, #"图片|图像|海报|插画|封面图|\b(image|poster|illustration)\b"#),
            (.spatial3d, #"3\s*d|三维(场景|空间|模型)|立体(场景|空间)|\bglb\b"#),
            (.tender, #"标书|投标文件|投标书|\bbid proposal\b"#)
        ]
        let matches = candidates.compactMap { tool, pattern -> (Self, String.Index)? in
            guard let range = target.range(of: pattern, options: .regularExpression) else { return nil }
            return (tool, range.lowerBound)
        }.sorted { $0.1 < $1.1 }
        // If two deliverables are independently requested, do not silently pick and run one.
        if matches.count > 1,
           target.range(of: #"再(生成|做|制作|写|创建|构建)|以及一|各做|分别|各生成|同时(生成|制作|做|写)|\band (generate|create|make|build)\b"#, options: .regularExpression) != nil {
            return nil
        }
        return matches.first?.0
    }

    public static func requestedVideoSeconds(in prompt: String) -> Int? {
        let pattern = #"(?<![\d.])(\d{1,2})\s*(?:秒|seconds?(?![a-z])|s(?![a-z]))"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = re.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let number = Range(match.range(at: 1), in: prompt), let value = Int(prompt[number]), value > 0
        else { return nil }
        return value
    }

    public static func supportedVideoSeconds(requested: Int?, allowed: [Int], fallback: Int) -> Int {
        guard let requested, !allowed.isEmpty else { return fallback }
        let sorted = allowed.sorted()
        return sorted.first(where: { $0 >= requested }) ?? sorted.last ?? fallback
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
