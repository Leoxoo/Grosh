#!/usr/bin/env python3
"""The publish step: write the rules a person accepted into rewards-catalog.json, the one file the app reads.

    python3 tools/rewards-catalog/pipeline/publish.py

reads catalog-seed.json (the cards), cache/candidates/ (each card's rules), review-decisions.json (what
a person accepted) and card-options.json (whether a card's bonuses add up), and writes rewards-catalog.json
beside this script.
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


def catalog(cards: list[dict], candidates: dict[str, dict], decisions: dict, previous: dict | None, today: str,
            options: dict | None = None) -> dict:
    """The catalog the app reads: every seed card a person accepted at least one rule on, with only those
    rules, and its options (review.CARD_OPTIONS, off unless `options` turns them on). `previous` is the catalog published last time, or None. A card with no candidate (cache/ isn't
    committed, so a fresh clone has none) keeps its last published entry: failure never deletes."""
    before = {card["id"]: card for card in (previous or {}).get("cards", [])}
    published = []
    for card in sorted(cards, key=lambda c: c["id"]):
        candidate = candidates.get(card["id"])
        if candidate is None and card["id"] in before:
            published.append(before[card["id"]])
            continue
        rules = review.accepted_rules(candidate, decisions) if candidate else []
        if not rules:  # nobody has checked this card, so its seed facts aren't ours to ship
            continue
        card_decisions = decisions[card["id"]]
        published.append({
            **{field: card[field] for field in CARD_FIELDS},
            "verifiedAt": max(card_decisions[review.rule_key(card["id"], r)]["decidedAt"] for r in rules),
            "cardConditions": sorted(candidate.get("cardConditions", [])),
            **{name: bool((options or {}).get(card["id"], {}).get(name)) for name in review.CARD_OPTIONS},
            "rules": sorted((published_rule(r) for r in rules), key=lambda r: json.dumps(r, sort_keys=True)),
        })
    # The date says when the catalog last changed, so a rerun that changes nothing else keeps it.
    unchanged = previous and previous.get("formatVersion") == FORMAT_VERSION and previous.get("cards") == published
    return {"formatVersion": FORMAT_VERSION, "publishedAt": previous["publishedAt"] if unchanged else today, "cards": published}


# Where publish reads and writes: the seed, the candidates, the decisions, the card options and the catalog. ui.Paths has the same
# fields, for the web page's own (test) folders.
PATHS = SimpleNamespace(seed=SEED, candidates=extract.CANDIDATES, decisions=review.DECISIONS, options=review.OPTIONS, catalog=OUT)


def publish(paths=PATHS, today: str = "") -> dict:
    """Build the catalog from the files in `paths` and write it to `paths.catalog` (fetch.write_json: keys sorted,
    so equal catalogs are equal bytes). Returns what was written."""
    cards = fetch.read_json(paths.seed, {"cards": []})["cards"]
    found = {path.stem: fetch.read_json(path, None) for path in sorted(paths.candidates.glob("*.json"))}
    document = catalog(cards, found, review.load_decisions(paths.decisions), fetch.read_json(paths.catalog, None),
                       today or date.today().isoformat(), review.load_options(paths.options))
    fetch.write_json(paths.catalog, document)
    return document


def main() -> None:
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    document = publish()
    rules = sum(len(card["rules"]) for card in document["cards"])
    print(f"Wrote {len(document['cards'])} cards and {rules} accepted rules to {OUT}")


if __name__ == "__main__":
    main()
