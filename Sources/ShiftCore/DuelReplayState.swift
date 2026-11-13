import Foundation

/// Canonical diagnostic bytes, not a save format, network packet, or cryptographic
/// digest. See docs/fighter-replay-state-encoding.md before changing this schema.
/// Full equipped profiles are included: asset SHA strings alone do not verify
/// the roles, combo links and collision tracks used by the simulation.
public enum DuelReplayStateEncoding {
    public static let schemaVersion: UInt16 = 2
    /// Bump when simulation semantics/constants change, even without new fields.
    public static let rulesVersion: UInt16 = 5
    public static let maximumBytes = 64 * 1024 * 1024
    public static let maximumStringBytes = 4096
    public static let maximumCollectionCount = 16_384

    public enum Failure: Error, Equatable {
        case byteLimit, stringLimit, collectionLimit
    }

    public static func encode(_ game: DuelGame) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 1)
        try game.appendReplayState(to: &writer)
        return writer.data
    }

    public static func encode(_ fight: DuelWeaponFight) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try fight.appendReplayState(to: &writer)
        return writer.data
    }

    /// Separate full catalog bytes for a caller that later uses a platform SHA.
    /// This does not assert resource authentication or replace catalog.validate().
    public static func encodeCatalog(_ catalog: DuelWeaponCatalog) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 3)
        try writer.int(catalog.schemaVersion)
        try writer.int(catalog.previewFramesPerSecond)
        try writer.optional(catalog.sourceFramesPerSecond) { try $0.double($1) }
        try writer.array(catalog.profiles, limit: 2) { try $0.profile($1) }
        return writer.data
    }
}

/// All integers have explicit widths and little-endian byte order. Floating
/// values retain their exact IEEE-754 bitPattern, including signed zero and NaN
/// payloads. No rounding/normalization, native memory layout, Hasher or reflection.
struct DuelReplayStateWriter {
    private(set) var data = Data()
    private let byteLimit: Int

    init(kind: UInt8, byteLimit: Int = DuelReplayStateEncoding.maximumBytes) throws {
        self.byteLimit = min(byteLimit, DuelReplayStateEncoding.maximumBytes)
        for byte in [UInt8(0x44), 0x55, 0x45, 0x4c, 0x53, 0x54, 0x41, 0x54] { try u8(byte) } // DUELSTAT
        try u16(DuelReplayStateEncoding.schemaVersion)
        try u16(DuelReplayStateEncoding.rulesVersion)
        try u8(kind)
    }

    private func require(_ count: Int) throws {
        guard count >= 0, count <= byteLimit, data.count <= byteLimit - count else {
            throw DuelReplayStateEncoding.Failure.byteLimit
        }
    }
    mutating func u8(_ value: UInt8) throws { try require(1); data.append(value) }
    mutating func u16(_ value: UInt16) throws {
        try require(2)
        for shift in stride(from: 0, to: 16, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    mutating func u32(_ value: UInt32) throws {
        try require(4)
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    mutating func u64(_ value: UInt64) throws {
        try require(8)
        for shift in stride(from: 0, to: 64, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    mutating func int(_ value: Int) throws { try u64(UInt64(bitPattern: Int64(value))) }
    mutating func bool(_ value: Bool) throws { try u8(value ? 1 : 0) }
    mutating func double(_ value: Double) throws { try u64(value.bitPattern) }
    mutating func string(_ value: String) throws {
        let bytes = value.utf8
        guard bytes.count <= DuelReplayStateEncoding.maximumStringBytes else {
            throw DuelReplayStateEncoding.Failure.stringLimit
        }
        try u32(UInt32(bytes.count)); try require(bytes.count); data.append(contentsOf: bytes)
    }
    mutating func optional<T>(_ value: T?, _ encode: (inout Self, T) throws -> Void) throws {
        try bool(value != nil)
        if let value { try encode(&self, value) }
    }
    mutating func array<T>(_ values: [T], limit: Int = DuelReplayStateEncoding.maximumCollectionCount,
                           _ encode: (inout Self, T) throws -> Void) throws {
        guard values.count <= min(limit, DuelReplayStateEncoding.maximumCollectionCount) else {
            throw DuelReplayStateEncoding.Failure.collectionLimit
        }
        try u32(UInt32(values.count))
        for value in values { try encode(&self, value) }
    }

    mutating func hero(_ value: DuelGame.Hero) throws {
        switch value { case .ember: try u8(0); case .gale: try u8(1); case .liu: try u8(2) }
    }
    mutating func difficulty(_ value: DuelGame.Difficulty) throws {
        switch value { case .learning: try u8(0); case .challenging: try u8(1) }
    }
    mutating func mode(_ value: DuelGame.Mode) throws {
        switch value { case .versus: try u8(0); case .practice: try u8(1); case .tutorial: try u8(2) }
    }
    mutating func move(_ value: DuelGame.Move) throws {
        switch value {
        case .jab: try u8(0); case .cross: try u8(1); case .finisher: try u8(2)
        case .heavy: try u8(3); case .skill1: try u8(4); case .skill2: try u8(5); case .ultimate: try u8(6)
        }
    }
    mutating func command(_ value: DuelWeaponCommand) throws {
        switch value {
        case .weapon: try u8(0); case .weaponForward: try u8(1); case .weaponUp: try u8(2)
        case .weaponDown: try u8(3); case .weaponBack: try u8(4); case .heavy: try u8(5)
        case .kick: try u8(6); case .kickForward: try u8(7); case .kickUp: try u8(8)
        case .kickDown: try u8(9); case .kickBack: try u8(10); case .shadow: try u8(11); case .ranged: try u8(12)
        }
    }
    mutating func phase(_ value: DuelGame.Phase) throws {
        switch value {
        case .fighting: try u8(0)
        case .roundBreak(let winner, let remaining):
            try u8(1); try optional(winner) { try $0.int($1) }; try int(remaining)
        case .matchOver(let winner): try u8(2); try int(winner)
        }
    }
    mutating func event(_ value: DuelGame.Event) throws {
        switch value {
        case .hit(let attacker, let damage): try u8(0); try int(attacker); try int(damage)
        case .blocked(let defender): try u8(1); try int(defender)
        case .guardBreak(let defender): try u8(2); try int(defender)
        case .whiff(let attacker): try u8(3); try int(attacker)
        case .jumped(let player): try u8(4); try int(player)
        case .roundEnded(let winner): try u8(5); try optional(winner) { try $0.int($1) }
        case .grappleStarted(let attacker): try u8(6); try int(attacker)
        case .grappleSlam(let attacker): try u8(7); try int(attacker)
        case .grappleReleased(let attacker): try u8(8); try int(attacker)
        case .grappleClash: try u8(9)
        }
    }
    mutating func input(_ value: DuelGame.Input) throws {
        try int(value.move); try bool(value.guardHeld); try int(value.taps.rawValue); try int(value.vertical)
        try optional(value.weaponCommand) { try $0.command($1) }
    }
    mutating func attack(_ value: DuelGame.Attack) throws {
        try move(value.move); try int(value.age); try bool(value.connected)
        try bool(value.spawned); try bool(value.comboQueued)
    }
    mutating func fighter(_ value: DuelGame.Fighter) throws {
        try hero(value.hero); try int(value.x); try int(value.y); try int(value.velocityY); try int(value.facing)
        try int(value.health); try int(value.guardMeter); try int(value.energy); try int(value.stun)
        try int(value.knockdown); try int(value.invulnerable); try bool(value.guarding)
        try optional(value.attack) { try $0.attack($1) }
        try int(value.flash); try bool(value.walking); try int(value.movementDirection)
        try optional(value.weaponPose) { try $0.pose($1) }
    }
    mutating func projectile(_ value: DuelGame.Projectile) throws {
        try int(value.id); try int(value.owner); try int(value.x); try int(value.direction); try int(value.lifetime)
    }
    mutating func grapple(_ value: DuelGame.Grapple) throws {
        try int(value.attacker); try int(value.direction); try int(value.age)
    }
    mutating func pose(_ value: DuelWeaponPose) throws {
        try string(value.clip); try int(value.tick); try int(value.duration)
        try double(value.groundLift); try bool(value.reaction)
    }
    mutating func point(_ value: DuelWeaponPoint) throws {
        try double(value.x); try double(value.y); try double(value.z)
    }
    mutating func contact(_ value: DuelWeaponFight.Contact) throws {
        switch value.kind { case .hit: try u8(0); case .block: try u8(1) }
        try int(value.attacker); try point(value.position); try int(value.direction)
        try bool(value.heavy); try bool(value.usesWeapon)
    }
    mutating func swing(_ value: DuelWeaponFight.Swing) throws {
        try int(value.attacker); try bool(value.heavy); try bool(value.usesWeapon)
    }
    mutating func profile(_ value: DuelWeaponProfile) throws {
        try string(value.id); try hero(value.hero); try string(value.faction); try string(value.resourceName)
        try int(value.bytes); try string(value.sha256); try string(value.bodyID); try string(value.weaponID)
        try array(value.activeWeaponSides, limit: 2) { try $0.string($1) }
        // Do not use dictionary iteration order, locale or Swift hash seeds.
        guard value.roles.count <= DuelReplayStateEncoding.maximumCollectionCount else {
            throw DuelReplayStateEncoding.Failure.collectionLimit
        }
        let keys = value.roles.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        try array(keys) { writer, key in
            try writer.string(key); try writer.string(value.roles[key]!)
        }
        try array(value.clips) { try $0.clip($1) }
        try optional(value.comboLinks) { writer, links in
            try writer.array(links) { try $0.combo($1) }
        }
    }
    mutating func clip(_ value: DuelWeaponClip) throws {
        try string(value.name); try int(value.frames); try string(value.sha256); try string(value.bundle)
        try tracks(value.tracks)
    }
    mutating func tracks(_ value: DuelWeaponTracks) throws {
        try int(value.samplesPerSourceFrame)
        try array(value.root) { try $0.point($1) }; try array(value.handL) { try $0.point($1) }
        try array(value.handR) { try $0.point($1) }; try array(value.footL) { try $0.point($1) }
        try array(value.footR) { try $0.point($1) }; try array(value.weaponBaseL) { try $0.point($1) }
        try array(value.weaponTipL) { try $0.point($1) }; try array(value.weaponBaseR) { try $0.point($1) }
        try array(value.weaponTipR) { try $0.point($1) }; try array(value.groundLift) { try $0.double($1) }
    }
    mutating func combo(_ value: DuelWeaponComboLink) throws {
        try string(value.from); try string(value.to); try int(value.sourceFrame)
    }
}
