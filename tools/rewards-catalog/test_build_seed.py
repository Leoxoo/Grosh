"""Offline tests for build_seed.py: python3 -m unittest discover -s tools/rewards-catalog"""

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


if __name__ == "__main__":
    unittest.main()
