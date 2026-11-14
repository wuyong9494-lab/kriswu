import XCTest
@testable import ShiftCore

/// Source lock923 interval timing only. These checks do not claim an installed
/// audio pack, a native FloorHit callback, spatial defaults or device playback.
final class DuelFloorfallSourceMarkerTests: XCTestCase {
    private func sample(frames: Int, previous: Int, tick: Int) -> DuelSourceMotionSample {
        .init(frame: 100, sequence: 0, owner: 0, clip: "source-floorfall-fixture",
              previousTick: previous, tick: tick, duration: 2 * (frames - 1))
    }

    func testBothRecoveredIntervalsCrossAtTick38() {
        // H_Head_Middle_Average_Critical_Fall: 59 samples.
        // H17_Root_Spike_Passive_End: 48 samples.
        // Interval.Start=20 becomes zero-based source sample 19.
        for frames in [59, 48] {
            XCTAssertFalse(sample(frames: frames, previous: 36, tick: 37)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
            XCTAssertTrue(sample(frames: frames, previous: 37, tick: 38)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
            XCTAssertFalse(sample(frames: frames, previous: 38, tick: 39)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
        }
    }

    func testFrozenTickDoesNotRepeatTheIntervalAndSpeedSkipKeepsIt() {
        for frames in [59, 48] {
            XCTAssertFalse(sample(frames: frames, previous: 38, tick: 38)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
            XCTAssertTrue(sample(frames: frames, previous: 37, tick: 41)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
            XCTAssertFalse(sample(frames: frames, previous: 41, tick: 42)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
        }
    }

    func testRestartBeforeMarkerAllowsANewPlaybackButRewindDoesNotCross() {
        for frames in [59, 48] {
            XCTAssertFalse(sample(frames: frames, previous: 50, tick: 0)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
            XCTAssertFalse(sample(frames: frames, previous: -1, tick: 0)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
            XCTAssertTrue(sample(frames: frames, previous: 37, tick: 38)
                .crosses(sourceFrame: 19, totalSourceFrames: frames))
        }
    }
}
