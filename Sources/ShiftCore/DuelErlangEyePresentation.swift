/// Read-only presentation record fed by already adjudicated sparring hits.
/// The source clip is real; all schedules below are *fixture* clocks.
public struct DuelErlangEyePresentation: Equatable, Encodable, Sendable {
    public static let sourceClip = "d15_avatara_laser"
    static let activeAges = 7...22
    static func isPulse(_ age: Int) -> Bool {
        activeAges.contains(age) && (age - activeAges.lowerBound) % 3 == 0
    }

    public enum Outcome: String, Encodable, Sendable { case idle, casting, hit, blocked, missed, cancelled, reset, roundEnded }
    public enum Contact: String, Encodable, Sendable { case landed, blocked }
    public private(set) var castID: UInt64 = 0
    public private(set) var visible = false
    public private(set) var active = false
    public private(set) var age = 0
    public private(set) var originX = 0
    public private(set) var direction = 1
    public private(set) var contactCount = 0
    public private(set) var landedCount = 0
    public private(set) var blockedCount = 0
    public private(set) var outcome: Outcome = .idle
    public private(set) var contact: Contact?
    public private(set) var contactX: Int?
    public private(set) var damage: Int?

    mutating func clearEdge() {
        contact = nil
        contactX = nil
        damage = nil
    }

    mutating func resetRound() {
        let id = castID
        self = .init()
        castID = id
        outcome = id == 0 ? .idle : .reset
    }

    mutating func observe(age: Int?, originX: Int, direction: Int, survived: Bool,
                          roundEnded: Bool, contact: Contact?, contactX: Int, damage: Int?) {
        guard let age else {
            // The adjudicator retires the plan after processing its final pulse.
            if visible {
                active = false
                visible = false
            }
            return
        }
        if age == 1 {
            castID += 1
            landedCount = 0
            blockedCount = 0
            contactCount = 0
        }
        self.age = age
        self.originX = originX
        self.direction = direction
        self.contact = contact
        if let contact {
            self.contactX = contactX
            self.damage = damage
            contactCount += 1
            if contact == .landed { landedCount += 1 } else { blockedCount += 1 }
        }
        visible = survived && !roundEnded
        active = visible && Self.activeAges.contains(age)
        if roundEnded { outcome = .roundEnded }
        else if !survived { outcome = .cancelled }
        else if landedCount > 0 { outcome = .hit }
        else if blockedCount > 0 { outcome = .blocked }
        else if age == Self.activeAges.upperBound { outcome = .missed }
        else { outcome = .casting }
    }
}
