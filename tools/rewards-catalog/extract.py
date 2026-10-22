#!/usr/bin/env python3
"""Propose each card's reward rules by asking a local model to read its cached page.

    python3 tools/rewards-catalog/extract.py --only capital-one-savor
    python3 tools/rewards-catalog/extract.py --issuer "capital one" --limit 5
    python3 tools/rewards-catalog/extract.py            # every card with a fetched page

Needs LM Studio's local server running (Developer tab, Start Server) with the model
loaded. Defaults: http://localhost:1234/v1 and k2-horizon-7b-uno-uncensored; change them
with --base-url / --model or the LM_STUDIO_URL / LM_STUDIO_MODEL environment variables.

For each card it reads cache/<id>/latest.txt (written by fetch.py), asks the model for
rules in chunks, and writes cache/candidates/<id>.json. The model only PROPOSES. A rule
is kept only if validate_rule can check it against the page without trusting the model:
its quote must appear on the page word for word, and the rate (and any cap) must appear
inside that quote. Anything else is listed under "rejected" with the reason, never fixed.

A card whose page doesn't name the card is "wrong-page" and gets no rules: Amex's state
holds many cards' marketing, and a redirect can land on a different card's page.

Rules for cards whose pages hide them (or that need a person's judgment) are entered by
hand in manual-rules.json, in the same shape, and go through the same checks. A hand-entered
rule whose quote is on the cached page is marked verified "page"; otherwise "manual".

Re-running skips a model-read card whose page, model and prompt are unchanged.
"""

import argparse
import json
import os
import re
import sys
import unicodedata
import urllib.request
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import fetch  # noqa: E402

CANDIDATES = fetch.CACHE / "candidates"
MANUAL_RULES = Path(__file__).with_name("manual-rules.json")
PROMPT_VERSION = "3"
DEFAULT_URL = "http://localhost:1234/v1"
DEFAULT_MODEL = "k2-horizon-7b-uno-uncensored"
CHUNK_CHARS = 12_000
CHUNK_OVERLAP_LINES = 3
MAX_RATE = 10
MAX_CONDITIONS = 5
MAX_CARD_CONDITIONS = 8
MAX_CONDITION_CHARS = 400
ATTEMPTS_PER_CHUNK = 2

# The catalog's fixed categories (PIPELINE.md), each with words a quote about it would use.
# A quote that uses none of them is filed under the wrong category.
CATEGORIES = {
    "dining": ("dining", "restaurant", "takeout", "take out", "food", "bars", "eating out"),
    "groceries": ("grocer", "supermarket", "food at home"),
    "gas": ("gas", "fuel", "charging", "service station"),
    "travel": ("travel", "flight", "airline", "hotel", "rental car", "car rental", "cruise", "vacation",
               "airfare", "lodging", "trip", "airport"),
    "transit": ("transit", "rideshare", "ride share", "ride-hailing", "taxi", "train", "buses", "parking",
                "toll", "commut", "uber", "lyft"),
    "streaming": ("streaming", "netflix", "spotify", "hulu", "disney"),
    "drugstores": ("drugstore", "drug store", "pharmac", "cvs", "walgreens"),
    "online-shopping": ("online", "amazon", "e-commerce", "internet retail"),
    "utilities": ("utilit", "phone", "wireless", "cable", "internet", "electric", "cell"),
    "everything-else": ("all other", "everything else", "other purchase", "other eligible", "every purchase",
                        "every $1", "every dollar", "all purchase", "all eligible", "everywhere", "each purchase",
                        "all your purchase", "on all", "on every"),
}
CATEGORY_HELP = {
    "dining": "restaurants, takeout, delivery, bars",
    "groceries": "grocery stores and supermarkets",
    "gas": "gas stations and fuel, including EV charging",
    "travel": "airlines, hotels, car rentals, cruises and travel booked through the issuer",
    "transit": "rideshare, taxis, trains, buses, parking, tolls",
    "streaming": "streaming services",
    "drugstores": "drugstores and pharmacies",
    "online-shopping": "online shopping and online retail",
    "utilities": "phone, internet, cable and utility bills",
    "everything-else": "the base rate on all other purchases",
}
PERIOD_WORDS = {"month": ("month",), "quarter": ("quarter",), "year": ("year", "annual")}

# Who decides which categories earn a rate. "fixed": the rate always applies to its one category.
# "choose": the cardholder picks (Bank of America Customized Cash). "top-spend": the card applies
# it to the eligible category where the cardholder spends most (Citi Custom Cash).
SELECTIONS = ("fixed", "choose", "top-spend")
SELECTION_WORDS = {
    "choose": ("choice", "choose", "choosing", "chosen", "select", "pick"),
    "top-spend": ("top", "highest", "most", "greatest"),
}
# What a rate can require beyond the purchase itself, and the words that must back the tag up.
REQUIRES = {
    "apple-pay": ("apple pay",),
    "activation": ("activate", "activation", "enroll"),
    "issuer-booking": ("booked through", "booked with", "book through", "book with", "booking through",
                       "purchased through", "portal"),
}
MONTHS = ("january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
          "november", "december")

RULE_SCHEMA = {
    "type": "object",
    "properties": {
        "categories": {"type": "array", "items": {"type": "string", "enum": list(CATEGORIES)}, "minItems": 1},
        "selection": {"type": "string", "enum": list(SELECTIONS)},
        "picks": {"type": ["integer", "null"]},
        "hasOtherChoices": {"type": "boolean"},
        "rate": {"type": "number"},
        "unit": {"type": "string", "enum": ["percent", "per-dollar"]},
        "capAmount": {"type": ["number", "null"]},
        "capPeriod": {"type": ["string", "null"], "enum": ["month", "quarter", "year", None]},
        "requires": {"type": "array", "items": {"type": "string", "enum": list(REQUIRES)}},
        "validFrom": {"type": ["string", "null"]},
        "validTo": {"type": ["string", "null"]},
        "quote": {"type": "string"},
        "conditions": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["categories", "selection", "picks", "hasOtherChoices", "rate", "unit", "capAmount", "capPeriod",
                 "requires", "validFrom", "validTo", "quote", "conditions"],
    "additionalProperties": False,
}
SCHEMA = {
    "type": "object",
    "properties": {
        "cardConditions": {"type": "array", "items": {"type": "string"}},
        "rules": {"type": "array", "items": RULE_SCHEMA},
    },
    "required": ["cardConditions", "rules"],
    "additionalProperties": False,
}


# --- Reading the page ------------------------------------------------------------------


def chunk_lines(text: str, max_chars: int = CHUNK_CHARS, overlap: int = CHUNK_OVERLAP_LINES) -> list[str]:
    """Consecutive lines grouped to fit the model's context, each chunk repeating the last few
    lines of the one before so a sentence split across the boundary is whole in one of them."""
    lines: list[str] = []
    for line in text.splitlines():
        lines += [line[i : i + max_chars] for i in range(0, len(line), max_chars)] or [""]
    chunks: list[str] = []
    current: list[str] = []
    size = 0
    for line in lines:
        if current and size + len(line) + 1 > max_chars:
            chunks.append("\n".join(current))
            current = current[-overlap:] if overlap else []
            size = sum(len(kept) + 1 for kept in current)
            while current and size + len(line) + 1 > max_chars:  # the overlap must not crowd out the next line
                size -= len(current.pop(0)) + 1
        current.append(line)
        size += len(line) + 1
    if current:
        chunks.append("\n".join(current))
    return chunks


_RATE_LOOKING = re.compile(r"\d\s*(?:%|[xX]\b)|\bper (?:\$1|dollar)\b", re.I)


def has_rates(chunk: str) -> bool:
    """Whether a chunk could state a rate at all, so we don't ask the model about navigation menus."""
    return bool(_RATE_LOOKING.search(chunk))


def normalize(text: str) -> str:
    """Text for comparing a quote to a page: same letters, ignoring case, spacing, curly quotes,
    dashes and the (R)/(TM) marks issuers scatter through names."""
    text = unicodedata.normalize("NFKC", text)
    text = text.translate({ord(c): "'" for c in "‘’′"} | {ord(c): '"' for c in "“”"} | {ord(c): "-" for c in "–—−"})
    text = re.sub("[®™℠©†‡​‌‍﻿]", "", text)
    return " ".join(text.casefold().split())


def _alnum_words(text: str) -> list[str]:
    return re.sub(r"[^a-z0-9]+", " ", normalize(text)).split()


def name_on_page(name: str, page_text: str) -> bool:
    """Whether the card's name appears on its page, as a phrase or with every word of it present."""
    words = _alnum_words(name)
    if not words:
        return False
    page_words = _alnum_words(page_text)
    padded = " " + " ".join(page_words) + " "
    return f" {' '.join(words)} " in padded or set(words) <= set(page_words)


_NUMBER = re.compile(r"(\d[\d,]*(?:\.\d+)?)\s*([kKmM]\b)?")


def numbers_in(text: str) -> set[float]:
    """Every number in the text, as a value: 6,000 and 6K and $6k are all 6000."""
    found: set[float] = set()
    for digits, suffix in _NUMBER.findall(text):
        try:
            value = float(digits.replace(",", "").rstrip("."))
        except ValueError:
            continue
        found.add(value * {"k": 1_000, "m": 1_000_000}.get(suffix.lower(), 1))
    return found


def mentions(text: str, words: tuple[str, ...]) -> bool:
    """Whether any word starts a word in the text ("grocer" matches "grocery"; "gas" doesn't match "vegas")."""
    return any(re.search(r"(?<![a-z0-9])" + re.escape(word), text) for word in words)


# --- Checking what the model said ---------------------------------------------------------


def _category_fits(category: str, quote_norm: str) -> bool:
    if mentions(quote_norm, CATEGORIES[category]):
        return True
    # "Get 2% back when you use Apple Pay" is a base rate without saying "all other purchases":
    # it fits if it names no other category.
    return category == "everything-else" and not any(
        mentions(quote_norm, words) for name, words in CATEGORIES.items() if name != category
    )


def _date_problem(label: str, value, text: str) -> str | None:
    """Why a validFrom / validTo isn't backed by the quote and conditions, or None. The year and the
    month's name must appear there: a date the page doesn't give can't be made up."""
    if value is None:
        return None
    try:
        day = date.fromisoformat(value)
    except (TypeError, ValueError):
        return f"{label} {value!r} is not a date like 2026-10-01"
    month = MONTHS[day.month - 1]
    if float(day.year) not in numbers_in(text):
        return f"{label} year {day.year} is not in the quote"
    if not re.search(rf"(?<![a-z]){month}(?![a-z])|(?<![a-z]){month[:3]}\.?(?![a-z])", text):
        return f"{label} month {month} is not in the quote"
    return None


def check_condition(condition, page_norm: str | None) -> str | None:
    """Why a condition can't be kept, or None. Conditions are shown as the issuer wrote them, so each
    must be the issuer's own words (when the page is available to check against)."""
    if not isinstance(condition, str) or not condition.strip() or len(condition) > MAX_CONDITION_CHARS:
        return f"a condition is empty or over {MAX_CONDITION_CHARS} characters"
    if page_norm is not None and normalize(condition) not in page_norm:
        return "a condition is not on the page word for word"
    return None


def validate_rule(rule, page_norm: str | None = None) -> str | None:
    """Why a proposed rule can't be kept, or None if every check holds. Nothing here trusts the model.

    With `page_norm` (the normalized page text) the quote and conditions must be on that page. Without
    it, only the checks that don't need the page run: used for hand-entered rules."""
    if not isinstance(rule, dict):
        return "not an object"
    categories, selection, picks = rule.get("categories"), rule.get("selection"), rule.get("picks")
    other, rate, unit = rule.get("hasOtherChoices"), rule.get("rate"), rule.get("unit")
    quote, cap, period = rule.get("quote"), rule.get("capAmount"), rule.get("capPeriod")
    requires, conditions = rule.get("requires"), rule.get("conditions")

    if selection not in SELECTIONS:
        return f"selection {selection!r} is not fixed, choose or top-spend"
    if (
        not isinstance(categories, list)
        or not categories
        or not all(isinstance(c, str) and c in CATEGORIES for c in categories)
        or len(set(categories)) != len(categories)
    ):
        return "categories must be distinct categories from the catalog's list"
    if not isinstance(other, bool):
        return "hasOtherChoices must be true or false"
    if selection == "fixed":
        if len(categories) != 1 or picks is not None or other:
            return "a fixed rule has one category, no picks and no other choices"
    else:
        if "everything-else" in categories:
            return "everything-else can't be one of the categories to choose from"
        if isinstance(picks, bool) or not isinstance(picks, int) or picks < 1:
            return "picks must be a whole number from 1"
        if len(categories) < 2 and not other:
            return f"a {selection} rule needs at least two choices"
        if picks > len(categories) and not other:
            return "picks is more than the categories listed"
    if unit not in ("percent", "per-dollar"):
        return f"unit {unit!r} is not percent or per-dollar"
    if isinstance(rate, bool) or not isinstance(rate, (int, float)) or not 0 < rate <= MAX_RATE:
        return f"rate {rate!r} is not a number from 0 to {MAX_RATE}"
    if not isinstance(quote, str) or not quote.strip():
        return "no quote"
    if cap is not None and (isinstance(cap, bool) or not isinstance(cap, (int, float)) or cap <= 0):
        return f"cap {cap!r} is not a positive number"
    if period not in (None, *PERIOD_WORDS):
        return f"cap period {period!r} is not month, quarter or year"
    if (cap is None) != (period is None):
        return "a cap needs both an amount and a period"
    if (
        not isinstance(requires, list)
        or not all(isinstance(tag, str) and tag in REQUIRES for tag in requires)
        or len(set(requires)) != len(requires)
    ):
        return f"requires must be some of {', '.join(REQUIRES)}"
    if not isinstance(conditions, list) or len(conditions) > MAX_CONDITIONS:
        return f"conditions must be a list of at most {MAX_CONDITIONS} quotes"
    for condition in conditions:
        problem = check_condition(condition, page_norm)
        if problem:
            return problem  # a rule with a made-up condition is dropped whole: its rate would overstate

    quote_norm = normalize(quote)
    if page_norm is not None and quote_norm not in page_norm:
        return "quote is not on the page word for word"
    if float(rate) not in numbers_in(quote):
        return f"rate {rate} is not in the quote"
    if unit == "percent" and "%" not in quote:
        return "unit is percent but the quote has no %"
    if unit == "per-dollar" and not re.search(r"\d\s*[xX]\b|\bpoints?\b|\bmiles?\b|\bper (?:\$1|dollar)", quote):
        return "unit is per-dollar but the quote has no points, miles or X"

    context = " ".join([quote_norm, *map(normalize, conditions)])
    if selection == "fixed":
        if not _category_fits(categories[0], quote_norm):
            return f"quote doesn't mention {categories[0]}"
    else:
        if not mentions(quote_norm, SELECTION_WORDS[selection]):
            return f"quote doesn't say who chooses ({selection})"
        haystack = page_norm if page_norm is not None else context
        for category in categories:
            if not mentions(haystack, CATEGORIES[category]):
                return f"{category} is not mentioned on the page"
    if cap is not None:
        if float(cap) not in numbers_in(quote):
            return f"cap {cap} is not in the quote"
        if not mentions(quote_norm, PERIOD_WORDS[period]):
            return f"cap period {period} is not in the quote"
    for tag in requires:
        if not mentions(context, REQUIRES[tag]):
            return f"requires {tag}, but neither the quote nor a condition says so"
    valid_from, valid_to = rule.get("validFrom"), rule.get("validTo")
    problem = _date_problem("validFrom", valid_from, context) or _date_problem("validTo", valid_to, context)
    if problem:
        return problem
    if valid_from and valid_to and valid_from > valid_to:
        return "validFrom is after validTo"
    return None


# --- Asking the model -----------------------------------------------------------------------

SYSTEM_PROMPT = "You extract credit card reward rules from web page text. Reply with JSON only."


def build_messages(card: dict, chunk: str) -> list[dict]:
    categories = "\n".join(f"  - {name}: {CATEGORY_HELP[name]}" for name in CATEGORIES)
    unit = {"cashback": "cash back percent", "points": "points per dollar", "miles": "miles per dollar"}[card["rewardKind"]]
    user = f"""Card: {card["name"]} (issued by {card["issuer"]}; it earns {unit}).

Find the rates this card earns on purchases, in the text below.

Rules:
- Only rates for THIS card, "{card["name"]}". The text may also describe other cards; ignore their rates.
- One entry per rate. categories must come from this list:
{categories}
  Skip a rate that fits none of these, and a rate for one named store.
- selection: "fixed" when the rate always applies to one category (list exactly that one). "choose" when the cardholder picks which categories earn the rate. "top-spend" when the card applies the rate by itself to the eligible category where the cardholder spends the most. For "choose" and "top-spend", list every eligible category that is in the list above, set picks to how many categories earn the rate (1 for "your top category"), and set hasOtherChoices to true if the text also lists eligible categories that are not in the list above. For "fixed", picks is null and hasOtherChoices is false.
- rate: the number alone (3 for "3%" and for "3X points").
- unit: "percent" for cash back percent, "per-dollar" for points or miles per dollar.
- quote: copy the exact words of one sentence or phrase from the text that states the rate. Do not change, shorten or join them.
- capAmount and capPeriod: only if that same sentence limits how much spending earns the rate (for "up to $6,000 per year": 6000 and "year"). Otherwise null for both.
- requires: only what the text says the rate needs. "apple-pay" (must pay with Apple Pay), "activation" (must activate or enroll), "issuer-booking" (must book through the issuer's travel site or portal). Otherwise [].
- validFrom and validTo: for a rate that applies only in a stated period, its first and last day as YYYY-MM-DD, and only when the text names the months and the year (October through December 2026 is 2026-10-01 and 2026-12-31). Otherwise null.
- conditions: copy, word for word, each sentence in the text that excludes or restricts this one rate: excluded stores, a minimum, who qualifies. These are often in footnotes, which repeat the rate with its exclusions. Never paraphrase. Use [] if there are none.
- cardConditions (at the top level, not in a rule): copy, word for word, each sentence that limits several of this card's rates at once, such as how stores get categorized or limits on digital wallets. Do not repeat them in a rule's conditions. Use [] if there are none.
- Ignore sign-up bonuses, statement credits, APRs, fees, and what points are worth.
- If the text states no rate for this card, reply {{"cardConditions": [], "rules": []}}.

Text:
\"\"\"
{chunk}
\"\"\""""
    return [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": user}]


def parse_reply(content: str) -> tuple[list, list]:
    """The model's (rules, cardConditions), or ValueError if it did not reply with the shape we asked for."""
    content = content.strip()
    content = re.sub(r"^```(?:json)?\s*|\s*```$", "", content)
    value = json.loads(content)
    if not isinstance(value, dict) or not isinstance(value.get("rules"), list):
        raise ValueError('reply is not {"cardConditions": [...], "rules": [...]}')
    card_conditions = value.get("cardConditions", [])
    if not isinstance(card_conditions, list):
        raise ValueError("cardConditions is not a list")
    return value["rules"], card_conditions


class LMStudio:
    """LM Studio's OpenAI-compatible server."""

    def __init__(self, base_url: str, model: str, timeout: float = 300, urlopen=urllib.request.urlopen) -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout = timeout
        self.urlopen = urlopen

    def models(self) -> list[str]:
        with self.urlopen(f"{self.base_url}/models", timeout=10) as reply:
            return [entry["id"] for entry in json.load(reply)["data"]]

    def complete(self, messages: list[dict]) -> str:
        body = {
            "model": self.model,
            "messages": messages,
            "temperature": 0,
            "max_tokens": 3000,
            "response_format": {"type": "json_schema", "json_schema": {"name": "rules", "strict": True, "schema": SCHEMA}},
        }
        request = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
        )
        with self.urlopen(request, timeout=self.timeout) as reply:
            data = json.load(reply)
        try:
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as problem:
            raise ValueError(f"unexpected reply from LM Studio: {problem}") from problem


# --- One card ---------------------------------------------------------------------------------


def accepted_rule(proposal: dict, url: str, page_hash: str | None, verified: str) -> dict:
    """A rule as the candidate stores it. `verified` is "page" when its quote was found on the page and
    "manual" when a person entered it and the page could not confirm the quote."""
    return {
        "categories": list(proposal["categories"]),
        "selection": proposal["selection"],
        "picks": proposal["picks"],
        "hasOtherChoices": proposal["hasOtherChoices"],
        "rate": proposal["rate"],
        "unit": proposal["unit"],
        "capAmount": proposal["capAmount"],
        "capPeriod": proposal["capPeriod"],
        "requires": list(proposal["requires"]),
        "validFrom": proposal["validFrom"],
        "validTo": proposal["validTo"],
        "conditions": [c.strip() for c in proposal["conditions"]],
        "verified": verified,
        "evidence": {"quote": proposal["quote"].strip(), "url": url, "pageHash": page_hash},
    }


def _rule_key(rule: dict) -> tuple:
    return (
        tuple(rule["categories"]), rule["selection"], rule["picks"], float(rule["rate"]), rule["unit"],
        rule["capAmount"], rule["capPeriod"], tuple(rule["requires"]), rule["validFrom"], rule["validTo"],
    )


def _empty_candidate(card: dict, model: str, prompt_version: str | None, page_hash: str | None, status: str) -> dict:
    return {
        "cardId": card["id"], "model": model, "promptVersion": prompt_version, "pageHash": page_hash,
        "status": status, "cardConditions": [], "rules": [], "rejected": [],
    }


def extract_card(card: dict, text: str, page_hash: str, complete, model: str, max_chars: int = CHUNK_CHARS) -> dict:
    """The candidate for one card: accepted rules, card-wide conditions, rejected proposals with reasons,
    and a status: ok, no-rules (the page states none), wrong-page (it doesn't name the card) or failed
    (the model could not be read for at least one chunk, so the result is incomplete)."""
    candidate = _empty_candidate(card, model, PROMPT_VERSION, page_hash, "ok")
    if not name_on_page(card["name"], text):
        candidate["status"] = "wrong-page"
        return candidate

    page_norm = normalize(text)
    accepted: dict[tuple, dict] = {}
    failures = 0
    for chunk in (c for c in chunk_lines(text, max_chars) if has_rates(c)):
        reply = None
        for _ in range(ATTEMPTS_PER_CHUNK):
            try:
                reply = parse_reply(complete(build_messages(card, chunk)))
                break
            except (OSError, ValueError):
                reply = None
        if reply is None:
            failures += 1
            continue
        proposals, card_conditions = reply
        for proposal in proposals:
            reason = validate_rule(proposal, page_norm)
            if reason:
                candidate["rejected"].append({"rule": proposal, "reason": reason})
                continue
            rule = accepted_rule(proposal, card["sourceUrl"], page_hash, "page")
            entry = accepted.setdefault(_rule_key(rule), rule)
            # The same rate seen in another chunk may carry a condition this chunk didn't have.
            entry["conditions"] += [c for c in rule["conditions"] if c not in entry["conditions"]]
        for condition in card_conditions:
            problem = check_condition(condition, page_norm) or (
                None if len(candidate["cardConditions"]) < MAX_CARD_CONDITIONS else "too many card conditions"
            )
            if problem:
                candidate["rejected"].append({"cardCondition": condition, "reason": problem})
            elif condition.strip() not in candidate["cardConditions"]:
                candidate["cardConditions"].append(condition.strip())
    candidate["rules"] = sorted(accepted.values(), key=lambda r: (r["categories"][0], -r["rate"]))
    if failures:
        candidate["status"] = "failed"
    elif not accepted:
        candidate["status"] = "no-rules"
    return candidate


def manual_candidate(card: dict, entry: dict, text: str | None, page_hash: str | None) -> dict:
    """The candidate for a card whose rules a person entered (manual-rules.json), checked the same way
    but without needing the page. A rule is "page" verified when its quote is on the cached page, else
    "manual". Rules that break the shape rules (bad category, rate not in the quote...) are rejected."""
    candidate = _empty_candidate(card, "manual", None, page_hash, "manual")
    page_norm = normalize(text) if text else None
    for proposal in entry.get("rules", []):
        problem = validate_rule(proposal, None)
        if problem:
            candidate["rejected"].append({"rule": proposal, "reason": problem})
            continue
        grounded = page_norm is not None and validate_rule(proposal, page_norm) is None
        candidate["rules"].append(accepted_rule(proposal, card["sourceUrl"], page_hash, "page" if grounded else "manual"))
    for condition in entry.get("cardConditions", []):
        problem = check_condition(condition, None)
        if problem:
            candidate["rejected"].append({"cardCondition": condition, "reason": problem})
        else:
            candidate["cardConditions"].append(condition.strip())
    candidate["cardConditionsOnPage"] = page_norm is not None and all(
        normalize(c) in page_norm for c in candidate["cardConditions"]
    )
    if not candidate["rules"]:
        candidate["status"] = "no-rules"
    return candidate


def up_to_date(path: Path, page_hash: str, model: str) -> bool:
    previous = fetch.read_json(path, None)
    return bool(
        previous
        and previous.get("status") != "failed"
        and (previous.get("pageHash"), previous.get("model"), previous.get("promptVersion")) == (page_hash, model, PROMPT_VERSION)
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Propose reward rules from fetched pages, using LM Studio.")
    parser.add_argument("--only", nargs="+", default=[], metavar="ID")
    parser.add_argument("--issuer", default="")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--force", action="store_true", help="redo cards whose page, model and prompt are unchanged")
    parser.add_argument("--base-url", default=os.environ.get("LM_STUDIO_URL", DEFAULT_URL))
    parser.add_argument("--model", default=os.environ.get("LM_STUDIO_MODEL", DEFAULT_MODEL))
    parser.add_argument("--chunk-chars", type=int, default=CHUNK_CHARS, help="page text sent to the model at a time")
    args = parser.parse_args()

    cards = fetch.read_json(fetch.SEED, {"cards": []})["cards"]
    state = fetch.read_json(fetch.STATE, {})
    manual = fetch.read_json(MANUAL_RULES, {})
    unknown = sorted(set(manual) - {card["id"] for card in cards})
    if unknown:
        sys.exit(f"manual-rules.json names cards that aren't in the seed: {unknown}")

    def page_path(card: dict) -> Path:
        return fetch.CACHE / card["id"] / "latest.txt"

    def fetched(card: dict) -> bool:
        return bool(state.get(card["id"], {}).get("hash")) and page_path(card).exists()

    chosen = [c for c in fetch.select(cards, args.only, args.issuer, None) if fetched(c) or c["id"] in manual]
    chosen = chosen[: args.limit] if args.limit else chosen
    if not chosen:
        sys.exit("No fetched pages match. Run fetch.py first.")

    client = LMStudio(args.base_url, args.model)
    server_checked = False

    def check_server() -> None:
        try:
            available = client.models()
        except (OSError, ValueError, KeyError) as problem:
            sys.exit(f"LM Studio isn't answering at {args.base_url} ({problem}). Start its local server (Developer tab).")
        if args.model not in available:
            sys.exit(f"LM Studio has no model {args.model!r}. It lists: {', '.join(available) or 'nothing'}.")

    counts: dict[str, int] = {}
    for number, card in enumerate(chosen, 1):
        page_hash = state.get(card["id"], {}).get("hash")
        text = page_path(card).read_text(encoding="utf-8") if fetched(card) else None
        path = CANDIDATES / f"{card['id']}.json"
        if card["id"] in manual:
            candidate = manual_candidate(card, manual[card["id"]], text, page_hash)
        else:
            if not args.force and up_to_date(path, page_hash, args.model):
                counts["up-to-date"] = counts.get("up-to-date", 0) + 1
                print(f"[{number}/{len(chosen)}] up-to-date    {card['id']}", flush=True)
                continue
            if not server_checked:
                check_server()  # only when a card needs the model: hand-entered rules don't
                server_checked = True
            candidate = extract_card(card, text, page_hash, client.complete, args.model, args.chunk_chars)
        fetch.write_json(path, candidate)
        counts[candidate["status"]] = counts.get(candidate["status"], 0) + 1
        print(
            f"[{number}/{len(chosen)}] {candidate['status']:<14} {card['id']}  "
            f"{len(candidate['rules'])} rules, {len(candidate['rejected'])} rejected",
            flush=True,
        )

    print("\n" + ", ".join(f"{count} {status}" for status, count in sorted(counts.items())))
    return 1 if counts.get("failed", 0) / len(chosen) > fetch.FAILURE_LIMIT else 0


if __name__ == "__main__":
    sys.exit(main())
