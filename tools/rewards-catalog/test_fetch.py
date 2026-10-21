"""Offline tests for fetch.py: python3 -m unittest discover -s tools/rewards-catalog"""

import copy
import json
import tempfile
import unittest
from pathlib import Path

import fetch
from fetch import Response, Throttle

BODY = "".join(f"<p>Earn {n}% back on category number {n} every month.</p>" for n in range(1, 30))


def page(body: str = BODY, status: int = 200, **headers) -> Response:
    headers.setdefault("content-type", "text/html; charset=utf-8")
    return Response(status, headers, f"<html><body>{body}</body></html>".encode(), "https://x.test/card")


class FakeWeb:
    """Serves queued responses per URL, in order, and remembers every request."""

    def __init__(self, **routes) -> None:
        self.routes = {url.replace("_", "/"): list(replies) for url, replies in routes.items()}
        self.requests: list[tuple[str, dict]] = []

    def route(self, url: str, *replies) -> None:
        self.routes[url] = list(replies)

    def __call__(self, url: str, headers: dict) -> Response:
        self.requests.append((url, headers))
        replies = self.routes.get(url)
        if not replies:
            return Response(404, {}, b"", url)
        reply = replies.pop(0) if len(replies) > 1 else replies[0]
        if isinstance(reply, Exception):
            raise reply
        return reply

    def fetched(self, url: str) -> int:
        return sum(1 for requested, _ in self.requests if requested == url)


def throttle() -> Throttle:
    return Throttle(delay=0, sleep=lambda seconds: None)


ALLOW = Response(200, {"content-type": "text/plain"}, b"User-agent: *\nAllow: /\n", "")


class VisibleTextTests(unittest.TestCase):
    def test_drops_scripts_and_styles_and_collapses_spacing(self):
        html = "<style>p{color:red}</style><script>var a = 1;</script><p>Earn   3%\n on  dining</p><p>Earn 3% on dining</p>"
        self.assertEqual(fetch.visible_text(html), "Earn 3% on dining")

    def test_blocks_become_lines(self):
        self.assertEqual(fetch.visible_text("<li>One</li><li>Two<br>Three</li>"), "One\nTwo\nThree")

    def test_markup_changes_do_not_change_the_hash(self):
        a = fetch.text_hash(fetch.visible_text("<div class='a'><p>5% on gas</p></div>"))
        b = fetch.text_hash(fetch.visible_text("<section><p>5%   on gas</p><script>track()</script></section>"))
        self.assertEqual(a, b)
        self.assertNotEqual(a, fetch.text_hash(fetch.visible_text("<p>4% on gas</p>")))

    def test_counts_changed_lines(self):
        self.assertEqual(fetch.changed_line_count("a\nb\nc", "a\nB\nc"), 2)
        self.assertEqual(fetch.changed_line_count("a", "a"), 0)


class EmbeddedTextTests(unittest.TestCase):
    def test_reads_json_script_tags_and_meta_descriptions(self):
        html = (
            '<meta name="description" content="Earn 3X points at supermarkets"/>'
            '<script type="application/ld+json">{"name": "Cash back on groceries", "value": "5% cash back", "id": "x1"}</script>'
        )
        self.assertEqual(
            fetch.embedded_text(html).splitlines(),
            ["Earn 3X points at supermarkets", "Cash back on groceries", "5% cash back"],
        )

    def test_reads_what_a_page_assigns_to_window(self):
        html = '<script>window.__DATA__ = {"a": {"b": ["Earn 2% on gas"]}}; var x = {not: json};</script>'
        self.assertEqual(fetch.embedded_text(html), "Earn 2% on gas")

    def test_opens_json_that_is_inside_a_string_inside_json(self):
        # Amex: window.__INITIAL_STATE__ = "<transit JSON, as a string>"
        inner = json.dumps(["~#iM", ["bodyContent", "Earn 3% Cash Back at US supermarkets<sup>®</sup>."]])
        html = f"<script>window.__INITIAL_STATE__ = {json.dumps(inner)};</script>"
        self.assertEqual(fetch.embedded_text(html), "Earn 3% Cash Back at US supermarkets®.")

    def test_keeps_only_prose(self):
        junk = ["bodyContent", "https://x.test/a b", "sha256-" + "A" * 60 + " sha384-" + "B" * 60, "a { color: red }", "~#iM x"]
        html = f'<script type="application/json">{json.dumps(["Plenty of words here", *junk, "Plenty of words here"])}</script>'
        self.assertEqual(fetch.embedded_text(html), "Plenty of words here")

    def test_a_script_that_is_not_json_is_ignored(self):
        self.assertEqual(fetch.embedded_text("<script>window.x = function() { return 1 }</script>"), "")
        self.assertEqual(fetch.embedded_text('<script type="application/json">not json</script>'), "")


class ThrottleTests(unittest.TestCase):
    def test_waits_only_for_the_same_host(self):
        now, slept = [0.0], []
        clock = lambda: now[0]
        t = Throttle(delay=1.0, clock=clock, sleep=lambda s: (slept.append(s), now.__setitem__(0, now[0] + s)))
        t.wait("a.test")
        t.wait("b.test")
        t.wait("a.test")
        self.assertEqual(slept, [1.0])


class RobotsTests(unittest.TestCase):
    def allowed(self, reply) -> bool:
        web = FakeWeb()
        web.route("https://x.test/robots.txt", reply)
        return fetch.Robots(web, throttle()).allowed("https://x.test/card")

    def test_follows_disallow(self):
        txt = b"User-agent: *\nDisallow: /card\n"
        self.assertFalse(self.allowed(Response(200, {}, txt, "")))
        self.assertTrue(self.allowed(Response(200, {}, b"User-agent: *\nDisallow: /other\n", "")))

    def test_missing_robots_allows_but_broken_robots_does_not(self):
        self.assertTrue(self.allowed(Response(404, {}, b"", "")))
        self.assertFalse(self.allowed(Response(500, {}, b"", "")))
        self.assertFalse(self.allowed(OSError("down")))


class FetchPageTests(unittest.TestCase):
    URL = "https://x.test/card"

    def fetch(self, *replies, validators=None) -> tuple[fetch.PageResult, FakeWeb]:
        web = FakeWeb()
        web.route("https://x.test/robots.txt", ALLOW)
        web.route(self.URL, *replies)
        result = fetch.fetch_page(self.URL, web, fetch.Robots(web, throttle()), throttle(), validators or {})
        return result, web

    def test_reads_a_page(self):
        result, _ = self.fetch(page(etag='"v1"'))
        self.assertEqual((result.status, result.etag), ("ok", '"v1"'))
        self.assertIn("Earn 3% back", result.text)

    def test_a_shell_page_needs_a_browser(self):
        self.assertEqual(self.fetch(page("<div id=app></div>"))[0].status, "needs-browser")

    def test_a_shell_page_with_embedded_data_is_read(self):
        data = json.dumps(["Earn %d%% back on category number %d every month." % (n, n) for n in range(1, 30)])
        result, _ = self.fetch(page(f'<div id=app></div><script type="application/json">{data}</script>'))
        self.assertEqual(result.status, "ok")
        self.assertTrue(result.embedded)
        self.assertIn("Earn 7% back on category number 7", result.text)

    def test_a_full_page_ignores_embedded_data(self):
        data = json.dumps(["Some hidden sentence here."])
        result, _ = self.fetch(page(BODY + f'<script type="application/json">{data}</script>'))
        self.assertFalse(result.embedded)
        self.assertNotIn("hidden", result.text)

    def test_error_statuses(self):
        self.assertEqual(self.fetch(page(status=403))[0].status, "refused")
        self.assertEqual(self.fetch(page(status=429))[0].status, "refused")
        self.assertEqual(self.fetch(page(status=404))[0].status, "gone")

    def test_retries_server_errors_then_succeeds(self):
        result, web = self.fetch(page(status=503), OSError("reset"), page())
        self.assertEqual(result.status, "ok")
        self.assertEqual(web.fetched(self.URL), 3)

    def test_gives_up_after_three_attempts(self):
        result, web = self.fetch(page(status=503))
        self.assertEqual((result.status, result.error), ("failed", "HTTP 503"))
        self.assertEqual(web.fetched(self.URL), fetch.ATTEMPTS)

    def test_sends_validators_and_reads_a_304(self):
        result, web = self.fetch(Response(304, {}, b"", self.URL), validators={"etag": '"v1"', "last_modified": "Mon"})
        self.assertEqual(result.status, "not-modified")
        sent = web.requests[-1][1]
        self.assertEqual((sent["If-None-Match"], sent["If-Modified-Since"]), ('"v1"', "Mon"))
        self.assertIn("GroshRewardsCatalog", sent["User-Agent"])

    def test_robots_stops_the_request(self):
        web = FakeWeb()
        web.route("https://x.test/robots.txt", Response(200, {}, b"User-agent: *\nDisallow: /\n", ""))
        result = fetch.fetch_page(self.URL, web, fetch.Robots(web, throttle()), throttle(), {})
        self.assertEqual(result.status, "robots")
        self.assertEqual(web.fetched(self.URL), 0)


    def test_unreachable_robots_is_a_failure_not_a_ban(self):
        web = FakeWeb()
        web.route("https://x.test/robots.txt", OSError("offline"))
        result = fetch.fetch_page(self.URL, web, fetch.Robots(web, throttle()), throttle(), {})
        self.assertEqual(result.status, "failed")
        self.assertIn("offline", result.error)
        self.assertEqual(web.fetched(self.URL), 0)


class RunTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.cache = Path(self.dir.name)
        self.cards = [
            {"id": "a", "sourceUrl": "https://x.test/a"},
            {"id": "b", "sourceUrl": "https://x.test/shared"},
            {"id": "c", "sourceUrl": "https://x.test/shared"},
        ]
        self.web = FakeWeb()
        self.web.route("https://x.test/robots.txt", ALLOW)
        self.web.route("https://x.test/a", page())
        self.web.route("https://x.test/shared", page())
        self.state: dict = {}

    def go(self, day="2026-10-20") -> fetch.RunSummary:
        return fetch.run(self.cards, self.state, self.cache, self.web, throttle(), day)

    def statuses(self, summary) -> dict[str, str]:
        return {o.card_id: o.status for o in summary.outcomes}

    def test_first_run_is_new_and_a_shared_page_is_fetched_once(self):
        summary = self.go()
        self.assertEqual(self.statuses(summary), {"a": "new", "b": "new", "c": "new"})
        self.assertEqual(self.web.fetched("https://x.test/shared"), 1)
        self.assertTrue((self.cache / "c" / "latest.txt").exists())

    def test_a_rerun_with_no_changes_changes_nothing(self):
        self.go()
        before = copy.deepcopy(self.state)
        summary = self.go(day="2026-11-20")
        self.assertEqual(set(self.statuses(summary).values()), {"unchanged"})
        self.assertEqual(self.state, before)

    def test_a_changed_page_is_reported_with_its_size(self):
        self.go()
        self.web.route("https://x.test/a", page(BODY.replace("Earn 3%", "Earn 4%")))
        summary = self.go(day="2026-11-20")
        changed = [o for o in summary.outcomes if o.status == "changed"]
        self.assertEqual([(o.card_id, o.detail) for o in changed], [("a", "2 lines changed")])
        self.assertEqual(self.state["a"]["changedAt"], "2026-11-20")
        self.assertEqual(self.state["b"]["changedAt"], "2026-10-20")
        self.assertTrue((self.cache / "a" / "previous.txt").exists())

    def test_a_failed_fetch_keeps_the_last_hash(self):
        self.go()
        kept = self.state["a"]["hash"]
        self.web.route("https://x.test/a", page(status=500))
        summary = self.go(day="2026-11-20")
        self.assertEqual(self.statuses(summary)["a"], "failed")
        self.assertEqual(self.state["a"]["hash"], kept)
        self.assertEqual(self.state["a"]["lastStatus"], "failed")

    def test_failure_rate_counts_failed_and_gone_but_not_refusals(self):
        self.web.route("https://x.test/a", page(status=403))
        self.web.route("https://x.test/shared", page(status=404))
        summary = self.go()
        self.assertEqual(self.statuses(summary), {"a": "refused", "b": "gone", "c": "gone"})
        self.assertAlmostEqual(summary.failure_rate, 2 / 3)

    def test_each_page_is_reported_as_soon_as_it_is_done(self):
        seen = []
        fetch.run(self.cards, self.state, self.cache, self.web, throttle(), "2026-10-20",
                  after_each=lambda outcomes: seen.append(([o.card_id for o in outcomes], sorted(self.state))))
        # "a" has its own page; "b" and "c" share one. State already holds each page's cards when called.
        self.assertEqual(seen, [(["a"], ["a"]), (["b", "c"], ["a", "b", "c"])])

    def test_report_lists_each_group(self):
        self.web.route("https://x.test/a", page(status=403))
        text = fetch.report(self.go(), len(self.cards))
        self.assertIn("| refused | 1 |", text)
        self.assertIn("- `a` https://x.test/a: HTTP 403", text)
        self.assertNotIn("## unchanged", text)


class SelectTests(unittest.TestCase):
    CARDS = [
        {"id": "chase-a", "issuer": "Chase", "sourceUrl": "https://x.test/a"},
        {"id": "chase-b", "issuer": "Chase", "sourceUrl": "https://x.test/b"},
        {"id": "citi-a", "issuer": "Citi", "sourceUrl": "https://x.test/c"},
        {"id": "citi-b", "issuer": "Citi", "sourceUrl": "https://x.test/new-b"},
    ]
    STATE = {
        "chase-a": {"url": "https://x.test/a", "lastStatus": "ok"},
        "chase-b": {"url": "https://x.test/b", "lastStatus": "failed"},
        "citi-b": {"url": "https://x.test/b", "lastStatus": "ok"},
    }

    def ids(self, **kwargs) -> list[str]:
        args = {"only": [], "issuer": "", "limit": None, **kwargs}
        return [c["id"] for c in fetch.select(self.CARDS, args.pop("only"), args.pop("issuer"), args.pop("limit"), **args)]

    def test_filters(self):
        self.assertEqual(self.ids(issuer="chase"), ["chase-a", "chase-b"])
        self.assertEqual(self.ids(only=["citi-a"]), ["citi-a"])
        self.assertEqual(len(self.ids(limit=2)), 2)

    def test_missing_picks_up_cards_never_fetched(self):
        self.assertEqual(self.ids(state=self.STATE, missing=True), ["citi-a", "citi-b"])

    def test_retry_picks_up_failures(self):
        self.assertEqual(self.ids(state=self.STATE, retry=True), ["chase-b", "citi-b"])

    def test_missing_and_retry_together(self):
        self.assertEqual(self.ids(state=self.STATE, missing=True, retry=True), ["chase-b", "citi-a", "citi-b"])

    def test_a_card_whose_page_moved_is_refetched(self):
        # citi-b was fetched from /b but the seed now says /new-b.
        self.assertIn("citi-b", self.ids(state=self.STATE, retry=True))


if __name__ == "__main__":
    unittest.main()
