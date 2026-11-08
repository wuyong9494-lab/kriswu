# Native UI motion evidence

The actual-character job now wraps its existing two `DuelFlowTests` with one
unretimed Simulator H.264 recording. This follows Apple's documented
[simctl recording and Control-C finalization](https://developer.apple.com/videos/play/wwdc2020/10647/).
The wrapper waits for recorder readiness, keeps recorder and test process
groups separate, and requests a bounded graceful stop before any cleanup
escalation. A test failure retains its exit status; a missing, interrupted or
unflushed recording cannot pass solely because XCTest succeeded.

The MP4, recorder diagnostics and provenance JSON live only under
`fighter-evidence/native-motion`, inside the existing authenticated encrypted
evidence archive. No plaintext recording or personal screenshot is added to
the public artifact paths. Provenance records the tested commit, workflow run,
Simulator identity, UTC boundaries, process exit statuses and actual video
byte count and SHA-256. No source assets or encrypted chunks are changed.

The test selectors and test count remain unchanged. In addition to the existing
Sun light attack, pause/background/portrait-return checks and Liu hold/release,
the Sun flow now restarts and approaches through real controls before each
heavy attack and two skills. Exact hit/damage checks distinguish successful
actions from button taps alone. These three actions add screenshot attachments
and run in both existing UI test jobs; only the actual-character job records
video. The existing 15-minute unit, 10-minute UI and 40-minute job limits remain.

## Actual capture and bounded review

All five jobs passed at `ed048cb3a58e6fa203e60a17fe2fa8f139084eb3` in
[run 42479153124](https://github.com/wuyong9494-lab/kriswu/actions/runs/42479153124).
The actual-asset group passed 43 unit and two UI tests with no failures or skips.
Its recorded UI tests took 247.448 seconds. Recorder and test exit codes were
both zero, and the sidecar matches this commit, run and exact original file.

The original H.264 MP4 is 356,660,305 bytes, 1320 by 2868 pixels and 320.128333
seconds long. Its SHA-256 is
`d22a4a3721b27c368e1922c8db360c9d12499592485118394afa4fbdd3c76659`.
All 6,895 frames decode. Landscape app content appears sideways within the fixed
portrait recording canvas; the raw file is retained unchanged.

The original presentation timestamps are nondecreasing but contain nine equal
adjacent pairs. FFmpeg's best-effort timestamp selection falls back to decoding
timestamps after a tie, producing output-time warnings and backward jumps in
that derived timeline. Independent checking reproduced that selection exactly.
This is a real timestamp-compatibility limitation of the raw recording, even
though the frame bitstream decodes. Whole-file playback compatibility is not
marked clean. Original warnings, timestamp diagnostics and provenance are kept.

Sixty sampled frames were inspected across Sun's heavy attack and two skills,
and Liu's hold, pause/background, resume and release. They show the expected
165/135/155 damage feedback, knockdown/recovery for heavy and skill2, and Liu's
first impact, paused hold and second impact reaching two hits and 280 damage.
This validates those observed sequences; final all-move animation quality and
physical-device performance remain open.

A separate viewing preview uses five verified intervals with strictly increasing
presentation timestamps. It rotates the image 90 degrees counterclockwise and
scales it to 1434 by 660. The 16.323333-second preview contains 1,058 original
frames with every within-segment time interval preserved exactly at 1/600-second
precision. Four hard cuts separate the excerpts; no action timing is accelerated.

| Excerpt | First source PTS (seconds) | Last source PTS (seconds) | Frames |
| --- | ---: | ---: | ---: |
| Sun heavy | 139.610000 | 142.595000 | 195 |
| Sun skill1 | 150.411667 | 153.010000 | 171 |
| Sun skill2 | 159.211667 | 161.995000 | 187 |
| Liu hold and pause | 237.810000 | 241.776667 | 285 |
| Liu resume and release | 245.026667 | 249.008333 | 220 |

The preview is 1,804,134 bytes, SHA-256
`caa18b6ed6de395aac5764292e6b1ba8876b67fd754e7335c50fb49af21bb565`.
Its complete decode passed with an empty error log, and six decoded checkpoints
were inspected for action order and upright presentation.
Its exact frame mapping, transforms and commands are retained privately with
the raw recording. Encoded/derived frame-rate fields do not establish source
animation FPS, stable device FPS or complete source-game skill logic/effects.
