# D15 independent model input recovery — 2026-11-16

## Actual result

The explicitly selected `recovered-v1` input produced all seven original D15
independent model pose/collision tracks in one local conversion. The command
returned exit 0. This is a new source-only candidate identity; it does not
reproduce or replace the historical candidate's byte pin.

| Candidate | Bytes | SHA-256 |
| --- | ---: | --- |
| `d15-model-tracks-candidate-private.json` | 666,196 | `25b7efc5cb38d2197ab49fcf58cc255feb8e3d6fa3309a9ab1ab31bb655496d0` |
| Historical candidate, not available for byte comparison | 653,960 | `870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc` |

The new document records the recovered settings and rule projections, their
original raw sources, and `inputRecovery`. Its differing receipt bytes must
not be accepted under the historical digest. No downstream consumer, App
identity, release catalog, or resource-pack gate was changed.

## Two explicit input identities

`prepare_erlang_model_tracks.py` still defaults to `--input-format historical`.
That path retains the complete historical settings SHA and every `RULE_SHA`
entry. Supplying the recovered settings without the new explicit format fails
the original digest check.

`--input-format recovered-v1` additionally requires `--decoded-splits` and the
two exact recovery receipts beside the named settings and rules. There is no
automatic fallback between the formats.

| Input | Exact SHA-256 |
| --- | --- |
| Historical named settings | `030ca65a96c38e1c335507c2d17c9570716e29510f85305a8e4d905fc179beaa` |
| Recovered 45-record D15 named settings | `259db85e76a7bb4175d3fc037012f0fa53e6c04eb8d9a08ba7b27ea66d6f4bb6` |
| Named-settings recovery receipt | `22541c12e95558c4e1a0a09e4b67ecb817ffde512ad41ea079a285fe0e9acd27` |
| Eighteen-lock recovery receipt | `44aa107032803aa8b4ef93a969cc971165fbe9cd63f81774dc1ee21615401ede` |
| Original decoded splits archive | `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a` |
| Original animation split | `efe3e5d48819adc1106302dacb2b9e94352d5b6735e79a7018a546b19531ab29` |
| Original battle-trigger split | `c3941a009cf87916ba076915b77bf308c33e7a00b9cdbd618bb353b5a6f7651b` |
| Original `settings_sets_dynasty.bytes` | `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701` |

The new input mode verifies all 45 D15 records, original indices 89–133,
against the 295-record original dynasty storage. It reverses the pinned native
method 16684 naming for all 29 animation fields and the complete nested
interval/damage/sound/gender/floor fields: 28/5/4/3/4 fields respectively.
Every primitive type is preserved, including bool versus int and the binary64
bits of source floating-point values.

All 18 original locks and 211 triggers are checked against the pinned decoded
archive. Each raw lock must match its original member CRC, full bytes/hash,
and the separately restored local copy. The pinned projection is then compared
with a fresh typed-storage decode, including all six trigger fields, set name,
set index, trigger index, priority, conditions, events and actions. The eleven
locks used by this converter retain their original creation/deletion semantic
checks. The other seven are verified source inputs, not additional exports.

No rule value is inferred, reduced, or rewritten. The new format does not claim
to restore the lost historical compact JSON serialization.

## Generated tracks and distinct event clocks

| Runtime role suffix | Raw frames | Cropped frames | Last sample tick | AnimationEnd tick | Explicit delete tick | Effective last tick |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `stomp` | 31 | 10 | 18 | 18 | — | 18 |
| `earth` | 68 | 16 | 30 | 22 | — | 22 |
| `eye` | 71 | 66 | 130 | 122 | — | 122 |
| `meditation` | 31 | 31 | 60 | 52 | — | 52 |
| `sword` | 51 | 51 | 100 | 92 | 70 | 70 |
| `judgement` | 92 | 33 | 64 | 64 | — | 64 |
| `aftershock` | 68 | 68 | 134 | 126 | — | 126 |

The original 2,250 mm meditation radius and 42 m Ursus capsule remain intact.
The source 2,000 cm Align shift remains source metadata. The exporter applies
the established source coordinate conversion and extracts horizontal root
motion once; it does not manufacture an actor release offset or damage value.

Five original motion objects were retained beside the candidate:

| Original object | Bytes | SHA-256 |
| --- | ---: | --- |
| `common_model_40_attack` | 3,782 | `3f5c4da828c1524d434b96c5c7ae38e78d5c55eb3562e0c45dcc88e262c7ab3f` |
| `d15_avatara_laser_model` | 8,582 | `a07f8989d863f0dad4ece1e2e6c518a52c3f392dcbc690e1e58d8bc228a337f6` |
| `d15_avatara_ult_swords_model` | 11,102 | `ec953b974583e0e513629d10c825c1d88201fdffc2de71d41008cac9f6a198d9` |
| `d15_hovering_sword` | 6,182 | `0705dac47e95dee7d66f39c8a2ede4e4774762aa241f79c08e64129119f36632` |
| `s_agl_helm_bullet` | 11,494 | `a34115ee04632ca871ead0823ad4acf2ec1884983ee24ac9cd46060c57f40775` |

## Validation actually performed

Six new input checks passed in 0.254 seconds. They cover historical-default
rejection of the new file, unknown/missing format prerequisites before reads,
changed named bytes, the complete actual source join, mutations to otherwise
unused trigger fields/set identity, and full field/type preservation including
bool/int and positive/negative zero. Existing old test suites were not rerun.

The single new conversion completed in 2.087 seconds. Its output was then read
once by the existing independent source-FK verifier: seven models, 2,917 source
matrix samples and 1,086 capsule endpoints passed. The maximum matrix error
was `8.277004916451959e-10` m; the maximum endpoint error was
`1.6000000000035083e-8` m. This verification starts from retained original
motion bytes and source hierarchy in centimeters, independently of the
exporter's converted-local FK.

An AST comparison confirmed that the eight existing input/geometry helpers
and all ten historical constant groups were unchanged. The recovery adapter
only selects separately pinned inputs and records their actual provenance.

Private recovery evidence is stored under the independent 2026-11-16 recovery
directory; no source assets are committed here:

- Input checks log SHA-256: `b004bbc0794d0f25267574f7fbd17022efc24788a56b5f19fbb0f31974e698dd`.
- Conversion log SHA-256: `e5d7799ba8967a30c6c98f1774477f29941c7be9990be30e25658f9ac827c802`.
- Independent readback log SHA-256: `ae29a86722ced9c7b113f6c087fcc099469e34806d128c6162ae3b6b0ae9754b`.
- Validation receipt: 11,359 bytes, SHA-256 `8981578aaad15779f74dc9e6ece99e89d8bb06cf62d3312b8529e7104d3c1e03`.

## Remaining boundary

These seven small original rigs provide model poses and collision inputs.
Their particle/mesh effects are separate resources. They are not a restored
full Wu actor, a restored 302-file base, a complete 440-file candidate, or
native App acceptance. Existing downstream historical candidate pins remain
strict and will require a separately reviewed recovery input identity before
they can consume this new document. No download, decryption, client launch,
protected workflow approval, or TestFlight action was performed for this batch.
