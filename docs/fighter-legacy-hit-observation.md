# Legacy practice hit observation

## Evidence and limits

On commit `ce8deb6`, run `42652583146`, actual-resource job `129282572482`, the legacy `testBothHeroesHitPauseBackgroundExitAndKeepExistingGameEntries` timed out while observing Gale's first skill. The ordinary legacy UI job passed. The actual-resource job's original Sun/Liu weapon UI flow also passed, in 559 seconds, and its 114 native tests passed.

The failing log shows the skill tap at 73.06 seconds, event synthesis at 75.20 seconds, and the next `duel.hits` lookup at 78.72 seconds. That lookup retried at 82.99/83.00 seconds before the five-second predicate wait failed. The log does not include a readable final hit value. No decrypted screenshot or accessibility attachment was inspected. It therefore establishes a failed observation, not whether a touch was lost, the simulation was delayed, or accessibility returned a stale/missing element. Simulator load is a timing hypothesis, not a proven root cause.

## Source contract

- Legacy touch-down queues the action in `DuelSession.taps`. Touch-up releases held state without clearing that pending action. The next simulation step consumes it once.
- Gale's skill starts after 18 ticks and launches a projectile moving 135 units per tick. At the initial 3000-unit gap, it hits on simulation tick 33 for 135 damage.
- `DuelClock` caps catch-up at six ticks per display callback. A synthetic one-callback-per-second schedule reaches only 30 ticks in five seconds. This explains why elapsed time alone does not establish contact; it does not assert that the failing run had this schedule.
- Ember's first jab deals 75 damage and reaches 1030 units. Its approach now uses the existing real-touch, bounded position observer to reach at most 1000 units instead of assuming a 0.8-second hold covers enough distance.
- Practice health regenerates after hit stun. Cumulative hit count and damage persist, making them the appropriate UI observations.

## Test-only changes

The legacy UI flow requires an initial zero-hit/zero-damage counter, performs one real attack tap, then expects the exact cumulative value of one hit and 135 damage for Gale or 75 damage for Ember. The hit element is the predicate expectation's stable object rather than a fresh query inside a block. Its 12-second observation budget matches the existing original-weapon flow. A label change, missing element, extra attack, or timeout does not count as success. There is no attack retry, skipped assertion, injected state, or gameplay change.

The focused native regression releases Gale's action before any simulation step, applies the real clock's catch-up cap, verifies no hit through tick 32, then checks one hit, 135 damage, defender health 865 and knockback to 6760 on tick 33. After recovery it requires the cumulative result to remain unchanged. This unit-level session test does not replace the real-touch UI test.

## Validation

This patch needs native/UI execution on an Xcode host, including both the ordinary and actual-resource legacy flows. The editing environment is Linux with neither Swift nor Xcode installed, so native compilation and simulator reruns have not been performed here. Physical-device touch latency and responsiveness have not been validated; a longer simulator observation budget is not a responsiveness claim.
