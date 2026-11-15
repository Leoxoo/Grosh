#!/usr/bin/env python3
"""The publish step: write the rules a person accepted into rewards-catalog.json, the one file the app reads.

    python3 tools/rewards-catalog/pipeline/publish.py

reads catalog-seed.json (the cards), cache/candidates/ (each card's rules), review-decisions.json (what
a person accepted) and card-options.json (whether a card's bonuses add up), and writes rewards-catalog.json
beside this script, and a copy to Grosh/Resources/rewards-catalog.json, the file the app bundles.
"""

import json
import sys
from datetime import date
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).parent))
import extract  # noqa: E402
import fetch  # noqa: E402
import review  # noqa: E402

OUT = fetch.DATA / "rewards-catalog.json"
# The file the app bundles (RewardsCatalog.bundled): a copy of OUT, which nothing else keeps current, so publish writes both.
APP_FILE = Path(__file__).resolve().parents[3] / "Grosh" / "Resources" / "rewards-catalog.json"
SEED = fetch.SEED
# Raised when the file's shape changes in a way an older app can't read (a field renamed or retyped).
# Adding a field doesn't need it: the app's reader ignores fields it doesn't know.
FORMAT_VERSION = 1

# What the app needs of a card and of a rule. The rest (the page's hash, whether the quote was confirmed on
# the saved page, the seed's sourceHost and verified) was for the checks and the review, which are over by now.
CARD_FIELDS = ("id", "name", "issuer", "network", "isBusiness", "annualFee", "rewardKind", "rewardProgram", "baseEarnRate",
               "discontinued", "sourceUrl")
RULE_FIELDS = ("categories", "selection", "picks", "hasOtherChoices", "rate", "unit", "capAmount", "capPeriod",
               "capUnknown", "requires", "paysWith", "validFrom", "validTo", "firstMonths", "tier", "needs", "conditions", "merchants")


def number(value):
    """3.0 is written 3, so a model that says 3.0 doesn't change the file."""
    return int(value) if isinstance(value, float) and value.is_integer() else value


def published_rule(rule: dict) -> dict:
    published = {field: rule.get(field) for field in RULE_FIELDS}
    for field in review.SET_FIELDS:
        published[field] = sorted(published[field] or [])
    published["merchants"] = sorted(published["merchants"] or [])
    published["rate"], published["capAmount"] = number(published["rate"]), number(published["capAmount"])
    published["evidence"] = {"quote": rule["evidence"]["quote"], "url": rule["evidence"]["url"]}
    return published


def lost_rules(old: dict, candidate: dict, entries: list, decisions: dict) -> list[dict]:
    """The rules `old` (a card's published entry) would lose if it were rebuilt from `candidate`: each published rule that
    is neither still accepted (in `entries`), nor one a person rejected, nor replaced by a new accepted rule. A reworded
    quote is another rule (review.rule_key hashes it), so until the new wording is accepted, the old rule is lost.
    A page that failed or went to the wrong card has no rules, so it loses them all."""
    def text(rule):
        return json.dumps(published_rule(rule), sort_keys=True)
    now = {text(rule) for rule, _ in entries}
    rejected = {text(row["rule"]) for row in review.card_review(candidate, decisions)["rules"] if row["decision"] == "reject"}
    lost = [rule for rule in old.get("rules", []) if text(rule) not in now | rejected]
    new = len(now - {text(rule) for rule in old.get("rules", [])})  # accepted rules the old entry didn't have: they take a lost one's place
    return lost if candidate.get("status") in ("failed", "wrong-page") or len(lost) > new else []


def catalog(cards: list[dict], candidates: dict[str, dict], decisions: dict, previous: dict | None, today: str,
            options: dict | None = None, kept: list | None = None) -> dict:
    """The catalog the app reads: every seed card a person accepted at least one rule on, with only those
    rules, and its options (review.CARD_OPTIONS, off unless `options` turns them on). `previous` is the catalog published last time, or None.

    A failed run never deletes a published card. A card with no candidate (cache/ isn't committed, so a fresh clone has
    none) keeps its last published entry. So does a card whose candidate would lose a published rule that no person
    rejected and no new accepted rule replaces (`lost_rules`): the page redirected up to a listing ("wrong-page"), the
    fetch or extraction "failed", or the model reworded a quote, which makes the rule a new one that waits for review.
    Each such card is added to `kept` as
    {"id", "status", "lost"} (the rules it would have lost, as published), so publish can say what it held back.
    To drop a published rule on purpose, Reject it: a rejected rule is not lost."""
    before = {card["id"]: card for card in (previous or {}).get("cards", [])}
    published = []
    for card in sorted(cards, key=lambda c: c["id"]):
        candidate = candidates.get(card["id"])
        added = any("added" in entry for entry in decisions.get(card["id"], {}).values())
        if candidate is None and card["id"] in before and not added:
            published.append(before[card["id"]])
            continue
        shown = candidate or review.empty_candidate(card["id"])
        entries = review.accepted_entries(shown, decisions)
        lost = lost_rules(before[card["id"]], shown, entries, decisions) if candidate and card["id"] in before else []
        if lost:
            published.append(before[card["id"]])
            if kept is not None:
                kept.append({"id": card["id"], "status": candidate.get("status"), "lost": lost})
            continue
        if not entries:  # nobody has checked this card, so its seed facts aren't ours to ship
            continue
        published.append({
            **{field: card[field] for field in CARD_FIELDS},
            "verifiedAt": max(day for _, day in entries),
            "cardConditions": sorted(shown.get("cardConditions") or before.get(card["id"], {}).get("cardConditions", [])),
            **{name: bool((options or {}).get(card["id"], {}).get(name)) for name in review.CARD_OPTIONS},
            "rules": sorted((published_rule(r) for r, _ in entries), key=lambda r: json.dumps(r, sort_keys=True)),
        })
    # The date says when the catalog last changed, so a rerun that changes nothing else keeps it.
    unchanged = previous and previous.get("formatVersion") == FORMAT_VERSION and previous.get("cards") == published
    return {"formatVersion": FORMAT_VERSION, "publishedAt": previous["publishedAt"] if unchanged else today, "cards": published}


# Where publish reads and writes: the seed, the candidates, the decisions, the card options and the catalog. ui.Paths has the same
# fields, for the web page's own (test) folders.
PATHS = SimpleNamespace(seed=SEED, candidates=extract.CANDIDATES, decisions=review.DECISIONS, options=review.OPTIONS, catalog=OUT,
                  app_copy=APP_FILE)


def publish(paths=PATHS, today: str = "", kept: list | None = None) -> dict:
    """Build the catalog from the files in `paths` and write it to `paths.catalog` (fetch.write_json: keys sorted,
    so equal catalogs are equal bytes). Returns what was written. The cards it held back (see `catalog`) are added to `kept`."""
    cards = fetch.read_json(paths.seed, {"cards": []})["cards"]
    found = {path.stem: fetch.read_json(path, None) for path in sorted(paths.candidates.glob("*.json"))}
    document = catalog(cards, found, review.load_decisions(paths.decisions), fetch.read_json(paths.catalog, None),
                       today or date.today().isoformat(), review.load_options(paths.options), kept)
    fetch.write_json(paths.catalog, document)
    if getattr(paths, "app_copy", None):  # the app bundles this copy: without it a published catalog never reaches a build
        fetch.write_json(paths.app_copy, document)
    return document


def held_back(kept: list) -> str:
    """What to tell the person about the cards publish left as they were, one line each, or "" if there were none."""
    return "".join(f"Kept {card['id']} as published ({card['status'] or 'no status'}): the new candidate would lose "
                   f"{len(card['lost'])} published rule(s), e.g. {card['lost'][0]['evidence']['quote'][:80]!r}. "
                   "Fix the page or the review, or Reject a rule to drop it.\n" for card in kept)


def main() -> None:
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    kept = []
    document = publish(kept=kept)
    rules = sum(len(card["rules"]) for card in document["cards"])
    print(f"Wrote {len(document['cards'])} cards and {rules} accepted rules to {OUT}")
    print(held_back(kept), end="")


if __name__ == "__main__":
    main()
