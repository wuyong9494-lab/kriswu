import Foundation

extension StarRail {
    /// Versioned, offline-curated layouts. Seeds alter kind placement, not just
    /// color names. The six templates have different occlusion/rail graphs.
    public struct Expedition: Identifiable, Equatable, Sendable {
        public static let count = 36
        public let id: Int
        public init?(id: Int) { guard (1...Self.count).contains(id) else { return nil }; self.id = id }
        public var template: Int { (id - 1) / 6 }
        public var code: String { String(format: "XP1-%03d", id) }
        public var stage: Stage { Self.make(template: template, seed: Self.seeds[template][(id - 1) % 6], id: id) }
        public static let all = (1...count).map { Expedition(id: $0)! }
        // XP1 is frozen with a full geometry/pairing fingerprint regression.
        // The later three groups are curated against shallow greedy choices;
        // this is an automated control, not a human difficulty measurement.
        static let seeds: [[UInt64]] = [[1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6], [2, 17, 22, 34, 46, 47], [2, 63, 79, 266, 307, 336], [14, 27, 84, 88, 107, 132]]
        public static func decode(_ text: String) -> Expedition? {
            guard text.utf8.count <= 8_192,
                  let regex = try? NSRegularExpression(pattern: "(?<![A-Z0-9-])XP[0-9]+-[A-Z0-9-]+(?![A-Z0-9-])") else { return nil }
            let upper = text.uppercased()
            let codes = Set(regex.matches(in: upper, range: NSRange(upper.startIndex..., in: upper))
                .compactMap { Range($0.range, in: upper).map { String(upper[$0]) } })
            guard codes.count == 1, let code = codes.first, code.count == 7, let id = Int(code.suffix(3)),
                  let expedition = Expedition(id: id), expedition.code == code else { return nil }
            return expedition
        }
        public static func containsCodePrefix(_ text: String) -> Bool {
            guard text.utf8.count <= 8_192 else { return true }
            return text.uppercased().range(of: "(?<![A-Z0-9-])XP[0-9]+-", options: .regularExpression) != nil
        }
        public static func daily(at date: Date) -> Expedition {
            let calendar = Calendar.dayMath
            let start = DayKey(year: 2026, month: 1, day: 1).date(calendar: calendar)
            let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
            // Coprime stride interleaves templates instead of six identical skeletons in a row.
            let slot = ((days % count) + count) % count
            return Expedition(id: (slot * 7) % count + 1)!
        }
        public var shareText: String {
            "来「\(TileGame.displayName)」走一条自己的航线：\(stage.title)。远征码 \(code)，在首页挑战码中粘贴即可同盘挑战。"
        }

        /// Internal for catalog authoring/audit; runtime only uses curated seeds.
        static func make(template: Int, seed: UInt64, id: Int) -> Stage {
            let rows = [[5,5,5,3], [5,4,5,4], [5,5,5,5], [5,5,5,5], [5,5,5,5], [4,5,4,5]][template]
            var positions: [(Int, Int, Int, Int?)] = []
            for (y, width) in rows.enumerated() { for x in 0..<width { positions.append((x*4, y*4, 0, nil)) } }
            var rails: [Rail] = []
            func middle(_ x: Int, _ y: Int) { positions.append((x, y, 1, nil)) }
            func member(_ rail: Int, _ x: Int, _ y: Int, _ z: Int) { positions.append((x, y, z, rail)) }
            func fork(_ id: Int, _ near: Point, _ far: Point) {
                rails.append(Rail(id: id, name: id == 0 ? "轨道 A" : "轨道 B", delta: near, extraStops: [far]))
            }
            switch template {
            case 0:
                for x in [4,8,12] { middle(x,4); member(0,x,4,2) }
                fork(0, Point(x:-4,y:4), Point(x:4,y:8))
            case 1:
                for x in [0,4,8] { middle(x,8); member(0,x,8,2) }
                fork(0, Point(x:8,y:-4), Point(x:8,y:4))
            case 2:
                middle(8,8)
                for x in [4,8,12] { member(0,x,4,1) }
                fork(0, Point(x:0,y:4), Point(x:0,y:8))
            case 3:
                middle(0,4); middle(4,4); middle(8,8)
                for x in [0,4] { member(0,x,4,2) }
                for x in [8,12] { member(1,x,4,2) }
                fork(0, Point(x:8,y:0), Point(x:8,y:8))
                rails.append(Rail(id:1,name:"轨道 B",delta:Point(x:0,y:4)))
            case 4:
                middle(16,12)
                for x in [0,4,8] { member(0,x,8,1) }
                for x in [4,8,12] { member(1,x,4,2) }
                fork(0, Point(x:0,y:-4), Point(x:8,y:4))
                rails.append(Rail(id:1,name:"轨道 B",delta:Point(x:0,y:8)))
            default:
                middle(0,4); middle(4,8); middle(12,12)
                for x in [0,4,8] { member(0,x,4,2) }
                for x in [4,8,12] { member(1,x,8,2) }
                fork(0, Point(x:8,y:0), Point(x:0,y:8))
                fork(1, Point(x:0,y:-4), Point(x:-4,y:4))
            }
            precondition(positions.count.isMultiple(of: 3))
            var kinds: [Int] = []
            for kind in 1..<(positions.count / 3) { kinds += [kind, kind, kind] }
            var random = SeededRandom(seed: seed); random.shuffle(&kinds)
            kinds = [0,0,0] + kinds
            let cards = positions.enumerated().map { index, p in
                Card(id:index,kind:kinds[index],x:p.0,y:p.1,z:p.2,rail:p.3)
            }
            let titles = ["双岔星门", "折角回航", "中央风眼", "双星接驳", "上下回响", "环岛夜航"]
            let lessons = ["不同终点，露出不同的第三张", "比较横向开窗与纵向返程", "先处理岔口的同层挡牌", "绕行或让行，由你选择", "上层轨道控制下层返程", "两条分岔共享落点"]
            return Stage(id:100+id,title:"\(titles[template]) · \((id-1)%6+1)",lesson:lessons[template],
                objective: "选择任一岔口，完成\(rails.count == 1 ? "A" : "A、B")往返，再清空棋盘",
                tip:"近岔消耗 1 点能量，远岔消耗 2 点。先看两处终点露出和盖住哪些牌；岔口之间必须经起点中转。最后一张轨道牌留到返航完成。",
                cards:cards,rails:rails,requiredArrivals:rails.count == 1 ? 1 : 9,
                plannedMoves:rails.count*2,targetPeak:5,revision:3,expeditionID:id)
        }
    }

    public struct ExpeditionSave: Codable, Equatable, Sendable {
        public static let storageKey = "tileGame.starExpeditions.v1"
        public let version: Int
        public private(set) var runs: [Int: Game.Archive]
        public private(set) var best: [Int: Game.Archive]
        public init() { version = 1; runs = [:]; best = [:] }
        public var isValid: Bool {
            guard version == 1, runs.count <= Expedition.count, best.count <= Expedition.count else { return false }
            func valid(_ entries: [Int: Game.Archive], wins: Bool) -> Bool {
                entries.allSatisfy { id, archive in
                    guard let expedition = Expedition(id:id), let game = Game(archive:archive), game.stage == expedition.stage else { return false }
                    return !wins || game.status == .won
                }
            }
            return valid(runs,wins:false) && valid(best,wins:true)
        }
        public init?(data: Data) {
            guard data.count <= 1_048_576, let value = try? JSONDecoder().decode(Self.self,from:data) else { return nil }
            self = value
        }
        private enum CodingKeys: String, CodingKey { case version, runs, best }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self,forKey:.version)
            runs = try c.decode([Int:Game.Archive].self,forKey:.runs)
            best = try c.decode([Int:Game.Archive].self,forKey:.best)
            guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid expedition replay")) }
        }
        public func encoded() -> Data? { try? JSONEncoder().encode(self) }
        public func game(for expedition: Expedition) -> Game { runs[expedition.id].flatMap(Game.init(archive:)) ?? Game(stage:expedition.stage) }
        public func record(for expedition: Expedition) -> Game? { best[expedition.id].flatMap(Game.init(archive:)) }
        public var totalStars: Int { best.values.compactMap(Game.init(archive:)).reduce(0) { $0 + $1.stars } }
        public var next: Expedition { Expedition.all.first { best[$0.id] == nil } ?? Expedition.all[0] }
        @discardableResult public mutating func keep(_ game: Game) -> Bool {
            guard let id = game.stage.expeditionID, let expedition = Expedition(id:id),game.stage == expedition.stage else { return false }
            runs[id] = game.archive
            if game.status == .won {
                if let previous = record(for:expedition) {
                    if TrialSave.isBetter(game,than:previous) { best[id] = game.archive }
                } else { best[id] = game.archive }
            }
            return true
        }
    }
}
