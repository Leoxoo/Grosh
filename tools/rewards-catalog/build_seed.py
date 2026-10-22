#!/usr/bin/env python3
"""Build the rewards catalog's seed from CardPin's raw_import.csv.

    python3 tools/rewards-catalog/build_seed.py raw_import.csv

reads CardPin's CSV (MIT, https://github.com/strike007-3000/cardpin) and writes
tools/rewards-catalog/catalog-seed.json beside this script.

The seed keeps only facts about each card: who issues it, its fee, its flat
earn rate and the issuer page to re-check. It drops everything we have no right
or reason to ship: the imageUrl column (hotlinked from offeroptimist.com, and
the art is the issuers'), CardPin's cardId (someone else's key), and the
sign-up bonus, credits and offer columns (stale within months).

Every card comes out unverified. A card becomes verified only when the refresh
pipeline (PIPELINE.md) has read its issuer page and a person has accepted what
it found.
"""

import csv
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

OUT = Path(__file__).with_name("catalog-seed.json")
# Hand-fixed issuer pages, {card id: url}, for cards whose CardPin url has moved. Kept apart
# from the seed so that rebuilding the seed from a fresh CSV doesn't undo the fixes.
URL_OVERRIDES = Path(__file__).with_name("url-overrides.json")
# Cards CardPin doesn't have (Apple Card, for one), added by hand: a list of objects with
# EXTRA_REQUIRED's keys. They join the seed like any other card.
EXTRA_CARDS = Path(__file__).with_name("extra-cards.json")

# CardPin's issuer codes, as people would write them.
ISSUER_NAMES = {
    "AMERICAN_EXPRESS": "American Express",
    "BANK_OF_AMERICA": "Bank of America",
    "BARCLAYS": "Barclays",
    "CHASE": "Chase",
    "CAPITAL_ONE": "Capital One",
    "CITI": "Citi",
    "COMENITY": "Comenity",
    "DISCOVER": "Discover",
    "FIRST": "First Bankcard",
    "FNBO": "FNBO",
    "PENFED": "PenFed",
    "SYNCHRONY": "Synchrony",
    "TD": "TD Bank",
    "US_BANK": "U.S. Bank",
    "WELLS_FARGO": "Wells Fargo",
    "WEB_BANK": "WebBank",
}

NETWORK_NAMES = {
    "AMERICAN_EXPRESS": "American Express",
    "DISCOVER": "Discover",
    "MASTERCARD": "Mastercard",
    "VISA": "Visa",
}


# Programs whose own name for what you earn is "miles". Every other program is
# "points": hotels, banks, and airlines that say points (JetBlue, Southwest, Spirit,
# Aeroplan, Avios, Virgin, Breeze). Labels follow how each program calls its currency
# today; they are a display unit, so a wrong one is cosmetic, not a wrong rate.
MILES_PROGRAMS = frozenset({
    "ALASKA", "AMERICAN", "ANA", "AVIANCA", "CAPITAL_ONE", "CATHAY_PACIFIC", "DELTA",
    "EMIRATES", "FLYING_BLUE", "FRONTIER", "HAWAIIAN", "KOREAN", "LATAM", "LUFTHANSA", "UNITED",
})
POINTS_PROGRAMS = frozenset({
    "AEROPLAN", "AMERICAN_EXPRESS", "AMTRAK", "AVIOS", "BANK_OF_AMERICA", "BARCLAYS",
    "BEST_WESTERN", "BREEZE", "CARNIVAL", "CHASE", "CHOICE", "CITI", "EXPEDIA", "HILTON",
    "HYATT", "IHG", "JETBLUE", "MARRIOTT", "PENFED", "SOUTHWEST", "SPIRIT", "US_BANK",
    "VIRGIN", "WELLS_FARGO", "WYNDHAM",
})


def reward_kind(currency: str) -> str:
    """What the card's flat earn rate is measured in: "cashback", "points" or "miles".

    CardPin's `currency` column is "USD" for a cash-back card and otherwise names a
    reward program. A program this script has never seen stops the run instead of
    defaulting to a guess, because the seed is meant to be rerun: a new CSV that
    brings a 42nd program should make someone classify it, not slip through mislabeled.
    """
    if currency == "USD":
        return "cashback"
    if currency in MILES_PROGRAMS:
        return "miles"
    if currency in POINTS_PROGRAMS:
        return "points"
    raise ValueError(f"Unknown reward program {currency!r}: add it to MILES_PROGRAMS or POINTS_PROGRAMS")


def slug(text: str) -> str:
    # "+" is part of a card's identity (One Key vs. One Key+), so spell it out first.
    return re.sub(r"[^a-z0-9]+", "-", text.lower().replace("+", " plus ")).strip("-")


def number(text: str) -> float | int:
    value = float(text)
    return int(value) if value.is_integer() else value


EXTRA_REQUIRED = ("name", "issuer", "network", "isBusiness", "annualFee", "rewardKind", "rewardProgram", "baseEarnRate", "sourceUrl")


def extra_card(entry: dict) -> dict:
    """A card added by hand in extra-cards.json, in the seed's shape. Its id comes from issuer and name,
    like every other card's, so it can't be given a different one."""
    missing = [key for key in EXTRA_REQUIRED if key not in entry]
    if missing:
        sys.exit(f"extra-cards.json: {entry.get('name', entry)!r} is missing {missing}")
    if entry["rewardKind"] not in ("cashback", "points", "miles"):
        sys.exit(f"extra-cards.json: {entry['name']!r} has rewardKind {entry['rewardKind']!r}, not cashback, points or miles")
    return {
        "id": slug(f'{entry["issuer"]} {entry["name"]}'),
        **{key: entry[key] for key in EXTRA_REQUIRED},
        "discontinued": entry.get("discontinued", False),
        "sourceHost": urlparse(entry["sourceUrl"]).netloc,
        "verified": False,
    }


def build(
    rows: list[dict[str, str]], url_overrides: dict[str, str] | None = None, extra_cards: list[dict] | None = None
) -> list[dict]:
    url_overrides = url_overrides or {}
    cards: dict[str, dict] = {}
    for row in rows:
        # A card with several sign-up offers has several rows that differ only in
        # the offer columns we drop, so the first row of each card is enough.
        source_id = row["cardId"]
        if source_id in cards:
            continue
        issuer = ISSUER_NAMES[row["issuer"]]
        cards[source_id] = {
            "id": slug(f'{issuer} {row["name"]}'),
            "name": row["name"],
            "issuer": issuer,
            "network": NETWORK_NAMES[row["network"]],
            "isBusiness": row["isBusiness"] == "true",
            "annualFee": number(row["annualFee"]),
            "rewardKind": reward_kind(row["currency"]),
            "rewardProgram": None if row["currency"] == "USD" else row["currency"],
            "baseEarnRate": number(row["universalCashbackPercent"]),
            "discontinued": row["discontinued"] == "true",
            "sourceUrl": row["url"],
            "sourceHost": urlparse(row["url"]).netloc,
            "verified": False,
        }
    catalog = sorted([*cards.values(), *map(extra_card, extra_cards or [])], key=lambda card: card["id"])
    ids = [card["id"] for card in catalog]
    unknown = sorted(set(url_overrides) - set(ids))
    if unknown:
        sys.exit(f"url-overrides.json names cards that aren't in the CSV: {unknown}")
    for card in catalog:
        if card["id"] in url_overrides:
            card["sourceUrl"] = url_overrides[card["id"]]
            card["sourceHost"] = urlparse(card["sourceUrl"]).netloc
    duplicates = {i for i in ids if ids.count(i) > 1}
    if duplicates:
        sys.exit(f"Two cards share an id, so one would overwrite the other: {sorted(duplicates)}")
    return catalog


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], newline="", encoding="utf-8") as file:
        overrides = json.loads(URL_OVERRIDES.read_text(encoding="utf-8")) if URL_OVERRIDES.exists() else {}
        extras = json.loads(EXTRA_CARDS.read_text(encoding="utf-8")) if EXTRA_CARDS.exists() else []
        catalog = build(list(csv.DictReader(file)), overrides, extras)
    document = {
        "seededFrom": "CardPin raw_import.csv (MIT)",
        "cards": catalog,
    }
    OUT.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(catalog)} cards to {OUT}")


if __name__ == "__main__":
    main()
