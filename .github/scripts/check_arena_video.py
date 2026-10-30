#!/usr/bin/env python3
"""Software-decode all frames; media integrity is separate from visual/device review."""
import json
import math
import subprocess
import sys


def validate_frames(frames):
    if len(frames) < 60:
        raise RuntimeError('Incomplete recording: fewer than 60 frames')
    previous = -math.inf
    first = None
    for frame in frames:
        stamp = float(frame['best_effort_timestamp_time'])
        if not math.isfinite(stamp) or stamp <= previous:
            raise RuntimeError('Invalid or non-increasing video timestamp')
        if min(frame['width'], frame['height']) < 500:
            raise RuntimeError('Undersized decoded frame')
        if first is None:
            first = stamp
        previous = stamp
    if previous - first < 6:
        raise RuntimeError('Incomplete recording: less than six seconds')
    return previous - first


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: check_arena_video.py movie.mp4')
    path = sys.argv[1]
    # Do not depend on paravirtual macOS hardware video drivers on hosted runners.
    # Raw output avoids null-muxer timebase rounding warnings on variable-rate input.
    subprocess.run(['ffmpeg', '-v', 'error', '-xerror', '-hwaccel', 'none', '-i', path,
                    '-map', '0:v:0', '-f', 'rawvideo', '-y', '/dev/null'], check=True, timeout=240)
    result = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_frames', '-show_entries', 'frame=best_effort_timestamp_time,width,height',
        '-of', 'json', path], capture_output=True, text=True, check=True, timeout=240)
    frames = json.loads(result.stdout)['frames']
    span = validate_frames(frames)
    print(f'Software-decoded {len(frames)} frames, span {span:.3f}s. Content/device acceptance remains separate.')


if __name__ == '__main__':
    main()
