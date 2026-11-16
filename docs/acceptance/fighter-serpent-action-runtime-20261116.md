# D13 ordinary-action runtime continuation

Base: `906601c177e0ed34fcc3c7e2b25402654d040119`, branch
`codex/fighter-visual-acceptance-20261113-1200`.

The recovered Liu/D13 physical profile now has a tested action adapter for
ordinary poison explosion and the level-six bottle. `DuelSerpentActionRuntime`
binds its real body clips, advances the source-unit state component, and returns
typed effect requests. It is not installed into `DuelWeaponFight` or registered
as a complete selectable production fighter. Existing H17 and D15 bindings and
all model/resource bytes are unchanged.

## Bound source timing

| Action | Original body alias | Named release interval | Simulation release tick | AnimationEnd tick | Last sampled tick |
| --- | --- | --- | --- | --- | --- |
| Poison explosion | D13_Poison_Ability | D13_Poison_Apply, Start 84 | 166 | 228 | 236 |
| Bottle | D13_Bottle_Throw | D13_Bottle_Throw_Model, Start 5 | 8 | 104 | 112 |

These are original source playback ticks, not render frame counts. Positive
interval starts use `(Start - 1) * 2`; ordinary sound Frames use `Frame * 2`.
The native AnimationEnd threshold precedes the exported transition tail by
four source frames. The distinct `D13_Deadly_Intoxication_Ability` alias is
rejected by this ordinary-action adapter even though it shares body bytes.

Binding requires the actual 66-clip D13 recovery generation, model size/hash,
body/weapon IDs, role mappings, clip hashes, durations and end thresholds. It
rejects generic shadow/ranged fallback roles. This is a binding check; the
existing resource loader still owns byte authentication and full-catalog gates.

## Runtime behavior

- The source input/equipment evaluator must accept an animation before calling
  `acceptedAnimationStart`. The adapter checks its own availability state and
  accepts each increasing playback ID once. It does not interpret button input.
- Bottle usage is deducted once at accepted StageChange; the original ranged
  input-clear request is returned then. The later marker returns an equipped
  Ranged model request, preserving the source spelling `D13_POSION_BOMB_MODEL`.
  A request is not a spawned mesh, collision or successful hit.
- Poison release reads the old stores for source ModHP damage and the dominant
  poison buff before the priority -5 cleanup triggers. Target invincibility
  suppresses the explosion damage, not the independently guarded buff/cleanup.
- Levels 2–3 clear all four stores and last poison type. Levels 4–5 clear the
  winning store and retain one quarter of each other amount with its own
  remaining lifetime. Level 6 distributes one third of the winning amount to
  each other channel, capped independently, refreshing those lifetimes to 900.
- The original strict maximum and capped/last-type tie rule select the buff.
  Equal non-capped amounts select no buff; upgraded cleanup/cooldown does not
  fire in that case. No arbitrary tie breaker is added.
- Cooldown begins at the actual cleanup event: 960 ticks, or 420 at level five.
  Granted channel buffs have independent 900-tick lifetimes. The adapter exposes
  them; downstream block-break, shadow-impact and other buff consumers remain
  separate integration work.
- Duplicate, backwards or skipped live ticks do nothing. Catch-up must submit
  every authoritative tick and its target state. Rendering cannot consume time.
  Interruption cancels unreleased markers without refunding bottle usage. A
  stale interruption ID cannot cancel a later cast. Round exit cancels pending
  actions; it does not guess cross-round poison or usage reset rules.
- Canonical encoding covers stores, lifetimes, buffs, cooldown, bottle state,
  remaining ranged usages, current tick, playback identity and action progress.
  It is component encoding only; the existing whole-match replay schema is
  unchanged until this component is installed in the fight engine.

## Independent source checks and tests

`check_serpent_action_source.py` authenticates the existing D13 source receipt,
eight original binary locks (1379, 1381, 1389, 1395, 1397, 1398, 1399, 1400),
the original level table, named settings and recovered physical profile. Every
typed trigger field is reconstructed against the binary source. Priority and
trigger index projections are now checked as well as events/conditions/actions.
The restricted oracle evaluator rejects unsupported expressions or conditions.

It derives two body action timelines and 100 explosion transition cases from
the original source, covering levels 2–6, all dominant channels, capped ties,
non-capped ties, empty stores, invincible targets and unequal remaining poison
lifetimes. Expected results do not call the Swift implementation. The prior
64-case arithmetic oracle remains byte-for-byte identical after regeneration.

Final results: **20 Swift tests passed, zero failures, zero skips**, including
nine action-runtime tests, seven state tests, the 64-case arithmetic oracle test
and three existing long-combo tests. The 100 transition cases run within the
action-runtime suite. **Three Python tests passed**, including five deliberate
source/priority/projection corruption variants. No compile warnings were emitted.

Validation commands, with private inputs from the existing recovery checkpoint:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts python3 scripts/check_serpent_action_source.py \
  --source "$RECOVERY_ROOT/continued-20261116/serpent-trigger-source-v1" \
  --profile "$WORK_PRODUCTS/serpent-physical-v1/SF3_Serpent_Physical_Combat_Profile.json" \
  --named "$RECOVERY_ROOT/continued-20261116/serpent-named-settings-v1/serpent-shuangou-animation-named-v1.json" \
  --output "$VALIDATION_DIR/serpent-action-oracle.json"
SERPENT_STATE_ORACLE="$VALIDATION_DIR/serpent-state-oracle.json" \
SERPENT_ACTION_ORACLE="$VALIDATION_DIR/serpent-action-oracle.json" \
SERPENT_PHYSICAL_PROFILE="$WORK_PRODUCTS/serpent-physical-v1/SF3_Serpent_Physical_Combat_Profile.json" \
  swift test -j 4 --filter 'DuelSerpent|DuelLongComboTests'
SERPENT_TRIGGER_SOURCE="$RECOVERY_ROOT/continued-20261116/serpent-trigger-source-v1" \
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts \
  python3 -m unittest scripts/test_serpent_action_source.py -v
```

This validates source arithmetic, action transitions and deterministic component
replay on Linux Swift 6.0.3. It does not establish iOS rendering, native event-order
parity or two-device network acceptance. No heavy native workflow was repeated
and no TestFlight upload was made for this continuation.

## Remaining integration boundary

Next bind the actual equipped bottle motion and its original cloud/ground model
geometry, creation/deletion events, collision and presentation resources. The
complete source input guards, Bloom model, helmet/armor skills, enhanced states,
buff consumers, authoritative health conversion and cross-round rules must also
be connected before registering the full D13 fighter. Maintain the current
identity/resource gates; do not make a partial adapter selectable as a complete
original character. After integration, validate complete fights and the two
iPhone 17 Pro Max devices before the requested TestFlight delivery.
