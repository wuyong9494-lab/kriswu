# D15 sword birth and held-pose recovery — 2026-11-16

## Actual output

One local `recovered-v1` conversion returned exit 0 and emitted the six
original sword birth slots, the original idle state, and the genuine
single-sample rotation state. The result contains eight model states and
seven sampled tracks. It does not add a visible sword substitute or collision
parts to non-attacking held states.

| Document | Bytes | SHA-256 |
| --- | ---: | --- |
| New `d15-sword-held-candidate-private.json` | 935,704 | `d84c455d5f2321980ed136cf15073663ba002f8ba76b8660ce7ce6638e5b8fb2` |
| Actual source model candidate | 666,196 | `25b7efc5cb38d2197ab49fcf58cc255feb8e3d6fa3309a9ab1ab31bb655496d0` |
| Historical held candidate, not reproduced | 909,838 | `22cf4bd31691a19adeaf92b10e745ca452c4f5d31ac390893a742527caf6b55e` |
| Historical model candidate, not substituted | 653,960 | `870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc` |

The new document's `modelCandidateSHA256` and `sourceCandidateReceipt` both
record the actual `25b7ef…` input. Its recovered settings/rule provenance is
retained in `inputRecovery`; it is not labeled with either historical digest.
No existing derived candidate was overwritten.

## Strict separate input path

`prepare_erlang_sword_holds.py` defaults to `--input-format historical`.
The original `CANDIDATE_SHA`, `MOTION_SHA`, `BIRTH_RULE_SHA`, settings pin and
historical `rule()` implementation remain unchanged, including its 100,000-byte
upper bound. No automatic fallback accepts recovered data under an old pin.

The explicit `--input-format recovered-v1 --decoded-splits …` path reuses
`prepare_erlang_model_tracks.model_inputs`. It verifies the fixed recovered
45-record named settings, their native field mapping, all 18 original locks
and 211 complete triggers against the exact original decoded archive and
splits. The source model candidate's entire typed `inputRecovery` must match
that newly verified proof. A different archive, named settings identity,
raw-lock identity or primitive type cannot be mixed into this candidate.

The settings and original-source identity chain is documented in
[the model recovery record](fighter-erlang-model-recovery-input-20261116.md).
This batch consumes those inputs without changing that helper.

The new rule branch uses only the already verified tuples returned by
`model_inputs`, while additionally checking the original birth-rule compact
identities against the unchanged `BIRTH_RULE_SHA`. This matters because the
recovered lock1449 full-field projection is 116,621 bytes: it is accepted only
through its separate fixed identity, not by raising the historical size limit.

The original hovering-sword motion remains 6,182 bytes, SHA-256
`0705dac47e95dee7d66f39c8a2ede4e4774762aa241f79c08e64129119f36632`,
with two 51-frame arrays and source IDs `[400, 402, 401, 403, 404]`. Original
model/XML, configuration indices 110–117, source origin/direction, bone
inventory and lifecycle checks all remain active.

## Preserved source states

| States | Source records | Frames | Last sample tick | AnimationEnd tick | Sampled tracks |
| --- | --- | ---: | ---: | ---: | ---: |
| Birth slots 1–6 | 110–115 | 51 each | 100 | 92 | 6 |
| Rotate | 116 | 1 | 0 | 0 | 0 |
| Idle | 117 | 51 | 100 | 92 | 1 |

Each state retains its seven original declared bones; the motion has five
animated channels and two rest-only weapon bones. Rotate remains one original
pose and is not padded to create a generic sampled track.

Birth AnimationEnd selects Idle rather than deleting the model. Idle keeps
its original `Looped=true` and `Me.Pivot` alignment declaration. The original
rotation/idle priority order 403→402, parent release event, six distinct
source shifts, interval-check ticks and separate sound clock are unchanged.
No new runtime loop-wrap or pursuit behavior is inferred from these poses.

All seven sampled tracks have zero collision edges, zero hurt capsules and
empty attack-part maps. None acquires a synthetic deletion event. The attack
state remains in the separately recovered independent-model candidate.

## Checks actually performed

Five new input checks passed in 0.513 seconds:

- Historical and recovered identity proofs cannot be mixed; the default
  historical model pin rejects the new candidate.
- The source-candidate receipt records the exact new file bytes/hash.
- A changed candidate byte or original-motion byte fails its complete pin.
- Altered archive/settings/raw-lock proof identities and `211`→`211.0` type
  changes fail the complete typed join.
- The nine required recovered rule tuples retain their birth identities,
  while the historical reader still rejects a 100,001-byte file.

The actual conversion executed once, completing in 2.125 seconds. The existing
`test_erlang_sword_holds.py` then accepted the new receipt without modifications
and passed its three source-contract/independent-FK checks in 0.171 seconds.
The independent FK reconstructs original centimeter-space poses at source
frames 0, 23 and 50 for each sampled state, and frame 0 for Rotate: **154
sampled bone matrices** in total. Its existing pose, slot, interval-clock,
single-sample and false-hitbox mutation checks also passed against this new
candidate. There are no held-state capsule endpoints to verify.

An AST comparison confirmed that `settings_record`, historical `rule`,
`window`, `verify_source_contract`, all six historical constant groups and the
entire original pose/track-generation loop were unchanged.

Private evidence identities:

| Evidence | Bytes | SHA-256 |
| --- | ---: | --- |
| New-input checks log | 1,042 | `93603fc34251abda67a5c1bfa1fcbfca4f1a3206f0662721ce86c1e55f3f7748` |
| Single conversion log | 216 | `c36d2113135688405e7fac8e61d718fb9951b21c82632d689f8672f44f7027b7` |
| Existing source/FK readback log | 524 | `dd5613c4378f0148bda2ed00353fd4a992fe377c27ad3739c8bb617ac385fb63` |
| Validation receipt | 3,485 | `62d85a72578483b0d3edcf0d5a5a5920a4ebda069ca3f2554a78624c874d0207` |

## Downstream boundary

This source-only recovery does not change `prepare_erlang_sword_effect.py`,
`extend_erlang_model_runtime_rules.py`, skill/stomp consumers, App/Identity,
the 302-file base or the 440-file candidate gate. Those consumers continue to
require their exact historical model/held pins; any new input support needs
its own reviewed identity. No download, decryption, native/client execution,
protected workflow approval or TestFlight action occurred in this batch.
