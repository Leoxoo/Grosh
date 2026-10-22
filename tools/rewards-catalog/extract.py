#!/usr/bin/env python3
"""Propose each card's reward rules by asking a local model to read its cached page.

    python3 tools/rewards-catalog/extract.py --only capital-one-savor
    python3 tools/rewards-catalog/extract.py --issuer "capital one" --limit 5
    python3 tools/rewards-catalog/extract.py            # every card with a fetched page

Needs a server that speaks the OpenAI chat completions API: LM Studio (Developer tab, Start
Server), OpenAI itself, vLLM, or any other. Settings come from what the web page (ui.py) last
saved, and flags override them: --base-url, --model, --max-tokens, --timeout, --extra-body,
--prompt-suffix, --response-mode, --token-field, --temperature. The API key (a bearer token) comes
from the LLM_API_KEY environment variable or the page's saved settings, never from a flag, so it
stays out of your shell history and process list.

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
import time
import unicodedata
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import fetch  # noqa: E402

CANDIDATES = fetch.CACHE / "candidates"
SAVED_SETTINGS = fetch.CACHE / "ui-settings.json"
MANUAL_RULES = Path(__file__).with_name("manual-rules.json")
PROMPT_VERSION = "6"
DEFAULT_URL = "http://localhost:1234/v1"
DEFAULT_MODEL = "k2-horizon-7b-uno-uncensored"
# A reasoning model "thinks" before it answers and can spend a small reply limit on that alone (the first
# real run did: 3,000 tokens of reasoning, no answer), so the limit is generous and the wait long.
DEFAULT_MAX_TOKENS = 8000
DEFAULT_TIMEOUT = 600
CHUNK_CHARS = 12_000
CHUNK_OVERLAP_LINES = 3
MAX_RATE = 10
MAX_CONDITIONS = 5
MAX_CARD_CONDITIONS = 8
MAX_CONDITION_CHARS = 400
ATTEMPTS_PER_CHUNK = 2

# The catalog's fixed categories (PIPELINE.md), each with words a quote about it would use.
# A quote that uses none of them is filed under the wrong category. Brand names (Lyft, Netflix, Amazon...)
# are deliberately not words: a rate at one named company is not a category rate, and the catalog skips it.
CATEGORIES = {
    "dining": ("dining", "restaurant", "takeout", "take out", "food", "bars", "eating out"),
    "groceries": ("grocer", "supermarket", "food at home"),
    "gas": ("gas", "fuel", "charging", "service station"),
    "travel": ("travel", "flight", "airline", "hotel", "rental car", "car rental", "cruise", "vacation",
               "airfare", "lodging", "trip", "airport"),
    "transit": ("transit", "rideshare", "ride share", "ride-hailing", "taxi", "train", "buses", "parking",
                "toll", "commut"),
    "streaming": ("streaming",),
    "drugstores": ("drugstore", "drug store", "pharmac"),
    "online-shopping": ("online", "e-commerce", "internet retail"),
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
PERIOD_WORDS = {"month": ("month",), "quarter": ("quarter",), "year": ("year", "annual"),
                "cycle": ("billing cycle", "statement period", "each cycle")}

# Who decides which categories earn a rate. "fixed": the rate always applies to its one category.
# "choose": the cardholder picks (Bank of America Customized Cash). "top-spend": the card applies
# it to the eligible category where the cardholder spends most (Citi Custom Cash). "rotating": the issuer
# changes the bonus categories every quarter or month (Discover, Chase Freedom Flex), so the rule has no
# fixed category: `categories` lists them only if the page names them for a stated period.
SELECTIONS = ("fixed", "choose", "top-spend", "rotating")
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
# Questions only the cardholder can answer, with the wording the app can ask. A rule's `needs` is worked out
# from the rule itself (needs_of), never taken from the model: a choose rule needs the category picked, a
# rate for the first N months needs the date the card was opened, an Apple Pay rate needs to know whether
# the cardholder pays that way. Not modeled yet: Bank of America's Preferred Rewards tier.
NEEDS = {
    "choice-categories": "Which category did you choose on this card?",
    "account-opened": "When did you open this card?",
    "pays-with-apple-pay": "Do you usually pay with Apple Pay?",
}
MONTHS = ("january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
          "november", "december")

RULE_SCHEMA = {
    "type": "object",
    "properties": {
        "categories": {"type": "array", "items": {"type": "string", "enum": list(CATEGORIES)}},
        "selection": {"type": "string", "enum": list(SELECTIONS)},
        "picks": {"type": ["integer", "null"]},
        "hasOtherChoices": {"type": "boolean"},
        "rate": {"type": "number"},
        "unit": {"type": "string", "enum": ["percent", "per-dollar"]},
        "capAmount": {"type": ["number", "null"]},
        "capPeriod": {"type": ["string", "null"], "enum": [*PERIOD_WORDS, None]},
        "requires": {"type": "array", "items": {"type": "string", "enum": list(REQUIRES)}},
        "validFrom": {"type": ["string", "null"]},
        "validTo": {"type": ["string", "null"]},
        "firstMonths": {"type": ["integer", "null"]},
        "quote": {"type": "string"},
        "conditions": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["categories", "selection", "picks", "hasOtherChoices", "rate", "unit", "capAmount", "capPeriod",
                 "requires", "validFrom", "validTo", "firstMonths", "quote", "conditions"],
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


# A base rate ("1% on all other purchases") holds all the time. A sentence about a quarter, activating,
# or "different places" describes a bonus rate that changes: that is a rotating rate, never the base.
NOT_A_BASE_RATE = ("quarter", "activate", "activation", "enroll", "different places", "rotating", "bonus categor")
# "Each quarter" alone is not enough: a cap ("up to $1,000 each quarter") says it too. A rotating rate says
# the categories themselves change.
ROTATING_WORDS = ("rotating", "different places", "bonus categor", "categories change", "categories that change")


def _category_fits(category: str, quote_norm: str) -> bool:
    if category == "everything-else":
        if mentions(quote_norm, NOT_A_BASE_RATE):
            return False
        if mentions(quote_norm, CATEGORIES[category]):
            return True
        # "Get 2% back when you use Apple Pay" is a base rate without saying "all other purchases":
        # it fits if it names no other category.
        return not any(mentions(quote_norm, words) for name, words in CATEGORIES.items() if name != category)
    return mentions(quote_norm, CATEGORIES[category])


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


def _first_months_backed(months: int, text: str) -> bool:
    """Whether the text speaks of a first period of that length: "first year", "first 12 months", "first 2 years"."""
    if not re.search(r"(?<![a-z])first[ -]", text):
        return False
    if months == 12 and re.search(r"first[ -]year", text):
        return True
    numbers = numbers_in(text)
    return (months in numbers and mentions(text, ("month",))) or (
        months % 12 == 0 and months // 12 in numbers and mentions(text, ("year",))
    )


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
        or (not categories and selection != "rotating")
        or not all(isinstance(c, str) and c in CATEGORIES for c in categories)
        or len(set(categories)) != len(categories)
    ):
        return "categories must be distinct categories from the catalog's list"
    if not isinstance(other, bool):
        return "hasOtherChoices must be true or false"
    if selection == "rotating":
        if "everything-else" in categories or picks is not None or other:
            return "a rotating rule has no everything-else, no picks and no other choices"
    elif selection == "fixed":
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
        return f"cap period {period!r} is not one of {', '.join(PERIOD_WORDS)}"
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
    if selection == "rotating":
        if not mentions(quote_norm, ROTATING_WORDS):
            return "quote doesn't say the categories change (quarter, rotating, bonus categories...)"
        for category in categories:
            if not mentions(quote_norm, CATEGORIES[category]):
                return f"quote doesn't mention {category}"
    elif selection == "fixed":
        if not _category_fits(categories[0], quote_norm):
            return f"quote doesn't mention {categories[0]}"
    else:
        if not mentions(quote_norm, SELECTION_WORDS[selection]):
            return f"quote doesn't say who chooses ({selection})"
        for category in categories:  # the choices usually sit apart from the quote, so only the page can confirm them
            if page_norm is not None and not mentions(page_norm, CATEGORIES[category]):
                return f"{category} is not mentioned on the page"
    if cap is not None:
        if float(cap) not in numbers_in(quote):
            return f"cap {cap} is not in the quote"
        if not mentions(quote_norm, PERIOD_WORDS[period]):
            return f"cap period {period} is not in the quote"
    for tag in requires:
        if not mentions(context, REQUIRES[tag]):
            return f"requires {tag}, but neither the quote nor a condition says so"
    first = rule.get("firstMonths")
    if first is not None:
        if isinstance(first, bool) or not isinstance(first, int) or not 1 <= first <= 60:
            return "firstMonths must be a whole number of months from 1 to 60"
        if not _first_months_backed(first, context):
            return f"the quote doesn't say the rate is for the first {first} months"
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
    """The prompt for one chunk of one card's page. Everything that is the same for every card comes first
    and the card and its page text come last, so a server that caches the start of a prompt (most can)
    reads the long instructions once instead of on every request."""
    categories = "\n".join(f"  - {name}: {CATEGORY_HELP[name]}" for name in CATEGORIES)
    unit = {"cashback": "cash back percent", "points": "points per dollar", "miles": "miles per dollar"}[card["rewardKind"]]
    user = f"""Find the rates a credit card earns on purchases, in the text at the end.

Rules:
- Only rates for the card named at the end. The text may also describe other cards; ignore their rates.
- One entry per rate. categories must come from this list:
{categories}
  Skip a rate that fits none of these, and a rate for one named store.
- selection: "fixed" when the rate always applies to one category (list exactly that one). "choose" when the cardholder picks which categories earn the rate. "top-spend" when the card applies the rate by itself to the eligible category where the cardholder spends the most. For "choose" and "top-spend", list every eligible category that is in the list above, set picks to how many categories earn the rate (1 for "your top category"), and set hasOtherChoices to true if the text also lists eligible categories that are not in the list above. For "fixed", picks is null and hasOtherChoices is false.
- "rotating" when the issuer changes the bonus categories every quarter or month (such as "5% in bonus categories that change each quarter"): leave categories as [] unless the text names them for a stated period, set picks to null and hasOtherChoices to false, and include requires ["activation"] if the text says to activate.
- rate: the number alone (3 for "3%" and for "3X points").
- unit: "percent" for cash back percent, "per-dollar" for points or miles per dollar.
- quote: copy the exact words of one sentence or phrase from the text that states the rate. Do not change, shorten or join them.
- capAmount and capPeriod: only if that same sentence limits how much spending earns the rate (for "up to $6,000 per year": 6000 and "year"; the period is month, quarter, year, or cycle for a billing cycle). Otherwise null for both.
- requires: only what the text says the rate needs. "apple-pay" (must pay with Apple Pay), "activation" (must activate or enroll), "issuer-booking" (must book through the issuer's travel site or portal). Otherwise [].
- validFrom and validTo: for a rate that applies only in a stated period, its first and last day as YYYY-MM-DD, and only when the text names the months and the year (October through December 2026 is 2026-10-01 and 2026-12-31). Otherwise null.
- firstMonths: only if the text says the rate applies just during an introductory period after the account is opened ("first year", "first 6 months"): the length in months (12 for "first year"). Otherwise null.
- conditions: copy, word for word, each sentence in the text that excludes or restricts this one rate: excluded stores, a minimum, who qualifies. These are often in footnotes, which repeat the rate with its exclusions. Never paraphrase. Use [] if there are none.
- cardConditions (at the top level, not in a rule): copy, word for word, each sentence that limits several of this card's rates at once, such as how stores get categorized or limits on digital wallets. Do not repeat them in a rule's conditions. Use [] if there are none.
- Ignore sign-up bonuses, statement credits, APRs, fees, and what points are worth.
- If the text states no rate for the card, reply {{"cardConditions": [], "rules": []}}.

Card: "{card["name"]}" (issued by {card["issuer"]}; it earns {unit}).

Text:
\"\"\"
{chunk}
\"\"\""""
    return [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": user}]


def parse_reply(content: str) -> tuple[list, list]:
    """The model's (rules, cardConditions), or ValueError if it did not reply with the shape we asked for."""
    content = content.strip()
    content = re.sub(r"^```(?:json)?\s*|\s*```$", "", content)
    try:
        value = json.loads(content)
    except ValueError as problem:
        # Say what the reply was, so a cut-off or chatty reply can be told from a bad schema.
        raise ValueError(f"{problem}; the reply was {len(content)} characters and began {content[:150]!r}") from problem
    if not isinstance(value, dict) or not isinstance(value.get("rules"), list):
        raise ValueError('reply is not {"cardConditions": [...], "rules": [...]}')
    card_conditions = value.get("cardConditions", [])
    if not isinstance(card_conditions, list):
        raise ValueError("cardConditions is not a list")
    return value["rules"], card_conditions


def empty_reply_message(meta: dict) -> str:
    """Why a model's reply held no text, and what to try. Reasoning models often spend their whole reply
    limit "thinking" and stop before answering."""
    used = (meta.get("usage") or {}).get("completion_tokens")
    parts = [f"finish reason {meta.get('finishReason')!r}", f"{used if used is not None else '?'} of {meta.get('maxTokens')} reply tokens used"]
    if meta.get("reasoningChars"):
        parts.append(f"{meta['reasoningChars']} characters of reasoning text")
    hint = ""
    if meta.get("finishReason") == "length" or meta.get("reasoningChars"):
        hint = " The model ran out of room before answering, probably because it reasons first: raise the reply limit in the page's settings, or choose a model that answers directly."
    return f"The model server returned an empty reply ({'; '.join(parts)}).{hint}"


# How the reply's shape is requested. Not every server accepts a JSON schema, so there are fallbacks that
# describe the shape in the prompt instead; the checks on what comes back are the same either way.
REPORT_TOOL = "report_rules"
RESPONSE_MODES = {
    "json_schema": "send the output schema with each request (LM Studio, OpenAI, and others that support it)",
    "tool": f"offer a function, {REPORT_TOOL}, whose arguments are the schema, and read the answer from its call (servers that enforce tool schemas, such as rec's flint, and others without json_schema)",
    "json_object": "ask for a JSON object, and describe its shape in the prompt",
    "prompt": "send no format field: describe the shape in the prompt and read the reply",
}
TOKEN_FIELDS = ("max_tokens", "max_completion_tokens")  # newer OpenAI models want the second


class ServerHTTPError(OSError):
    """The server answered with an HTTP error: `code` is its status, and the message carries its own words."""

    def __init__(self, code: int, detail: str) -> None:
        super().__init__(f"the server answered HTTP {code}: {detail}" if detail else f"the server answered HTTP {code}")
        self.code = code


class ChatServer:
    """Any server that speaks the OpenAI chat completions API: LM Studio, OpenAI itself, vLLM, a vendor's own.
    `api_key` is sent as a bearer token. It is never logged or put in an error message."""

    def __init__(
        self, base_url: str, model: str, timeout: float = DEFAULT_TIMEOUT, urlopen=urllib.request.urlopen,
        max_tokens: int = DEFAULT_MAX_TOKENS, extra_body: dict | None = None, prompt_suffix: str = "",
        api_key: str = "", response_mode: str = "json_schema", token_field: str = "max_tokens",
        temperature: float | None = 0,
    ) -> None:
        if response_mode not in RESPONSE_MODES or token_field not in TOKEN_FIELDS:
            raise ValueError(f"response_mode must be one of {list(RESPONSE_MODES)} and token_field one of {list(TOKEN_FIELDS)}")
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout = timeout
        self.urlopen = urlopen
        self.max_tokens = max_tokens
        # Two ways to steer a model without changing code: fields added to every request (for example
        # {"reasoning_effort": "none"}) and a line added to the end of every prompt (for example "/no_think").
        self.extra_body = extra_body or {}
        self.prompt_suffix = prompt_suffix.strip()
        self.api_key = api_key.strip()
        self.response_mode = response_mode
        self.token_field = token_field
        self.temperature = temperature
        self.last_meta: dict = {}  # how the latest reply ended: finish reason, tokens used, reasoning text

    def _request(self, url: str, data: bytes | None = None) -> urllib.request.Request:
        headers = {"Content-Type": "application/json"} if data is not None else {}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return urllib.request.Request(url, data=data, headers=headers)

    def _open(self, request: urllib.request.Request, timeout: float):
        try:
            return self.urlopen(request, timeout=timeout)
        except urllib.error.HTTPError as problem:
            # A refused request is explained in the body (a schema it can't use, no such model, a bad key).
            raise ServerHTTPError(problem.code, problem.read(600).decode("utf-8", "replace").strip()) from problem

    def models(self) -> list[str]:
        with self._open(self._request(f"{self.base_url}/models"), 10) as reply:
            data = json.load(reply)
        return [entry["id"] for entry in (data["data"] if isinstance(data, dict) else data)]

    def complete(self, messages: list[dict], free: bool = False, extra_body: dict | None = None) -> str:
        """The model's reply. `free` sends a plain chat request (no output format asked for), for trying
        a prompt by hand; `extra_body` adds fields for this call only."""
        notes = []
        if self.response_mode == "tool" and not free:
            notes.append(f"Report your answer by calling the {REPORT_TOOL} function, with the answer as its arguments.")
        elif self.response_mode != "json_schema" and not free:
            notes.append("Reply with only a JSON object that follows this JSON Schema, and nothing else:\n" + json.dumps(SCHEMA))
        if self.prompt_suffix:
            notes.append(self.prompt_suffix)
        if notes:
            messages = [*messages[:-1], {**messages[-1], "content": "\n\n".join([messages[-1]["content"], *notes])}]
        body: dict = {self.token_field: self.max_tokens}
        if self.temperature is not None:  # some models accept only their default
            body["temperature"] = self.temperature
        if free:
            pass
        elif self.response_mode == "tool":
            # strict: a server that constrains tool arguments to their schema (rec's flint does for strict tools)
            # then can't return the wrong field names. tool_choice is left to the server: some accept only "auto".
            body["tools"] = [{"type": "function", "function": {
                "name": REPORT_TOOL, "description": "Report the reward rules found in the text.", "strict": True, "parameters": SCHEMA}}]
        elif self.response_mode == "json_schema":
            body["response_format"] = {"type": "json_schema", "json_schema": {"name": "rules", "strict": True, "schema": SCHEMA}}
        elif self.response_mode == "json_object":
            body["response_format"] = {"type": "json_object"}
        body.update({k: v for k, v in {**self.extra_body, **(extra_body or {})}.items() if k not in ("model", "messages")})
        body.update(model=self.model, messages=messages)
        request = self._request(f"{self.base_url}/chat/completions", json.dumps(body).encode())
        self.last_meta = {}
        with self._open(request, self.timeout) as reply:
            data = json.load(reply)
        try:
            choice = data["choices"][0]
            message = choice["message"]
        except (KeyError, IndexError, TypeError) as problem:
            raise ValueError(f"unexpected reply from the model server: {problem}") from problem
        content = message.get("content") or ""
        called = False
        for call in message.get("tool_calls") or []:  # the answer, when it came as a function call
            function = (call or {}).get("function") or {}
            if function.get("name") == REPORT_TOOL and function.get("arguments"):
                arguments = function["arguments"]
                content, called = (arguments if isinstance(arguments, str) else json.dumps(arguments)), True
                break
        reasoning = message.get("reasoning_content") or message.get("reasoning") or ""
        self.last_meta = {
            "finishReason": choice.get("finish_reason"), "usage": data.get("usage"), "reasoningChars": len(reasoning),
            "replyChars": len(content), "maxTokens": self.max_tokens, "viaTool": called,
        }
        if not content.strip():
            raise ValueError(empty_reply_message(self.last_meta))
        return content


# --- One card ---------------------------------------------------------------------------------


def needs_of(rule: dict) -> list[str]:
    """The questions the cardholder must answer for this rule to be worked out (NEEDS)."""
    needs = []
    if rule["selection"] == "choose":
        needs.append("choice-categories")
    if rule.get("firstMonths") is not None:
        needs.append("account-opened")
    if "apple-pay" in rule["requires"]:
        needs.append("pays-with-apple-pay")
    return needs


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
        "firstMonths": proposal.get("firstMonths"),
        "needs": needs_of(proposal),
        "conditions": [c.strip() for c in proposal["conditions"]],
        "verified": verified,
        "evidence": {"quote": proposal["quote"].strip(), "url": url, "pageHash": page_hash},
    }


def _rule_key(rule: dict) -> tuple:
    return (
        tuple(rule["categories"]), rule["selection"], rule["picks"], float(rule["rate"]), rule["unit"],
        rule["capAmount"], rule["capPeriod"], rule["validFrom"], rule["validTo"], rule["firstMonths"],
    )


def review_warnings(rules: list[dict]) -> list[str]:
    """Things that pass every check but that a person should look at before trusting the card: the same
    thing earning two different rates with nothing to tell them apart (two base rates, say). Each of the
    rates is on the page; at most one is probably the right reading."""
    groups: dict[tuple, set] = {}
    for rule in rules:
        if rule["selection"] != "fixed" or rule["capAmount"] is not None:
            continue
        key = (rule["categories"][0], tuple(rule["requires"]), rule["validFrom"], rule["validTo"], rule["firstMonths"])
        groups.setdefault(key, set()).add(rule["rate"])
    warnings = [
        f"{key[0]} earns {' and '.join(f'{rate:g}' for rate in sorted(rates))} with nothing to tell them apart"
        for key, rates in sorted(groups.items(), key=lambda item: repr(item[0])) if len(rates) > 1
    ]
    if rules and not any(r["selection"] == "fixed" and r["categories"] == ["everything-else"] for r in rules):
        warnings.append("no rate for all other purchases was found: check the page for what everything else earns")
    return warnings


def _empty_candidate(card: dict, model: str, prompt_version: str | None, page_hash: str | None, status: str) -> dict:
    return {
        "cardId": card["id"], "model": model, "promptVersion": prompt_version, "pageHash": page_hash,
        "status": status, "needs": [], "warnings": [], "cardConditions": [], "rules": [], "rejected": [],
    }


def _retype_rotating(proposal):
    """A "choose" or "top-spend" rule, or a base rate, whose quote says the categories change and says nothing
    about who picks them, is a rotating rule that was mislabeled (the model reads "different places you shop
    each quarter" as "top spend", or as "everything else"). Its categories were guessed, so they are dropped."""
    if not isinstance(proposal, dict):
        return proposal
    selection = proposal.get("selection")
    base_rate = selection == "fixed" and proposal.get("categories") == ["everything-else"]
    if selection not in ("choose", "top-spend") and not base_rate:
        return proposal
    quote = normalize(proposal["quote"]) if isinstance(proposal.get("quote"), str) else ""
    says_who_picks = bool(selection in SELECTION_WORDS) and mentions(quote, SELECTION_WORDS[selection])
    if mentions(quote, ROTATING_WORDS) and not says_who_picks:
        # A base rate never says "at different places you shop each quarter": it is the rotating bonus.
        return {**proposal, "selection": "rotating", "categories": [], "picks": None, "hasOtherChoices": False}
    return proposal


def split_fixed(proposal) -> list:
    """Tidy-ups of what the model proposed that change nothing about its meaning: a rotating rule mislabeled
    as choose or top-spend is retyped, and a "fixed" rule that lists several categories says the rate applies to each, so it becomes one rule
    per category with the same quote, and each is then checked on its own. The model does this often
    ("3% on dining, groceries and streaming"); nothing about the rule changes. A "choose" or "top-spend" rule
    that picks as many categories as it lists is fixed in the same way."""
    proposal = _retype_rotating(proposal)
    categories = proposal.get("categories") if isinstance(proposal, dict) else None
    picks = proposal.get("picks") if isinstance(proposal, dict) else None
    if (
        isinstance(proposal, dict) and proposal.get("selection") in ("choose", "top-spend") and isinstance(categories, list)
        and categories and isinstance(picks, int) and not isinstance(picks, bool) and picks >= len(categories)
    ):
        # "Choose 3 of these 3" leaves nothing to choose: every listed category earns the rate. (Categories
        # the model saw but the catalog lacks, such as entertainment, stay out, as in any fixed rule.)
        proposal = {**proposal, "selection": "fixed", "picks": None, "hasOtherChoices": False}
    if isinstance(proposal, dict) and proposal.get("selection") == "fixed" and isinstance(categories, list) and len(categories) > 1:
        return [
            {**proposal, "categories": [category], "conditions": _conditions_about(proposal.get("conditions"), category)}
            for category in categories
        ]
    return [proposal]


def _conditions_about(conditions, category) -> list:
    """The conditions that apply to one category of a split rule: those about it, and those that name no
    category at all. A sentence about supermarkets belongs to groceries, not to dining."""
    if not isinstance(conditions, list) or category not in CATEGORIES:
        return conditions
    kept = []
    for condition in conditions:
        text = normalize(condition) if isinstance(condition, str) else ""
        about_this = mentions(text, CATEGORIES[category])
        about_another = any(mentions(text, words) for name, words in CATEGORIES.items() if name not in (category, "everything-else"))
        if about_this or not about_another:
            kept.append(condition)
    return kept


def extract_card(
    card: dict, text: str, page_hash: str, complete, model: str, max_chars: int = CHUNK_CHARS, progress=None
) -> dict:
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
    errors: list[str] = []
    to_ask = [c for c in chunk_lines(text, max_chars) if has_rates(c)]
    for number, chunk in enumerate(to_ask, 1):
        if progress:
            progress(number, len(to_ask))  # may raise Stopped to end the card early
        reply = None
        for _ in range(ATTEMPTS_PER_CHUNK):
            try:
                reply = parse_reply(complete(build_messages(card, chunk)))
                break
            except (OSError, ValueError) as problem:
                reply = None
                message = f"{type(problem).__name__}: {problem}"[:700]
                if message not in errors:
                    errors.append(message)
        if reply is None:
            failures += 1
            continue
        proposals, card_conditions = reply
        for proposal in (split for raw in proposals for split in split_fixed(raw)):
            reason = validate_rule(proposal, page_norm)
            if reason:
                candidate["rejected"].append({"rule": proposal, "reason": reason})
                continue
            rule = accepted_rule(proposal, card["sourceUrl"], page_hash, "page")
            entry = accepted.setdefault(_rule_key(rule), rule)
            # The same rule seen again (the model words a quote a little differently in each part of a page) may carry a
            # condition or requirement the first time lacked.
            entry["conditions"] += [c for c in rule["conditions"] if c not in entry["conditions"]]
            entry["requires"] += [q for q in rule["requires"] if q not in entry["requires"]]
            entry["needs"] = needs_of(entry)
        for condition in card_conditions:
            problem = check_condition(condition, page_norm) or (
                None if len(candidate["cardConditions"]) < MAX_CARD_CONDITIONS else "too many card conditions"
            )
            if problem:
                candidate["rejected"].append({"cardCondition": condition, "reason": problem})
            elif condition.strip() not in candidate["cardConditions"]:
                candidate["cardConditions"].append(condition.strip())
    candidate["rules"] = sorted(accepted.values(), key=lambda r: (r["categories"][0] if r["categories"] else "~", -r["rate"]))  # "~" sorts rotating rules last
    candidate["needs"] = sorted({need for r in candidate["rules"] for need in r["needs"]})
    candidate["warnings"] = review_warnings(candidate["rules"])
    if failures:
        candidate["status"] = "failed"
        candidate["errors"] = errors
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
        grounded = page_norm is not None and validate_rule(proposal, page_norm) is None
        problem = None if grounded else validate_rule(proposal, None)
        if problem:
            candidate["rejected"].append({"rule": proposal, "reason": problem})
            continue
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
    candidate["needs"] = sorted({need for r in candidate["rules"] for need in r["needs"]})
    candidate["warnings"] = review_warnings(candidate["rules"])
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


class ServerProblem(Exception):
    """The model server isn't answering, refuses the key, or doesn't have the chosen model."""


class Stopped(Exception):
    """A running job was asked to stop."""


def check_server(client: ChatServer) -> list[str]:
    """The model ids the server lists, or ServerProblem saying what to fix. A server with no model list
    (HTTP 404/405) is taken on trust, and the model id is used as given."""
    try:
        available = client.models()
    except ServerHTTPError as problem:
        if problem.code in (401, 403):
            raise ServerProblem(
                f"The server at {client.base_url} refused the API key (HTTP {problem.code}). Check the key in the page's settings."
            ) from problem
        if problem.code in (404, 405, 501):
            return []
        raise ServerProblem(f"The server at {client.base_url} answered badly: {problem}") from problem
    except (OSError, ValueError, KeyError, TypeError) as problem:
        raise ServerProblem(f"The model server isn't answering at {client.base_url} ({problem}). Is it running?") from problem
    if client.model not in available:
        raise ServerProblem(f"The server has no model {client.model!r}. It lists: {', '.join(available) or 'nothing'}.")
    return available


def load_manual(cards: list[dict], path: Path = MANUAL_RULES) -> dict:
    manual = fetch.read_json(path, {})
    unknown = sorted(set(manual) - {card["id"] for card in cards})
    if unknown:
        raise ValueError(f"manual-rules.json names cards that aren't in the seed: {unknown}")
    return manual


def has_page(card: dict, state: dict, cache: Path) -> bool:
    return bool(state.get(card["id"], {}).get("hash")) and (cache / card["id"] / "latest.txt").exists()


def summarize_calls(calls: list[dict]) -> dict:
    """Totals for the model calls made for one card: how many, how long, and how many tokens went where."""
    def total(get) -> int:
        return sum(get(call) or 0 for call in calls)

    return {
        "calls": len(calls),
        "seconds": round(sum(call["seconds"] for call in calls), 1),
        "promptTokens": total(lambda c: (c.get("usage") or {}).get("prompt_tokens")),
        "cachedTokens": total(lambda c: ((c.get("usage") or {}).get("prompt_tokens_details") or {}).get("cached_tokens")),
        "replyTokens": total(lambda c: (c.get("usage") or {}).get("completion_tokens")),
        "reasoningTokens": total(lambda c: ((c.get("usage") or {}).get("completion_tokens_details") or {}).get("reasoning_tokens")),
    }


def process_cards(
    chosen: list[dict], *, state: dict, manual: dict, client: ChatServer, chunk_chars: int, force: bool,
    cache: Path, candidates: Path, emit, ensure_server=None, progress=None, should_stop=None,
) -> dict[str, int]:
    """Extract rules for the chosen cards one at a time, saving each candidate as it finishes.

    `emit(event)` hears about every card: {"event": "card-start", ...} then {"event": "card", "status": ...}.
    `ensure_server()` runs once, just before the first card that needs the model (hand-entered cards
    don't). `progress(card_id, done, total)` hears about each chunk sent. `should_stop()` is asked
    between cards, and `progress` may raise Stopped to end a card early."""
    counts: dict[str, int] = {}
    server_checked = False
    for number, card in enumerate(chosen, 1):
        if should_stop and should_stop():
            raise Stopped
        base = {"index": number, "total": len(chosen), "id": card["id"], "name": card["name"]}
        page_hash = state.get(card["id"], {}).get("hash")
        text = (cache / card["id"] / "latest.txt").read_text(encoding="utf-8") if has_page(card, state, cache) else None
        path = candidates / f"{card['id']}.json"
        if card["id"] in manual:
            emit({"event": "card-start", **base, "kind": "hand-entered"})
            candidate = manual_candidate(card, manual[card["id"]], text, page_hash)
        else:
            if not force and up_to_date(path, page_hash, client.model):
                counts["up-to-date"] = counts.get("up-to-date", 0) + 1
                emit({"event": "card", **base, "status": "up-to-date", "rules": None, "rejected": None, "errors": []})
                continue
            if not server_checked:
                if ensure_server:
                    ensure_server()
                server_checked = True
            emit({"event": "card-start", **base, "kind": "model"})
            calls: list[dict] = []

            def timed(messages: list[dict]) -> str:
                started = time.monotonic()
                try:
                    return client.complete(messages)
                finally:
                    calls.append({"seconds": time.monotonic() - started, **client.last_meta})

            candidate = extract_card(
                card, text, page_hash, timed, client.model, chunk_chars,
                progress=(lambda done, total, _id=card["id"]: progress(_id, done, total)) if progress else None,
            )
            candidate["stats"] = summarize_calls(calls)
        fetch.write_json(path, candidate)
        counts[candidate["status"]] = counts.get(candidate["status"], 0) + 1
        emit({
            "event": "card", **base, "status": candidate["status"], "rules": len(candidate["rules"]), "warnings": candidate.get("warnings", []),
            "rejected": len(candidate["rejected"]), "errors": candidate.get("errors", []), "stats": candidate.get("stats"),
        })
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description="Propose reward rules from fetched pages, using an OpenAI-compatible model server.")
    parser.add_argument("--only", nargs="+", default=[], metavar="ID")
    parser.add_argument("--issuer", default="")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--force", action="store_true", help="redo cards whose page, model and prompt are unchanged")
    saved = fetch.read_json(SAVED_SETTINGS, {})  # what the web page (ui.py) last saved; flags override it
    parser.add_argument("--base-url", default=os.environ.get("LLM_BASE_URL") or os.environ.get("LM_STUDIO_URL") or saved.get("baseUrl", DEFAULT_URL))
    parser.add_argument("--model", default=os.environ.get("LLM_MODEL") or os.environ.get("LM_STUDIO_MODEL") or saved.get("model", DEFAULT_MODEL))
    parser.add_argument("--chunk-chars", type=int, default=saved.get("chunkChars", CHUNK_CHARS), help="page text sent to the model at a time")
    parser.add_argument("--max-tokens", type=int, default=saved.get("maxTokens", DEFAULT_MAX_TOKENS), help="reply limit, including any reasoning")
    parser.add_argument("--timeout", type=int, default=saved.get("timeoutSeconds", DEFAULT_TIMEOUT), help="seconds to wait for one reply")
    parser.add_argument("--extra-body", default=saved.get("extraBody", ""), metavar="JSON", help='fields added to every request, e.g. \'{"reasoning_effort": "none"}\'')
    parser.add_argument("--prompt-suffix", default=saved.get("promptSuffix", ""), help='text added to the end of every prompt, e.g. "/no_think"')
    parser.add_argument("--response-mode", default=saved.get("responseMode", "json_schema"), choices=list(RESPONSE_MODES))
    parser.add_argument("--token-field", default=saved.get("tokenField", "max_tokens"), choices=TOKEN_FIELDS, help="name of the reply-limit field")
    parser.add_argument("--temperature", type=float, default=saved.get("temperature", 0), help="sampling temperature (omit with the page's settings if the model accepts only its default)")
    args = parser.parse_args()
    try:
        extra_body = json.loads(args.extra_body) if args.extra_body else {}
        if not isinstance(extra_body, dict):
            raise ValueError("it must be a JSON object")
    except ValueError as problem:
        sys.exit(f"--extra-body: {problem}")

    cards = fetch.read_json(fetch.SEED, {"cards": []})["cards"]
    state = fetch.read_json(fetch.STATE, {})
    try:
        manual = load_manual(cards)
    except ValueError as problem:
        sys.exit(str(problem))
    chosen = [
        c for c in fetch.select(cards, args.only, args.issuer, None)
        if has_page(c, state, fetch.CACHE) or c["id"] in manual
    ]
    chosen = chosen[: args.limit] if args.limit else chosen
    if not chosen:
        sys.exit("No fetched pages match. Run fetch.py first.")

    if saved:
        print(f"Using model settings saved by the web page ({SAVED_SETTINGS.name}); flags override them.", flush=True)
    client = ChatServer(
        args.base_url, args.model, args.timeout, max_tokens=args.max_tokens, extra_body=extra_body,
        prompt_suffix=args.prompt_suffix, api_key=os.environ.get("LLM_API_KEY") or saved.get("apiKey", ""),
        response_mode=args.response_mode, token_field=args.token_field, temperature=args.temperature,
    )

    def ensure_server() -> None:
        try:
            check_server(client)
        except ServerProblem as problem:
            sys.exit(str(problem))

    def show(event: dict) -> None:
        if event["event"] != "card":
            return
        counts_text = "" if event["rules"] is None else f"  {event['rules']} rules, {event['rejected']} rejected"
        print(f"[{event['index']}/{event['total']}] {event['status']:<14} {event['id']}{counts_text}", flush=True)
        for message in event["errors"][:2]:
            print(f"        {message}", flush=True)

    counts = process_cards(
        chosen, state=state, manual=manual, client=client, chunk_chars=args.chunk_chars, force=args.force,
        cache=fetch.CACHE, candidates=CANDIDATES, emit=show, ensure_server=ensure_server,
    )
    print("\n" + ", ".join(f"{count} {status}" for status, count in sorted(counts.items())))
    return 1 if counts.get("failed", 0) / len(chosen) > fetch.FAILURE_LIMIT else 0


if __name__ == "__main__":
    sys.exit(main())
