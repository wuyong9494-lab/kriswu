# Erlang original eye FX: first visible group, 2026-11-15

## Actual change

The normal D15 eye effect now has an independent actor-bone renderer. The
original `D15_Laser_Fx` IntervalStart is frame 62 of record 104, hence live tick
122 with its original default MidFrames value. Source lock 1432 triggers 50
and 53 create the collision model and normal eye effect on that same event.
The adapter observes that actual model's birth once and samples the owner's
original `head` world transform at every fixed simulation step. It copies
position and rotation with body scale removed, following the original local
attachment and Follow XYZ = 111. The collision model's `head.x` anchor is not
used as the visual head position.

The original eye prefab has 19 active emitters. This group binds its 11 mesh
emitters and four standard billboards, producing 247 bounded particle tracks.
Their seven original materials retain exact source shader variants and original
textures. The recovered `geo_spiral_lightning_002` mesh is used by both lightning
emitters. No generated beam, texture or replacement mesh is supplied.

The longest original particle ends at 2.4123234 seconds: the fixed-step effect
expires at age 145. Its last particles continue after the collision model's
source AnimationEnd at age 122. Drawing never advances the clock. Hit stop and
pause hold it; round cleanup clears it. A model first observed after its birth
cannot invent an attachment at an unobserved historical position.

## Bound identities

| Item | SHA-256 |
| --- | --- |
| Original D15 FX bundle | `971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90` |
| Original settings_sets_dynasty | `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701` |
| Original eye motion | `c05c657b4eafdbe0e8785ea5672050fece08d4620d52f76e0bd401f77957645f` |
| Original spiral mesh object | `476d50be9a7fc74eae8ca77ba85d38afa82945e02b98d7bf0ab4d837dd31b48c` |
| Four recovered source texture input receipt | `6d37f512a036582a490ea501d59b4859296859369bdd24fc7d4b0016bbfa605a` |
| Recovered spiral mesh input receipt | `89ed56828338e7acd5c26f1b39c340fe18d7ab2bb1be2a89548dfdd0a650a648` |
| Final 62-clip actor GLB | `debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd` |
| Derived `SF3_D15_SkillEffects.json.gz`, 161,517 bytes | `fc5c49da06415bdefdb294ad78bfbf406b9dab79fcb527ecbd4f9dc926165619` |
| Private source/derivative receipt, 317,101 bytes | `b530c0c151a62c4487200290a7e9721be5bc0e26a4eed835d0bdbc0011689917` |

The manifest lists 26 individually hashed resources, totaling 1,212,813 bytes.
Its character identity and exact original eye track, release and source clip
are verified by the dedicated loader. The private output contains no change to
the actor GLB or gameplay profile. Its raw JSON is 1,657,695 bytes, 3,804 particle
samples and 3,844 serialized mesh vertices, within the existing loader limits.

## Verification actually performed

- Six new pure Swift clock scenarios passed with Swift 6.0.3: one birth,
  independent model/effect endings, no late historical burst, frozen live
  clock, separate owners plus round cleanup, and rejected invalid observations.
- Five actual-source Python methods passed on the initial six-method run:
  emitter scope, both original mesh topologies, tick-122/head binding and
  mutated release/track rejection, particle lifetime/resource bounds, and all
  seven original shader bodies' arithmetic.
- The remaining material test initially read a keyword table from an existing
  reduced shader projection, causing a test-harness `KeyError`. It was corrected
  to inspect the actual original shader object and rerun alone: passed in 2.448
  seconds. The five passing methods were not repeated. This harness error is
  not recorded as a gameplay or renderer regression.
- Four affected App Swift files passed syntax parsing. No Apple SDK typecheck,
  Metal compilation, native GPU frame or pixel-parity result is asserted here.

The clock command compiles `DuelErlangSkillEffectClock.swift` with
`scripts/check_erlang_skill_effect_clock.swift`. Actual-source checks use
`scripts/test_erlang_skill_effects.py` with the prepared candidate, original D15
and shader bundles, source model/rule inputs, material snapshots and mesh receipt.
Private execution logs are `erlang-skill-effect-clock-checks-20261115.log`,
`erlang-skill-fx-source-checks-20261115.log`,
`erlang-skill-fx-material-check-20261115.log`, and
`erlang-skill-fx-app-parse-20261115.log`.

## Deliberate remaining boundaries

Four stretched billboard emitters need their original velocity-facing adapter;
they are inventoried and unbound. The separate ground prefab and mirrored-eye
branch are also unbound. This is explicitly a partial original eye prefab, not
a completed original visual-parity claim. The original material's stale invalid
keyword is retained as provenance and is accepted only because it is absent
from the exact source shader's complete keyword table; it is never activated.

The source effect uses one reproducible realization of original automatic
particle seeds. That does not establish Unity random-sequence or pixel parity.
The existing H17 scope stays the default with its original identity checks.
This group adds a separate opt-in D15 loader scope and small World hooks; the
central release identity and loader installation are integrated separately.
