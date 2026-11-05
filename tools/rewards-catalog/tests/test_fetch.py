"""Offline tests for fetch.py: python3 -m unittest discover -s tools/rewards-catalog"""

import copy
import json
import tempfile
import unittest
from pathlib import Path

import fetch
import quarters
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

CALENDAR_URL = "https://x.test/calendar"
SENTENCE = "Earn <b>5% <i>Cashback Bonus</i></b> at <b>Restaurants, Entertainment and Utilities,</b> now to December 31, 2026, on up to $1,500 in purchases when you activate."
SAID = "Earn 5% Cashback Bonus at Restaurants, Entertainment and Utilities, now to December 31, 2026, on up to $1,500 in purchases when you activate."


def calendar_data(sentence: str = SENTENCE) -> Response:
    """Discover's calendar data, cut down: what the page's script builds its calendar from."""
    quarter = {"offerDescUnenrolled": sentence, "offerId": 34285, "offerStatus": "qualification",
               "quarterLabelEndDate": "December 31, 2026", "title": "Restaurants, Entertainment and Utilities"}
    return Response(200, {"content-type": "application/json"}, json.dumps({"quarters": [quarter]}).encode(), CALENDAR_URL)


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

    def test_a_long_menu_with_no_reward_words_is_not_a_page(self):
        menu = "<p>Home</p><p>Cash Back Credit Cards</p><p>Points Rewards</p><p>Learn About Credit</p>" + "<p>Locations and hours of operation for branches near you.</p>" * 20
        self.assertEqual(self.fetch(page(menu))[0].status, "needs-browser")

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


class CalendarDataTests(unittest.TestCase):
    def fetch(self, reply: Response, accepts_json: bool = True) -> fetch.PageResult:
        web = FakeWeb()
        web.route("https://x.test/robots.txt", ALLOW)
        web.route(CALENDAR_URL, reply)
        return fetch.fetch_page(CALENDAR_URL, web, fetch.Robots(web, throttle()), throttle(), {}, accepts_json=accepts_json)

    def test_a_calendar_can_be_a_pages_json_data_and_its_sentences_are_what_is_saved(self):
        result = self.fetch(calendar_data())
        self.assertEqual(result.status, "ok")  # one quarter is a short reply, and a whole one
        self.assertEqual(result.text.splitlines(), [SAID, "Restaurants, Entertainment and Utilities"])

    def test_the_body_says_a_reply_is_json_whatever_its_content_type_says(self):
        for headers in ({"content-type": "text/plain"}, {"content-type": "text/html"}, {"content-type": "application/octet-stream"}, {}):
            result = self.fetch(Response(200, headers, calendar_data().body, CALENDAR_URL))
            self.assertEqual((result.status, result.text.splitlines()[0]), ("ok", SAID), headers)

    def test_a_line_break_inside_a_sentence_does_not_split_it(self):
        for tag in ("<br>", "<br/>", "<BR />"):
            result = self.fetch(calendar_data(SENTENCE.replace(",</b> now", f",</b>{tag}now")))
            self.assertIn(SAID, result.text.splitlines(), tag)
            self.assertEqual(len(quarters.read_calendar(result.text)), 1, tag)

    def test_a_non_breaking_space_with_no_tag_near_it_is_a_space(self):
        result = self.fetch(calendar_data(SAID.replace("Entertainment and", "Entertainment&nbsp;and")))
        self.assertEqual(quarters.read_calendar(result.text)[0].names, ("Restaurants", "Entertainment", "Utilities"))

    def test_a_card_pages_embedded_text_is_kept_as_it_was(self):
        page = '<script type="application/json">{"a": "Earn more on food &amp; drink", "b": "Earn more<br>every day"}</script>'
        self.assertEqual(fetch.embedded_text(page), "Earn more on food &amp; drink\nEarn more\nevery day")

    def test_a_json_reply_that_says_nothing_about_earning_is_a_failed_read(self):
        reply = Response(200, {"content-type": "application/json"}, b'{"error": "Service not available today"}', CALENDAR_URL)
        result = self.fetch(reply)
        self.assertEqual(result.status, "failed")
        self.assertIn("says nothing about earning", result.error)

    def test_a_thin_html_reply_is_not_a_calendar(self):
        for headers in ({"content-type": "text/html"}, {}):
            reply = Response(200, headers, b"<html><body>Pardon our interruption. Earn nothing here.</body></html>", CALENDAR_URL)
            self.assertEqual(self.fetch(reply).status, "needs-browser", headers)

    def test_a_card_page_answering_json_is_still_not_a_web_page(self):
        self.assertEqual(self.fetch(calendar_data(), accepts_json=False).status, "failed")

    def test_calendar_data_that_is_not_json_is_a_failed_read(self):
        reply = Response(200, {"content-type": "application/json"}, b"<html>Oops</html>", CALENDAR_URL)
        result = self.fetch(reply)
        self.assertEqual(result.status, "failed")
        self.assertIn("unreadable", result.error)


class BrowserTests(unittest.TestCase):
    URL = "https://x.test/card"
    MENU = "<p>Home</p><p>Cash Back Credit Cards</p>" + "<p>Locations near you.</p>" * 40
    REWARDS = "".join(f"<p>Earn unlimited 1.5 points for every $1 you spend on everyday purchases, tier {n}.</p>" for n in range(10))

    def fetch(self, render):
        web = FakeWeb()
        web.route("https://x.test/robots.txt", ALLOW)
        web.route(self.URL, page(self.MENU))
        return fetch.fetch_page(self.URL, web, fetch.Robots(web, throttle()), throttle(), {}, render=render)

    def test_a_shell_is_rendered_and_read_when_a_browser_is_given(self):
        result = self.fetch(lambda url: "<html><body>" + self.REWARDS + "</body></html>")
        self.assertEqual(result.status, "ok")
        self.assertIn("1.5 points for every $1", result.text)

    def test_without_a_browser_a_shell_stays_needs_browser(self):
        self.assertEqual(self.fetch(None).status, "needs-browser")

    def test_a_browser_that_cannot_run_says_why_and_keeps_needs_browser(self):
        def missing(url):
            raise RuntimeError("the browser option needs Playwright; install it with: python3 -m pip install playwright")

        result = self.fetch(missing)
        self.assertEqual(result.status, "needs-browser")
        self.assertIn("needs Playwright", result.error)

    def test_a_rendered_page_still_without_rewards_is_not_ok(self):
        result = self.fetch(lambda url: "<html><body>" + self.MENU + "</body></html>")
        self.assertEqual(result.status, "needs-browser")

    def test_the_browser_option_is_off_by_default_and_names_its_install(self):
        self.assertIn("playwright install chromium", fetch.BROWSER_INSTALL)


class NotModifiedTests(unittest.TestCase):
    def test_not_modified_still_judges_the_saved_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            (cache / "x").mkdir()
            (cache / "x" / "latest.txt").write_text("Home\nCash Back Credit Cards\n" + "Locations near you. " * 40)
            (cache / "x" / "http.json").write_text(json.dumps({"url": "https://x.test/a", "etag": '"v1"'}))
            web = FakeWeb()
            web.route("https://x.test/robots.txt", ALLOW)
            web.route("https://x.test/a", Response(304, {}, b"", "https://x.test/a"))
            state = {"x": {"url": "https://x.test/a", "hash": "h", "lastStatus": "ok"}}
            summary = fetch.run([{"id": "x", "sourceUrl": "https://x.test/a"}], state, cache, web, throttle(), "2026-10-22")
            self.assertEqual(state["x"]["lastStatus"], "needs-browser")
            self.assertEqual(summary.outcomes[0].status, "needs-browser")
            self.assertEqual(state["x"]["hash"], "h")  # the last good hash is kept, as always


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

    def test_validators_are_only_sent_back_to_the_page_they_came_from(self):
        self.web.route("https://x.test/a", page(etag='"v1"'))
        self.go()
        self.go(day="2026-11-20")
        last_for_a = [r for r in self.web.requests if r[0] == "https://x.test/a"][-1]
        self.assertIn("If-None-Match", last_for_a[1])  # same page: ask whether it changed

        self.cards[0] = {"id": "a", "sourceUrl": "https://x.test/a-moved"}
        self.web.route("https://x.test/a-moved", page(BODY.replace("Earn 3%", "Earn 4%")))
        summary = self.go(day="2026-12-20")
        moved = [r for r in self.web.requests if r[0] == "https://x.test/a-moved"]
        self.assertEqual(len(moved), 1)
        self.assertNotIn("If-None-Match", moved[0][1])  # a new page: read it in full
        self.assertEqual(self.statuses(summary)["a"], "changed")

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


class CalendarPageTests(unittest.TestCase):
    """A card that names a calendar page: the page is fetched and saved with the card's own."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.cache = Path(self.dir.name)
        self.card = {"id": "a", "sourceUrl": "https://x.test/a", "calendarUrl": CALENDAR_URL}
        self.web = FakeWeb()
        self.web.route("https://x.test/robots.txt", ALLOW)
        self.web.route("https://x.test/a", page())
        self.web.route(CALENDAR_URL, calendar_data())
        self.state: dict = {}

    def go(self, *cards, day="2026-10-20") -> dict[str, fetch.CardOutcome]:
        summary = fetch.run(list(cards) or [self.card], self.state, self.cache, self.web, throttle(), day)
        return {o.card_id: o for o in summary.outcomes}

    def saved(self, name: str) -> str:
        return (self.cache / "a" / name).read_text(encoding="utf-8")

    def test_the_calendar_is_saved_beside_the_cards_page(self):
        self.go()
        self.assertIn(SAID, self.saved("calendar.txt").splitlines())
        entry = self.state["a"]
        self.assertEqual((entry["calendarUrl"], entry["calendarStatus"]), (CALENDAR_URL, "ok"))
        self.assertEqual(entry["calendarHash"], fetch.text_hash(self.saved("calendar.txt")))

    def test_the_cards_own_hash_is_its_own_pages(self):
        self.go()
        self.assertEqual(self.state["a"]["hash"], fetch.text_hash(self.saved("latest.txt")))

    def test_a_rerun_with_no_changes_changes_nothing(self):
        self.go()
        before = copy.deepcopy(self.state)
        self.assertEqual(self.go(day="2026-11-20")["a"].status, "unchanged")
        self.assertEqual(self.state, before)

    def test_a_changed_calendar_is_a_changed_card_though_its_page_is_the_same(self):
        self.go()
        hashed = fetch.pages_hash(self.state["a"])
        self.web.route(CALENDAR_URL, calendar_data(SENTENCE.replace("Utilities", "Gas Stations")))
        outcome = self.go(day="2026-11-20")["a"]
        self.assertEqual(outcome.status, "changed")
        self.assertIn("calendar page", outcome.detail)
        self.assertEqual(self.state["a"]["changedAt"], "2026-11-20")
        self.assertNotEqual(fetch.pages_hash(self.state["a"]), hashed)

    def test_a_changed_calendar_counts_when_the_server_says_the_card_page_is_not_modified(self):
        self.web.route("https://x.test/a", page(etag='"v1"'))
        self.go()
        self.web.route("https://x.test/a", Response(304, {}, b"", "https://x.test/a"))
        self.web.route(CALENDAR_URL, calendar_data(SENTENCE.replace("Utilities", "Gas Stations")))
        self.assertEqual(self.go(day="2026-11-20")["a"].status, "changed")

    def test_a_card_given_a_calendar_after_it_was_fetched_has_changed(self):
        self.go({"id": "a", "sourceUrl": "https://x.test/a"})
        self.assertEqual(self.go(day="2026-11-20")["a"].status, "changed")

    def test_a_calendar_that_fails_keeps_what_was_saved_and_says_so(self):
        self.go()
        saved, before = self.saved("calendar.txt"), fetch.pages_hash(self.state["a"])
        self.web.route(CALENDAR_URL, Response(403, {}, b"", CALENDAR_URL))
        outcome = self.go(day="2026-11-20")["a"]
        self.assertEqual(outcome.status, "unchanged")  # the card's page is fine: the card isn't a failed fetch
        self.assertIn("calendar page: refused", outcome.detail)
        self.assertEqual(self.state["a"]["calendarStatus"], "refused")
        self.assertEqual(fetch.pages_hash(self.state["a"]), before)
        self.assertEqual(self.saved("calendar.txt"), saved)

    def test_a_calendar_that_fails_is_an_error_in_the_report_though_the_card_is_unchanged(self):
        self.go()
        self.web.route(CALENDAR_URL, Response(403, {}, b"", CALENDAR_URL))
        summary = fetch.run([self.card], self.state, self.cache, self.web, throttle(), "2026-11-20")
        self.assertEqual(summary.outcomes[0].calendar_error, "refused: HTTP 403")
        text = fetch.report(summary, 1)
        self.assertIn("| calendar page not read | 1 |", text)
        self.assertIn("## calendar page not read", text)
        self.assertIn("- `a` refused: HTTP 403", text)

    def test_a_bot_wall_answered_with_html_is_not_saved_as_the_calendar_and_is_an_error(self):
        self.go()
        saved, before = self.saved("calendar.txt"), fetch.pages_hash(self.state["a"])
        self.web.route(CALENDAR_URL, Response(200, {"content-type": "text/html"}, b"<p>Are you a robot?</p>", CALENDAR_URL))
        outcome = self.go(day="2026-11-20")["a"]
        self.assertEqual((outcome.status, outcome.calendar_error), ("unchanged", "needs-browser"))
        self.assertEqual((self.saved("calendar.txt"), fetch.pages_hash(self.state["a"])), (saved, before))

    def test_json_sent_as_plain_text_does_not_change_the_card(self):
        self.go()
        self.web.route(CALENDAR_URL, Response(200, {"content-type": "text/plain"}, calendar_data().body, CALENDAR_URL))
        self.assertEqual(self.go(day="2026-11-20")["a"].status, "unchanged")

    def test_a_calendar_robots_blocks_is_an_error_too(self):
        self.web.route("https://y.test/robots.txt", Response(200, {"content-type": "text/plain"}, b"User-agent: *\nDisallow: /\n", ""))
        card = {**self.card, "calendarUrl": "https://y.test/calendar"}
        self.assertEqual(self.go(card)["a"].calendar_error, "robots")

    def test_a_calendar_that_was_read_is_no_error_and_the_report_has_no_such_part(self):
        summary = fetch.run([self.card], self.state, self.cache, self.web, throttle(), "2026-11-20")
        self.assertEqual(summary.outcomes[0].calendar_error, "")
        self.assertNotIn("calendar page not read", fetch.report(summary, 1))

    def test_cards_that_share_a_calendar_fetch_it_once(self):
        self.web.route("https://x.test/b", page())
        self.go(self.card, {"id": "b", "sourceUrl": "https://x.test/b", "calendarUrl": CALENDAR_URL})
        self.assertEqual(self.web.fetched(CALENDAR_URL), 1)
        self.assertTrue((self.cache / "b" / "calendar.txt").exists())

    def test_a_card_with_no_calendar_page_has_the_state_and_hash_it_always_had(self):
        self.go({"id": "a", "sourceUrl": "https://x.test/a"})
        entry = self.state["a"]
        self.assertEqual(set(entry), {"url", "hash", "textChars", "finalUrl", "changedAt", "lastStatus"})
        self.assertEqual(fetch.pages_hash(entry), entry["hash"])
        self.assertEqual(self.web.fetched(CALENDAR_URL), 0)
        self.assertFalse((self.cache / "a" / "calendar.txt").exists())


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

    def test_missing_picks_up_fetched_cards_whose_text_is_not_saved(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            state = {**self.STATE, "chase-a": {**self.STATE["chase-a"], "hash": "h"}, "citi-b": {**self.STATE["citi-b"], "hash": "h"}}
            (cache / "citi-b").mkdir()
            (cache / "citi-b" / "latest.txt").write_text("saved")
            # chase-a was fetched but its text is gone; chase-b failed, so it never had text to lose.
            self.assertEqual(self.ids(state=state, missing=True, cache=cache), ["chase-a", "citi-a", "citi-b"])
            self.assertEqual(self.ids(state=state, missing=True), ["citi-a", "citi-b"])  # no cache given: state alone

    def test_retry_picks_up_failures(self):
        self.assertEqual(self.ids(state=self.STATE, retry=True), ["chase-b", "citi-b"])

    def test_missing_and_retry_together(self):
        self.assertEqual(self.ids(state=self.STATE, missing=True, retry=True), ["chase-b", "citi-a", "citi-b"])

    def test_a_card_whose_page_moved_is_refetched(self):
        # citi-b was fetched from /b but the seed now says /new-b.
        self.assertIn("citi-b", self.ids(state=self.STATE, retry=True))

    def select_calendar_card(self, entry: dict, **kwargs) -> list[str]:
        card = {"id": "d", "issuer": "Discover", "sourceUrl": "https://x.test/d", "calendarUrl": CALENDAR_URL}
        state = {"d": {"url": "https://x.test/d", "lastStatus": "ok", **entry}}
        return [c["id"] for c in fetch.select([card], [], "", None, state, **kwargs)]

    def test_a_card_whose_calendar_page_was_never_read_is_picked_up(self):
        self.assertEqual(self.select_calendar_card({}, missing=True), ["d"])
        self.assertEqual(self.select_calendar_card({"calendarUrl": "https://x.test/old"}, retry=True), ["d"])

    def test_a_card_whose_calendar_page_failed_is_retried(self):
        read = {"calendarUrl": CALENDAR_URL, "calendarStatus": "ok"}
        self.assertEqual(self.select_calendar_card(read, retry=True), [])
        self.assertEqual(self.select_calendar_card({**read, "calendarStatus": "failed"}, retry=True), ["d"])

    def test_missing_picks_up_a_card_whose_calendar_text_is_not_saved(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            (cache / "d").mkdir()
            (cache / "d" / "latest.txt").write_text("saved")
            read = {"hash": "h", "calendarUrl": CALENDAR_URL, "calendarHash": "c", "calendarStatus": "ok"}
            self.assertEqual(self.select_calendar_card(read, missing=True, cache=cache), ["d"])
            (cache / "d" / "calendar.txt").write_text("saved")
            self.assertEqual(self.select_calendar_card(read, missing=True, cache=cache), [])


if __name__ == "__main__":
    unittest.main()
