import SceneKit
import UIKit
import simd

/// 100% original 3D combat VFX & weapon slash ribbon engine built on SceneKit `SCNParticleSystem`
/// and the repository's already-licensed `App/ArenaVendor/vendor_effect_*.png` textures.
/// Zero third-party Shadow Fight 3 shaders, textures, or assets are referenced or loaded.
@MainActor
final class DuelOriginalVFX {
    private let root = SCNNode()
    private var burstPool: [(node: SCNNode, system: SCNParticleSystem)] = []
    private var burstCursor = 0
    private var slashNodes: [SlashArc] = []
    private var shockRings: [ShockRing] = []
    private let flashLightNode = SCNNode()
    private var flashTicks = 0
    private var fighterAuras: [Int: AuraEmitter] = [:]
    private var salvationEchoMarkers: [Int: SCNNode] = [:]
    private var bladeRibbons: [[BladeRibbon]] = []
    private var hasLiveBladeSegments: [Bool] = [false, false]
    private var lastAttackKeys: [String?] = [nil, nil]

    private struct SlashArc {
        let node: SCNNode
        var age: Int
        let duration: Int
        let basePitch: Float
        let sweepPitch: Float
        let facing: Float
    }

    private struct ShockRing {
        let node: SCNNode
        var age: Int
        let duration: Int
        let maxScale: Float
    }

    /// Real blade-attached 3D swept weapon trail ribbon hugging live animated weapon sockets.
    @MainActor
    private final class BladeRibbon {
        let node = SCNNode()
        private let material = SCNMaterial()
        private var samples: [(base: SIMD3<Float>, tip: SIMD3<Float>)] = []
        private var lastTint: SIMD4<Float> = SIMD4(1, 1, 1, 1)
        private let maxSamples = 9

        init() {
            node.name = "duel.blade.ribbon"
            node.castsShadow = false
            node.renderingOrder = 14
            material.diffuse.contents = ArenaEffectAssets.image(.trace) ?? ArenaEffectAssets.image(.slash) ?? UIColor.white
            material.emission.contents = UIColor.black
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.blendMode = .add
            material.writesToDepthBuffer = false
        }

        func clear() {
            samples.removeAll(keepingCapacity: true)
            node.geometry = nil
            node.isHidden = true
        }

        func push(base: SIMD3<Float>, tip: SIMD3<Float>, color: UIColor) {
            var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            lastTint = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
            let lift = SIMD3<Float>(0, 0, 0.03)
            samples.append((base + lift, tip + lift))
            if samples.count > maxSamples {
                samples.removeFirst(samples.count - maxSamples)
            }
            rebuild()
        }

        func fadeTail() {
            guard !samples.isEmpty else {
                node.isHidden = true
                return
            }
            samples.removeFirst()
            if samples.count < 2 {
                clear()
            } else {
                rebuild()
            }
        }

        private func rebuild() {
            let count = samples.count
            guard count >= 2 else {
                node.geometry = nil
                node.isHidden = true
                return
            }
            var vertices: [SCNVector3] = []
            var texcoords: [CGPoint] = []
            var colors: [SIMD4<Float>] = []
            var indices: [UInt16] = []
            vertices.reserveCapacity(count * 2)
            texcoords.reserveCapacity(count * 2)
            colors.reserveCapacity(count * 2)
            indices.reserveCapacity((count - 1) * 6)

            for i in 0..<count {
                let s = samples[i]
                let u = Float(i) / Float(count - 1)
                let fade = u * u
                let baseColor = SIMD4<Float>(lastTint.x * fade * 0.55, lastTint.y * fade * 0.55, lastTint.z * fade * 0.55, fade * 0.55)
                let tipColor = SIMD4<Float>(min(1.5, lastTint.x * fade * 1.35), min(1.5, lastTint.y * fade * 1.35), min(1.5, lastTint.z * fade * 1.35), fade * 0.96)
                vertices.append(SCNVector3(s.base.x, s.base.y, s.base.z))
                vertices.append(SCNVector3(s.tip.x, s.tip.y, s.tip.z))
                texcoords.append(CGPoint(x: CGFloat(u), y: 0.05))
                texcoords.append(CGPoint(x: CGFloat(u), y: 0.95))
                colors.append(baseColor)
                colors.append(tipColor)
                if i + 1 < count {
                    let v0 = UInt16(i * 2)
                    let v1 = v0 + 1
                    let v2 = v0 + 2
                    let v3 = v0 + 3
                    indices.append(contentsOf: [v0, v1, v2, v2, v1, v3])
                }
            }

            let vSource = SCNGeometrySource(vertices: vertices)
            let uvSource = SCNGeometrySource(textureCoordinates: texcoords)
            let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let colorSource = SCNGeometrySource(
                data: colorData,
                semantic: .color,
                vectorCount: colors.count,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD4<Float>>.stride
            )
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let geom = SCNGeometry(sources: [vSource, uvSource, colorSource], elements: [element])
            geom.materials = [material]
            node.geometry = geom
            node.isHidden = false
        }
    }

    @MainActor
    private final class AuraEmitter {
        let node = SCNNode()
        let system = SCNParticleSystem()
        var currentKind: AuraKind = .none

        enum AuraKind: Equatable {
            case none, shogunShadow, shogunCataclysm, shogunCharge
            case inquisitorLight, nonnaFlame, nonnaEmber
            case midnightShift, midnightBlink, midnightShadow
        }

        init() {
            system.birthRate = 0
            system.particleLifeSpan = 0.55
            system.particleLifeSpanVariation = 0.20
            system.particleSize = 0.24
            system.particleSizeVariation = 0.10
            system.particleVelocity = 0.65
            system.particleVelocityVariation = 0.35
            system.spreadingAngle = 35
            system.emittingDirection = SCNVector3(0, 1, 0)
            system.emitterShape = SCNCylinder(radius: 0.35, height: 1.35)
            system.blendMode = .additive
            system.isLightingEnabled = false
            system.isAffectedByGravity = false
            system.loops = true
            node.addParticleSystem(system)
        }

        func update(kind: AuraKind, position: SCNVector3) {
            node.position = position
            guard kind != currentKind else { return }
            currentKind = kind
            switch kind {
            case .none:
                system.birthRate = 0
            case .shogunShadow:
                system.particleImage = ArenaEffectAssets.image(.flame)
                system.particleColor = UIColor(red: 0.62, green: 0.24, blue: 1.0, alpha: 0.85)
                system.birthRate = 26
                system.particleSize = 0.32
                system.particleVelocity = 0.75
            case .shogunCataclysm:
                system.particleImage = ArenaEffectAssets.image(.fire) ?? ArenaEffectAssets.image(.flame)
                system.particleColor = UIColor(red: 1.0, green: 0.14, blue: 0.24, alpha: 0.95)
                system.birthRate = 48
                system.particleSize = 0.42
                system.particleVelocity = 1.25
            case .shogunCharge:
                system.particleImage = ArenaEffectAssets.image(.star)
                system.particleColor = UIColor(red: 1.0, green: 0.76, blue: 0.22, alpha: 0.9)
                system.birthRate = 22
                system.particleSize = 0.22
                system.particleVelocity = 0.5
            case .inquisitorLight:
                system.particleImage = ArenaEffectAssets.image(.heal) ?? ArenaEffectAssets.image(.magic)
                system.particleColor = UIColor(red: 1.0, green: 0.88, blue: 0.34, alpha: 0.92)
                system.birthRate = 34
                system.particleSize = 0.34
                system.particleVelocity = 1.05
            case .nonnaFlame:
                system.particleImage = ArenaEffectAssets.image(.fire) ?? ArenaEffectAssets.image(.flame)
                system.particleColor = UIColor(red: 1.0, green: 0.44, blue: 0.08, alpha: 0.95)
                system.birthRate = 44
                system.particleSize = 0.40
                system.particleVelocity = 1.20
            case .nonnaEmber:
                system.particleImage = ArenaEffectAssets.image(.flame)
                system.particleColor = UIColor(red: 1.0, green: 0.55, blue: 0.14, alpha: 0.82)
                system.birthRate = 18
                system.particleSize = 0.24
                system.particleVelocity = 0.65
            case .midnightShift:
                system.particleImage = ArenaEffectAssets.image(.twirl) ?? ArenaEffectAssets.image(.smoke)
                system.particleColor = UIColor(red: 0.56, green: 0.24, blue: 0.98, alpha: 0.82)
                system.birthRate = 36
                system.particleSize = 0.46
                system.particleVelocity = 0.50
            case .midnightBlink:
                system.particleImage = ArenaEffectAssets.image(.circle) ?? ArenaEffectAssets.image(.magic)
                system.particleColor = UIColor(red: 0.40, green: 0.82, blue: 1.0, alpha: 0.90)
                system.birthRate = 26
                system.particleSize = 0.30
                system.particleVelocity = 0.45
            case .midnightShadow:
                system.particleImage = ArenaEffectAssets.image(.magic)
                system.particleColor = UIColor(red: 0.84, green: 0.24, blue: 1.0, alpha: 0.92)
                system.birthRate = 34
                system.particleSize = 0.34
                system.particleVelocity = 0.85
            }
        }
    }

    init(parent: SCNNode) {
        ArenaEffectAssets.prepare()
        root.name = "duel.original.vfx"
        parent.addChildNode(root)

        // Pre-allocate bounded particle burst pool so combat never stalls on allocations.
        for _ in 0..<10 {
            let node = SCNNode()
            let system = SCNParticleSystem()
            system.birthRate = 0
            system.emissionDuration = 0.08
            system.loops = false
            system.particleLifeSpan = 0.32
            system.particleLifeSpanVariation = 0.12
            system.particleSize = 0.26
            system.particleSizeVariation = 0.10
            system.particleVelocity = 2.6
            system.particleVelocityVariation = 1.1
            system.spreadingAngle = 155
            system.blendMode = .additive
            system.isLightingEnabled = false
            system.isAffectedByGravity = false
            node.addParticleSystem(system)
            root.addChildNode(node)
            burstPool.append((node, system))
        }

        // Dynamic impact flash omni-light for crits, head-hits, and shadow bursts.
        let light = SCNLight()
        light.type = .omni
        light.intensity = 0
        light.attenuationStartDistance = 1.5
        light.attenuationEndDistance = 9.0
        flashLightNode.light = light
        root.addChildNode(flashLightNode)

        for i in 0..<2 {
            let aura = AuraEmitter()
            root.addChildNode(aura.node)
            fighterAuras[i] = aura
            let echoRing = SCNTorus(ringRadius: 0.52, pipeRadius: 0.036)
            let echoMat = SCNMaterial()
            echoMat.diffuse.contents = UIColor(red: 1.0, green: 0.88, blue: 0.28, alpha: 0.92)
            echoMat.emission.contents = UIColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1)
            echoMat.lightingModel = .constant
            echoMat.blendMode = .add
            echoMat.writesToDepthBuffer = false
            echoRing.materials = [echoMat]
            let echoNode = SCNNode(geometry: echoRing)
            echoNode.castsShadow = false
            echoNode.isHidden = true
            root.addChildNode(echoNode)
            salvationEchoMarkers[i] = echoNode
            var pair: [BladeRibbon] = []
            for _ in 0..<2 {
                let ribbon = BladeRibbon()
                root.addChildNode(ribbon.node)
                pair.append(ribbon)
            }
            bladeRibbons.append(pair)
        }
    }

    func reset() {
        for slash in slashNodes { slash.node.removeFromParentNode() }
        slashNodes.removeAll()
        for ring in shockRings { ring.node.removeFromParentNode() }
        shockRings.removeAll()
        flashTicks = 0
        flashLightNode.light?.intensity = 0
        lastAttackKeys = [nil, nil]
        hasLiveBladeSegments = [false, false]
        for pair in bladeRibbons { for r in pair { r.clear() } }
        for aura in fighterAuras.values { aura.update(kind: .none, position: SCNVector3Zero) }
        for marker in salvationEchoMarkers.values { marker.isHidden = true }
    }

    func shutdown() {
        reset()
        root.removeFromParentNode()
        burstPool.removeAll()
        bladeRibbons.removeAll()
        fighterAuras.removeAll()
        salvationEchoMarkers.removeAll()
    }

    private func heroSlashColor(_ hero: DuelGame.Hero, shadow: Bool = false) -> UIColor {
        if shadow {
            switch hero {
            case .wuYong: return UIColor(red: 0.96, green: 0.14, blue: 0.36, alpha: 1)
            case .gale: return UIColor(red: 1.0, green: 0.88, blue: 0.28, alpha: 1)
            case .liu: return UIColor(red: 1.0, green: 0.38, blue: 0.08, alpha: 1)
            case .ember: return UIColor(red: 0.78, green: 0.22, blue: 1.0, alpha: 1)
            }
        }
        switch hero {
        case .wuYong: return UIColor(red: 0.94, green: 0.34, blue: 0.28, alpha: 1)
        case .gale: return UIColor(red: 1.0, green: 0.84, blue: 0.36, alpha: 1)
        case .liu: return UIColor(red: 1.0, green: 0.56, blue: 0.16, alpha: 1)
        case .ember: return UIColor(red: 0.56, green: 0.76, blue: 1.0, alpha: 1)
        }
    }

    private func emitBurst(at position: SCNVector3, style: ArenaEffectAssets.Style, color: UIColor,
                           count: CGFloat, size: CGFloat, speed: CGFloat, life: CGFloat = 0.30,
                           spread: CGFloat = 150, direction: SCNVector3 = SCNVector3(0, 1, 0)) {
        guard !burstPool.isEmpty else { return }
        let entry = burstPool[burstCursor]
        burstCursor = (burstCursor + 1) % burstPool.count
        entry.node.position = position
        let sys = entry.system
        sys.reset()
        sys.particleImage = ArenaEffectAssets.image(style) ?? ArenaEffectAssets.image(.spark)
        sys.particleColor = color
        sys.particleSize = size
        sys.particleVelocity = speed
        sys.particleLifeSpan = life
        sys.spreadingAngle = spread
        sys.emittingDirection = direction
        sys.emissionDuration = 0.07
        sys.birthRate = count / 0.07
        sys.loops = false
    }

    private func spawnShockRing(at position: SCNVector3, color: UIColor, maxScale: Float,
                                duration: Int = 16, vertical: Bool = false) {
        let torus = SCNTorus(ringRadius: 0.45, pipeRadius: 0.045)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.lightingModel = .constant
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        torus.materials = [mat]
        let node = SCNNode(geometry: torus)
        node.position = position
        node.castsShadow = false
        if vertical {
            node.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        }
        root.addChildNode(node)
        shockRings.append(ShockRing(node: node, age: 0, duration: duration, maxScale: maxScale))
    }

    private func triggerFlash(at position: SCNVector3, color: UIColor, intensity: CGFloat = 2400, ticks: Int = 8) {
        flashLightNode.position = SCNVector3(position.x, position.y + 0.3, 1.4)
        flashLightNode.light?.color = color
        flashLightNode.light?.intensity = intensity
        flashTicks = max(flashTicks, ticks)
    }

    /// Spawn a curved 3D swept weapon slash crescent following the hero's strike angle!
    private func spawnSlashArc(fighter: DuelGame.Fighter, move: DuelGame.Move, enhanced: Bool) {
        let isKick = move == .kick || move == .kickForward || move == .kickUp || move == .kickDown || move == .kickBack
        let isThrow = move == .throwForward || move == .throwBack
        if isThrow { return }
        let radius: CGFloat = isKick ? 0.62 : (move == .heavy || move == .shogunFierceReprisal || move == .midnightRemoval ? 1.28 : 0.96)
        let plane = SCNPlane(width: radius * 2.1, height: radius * 1.15)
        let mat = SCNMaterial()
        let color = isKick
            ? UIColor(red: 0.88, green: 0.94, blue: 1.0, alpha: 0.9)
            : heroSlashColor(fighter.hero, shadow: enhanced || move == .shogunFierceReprisal || move == .shogunDespotism || move == .inquisitorLightSpin || move == .midnightRemoval)
        mat.diffuse.contents = ArenaEffectAssets.image(isKick ? .trace : .slash) ?? color
        mat.multiply.contents = color
        mat.emission.contents = color
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.castsShadow = false
        let facing = Float(fighter.facing)
        let yOffset: Float
        let basePitch: Float
        let sweepPitch: Float
        switch move {
        case .weaponUp, .kickUp, .shogunDespotism:
            yOffset = 1.48; basePitch = 0.65; sweepPitch = -1.25
        case .weaponDown, .kickDown:
            yOffset = 0.56; basePitch = -0.35; sweepPitch = 0.55
        case .heavy, .skill2, .shogunFierceReprisal, .midnightRemoval:
            yOffset = 1.22; basePitch = -0.85; sweepPitch = 1.55
        case .inquisitorLightSpin:
            yOffset = 1.12; basePitch = 0.0; sweepPitch = 3.14
        default:
            yOffset = 1.15; basePitch = -0.25; sweepPitch = 0.85
        }
        node.position = SCNVector3(Float(fighter.x) / 1000 + facing * 0.72, Float(fighter.y) / 1000 + yOffset, 0.24)
        node.eulerAngles = SCNVector3(0, facing > 0 ? 0 : .pi, basePitch * facing)
        root.addChildNode(node)
        slashNodes.append(SlashArc(node: node, age: 0, duration: 13, basePitch: basePitch, sweepPitch: sweepPitch, facing: facing))
    }

    private static func isKickOrThrow(_ move: DuelGame.Move) -> Bool {
        switch move {
        case .kick, .kickForward, .kickUp, .kickDown, .kickBack, .throwForward, .throwBack:
            return true
        default:
            return false
        }
    }

    private func isHeroEnhanced(_ game: DuelGame, index: Int) -> Bool {
        (game.shogunState(index)?.isInShadow == true) ||
        (game.inquisitorState(index)?.isInFormOfLight == true) ||
        (game.nonnaState(index)?.isInFlameForm == true) ||
        (game.midnightState(index)?.isInShadowForm == true)
    }

    /// Sample live world-space weapon `(base, tip)` segments from rigged actors every frame
    /// to paint real blade-attached 3D swept trails hugging the Odachi, Great Axe, Greatsword, and Dual Ninjato!
    func sampleBladeTrails(game: DuelGame, bladeSegments: [[(base: SIMD3<Float>, tip: SIMD3<Float>)]]) {
        guard game.fighters.count == 2 else { return }
        for i in 0..<2 {
            let segs = bladeSegments.indices.contains(i) ? bladeSegments[i] : []
            hasLiveBladeSegments[i] = !segs.isEmpty
            guard bladeRibbons.indices.contains(i) else { continue }
            let f = game.fighters[i]
            var activeBladeSwing = false
            var color = heroSlashColor(f.hero, shadow: isHeroEnhanced(game, index: i))
            if let attack = f.attack, !Self.isKickOrThrow(attack.move) {
                let data = DuelGame.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
                let startWin = max(0, data.startup - 1)
                let endWin = data.startup + data.active + 5
                if attack.age >= startWin && attack.age <= endWin {
                    activeBladeSwing = true
                    let signatureMove = attack.move == .heavy || attack.move == .shogunFierceReprisal ||
                        attack.move == .shogunDespotism || attack.move == .inquisitorLightSpin ||
                        attack.move == .midnightRemoval || attack.move == .skill2
                    color = heroSlashColor(f.hero, shadow: isHeroEnhanced(game, index: i) || signatureMove)
                }
            }
            for hand in 0..<bladeRibbons[i].count {
                let ribbon = bladeRibbons[i][hand]
                if activeBladeSwing && hand < segs.count {
                    ribbon.push(base: segs[hand].base, tip: segs[hand].tip, color: color)
                } else {
                    ribbon.fadeTail()
                }
            }
        }
    }

    private func impactPosition(defender: DuelGame.Fighter, z: Float = 0.36) -> SCNVector3 {
        let cx = defender.lastContactX != 0 ? Float(defender.lastContactX) / 1000 : Float(defender.x) / 1000
        let cy = defender.lastContactY > 0 ? Float(defender.lastContactY) / 1000 : Float(defender.y) / 1000 + 1.15
        return SCNVector3(cx, cy, z)
    }

    /// Consume simulation step events & fighter states to trigger bursts, slash trails, shockwaves, and persistent auras.
    func consumeStep(_ game: DuelGame, tick: Int) {
        guard game.fighters.count == 2 else { return }

        // 1. Trigger fallback crescent slash trails & signature SF4 skill startup VFX!
        for i in 0..<2 {
            let f = game.fighters[i]
            if let attack = f.attack {
                let data = DuelGame.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
                let key = "\(attack.move.rawValue):\(tick - attack.age)"
                if attack.age >= data.startup && lastAttackKeys[i] != key {
                    lastAttackKeys[i] = key
                    let needsFallbackArc = !hasLiveBladeSegments[i] || Self.isKickOrThrow(attack.move)
                    if needsFallbackArc {
                        spawnSlashArc(fighter: f, move: attack.move, enhanced: isHeroEnhanced(game, index: i))
                    }
                    let origin = SCNVector3(Float(f.x) / 1000 + Float(f.facing) * 0.45, Float(f.y) / 1000 + 1.05, 0.25)
                    switch attack.move {
                    case .shogunDespotism:
                        // Despotism gravity-vortex ring & frontal shadow barrier burst!
                        let floorPos = SCNVector3(Float(f.x) / 1000 + Float(f.facing) * 0.55, 0.10, 0.15)
                        emitBurst(at: origin, style: .twirl, color: UIColor(red: 0.62, green: 0.20, blue: 1.0, alpha: 0.95),
                                  count: 34, size: 0.48, speed: 3.2, life: 0.40, spread: 160)
                        spawnShockRing(at: floorPos, color: .systemPurple, maxScale: 3.4, duration: 18, vertical: false)
                        triggerFlash(at: origin, color: .systemPurple, intensity: 2400, ticks: 8)
                    case .shogunFierceReprisal:
                        // Fierce Reprisal crimson-purple dash streak burst!
                        emitBurst(at: origin, style: .fire, color: UIColor(red: 0.96, green: 0.16, blue: 0.44, alpha: 1),
                                  count: 32, size: 0.44, speed: 4.4, life: 0.36, spread: 90,
                                  direction: SCNVector3(-Float(f.facing), 0.15, 0))
                        spawnShockRing(at: origin, color: UIColor(red: 0.96, green: 0.16, blue: 0.44, alpha: 1),
                                       maxScale: 2.8, duration: 14, vertical: true)
                    case .midnightRemoval:
                        // Midnight Removal dimensional dash twin rings!
                        emitBurst(at: origin, style: .magic, color: UIColor(red: 0.86, green: 0.22, blue: 1.0, alpha: 1),
                                  count: 34, size: 0.44, speed: 3.8, life: 0.38, spread: 180)
                        spawnShockRing(at: origin, color: .systemPink, maxScale: 2.9, duration: 15, vertical: true)
                    default:
                        break
                    }
                }
            } else {
                lastAttackKeys[i] = nil
            }
        }

        // 2. React to all combat events with rich layered particle bursts & shockwaves at exact 3D capsule contacts!
        for event in game.events {
            switch event {
            case .hit(let attacker, let damage):
                let def = game.fighters[1 - attacker]
                let dir = Float(game.fighters[attacker].facing)
                let pos = impactPosition(defender: def, z: 0.34)
                let heavy = damage >= 260 || (game.ruleset == .laboratory && damage >= 145)
                let color = heroSlashColor(game.fighters[attacker].hero, shadow: heavy)
                emitBurst(at: pos, style: heavy ? .star : .spark, color: color,
                          count: heavy ? 28 : 16, size: heavy ? 0.36 : 0.24, speed: heavy ? 3.8 : 2.6,
                          direction: SCNVector3(dir, 0.35, 0))
                if heavy {
                    spawnShockRing(at: pos, color: color, maxScale: 2.3, duration: 14, vertical: true)
                    triggerFlash(at: pos, color: color, intensity: 1900, ticks: 6)
                }

            case .headHit(let attacker, _):
                let def = game.fighters[1 - attacker]
                let raw = impactPosition(defender: def, z: 0.38)
                let pos = SCNVector3(raw.x, max(raw.y, Float(def.y) / 1000 + 1.56), 0.38)
                emitBurst(at: pos, style: .star, color: UIColor(red: 1.0, green: 0.94, blue: 0.45, alpha: 1),
                          count: 30, size: 0.38, speed: 3.6, spread: 180)
                spawnShockRing(at: pos, color: .systemYellow, maxScale: 2.1, duration: 14, vertical: true)
                triggerFlash(at: pos, color: .systemYellow, intensity: 2400, ticks: 7)

            case .criticalHit(let attacker, _), .shogunCritical(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = impactPosition(defender: def, z: 0.40)
                emitBurst(at: pos, style: .fire, color: UIColor(red: 1.0, green: 0.26, blue: 0.14, alpha: 1),
                          count: 38, size: 0.44, speed: 4.5, spread: 180)
                spawnShockRing(at: pos, color: UIColor(red: 1.0, green: 0.35, blue: 0.15, alpha: 1),
                               maxScale: 3.0, duration: 16, vertical: true)
                triggerFlash(at: pos, color: .systemRed, intensity: 3000, ticks: 10)

            case .blocked(let defender):
                let def = game.fighters[defender]
                let pos = impactPosition(defender: def, z: 0.36)
                emitBurst(at: pos, style: .star, color: UIColor(red: 0.55, green: 0.90, blue: 1.0, alpha: 1),
                          count: 16, size: 0.24, speed: 2.4, spread: 110,
                          direction: SCNVector3(Float(def.facing), 0.2, 0))
                spawnShockRing(at: pos, color: UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 0.9),
                               maxScale: 1.45, duration: 10, vertical: true)

            case .guardBreak(let defender):
                let def = game.fighters[defender]
                let pos = impactPosition(defender: def, z: 0.38)
                emitBurst(at: pos, style: .circle, color: UIColor(red: 1.0, green: 0.30, blue: 0.18, alpha: 1),
                          count: 32, size: 0.42, speed: 4.2, spread: 180)
                spawnShockRing(at: pos, color: .systemRed, maxScale: 2.9, duration: 16, vertical: true)
                triggerFlash(at: pos, color: .systemRed, intensity: 2600, ticks: 8)

            case .throwHit(let attacker, _, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 0.12, 0.25)
                emitBurst(at: pos, style: .dirt, color: UIColor(red: 0.86, green: 0.74, blue: 0.56, alpha: 0.9),
                          count: 26, size: 0.46, speed: 3.0, spread: 120, direction: SCNVector3(0, 1, 0))
                spawnShockRing(at: pos, color: UIColor(red: 1.0, green: 0.72, blue: 0.32, alpha: 0.9),
                               maxScale: 2.8, duration: 18, vertical: false)

            case .shogunShadowForm(let fighter), .shogunCataclysm(let fighter):
                let f = game.fighters[fighter]
                let cataclysm = game.shogunState(fighter)?.isCataclysm == true
                let color: UIColor = cataclysm ? .systemRed : .systemPurple
                let pos = SCNVector3(Float(f.x) / 1000, 0.18, 0.20)
                emitBurst(at: pos, style: cataclysm ? .fire : .flame, color: color,
                          count: 42, size: 0.50, speed: 4.0, life: 0.45, spread: 140)
                spawnShockRing(at: pos, color: color, maxScale: cataclysm ? 4.2 : 3.0, duration: 20, vertical: false)
                triggerFlash(at: pos, color: color, intensity: 3200, ticks: 12)

            case .shogunCataclysmStrike(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.15, 0.40)
                emitBurst(at: pos, style: .fire, color: .systemRed, count: 48, size: 0.55, speed: 5.0, life: 0.45, spread: 180)
                spawnShockRing(at: pos, color: .systemRed, maxScale: 3.8, duration: 20, vertical: true)
                triggerFlash(at: pos, color: .systemRed, intensity: 3800, ticks: 14)

            case .shogunCompanionHit(let owner, _):
                let def = game.fighters[1 - owner]
                let pos = SCNVector3(Float(def.x) / 1000, 1.10, 0.30)
                emitBurst(at: pos, style: .twirl, color: .systemPurple, count: 24, size: 0.38, speed: 3.2)

            case .inquisitorFormOfLight(let fighter):
                let f = game.fighters[fighter]
                let pos = SCNVector3(Float(f.x) / 1000, 0.20, 0.20)
                emitBurst(at: pos, style: .heal, color: UIColor(red: 1.0, green: 0.88, blue: 0.34, alpha: 1),
                          count: 42, size: 0.46, speed: 3.8, life: 0.50, spread: 120)
                spawnShockRing(at: pos, color: .systemYellow, maxScale: 3.6, duration: 20, vertical: false)
                triggerFlash(at: pos, color: .systemYellow, intensity: 3200, ticks: 12)

            case .inquisitorStigmataFlash(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.40, 0.38)
                emitBurst(at: pos, style: .magic, color: UIColor(red: 1.0, green: 0.90, blue: 0.36, alpha: 1),
                          count: 44, size: 0.52, speed: 4.5, life: 0.42, spread: 180)
                spawnShockRing(at: pos, color: .systemYellow, maxScale: 3.4, duration: 18, vertical: true)
                triggerFlash(at: pos, color: .systemYellow, intensity: 3400, ticks: 12)

            case .inquisitorSalvationEcho(_, let x, let damage):
                // Light's Will 2nd Sky Smite: towering golden beam crashing down onto the armed ground rune!
                let fx = Float(x) / 1000
                let floorPos = SCNVector3(fx, 0.14, 0.20)
                let skyPos = SCNVector3(fx, 1.55, 0.28)
                emitBurst(at: floorPos, style: .heal, color: UIColor(red: 1.0, green: 0.90, blue: 0.32, alpha: 1),
                          count: 42, size: 0.48, speed: 4.6, life: 0.45, spread: 50, direction: SCNVector3(0, 1, 0))
                spawnShockRing(at: floorPos, color: .systemYellow, maxScale: 3.2, duration: 18, vertical: false)
                if damage > 0 {
                    spawnShockRing(at: skyPos, color: .systemYellow, maxScale: 2.8, duration: 16, vertical: true)
                    triggerFlash(at: skyPos, color: .systemYellow, intensity: 3200, ticks: 10)
                } else {
                    triggerFlash(at: floorPos, color: .systemYellow, intensity: 1800, ticks: 6)
                }

            case .nonnaFlameForm(let fighter):
                let f = game.fighters[fighter]
                let pos = SCNVector3(Float(f.x) / 1000, 0.20, 0.20)
                emitBurst(at: pos, style: .fire, color: UIColor(red: 1.0, green: 0.42, blue: 0.08, alpha: 1),
                          count: 46, size: 0.52, speed: 4.2, life: 0.48, spread: 140)
                spawnShockRing(at: pos, color: .systemOrange, maxScale: 3.8, duration: 20, vertical: false)
                triggerFlash(at: pos, color: .systemOrange, intensity: 3200, ticks: 12)

            case .nonnaWolfHit(let owner, _), .nonnaOwlHit(let owner, _, _):
                let def = game.fighters[1 - owner]
                let pos = SCNVector3(Float(def.x) / 1000, 1.12, 0.34)
                emitBurst(at: pos, style: .flame, color: UIColor(red: 1.0, green: 0.48, blue: 0.12, alpha: 1),
                          count: 26, size: 0.38, speed: 3.4, spread: 160)

            case .nonnaTrueShapeExecute(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.15, 0.40)
                emitBurst(at: pos, style: .fire, color: .systemOrange, count: 52, size: 0.56, speed: 5.2, life: 0.50, spread: 180)
                spawnShockRing(at: pos, color: .systemRed, maxScale: 4.0, duration: 22, vertical: true)
                triggerFlash(at: pos, color: .systemOrange, intensity: 3800, ticks: 14)

            case .midnightShadowShift(let fighter):
                let f = game.fighters[fighter]
                let pos = SCNVector3(Float(f.x) / 1000, 1.05, 0.25)
                emitBurst(at: pos, style: .twirl, color: UIColor(red: 0.56, green: 0.22, blue: 1.0, alpha: 0.9),
                          count: 28, size: 0.48, speed: 2.2, life: 0.38, spread: 180)

            case .midnightBlinkCounter(let attacker, _):
                // Spacetime rift cyan-violet counter + 18% heal shimmer!
                let atk = game.fighters[attacker]
                let def = game.fighters[1 - attacker]
                let hitPos = SCNVector3(Float(def.x) / 1000, 1.18, 0.38)
                let healPos = SCNVector3(Float(atk.x) / 1000, 1.05, 0.30)
                emitBurst(at: hitPos, style: .magic, color: UIColor(red: 0.42, green: 0.86, blue: 1.0, alpha: 1),
                          count: 40, size: 0.46, speed: 4.2, life: 0.42, spread: 180)
                emitBurst(at: healPos, style: .heal, color: UIColor(red: 0.36, green: 0.96, blue: 0.82, alpha: 0.95),
                          count: 22, size: 0.32, speed: 2.2, life: 0.44, spread: 90, direction: SCNVector3(0, 1, 0))
                spawnShockRing(at: hitPos, color: .systemCyan, maxScale: 3.2, duration: 16, vertical: true)
                triggerFlash(at: hitPos, color: .systemCyan, intensity: 3000, ticks: 10)

            case .midnightRemovalStrike(let attacker, _):
                // Double-crossed dimensional execute burst!
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.18, 0.40)
                emitBurst(at: pos, style: .magic, color: UIColor(red: 0.88, green: 0.18, blue: 1.0, alpha: 1),
                          count: 52, size: 0.54, speed: 5.0, life: 0.48, spread: 180)
                spawnShockRing(at: pos, color: .systemPurple, maxScale: 3.8, duration: 18, vertical: true)
                spawnShockRing(at: SCNVector3(pos.x, 0.14, 0.20), color: .systemPink, maxScale: 3.6, duration: 20, vertical: false)
                triggerFlash(at: pos, color: .systemPurple, intensity: 3600, ticks: 14)

            default:
                break
            }
        }

        // 3. Advance active slash arcs, shockwaves, and flash light smoothly at 60 Hz!
        for idx in slashNodes.indices.reversed() {
            slashNodes[idx].age += 1
            let s = slashNodes[idx]
            if s.age >= s.duration {
                s.node.removeFromParentNode()
                slashNodes.remove(at: idx)
            } else {
                let t = Float(s.age) / Float(s.duration)
                s.node.opacity = CGFloat(max(0, 1 - t * t))
                let pitch = (s.basePitch + s.sweepPitch * t) * s.facing
                s.node.eulerAngles.z = pitch
                let sc = 0.85 + 0.45 * t
                s.node.scale = SCNVector3(sc, sc, 1)
            }
        }
        for idx in shockRings.indices.reversed() {
            shockRings[idx].age += 1
            let r = shockRings[idx]
            if r.age >= r.duration {
                r.node.removeFromParentNode()
                shockRings.remove(at: idx)
            } else {
                let t = Float(r.age) / Float(r.duration)
                let sc = 0.4 + (r.maxScale - 0.4) * t
                r.node.scale = SCNVector3(sc, 1, sc)
                r.node.opacity = CGFloat(max(0, 1 - t))
            }
        }
        if flashTicks > 0 {
            flashTicks -= 1
            if flashTicks == 0 {
                flashLightNode.light?.intensity = 0
            } else {
                flashLightNode.light?.intensity = CGFloat(flashTicks) * 280
            }
        }
    }

    /// Update persistent hero form auras & Light's Will ground warning rune during `drawState()`.
    func updateAuras(_ game: DuelGame) {
        for i in 0..<min(2, game.fighters.count) {
            if let marker = salvationEchoMarkers[i] {
                if let inq = game.inquisitorState(i), inq.salvationEchoTicks > 0 {
                    let progress = 1.0 - Float(inq.salvationEchoTicks) / Float(max(1, DuelInquisitorState.salvationEchoDelayTicks))
                    let pulse: Float = 0.72 + 0.48 * progress
                    marker.isHidden = false
                    marker.position = SCNVector3(Float(inq.salvationEchoX) / 1000, 0.05, 0.05)
                    marker.scale = SCNVector3(pulse, 1, pulse)
                    marker.opacity = CGFloat(0.45 + 0.55 * progress)
                } else {
                    marker.isHidden = true
                }
            }
            guard let aura = fighterAuras[i] else { continue }
            let f = game.fighters[i]
            let pos = SCNVector3(Float(f.x) / 1000, Float(f.y) / 1000 + 0.95, 0)
            let kind: AuraEmitter.AuraKind
            if let shogun = game.shogunState(i) {
                if shogun.isCataclysm { kind = .shogunCataclysm }
                else if shogun.heavyChargeTicks > 0 { kind = .shogunCharge }
                else if shogun.isInShadow { kind = .shogunShadow }
                else { kind = .none }
            } else if let inq = game.inquisitorState(i), inq.isInFormOfLight {
                kind = .inquisitorLight
            } else if let nonna = game.nonnaState(i) {
                if nonna.isInFlameForm { kind = .nonnaFlame }
                else if nonna.empoweredStrikeReady { kind = .nonnaEmber }
                else { kind = .none }
            } else if let mid = game.midnightState(i) {
                if mid.isPhasedOut { kind = .midnightShift }
                else if mid.isInBlinkStance { kind = .midnightBlink }
                else if mid.isInShadowForm { kind = .midnightShadow }
                else { kind = .none }
            } else {
                kind = .none
            }
            aura.update(kind: kind, position: pos)
        }
    }

    /// Build a multi-layered golden Salvation Light Pillar with rising particle motes for Grand Inquisitor.
    static func makeSalvationPillarNode() -> SCNNode {
        func glowShape(_ geom: SCNGeometry, diffuse: UIColor, emission: UIColor, additive: Bool) -> SCNNode {
            let m = SCNMaterial()
            m.diffuse.contents = diffuse
            m.emission.contents = emission
            m.lightingModel = .constant
            if additive { m.blendMode = .add; m.writesToDepthBuffer = false }
            geom.materials = [m]
            let n = SCNNode(geometry: geom)
            n.castsShadow = false
            return n
        }
        let container = SCNNode()
        let core = glowShape(SCNCylinder(radius: 0.14, height: 3.2),
                             diffuse: UIColor(red: 1.0, green: 0.98, blue: 0.85, alpha: 0.95),
                             emission: UIColor(red: 1.0, green: 0.94, blue: 0.65, alpha: 1), additive: true)
        container.addChildNode(core)

        let outer = glowShape(SCNCylinder(radius: 0.34, height: 3.4),
                              diffuse: UIColor(red: 1.0, green: 0.80, blue: 0.22, alpha: 0.42),
                              emission: UIColor(red: 1.0, green: 0.72, blue: 0.14, alpha: 1), additive: true)
        container.addChildNode(outer)

        let ring = glowShape(SCNTorus(ringRadius: 0.56, pipeRadius: 0.032),
                             diffuse: UIColor(red: 1.0, green: 0.86, blue: 0.30, alpha: 0.95),
                             emission: .systemYellow, additive: false)
        ring.position = SCNVector3(0, -1.22, 0)
        container.addChildNode(ring)

        // Rising golden light particles
        let motes = SCNParticleSystem()
        motes.particleImage = ArenaEffectAssets.image(.heal) ?? ArenaEffectAssets.image(.magic)
        motes.particleColor = UIColor(red: 1.0, green: 0.90, blue: 0.36, alpha: 0.95)
        motes.birthRate = 32
        motes.particleLifeSpan = 0.55
        motes.particleSize = 0.28
        motes.particleVelocity = 2.2
        motes.spreadingAngle = 22
        motes.emittingDirection = SCNVector3(0, 1, 0)
        motes.blendMode = .additive
        motes.isLightingEnabled = false
        container.addParticleSystem(motes)
        return container
    }

    /// Build a fast spinning violet-steel Shadow Kunai with glowing shadow-energy trail for Midnight (Sun Deng).
    static func makeShadowKunaiNode() -> SCNNode {
        func kunaiPart(_ geom: SCNGeometry, diffuse: UIColor, emission: UIColor, additive: Bool = false) -> SCNNode {
            let m = SCNMaterial()
            m.diffuse.contents = diffuse
            m.emission.contents = emission
            m.lightingModel = additive ? .constant : .physicallyBased
            m.metalness.contents = 0.85
            m.roughness.contents = 0.22
            if additive { m.blendMode = .add; m.writesToDepthBuffer = false }
            geom.materials = [m]
            let n = SCNNode(geometry: geom)
            n.castsShadow = false
            return n
        }
        let container = SCNNode()
        // Tapered kunai blade pointing forward along +X
        let blade = kunaiPart(SCNCone(topRadius: 0.005, bottomRadius: 0.055, height: 0.34),
                              diffuse: UIColor(red: 0.78, green: 0.84, blue: 1.0, alpha: 1),
                              emission: UIColor(red: 0.56, green: 0.26, blue: 1.0, alpha: 0.85))
        blade.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        blade.position = SCNVector3(0.14, 0, 0)
        container.addChildNode(blade)

        let hilt = kunaiPart(SCNCylinder(radius: 0.022, height: 0.16),
                             diffuse: UIColor(red: 0.12, green: 0.10, blue: 0.18, alpha: 1),
                             emission: UIColor(red: 0.28, green: 0.12, blue: 0.55, alpha: 0.45))
        hilt.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        hilt.position = SCNVector3(-0.08, 0, 0)
        container.addChildNode(hilt)

        let pommel = kunaiPart(SCNTorus(ringRadius: 0.045, pipeRadius: 0.012),
                               diffuse: UIColor(red: 0.68, green: 0.42, blue: 1.0, alpha: 1),
                               emission: UIColor(red: 0.78, green: 0.36, blue: 1.0, alpha: 1), additive: true)
        pommel.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        pommel.position = SCNVector3(-0.18, 0, 0)
        container.addChildNode(pommel)

        // Glowing shadow aura cone wrapping the blade
        let aura = kunaiPart(SCNCone(topRadius: 0.01, bottomRadius: 0.095, height: 0.48),
                             diffuse: UIColor(red: 0.66, green: 0.24, blue: 1.0, alpha: 0.42),
                             emission: UIColor(red: 0.58, green: 0.22, blue: 1.0, alpha: 0.9), additive: true)
        aura.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        aura.position = SCNVector3(0.08, 0, 0)
        container.addChildNode(aura)

        let trail = SCNParticleSystem()
        trail.particleImage = ArenaEffectAssets.image(.trace) ?? ArenaEffectAssets.image(.magic)
        trail.particleColor = UIColor(red: 0.68, green: 0.28, blue: 1.0, alpha: 0.92)
        trail.birthRate = 48
        trail.particleLifeSpan = 0.22
        trail.particleSize = 0.20
        trail.particleVelocity = 1.6
        trail.spreadingAngle = 18
        trail.emittingDirection = SCNVector3(-1, 0, 0)
        trail.blendMode = .additive
        trail.isLightingEnabled = false
        container.addParticleSystem(trail)
        return container
    }
}
