import SwiftUI
import UIKit

/// 多点触控操作面板：左侧摇杆（左右移动、上推跳、快速双击冲刺），右侧技能键。
/// 用 UIKit 直接处理触摸，几根手指同时按也不会丢。
struct RiftControls: UIViewRepresentable {
    @ObservedObject var session: RiftSession
    let hero: RiftHeroID

    func makeUIView(context: Context) -> RiftControlPad {
        let pad = RiftControlPad(hero: hero)
        pad.onPress = { [weak session] in session?.press($0) }
        pad.onHorizontal = { [weak session] in session?.holdHorizontal = $0 }
        pad.onGuard = { [weak session] in session?.holdGuard = $0 }
        return pad
    }

    func updateUIView(_ pad: RiftControlPad, context: Context) {
        pad.update(hud: session.hud)
    }
}

final class RiftControlPad: UIView {
    struct Key {
        let id: String
        let button: RiftButton?
        let label: String
        var center: CGPoint = .zero
        let radius: CGFloat
        let layer = CAShapeLayer()
        let text = CATextLayer()
        let ring = CAShapeLayer()
        var touch: UITouch?
    }

    var onPress: ((RiftButton) -> Void)?
    var onHorizontal: ((Int8) -> Void)?
    var onGuard: ((Bool) -> Void)?

    private let hero: RiftHeroID
    private var keys: [Key] = []
    private let stickBase = CAShapeLayer()
    private let stickKnob = CAShapeLayer()
    private var stickTouch: UITouch?
    private var stickOrigin: CGPoint = .zero
    private var stickHome: CGPoint = .zero
    private var lastHorizontal: Int8 = 0
    private var lastTapDir: Int8 = 0
    private var lastTapTime: CFTimeInterval = 0
    private var jumpArmed = true
    private var guardTouch: UITouch?

    init(hero: RiftHeroID) {
        self.hero = hero
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        let spec = RiftRoster.spec(hero)
        keys = [
            Key(id: "rift.btn.light", button: .light, label: "轻击", radius: 46),
            Key(id: "rift.btn.heavy", button: .heavy, label: "重击", radius: 36),
            Key(id: "rift.btn.skill1", button: .skill1, label: spec.move(.skill1)?.name ?? "技能1", radius: 33),
            Key(id: "rift.btn.skill2", button: .skill2, label: spec.move(.skill2)?.name ?? "技能2", radius: 33),
            Key(id: "rift.btn.guard", button: nil, label: "防御", radius: 34),
            Key(id: "rift.btn.jump", button: .jump, label: "跳", radius: 27),
            Key(id: "rift.btn.dash", button: .dash, label: "闪", radius: 27),
            Key(id: "rift.btn.transform", button: .transform, label: spec.transformName, radius: 34),
        ]
        let accent = RiftPalette.accent(hero)
        let accentColor = UIColor(red: CGFloat(accent.x), green: CGFloat(accent.y), blue: CGFloat(accent.z), alpha: 1)
        for i in keys.indices {
            let k = keys[i]
            k.layer.fillColor = UIColor(white: 0.05, alpha: 0.42).cgColor
            k.layer.strokeColor = UIColor(white: 1, alpha: 0.55).cgColor
            k.layer.lineWidth = 2
            k.layer.shadowColor = accentColor.cgColor
            k.layer.shadowRadius = 0
            k.layer.shadowOpacity = 0
            layer.addSublayer(k.layer)
            k.ring.fillColor = UIColor(white: 0, alpha: 0.55).cgColor
            k.ring.strokeColor = UIColor.clear.cgColor
            layer.addSublayer(k.ring)
            k.text.string = k.label
            k.text.alignmentMode = .center
            k.text.fontSize = k.radius > 40 ? 17 : (k.label.count > 3 ? 11 : 13)
            k.text.font = UIFont.systemFont(ofSize: 13, weight: .heavy)
            k.text.foregroundColor = UIColor.white.cgColor
            k.text.contentsScale = UIScreen.main.scale
            layer.addSublayer(k.text)
        }
        stickBase.fillColor = UIColor(white: 0, alpha: 0.28).cgColor
        stickBase.strokeColor = UIColor(white: 1, alpha: 0.35).cgColor
        stickBase.lineWidth = 2
        stickKnob.fillColor = UIColor(white: 1, alpha: 0.55).cgColor
        layer.addSublayer(stickBase)
        layer.addSublayer(stickKnob)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = safeAreaInsets
        let w = bounds.width - inset.right, h = bounds.height - max(inset.bottom, 8)
        let positions: [String: CGPoint] = [
            "rift.btn.light": CGPoint(x: w - 92, y: h - 82),
            "rift.btn.heavy": CGPoint(x: w - 188, y: h - 52),
            "rift.btn.skill1": CGPoint(x: w - 178, y: h - 140),
            "rift.btn.skill2": CGPoint(x: w - 96, y: h - 184),
            "rift.btn.guard": CGPoint(x: w - 276, y: h - 46),
            "rift.btn.jump": CGPoint(x: w - 30, y: h - 150),
            "rift.btn.dash": CGPoint(x: w - 268, y: h - 124),
            "rift.btn.transform": CGPoint(x: w - 34, y: h - 232),
        ]
        for i in keys.indices {
            keys[i].center = positions[keys[i].id] ?? .zero
            let k = keys[i]
            let rect = CGRect(x: k.center.x - k.radius, y: k.center.y - k.radius, width: k.radius * 2, height: k.radius * 2)
            k.layer.path = UIBezierPath(ovalIn: rect).cgPath
            k.layer.shadowPath = k.layer.path
            k.ring.frame = bounds
            k.text.frame = CGRect(x: rect.minX - 6, y: k.center.y - k.text.fontSize * 0.68, width: rect.width + 12, height: k.text.fontSize * 1.5)
        }
        stickHome = CGPoint(x: inset.left + 112, y: h - 92)
        if stickTouch == nil { placeStick(origin: stickHome, knob: stickHome) }
        updateAccessibility()
    }

    private func placeStick(origin: CGPoint, knob: CGPoint) {
        stickBase.path = UIBezierPath(ovalIn: CGRect(x: origin.x - 66, y: origin.y - 66, width: 132, height: 132)).cgPath
        stickKnob.path = UIBezierPath(ovalIn: CGRect(x: knob.x - 28, y: knob.y - 28, width: 56, height: 56)).cgPath
    }

    private var fightingReady = false

    private func updateAccessibility() {
        var elements: [UIAccessibilityElement] = []
        for k in keys {
            let e = UIAccessibilityElement(accessibilityContainer: self)
            e.accessibilityIdentifier = k.id
            e.accessibilityLabel = k.label
            e.accessibilityValue = fightingReady ? "可施放" : "开场中"
            e.accessibilityTraits = .button
            e.accessibilityFrameInContainerSpace = CGRect(x: k.center.x - k.radius, y: k.center.y - k.radius, width: k.radius * 2, height: k.radius * 2)
            elements.append(e)
        }
        let left = UIAccessibilityElement(accessibilityContainer: self)
        left.accessibilityIdentifier = "rift.stick"
        left.accessibilityLabel = "移动"
        left.accessibilityFrameInContainerSpace = CGRect(x: stickHome.x - 66, y: stickHome.y - 66, width: 132, height: 132)
        elements.append(left)
        accessibilityElements = elements
    }

    func update(hud: RiftSession.HUD) {
        if hud.fighting != fightingReady {
            fightingReady = hud.fighting
            alpha = fightingReady ? 1.0 : 0.55
            updateAccessibility()
        }
        for i in keys.indices {
            let k = keys[i]
            var fraction = 0.0
            var glow = false
            switch k.button {
            case .skill1: fraction = hud.cooldown1
            case .skill2: fraction = hud.cooldown2
            case .transform:
                fraction = (hud.canTransform || hud.canUltimate) ? 0 : 1 - hud.rage[0]
                glow = hud.canTransform || hud.canUltimate
                let label = hud.canUltimate ? "终极" : RiftRoster.spec(hero).transformName
                if (k.text.string as? String) != label { k.text.string = label }
            case .light: glow = hud.counterReady
            default: break
            }
            let rect = CGRect(x: k.center.x - k.radius, y: k.center.y - k.radius, width: k.radius * 2, height: k.radius * 2)
            if fraction > 0.001 {
                let path = UIBezierPath()
                path.move(to: k.center)
                path.addArc(withCenter: k.center, radius: k.radius, startAngle: -.pi / 2,
                            endAngle: -.pi / 2 + .pi * 2 * CGFloat(fraction), clockwise: true)
                path.close()
                k.ring.path = path.cgPath
            } else {
                k.ring.path = nil
            }
            _ = rect
            k.layer.shadowOpacity = glow ? 1 : 0
            k.layer.shadowRadius = glow ? 12 : 0
            k.layer.strokeColor = glow ? UIColor.white.cgColor : UIColor(white: 1, alpha: 0.55).cgColor
        }
    }

    // MARK: 触摸

    private func key(at p: CGPoint) -> Int? {
        var best: (Int, CGFloat)?
        for (i, k) in keys.enumerated() {
            let d = hypot(p.x - k.center.x, p.y - k.center.y)
            if d <= k.radius + 12, best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if point.y < safeAreaInsets.top + 92 { return false }
        return super.point(inside: point, with: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if let i = key(at: p) {
                keys[i].touch = t
                setPressed(i, true)
                if let b = keys[i].button { onPress?(b) } else { onGuard?(true); guardTouch = t }
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            } else if p.x < bounds.width * 0.45, stickTouch == nil {
                stickTouch = t
                stickOrigin = p
                jumpArmed = true
                placeStick(origin: p, knob: p)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = stickTouch, touches.contains(t) else { return }
        let p = t.location(in: self)
        var dx = p.x - stickOrigin.x, dy = p.y - stickOrigin.y
        let len = hypot(dx, dy)
        if len > 56 { dx *= 56 / len; dy *= 56 / len }
        placeStick(origin: stickOrigin, knob: CGPoint(x: stickOrigin.x + dx, y: stickOrigin.y + dy))
        let h: Int8 = dx > 18 ? 1 : (dx < -18 ? -1 : 0)
        setHorizontal(h)
        if dy < -38 && jumpArmed { jumpArmed = false; onPress?(.jump) }
        if dy > -20 { jumpArmed = true }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

    private func finish(_ touches: Set<UITouch>) {
        for t in touches {
            if t === stickTouch {
                stickTouch = nil
                setHorizontal(0)
                placeStick(origin: stickHome, knob: stickHome)
            }
            for i in keys.indices where keys[i].touch === t {
                keys[i].touch = nil
                setPressed(i, false)
            }
            if t === guardTouch { guardTouch = nil; onGuard?(false) }
        }
    }

    private func setHorizontal(_ h: Int8) {
        guard h != lastHorizontal else { return }
        if h != 0 {
            let now = CACurrentMediaTime()
            // 同方向快速推两下：冲刺
            if h == lastTapDir && now - lastTapTime < 0.28 { onPress?(.dash) }
            lastTapDir = h
            lastTapTime = now
        }
        lastHorizontal = h
        onHorizontal?(h)
    }

    private func setPressed(_ i: Int, _ on: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        keys[i].layer.fillColor = UIColor(white: on ? 0.9 : 0.05, alpha: on ? 0.55 : 0.42).cgColor
        CATransaction.commit()
    }
}
