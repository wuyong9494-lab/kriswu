# Recovered D13/D15 runtime bindings and long combos

Continuation base: `520793472a2460f3770630887ab98215ac491469` on
`codex/fighter-visual-acceptance-20261113-1200` in `wuyong9494-lab/kriswu`.
The current requested identities remain Liu / King of Serpents / D13 and
WuYong / Erlang / D15. Pangu is superseded; D14 is a different set.
Sun's existing H17 work was not replaced.

## Executable change

The shared combat interpreter capped combo depth at two transitions, preventing
a five-stage Shuangou chain from reaching stages four and five. It now consumes
the authored acyclic link count, bounded at 128. Catalog validation rejects
ambiguous outgoing links and cycles before simulation starts. Input is still
required at each link; releasing the button does not automatically complete the
chain. Shared-pose collision suppression remains in force.

Replay simulation rules advance from 17 to 18; serialization schema remains 12.
The version is included in canonical state bytes, so the changed behavior is
not presented as the old simulation. Network content generation already hashes
the changed core sources.

## Liu / D13

`recover_serpent_combat_profile.py` appends twelve authenticated common paired,
stun and root-victim animations to the verified 54-clip body. Raw common motion
bytes are sampled against Liu's own 80-bone rig, four hook/handle capsules and
fifteen hurt capsules. D15 collision tracks are not copied. The written GLB
retains its original binary prefix, geometry, skins, materials and all first
54 animations. The supplied personal head remains preserved under the original
Headless helmet policy.

The new 66-clip body passed 69,760 additional readback comparisons with maximum
error `1.1126200361033511e-7` meters. The rig-independent throw contract is
`04ae077c5cfb225ff0e794614bec3c15e2142285e885e45257f1e4c93f0ab79c`.

`bind_serpent_physical_combat.py` joins the original named settings and locks
4993/4996. It resolves destinations by original animation alias and requires
the original zero destination frame shift; it does not guess filenames.

| Chain | Original source-frame anchors | Stages |
| --- | --- | ---: |
| Basic Shuangou | 14, 24, 33, 45 | 5 |
| Low Shuangou | 21 | 2 |
| Shuangou super 1 | 22, 41, 62 | 4 |

The private physical candidate has 24 command/clip rules and 48 original
contact windows. Damage normalization, block damage, hit stop and recoil are
explicit application adapters, not claimed original magnitudes. Generic
`shadow` and `ranged` aliases are withheld; the original skill clips remain
under their D13-specific roles. Poison, Bloom and bottle behavior cannot be
silently supplied by the legacy hammer/shadow interpreter.

## WuYong / D15

`recover_erlang_runtime_profile.py` combines the recovered 62-clip body, hound,
seven original model tracks and six held-sword slots. The result contains:

- 36 source ability attack bindings and 6 release bindings;
- 120 source control intervals and 15 summon motion tracks;
- all six sword birth slots, original idle/rotate behavior, and the earlier
  launched-sword deletion tick 70 rather than its later AnimationEnd tick 92.

The binder rejects absent collision capsules, attack windows beyond the source
model lifetime, late body releases and incomplete sword slots. Existing body
clips, ordinary physical rules, paired policy, geometry and portrait data are
unchanged. The earlier converter's CLI pins stay intact; the recovered input
generation has its own explicit, checked hashes. Running the old and refactored
body-rule transform against the same authenticated inputs produced two
byte-identical output files.

## Private product identities

These are candidates, not an installed or uploaded build.

| Product | Bytes | SHA-256 |
| --- | ---: | --- |
| `Liu_KingOfSerpents_D13_Recovered_Combat.glb` | 15,561,412 | `f25b35dec9bf335bbe01ceee557389f47165c3d0b45b54502017fda394a8bd70` |
| `SF3_Serpent_Recovered_Combat_Profile.json` | 22,201,838 | `2242e07e8768c929b89191cf2d7c95ab51aa3560ef34e998415ece8a3b8561da` |
| `SF3_Serpent_Physical_Combat_Profile.json` | 22,229,744 | `05f5e49993120467a1c2cd5fdcbce3dba0dd3e8a5223b455f50adcfcd5441818` |
| `WuYong_Erlang_D15_Recovered_Combat.glb` | 18,576,776 | `7abc2955e2779c23541d14d51823369ec11d1954c8b3212ca0301834646460b3` |
| `SF3_Erlang_Recovered_Runtime_Profile.json` | 18,924,143 | `bb058e221c6402c3c1562e0c18c2f24970682d73b8052ef372e09c194c7604ff` |

Raw resource products and logs remain private. This commit contains code,
tests, source references and hashes only; it does not publish decryption keys.

## Validation scope

Final expanded run: 314 Swift tests discovered/executed by XCTest, **299
passed, 15 explicitly skipped, zero failures**. The skipped tests require a
complete authenticated opponent catalog which was not staged. They are not
acceptance evidence. All seven private-input Python binding tests passed.
The earlier expanded run's stale field-audit failure and fixture-setup errors
are retained in the private logs, together with the successful follow-up.

The actual recovered D13 and D15 JSON profiles were decoded and checked using
the Swift core. The paired rules accept the other recovered character and use
their own capsule geometry. The D13 physical rules cover every configured combo
stage. D15 source motion/collision rules reject a removed eye track. Python
checks also reject a changed held-sword source, a nonexistent contact capsule,
a post-deletion attack, a late release and a nonzero combo destination shift.

The expanded regression exposed an existing throw-field audit that omitted the
already-encoded `source` property. Its audit now covers that property. Source
test setup is evaluated outside `XCTUnwrap` so a missing fixture retains its
explicit skip status instead of becoming an unexpected assertion failure.
Sword-only checks no longer require an unrelated full opponent catalog. No
contact, timing or geometry assertion was removed.

The new validation uses Swift 6.0.3 on Linux. It is not an iOS build, simulator
rendering, audio, frame-rate or physical-device acceptance result. Prior
[unsigned source compile 43731630399](https://github.com/wuyong9494-lab/kriswu/actions/runs/43731630399)
and [public shader check 43738069528](https://github.com/wuyong9494-lab/kriswu/actions/runs/43738069528)
were inspected and not repeated. Skipped workflow jobs are not passing tests.

## Remaining delivery work

1. Bind D13 poison/Bloom, helmet/armor behavior and bottle/projectile models to
   the recovered level-six source state and exact original conditions.
2. Complete D15 source FX/audio rebinding, original appearance and personal-neck
   integration. Complete the verified opponent catalog for whole-match tests.
3. Assemble the actual release resources, perform one combined iOS/native
   acceptance pass, then verify on the requested iPhone 17 Pro Max devices.
4. Upload TestFlight after both requested characters are complete and validated,
   as authorized. No TestFlight upload occurred in this batch.

The new candidates are not registered as a complete production D13 release.
No identity gate was loosened and no missing original hash was manufactured.
