# Fighter renderer teardown investigation — 2026-11-09

## Failure evidence and limits

[Run 42661107172](https://github.com/wuyong9494-lab/kriswu/actions/runs/42661107172),
source `01f87e9`, character job `129312605630`, reported 115 native cases and one
failure. `DuelLifecycleTests.testSceneClockStopsOnPauseAndResourcesReleaseAcrossRepeatedEntries`
still observed a `DuelWorldView` 100 ms after shutdown, removal and clearing the
test's local reference. The log showed `scene=(null)` and a non-nil camera.
It does not show when that view was eventually released or identify its owner.
An earlier successful run is not proof that this failure is harmless.

The current log alone cannot distinguish an in-flight renderer/UIKit reference,
an autoreleased or async-test temporary, and persistent retention. The camera
description alone also cannot establish whether it is the original camera or
a renderer-provided fallback. No GPU-drain diagnosis is claimed.

## Ownership audit and production correction

- The view's `CADisplayLink` target holds the view weakly. `stopClock` invalidates
  and clears the link and disables both continuous rendering and playback.
- All three session callbacks capture the view weakly. Shutdown clears those
  slots and removes notification observation. Source/weapon effects and all
  application-owned model and node collections are explicitly released.
- `tick` and `startClock` already reject an ended view. `drawState` already
  rejected a nil scene, so an extra ended guard there is defense, not a proven
  explanation of the failure.
- A concrete gap existed in `layoutSubviews` → `updateCameraFraming`: late UIKit
  layout still asked a closed renderer for its camera and mutated it. Framing
  now rejects ended views and missing scenes. Copied pause/reset/feedback
  callbacks and late window/interruption callbacks also reject ended views.
- Shutdown clears session callbacks before invoking input cleanup and clears
  the camera after disconnecting the scene. The existing transaction flush and
  node/cache cleanup remain. These changes do not establish that SceneKit's
  internal view lifetime is fixed until native verification completes.

No gameplay, assets, UI flow, network compatibility or workflow changes are
part of this patch.

## Regression and lifetime observation

`testShutdownRejectsLateLayoutAndCopiedSessionCallbacks` retains the closed view
and copies of its session callbacks. A sentinel camera makes unwanted framing
observable without depending on when SceneKit supplies a default camera.
Late layout, draw, reset, pause/resume, window callbacks and repeated shutdown
must not change that camera, invoke session input cleanup, start playback or
advance the clock. The previous layout implementation would replace its
sentinel orthographic scale, and the previous window callback would clear input.
This is a targeted behavior regression, not a simulated memory-leak result.

The existing three-entry hosted lifecycle test still requires actual foreground
clock progression, a stable paused frame, explicit resume, immediate stopped
clocks and `view.scene == nil` on shutdown. It additionally checks renderer
flags, cleared callbacks and cleared resource owners before releasing the view.

Setup, rendering, `XCTUnwrap` arguments and teardown now finish inside a separate
async helper. Only weak resource probes and weakly capturing callbacks return.
This prevents the observation scope itself from keeping strong setup/progress
temporaries. The session and copied callbacks remain alive throughout the weak
reference observation, so a strong callback cycle must still fail.

The observer polls every 10 ms with a 3-second ceiling. It requires the view,
original scene and original camera to all deallocate. Each poll uses a scoped
autorelease pool and returns only booleans. It does not access `pointOfView` on
the closed renderer, call shutdown again, flush extra transactions, pump a
private renderer, or skip the assertion. Frame stability and the active-clock
baseline must hold through observation. Teardown also runs if an earlier test
step throws.

The test prints a compact `[fighter-release]` summary into the normal test log,
so diagnosis does not depend on recovering the complete private xcresult. The
retained `fighter-release-<hero>` attachment records:

- First observed release time for each of the three original objects, measured
  from dropping the last test-owned view reference, including helper exit time.
- Every sampled live/dead state, including the first sample at or after 100 ms
  when the observation lasts that long. Sampling gives a release interval, not
  the exact deinit instant.
- A failure if any object remains after the ceiling. An object observed alive
  past 100 ms and then gone proves transient retention for that run; it does
  not by itself identify a GPU owner. If all objects release sooner, the
  historical cause remains unproven. Persistent retention still blocks acceptance.

## Verification status

Local `git diff --check` passes. This Linux executor has neither Swift nor Xcode,
so it cannot compile UIKit/SceneKit, run the regression, measure release times
or reproduce the original resource failure. No native pass or leak fix is
claimed. Existing ordinary and actual-resource workflow selections already
include the complete `DuelLifecycleTests` suite; no test-selection change is
needed. Native compile, both lifecycle cases, and the full actual-resource
suite remain required before accepting the candidate.

No commit, push or CI run was performed for this investigation.
