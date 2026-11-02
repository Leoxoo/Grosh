#!/usr/bin/env python3
"""The review step: a person accepts or rejects each rule a candidate proposes, and only accepted
rules move on to the catalog.

Passing the checks in extract.py means a rule is *supported* by its page, not that it is right, so
every rule waits for a person. Decisions are saved in review-decisions.json (committed, unlike
cache/), as {card id: {rule key: {"decision": "accept" | "reject", "decidedAt", "rule", "quote", "edited"?}}}:
the date, and the rule described in a few words with its quote, so the file reads in a diff. A person can also
fix what a rule says (its categories, rate, cap or requirements, never its quote): the fixed rule is kept whole
under "edited", accepted, and goes to the catalog in place of the extracted one. It must still pass the page checks.

A rule's key is a hash of the card id and everything the rule says (its rate, categories, cap,
dates, requirements, conditions, quote, source URL, and whether the page confirmed it), so a
decision follows the exact rule it was made on: a re-extraction that changes any of that is a new
rule, waiting for review, and never inherits the old accept. Only the page's hash is left out, so a
page that churns without changing the rule keeps its decision.

The publish step calls accepted_rules(candidate, decisions): it returns only rules a person accepted.
"""

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import extract  # noqa: E402
import fetch  # noqa: E402

DECISIONS = Path(__file__).with_name("review-decisions.json")
DECISION_VALUES = ("accept", "reject")
COUNTS = ("waiting", *DECISION_VALUES)  # how a card's rules, and all of them, are counted
# Lists that are sets: their order is whatever the model gave, so it is sorted wherever a rule is compared or written.
SET_FIELDS = ("categories", "requires", "conditions", "needs")
# What a person may fix on a rule. The quote is the evidence, and the rest (selection, dates) is rare enough to re-extract.
EDITABLE = ("categories", "rate", "unit", "capAmount", "capPeriod", "requires", "tier")


def rule_key(card_id: str, rule: dict) -> str:
    """What a decision is saved under: the same for the same rule on the same card, different if anything it says changes."""
    content = dict(rule, evidence={k: v for k, v in rule["evidence"].items() if k != "pageHash"})
    for field in SET_FIELDS:
        content[field] = sorted(content.get(field) or [])
    del content["needs"]  # worked out from the rest
    for field in ("rate", "capAmount"):  # 3 and 3.0 are the same rate
        if content.get(field) is not None:
            content[field] = float(content[field])
    text = json.dumps({"card": card_id, "rule": content}, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def load_decisions(path: Path = DECISIONS) -> dict:
    return fetch.read_json(path, {})


def describe(rule: dict) -> str:
    """The rule in a few words, as the web page shows it and the decisions file keeps it: "3% on dining, up to
    $6,000 per year", "3% in the category the cardholder chooses: gas, online shopping (and others)"."""
    rate = f"{float(rule['rate']):g}{'%' if rule['unit'] == 'percent' else 'x'}"
    categories = ", ".join(extract.CATEGORY_LABELS[category].lower() for category in rule["categories"])
    others = " (and others)" if rule.get("hasOtherChoices") else ""
    picks = rule.get("picks")
    chosen = "category" if picks in (None, 1) else f"{picks} categories"
    what = {
        "choose": f"{rate} in the {chosen} the cardholder chooses: {categories}{others}",
        "top-spend": f"{rate} on the top-spend category each billing cycle, from: {categories}{others}",
        "rotating": f"{rate} in rotating bonus categories" + (f" (this period: {categories})" if categories else ""),
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
    rule = _find(candidate, key)
    decisions = load_decisions(path)
    card_decisions = decisions.setdefault(candidate["cardId"], {})
    if decision == "undo":
        card_decisions.pop(key, None)
    else:
        card_decisions[key] = {"decision": decision, "decidedAt": today, "rule": describe(rule), "quote": rule["evidence"]["quote"]}
    decisions = {card: saved for card, saved in decisions.items() if saved}
    fetch.write_json(path, decisions)
    return decisions


def edit(candidate: dict, key: str, changes: dict, page_text: str | None, path: Path = DECISIONS, today: str = "") -> dict:
    """Fix what one of the candidate's rules says (EDITABLE fields only) and accept the fixed rule. It is checked
    like any proposal, against `page_text` when there is one; a hand-entered rule whose quote the page doesn't
    confirm is checked without it, as it was entered. ValueError, and nothing saved, if the fix doesn't hold."""
    rule = _find(candidate, key)
    if not changes or set(changes) - set(EDITABLE):
        raise ValueError(f"Only these can be changed: {', '.join(EDITABLE)}")
    proposal = {field: rule.get(field) for field in extract.RULE_SCHEMA["required"] if field != "quote"}
    proposal.update(changes, quote=rule["evidence"]["quote"])
    page_norm, rows = (extract.normalize(page_text), extract.tier_rows(page_text)) if page_text else (None, None)
    problem = extract.validate_rule(proposal, page_norm, rows)
    verified = "page"
    if problem and page_norm is not None and rule.get("verified") == "manual":
        problem, verified = extract.validate_rule(proposal, None), "manual"
    if problem:
        raise ValueError(f"The quote doesn't back that change: {problem}")
    edited = extract.candidate_rule(proposal, rule["evidence"]["url"], rule["evidence"]["pageHash"], verified if page_norm else rule["verified"])
    decisions = load_decisions(path)
    decisions.setdefault(candidate["cardId"], {})[key] = {
        "decision": "accept", "decidedAt": today, "rule": describe(edited), "quote": rule["evidence"]["quote"], "edited": edited,
    }
    fetch.write_json(path, decisions)
    return decisions


def _find(candidate: dict, key: str) -> dict:
    rule = next((r for r in candidate.get("rules", []) if rule_key(candidate["cardId"], r) == key), None)
    if rule is None:
        raise ValueError("That rule is no longer in the card's candidate (was it extracted again?). Reload the card.")
    return rule


def summarize(entries: list[dict]) -> dict:
    """The review's totals over card_review entries: how many cards, and how many rules wait or were decided each way."""
    summary = {"cards": len(entries), **dict.fromkeys(COUNTS, 0)}
    for entry in entries:
        for name, count in entry["counts"].items():
            summary[name] += count
    return summary


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
    card_decisions = decisions.get(candidate["cardId"], {})
    rules = []
    for extracted in candidate.get("rules", []):
        key = rule_key(candidate["cardId"], extracted)
        saved = card_decisions.get(key, {})
        rule = saved.get("edited") or extracted  # what goes to the catalog if accepted
        rules.append({
            "key": key, "rule": rule, "decision": saved.get("decision"), "summary": describe(rule),
            "edited": "edited" in saved, "original": extracted if "edited" in saved else None,
            "quote": rule["evidence"]["quote"], "url": rule["evidence"]["url"], "warnings": rule_warnings(rule),
        })
    counts = dict.fromkeys(COUNTS, 0)
    for row in rules:
        counts[row["decision"] or "waiting"] += 1
    return {"cardId": candidate["cardId"], "status": candidate.get("status"), "warnings": list(candidate.get("warnings", [])),
            "cardConditions": list(candidate.get("cardConditions", [])), "rules": rules, "counts": counts}


def accepted_rules(candidate: dict, decisions: dict | None = None) -> list[dict]:
    """The candidate's rules a person accepted, in the candidate's order, each as the person fixed it if they
    did. Rejected rules and rules still waiting for review are left out."""
    decisions = load_decisions() if decisions is None else decisions
    card_decisions = decisions.get(candidate["cardId"], {})
    saved = [card_decisions.get(rule_key(candidate["cardId"], r), {}) for r in candidate.get("rules", [])]
    return [entry.get("edited") or r for r, entry in zip(candidate.get("rules", []), saved) if entry.get("decision") == "accept"]
