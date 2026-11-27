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
