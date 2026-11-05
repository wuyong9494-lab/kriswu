# Result audio lifecycle · 2026-11-05

Continues the validated Build 513 source on `codex/plan-photo-rules`. Hero scope stays frozen.

## Reproducible defects

- `ArenaWorldView.resumeRendering()` calls `ArenaSound.begin(owner:)` after foregrounding. Previously, `begin` unconditionally cleared result playback even for the same renderer, while the logical scene remained `.result`.
- Match teardown did not stop result players until a later lobby appearance callback. A result could overlap the returning lobby bed during that interval.
- Theme/resource replacement discarded the current result outcome. Muted completion could also lose its outcome before players were loaded.

## Changes

Retain the outcome when the same renderer resumes or the underlying lobby reappears. Stop result playback during actual teardown/new-match ownership. Preserve result progress across deferred theme reloads, retain completed status without replay, and defer muted result playback until audio resumes. Repeated finish callbacks cannot restart or replace an established outcome. Discard queued combat effects when the result starts.

The audio owner accepts a resource store and player factory so native tests can install synthetic tones and inspect real `AVAudioPlayer` instances. Production still uses the same shared store, mixer, music files, mute settings and volume controls. The generated asset inventory has been refreshed.

## Validation scope

Eight new native cases cover background/renderer ordering, teardown before lobby callbacks, lobby reappearance, paused theme reloads, natural completion without replay, new renderer ownership plus stale teardown, repeated result delivery/new-match rewind, and muted completion. The existing seven audio tests remain included. `[arena-audio-tests]` selects both suites on the iPhone 17 Pro Max simulator, without unrelated website/OCR tests.

Local asset inventory, workflow YAML/shell parsing and whitespace checks pass. iOS compilation and native execution are pending CI at this commit; no local Swift/Xcode toolchain is available. Synthetic tones do not establish private-pack listening quality, full gameplay acceptance or physical-device frame rate. No TestFlight upload has been performed for this batch.
