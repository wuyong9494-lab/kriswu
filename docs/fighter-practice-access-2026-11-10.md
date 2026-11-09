# Original-weapon lobby navigation regression

The actual-source character job in run `42642304518`, on published commit
`601452e`, reached the original-weapon UI case but failed before combat:
`duel.practice` existed and was not hittable after the test's app-wide swipes.
The two legacy UI cases passed. The separate native test process reported
94 tests with zero failures, but its enclosing step timed out during cleanup;
that is not a fully successful native job.

## Cause and scoped change

`DuelHomeView` intentionally stays in landscape. Its actions scroll view is the
rightmost 36% of the available width, capped at 310 points, while the interactive
showroom occupies the app's center. The original-weapon helper swiped the whole
app, so gestures started outside the scroll view that contains the practice
button. The helper then rejected the offscreen button before attempting its tap.

- Give the existing actions scroll view the `duel.lobby.actions` accessibility
  identifier in both layouts. No layout dimensions or controls change.
- Scroll that actual container with the existing bounded four-up/four-down
  gesture budget. Keep the required hittability check and normal button tap.
- Wait for landscape before first lobby interaction, require landscape after
  each match exit, and require portrait only after returning to games home.
  These expectations match the existing landscape ownership and legacy tests.
- Keep a screenshot of each selected hero's landscape lobby, in addition to
  the existing combat, return, and failure evidence.

All source-control, damage, heavy-attack, pause, background, release and retained
game-entry assertions remain intact. No workflow, timeout, simulation, resource,
duty, reminder or notification change is included.

## Validation boundary

This Linux workspace has neither Swift nor Xcode. Static diff checks can run
here, but the change still requires the actual-source `DuelWeaponFlowTests` and
the legacy `DuelFlowTests` on iOS. No native/UI pass or visual acceptance is
claimed by this local change.

Local checks: `git diff --check` passed, and all 27 `test_fighter_*.py`
infrastructure tests passed. Those synthetic-envelope tests do not execute
this SwiftUI navigation or validate the real character assets.
