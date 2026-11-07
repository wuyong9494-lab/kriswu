# Daily planning qualification (edition 2 candidate)

Target: approximately 0.1% human first-attempt, no-tool daily completion. No human rate has been measured; automated solver statistics must never be reported as player pass rates.

Adds a bounded deterministic beam planner with legal pick/cover/tray transitions, deduplication, fixed tie breaks, cancellation and explicit budget exhaustion. Narrow width 4 (16,000 expansions) is compared with width 32 (100,000). Failure is never classified as impossibility.

A qualifying candidate requires: narrow search finishes without a solution or budget exhaustion; wider search returns an actual winning sequence; and that winning path has at least one alternative pick that does not immediately lose but provably loses under every continuation within the next two picks. This short proof uses full enumeration, not beam pruning, and treats exhaustion as unknown. Witnesses are capped at three and proof work at 8,000 nodes. Every supplied winning path is replayed before witnesses are accepted.

Selection examines at most eight date-derived candidates and three wider searches. If no candidate qualifies, the unchanged edition-1 selection is retained, explicitly marked unqualified. This is not a claim that a wider-search witness alone achieves the human target.

The audit covers seven consecutive dates, contrasts the old daily candidate, replays solver solutions and records budgets, critical forks and duration. UI integration waits for audit results and practical runtime cost. Edition 1, old daily records and all existing seed/challenge mappings remain unchanged.
