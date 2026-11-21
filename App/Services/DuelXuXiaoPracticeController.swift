#if L12_INTERNAL_PREVIEW
import SwiftUI

/// Owns the one preview loop. Suspension discards held input and elapsed time.
@MainActor
final class DuelXuXiaoPracticeController: ObservableObject {
    @Published private(set) var game = DuelXuXiaoPractice()
    @Published private(set) var paused = false
    private var input = DuelXuXiaoPractice.Input()
    private var sceneActive = false
    private var loop: Task<Void, Never>?
    private var generation = 0

    deinit { loop?.cancel() }
    func left(_ held: Bool) { input.left = held && sceneActive && !paused }
    func right(_ held: Bool) { input.right = held && sceneActive && !paused }
    func attack(heavy: Bool = false) {
        guard sceneActive, !paused, game.outcome == nil else { return }
        if heavy { input.heavy = true } else { input.attack = true }
    }
    func nudge(left: Bool) {
        guard sceneActive, !paused, game.outcome == nil else { return }
        input = .init(left: left, right: !left)
        game.step(input)
        input = .init()
    }
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        stopLoop()
        if active && !paused && game.outcome == nil { startLoop() }
    }
    func togglePause() {
        paused.toggle(); stopLoop()
        if !paused && sceneActive && game.outcome == nil { startLoop() }
    }
    func restart() {
        stopLoop(); game = .init(); paused = false
        if sceneActive { startLoop() }
    }
    func leave() { sceneActive = false; stopLoop() }
    private func stopLoop() {
        generation += 1; loop?.cancel(); loop = nil; input = .init()
    }
    private func startLoop() {
        let token = generation
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 16_666_667) } catch { return }
                guard let self, self.generation == token, self.sceneActive,
                      !self.paused, self.game.outcome == nil else { return }
                self.game.step(self.input)
                self.input.attack = false; self.input.heavy = false
                if self.game.outcome != nil { self.input = .init(); return }
            }
        }
    }
}
#endif
