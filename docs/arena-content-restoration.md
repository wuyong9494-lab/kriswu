# Restore the complete arena after Build 471

## Report and evidence

On 2026-10-30 the owner reported that TestFlight 1.2 (471) had only three heroes,
the resource packs did not appear, and the previous maps were missing.

Source `719cb8369e2c248a7aa6c86bc3d5022edd63f77c` defaulted `ArenaHomeView` to
`threeHeroSample = true`. Ordinary entry points consequently substituted the
three-hero list, Twin Gates review and fixed zone match for the complete game.
The existing heroes, progression, story and map definitions were not deleted.

The actual 471 IPA from iOS run `41062131601`, artifact `12982085490`, was inspected.
It contains all 28 selected runtime files from 11 source packs, the runtime
manifest and licenses, previous character models and music. All 19 non-PNG
runtime files match their source SHA-256. The 9 PNGs retain their decoded image
content after Xcode PNG/CgBI conversion. The 11 source ZIP archives also match
their recorded SHA-256. Source archives are development inputs and are not
copied wholesale into the installed app.

This was limited integration: imported crates and barrels appeared only in
Twin Gates, and the nature models were ten objects outside the playable bounds.
File inclusion alone did not establish visible integration throughout the game.

## Correction

- Normal entry opens the complete 13-hero roster and 11 modes. Existing unlock
  conditions, saved progression and skins are preserved.
- The mode page exposes all 14 original maps and their 7 expanded variants in
  a mode-specific selector. A selected map ID is carried into the actual match.
- Game initialization accepts the expanded IDs instead of silently substituting
  the first original map. Random rotation retains its established expanded pool.
- Multiplayer map capability revision 3 enables expanded maps only when every
  peer supports the corrected initializer. Mixed-version rooms use original maps.
- Twin Gates and the three-hero study remain explicit extra entries. Simulator
  flow capture must explicitly request its three-hero entry.
- Ordinary maps use imported crates and barrels in existing matching wall cells.
  At most 24 shared-mesh instances are spread over each map; remaining walls keep
  their merged geometry. Model bounds fit the original collision cells, with no
  additional obstacle on walkable ground. Stone themes, grass behavior and the
  existing nature border are preserved.

## Validation and publication scope

The owner's latest instruction is to upload first and test gameplay later.
The source commit explicitly defers arena-look, sample-capture and hero-flow
jobs; manual runs remain available. Device compilation and the existing core
suite still run as packaging checks. The publication guard must pin the exact
new source/run/build, verify signed app and widget identities, and confirm all
28 selected runtime files and 11 packs are in the archive before upload.

The map-selection assertions were added to the existing core regression test.
A deferred SceneKit test also checks that ordinary walls actually instantiate
imported cargo within existing wall cells and respect the instance limit.
No full gameplay, screenshots, recording, audio listening, multiplayer device
session or sustained device-frame-rate acceptance is claimed by this repair.
