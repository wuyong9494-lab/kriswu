# D13 source-unit state component

Continuation of `e5cb32ca37d7b577d0ab231074871f5ce665565f` on
`codex/fighter-visual-acceptance-20261113-1200`. Liu remains King of Serpents/D13;
WuYong's D15 resources and Sun's existing H17 implementation are unchanged.

## Implemented behavior

`DuelSerpentState` is an executable, independently tested state component for
source levels 2–6. It is **not yet installed into DuelWeaponFight or registered
as a complete production fighter**.

| Source behavior | Implementation |
| --- | --- |
| Four poison channels | Independent weapon, unarmed, ranged and shadow stores, with independent 900-tick lifetimes. A new contact refreshes only its channel. |
| Channel coefficients | 0.35 for weapon/unarmed/shadow, 0.45 for ranged; original level-three multiplier 1.3. Applicable perk contributions enter before multiplication. |
| Accumulation cap | `0.2 * RaidDamageAmplifier`; `f213` is not maximum health. |
| Continuous poison | Source ModHP magnitude is stored amount / 900 per completed status tick. Accumulation is retained until expiry rather than incorrectly draining the store each tick. |
| Bloom | Incoming source damage multiplies 0.45; outgoing source damage divides by RaidDamageAmplifier before multiplying 0.45. Value clamps at one. Thresholds are exposed without pretending barkskin/life-drain callbacks are already implemented. |
| Source contact guards | Repeated non-first PostHit events cannot accumulate again unless carrying the original invisible-hit exception. Bloom/poison-ability-end magic tags cannot recursively accumulate shadow poison or Bloom. |
| Poison explosion | Four stored amounts multiply 2.75, or 4.5 at level five. Invincible targets receive no projected explosion. Clearing and buff selection remain distinct events. |
| Level-six cloud | Each verified channel callback adds `0.02 * RaidDamageAmplifier`, capped independently. Invincible targets reject the callback. No arbitrary global four-channel pulse is fabricated. |
| Bottle use | Usage is consumed on accepted `D13_Bottle_Throw` animation start; creation happens once at the later release marker. Interruption prevents release and does not refund use. Input eligibility and equipped-model creation still belong to the future adapter. |

`beginRound`/`endRound` control whether source ticks are processed. They do not
guess cross-round reset policy. `resetMatch` explicitly clears all state.
Numeric input bounds are application guards, not original game stats. Returned
damage remains in source units; no implicit integer-health conversion occurs.
Native float/tick-order parity is not claimed by this mathematical projection.

## Source and validation

`check_serpent_state_source.py` verifies the existing source receipt SHA-256
`d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37`.
It authenticates locks 1379, 1384, 1389, 1395, 1397 and 1400 against their original
binary bytes, reconstructs every typed trigger field, and checks that the
readable events/conditions/actions match those originals.

The generator evaluates the selected original arithmetic expressions directly;
it does not calculate expected results using the Swift implementation. Its
restricted evaluator rejects unsupported operations/functions. It produces 64
cases across four channels, levels 2/3/5/6, two raid amplifiers and two damage
values, including consecutive accumulation and caps. The Swift source-oracle
test checks poison amount, lifetime, Bloom, cooldown and explosion against those
independent results.

The final Swift 6.0.3 Linux run passed **11 tests, zero failures and zero skips**:
seven state tests, one 64-case original-source oracle test and the existing three
long-combo tests. This is core validation, not iOS rendering or device testing.
No already-successful heavy workflow was rerun and no TestFlight upload occurred.

Reproduce from the existing private recovery package:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts python3 scripts/check_serpent_state_source.py \
  --source "$RECOVERY_ROOT/continued-20261116/serpent-trigger-source-v1" \
  --output "$VALIDATION_DIR/serpent-state-oracle.json"
SERPENT_STATE_ORACLE="$VALIDATION_DIR/serpent-state-oracle.json" \
  swift test -j 4 --filter 'DuelSerpent|DuelLongComboTests'
```

The oracle output is reproducible intermediate test data. Original source bytes
remain in the existing private recovery package; this commit contains no new
model, source-resource archive, release credential or decryption key.

## Next integration

The subsequent [ordinary-action runtime continuation](fighter-serpent-action-runtime-20261116.md)
binds actual poison/bottle body markers, source cleanup/redistribution, cooldowns
and canonical component replay. Its explicit production integration boundary
remains in force.

Install the action adapter into the fight engine with actual D13 collisions
and equipped bottle/projectile models. Complete the Bloom threshold event
callbacks, barkskin, life drain, overload, helmet/armor skills, enhanced-state
conditions and source appearance/audio. Before activation, connect canonical replay
encoding to whole-match validation for the complete state. Do not bypass the
current full-character identity or resource gates to expose this component.
