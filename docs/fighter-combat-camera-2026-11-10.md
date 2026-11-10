# Combat framing and confirmed-contact presentation

This patch is based on the unpublished lobby candidate `2c5f9f7`. It changes
combat presentation only. It does not alter source rigs, scale individual body
parts, rewrite source clips, change hitboxes or damage, or claim source-game
timing or physical-device feel equivalence.

## Evidence and changes

- `DuelWorldView.drawState()` previously advanced camera tracking by 12% and
  decayed impact amplitude by 30% on every draw. Repeated captures or a changed
  draw cadence therefore changed the visible tracking/impact duration without
  any new combat step. `DuelCombatCamera` now consumes every published simulation
  step, and drawing only samples its state. Both offline and authoritative
  presentation use the same callback.
- Camera tracking and easing back into close-up use animation ticks, which
  freeze during hit-stop. Directional contact recoil uses simulation frames,
  which continue during hit-stop, and settles around the frozen pose. Repeated
  publication of one frame cannot restart an impulse. Confirmed heavy/light/
  blocked contacts retain distinct strengths; movement and button presses do
  not produce recoil. Reduce Motion still suppresses the visible offset.
- The fit now includes the farthest fighter's distance from the tracked center,
  including tracking lag. It expands immediately and eases back in after the
  fighters close, avoiding abrupt zoom-in after knockback.
- At 3:2 landscape, separation 10 and the old 47-degree FOV cap, the old 7.7-unit
  camera distance gave a 10.044-unit horizontal span. The two roots plus the
  0.8-unit silhouette margin each need 11.6 units. The new perspective
  fit backs away to 8.893 units for that case. Normal wide-phone opening framing
  stays at 31 degrees and 7.7 units, with unchanged source character scale.

This margin protects the root/silhouette envelope; it is not a measurement of
every animated weapon tip or of screen-space clearance from HUD/control art.
Real-source captures remain necessary for visual acceptance.

## Existing skill boundary

The current equipped mode uses the original, distinct katana and dual-hammer
clips for its supported attacks. Shadow attacks remain unavailable because the
source motion contains root/weapon teleport discontinuities without recovered
visibility, projectile and contact events. This patch preserves that guard. It
does not claim that every original skill is restored.

## Validation

- `git diff --check`: passed.
- Synthetic infrastructure checks: 16 network-rules builder tests and 42
  fighter envelope/asset-script tests passed. They do not execute this camera.
- A Python arithmetic cross-check of the projection formula passed for 63
  aspect/separation combinations. This is not Swift or SceneKit execution.
- Added seven core camera-state tests, two projection tests, and three native
  lifecycle tests for redraw/batching, pause/restart and authoritative
  cancellation. Extended the actual-source gameplay acceptance case to assert
  contact recoil, hit-stop framing and reset behavior.
- Swift tests were attempted but did not run: `swift: command not found`.
  This executor also has no Xcode or iOS simulator. Compilation, native tests,
  actual-source screenshots and on-device feel are pending.

Before publishing this as accepted, run the exact candidate's full core/native
pipeline and actual-source `DuelWeaponGameplayTests`. Inspect separated fighters,
both stage edges, jumps and weapon/kick/heavy contacts on narrow and wide
landscape sizes. Keep model proportions and active move silhouettes visible;
compare captures rather than inferring parity from test counts.
