# Distinct katana / dual-hammer native acceptance — 2026-11-09

## Published resource baseline

- Resource commit: `b444d0f0e513875ea2ae929b80d3c7b6c4624ca4`.
- Branch: `codex/fighter-lab-sf3-resources-20261108`.
- All 32 encrypted parts and their manifest are published; 61 packaged files were verified by exact name, byte count and SHA-256. Existing successful blobs were reused.
- Sun uses the Herald katana profile (52 clips); Liu uses the Legion dual-hammer profile (50 clips).
- The decryption key is not part of the repository or app bundle.

## First actual-resource run

[Run 42544941420, attempt 1](https://github.com/wuyong9494-lab/kriswu/actions/runs/42544941420) executed the new assets and exposed failures that the earlier code-only checks could not exercise.

- Core: 825 tests, 809 passed, 16 existing skips, zero failures.
- Envelope: 10 checks passed.
- Device: unsigned Release build and concurrency-warning gate passed. Ordinary deprecation warnings remain; this is not a zero-warning claim.
- Ordinary native: both test bundles compiled, but CoreLocationMigrator exceeded the existing 240-second simulator boot deadline. No tests started in that job.
- Actual-resource character: 65 native cases executed, with 16 assertion/error failures; 3 UI cases executed, with 2 failures. This run is **not accepted**.
- The recorder finalized and retained the failed run's evidence; its presence does not turn failed tests into acceptance.

## Causal fixes prepared from that evidence

### Verified model root declaration

Both exact source GLBs include node 0 (`skeleton`) as a skin joint but declare node 1 (`Armature`, its child) as the skin root. The common ancestor of all joints is node 0; the normal loader correctly rejected the declaration.

Only the two known, byte-verified model hashes opt into an explicit in-memory correction for skin 0, declared node 1 to common ancestor node 0. Default glTF loading stays strict, and the correction itself validates its expected declaration, joint membership, common root and skin index. No encrypted part, model byte, joint order, inverse bind, animation channel or frame changes.

Native regressions retain every source frame and geometry tolerance, check 84/76 retained joints, test actual corrected skinners, and ensure a subsequent ordinary load still rejects the invalid source declaration.

### Original mirrored block effects

The authenticated source effect manifest is intact. Its 21 block tracks legitimately contain negative X scale to represent reflection. Validation now bounds the absolute magnitude while retaining sign, finite-value checks, chronology, sizes and hashes. Rendering hides collapsed axes rather than reflected axes. A real-fixture regression checks the original sampled scale in both directions.

The weapon shader's `sourceTime` starts as Double, matching later updates and avoiding the observed int-to-double uniform warning.

### Ownership observations

Final unrendered trail/particle lifetime probes now drain an explicit Objective-C autorelease pool before the existing weak-reference assertion. The effects owner, scene and container remain alive. Tests additionally require a real node before shutdown and an empty container afterward; ownership assertions are not removed.

### Real-input interruption observation

The failed legacy UI evidence contains two hits and 280 damage. The coordinate-based pause arrived more than five seconds after the ultimate input, beyond the unchanged three-second hold. The test now observes the real hold and uses a real Home event to invoke the production background-pause path before inspecting it. It still requires the frozen hold, one hit/100 damage before resuming, unchanged state across another background cycle, and two hits/280 damage after resuming. The separate flow continues to exercise the pause button.

## Second actual-resource run and resource-owner teardown

[Run 42549436395, attempt 1](https://github.com/wuyong9494-lab/kriswu/actions/runs/42549436395), at `4d7843e5221944199dc3065a6e0c790deb9f525e`, completed 68 actual-resource native cases. Two assertions failed in the same equipped-session teardown case, once per hero: `DuelWeaponGameplayTests.testEquippedSessionsShowRealHitsPauseRestartAndReleaseTheirScenes`, line 191, still observed `DuelWeaponAssets` after shutdown. The other cases passed, including both verified model roots, real weapon contact, source controls, source effects and their scene-node lifetime checks. This is not a passing actual-resource run.

The ordinary native job passed 27 native cases and two legacy UI cases. Its artifact contains procedural characters and no video, so it is not visual acceptance of the new equipped models. The actual-resource UI group subsequently passed all three cases. The recorder reported `recordingComplete=True` and `testExit=0`. Those producer-side results establish completed test/recording steps; playable video and visual quality still require inspection of the actual private evidence.

The session previously held its resource owner in an immutable property; shutdown cleared the owner's character cache but kept the owner itself. A closed SceneKit view can outlive the event and continue holding its session. The focused follow-up now makes that ownership explicit: shutdown releases the character cache and clears the session's `weaponAssets` reference immediately. A terminal session flag makes shutdown idempotent and rejects later resume/restart calls, preventing an already-closed equipped session from rebuilding without its catalog. Normal pause, resume and in-match restart retain their existing behavior.

The native regression now requires the owner to be absent while the session and view are still strongly held, keeps the existing outer weak-reference checks, and checks that resume, restart and input cannot advance a closed session. No waiting period, assertion removal, model bytes, combat timing or damage constants are changed. The game snapshot still owns value-type motion data until the session is released; owner-object release alone is not proof that all CPU/GPU memory has returned to baseline.

## Third actual-resource run — all automated checks passed

[Run 42552805778, attempt 1](https://github.com/wuyong9494-lab/kriswu/actions/runs/42552805778)
tested `ab68cc4653304873378f483b9fa7e53b15a9292f`, including the resource-owner
teardown correction. The complete workflow finished successfully on
2026-11-09 at 11:25:56 China Standard Time (UTC+08:00). All five jobs passed.

- Core: 825 cases, 809 passed, 16 existing skips, zero failures.
- Envelope/staging: all 10 checks passed.
- Unsigned Release device compilation and the concurrency-warning gate passed.
- Ordinary native: all 27 native cases and both legacy UI cases passed.
- Actual-resource native: **all 68 cases passed**, with zero failures, in
  433.645 seconds. This includes the equipped-session resource-owner release
  regression for both heroes.
- Actual-resource UI: **all three cases passed**, with zero failures or skips,
  in 733.614 seconds. The actual-resource native suite also had no skips.

The previously failing equipped-session teardown case passed in 28.842 seconds,
with the stricter checks that retain the session and view while requiring the
resource owner to be released. The actual-resource UI cases were:

| Case | Result | Seconds |
| --- | --- | ---: |
| Both heroes hit, pause, background, exit and preserve existing game entries | Passed | 195.353 |
| Liu's ultimate uses real touch input, pauses and deals two impacts | Passed | 64.596 |
| Both original weapon profiles use source controls and land real hits | Passed | 473.666 |

The character job's 13 stages all completed successfully, including export,
encryption and upload. Its total job duration was 38 minutes 53 seconds; this
includes setup and archiving and is not the same as the summed test durations.
The runtime was the iPhone 17 Pro Max simulator on iOS 26.5 with Xcode 26.6.
The generic iOS device Release job compiled without signing; it did not run on
a physical iPhone. The configured concurrency-warning gate passed, while
existing UIKit deprecation and test/compiler notices remain.

The corrected source commit has passed the automated native and UI checks.
The authenticated recording has now been decoded completely and inspected as
described below. The review confirms the equipped models and basic combat flow,
while identifying remaining presentation defects. Physical-device performance
has not been measured.

## Evidence retrieved and authenticated

The current third run's `fighter-character-private` artifact is **13647397866**,
bound to run `42552805778`, attempt 1, and source commit
`ab68cc4653304873378f483b9fa7e53b15a9292f`. Its successful upload and the
11:20:07.516 China Standard Time recorder report (`recordingComplete=True`,
`testExit=0`) are now supplemented by recovered, authenticated evidence.

The original artifact ZIP exceeds the download connector's 512 MiB limit. A
separate repository operation advanced the branch to
`7349caedd8ae49d33e60e8c10cfb78c9db9130f5` and started the existing
[native evidence recovery run 42556476235](https://github.com/wuyong9494-lab/kriswu/actions/runs/42556476235),
which completed successfully. This continuation read that run and reused its
already-generated artifacts; it did not start a duplicate recovery workflow.

The recovery runner's measured SHA-256 for the original downloaded ZIP matches
the independently read GitHub API digest below. The download log contains no
digest-mismatch warning. The original ZIP was verified at the runner; it was
not reconstructed or hashed locally. The recovery extracted and partitioned
`fighter-evidence.enc`, preserving that complete encrypted envelope.

| Evidence object | Bytes | SHA-256 and verification scope |
| --- | ---: | --- |
| Original artifact ZIP | 1,947,069,816 | `ebc4943e4f11163a033e8b5f4da2026733248f8ecfad59310b834b76187c95aa` — GitHub API metadata matched by the recovery runner's measured download digest |
| Complete `fighter-evidence.enc` | 1,946,401,858 | `852fc28905924e52ef1e52f43dce8e877ccedaaf51b85bfa8ee1c2c62d5b65ba` — locally reassembled, measured and matched to the recovery manifest |

All five downloaded wrapper archives matched their GitHub artifact digests and
contained the same complete manifest. Every extracted part's size, ordering,
offset and SHA-256 matched that manifest. The envelope comprises four parts of
**419,430,400 bytes (400 MiB)** and a final part of **268,680,258 bytes**.
Reassembly preserved the full envelope's byte count and SHA-256 above. The source
metadata in the manifests identifies the successful third run and its exact
source commit; the failed second run's archive was not used for this recovery.

Subsequent private verification authenticated the complete envelope's **HMAC**
and decrypted it successfully. The internal recording provenance identifies
run `42552805778`, attempt 1, and source
`ab68cc4653304873378f483b9fa7e53b15a9292f`; the recovered video bytes also match
the video hash recorded in that provenance. Transport integrity checks, envelope
authentication and decryption are complete. No decryption key was published.

### Recorded pixels and continuous motion reviewed

The actual third-run video `arena-flow.mp4` is **1,567,502,764 bytes**, SHA-256
`8fd3c5d45b374ef98f247223ff2826add72311ae7e4dafd7175707d2fc709477`.
Its video track is H.264, 1320 × 2868, with **30,572 frames** and a 1/600 timebase.
The complete stream decoded successfully with zero decoder output errors when
that source timebase was preserved. Packet DTS values increase strictly and
frame PTS values are unique. Earlier null-output warnings were caused by output
timebase rounding, not corrupt source frames.

The video track lasts **809.688333 seconds (13:29.688)** and uses variable frame
timing. The final image begins at 793.486667 seconds and its source sample remains
on screen for 16.201667 seconds. The source `stts`/`mdhd` tables account for that
last held image; a demuxer's default one-tick packet duration does not. A complete
decode does not mean every second contains new motion, and neither these capture
timings nor a derived playback file establish the game's rendered FPS. The movie
header/edit duration also differs from the video track; media times here refer
to the actual video-track timestamps, not host wall-clock duration.

The fixed portrait recording canvas includes sideways landscape gameplay and
normal portrait selection screens. The landscape review extracts rotate the
recorded pixels 90 degrees counterclockwise. The full-flow review copy preserves
the original canvas orientation. These are views of actual simulator output,
not newly rendered illustrations. The source has no audio stream, so this video
cannot establish audible sound quality or synchronization.

Both original equipped-model control screenshots and time-aligned attack
sequences were inspected. Continuous 10 fps samples cover Sun at 405.8–409.2
seconds and Liu at 630.2–634.0 seconds, with additional original-frame inspection
around Liu's recovery transition. This is a full-stream decode plus targeted
visual inspection, not a claim that a person watched every original frame.

| Observed sequence | Actual recorded result |
| --- | --- |
| Sun Deng, Herald katana | Distinct armor and a visible katana; the weapon and limbs remain attached through the inspected attack. Around 406.9 s the HUD reports a hit for 80 damage; the opponent's health changes to 920 and the cumulative count becomes one hit / 80. Sun returns to idle around 407.8 s. |
| Liu Quanwei, Legion dual hammers | Distinct armor and two visible hammers; the inspected attack produces 105 damage around 631.3 s, opponent health 895, and one hit / 105. Recovery returns to idle around 633.0 s. |
| Source controls | Original joystick and weapon/kick controls are visible. The shadow control remains visibly disabled, consistent with the documented unavailable event semantics. |
| Sun pause/background/return | Paused at 499 s; system home screen at 503.5 s; still paused after returning at 507 s; resumed fight at 510 s; portrait selection at 534 s. |
| Liu pause/background/return | The original XCTest screenshot confirms the pause panel. Video shows system home at 741.7 s, still paused after returning at 745 s, resumed fight at 749 s and portrait selection at 771.8 s. |

The inspected sequences show different weapon geometry, attack poses and impact
feedback for the two profiles. They do not establish full original-engine combat
behavior, pixel-identical rendering or the quality of all 102 source clips.

### Remaining visible defects

- **Liu's recovery-to-idle transition has a visible pose cut.** Adjacent decoded
  source-video frames around 632.9–633.0 seconds change from the recovery pose to
  the forward idle pose without a gradual transition. This is not an artifact
  of 10 fps review sampling. Position does not teleport and no head, limb or
  weapon detachment was observed in that sequence, but the animation handoff
  still needs improvement.
- **Right-side controls partially cover a knocked-down character.** Around
  690.2 seconds, Liu's heavy hit reports 190 damage and knocks Sun down near the
  right edge. The touch-control area overlaps part of the downed body during
  the inspected 690.8–691.9 second interval; the Sun heavy sequence also shows
  this around 448–450 seconds. The active fighter and upper HUD remain visible,
  with no interface failure observed in these samples. They establish an
  overlap, not its frequency in ordinary play.
- **Sun's broad weapon-trail effect obscures the upper body at impact.** The
  effect is visible and follows the attack, but its thickness and opacity need
  aesthetic review; source-resource integrity is not proof of final visual
  quality.

The basic distinct-profile rendering and observed hit/recovery flow are verified.
Final visual polish is **not accepted as complete** while these issues remain.

### Historical recovery proposal

The earlier proposal at commit
`50365db8b3b3fc3f7647c5f8c6a7258fe7738cd8` was never activated. Automatic approval
review rejected its `update_ref` action for missing explicit authorization for
an additional encrypted screenshot/video transfer as split Actions artifacts.
That proposal was distinct from the subsequently observed repository workflow
at `7349caedd8ae49d33e60e8c10cfb78c9db9130f5`. Its prepared workflow is not being
pushed as a second recovery mechanism; the existing successful recovery's
artifacts have already supplied the current evidence. No new native test run
or TestFlight distribution was required for that retrieval.

For historical comparison, the second run's archive was artifact `13646300726`,
1,848,258,593 bytes, with API SHA-256
`64d29d687ba3f449658ab92d157a8e423143bad5ae7b7b5cb762df6152fe945b`,
from run `42549436395` at `4d7843e5221944199dc3065a6e0c790deb9f525e`.
Its earlier browser download attempts did not produce a confirmed local file;
these older metadata do not replace the third run's recovered evidence.

## Remaining acceptance work

- Improve and re-record Liu's recovery-to-idle transition, the right-edge
  knocked-down-character/control overlap and the impact-trail presentation.
  Retain source clips and the existing combat values when evaluating those
  presentation changes.
- Complete iPhone 17 Pro Max physical-device gameplay and sustained-performance
  acceptance separately from simulator automation.
- Validate audible sound behavior with a suitable capture or device observation;
  this silent simulator recording is not audio acceptance.

Original shadow teleport/hammer-throw sequencing and ranged equipment remain
unavailable. Original combat timing, damage and AI are still application
adaptations; this work does not establish full original-engine equivalence or
physical-device 60 FPS. No TestFlight upload is part of this acceptance run.
