# Shadow Fight Arena reference: 2026-11-13 user capture

Source: user-provided 43.8 s screen recording, 1112×512, 30 FPS. Reference for visual language only; do not import proprietary footage, art, audio or code into the game. No claim of exact original implementation.

## Evidence windows

| Time (s) | Observed | Verification target |
|---|---|---|
| 02–05 | Blue curved weapon trails, distinct character silhouettes, close-range hit flash | Katana/hammer trails follow sampled tips and terminate at attack end; no stationary glowing arc |
| 08 | Blue aura around airborne fighter and separation between fighters | Shadow activation requires authoritative skill event, not arbitrary button animation |
| 11–14 | Jump, knockdown and bright short hit flash | Preserve root pose and grounded state; contact effects on confirmed hits only |
| 17–20 | Broad cyan slash, grounded crouched follow-through, strong foreground/background contrast | Directional trail, short impact burst, no false teleport sweep |
| 23–32 | Loading and phone system overlays | Exclude from combat comparison |
| 35–38 | Close melee exchange after next round | Test both fighters visible, manual guard, hit feedback and camera stability |

## Acceptance gates (not yet passed)

1. **Katana / Sun Deng:** independent attack animation and verified weapon tip trajectory; shadow attack has separate pose, energy cost, contact window and VFX.
2. **Dual hammers / Liu Quanwei:** independent two-hand trails; user-supplied 333.fbx must be safely converted, rigged and tested before transformation is enabled. Its audio is a preproduced Chinese shout, never iOS TTS.
3. **Effects:** confirmed contact drives impact light and camera shake. Trail discontinuities >0.75 m per simulation tick must not produce long false sweeps.
4. **Camera:** keep both fighters and weapons in frame at typical melee spacing, with HUD controls not obscuring the active combat area.
5. **Performance:** test 60 FPS on iPhone 17 Pro Max with effects enabled; collect frame-time and thermal evidence. Simulator or source review alone does not pass.
6. **Reference comparison:** compare matching action phases from actual game recording and app capture, not cherry-picked static poses. Track character height as fraction of combat viewport and attack effect duration in frames.

## Status

This document is an implementation/QA reference. It is not evidence that any of the above gates passed. The reference recording stays in the conversation and is not committed to the public repository.
