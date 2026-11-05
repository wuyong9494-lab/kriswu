# Map selection and preview recovery · 2026-11-05

## Changes

- Refresh the generated asset configuration after the reload audio binding changed. Build 510 stopped at this source-hash check before iOS compilation; the validation remains enabled.
- Decode imported map previews outside the main actor. A cancelled thumbnail task cannot overwrite a newer preview.
- Track resource content revisions, including enable/disable transitions. A replacement with the same pack ID and catalogue still invalidates its map previews; a result from an earlier revision cannot enter the active cache.
- Preserve a supported project or imported map when changing heroes. A mode does not require imported maps if its existing project maps are available. Unsupported imported-roster modes retain their existing restrictions.
- Highlight only the selected map; selecting an imported map no longer also highlights random rotation.
- Reconcile saved selections on entry and resource changes. Disabling the pack releases an imported map selection so project matches can start normally.

## Validation

Final product source: `e35fee8a14d7054b92de63a12778a787b79ec8e1` on `codex/plan-photo-rules`.

[Build 513](https://github.com/wuyong9494-lab/kriswu/actions/runs/41961440360) completed successfully at 2026-11-05 03:47:42 UTC (11:47:42 Beijing). macOS core: 616 tests, 14 existing skips, zero failures, 252.204 seconds. Linux core: 616 tests, 15 existing skips, zero failures, 72.024 seconds. All six new selection cases passed on both platforms. Generated asset verification, iOS Release compilation and unsigned IPA packaging succeeded; concurrency warnings: zero. No Release or TestFlight publication occurred.

The focused native suite ran in [Build 512](https://github.com/wuyong9494-lab/kriswu/actions/runs/41960711189/job/127026150272) on source `800f1a1a8d1309504a47cefa5851ec6dc6976f02`: iPhone 17 Pro Max, iOS 26.2 simulator, five tests, zero skips, zero failures, 64.017 seconds. This source differs from the final source only in the one-line map-card highlight correction; the resource store, loader, selection policy and tests are identical. Build 512 also passed 616 Linux core tests, with 15 existing skips and zero failures. Its superseded iOS build was cancelled by the normal branch concurrency policy, while native testing continued to completion.

Six core regression cases cover both hero families, missing imported maps, invalid cross-mode selections, disabled resources and unsupported roster modes. Five native cases install generated resource packs and exercise preview/match consistency, replacement with an unchanged catalogue, disable/re-enable recovery, cancelled cache reads and mismatched map identities.

Local checks passed: generated asset inventory, workflow YAML and whitespace checks. No Swift/Xcode toolchain is installed in the local Linux workspace; execution results must come from CI.

These checks do not certify full private-resource gameplay, visual parity or physical-device frame rate. No new TestFlight upload is part of this source validation.

Machine-readable evidence: [arena-map-513.json](evidence/arena-map-513.json).
