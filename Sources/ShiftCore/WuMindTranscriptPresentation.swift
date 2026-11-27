import Foundation

public enum WuMindTranscriptPresentation {
    private static let lengthLimit = 700
    private static let newlineLimit = 12
    private static let previewLimit = 250

    /// Bound work even when an active model is streaming a very large response.
    public static func shouldFoldAnswer(_ text: String) -> Bool {
        var length = 0
        var newlines = 0
        for character in text {
            length += 1
            if character.isNewline { newlines += 1 }
            if length > lengthLimit || newlines >= newlineLimit { return true }
        }
        return false
    }

    public static func answerPreview(_ text: String) -> String {
        String(text.prefix(previewLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Seals display blocks at line breaks. The verbatim answer also retains every original separator.
public struct WuMindStreamingAnswer {
    public private(set) var text = ""
    public private(set) var completeBlocks: [String] = []
    public private(set) var tail = ""
    public private(set) var revision: UInt64 = 0

    public init() {}

    public mutating func replace(with replacement: String) {
        text = ""
        completeBlocks.removeAll(keepingCapacity: false)
        tail = ""
        revision &+= 1
        append(replacement)
    }

    public mutating func append(_ delta: String) {
        guard !delta.isEmpty else { return }
        revision &+= 1
        text.append(delta)
        var rest = delta[...]
        while let newline = rest.utf8.firstIndex(of: 0x0A) {
            let next = rest.utf8.index(after: newline)
            tail.append(contentsOf: rest[..<next])
            if tail.utf8.count >= 768 {
                completeBlocks.append(String(tail.dropLast()))
                tail = ""
            }
            rest = rest[next...]
        }
        tail.append(contentsOf: rest)
    }
}

extension WuMindTranscriptPresentation {
    public static func needsScrollToRevealBottom(contentBottom: Double, viewportHeight: Double) -> Bool {
        viewportHeight > 0 && contentBottom - viewportHeight > 1
    }
}
