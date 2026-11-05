"""Offline tests for build_seed.py: python3 -m unittest discover -s tools/rewards-catalog"""

import json
import unittest

import build_seed

ROW = {
    "cardId": "abc", "name": "Savor", "issuer": "CAPITAL_ONE", "network": "MASTERCARD", "currency": "USD",
    "isBusiness": "false", "annualFee": "0", "universalCashbackPercent": "1", "url": "https://x.test/savor",
    "discontinued": "false",
}
EXTRA = {
    "name": "Apple Card", "issuer": "Goldman Sachs", "network": "Mastercard", "isBusiness": False, "annualFee": 0,
    "rewardKind": "cashback", "rewardProgram": None, "baseEarnRate": 1, "sourceUrl": "https://www.apple.com/apple-card/",
}


class BuildTests(unittest.TestCase):
    def test_extra_cards_join_the_seed_in_the_same_shape(self):
        catalog = build_seed.build([ROW], extra_cards=[EXTRA])
        self.assertEqual([c["id"] for c in catalog], ["capital-one-savor", "goldman-sachs-apple-card"])
        apple = catalog[1]
        self.assertEqual(set(apple), set(catalog[0]))
        self.assertEqual((apple["sourceHost"], apple["verified"], apple["discontinued"]), ("www.apple.com", False, False))

    def test_an_extra_card_cannot_take_another_cards_id(self):
        clash = {**EXTRA, "issuer": "Capital One", "name": "Savor"}
        with self.assertRaises(SystemExit) as stopped:
            build_seed.build([ROW], extra_cards=[clash])
        self.assertIn("share an id", str(stopped.exception))

    def test_an_extra_card_must_say_everything_the_seed_needs(self):
        with self.assertRaises(SystemExit) as stopped:
            build_seed.build([ROW], extra_cards=[{"name": "Half a card"}])
        self.assertIn("missing", str(stopped.exception))
        with self.assertRaises(SystemExit) as stopped:
            build_seed.build([ROW], extra_cards=[{**EXTRA, "rewardKind": "bitcoin"}])
        self.assertIn("rewardKind", str(stopped.exception))

    def test_url_overrides_reach_extra_cards_too_and_unknown_ids_stop_the_build(self):
        catalog = build_seed.build([ROW], {"goldman-sachs-apple-card": "https://x.test/new"}, [EXTRA])
        self.assertEqual(catalog[1]["sourceUrl"], "https://x.test/new")
        with self.assertRaises(SystemExit):
            build_seed.build([ROW], {"no-such-card": "https://x.test"})

    def test_removed_cards_leave_the_seed_and_unknown_ids_stop_the_build(self):
        catalog = build_seed.build([ROW], extra_cards=[EXTRA], removed_cards={"goldman-sachs-apple-card": "why"})
        self.assertEqual([c["id"] for c in catalog], ["capital-one-savor"])
        with self.assertRaises(SystemExit) as stopped:
            build_seed.build([ROW], removed_cards={"no-such-card": "why"})
        self.assertIn("removed-cards.json", str(stopped.exception))

    def test_a_card_waiting_on_a_decision_is_marked_needs_info_and_unknown_ids_stop_the_build(self):
        catalog = build_seed.build([ROW], extra_cards=[EXTRA], needs_info={"capital-one-savor": "Is it discontinued?"})
        self.assertEqual([c.get("needsInfo") for c in catalog], ["Is it discontinued?", None])
        with self.assertRaises(SystemExit) as stopped:
            build_seed.build([ROW], needs_info={"no-such-card": "why"})
        self.assertIn("needs-info.json", str(stopped.exception))

    def test_a_card_can_name_a_calendar_page_and_unknown_ids_stop_the_build(self):
        catalog = build_seed.build([ROW], extra_cards=[EXTRA], calendar_pages={"capital-one-savor": "https://x.test/calendar"})
        self.assertEqual([c.get("calendarUrl") for c in catalog], ["https://x.test/calendar", None])
        self.assertNotIn("calendarUrl", catalog[1])  # a card with no calendar page is the card it always was
        with self.assertRaises(SystemExit) as stopped:
            build_seed.build([ROW], calendar_pages={"no-such-card": "https://x.test/calendar"})
        self.assertIn("calendar-pages.json", str(stopped.exception))

    def test_the_committed_seed_carries_every_calendar_page(self):
        pages = json.loads(build_seed.CALENDAR_PAGES.read_text(encoding="utf-8"))
        seed = json.loads(build_seed.OUT.read_text(encoding="utf-8"))["cards"]
        self.assertEqual({c["id"]: c["calendarUrl"] for c in seed if c.get("calendarUrl")}, pages)
        self.assertIn("discover-discover-it", pages)

    def test_the_committed_seed_carries_every_needs_info_mark(self):
        marks = json.loads(build_seed.NEEDS_INFO.read_text(encoding="utf-8"))
        seed = json.loads(build_seed.OUT.read_text(encoding="utf-8"))["cards"]
        self.assertEqual({c["id"]: c["needsInfo"] for c in seed if c.get("needsInfo")}, marks)
        self.assertLessEqual({"barclays-carnival-world-mastercard", "american-express-green"}, set(marks))


if __name__ == "__main__":
    unittest.main()
