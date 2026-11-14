import Foundation

/// The recovered PlaySound action selects an array position uniformly. Repeated
/// entries therefore retain their original weighting; the array is not a playlist.
/// This arena adapter derives variation from accepted event ordinals, independently
/// of combat RNG and render cadence. It does not reproduce Unity's global RNG state.
public enum DuelSourceAudioVariation {
    public static func index(category: String, eventOrdinal: UInt64, count: Int) -> Int? {
        guard !category.isEmpty, category.utf8.count <= 128, (1...32).contains(count) else { return nil }
        // Swift's randomized Hasher must never seed a reproducible audio stream.
        var state: UInt64 = 14_695_981_039_346_656_037
        for byte in category.utf8 { state = (state ^ UInt64(byte)) &* 1_099_511_628_211 }
        state ^= eventOrdinal &* 0x9E3779B97F4A7C15
        let bound = UInt64(count)
        let threshold = (0 &- bound) % bound
        while true {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            value ^= value >> 31
            // Rejection avoids modulo bias without sorting/deduplicating the
            // authored alternatives. No wall clock or global random state is read.
            if value >= threshold { return Int(value % bound) }
        }
    }
}
