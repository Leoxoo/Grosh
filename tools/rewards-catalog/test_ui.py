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
        self.paths = ui.Paths(seed=root / "seed.json", state=root / "state.json", cache=root / "cache", manual=root / "manual.json")
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
