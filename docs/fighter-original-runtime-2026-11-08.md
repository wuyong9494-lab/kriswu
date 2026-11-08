# Original-rig runtime integration

Base: `29e944ee0876faf6ca783e4a1968de0252c72292`, following the successful
[asset acceptance](fighter-asset-acceptance-2026-11-08.md). Existing encrypted
files and secrets are reused unchanged. No new model upload is needed.

The default personal-fighter lobby and battle now load the real Sun/Liu
64-node source hierarchies with their personal heads. These are the existing
verified GLBs, with unchanged joint names, skin weights and source clips.
The old 42-bone profile remains an explicit regression target and the fallback
when the original files are absent. A present original file with invalid
integrity cannot silently select the old model.

`DuelOriginalCombatAnimation` maps the app's existing integer rule clock to
source poses. The visual windows below are application-authored, using inspected
limb extension and source frames. They are **not recovered original-game hit
windows or certified combo splice points**. Damage, reach, energy, startup,
active/recovery durations and the three-second Liu hold remain the app's rules.

| App move | Source clip | First / contact / recovery / last source frame (zero based) |
| --- | --- | --- |
| Jab | Jab | 0 / 9 / 11 / 33 |
| Cross | Cross | 15 / 22 / 25 / 52 |
| Finisher | ComboFinish | 27 / 32 / 35 / 55 |
| Heavy | Heavy | 0 / 21 / 24 / 53 |
| Skill 1 | SpinStrike | 0 / 13 / 16 / 47 |
| Skill 2 | Uppercut | 0 / 13 / 16 / 38 |
| Grab startup | BackThrowActive | 0 / 8 / 10 / 10 |

Each contact samples the source pose without startup blending. Transition
buffers reset on a new attack instance and on restart; repeated frozen draws
do not accumulate transformations. Movement distinguishes forward/backward
steps, and jump phase follows the unchanged physics velocity. Actor translation
compensates the clip's vertical pelvis motion so physics lift is not counted
twice; source local joint transforms remain intact.

The app's martial arm lock blends source Guard/BackThrowActive frame 32 for Liu
and Idle/BackThrowPassive frame 51 for the captured fighter. A wrist constraint
rotates the original arm joints without changing their lengths. This is an
application-authored hold using source poses, **not playback of the source
game's complete back throw**. The full paired source clips include a flip and
an inherent passive facing change; directly playing both with ordinary combat
facings would not establish correct contact.

## Verification

The original source-inspection suites remain. Legacy model tests explicitly
select the legacy profile rather than accidentally inspecting a hidden fallback.
New core tests cover visual windows, attack-instance keys, movement direction,
continuous jump phase and unchanged hold damage. New strict native tests require
both original assets and verify default lobby/combat selection, all source bones
at attack contact in both directions, pause/hit stop/restart, jump lift, both
directions of actual-rule wrist contact/grounding/body separation and repeated
asset/scene/skeleton release. Missing real assets cannot pass by skipping.

## Runtime base acceptance

Commit `bb8b7cfb88f27d46f75141a0277d7e7cb28330c8` passed all five jobs in
[run 42463078676](https://github.com/wuyong9494-lab/kriswu/actions/runs/42463078676):
790 core tests (16 existing optional/platform skips), 6 envelope/staging tests,
unsigned Release device compilation and its concurrency gate, 24 standard
native tests plus 2 UI tests, and 42 actual-asset native tests plus 2 UI tests.
All reported zero failures; no actual-asset suite was skipped.

Both original-wrist hold directions passed all 180 hold samples, with worst
gaps 0.00030452127 and 0.00068015594, below the unchanged 0.10 limit. The private
artifact `13611326905` is 78,898,593 bytes, SHA-256
`e2afe4859ad35fa9d1514a30c6146ae232efa5e97a469b3fca74f529b062b0e2`.
Its archive digest and evidence envelope authentication passed. All 37 native
PNGs were preserved privately. Manual review confirmed both personal heads on
the source armored bodies in the actual lobby and touch-driven battle, the
reverse-facing hold and the heavy contact pose. The battlefield remains dark
with strong cyan rim lighting; contact diagnostics are overexposed. This is
functional integration evidence, not final visual polish or continuous-motion
certification.

Review also found a first-draw/restart edge: a second draw at the same tick could
incorrectly enable a transition from the discarded pose. Commit
`8d2844da0b3760b5b978f110bef39ff263304230` records whether a transition was valid
when its key changed and tests both the first sampled walk pose and repeated
draws immediately after restart.

## Resumed validation after the interrupted run

Run [42464779065](https://github.com/wuyong9494-lab/kriswu/actions/runs/42464779065)
tested `8d2844da0b3760b5b978f110bef39ff263304230`. Core regression (790 tests,
16 existing skips, zero failures), the six envelope/staging tests, unsigned
device compilation and standard native checks (24 unit plus 2 UI tests) passed.
The actual-asset job's unit-test step expired after 15 minutes. It spent about
eight minutes compiling before XCTest began; every completed test had passed,
including all five original-runtime tests, but the final personal-asset and
material checks did not finish within that step. Its two UI tests passed.
This run is incomplete actual-asset acceptance, not a successful final result.

The native and actual-asset jobs now build both existing Debug simulator test
bundles with `build-for-testing` in a separate step, then execute the unchanged
test selectors with `test-without-building`. The lifecycle and UI test limits
remain 15 and 10 minutes, and the job remains bounded at 40 minutes. Build and
test failures still propagate through `pipefail`; exported private render
evidence, its authentication and the existing source-asset hashes are retained.
No source ciphertext was uploaded again. Complete validation of this change
and the resulting rendered evidence is pending.

The battle's rear fill now uses neutral white at intensity 180 instead of pure
cyan at 320, addressing the strong colored rim seen in the accepted runtime
captures. The baked environment materials are unchanged: this is a character
lighting adjustment, not a claim to have recovered the original lightmap
decoding or fixed the dark palace background.

The six envelope/staging tests above are distinct from the 16 promotion-gate
tests. An earlier local total of 22 combined those categories; the native
workflow's `envelope` job itself runs six tests.

Source FPS, original skill logic/effects, final art quality and physical-device
performance remain unverified. This branch's workflow is unsigned and does not
upload TestFlight.
