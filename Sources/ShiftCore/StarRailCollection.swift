import Foundation

extension StarRail {
    public enum SkyTheme: String, Codable, CaseIterable, Sendable {
        case midnight, dawn, nebula
        public var title: String { self == .midnight ? "静夜星海" : self == .dawn ? "日出航道" : "紫晶星云" }
        public var requiredStars: Int { self == .midnight ? 0 : self == .dawn ? 9 : 30 }
    }
    public enum CardBack: String, Codable, CaseIterable, Sendable {
        case starlines, orbit, aurora, solar
        public var title: String {
            switch self { case .starlines:return "星线"; case .orbit:return "环轨"; case .aurora:return "极光"; case .solar:return "日珥" }
        }
        public var requiredStars: Int {
            switch self { case .starlines:return 0; case .orbit:return 6; case .aurora:return 18; case .solar:return 36 }
        }
    }
    public struct Journal: Codable, Equatable, Sendable {
        public static let storageKey = "tileGame.starJournal.v1"
        public let version: Int
        public private(set) var sky: SkyTheme
        public private(set) var back: CardBack
        public private(set) var dismissedLessons: Set<Lesson>
        public init() { version = 1; sky = .midnight; back = .starlines; dismissedLessons = [] }
        public init?(data: Data) {
            guard data.count <= 8_192, let value = try? JSONDecoder().decode(Self.self,from:data),value.version == 1 else { return nil }
            self = value
        }
        public func encoded() -> Data? { version == 1 ? try? JSONEncoder().encode(self) : nil }
        @discardableResult public mutating func select(sky: SkyTheme, earned: Int) -> Bool {
            guard version == 1, earned >= sky.requiredStars else { return false }; self.sky = sky; return true
        }
        @discardableResult public mutating func select(back: CardBack, earned: Int) -> Bool {
            guard version == 1, earned >= back.requiredStars else { return false }; self.back = back; return true
        }
        public mutating func dismiss(_ lesson: Lesson) { dismissedLessons.insert(lesson) }
        public mutating func resetLessons() { dismissedLessons = [] }
    }
    public enum StarMap {
        public static let thresholds = [1,3,6,9,12,18,24,30,36,48,60,72]
        /// Main R1/R2 scores for the same stage count once. Repeating the same
        /// challenge cannot farm stars; only each record's best score counts.
        public static func earned(progress: Progress, trials: TrialSave, expeditions: ExpeditionSave) -> Int {
            let main = (1...6).reduce(0) { $0 + max(progress.stars[$1] ?? 0,progress.legacyStars[$1] ?? 0) }
            let contracts = trials.best.values.compactMap(Game.init(archive:)).reduce(0) { $0 + $1.stars }
            return main + contracts + expeditions.totalStars
        }
        public static func restored(earned: Int) -> Int { thresholds.filter { $0 <= earned }.count }
        public static func next(earned: Int) -> Int? { thresholds.first { $0 > earned } }
    }
}
