/// Gold stomp view for the independent sparring fixture. The native clip is
/// separate; the combat step and active interval are not verified source timing.
public struct DuelErlangStepPresentation: Equatable, Encodable, Sendable {
    public static let sourceClip = "d15_avatara_stomp"
    public enum Outcome: String, Encodable, Sendable { case idle, casting, landed, blocked, missed, cancelled, reset, roundEnded }
    public enum Contact: String, Encodable, Sendable { case landed, blocked }

    public private(set) var castID: UInt64 = 0
    public private(set) var age = 0
    public private(set) var stage = 0
    public private(set) var originX = 0
    public private(set) var direction = 1
    public private(set) var visible = false
    public private(set) var groundBeat = false
    public private(set) var outcome: Outcome = .idle
    public private(set) var contact: Contact?
    public private(set) var contactX: Int?
    public private(set) var damage: Int?

    mutating func clearEdges() {
        groundBeat = false
        contact = nil
        contactX = nil
        damage = nil
    }

    mutating func reset() {
        let id = castID
        self = .init()
        castID = id
        if id > 0 { outcome = .reset }
    }

    mutating func observe(age: Int?, stage: Int, originX: Int, direction: Int,
                          lived: Bool, ended: Bool, activeAges: ClosedRange<Int>,
                          contact: Contact?, contactX: Int, damage: Int?) {
        guard let age else {
            visible = false
            return
        }
        if age == 1 {
            castID += 1
            outcome = .casting
        }
        self.age = age
        self.stage = stage
        self.originX = originX
        self.direction = direction
        visible = lived && !ended
        // A timed ground beat is separate from collision. The plan was still
        // valid when the resolver took its simultaneous-hit snapshot.
        groundBeat = age == activeAges.lowerBound
        if let contact {
            self.contact = contact
            self.contactX = contactX
            self.damage = damage
            outcome = contact == .landed ? .landed : .blocked
        }
        if ended { outcome = .roundEnded }
        else if !lived { outcome = .cancelled }
        else if age >= activeAges.upperBound && outcome == .casting { outcome = .missed }
    }
}
