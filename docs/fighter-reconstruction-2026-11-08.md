# Interrupted fighter work: local reconstruction

This is a new reconstruction from `95f913d`, not recovery of the unavailable
`3912897` object or proof that its original ten-file patch is identical.
The remote fighter branch was fetched and still pointed to `95f913d` at the
start of this work. No combat rules, damage, grapple duration, other games,
or reminder behavior are changed.

## Changes

- An attack first rendered during its active window now displays the authored
  contact pose immediately, rather than blending it back to the previous idle
  pose. Startup still has its short transition.
- Attack transition keys include the simulation start tick. Consecutive
  instances of the same punch restart independently, including when no idle
  frame is drawn between them. Hit stop freezes both animation tick and attack
  age, keeping that key stable.
- Normal hit stun starts at the Hit clip's impact keyframe (frame 4 of 1–13,
  normalized 0.25), then recovers over the rule's 17-tick hit stun. Block stun
  retains the guard pose. The private backup's authenticated GLB was inspected
  locally in memory to verify the Hit keyframe; neither key nor model is part
  of this patch.
- Initial opening feedback now lasts 75 simulation ticks, as restart feedback
  already did. Previously its zero initial deadline removed it on the first
  tick. This fixes the existing cue; it does not add a countdown or delay input.
- Added core timing/key/reaction regression tests and actual-model native
  checks for first-rendered contact, repeated punches and frozen repeated
  draws, plus a session test for the opening cue and restart.

## Verification status

- PASS: `python3 -m unittest discover -s .github/scripts -p test_fighter_private_model.py`
  (one synthetic envelope test; no real-model native acceptance implied).
- PASS: `git diff --check`.
- PASS: authenticated private backup decrypt and expected model size/SHA-256
  check, performed locally in memory only.
- NOT RUN: `swift test --jobs 2` cannot start: `swift: command not found`.
- NOT RUN: Xcode build, SceneKit/native tests, UI tests and physical-device
  performance/thermal checks. This Linux executor has no Xcode.

No public push, Actions dispatch, secret change, asset upload, or TestFlight
release was performed. The previous native run cannot validate this new patch.
A fresh unsigned native run with the actual authorized asset is still needed.
The historical missing patch's workflow and documentation changes have not
been claimed as recovered.

## Review follow-up

Added a native regression that starts another jab without an intervening idle
render, verifies distinct instance keys and stable keys on consecutive startup
ticks, compares every animated node against the expected three-tick blend,
and repeats frozen draws at each startup tick. This covers transition restart
behavior independently of the existing active-contact checks. Native execution
remains unavailable on this executor; the test has not been run.
