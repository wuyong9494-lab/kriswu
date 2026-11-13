# Controller / keyboard-Hitbox candidate (not device-certified)

Base: a0657d3, candidate branch codex/fighter-lab-compile-only-20261111.
Parallel ChatGPT branch observed at 6de61619fe94d9f005c87bc9b4519432e83d2227.
No camera, music, fighter resources, networking authority, or damage data changed.

## Supported path and defaults
Pair a compatible Bluetooth controller in iPhone Settings first. App consumes
GCController.extendedGamepad, not arbitrary BLE advertisements or vendor protocols.
X / A / B / Y map to weapon / kick / ranged / shadow; D-pad or left stick moves;
LB / LT request stationary defense subject to existing eligibility/recovery.
Existing neutral auto-guard remains; this is not a new defensive mechanic.
Direction+attack, heavy hold and skills retain DuelWeaponInput timing and equipment rules.
Direction remains world-relative and is converted to facing only by existing combat.

Keyboard-mode Hitbox must actually appear to iOS as GCKeyboard:
WASD/arrows move, Space is up, J weapon, K kick, L ranged, I shadow,
left/right Shift defense. Opposite keyboard directions neutralize (SOCD).
This first version has fixed bindings; configure the device to these keys.
Not every Hitbox supports Bluetooth, iOS, keyboard mode or extended-gamepad mode.
USB-only or unsupported vendor devices are NOT made Bluetooth-compatible by this code.
No Bluetooth permission dialog or custom pairing UI is introduced.

Touch controls remain visible and usable. Each physical source owns its buttons,
and releasing one source cannot finish another source's held button.
Touch/device opposite directions cancel; same directions do not stack.
D-pad takes precedence over stick separately for each nonzero axis.
Connect, reconnect, pause, background, window loss and replacement clear unsafe input.
After a reset every device must return to neutral before becoming active again.
Disconnected input discards pending attack/jump intent, not an attack-on-release.
Source cancellation conservatively discards pending shared chords as well.

Scope: current original-weapon DuelWeaponControls path (offline + coordinator
network presentation). Legacy laboratory DuelInputView is not extended.
Menu navigation, remapping UI, rumble, gyro and two controllers on one phone
as separate fighters are not part of this candidate.

## Verification status and gates
- Executed: git diff --check. Passed.
- Added: 6 ShiftCore tests for source ownership, SOCD, deadzone, reset/cancellation.
- Added: 4 adapter lifecycle tests (injected controller discovery), plus 4 session DuelLifecycleTests for shared button, disconnect and pause.
- Native compilation/tests NOT executed here: this Linux workspace has no Swift or Xcode.
- No CI upload, public push, TestFlight upload or physical-device success claimed.

On an authorized macOS runner:
1. swift test --filter DuelPhysicalInputTests and all DuelWeaponInputTests.
2. Generate project using existing project-private-resources.yml workflow.
3. Run SiteTests/DuelLifecycleTests plus existing DuelSourceControlsTests.
4. Run added injected GCController.withExtendedGamepad lifecycle tests, then expand: connect/disconnect during held attack, delayed callbacks,
   replacement view, foreground/resume, disabled skill and absent profile.
5. Test on real iPhone + a named compatible controller and a named Hitbox:
   pairing, launch already connected, hot plug, all diagonals, neutral heavy hold,
   jump+attack, all supported skills, defense recovery, repeated input, touch+pad
   shared keys, two attached pads, loss while moving/attacking, home/lock/calls,
   landscape transitions, exit and re-enter.
6. Two real iPhones in coordinator network mode, host handover and reconnect,
   input-edge identity, skills and result synchronization. Simulator is not proof
   of Bluetooth latency or real peer network correctness.
Record device model/firmware/iOS, actual input profile, bindings, outcome and video
before claiming hardware compatibility or acceptance.

Official references consulted:
- https://support.apple.com/en-gb/111099
- https://developer.apple.com/documentation/gamecontroller/gckeyboard
- https://developer.apple.com/documentation/gamecontroller/gckeyboardinput
- https://developer.apple.com/documentation/gamecontroller/gckeyboardvaluechangedhandler
