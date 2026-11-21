import Foundation

// 四位英雄的原创招式表。数值单位：帧（60 帧 = 1 秒）、米。
// 平衡原则：
// - 单套连招上限由 RiftFight.comboDamageCap 统一封顶（最大血量的 35%），不可能被秒。
// - 快的角色伤害低、血少；慢的角色伤害高、血厚、带霸体。
// - 每个英雄都有：三段轻击、重击、空中攻击、两个技能、变身、终极技、格挡反击。

public enum RiftRoster {
    public static func spec(_ id: RiftHeroID) -> RiftHeroSpec {
        switch id {
        case .sunDeng: return sunDeng
        case .wuYong: return wuYong
        case .liuQuanwei: return liuQuanwei
        case .xuXiao: return xuXiao
        }
    }

    public static let all: [RiftHeroSpec] = RiftHeroID.allCases.map(spec)

    // MARK: 孙登 · 双刀

    public static let sunDeng = RiftHeroSpec(
        id: .sunDeng, name: "孙登", title: "双刃疾影", weapon: "双刀",
        transformName: "影刃", ultimateName: "千影乱舞",
        maxHealth: 1300, walkSpeed: 0.062, dashSpeed: 0.22, jumpVelocity: 0.20, parryWindow: 7, scale: 1.0,
        moves: [
            .light1: RiftMoveSpec(name: "裂风", style: .quickSlash, startup: 5, active: 3, recovery: 10,
                                  damage: 34, hitstun: 16, blockstun: 10, knockback: 0.02,
                                  reachEnd: 1.45, lunge: 0.03, impact: .light, guardDamage: 6),
            .light2: RiftMoveSpec(name: "回燕", style: .crossSlash, startup: 5, active: 4, recovery: 11,
                                  damage: 36, hitstun: 17, blockstun: 10, knockback: 0.025,
                                  reachEnd: 1.5, lunge: 0.03, impact: .light, guardDamage: 6),
            .light3: RiftMoveSpec(name: "双月斩", style: .spinSlash, startup: 7, active: 8, recovery: 16,
                                  damage: 26, hits: 2, hitstun: 22, blockstun: 14, knockback: 0.07,
                                  knockdown: false, reachEnd: 1.6, lunge: 0.04, impact: .medium, guardDamage: 12),
            .heavy: RiftMoveSpec(name: "交错斩", style: .dashSlash, startup: 11, active: 5, recovery: 20,
                                 damage: 84, hitstun: 26, blockstun: 16, knockback: 0.11,
                                 reachEnd: 1.5, lunge: 0.12, impact: .heavy, guardDamage: 22),
            .airAttack: RiftMoveSpec(name: "落燕", style: .airSlash, startup: 5, active: 6, recovery: 10,
                                     damage: 44, hitstun: 18, blockstun: 10, knockback: 0.04,
                                     reachEnd: 1.2, hitLow: -0.4, hitHigh: 1.4, impact: .medium),
            .skill1: RiftMoveSpec(name: "影袭", style: .dashSlash, startup: 6, active: 9, recovery: 16,
                                  damage: 70, hitstun: 24, blockstun: 14, knockback: 0.09,
                                  reachEnd: 1.2, lunge: 0.26, invulnFrom: 3, invulnUntil: 12,
                                  impact: .heavy, guardDamage: 18, cooldown: 240),
            .skill2: RiftMoveSpec(name: "旋刃风暴", style: .spinSlash, startup: 8, active: 30, recovery: 18,
                                  damage: 19, hits: 5, hitstun: 20, blockstun: 12, knockback: 0.025,
                                  reachEnd: 1.5, lunge: 0.04, impact: .medium, guardDamage: 8,
                                  radius: 1.5, cooldown: 480),
            .transform: RiftMoveSpec(name: "影刃", style: .transform, startup: 40, active: 1, recovery: 10,
                                     damage: 0, hitstun: 0, blockstun: 0, knockback: 0, reachEnd: 0,
                                     invulnFrom: 0, invulnUntil: 51, impact: .ultimate),
            .ultimate: RiftMoveSpec(name: "千影乱舞", style: .flurry, startup: 10, active: 48, recovery: 24,
                                    damage: 22, hits: 9, hitstun: 26, blockstun: 14, knockback: 0.02,
                                    launch: 0, knockdown: true, reachEnd: 1.8, lunge: 0.05,
                                    invulnFrom: 0, invulnUntil: 12, impact: .ultimate, guardDamage: 10),
            .counter: RiftMoveSpec(name: "回身斩", style: .risingSlash, startup: 3, active: 4, recovery: 14,
                                   damage: 70, hitstun: 30, blockstun: 12, knockback: 0.08, launch: 0.17,
                                   knockdown: true, reachEnd: 1.4, impact: .heavy),
        ],
        transform: RiftTransformSpec(duration: 600, frameScale: 0.8, damageScale: 1.0, damageTaken: 1.0,
                                     speedScale: 1.25, permanentArmor: false, echoDamage: 0.30,
                                     doubleProjectile: false, scale: 1.0))

    // MARK: 吴庸 · 幕府武将

    public static let wuYong = RiftHeroSpec(
        id: .wuYong, name: "吴庸", title: "幕府大将", weapon: "大太刀",
        transformName: "鬼武者", ultimateName: "鬼神一闪",
        maxHealth: 1380, walkSpeed: 0.052, dashSpeed: 0.19, jumpVelocity: 0.18, parryWindow: 11, scale: 1.04,
        moves: [
            .light1: RiftMoveSpec(name: "斩", style: .quickSlash, startup: 7, active: 3, recovery: 12,
                                  damage: 48, hitstun: 17, blockstun: 11, knockback: 0.025,
                                  reachEnd: 1.6, lunge: 0.02, impact: .light, guardDamage: 8),
            .light2: RiftMoveSpec(name: "逆袈裟", style: .risingSlash, startup: 7, active: 4, recovery: 13,
                                  damage: 48, hitstun: 18, blockstun: 11, knockback: 0.03,
                                  reachEnd: 1.6, lunge: 0.02, impact: .light, guardDamage: 8),
            .light3: RiftMoveSpec(name: "居合", style: .iaiDraw, startup: 10, active: 4, recovery: 18,
                                  damage: 68, hitstun: 24, blockstun: 15, knockback: 0.10,
                                  reachEnd: 1.8, lunge: 0.05, impact: .medium, guardDamage: 16),
            .heavy: RiftMoveSpec(name: "袈裟斩", style: .overhead, startup: 14, active: 5, recovery: 22,
                                 damage: 102, hitstun: 28, blockstun: 18, knockback: 0.12,
                                 reachEnd: 1.8, lunge: 0.04, impact: .heavy, guardDamage: 26),
            .airAttack: RiftMoveSpec(name: "天斩", style: .airSlash, startup: 6, active: 6, recovery: 12,
                                     damage: 50, hitstun: 18, blockstun: 11, knockback: 0.04,
                                     reachEnd: 1.4, hitLow: -0.4, hitHigh: 1.4, impact: .medium),
            .skill1: RiftMoveSpec(name: "一闪", style: .iaiDraw, startup: 12, active: 6, recovery: 20,
                                  damage: 92, hitstun: 26, blockstun: 16, knockback: 0.10,
                                  reachEnd: 1.3, lunge: 0.24, impact: .heavy, guardDamage: 24, cooldown: 300),
            .skill2: RiftMoveSpec(name: "铁壁", style: .counterStance, startup: 4, active: 40, recovery: 14,
                                  damage: 0, hitstun: 0, blockstun: 0, knockback: 0, reachEnd: 0,
                                  impact: .heavy, cooldown: 420, counterStance: true),
            .transform: RiftMoveSpec(name: "鬼武者", style: .transform, startup: 40, active: 1, recovery: 10,
                                     damage: 0, hitstun: 0, blockstun: 0, knockback: 0, reachEnd: 0,
                                     invulnFrom: 0, invulnUntil: 51, impact: .ultimate),
            .ultimate: RiftMoveSpec(name: "鬼神一闪", style: .iaiDraw, startup: 18, active: 18, recovery: 26,
                                    damage: 75, hits: 3, hitstun: 34, blockstun: 18, knockback: 0.06,
                                    launch: 0.14, knockdown: true, reachEnd: 2.4, lunge: 0.14,
                                    invulnFrom: 0, invulnUntil: 20, impact: .ultimate, guardDamage: 20),
            .counter: RiftMoveSpec(name: "返し斩", style: .iaiDraw, startup: 3, active: 4, recovery: 14,
                                   damage: 110, hitstun: 32, blockstun: 12, knockback: 0.12, launch: 0.12,
                                   knockdown: true, reachEnd: 1.8, impact: .heavy),
        ],
        transform: RiftTransformSpec(duration: 600, frameScale: 1.0, damageScale: 1.2, damageTaken: 0.9,
                                     speedScale: 1.1, permanentArmor: false, echoDamage: 0,
                                     doubleProjectile: false, scale: 1.06))

    // MARK: 刘泉纬 · 盘古

    public static let liuQuanwei = RiftHeroSpec(
        id: .liuQuanwei, name: "刘泉纬", title: "盘古", weapon: "开天巨斧",
        transformName: "开天", ultimateName: "开天辟地",
        maxHealth: 1300, walkSpeed: 0.040, dashSpeed: 0.16, jumpVelocity: 0.16, parryWindow: 6, scale: 1.12,
        moves: [
            .light1: RiftMoveSpec(name: "劈", style: .quickSlash, startup: 10, active: 4, recovery: 15,
                                  damage: 52, hitstun: 18, blockstun: 12, knockback: 0.035,
                                  reachEnd: 1.5, lunge: 0.015, impact: .medium, guardDamage: 12),
            .light2: RiftMoveSpec(name: "横扫", style: .crossSlash, startup: 10, active: 5, recovery: 15,
                                  damage: 56, hitstun: 19, blockstun: 12, knockback: 0.04,
                                  reachEnd: 1.75, lunge: 0.015, impact: .medium, guardDamage: 12),
            .light3: RiftMoveSpec(name: "崩山", style: .groundSlam, startup: 15, active: 5, recovery: 24,
                                  damage: 70, hitstun: 30, blockstun: 16, knockback: 0.05, launch: 0.20,
                                  knockdown: true, reachEnd: 1.8, lunge: 0.02, impact: .heavy, guardDamage: 22),
            .heavy: RiftMoveSpec(name: "开山", style: .overhead, startup: 18, active: 6, recovery: 24,
                                 damage: 104, hitstun: 30, blockstun: 20, knockback: 0.14,
                                 reachEnd: 1.8, lunge: 0.03, armorFrom: 4, armorUntil: 18,
                                 impact: .heavy, guardDamage: 34),
            .airAttack: RiftMoveSpec(name: "坠斧", style: .groundSlam, startup: 8, active: 8, recovery: 16,
                                     damage: 66, hitstun: 22, blockstun: 12, knockback: 0.05,
                                     reachEnd: 1.5, hitLow: -0.6, hitHigh: 1.3, impact: .heavy),
            .skill1: RiftMoveSpec(name: "裂地波", style: .groundSlam, startup: 16, active: 2, recovery: 22,
                                  damage: 64, hitstun: 26, blockstun: 16, knockback: 0.08, launch: 0.12,
                                  knockdown: true, reachEnd: 0, impact: .heavy, guardDamage: 20,
                                  projectile: RiftProjectileSpec(speed: 0.16, lifetime: 48, halfWidth: 0.45,
                                                                 height: 0.35, halfHeight: 0.4, style: .groundSlam),
                                  cooldown: 360),
            .skill2: RiftMoveSpec(name: "盘古旋斧", style: .spinSlash, startup: 10, active: 30, recovery: 22,
                                  damage: 40, hits: 3, hitstun: 22, blockstun: 14, knockback: 0.06,
                                  reachEnd: 1.9, lunge: 0.03, armorFrom: 0, armorUntil: 40,
                                  impact: .heavy, guardDamage: 18, radius: 1.9, cooldown: 480),
            .transform: RiftMoveSpec(name: "开天", style: .transform, startup: 40, active: 1, recovery: 10,
                                     damage: 0, hitstun: 0, blockstun: 0, knockback: 0, reachEnd: 0,
                                     invulnFrom: 0, invulnUntil: 51, impact: .ultimate),
            .ultimate: RiftMoveSpec(name: "开天辟地", style: .groundSlam, startup: 26, active: 6, recovery: 30,
                                    damage: 160, hitstun: 40, blockstun: 24, knockback: 0.16, launch: 0.24,
                                    knockdown: true, reachEnd: 2.6, armorFrom: 0, armorUntil: 32,
                                    impact: .ultimate, guardDamage: 60, radius: 2.6),
            .counter: RiftMoveSpec(name: "震岳", style: .groundSlam, startup: 4, active: 5, recovery: 16,
                                   damage: 100, hitstun: 32, blockstun: 12, knockback: 0.10, launch: 0.18,
                                   knockdown: true, reachEnd: 1.8, impact: .heavy),
        ],
        transform: RiftTransformSpec(duration: 600, frameScale: 1.0, damageScale: 1.05, damageTaken: 0.75,
                                     speedScale: 1.0, permanentArmor: true, echoDamage: 0,
                                     doubleProjectile: false, scale: 1.3))

    // MARK: 徐骁 · 嬴政

    public static let xuXiao = RiftHeroSpec(
        id: .xuXiao, name: "徐骁", title: "始皇", weapon: "秦王剑",
        transformName: "始皇", ultimateName: "龙魂天下",
        maxHealth: 1320, walkSpeed: 0.052, dashSpeed: 0.20, jumpVelocity: 0.19, parryWindow: 8, scale: 1.02,
        moves: [
            .light1: RiftMoveSpec(name: "刺", style: .thrust, startup: 6, active: 3, recovery: 11,
                                  damage: 38, hitstun: 16, blockstun: 10, knockback: 0.025,
                                  reachEnd: 1.7, lunge: 0.02, impact: .light, guardDamage: 6),
            .light2: RiftMoveSpec(name: "挑", style: .risingSlash, startup: 6, active: 4, recovery: 12,
                                  damage: 42, hitstun: 17, blockstun: 10, knockback: 0.03,
                                  reachEnd: 1.7, lunge: 0.02, impact: .light, guardDamage: 8),
            .light3: RiftMoveSpec(name: "王道", style: .thrust, startup: 9, active: 4, recovery: 16,
                                  damage: 62, hitstun: 22, blockstun: 14, knockback: 0.10,
                                  reachEnd: 2.1, lunge: 0.06, impact: .medium, guardDamage: 14),
            .heavy: RiftMoveSpec(name: "天子剑", style: .crossSlash, startup: 13, active: 5, recovery: 21,
                                 damage: 90, hitstun: 26, blockstun: 17, knockback: 0.12,
                                 reachEnd: 1.9, lunge: 0.04, impact: .heavy, guardDamage: 22),
            .airAttack: RiftMoveSpec(name: "凌云", style: .airSlash, startup: 5, active: 6, recovery: 11,
                                     damage: 46, hitstun: 18, blockstun: 10, knockback: 0.04,
                                     reachEnd: 1.5, hitLow: -0.4, hitHigh: 1.4, impact: .medium),
            .skill1: RiftMoveSpec(name: "剑气", style: .cast, startup: 12, active: 2, recovery: 18,
                                  damage: 64, hitstun: 22, blockstun: 14, knockback: 0.07,
                                  reachEnd: 0, impact: .medium, guardDamage: 14,
                                  projectile: RiftProjectileSpec(speed: 0.20, lifetime: 60, halfWidth: 0.35,
                                                                 height: 1.1, halfHeight: 0.45, style: .cast),
                                  cooldown: 210),
            .skill2: RiftMoveSpec(name: "帝威", style: .roar, startup: 14, active: 4, recovery: 22,
                                  damage: 46, hitstun: 24, blockstun: 16, knockback: 0.13,
                                  reachEnd: 0, impact: .heavy, guardDamage: 30, radius: 2.4, stun: 40,
                                  cooldown: 540),
            .transform: RiftMoveSpec(name: "始皇", style: .transform, startup: 40, active: 1, recovery: 10,
                                     damage: 0, hitstun: 0, blockstun: 0, knockback: 0, reachEnd: 0,
                                     invulnFrom: 0, invulnUntil: 51, impact: .ultimate),
            .ultimate: RiftMoveSpec(name: "龙魂天下", style: .dragonWave, startup: 20, active: 2, recovery: 30,
                                    damage: 48, hits: 1, hitstun: 30, blockstun: 16, knockback: 0.05,
                                    launch: 0.10, knockdown: true, reachEnd: 0,
                                    invulnFrom: 0, invulnUntil: 22, impact: .ultimate, guardDamage: 14,
                                    projectile: RiftProjectileSpec(speed: 0.14, lifetime: 90, halfWidth: 0.9,
                                                                   height: 1.0, halfHeight: 0.9, hits: 4,
                                                                   hitInterval: 9, style: .dragonWave)),
            .counter: RiftMoveSpec(name: "斩龙", style: .risingSlash, startup: 3, active: 4, recovery: 14,
                                   damage: 80, hitstun: 30, blockstun: 12, knockback: 0.08, launch: 0.17,
                                   knockdown: true, reachEnd: 1.8, impact: .heavy),
        ],
        transform: RiftTransformSpec(duration: 600, frameScale: 0.95, damageScale: 1.1, damageTaken: 0.95,
                                     speedScale: 1.1, permanentArmor: false, echoDamage: 0,
                                     doubleProjectile: true, scale: 1.04))
}
