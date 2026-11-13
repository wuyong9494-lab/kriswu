# Wireless TV output: private implementation candidate

Baseline: a0657d3. No public upload, native build, simulator acceptance, TV test or TestFlight release performed.

## Implemented

- iOS 16.2–26 noninteractive external display scene (AirPlay routes exposing that scene, also compatible wired external scenes).
- One existing DuelWorldView/SCNScene/session moves between mounted containers. No second simulation, physics scene, audio owner or CADisplayLink is created for the television.
- TV renders to its own viewport; existing aspect-aware camera framing recalculates without stretching phone screenshots. Native route mode is retained, not forced to 4K.
- Phone retains existing touch/peripheral input and pause/result UI. TV has noninteractive health/time/result/pause overlay. Its window never becomes the phone key window.
- Transfer cancels held input through the existing cancellation contract; user must reapply direction after a switch. No synthetic attack release.
- Only the synchronous controlled renderer transfer suppresses temporary window=nil mount invalidation. Ordinary unexpected network detach remains fail-closed. Same resource/session identities are retained.
- Disconnect returns the same renderer to the phone. Closed owner cannot remount it. Phone owner disappearance pauses before delayed dismantle, and teardown closes the renderer even if it is on TV.
- Phone orientation updates exclude external scenes.

## Explicit scope/limitations

This is a battle-screen implementation. Lobby currently displays a neutral TV waiting screen, not a second lobby rendering. No App navigation, task list or unrelated private screen is sent to TV.
AirPlay selection remains under user/system control (Control Center → Screen Mirroring). This code does not silently connect to arbitrary televisions or use a video-only AVRoutePicker as if it established a game-screen route.
Not every wireless receiver offers a noninteractive external-display scene. If not offered, existing system mirroring remains; independent full-viewport behavior is not claimed.
No promise of 4K, 60 Hz output, zero black borders imposed by receiver, no overscan, or low wireless latency. Native viewport aspect is used; camera may show different scene breadth. Actual route resolution, compression and delay depend on phone, receiver and Wi-Fi.
Apple changed scene registration starting with iOS 27. Current repository CI uses Xcode 26.6. The iOS 27 UISceneAccessory registration must be implemented and compiled with that SDK before claiming iOS 27 dedicated output; mirroring fallback is the only current expectation there.

## Source evidence (checked 2026-11-13)

Apple: https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display.md
Explains AirPlay/cable scene provisioning, fullscreen noninteractive role, screen context, lifecycle and iOS 27 accessory registration requirement.
Apple: https://developer.apple.com/documentation/uikit/uiscenesession/role-swift.struct/windowexternaldisplaynoninteractive

## Verification status

- `python Tools/check_television_contract.py`: 8 structural assertions pass.
- `git diff --check`: pass.
- Four XCTest cases added to existing DuelLifecycleTests selected by fighter lifecycle CI. NOT EXECUTED: this workspace has no Swift/Xcode.
- Tests cover same renderer/scene/state/tick/clock count after 10 transfers, invalid target/closed renderer, disconnect return, stale display ownership/teardown. Synthetic fixtures are not proof of prepared private-resource network acceptance.

## Required native and real-device acceptance before delivery

1. Compile all sources and run existing + new native lifecycle tests, including real-resource network preparation suite. Confirm SwiftUI primary scene is unaffected by AppDelegate scene configuration.
2. Simulator external-display connect/disconnect, various landscape viewports; connect before fight, during preparation, mid-attack, paused, match-over, and restart. No double clocks or scene leakage.
3. Real phone + AirPlay receiver, game mode if available: record receiver/OS/negotiated pixel mode, frame pacing and input-to-photon delay. Never infer 4K from TV marketing name.
4. Hold touch directions/attacks through connection loss: no stuck direction, phantom release attack or stale keyboard callback. Test Bluetooth controller/keyboard Hitbox while TV is active. Confirm phone remains key window.
5. Two-device Game Center match: connect TV during resource preparation and running match; verify owner receipt/state hash unchanged, no spurious detached error, remote host/guest gameplay and settlement remain synchronized.
6. Background/lock/audio interruption: no automatic unsafe resume, music pauses under existing policy; explicit phone resume works. Exit fight releases scene resources and TV shows waiting screen, no other App content.
7. Test return to phone aspect and safe areas after multiple disconnect/reconnect cycles, no portrait flash regression. Compare control occlusion policy and camera framing on 16:9 TV.
8. iOS 27 requires additional accessory implementation and testing with compatible SDK, not a checked item in this candidate.

## Merge boundaries

New files: DuelTelevision.swift, television lifecycle tests, structural check, this document.
Existing changes: Info.plist scene configuration; ShiftApp delegate scene/orientation hooks; ArenaView phone-only orientation filter; DuelWorld wrapper and controlled transfer.
No changes to DuelView, controller adapter, source music, network rules or combat assets. Integrate alongside controller/music patches, then perform one concentrated native validation. Do not count this source candidate as accepted or upload TestFlight yet.
