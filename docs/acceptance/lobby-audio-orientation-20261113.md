# Lobby music / immediate landscape candidate

Base: a0657d3, TestFlight 1.2 (702) source branch. Private unpublished work.

The user confirmed: “进去就是横屏”. Host application stays portrait; the first
actual lobby is landscape. Request landscape before presentation and retain its
lease across all nested game covers. While UIKit has not delivered landscape
geometry, show a dismissible transition, not the portrait showroom. This cannot
promise the OS itself never animates between orientations. Verify visually on
an iPhone, including rotation lock, fast exit/reentry and backgrounding.

702 intentionally had no lobby binding. Use the already hash-verified Temple
Fall clip as an explicitly labelled temporary product fallback. Preserve nil
source binding for Autumn, prefer a future proven lobby track, and leave Palace
battle music untouched. No new audio asset, secret, extraction or public upload.
Absence/corruption must remain silent, not fall back to unrelated audio.

## Collective validation
1. Native compile of full candidate with all private resources.
2. DuelLobbyMusicSelectionTests (3), all DuelMusicTests including ownership
   permission transitions, and DuelLifecycleTests music/readiness coverage.
3. DuelFlowTests lobby entry/exit/reentry, largest accessibility text, local
   practice return, remote room entry/return, and full real-weapon UI flow.
4. Device listening: lobby starts once, battle replaces it, return restores it,
   interrupted/headphone removal behavior respects explicit resume policy.
5. Device visual: no portrait showroom or app tabs, no camera/proportion
   regression, close remains accessible during rotation and restores host.
6. Two-iPhone room handoff/continuous input/result synchronization separately.

Local evidence: 19 music package Python tests pass; diff whitespace check pass.
No Xcode, Swift compiler or decrypted WAV available locally. Native/UI/device
checks above are pending, not successful. No new TestFlight build published.
