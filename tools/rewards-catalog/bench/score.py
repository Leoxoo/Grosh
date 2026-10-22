#!/usr/bin/env python3
"""Score candidate files against hand-checked rules in bench/expected.json.

    python3 tools/rewards-catalog/bench/score.py cache/candidates        # the current candidates
    python3 tools/rewards-catalog/bench/score.py some/other/dir          # any folder of <card id>.json files

A rule matches an expected rule when its categories, selection, rate and any requirement
or cap in the expectation all agree. Recall is expected rules found / expected rules.
Precision is accepted rules that match something expected / accepted rules.
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).parent


def matches(expected: dict, found: dict) -> bool:
    if sorted(expected["categories"]) != sorted(found["categories"]):
        return False
    if expected["selection"] != found["selection"]:
        return False
    if abs(float(expected["rate"]) - float(found["rate"])) > 1e-9:
        return False
    if "requires" in expected and sorted(expected["requires"]) != sorted(found.get("requires", [])):
        return False
    if "capAmount" in expected and expected["capAmount"] != found.get("capAmount"):
        return False
    if "capPeriod" in expected and expected["capPeriod"] != found.get("capPeriod"):
        return False
    return True


def score(folder: Path) -> dict:
    expected = json.loads((HERE / "expected.json").read_text(encoding="utf-8"))
    totals = {"expected": 0, "found": 0, "accepted": 0, "precise": 0, "rejected": 0, "calls": 0, "seconds": 0.0, "cards": 0}
    per_card = {}
    for card_id, wanted in expected.items():
        path = folder / f"{card_id}.json"
        if not path.exists():
            per_card[card_id] = "no candidate file"
            continue
        candidate = json.loads(path.read_text(encoding="utf-8"))
        rules = candidate.get("rules", [])
        hit_expected = {i for i, want in enumerate(wanted) if any(matches(want, rule) for rule in rules)}
        right = [rule for rule in rules if any(matches(want, rule) for want in wanted)]
        stats = candidate.get("stats") or {}
        totals["cards"] += 1
        totals["expected"] += len(wanted)
        totals["found"] += len(hit_expected)
        totals["accepted"] += len(rules)
        totals["precise"] += len(right)
        totals["rejected"] += len(candidate.get("rejected", []))
        totals["calls"] += stats.get("calls", 0)
        totals["seconds"] += stats.get("seconds", 0.0)
        missed = [f"{w['categories'] or 'rotating'} {w['rate']}%" for i, w in enumerate(wanted) if i not in hit_expected]
        per_card[card_id] = {"status": candidate.get("status"), "recall": f"{len(hit_expected)}/{len(wanted)}",
                             "accepted": len(rules), "right": len(right), "missed": missed}
    totals["recall"] = round(totals["found"] / totals["expected"], 2) if totals["expected"] else None
    totals["precision"] = round(totals["precise"] / totals["accepted"], 2) if totals["accepted"] else None
    return {"totals": totals, "cards": per_card}


if __name__ == "__main__":
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "cache" / "candidates"
    print(json.dumps(score(folder), indent=2))
