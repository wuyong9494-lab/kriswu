# Pulse engine gameplay

Branch: `codex/star-gameplay-pulse-20261107`.
Source: `a62b36c29a56ad1efd4b38cc991843e7263284f2`.

## Behavior

The journey now offers a fourth ability, 脉冲引擎. It has six tray slots and an energy limit of two. Completing two triples between rail moves charges one free rail move, including the two-energy far fork. Every successful move clears charge, including a move made before charging completes. Rejected actions, previews and wall-clock time do not spend charge. Charge never bypasses gates, collisions, anchors or required arrivals. It resets between chapters; remaining ordinary energy follows the existing carry rule.

This creates a choice between moving early to expose cards and retaining the current rail position long enough to earn free travel under a smaller tray capacity. The board shows charge and actual preview cost; feedback reports charged travel. Existing abilities and frozen classic/rail/expedition catalogs retain their rules.

Charge is reconstructed by replaying committed actions. Undo and save recovery restore it together with energy and rail position. Solver state identity includes charge. The journey save accepts eight ability/route combinations while continuing to accept older records.

## Verification

Initial implementation `697db021d66901e66c62eea6a067770456e44a06`:
- 83 relevant tests passed, zero failures.
- Audit passed all 56 ability/chapter/route/starting-energy boards and eight three-chapter ability/route chains, with three-star solutions and archive round trips.
- Run: https://github.com/wuyong9494-lab/kriswu/actions/runs/42329334474

Final source adds empty-battery and closed-gate boundary coverage and preserves completion feedback when pulse fires. Final rule run: https://github.com/wuyong9494-lab/kriswu/actions/runs/42329690554 — success: 84 tests, zero failures; the full 56-board/eight-chain audit also passed.

The preceding touch/chain run `42327386710` passed native visuals, store recovery and legacy compatibility, and has entered actual interaction tests. This is evidence for its earlier source, not Pulse UI acceptance.

Native UI coverage includes selecting Pulse, charging, previewing, relaunching, and undoing through actual controls. Those assertions have been authored but have not yet passed native execution. Device compilation and native acceptance are separate from the Linux rule results. No TestFlight upload is included in this change. Solvability is not a claim of human difficulty calibration or fun.
