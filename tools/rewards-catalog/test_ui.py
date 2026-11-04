"""Offline tests for ui.py's logic (no browser, no LM Studio): python3 -m unittest discover -s tools/rewards-catalog"""

import io
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

import extract
import fetch
import review
import ui

PAGE_TEXT = "Savor Rewards Credit Card\nEarn unlimited 3% cash back on dining, entertainment and popular streaming services.\n" + "Filler line.\n" * 5
RULE = {
    "categories": ["dining"], "selection": "fixed", "picks": None, "hasOtherChoices": False, "rate": 3, "unit": "percent",
    "capAmount": None, "capPeriod": None, "requires": [], "validFrom": None, "validTo": None, "firstMonths": None,
    "conditions": [], "quote": "Earn unlimited 3% cash back on dining, entertainment and popular streaming services.",
}
REPLY = json.dumps({"cardConditions": [], "rules": [RULE]})


def card(card_id: str, name: str, issuer: str = "Bank") -> dict:
    return {"id": card_id, "name": name, "issuer": issuer, "network": "Visa", "rewardKind": "cashback", "annualFee": 0,
            "sourceUrl": f"https://x.test/{card_id}"}


class FakeLM:
    """Stands in for LM Studio's server: lists `models` and answers each completion with the next reply."""

    def __init__(self, models=("good-model", "other-model"), replies=(REPLY,), on_complete=None) -> None:
        self.models, self.replies, self.on_complete = list(models), list(replies), on_complete
        self.asked: list[dict] = []

    def __call__(self, request, timeout):
        if request.full_url.endswith("/models"):
            self.seen_headers = dict(request.header_items())
            return io.BytesIO(json.dumps({"data": [{"id": m} for m in self.models]}).encode())
        body = json.loads(request.data)
        self.seen_headers = dict(request.header_items())
        self.asked.append(body)
        if self.on_complete:
            self.on_complete()
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
        if isinstance(reply, Exception):
            raise reply
        return io.BytesIO(json.dumps({"choices": [{"message": {"content": reply}}]}).encode())


class AppCase(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        self.paths = ui.Paths(seed=root / "seed.json", state=root / "state.json", cache=root / "cache", manual=root / "manual.json",
                              decisions=root / "review-decisions.json", options=root / "card-options.json",
                              catalog=root / "rewards-catalog.json")
        self.cards = [card("bank-a", "Savor Rewards"), card("bank-b", "Other Card"), card("zed-c", "Zed Card", "Zed")]
        self.paths.seed.write_text(json.dumps({"cards": self.cards}))
        self.state: dict = {}
        self.app = ui.App(self.paths, throttle_delay=0, lm_urlopen=FakeLM())

    def give_page(self, card_id: str, text: str = PAGE_TEXT, status: str = "ok") -> None:
        folder = self.paths.cache / card_id
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "latest.txt").write_text(text)
        self.state[card_id] = {"url": f"https://x.test/{card_id}", "hash": fetch.text_hash(text), "textChars": len(text),
                               "lastStatus": status, "changedAt": "2026-10-20"}
        self.paths.state.write_text(json.dumps(self.state))

    def wait(self) -> dict:
        self.app._thread.join(10)
        self.assertFalse(self.app._thread.is_alive(), "the job didn't finish")
        return self.app.job.snapshot()

    def use(self, **fake) -> FakeLM:
        lm = FakeLM(**fake)
        self.app.lm_urlopen = lm
        return lm


class SettingsTests(AppCase):
    def test_defaults_and_saving(self):
        self.assertEqual(self.app.settings()["model"], ui.default_settings()["model"])
        saved = self.app.save_settings({"model": "good-model", "baseUrl": "http://localhost:1234/v1/", "chunkChars": 8000, "junk": 1})
        self.assertEqual((saved["model"], saved["baseUrl"], saved["chunkChars"]), ("good-model", "http://localhost:1234/v1", 8000))
        self.assertNotIn("junk", saved)
        self.assertEqual(ui.public_settings(self.app.settings()), saved)  # read back from cache/ui-settings.json

    def test_bad_settings_are_refused_with_a_reason(self):
        for bad, message in (({"extraBody": "{nope"}, "JSON"), ({"extraBody": "[1]"}, "object"), ({"promptSuffix": "x" * 501}, "suffix"),
                             ({"baseUrl": "ftp://x"}, "http"), ({"model": " "}, "model"), ({"chunkChars": 5}, "chunkChars"),
                             ({"maxTokens": "lots"}, "maxTokens"), ({"timeoutSeconds": True}, "timeoutSeconds")):
            status, payload = self.app.handle("POST", "/api/settings", {}, bad)
            self.assertEqual(status, 400, bad)
            self.assertIn(message, payload["error"])

    def test_extra_fields_and_suffix_are_used_by_the_client(self):
        self.app.save_settings({"extraBody": '{"reasoning_effort": "low"}', "promptSuffix": "/no_think", "maxTokens": 4000})
        client = self.app.client()
        self.assertEqual((client.extra_body, client.prompt_suffix, client.max_tokens), ({"reasoning_effort": "low"}, "/no_think", 4000))
        self.assertEqual(ui.default_settings()["maxTokens"], extract.DEFAULT_MAX_TOKENS)

    def test_the_api_key_is_kept_private(self):
        public = self.app.save_settings({"apiKey": "secret-token-123"})
        self.assertEqual((public["apiKey"], public["apiKeySet"]), ("", True))
        self.assertEqual(self.app.settings()["apiKey"], "secret-token-123")
        self.assertEqual(self.paths.settings.stat().st_mode & 0o777, 0o600)

        for path in ("/api/settings", "/api/overview"):  # nothing the page can read includes the key
            status, payload = self.app.handle("GET", path, {}, {})
            self.assertEqual(status, 200)
            self.assertNotIn("secret-token-123", json.dumps(payload))
        status, payload = self.app.handle("POST", "/api/settings", {}, {"model": "good-model", "apiKey": "secret-token-123"})
        self.assertNotIn("secret-token-123", json.dumps(payload))

    def test_a_blank_key_keeps_the_saved_one_and_clearing_removes_it(self):
        self.app.save_settings({"apiKey": "secret-token-123"})
        self.app.save_settings({"model": "other-model", "apiKey": ""})
        self.assertEqual(self.app.settings()["apiKey"], "secret-token-123")
        public = self.app.save_settings({"clearApiKey": True})
        self.assertEqual((self.app.settings()["apiKey"], public["apiKeySet"]), ("", False))

    def test_the_settings_file_stays_private_when_it_already_existed(self):
        self.paths.cache.mkdir(parents=True)
        self.paths.settings.write_text("{}")
        self.paths.settings.chmod(0o644)
        self.app.save_settings({"apiKey": "secret-token-123"})
        self.assertEqual(self.paths.settings.stat().st_mode & 0o777, 0o600)

    def test_new_settings_are_checked(self):
        for bad, message in (({"apiKey": "has space"}, "API key"), ({"apiKey": "line\nbreak"}, "API key"), ({"apiKey": "kéy"}, "API key"),
                             ({"responseMode": "xml"}, "responseMode"), ({"tokenField": "limit"}, "tokenField"),
                             ({"temperature": 5}, "temperature"), ({"temperature": "hot"}, "temperature")):
            status, payload = self.app.handle("POST", "/api/settings", {}, bad)
            self.assertEqual(status, 400, bad)
            self.assertIn(message, payload["error"])
        self.assertIsNone(self.app.save_settings({"temperature": ""})["temperature"])
        self.assertEqual(self.app.save_settings({"temperature": 0.5})["temperature"], 0.5)

    def test_the_client_carries_all_of_it(self):
        self.app.save_settings({"apiKey": "k", "responseMode": "prompt", "tokenField": "max_completion_tokens", "temperature": ""})
        client = self.app.client()
        self.assertEqual((client.api_key, client.response_mode, client.token_field, client.temperature), ("k", "prompt", "max_completion_tokens", None))

    def test_profiles_keep_a_server_with_its_key_and_switching_swaps_them(self):
        self.app.save_settings({"baseUrl": "http://a.test/v1", "model": "model-a", "apiKey": "key-a"})
        self.app.change_profile({"action": "save", "name": "Server A"})
        self.app.save_settings({"baseUrl": "http://b.test/v1", "model": "model-b", "apiKey": "key-b", "chunkChars": 5000})
        listed = self.app.change_profile({"action": "save", "name": "Server B"})
        self.assertEqual([p["name"] for p in listed["profiles"]], ["Server A", "Server B"])
        self.assertEqual(listed["active"], "Server B")
        self.assertNotIn("key-", json.dumps(listed))

        used = self.app.change_profile({"action": "use", "name": "Server A"})
        self.assertEqual((used["settings"]["model"], used["settings"]["apiKeySet"], used["active"]), ("model-a", True, "Server A"))
        self.assertEqual(self.app.settings()["apiKey"], "key-a")  # B's key is no longer the one in use
        self.assertEqual(self.app.profile_list()["profiles"][1]["name"], "Server B")  # and B is still saved

        self.app.save_settings({"model": "model-a2"})  # editing the active settings doesn't lose the profiles
        self.assertEqual(len(self.app.profile_list()["profiles"]), 2)
        self.assertIsNone(self.app.profile_list()["active"])  # no longer matches Server A

    def test_profile_requests_are_checked_and_deleting_removes_the_key(self):
        self.app.save_settings({"apiKey": "key-a"})
        self.app.change_profile({"action": "save", "name": "A"})
        for body, status in (({"action": "save", "name": ""}, 400), ({"action": "save", "name": "x" * 41}, 400),
                             ({"action": "use", "name": "nope"}, 404), ({"action": "explode", "name": "A"}, 400)):
            self.assertEqual(self.app.handle("POST", "/api/profiles", {}, body)[0], status, body)
        self.app.change_profile({"action": "delete", "name": "A"})
        self.assertNotIn("A", self.paths.settings.read_text())
        self.assertEqual(self.paths.settings.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.app.handle("GET", "/api/profiles", {}, {})[1]["profiles"], [])

    def test_the_browser_option_is_saved_and_on_by_default(self):
        self.assertTrue(self.app.settings()["browser"])
        self.assertTrue(self.app.save_settings({"browser": True})["browser"])
        self.assertTrue(self.app.settings()["browser"])

    def test_a_corrupt_settings_file_falls_back_to_defaults(self):
        self.paths.cache.mkdir(parents=True)
        self.paths.settings.write_text('{"chunkChars": 1}')
        self.assertEqual(self.app.settings(), ui.default_settings())


class OverviewTests(AppCase):
    def test_every_card_with_what_is_known_about_it(self):
        self.give_page("bank-a")
        self.app.save_settings({"model": "good-model"})
        rows = {r["id"]: r for r in self.app.overview()["cards"]}
        self.assertEqual(set(rows), {"bank-a", "bank-b", "zed-c"})
        self.assertEqual((rows["bank-a"]["fetch"]["hasPage"], rows["bank-a"]["pending"], rows["bank-a"]["extract"]), (True, True, None))
        self.assertEqual((rows["bank-b"]["fetch"]["status"], rows["bank-b"]["pending"]), ("never", False))

    def test_a_card_is_pending_until_extracted_with_the_chosen_model(self):
        self.give_page("bank-a")
        self.app.save_settings({"model": "good-model"})
        self.app.start_job({"kind": "extract", "which": "pending"})
        self.wait()
        row = next(r for r in self.app.overview()["cards"] if r["id"] == "bank-a")
        self.assertEqual((row["pending"], row["extract"]["status"], row["extract"]["rules"]), (False, "ok", 1))
        self.app.save_settings({"model": "other-model"})
        row = next(r for r in self.app.overview()["cards"] if r["id"] == "bank-a")
        self.assertTrue(row["pending"])  # same page, different model

    def test_hand_entered_cards_are_never_pending_and_the_summary_counts(self):
        self.give_page("bank-a")
        self.paths.manual.write_text(json.dumps({"bank-a": {"rules": []}}))
        overview = self.app.overview()
        row = next(r for r in overview["cards"] if r["id"] == "bank-a")
        self.assertEqual((row["handEntered"], row["pending"]), (True, False))
        self.assertEqual((overview["summary"]["cards"], overview["summary"]["fetched"], overview["summary"]["pending"]), (3, 1, 0))


    def test_a_card_waiting_on_a_decision_says_what_is_needed(self):
        self.cards[1]["needsInfo"] = "The card no longer exists: mark it discontinued or replace it?"
        self.paths.seed.write_text(json.dumps({"cards": self.cards}))
        rows = {r["id"]: r for r in self.app.overview()["cards"]}
        self.assertEqual((rows["bank-a"]["needsInfo"], rows["bank-b"]["needsInfo"]), (None, self.cards[1]["needsInfo"]))

    def test_a_page_in_the_state_but_not_the_cache_says_so_and_is_fetched_as_missing(self):
        self.give_page("bank-a")
        (self.paths.cache / "bank-a" / "latest.txt").unlink()
        row = next(r for r in self.app.overview()["cards"] if r["id"] == "bank-a")
        self.assertEqual((row["fetch"]["status"], row["fetch"]["hasPage"], row["pending"]), ("not-saved", False, False))
        chosen, _ = self.app.choose_cards({"kind": "fetch", "which": "missing"})
        self.assertIn("bank-a", [c["id"] for c in chosen])

    def test_extracting_ticked_cards_says_which_were_skipped_for_want_of_a_page(self):
        self.give_page("bank-a")
        chosen, what = self.app.choose_cards({"kind": "extract", "which": "ids", "ids": ["bank-a", "bank-b"]})
        self.assertEqual(([c["id"] for c in chosen], what), (["bank-a"], "1 ticked card(s); 1 skipped, no saved page (fetch them first)"))
        with self.assertRaises(ui.Problem):
            self.app.choose_cards({"kind": "extract", "which": "ids", "ids": ["bank-b"]})


class DetailAndModelTests(AppCase):
    def test_card_detail_shows_the_page_candidate_and_rate_lines(self):
        self.give_page("bank-a")
        detail = self.app.card_detail("bank-a")
        self.assertEqual(detail["card"]["name"], "Savor Rewards")
        self.assertEqual(detail["page"]["rateLineCount"], 1)
        self.assertIn("3% cash back on dining", detail["page"]["rateLines"][0])
        self.assertIsNone(detail["candidate"])
        self.assertEqual(self.app.handle("GET", "/api/card/nope", {}, {})[0], 404)

    def test_models_listed_or_a_reason_given(self):
        self.use(models=("a", "b"))
        self.assertEqual(self.app.lm_models(), {"ok": True, "models": ["a", "b"], "error": None})

        def down(request, timeout):
            raise urllib.error.URLError("refused")

        self.app.lm_urlopen = down
        result = self.app.lm_models()
        self.assertFalse(result["ok"])
        self.assertIn("refused", result["error"])

    def test_a_server_without_a_model_list_still_works_and_a_bad_key_is_named(self):
        def no_list(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 404, "Not Found", {}, io.BytesIO(b"{}"))

        self.app.lm_urlopen = no_list
        result = self.app.lm_models()
        self.assertEqual((result["ok"], result["models"]), (True, []))
        self.assertIn("type the model id", result["note"])

        def refused(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 401, "Unauthorized", {}, io.BytesIO(b'{"error": "bad key"}'))

        self.app.lm_urlopen = refused
        result = self.app.lm_models()
        self.assertFalse(result["ok"])
        self.assertIn("Check the API key", result["error"])

    def test_the_key_goes_out_as_a_bearer_token_when_models_are_listed_and_asked(self):
        self.app.save_settings({"apiKey": "secret-token-123", "model": "good-model"})
        lm = self.use()
        self.app.lm_models()
        self.assertEqual(lm.seen_headers["Authorization"], "Bearer secret-token-123")
        self.give_page("bank-a")
        self.app.start_job({"kind": "extract", "which": "pending"})
        self.wait()
        self.assertEqual(lm.seen_headers["Authorization"], "Bearer secret-token-123")

    def test_the_model_test_uses_the_real_schema_and_reports_lm_studios_complaint(self):
        lm = self.use(replies=['{"cardConditions": [], "rules": []}'])
        self.assertTrue(self.app.test_model()["ok"])
        self.assertEqual(lm.asked[0]["response_format"]["json_schema"]["schema"], extract.SCHEMA)

        def refuse(request, timeout):
            raise urllib.error.HTTPError("u", 400, "Bad Request", {}, io.BytesIO(b'{"error": "schema not supported"}'))

        self.app.lm_urlopen = refuse
        result = self.app.test_model()
        self.assertFalse(result["ok"])
        self.assertIn("schema not supported", result["error"])

        self.use(replies=["Sure! Here are the rules:"])
        self.assertIn("shape we need", self.app.test_model()["error"])

    def test_try_shows_the_raw_reply_and_what_the_checks_make_of_it(self):
        self.give_page("bank-a")
        bad = dict(RULE, rate=4, quote="Earn 4% cash back on gas.")
        self.use(replies=[json.dumps({"cardConditions": ["Made up."], "rules": [RULE, bad]})])
        result = self.app.try_card("bank-a")
        self.assertEqual(result["chunks"], 1)
        self.assertEqual([x["problem"] is None for x in result["rules"]], [True, False])
        self.assertIn("not on the page", result["rules"][1]["problem"])
        self.assertIn("not on the page", result["cardConditions"][0]["problem"])
        self.assertIn("cardConditions", result["reply"])
        self.assertIsNone(self.app.candidate("bank-a"))  # nothing saved

    def test_try_without_a_page_or_without_rates(self):
        with self.assertRaises(ui.Problem):
            self.app.try_card("bank-b")
        self.give_page("bank-b", "Other Card\nNothing to see here.")
        self.assertEqual(self.app.try_card("bank-b")["chunks"], 0)


class JobTests(AppCase):
    def test_extract_runs_one_card_at_a_time_and_saves_each(self):
        self.give_page("bank-a")
        self.give_page("zed-c", PAGE_TEXT.replace("Savor Rewards", "Zed Card"))
        self.app.save_settings({"model": "good-model"})
        self.app.start_job({"kind": "extract", "which": "pending"})
        done = self.wait()
        self.assertEqual((done["state"], done["done"], done["total"], done["counts"]), ("done", 2, 2, {"ok": 2}))
        self.assertTrue((self.paths.candidates / "bank-a.json").exists())
        self.assertTrue(any("Savor Rewards" in line["text"] for line in done["log"]))
        self.assertEqual(self.app.job.state, "done")

    def test_a_running_job_refuses_another(self):
        self.give_page("bank-a")
        self.app.save_settings({"model": "good-model"})
        gate = threading.Event()
        self.use(on_complete=lambda: gate.wait(5))
        self.app.start_job({"kind": "extract", "which": "pending"})
        status, payload = self.app.handle("POST", "/api/job", {}, {"kind": "extract", "which": "pending"})
        self.assertEqual(status, 409)
        gate.set()
        self.wait()

    def test_stop_ends_the_job_between_cards(self):
        for card_id, name in (("bank-a", "Savor Rewards"), ("zed-c", "Zed Card")):
            self.give_page(card_id, PAGE_TEXT.replace("Savor Rewards", name))
        self.app.save_settings({"model": "good-model"})
        self.use(on_complete=lambda: self.app.stop_job())
        self.app.start_job({"kind": "extract", "which": "pending"})
        done = self.wait()
        self.assertEqual(done["state"], "stopped")
        self.assertLess(done["done"], done["total"])

    def test_a_missing_model_fails_the_job_with_the_fix(self):
        self.give_page("bank-a")
        self.app.save_settings({"model": "not-loaded"})
        self.app.start_job({"kind": "extract", "which": "pending"})
        done = self.wait()
        self.assertEqual(done["state"], "failed")
        self.assertIn("no model 'not-loaded'", done["error"])
        self.assertIn("good-model", done["error"])

    def test_a_card_whose_model_call_fails_is_logged_with_the_reason(self):
        self.give_page("bank-a")
        self.app.save_settings({"model": "good-model"})
        self.use(replies=["not json"])
        self.app.start_job({"kind": "extract", "which": "pending"})
        done = self.wait()
        self.assertEqual((done["state"], done["counts"]), ("done", {"failed": 1}))
        self.assertTrue(any(line["level"] == "error" and "not json" in line["text"] for line in done["log"]))

    def test_hand_entered_cards_need_no_model(self):
        self.give_page("bank-a")
        rule = dict(RULE, quote="Earn unlimited 3% cash back on dining")
        self.paths.manual.write_text(json.dumps({"bank-a": {"rules": [rule]}}))
        self.app.save_settings({"model": "not-loaded"})  # LM Studio wouldn't have it, and it isn't needed
        self.app.start_job({"kind": "extract", "which": "ids", "ids": ["bank-a"]})
        done = self.wait()
        self.assertEqual((done["state"], done["counts"]), ("done", {"manual": 1}))

    def test_fetch_runs_and_saves_state_after_each_page(self):
        body = "<html><body>" + "".join(f"<p>Earn {n}% back on category {n} every month.</p>" for n in range(1, 30)) + "</body></html>"

        def get(url, headers):
            if url.endswith("/robots.txt"):
                return fetch.Response(404, {}, b"", url)
            return fetch.Response(200, {"content-type": "text/html"}, body.encode(), url)

        self.app.http_get = get
        self.app.start_job({"kind": "fetch", "which": "missing"})
        done = self.wait()
        self.assertEqual((done["state"], done["done"], done["counts"]), ("done", 3, {"new": 3}))
        self.assertEqual(len(json.loads(self.paths.state.read_text())), 3)

    def test_fetch_can_be_stopped(self):
        def get(url, headers):
            if not url.endswith("/robots.txt"):
                self.app.stop_job()
            return fetch.Response(404, {}, b"", url)

        self.app.http_get = get
        self.app.start_job({"kind": "fetch", "which": "all"})
        self.assertEqual(self.wait()["state"], "stopped")

    def test_requests_that_make_no_sense_are_refused(self):
        for body, message in (({"kind": "dance", "which": "all"}, "kind"), ({"kind": "fetch", "which": "pending"}, "which"),
                              ({"kind": "extract", "which": "retry"}, "which"), ({"kind": "fetch", "which": "ids", "ids": []}, "Tick"),
                              ({"kind": "extract", "which": "ids", "ids": ["bank-a"]}, "fetched page"),
                              ({"kind": "fetch", "which": "retry"}, "Nothing to do")):
            status, payload = self.app.handle("POST", "/api/job", {}, body)
            self.assertEqual(status, 400, body)
            self.assertIn(message, payload["error"])
        self.assertEqual(self.app.handle("POST", "/api/job/stop", {}, {})[0], 409)

    def test_the_log_is_numbered_so_a_poll_gets_only_what_is_new(self):
        job = ui.Job("fetch", "t", 1)
        for n in range(5):
            job.log(f"line {n}")
        first = job.snapshot(0)
        self.assertEqual((len(first["log"]), first["logNext"]), (5, 5))
        job.log("line 5")
        later = job.snapshot(first["logNext"])
        self.assertEqual([line["text"] for line in later["log"]], ["line 5"])
        for n in range(ui.LOG_LIMIT + 10):
            job.log("x")
        self.assertEqual(len(job.snapshot(0)["log"]), ui.LOG_LIMIT)
        self.assertEqual(job.snapshot(job.snapshot(0)["logNext"])["log"], [])


ROTATING_QUOTE = "Earn 5% cash back on up to $1,500 in rotating bonus categories each quarter you activate."
ROTATING_RULE = {**RULE, "categories": [], "selection": "rotating", "rate": 5, "capAmount": 1500, "capPeriod": "quarter",
                 "requires": ["activation"], "quote": ROTATING_QUOTE}
ROTATING_PAGE = f"Savor Rewards\n{ROTATING_QUOTE}\n" + "".join(f"Filler line number {n}.\n" for n in range(30))
NEXT_QUARTER = "JAN-MAR\n2099\nGrocery Stores\nActivate starting December 15, 2098\n"
COMING_SOON = "APR-JUN\n2099\nComing Soon\nActivate starting March 15, 2099\n"


class RefreshTests(AppCase):
    """Quarters are in 2099 so that none has ended, whatever day the tests run."""

    def setUp(self) -> None:
        super().setUp()
        self.app.save_settings({"model": "good-model"})

    def give_candidate(self, card_id: str, text: str, *rules: dict) -> None:
        text = text.strip()  # as fetch saves it, so serving the same page counts as unchanged
        self.give_page(card_id, text)
        made = [extract.candidate_rule(r, f"https://x.test/{card_id}", fetch.text_hash(text), "page") for r in rules]
        fetch.write_json(self.paths.candidates / f"{card_id}.json", {
            "cardId": card_id, "status": "ok", "model": self.app.settings()["model"], "promptVersion": extract.PROMPT_VERSION,
            "pageHash": fetch.text_hash(text), "rules": made, "rejected": [], "warnings": [], "needs": [], "cardConditions": [],
        })

    def serve(self, pages: dict) -> list[str]:
        """Answers each URL with the page text given for it, and returns the list of pages asked for."""
        asked: list[str] = []

        def get(url: str, headers: dict) -> fetch.Response:
            if url.endswith("robots.txt"):
                return fetch.Response(404, {}, b"", url)
            asked.append(url)
            if url not in pages:
                return fetch.Response(404, {}, b"", url)
            body = "".join(f"<p>{line}</p>" for line in pages[url].splitlines())
            return fetch.Response(200, {"content-type": "text/html"}, f"<html><body>{body}</body></html>".encode(), url)

        self.app.http_get = get
        return asked

    def refresh(self) -> tuple[dict, str]:
        status, job = self.app.handle("POST", "/api/job", {}, {"kind": "refresh", "which": "rotating"})
        self.assertEqual(status, 200, job)
        finished = self.wait()
        return finished, "\n".join(line["text"] for line in finished["log"])

    def test_only_cards_with_a_rotating_rule_are_fetched_and_a_new_quarter_is_said_to_wait(self):
        self.give_candidate("bank-a", ROTATING_PAGE, ROTATING_RULE)
        self.give_candidate("bank-b", PAGE_TEXT, RULE)
        asked = self.serve({"https://x.test/bank-a": ROTATING_PAGE + NEXT_QUARTER, "https://x.test/bank-b": PAGE_TEXT})
        lm = self.use(replies=(json.dumps({"cardConditions": [], "rules": [ROTATING_RULE]}),))
        job, log = self.refresh()
        self.assertEqual(job["state"], "done")
        self.assertEqual(asked, ["https://x.test/bank-a"])
        self.assertTrue(lm.asked)  # its page changed, so it is extracted again
        self.assertIn("waiting for review: 5% in rotating bonus categories from 2099-01-01 to 2099-03-31: groceries", log)
        self.assertIn("Quarter rules waiting for review on: Savor Rewards.", log)

    def test_an_unchanged_page_asks_no_model_and_a_decided_quarter_no_longer_waits(self):
        page = ROTATING_PAGE + NEXT_QUARTER
        self.give_candidate("bank-a", page, ROTATING_RULE)
        self.serve({"https://x.test/bank-a": page})
        lm = self.use()
        self.refresh()
        candidate = self.app.candidate("bank-a")
        quarter = next(r for r in candidate["rules"] if r["validFrom"])
        review.decide(candidate, review.rule_key("bank-a", quarter), "accept", self.paths.decisions, "2098-12-20")
        job, log = self.refresh()
        self.assertEqual(lm.asked, [])
        self.assertEqual(job["counts"].get("up-to-date"), 1)
        self.assertIn("nothing waiting, 1 quarter rule(s) decided", log)
        self.assertIn("No quarter rules are waiting for review.", log)

    def test_an_undated_rotating_rule_gets_its_quarters_from_the_unchanged_page_without_a_model(self):
        page = ROTATING_PAGE + NEXT_QUARTER
        self.give_candidate("bank-a", page, ROTATING_RULE)  # extracted before its calendar could be read
        self.serve({"https://x.test/bank-a": page})
        lm = self.use()
        _, log = self.refresh()
        self.assertEqual(lm.asked, [])
        self.assertEqual([r["validFrom"] for r in self.app.candidate("bank-a")["rules"]], ["2099-01-01", None])
        self.assertIn("waiting for review", log)

    def test_a_rotating_rule_on_a_page_with_no_calendar_is_said_without_a_model_run(self):
        self.give_candidate("bank-a", ROTATING_PAGE, ROTATING_RULE)
        self.serve({"https://x.test/bank-a": ROTATING_PAGE})
        lm = self.use()
        job, log = self.refresh()
        self.assertEqual((job["state"], lm.asked), ("done", []))
        self.assertIn("Savor Rewards: no quarter rules: its page names no quarter ahead", log)

    def test_coming_soon_is_reported_and_is_no_failure(self):
        page = ROTATING_PAGE + COMING_SOON
        self.give_candidate("bank-a", page, ROTATING_RULE)
        self.serve({"https://x.test/bank-a": page})
        self.use()
        job, log = self.refresh()
        self.assertEqual((job["state"], job["error"]), ("done", None))
        self.assertIn("Savor Rewards: 2099-04-01 to 2099-06-30 is Coming Soon", log)
        self.assertEqual([line["text"] for line in job["log"] if line["level"] == "error"], [])
        self.assertNotIn("no quarter rules", log)

    def test_a_page_that_cannot_be_read_is_an_error_and_its_saved_copy_still_counts(self):
        page = ROTATING_PAGE + NEXT_QUARTER
        self.give_candidate("bank-a", page, ROTATING_RULE)
        self.serve({})  # every page fails
        lm = self.use()
        job, log = self.refresh()
        self.assertEqual((job["state"], lm.asked), ("done", []))
        self.assertTrue(any("page not read (gone)" in line["text"] for line in job["log"] if line["level"] == "error"))
        self.assertIn("waiting for review", log)

    def test_a_failed_extraction_is_an_error(self):
        self.give_candidate("bank-a", ROTATING_PAGE, ROTATING_RULE)
        self.serve({"https://x.test/bank-a": ROTATING_PAGE + NEXT_QUARTER})
        self.use(replies=("not json",))
        job, _ = self.refresh()
        self.assertTrue(any("extraction says failed" in line["text"] for line in job["log"] if line["level"] == "error"))

    def test_a_model_server_that_is_down_fails_the_job_when_a_page_changed(self):
        self.give_candidate("bank-a", ROTATING_PAGE, ROTATING_RULE)
        self.serve({"https://x.test/bank-a": ROTATING_PAGE + NEXT_QUARTER})
        self.use(models=())
        job, _ = self.refresh()
        self.assertEqual(job["state"], "failed")

    def test_a_rotating_rule_gone_after_a_page_change_is_said(self):
        self.give_candidate("bank-a", ROTATING_PAGE, ROTATING_RULE)
        self.serve({"https://x.test/bank-a": ROTATING_PAGE.replace(ROTATING_QUOTE, RULE["quote"])})
        self.use()
        job, log = self.refresh()
        self.assertEqual(job["state"], "done")
        self.assertIn("Savor Rewards: its rotating rule is no longer in the candidate", log)

    def test_with_no_rotating_rule_anywhere_nothing_is_fetched(self):
        self.give_candidate("bank-b", PAGE_TEXT, RULE)
        asked = self.serve({"https://x.test/bank-b": PAGE_TEXT})
        status, reply = self.app.handle("POST", "/api/job", {}, {"kind": "refresh", "which": "rotating"})
        self.assertEqual(status, 400)
        self.assertIn("No card has a rotating rule", reply["error"])
        self.assertEqual(asked, [])

    def test_the_count_starts_again_for_the_extract_stage(self):
        self.give_candidate("bank-a", ROTATING_PAGE, ROTATING_RULE)
        self.serve({"https://x.test/bank-a": ROTATING_PAGE})
        self.use()
        job, _ = self.refresh()
        self.assertEqual((job["done"], job["total"]), (1, 1))

    def test_stopping_during_the_fetch_stage_extracts_nothing_and_reports_nothing(self):
        self.give_candidate("bank-a", ROTATING_PAGE, ROTATING_RULE)
        self.give_candidate("bank-b", ROTATING_PAGE.replace("Savor Rewards", "Other Card"), ROTATING_RULE)
        served = self.serve({"https://x.test/bank-a": ROTATING_PAGE + NEXT_QUARTER})
        serve = self.app.http_get

        def stop_after_the_page(url: str, headers: dict) -> fetch.Response:
            reply = serve(url, headers)
            if served:
                self.app.job.stop.set()
            return reply

        self.app.http_get = stop_after_the_page
        lm = self.use()
        job, log = self.refresh()
        self.assertEqual((job["state"], lm.asked), ("stopped", []))
        self.assertEqual(served, ["https://x.test/bank-a"])
        self.assertNotIn("Quarters:", log)

    def test_asking_to_force_a_refresh_still_runs_no_model_on_an_unchanged_page(self):
        self.give_candidate("bank-a", ROTATING_PAGE, ROTATING_RULE)
        self.serve({"https://x.test/bank-a": ROTATING_PAGE})
        lm = self.use()
        self.app.handle("POST", "/api/job", {}, {"kind": "refresh", "which": "rotating", "force": True})
        self.wait()
        self.assertEqual(lm.asked, [])

    def test_the_page_has_the_button(self):
        self.assertIn('data-job="refresh:rotating"', ui.PAGE.read_text(encoding="utf-8"))


class AskAndStatsTests(AppCase):
    def test_ask_sends_a_plain_request_with_extras_for_that_try_only(self):
        lm = self.use(replies=["Three."])
        result = self.app.ask({"prompt": "How many r in strawberry?", "extraBody": '{"top_k": 3}'})
        self.assertEqual((result["ok"], result["reply"]), (True, "Three."))
        body = lm.asked[0]
        self.assertEqual((body["top_k"], body["messages"][0]["content"]), (3, "How many r in strawberry?"))
        self.assertNotIn("response_format", body)
        self.assertNotIn("top_k", self.app.settings()["extraBody"])

    def test_ask_refuses_nonsense_and_reports_failures(self):
        for body in ({"prompt": ""}, {"prompt": "x" * 6001}, {"prompt": "hi", "extraBody": "{nope"}, {"prompt": "hi", "extraBody": "[1]"}):
            self.assertEqual(self.app.handle("POST", "/api/ask", {}, body)[0], 400, body)
        self.app.lm_urlopen = lambda request, timeout: io.BytesIO(b'{"choices": [{"finish_reason": "length", "message": {"content": ""}}]}')
        result = self.app.ask({"prompt": "hi"})
        self.assertFalse(result["ok"])
        self.assertIn("empty reply", result["error"])
        self.assertEqual(result["meta"]["finishReason"], "length")

    def test_a_cards_cost_is_shown_in_the_log_and_the_overview(self):
        self.give_page("bank-a")
        self.app.save_settings({"model": "good-model"})
        lm = self.use()
        original = lm.__call__

        def with_usage(request, timeout):
            reply = original(request, timeout)
            if request.full_url.endswith("/models"):
                return reply
            data = json.loads(reply.read())
            data["usage"] = {"prompt_tokens": 2486, "completion_tokens": 403, "prompt_tokens_details": {"cached_tokens": 2400}}
            return io.BytesIO(json.dumps(data).encode())

        self.app.lm_urlopen = with_usage
        self.app.start_job({"kind": "extract", "which": "pending"})
        done = self.wait()
        self.assertTrue(any("2,486 prompt tokens (2,400 cached), 403 reply tokens" in line["text"] for line in done["log"]))
        row = next(r for r in self.app.overview()["cards"] if r["id"] == "bank-a")
        self.assertIn("2,400 cached", row["extract"]["statsText"])

    def test_format_stats(self):
        self.assertEqual(ui.format_stats(None), "")
        self.assertEqual(ui.format_stats({"calls": 0}), "")
        self.assertEqual(ui.format_stats({"calls": 2, "seconds": 3.5, "promptTokens": 10, "cachedTokens": 0, "replyTokens": 5, "reasoningTokens": 2}),
                         "2 calls, 3.5s, 10 prompt tokens, 5 reply tokens (2 reasoning)")


class ReviewTests(AppCase):
    def extracted(self) -> None:
        self.give_page("bank-a")
        self.app.save_settings({"model": "good-model"})
        self.app.start_job({"kind": "extract", "which": "pending"})
        self.wait()

    def test_the_review_lists_every_card_with_rules_and_what_waits(self):
        self.extracted()
        status, payload = self.app.handle("GET", "/api/review", {}, {})
        self.assertEqual(status, 200)
        (entry,) = payload["cards"]  # cards without rules have nothing to review
        self.assertEqual((entry["cardId"], entry["name"], entry["issuer"]), ("bank-a", "Savor Rewards", "Bank"))
        (row,) = entry["rules"]
        self.assertEqual((row["decision"], row["quote"], row["url"]), (None, RULE["quote"], "https://x.test/bank-a"))
        self.assertEqual(payload["summary"], {"cards": 1, "waiting": 1, "accept": 0, "reject": 0})

    def test_a_decision_is_saved_in_the_committed_file_and_only_accepted_rules_move_on(self):
        self.extracted()
        key = self.app.handle("GET", "/api/review", {}, {})[1]["cards"][0]["rules"][0]["key"]
        status, payload = self.app.handle("POST", "/api/review", {}, {"cardId": "bank-a", "key": key, "decision": "reject"})
        self.assertEqual((status, payload["rules"][0]["decision"]), (200, "reject"))
        self.assertIn(key, self.paths.decisions.read_text())
        self.assertNotIn(fetch.CACHE, ui.Paths().decisions.parents)  # the real file is committed, so decisions travel with the repo
        self.assertEqual(review.accepted_rules(self.app.candidate("bank-a"), review.load_decisions(self.paths.decisions)), [])
        self.app.handle("POST", "/api/review", {}, {"cardId": "bank-a", "key": key, "decision": "accept"})
        self.assertEqual(len(review.accepted_rules(self.app.candidate("bank-a"), review.load_decisions(self.paths.decisions))), 1)

    def test_decisions_that_make_no_sense_are_refused(self):
        self.extracted()
        key = self.app.handle("GET", "/api/review", {}, {})[1]["cards"][0]["rules"][0]["key"]
        for body, status, message in (({"cardId": "bank-a", "key": key, "decision": "maybe"}, 400, "accept, reject or undo"),
                                      ({"cardId": "bank-a", "key": "0" * 16, "decision": "accept"}, 400, "no longer"),
                                      ({"cardId": "bank-b", "key": key, "decision": "accept"}, 404, "no candidate"),
                                      ({"cardId": "nope", "key": key, "decision": "accept"}, 404, "No card")):
            got, payload = self.app.handle("POST", "/api/review", {}, body)
            self.assertEqual(got, status, body)
            self.assertIn(message, payload["error"])
        self.assertFalse(self.paths.decisions.exists())

    def test_the_card_view_carries_each_rules_review_and_the_overview_counts_it(self):
        self.extracted()
        detail = self.app.card_detail("bank-a")
        (row,) = detail["review"]["rules"]
        self.assertEqual((row["decision"], row["summary"]), (None, "3% on dining"))
        overview = self.app.overview()
        counts = {r["id"]: r["review"] for r in overview["cards"]}
        self.assertEqual((counts["bank-a"], counts["bank-b"]), ({"waiting": 1, "accept": 0, "reject": 0}, None))
        self.assertEqual((overview["summary"]["waiting"], overview["summary"]["accept"]), (1, 0))
        dining = next(c for c in overview["catalog"]["categories"] if c["id"] == "dining")
        self.assertEqual((dining["label"], "Restaurants" in dining["app"]), ("Dining", True))
        self.assertIn("activation", overview["catalog"]["requires"])

    def test_a_fix_is_saved_when_the_quote_backs_it_and_refused_when_it_does_not(self):
        self.extracted()
        key = self.app.card_detail("bank-a")["review"]["rules"][0]["key"]
        status, payload = self.app.handle("POST", "/api/review", {}, {"cardId": "bank-a", "key": key, "decision": "edit", "changes": {"categories": ["groceries"]}})
        self.assertEqual(status, 400)
        self.assertIn("groceries", payload["error"])
        status, payload = self.app.handle("POST", "/api/review", {}, {"cardId": "bank-a", "key": key, "decision": "edit", "changes": {"categories": ["entertainment"]}})
        self.assertEqual((status, payload["rules"][0]["decision"], payload["rules"][0]["rule"]["categories"]), (200, "accept", ["entertainment"]))
        accepted = review.accepted_rules(self.app.candidate("bank-a"), review.load_decisions(self.paths.decisions))
        self.assertEqual([r["categories"] for r in accepted], [["entertainment"]])

    def test_publish_writes_the_accepted_rules_to_the_catalog_file(self):
        facts = {"isBusiness": False, "rewardProgram": None, "baseEarnRate": 1, "discontinued": False}
        self.paths.seed.write_text(json.dumps({"cards": [dict(c, **facts) for c in self.cards]}))
        self.extracted()
        key = self.app.handle("GET", "/api/review", {}, {})[1]["cards"][0]["rules"][0]["key"]
        self.app.handle("POST", "/api/review", {}, {"cardId": "bank-a", "key": key, "decision": "accept"})
        status, payload = self.app.handle("POST", "/api/publish", {}, {})
        self.assertEqual((status, payload["cards"], payload["rules"]), (200, 1, 1))
        (published,) = json.loads(self.paths.catalog.read_text())["cards"]
        self.assertEqual([r["evidence"]["quote"] for r in published["rules"]], [RULE["quote"]])
        self.assertEqual(ui.Paths().catalog.parent, Path(ui.__file__).parent)  # committed beside the scripts, not in cache/

    def test_a_card_option_is_saved_shown_in_the_card_and_published(self):
        facts = {"isBusiness": False, "rewardProgram": None, "baseEarnRate": 1, "discontinued": False}
        self.paths.seed.write_text(json.dumps({"cards": [dict(c, **facts) for c in self.cards]}))
        self.extracted()
        status, payload = self.app.handle("POST", "/api/card-options", {}, {"cardId": "bank-a", "name": "bonusesStack", "value": True})
        self.assertEqual((status, payload["options"]["bonusesStack"]), (200, True))
        self.assertTrue(self.app.handle("GET", "/api/card/bank-a", {}, {})[1]["options"]["bonusesStack"])
        key = self.app.handle("GET", "/api/review", {}, {})[1]["cards"][0]["rules"][0]["key"]
        self.app.handle("POST", "/api/review", {}, {"cardId": "bank-a", "key": key, "decision": "accept"})
        self.app.handle("POST", "/api/publish", {}, {})
        self.assertIs(json.loads(self.paths.catalog.read_text())["cards"][0]["bonusesStack"], True)
        self.assertEqual(self.app.handle("POST", "/api/card-options", {}, {"cardId": "bank-a", "name": "x", "value": True})[0], 400)
        self.assertNotIn(fetch.CACHE, ui.Paths().options.parents)  # committed, like the decisions


class ServerTests(AppCase):
    def serve(self):
        try:
            server = ui.ThreadingHTTPServer(("127.0.0.1", 0), ui.make_handler(self.app))
        except OSError as problem:
            self.skipTest(f"can't listen on a local port here: {problem}")
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_address[1]}"

    def ask(self, url, method="GET", headers=None, body=None):
        request = urllib.request.Request(url, method=method, headers=headers or {}, data=None if body is None else json.dumps(body).encode())
        try:
            with urllib.request.urlopen(request, timeout=5) as reply:
                return reply.status, reply.read()
        except urllib.error.HTTPError as problem:
            return problem.code, problem.read()

    def test_serves_the_page_and_the_api_to_the_page_only(self):
        base = self.serve()
        status, html = self.ask(base + "/")
        self.assertEqual(status, 200)
        self.assertIn(b"Rewards catalog", html)
        self.assertEqual(self.ask(base + "/api/overview")[0], 200)
        self.assertEqual(self.ask(base + "/api/job", "POST", body={})[0], 403)  # no X-Requested-With: a web page you visit can't drive it
        self.assertEqual(self.ask(base + "/api/job/stop", "POST", {"X-Requested-With": "rewards-ui"}, {})[0], 409)
        self.assertEqual(self.ask(base + "/api/overview", headers={"Host": "evil.example"})[0], 403)

    def test_host_names(self):
        self.assertEqual([ui.host_name(h) for h in ("localhost:8765", "127.0.0.1", "[::1]:8765", "evil.com:80")],
                         ["localhost", "127.0.0.1", "[::1]", "evil.com"])

    def test_the_page_never_puts_text_into_markup(self):
        page = ui.PAGE.read_text()
        self.assertNotIn("innerHTML", page)
        self.assertNotIn("document.write", page)


if __name__ == "__main__":
    unittest.main()
