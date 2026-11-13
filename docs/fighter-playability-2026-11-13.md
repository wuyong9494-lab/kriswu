# Back defense, shadow recharge and closer lobby

Holding Back on the stick now requests defense relative to the local fighter's
facing. Neutral input does not auto-block. Forward motion, jump, crouch and
attack chords do not block; an attack's source recovery still finishes first.
The separate center defense button is removed. VoiceOver retains a deliberate
stick custom action, and peripheral defense ownership remains supported.

The showroom defaults to 0.75 of its previous optical tangent: the same model
and face occupy roughly 33% more screen space. The eye remains in front of the
verified opaque foreground rail. Pinch and rotation remain available. Actual
body/head/weapon vertices and the real navigated opening are the clipping gate;
unused floor footprint is no longer a requirement of the closer default.

Native balance changes recharge from fixed 12/5 per hit to one energy per five
damage dealt / four damage received (rounded up, capped at 100). Blocks award
8/10 to attacker/defender. Shadow hits do not refund the caster. Existing damage,
starting energy and six-second shadow cooldown are unchanged. Replay rules
version is 4; the build's source-derived network fingerprint prevents mixed
simulation versions. These are application rules, not recovered SF3 constants.

Liu's existing independent shadow throw, contact, return and audio are included.
A new real-catalog probe exercises the first cast, recharge, cooldown and second
cast before KO. Original-game choreography/shader equivalence is not claimed.

Validation before native capture: 91 focused core methods executed; one old
block-energy expectation was updated to the new balance and rechecked. The
unsigned playability scope contains eight exact native methods, six screenshots
and the same 73 authenticated resources. It does not upload another TestFlight
build. External TestFlight promotion must reference a successful exact-source
run and explicitly allow external testing, unlike internal-only build 703.
