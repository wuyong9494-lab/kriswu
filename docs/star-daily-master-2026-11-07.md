# Daily master edition 1

The daily home entry now selects a deterministic constellation-hard board from 12 date-derived candidates. Three shallow policies rank each candidate. Fewer policy wins ranks first; ties prefer greater minimum cleared progress, avoiding selection solely for instant opening failure. Fixed traversal and first-best tie handling make the same calendar date reproducible. Existing dailySeed, generator, solution and challenge encoding remain unchanged. Future policy changes must use a new daily edition.

Selection runs off the UI actor, bounded and cancellable. Daily mode permits retry of the same seed and has no Change Deal button. A new master-v1 date key separates daily results from old daily results without changing the saved Codable schema. Daily selection captures its date before asynchronous work, including across midnight.

Tests compare the selected board against the old date-derived candidate, check repeatability and valid seed bounds, then replay its full guaranteed solution. Audit lines expose heuristic wins for sampled dates. This is evidence about those policies only, not a human pass rate or proof of comparable difficulty to another game. No forced-loss/random impossibility mechanics are introduced.

Previous master-focused commit 7ea517417b35b26c2f9d430be158f5cde4a7aa50 passed both iOS build and Linux regression. Latest confirmed TestFlight remains 569; these daily changes are not yet published there.
