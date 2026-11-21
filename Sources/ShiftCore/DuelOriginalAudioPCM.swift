import Foundation

/// 100% original procedural martial-arts combat audio synthesizer (22.05 kHz mono Float32 PCM).
/// Generates crisp blade whooshes, metallic parry clangs, flesh/armor impacts, head-hit cracks,
/// critical thunder booms, judo throw slams, and hero Shadow/Light/Flame/Phase activation cues
/// with zero third-party or copyrighted audio files.
public enum DuelOriginalAudioPCM {
    public static let sampleRate: Int = 22_050

    public enum Cue: String, CaseIterable, Sendable {
        case bladeWhooshLight
        case bladeWhooshHeavy
        case kickWhoosh
        case hitLight
        case hitHeavy
        case headHit
        case criticalHit
        case blockClang
        case guardBreak
        case throwSlam
        case shadowActivate
        case lightForm
        case flameForm
        case midnightPhase
    }

    public static func samples(for cue: Cue) -> [Float] {
        switch cue {
        case .bladeWhooshLight:
            return synthesizeWhoosh(duration: 0.13, startFreq: 1900, endFreq: 680, gain: 0.34, seed: 101)
        case .bladeWhooshHeavy:
            return synthesizeWhoosh(duration: 0.23, startFreq: 1150, endFreq: 240, gain: 0.48, seed: 202)
        case .kickWhoosh:
            return synthesizeWhoosh(duration: 0.10, startFreq: 2500, endFreq: 860, gain: 0.30, seed: 303)
        case .hitLight:
            return synthesizeImpact(duration: 0.13, bodyStart: 165, bodyEnd: 46, bodyGain: 0.62,
                                    snapGain: 0.34, ringFreqs: [], ringGain: 0, seed: 404)
        case .hitHeavy:
            return synthesizeImpact(duration: 0.24, bodyStart: 128, bodyEnd: 32, bodyGain: 0.80,
                                    snapGain: 0.45, ringFreqs: [820, 1480], ringGain: 0.12, seed: 505)
        case .headHit:
            return synthesizeImpact(duration: 0.19, bodyStart: 190, bodyEnd: 54, bodyGain: 0.68,
                                    snapGain: 0.56, ringFreqs: [1180, 2140], ringGain: 0.22, seed: 606)
        case .criticalHit:
            return synthesizeCritical()
        case .blockClang:
            return synthesizeBlockClang()
        case .guardBreak:
            return synthesizeGuardBreak()
        case .throwSlam:
            return synthesizeThrowSlam()
        case .shadowActivate:
            return synthesizeShadowActivate()
        case .lightForm:
            return synthesizeLightForm()
        case .flameForm:
            return synthesizeFlameForm()
        case .midnightPhase:
            return synthesizeMidnightPhase()
        }
    }

    private struct PRNG {
        var state: UInt64
        mutating func nextFloat() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let v = Int32(bitPattern: UInt32(truncatingIfNeeded: state >> 32))
            return Float(v) / Float(Int32.max)
        }
    }

    private static func synthesizeWhoosh(duration: Double, startFreq: Double, endFreq: Double,
                                         gain: Float, seed: UInt64) -> [Float] {
        let n = max(1, Int(duration * Double(sampleRate)))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: seed)
        var lp: Double = 0
        var bp: Double = 0
        let sr = Double(sampleRate)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let env = sin(t * .pi) * pow(1.0 - t * 0.4, 1.4)
            let freq = startFreq + (endFreq - startFreq) * t
            let alpha = min(0.95, 2.0 * .pi * freq / sr)
            let noise = Double(rng.nextFloat())
            lp += alpha * (noise - lp)
            bp += (alpha * 0.55) * (lp - bp)
            let air = (lp - bp) * 2.2
            out[i] = Float(air * env) * gain
        }
        return clampPeak(out, limit: 0.85)
    }

    private static func synthesizeImpact(duration: Double, bodyStart: Double, bodyEnd: Double,
                                         bodyGain: Float, snapGain: Float,
                                         ringFreqs: [Double], ringGain: Float, seed: UInt64) -> [Float] {
        let n = max(1, Int(duration * Double(sampleRate)))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: seed)
        let sr = Double(sampleRate)
        var phase: Double = 0
        var lp: Double = 0
        for i in 0..<n {
            let sec = Double(i) / sr
            let t = Double(i) / Double(n)
            let freq = bodyEnd + (bodyStart - bodyEnd) * exp(-sec * 34.0)
            phase += 2.0 * .pi * freq / sr
            let bodyEnv = exp(-sec * 18.0)
            let body = sin(phase) * bodyEnv * Double(bodyGain)

            let noise = Double(rng.nextFloat())
            lp += 0.35 * (noise - lp)
            let snapEnv = exp(-sec * 65.0)
            let snap = (noise * 0.6 + lp * 0.4) * snapEnv * Double(snapGain)

            var ring: Double = 0
            if !ringFreqs.isEmpty {
                let ringEnv = exp(-sec * 24.0)
                for f in ringFreqs {
                    ring += sin(2.0 * .pi * f * sec)
                }
                ring = (ring / Double(ringFreqs.count)) * ringEnv * Double(ringGain)
            }
            let attack = min(1.0, Double(i) / 48.0)
            let fadeOut = t > 0.85 ? (1.0 - t) / 0.15 : 1.0
            out[i] = Float((body + snap + ring) * attack * fadeOut)
        }
        return clampPeak(out, limit: 0.92)
    }

    private static func synthesizeCritical() -> [Float] {
        let duration = 0.36
        let n = Int(duration * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: 7777)
        let sr = Double(sampleRate)
        var phase: Double = 0
        let modes: [(Double, Double)] = [(1640, 0.24), (2490, 0.18), (3710, 0.12)]
        for i in 0..<n {
            let sec = Double(i) / sr
            let freq = 28.0 + 110.0 * exp(-sec * 16.0)
            phase += 2.0 * .pi * freq / sr
            let sub = tanh(sin(phase) * 1.9) * exp(-sec * 7.5) * 0.78
            let crack = Double(rng.nextFloat()) * exp(-sec * 42.0) * 0.55
            var metal = 0.0
            for (f, g) in modes {
                metal += sin(2.0 * .pi * f * sec) * g * exp(-sec * 13.0)
            }
            let env = min(1.0, Double(i) / 36.0) * (sec > 0.30 ? max(0, (duration - sec) / 0.06) : 1.0)
            out[i] = Float((sub + crack + metal) * env)
        }
        return clampPeak(out, limit: 0.95)
    }

    private static func synthesizeBlockClang() -> [Float] {
        let duration = 0.24
        let n = Int(duration * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: 8888)
        let sr = Double(sampleRate)
        // Inharmonic steel blade parry modes for authentic katana/sword clang
        let modes: [(Double, Double, Double)] = [
            (1380, 0.36, 16.0),
            (2260, 0.30, 20.0),
            (3410, 0.22, 26.0),
            (4890, 0.14, 34.0)
        ]
        for i in 0..<n {
            let sec = Double(i) / sr
            var sum = Double(rng.nextFloat()) * exp(-sec * 110.0) * 0.45
            for (f, g, decay) in modes {
                sum += sin(2.0 * .pi * f * sec) * g * exp(-sec * decay)
            }
            let thud = sin(2.0 * .pi * 170.0 * sec) * exp(-sec * 45.0) * 0.22
            let env = min(1.0, Double(i) / 20.0)
            out[i] = Float((sum + thud) * env)
        }
        return clampPeak(out, limit: 0.88)
    }

    private static func synthesizeGuardBreak() -> [Float] {
        let duration = 0.30
        let n = Int(duration * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: 9999)
        let sr = Double(sampleRate)
        var phase = 0.0
        for i in 0..<n {
            let sec = Double(i) / sr
            let f = 420.0 * exp(-sec * 9.0) + 45.0
            phase += 2.0 * .pi * f / sr
            let boom = sin(phase) * exp(-sec * 10.0) * 0.65
            let shatter = (sin(2.0 * .pi * 2850.0 * sec) + sin(2.0 * .pi * 3920.0 * sec) * 0.7) * exp(-sec * 22.0) * 0.28
            let crunch = Double(rng.nextFloat()) * exp(-sec * 20.0) * 0.42
            out[i] = Float((boom + shatter + crunch) * min(1.0, Double(i) / 24.0))
        }
        return clampPeak(out, limit: 0.92)
    }

    private static func synthesizeThrowSlam() -> [Float] {
        let duration = 0.34
        let n = Int(duration * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: 5511)
        let sr = Double(sampleRate)
        var phase = 0.0
        var lp = 0.0
        for i in 0..<n {
            let sec = Double(i) / sr
            let f = 26.0 + 78.0 * exp(-sec * 14.0)
            phase += 2.0 * .pi * f / sr
            let sub = tanh(sin(phase) * 2.2) * exp(-sec * 8.0) * 0.84
            let noise = Double(rng.nextFloat())
            lp += 0.16 * (noise - lp)
            let gravel = lp * exp(-sec * 16.0) * 0.65
            out[i] = Float((sub + gravel) * min(1.0, Double(i) / 40.0))
        }
        return clampPeak(out, limit: 0.95)
    }

    private static func synthesizeShadowActivate() -> [Float] {
        let duration = 0.52
        let n = Int(duration * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: 1212)
        let sr = Double(sampleRate)
        var p1 = 0.0, p2 = 0.0, lp = 0.0
        for i in 0..<n {
            let sec = Double(i) / sr
            let t = sec / duration
            let f1 = 110.0 - 52.0 * t
            let f2 = 220.0 + 180.0 * sin(t * .pi)
            p1 += 2.0 * .pi * f1 / sr
            p2 += 2.0 * .pi * f2 / sr
            let bass = tanh(sin(p1) * 1.6) * 0.55
            let eerie = sin(p2) * 0.24 * sin(t * .pi)
            let nval = Double(rng.nextFloat())
            lp += 0.08 * (nval - lp)
            let env = sin(t * .pi) * pow(1.0 - t * 0.25, 1.2)
            out[i] = Float((bass + eerie + lp * 0.45) * env)
        }
        return clampPeak(out, limit: 0.90)
    }

    private static func synthesizeLightForm() -> [Float] {
        let duration = 0.48
        let n = Int(duration * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        let sr = Double(sampleRate)
        let chord: [(Double, Double)] = [(523.25, 0.28), (659.25, 0.24), (783.99, 0.24), (1046.5, 0.20)]
        for i in 0..<n {
            let sec = Double(i) / sr
            let t = sec / duration
            var s = 0.0
            for (f, g) in chord {
                s += sin(2.0 * .pi * f * sec) * g
            }
            let env = min(1.0, sec / 0.03) * exp(-sec * 5.2) * (t > 0.85 ? (1.0 - t) / 0.15 : 1.0)
            out[i] = Float(s * env)
        }
        return clampPeak(out, limit: 0.86)
    }

    private static func synthesizeFlameForm() -> [Float] {
        let duration = 0.44
        let n = Int(duration * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: 4242)
        let sr = Double(sampleRate)
        var lp = 0.0
        var phase = 0.0
        for i in 0..<n {
            let sec = Double(i) / sr
            let t = sec / duration
            let noise = Double(rng.nextFloat())
            let cutoff = 0.12 + 0.35 * sin(t * .pi)
            lp += cutoff * (noise - lp)
            phase += 2.0 * .pi * (95.0 - 45.0 * t) / sr
            let roar = lp * 1.45 + sin(phase) * 0.45
            let env = min(1.0, sec / 0.035) * exp(-sec * 4.5)
            out[i] = Float(roar * env)
        }
        return clampPeak(out, limit: 0.90)
    }

    private static func synthesizeMidnightPhase() -> [Float] {
        let duration = 0.26
        let n = Int(duration * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        var rng = PRNG(state: 9090)
        let sr = Double(sampleRate)
        var p = 0.0
        var lp = 0.0
        for i in 0..<n {
            let sec = Double(i) / sr
            let t = sec / duration
            let f = 920.0 - 540.0 * sin(t * .pi)
            p += 2.0 * .pi * f / sr
            let nv = Double(rng.nextFloat())
            lp += 0.22 * (nv - lp)
            let env = sin(t * .pi)
            out[i] = Float((sin(p) * 0.30 + (nv - lp) * 0.48) * env)
        }
        return clampPeak(out, limit: 0.82)
    }

    private static func clampPeak(_ samples: [Float], limit: Float) -> [Float] {
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        guard peak > limit, peak > 0 else { return samples }
        let scale = limit / peak
        return samples.map { $0 * scale }
    }
}
