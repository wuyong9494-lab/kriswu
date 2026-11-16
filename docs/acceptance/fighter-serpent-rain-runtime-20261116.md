# D13 bottle entity and ordinary rain/ground continuation

Base: `735a8de3483f47663af1e3a71f873f856c66016a`, existing branch
`codex/fighter-visual-acceptance-20261113-1200`.

`DuelSerpentRainRuntime` now connects the accepted body-action adapter to a
bottle entity, cloud creation acknowledgement, cloud contact callbacks and
lingering ground poison. It is a source-unit integration component. The normal
`DuelWeaponFight` catalog, selection UI and production resource gates remain
unchanged: a partially recovered D13 fighter is not made selectable.

## What is connected

- The body's tick-eight equipped-model request creates the actual recovered
  bottle at motion tick zero. Its original 49 half-frame FK samples drive the
  flight, with source pelvis-X alignment and externally resolved direction and
  parent-repulsion input. It has no Attack intervals and deals no contact damage.
- The bottle's tick-48 AnimationEnd requests the original cloud before deleting
  the bottle. The cloud's X alignment is the current owner's pelvis plus the
  authored 200-source-unit facing offset, not the bottle's landing point.
- A body interruption before release cancels the marker; an interruption after
  release leaves the independent bottle alive. Explicit bottle destruction
  deletes it without synthesizing an AnimationEnd/cloud event.
- The model host must acknowledge the cloud's actual original animation at the
  requested tick. Each later tick requires its current `magic_joint_root` sample.
  Missing, duplicate, stale or invalid inputs reject the whole step unchanged.
  There is no stationary cloud, generic motion or guessed collision fallback.
- Each rain expiration uses the previous random choice, then rerolls at priority
  -10 even when the target is outside the zone or invincible. The original host
  supplies and records f14's 1..4 result; no claim is made about reproducing the
  native RNG algorithm from a substitute generator.
- Zone checks compare target COM-X against cloud root-X ±300, inclusively.
  Y is not a source condition. Cloud callbacks apply the existing four-channel
  state component's invincibility guard. Ground status grants have no such
  trigger condition; downstream ModHP defenses remain the health adapter's job.
- Ground stacks each replace the prior ground-poison status and refresh its
  independent 1200-tick lifetime. Per-tick source damage is
  `0.02 * stacks / 1200 * RaidDamageAmplifier`. The level-eight damage-reduction
  upgrade is not imported into this ordinary level-six path.
- Round exit removes active and pending entities, emits cleanup/audio requests
  once and freezes status damage. It does not guess cross-round store/usage
  reset rules. Already applied poison can outlast a normally expired cloud.
- Replay bytes include action state, full bottle motion binding, entity IDs,
  birth ticks, alignment, flight progress, pending cloud, actual cloud position,
  current random choice and ground status. This is component encoding; the
  existing whole-match network schema has not been changed.

## Original timing contract

Times below are relative to accepted cloud birth, in source live ticks.

| Event | Tick(s) |
| --- | --- |
| Rain starts, initial f14 selection | 0 |
| Rain pulses | 20, 40, …, 580 (29) |
| Ground starts and first status grant | 180 |
| Further ground pulses | 240, 300, …, 1020 (15 including first) |
| Rain ends and sequence sound stops | 600 |
| Ground ends and model deletes | 1080 |
| Last ground poison expires if not refreshed | 2220 |

The schedule removes expired duration variables before evaluating their
same-tick conditions, and processes zero-duration ground start in that tick.
These event-order adaptations are explicit; native event-order parity still
requires the original model and device validation. New statuses begin producing
per-tick ModHP on the next live tick. The return value is source damage before
final defenses/health conversion, not integer application hit points.

## Authenticated resources and checks

`prepare_serpent_rain_runtime.py` reconstructs locks 1400, 1402 and 1403 against
their original binary source and verifies the named animation settings. It
reuses the pinned original bottle GLB and its bone/skin readback before exporting
the 49 FK samples. Existing model/texture/body bytes are unchanged.

| Private generated file | Bytes | SHA-256 |
| --- | ---: | --- |
| SF3_D13_Bottle_Motion_Binding.json | 10036 | `00ac21fb2fa859495b4297f455020f17ccc0c284cf1abd7cd2086b98039bd3e7` |
| serpent-rain-oracle.json | 16673 | `f518c5714d235ea5f3ce2581267edb767de3d0290fa4593d9cd6e1db2ec285ce` |

The binding is a structural gate; the future production loader must also
authenticate its bytes. Its first original motion array uses the existing
reviewed GLB source-coordinate export. Full native mirrored-array/mesh selection
remains a presentation integration requirement, not proved by testing both
world-facing transformations.

Validation on Linux Swift 6.0.3:

- Initial focused regression: 31 Swift tests passed, zero failures/skips,
  including the existing 20 action/state/combo tests and 11 new rain tests.
- Final rain suite after interface review: 13 tests passed, zero failures/skips.
  This includes 168 independently generated source contact cases, exact range
  edges, every channel, immunity, changing cloud position, old-choice/reroll
  ordering, flight, destruction, interruption, pending-resource rejection,
  lifetime/round cleanup, contact guards/perks and deterministic component replay.
- Nine Python tests passed, zero failures/skips: source rain rules, original
  bottle bone/skin data and earlier action-source checks. Mutation checks reject
  changed timer, priority, radius, immunity condition and model bytes.
- The production Swift target compiled successfully. New files emitted no
  warnings; pre-existing unrelated test warnings remain in the initial log.

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts:"$UNITYPY_PATH" \
  python3 scripts/prepare_serpent_rain_runtime.py \
  --source "$RECOVERY_ROOT/continued-20261116/serpent-trigger-source-v1" \
  --named "$RECOVERY_ROOT/continued-20261116/serpent-named-settings-v1/serpent-shuangou-animation-named-v1.json" \
  --bottle "$WORK_PRODUCTS/serpent-bottle-v3" --output "$FRESH_OUTPUT_DIR"
SERPENT_PHYSICAL_PROFILE="$WORK_PRODUCTS/serpent-physical-v1/SF3_Serpent_Physical_Combat_Profile.json" \
SERPENT_BOTTLE_BINDING="$FRESH_OUTPUT_DIR/SF3_D13_Bottle_Motion_Binding.json" \
SERPENT_RAIN_ORACLE="$FRESH_OUTPUT_DIR/serpent-rain-oracle.json" \
  swift test -j 4 --filter DuelSerpentRainRuntimeTests
```

## Remaining integration

The exact `ranged/universal/s_rng_agl_cloud_bullet.bin` loop is still missing
from the authenticated motion catalog. Obtain it and bind the original cloud
model host before acknowledging creation; an unbound request deliberately cannot
advance or inflict cloud damage. Then finish source input guards, native mirror
selection, health conversion, particle/shader/audio resources, the other D13
ability paths and cross-round rules. Complete whole-fight, native and two-device
acceptance before the requested TestFlight delivery. This continuation neither
repeats a heavy native workflow nor uploads TestFlight.
