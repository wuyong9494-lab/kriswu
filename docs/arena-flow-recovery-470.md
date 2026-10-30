# Build 470 evidence and continuation

Source `359a63e21bad542d0fecf22bc7d1834e248d0963` ran the repairs from 469.

- iOS: https://github.com/wuyong9494-lab/kriswu/actions/runs/41052098798
- Sample/three-hero: https://github.com/wuyong9494-lab/kriswu/actions/runs/41052098772
- Promotion: https://github.com/wuyong9494-lab/kriswu/actions/runs/41052248626

The sample workflow failed. Do not upload 470. Builds 468 and 469 remain excluded.
Linux core tests, arena-look and the device build passed; the separately named
lobby-runtime step was skipped. The promotion failed at required sample validation,
so its upload and Apple-status jobs were skipped. The latest independently confirmed
uploaded version remains 1.2 (425), with Apple VALID / internal IN_BETA_TESTING in
promotion run 40909383570. This is historical processing evidence, not a fresh
check of current tester availability.

## Verified repairs

Ranger's real UI flow and continuous original recording validation passed. The
original scene contains ten player attacks, one earned super and a natural result
at simulation time 90.0333. The UI test returned to the lobby. Diagnostic artifact
12974899011 was downloaded; lobby, detail and returned-lobby screenshots were
actually viewed. Blue/yellow button faces, their text and the close icon render.
The original video evidence remains in artifact 12975004134.

Vendor/audio artifact 12975268078 and job logs show all five audio tests passed,
including real PCM rendering and pause/queue behavior. Bundled file loading, axe
attachment, cargo bounds and actual SwiftUI button/icon pixel rendering passed.
The nature-border test failed: zero generated children, expected ten.

## Remaining failures and repairs

The three Kenney nature files declare scene root node 1 while retaining an unused
`tmpParent` node 0 that references node 1. The loader built the global parent
relationship, then omitted the declared scene root because it already had a parent.
Parsing succeeded but the instantiated scene had no attached geometry. Honor the
selected scene roots when constructing parent relationships. The existing border
count/bounds test remains; all imported props now also require actual attached
mesh vertices, rather than only a nonnil parsed model.

Mage diagnostics 12975433363 contain ten attacks, zero damage, three deaths and
natural result at 120.6 simulation seconds. Barbarian diagnostics 12976680326
contain ten attacks, zero damage, three deaths and natural result at 110.4167.
Both fail the unchanged earned-super assertion. Their read-only control traces
show repeated respawns while following the exposed x=11 approach; neither reached
a target in range at an observation point. Their recorders completed normally,
but their failed gameplay is not certified as a successful flow.

The next UI driver uses the shorter x=7 covered lane, full normal stick travel
and holds of at most five seconds to avoid repeated pauses and out-of-range fire.
It checks actual target reachability before combat, reobserves after movement,
and approaches the objective once clear of the southern walls. This changes only
real touch input, not game speed, health, AI, ammo, charge or match outcome. All
real attack, earned super, natural result, returned-lobby and video checks remain.

## Recovered continuation checks

The interrupted files were recovered from the previous working directory and
reviewed against remote source `359a63e`. Static inspection of all 33 bundled
GLTF/GLB models shows that the scene-root fix only changes the three nature props:
each changes from zero attached meshes to one. The 11 skinned model hierarchies
remain unchanged, with all joints reachable. See
[the model-root audit](evidence/model-roots-recovery-470.json).

Independent geometry sampling checked 5,249 positions using the actual Twin Gates
wall cells and fighter radius 0.42. The covered approach, spawn alignment and
objective entrance remained collision-free with the driver's position tolerances;
the minimum body-to-wall clearance was 0.23 tiles. A core regression now checks
those corridor bounds and its grass cells against the real map implementation.
This does not establish that the player survives or earns a super at runtime.

43 capture/evidence Python tests, two GLTF contract tests, both ranger asset audits,
and all 11 packs / 28 runtime file source-hash checks passed locally. Swift/Xcode
are unavailable in this recovery environment. The recovered source still needs
its own device build, core/animation tests, vendor scene/audio tests, three real
hero flows and complete media checks before promotion.

Sample recordings were skipped after the vendor test failure. The previous
traversal-finalization hypothesis is therefore still unverified. No physical-
device FPS, thermal, full audio listening or final visual acceptance claim.

Promote only the next exact source/build/run combination after every required
validation passes. Do not reuse the failed 470 manifest.
