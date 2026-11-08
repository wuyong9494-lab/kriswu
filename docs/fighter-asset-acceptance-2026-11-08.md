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
envelope/staging unit tests pass.

## Published assets and native follow-up

All 79 encrypted parts and both manifests are public on the existing branch.
Commit `cb6e2130d9406d938b0b8556cb0c8ac009636e1b` has the exact prepared tree
`0b6517509ea961b4e0645279b26faabdaf40d94d`; existing uploaded objects were reused.
The actual-resource run is
[42458466283](https://github.com/wuyong9494-lab/kriswu/actions/runs/42458466283).
Its secret successfully authenticates and stages every actual asset. Core
checks (785 tests, 16 pre-existing optional/platform skips, zero failures),
device compilation/concurrency gate, and standard native checks (23 unit and
2 UI tests) passed.

The first actual-resource run had 8 failed assertions in 3 of 36 unit test
cases; both of its UI tests passed. The three issues were corrected in
`231b7153582c04e0a6b174b876ec6da0928a4cdd`:

- The older grapple assertion measured the hidden procedural opponent. It now
  measures the visible Sun wrist/head. Sun's captured Hit pose also left the
  wrist beyond Liu's reach; both arms now meet between their shoulders before
  the grip constraint, without changing bone lengths or combat rules. The
  0.10-unit contact limit remains, with a repeated-draw drift assertion added.
- The synchronous source-rig lifetime test checks weak references before
  SceneKit's automatic transaction normally commits at the end of a run-loop
  pass. It now flushes that transaction before its autorelease pool drains;
  both scene and skeleton weak-reference assertions remain. This follows
  [SceneKit's transaction lifecycle](https://developer.apple.com/documentation/scenekit/scntransaction/flush%28%29)
  and passed native revalidation; no delay or relaxed assertion is used.
- Autumn-lobby background meshes reference uniform 32x32 gray lightmaps but
  contain only UV0. The loader rejected the entire scene. Small lightmaps are
  now checked pixel by pixel; uniform images can use UV0 without changing the
  sampled value, while spatial atlases still require UV1. Synthetic rendering
  covers the constant case, and missing-UV rejection uses a nonuniform texture.
  The original encrypted scenery bytes and their integrity checks stay intact.

## Completed native acceptance

Run [42459804189](https://github.com/wuyong9494-lab/kriswu/actions/runs/42459804189)
completed successfully on the exact code commit `231b7153582c04e0a6b174b876ec6da0928a4cdd`.
All five jobs passed:

| Check | Result |
| --- | --- |
| Core regression | 785 tests, 16 existing optional-resource/platform skips, 0 failures |
| Authenticated envelopes and staging | 22 tests, 0 failures |
| Device compilation | Release build succeeded; concurrency-warning gate passed |
| Standard native and UI | 24 unit tests and 2 UI tests, 0 failures |
| Actual Sun/Liu models, scenes and original rigs | 37 unit tests and 2 UI tests, 0 failures; no actual-asset suite skipped |

The previously failing visible-wrist contact, autumn lobby and repeated
original-skeleton release cases all passed. Both UI cases exercised the actual
staged resources, including touch-driven ultimate input, pause/resume, two
damage impacts, both selections, exit and the existing app entries.

The private evidence artifact is `fighter-character-private` (`13609384233`,
68,483,354 bytes), SHA-256
`3722a944160371f29bdd2eb9c3b614d20a65b5e2392dfb68fd7789f2f417f1ee`.
Its ZIP digest and authenticated evidence envelope were verified after download.
The 22 PNG attachments include both autumn-lobby characters, palace selections,
the grapple stages, four source-rig poses and real UI captures. Manual inspection
confirmed the newly loaded autumn backdrop, both full-body lobby models and
the revised captured arm in the hold/UI render. Private images remain outside
the public repository. The source-rig diagnostic lighting is overexposed, and
these captures are not final visual-quality approval.

The fixes changed no ciphertext. The published resource subtrees remain
`0a0a9c51b4ebec684989416f3b12c996939a06f5` (`sf3`) and
`e8cac8ef097d58a506be0821128b637d7fee460f` (`sf3-original`). No duplicate
resource upload or extra workflow dispatch was needed. This final record is
documentation only and does not request another build.

## Remaining scope

At the accepted commit above, the two original-rig action sets were a native
review profile. The subsequent [runtime integration](fighter-original-runtime-2026-11-08.md)
changes the default lobby and combat model and records its separate validation.
Source animation rate, original hero skill
rules/hit timing, full effects and physical-device 60 FPS are not certified by
these loading/pose/lifecycle tests. This workflow does not upload to TestFlight.
