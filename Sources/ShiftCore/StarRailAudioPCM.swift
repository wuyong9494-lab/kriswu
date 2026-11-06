import Foundation

/// Original synthesized cues. Generated once, kept as bounded PCM buffers; no
/// downloaded assets, per-tap file access, or audio work in gameplay rules.
public enum StarRailAudioPCM {
    public enum Cue: String, CaseIterable, Sendable { case pick, match, charge, shift, win, fail }
    public static let sampleRate = 44_100
    public static func duration(_ cue: Cue) -> Double {
        switch cue { case .pick:return 0.055; case .match:return 0.18; case .charge:return 0.15; case .shift:return 0.20; case .win:return 0.62; case .fail:return 0.22 }
    }
    public static func samples(_ cue: Cue) -> [Float] {
        let length = Int(Double(sampleRate)*duration(cue))
        var result = Array(repeating:Float(0),count:length)
        let notes: [Double]
        switch cue {
        case .pick: notes=[880]
        case .match: notes=[523.25,659.25,783.99]
        case .charge: notes=[1046.5,1318.5]
        case .shift: notes=[220,293.66]
        case .win: notes=[523.25,659.25,783.99,1046.5]
        case .fail: notes=[293.66,220]
        }
        let total = duration(cue)
        for i in 0..<length {
            let t = Double(i)/Double(sampleRate)
            var value = 0.0
            for (n, frequency) in notes.enumerated() {
                let offset = Double(n)*total*0.13
                let age = t-offset
                guard age >= 0 else { continue }
                let attack = min(1,age/0.004)
                let tail = max(0,min(1,(total-t)/0.025))
                let envelope = attack*tail*exp(-age/(total*0.36))
                let phase = 2*Double.pi*frequency*age
                value += (sin(phase)+0.17*sin(phase*2))*envelope
            }
            result[i] = Float(value*0.22/Double(notes.count))
        }
        result[0]=0;result[length-1]=0
        return result
    }
}
