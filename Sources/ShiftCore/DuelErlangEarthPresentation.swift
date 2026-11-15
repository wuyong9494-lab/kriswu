/// Display-only view of the sparring resolver. The original assets are separate
/// from this module. Timings, range, damage and effect placement are fixtures.
public struct DuelErlangEarthPresentation: Equatable, Encodable, Sendable {
    public static let sourceClip = "d15_avatara_spear_earthshake"
    public enum State: String, Encodable, Sendable {
        case idle, casting, impact, cancelled, reset, roundEnded
    }
    public enum Contact: String, Encodable, Sendable { case landed, blocked, missed }
    public struct Impact: Equatable, Encodable, Sendable {
        public let originX: Int
        public let outcome: Contact
        public let damage: Int?
        public let contactX: Int?
    }
    public struct Barrage: Equatable, Encodable, Sendable {
        public let released: Int
        public let originX: Int
        public let landed: Int
        public let blocked: Int
        public let damage: Int
        public let contactX: Int?
    }
    public private(set) var castID: UInt64 = 0
    public private(set) var age = 0
    public private(set) var originX = 0
    public private(set) var direction = 1
    public private(set) var visible = false
    public private(set) var outcome: State = .idle
    public private(set) var consumed = 0
    public private(set) var impact: Impact?
    public private(set) var barrage: Barrage?

    mutating func clearEdges() {
        impact = nil
        barrage = nil
    }

    mutating func reset() {
        let id = castID
        self = .init()
        castID = id
        if id > 0 { outcome = .reset }
    }

    mutating func observe(age: Int?, originX: Int, direction: Int, consumed: Int,
                          visible: Bool, finished: Bool, impact: Impact?, barrage: Barrage?) {
        guard let age else {
            self.visible = false
            return
        }
        if age == 1 {
            castID += 1
            outcome = .casting
        }
        self.age = age
        self.originX = originX
        self.direction = direction
        self.consumed = consumed
        self.visible = visible && !finished
        self.impact = impact
        self.barrage = barrage
        if finished { outcome = .roundEnded }
        else if impact != nil { outcome = .impact }
        else if !visible { outcome = .cancelled }
    }
}
