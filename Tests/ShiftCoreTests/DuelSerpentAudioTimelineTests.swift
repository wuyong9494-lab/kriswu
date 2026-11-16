import XCTest
@testable import ShiftCore

final class DuelSerpentAudioTimelineTests: XCTestCase {
    private let rain = DuelSerpentRainRuntime.rainSound
    private func model(_ effect: DuelSerpentRainRuntime.Effect, owner: Int = 0) -> DuelSerpentMatchEvent {
        .init(owner: owner, liveTick: 57, effect: .model(effect))
    }

    func testRepeatedDisplayCallbacksCannotReplayAcceptedSounds() {
        var timeline = DuelSerpentAudioTimeline()
        let event = model(.soundStarted(rain))
        let first = timeline.consume([event], frame: 61, fighting: true, paused: false, owners: [0])
        XCTAssertEqual(first.map(\.operation), [.play(loop: true)])
        XCTAssertTrue(timeline.consume([event], frame: 61, fighting: true, paused: false, owners: [0]).isEmpty)
        XCTAssertTrue(timeline.consume([event], frame: 60, fighting: true, paused: false, owners: [0]).isEmpty)
        XCTAssertEqual(timeline.finish().map(\.operation), [.stop])
        XCTAssertTrue(timeline.finish().isEmpty)
    }

    func testSourceStopAndOutroAreOrderedAndRemainSingleDuringRoundCompletion() {
        var timeline = DuelSerpentAudioTimeline()
        _ = timeline.consume([model(.soundStarted(rain))], frame: 1, fighting: true, paused: false, owners: [0])
        let end = [model(.soundStopped(rain)), model(.soundStarted(DuelSerpentRainRuntime.rainOutSound))]
        let result = timeline.consume(end, frame: 2, fighting: false, paused: false, owners: [0])
        XCTAssertEqual(result.map(\.operation), [.stop, .play(loop: false)])
        XCTAssertEqual(result.map(\.reason), [.sourceEvent, .sourceEvent])
        XCTAssertTrue(timeline.consume(end, frame: 2, fighting: false, paused: false, owners: [0]).isEmpty)
        XCTAssertTrue(timeline.finish().isEmpty)
    }

    func testPauseKeepsEventFenceAndRemovedOwnersStopOnlyTheirLoop() {
        var timeline = DuelSerpentAudioTimeline()
        let events = [model(.soundStarted(rain)), model(.soundStarted(rain), owner: 1)]
        XCTAssertTrue(timeline.consume(events, frame: 1, fighting: true, paused: true, owners: [0, 1]).isEmpty)
        XCTAssertEqual(timeline.consume(events, frame: 1, fighting: true, paused: false, owners: [0, 1]).count, 2)
        XCTAssertTrue(timeline.consume(events, frame: 1, fighting: true, paused: true, owners: [0, 1]).isEmpty)
        XCTAssertTrue(timeline.consume(events, frame: 1, fighting: true, paused: false, owners: [0, 1]).isEmpty)
        let stop = timeline.consume([], frame: 2, fighting: true, paused: false, owners: [1])
        XCTAssertEqual(stop.map(\.owner), [0]); XCTAssertEqual(stop.map(\.reason), [.applicationLifecycle])
        XCTAssertEqual(timeline.finish().map(\.owner), [1])
    }

    func testRoundEndCleansLoopWithoutInventingSourceOutroAndRejectsNewLoop() {
        var timeline = DuelSerpentAudioTimeline()
        _ = timeline.consume([model(.soundStarted(rain))], frame: 1, fighting: true, paused: false, owners: [0])
        let result = timeline.consume([], frame: 2, fighting: false, paused: false, owners: [0])
        XCTAssertEqual(result.map(\.operation), [.stop]); XCTAssertEqual(result.map(\.reason), [.applicationLifecycle])
        XCTAssertTrue(timeline.consume([model(.soundStarted(rain))], frame: 3, fighting: false, paused: false, owners: [0]).isEmpty)
    }

    func testUnknownIdentifiersAndMismatchedActionClockCannotPlay() {
        var timeline = DuelSerpentAudioTimeline()
        let sound = "set_d13/poison_energy_cast@Battle@Movement"
        let good = DuelSerpentMatchEvent(owner: 0, liveTick: 20,
            effect: .action(.init(playbackID: 1, liveTick: 20, motionTick: 20, effect: .sound(sound))))
        let stale = DuelSerpentMatchEvent(owner: 0, liveTick: 20,
            effect: .action(.init(playbackID: 1, liveTick: 19, motionTick: 20, effect: .sound(sound))))
        let result = timeline.consume([model(.soundStarted("made_up")), stale, good],
                                      frame: 1, fighting: true, paused: false, owners: [0])
        XCTAssertEqual(result.map(\.identifier), [sound])
        XCTAssertEqual(result.map(\.operation), [.play(loop: false)])
    }
}
