# Build 469 evidence and continuation

Source `fcb8505682f9d065edfcf196f5554863d95d8a2a` publicly committed all 11 licensed
packs, 28 runtime files and source archives. The owner explicitly authorized this
publication and a new TestFlight upload only after verification; 468 is cancelled.

- iOS run: https://github.com/wuyong9494-lab/kriswu/actions/runs/41048809336
- Sample/three-hero run: https://github.com/wuyong9494-lab/kriswu/actions/runs/41048809190
- Promotion: https://github.com/wuyong9494-lab/kriswu/actions/runs/41049046192
  Verification failed; upload and Apple status jobs were skipped. Do not upload 469.

iOS completed successfully: device build and arena animation regressions passed.
The separately named lobby-runtime step was skipped by the branch condition; it
must not be described as passed. Linux ran 304 tests, one platform-specific Excel
test skipped, zero failures. Three-hero and vendor/media validation did not pass.

## Observed failures

Menu artifact 12974307091 was downloaded and both original PNGs viewed. Hero/map
content is present, but vendor button faces and the close glyph are blank. The
actual build log in Mage diagnostics 12973269359 confirms CopyPNGFile copied all
eight UI/particle PNGs into the app. File presence alone did not establish rendering.

All three UI flows failed at the required earned-player-super assertion. Mage's
original scene/trace, battle screenshot and accessibility tree were inspected:
19 control samples; only two player attacks, zero damage, four deaths, natural
result at simulation time 95.9667. The movement branch always continued before
combat until y<=15.2, so enemies killed the player during repeated approaches.
Ranger diagnostics 12973684027 and all workflow logs remain preserved remotely.
Barbarian also hit the command deadline after its failed test; immediate process
kill left xcresult without Info.plist (diagnostics 12973384721; video 12975015678).

Sample artifact 12974951705 was downloaded. Opening decoded 285 frames with no
duplicate PTS. Traversal scene completed at simulation time 16.0 with routeComplete
true, but recordVideo did not finalize within 90 seconds. Its original log contains
`Recording started` without completion; both opening and traversal logs show the
same AppleM2ScalerParavirtDriver message, so that message alone does not establish
the cause. The original partial file is retained, not repaired or certified.

## Changes requiring the next exact CI

- Explicit cached UIImage file decoding for loose vendor PNGs; render those decoded
  images in SwiftUI. Add pixel-level button/close-control rendering regression tests.
- Keep all actual attack, earned super, natural result, returned-lobby and media
  assertions. Fight reachable visible enemies before continuing the route. Additional
  read-only target reachability never injects input, ammo, charge, AI or result.
- Wait for recorder readiness before releasing the time-zero gate. Keep the frozen
  SceneKit surface presenting while recording drains, with simulation/animation
  still frozen. This tests a finalization hypothesis, not an established root cause.
- On XCTest timeout, send SIGINT for bounded xcresult flushing, then kill if still
  stuck. The original timeout remains failure even if cleanup returns success.
- Run vendor loading/rendering/audio tests before media collection so a later
  recorder failure cannot prevent those diagnostics. All media gates remain required.

No physical-device FPS, thermal stability, full audio listening or final visual
acceptance claim. Promote only a newly passed exact source/build/run combination.
