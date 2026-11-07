# Master-focused entry and bounded deal screening

User decision: retire tile shifting from the main loop; preserve existing saves in More Modes. Prioritize classic Master and Deep-space Master.

Home now directly opens hard classic (9 kinds) and hard constellation (12 kinds), followed by the unchanged daily board. Rail journeys, expeditions, trials, rewards and old campaign entry remain under More Modes, including pending rewards and resume. Help begins with tile rules instead of the rail tutorial.

Fresh home master games screen up to eight existing seeds using three shallow, deterministic policies: matching, exposing, and reversed tie-breaking. Choose the first lowest greedy win count, stopping at zero. This changes seed selection, not the generator, solution, share codes, saved records or daily boards. Work runs off the main actor with cancellation checks. If every candidate is easy, bounded fallback still opens the best candidate; this is not a guarantee of difficulty or a measure of enjoyment. In-board Change Deal still uses its existing random behavior.

Regression tests cover deterministic selection, seed boundaries, both rule sets, no worse greedy win count than the starting candidate, and replay of every selected board's guaranteed solution. Human strategy depth and device responsiveness still require play testing. No new mechanic or forced-loss rule was added.

Previous release 1.2 (569): Apple VALID and IN_BETA_TESTING confirmed 2026-11-07 03:48 UTC, source a62b36c29a56ad1efd4b38cc991843e7263284f2. These changes are a later candidate, not part of 569.
