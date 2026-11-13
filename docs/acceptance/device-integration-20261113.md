# Private combined device candidate — NOT native/device accepted

## Provenance and scope
Base is the exact archive of a0657d3f42141d673e37e4afd3a41354d644ddfc. Local baseline commit 8e81057 is an archive snapshot, not the upstream Git identity. Live GitHub branch list checked 2026-11-13: candidate unchanged; parallel combat branch now 6044c3c1ee8e6b58eed3ee0d5109be50c255db41; camera-reset-optics branch ae0d848de0ad8c2d39d29f06aff56c2d9b4e0d5e. No parallel branch was copied over the current session/network/resource architecture.

Inputs: lobby libfile_0e12ea8f92f48191bc4aeca2b46cc7eb v0; controllers libfile_75dcd0d79cac81918eb1437b971eb7b4 v2 (byte matched); television libfile_dcedb18dd594819187d860e662d1c584 v0. All applied without text conflicts. No game assets, credentials, signing data, public commit or TestFlight upload are part of this deliverable.

## Integration review
- Existing DuelWorld renderer is moved, not recreated. Session authority and clocks retain their existing lifecycle guards.
- Renderer transfer calls clearInput. Its bound inputReset cancels pointer ownership and resets controller gates. A button held across migration requires neutral before reuse. Already-routed layout callbacks do not cancel again.
- Character-occlusion projection is used only when controls and renderer share the same UIWindow. TV rectangles therefore do not hide phone controls.
- TV does not become key, own audio, instantiate another game, or claim phone orientation. Landscape request filters windowApplication scenes; controls stay phone-side.
- Lobby fallback remains explicitly temporary TempleFall, not an invented original lobby association. Music ownership readiness fix remains intact. AirPlay disconnect may trigger audio route safety pause; do not bypass it.
- Latest parallel combat change synchronizes shadow voice pause. It is NOT silently imported: that branch must be selectively reconciled in its own workstream, not merged wholesale.
- No additional production-code defect was demonstrated by this static integration review. Two cross-feature regression tests were added rather than inventing fixes.

## Verification actually performed
- git apply --check and application of all three patches: PASS.
- git diff --check: PASS.
- 19 music envelope/package Python tests: PASS.
- 8 television static contract checks: PASS.
- Two cross-feature UIKit/GameController tests authored: NOT RUN.
- Swift/Xcode/iOS frameworks unavailable on this Linux executor. NO native build, simulator, Bluetooth, AirPlay, two-phone or music listening pass is claimed.

## Concentrated validation gate before publication/delivery
Run on supported macOS/Xcode, against this exact combined source, not build 702:
1. xcodegen; unsigned iOS build; swift test (all core tests including DuelPhysicalInputTests).
2. SiteTests/DuelLifecycleTests (includes controller, external-authority and six television cases), DuelMusicTests, DuelLobbyMusicSelectionTests, DuelSourceControlsTests; preserve all existing real-resource rig/material/combat tests.
3. ArenaFlowTests/DuelFlowTests and DuelWeaponFlowTests: phone portrait→direct landscape lobby, exit/reentry, temporary music audible, match/lobby audio handoff, no app tab bar, interruption recovery.
4. Real iPhone + AirPlay receiver: 16:9 independent viewport, connect before/after match, repeated disconnect/reconnect, TV standby in lobby, background, failed route, pause/resume, return to phone. Check single simulation clock/authority; sound route and headphone-removal safety. Do not claim all receivers or 4K/zero latency.
5. Real recognized controller and keyboard-Hitbox: held-on-connect, held-during-TV-transfer, neutral rearm, touch+pad union, opposing axes, disconnect, view replacement. No claim of proprietary BLE compatibility.
6. Two-iPhone host/guest: room transfer, continuous touch, settlements and disconnect during TV route switches, unchanged canonical simulation/ordering.

Existing protected real-resource workflow does not select music test classes by default. Add both explicitly when a publication/CI run is authorized; retain protected environment and no-upload boundary. Do not mark native coverage based on the Python/static checks above.
