#!/usr/bin/env python3
"""The review step: a person accepts or rejects each rule a candidate proposes, and only accepted
rules move on to the catalog.

Passing the checks in extract.py means a rule is *supported* by its page, not that it is right, so
every rule waits for a person. Decisions are saved in review-decisions.json (committed, unlike
cache/), as {card id: {rule key: {"decision": "accept" | "reject", "decidedAt", "rule"}}}.

A rule's key is a hash of the card id and everything the rule says (its rate, categories, cap,
dates, requirements, conditions, quote, source URL, and whether the page confirmed it), so a
decision follows the exact rule it was made on: a re-extraction that changes any of that is a new
rule, waiting for review, and never inherits the old accept. Only the page's hash is left out, so a
page that churns without changing the rule keeps its decision.

The publish step calls accepted_rules(candidate): it returns only rules a person accepted.
"""

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import fetch  # noqa: E402

DECISIONS = Path(__file__).with_name("review-decisions.json")
DECISION_VALUES = ("accept", "reject")


def rule_key(card_id: str, rule: dict) -> str:
    """What a decision is saved under: the same for the same rule on the same card, different if anything it says changes."""
    said = {k: v for k, v in rule.items() if k != "needs"}  # needs is worked out from the rest
    said["evidence"] = {k: v for k, v in rule["evidence"].items() if k != "pageHash"}
    for field in ("categories", "requires", "conditions"):  # sets, in whatever order the model listed them
        said[field] = sorted(said.get(field) or [])
    for field in ("rate", "capAmount"):  # 3 and 3.0 are the same rate
        if said.get(field) is not None:
            said[field] = float(said[field])
    text = json.dumps({"card": card_id, "rule": said}, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def load_decisions(path: Path = DECISIONS) -> dict:
    return fetch.read_json(path, {})


def describe(rule: dict) -> str:
    """The rule in a few words, so the decisions file reads in a diff: "3% on dining, up to $6,000 per year"."""
    rate = f"{float(rule['rate']):g}{'%' if rule['unit'] == 'percent' else 'x'}"
    categories = ", ".join(rule["categories"])
    what = {
        "choose": f"{rate} in the category the cardholder chooses: {categories}",
        "top-spend": f"{rate} on the top-spend category from: {categories}",
        "rotating": f"{rate} in rotating bonus categories" + (f" ({categories})" if categories else ""),
    }.get(rule["selection"], f"{rate} on {categories}")
    if rule.get("capAmount") is not None:
        period = "billing cycle" if rule["capPeriod"] == "cycle" else rule["capPeriod"]
        what += f", up to ${float(rule['capAmount']):,.0f} per {period}"
    return what


def decide(candidate: dict, key: str, decision: str, path: Path = DECISIONS, today: str = "") -> dict:
    """Save a person's decision ("accept", "reject", or "undo" to forget it) on one of the candidate's
    rules, named by its rule_key. Returns every decision. ValueError if the decision or key is wrong."""
    if decision not in (*DECISION_VALUES, "undo"):
        raise ValueError("A decision is accept, reject or undo")
    rule = next((r for r in candidate.get("rules", []) if rule_key(candidate["cardId"], r) == key), None)
    if rule is None:
        raise ValueError("That rule is no longer in the card's candidate (was it extracted again?). Reload the review.")
    decisions = load_decisions(path)
    mine = decisions.setdefault(candidate["cardId"], {})
    if decision == "undo":
        mine.pop(key, None)
    else:
        mine[key] = {"decision": decision, "decidedAt": today, "rule": describe(rule), "quote": rule["evidence"]["quote"]}
    decisions = {card: saved for card, saved in decisions.items() if saved}
    fetch.write_json(path, decisions)
    return decisions


def rule_warnings(rule: dict) -> list[str]:
    """What a reviewer should check about this one rule, beyond reading its quote."""
    warnings = []
    if rule.get("verified") == "manual":
        warnings.append("hand-entered, and the saved page doesn't confirm the quote: check it on the page")
    if rule.get("capUnknown"):
        warnings.append("the page says there is a cap but doesn't state the amount")
    return warnings


def card_review(candidate: dict, decisions: dict) -> dict:
    """One card's rules as the review page shows them: each with its key, quote, source URL, warnings and
    decision (None while it waits), plus the card's own warnings (two rates for one thing, a missing base
    rate...), which are about its rules taken together."""
    mine = decisions.get(candidate["cardId"], {})
    rules = []
    for rule in candidate.get("rules", []):
        key = rule_key(candidate["cardId"], rule)
        rules.append({
            "key": key, "rule": rule, "decision": mine.get(key, {}).get("decision"), "summary": describe(rule),
            "quote": rule["evidence"]["quote"], "url": rule["evidence"]["url"], "warnings": rule_warnings(rule),
        })
    counts = {"waiting": 0, "accept": 0, "reject": 0}
    for row in rules:
        counts[row["decision"] or "waiting"] += 1
    return {"cardId": candidate["cardId"], "status": candidate.get("status"), "warnings": list(candidate.get("warnings", [])),
            "cardConditions": list(candidate.get("cardConditions", [])), "rules": rules, "counts": counts}


def accepted_rules(candidate: dict, decisions: dict | None = None) -> list[dict]:
    """The candidate's rules a person accepted, in the candidate's order. Rejected rules and rules
    still waiting for review are left out."""
    decisions = load_decisions() if decisions is None else decisions
    mine = decisions.get(candidate["cardId"], {})
    return [r for r in candidate.get("rules", []) if mine.get(rule_key(candidate["cardId"], r), {}).get("decision") == "accept"]
