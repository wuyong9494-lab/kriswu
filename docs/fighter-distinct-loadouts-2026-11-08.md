# Two independently equipped fighters — 2026-11-08

The user authorized choosing two different original characters. The previously
accepted Sun and Liu exports shared the Dynasty `arm__agl_10` body and unarmed
actions. This update gives each personal head its own original body, weapons,
bone hierarchy and complete source animation clips. These are verified equipment
profiles, not a claim to have recovered the complete identities of story bosses.

| Personal identity | Original profile | Body | Weapon | Bones | Clips | Original frames |
| --- | --- | --- | --- | ---: | ---: | ---: |
| Sun Deng / ember | Herald katana | arm__prc_02 | wpn__katana_01_01 | 84 | 52 | 2,695 |
| Liu Quanwei / liu | Legion dual hammers | arm__str_03 | wpn__hammers_01_01 | 76 | 50 | 2,542 |

Sun has one source left-hand katana and its left sheath. Liu has two separately
skinned hammers. The accepted personal head and neck meshes remain unchanged.
The catalog records original raw clip bytes, bone paths, weapon vertices,
provenance, and 10,372 half-frame kinematic samples. Native pose sampling retains
source pelvis height; horizontal root displacement drives movement exactly once.

## Input and combat

The new default mode uses seven original control images, the original four-button
arrangement and an eight-way joystick. Direction plus weapon/kick selects a clip
from the selected fighter's own profile. Neutral weapon hold selects heavy attack.
Releasing, dragging out, cancellation, pausing, backgrounding and leaving the
screen clear their own input state. Neutral standing guards automatically.

The new engine resolves actual swept weapon segments or foot trajectories against
native hurtboxes. Source-aligned combo anchors continue the longer clips at their
shared frame instead of replaying the first strike. Source root motion also drives
walking, preventing the previous unrelated movement speed from sliding the feet.

Original weapon, hit, block and kick sounds are selected by attack type. Verified
source particles and curves drive hit/block feedback. Weapon trail materials use
the source textures and sampled weapon endpoints. Pause, hit stop, restart and
shutdown share the simulation clock and release their audio and scene resources.

The legacy mode remains an explicit regression path (`-duel-legacy-controls`).
Once the distinct catalog is present, a missing or invalid source resource stops
that mode; it cannot silently become the earlier common-body implementation.

## Deliberate limits

The installation resources contain models, animations, effects and compiled
program data, not a complete compilable original combat project. The 30 FPS
preview rate, input hold threshold, attack windows, damage, AI and hurtboxes are
documented application adaptations. They are not recovered original combat rules.
The SceneKit material and ribbon renderers are also adaptations, not proof of
pixel-identical original Unity rendering.

Both shadow inputs are disabled while their original resources remain preserved.
Katana shadow root motion jumps 8.4594 m in one half-frame; a thrown hammer vertex
jumps 7.7835 m. Treating those discontinuities as ordinary swept attacks would
create false hits. Original teleport, projectile, weapon visibility and contact
events must be recovered before these two skills can be enabled. Ranged attacks
are not equipped. The visible disabled controls do not consume energy or queue
hidden attacks. No borrowed Dynasty move fills a missing role.

## Integrity and publication

Only authenticated encrypted chunks and public integrity metadata are committed.
The existing authorized key is consumed in memory and is never published.

Published resource baseline: commit
`b444d0f0e513875ea2ae929b80d3c7b6c4624ca4` on
`codex/fighter-lab-sf3-resources-20261108` contains all **32/32 encrypted
parts** and their manifest. All 61 packaged files were verified by exact name,
byte count and SHA-256; existing successful blobs were reused. This resource
batch has no remaining parts to upload. Publication does not itself establish
native, visual or physical-device acceptance. The subsequent executed results,
runtime corrections and outstanding acceptance gates are recorded in
[the 2026-11-09 native acceptance log](fighter-distinct-native-2026-11-09.md).

Historical publication pause on 2026-11-08: automatic approval rejected a later
resource chunk after the earlier authorization was recovered and a recheck
succeeded. Uploads paused with nine unreferenced encrypted blob receipts and no
asset-branch update at that point. The published resource baseline above
supersedes that state. At the time, the separate
`codex/fighter-lab-distinct-code-20261108` branch validated code without this
batch's encrypted parts; that code-only CI did not validate the new private
models.

| Resource | Bytes | SHA-256 |
| --- | ---: | --- |
| Sun_Herald_Katana.glb | 11,147,772 | 5a1a64c9986b0d5284a7986efc1589dbfc1f00f91ac9477cdae45930612ac553 |
| Liu_Legion_Hammers.glb | 9,577,896 | 9ff998118a69b1d089694e97b2623cf6d6fb81e64451a8462dddaff756b6a09f |
| SF3_DistinctFighters.json | 13,211,630 | c4ee840d89cf1b2b8b82db0aebce878dbc5c2f2f60a52cf5b5a77b84f139ed5f |
| SF3_DistinctFighters.zip | 16,499,513 | 1b228965b08c5d1b6cc659426722705a1ea734a906e183082d6556bde3fc18a8 |

The 61-file archive contains two GLBs, the motion catalog, seven control images,
39 source-feedback files and 12 weapon-trail files. Its 32 encrypted chunks are
authenticated before any resource is staged. PNG resources bypass Xcode image
rewriting so native hash checks verify the exact source bytes.

## Verification at initial preparation (historical)

The checks below describe preparation before the published resource baseline.
For subsequent actual-resource execution, use the linked native acceptance log.

- Local independent skinning/FK validation checks every half-frame; maximum
  endpoint disagreement is 1.433e-7 m. This is offline validation, not iOS evidence.
- All 26 local fighter script tests pass, including four new authenticated
  staging tests covering tampering, wrong identity, unsafe paths and symlinks.
- Workflow/project YAML parses and `git diff --check` passes.
- Linux has no Swift/Xcode. New Swift compilation, Metal pixels, actual-resource
  motion, lifecycle and touch-driven UI tests are pending the exact new commit's
  unsigned native workflow. Prior accepted CI 42479153124 does not validate this
  update. Personal screenshots and video remain encrypted in the character job.
- No TestFlight upload is part of this update.
