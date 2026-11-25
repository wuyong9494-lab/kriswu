import Foundation

/// App-wide user identity tier distinguishing internal duty-roster personnel
/// from external registered users (phone / WeChat).
public enum AppUserAccessRole: String, Codable, Equatable, Sendable {
    /// Internal duty-roster personnel who authenticated with the duty schedule system.
    case rosterMember
    /// External registered user (phone number / WeChat / guest preview).
    /// Strictly limited to WUMIND AI, Games, and personal account settings.
    case externalUser

    public var displayTitle: String {
        switch self {
        case .rosterMember: return "值班表内部人员"
        case .externalUser: return "外部注册用户"
        }
    }

    public var boundarySummary: String {
        switch self {
        case .rosterMember:
            return "完整权限：可查看内部排班、日历、统计、网站与值班工具，以及 WUMIND AI 与游戏。"
        case .externalUser:
            return "外部界限：仅可使用 WUMIND AI 工作台、游戏中心与个人设置；已隔离并隐藏全部内部排班、花名册、值班网站、周会与工作留痕。"
        }
    }
}

/// Functional surfaces governed by `AppAccessBoundary`.
public enum AppFeatureSurface: String, CaseIterable, Sendable {
    case dutyToday
    case dutyCalendar
    case dutyStats
    case dutySite
    case dutyWorkLog
    case dutyPassPlan
    case dutyMeeting
    case wumindAI
    case games
    case accountSettings
}

/// Pure, deterministic access-boundary & credential-format policy shared across iOS UI and tests.
public enum AppAccessBoundary {
    /// Returns true iff `role` is permitted to view or open `surface`.
    public static func canAccess(_ surface: AppFeatureSurface, role: AppUserAccessRole) -> Bool {
        switch role {
        case .rosterMember:
            return true
        case .externalUser:
            switch surface {
            case .wumindAI, .games, .accountSettings:
                return true
            case .dutyToday, .dutyCalendar, .dutyStats, .dutySite, .dutyWorkLog, .dutyPassPlan, .dutyMeeting:
                return false
            }
        }
    }

    /// Blocks internal duty deep-links / notification routes for external users.
    public static func canOpenDeepLinkRoute(_ route: String, role: AppUserAccessRole) -> Bool {
        guard role == .externalUser else { return true }
        let lower = route.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("day:") || lower.hasPrefix("managed-calendar") { return false }
        let internalOnly: Set<String> = [
            "worklog", "record", "note", "rosterlog", "teamchanges",
            "notices", "meeting", "meetingmine", "passplan"
        ]
        return !internalOnly.contains(lower)
    }

    /// Validates and normalizes a Chinese mainland mobile number (`1[3-9]xxxxxxxxx`).
    public static func normalizeMainlandPhone(_ raw: String) -> String? {
        var digits = raw.filter(\.isNumber)
        if digits.hasPrefix("86") && digits.count == 13 {
            digits = String(digits.dropFirst(2))
        }
        guard digits.count == 11,
              digits.first == "1",
              let second = digits.dropFirst().first,
              ("3"..."9").contains(second) else {
            return nil
        }
        return digits
    }

    /// Masks middle 4 digits (`138****8888`) for safe UI display and logs.
    public static func maskedPhone(_ phone: String) -> String {
        guard let clean = normalizeMainlandPhone(phone) else { return phone }
        return "\(clean.prefix(3))****\(clean.suffix(4))"
    }

    /// Validates a 6-digit numeric SMS OTP code.
    public static func isValidSMSCode(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 6 && trimmed.allSatisfy(\.isNumber)
    }
}
