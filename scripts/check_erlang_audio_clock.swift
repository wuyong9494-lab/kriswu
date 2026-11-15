import Foundation

/// Compiles with the production clock and source sample files only. No game,
/// native renderer, audio decoder, original media, or network is started.
@main
struct ErlangAudioClockChecks {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
    static func sample(_ frame: Int = 10, _ sequence: Int = 0, owner: Int = 0,
                       from: Int, to: Int, duration: Int = 20, clip: String = "actual_clip") -> DuelSourceMotionSample {
        .init(frame: frame, sequence: sequence, owner: owner, clip: clip,
              previousTick: from, tick: to, duration: duration)
    }
    static func main() {
        let marker = DuelErlangAudioClock.Marker(category: "body", clip: "actual_clip",
            modelRole: nil, sourceTick: 2, duration: 20)
        var clock = DuelErlangAudioClock()
        let body = sample(from: 1, to: 2)
        func bodyOutput(_ clock: inout DuelErlangAudioClock, _ samples: [DuelSourceMotionSample],
                        frame: Int = 10, fighting: Bool = true, paused: Bool = false,
                        owners: Set<Int> = [0]) -> [String] {
            clock.consume(markers: [marker], samples: samples, models: [], frame: frame,
                fighting: fighting, paused: paused, owners: owners)
        }
        require(bodyOutput(&clock,[body],paused:true).isEmpty,"paused step played")
        require(bodyOutput(&clock,[body]) == ["body"],"source crossing missing")
        require(bodyOutput(&clock,[body]).isEmpty,"same source sequence replayed")
        require(bodyOutput(&clock,[body],frame:11).isEmpty,"stale source sample replayed")
        require(bodyOutput(&clock,[body]).isEmpty,"older frame replayed")
        print("PASS pause, duplicate sequence, stale sample and backward frame fences")

        clock.reset()
        require(bodyOutput(&clock,[sample(owner:1,from:1,to:2)]).isEmpty,"other owner played")
        require(bodyOutput(&clock,[sample(10,1,from:1,to:2,clip:"wrong_clip")]).isEmpty,"wrong role played")
        require(bodyOutput(&clock,[sample(10,2,from:1,to:2,duration:21)]).isEmpty,"wrong duration played")
        require(bodyOutput(&clock,[sample(10,3,from:1,to:2)]) == ["body"],"valid owner clock lost")
        print("PASS owner, clip and complete playback duration identity")

        clock.reset()
        let skipped = [sample(from:0,to:5),sample(10,1,from:5,to:8)]
        require(bodyOutput(&clock,skipped) == ["body"],"catch-up intervals doubled marker")
        let fast = DuelErlangAudioClock.Marker(category:"mid0",clip:"earthshake",modelRole:nil,
            sourceTick:12,duration:110)
        require(clock.consume(markers:[fast],samples:[sample(11,from:11,to:12,duration:110,clip:"earthshake")],
            models:[],frame:11,fighting:true,paused:false,owners:[0]) == ["mid0"],"MidFrames zero clock rescaled")
        print("PASS skipped display frames and exact MidFrames zero source clock")

        clock.reset()
        let dog = DuelErlangAudioClock.Marker(category:"dog",clip:"d15_dog_attack",
            modelRole:"erlangSummon_hound",sourceTick:2,duration:118)
        func dogOutput(_ age: Int, frame: Int, owner: Int = 0, id: UInt64 = 1, fighting: Bool = true) -> [String] {
            clock.consume(markers:[dog],samples:[],models:[.init(owner:owner,id:id,role:"erlangSummon_hound",age:age)],
                frame:frame,fighting:fighting,paused:false,owners:[0])
        }
        require(dogOutput(0,frame:10).isEmpty,"sound Frame1 incorrectly became age0")
        require(dogOutput(1,frame:11).isEmpty,"dog marker was early")
        require(dogOutput(2,frame:12) == ["dog"],"dog source sound tick2 missing")
        require(dogOutput(2,frame:12).isEmpty && dogOutput(3,frame:13).isEmpty,"dog clock replayed")
        require(dogOutput(2,frame:14,owner:1,id:2).isEmpty,"other model owner played")
        print("PASS independent model birth clock and sound Frame origin")

        clock.reset()
        require(bodyOutput(&clock,[body],fighting:false) == ["body"],"finishing step source sample lost")
        require(bodyOutput(&clock,[body],fighting:false).isEmpty,"finishing sample repeated")
        require(dogOutput(2,frame:11,fighting:false).isEmpty,"KO model started new sound")
        clock.reset()
        require(dogOutput(0,frame:0).isEmpty && dogOutput(2,frame:2) == ["dog"],"next-round clock inherited old state")
        print("PASS KO finishing sample, no post-KO model cue, round reset")
        print("5 production-clock checks passed")
    }
}
