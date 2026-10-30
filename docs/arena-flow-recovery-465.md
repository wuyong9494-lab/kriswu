# Build465 recovery and next validation

Base: `1f26a334`; first repair: `7604b56c`; saved diagnostics recovery: `80862e5d`.

## Confirmed, not accepted as full success

- iOS run 41026778535 succeeded. Sample run 41026778508 failed.
- Removing ancestor accessibility identifiers fixed entry → lobby → hero list/detail → battle navigation.
- Barbarian and Ranger UI tests reached natural results and returned; their player event evidence has no super, so neither passes full scene acceptance.
- Mage failed the unchanged 360-second natural-result deadline. Original final screenshot still shows 1:20 remaining. The accessibility tree exposes hundreds of SceneKit nodes with enormous offscreen bounds; this is a suspected snapshot/main-loop bottleneck, not a confirmed fix until the next run.
- Fresh traversal device was unnecessarily terminated before its first launch. Terminate timed out, causing a restart; launch then timed out. Skip this only when the caller explicitly identifies a fresh device.
- xcresult exports normalize attachment names to `arena-flow-hero-2_0_UUID.json`; fix the collector's incorrect `.json` prefix match.
- Automatic Xcode movies failed timestamp validation. Preserve those originals; do not repair, retime, or call them accepted.

## Changes to verify

Hide decorative SceneKit geometry from accessibility while retaining sibling HUD/controls. Real joystick test goes east around the spawn wall before heading north. Keep all navigation/result assertions and the same 360-second match deadline; assert actual player attack and super events as well.

Run each hero on an independent simulator with an independent continuous recording. Upload screenshots, trees, JSON and logs before long media validation. Persist partial validation reports. Disable Xcode automatic movie capture only in favor of the continuous original recording, retaining automatic failure screenshots. This is pending CI and visual review, not a declaration of acceptance.

Existing downloaded assets remain integrated; see `arena-existing-resources.md`. No asset replacements, forced wins, accelerated simulation, main merge or TestFlight release.

Original evidence: https://github.com/wuyong9494-lab/kriswu/actions/runs/41026778508
Recovered small evidence: https://github.com/wuyong9494-lab/kriswu/actions/runs/41033100736
