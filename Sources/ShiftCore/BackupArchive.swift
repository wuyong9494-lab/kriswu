import Foundation

/// 先校验备份的完整结构，再交给 App 替换现有数据。
/// 设置内部仍由 App 逐字段兼容旧格式；排班、覆盖日期、全员排班不能把损坏的数据当成空数据。
public struct BackupArchive {
    public static let currentVersion = 2

    public let version: Int
    public let settings: [String: Any]
    public let schedule: [DayKey: String]
    public let covered: Set<DayKey>
    public let roster: Roster
    public let meeting: [String: Any]?
    public let records: [String: Any]?

    public enum ReadError: LocalizedError, Equatable {
        case invalidFile
        case missingField(String)
        case invalidField(String)
        case unsupportedVersion(Int)
        case invalidDate(field: String, value: String)
        case duplicateDate(field: String, value: String)

        public var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "这不是值班提醒的备份文件"
            case .missingField(let field):
                return "备份缺少数据：\(field)，没有恢复"
            case .invalidField(let field):
                return "备份数据格式不正确：\(field)，没有恢复"
            case .unsupportedVersion(let version):
                return "不支持这个备份版本（\(version)），请使用与备份匹配的 App 版本"
            case .invalidDate(let field, let value):
                return "备份中的日期不正确：\(field) / \(value)，没有恢复"
            case .duplicateDate(let field, let value):
                return "备份中同一天有重复数据：\(field) / \(value)，没有恢复"
            }
        }
    }

    public init(data: Data) throws {
        guard let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ReadError.invalidFile
        }

        if file["version"] != nil {
            // JSONDecoder 会拒绝布尔值、字符串、小数和 null，不让它们冒充版本号。
            guard let header = try? JSONDecoder().decode(VersionHeader.self, from: data) else {
                throw ReadError.invalidField("version")
            }
            version = header.version
        } else {
            // 兼容未带版本号的旧格式，至少必须包含设置和个人排班。
            version = 1
        }
        guard (1...Self.currentVersion).contains(version) else {
            throw ReadError.unsupportedVersion(version)
        }

        settings = try Self.object(in: file, key: "settings")
        schedule = try Self.days(in: Self.object(in: file, key: "schedule"), field: "schedule")

        if let raw = file["covered"] {
            guard let dates = raw as? [String] else { throw ReadError.invalidField("covered") }
            covered = Set(try dates.map { try Self.day($0, field: "covered") })
        } else if version >= 2 {
            throw ReadError.missingField("covered")
        } else {
            // 旧备份没记覆盖范围，只把确实有排班的日子记为已取得，其他日子仍是未知。
            covered = Set(schedule.keys)
        }

        if let raw = file["roster"] {
            guard let people = raw as? [String: Any] else { throw ReadError.invalidField("roster") }
            var restored: Roster = [:]
            for (name, rawDays) in people {
                let field = "roster.\(name)"
                guard let dates = rawDays as? [String: Any] else { throw ReadError.invalidField(field) }
                restored[name] = try Self.days(in: dates, field: field)
            }
            roster = restored
        } else if version >= 2 {
            throw ReadError.missingField("roster")
        } else {
            roster = [:]
        }

        // 周会和记录是后来独立出来的段；旧备份从 settings 中迁移，缺少或 null 均表示未提供。
        meeting = try Self.optionalObject(in: file, key: "meeting")
        records = try Self.optionalObject(in: file, key: "records")
    }

    private struct VersionHeader: Decodable {
        let version: Int
    }

    private static func object(in file: [String: Any], key: String) throws -> [String: Any] {
        guard let raw = file[key] else { throw ReadError.missingField(key) }
        guard let object = raw as? [String: Any] else { throw ReadError.invalidField(key) }
        return object
    }

    private static func optionalObject(in file: [String: Any], key: String) throws -> [String: Any]? {
        guard let raw = file[key], !(raw is NSNull) else { return nil }
        guard let object = raw as? [String: Any] else { throw ReadError.invalidField(key) }
        return object
    }

    private static func days(in object: [String: Any], field: String) throws -> [DayKey: String] {
        var days: [DayKey: String] = [:]
        for (key, raw) in object {
            let date = try day(key, field: field)
            guard let value = raw as? String else { throw ReadError.invalidField("\(field).\(key)") }
            guard days[date] == nil else { throw ReadError.duplicateDate(field: field, value: date.description) }
            days[date] = value
        }
        return days
    }

    private static func day(_ value: String, field: String) throws -> DayKey {
        // 旧备份允许未补零的日期；字典里的同日重复键由 days(in:field:) 单独拒绝。
        guard let day = DayKey(string: value) else {
            throw ReadError.invalidDate(field: field, value: value)
        }
        return day
    }
}
