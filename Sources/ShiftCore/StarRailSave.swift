import Foundation

extension StarRail {
    /// One atomic document, separate from both classic and constellation keys.
    /// Keep one resumable run per stage, including its undo history via replay.
    public struct Save: Codable, Equatable, Sendable {
        public static let storageKey = "tileGame.starRails.v1"
        public let version: String
        public private(set) var progress: Progress
        public private(set) var runs: [Int: Game.Archive]
        public private(set) var selectedStage: Int

        public init() {
            version = StarRail.version
            progress = Progress()
            runs = [:]
            selectedStage = 1
        }

        public var isValid: Bool {
            version == StarRail.version && progress.isValid && progress.unlocked(selectedStage)
                && runs.count <= StarRail.stages.count && runs.allSatisfy { id, archive in
                    archive.trial == nil && archive.expeditionID == nil && archive.journey == nil && id == archive.stage && progress.unlocked(id) && Game(archive: archive) != nil
                }
        }

        public init?(data: Data) {
            guard data.count <= 131_072,
                  let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
            self = value
        }

        private enum CodingKeys: String, CodingKey { case version, progress, runs, selectedStage }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(String.self, forKey: .version)
            progress = try c.decode(Progress.self, forKey: .progress)
            runs = try c.decode([Int:Game.Archive].self, forKey: .runs)
            selectedStage = try c.decode(Int.self, forKey: .selectedStage)
            guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid campaign replay")) }
        }
        // All mutation is private or checked by keep; validate imported data once,
        // rather than replaying every saved run on each rapid pick.
        public func encoded() -> Data? { try? JSONEncoder().encode(self) }

        public func game(for id: Int) -> Game? {
            guard progress.unlocked(id), let stage = StarRail.stage(id) else { return nil }
            return runs[id].flatMap(Game.init(archive:)) ?? Game(stage: stage)
        }

        @discardableResult public mutating func keep(_ game: Game) -> Bool {
            guard version == StarRail.version, progress.unlocked(game.stage.id),
                  game.stage == StarRail.stage(game.stage.id, revision: game.stage.revision) else { return false }
            runs[game.stage.id] = game.archive
            selectedStage = game.stage.id
            if game.status == .won { progress.record(game) }
            return true
        }
    }
}
