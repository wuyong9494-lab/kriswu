import GameController
import UIKit

/// iOS performs pairing. No private Bluetooth protocol or speculative Hitbox
/// compatibility: this accepts only the profiles GameController actually exposes.
@MainActor
final class DuelPeripheralInput {
    typealias State = DuelPhysicalInput.State
    var onState: ((String, State, Bool) -> Void)?
    var canAccept: (() -> Bool)?
    private var observers: [NSObjectProtocol] = []
    private var pads: [ObjectIdentifier: GCController] = [:]
    private var keyboard: GCKeyboard?
    private var blocked = Set<String>()
    private static var owners: [ObjectIdentifier: UUID] = [:]
    private let ownerID = UUID()
    private var running = false
    private var active = true
    private let discoverControllers: () -> [GCController]
    private let discoverKeyboard: () -> GCKeyboard?
    private let applicationIsActive: () -> Bool
    private let center: NotificationCenter

    init(controllers: @escaping () -> [GCController] = { GCController.controllers() },
         keyboard: @escaping () -> GCKeyboard? = { GCKeyboard.coalesced },
         center: NotificationCenter = .default,
         applicationIsActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }) {
        discoverControllers = controllers; discoverKeyboard = keyboard
        self.applicationIsActive = applicationIsActive; self.center = center
    }

    func start() {
        guard !running else { return }
        running = true
        active = applicationIsActive()
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect,
                     .GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // NotificationCenter explicitly delivers on the main queue.
                // Keep cancellation synchronous; an unstructured Task could
                // arrive after a new press or a replacement control owner.
                MainActor.assumeIsolated {
                    guard let self, self.running else { return }
                    self.refreshDevices()
                }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.active = false; self.reset()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.active = true; self.refreshDevices()
            }
        })
        refreshDevices()
    }
    func stop() {
        guard running else { return }
        running = false
        reset()
        observers.forEach { center.removeObserver($0) }; observers.removeAll()
        for pad in pads.values { release(pad) }
        if let keyboard { release(keyboard) }
        pads.removeAll(); keyboard = nil; blocked.removeAll()
    }
    /// Re-arm only after all physical controls return to neutral. A held button
    /// across resume/reconnect must not fire or stick automatically.
    func reset() {
        for pad in pads.values where Self.owners[ObjectIdentifier(pad)] == ownerID {
            let key = id(pad); blocked.insert(key); onState?(key, .neutral, true)
        }
        if let keyboard, Self.owners[ObjectIdentifier(keyboard)] == ownerID {
            blocked.insert("keyboard"); onState?("keyboard", .neutral, true)
        }
        refreshReadiness()
    }
    private func release(_ device: GCDevice) {
        let key = ObjectIdentifier(device)
        guard Self.owners[key] == ownerID else { return }
        Self.owners.removeValue(forKey: key)
        if let pad = device as? GCController { pad.extendedGamepad?.valueChangedHandler = nil }
        if let keyboard = device as? GCKeyboard { keyboard.keyboardInput?.keyChangedHandler = nil }
    }
    /// Called after UIKit readiness/layout transitions as well as foreground.
    /// Neutral samples re-arm; held samples remain blocked.
    func refreshReadiness() {
        guard running else { return }
        for pad in pads.values { sample(pad) }
        sampleKeyboard()
    }
    private func id(_ pad: GCController) -> String { "pad:\(ObjectIdentifier(pad))" }
    func refreshDevices() {
        guard running else { return }
        let connected = discoverControllers().filter { $0.extendedGamepad != nil }
        let live = Set(connected.map { ObjectIdentifier($0) })
        for (key, pad) in Array(pads) where !live.contains(key) {
            if Self.owners[key] == ownerID { onState?(id(pad), .neutral, true) }
            release(pad)
            blocked.remove(id(pad)); pads.removeValue(forKey: key)
        }
        for pad in connected where pads[ObjectIdentifier(pad)] == nil {
            pads[ObjectIdentifier(pad)] = pad
            Self.owners[ObjectIdentifier(pad)] = ownerID
            onState?(id(pad), .neutral, true)
            pad.handlerQueue = .main
            blocked.insert(id(pad))
            pad.extendedGamepad?.valueChangedHandler = { [weak self, weak pad] _, _ in
                guard let self, let pad, self.pads[ObjectIdentifier(pad)] === pad, Self.owners[ObjectIdentifier(pad)] == self.ownerID else { return }
                self.sample(pad)
            }
            sample(pad)
        }
        let next = discoverKeyboard()
        if keyboard !== next {
            if let keyboard, Self.owners[ObjectIdentifier(keyboard)] == ownerID {
                onState?("keyboard", .neutral, true)
                release(keyboard)
            }
            keyboard = next; blocked.insert("keyboard")
            if let next {
                Self.owners[ObjectIdentifier(next)] = ownerID
                onState?("keyboard", .neutral, true)
            }
            next?.handlerQueue = .main
            next?.keyboardInput?.keyChangedHandler = { [weak self] _, _, _, _ in self?.sampleKeyboard() }
            sampleKeyboard()
        }
        refreshReadiness()
    }
    private func emit(_ state: State, key: String) {
        guard running else { return }
        guard active, canAccept?() == true else {
            if state == .neutral { blocked.remove(key) } else { blocked.insert(key) }
            onState?(key, .neutral, true); return
        }
        if blocked.contains(key) {
            if state == .neutral { blocked.remove(key) }
            return
        }
        onState?(key, state, false)
    }
    private func sample(_ pad: GCController) {
        guard Self.owners[ObjectIdentifier(pad)] == ownerID, let p = pad.extendedGamepad else { return }
        let dx = DuelPhysicalInput.digitalAxis(p.dpad.xAxis.value)
        let dy = DuelPhysicalInput.digitalAxis(p.dpad.yAxis.value)
        var actions = Set<DuelWeaponInput.Action>()
        if p.buttonX.isPressed { actions.insert(.weapon) }
        if p.buttonA.isPressed { actions.insert(.kick) }
        if p.buttonB.isPressed { actions.insert(.ranged) }
        if p.buttonY.isPressed { actions.insert(.shadow) }
        emit(State(x: dx == 0 ? DuelPhysicalInput.digitalAxis(p.leftThumbstick.xAxis.value) : dx,
                   y: dy == 0 ? DuelPhysicalInput.digitalAxis(p.leftThumbstick.yAxis.value) : dy,
                   actions: actions, guardHeld: p.leftShoulder.isPressed || p.leftTrigger.isPressed), key: id(pad))
    }
    private func sampleKeyboard() {
        guard let keyboard, Self.owners[ObjectIdentifier(keyboard)] == ownerID, let input = keyboard.keyboardInput else { return }
        func pressed(_ codes: [GCKeyCode]) -> Bool {
            codes.contains { input.button(forKeyCode: $0)?.isPressed == true }
        }
        var actions = Set<DuelWeaponInput.Action>()
        if pressed([.keyJ]) { actions.insert(.weapon) }
        if pressed([.keyK]) { actions.insert(.kick) }
        if pressed([.keyL]) { actions.insert(.ranged) }
        if pressed([.keyI]) { actions.insert(.shadow) }
        emit(State(x: (pressed([.keyD, .rightArrow]) ? 1 : 0) - (pressed([.keyA, .leftArrow]) ? 1 : 0),
                   y: (pressed([.keyW, .upArrow, .spacebar]) ? 1 : 0) - (pressed([.keyS, .downArrow]) ? 1 : 0),
                   actions: actions, guardHeld: pressed([.leftShift, .rightShift])), key: "keyboard")
    }
}
