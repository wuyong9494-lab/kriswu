#!/usr/bin/env python3
"""Generate tiny original synthetic fixtures for the host iOS audio decoder.

No supplied game material is used. Ramp, wrap and end-point samples exercise
16-bit extrema, stereo separation and a final partial ALAC packet.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import wave


def generate(destination):
    destination.mkdir(parents=True, exist_ok=True)
    records = []
    for rate, channels in [(22050, 1), (44100, 1), (44100, 2), (48000, 1), (48000, 2)]:
        name = f"alac_pcm_{rate}_{channels}"
        frames = 5003  # Not divisible by the usual ALAC packet size.
        samples = []
        for frame in range(frames):
            for channel in range(channels):
                sample = ((frame * (97 + channel * 16) + channel * 12345) % 65536) - 32768
                if frame == 0:
                    sample = -32768 + channel
                elif frame == 1:
                    sample = 32767 - channel
                elif frame == frames - 1:
                    sample = 12345 if channel == 0 else -12345
                samples.append(sample)
        pcm = struct.pack("<" + "h" * len(samples), *samples)
        wav = destination / (name + ".wav")
        with wave.open(str(wav), "wb") as out:
            out.setnchannels(channels)
            out.setsampwidth(2)
            out.setframerate(rate)
            out.writeframes(pcm)
        alac = destination / (name + ".m4a")
        subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav),
                        "-map", "0:a:0", "-vn", "-map_metadata", "-1", "-c:a", "alac", "-sample_fmt", "s16p",
                        "-bits_per_raw_sample", "16", "-threads", "1", "-movflags", "+faststart", "-f", "ipod", str(alac)],
                       capture_output=True, check=True)
        decoded = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(alac),
                                  "-map", "0:a:0", "-c:a", "pcm_s16le", "-f", "s16le", "-"],
                                 capture_output=True, check=True).stdout
        if decoded != pcm:
            raise ValueError("Synthetic ALAC did not round-trip exact PCM")
        records.append({"name": name, "sampleRate": rate, "channels": channels, "bitsPerSample": 16,
                        "frames": frames, "PCMBytes": len(pcm), "PCMSHA256": hashlib.sha256(pcm).hexdigest(),
                        "wavFile": wav.name, "wavSHA256": hashlib.sha256(wav.read_bytes()).hexdigest(),
                        "m4aFile": alac.name, "m4aSHA256": hashlib.sha256(alac.read_bytes()).hexdigest(),
                        "roundTripPCMExact": True})
    manifest = {"schemaVersion": 1, "syntheticOnly": True, "originalGameMaterialIncluded": False,
                "generator": "generate_alac_fixture.py", "fixtures": records}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"output": str(destination), "fixtures": len(records),
                      "bytes": sum(p.stat().st_size for p in destination.iterdir() if p.is_file())}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    generate(args.output)
