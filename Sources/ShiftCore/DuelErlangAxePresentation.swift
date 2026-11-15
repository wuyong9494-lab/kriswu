/// A private sparring presentation feed. Neither the timing nor numerical
/// values are a claim about the source game.
public struct DuelErlangAxePresentation: Equatable, Encodable, Sendable {
    public static let sourceClip = "d15_avatara_axe_slash"
    public enum Outcome: String, Encodable, Sendable { case idle, casting, landed, blocked, missed, cancelled, reset, roundEnded }
    public enum Contact: String, Encodable, Sendable { case landed, blocked }
    public enum QuakeOutcome: String, Encodable, Sendable { case landed, blocked, missed }

    public struct Schedule: Equatable, Encodable, Sendable {
        public let originX: Int
        public let dueTick: Int
        public let direction: Int
    }
    public struct Quake: Equatable, Encodable, Sendable {
        public let originX: Int
        public let dueTick: Int
        public let direction: Int
        public let outcome: QuakeOutcome
        public let damage: Int?
        public let contactX: Int?
    }

    public private(set) var castID: UInt64 = 0
    public private(set) var age = 0
    public private(set) var originX = 0
    public private(set) var direction = 1
    public private(set) var visible = false
    public private(set) var outcome: Outcome = .idle
    public private(set) var contact: Contact?
    public private(set) var contactX: Int?
    public private(set) var damage: Int?
    public private(set) var pendingQuake: Schedule?
    public private(set) var quake: Quake?

    mutating func clearEdges() {
        contact = nil
        contactX = nil
        damage = nil
        quake = nil
    }

    mutating func reset() {
        let id = castID
        self = .init()
        castID = id
        if id > 0 { outcome = .reset }
    }

    mutating func observeSwing(age: Int?, originX: Int, direction: Int,
                               survives: Bool, terminalAge: Int, finished: Bool,
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
        self.originX = originX
        self.direction = direction
        visible = survives && !finished
        if let contact {
            self.contact = contact
            self.contactX = contactX
            self.damage = damage
            outcome = contact == .landed ? .landed : .blocked
        }
        if finished { outcome = .roundEnded }
        else if !survives { outcome = .cancelled }
        else if age >= terminalAge && outcome == .casting { outcome = .missed }
    }

    mutating func observeQuake(pending: Schedule?, fired: Schedule?, hit: Contact?,
                               contactX: Int, damage: Int?) {
        pendingQuake = pending
        if let fired {
            quake = Quake(originX: fired.originX, dueTick: fired.dueTick, direction: fired.direction,
                          outcome: hit == .landed ? .landed : hit == .blocked ? .blocked : .missed,
                          damage: damage, contactX: hit == nil ? nil : contactX)
        }
    }
}
