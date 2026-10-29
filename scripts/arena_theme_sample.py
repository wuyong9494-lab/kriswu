#!/usr/bin/env python3
"""Original procedural music study; not a recording or adaptation of a game soundtrack.
32 bars with A / A variation / contrasting B / A return; no copied audio or samples.
Outputs PCM WAV for audition and gapless game loops. NumPy only.
"""
import json
import math
from pathlib import Path
import wave
import subprocess
import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'App' / 'ArenaSounds'
RNG = np.random.default_rng(170017)

def tone(note, duration, voice='mallet'):
    t = np.arange(max(1, int(duration * RATE))) / RATE
    f = 440 * 2 ** ((note - 69) / 12)
    attack = np.minimum(t / 0.008, 1)
    release = np.minimum((duration - t) / 0.04, 1)
    if voice == 'pad':
        envelope = np.minimum(t / 0.09, 1) * np.minimum((duration-t)/0.16, 1)
        x = np.sin(2*np.pi*f*t) + 0.15*np.sin(2*np.pi*f*2*t)
    elif voice == 'bass':
        envelope = attack * release * np.exp(-t*3)
        x = np.sin(2*np.pi*f*t) + 0.22*np.sin(2*np.pi*f*2*t)
    else:
        envelope = attack * release * np.exp(-t*4)
        x = np.sin(2*np.pi*f*t) + 0.3*np.sin(2*np.pi*f*2*t)*np.exp(-t*6) + 0.08*np.sin(2*np.pi*f*3*t)
    return x * np.maximum(envelope, 0)

def drum(kind):
    length = 0.16 if kind != 'hat' else 0.055
    t = np.arange(int(length*RATE))/RATE
    if kind == 'kick':
        f = 45 + 95*np.exp(-t*42)
        x = np.sin(2*np.pi*np.cumsum(f)/RATE)*np.exp(-t*22)
    else:
        noise = RNG.uniform(-1, 1, len(t))
        x = np.diff(noise, prepend=0)*np.exp(-t*(65 if kind == 'hat' else 28))*0.25
    x[:50] *= np.linspace(0,1,50)
    x[-100:] *= np.linspace(1,0,100)
    return x

def add(out, signal, at, gain=1, wrap=True):
    index = int(at*RATE)
    if wrap:
        np.add.at(out, (index + np.arange(len(signal))) % len(out), signal*gain)
    else:
        n = min(len(signal), max(0,len(out)-index))
        out[index:index+n] += signal[:n]*gain

# Shared five-note identity, rhythm and orchestration vary by scene.
MOTIF = [74, 77, 81, 79, 76, 74, 72, 69]
CHORDS = [(50, [62,65,69]), (46, [62,65,70]), (53,[60,65,69]), (48,[60,64,67])]

def loop(bpm, battle=False):
    beat = 60/bpm
    out = np.zeros(round(32*4*beat*RATE))
    for bar in range(32):
        section = bar//8
        root,chord = CHORDS[bar%4]
        at = bar*4*beat
        add(out, sum(tone(n, beat*3.8, 'pad') for n in chord), at, 0.065)
        for k in range(4 if battle else 2):
            add(out, tone(root-12, beat*0.72, 'bass'), at+k*beat*(1 if battle else 2), 0.22)
        for k in (range(4) if battle else [0,2]):
            add(out, drum('kick'), at+k*beat, 0.13 if battle else 0.08)
        if battle or section in [1,3]:
            for k in [1,3]: add(out, drum('snare'), at+k*beat, 0.12 if battle else 0.055)
        for k in range(8 if battle else 4):
            add(out, drum('hat'), at+(k+0.5)*beat*(0.5 if battle else 1), 0.055 if battle else 0.025)
        # A phrase leaves breathing room; B changes contour/register and harmonic response.
        if section == 2:
            notes = [chord[2]+12,chord[1]+12,chord[0]+12, chord[1]+12]
            times = [0,1.5,2.5,3.25]
        else:
            offset = (bar%2)*4
            notes = MOTIF[offset:offset+4]
            if section == 1 and bar%4 == 3: notes = [76,79,77,74]
            if section == 3 and bar%4 == 2: notes = [81,84,81,79]
            times = [0,0.75,1.5,2.75] if battle else [0,1,2,3]
        if not battle and bar%4 == 3: notes,times = notes[:2],times[:2]
        for note,t in zip(notes,times): add(out,tone(note, beat*0.7),at+t*beat,0.15 if battle else 0.13)
    return out

def jingle(win):
    out=np.zeros(RATE*5)
    notes=[74,77,81,86] if win else [81,77,76,74]
    for i,n in enumerate(notes): add(out,tone(n,1.5 if i==3 else 0.5),i*0.3,0.3,False)
    chord=[62,65,69] if win else [62,65,68]
    add(out,sum(tone(n,2.7,'pad') for n in chord),0.3,0.10,False)
    return out

def save(name,x,looping):
    rms=np.sqrt(np.mean(x*x))
    gain=min(0.72/max(np.max(np.abs(x)),1e-9), 0.10/max(rms,1e-9))
    x=x*gain
    if looping:
        # Fade only 3 ms at the join; arrangement wraps sustained note tails.
        n=int(RATE*.003);x[:n]*=np.linspace(0,1,n);x[-n:]*=np.linspace(1,0,n)
    else:
        n=int(RATE*.03);x[-n:]*=np.linspace(1,0,n)
    pcm=(np.clip(x,-1,1)*32767).astype('<i2')
    path=OUT/(name+'.wav')
    with wave.open(str(path),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(pcm.tobytes())
    return {'file':path.name,'seconds':len(x)/RATE,'peak_dbfs':20*math.log10(max(np.max(abs(x)),1e-9)), 'rms_dbfs':20*math.log10(max(np.sqrt(np.mean(x*x)),1e-9)), 'loop_join_delta':float(abs(x[0]-x[-1])), 'listening_review':'not performed'}

if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    reports=[save('arena_theme_lobby',loop(112),True),save('arena_theme_battle',loop(128,True),True),save('arena_theme_win',jingle(True),False),save('arena_theme_lose',jingle(False),False)]
    for report in reports:
        wav = OUT / report['file']
        subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', str(wav), '-c:a', 'aac', '-b:a', '64k', str(wav.with_suffix('.m4a'))], check=True)
        report['delivery'] = wav.with_suffix('.m4a').name
        report['encoded_loop_listening'] = 'not performed'
        wav.unlink()
    print(json.dumps(reports,indent=2))
