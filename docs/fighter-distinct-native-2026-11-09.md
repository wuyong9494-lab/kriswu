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

The ordinary native job passed 27 native cases and two legacy UI cases. Its artifact contains procedural characters and no video, so it is not visual acceptance of the new equipped models. The actual-resource UI/recording outcome must be read separately.

The session previously held its resource owner in an immutable property; shutdown cleared the owner's character cache but kept the owner itself. A closed SceneKit view can outlive the event and continue holding its session. The focused follow-up now makes that ownership explicit: shutdown releases the character cache and clears the session's `weaponAssets` reference immediately. A terminal session flag makes shutdown idempotent and rejects later resume/restart calls, preventing an already-closed equipped session from rebuilding without its catalog. Normal pause, resume and in-match restart retain their existing behavior.

The native regression now requires the owner to be absent while the session and view are still strongly held, keeps the existing outer weak-reference checks, and checks that resume, restart and input cannot advance a closed session. No waiting period, assertion removal, model bytes, combat timing or damage constants are changed. The game snapshot still owns value-type motion data until the session is released; owner-object release alone is not proof that all CPU/GPU memory has returned to baseline.

## Required follow-up

Run the updated native and UI suites with the actual encrypted assets, inspect the executed counts and failures, and review fresh rendered/recorded evidence. Until that run finishes successfully, the corrected resources are not declared accepted.

Original shadow teleport/hammer-throw sequencing and ranged equipment remain unavailable. Original combat timing, damage and AI are still application adaptations; this work does not establish full original-engine equivalence or physical-device 60 FPS. No TestFlight upload is part of this acceptance run.
