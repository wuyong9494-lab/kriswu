import Foundation

/// Derived fixed-step pose intervals for source sound/effect markers. Multiple
/// speed microsteps retain their intervals even when only the last pose is drawn.
/// These observations cannot apply damage and do not enter replay state bytes.
public struct DuelSourceMotionSample: Equatable, Sendable {
    public let frame: Int
    public let sequence: Int
    public let owner: Int
    public let clip: String
    public let previousTick: Int
    public let tick: Int
    public let duration: Int
    public func crosses(sourceFrame: Int, totalSourceFrames: Int) -> Bool {
        guard totalSourceFrames > 1, (0..<totalSourceFrames).contains(sourceFrame), duration > 0 else { return false }
        let marker = sourceFrame * duration / (totalSourceFrames - 1)
        return previousTick < marker && marker <= tick
    }
}
