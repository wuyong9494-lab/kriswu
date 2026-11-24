import GameController
import QuartzCore
import SwiftUI
import UIKit

/// Non-invasive physical controller & keyboard menu navigator for SwiftUI screens
/// (Lobby, Pause menu, Match Result panel, and Network Lobby).
/// Polls controller state directly on a 30 Hz CADisplayLink when enabled so it
/// never overwrites `DuelPeripheralInput`'s combat `valueChangedHandler` ownership.
@MainActor
final class DuelGamepadMenuMonitor: ObservableObject {
    @Published private(set) var connectedNames: [String] = []
    var hasController: Bool { !connectedNames.isEmpty }
    var onAction: ((DuelGamepadMenuAction) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var displayLink: CADisplayLink?
    private var detector = DuelGamepadMenuEdgeDetector()
    private var menuActive = false
    private var started = false

    @MainActor
    private final class PollTarget: NSObject {
        weak var owner: DuelGamepadMenuMonitor?
        init(_ owner: DuelGamepadMenuMonitor) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.poll() }
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect,
                     .GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshConnected() }
            })
        }
        refreshConnected()
        if menuActive { startPolling() }
    }

    func stop() {
        guard started else { return }
        started = false
        stopPolling()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        detector.reset()
    }

    func setMenuActive(_ active: Bool) {
        guard menuActive != active else { return }
        menuActive = active
        detector.reset()
        if active && started { startPolling() } else { stopPolling() }
    }

    private func refreshConnected() {
        let names = GCController.controllers()
            .filter { $0.extendedGamepad != nil || $0.microGamepad != nil }
            .map { $0.vendorName ?? "游戏手柄" }
            .sorted()
        if connectedNames != names {
            connectedNames = names
        }
    }

    private func startPolling() {
        guard displayLink == nil else { return }
        detector.reset()
        let link = CADisplayLink(target: PollTarget(self), selector: #selector(PollTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopPolling() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func poll() {
        guard started, menuActive, UIApplication.shared.applicationState == .active else {
            detector.reset()
            return
        }
        var x = 0, y = 0
        var confirm = false, cancel = false, secondary = false, tertiary = false
        var shoulderL = false, shoulderR = false, menu = false

        for pad in GCController.controllers() {
            if let p = pad.extendedGamepad {
                let dx = DuelPhysicalInput.digitalAxis(p.dpad.xAxis.value)
                let dy = DuelPhysicalInput.digitalAxis(p.dpad.yAxis.value)
                let lx = DuelPhysicalInput.digitalAxis(p.leftThumbstick.xAxis.value)
                let ly = DuelPhysicalInput.digitalAxis(p.leftThumbstick.yAxis.value)
                if dx != 0 { x = dx } else if lx != 0 { x = lx }
                if dy != 0 { y = dy } else if ly != 0 { y = ly }
                if p.buttonA.isPressed { confirm = true }
                if p.buttonB.isPressed { cancel = true }
                if p.buttonX.isPressed { secondary = true }
                if p.buttonY.isPressed { tertiary = true }
                if p.leftShoulder.isPressed { shoulderL = true }
                if p.rightShoulder.isPressed { shoulderR = true }
                if p.buttonMenu.isPressed { menu = true }
            } else if let m = pad.microGamepad {
                let dx = DuelPhysicalInput.digitalAxis(m.dpad.xAxis.value)
                let dy = DuelPhysicalInput.digitalAxis(m.dpad.yAxis.value)
                if dx != 0 { x = dx }
                if dy != 0 { y = dy }
                if m.buttonA.isPressed { confirm = true }
                if m.buttonX.isPressed { secondary = true }
                if m.buttonMenu.isPressed { menu = true }
            }
        }
        if let input = GCKeyboard.coalesced?.keyboardInput {
            func key(_ codes: [GCKeyCode]) -> Bool {
                codes.contains { input.button(forKeyCode: $0)?.isPressed == true }
            }
            if key([.rightArrow, .keyD]) { x = 1 } else if key([.leftArrow, .keyA]) { x = -1 }
            if key([.upArrow, .keyW]) { y = 1 } else if key([.downArrow, .keyS]) { y = -1 }
            if key([.returnOrEnter, .spacebar]) { confirm = true }
            if key([.escape]) { cancel = true; menu = true }
            if key([.keyX, .keyJ]) { secondary = true }
            if key([.keyY]) { tertiary = true }
        }

        let snapshot = DuelGamepadMenuSnapshot(
            x: x, y: y, confirm: confirm, cancel: cancel,
            secondary: secondary, tertiary: tertiary,
            shoulderLeft: shoulderL, shoulderRight: shoulderR, menu: menu
        )
        let actions = detector.update(snapshot)
        for action in actions {
            onAction?(action)
        }
    }
}
