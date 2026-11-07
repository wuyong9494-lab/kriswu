# Daily planning qualification (edition 2 candidate)

Target: approximately 0.1% human first-attempt, no-tool daily completion. No human rate has been measured; automated solver statistics must never be reported as player pass rates.

Adds a bounded deterministic beam planner with legal pick/cover/tray transitions, deduplication, fixed tie breaks, cancellation and explicit budget exhaustion. Narrow width 4 (16,000 expansions) is compared with width 32 (100,000). Failure is never classified as impossibility.

A qualifying candidate requires: narrow search finishes without a solution or budget exhaustion; wider search returns an actual winning sequence; and that winning path has at least one alternative pick that does not immediately lose but provably loses under every continuation within the next two picks. This short proof uses full enumeration, not beam pruning, and treats exhaustion as unknown. Witnesses are capped at three and proof work at 8,000 nodes. Every supplied winning path is replayed before witnesses are accepted.

Selection examines at most eight date-derived candidates and three wider searches. If no candidate qualifies, the unchanged edition-1 selection is retained, explicitly marked unqualified. This is not a claim that a wider-search witness alone achieves the human target.

The audit covers seven consecutive dates, contrasts the old daily candidate, replays solver solutions and records budgets, critical forks and duration. The seven-day audit qualified five days; November 10 and 12 retain edition-1 fallback and are not marked qualified. All seven chosen seeds are precomputed in the edition-2 entry, avoiding search on launch; the audit verifies the table against the deterministic selector. Future dates use the same bounded search off the UI actor and cache their result while the home view remains alive. The daily entry now uses this selector and Beijing calendar dates. Edition 1, old daily records and all existing seed/challenge mappings remain unchanged. Edition-2 daily records use a separate key; retention sorts by date across editions.


Device-local first-attempt records start at the first legal pick, persist immediately, and distinguish pending, unassisted win, loss, tool use and abandonment. Retry wins and rescue tools cannot overwrite a first loss. An interrupted pending attempt is retained and becomes abandoned when another attempt begins. These observations are shown on the daily card, stored separately from old best-score records and are not global player statistics. Tests cover duplicates, retries, tools, restart persistence and date separation.

Evidence: workflow 42341033759 at bb65f0e3693c1a5810128a6f3939ad31e6eaa8de; artifact 13561074808; report docs/evidence/star-daily-planning-2026-11-07.json. Five of seven qualified days is a board-quality result, not a player pass rate. No proof of the 0.1% human target exists.
