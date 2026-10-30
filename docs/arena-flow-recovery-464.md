# Build464 flow and launch recovery

Base: 1f26a334147ff66a9ba4e40bef872875d92cfef3. Application 41022416629 passed; sample 41022416630 failed. Inspected downloaded artifact 12962993875, its exported accessibility trees, and the Ranger test movie at 35 seconds (original movie unchanged).

The lobby is visibly present. The tree identifies the hero button by label 英雄 but assigns it arena.lobby, like every other lobby button. The root SwiftUI identifier propagated to descendants, overwriting arena.openHeroes and arena.start. Remove the ancestor identifier, plus the analogous hero-list/detail ancestor identifiers, retaining individual control IDs and all assertions. Every UI test now preserves a final screenshot and accessibility tree even on failure.

Traversal failed in simctl launch after 150 seconds, before scene evidence. The recorder was started before launching into a newly rebooted simulator. This proves the failure phase, not an encoder/OS root cause. Replace reused/rebooted recording sessions with isolated devices and a time-zero debug simulator handshake: launch and await scene readiness before starting the encoder, then release the simulation gate. No simulation acceleration, forced result, timestamp repair, or increased launch timeout. Revalidation required.

Xcode's exported trees show randomized per-test app bundle identifiers. Reading only the original com.kriswu.shiftreminder container is not reliable. Attach the app-written natural-result JSON through the UI test before sandbox teardown and collect it from xcresult exports; preserve strict hero/roster/action/natural-result checks. No JSON is fabricated in the test.

Local checks: Python capture regressions and YAML parse. No local Xcode; do not call the flow or simulator issue resolved until the unique successor CI and its real artifacts are inspected. No release or TestFlight.
