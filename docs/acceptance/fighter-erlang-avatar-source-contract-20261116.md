# Erlang Avatar: source selectors and shared-clock state

## Scope

This change adds a standalone Python model of the original Avatar uniform
timing and an authenticated reader for the two original action configurations.
It does not activate an App material, change a release identity, select a
personal head, evaluate combat conditions, or add a native/GPU test input.
The files are `scripts/erlang_avatar_source_state.py` and its focused test.

The evidence is a new bounded read of the restored original Mach-O, metadata,
lock bytes and static geometry. It does not rely on the earlier execution-history
reconstruction as if the lost files were still present. No original application
was executed and no global native method map was rebuilt.

## Original action and renderer contract

The actual dispatcher uses raw selector 167 directly. The table entry at
`0x86b3e38 + 167*2` is `0x05e4`; its target is
`0x6b9e8ec + 0x05e4*4 = 0x6ba007c`. That branch calls constructor 30590
at `0x6f80138`, then consumer 30601 at `0x6f80b0c`. This is an original
dispatch proof, not a guess from a registry ordinal.

All four addition actions in each row below use the **same material**. The
head-prefix step does not select a separate head material and is not an
exclusion or removal action.

| Source trigger | Material variant | Event | Four selectors, in source order | Target `_Transparent` | Duration |
| --- | --- | --- | --- | --- | --- |
| 1432 / t2 | `mtl_Erlang_triplanar_Avatar` | RoundInitialize | type 2; type 1; type 0 + `head_`; type 3 | 1 | source null → direct setter, 0 |
| 1432 / t3 | `mtl_Erlang_triplanar_Avatar_retext` | RoundInitialize | type 2; type 1; type 0 + `head_`; type 3 | 1 | source null → direct setter, 0 |
| 1432 / t26 | normal | IntervalStart `D15_Explosion_FX` | type 2; type 1; type 0 + `head_`; type 3 | 1 | 20 shared logical units |
| 1432 / t27 | retext | IntervalStart `D15_Explosion_FX` | type 2; type 1; type 0 + `head_`; type 3 | 1 | 20 shared logical units |

Types 1, 2 and 3 are the original Helmet, Armor and Weapon values. Type 0
comes from a null MeshType. Consumer 30601 uses method 38345 for a nonzero
equipment type; a missing equipment entry returns an empty enumeration. Type
0 uses iterator 38346 / MoveNext 38420, which walks the original equipment and
base-part renderer collections. Predicate 30606 then reads the renderer's
Unity object name and calls `String.StartsWith` with `head_`. This is not a
substring test, material-name test, bone-name test, or arbitrary GLTF-node walk.

Normal t2/t26 require **not all** four Armor/Helmet/Weapon/Ranged item IDs to
equal 101741. Retext t3/t27 require all four to equal 101741. RoundInitialize
t2/t3 also retain their original form/SRR conditions. The helper authenticates
and fingerprints these conditions; it does not replace them with a form flag.
Retext metadata is recorded to explain the branch, not to claim its shader has
been exported or bound by this normal-material work.

### Addition and removal are distinct operations

Method 35845 reuses a matching existing additional material instance when its
name contains the requested material name. Otherwise it clones the requested
material into an available slot or extends the renderer's shared-material
array. The original base material is retained. Optional configuration
registration occurs before the consumer captures each returned instance's
current `_Transparent` with `Material.GetFloat`.

Normal removal occurs in 1454 / t59 and t61; retext removal occurs in t60 and
t62. All have priority 404 and selectors type 1, type 2, type 0 + `head_`,
type 3. The source action has no AdditionalMaterial, specifies RemoveMaterial,
and has no target value or tween duration. t59/t60 use the original disable
timer plus return/stance conditions. t61/t62 use the original Uninterrupt-end
or stance event and their complete combat conditions. The other FX removal
actions' duration 30 is not a material fade duration.

Method 35844 removes the matching pass and unregisters its optional dynamic
configuration. The selected path does not cancel the already scheduled uniform
job or destroy its captured material object. Therefore detaching a pass from a
renderer must not be treated as the Unity-null test used by callback 30608.
The helper reports removal commands separately; it never invents a reverse
tween, automatic cancellation, or an opacity fade.

## Actual static Wu geometry correspondence

The new static geometry was read back independently: 89 nodes, 8 meshes,
one 80-joint skin, and **zero animations**. Its SHA-256 is
`fe02e7c96d99905e70af712cfd0b52bea1d6d3b732f07eb44bbe5fe6b8182f39`
(10,379,416 bytes). This is not the historical animated actor identity.

| Original selector | New static geometry evidence | Boundaries |
| --- | --- | --- |
| Armor, type 2 | Six `arm__agl_44_m` body/tie meshes; source `ARM_AGL_44`, item 22045, ItemType.ARMOR | Three-dimensional source geometry and original material provenance are present; no Avatar pass is installed |
| Weapon, type 3 | `wpn__agl_spear_01_01__l`; source `WPN_IMPERIAL_SPEAR_01_01`, item 21056, ItemType.WEAPON | One displayed original spear; no second visible weapon is inferred |
| Helmet, type 1 | No helmet mesh in this candidate | An empty selector is not an instruction to substitute the portrait |
| Type 0 + `head_` | Zero matching render nodes | The portrait is named `WuYong_Personal_Head`, has no skin, and is rigidly parented to the original `head` bone |

The two equipment classifications were checked against the exact original
`scripts/features/items/entities/items.js` and `scripts/common/enums.js`, not
deduced solely from name prefixes. The static portrait retains the delivered
59,878 vertices and its original attributes/images under the separate geometry
receipt. This candidate has no generated neck bridge.

Zero `head_` matches is a faithful observation about this adapted geometry,
not proof that renaming it would reproduce original selection. A future
personal-head treatment requires an explicit application adaptation: which
personal geometry receives the same additional pass, which original vertex
inputs it supplies, and how that treatment preserves the user's face. The
existing H17 victory-morph classification of personal geometry as actor base
does not establish that Avatar mapping.

## Shared logical-clock timeline

For a timed job, native start method 35947 records `start = trunc(Float32(clock))`
and `end = start + duration`. Enqueue 35905 starts the job and adds it to a
queue; it does **not** invoke an initial progress-zero uniform write.

Update 35946 skips both the write and completion when either of the two
original pause flags is set. Otherwise it uses the observed integer clock:

```
progress = clamp01(1 - Float32(end - trunc(clock)) / Float32(end - start))
value = captured + (target - captured) * progress
```

Callback 30608 preserves separate Float32 subtraction, multiplication and
addition. It clamps progress, not the target value. Destroyed Unity material
instances are skipped. The callback runs before `trunc(clock) >= end` reports
completion. An unchanged integer clock does not suppress a subsequent
unpaused callback.

Scheduler constructor 35912 registers update 35915 with the shared clock's
callback. Clock advance 35977 adds its current increment before invoking that
delegate when unpaused. If another job is enqueued during an update callback,
35905 puts it in the pending list, so it cannot run in the current traversal.

An independent, separately authorized read of three exact functions (1,744
code bytes) closed the previously unproved tail cleanup. The order in this
particular normal callback path is:

1. Keep incomplete jobs in a separate survivor list; report completed jobs.
2. After traversal, append pending jobs to active and clear pending.
3. Tail `0x70c34b0` clears active, copies only survivors back, and clears the
   survivor list.

Thus completed jobs are removed. A new pending job created during the callback
is also discarded by that tail; it is **not** retained for the next pass. The
collection wrapper `0x4994230` and implementation `0x49954f4` were read to
verify that the intervening operation really is append/AddRange. These are
three distinct original lists, not aliases.

The helper follows that order and reports `discarded_pending_job_ids` alongside
uniform writes and completed IDs. It does not silently promise deferred
execution, repair the original queue, or cancel an older incomplete job merely
because a newly enqueued one targets the same material. This observation is
limited to the selected queue path: it is not a claim about all original-game
schedulers or proof that an Avatar `Material.SetFloat` callback actually
enqueues another job in game execution.

The helper therefore takes an explicit shared-clock observation for every
enqueue and update, plus explicit captured values and material liveness.
It never derives the clock from a call count, display frame, 60 Hz assumption,
source animation frame or cast phase. The absolute first callback's game-frame
phase relative to the source action dispatcher remains outside this model.
Nested scheduler updates and exceptional callback recovery are not established
by this narrow proof; the helper rejects them and prevents retrying a partially
delivered callback pass as if it had emitted no writes.

### The actual fresh normal case is 1 → 1

The authenticated original normal material stores `_Transparent = 1`. Both
normal addition configurations target 1. For a newly cloned instance whose
captured value remains 1, the 20-unit interpolation is constant 1. A caller
must still supply the actual captured value: reused instances are not reset to
a guessed start value by this model.

The optional configuration chain was narrowed to its type-0 factory and
`neck` source-bone binding. Its constructor registers an updater; its observed
update uses `Material.SetVector`, not `SetFloat`. No 0-valued `_Transparent`
initializer was found there. The exact optional provider entry/property for
this particular material was not separately recovered, so it is not assumed.

As established by the selected normal GLSL, `_Transparent` scales the colored
contribution. The background term remains and final alpha is 1 under the
current nonnegative source texture inputs, even when `_Transparent` is 0.
Neither the helper nor a future binding may replace this with SceneKit node
opacity, generic alpha fading, or the existing H17 victory-morph effect.

## Inputs and new validation

| Input | SHA-256 |
| --- | --- |
| Original Mach-O | `7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b` |
| Original metadata | `12d52d278c904b210541e7c337025c68454e2b89a83eddab51f9c74fcc5a245c` |
| Original `lock_1432.bytes` | `74917b81d2e8e0bae60123a7bb2a42f15d7ce4dc9f90f57a62c787c66dc4dde7` |
| Original `lock_1454.bytes` | `0bf4ae016ff582b8dc8e4753cd94aca3cd98027c03151820b575dff2b83d605d` |
| Original normal Material object | `a0fa93408bb0cc520ec64cb8b77d460c8562837dc808198a9e7f072bf3729cbc` |
| New bounded proof receipt | `5244c221c16aa59766bceb54ac5b866d44a2a21316a80dbd878c9d86ec551d57` |
| Independent three-function tail proof | `d109cfcff1d418e482ce9a1792cd844df22da5805f4f65ae0a65eea9fce18263` |

The two restored field-view digests are pinned independently inside the helper;
they are not substituted for the old compact-file digests. The private proof
contains the bounded native snippets, exact original conditions/actions,
selected Unity API pointer cross-check, static-node readback and source-item
classification hashes. No original resource body or derived shader is added
to Git by this change. The earlier receipt is retained as an evidence snapshot;
its assertion that pending entries first run in a later pass is superseded by
the independent tail proof and the explicit correction receipt.

Eight targeted checks cover the actual original selector branches and
separate removal, changed-source refusal, actual material 1 → 1/direct entry,
nonzero clock with delayed first callback and truncation, reentrant enqueue,
both pause flags/liveness/write-before-completion, simultaneous completion and
pending discard, and unsupported input or nested-update refusal.
The first invocation passed the four timing checks but found that the loader
compared the original integer `sourceLock` with a string. After correcting that
type comparison, only the three affected original-input checks were run again;
all three passed with no skips in 0.023 seconds. Independent native review then
identified the earlier reentrant test's incorrect next-pass expectation. The
three methods affected by tail cleanup were selected for correction and
regression; the already passed original-input group was not repeated.
All three passed with no skips (unittest reported 0.000 seconds). All eight
current methods are covered across these scoped invocations. This is no
native, Apple or GPU pass.

```sh
ERLANG_AVATAR_SOURCE_DIR=/private/restored-trigger-fields \
ERLANG_AVATAR_MATERIAL_DIR=/private/avatar-normal-source-candidate \
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts \
python3 -m unittest discover -s scripts \
  -p test_erlang_avatar_source_state.py -v
```

Without the two explicit private input directories, the three original-input
checks are marked skipped. They cannot be counted as original-source passes.
The prior six source-material export checks are not rerun by this command.
