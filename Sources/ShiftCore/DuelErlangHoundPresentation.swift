/// One observation of the independent sparring hound. Positions and sweep
/// indices are fixture units, not decoded source animation or native hit frames.
public struct DuelErlangHoundPresentation: Equatable, Encodable, Sendable {
    public enum Outcome: String, Encodable, Sendable { case hit, blocked, missed, cancelled }

    public struct Sweep: Equatable, Encodable, Sendable {
        public let start: Int
        public let end: Int
    }

    public static let sourceClip = "d15_dog_attack"
    public private(set) var castID: UInt64 = 0
    public private(set) var started = false
    public private(set) var visible = false
    public private(set) var actionAge: Int?
    public private(set) var origin: Int?
    public private(set) var direction: Int?
    public private(set) var sweep: Sweep?
    public private(set) var outcome: Outcome?
    public private(set) var contactPosition: Int?
    private var unsettled = false

    private enum CodingKeys: String, CodingKey {
        case castID, started, visible, actionAge, origin, direction, sweep, outcome, contactPosition
    }

    public init() {}

    mutating func clearObservation() {
        started = false
        visible = false
        actionAge = nil
        origin = nil
        direction = nil
        sweep = nil
        outcome = nil
        contactPosition = nil
    }

    mutating func cancelRound() {
        clearObservation()
        if unsettled { outcome = .cancelled }
        unsettled = false
    }

    mutating func observe(accepted: Bool, age: Int, origin: Int, direction: Int, sweep: Sweep?,
                          survived: Bool, atEnd: Bool, contact: Outcome?, contactPosition: Int?) {
        if accepted {
            castID &+= 1
            started = true
            unsettled = true
        }
        self.actionAge = age
        self.origin = origin
        self.direction = direction
        self.sweep = sweep
        visible = survived
        if let contact, unsettled {
            outcome = contact
            self.contactPosition = contactPosition
            unsettled = false
        } else if unsettled && !survived {
            outcome = .cancelled
            unsettled = false
        } else if unsettled && atEnd {
            outcome = .missed
            unsettled = false
        }
    }
}
