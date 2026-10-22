#!/usr/bin/env python3
"""A local web page for the rewards catalog pipeline: see every card, pick the model, run and watch jobs.

    python3 tools/rewards-catalog/ui.py            # then open http://127.0.0.1:8765
    python3 tools/rewards-catalog/ui.py --port 9000

It runs the same code as fetch.py and extract.py, on the same files, so the command line and the
page stay in step. Standard library only. It listens on 127.0.0.1 only, and refuses requests whose
Host isn't local or whose POSTs lack the X-Requested-With header, so a web page you visit can't
drive it.

What the page does:
  - works with any server that speaks the OpenAI chat completions API (LM Studio, OpenAI, vLLM, a
    vendor's own), including ones that need a bearer token; lists the server's models and lets you
    choose one, plus the reply limit, time limit, page size, output format and other request fields;
  - keeps the API key in cache/ui-settings.json (not committed, readable only by you) and never
    sends it back to the page;
  - tests the model on the real output schema, which shows at once whether the server accepts it;
  - runs one job at a time, either "fetch pages" or "extract rules", on all cards, the ones that
    need it, or the ones you tick, with a live log, a progress bar and a Stop button;
  - shows every card's fetch and extraction status, and for one card: the rules found, what was
    rejected and why, any error, the page's rate lines, and a "try" that shows the model's raw reply.
"""

import argparse
import json
import os
import re
import sys
import threading
import time
import traceback
import urllib.request
from dataclasses import dataclass
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).parent))
import extract  # noqa: E402
import fetch  # noqa: E402

PAGE = Path(__file__).with_name("ui.html")
DEFAULT_PORT = 8765
LOG_LIMIT = 2000
LOCAL_HOSTS = {"127.0.0.1", "localhost", "[::1]"}
REQUEST_HEADER = "rewards-ui"


@dataclass
class Paths:
    seed: Path = fetch.SEED
    state: Path = fetch.STATE
    cache: Path = fetch.CACHE
    manual: Path = extract.MANUAL_RULES

    @property
    def candidates(self) -> Path:
        return self.cache / "candidates"

    @property
    def settings(self) -> Path:
        return self.cache / "ui-settings.json"


def default_settings() -> dict:
    return {
        "baseUrl": os.environ.get("LLM_BASE_URL") or os.environ.get("LM_STUDIO_URL") or extract.DEFAULT_URL,
        "model": os.environ.get("LLM_MODEL") or os.environ.get("LM_STUDIO_MODEL") or extract.DEFAULT_MODEL,
        "apiKey": os.environ.get("LLM_API_KEY", ""),
        "responseMode": "json_schema",
        "tokenField": "max_tokens",
        "temperature": 0,
        "chunkChars": extract.CHUNK_CHARS,
        "maxTokens": extract.DEFAULT_MAX_TOKENS,
        "timeoutSeconds": extract.DEFAULT_TIMEOUT,
        "extraBody": "",
        "promptSuffix": "",
    }


MAX_PROFILES = 20


def _same_server(a: dict, b: dict) -> bool:
    """Whether two settings point at the same server, key and model (the other settings are tuning)."""
    return all(a.get(k) == b.get(k) for k in ("baseUrl", "model", "apiKey"))


def public_settings(settings: dict) -> dict:
    """The settings as the page may see them: everything except the API key, which is only ever reported as set or not."""
    return {**{k: v for k, v in settings.items() if k != "apiKey"}, "apiKey": "", "apiKeySet": bool(settings.get("apiKey"))}


def write_private(path: Path, data: str) -> None:
    """Write a file only its owner can read: it may hold an API key."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as file:
        os.fchmod(file.fileno(), 0o600)  # also for a file that existed with looser permissions
        file.write(data)


def clean_settings(raw: dict, current: dict) -> dict:
    """`current` with the given settings applied, or ValueError saying which one is wrong."""
    merged = {**current, **{key: raw[key] for key in current if key in raw}}
    url, model = merged["baseUrl"], merged["model"]
    if not isinstance(url, str) or not re.match(r"^https?://", url.strip()):
        raise ValueError("The server address must start with http:// or https://")
    if not isinstance(model, str) or not model.strip():
        raise ValueError("Choose a model")
    ranges = {"chunkChars": (1_000, 60_000), "maxTokens": (200, 32_000), "timeoutSeconds": (10, 3_600)}
    for key, (low, high) in ranges.items():
        value = merged[key]
        if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
            raise ValueError(f"{key} must be a whole number from {low} to {high}")
    key = merged["apiKey"]
    if not isinstance(key, str) or len(key) > 500 or not key.isascii() or any(c.isspace() or not c.isprintable() for c in key):
        raise ValueError("The API key must be a single line of plain characters (up to 500)")
    if merged["responseMode"] not in extract.RESPONSE_MODES:
        raise ValueError(f"responseMode must be one of: {', '.join(extract.RESPONSE_MODES)}")
    if merged["tokenField"] not in extract.TOKEN_FIELDS:
        raise ValueError(f"tokenField must be one of: {', '.join(extract.TOKEN_FIELDS)}")
    temperature = merged["temperature"]
    if temperature in ("", None):
        merged["temperature"] = None  # leave it out of requests: some models accept only their default
    elif isinstance(temperature, bool) or not isinstance(temperature, (int, float)) or not 0 <= temperature <= 2:
        raise ValueError("temperature must be a number from 0 to 2, or empty to leave it out")
    extra, suffix = merged["extraBody"], merged["promptSuffix"]
    if not isinstance(extra, str) or not isinstance(suffix, str) or len(suffix) > 500:
        raise ValueError("Extra request fields and the prompt suffix must be text (the suffix at most 500 characters)")
    if extra.strip():
        try:
            parsed = json.loads(extra)
        except ValueError as problem:
            raise ValueError(f"Extra request fields aren't valid JSON: {problem}") from problem
        if not isinstance(parsed, dict):
            raise ValueError('Extra request fields must be a JSON object, like {"reasoning_effort": "low"}')
    merged["baseUrl"], merged["model"] = url.strip().rstrip("/"), model.strip()
    merged["extraBody"], merged["promptSuffix"] = extra.strip(), suffix.strip()
    return merged


class Job:
    """One running (or finished) fetch or extract job, safe to read while it runs."""

    def __init__(self, kind: str, label: str, total: int, clock=time.time) -> None:
        self.kind, self.label, self.total = kind, label, total
        self.state = "running"  # running, done, stopped, failed
        self.done = 0
        self.current: str | None = None
        self.chunk: dict | None = None
        self.counts: dict[str, int] = {}
        self.error: str | None = None
        self.stop = threading.Event()
        self.clock = clock
        self.started = clock()
        self.finished: float | None = None
        self._log: list[dict] = []
        self._count = 0  # lines ever logged: each line's number never changes, even after old ones are dropped
        self._lock = threading.Lock()

    def log(self, text: str, level: str = "info") -> None:
        with self._lock:
            self._log.append({"n": self._count, "t": round(self.clock() - self.started, 1), "level": level, "text": text})
            self._count += 1
            del self._log[: max(0, len(self._log) - LOG_LIMIT)]

    def start_card(self, name: str, detail: str = "") -> None:
        with self._lock:
            self.current, self.chunk = name, None
        self.log(f"{name}  {detail}".rstrip())

    def card_done(self, card_id: str, status: str, detail: str = "", level: str = "info") -> None:
        with self._lock:
            self.done += 1
            self.counts[status] = self.counts.get(status, 0) + 1
            self.chunk = None
        self.log(f"  → {status}  {card_id}{('  ' + detail) if detail else ''}", level)

    def set_chunk(self, done: int, total: int) -> None:
        with self._lock:
            self.chunk = {"done": done, "total": total}

    def finish(self, state: str, error: str | None = None) -> None:
        with self._lock:
            self.state, self.error, self.finished = state, error, self.clock()
            self.current, self.chunk = None, None
        self.log({"done": "Finished.", "stopped": "Stopped.", "failed": f"Failed: {error}"}[state], "error" if state == "failed" else "info")

    def snapshot(self, since: int = 0, with_log: bool = True) -> dict:
        """The job's state, and the log lines numbered `since` or later (`logNext` is what to ask for next)."""
        with self._lock:
            end = self.finished or self.clock()
            return {
                "kind": self.kind, "label": self.label, "state": self.state, "total": self.total, "done": self.done,
                "current": self.current, "chunk": self.chunk, "counts": dict(self.counts), "error": self.error,
                "seconds": round(end - self.started, 1), "logNext": self._count,
                "log": [line for line in self._log if line["n"] >= since] if with_log else [],
            }


def format_stats(stats: dict | None) -> str:
    """One line on what a card cost: "2 calls, 12.2s, 2,486 prompt tokens (2,400 cached), 403 reply tokens"."""
    if not stats or not stats.get("calls"):
        return ""
    prompt = f"{stats['promptTokens']:,} prompt tokens" + (f" ({stats['cachedTokens']:,} cached)" if stats.get("cachedTokens") else "")
    reply = f"{stats['replyTokens']:,} reply tokens" + (f" ({stats['reasoningTokens']:,} reasoning)" if stats.get("reasoningTokens") else "")
    return f"{stats['calls']} call{'s' if stats['calls'] != 1 else ''}, {stats['seconds']}s, {prompt}, {reply}"


class Problem(Exception):
    """A request the page should be told is wrong: carries the HTTP status."""

    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.status = status


class App:
    """Everything the page can ask for. `handle` is the whole API, so it can be tested without a socket."""

    def __init__(
        self, paths: Paths | None = None, http_get=None, throttle_delay: float = fetch.DELAY_SECONDS, lm_urlopen=None
    ) -> None:
        self.paths = paths or Paths()
        self.http_get = http_get or fetch.http_get
        self.lm_urlopen = lm_urlopen or urllib.request.urlopen
        self.throttle_delay = throttle_delay
        self.job: Job | None = None
        self._job_lock = threading.Lock()
        self._thread: threading.Thread | None = None

    # --- reading the files -------------------------------------------------------------

    def cards(self) -> list[dict]:
        return fetch.read_json(self.paths.seed, {"cards": []})["cards"]

    def card(self, card_id: str) -> dict:
        for card in self.cards():
            if card["id"] == card_id:
                return card
        raise Problem(f"No card {card_id!r}", 404)

    def settings(self) -> dict:
        saved = {k: v for k, v in fetch.read_json(self.paths.settings, {}).items() if k != "profiles"}
        try:
            return clean_settings(saved, default_settings())
        except ValueError:
            return default_settings()

    def _profiles(self) -> dict:
        profiles = fetch.read_json(self.paths.settings, {}).get("profiles", {})
        return profiles if isinstance(profiles, dict) else {}

    def _write_settings(self, active: dict, profiles: dict) -> None:
        # One private file holds the active settings, the saved profiles, and every key in them.
        write_private(self.paths.settings, json.dumps({**active, "profiles": profiles}, indent=2, sort_keys=True) + "\n")

    def profile_list(self) -> dict:
        """Saved profiles (a server address, key and model kept together), without their keys."""
        current, profiles = self.settings(), self._profiles()
        names = sorted(profiles)
        same = [n for n in names if _same_server(profiles[n], current)]
        return {
            "profiles": [{"name": n, "baseUrl": profiles[n].get("baseUrl"), "model": profiles[n].get("model"),
                          "apiKeySet": bool(profiles[n].get("apiKey"))} for n in names],
            "active": same[0] if same else None,
        }

    def change_profile(self, body: dict) -> dict:
        action, name = body.get("action"), body.get("name")
        if not isinstance(name, str) or not name.strip() or len(name.strip()) > 40 or not name.isprintable():
            raise Problem("A profile name is 1 to 40 plain characters")
        name = name.strip()
        profiles = self._profiles()
        if action == "save":
            if name not in profiles and len(profiles) >= MAX_PROFILES:
                raise Problem(f"At most {MAX_PROFILES} profiles")
            profiles[name] = self.settings()
        elif action in ("use", "delete"):
            if name not in profiles:
                raise Problem(f"No profile {name!r}", 404)
            if action == "delete":
                del profiles[name]
            else:
                try:
                    self._write_settings(clean_settings(profiles[name], default_settings()), profiles)
                except ValueError as problem:
                    raise Problem(f"That profile is no longer valid: {problem}") from problem
                return {**self.profile_list(), "settings": public_settings(self.settings())}
        else:
            raise Problem("action must be save, use or delete")
        self._write_settings(self.settings(), profiles)
        return {**self.profile_list(), "settings": public_settings(self.settings())}

    def save_settings(self, raw: dict) -> dict:
        """Apply and save settings; returns them without the API key. A blank key in `raw` keeps the saved
        key, so the page need not hold it; `clearApiKey` removes it."""
        current = self.settings()
        raw = {k: v for k, v in raw.items() if not (k == "apiKey" and not v)}
        if raw.get("clearApiKey"):
            raw["apiKey"] = ""
        try:
            merged = clean_settings(raw, current)
        except ValueError as problem:
            raise Problem(str(problem)) from problem
        self._write_settings(merged, self._profiles())
        return public_settings(merged)

    def client(self, settings: dict | None = None) -> extract.ChatServer:
        s = settings or self.settings()
        return extract.ChatServer(
            s["baseUrl"], s["model"], s["timeoutSeconds"], urlopen=self.lm_urlopen, max_tokens=s["maxTokens"],
            extra_body=json.loads(s["extraBody"]) if s["extraBody"] else {}, prompt_suffix=s["promptSuffix"],
            api_key=s["apiKey"], response_mode=s["responseMode"], token_field=s["tokenField"], temperature=s["temperature"],
        )

    def candidate(self, card_id: str) -> dict | None:
        return fetch.read_json(self.paths.candidates / f"{card_id}.json", None)

    # --- the overview ----------------------------------------------------------------------

    def overview(self) -> dict:
        cards, state, settings = self.cards(), fetch.read_json(self.paths.state, {}), self.settings()
        manual = fetch.read_json(self.paths.manual, {})
        rows = []
        for card in cards:
            entry = state.get(card["id"], {})
            candidate = self.candidate(card["id"])
            page = extract.has_page(card, state, self.paths.cache)
            hand_entered = card["id"] in manual
            pending = (
                False if hand_entered or not page
                else not extract.up_to_date(self.paths.candidates / f"{card['id']}.json", entry["hash"], settings["model"])
            )
            rows.append({
                "id": card["id"], "name": card["name"], "issuer": card["issuer"], "kind": card["rewardKind"],
                "sourceUrl": card["sourceUrl"], "handEntered": hand_entered,
                "fetch": {
                    "status": entry.get("lastStatus", "never"), "chars": entry.get("textChars"),
                    "embedded": bool(entry.get("embedded")), "changedAt": entry.get("changedAt"), "hasPage": page,
                },
                "extract": None if candidate is None else {
                    "status": candidate.get("status"), "rules": len(candidate.get("rules", [])),
                    "rejected": len(candidate.get("rejected", [])), "model": candidate.get("model"),
                    "promptVersion": candidate.get("promptVersion"), "needs": candidate.get("needs", []),
                    "errors": candidate.get("errors", [])[:1], "stats": candidate.get("stats"),
                    "warnings": candidate.get("warnings", []),
                    "statsText": format_stats(candidate.get("stats")),
                },
                "pending": pending,
            })
        summary: dict[str, int] = {"cards": len(rows), "fetched": 0, "pending": 0, "extracted": 0, "failed": 0}
        for row in rows:
            summary["fetched"] += row["fetch"]["hasPage"]
            summary["pending"] += row["pending"]
            summary["extracted"] += bool(row["extract"] and row["extract"]["status"] in ("ok", "manual"))
            summary["failed"] += bool(row["extract"] and row["extract"]["status"] == "failed")
        return {
            "cards": rows, "summary": summary, "settings": public_settings(settings), "promptVersion": extract.PROMPT_VERSION,
            "job": self.job.snapshot(with_log=False) if self.job else None,
        }

    def card_detail(self, card_id: str) -> dict:
        card = self.card(card_id)
        state = fetch.read_json(self.paths.state, {}).get(card_id)
        page_file = self.paths.cache / card_id / "latest.txt"
        page = None
        if page_file.exists():
            text = page_file.read_text(encoding="utf-8")
            lines = [line for line in text.splitlines() if extract.has_rates(line)]
            page = {"chars": len(text), "rateLines": [line[:400] for line in lines[:60]], "rateLineCount": len(lines),
                    "head": text[:1200]}
        return {
            "card": card, "fetch": state, "candidate": self.candidate(card_id),
            "manual": fetch.read_json(self.paths.manual, {}).get(card_id), "page": page,
        }

    # --- the model server ---------------------------------------------------------------------

    def lm_models(self) -> dict:
        settings = self.settings()
        try:
            models = self.client(settings).models()
        except extract.ServerHTTPError as problem:
            if problem.code in (404, 405, 501):  # some servers have no model list: typing a model id still works
                return {"ok": True, "models": [], "error": None, "note": "This server doesn't list its models; type the model id."}
            hint = " Check the API key." if problem.code in (401, 403) else ""
            return {"ok": False, "models": [], "error": f"The server at {settings['baseUrl']} refused the request: {problem}.{hint}"}
        except (OSError, ValueError, KeyError, TypeError) as problem:
            return {"ok": False, "models": [], "error": f"Can't reach the model server at {settings['baseUrl']}: {problem}"}
        return {"ok": True, "models": models, "error": None}

    def test_model(self) -> dict:
        """Ask the chosen model for an empty list of rules, using the real output schema. This is the
        quickest way to learn whether the server accepts the schema and the model answers in time."""
        client = self.client()
        messages = [
            {"role": "system", "content": extract.SYSTEM_PROMPT},
            {"role": "user", "content": 'There are no rates in this text. Reply {"cardConditions": [], "rules": []}.'},
        ]
        started = time.time()
        try:
            reply = client.complete(messages)
        except (OSError, ValueError) as problem:
            return {"ok": False, "seconds": round(time.time() - started, 1), "meta": client.last_meta,
                    "error": f"{type(problem).__name__}: {problem}"}
        seconds = round(time.time() - started, 1)
        try:
            extract.parse_reply(reply)
        except ValueError as problem:
            return {"ok": False, "seconds": seconds, "meta": client.last_meta, "reply": reply[:600],
                    "error": f"The reply isn't in the shape we need: {problem}"}
        return {"ok": True, "seconds": seconds, "meta": client.last_meta, "reply": reply[:600], "error": None}

    def ask(self, body: dict) -> dict:
        """Send any prompt to the chosen model, with extra request fields for this one try. For finding out
        what a server accepts: which field shortens its thinking, how fast it answers, how much it reasons."""
        prompt, extra = body.get("prompt"), body.get("extraBody") or ""
        if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 6000:
            raise Problem("Write a prompt (up to 6,000 characters)")
        try:
            extra_fields = json.loads(extra) if isinstance(extra, str) and extra.strip() else (extra if isinstance(extra, dict) else {})
        except ValueError as problem:
            raise Problem(f"The extra fields aren't valid JSON: {problem}") from problem
        if not isinstance(extra_fields, dict):
            raise Problem("The extra fields must be a JSON object")
        client = self.client()
        started = time.time()
        try:
            reply = client.complete([{"role": "user", "content": prompt}], free=True, extra_body=extra_fields)
        except (OSError, ValueError) as problem:
            return {"ok": False, "seconds": round(time.time() - started, 1), "meta": client.last_meta,
                    "error": f"{type(problem).__name__}: {problem}"}
        return {"ok": True, "seconds": round(time.time() - started, 1), "meta": client.last_meta, "reply": reply[:4000]}

    def try_card(self, card_id: str) -> dict:
        """Send the card's first rate-bearing chunk to the model and show the raw reply and what the
        checks make of each rule. Nothing is saved."""
        card = self.card(card_id)
        page_file = self.paths.cache / card_id / "latest.txt"
        if not page_file.exists():
            raise Problem("This card has no fetched page yet.")
        text = page_file.read_text(encoding="utf-8")
        settings = self.settings()
        chunks = [c for c in extract.chunk_lines(text, settings["chunkChars"]) if extract.has_rates(c)]
        if not chunks:
            return {"chunks": 0, "message": "No part of this page states a rate, so the model would not be asked."}
        messages = extract.build_messages(card, chunks[0])
        result = {"chunks": len(chunks), "promptChars": sum(len(m["content"]) for m in messages)}
        started = time.time()
        client = self.client(settings)
        try:
            reply = client.complete(messages)
        except (OSError, ValueError) as problem:
            return {**result, "seconds": round(time.time() - started, 1), "meta": client.last_meta,
                    "error": f"{type(problem).__name__}: {problem}"}
        result.update(seconds=round(time.time() - started, 1), reply=reply[:8000], replyChars=len(reply), meta=client.last_meta)
        try:
            proposals, card_conditions = extract.parse_reply(reply)
        except ValueError as problem:
            return {**result, "error": str(problem)}
        page_norm = extract.normalize(text)
        result["rules"] = [{"rule": rule, "problem": extract.validate_rule(rule, page_norm)} for rule in proposals]
        result["cardConditions"] = [
            {"text": c, "problem": extract.check_condition(c, page_norm)} for c in card_conditions
        ]
        return result

    # --- jobs ---------------------------------------------------------------------------------

    def choose_cards(self, body: dict) -> tuple[list[dict], str]:
        kind, which, ids = body.get("kind"), body.get("which"), body.get("ids") or []
        cards, state = self.cards(), fetch.read_json(self.paths.state, {})
        if which == "ids":
            chosen = [card for card in cards if card["id"] in set(ids)]
            if kind == "extract":
                manual_ids = set(fetch.read_json(self.paths.manual, {}))
                chosen = [c for c in chosen if extract.has_page(c, state, self.paths.cache) or c["id"] in manual_ids]
                if ids and not chosen:
                    raise Problem("None of the ticked cards has a fetched page yet. Fetch them first.")
            if not chosen:
                raise Problem("Tick at least one card first.")
            return chosen, f"{len(chosen)} ticked card(s)"
        if kind == "fetch":
            chosen = fetch.select(cards, [], "", None, state, missing=which == "missing", retry=which == "retry")
            if which == "all":
                chosen = cards
            return chosen, {"missing": "cards never fetched", "retry": "cards that failed or came back thin", "all": "every card"}.get(which, "")
        manual = extract.load_manual(cards, self.paths.manual)
        with_pages = [c for c in cards if extract.has_page(c, state, self.paths.cache) or c["id"] in manual]
        if which == "all":
            return with_pages, "every card with a page"
        model = self.settings()["model"]
        chosen = [
            c for c in with_pages
            if c["id"] in manual or not extract.up_to_date(self.paths.candidates / f"{c['id']}.json", state[c["id"]]["hash"], model)
        ]
        return chosen, "cards that need extracting"

    def start_job(self, body: dict) -> dict:
        kind = body.get("kind")
        if kind not in ("fetch", "extract"):
            raise Problem("kind must be fetch or extract")
        allowed = {"fetch": ("ids", "missing", "retry", "all"), "extract": ("ids", "pending", "all")}[kind]
        if body.get("which") not in allowed:
            raise Problem(f"For {kind}, which must be one of: {', '.join(allowed)}")
        with self._job_lock:
            if self.job and self.job.state == "running":
                raise Problem("A job is already running. Stop it or wait for it to finish.", 409)
            try:
                chosen, what = self.choose_cards(body)
            except ValueError as problem:
                raise Problem(str(problem)) from problem
            if not chosen:
                raise Problem("Nothing to do: no cards match.")
            job = Job(kind, f"{'Fetch pages' if kind == 'fetch' else 'Extract rules'}: {what}", len(chosen))
            self.job = job
            target = self._run_fetch if kind == "fetch" else self._run_extract
            self._thread = threading.Thread(target=target, args=(job, chosen, bool(body.get("force"))), daemon=True)
            self._thread.start()
        return job.snapshot()

    def stop_job(self) -> dict:
        if not self.job or self.job.state != "running":
            raise Problem("No job is running.", 409)
        self.job.stop.set()
        self.job.log("Stopping after the current step...")
        return self.job.snapshot()

    def _run_fetch(self, job: Job, chosen: list[dict], force: bool) -> None:
        state = fetch.read_json(self.paths.state, {})
        names = {card["id"]: card["name"] for card in chosen}

        def before(url: str, sharing: list[dict]) -> None:
            job.start_card(sharing[0]["name"], f"fetching {url}")

        def after(outcomes) -> None:
            fetch.write_json(self.paths.state, state)  # saved after every page, as on the command line
            for outcome in outcomes:
                bad = outcome.status in ("failed", "gone")
                job.card_done(names.get(outcome.card_id, outcome.card_id), outcome.status, outcome.detail, "error" if bad else "info")

        try:
            fetch.run(chosen, state, self.paths.cache, self.http_get, fetch.Throttle(self.throttle_delay),
                      date.today().isoformat(), after_each=after, before_each=before, should_stop=job.stop.is_set)
            job.finish("stopped" if job.stop.is_set() and job.done < job.total else "done")
        except Exception as problem:  # the page shows any failure instead of dying silently
            job.log(traceback.format_exc(limit=3), "error")
            job.finish("failed", f"{type(problem).__name__}: {problem}")

    def _run_extract(self, job: Job, chosen: list[dict], force: bool) -> None:
        settings = self.settings()
        client = self.client(settings)
        cards = self.cards()
        state = fetch.read_json(self.paths.state, {})

        def emit(event: dict) -> None:
            if event["event"] == "card-start":
                job.start_card(event["name"], "(hand-entered)" if event["kind"] == "hand-entered" else f"· {client.model}")
            else:
                detail = "" if event["rules"] is None else f"{event['rules']} rules, {event['rejected']} rejected"
                if event.get("stats"):
                    detail += f"  [{format_stats(event['stats'])}]"
                failed = event["status"] == "failed"
                job.card_done(event["name"], event["status"], detail, "error" if failed else "info")
                for message in event["errors"][:2]:
                    job.log(f"      {message}", "error")
                for message in event.get("warnings", []):
                    job.log(f"      check: {message}", "warn")

        def progress(card_id: str, done: int, total: int) -> None:
            job.set_chunk(done, total)
            if job.stop.is_set():
                raise extract.Stopped

        try:
            manual = extract.load_manual(cards, self.paths.manual)
            extract.process_cards(
                chosen, state=state, manual=manual, client=client, chunk_chars=settings["chunkChars"], force=force,
                cache=self.paths.cache, candidates=self.paths.candidates, emit=emit,
                ensure_server=lambda: extract.check_server(client), progress=progress, should_stop=job.stop.is_set,
            )
            job.finish("done")
        except extract.Stopped:
            job.finish("stopped")
        except extract.ServerProblem as problem:
            job.finish("failed", str(problem))
        except Exception as problem:
            job.log(traceback.format_exc(limit=3), "error")
            job.finish("failed", f"{type(problem).__name__}: {problem}")

    # --- routing --------------------------------------------------------------------------------

    def handle(self, method: str, path: str, query: dict, body: dict) -> tuple[int, dict]:
        try:
            return 200, self._route(method, path, query, body)
        except Problem as problem:
            return problem.status, {"error": str(problem)}
        except ValueError as problem:
            return 400, {"error": str(problem)}

    def _route(self, method: str, path: str, query: dict, body: dict):
        if method == "GET":
            if path == "/api/overview":
                return self.overview()
            if path == "/api/settings":
                return public_settings(self.settings())
            if path == "/api/models":
                return self.lm_models()
            if path == "/api/profiles":
                return self.profile_list()
            if path == "/api/job":
                since = int((query.get("since") or ["0"])[0] or 0)
                return {"job": self.job.snapshot(since) if self.job else None}
            if match := re.fullmatch(r"/api/card/([\w.-]+)", path):
                return self.card_detail(match.group(1))
        elif method == "POST":
            if path == "/api/settings":
                return self.save_settings(body)
            if path == "/api/profiles":
                return self.change_profile(body)
            if path == "/api/test-model":
                return self.test_model()
            if path == "/api/ask":
                return self.ask(body)
            if path == "/api/job":
                return self.start_job(body)
            if path == "/api/job/stop":
                return self.stop_job()
            if match := re.fullmatch(r"/api/card/([\w.-]+)/try", path):
                return self.try_card(match.group(1))
        raise Problem("Not found", 404)


def host_name(header: str) -> str:
    """The host in a Host header, without its port: "localhost:8765" -> "localhost", "[::1]:8765" -> "[::1]"."""
    return header.split("]")[0] + "]" if header.startswith("[") else header.split(":")[0]


def make_handler(app: App):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args) -> None:  # the page polls often; keep the terminal quiet
            pass

        def _send(self, status: int, payload, content_type: str = "application/json") -> None:
            data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", f"{content_type}; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _dispatch(self, method: str) -> None:
            if host_name(self.headers.get("Host", "")) not in LOCAL_HOSTS:
                return self._send(403, {"error": "Only local requests are accepted."})
            parsed = urlparse(self.path)
            if method == "GET" and parsed.path in ("/", "/index.html"):
                return self._send(200, PAGE.read_bytes(), "text/html")
            body: dict = {}
            if method == "POST":
                if self.headers.get("X-Requested-With") != REQUEST_HEADER:
                    return self._send(403, {"error": "Missing X-Requested-With header."})
                length = int(self.headers.get("Content-Length") or 0)
                try:
                    body = json.loads(self.rfile.read(length) or b"{}")
                except ValueError:
                    return self._send(400, {"error": "The request body isn't JSON."})
                if not isinstance(body, dict):
                    return self._send(400, {"error": "The request body must be a JSON object."})
            status, payload = app.handle(method, parsed.path, parse_qs(parsed.query), body)
            self._send(status, payload)

        def do_GET(self) -> None:
            self._dispatch("GET")

        def do_POST(self) -> None:
            self._dispatch("POST")

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description="A local web page for the rewards catalog pipeline.")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()
    app = App()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(app))
    print(f"Rewards catalog page: http://127.0.0.1:{args.port}   (Ctrl-C to stop)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        if app.job and app.job.state == "running":
            app.job.stop.set()
        print("\nStopped.")


if __name__ == "__main__":
    main()
