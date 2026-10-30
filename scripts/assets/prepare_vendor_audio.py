#!/usr/bin/env python3
"""Prepare a small offline audition set for the existing iOS PCM audio path.

Does not replace shipped sounds or claim a listening/mixing review.
"""
import array
import hashlib
import json
import math
import pathlib
import subprocess
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]
VENDOR = ROOT / 'art/vendor'
SELECTION = {
    'ui_select': 'kenney-interface-sounds/Audio/select_001.ogg',
    'ui_back': 'kenney-interface-sounds/Audio/back_001.ogg',
    'ui_confirm': 'kenney-interface-sounds/Audio/confirmation_001.ogg',
    'ui_click': 'kenney-interface-sounds/Audio/click_001.ogg',
    'grass_step': 'kenney-impact-sounds/Audio/footstep_grass_000.ogg',
    'stone_step': 'kenney-impact-sounds/Audio/footstep_concrete_000.ogg',
    'body_impact': 'kenney-impact-sounds/Audio/impactPunch_medium_000.ogg',
    'wood_impact': 'kenney-impact-sounds/Audio/impactWood_medium_000.ogg',
    'weapon_slice': 'kenney-rpg-audio/Audio/knifeSlice.ogg',
    'weapon_chop': 'kenney-rpg-audio/Audio/chop.ogg',
}


def main():
    out = VENDOR / 'prepared/audio'
    out.mkdir(parents=True, exist_ok=True)
    report = {'tool': subprocess.check_output(['ffmpeg', '-version'], text=True).splitlines()[0],
              'license': 'CC0-1.0', 'author': 'Kenney',
              'status': 'format-verified-audition-candidates-not-in-App', 'files': []}
    for name, relative in SELECTION.items():
        source = VENDOR / relative
        dest = out / ('kenney_' + name + '.wav')
        args = ['-map_metadata', '-1', '-vn', '-ac', '1', '-ar', '44100',
                '-af', 'volume=0.7', '-c:a', 'pcm_s16le']
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', str(source),
                        *args, str(dest)], check=True, timeout=30)
        with wave.open(str(dest)) as wav:
            assert wav.getnchannels() == 1 and wav.getsampwidth() == 2 and wav.getframerate() == 44100
            samples = array.array('h', wav.readframes(wav.getnframes()))
            if sys.byteorder != 'little':
                samples.byteswap()
            peak = max(abs(v) for v in samples)
            assert 0 < peak < 32767
            rms = math.sqrt(sum(v * v for v in samples) / len(samples)) / 32768
            report['files'].append({'purpose': name, 'source': relative,
                                    'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
                                    'output': str(dest.relative_to(VENDOR)), 'bytes': dest.stat().st_size,
                                    'outputSHA256': hashlib.sha256(dest.read_bytes()).hexdigest(),
                                    'durationSeconds': len(samples) / 44100,
                                    'peakDBFS': 20 * math.log10(peak / 32768),
                                    'rmsDBFS': 20 * math.log10(rms), 'conversion': args})
    (out / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"Prepared {len(report['files'])} PCM WAV candidates; {sum(f['bytes'] for f in report['files'])} bytes")


if __name__ == '__main__':
    main()
