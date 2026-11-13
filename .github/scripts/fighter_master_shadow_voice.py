#!/usr/bin/env python3
"""Master an original Mandarin performance into the game's Liu shadow callout.

Input must be a licensed human recording or a permitted neural-voice export.
No system TTS, synthetic placeholder, or unlicensed game audio is generated.
Requires ffmpeg and ffprobe; writes a mono 44.1kHz 16-bit CAF asset.
"""
import argparse
from pathlib import Path
import shutil
import subprocess

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Approved recording of 看我黑懒")
    parser.add_argument("output", type=Path, help="liu_shadow_callout.caf")
    args = parser.parse_args()
    if args.output.suffix.lower() != ".caf":
        parser.error("Output must be a .caf file")
    for binary in ("ffmpeg", "ffprobe"):
        if not shutil.which(binary):
            parser.error(f"{binary} is required")
    if not args.source.is_file() or args.source.stat().st_size > 30_000_000:
        parser.error("Source audio missing or too large")
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
        "format=duration", "-of", "default=noprint_wrappers=1:nokey=1",
        str(args.source)], capture_output=True, text=True, check=True)
    try:
        duration = float(probe.stdout.strip())
    except ValueError:
        parser.error("Unable to determine source duration")
    if not 0.25 <= duration <= 8.0:
        parser.error("Voice performance must be 0.25–8 seconds")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # High-pass to clear rumble, dynamic compression, short shadow-room echo,
    # and peak limiting. This is a mix preset, not a replacement for acting.
    filter_chain = ("highpass=f=75,acompressor=threshold=-20dB:ratio=3:"
                    "attack=8:release=110,aecho=0.8:0.25:95:0.13,"
                    "alimiter=limit=0.89")
    subprocess.run(["ffmpeg", "-nostdin", "-y", "-loglevel", "error",
        "-i", str(args.source), "-af", filter_chain, "-ar", "44100",
        "-ac", "1", "-c:a", "pcm_s16le", str(args.output)], check=True)
    print(f"Mastered {args.output} ({args.output.stat().st_size} bytes)")

if __name__ == "__main__":
    main()
