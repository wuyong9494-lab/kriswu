# Fighter continuation: recovery, landscape lobby and camera

## Baseline and isolation

- Verified remote fighter branch HEAD: `6c2ee11379c43607a3035ba4f8bfff7a0a0dc6d8`.
- Changes prepared in an isolated local continuation branch. No changes to main, published fighter branch, encrypted assets, release workflows, duty scheduling or notifications.
- The current environment lists only the connected cloud computer. A disconnected/unlisted Mac's unpushed edits cannot be verified here. Recent accessible task outcomes inspected were completed/interrupted, not active development runs.
- No Actions run exists for the baseline SHA (its message includes `[skip ci]`). Earlier successful runs do not validate this candidate.

## Implemented candidate changes

1. Fighter character-selection lobby acquires its own landscape orientation holder. Returning from a fight keeps the lobby landscape; leaving the lobby releases the holder. Short landscape screens can scroll the action panel instead of clipping start/practice/tutorial controls.
2. Layout and rendering use one camera-framing calculation. Portrait/rotation-safe framing is no longer overwritten on the next perspective render frame. Wide-screen close framing and separation-driven zoom remain. Narrow perspective windows back the camera away when the FOV cap would otherwise crop the stage.
3. Restart clears camera tracking and impact shake along with effects, preventing the previous fight's camera state from leaking into the new round.
4. Completed attack/reaction recovery applies current automatic defense, movement or crouch on the first ready tick, eliminating the extra unguarded idle tick. A buffered attack still takes priority.
5. Unsupported actions do not occupy the single recovery/hit-stop command buffer and suppress a later valid attack. Reaction hit-stop commands do not replay after stun.

Sun (`ember`) retains katana and Liu (`liu`) retains dual hammers. No source clips, rigs, damage or weapon identities were replaced.

## Validation

Passed locally:
- `git diff --check`.
- `python3 -m unittest discover -s .github/scripts -p 'test_fighter_*.py'`: 27 infrastructure tests, 0 failures. These use synthetic fixtures and are not real-resource visual acceptance.

Added/updated, not executed here:
- Seven combat regression tests covering both weapon recoveries, movement/crouch, buffered priority, aerial kicks, reaction recovery and unsupported buffer entries.
- Three camera-policy tests for landscape close-up/separation, portrait preservation and invalid geometry.
- Native repeated-render/rotation/restart camera regression.
- Existing UI flow expectations updated for landscape lobby, including portrait restoration after leaving it.

Swift is not installed on this executor; the focused Swift command fails with `swift: command not found` (exit 127). Xcode/iOS simulator are unavailable. No Swift compile, native/UI test or physical-device FPS/latency check is claimed. Remote publication and unsigned CI remain pending review of this exact candidate.

## Remaining acceptance work

- Run core regressions and unsigned device build, ordinary native/UI flows, and authenticated actual-resource tests at one grouped milestone.
- Visually assess full-body proportions, head/neck binding, Liu recovery-to-idle continuity, edge controls, attack trails and camera on both characters.
- Verify landscape lobby entry, selection, match exit, app-background interruption and return to the duty app.
- Measure actual iPhone touch-to-action latency and frame pacing; do not equate source tests with those measurements.
- Two-player network selection and combat are not implemented by this patch. Network protocol/authority, disconnect handling and two-device testing remain separate work.
- Original shadow/ranged source timing remains unavailable. This patch does not invent source-equivalence claims.
- No TestFlight distribution or release was performed.

## Remote checkpoint: approved candidate 5f5834a

Run [42624654940](https://github.com/wuyong9494-lab/kriswu/actions/runs/42624654940)
validated the exact first-batch source tree. Core: 836 tests, 16 skips, 0 failures;
envelope and unsigned device build passed. Native/UI bundles compiled. The first
native attempt timed out starting the simulator; only that job was retried.

On retry, the new camera regression, repeated-entry clock/resource release test,
and both real-touch UI flows passed. Native overall remained failed: two existing
showroom tests made eight success/reset assertions despite the ordinary job not
staging private character models. Atomic selection intentionally preserves the
current scene and camera when source files are absent.

The follow-up test correction selects expected behavior using source-file/catalog
availability, never decoder success. Present assets still require successful
selection and camera reset; absent assets require unchanged selection, node count,
yaw and zoom. No test is skipped and no fabricated model substitutes for actual
resource acceptance. That correction still needs the next native run. The private
resource job was skipped on this independent branch; browser dispatch is blocked
by a signed-out GitHub session, so actual-resource coverage is not claimed.
