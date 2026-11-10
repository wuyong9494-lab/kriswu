# Playable provisional shadow skills, 2026-11-10

## What this is

The current user request prioritizes playing both fighters' shadow skills in
parallel with normal combo work. This is an explicitly inferred native rules
implementation, **not recovered original SF3 combat timing or choreography**.
The previously audited raw katana/hammer shadow clips and encrypted source
configuration remain unchanged. Neither their root discontinuities nor weapon
visibility jumps enter movement, collision, or the displayed skeleton.

Each fighter uses its own existing verified heavy body animation, sampled over
the provisional skill duration. Sun keeps his katana; Liu's existing skinned
right hammer is transformed through its original weapon bone. No replacement
body, generic hammer projectile mesh, new assets, source-channel edits, or
private bytes are added. Original shadow choreography remains a separate
source-recovery goal. The original shadow role must still exist to advertise
this capability; ranged remains unsupported.

## Fixed-step contract (60 gameplay ticks/second)

Both commands require 100 energy and zero cooldown. Activation spends exactly
100 and starts a 360-tick cooldown. Shadow hits do not refund the caster's own
energy. Cooldown and action clock freeze in hit-stop; pause/background freezes
the simulation through the existing session lifecycle. Recovery cannot be
cancelled by guard or a repeated shadow press. Normal follow-ups may be buffered
in the last 24 ticks, and interruption clears those inputs.

- Sun: ticks 0–23 startup, 24–39 dash/contact, 40–72 recovery; idle/live stance
  resumes on the following tick. Dash is at most 150 mm per active tick and
  stops at the body/wall. The explicit provisional sword band extends 250–1400
  mm forward and 850–1250 mm above ground. It allows one hit, 170 damage (14
  blocked chip), and knockdown. It does not teleport through the opponent.
- Liu: ticks 0–23 startup, 24–47 outbound, 48–71 harmless return, 72–96 recovery;
  idle/live stance resumes on the following tick. Release starts 450 mm forward
  and travels up to 4800 mm farther in 23 intervals, mirrored and wall-bounded.
  The actual right hammer stands vertically at Y=820 mm; its length comes from
  the currently sampled original heavy clip geometry. Collision follows the
  same endpoints with 180 mm clearance. A horizontal sweep prevents tunnelling.
  Only the outbound path can land one hit, 195 damage (16 blocked chip), and
  knockdown. The held left hammer never becomes a second damage source.

Guard blocks both skills. A hit interrupts the caster, removes the detached
hammer and its future collision immediately, and preserves the paid cost and
cooldown. Round end clears any shadow action; reset restores energy/zero
cooldown/idle. Rendering derives everything from the authoritative action:
repeated draws cannot advance a throw, consume energy or emit another hit.
Existing original shadow FX layers and heavy swing/hit audio are reused.

## Authority and replay

The existing host-owned input simulation and ordered guest replay are unchanged.
No display callback decides collisions or spawns independent projectiles. Replay
schema/rules are now 2: optional `Action.shadowOriginX` and `shadowCooldowns` are
included in canonical bytes and the stored-state audit. The source fingerprint
includes the new Swift rules file, so incompatible peers do not silently share
one rules identity. Raw catalog hashes are untouched.

## Verification and limits

Added core coverage for both heroes/facings, startup, one hit, energy, cooldown,
whiff, harmless return, guard/hit-stop freeze, interruption, round reset,
replay/cancellation, and hostile discontinuous shadow tracks. Native tests check
real weighted hammer vertices, source geometry/material identity, held-left
preservation, mirrored throws, repeated drawing, restoration, and source FX.
Existing disabled-shadow assertions are changed to test absent capabilities or
the explicit provisional implementation rather than pretending events recovered.

At implementation time this Linux executor has no Swift compiler, Xcode, or
materialized private native assets. Swift/native tests are authored but **not
executed**. `git diff --check` and public Python integrity/network helper tests
can run here; they do not substitute for compilation or visual acceptance.
Before integration is called verified, run `swift test --jobs 2`, the unsigned
device build and actual private-resource `DuelShadowPresentationTests` plus
`DuelWeaponGameplayTests` in the existing native pipeline. Review both fighters'
visible provisional skills on the real models, including pause, return,
interruption and restart. No TestFlight/media deployment is part of this work.

### Integration follow-up

The first two integrated runs compiled the skills, passed the 958 core cases
(16 skipped), and passed all 260 actual-resource native cases. Release acceptance
is still incomplete: run `42783685165` at `dbde04e` failed the real-touch shadow
readiness assertion after a successful hit. The controls adapter retained a plain
session reference instead of observing its publications, allowing the UIKit
readiness state to stay stale while the enclosing HUD changed.

The follow-up makes the controls observe the same session without changing the
touch owner, simulation, or authority. A hosted-view regression exercises cost,
cooldown, pause/resume and restart for both fighters without manually refreshing
readiness. The real-touch predicate retains its energy/readiness requirements and
now logs both operands from one accessibility snapshot. This fix still needs its
own exact-commit native/UI validation; the prior passes do not prove this version.
The separately authorized internal TestFlight release remains gated on all five
validation jobs and is not activated by this source change.

Run `42791846500` at `b4db613` subsequently passed the new hosted readiness test
and all five actual-resource UI tests. The Sun and Liu touch traces each observed
zero energy and a live three-second cooldown. All 72 lobby samples passed. The
only native failure among 261 cases was the existing hosted network-room test,
which deliberately left the guest unmounted while using a real 15-second startup
deadline. Its old assertion did not record the terminal reason, so this run's
precise cancellation cause is not proven.

The follow-up isolates that lifecycle test from GPU scheduling with a DEBUG-only
controllable clock. It still requires real verified resources and actual renderer
receipts; synthetic fixtures remain forbidden. A companion verified-resource
test advances to the unchanged deadline, checks cancellation and resource release,
and checks that late renderer callbacks cannot restart combat. Shipping clock,
deadline and startup behavior remain unchanged. The follow-up requires a new
exact-source validation before release.

### Remaining visual boundary limitation

The provisional hammer path uses a fixed release/catch anchor rather than the
heavy animation's exact hand position. The transitions at ticks 23→24 and
71→72 can visibly snap, although there is no damaging return or raw source
teleport sweep. Native tests verify the detached mesh against the authoritative
path and restoration separately; they do not prove those two boundaries are
smooth. Exact hand-matched release/catch and original shadow choreography need
asset-backed visual review before this is described as polished or faithful.
