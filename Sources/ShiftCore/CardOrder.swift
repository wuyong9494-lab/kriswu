import Foundation

/// 今天页卡片自己排的顺序：存下来的顺序里认得的留下（去掉重复、已经没有的卡片），
/// 以后新加的卡片按默认顺序插到它前一张卡片后面，不会被藏到最底下
public enum CardOrder {
    public static func resolve(stored: [String], defaults: [String]) -> [String] {
        let known = Set(defaults)
        var seen = Set<String>()
        var result = stored.filter { known.contains($0) && seen.insert($0).inserted }
        for (i, id) in defaults.enumerated() where !seen.contains(id) {
            let previous = defaults[..<i].reversed().first { seen.contains($0) }
            let at = previous.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(id, at: at)
            seen.insert(id)
        }
        return result
    }
}
