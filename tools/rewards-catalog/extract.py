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

Re-running skips a card whose page, model and prompt are unchanged.
"""

import argparse
import json
import os
import re
import sys
import unicodedata
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import fetch  # noqa: E402

CANDIDATES = fetch.CACHE / "candidates"
PROMPT_VERSION = "1"
DEFAULT_URL = "http://localhost:1234/v1"
DEFAULT_MODEL = "k2-horizon-7b-uno-uncensored"
CHUNK_CHARS = 12_000
CHUNK_OVERLAP_LINES = 3
MAX_RATE = 10
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

SCHEMA = {
    "type": "object",
    "properties": {
        "rules": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "category": {"type": "string", "enum": list(CATEGORIES)},
                    "rate": {"type": "number"},
                    "unit": {"type": "string", "enum": ["percent", "per-dollar"]},
                    "capAmount": {"type": ["number", "null"]},
                    "capPeriod": {"type": ["string", "null"], "enum": ["month", "quarter", "year", None]},
                    "quote": {"type": "string"},
                },
                "required": ["category", "rate", "unit", "capAmount", "capPeriod", "quote"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["rules"],
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


# --- Checking what the model said ---------------------------------------------------------


def validate_rule(rule, page_norm: str) -> str | None:
    """Why a proposed rule can't be kept, or None if every check holds. Nothing here trusts the model."""
    if not isinstance(rule, dict):
        return "not an object"
    category, rate, unit = rule.get("category"), rule.get("rate"), rule.get("unit")
    quote, cap, period = rule.get("quote"), rule.get("capAmount"), rule.get("capPeriod")
    if category not in CATEGORIES:
        return f"category {category!r} is not in the catalog's list"
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

    quote_norm = normalize(quote)
    if quote_norm not in page_norm:
        return "quote is not on the page word for word"
    if float(rate) not in numbers_in(quote):
        return f"rate {rate} is not in the quote"
    if unit == "percent" and "%" not in quote:
        return "unit is percent but the quote has no %"
    if unit == "per-dollar" and not re.search(r"\d\s*[xX]\b|\bpoints?\b|\bmiles?\b|\bper (?:\$1|dollar)", quote):
        return "unit is per-dollar but the quote has no points, miles or X"
    if not mentions(quote_norm, CATEGORIES[category]):
        return f"quote doesn't mention {category}"
    if cap is not None:
        if float(cap) not in numbers_in(quote):
            return f"cap {cap} is not in the quote"
        if not mentions(quote_norm, PERIOD_WORDS[period]):
            return f"cap period {period} is not in the quote"
    return None


def mentions(text: str, words: tuple[str, ...]) -> bool:
    """Whether any word starts a word in the text ("grocer" matches "grocery"; "gas" doesn't match "vegas")."""
    return any(re.search(r"(?<![a-z0-9])" + re.escape(word), text) for word in words)


# --- Asking the model -----------------------------------------------------------------------

SYSTEM_PROMPT = "You extract credit card reward rules from web page text. Reply with JSON only."


def build_messages(card: dict, chunk: str) -> list[dict]:
    categories = "\n".join(f"  - {name}: {CATEGORY_HELP[name]}" for name in CATEGORIES)
    unit = {"cashback": "cash back percent", "points": "points per dollar", "miles": "miles per dollar"}[card["rewardKind"]]
    user = f"""Card: {card["name"]} (issued by {card["issuer"]}; it earns {unit}).

Find the rates this card earns on purchases, in the text below.

Rules:
- Only rates for THIS card, "{card["name"]}". The text may also describe other cards; ignore their rates.
- One entry per category and rate. category must be one of:
{categories}
  Skip a rate that fits none of these, and a rate for one named store.
- rate: the number alone (3 for "3%" and for "3X points").
- unit: "percent" for cash back percent, "per-dollar" for points or miles per dollar.
- quote: copy the exact words of one sentence or phrase from the text that states the rate. Do not change, shorten or join them.
- capAmount and capPeriod: only if that same sentence limits how much spending earns the rate (for "up to $6,000 per year": 6000 and "year"). Otherwise null for both.
- Ignore sign-up bonuses, statement credits, APRs, fees, and what points are worth.
- If the text states no rate for this card, reply {{"rules": []}}.

Text:
\"\"\"
{chunk}
\"\"\""""
    return [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": user}]


def parse_reply(content: str) -> list:
    """The model's rules list, or ValueError if it did not reply with the shape we asked for."""
    content = content.strip()
    content = re.sub(r"^```(?:json)?\s*|\s*```$", "", content)
    value = json.loads(content)
    if not isinstance(value, dict) or not isinstance(value.get("rules"), list):
        raise ValueError('reply is not {"rules": [...]}')
    return value["rules"]


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


def extract_card(card: dict, text: str, page_hash: str, complete, model: str, max_chars: int = CHUNK_CHARS) -> dict:
    """The candidate for one card: accepted rules, rejected proposals with reasons, and a status:
    ok, no-rules (the page states none), wrong-page (it doesn't name the card) or failed
    (the model could not be read for at least one chunk, so the result is incomplete)."""
    candidate = {
        "cardId": card["id"],
        "model": model,
        "promptVersion": PROMPT_VERSION,
        "pageHash": page_hash,
        "status": "ok",
        "rules": [],
        "rejected": [],
    }
    if not name_on_page(card["name"], text):
        candidate["status"] = "wrong-page"
        return candidate

    page_norm = normalize(text)
    accepted: dict[tuple, dict] = {}
    failures = 0
    for chunk in (c for c in chunk_lines(text, max_chars) if has_rates(c)):
        proposals = None
        for _ in range(ATTEMPTS_PER_CHUNK):
            try:
                proposals = parse_reply(complete(build_messages(card, chunk)))
                break
            except (OSError, ValueError):
                proposals = None
        if proposals is None:
            failures += 1
            continue
        for proposal in proposals:
            reason = validate_rule(proposal, page_norm)
            if reason:
                candidate["rejected"].append({"rule": proposal, "reason": reason})
                continue
            key = (proposal["category"], float(proposal["rate"]), proposal["unit"], proposal["capAmount"], proposal["capPeriod"])
            accepted.setdefault(key, {
                "category": proposal["category"],
                "rate": proposal["rate"],
                "unit": proposal["unit"],
                "capAmount": proposal["capAmount"],
                "capPeriod": proposal["capPeriod"],
                "evidence": {"quote": proposal["quote"].strip(), "url": card["sourceUrl"], "pageHash": page_hash},
            })
    candidate["rules"] = sorted(accepted.values(), key=lambda r: (r["category"], -r["rate"]))
    if failures:
        candidate["status"] = "failed"
    elif not accepted:
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

    client = LMStudio(args.base_url, args.model)
    try:
        available = client.models()
    except (OSError, ValueError, KeyError) as problem:
        sys.exit(f"LM Studio isn't answering at {args.base_url} ({problem}). Start its local server (Developer tab).")
    if args.model not in available:
        sys.exit(f"LM Studio has no model {args.model!r}. It lists: {', '.join(available) or 'nothing'}.")

    cards = fetch.read_json(fetch.SEED, {"cards": []})["cards"]
    state = fetch.read_json(fetch.STATE, {})
    chosen = [
        card for card in fetch.select(cards, args.only, args.issuer, None)
        if state.get(card["id"], {}).get("hash") and (fetch.CACHE / card["id"] / "latest.txt").exists()
    ]
    chosen = chosen[: args.limit] if args.limit else chosen
    if not chosen:
        sys.exit("No fetched pages match. Run fetch.py first.")

    counts: dict[str, int] = {}
    for number, card in enumerate(chosen, 1):
        page_hash = state[card["id"]]["hash"]
        path = CANDIDATES / f"{card['id']}.json"
        if not args.force and up_to_date(path, page_hash, args.model):
            counts["up-to-date"] = counts.get("up-to-date", 0) + 1
            print(f"[{number}/{len(chosen)}] up-to-date    {card['id']}", flush=True)
            continue
        text = (fetch.CACHE / card["id"] / "latest.txt").read_text(encoding="utf-8")
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
