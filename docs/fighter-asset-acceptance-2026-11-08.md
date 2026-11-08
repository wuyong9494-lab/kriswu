# Actual fighter asset acceptance

Continuation base: `cf5aea7cc0189bd6db775ab0116503d593762247` on
`codex/fighter-lab-sf3-resources-20261108`. Its run
[42453935622](https://github.com/wuyong9494-lab/kriswu/actions/runs/42453935622)
passed the code checks, but skipped `character`; it is not actual-asset evidence.

The user's authorization explicitly covers publication of this batch's encrypted
Sun/Liu models, motions and scenes, their filenames, sizes, hashes and test code
to `wuyong9494-lab/kriswu`, and native testing. The previous upload interruption
is recorded in the private checkpoint; this change publishes the complete set.

## Included

- `.github/private/sf3`: 56 authenticated ciphertext parts and a manifest for
  Sun's existing gameplay model, autumn lobby and palace scenery.
- `.github/private/sf3-original`: 23 authenticated ciphertext parts and a
  manifest for both original-rig action sets.
- The existing encrypted Liu gameplay model and repository secret are reused.
  No plaintext model, portrait or key is committed.
- Pushes on the existing personal-fighter branch now run both real-asset suites
  and `DuelOriginalRigAdapterTests`, in addition to the existing native/flow tests.
- Each original-rig actor is created, sampled and discarded three times; both
  its scene and head node must be released after autorelease drainage.
- Private render attachments remain encrypted before artifact upload.

## Local verification

All 79 parts match their manifest byte counts and SHA-256 values. All five
envelopes authenticate and decrypt to exactly the source GLB bytes from version
4 of `ShadowFight3_Personal_Fighters_Integration.zip`. The 22 authenticated
envelope/staging unit tests pass. Native results will be recorded after CI.

## Remaining scope

The two original-rig action sets remain a native review profile. They have not
replaced the existing gameplay rig. Source animation rate, original hero skill
rules/hit timing, full effects and physical-device 60 FPS are not certified by
these loading/pose/lifecycle tests. This workflow does not upload to TestFlight.
