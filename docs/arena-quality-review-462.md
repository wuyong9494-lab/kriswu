# Build462 review and next art iteration

Base:2b3cc7dca4e94e812a7eea3dc16b28fb69cc4ed6, branch codex/arena-quality-sample.

## Original reference recovered

The two previously supplied battle images IMG_3911.jpeg (SHA2566195e3c56cc7a8747766b0f94b5ee6a557b17c358cff1cb88da61c92de54edb9) and IMG_3912.jpeg (SHA256d9eda789237d91b35743c44faeeddcd7a91fe8332f0f1a0e1b7391bd09ec39f5) were retrieved and actually viewed this continuation. They are player-video screenshots with overlays/cropped viewports, not full source videos or precise dimensional references. Original bytes remain in the user's files, not bundled as game assets.

Visible design evidence: continuous upright pointed grass clusters; bright rounded wall cap rims with darker centres and distinctly shaded sides; low-frequency dark ground; character, health and target information remain prominent. The first reference includes bright impact overlap over bodies, so it does not support a claim that original combat is always unobstructed. These are two stills only; exact motion timings, sound and gameplay feel remain unobserved in this turn.

## Duplicate-PTS follow-up

Build460 original traversal was decoded to full-resolution RGB24 without changing the source video. For frame pairs20/21 and291/292, hashes differ. Changed pixel counts529 and12072 out of3785760 respectively; mean absolute channel differences0.00016245 and0.00327429 on the0–255 scale. Differences are small and may include compression effects; they do not prove distinct movement or a frozen render. See evidence/build460-duplicate-pixels.json. Packet timing remains unresolved; no resampling, dropping or retiming of original evidence.

## Prepared wall art

Retain collision cells, rounded lid, cool sides and warm cap. Replace two repeated thin top strips with one shared darker inset panel, retaining the bright cap rim; three child pieces per wall instead of four. This changes only harbor sample rendering. The centre panel is a surface detail, not a newly carved collision recess. Visual appearance and runtime cost require the next actual capture; reduced node count alone is not a performance result.

## Application regression

Build462 application run41017743379 completed successfully: Linux/macOS core, device compilation and arena-look simulator regression passed. Release/TestFlight were skipped. This confirms the grass-bound and normal-bolt test corrections compile and pass the selected suite; it does not prove visual or physical-device acceptance. Sample-capture run41017743617 is tracked separately below.

## Actual menu evidence

Artifact12961000632 from sample run41017743617 downloaded and both hero/map PNGs viewed. Map readiness now720x243.6667 landscape; full map boundary, all six spawns, tab controls and bottom play action are visible. Hero full body, crossbow and play action remain visible. This run recovered presentation; it does not establish the root cause of461's blank frame or all-startup reliability. Right-hand explanatory text scrolls within its own box as designed.

## Actual combat and recording review

Full artifact12960502734 downloaded. Both Twin Gates stills were viewed: generic decorative shot rings are gone; cool wall sides and warm tops separate better. Grass still reads as separated leafy clumps and early impact brightness obscures the ranger; final visual acceptance fails. Proceed with the narrow wall-top panel iteration, retaining current grass bounds and combat rules. Derived combat/map review images plus original sidecar metadata and transform manifest are committed under art/arena-quality-review/2026-10-30/build462.

Opening: local full software decode confirms448 frames, PTS span32.906667s, zero duplicate PTS. Viewed a2-second sampling contact sheet spanning launch/rotation, fighting and long frozen tail; not full real-time playback or audio review, and not32seconds of fighting. Video SHA256441fe912ddb435bda1e69f2425a66c18302861a531adc7a24343603b43513bc0.

Traversal: recorder timed out after90seconds finalizing; local ffprobe rejects the original23MB file with moov atom not found. No traversal success JSON exists; do not claim462 route completion from the success of460. Therefore the sample workflow failed even though application CI and still capture passed.

Next capture change restarts only the dedicated sample simulator before the second (traversal) recording, isolating it from the first recording's encoder/surface session. This is a recovery hypothesis, not a proven root cause. New recording diagnostics persist validated scene evidence before finalization plus separate recorder logs; successful-video JSON still requires normal exit and nonempty output. No timebase repair, remux, broad host-process kill or relaxed success gate.25 Python tests pass, including finalization-timeout evidence preservation and device-specific restart failure propagation. Cloud behavior remains pending.
