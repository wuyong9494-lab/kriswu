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

Native results are pending for this code change. Source FPS, original skill
logic/effects, final art quality and physical-device performance remain
unverified. This branch's workflow is unsigned and does not upload TestFlight.
