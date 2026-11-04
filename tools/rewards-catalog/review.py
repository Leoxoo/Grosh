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

A person also sets options on a whole card, saved in card-options.json (committed) as {card id: {option: value,
"setAt"}}. The one option, "bonusesStack", says the card's bonuses add up: a purchase earns the base rate plus
what each bonus covering it adds over the base, not only the best single rate (CARD_OPTIONS).
"""

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import extract  # noqa: E402
import fetch  # noqa: E402
import quarters  # noqa: E402

DECISIONS = Path(__file__).with_name("review-decisions.json")
OPTIONS = Path(__file__).with_name("card-options.json")
# What a person can turn on for a card, and what it means. Every option is off until someone turns it on.
CARD_OPTIONS = {
    "bonusesStack": "Bonuses add up: a purchase earns the base rate plus what every bonus covering it adds over the base",
}
DECISION_VALUES = ("accept", "reject")
COUNTS = ("waiting", *DECISION_VALUES)  # how a card's rules, and all of them, are counted
# Lists that are sets: their order is whatever the model gave, so it is sorted wherever a rule is compared or written.
SET_FIELDS = ("categories", "requires", "conditions", "needs")
# What a person may fix on a rule. The quote is the evidence, and the rest (selection, dates) is rare enough to re-extract.
EDITABLE = ("categories", "rate", "unit", "capAmount", "capPeriod", "requires", "tier")


def rule_key(card_id: str, rule: dict) -> str:
    """What a decision is saved under: the same for the same rule on the same card, different if anything it says changes.
    A quarter rule's quote is left out: a calendar rewords a quarter as it comes round ("January 1 to March 31", then "now
    to March 31"), and all the rule says is in its dates, rate, categories and merchants."""
    left_out = ("pageHash", "quote") if rule.get("verified") == "calendar" else ("pageHash",)
    content = dict(rule, evidence={k: v for k, v in rule["evidence"].items() if k not in left_out})
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
        "rotating": f"{rate} in rotating bonus categories" + _period(rule, categories),
    }.get(rule["selection"], f"{rate} on {categories}")
    if rule.get("capAmount") is not None:
        period = "billing cycle" if rule["capPeriod"] == "cycle" else rule["capPeriod"]
        what += f", up to ${float(rule['capAmount']):,.0f} per {period}"
    return what


def _period(rule: dict, categories: str) -> str:
    """A rotating rule's categories for its quarter: " from 2026-10-01 to 2026-12-31: groceries, dining (also at American Red Cross®)"."""
    named = categories + (f" (also at {', '.join(rule['merchants'])})" if rule.get("merchants") else "")
    if rule.get("validFrom"):
        return f" from {rule['validFrom']} to {rule['validTo']}: {named.strip() or 'nothing named'}"
    return f" (this period: {named})" if named else ""


def load_options(path: Path = OPTIONS) -> dict:
    return fetch.read_json(path, {})


def set_option(card_id: str, name: str, value: bool, path: Path = OPTIONS, today: str = "") -> dict:
    """Turn one of CARD_OPTIONS on or off for a card. Off is the default, so it isn't kept. Returns every card's options."""
    if name not in CARD_OPTIONS:
        raise ValueError(f"A card option is one of {', '.join(CARD_OPTIONS)}")
    if not isinstance(value, bool):
        raise ValueError("A card option is on or off")
    options = load_options(path)
    mine = {k: v for k, v in options.get(card_id, {}).items() if k != "setAt"}
    mine.pop(name, None)
    if value:
        mine[name] = True
    if mine:
        options[card_id] = {**mine, "setAt": today}
    else:
        options.pop(card_id, None)
    fetch.write_json(path, options)
    return options


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
    if rule.get("verified") == "calendar":
        raise ValueError("A rule read from the quarterly calendar can't be fixed: reject it, and fix the rotating rule its rate comes from")
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
    if rule.get("verified") == "calendar":
        warnings.append("read from the page's quarterly calendar: its rate, cap and activation are the rotating rule's")
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


def quarter_status(candidate: dict, page_text: str, decisions: dict, today: str) -> dict:
    """Where a card with a rotating rule stands for the quarters that haven't ended by `today`. "waiting": each
    quarter rule (a rotating rule with dates) no person has decided on yet, in a few words: it isn't published until
    accepted. "decided": how many have a decision. "comingSoon": the {start, end} of each quarter its page marks
    "Coming Soon", which names nothing yet: the issuer hasn't said, so nothing has gone wrong. "rotating": whether the
    candidate still has a rotating rule at all."""
    rows = card_review(candidate, decisions)["rules"]
    ahead = [row for row in rows if row["rule"]["selection"] == "rotating" and row["rule"]["validFrom"]
             and (row["rule"]["validTo"] or today) >= today]
    return {
        "waiting": [row["summary"] for row in ahead if row["decision"] is None],
        "decided": sum(row["decision"] is not None for row in ahead),
        "comingSoon": [{"start": q.start, "end": q.end} for q in quarters.coming_soon(page_text) if q.end >= today],
        "rotating": any(row["rule"]["selection"] == "rotating" for row in rows),
    }


def accepted_rules(candidate: dict, decisions: dict | None = None) -> list[dict]:
    """The candidate's rules a person accepted, in the candidate's order, each as the person fixed it if they
    did. Rejected rules and rules still waiting for review are left out."""
    decisions = load_decisions() if decisions is None else decisions
    card_decisions = decisions.get(candidate["cardId"], {})
    saved = [card_decisions.get(rule_key(candidate["cardId"], r), {}) for r in candidate.get("rules", [])]
    return [entry.get("edited") or r for r, entry in zip(candidate.get("rules", []), saved) if entry.get("decision") == "accept"]
