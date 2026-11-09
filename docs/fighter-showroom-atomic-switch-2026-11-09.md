# Showroom atomic-switch integration — 2026-11-09

Branch: `codex/fighter-lab-sf3-resources-20261108`
Verified parent HEAD before writing: `04c35b2cf5dd43ede521c199832d8ca04d909c44`
Previously completed fighter workflow: [42611635366](https://github.com/wuyong9494-lab/kriswu/actions/runs/42611635366), all five jobs successful.

## Scope and behavior

- Prepare the new actor's verified model, animation sample and SceneKit node before touching the visible actor or the idle clock.
- Apply the same staged handoff to original-rig and full-body fallback models.
- On a missing/invalid profile or failed model decode, keep the old actor, selected hero, yaw, zoom and idle loop untouched.
- On a successful switch, detach the old actor, release its equipped cache, set the new selection and camera, attach the new root and resume its idle clock.
- Shutdown teardown remains in place and must still release scene ownership.

## Regression evidence required

`DuelWeaponAssetTests.testShowroomRejectsMissingProfileWithoutDiscardingCurrentPose` requires the authenticated equipped pack. It verifies that selecting unsupported Gale does not detach Sun or alter its camera/idle frame counter, that a subsequent idle sample still runs, and that selecting Liu detaches Sun and resets yaw/zoom. Existing resource-lifetime, action/impact, source-rig and UI assertions remain unchanged.

The candidate patch was authored earlier against `39f29fd4`; before integration, both affected source/test blobs were compared against that baseline and confirmed identical on the verified parent `04c35b2cf5dd43ede521c199832d8ca04d909c44`. This applies only those two blobs on top of the newer head, retaining subsequent unrelated gameplay/UI changes.

## Acceptance boundary

Only code and regression test integration is claimed until the resulting GitHub Actions workflow completes. Core, device unsigned compile, ordinary native/UI, real-source character/UI and envelope are separate checks. Captured simulator output is not an iPhone 17 Pro Max physical performance or final visual-quality acceptance. Head/neck binding, Liu recovery-to-idle discontinuity, edge control overlap and the attack trail still require visual evaluation.

No encrypted resource bytes, secrets, release triggers, combat damage/animation source clips, main branch or TestFlight distribution are changed here.
