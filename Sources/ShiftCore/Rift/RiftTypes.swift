import Foundation

// 裂隙对决 · 原创战斗核心
//
// 这里只有纯数据和纯逻辑：60 帧确定性模拟、帧数据、命中判定、打击感参数。
// 不依赖任何外部美术资源，也不包含任何第三方游戏的数值；所有招式和数值
// 都是为本项目原创设计的，可以在 Linux / macOS 上直接 `swift test`。

public enum RiftHeroID: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 孙登：双刀速攻
    case sunDeng
    /// 吴庸：幕府武将，大太刀，格挡反击
    case wuYong
    /// 刘泉纬：盘古，开天巨斧，重击霸体
    case liuQuanwei
    /// 徐骁：嬴政，秦剑，中距离控场
    case xuXiao

    public var id: String { rawValue }
}

/// 每个英雄的招式槽位。招式的具体内容由 `RiftHeroSpec` 决定。
public enum RiftMoveSlot: String, CaseIterable, Codable, Sendable {
    case light1, light2, light3
    case heavy
    case airAttack
    case skill1, skill2
    /// 变身动作本身（无敌，播放变身演出）
    case transform
    /// 变身期间再按一次：终极技，结束变身
    case ultimate
    /// 完美格挡后按轻击：反击斩
    case counter
}

/// 给表现层的动作风格提示：渲染器据此选择骨骼姿势和刀光形状。
public enum RiftMoveStyle: String, Codable, Sendable {
    case quickSlash, crossSlash, risingSlash, spinSlash, thrust, overhead
    case groundSlam, dashSlash, iaiDraw, counterStance, cast, roar, airSlash
    case transform, flurry, dragonWave
}

/// 招式命中时的手感档位：决定顿帧、震屏、火花与音效强度。
public enum RiftImpactTier: Int, Codable, Sendable, Comparable {
    case light = 0, medium, heavy, ultimate
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var hitstop: Int {
        switch self { case .light: return 4; case .medium: return 7; case .heavy: return 10; case .ultimate: return 14 }
    }
    /// 震屏强度（米），表现层直接使用
    public var shake: Double {
        switch self { case .light: return 0.03; case .medium: return 0.07; case .heavy: return 0.14; case .ultimate: return 0.22 }
    }
}

public struct RiftProjectileSpec: Codable, Sendable, Equatable {
    public var speed: Double          // 米/帧
    public var lifetime: Int          // 帧
    public var halfWidth: Double
    public var height: Double         // 离地中心高度
    public var halfHeight: Double
    public var hits: Int              // 可命中次数（穿透）
    public var hitInterval: Int       // 多段命中间隔
    public var style: RiftMoveStyle
    public init(speed: Double, lifetime: Int, halfWidth: Double, height: Double, halfHeight: Double,
                hits: Int = 1, hitInterval: Int = 8, style: RiftMoveStyle) {
        self.speed = speed; self.lifetime = lifetime; self.halfWidth = halfWidth
        self.height = height; self.halfHeight = halfHeight; self.hits = hits
        self.hitInterval = hitInterval; self.style = style
    }
}

public struct RiftMoveSpec: Codable, Sendable, Equatable {
    public var name: String
    public var style: RiftMoveStyle
    public var startup: Int
    public var active: Int
    public var recovery: Int
    /// 每一段命中的伤害
    public var damage: Int
    /// 段数，在 active 内平均分布
    public var hits: Int = 1
    public var hitstun: Int
    public var blockstun: Int
    /// 命中后对手水平速度（米/帧，正值表示远离攻击者）
    public var knockback: Double
    /// 命中后对手竖直速度（>0 表示击飞）
    public var launch: Double = 0
    /// 是否造成倒地
    public var knockdown: Bool = false
    /// 判定区：相对攻击者朝向的前方距离
    public var reachStart: Double = 0.2
    public var reachEnd: Double
    public var hitLow: Double = 0.2
    public var hitHigh: Double = 1.7
    /// 招式期间向前位移（米/帧），只在 startup+active 生效
    public var lunge: Double = 0
    /// 霸体帧（相对招式开始），霸体期间受击不硬直
    public var armorFrom: Int = -1
    public var armorUntil: Int = -1
    /// 无敌帧
    public var invulnFrom: Int = -1
    public var invulnUntil: Int = -1
    public var impact: RiftImpactTier
    public var guardDamage: Int = 10
    public var unblockable: Bool = false
    /// 发射飞行道具（在 startup 结束那一帧发出）
    public var projectile: RiftProjectileSpec?
    /// 以自身为中心的范围攻击半径（>0 时忽略 reach）
    public var radius: Double = 0
    /// 命中后对手额外眩晕（帧）
    public var stun: Int = 0
    /// 冷却（帧）
    public var cooldown: Int = 0
    /// 吴庸铁壁：架势期间被击中自动反击
    public var counterStance: Bool = false

    public var total: Int { startup + active + recovery }
}

public struct RiftHeroSpec: Sendable {
    public var id: RiftHeroID
    public var name: String
    public var title: String
    public var weapon: String
    public var transformName: String
    public var ultimateName: String
    public var maxHealth: Int
    public var walkSpeed: Double       // 米/帧
    public var dashSpeed: Double
    public var jumpVelocity: Double
    public var parryWindow: Int
    /// 体型（渲染缩放）
    public var scale: Double
    public var moves: [RiftMoveSlot: RiftMoveSpec]
    public var transform: RiftTransformSpec

    public func move(_ slot: RiftMoveSlot) -> RiftMoveSpec? { moves[slot] }
}

public struct RiftTransformSpec: Sendable {
    public var duration: Int
    /// 帧数缩放（<1 更快）
    public var frameScale: Double
    public var damageScale: Double
    public var damageTaken: Double
    public var speedScale: Double
    /// 所有攻击带霸体
    public var permanentArmor: Bool
    /// 每次命中追加的影子伤害比例
    public var echoDamage: Double
    /// 飞行道具追加一发
    public var doubleProjectile: Bool
    /// 渲染缩放
    public var scale: Double
}

public struct RiftInput: Equatable, Codable, Sendable {
    /// -1 后退 / 0 / 1 前进（以屏幕左右为准，不是朝向）
    public var horizontal: Int8 = 0
    public var jump = false
    public var dash = false
    public var guardHeld = false
    public var light = false
    public var heavy = false
    public var skill1 = false
    public var skill2 = false
    public var transform = false

    public init(horizontal: Int8 = 0, jump: Bool = false, dash: Bool = false, guardHeld: Bool = false,
                light: Bool = false, heavy: Bool = false, skill1: Bool = false, skill2: Bool = false,
                transform: Bool = false) {
        self.horizontal = horizontal; self.jump = jump; self.dash = dash; self.guardHeld = guardHeld
        self.light = light; self.heavy = heavy; self.skill1 = skill1; self.skill2 = skill2
        self.transform = transform
    }
    public static let none = RiftInput()
}
