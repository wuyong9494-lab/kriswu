import Foundation

/// Narrow checks for the actual t13/t21 event consumer, without media playback.
@main
struct ErlangMeditationAudioClockChecks {
    typealias Clock = DuelErlangMeditationAudioClock
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
    static func event(_ frame: Int, _ sequence: Int, _ owner: Int, _ kind: Clock.Kind) -> Clock.Event {
        .init(frame: frame, sequence: sequence, liveTick: frame, owner: owner, kind: kind)
    }
    static func command(_ owner: Int, _ kind: Clock.Kind,
                        _ reason: Clock.Reason = .sourceTrigger) -> Clock.Command {
        .init(owner: owner, kind: kind, reason: reason)
    }

    static func main() {
        var clock = Clock()
        let start = event(10, 0, 0, .start)
        require(clock.consume([start], frame: 10, fighting: true, paused: false, owners: [0]) ==
                [command(0, .start)], "actual source start did not play")
        require(clock.consume([start], frame: 10, fighting: true, paused: false, owners: [0]).isEmpty,
                "repeated display consumption replayed t13")
        require(clock.consume([], frame: 11, fighting: true, paused: false, owners: [0]).isEmpty,
                "an animation transition without t21 invented a stop")
        let stop = event(12, 0, 0, .stop)
        require(clock.consume([stop], frame: 12, fighting: true, paused: false, owners: [0]) ==
                [command(0, .stop)], "actual conditional stop did not stop")
        require(clock.consume([stop], frame: 12, fighting: true, paused: false, owners: [0]).isEmpty,
                "source stop replayed")
        print("PASS real source events once; Start/Loop/End poses alone cannot stop audio")

        clock.reset()
        require(clock.consume([event(1, 0, 0, .start), event(1, 1, 1, .start)],
            frame: 1, fighting: true, paused: false, owners: [0, 1]) ==
                [command(0, .start), command(1, .start)], "owner starts collided")
        require(clock.consume([event(2, 0, 0, .stop), event(2, 1, 0, .start), event(2, 2, 0, .stop)],
            frame: 2, fighting: true, paused: false, owners: [0, 1]) ==
                [command(0, .stop), command(0, .start), command(0, .stop)],
                "same-step actual source order or replacement changed")
        require(clock.consume([event(3, 0, 1, .stop)], frame: 3,
            fighting: true, paused: false, owners: [0, 1]) == [command(1, .stop)],
                "another owner's stop affected the retained player")
        print("PASS source ordering and independent per-owner player commands")

        clock.reset()
        require(clock.consume([event(5, 0, 0, .start)], frame: 5,
            fighting: true, paused: true, owners: [0]).isEmpty, "pause consumed a new source event")
        require(clock.consume([event(5, 0, 0, .start)], frame: 5,
            fighting: true, paused: false, owners: [0]) == [command(0, .start)], "resume lost the event")
        require(clock.consume([event(4, 0, 0, .stop)], frame: 4,
            fighting: true, paused: false, owners: [0]).isEmpty, "backward frame mutated player state")
        require(clock.consume([event(6, 0, 1, .stop), event(5, 1, 0, .stop)], frame: 6,
            fighting: true, paused: false, owners: [0]).isEmpty, "foreign owner or stale event was accepted")
        print("PASS pause, backward-frame, foreign-owner and stale-event fences")

        require(clock.consume([], frame: 7, fighting: false, paused: false, owners: [0]) ==
                [command(0, .stop, .applicationLifecycle)], "KO cleanup was not distinguished from t21")
        require(clock.consume([], frame: 7, fighting: false, paused: false, owners: [0]).isEmpty,
                "KO cleanup repeated")
        clock.reset()
        require(clock.consume([event(0, 0, 0, .start)], frame: 0,
            fighting: true, paused: false, owners: [0]) == [command(0, .start)], "new round retained old fence")
        require(clock.consume([], frame: 1, fighting: true, paused: false, owners: []) ==
                [command(0, .stop, .applicationLifecycle)], "removed owner retained its application player")
        print("PASS round/owner lifecycle cleanup remains separate from original StopSound")
        print("4 new meditation source-event checks passed; no media or native execution")
    }
}
