import XCTest
@testable import ShiftCore

final class DuelSerpentBodyAudioClockTests: XCTestCase {
    private let markers: [DuelSerpentBodyAudioClock.Marker] = [
        .init(id: "birth", clip: "source", tick: 0, duration: 60),
        .init(id: "swing", clip: "source", tick: 20, duration: 60),
        .init(id: "voice", clip: "source", tick: 20, duration: 60),
        .init(id: "stone", clip: "source", tick: 22, duration: 60, requiresPalaceStone: true)
    ]
    private func sample(_ frame: Int, _ previous: Int, _ tick: Int,
                        sequence: Int = 0, owner: Int = 0, duration: Int = 60,
                        clip: String = "source") -> DuelSourceMotionSample {
        .init(frame: frame, sequence: sequence, owner: owner, clip: clip,
              previousTick: previous, tick: tick, duration: duration)
    }

    func testSourceIntervalsPreserveZeroAndSimultaneousMarkerOrderForBothOwners() {
        var clock = DuelSerpentBodyAudioClock()
        let first = clock.consume(markers: markers, samples: [sample(1, -1, 0)],
            frame: 1, paused: false, owners: [0, 1], stageSHA256: nil)
        XCTAssertEqual(first, [.init(owner: 0, markerID: "birth")])
        let samples = [sample(2, 19, 21), sample(2, 19, 21, sequence: 1, owner: 1)]
        let result = clock.consume(markers: markers, samples: samples,
            frame: 2, paused: false, owners: [0, 1], stageSHA256: nil)
        XCTAssertEqual(result, [.init(owner: 0, markerID: "swing"), .init(owner: 0, markerID: "voice"),
                                .init(owner: 1, markerID: "swing"), .init(owner: 1, markerID: "voice")])
        XCTAssertTrue(clock.consume(markers: markers, samples: samples, frame: 2, paused: false,
                                    owners: [0, 1], stageSHA256: nil).isEmpty)
    }

    func testFloorAuthenticationCannotReplayAnAlreadyConsumedInterval() {
        var clock = DuelSerpentBodyAudioClock()
        let samples = [sample(1, 21, 22)]
        XCTAssertTrue(clock.consume(markers: markers, samples: samples, frame: 1,
                                    paused: false, owners: [0], stageSHA256: nil).isEmpty)
        XCTAssertTrue(clock.consume(markers: markers, samples: samples, frame: 1,
            paused: false, owners: [0], stageSHA256: DuelSerpentBodyAudioClock.palaceStageSHA256).isEmpty)
        XCTAssertEqual(clock.consume(markers: markers, samples: [sample(2, 21, 22)], frame: 2,
            paused: false, owners: [0], stageSHA256: DuelSerpentBodyAudioClock.palaceStageSHA256),
            [.init(owner: 0, markerID: "stone")])
    }

    func testPauseStaleFramesResetAndWrongMotionDuration() {
        var clock = DuelSerpentBodyAudioClock()
        XCTAssertTrue(clock.consume(markers: markers, samples: [sample(9, 19, 20)], frame: 9,
                                    paused: true, owners: [0], stageSHA256: nil).isEmpty)
        XCTAssertEqual(clock.consume(markers: markers, samples: [sample(9, 19, 20)], frame: 9,
            paused: false, owners: [0], stageSHA256: nil).count, 2)
        XCTAssertTrue(clock.consume(markers: markers, samples: [sample(8, 19, 20)], frame: 8,
                                    paused: false, owners: [0], stageSHA256: nil).isEmpty)
        clock.reset()
        XCTAssertEqual(clock.consume(markers: markers, samples: [sample(0, -1, 0)], frame: 0,
            paused: false, owners: [0], stageSHA256: nil), [.init(owner: 0, markerID: "birth")])
        let invalid = [sample(1, 19, 20, duration: 59),
                       sample(1, 19, 20, sequence: 1, clip: "other"), sample(1, 19, 20, sequence: 2, owner: 2)]
        XCTAssertTrue(clock.consume(markers: markers, samples: invalid, frame: 1,
                                    paused: false, owners: [0, 2], stageSHA256: nil).isEmpty)
    }

    func testARealFinishingIntervalDoesNotRequireAnActiveRoundAndLoopRestartIsExplicit() {
        var clock = DuelSerpentBodyAudioClock()
        // The consumer receives the authoritative last pose even after the
        // fight has changed phase. It must not invent any subsequent interval.
        XCTAssertEqual(clock.consume(markers: markers, samples: [sample(100, 19, 20)], frame: 100,
            paused: false, owners: [0], stageSHA256: nil).count, 2)
        XCTAssertTrue(clock.consume(markers: markers, samples: [], frame: 101,
                                    paused: false, owners: [0], stageSHA256: nil).isEmpty)
        XCTAssertEqual(clock.consume(markers: markers, samples: [sample(102, -1, 0)], frame: 102,
            paused: false, owners: [0], stageSHA256: nil), [.init(owner: 0, markerID: "birth")])
    }
}
