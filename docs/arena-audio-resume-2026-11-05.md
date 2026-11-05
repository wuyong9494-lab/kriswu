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

Final source: `f4ee3ee4754e77fc0a86aaf30a41d99960db0a8a`, tree `b6cbddcb5d7af60a405c9eb8f9d127446b310443`.

[Build 514](https://github.com/wuyong9494-lab/kriswu/actions/runs/41965055385) completed successfully at 2026-11-05 04:23:01 UTC (12:23:01 Beijing). macOS core: 616 tests, 14 existing skips, zero failures, 253.172 seconds. Linux core: 616 tests, 15 existing skips, zero failures, 78.349 seconds. Generated asset verification, iOS Release compilation and unsigned IPA packaging succeeded; concurrency warnings: zero. IPA artifact and GitHub Release publication were skipped. No TestFlight upload occurred.

The native suite ran on the exact same source, using iPhone 17 Pro Max / iOS 26.2 simulator. All 15 unique cases passed, including all eight new result cases, with zero skips/failures in 10.984 seconds. The workflow repeats its log summary; these repeated lines are not additional test executions. The actual AVAudioPlayer completion callback and resumed playback positions were exercised with generated tones. [Native result artifact](https://github.com/wuyong9494-lab/kriswu/actions/runs/41965055385/artifacts/13386879974): `site-tests-514-1`, 152,807 bytes, digest `sha256:2c128c4f0124f57a7b01af277bd5f3e0602e73ff049115422886e55ba4c1f752`.

Local asset inventory, workflow YAML / 40 shell-step parsing and whitespace checks also pass. No local Swift/Xcode toolchain is available; execution evidence is from CI. Synthetic tones do not establish private-pack listening quality, full gameplay acceptance or physical-device frame rate. Hero scope remains frozen.

Machine-readable evidence: [arena-audio-514.json](evidence/arena-audio-514.json).
