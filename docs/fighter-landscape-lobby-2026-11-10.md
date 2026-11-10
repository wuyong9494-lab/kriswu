# Landscape fighter lobby

Base: `8af29a2b28f405d1b8769bb49d21a9935e2d69cc` on the existing
`codex/fighter-lab-host-simulation-20261109` branch.

## Change

The horizontal lobby now uses the existing showroom as a continuous background,
rather than cropping it into a rounded card beside a long menu. A compact roster
sits at the left, difficulty/network/help sit at the right, and the center remains
open for rotating and zooming the existing character. Bronze-colored controls
and dark edge shading are authored in SwiftUI; no new art or external assets are
introduced.

Practice, tutorial and versus entry stay in a bottom action rail outside both
scroll views. Changing the character updates its selected accessibility value
and identity label. The same actions and state are reused by a stacked scroll
layout for portrait transitions and accessibility text sizes. The settings
scroll view retains `duel.lobby.actions`; the roster has its own identifier so
network entry tests no longer depend on which scroll view is first.

`DuelHomeView` is extracted into its own file; the following `DuelSetup` and
session/combat implementation in `DuelView.swift` are unchanged. Character
loading, source geometry, materials, lighting, camera, idle sampling, gestures,
showroom teardown, combat rules, network transport, resources, secrets, signing
and release workflows are unchanged. This is a lobby presentation improvement,
not a claim that the character proportions or combat now match another game.

## Regression coverage

The existing ordinary and equipped-character UI flows now check that the stage
spans at least 90% of the window width, all three play actions are hittable
without scrolling, and none is inside the settings scroll view. They also check
selected-state accessibility values and preserve landscape lobby screenshots.
The existing three repeated network-entry dismissals repeat the layout checks.
A new largest-accessibility-text UI case verifies the scrollable fallback,
character switching and practice entry visibility without starting a match.
All original hit, input, pause, background, exit and portrait-return assertions
remain in place.

## Validation boundary

- `git diff --check`: passed locally.
- Existing Python fighter infrastructure tests: 42 passed.
- Fighter network rules generator tests: 16 passed.
- This Linux executor has no Swift compiler, UIKit/SceneKit SDK or Xcode.
  Swift compilation, simulator UI tests and rendered screenshots for this
  candidate have **not** run locally. Python checks do not validate SwiftUI.
- CI run `42736167554` belongs to the unchanged base above, not this candidate.
  Its passing jobs must not be reported as acceptance for this layout change.
- After publication, require fresh exact-commit unsigned device, native/UI and
  actual-resource UI results, then review the landscape screenshots. No release,
  TestFlight upload or physical-device acceptance is included here.

## First native run and accessibility correction

Combined candidate `fc2f677b`, run `42741537580`, compiled successfully for device
and simulator. Core passed 934 cases (16 skipped), native passed 207 cases
(12 skipped), and the largest-text UI case passed. The ordinary landscape UI
cases failed before combat because the `duel.lobby.landscape` identifier on the
transparent ancestor stack propagated onto both scroll views and the three play
buttons, replacing their own identifiers. Exported accessibility trees show the
buttons still visible with their correct labels and 44–50 point heights, but
with the ancestor's identifier. The stage's 956 × 440 frame also confirms the
new full-window background layout.

The correction removes identifiers from the two presentation-only stacks,
keeping the existing identifiers on actual scroll views and play buttons. The
regression helper now explicitly rejects either ancestor identifier appearing
on a button. The accessibility-size test asserts a single scroll view with no
roster side panel instead of depending on an identifier that is no longer used.
The screenshot also exposed a dark unselected segmented-control label inherited
from the surrounding light app theme; only the difficulty picker now receives
the dark color-scheme environment. The user's app theme setting is unchanged.
No original assertion is weakened and no simulation/camera code changes here.
Fresh exact-candidate native/UI acceptance remains required after this fix.
