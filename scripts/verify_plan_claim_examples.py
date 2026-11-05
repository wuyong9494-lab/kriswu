"""Deterministic counterexamples for OCR advice, not an OCR accuracy benchmark.

Only fictional identifiers/times are used. No user plan photos or records are read.
Run: python3 scripts/verify_plan_claim_examples.py
"""

import json
import re
from collections import Counter


def distance(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def demonstrate():
    # The screenshot's pattern accepts only digits after this prefix.
    example_id = "JL1KF12A34"  # Fictional; no claim that this is an actual satellite.
    partial = re.search(r"JL1KF\d+", example_id)
    regex_example = {
        "pattern": r"JL1KF\d+",
        "input": example_id,
        "full_match": re.fullmatch(r"JL1KF\d+", example_id) is not None,
        "substring_match": partial.group() if partial else None,
    }
    assert regex_example["full_match"] is False
    assert regex_example["substring_match"] == "JL1KF12"

    clock = r"(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d"
    time_pattern = rf"{clock}-{clock}"
    expected = {"time_range": "08:00:00-08:05:00"}
    wrong = json.loads('{"time_range":"08:00:00-08:06:00"}')
    time_example = {
        "expected": expected,
        "recognized": wrong,
        "both_pass_24_hour_format": all(re.fullmatch(time_pattern, r["time_range"]) is not None for r in [expected, wrong]),
        "value_equals_source": wrong == expected,
    }
    assert time_example["both_pass_24_hour_format"] and not time_example["value_equals_source"]

    raw = "DEMO07D0X"
    whitelist = ["DEMO07D01", "DEMO07D02"]
    distances = {candidate: distance(raw, candidate) for candidate in whitelist}
    nearest = [candidate for candidate, d in distances.items() if d == min(distances.values())]
    assert len(nearest) == 2 and set(distances.values()) == {1}

    votes = Counter(whitelist)
    winners = [value for value, count in votes.items() if count == max(votes.values())]
    assert len(winners) == 2

    # Same fictional pixel truth/candidate observed in Build 524; this is not a new model run.
    truth = "DEMO07D02"
    repeated = ["DEM007D02"] * 3
    consensus = {"pixel_truth": truth, "observed_readings": repeated, "all_agree": len(set(repeated)) == 1,
                 "consensus_correct": repeated[0] == truth}
    assert consensus["all_agree"] and not consensus["consensus_correct"]

    return {
        "scope": "logic counterexamples only; no live LLM calls or OCR benchmark",
        "regex": regex_example,
        "format_is_not_truth": time_example,
        "edit_distance_ambiguity": {"input": raw, "distances": distances, "nearest": nearest},
        "two_conflicting_results": {"votes": dict(votes), "winners": winners, "strict_majority": False},
        "agreement_is_not_truth": consensus,
    }


if __name__ == "__main__":
    print(json.dumps(demonstrate(), ensure_ascii=False, indent=2))
