# Combat input lifecycle · 2026-11-05

Continues the validated Build 514 source on `codex/plan-photo-rules`. No new heroes or private assets are added.

## Defect and behavior

The exit/disconnection UI previously cleared visible movement/aiming but left queued attacks, ultimates, gadgets and emotes in the controller. The next simulation tick could execute those commands under the modal. A renderer stop cleared existing commands once, but subsequent gesture callbacks could enqueue them again before rendering resumed.

The controller now owns independent dialog and renderer pause reasons. Entering or leaving either pause clears held and queued input; foregrounding cannot remove an outstanding dialog pause. The exit button blocks immediately, before SwiftUI's change callback. Movement, aim and action callbacks are checked at the controller, and local simulation/network movement use neutral input while blocked. Intro completion and the first result clear any remaining input. A dialog blocks only local input: match clocks, AI and other participants keep running.

Seven new native tests exercise actual controller ticks and events: intro buffering, queued actions under a dialog, late callbacks while paused, overlapping pause reasons in both release orders, natural survivor-rule completion, continuing bots/clock, and a queued ultimate whose charge was earned through real attacks. The crowd cases use a normal, seeded player-controlled roster; the charge test drives movement and attacks through controller callbacks without injecting charge. Three relevant existing methods cover renderer teardown, manual movement and diagnostic input export. Test scenarios do not change progression saves.

## Validation

Local resource inventory, workflow YAML/shell parsing and whitespace checks pass. The `[arena-input-tests]` marker selects the ten focused native cases on an iPhone 17 Pro Max simulator. This workspace has no local Swift/Xcode toolchain.

[Build 516](https://github.com/wuyong9494-lab/kriswu/actions/runs/41970681764) validates source `072d58816b68887759cf3f9d648c72ff49de6b01`, tree `111ed24c95397a0a274adc3791fc41fdc9478280`.

| Check | Result |
| --- | --- |
| Native input / renderer tests | 10 passed, 0 skipped, 0 failures; 15.770 seconds on iPhone 17 Pro Max / iOS 26.2 simulator with Xcode 26.3. |
| Linux core | 616 tests, 15 skipped, 0 failures; 64.334 seconds; 0 concurrency warnings. |
| macOS core | 616 tests, 14 skipped, 0 failures; 208.309 seconds. |
| iPhone Release / unsigned IPA | Compilation and packaging passed; 0 concurrency warnings. IPA artifact publication and GitHub Release publication were skipped for this branch. |

Native evidence artifact: `site-tests-516-1`, ID `13390250282`, 137573 bytes, digest `sha256:fe8a5e679b96230b5939e75fadb1b74d63c279132f93ec3e5e127c2ba92dc406`.

The run completed successfully at 2026-11-05 13:13:33 Beijing time. Exact producing source, job IDs, test names and artifact digest are recorded in [arena-input-516.json](evidence/arena-input-516.json). TestFlight and its release-notes job were skipped; no new upload was made.

Build 515 completed all ten cases: eight passed, and the two crowd cases produced four assertion failures because the benchmark fixture deliberately gave AI control of the player. The fixture correction uses a normal seeded roster and earns charge through real controller input. All ten cases pass in Build 516 without weakening the movement, charge or event assertions.

These controller/renderer checks do not establish a real multi-device network session, finger interaction on physical hardware, or stable physical-device FPS. No new TestFlight upload is part of this batch.
