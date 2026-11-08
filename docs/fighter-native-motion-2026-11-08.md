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

The recording is evidence of the tested app interactions in a Simulator.
Native capture, decoding and visual review are pending. Even after a successful
capture, encoded video frame rate does not establish source animation FPS,
physical-device performance, all-move art quality or complete source-game skill
logic/effects. Any acceptance record must distinguish those open items from
the specific actions actually observed.
