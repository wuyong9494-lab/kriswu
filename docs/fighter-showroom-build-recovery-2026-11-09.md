# Showroom build recovery — 2026-11-09

Branch: `codex/fighter-lab-sf3-resources-20261108`.
Base: `93d671113559333d6b15cb59ce2b6ad6ab0fc1b0`.

## Observed failure

Run `42566277515` failed before native tests could execute. The device compiler
reported `DuelLobbyPreview.swift:113:10: overriding declaration requires an
'override' keyword`. Core and synthetic envelope jobs passed; native, device and
actual-resource character jobs failed compilation. Their skipped simulator and
UI stages are not acceptance results.

## Focused correction

- Mark `gestureRecognizerShouldBegin(_:)` as the override of UIView's method.
  Preserve the existing horizontal-pan threshold and non-pan/pinch behavior.
- Replace the unused actor/idle bindings in `advanceIdle(_:)` with equivalent
  presence checks. `renderIdle(at:)` still unwraps and samples the same objects.
- Add two Objective-C-visible XCTest methods in an extension of the existing
  `DuelLifecycleTests` class. They exercise the registered pan delegate and
  UIView dispatch in both directions, vertical/diagonal/tiny/zero rejection,
  pinch acceptance, recognizer teardown and no idle update after shutdown.
  XcodeGen includes the whole `Tests/SiteTests` directory, and both native jobs
  already select `SiteTests/DuelLifecycleTests`; no workflow expansion is needed.

No existing test assertion is removed or relaxed. Character assets, encrypted
parts, secrets, combat values, animation sampling and CI/distribution configuration
are unchanged. The branch is advanced only by a non-forced update from the
verified base; do not replay an old native run as evidence for this correction.

## Validation boundary

Local Swift frontend parsing of the changed source and new tests is a syntax
check only. The local host has no UIKit/SceneKit SDK and cannot perform native
compilation or simulator acceptance. The push-triggered fighter workflow must
establish those results. At commit preparation, fresh native/actual-resource/UI
results are pending; no new visual or physical-device acceptance is claimed.

Keep the remaining acceptance work in
`docs/fighter-distinct-native-2026-11-09.md`: head/neck presentation, recovery-to-idle
continuity, control overlap, weapon trails, audible feedback and physical-device
performance still require separate evidence. No main merge or TestFlight upload
is part of this recovery.
