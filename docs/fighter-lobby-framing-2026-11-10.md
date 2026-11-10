# Local lobby clearance candidate — 2026-11-10

## Evidence and scope

The real-resource Sun and Liu lobby captures from candidate `8d6fc923`, run
[42746304926, attempt 1](https://github.com/wuyong9494-lab/kriswu/actions/runs/42746304926),
were inspected before editing. In both 2868×1320 frames the dark play rail starts
near y=1008 and covers the forward foot / lower leg and much of the pedestal.
These are actual app captures, not reference mockups. No source capture or asset
is included in this change.

This candidate starts at local `63922050b8003fefac1f7d54335e5b53b269294b`.
It changes only the local lobby's camera composition and its layout measurement,
with focused core/native tests and this note. It does not change character or
weapon geometry, materials, idle clips, combat cameras, input rules, skill logic,
network state, scene ownership, resources, workflows, signing or distribution.

## Composition

- The SceneKit stage remains the same full-screen view, including under safe-area
  chrome. The actual stage frame and transparent central column are measured in
  one SwiftUI coordinate space; the normalized opening is passed to that view.
- Header labels are confined to their existing side columns. The empty central
  column remains available all the way to the top of the stage, rather than
  discarding the area above the roster and making the character unnecessarily
  small. The measured center ends above the play rail, including its layout gap.
- The camera keeps its original 35-degree vertical perspective FOV and viewing
  direction. A pure helper intersects the perspective half-spaces of an authored
  presentation envelope to solve the closest safe camera distance **and** its
  right/up translation. It does not use orthographic scale or force the former
  look-at point to the center of the opening.
- In an independent numerical reference, the 956×440 opening at x=285,
  width=386, height=326 yields distance 6.556 m, versus 5.213 m originally. The
  camera/target translate about 0.578 m down their local up axis, moving the
  composition upward. These are geometric reference results, not rendered
  acceptance or measured character pixel dimensions.
- The lower allowance is a 2.7 m-wide footprint from y=-0.28 to -0.12. The upper
  allowance has ±1.05 m horizontal/depth extent and y=-0.14 to 2.05. These are
  conservative **authored bounds**, not claimed recovered source dimensions.
  Real mesh projection and rendered pedestal inspection must validate them.
  If they prove too loose or too tight, revise the envelope from real evidence,
  not by changing model scale or weakening source-vertex assertions.
- Pinch retains the existing 0.7…1.5 zoom range relative to the fitted distance.
  Explicit zoom-in can intentionally crop the default fit. Rotation and zoom
  survive relayout. Successful hero selection keeps its existing reset behavior;
  rejected selection preserves the current actor and camera. Zero-size layout
  retains the last valid camera. Shutdown still releases the same scene owners.
- The largest-text / stacked fallback and other preview callers do not supply a
  landscape control region and retain their existing camera behavior. Controls
  and their accessibility identifiers stay in place; landscape play actions
  remain outside scroll views. Measurement layers never receive gestures.

## Tests authored, not yet executed natively

Six `DuelLobbyFramingTests` cover phone/tablet and asymmetric openings,
rail-height changes, zoom, deterministic results, rejected transient geometry,
a bound on unnecessary pullback for the screenshot-sized opening, and extreme
but finite viewports whose normalized spans collapse or whose results overflow.
The final camera guard also rejects values outside SceneKit Float range, keeping
the previous valid camera rather than forwarding infinities / NaNs.

Two additions to the existing `DuelLifecycleTests` suite compare every envelope
corner against **SceneKit's own `projectPoint`**, including perspective depth and
UIKit Y-axis expectations, full view dimensions, repeated/zero-size layouts,
gesture-state preservation and shutdown. This guards against an internally
consistent but wrong custom projection assumption.

Two additions to the existing actual-resource `DuelWeaponAssetTests` suite:

1. Evaluate every imported skinned / static mesh vertex using the real bone
   transforms and inverse binds. Check Sun → Liu → Sun, two phone sizes, four
   facings and three idle samples against the clear opening. No missing-asset
   skip or procedural substitute is permitted.
2. Mount the real SwiftUI lobby as a pushed `NavigationStack` destination and
   wait for settled production stage, center and rail preferences. Compare the
   measured stage dimensions exactly with SceneKit bounds, map every normalized
   opening edge back to the measured center/stage, and require the real 10-point
   rail gap plus 8-point fitting margin. Project both the authored body/pedestal
   envelope and the actual selected actor into that navigated opening. This
   catches a missing preference bridge or incorrect navigation-safe-area space
   that broad bounds and injected rectangles would miss. The rail measurement
   is noninteractive and adds no accessibility wrapper.

Existing landscape hit-target, largest-text scrolling, source-weapon, atomic
selection and resource-release suites remain unchanged. No CI was started for
this visual candidate.

## Local checks and remaining acceptance

Passed locally:

- `git diff --check`.
- 16 `test_build_fighter_network_rules.py` tests.
- 42 synthetic `test_fighter_*.py` infrastructure tests.
- An independent Python perspective reference: 112 envelope projections across
  seven openings, plus minimal-distance interval checks. The tightened candidate
  also passes three pathological-finite rejections and one valid large-viewport
  reference case. This does not execute Swift and is not a substitute for the
  authored tests.

Swift and Xcode are unavailable in this workspace. The new Swift tests, SwiftUI
measurement, SceneKit projection convention, actual mesh coverage, rendered
background and pedestal clearance have **not** run on this candidate.

Before accepting the visual correction, run the full core suite, unsigned device
build, `DuelLifecycleTests`, `DuelWeaponAssetTests`, `DuelFlowTests` (including the
largest-text case) and real-source `DuelWeaponFlowTests` on the exact candidate.
Inspect both source lobbies before and after rotation / pinch, return from all
three local play modes and network entry, and repeat after size / Dynamic Type
changes. Require visible head, feet and pedestal at default zoom without a tiny
figure, unchanged source materials, a full background, reachable 44-point play
buttons, and no new retained scene or display-link work. Source screenshots stay
private. No physical-device performance or final visual-parity claim is made. The
authored floor envelope is projected natively, but the source does not expose a
verified pedestal-node identity; no guessed geometry filter is represented as
actual-pedestal mesh coverage.

This is a local-only candidate. No push, release, asset upload or TestFlight action
is part of this change.

## Exact-candidate validation and bounded sweep follow-up

[Run 42770485003](https://github.com/wuyong9494-lab/kriswu/actions/runs/42770485003)
validated published candidate `60ab580e40f344d3fa933529aefbd5a89decb4a4`:

- Core: 940 tests, 16 skipped, zero failures. Ordinary native: 209 tests,
  12 skipped, zero failures; all four ordinary UI cases passed. Unsigned device
  compilation and authenticated-envelope checks passed.
- The actual-resource native log records 257 cases starting and 256 cases
  passing. The new real navigated lobby/stage/rail geometry case passed, as did
  the corrected host-offer fixture readiness case.
- The sole failed case is
  `testRealSourceIdleVerticesRemainAboveRailThroughRotationAndHeroSwitch`.
  It started at 07:07:15 UTC; XCTest later reported an unexpected exit, crash,
  or test timeout and restarted the hosted process. It did not report a clipped
  vertex or another ordinary assertion failure. The enclosing native step
  finished with exit code 65 after 22 minutes 37 seconds, below its 25-minute
  cap. The log does not establish the OS termination reason.
- All five actual-resource UI cases subsequently passed, including both
  equipped characters, real input/hit checks, background/resume, lobby returns
  and portrait restoration. Evidence export and encryption completed. The
  actual-resource job and overall run still failed because of the native case.
  Current private character screenshots have not been visually reviewed here.

The follow-up changes only this test and its mesh-reading helper:

- Read idle timing from the already authenticated catalog instead of loading a
  second, retained copy of each full character just to obtain clip metadata.
  The production lobby still authenticates and loads the actual character.
- Keep each pose, full vertex projection and all assertions inside a synchronous
  autorelease pool, then briefly suspend between samples so the hosted app can
  service its main run loop. No await occurs inside the pool. The off-window
  lobby has no running idle display link, so suspension cannot advance its pose.
- Preserve the six layout snapshots, each with its own temporary-object pool.
  Cache source data/offsets/strides per mesh, rather than repeatedly crossing
  Objective-C-backed data accessors per vertex component. Scoped byte pointers
  never escape. Bone transforms are still recomputed for every pose.
- Preserve all 72 hero/size/facing/idle combinations, every actual skin/static
  vertex, native SceneKit projection, and all original depth/edge assertions.
  Add sample-progress diagnostics and a final 72-sample count assertion.

This addresses identifiable duplicate loading and unbounded synchronous test
work, not a proven crash cause or a production rendering defect. It introduces
no retries, skipped samples, weakened bounds, longer workflow budgets, resource
changes, or production changes. Static review and `git diff --check` pass;
Swift compilation and actual-resource native execution remain required for the
follow-up candidate. Its verification is to be grouped with the next reviewed
integration, not run as a competing workflow.
