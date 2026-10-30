#!/usr/bin/env python3
"""Software-decode all frames; media integrity is separate from visual/device review."""
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys


def validate_frames(frames):
    if len(frames) < 60:
        raise RuntimeError('Incomplete recording: fewer than 60 frames')
    previous = -math.inf
    first = None
    duplicate_timestamps = 0
    for frame in frames:
        stamp = float(frame.get('pts_time', frame.get('best_effort_timestamp_time', 'nan')))
        if not math.isfinite(stamp) or stamp < previous:
            raise RuntimeError('Invalid or backward presentation timestamp')
        if stamp == previous:
            duplicate_timestamps += 1
        if min(frame['width'], frame['height']) < 500:
            raise RuntimeError('Undersized decoded frame')
        if first is None:
            first = stamp
        previous = stamp
    if previous - first < 6:
        raise RuntimeError('Incomplete recording: less than six seconds')
    return previous - first, duplicate_timestamps


def timing_evidence(frames, packets):
    """Locate timestamp collisions without rewriting, dropping or resampling frames."""
    groups = {}
    for packet in packets:
        if 'pts' in packet:
            groups.setdefault(int(packet['pts']), []).append({key: packet.get(key) for key in
                ('pts', 'pts_time', 'dts', 'dts_time', 'pos', 'size', 'flags')})
    duplicates = []
    for index in range(1, len(frames)):
        previous, current = frames[index - 1], frames[index]
        if 'pts' in previous and 'pts' in current and int(previous['pts']) == int(current['pts']):
            duplicates.append(dict(frameIndices=[index - 1, index], pts=current['pts'],
                ptsSeconds=current.get('pts_time'),
                packetEvidence=groups.get(int(current['pts']), []),
                frameContext=[dict(frameIndex=j, **frames[j]) for j in
                    range(max(0, index - 2), min(len(frames), index + 3))]))
    return dict(duplicateGroups=duplicates,
        framesWithoutActualPTS=sum('pts' not in frame for frame in frames),
        timingAcceptance='needs-review' if duplicates or any('pts' not in f for f in frames) else 'strictly-increasing',
        interpretation='Packet PTS collisions originate in the recorded stream; encoder versus source-clock cause is not established.')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: check_arena_video.py movie.mp4')
    path = sys.argv[1]
    report = Path(path).with_suffix(".decode.json")
    report.unlink(missing_ok=True)
    # Do not depend on paravirtual macOS hardware video drivers on hosted runners.
    # Raw output avoids null-muxer timebase rounding warnings on variable-rate input.
    subprocess.run(['ffmpeg', '-v', 'error', '-xerror', '-hwaccel', 'none', '-i', path,
                    '-map', '0:v:0', '-f', 'rawvideo', '-y', '/dev/null'], check=True, timeout=240)
    result = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_frames', '-show_packets', '-show_streams', '-show_entries',
        'frame=pts,pts_time,pkt_dts_time,best_effort_timestamp_time,pkt_pos,pict_type,width,height:packet=pts,pts_time,dts,dts_time,pos,size,flags:stream=codec_name,time_base,start_time,duration,nb_frames',
        '-of', 'json', path], capture_output=True, text=True, check=True, timeout=240)
    probe = json.loads(result.stdout)
    entries = probe.get('packets_and_frames', [])
    frames = probe.get('frames', [e for e in entries if e.get('type') == 'frame'])
    packets = probe.get('packets', [e for e in entries if e.get('type') == 'packet'])
    span, duplicates = validate_frames(frames)
    report.write_text(json.dumps(dict(sourceCommit=os.environ.get('GITHUB_SHA'), video=Path(path).name,
        frames=len(frames), presentationSpanSeconds=span, duplicatePresentationTimestamps=duplicates,
        softwareDecoded=True, retimed=False,
        videoSHA256=hashlib.sha256(Path(path).read_bytes()).hexdigest(),
        streams=probe.get('streams', []), timing=timing_evidence(frames, packets),
        limitations=['Not a presented-device FPS measurement', 'Visual/audio acceptance remains separate']), indent=2) + '\n')
    print(f'Software-decoded {len(frames)} frames, PTS span {span:.3f}s, duplicate PTS frames={duplicates}.')
    print('Duplicate timestamps are retained/reported, not retimed or counted as device FPS. Content/device acceptance remains separate.')


if __name__ == '__main__':
    main()

