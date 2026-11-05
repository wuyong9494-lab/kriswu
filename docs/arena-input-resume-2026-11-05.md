# Combat input lifecycle · 2026-11-05

Continues the validated Build 514 source on `codex/plan-photo-rules`. No new heroes or private assets are added.

## Defect and behavior

The exit/disconnection UI previously cleared visible movement/aiming but left queued attacks, ultimates, gadgets and emotes in the controller. The next simulation tick could execute those commands under the modal. A renderer stop cleared existing commands once, but subsequent gesture callbacks could enqueue them again before rendering resumed.

The controller now owns independent dialog and renderer pause reasons. Entering or leaving either pause clears held and queued input; foregrounding cannot remove an outstanding dialog pause. The exit button blocks immediately, before SwiftUI's change callback. Movement, aim and action callbacks are checked at the controller, and local simulation/network movement use neutral input while blocked. Intro completion and the first result clear any remaining input. Match clocks, AI and other participants keep running.

Seven new native tests exercise actual controller ticks and events: intro buffering, queued actions under a dialog, late callbacks while paused, overlapping pause reasons in both release orders, natural survivor-rule completion, continuing bots/clock, and a queued ultimate whose charge was earned through real attacks. Three relevant existing methods cover renderer teardown, manual movement and diagnostic input export. Test scenarios do not change progression saves.

## Validation

Local resource inventory, workflow YAML/shell parsing and whitespace checks pass. The `[arena-input-tests]` marker selects the ten focused native cases on an iPhone 17 Pro Max simulator. CI execution, device compilation and concurrency checks are pending at this commit; this workspace has no local Swift/Xcode toolchain.

These controller/renderer checks do not establish a real multi-device network session, finger interaction on physical hardware, or stable physical-device FPS. No new TestFlight upload is part of this batch.
