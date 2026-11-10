# Original-source resume observation diagnosis

Source candidate: `8d6fc923a105110e3e54925f201b82d8958794e3`, whose tree
matches local `906e026`. This is a test diagnostic change, not a demonstrated
app fix or accepted native result.

## Observed failure

[Run 42746304926, attempt 2, actual-resource job 129618730964](https://github.com/wuyong9494-lab/kriswu/actions/runs/42746304926/job/129618730964)
failed `DuelWeaponFlowTests.testBothOriginalWeaponProfilesUseSourceControlsAndLandRealHits`.
The log establishes the following sequence for Sun (`ember`):

- 04:37:13: the released-stick check completed and its screenshot was attached.
- 04:37:19: manual resume completed its explicit pause-panel/hittable-pause
  check before Home was pressed.
- 04:37:24: returning to the app exposed Resume; the position and hit-count
  equality checks completed before the background-return screenshot.
- 04:37:25: the second Resume tap began. Unlike the earlier manual resume,
  this path immediately entered the stationary waiter without separately
  observing the active control tree.
- 04:37:28 and 04:37:30: the predicate queried the player HUD.
- 04:37:31: it queried the joystick, with lookup retries at 04:37:32.
- 04:37:33: the five-second waiter failed. The subsequent 1.4-second inverted
  movement assertion was never reached.

The original predicate's short circuit evaluates the joystick only after two
successive parsed positions compare equal. Therefore these logs do not establish
continued movement. They also do not reveal the joystick value, the post-tap
pause state, or whether accessibility was transiently unavailable. Element-lookup
retries alone are insufficient to distinguish those possibilities. Screenshot
pixels and the final accessibility attachment were not inspected or decrypted.
Attempt 1 of the same published commit passed all five actual-resource UI cases; this diagnosis does not reinterpret that earlier pass
as proof that attempt 2 was only infrastructure noise.

## Relevant code and coverage

- `DuelSession.resume()` clears the physical input mailbox, publishes
  `paused = false`, then resumes the renderer. `pause()` clears input first.
- `DuelMatchContent` observes the session and keeps `DuelWeaponControls`
  mounted while its pause overlay is shown. Its scene-phase handler pauses on
  non-active phases. `DuelWorldView` also pauses for `willResignActive`.
- `DuelWeaponControls.updateReadiness` derives `inputEnabled` from pause and
  resource state. `DuelSourceControlsView` cancels ownership on disable,
  relayout, and window loss. Disabling changes the joystick value to
  `操作已暂停` and adds `.notEnabled`; it does not intentionally remove the
  accessibility element. Re-enabling refreshes the value to `居中` after reset.
- Audio interruption notifications also enqueue a main-actor pause. A late
  interruption or scene transition is a possible re-pause mechanism, but no
  such notification is evidenced by this failure log. Changing lifecycle
  behavior on that hypothesis would be premature.

The failing job passed all 14 `DuelSourceControlsTests`, including pause and
equipment accessibility restoration, cancellation on disable/layout, duplicate
pointer ownership, and reentrant mailbox cancellation. It also passed
`testSceneClockStopsOnPauseAndResourcesReleaseAcrossRepeatedEntries` and the
ordinary pause/input-buffer tests. Those clock and session checks use the
legacy/default session path, and the standalone control tests directly inspect
UIKit properties; they do not prove that SwiftUI/OS accessibility recovers the
original controls after a real background round trip. The four passing
`DuelFlowTests` do not establish this original-weapon control behavior either.
The actual-source gameplay/native suite did not finish before its separate
deadline, so it is not a full native pass.

## Local diagnostic change

Only `DuelWeaponFlowTests.swift` changes executable code. Each stationary poll
now reads one immutable accessibility snapshot, then obtains the HUD, joystick,
Resume, Pause, and resource-error state from that same tree. A missing joystick
becomes recorded data rather than a direct `.value` query with implicit lookup
retries. The existing five-second settling waiter timeout and 1.4-second no-movement
waiter timeout are unchanged; no sleeps, retry taps, simulated input, accelerated
ticks, skipped actions, or production changes are introduced.

Two consecutive active, centered observations with equal positions are required.
The no-movement interval also rejects missing controls, a paused joystick value,
a returned pause panel, a resource error, or a failed snapshot, so a paused game cannot falsely
pass as resumed stationary play. Existing hit-count and real-touch assertions
remain in place.
The joystick's `isEnabled` snapshot property is recorded but not asserted:
the underlying UIView deliberately has `isUserInteractionEnabled = false`
because its parent owns touches, and its XCTest enablement mapping has not been
verified. The existing accessibility value contract supplies the pause check.

Timestamped narrow observations are printed with `[fighter-stationary]` and
retained as `original-weapons-stationary-observations.json` through the existing
private attachment flow. They distinguish missing/duplicate controls, paused
controls, malformed or absent HUD values, and snapshot errors, and include each
snapshot's duration. Full trees and screenshots are not printed to the log.
This may reduce redundant cross-process lookups, but no performance or failure
recovery improvement is claimed without a native run.
`app.snapshot()` remains synchronous and can itself be slow; waiter timeouts
do not guarantee a strict wall-clock limit or sampling rate. Accessibility
readiness also does not independently prove renderer advancement or hit-testing.

## Verification and limits

- `git diff --check`: passed.
- Manual source review: preserved both assertion waiter timeouts, the real-touch
  scenario, source requirements, and post-resume hit-count assertion.
- A focused Python structural check verified that only the intended stationary
  helper and its diagnostics changed, and that the timeout values remain 5 and
  1.4 seconds. This is not Swift compilation or behavioral testing.
- This Linux workspace has neither Swift nor Xcode. The modified UI test was
  not compiled or executed. UIKit/XCTest API compilation and both actual-source
  background/resume sequences remain required before accepting the change.
- Independent read-only review found no blocking source-level issue and
  confirmed the timeout/real-touch assertions were retained; it did not compile
  or execute the modified test.
- No workflow, app/runtime, source assets, secret, publication, CI dispatch,
  or TestFlight action was changed by this patch.

Next evidence should classify the first failing observation before any app
change: a missing joystick with active HUD differs from a returned Resume panel,
a paused joystick value, an invalid position, or a snapshot failure. If the
tree is active and centered but positions change, then investigate actual input
or rule-state motion. If all observations are ready and stationary but expire,
their durations quantify observer latency rather than justify weakening the
assertion.
