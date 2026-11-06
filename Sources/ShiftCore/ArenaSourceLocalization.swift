import Foundation

/// Original text and placeholders remain private pack data, not source literals.
public struct ArenaSourceLocalization: Decodable, Sendable {
    public let schemaVersion: Int
    public let locale: String
    public let sourceIPASHA256: String
    public let strings: [String: String]

    public init(data: Data, expectedSourceSHA256: String) throws {
        guard data.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        self = try JSONDecoder().decode(Self.self, from: data)
        guard schemaVersion == 1, ["CN", "CNT", "EN"].contains(locale),
              ArenaResourcePackManifest.isSHA256(sourceIPASHA256), sourceIPASHA256 == expectedSourceSHA256,
              strings.count <= 50_000,
              strings.allSatisfy({ !$0.key.isEmpty && $0.key.utf8.count <= 240 && $0.value.utf8.count <= 65_536 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    /// Plain labels must not expose unresolved counters or rich-text commands.
    /// Rich source strings stay available in `strings` for their dedicated adapter.
    public func plainText(_ key: String) -> String? {
        guard let value = strings[key], !value.isEmpty,
              !value.contains("<"), !value.contains(">") else { return nil }
        return value
    }
}
