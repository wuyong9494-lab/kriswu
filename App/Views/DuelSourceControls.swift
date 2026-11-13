import UIKit
import CryptoKit

/// Touch controls reconstructed from the source FightButtons/Joystick prefabs.
/// The renderer and touch mailbox are native UIKit; this is not recovered Unity code.
@MainActor
final class DuelSourceControlsView: UIView {
    enum Action: String, CaseIterable {
        case weapon, kick, ranged, shadow

        fileprivate var sprite: String {
            switch self {
            case .weapon: return "fist"
            case .kick: return "foot"
            case .ranged: return "shuriken_button"
            case .shadow: return "shadow"
            }
        }
        fileprivate var label: String {
            switch self {
            case .weapon: return "拳击或武器攻击"
            case .kick: return "踢击"
            case .ranged: return "远程武器"
            case .shadow: return "暗影能力"
            }
        }
        fileprivate var fallback: String {
            switch self {
            case .weapon: return "拳"
            case .kick: return "踢"
            case .ranged: return "远"
            case .shadow: return "影"
            }
        }
    }

    struct ActionState: Equatable {
        var enabled: Bool = true
        var ready: Bool = true
        var description: String = ""
        /// Each fighter can announce its own equipped weapon without changing
        /// the source glyph or coupling this control to a particular moveset.
        var accessibilityLabel: String? = nil
    }

    struct Layout {
        let scale: CGFloat
        let joystick: CGRect
        let joystickTouch: CGRect
        let actions: [Action: CGRect]
        let actionTouch: [Action: CGRect]
        /// Supplemental manual defense control; not an extra recovered source sprite.
        let manualGuard: CGRect

        static let empty = Layout(scale: 0, joystick: .zero, joystickTouch: .zero,
                                  actions: [:], actionTouch: [:], manualGuard: .zero)
    }

    /// Shared input representation for UIKit touch callbacks and native router tests.
    struct Pointer {
        let id: AnyHashable
        let location: CGPoint
    }

    /// Direction uses screen-independent axes: x right is +1, y up is +1.
    var onDirection: ((Int, Int) -> Void)?
    var onAction: ((Action, Bool) -> Void)?
    var onGuard: ((Bool) -> Void)?
    /// Cancellation precedes a matching release so a pending tap is discarded.
    var onActionCancelled: ((Action) -> Void)?
    /// Clears chord grace periods as well as buttons on pause/orientation/window loss.
    var onInputCancelled: (() -> Void)?
    /// Terminal renderer ownership release, distinct from temporary touch loss.
    var onShutdown: (() -> Void)?
    let peripheralInput = DuelPeripheralInput()
    private(set) var isShutdown = false
    var inputEnabled = true {
        didSet {
            if isShutdown { inputEnabled = false }
            guard inputEnabled != oldValue else { return }
            if !inputEnabled { cancelAll() }
            for action in Action.allCases { refresh(action) }
            refreshManualGuard()
            refreshStickDirection()
        }
    }
    /// A prone opponent can extend underneath the right-hand painted buttons.
    /// Keep the original touch rectangles and accessibility active while fading
    /// only their artwork; no gameplay or hit-testing geometry is changed.
    var opponentProne = false {
        didSet {
            guard opponentProne != oldValue else { return }
            for action in Action.allCases { refresh(action) }
        }
    }
    private(set) var obscuredActions: Set<Action> = []

    /// Renderer-projected conservative character bounds in this view's coordinates.
    /// Change artwork only: no touch rectangle, ownership, readiness or a11y changes.
    /// A small hysteresis band prevents flicker along a moving silhouette edge.
    func setCharacterOcclusion(_ rectangles: [CGRect]) {
        guard !isShutdown else { return }
        var next: Set<Action> = []
        for action in Action.allCases {
            guard let frame = layoutSnapshot.actions[action], frame.width > 0, frame.height > 0 else { continue }
            var fraction: CGFloat = 0
            for rect in rectangles {
                guard !rect.isNull, !rect.isInfinite, rect.minX.isFinite, rect.minY.isFinite,
                      rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { continue }
                let overlap = frame.intersection(rect)
                if !overlap.isNull {
                    fraction = max(fraction, overlap.width * overlap.height / (frame.width * frame.height))
                }
            }
            if fraction >= (obscuredActions.contains(action) ? 0.04 : 0.08) { next.insert(action) }
        }
        let changed = obscuredActions.symmetricDifference(next)
        obscuredActions = next
        for action in changed { refresh(action) }
    }

    private(set) var layoutSnapshot = Layout.empty
    private(set) var sourceArtAvailable = false
    private(set) var loadedSpriteNames: Set<String> = []

    private enum Contact { case joystick, action(Action), manualGuard }
    private var contacts: [AnyHashable: Contact] = [:]
    private var joystickOwner: AnyHashable?
    private var direction = (x: 0, y: 0)
    private var knobOffset = CGPoint.zero
    private var actionStates: [Action: ActionState] = [:]
    private var cancellingInput = false
    private var inputEpoch: UInt64 = 0
    private var buttons: [Action: DuelSourceActionButton] = [:]
    private let guardButton = DuelSourceActionButton(type: .custom)
    private var accessibilityGuardHeld = false
    private let stick = UIView()
    private let stickBackground = UIView()
    private let stickKnob = UIImageView()
    private var arrows: [UIImageView] = []
    private var lastLayoutBounds = CGRect.zero
    private var lastSafeArea = UIEdgeInsets.zero
    private let sprites: [String: UIImage]

    /// `assetDirectory` can point at the already-verified private resource folder.
    /// Xcode's flattened resources and preserved directory layouts are both supported.
    init(assetDirectory: URL? = nil, bundle: Bundle = .main) {
        sprites = Self.loadSprites(assetDirectory: assetDirectory, bundle: bundle)
        super.init(frame: .zero)
        loadedSpriteNames = Set(sprites.keys)
        sourceArtAvailable = Self.spriteHashes.keys.allSatisfy { sprites[$0] != nil }
        configure()
    }

    /// Image injection is useful for rendering checks; it never claims source verification.
    init(images: [String: UIImage]) {
        sprites = images
        super.init(frame: .zero)
        loadedSpriteNames = Set(images.keys)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        stick.isUserInteractionEnabled = false
        stick.isAccessibilityElement = true
        stick.accessibilityIdentifier = "duel.control.joystick"
        stick.accessibilityLabel = "八方向摇杆"
        stick.accessibilityHint = "向所需方向拖动，松开回到中央。方向可配合武器、踢击或暗影按钮。"
        stick.accessibilityTraits = [.allowsDirectInteraction]
        stick.accessibilityValue = "居中"
        addSubview(stick)
        stickBackground.backgroundColor = UIColor.white.withAlphaComponent(0.1019607857)
        stick.addSubview(stickBackground)
        for index in 0..<8 {
            let arrow = UIImageView(image: sprites[index.isMultiple(of: 2) ? "stick_arrow" : "stick_arrow_small"])
            arrow.isUserInteractionEnabled = false
            arrow.contentMode = .scaleToFill
            arrow.alpha = index.isMultiple(of: 2) ? 0.572 : 0.403
            stick.addSubview(arrow)
            arrows.append(arrow)
        }
        stickKnob.image = sprites["stick_circle"]
        stickKnob.contentMode = .scaleToFill
        stickKnob.alpha = 0.572
        stick.addSubview(stickKnob)
        for action in Action.allCases {
            let button = DuelSourceActionButton(type: .custom)
            button.isUserInteractionEnabled = false // Parent owns every touch until its release.
            button.isAccessibilityElement = true
            button.adjustsImageWhenDisabled = false
            button.accessibilityIdentifier = "duel.control.\(action.rawValue)"
            button.accessibilityLabel = action.label
            button.accessibilityHint = action == .weapon || action == .kick ? "可配合摇杆方向出招" : nil
            if let sprite = sprites[action.sprite] {
                button.setImage(sprite.withRenderingMode(.alwaysOriginal), for: .normal)
                button.imageView?.contentMode = .scaleToFill
            } else {
                // Non-private development builds must still expose usable controls.
                // The source-asset status remains false and cannot pass a source-art assertion.
                button.setTitle(action.fallback, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 22, weight: .medium)
                button.layer.borderWidth = 1
                button.layer.borderColor = UIColor.white.cgColor
            }
            button.activate = { [weak self] in
                self?.activateAction(action) ?? false
            }
            buttons[action] = button
            actionStates[action] = ActionState()
            addSubview(button)
            refresh(action)
        }
        // Defense is an explicit app control. Keep all four verified source
        // actions, their artwork and their measured touch zones unchanged.
        guardButton.isUserInteractionEnabled = false
        guardButton.isAccessibilityElement = true
        guardButton.accessibilityIdentifier = "duel.control.guard"
        guardButton.accessibilityLabel = "手动防御"
        guardButton.accessibilityHint = "触摸时按住防御，松开解除。双击可切换防御。移动、跳跃或攻击时不能防御。"
        guardButton.setTitle("按住防御", for: .normal)
        guardButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        guardButton.layer.borderWidth = 1
        guardButton.layer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor
        guardButton.layer.cornerRadius = 12
        guardButton.activate = { [weak self] in self?.activateManualGuard() ?? false }
        addSubview(guardButton)
        refreshManualGuard()
        var elements: [Any] = [stick, guardButton]
        elements.append(contentsOf: Action.allCases.compactMap { buttons[$0] })
        accessibilityElements = elements
    }

    /// Equipment or unimplemented actions are disabled explicitly. Readiness is a visual
    /// state; gameplay decides whether an enabled button can currently start its move.
    /// Changing readiness while a finger is down must not synthesize a release.
    func setState(_ value: ActionState, for action: Action) {
        guard state(for: action) != value else { return }
        actionStates[action] = value
        if !value.enabled { releaseAction(action) }
        refresh(action)
    }

    func state(for action: Action) -> ActionState { actionStates[action] ?? ActionState() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds != lastLayoutBounds || safeAreaInsets != lastSafeArea {
            // Orientation and safe-area changes cannot leave a finger attached to an old zone.
            cancelAll()
            setCharacterOcclusion([]) // Old coordinates are invalid after rotation.
            lastLayoutBounds = bounds
            lastSafeArea = safeAreaInsets
        }
        layoutSnapshot = Self.makeLayout(in: bounds, safeArea: safeAreaInsets)
        guardButton.frame = layoutSnapshot.manualGuard
        let s = layoutSnapshot.scale
        stick.frame = layoutSnapshot.joystick
        stickBackground.frame = stick.bounds
        stickBackground.layer.cornerRadius = stick.bounds.width / 2
        for (index, arrow) in arrows.enumerated() {
            let cardinal = index.isMultiple(of: 2)
            let point = Self.arrowCenters[index]
            arrow.transform = .identity
            arrow.bounds = CGRect(x: 0, y: 0, width: (cardinal ? 80 : 40) * s,
                                  height: (cardinal ? 50 : 20) * s)
            arrow.center = CGPoint(x: stick.bounds.midX + point.x * s,
                                   y: stick.bounds.midY - point.y * s)
            arrow.transform = CGAffineTransform(rotationAngle: CGFloat(index) * .pi / 4)
        }
        stickKnob.bounds = CGRect(x: 0, y: 0, width: 190 * s, height: 190 * s)
        stickKnob.center = CGPoint(x: stick.bounds.midX + knobOffset.x, y: stick.bounds.midY + knobOffset.y)
        for action in Action.allCases {
            guard let button = buttons[action], let frame = layoutSnapshot.actions[action] else { continue }
            button.frame = frame
            button.layer.cornerRadius = frame.width / 2
            if action == .ranged {
                // The source missile's 210-square button contains a 134 x 140 glyph.
                button.imageEdgeInsets = UIEdgeInsets(top: 35 * s, left: 38 * s,
                                                      bottom: 35 * s, right: 38 * s)
            }
        }
    }

    /// Source reference canvas is 2732 x 1536. Preserve its control sizes, offsets,
    /// and bottom/edge margins inside the current device's safe drawing area.
    /// This is an explicit UIKit adaptation, not a claim to reproduce Unity's scaler.
    static func makeLayout(in bounds: CGRect, safeArea: UIEdgeInsets) -> Layout {
        let safe = bounds.inset(by: safeArea)
        guard safe.width > 0, safe.height > 0 else { return .empty }
        let s = min(safe.width / 2732, safe.height / 1536)
        let left = CGPoint(x: safe.minX + 304 * s, y: safe.maxY - 304 * s)
        let right = CGPoint(x: safe.maxX - 321 * s, y: safe.maxY - 390 * s)
        func rect(center: CGPoint, width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: center.x - width * s / 2, y: center.y - height * s / 2,
                   width: width * s, height: height * s)
        }
        func offset(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: right.x + x * s, y: right.y - y * s)
        }
        let frames: [Action: CGRect] = [
            .weapon: rect(center: offset(100, 5), width: 205, height: 205),
            .kick: rect(center: offset(-0.1249542, -190), width: 205, height: 205),
            .ranged: rect(center: offset(0, 214.7), width: 210, height: 210),
            .shadow: rect(center: offset(-100, 5), width: 210, height: 210)
        ]
        // The original touch zones are deliberately larger than the painted glyphs.
        let zones: [Action: CGRect] = [
            .weapon: rect(center: offset(154.5, 50.75), width: 314, height: 296),
            .kick: rect(center: offset(-1.1249542, -246), width: 462, height: 288),
            .ranged: rect(center: offset(2, 249.7), width: 460, height: 277),
            .shadow: rect(center: offset(-152.75, 48.75), width: 315.5, height: 297.5)
        ]
        let guardWidth = min(safe.width, max(88, 260 * s))
        let guardHeight = min(safe.height, max(44, 135 * s))
        let guardFrame = CGRect(x: safe.midX - guardWidth / 2,
                                y: max(safe.minY, safe.maxY - max(12, 44 * s) - guardHeight),
                                width: guardWidth, height: guardHeight)
        return Layout(scale: s, joystick: rect(center: left, width: 500, height: 500),
                      joystickTouch: rect(center: left, width: 700, height: 700),
                      actions: frames, actionTouch: zones, manualGuard: guardFrame)
    }

    /// Uses the prefab's 65-unit neutral radius and 60/30-degree cardinal/diagonal
    /// sectors. Equality at a sector boundary is assigned deterministically.
    static func quantizedDirection(offset: CGPoint, scale: CGFloat) -> (x: Int, y: Int) {
        guard scale > 0, offset.x.isFinite, offset.y.isFinite,
              hypot(offset.x, offset.y) > 65 * scale else { return (0, 0) }
        let x = offset.x, y = offset.y
        let diagonalEdge = CGFloat(0.5773502691896257) // tan(30 degrees)
        if abs(y) <= abs(x) * diagonalEdge { return (x > 0 ? 1 : -1, 0) }
        if abs(x) <= abs(y) * diagonalEdge { return (0, y > 0 ? 1 : -1) }
        return (x > 0 ? 1 : -1, y > 0 ? 1 : -1)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard inputEnabled, !isShutdown else { return false }
        return layoutSnapshot.joystickTouch.contains(point) ||
            layoutSnapshot.manualGuard.contains(point) ||
            layoutSnapshot.actionTouch.values.contains { $0.contains(point) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        beginPointers(touches.map { Pointer(id: ObjectIdentifier($0), location: $0.location(in: self)) })
    }

    func beginPointers(_ pointers: [Pointer]) {
        guard inputEnabled, !cancellingInput, !isShutdown else { return }
        let epoch = inputEpoch
        // Resolve the direction first when an action and joystick arrive in one event.
        if joystickOwner == nil,
           let pointer = pointers.first(where: {
               contacts[$0.id] == nil && layoutSnapshot.joystickTouch.contains($0.location)
           }) {
            joystickOwner = pointer.id
            contacts[pointer.id] = .joystick
            moveJoystick(to: pointer.location)
        }
        for pointer in pointers {
            guard inputEnabled, !cancellingInput, inputEpoch == epoch else { break }
            guard contacts[pointer.id] == nil else { continue }
            if layoutSnapshot.manualGuard.contains(pointer.location) {
                let wasHeld = isGuardHeld
                contacts[pointer.id] = .manualGuard
                refreshManualGuard()
                if !wasHeld { onGuard?(true) }
                continue
            }
            guard contacts[pointer.id] == nil, let action = action(at: pointer.location),
                  state(for: action).enabled else { continue }
            let wasHeld = isHeld(action)
            contacts[pointer.id] = .action(action)
            refresh(action)
            if !wasHeld { onAction?(action, true) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        movePointers(touches.map { Pointer(id: ObjectIdentifier($0), location: $0.location(in: self)) })
    }

    func movePointers(_ pointers: [Pointer]) {
        guard inputEnabled, !cancellingInput, !isShutdown else { return }
        for pointer in pointers where pointer.id == joystickOwner {
            moveJoystick(to: pointer.location)
        }
        for pointer in pointers {
            guard let contact = contacts[pointer.id] else { continue }
            let zone: CGRect
            switch contact {
            case .joystick: continue
            case .manualGuard: zone = layoutSnapshot.manualGuard
            case .action(let action):
                guard let frame = layoutSnapshot.actionTouch[action] else { continue }
                zone = frame
            }
            if !zone.insetBy(dx: -12, dy: -12).contains(pointer.location) {
                release(pointer.id, cancelled: true)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endPointers(touches.map { AnyHashable(ObjectIdentifier($0)) })
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelPointers(touches.map { AnyHashable(ObjectIdentifier($0)) })
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { peripheralInput.stop(); cancelAll(); setCharacterOcclusion([]) }
        else if !isShutdown { peripheralInput.start() }
    }

    func endPointers(_ ids: [AnyHashable]) { ids.forEach { release($0, cancelled: false) } }

    func cancelPointers(_ ids: [AnyHashable]) {
        // A cancelled direction touch invalidates a pending two-finger chord.
        // Clear both sides atomically; a normal joystick release is not cancellation.
        if let owner = joystickOwner, ids.contains(owner) { cancelAll(); return }
        ids.forEach { release($0, cancelled: true) }
    }

    func cancelAll(notify: Bool = true) {
        // The consumer may clear its mailbox and call cancelAll(notify: false)
        // from the cancellation hook. Clear ownership first and avoid recursion.
        guard !cancellingInput else { return }
        cancellingInput = true
        peripheralInput.reset()
        inputEpoch &+= 1
        defer { cancellingInput = false }
        let held = Action.allCases.filter(isHeld)
        let guardWasHeld = isGuardHeld
        contacts.removeAll()
        accessibilityGuardHeld = false
        joystickOwner = nil
        let changed = direction.x != 0 || direction.y != 0
        direction = (0, 0)
        resetStickVisuals()
        for action in Action.allCases { refresh(action) }
        refreshManualGuard()
        if notify {
            onInputCancelled?()
            held.forEach { onActionCancelled?($0) }
            if changed { onDirection?(0, 0) }
            for action in held { onAction?(action, false) }
            if guardWasHeld { onGuard?(false) }
        }
    }

    /// A replaced/dismantled control must never cancel the current view's
    /// mailbox. Disconnect consumers before dropping its physical contacts.
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        peripheralInput.stop()
        let released = onShutdown; onShutdown = nil
        onDirection = nil; onAction = nil; onGuard = nil
        onActionCancelled = nil; onInputCancelled = nil
        cancelAll(notify: false)
        inputEnabled = false
        released?()
    }

    private func activateAction(_ action: Action) -> Bool {
        guard inputEnabled, !cancellingInput, !isShutdown, state(for: action).enabled, !isHeld(action),
              let frame = layoutSnapshot.actions[action], frame.width > 0, frame.height > 0 else { return false }
        let id = UUID()
        // Accessibility activation uses the same ownership and cancellation path.
        // A consumer disabling the action during Down cannot turn this into a tap.
        beginPointers([Pointer(id: id, location: CGPoint(x: frame.midX, y: frame.midY))])
        let accepted = contacts[id] != nil
        endPointers([id])
        return accepted
    }

    private func action(at point: CGPoint) -> Action? {
        // Source touch rectangles overlap. Resolve overlap by the nearest icon,
        // making a single touch own exactly one action for its entire lifetime.
        Action.allCases.filter { layoutSnapshot.actionTouch[$0]?.contains(point) == true }
            .min { first, second in
                guard let a = layoutSnapshot.actions[first], let b = layoutSnapshot.actions[second] else { return false }
                return hypot(point.x - a.midX, point.y - a.midY) < hypot(point.x - b.midX, point.y - b.midY)
            }
    }

    private var hasGuardTouch: Bool {
        contacts.values.contains { if case .manualGuard = $0 { return true }; return false }
    }

    private var isGuardHeld: Bool { accessibilityGuardHeld || hasGuardTouch }

    private func activateManualGuard() -> Bool {
        guard inputEnabled, !cancellingInput, !isShutdown, !hasGuardTouch,
              layoutSnapshot.manualGuard.width >= 44, layoutSnapshot.manualGuard.height >= 44 else { return false }
        // VoiceOver cannot sustain an ordinary pointer. A deliberate activation
        // toggles the same held intent; every lifecycle cancellation releases it.
        let epoch = inputEpoch
        let next = !accessibilityGuardHeld
        accessibilityGuardHeld = next
        refreshManualGuard()
        onGuard?(next)
        return inputEnabled && !isShutdown && inputEpoch == epoch && accessibilityGuardHeld == next
    }

    private func refreshManualGuard() {
        let enabled = inputEnabled && !isShutdown
        guardButton.isEnabled = enabled
        guardButton.alpha = enabled ? 0.85 : 0.3
        guardButton.backgroundColor = UIColor.white.withAlphaComponent(isGuardHeld ? 0.35 : 0.08)
        guardButton.accessibilityTraits = enabled ? [.button] : [.button, .notEnabled]
        if isGuardHeld { guardButton.accessibilityTraits.insert(.selected) }
        // This reports explicit input intent, never claims the fighter can block
        // while airborne, moving, attacking or recovering.
        guardButton.accessibilityValue = !enabled ? "操作已暂停" : isGuardHeld ? "已按住" : "未按住"
    }

    private func moveJoystick(to point: CGPoint) {
        let frame = layoutSnapshot.joystick
        let delta = CGPoint(x: point.x - frame.midX, y: frame.midY - point.y)
        let next = Self.quantizedDirection(offset: delta, scale: layoutSnapshot.scale)
        let distance = hypot(delta.x, delta.y)
        let limit = 95 * layoutSnapshot.scale
        let ratio = distance > limit && distance > 0 ? limit / distance : 1
        knobOffset = CGPoint(x: delta.x * ratio, y: -delta.y * ratio)
        stickKnob.center = CGPoint(x: stick.bounds.midX + knobOffset.x,
                                   y: stick.bounds.midY + knobOffset.y)
        if next.x != direction.x || next.y != direction.y {
            direction = next
            refreshStickDirection()
            onDirection?(next.x, next.y)
        }
    }

    private func release(_ id: AnyHashable, cancelled: Bool) {
        guard let contact = contacts.removeValue(forKey: id) else { return }
        switch contact {
        case .joystick:
            joystickOwner = nil
            let changed = direction.x != 0 || direction.y != 0
            direction = (0, 0)
            resetStickVisuals()
            if changed { onDirection?(0, 0) }
        case .action(let action):
            if !isHeld(action) {
                if cancelled { onActionCancelled?(action) }
                onAction?(action, false)
            }
            refresh(action)
        case .manualGuard:
            refreshManualGuard()
            if !isGuardHeld { onGuard?(false) }
        }
    }

    private func isHeld(_ action: Action) -> Bool {
        contacts.values.contains { if case .action(let value) = $0 { return value == action }; return false }
    }

    private func releaseAction(_ action: Action) {
        let ids = contacts.compactMap { id, value -> AnyHashable? in
            if case .action(let held) = value, held == action { return id }; return nil
        }
        for id in ids { contacts.removeValue(forKey: id) }
        if !ids.isEmpty {
            onActionCancelled?(action)
            onAction?(action, false)
        }
    }

    private func refresh(_ action: Action) {
        guard let button = buttons[action] else { return }
        let state = state(for: action)
        let enabled = inputEnabled && state.enabled
        button.isEnabled = enabled
        // Keep the existing prone treatment, but never multiply two fades.
        // A held overlapping button remains legible as immediate touch feedback.
        let overlapFade: CGFloat = obscuredActions.contains(action) ? (isHeld(action) ? 0.75 : 0.45) : 1
        let artworkFade: CGFloat = opponentProne ? 0.35 : overlapFade
        button.alpha = (enabled ? (state.ready ? 2.0 / 3.0 : 0.38) * (isHeld(action) ? 0.7843137 : 1) : 0.22) * artworkFade
        button.accessibilityTraits = enabled ? [.button] : [.button, .notEnabled]
        button.accessibilityLabel = state.accessibilityLabel ?? action.label
        button.accessibilityValue = !inputEnabled ? "操作已暂停" :
            state.description.isEmpty ? (state.enabled ? (state.ready ? "可用" : "恢复中") : "未装备") : state.description
    }

    private func resetStickVisuals() {
        knobOffset = .zero
        stickKnob.center = CGPoint(x: stick.bounds.midX, y: stick.bounds.midY)
        refreshStickDirection()
    }

    private func refreshStickDirection() {
        for (index, arrow) in arrows.enumerated() {
            let point = Self.arrowCenters[index]
            let x = point.x == 0 ? 0 : point.x > 0 ? 1 : -1
            let y = point.y == 0 ? 0 : point.y > 0 ? 1 : -1
            arrow.alpha = direction.x == x && direction.y == y ? 1 : index.isMultiple(of: 2) ? 0.572 : 0.403
        }
        let horizontal = direction.x < 0 ? "左" : direction.x > 0 ? "右" : ""
        let vertical = direction.y < 0 ? "下" : direction.y > 0 ? "上" : ""
        stick.accessibilityTraits = inputEnabled ? [.allowsDirectInteraction] : [.allowsDirectInteraction, .notEnabled]
        stick.accessibilityValue = !inputEnabled ? "操作已暂停" :
            horizontal.isEmpty && vertical.isEmpty ? "居中" : horizontal + vertical
    }

    private static let arrowCenters: [CGPoint] = [
        CGPoint(x: 0, y: 180), CGPoint(x: 120, y: 120), CGPoint(x: 180, y: 0), CGPoint(x: 120, y: -120),
        CGPoint(x: 0, y: -180), CGPoint(x: -120, y: -120), CGPoint(x: -180, y: 0), CGPoint(x: -120, y: 120)
    ]

    /// PNG hashes are for the exact exported source sprites, not screenshots or redraws.
    private static let spriteHashes: [String: String] = [
        "fist": "be9260fe6a6568d574a52cea91b9566157d4bdb4e2910ce56b7f6aed77df08cf",
        "foot": "1629dedbbec4232ff5c1fe9d0a9274a2833620b98b5a299d3df8b1cf3ca06fba",
        "shadow": "288bccb032861cf27f368cbbe4acccc5d37c47de318c95cb067f983d67ff3895",
        "shuriken_button": "da3341281cebced8f61046f16f16901fd919341d281cdb888408488044b44750",
        "stick_arrow": "3e051a2543f650372768738aef21264fac0e1dd4567293c948d696a6c0d7888b",
        "stick_arrow_small": "b2ee0fdc016545f81f40c016774fa4923a9e0aabb16203c572f385b6b0fcb5a0",
        "stick_circle": "afdeff42db49b8526a67f4264cce7e19380aff839e15317c62e9ccaed936e8d8"
    ]

    private static func loadSprites(assetDirectory: URL?, bundle: Bundle) -> [String: UIImage] {
        var images: [String: UIImage] = [:]
        for (name, expected) in spriteHashes {
            let prefixed = "SF3UI_\(name)"
            var candidates: [URL] = []
            if let directory = assetDirectory {
                // An explicit resource directory is authoritative. A corrupt file must
                // not pass by falling back to a second bundle copy of the same sprite.
                candidates.append(directory.appendingPathComponent("\(prefixed).png"))
                candidates.append(directory.appendingPathComponent("\(name).png"))
            } else {
                if let url = bundle.url(forResource: prefixed, withExtension: "png") { candidates.append(url) }
                if let resource = bundle.resourceURL {
                    candidates.append(resource.appendingPathComponent("FighterPrivate/\(prefixed).png"))
                    candidates.append(resource.appendingPathComponent("FighterPrivate/Controls/\(prefixed).png"))
                    candidates.append(resource.appendingPathComponent("FighterPrivate/Controls/\(name).png"))
                }
            }
            for url in candidates {
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 131_072,
                      let data = try? Data(contentsOf: url), data.count == size,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected,
                      let image = UIImage(data: data) else { break }
                images[name] = image
                break
            }
        }
        return images
    }
}

@MainActor
private final class DuelSourceActionButton: UIButton {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}

