import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// On-device handoff between the iOS share extension and the main app.
/// No authentication or network access occurs in the inbox.
public struct TenderShareInbox: Sendable {
    public static let appGroupIdentifier = "group.com.kriswu.shiftreminder"
    public static let maxFileBytes = 16 * 1024 * 1024
    public static let maxInboxItems = 20

    /// Expiry is enforced on the next inbox access, not by an iOS background timer.
    public static let expirationInterval: TimeInterval = 24 * 60 * 60

    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let filename: String
        public let createdAt: Date
        public let byteCount: Int
    }

    public enum Failure: LocalizedError, Equatable, Sendable {
        case unavailable, invalidDocument, tooLarge, noLongerAvailable, storageFull

        public var errorDescription: String? {
            switch self {
            case .unavailable: return "无法访问本机分享收件箱，请直接在值班提醒里选文件。"
            case .invalidDocument: return "仅支持可读取的 PDF 或 DOCX 文件。"
            case .tooLarge: return "单个文件不能超过 16 MB。"
            case .noLongerAvailable: return "这份文件已删除、已过期或无法读取，请重新分享。"
            case .storageFull: return "本机收件箱已满，请先在值班提醒中移除不再需要的文件。"
            }
        }
    }

    private let directory: URL

    /// Tests can supply a dedicated temporary directory without requiring an App Group entitlement.
    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    public static func appGroup() throws -> Self {
        #if os(iOS)
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { throw Failure.unavailable }
        return Self(directory: group.appendingPathComponent("TenderShareInbox", isDirectory: true))
        #else
        throw Failure.unavailable
        #endif
    }

    /// Call while the share provider's temporary URL is still readable.
    @discardableResult
    public func save(fileURL: URL, filename: String? = nil, now: Date = Date()) throws -> Item {
        let selectedName = filename ?? fileURL.lastPathComponent
        return try save(data: boundedRead(fileURL, limit: Self.maxFileBytes, error: .invalidDocument),
                        filename: selectedName, now: now)
    }

    @discardableResult
    public func save(data: Data, filename: String, now: Date = Date()) throws -> Item {
        guard data.count <= Self.maxFileBytes else { throw Failure.tooLarge }
        let format = try Self.format(filename)
        guard format.accepts(data) else { throw Failure.invalidDocument }
        let manager = FileManager.default
        let root = try readyDirectory()
        try purgeExpired(in: root, now: now)
        let existing = try children(in: root).filter { url in
            Self.directoryExists(url) && (Self.id(from: url) != nil || url.lastPathComponent.hasPrefix(".incoming-"))
        }
        guard existing.count < Self.maxInboxItems else { throw Failure.storageFull }
        let id = UUID()
        let item = Item(id: id, filename: Self.safeDisplayName(filename, format: format),
                        createdAt: now, byteCount: data.count)
        let final = package(id, in: root)
        let stage = root.appendingPathComponent(".incoming-\(id.uuidString.lowercased())", isDirectory: true)
        do {
            try manager.createDirectory(at: stage, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: stage) }
            Self.applyProtection(to: stage)
            try Self.write(data, to: stage.appendingPathComponent(format.payload))
            let metadata = try JSONEncoder().encode(item)
            try Self.write(metadata, to: stage.appendingPathComponent(Self.manifestName))
            // Both names are siblings on the same filesystem. The visible package appears only
            // after source and manifest are complete; an interrupted stage is never listed.
            try manager.moveItem(at: stage, to: final)
            return item
        } catch {
            throw Failure.unavailable
        }
    }

    public func items(now: Date = Date()) throws -> [Item] {
        let root = try readyDirectory()
        try purgeExpired(in: root, now: now)
        return try children(in: root).compactMap { url -> Item? in
            guard let id = Self.id(from: url), let found = try? load(id, in: root),
                  !Self.expired(found, asOf: now) else { return nil }
            return found
        }.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public func read(_ item: Item, now: Date = Date()) throws -> Data {
        let root = try readyDirectory()
        try purgeExpired(in: root, now: now)
        let stored = try load(item.id, in: root)
        guard !Self.expired(stored, asOf: now) else { throw Failure.noLongerAvailable }
        let format = try Self.format(stored.filename)
        let payload = package(stored.id, in: root).appendingPathComponent(format.payload)
        let data = try boundedRead(payload, limit: Self.maxFileBytes, error: .noLongerAvailable)
        guard data.count == stored.byteCount, format.accepts(data) else { throw Failure.noLongerAvailable }
        return data
    }

    public func delete(_ item: Item) throws {
        let root = try readyDirectory()
        let target = package(item.id, in: root)
        guard Self.directoryExists(target) else {
            if FileManager.default.fileExists(atPath: target.path) { throw Failure.noLongerAvailable }
            return
        }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            if FileManager.default.fileExists(atPath: target.path) { throw Failure.unavailable }
        }
    }

    private static let manifestName = "metadata.json"

    private func readyDirectory() throws -> URL {
        guard directory.isFileURL else { throw Failure.unavailable }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch { throw Failure.unavailable }
        guard Self.directoryExists(directory) else { throw Failure.unavailable }
        Self.applyProtection(to: directory)
        return directory
    }

    private func package(_ id: UUID, in root: URL) -> URL {
        root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private static func id(from url: URL) -> UUID? {
        let raw = url.lastPathComponent
        guard let id = UUID(uuidString: raw), raw == id.uuidString.lowercased() else { return nil }
        return id
    }

    private func children(in root: URL) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            )
        } catch { throw Failure.unavailable }
    }

    private func load(_ id: UUID, in root: URL) throws -> Item {
        let folder = package(id, in: root)
        guard Self.directoryExists(folder) else { throw Failure.noLongerAvailable }
        let data = try boundedRead(folder.appendingPathComponent(Self.manifestName), limit: 4_096, error: .noLongerAvailable)
        guard let item = try? JSONDecoder().decode(Item.self, from: data),
              item.id == id, item.createdAt.timeIntervalSince1970.isFinite,
              (1...Self.maxFileBytes).contains(item.byteCount),
              let format = try? Self.format(item.filename), Self.safeDisplayName(item.filename, format: format) == item.filename,
              let size = Self.regularSize(folder.appendingPathComponent(format.payload)),
              size == item.byteCount else { throw Failure.noLongerAvailable }
        return item
    }

    private func purgeExpired(in root: URL, now: Date) throws {
        let manager = FileManager.default
        for url in try children(in: root) where Self.directoryExists(url) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if url.lastPathComponent.hasPrefix(".incoming-"),
               let modified, now.timeIntervalSince(modified) >= Self.expirationInterval {
                try? manager.removeItem(at: url)
            } else if let id = Self.id(from: url) {
                if let item = try? load(id, in: root) {
                    if Self.expired(item, asOf: now) { try? manager.removeItem(at: url) }
                } else if let modified, now.timeIntervalSince(modified) >= Self.expirationInterval {
                    // Clean up an old incomplete/corrupt package even if its metadata is unreadable.
                    try? manager.removeItem(at: url)
                }
            }
        }
    }

    private static func expired(_ item: Item, asOf now: Date) -> Bool {
        now.timeIntervalSince(item.createdAt) >= expirationInterval
    }

    private static func regularSize(_ file: URL) -> Int? {
        guard file.isFileURL,
              let value = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              value.isRegularFile == true, value.isSymbolicLink != true else { return nil }
        return value.fileSize
    }

    private static func directoryExists(_ file: URL) -> Bool {
        guard let value = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return value.isDirectory == true && value.isSymbolicLink != true
    }

    private func boundedRead(_ file: URL, limit: Int, error: Failure) throws -> Data {
        guard let size = Self.regularSize(file) else { throw error }
        guard size <= limit else { throw error == .invalidDocument ? Failure.tooLarge : error }
        do {
            #if canImport(Darwin) || canImport(Glibc)
            let descriptor = file.path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
            guard descriptor >= 0 else { throw error }
            var info = stat()
            guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                _ = close(descriptor)
                throw error
            }
            let stream = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            #else
            let stream = try FileHandle(forReadingFrom: file)
            #endif
            defer { try? stream.close() }
            var data = Data()
            while data.count <= limit {
                let maximum = min(512 * 1024, limit + 1 - data.count)
                guard let chunk = try stream.read(upToCount: maximum), !chunk.isEmpty else { break }
                data.append(chunk)
            }
            guard data.count <= limit else { throw error == .invalidDocument ? Failure.tooLarge : error }
            return data
        } catch let known as Failure { throw known }
        catch { throw error }
    }

    private static func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        applyProtection(to: url)
    }

    private static func applyProtection(to url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path
        )
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? protectedURL.setResourceValues(values)
        #endif
    }

    private enum Format: String {
        case pdf, docx
        var payload: String { "source." + rawValue }

        func accepts(_ data: Data) -> Bool {
            switch self {
            case .pdf:
                return data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil
            case .docx:
                return TenderShareInbox.hasWordContainer(data)
            }
        }
    }

    private static func format(_ filename: String) throws -> Format {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard let format = Format(rawValue: ext) else { throw Failure.invalidDocument }
        return format
    }

    private static func safeDisplayName(_ filename: String, format: Format) -> String {
        let leaf = String(filename.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last ?? "")
        let clean = String((leaf as NSString).deletingPathExtension.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
                && ![0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069].contains($0.value)
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        var stem = String()
        var byteCount = 0
        for character in clean {
            let count = String(character).utf8.count
            guard byteCount + count <= 150 else { break }
            byteCount += count
            stem.append(character)
        }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.isEmpty || stem == "." || stem == ".." { stem = "招标文件" }
        return stem + "." + format.rawValue
    }

    /// Inspect only the bounded ZIP directory. Do not extract, execute, or decode any entry.
    private static func hasWordContainer(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 22, bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) else { return false }
        func value16(_ offset: Int) -> Int {
            guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
            return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
        }
        func value32(_ offset: Int) -> Int { value16(offset) | (value16(offset + 2) << 16) }
        guard let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1)
            .first(where: { value32($0) == 0x06054b50 && $0 + 22 + value16($0 + 20) == bytes.count }),
              value16(end + 4) == 0, value16(end + 6) == 0, value16(end + 8) == value16(end + 10) else { return false }
        let count = value16(end + 10)
        var offset = value32(end + 16)
        let directoryStart = offset
        let directoryEnd = offset + value32(end + 12)
        guard (1...3000).contains(count), directoryEnd <= end else { return false }
        var hasContainer = false, hasDocument = false
        for _ in 0..<count {
            guard offset + 46 <= directoryEnd, value32(offset) == 0x02014b50 else { return false }
            let flags = value16(offset + 8)
            let method = value16(offset + 10)
            let compressed = value32(offset + 20)
            let local = value32(offset + 42)
            let nameStart = offset + 46
            let nameEnd = nameStart + value16(offset + 28)
            let next = nameEnd + value16(offset + 30) + value16(offset + 32)
            guard nameEnd <= directoryEnd, next <= directoryEnd else { return false }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
            offset = next
            if name.caseInsensitiveCompare("word/vbaProject.bin") == .orderedSame { return false }
            if name == "[Content_Types].xml" || name == "word/document.xml" {
                guard flags & 1 == 0, (method == 0 || method == 8), local + 30 <= directoryStart,
                      value32(local) == 0x04034b50 else { return false }
                let start = local + 30 + value16(local + 26) + value16(local + 28)
                guard start <= directoryStart, start + compressed <= directoryStart else { return false }
                if name == "[Content_Types].xml" {
                    guard !hasContainer else { return false }
                    hasContainer = true
                } else {
                    guard !hasDocument else { return false }
                    hasDocument = true
                }
            }
        }
        return hasContainer && hasDocument && offset == directoryEnd
    }
}
