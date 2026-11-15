# Liu / Pangu production status — 2026-11-15

## Direct answer

**Liu has not fully become Pangu. The current production character remains
`liu_hammers / isPangu=false`.** Pangu mechanics have substantial source-rule
implementations, but the current character does not activate that profile.
Dedicated assets, complete bindings, remaining source-to-application adaptations,
and end-to-end acceptance are still incomplete.

This is a read-only status review against canonical source
`c522fed95e22c105a7e90caccd81ff9e0e4709a1`, tree
`f1885954bda3fe725d443069ed5669832f5b60fe`. The App tree remains
`440cbf24a285397d34dc3e9ccf84463230d12664`. This report changes neither the
production character nor the release allowlist.

## What the current game activates

| Evidence | Current result |
| --- | --- |
| `DuelWeaponProfile.isPangu` | True only when the profile ID is `liu_pangu`; the production ID is `liu_hammers`. |
| Fight-state construction | `DuelPanguState` is created only when the selected profile has `panguRules`. The current Liu profile does not. |
| H17 assembly contract | Exactly `sun_triad` and `liu_hammers`; `panguAudio` is absent. Liu body is `arm__str_03`, weapon is `wpn__hammers_01_01`. |
| Current motion count | 59 double-hammer/shared clips. This is not a count of 59 Pangu clips. |
| Latest accepted normal iOS simulator frames | Run `43691877506` records `liu_hammers / isPangu=false`, and the original practice frames show Liu using two hammers. These are simulator images, not physical-device evidence. |

Sources: [profile identity](../../Sources/ShiftCore/DuelWeaponMotion.swift),
[fight-state construction](../../Sources/ShiftCore/DuelWeaponFight.swift),
[H17 assembly contract](../../scripts/stage_h17_shared_root_release.py),
[shared-root acceptance](fighter-shared-root-material-run-43647414701.json),
and [normal-frame acceptance](fighter-normal-frame-capture-run-43691877506.json).

## What is already implemented

The existing D19/Pangu code includes level 1–6 Light and shield handling,
combos and cooldowns, directional skills, spear/projectile logic, Heavenfall
phases, wind blades, control and counterthrow behavior, state cleanup, replay
serialization, and input wiring. This is substantive implementation, not an
empty placeholder. It does not establish that the current production Liu uses
these mechanics.

The recovered rules identify the source as
`user-ipa-1.46.1/config-1.46.0.16.16733-prod/D19`, source SHA256
`02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a`.
This is a specific recovered source version, not a claim about the latest
official game's balance.

Sources: [restoration record](../DUEL_SOURCE_RESTORATION_20261114.md),
[Pangu state](../../Sources/ShiftCore/DuelPanguState.swift), and
[runtime profile and adaptations](../../Sources/ShiftCore/DuelPanguRuntimeProfile.swift).

## What still prevents complete activation

| Area | Verified remaining gap |
| --- | --- |
| Dedicated motions | 12 unrecovered aliases refer to 11 distinct source motion files. The 17 recovered aliases / 10 shared motion objects do not replace these missing dedicated motions. |
| Equipment and identity | Five required equipment identity records have no verified input matches: two axe skins, armor, helmet, and the ranged spear. |
| Rendered character | Complete verified model/rig/material/texture bindings remain unfinished. Existing double-hammer assembly cannot be treated as a complete Pangu character. |
| Effects and sound | Complete dedicated trail/effect/audio media and bindings remain unfinished. Diagnostic geometry cannot substitute for original rock, wind, or pillar effects. |
| Source-to-application behavior | The runtime profile still declares application adaptations and unresolved source details, including dedicated motion tails, world geometry/trajectory scales, normalized HP/damage scales, generic ranged recharge, debuff propagation, and shard reaction eligibility. |
| Release acceptance | Full production activation and end-to-end visual, audio, performance, simulator, and physical-device acceptance remain incomplete. |

The input preparation record explicitly retains:
`inputCoverageComplete=false`, `releaseActivationAllowed=false`, and
`productionPanguActivated=false`.

Sources: [motion inventory](../../scripts/pangu_source_motion_inventory_20261114.json),
[identity inventory](../../scripts/pangu_source_identity_20261114.json),
[input-preparation decision](liu-pangu-input-preparation-20261114.json),
[asset-binding boundaries](../fighter-pangu-asset-bindings-20261114.md),
[source-morph bindings](../../App/Services/DuelTriadSourceMorphAssets.swift),
and [diagnostic visual boundaries](../../App/Services/DuelPanguDiagnostics.swift).

## Effect of the newly authorized Android run

Run `43704660391` completed the two authorized Terms input commands once each.
The Terms UI disappeared and a loading frame followed. The same game process
then recorded SIGILL and the next original screenshot showed Android Launcher.
The observation stopped at `app_process_unavailable`; full initialization was
not observed. The one ordinary-shell Configs listing returned `Permission denied`.
Readable files and newly recovered D19 assets both remained **0**.

Consequently this run does not close the asset gaps above and does not change
the production Liu profile. It also does not establish that the official
resources are absent: the ordinary read was denied. The anonymous crash stack
is insufficient to assign a specific module or instruction as the cause.

See the [run review](fighter-android-official-client-run-43704660391.md) and
[structured evidence summary](fighter-android-official-client-run-43704660391.json).
No new Android run was prepared by this review. TestFlight uploads: **0**.
