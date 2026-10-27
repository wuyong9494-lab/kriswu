"""勇者乱斗的音效和背景音乐：全部用程序合成（原创，不用别人的素材）。

重新生成：python3 scripts/arena_sounds.py App/ArenaSounds（要装 numpy）
"""
import numpy as np, wave, os, sys

SR = 22050
rng = np.random.default_rng(7)

def t(d): return np.arange(int(SR * d)) / SR

def adsr(n, a=0.005, d=0.05, s=0.6, r=0.1, hold=None):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    hold = n - a - d - r if hold is None else int(hold * SR)
    hold = max(hold, 0)
    e = np.concatenate([np.linspace(0, 1, max(a, 1), endpoint=False), np.linspace(1, s, max(d, 1), endpoint=False),
                        np.full(hold, s), np.linspace(s, 0, max(r, 1))])
    if len(e) < n: e = np.concatenate([e, np.zeros(n - len(e))])
    return e[:n]

def expdecay(n, tau): return np.exp(-np.arange(n) / (tau * SR))

def osc(freq, n, kind='sine', phase=0.0):
    f = np.broadcast_to(np.asarray(freq, float), (n,))
    ph = phase + 2 * np.pi * np.cumsum(f) / SR
    if kind == 'sine': return np.sin(ph)
    if kind == 'square': return np.sign(np.sin(ph))
    if kind == 'pulse': return np.where((ph / (2 * np.pi)) % 1 < 0.25, 1.0, -1.0)
    if kind == 'saw': return 2 * ((ph / (2 * np.pi)) % 1) - 1
    if kind == 'tri': return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1) - 1) - 1
    raise ValueError(kind)

def noise(n): return rng.uniform(-1, 1, n)

def lowpass(x, cutoff):
    """一阶低通，cutoff 可以随时间变"""
    c = np.broadcast_to(np.asarray(cutoff, float), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc); y[i] = acc
    return y

def highpass(x, cutoff): return x - lowpass(x, cutoff)

def bandpass(x, low, high): return lowpass(highpass(x, low), high)

def note(name):
    names = {'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave + 1) - 69) / 12)

def mix(*parts):
    n = max(len(p) for p in parts); out = np.zeros(n)
    for p in parts: out[:len(p)] += p
    return out

def place(buf, sound, at):
    i = int(at * SR); j = min(len(buf), i + len(sound))
    buf[i:j] += sound[:j - i]

def normalize(x, peak=0.7):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x

def fade_edges(x, ms=4):
    n = int(SR * ms / 1000)
    if len(x) > 2 * n:
        x = x.copy(); x[:n] *= np.linspace(0, 1, n); x[-n:] *= np.linspace(1, 0, n)
    return x

def save(path, x, peak=0.7, fade=True):
    x = normalize(x, peak)
    if fade: x = fade_edges(x)
    data = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)

# ---------- 音效 ----------

def shot():
    n = int(SR * 0.16)
    f = np.geomspace(1500, 420, n)
    body = osc(f, n, 'pulse') * expdecay(n, 0.05)
    air = bandpass(noise(n), 1500, 6000) * expdecay(n, 0.02) * 0.5
    return lowpass(body * 0.6 + air, 7000)

def slash():
    n = int(SR * 0.28)
    cut = np.geomspace(6000, 900, n)
    whoosh = lowpass(highpass(noise(n), 400), cut) * adsr(n, 0.01, 0.08, 0.5, 0.15)
    ring = osc(1180, n) * expdecay(n, 0.04) * 0.25 + osc(1770, n) * expdecay(n, 0.03) * 0.12
    return whoosh * 1.2 + ring

def magic():
    n = int(SR * 0.4)
    tt = t(0.4)
    f = np.geomspace(500, 1250, n) * (1 + 0.03 * np.sin(2 * np.pi * 18 * tt))
    tone = (osc(f, n) + 0.4 * osc(f * 1.5, n, 'tri')) * adsr(n, 0.02, 0.1, 0.6, 0.2)
    sparkle = bandpass(noise(n), 3000, 9000) * adsr(n, 0.05, 0.1, 0.3, 0.2) * 0.35
    return tone * 0.6 + sparkle

def boom():
    n = int(SR * 0.8)
    cut = np.geomspace(5000, 120, n)
    rumble = lowpass(noise(n), cut) * expdecay(n, 0.22) * 1.6
    thump = osc(np.geomspace(90, 38, n), n) * expdecay(n, 0.18) * 0.9
    crack = highpass(noise(n), 2000) * expdecay(n, 0.015) * 0.5
    return rumble + thump + crack

def hit():
    n = int(SR * 0.13)
    knock = osc(np.geomspace(260, 120, n), n) * expdecay(n, 0.035)
    smack = lowpass(noise(n), 2500) * expdecay(n, 0.018) * 0.8
    return knock + smack

def knockout():
    n = int(SR * 0.7)
    fall = osc(np.geomspace(700, 130, n), n, 'square') * adsr(n, 0.005, 0.1, 0.5, 0.3) * 0.35
    crunch = lowpass(noise(n), np.geomspace(4000, 300, n)) * expdecay(n, 0.12)
    return lowpass(fall, 3000) + crunch

def power_up():
    n = int(SR * 0.6)
    f = np.geomspace(280, 1300, n)
    sweep = (osc(f, n, 'saw') + osc(f * 1.007, n, 'saw')) * adsr(n, 0.02, 0.2, 0.7, 0.25) * 0.3
    sparkle = bandpass(noise(n), 4000, 10000) * adsr(n, 0.2, 0.1, 0.5, 0.25) * 0.3
    return lowpass(sweep, np.geomspace(1200, 6000, n)) + sparkle

def chime(notes, step=0.06, length=0.35, kind='sine', bright=0.3):
    parts = []
    for k, name in enumerate(notes):
        n = int(SR * length)
        f = note(name)
        x = (osc(f, n, kind) + bright * osc(f * 2, n)) * expdecay(n, length / 3)
        parts.append((k * step, x))
    total = int(SR * (step * len(notes) + length))
    out = np.zeros(total)
    for at, x in parts: place(out, x, at)
    return out

def blink():
    n = int(SR * 0.32)
    cut = np.geomspace(500, 7000, n)
    up = lowpass(noise(n), cut) * adsr(n, 0.02, 0.1, 0.6, 0.15)
    tone = osc(np.geomspace(300, 1600, n), n, 'tri') * adsr(n, 0.01, 0.1, 0.4, 0.15) * 0.4
    return up + tone

def jingle(melody, tempo=0.14, last=0.8, kind='square'):
    out = np.zeros(int(SR * (tempo * len(melody) + last + 0.2)))
    for k, name in enumerate(melody):
        dur = last if k == len(melody) - 1 else tempo * 1.2
        n = int(SR * dur)
        f = note(name)
        lead = osc(f, n, kind) * adsr(n, 0.005, 0.06, 0.55, min(0.2, dur / 2)) * 0.35
        under = osc(f / 2, n, 'tri') * adsr(n, 0.005, 0.06, 0.6, min(0.2, dur / 2)) * 0.4
        place(out, lowpass(lead, 4000) + under, k * tempo)
    return out

# ---------- 背景音乐：A 小调，128 拍，16 小节，循环 ----------

def music():
    bpm = 128; beat = 60 / bpm; bar = beat * 4; bars = 16
    total = int(SR * bar * bars)
    # 多留一秒，最后把伸出去的尾巴叠回开头，循环时接得上
    out = np.zeros(total + SR)
    chords = [('A2', ['A3', 'C4', 'E4']), ('F2', ['F3', 'A3', 'C4']), ('C3', ['C4', 'E4', 'G4']), ('G2', ['G3', 'B3', 'D4'])]
    def kick():
        n = int(SR * 0.3)
        return osc(np.geomspace(120, 42, n), n) * expdecay(n, 0.09) + lowpass(noise(n), 800) * expdecay(n, 0.01) * 0.3
    def snare():
        n = int(SR * 0.22)
        return highpass(noise(n), 900) * expdecay(n, 0.06) * 0.7 + osc(np.geomspace(260, 180, n), n) * expdecay(n, 0.04) * 0.4
    def hat(open_=False):
        n = int(SR * (0.18 if open_ else 0.05))
        return highpass(noise(n), 6000) * expdecay(n, 0.05 if open_ else 0.012) * 0.35
    k, s, h, ho = kick(), snare(), hat(), hat(True)
    for b in range(bars):
        t0 = b * bar
        intro = b < 2
        for q in range(4):
            if not intro or q % 2 == 0: place(out, k * 0.9, t0 + q * beat)
            if not intro and q in (1, 3): place(out, s * 0.8, t0 + q * beat)
            for e in range(2):
                place(out, (ho if (q == 3 and e == 1 and b % 4 == 3) else h) * (0.9 if e == 0 else 0.6), t0 + q * beat + e * beat / 2)
        if b % 4 == 3 and not intro:
            place(out, k * 0.6, t0 + 3.5 * beat)
    # 贝斯：每小节根音 8 分音符
    for b in range(bars):
        root, triad = chords[b % 4]
        for e in range(8):
            n = int(SR * beat / 2 * 0.95)
            f = note(root) * (2 if e in (3, 6) else 1)
            x = osc(f, n, 'saw') * adsr(n, 0.004, 0.05, 0.6, 0.04)
            place(out, lowpass(x, 900) * 0.32, b * bar + e * beat / 2)
    # 和弦垫底：三角波，轻
    for b in range(bars):
        root, triad = chords[b % 4]
        n = int(SR * bar)
        x = sum(osc(note(m), n, 'tri') for m in triad) * adsr(n, 0.08, 0.3, 0.7, 0.3) * 0.06
        place(out, x, b * bar)
    # 前 8 小节：琶音拨弦；后 8 小节：主旋律
    arp_order = [0, 1, 2, 1, 0, 2, 1, 2]
    for b in range(8):
        root, triad = chords[b % 4]
        for e in range(8):
            n = int(SR * beat / 2)
            f = note(triad[arp_order[e]]) * 2
            x = osc(f, n, 'pulse') * expdecay(n, 0.08)
            place(out, lowpass(x, 3500) * (0.10 if b < 2 else 0.14), b * bar + e * beat / 2)
    melody = [
        # (小节内第几拍, 音, 拍数)
        [(0, 'E5', 1), (1, 'A5', 1), (2, 'G5', 0.5), (2.5, 'E5', 0.5), (3, 'C5', 1)],
        [(0, 'F5', 1.5), (1.5, 'E5', 0.5), (2, 'C5', 1), (3, 'A4', 1)],
        [(0, 'G4', 0.5), (0.5, 'C5', 0.5), (1, 'E5', 1), (2, 'G5', 1), (3, 'E5', 1)],
        [(0, 'D5', 1.5), (1.5, 'B4', 0.5), (2, 'D5', 1), (3, 'G5', 1)],
        [(0, 'A5', 1), (1, 'C6', 1), (2, 'B5', 0.5), (2.5, 'A5', 0.5), (3, 'E5', 1)],
        [(0, 'F5', 1), (1, 'A5', 1), (2, 'G5', 1), (3, 'F5', 1)],
        [(0, 'E5', 1), (1, 'G5', 0.5), (1.5, 'C6', 0.5), (2, 'B5', 1), (3, 'G5', 1)],
        [(0, 'D5', 1), (1, 'B4', 1), (2, 'D5', 0.5), (2.5, 'E5', 0.5), (3, 'E5', 1)],
    ]
    for b, notes in enumerate(melody):
        for at, name, length in notes:
            n = int(SR * beat * length * 0.95)
            f = note(name)
            vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * np.arange(n) / SR)
            x = (osc(f * vib, n, 'square') * 0.5 + osc(f * vib, n, 'tri') * 0.5) * adsr(n, 0.01, 0.08, 0.7, 0.06)
            place(out, lowpass(x, 3000) * 0.16, (8 + b) * bar + at * beat)
    tail = out[total:]
    out = out[:total].copy()
    out[:len(tail)] += tail
    return out

if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    sounds = {
        'arena_shot': shot(), 'arena_slash': slash(), 'arena_magic': magic(), 'arena_boom': boom(),
        'arena_hit': hit(), 'arena_ko': knockout(), 'arena_super': power_up(),
        'arena_pickup': chime(['E6', 'B6'], step=0.07, length=0.3),
        'arena_heal': chime(['C5', 'E5', 'G5', 'C6'], step=0.06, length=0.4, bright=0.15),
        'arena_respawn': chime(['C5', 'G5', 'C6', 'E6'], step=0.05, length=0.45, kind='tri'),
        'arena_blink': blink(),
        'arena_win': jingle(['C5', 'E5', 'G5', 'C6', 'G5', 'C6'], tempo=0.13, last=0.9),
        'arena_lose': jingle(['G4', 'F4', 'D#4', 'C4'], tempo=0.22, last=0.9, kind='tri'),
    }
    for name, x in sounds.items():
        save(os.path.join(out, name + '.wav'), x, peak=0.8 if name in ('arena_win', 'arena_lose') else 0.7)
        print(name, round(len(x) / SR, 2), 's')
    m = music()
    save(os.path.join(out, 'arena_music.wav'), m, peak=0.6, fade=False)
    print('music', round(len(m) / SR, 2), 's')
