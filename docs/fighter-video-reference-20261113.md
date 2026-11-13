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

## Recovered reference and actual frame review, 2026-11-13

The original document above was recovered from commit
`2bef149d52fecb51c3de3c9e04cc84b11a578837`; it was missing from the later integrated
development tree. The original user recording was found again and read-only
decoded: 43.800 seconds, 1112 x 512, H.264 at 30/1 FPS, with AAC audio.
The video, extracted frames, Library identifiers and notifications are not
included in this public repository.

The earlier coarse evidence windows need the following qualifications:

- Frames at 2, 4, 8, 11 and 14 seconds show distinct silhouettes, layered armor
  and clothing, cyan/blue directional weapon effects and short gold contact
  flashes. Bamboo, wooden floor, firelight and depth-separated scenery are
  directly visible; this is a visual observation, not recovery of shader code.
- A denser visual sample at 3.7--4.4 seconds, every 0.1 second, separates cyan
  trails from gold contact bursts. The gold burst is visible in the 3.9 and
  4.0 samples and absent at 4.1; exact original event frames, hit-stop and audio
  latency have not been recovered from these samples.
- 17--19 seconds include repeated/stalled combat poses. Do not calibrate skill
  duration or hit-stop from that apparent hold. At 20 seconds a notification
  covers part of the picture; 22--33 seconds contain loading/system UI.
- 34 seconds contains the next-round overlay. The 35-second frame is useful
  for a new close-range exchange; 37 seconds adds streaming UI and changes the
  framing, and 38 seconds is system notifications. The old 35--38 window is
  therefore not an uninterrupted clean battle sample.
- The shown long-weapon match is not a one-to-one katana/dual-hammer skill
  reference. Use its visual quality as a target while keeping each verified
  equipped hero's own rig, weapon and source clips. Do not copy unrelated skill
  timing or infer source-game damage, contact or cooldown rules from the clip.

The five requested quality goals are explicitly retained as **人物比例、人物质感、
打击质感、技能质感、特效质感**. Their current implementation and missing visual
evidence are tracked in `fighter-visual-fidelity-2026-11-13.md`. None is signed
off by the synthetic regression at `4dd788e3`.
