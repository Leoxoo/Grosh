#!/usr/bin/env python3
"""Fetch each catalog card's issuer page and report which pages changed.

    python3 tools/rewards-catalog/fetch.py
    python3 tools/rewards-catalog/fetch.py --issuer chase --limit 5
    python3 tools/rewards-catalog/fetch.py --only chase-sapphire-preferred

reads catalog-seed.json, fetches every card's sourceUrl (once per distinct URL),
and keeps two things:

    fetch-state.json   committed: per card, the hash of the page's visible text,
                       so a run on any machine can tell whether a page changed.
    cache/             not committed: the page text itself (latest and previous),
                       and the HTTP validators used for conditional requests.

A run also writes cache/report.md and prints the same summary. It stops only for
a reason that means the run itself broke: more than 25% of cards failing to fetch.
A page that refuses us, blocks us in robots.txt, or needs a real browser is
reported, but is an expected outcome, not a failure.

A card whose fetch did not succeed keeps its last hash. Failure never erases.

Only the standard library is used, so it runs anywhere python3 does (PIPELINE.md).
"""

import argparse
import difflib
import gzip
import hashlib
import http.client
import json
import re
import sys
import time
import urllib.error
import urllib.request
import zlib
from dataclasses import dataclass, field
from datetime import date
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
from urllib.robotparser import RobotFileParser

HERE = Path(__file__).parent
SEED = HERE / "catalog-seed.json"
STATE = HERE / "fetch-state.json"
CACHE = HERE / "cache"

USER_AGENT = "GroshRewardsCatalog/0.1 (personal finance app; github.com/Leoxoo)"
TIMEOUT_SECONDS = 20
MAX_BYTES = 5_000_000
ATTEMPTS = 3
DELAY_SECONDS = 1.0
# A page with less visible text than this is a shell that a browser would fill in
# (or a bot wall), not something we can extract rules from.
MIN_TEXT_CHARS = 400
FAILURE_LIMIT = 0.25

SKIPPED_TAGS = {"script", "style", "noscript", "template", "svg"}
BLOCK_TAGS = {
    "address", "article", "aside", "br", "dd", "div", "dl", "dt", "footer", "h1", "h2", "h3",
    "h4", "h5", "h6", "header", "hr", "li", "main", "nav", "ol", "p", "section", "table",
    "td", "th", "tr", "ul",
}


# --- Reading a page ----------------------------------------------------------------


class _VisibleText(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.skipping = 0

    def handle_starttag(self, tag: str, attrs: list) -> None:
        if tag in SKIPPED_TAGS:
            self.skipping += 1
        elif tag in BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in SKIPPED_TAGS:
            self.skipping = max(0, self.skipping - 1)
        elif tag in BLOCK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.skipping:
            # A newline inside a paragraph's source is just a space; only block tags end a line.
            self.parts.append(re.sub(r"\s+", " ", data))


def visible_text(html: str) -> str:
    """The text a reader sees: one line per block, spacing collapsed, no scripts or styles.

    Hashing this rather than the HTML means a changed script bundle or tracking id
    doesn't look like a changed page.
    """
    parser = _VisibleText()
    parser.feed(html)
    parser.close()
    lines: list[str] = []
    for line in "".join(parser.parts).splitlines():
        line = " ".join(line.split())
        if line and (not lines or lines[-1] != line):
            lines.append(line)
    return "\n".join(lines)


def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def changed_line_count(old: str, new: str) -> int:
    """How many lines were added or removed, so a reviewer can tell a rate change from page churn."""
    diff = difflib.unified_diff(old.splitlines(), new.splitlines(), n=0, lineterm="")
    return sum(1 for line in diff if line[0] in "+-" and not line.startswith(("+++", "---")))


# --- Talking to the network ----------------------------------------------------------


@dataclass
class Response:
    status: int
    headers: dict[str, str]  # lower-case names
    body: bytes
    url: str


def http_get(url: str, headers: dict[str, str]) -> Response:
    """One GET. HTTP error statuses come back as a Response; network errors raise OSError."""
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as reply:
            return _response(reply.status, reply.headers, reply.read(MAX_BYTES + 1), reply.geturl())
    except urllib.error.HTTPError as error:
        try:
            body = error.read(MAX_BYTES + 1)
        except (OSError, http.client.HTTPException):
            body = b""
        return _response(error.code, error.headers, body, url)
    except http.client.HTTPException as problem:
        # A reply cut off mid-body (IncompleteRead) or a malformed one: retry it like a dropped connection.
        raise OSError(f"{type(problem).__name__}: {problem}") from problem


def _response(status: int, headers, body: bytes, url: str) -> Response:
    return Response(status, {name.lower(): value for name, value in headers.items()}, body, url)


def decode(response: Response) -> str:
    body = response.body
    if response.headers.get("content-encoding", "").lower() == "gzip":
        body = gzip.decompress(body)
    charset = "utf-8"
    for part in response.headers.get("content-type", "").split(";")[1:]:
        name, _, value = part.strip().partition("=")
        if name.lower() == "charset" and value:
            charset = value.strip("\"' ")
    try:
        return body.decode(charset, errors="replace")
    except LookupError:
        return body.decode("utf-8", errors="replace")


class Throttle:
    """Keeps at least `delay` seconds between requests to the same host."""

    def __init__(self, delay: float = DELAY_SECONDS, clock=time.monotonic, sleep=time.sleep) -> None:
        self.delay = delay
        self.clock = clock
        self.sleep = sleep
        self.last: dict[str, float] = {}

    def wait(self, host: str) -> None:
        due = self.last.get(host, float("-inf")) + self.delay
        now = self.clock()
        if now < due:
            self.sleep(due - now)
        self.last[host] = self.clock()


class Robots:
    """robots.txt for each host, fetched once per run.

    An unreadable robots.txt (network error or server error) means we don't fetch, but
    that is recorded in `problems` so it is reported as a failure, not as a ban.
    """

    def __init__(self, get, throttle: Throttle) -> None:
        self.get = get
        self.throttle = throttle
        self.parsers: dict[str, RobotFileParser] = {}
        self.problems: dict[str, str] = {}

    @staticmethod
    def origin(url: str) -> str:
        parts = urlparse(url)
        return f"{parts.scheme}://{parts.netloc}"

    def allowed(self, url: str) -> bool:
        origin = self.origin(url)
        if origin not in self.parsers:
            self.parsers[origin] = self._load(origin, urlparse(url).netloc)
        return self.parsers[origin].can_fetch(USER_AGENT, url)

    def _load(self, origin: str, host: str) -> RobotFileParser:
        parser = RobotFileParser()
        self.throttle.wait(host)
        try:
            response = self.get(f"{origin}/robots.txt", {"User-Agent": USER_AGENT})
        except OSError as problem:
            self.problems[origin] = f"robots.txt unreachable: {problem}"
            parser.disallow_all = True
            return parser
        if 200 <= response.status < 300:
            parser.parse(decode(response).splitlines())
        elif 400 <= response.status < 500:
            parser.allow_all = True
        else:
            self.problems[origin] = f"robots.txt answered HTTP {response.status}"
            parser.disallow_all = True
        return parser


@dataclass
class PageResult:
    """What came of fetching one URL. `status` is one of:

    ok, not-modified    the page was read (or the server says it is unchanged)
    gone                404 or 410: the card's page moved or was removed
    refused             401, 403 or 429: the site turned us away
    robots              robots.txt does not let us fetch it
    needs-browser       too little text: a script builds the page, or a bot wall answered
    failed              network error, timeout, server error or an unreadable reply
    """

    status: str
    text: str = ""
    final_url: str = ""
    etag: str = ""
    last_modified: str = ""
    error: str = ""


def fetch_page(url: str, get, robots: Robots, throttle: Throttle, validators: dict[str, str]) -> PageResult:
    if not robots.allowed(url):
        problem = robots.problems.get(robots.origin(url))
        return PageResult("failed", error=problem) if problem else PageResult("robots")
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en-US,en;q=0.9",
        # Uncompressed: some issuers cut a gzip body off mid-stream, and half a page must not pass as a page.
        "Accept-Encoding": "identity",
    }
    if validators.get("etag"):
        headers["If-None-Match"] = validators["etag"]
    if validators.get("last_modified"):
        headers["If-Modified-Since"] = validators["last_modified"]

    host = urlparse(url).netloc
    error = ""
    for attempt in range(ATTEMPTS):
        if attempt:
            throttle.sleep(2**attempt)
        throttle.wait(host)
        try:
            response = get(url, headers)
        except OSError as problem:
            error = str(problem) or type(problem).__name__
            continue
        status = response.status
        if status == 304:
            return PageResult("not-modified", final_url=response.url)
        if 200 <= status < 300:
            if len(response.body) > MAX_BYTES:
                return PageResult("failed", error="page larger than the size limit")
            content_type = response.headers.get("content-type", "")
            if content_type and "html" not in content_type and "text" not in content_type:
                return PageResult("failed", error=f"not a web page ({content_type})")
            try:
                text = visible_text(decode(response))
            except (OSError, EOFError, ValueError, zlib.error) as problem:
                return PageResult("failed", error=f"unreadable reply: {problem}")
            return PageResult(
                "ok" if len(text) >= MIN_TEXT_CHARS else "needs-browser",
                text=text,
                final_url=response.url,
                etag=response.headers.get("etag", ""),
                last_modified=response.headers.get("last-modified", ""),
            )
        if status in (404, 410):
            return PageResult("gone", error=f"HTTP {status}")
        if status in (401, 403, 429):
            return PageResult("refused", error=f"HTTP {status}")
        error = f"HTTP {status}"
    return PageResult("failed", error=error)


# --- One run ---------------------------------------------------------------------------


@dataclass
class CardOutcome:
    card_id: str
    url: str
    status: str  # new, unchanged, changed, or one of PageResult's non-ok statuses
    detail: str = ""


@dataclass
class RunSummary:
    outcomes: list[CardOutcome] = field(default_factory=list)

    def by_status(self) -> dict[str, list[CardOutcome]]:
        groups: dict[str, list[CardOutcome]] = {}
        for outcome in self.outcomes:
            groups.setdefault(outcome.status, []).append(outcome)
        return groups

    @property
    def failure_rate(self) -> float:
        if not self.outcomes:
            return 0.0
        failed = sum(1 for o in self.outcomes if o.status in ("failed", "gone"))
        return failed / len(self.outcomes)


def read_json(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def run(cards: list[dict], state: dict, cache: Path, get, throttle: Throttle, today: str) -> RunSummary:
    """Fetch the given cards' pages, update `state` and `cache` in place, and say what happened."""
    robots = Robots(get, throttle)
    summary = RunSummary()
    by_url: dict[str, list[dict]] = {}
    for card in cards:
        by_url.setdefault(card["sourceUrl"], []).append(card)

    for url, sharing in by_url.items():
        # Ask "has it changed?" only when every card on this page has a hash and a cached copy to
        # fall back on; otherwise a 304 would leave some card with nothing to compare against.
        known = all(state.get(c["id"], {}).get("hash") and (cache / c["id"] / "latest.txt").exists() for c in sharing)
        validators = read_json(cache / sharing[0]["id"] / "http.json", {}) if known else {}
        page = fetch_page(url, get, robots, throttle, validators)
        for card in sharing:
            summary.outcomes.append(_record(card, url, page, state, cache, today))
    return summary


def _record(card: dict, url: str, page: PageResult, state: dict, cache: Path, today: str) -> CardOutcome:
    card_id = card["id"]
    entry = state.get(card_id, {})
    folder = cache / card_id
    status = page.status

    if page.status == "ok":
        new_hash = text_hash(page.text)
        old_hash = entry.get("hash")
        latest = folder / "latest.txt"
        if old_hash is None:
            status, detail = "new", ""
        elif old_hash == new_hash:
            status, detail = "unchanged", ""
        else:
            previous_text = latest.read_text(encoding="utf-8") if latest.exists() else ""
            if previous_text:
                (folder / "previous.txt").write_text(previous_text, encoding="utf-8")
                detail = f"{changed_line_count(previous_text, page.text)} lines changed"
            else:
                detail = "no earlier copy to compare"
            status = "changed"
        folder.mkdir(parents=True, exist_ok=True)
        latest.write_text(page.text, encoding="utf-8")
        write_json(folder / "http.json", {"etag": page.etag, "last_modified": page.last_modified})
        state[card_id] = {
            "url": url,
            "hash": new_hash,
            "textChars": len(page.text),
            "finalUrl": page.final_url,
            "changedAt": today if status in ("new", "changed") else entry.get("changedAt", today),
            "lastStatus": "ok",
        }
        return CardOutcome(card_id, url, status, detail)

    if page.status == "not-modified":
        state[card_id] = {**entry, "url": url, "lastStatus": "ok"}
        return CardOutcome(card_id, url, "unchanged", "not modified since last fetch")

    # Anything else leaves the last good hash alone and records only why this fetch fell short.
    state[card_id] = {**entry, "url": url, "lastStatus": page.status}
    return CardOutcome(card_id, url, page.status, page.error)


def report(summary: RunSummary, total_cards: int) -> str:
    order = ["changed", "new", "unchanged", "needs-browser", "refused", "robots", "gone", "failed"]
    groups = summary.by_status()
    lines = ["# Fetch report", "", f"{len(summary.outcomes)} of {total_cards} cards fetched.", ""]
    lines.append("| Status | Cards |")
    lines.append("|---|---|")
    for status in order + sorted(set(groups) - set(order)):
        if status in groups:
            lines.append(f"| {status} | {len(groups[status])} |")
    for status in order:
        if status in groups and status != "unchanged":
            lines += ["", f"## {status}", ""]
            for outcome in groups[status]:
                note = f": {outcome.detail}" if outcome.detail else ""
                lines.append(f"- `{outcome.card_id}` {outcome.url}{note}")
    return "\n".join(lines) + "\n"


def select(cards: list[dict], only: list[str], issuer: str, limit: int | None) -> list[dict]:
    chosen = [
        card
        for card in cards
        if (not only or card["id"] in only) and (not issuer or issuer.lower() in card["issuer"].lower())
    ]
    return chosen[:limit] if limit else chosen


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch issuer pages and report which changed.")
    parser.add_argument("--only", nargs="+", default=[], metavar="ID", help="fetch just these card ids")
    parser.add_argument("--issuer", default="", help="fetch just cards whose issuer contains this text")
    parser.add_argument("--limit", type=int, help="fetch at most this many cards")
    parser.add_argument("--delay", type=float, default=DELAY_SECONDS, help="seconds between requests to one host")
    args = parser.parse_args()

    cards = read_json(SEED, {"cards": []})["cards"]
    chosen = select(cards, args.only, args.issuer, args.limit)
    if not chosen:
        sys.exit("No cards match.")
    state = read_json(STATE, {})
    summary = run(chosen, state, CACHE, http_get, Throttle(args.delay), date.today().isoformat())
    write_json(STATE, state)

    text = report(summary, len(chosen))
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / "report.md").write_text(text, encoding="utf-8")
    print(text)

    if summary.failure_rate > FAILURE_LIMIT:
        print(f"{summary.failure_rate:.0%} of cards failed to fetch (limit {FAILURE_LIMIT:.0%}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
