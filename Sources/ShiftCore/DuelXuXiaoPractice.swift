#if L12_INTERNAL_PREVIEW
/// Reconstructed, synthetic local practice. No official L12/D20 values, assets,
/// catalog identity, network session or replay serialization are used here.
public struct DuelXuXiaoPractice: Equatable, Sendable {
    public enum Outcome: String, Equatable, Sendable { case won, lost, draw }
    public enum Strike: Equatable, Sendable {
        case sword, heavy
        var windup: Int { self == .sword ? 8 : 20 }
        var recovery: Int { self == .sword ? 18 : 36 }
        var reach: Int { self == .sword ? 1100 : 1400 }
        var damage: Int { self == .sword ? 12 : 24 }
    }
    public struct Input: Equatable, Sendable {
        public var left = false
        public var right = false
        public var attack = false
        public var heavy = false
        public init(left: Bool = false, right: Bool = false,
                    attack: Bool = false, heavy: Bool = false) {
            self.left = left; self.right = right
            self.attack = attack; self.heavy = heavy
        }
    }
    public struct Fighter: Equatable, Sendable {
        public fileprivate(set) var x: Int
        public fileprivate(set) var health = 100
        public fileprivate(set) var facing: Int
        public fileprivate(set) var guarding = false
        public fileprivate(set) var stun = 0
        public fileprivate(set) var strike: Strike?
        public fileprivate(set) var strikeAge = 0
    }
    public struct Impact: Equatable, Sendable {
        public let tick: Int
        public let x: Int
        public let blocked: Bool
    }
    public static let ticksPerSecond = 60
    public static let maximumTicks = 3600
    public private(set) var fighters = [Fighter(x: 3900, facing: 1), Fighter(x: 6100, facing: -1)]
    public private(set) var tick = 0
    public private(set) var outcome: Outcome?
    public private(set) var lastImpact: Impact?
    public private(set) var feedback = "替代练习开始：靠近后攻击，向后移动可防御。"
    public var remainingSeconds: Int { max(0, (Self.maximumTicks - tick + 59) / 60) }
    public init() {}

    /// One explicit synthetic 1/60-second step. No wall clock or catch-up.
    public mutating func step(_ input: Input) {
        guard outcome == nil else { return }
        tick += 1
        if let impact = lastImpact, tick - impact.tick >= 12 { lastImpact = nil }
        let gap = abs(fighters[1].x - fighters[0].x)
        let aiApproach = gap > 900
        let aiFacing = fighters[0].x > fighters[1].x ? 1 : -1
        let ai = Input(left: aiApproach && aiFacing < 0,
                       right: aiApproach && aiFacing > 0,
                       attack: !aiApproach && tick % 48 == 0)
        let inputs = [input, ai]
        for seat in 0...1 {
            let other = 1 - seat
            let direction = inputs[seat].left == inputs[seat].right ? 0 : inputs[seat].left ? -1 : 1
            fighters[seat].facing = fighters[other].x > fighters[seat].x ? 1 : -1
            fighters[seat].guarding = false
            if fighters[seat].stun > 0 { fighters[seat].stun -= 1; continue }
            if let strike = fighters[seat].strike {
                fighters[seat].strikeAge += 1
                if fighters[seat].strikeAge >= strike.windup + strike.recovery {
                    fighters[seat].strike = nil; fighters[seat].strikeAge = 0
                }
                continue
            }
            if inputs[seat].attack || inputs[seat].heavy {
                fighters[seat].strike = inputs[seat].heavy ? .heavy : .sword
                fighters[seat].strikeAge = 0
            } else {
                fighters[seat].guarding = direction == -fighters[seat].facing
                let next = min(9300, max(700, fighters[seat].x + direction * 48))
                // Fixed seats never cross. This is a schematic lane, not physics.
                fighters[seat].x = seat == 0 ? min(next, fighters[1].x - 500) : max(next, fighters[0].x + 500)
            }
        }
        // Evaluate both contacts before applying either. Trades are symmetric.
        let before = fighters
        var hits: [(victim: Int, damage: Int, blocked: Bool)] = []
        for seat in 0...1 {
            guard let strike = before[seat].strike,
                  before[seat].strikeAge == strike.windup,
                  before[seat].stun == 0,
                  abs(before[seat].x - before[1 - seat].x) <= strike.reach else { continue }
            let blocked = before[1 - seat].guarding
            hits.append((1 - seat, blocked ? 2 : strike.damage, blocked))
        }
        for hit in hits {
            fighters[hit.victim].health = max(0, fighters[hit.victim].health - hit.damage)
            fighters[hit.victim].stun = hit.blocked ? 4 : 10
            fighters[hit.victim].strike = nil
            fighters[hit.victim].strikeAge = 0
            lastImpact = Impact(tick: tick, x: fighters[hit.victim].x, blocked: hit.blocked)
            feedback = "\(hit.victim == 1 ? "徐骁" : "练习对手")\(hit.blocked ? "攻击被挡" : "命中") · \(hit.damage) 点"
        }
        if fighters[0].health == 0 || fighters[1].health == 0 || tick >= Self.maximumTicks {
            outcome = fighters[0].health == fighters[1].health ? .draw : fighters[0].health > fighters[1].health ? .won : .lost
            for seat in 0...1 { fighters[seat].guarding = false; fighters[seat].strike = nil }
            feedback = "本局结束。此结果仅属于替代练习，不计入正式对战。"
        }
    }
}
#endif
