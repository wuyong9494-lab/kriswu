# Existing material configuration — production gameplay

## Owner scope

Complete the existing asset assignments and upload the next TestFlight build.
The three heroes and Twin Gates are ordinary released gameplay, not test/trial
content. Full gameplay, simulator recordings and device acceptance remain deferred
at the owner's request; packaging and compilation checks still run.

## Completed assignments

- All 13 heroes retain model, idle/run/attack/super/hit/death/cheer bindings.
  Seven additional held models (17 dependency files) provide knight sword/shield,
  mage staff, assassin/darter daggers, swordsman greatsword, brewer mug and scholar
  spellbook. Each replacement reuses the embedded object's actual transform and
  restores that embedded object if the replacement cannot load.
- The finished 27-joint Ranger facial rig is the normal model in every entry.
  Earlier Ranger resources remain bundled for identity/provenance. Normal play
  also uses the completed hat proportions, thin outlines, brief hit flash and
  fitted bolt geometry. Duplicate helmet eyes and overlapping held items are fixed.
- Fifteen base palettes cover 14 original maps, Twin Gates and the seven expanded
  layouts. Added scenery includes 26 GLBs for stone/sandstone walls, broken columns,
  cactus/palm/pine/autumn trees, stumps/logs, flowers/leaves/mushrooms and paving.
  Sand, stone, meadow and dusk floor colors are distinct.
- Each scene keeps a bounded selection: at most 24 imported wall instances in
  existing collision cells, ten outside landmarks, and at most 16 low ground
  details/paving pieces. Internal decorations stay on floor cells away from
  spawns, objectives, goals and vaults. No new collisions or per-frame asset loads.
- Thirteen hero effect profiles and all nine gadgets select existing particle
  textures. Eleven additional 256px textures join the existing two; event effects
  and trails reuse the bounded pool and alpha blending to preserve silhouettes.
- Existing eleven Game-icons assets now render in their actual lobby roles.
  Fourteen additional Kenney images configure panels, toggles, sliders, audio
  state, navigation, information and locked states. Chinese text and fonts stay.
- Twenty selected vendor WAV files cover menus, attacks, damage, footsteps,
  knockouts, pickups, gadgets, upgrades, purchases and season reward claims.
  Wood footsteps correspond to actual paving cells. Existing synthesis remains
  for sound categories without a suitable downloaded replacement.
- All four previously composed themes are connected: lobby, battle, win and lose.
  Theme music defaults on if no choice was saved. Explicit off, mute and volume
  settings are preserved, with fallbacks if a selected file cannot decode.

## Formal gameplay

Twin Gates is selectable and rotates in team fight, stars, bounty, zone and
knockout. Ball, heist, duel, boss and solo/duo retain their appropriate layouts.
Network capability revision 4 prevents older peers from silently substituting a
different map. Its historical wire ID is retained for compatibility.

The three-hero entry is a balanced local 3v3 with the normal reward and season
pipeline. All three heroes are also available through the complete 13-hero roster.
Only explicit benchmark/recording/injected-result fixtures suppress progress.
Player-facing trial labels and 'no growth rewards' text have been removed.

## What is stored and what runs

The complete 11 source packs remain archived: 6,675 files / 85,364,328 bytes,
including alternate authoring formats, color variants, previews and licenses.
The assigned runtime selection is 104 files / 2,261,973 bytes (about 2.16 MiB),
plus the preexisting character models, catalog icons and four theme tracks.
Source archives are not copied wholesale into the app. These are the existing
KayKit/Kenney and project resources, not an original Brawl Stars client dump.

`scripts/assets/integrate_vendor_assets.py` consumes the four reviewed recipes.
`App/ArenaVendor/arena-vendor-runtime.json` records source and output hashes.
`arena-asset-configuration.json` is generated from actual Swift mappings and pins
all heroes, maps, gadgets, effects, themes and configuration source identities.

## Validation scope

Offline checks verify the 104 resources and all dependencies/provenance, all 13
hero rigs and 112 animation bindings, exact embedded attachment transforms,
26 additional model bounds and safe placement coverage for all 22 layouts.
The generated configuration must match current code in CI. Device compilation,
existing core tests and signed-archive resource/identity checks are mandatory.
New targeted SceneKit checks are saved for the later simulator session.

No device frame-rate, visual polish, listening, full combat, multiplayer session
or continuous recording acceptance is claimed by this configuration release.
