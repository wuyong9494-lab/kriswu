import Foundation
import MetalKit
import SceneKit

/// Presents the existing source renderer inside MetalKit's synchronous draw
/// callback. MTKView advances currentDrawable only after that callback returns;
/// presenting directly from World would keep reusing an already presented one.
///
/// This adapter owns no clock and never changes pause, poses or source effects.
/// https://developer.apple.com/documentation/metalkit/mtkview/currentdrawable
/// https://developer.apple.com/documentation/metalkit/mtkview/draw()
@MainActor
final class DuelTriadSurfaceFrameDriver: NSObject, MTKViewDelegate {
    enum Failure: Error, Equatable {
        case stopped, delegateOwnership, reentrant
    }

    private struct Frame {
        let tick: Int
        let pointOfView: SCNNode?
        let samples: Int
    }

    private weak var surface: DuelTriadRenderSurface?
    private var pending: Frame?
    private var frameError: Error?
    private var drawing = false
    private var stopped = false

    init(surface: DuelTriadRenderSurface) throws {
        guard surface.delegate == nil else { throw Failure.delegateOwnership }
        self.surface = surface
        super.init()
        surface.delegate = self
    }

    /// `draw()` calls the delegate synchronously even though the automatic
    /// MetalKit loop is paused. A missing window/drawable or an in-flight skip
    /// remains a normal display skip in the original renderer. A callback that
    /// does not occur also consumes no simulation time and retains no request.
    func drawFrame(tick: Int, pointOfView: SCNNode?, samples: Int) throws {
        guard !stopped, let surface else { throw Failure.stopped }
        guard !drawing, pending == nil else { throw Failure.reentrant }
        guard surface.delegate === self else { throw Failure.delegateOwnership }
        drawing = true
        pending = Frame(tick: tick, pointOfView: pointOfView, samples: samples)
        frameError = nil
        defer {
            pending = nil
            frameError = nil
            drawing = false
        }
        surface.draw()
        if let frameError { throw frameError }
    }

    func draw(in view: MTKView) {
        guard !stopped, drawing, let surface, view === surface,
              let frame = pending else { return }
        // Consume before calling the renderer: an extra/reentrant callback
        // cannot submit the same frame a second time.
        pending = nil
        do {
            try surface.drawFrame(tick: frame.tick, pointOfView: frame.pointOfView, samples: frame.samples)
        } catch {
            frameError = error
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The existing surface owns its targets and World owns viewport fitting.
    }

    /// World calls this before shutting down the original surface. MTKView's
    /// delegate is weak; World retains this adapter only for the live renderer.
    func shutdown() {
        guard !stopped else { return }
        stopped = true
        pending = nil
        frameError = nil
        if let surface, surface.delegate === self { surface.delegate = nil }
        surface = nil
    }
}
