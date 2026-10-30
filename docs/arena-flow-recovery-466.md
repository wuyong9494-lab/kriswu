# Build 466 evidence and continuation

Source: `bc8f5fe557d994dd03a1d3961942ff48859a0b7a` on `codex/arena-quality-sample`.
Both runs completed; no retry or parallel replacement was started before reviewing them.

- [iOS 466](https://github.com/wuyong9494-lab/kriswu/actions/runs/41034343629): device build, Linux core tests, and all 46 simulator regressions passed. The later original/legacy ranger comparison capture failed its model-readiness check. Overall run failed; no release/TestFlight.
- [Sample validation](https://github.com/wuyong9494-lab/kriswu/actions/runs/41034343639): menu/map/opening/traversal job passed. All three independent UI-flow jobs failed. Originals and diagnostics were saved separately for each hero.
- Mage and Barbarian reached natural results but failed the required player-super assertion. Mage had 13 attacks; Barbarian had 12 attacks and zero damage. Neither is accepted. Their battle-start screenshots were actually the VS overlay, so controls existing did not prove input readiness.
- Ranger missed the unchanged 360-second natural-result deadline. Its final screenshot still showed 1:41; its accessibility tree was 110,628 characters and exposed `harbor-wall-cells` and many SceneKit nodes despite underlying UIKit accessibility flags.
- The continuous media collector incorrectly compared video duration to the whole xcodebuild invocation (including install and result processing). Actual XCTest durations were Ranger 447.896s, Barbarian 290.072s, Mage 400.846s. Failed tests remain failed irrespective of video duration. Original timing is never repaired.
- Legacy capture expected Rogue/Original ranger while the default lobby now uses the face-sample model. Give that existing comparison its own demo route instead of weakening the expected-model check or changing the real three-hero entry flow.

## Changes prepared after inspecting the evidence

1. Hide scene geometry at the SwiftUI representable boundary as well as UIKit. Assert the wall mesh is absent from the real battle accessibility tree.
2. Hide and disable controls while the VS overlay is present. Wait for the real control and check hittability before movement.
3. Cache stable control coordinates after readiness and use real taps; remove repeated failed one-second `waitForExistence` calls from the fight loop. Keep the same 360-second deadline, real damage/charge, player attack/super assertions, natural results, and return-to-lobby assertion.
4. Wait for the recorder's actual readiness message before invoking XCTest. Record command and actual-test durations separately. Reject missing/ambiguous timing, failed tests, incomplete recording, and a video shorter than the test.
5. Keep original/legacy asset capture on `arenaRangerComparison`; keep `game → arena` on the actual three-hero lobby. Do not terminate an app before its first launch on the fresh comparison simulator.

Local validation: 34 Python capture/evidence regressions passed; workflow YAML, embedded Bash syntax, and diff whitespace passed. Xcode is unavailable locally. These are proposed repairs awaiting their own CI result, not a full-flow acceptance claim.

Artifact IDs: sample 12968520999; Ranger diagnostics 12968472013 / evidence 12967719609; Barbarian diagnostics 12967279566 / evidence 12967284787; Mage diagnostics 12968287362 / evidence 12968103351. `docs/evidence/build466-summary.json` records inspected attachment hashes. Do not repeat downloads already present locally or confuse 466 results with the successor commit.

Existing KayKit, Game-icons, original ranger, scenery, background, and audio assets are preserved; see `arena-existing-resources.md`. No engine change, forced result, accelerated match, relaxed assertions, main merge or TestFlight publication.
