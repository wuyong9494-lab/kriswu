import Foundation

/// A local edit on the original clip's time axis. Ambiguous instructions never start an export.
public struct WuMindFootageEdit: Equatable, Sendable {
    public let removal: Range<Double>?
    public let subtitle: String?

    public init?(instruction: String) {
        let parts = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:请)?\s*(?:(?:删除|删掉|剪掉|去掉)\s*第?\s*(\d+(?:\.\d+)?)\s*秒?\s*(?:到|至|[-–])\s*第?\s*(\d+(?:\.\d+)?)\s*秒)?\s*[，,；;]?\s*(?:(?:并|再)?(?:将|把)?字幕(?:改为|改成|设为|设置为)\s*[：:]?\s*(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: parts, range: NSRange(parts.startIndex..., in: parts)) else { return nil }
        func value(_ index: Int) -> String? {
            Range(match.range(at: index), in: parts).map { String(parts[$0]) }
        }
        if let a = value(1), let b = value(2) {
            guard let start = Double(a), let end = Double(b), start.isFinite, end.isFinite, start < end else { return nil }
            removal = start..<end
        } else { removal = nil }
        subtitle = value(3)?.trimmingCharacters(in: CharacterSet(charactersIn: "「」“”"))
        guard removal != nil || subtitle?.isEmpty == false else { return nil }
    }

    public func retainedRanges(duration: Double) -> [Range<Double>] {
        guard duration.isFinite, duration > 0 else { return [] }
        guard let removal else { return [0..<duration] }
        guard removal.upperBound <= duration else { return [] }
        return [0..<removal.lowerBound, removal.upperBound..<duration].filter { !$0.isEmpty }
    }
}
