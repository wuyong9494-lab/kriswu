# Shared original Stun motions: binding and private candidate

## Result and boundary

The three cached original `Stun_In`, `Stun_Loop`, and `Stun_Out` motions now have an implemented catalog capability and an actual private GLB/catalog/release candidate for both current rigs. Sun has 68 clips (65 preserved plus 3); Liu has 62 (59 preserved plus 3). The existing renderer samples these named GLB clips through `DuelWeaponPose`; the morph loader explicitly accepts the new reviewed Liu container only with complete Root-victim and Stun capabilities.

**Liu remains `liu_hammers`, `isPangu == false`, with no `panguRules` and no Pangu audio release binding.** These are common victim motions, not D19 owner actions or equipment. The signed build release pin is unchanged by this change. No native rendering, simulator playback, TestFlight delivery, or original-engine equivalence is claimed here.

Source baseline: canonical `63b8d84b4bfad4ad492e458a16f5ad1f6c68cf15`; this continuation follows local core commits `44d266169b4268a2ac27ab94f98cbb0d80ffe8d3` and `ecc19fc9da454d9c92719960e18e7f34744b231f`. Replay schema/rules versions are managed by the integrating change. This animation binding adds no stored replay fields: existing Action name/role/tick/reaction and the existing Pangu control timer determine its future state.

## Exact original inputs

The existing complete source archive contains `bundles/1b0a132a449bc2947a2a326ff30ff33d.bin`: 2,746,808 bytes, SHA256 `0f94e38b3270548b43d601e00e65dfdcf430d7a06c38e4d6c1eb407102fe5b20`. No resource was downloaded. The bundle was joined to both pinned inventory members before reading only the three exact TextAssets.

| Source setting / file | Path ID | Source frames / half-frame samples | Original TextAsset SHA256 |
|---|---|---|---|
| record87 `Stun_In`, `hits/h_stun_start.bin` | 1063423564692364207 | 31 / 61 | `ea3b5942fd8c7d8721f9b90bfab4c7c03c55a3dd570c4aa9cff12eefd4d9965b` |
| record88 `Stun_Loop`, `hits/h_stun_loop.bin` | 4075479027709813272 | 35 / 69 | `bd1e3f455499a3caf6df7b67d5c5e40c0aff418fa88dd96aab6fd014de879eb3` |
| record89 `Stun_Out`, `hits/h_stun_end.bin` | 3764084586578974847 | 31 / 61 | `5d23977e9369fa15724fe5f0b9e3abdf7393d944182425f734258f14369c1eac` |

All three retain their two original arrays in the private profile. As in the existing motion importer, array0 supplies 58 body-bone transforms; each new GLB animation contains 116 translation/rotation channels. Each rig independently evaluates half-frame local interpolation, its own hands/feet/pelvis, weapon landmarks, source hurt capsules, and Float mass centers. Sun uses its original blade capsules; Liu uses its original skinned hammer vertices. No Sun body tracks are copied onto Liu.

Inventory member pins:

- `research/motion_catalog.json`: 3,008,671 bytes, SHA256 `09829af10b6691124853335a3b8a2821a53c771ffeb4ec0bac97ad8eb6c6fee8`.
- `research/android_bundle_catalog.jsonl`: 9,100,700 bytes, SHA256 `2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055`.
- Source `moves_settings` receipt: source SHA256 `fcdecefdc0ef9cb5bc0a079c6511ccf2a9a352bb29aae8b016113236beac9a6b`, records87/88/89. Source `lock_1548` TextAsset SHA256 `e8a708dd72a900a8d529b73c57887fa01bdaa9b7980de77dbc4f38f7d54a5ef2`, enemy-stun t1/t2/t3/t4.

## Implemented behavior

The optional roles `sourceStunIn`, `sourceStunLoop`, and `sourceStunOut` must all bind the exact source names, bundle, hashes, frame counts, two-ticks-per-frame clock, pelvis/COM sample counts, and 15 hurt capsules. A partial or mismatched declaration fails catalog validation. Older catalogs without these roles retain their established reaction path.

A deferred source Shard control starts `Stun_In` at authored tick0. That sample remains visible on the activation tick. In and Loop follow the recovered `MidFrames=1` / `SelfEndFrame=4` AnimationEnd conditions at ticks52 and60 respectively. The active duration flag chooses Loop or Out at those boundaries; timer expiry alone does not cut a loop short. The source settings' whole-motion `Uninterrupt` retains the original reaction through ordinary damage hits, while health damage and hit-stop still occur. Hit-stop does not advance the source pose or the control timer. Input cannot start a new action during the three source reactions.

X-only `Align(Me.Pivot, foot_l)` uses the new clip's own first foot sample and the existing actor-coordinate convention. Horizontal root displacement and external impact each advance once per live tick. Out retains samples0…60; the subsequent idle recovery is explicitly the arena adapter. Round reset removes the reaction as part of existing Action/control reset.

The original repeated-hit re-entry event order remains unresolved: a Shard re-hit during active source stun currently waits for the existing control and reaction to release. The native action6 → keep/clear interval dispatch order has not been proven for this specific transition. Original generic Out→idle dispatch and cross-animation blending are also outside this binding's verification. The implementation does not label this timing 1:1.

## Derived private release

All media remains private. Public source contains only conversion/staging code, identity metadata, tests, and this record.

| Candidate | Bytes | SHA256 |
|---|---:|---|
| Sun68 `Sun_DeadForestTriad_Ninjato.glb` | 15,721,912 | `9513c85028541fe514f552a5e0d11fd01df277b8cd9f8ddeb832508ff975c699` |
| Liu62 `Liu_Legion_Hammers.glb` | 11,055,648 | `66f8a748efb431bb28bdcd5e4cd91bc2d5d374fd456eb00e843f5d6590a26bfe` |
| `SF3_DistinctFighters.json` | 30,151,732 | `41a63ef6a87f994be75560da10ae3adea881d472ae343eaaaaf7758593d279e8` |
| `SF3_FighterRelease.json` | 34,623 | `53382445ba6867890a67b255e3dd671b6906a9a2ab044e765dd46d5ae3e35c19` |

The base complete release is SHA256 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`. The candidate contains 302 files / 132,513,826 bytes. Nine files change; 293 retain exact original bytes. Both GLBs preserve their complete old BIN prefixes and original nodes, meshes, materials, skins, textures, images, and old animation/accessor/buffer-view records. The catalog appends only the three clips and roles, retaining its later production FK fixes, combo links, rules, and equipment identities. Dependent audio, summon, FX, morph, and trail manifests change only character digests; their source data remains identical before gzip recompression.

Private receipt identities:

- `stun-candidate-receipt-private.json`: 5,488 bytes, SHA256 `eb49bcef70e8923b3aaa5a24866cfb798aee8f70c8340d65f3d27bbc559244d1`.
- `stun-release-receipt-private.json`: 43,280 bytes, SHA256 `7c82dadc14b9e12ee84ecae08bb05154fb1f265c4fe81e0caea96e3d3fcf7cfe`.
- `source-stun-glb-readback-20261115.json`: 1,983 bytes, SHA256 `6f49a4d632b9d3d172b80cce61aad0fa0777526fa459d601ce1d2a22ab1f5a79`.

## Actual targeted verification

Swift6.0.3 on Debian12 was used. No full Swift suite, previous native workflow, original client, or source download was run.

| Check | Actual result |
|---|---|
| Four new `DuelSourceStunMotionTests` behavior/contract methods | Passed, 4 tests / 0 failures, 2.631 seconds; build50.80 seconds |
| One additional method with the actual new private catalog and release | Passed, 1 test / 0 failures, 2.386 seconds; build10.55 seconds |
| Four new `test_cached_stun_binding.py` importer/staging gates | Passed, 4 tests, 0.007 seconds |
| Read-back of all six written GLB animations | Passed: original channel values, own-rig pelvis/hands/feet and root displacement match exactly; 382 samples per landmark across both rigs |
| Modified App morph loader | Swift frontend syntax parse passed; native Metal/SceneKit loading/rendering still pending |

The first private append attempt stopped after generating Sun's GLB because a reused old validator required exactly56→59 animations. That incomplete directory is retained separately. The validator was replaced with an exact three-Stun append check for each independently pinned current count; the fresh v2 candidate succeeded. This importer construction failure is not reported as a combat regression red test.

Commands (private paths supplied locally):

```sh
swift test --jobs 4 --scratch-path "$BUILD" --filter DuelSourceStunMotionTests
SOURCE_STUN_PRIVATE_CANDIDATE="$CANDIDATE/FighterPrivate" swift test --jobs 4 --scratch-path "$BUILD" --filter DuelSourceStunMotionTests.testPrivateStagedCatalogAndReleaseKeepProductionIdentityWhenProvided
python3 -m unittest discover -s scripts -p test_cached_stun_binding.py -v
python3 scripts/verify_cached_stun_candidate.py --candidate "$APPEND" --base "$BASE" --report "$REPORT"
swiftc -frontend -parse App/Services/DuelTriadSourceMorphAssets.swift
```

The first Swift command ran before the private-catalog method was added. Only the added method ran afterward; the four passing methods were not rerun.

Log hashes:

- `source-stun-core-first-20261115.log`: `8dc96b0f68da6dcf3a2358fc717016cac7d3a242ebaf07513bcd3e5743db1d79`.
- `source-stun-private-catalog-20261115.log`: `018755c86922f10406d54a7182a907d051c8d794b8275886dd2cd6a820e88c56`.
- `source-stun-python-20261115.log`: `5ac43ec98e7b8e020b38a5c11547e1eb1240d8ebe0d7c01d88aff87e7b14450d`.
- `source-stun-glb-readback-20261115.log`: `2cbcd3be1bf7273423db9f757d6807abe5615b75aeaa6b61e8634894803bc8ba`.
