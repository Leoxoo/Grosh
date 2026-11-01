"""Offline tests for publish.py: python3 -m unittest discover -s tools/rewards-catalog"""

import json
import tempfile
import unittest
from pathlib import Path

import extract
import publish
import review

PROPOSAL = {
    "categories": ["dining"], "selection": "fixed", "picks": None, "hasOtherChoices": False, "rate": 3, "unit": "percent",
    "capAmount": None, "capPeriod": None, "requires": [], "validFrom": None, "validTo": None, "firstMonths": None,
    "conditions": [], "quote": "Earn unlimited 3% cash back on dining.",
}
URL = "https://x.test/savor"
SAVOR = {
    "id": "bank-savor", "name": "Savor", "issuer": "Capital One", "network": "Mastercard", "isBusiness": False,
    "annualFee": 0, "rewardKind": "cashback", "rewardProgram": None, "baseEarnRate": 1, "discontinued": False,
    "sourceUrl": URL, "sourceHost": "x.test", "verified": False,
}


def rule(**changes) -> dict:
    return extract.accepted_rule(dict(PROPOSAL, **changes), URL, "hash-1", "page")


def candidate(*rules, card_id: str = "bank-savor", card_conditions=()) -> dict:
    return {"cardId": card_id, "status": "ok", "model": "m", "promptVersion": "9", "pageHash": "hash-1", "needs": [],
            "warnings": ["a warning"], "cardConditions": list(card_conditions), "rules": list(rules), "rejected": [{"x": 1}]}


def decided(cand: dict, *pairs) -> dict:
    """Decisions as review.decide saves them: (rule index, decision, date) per rule."""
    return {cand["cardId"]: {review.rule_key(cand["cardId"], cand["rules"][i]): {"decision": d, "decidedAt": day}
                             for i, d, day in pairs}}


class CatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dining, self.base = rule(), rule(categories=["everything-else"], rate=1, quote="1% on all other purchases.")

    def test_only_accepted_rules_are_written_each_with_its_quote_and_source(self):
        cand = candidate(self.dining, self.base, rule(categories=["gas"], quote="3% on gas."))
        decisions = decided(cand, (0, "accept", "2026-11-01"), (1, "reject", "2026-11-01"))  # gas is still waiting
        doc = publish.catalog([SAVOR], {"bank-savor": cand}, decisions, None, "2026-11-02")
        (card,) = doc["cards"]
        self.assertEqual(card["rules"], [{
            "categories": ["dining"], "selection": "fixed", "picks": None, "hasOtherChoices": False, "rate": 3,
            "unit": "percent", "capAmount": None, "capPeriod": None, "capUnknown": False, "requires": [],
            "validFrom": None, "validTo": None, "firstMonths": None, "tier": None, "needs": [], "conditions": [],
            "evidence": {"quote": "Earn unlimited 3% cash back on dining.", "url": URL},  # no page hash, no "verified"
        }])

    def test_a_card_carries_its_seed_facts_its_card_wide_conditions_and_the_day_its_last_rule_was_accepted(self):
        cand = candidate(self.dining, self.base, card_conditions=["Digital wallets may not earn the higher rate."])
        decisions = decided(cand, (0, "accept", "2026-10-30"), (1, "accept", "2026-11-01"))
        (card,) = publish.catalog([SAVOR], {"bank-savor": cand}, decisions, None, "2026-11-02")["cards"]
        self.assertEqual({k: v for k, v in card.items() if k != "rules"}, {
            "id": "bank-savor", "name": "Savor", "issuer": "Capital One", "network": "Mastercard", "isBusiness": False,
            "annualFee": 0, "rewardKind": "cashback", "rewardProgram": None, "baseEarnRate": 1, "discontinued": False,
            "sourceUrl": URL, "verifiedAt": "2026-11-01",
            "cardConditions": ["Digital wallets may not earn the higher rate."],
        })  # sourceHost is the URL's, and every published card is verified, so neither is written

    def test_a_card_no_person_accepted_a_rule_on_is_left_out(self):
        other = dict(SAVOR, id="bank-quicksilver", name="Quicksilver")
        waiting, rejected = candidate(self.dining, card_id="bank-quicksilver"), candidate(self.dining)
        decisions = decided(rejected, (0, "reject", "2026-11-01"))
        doc = publish.catalog([SAVOR, other], {"bank-savor": rejected, "bank-quicksilver": waiting}, decisions, None, "2026-11-02")
        self.assertEqual(doc["cards"], [])
        self.assertEqual(publish.catalog([SAVOR], {}, {}, None, "2026-11-02")["cards"], [])  # no candidate at all

    def test_the_file_has_a_format_version_and_the_day_it_was_published(self):
        doc = publish.catalog([SAVOR], {}, {}, None, "2026-11-02")
        self.assertEqual(doc, {"formatVersion": 1, "publishedAt": "2026-11-02", "cards": []})

    def test_publishing_again_with_nothing_new_keeps_the_old_date_so_the_diff_is_empty(self):
        cand = candidate(self.dining, self.base)
        first = publish.catalog([SAVOR], {"bank-savor": cand}, decided(cand, (0, "accept", "2026-11-01")), None, "2026-11-01")
        again = publish.catalog([SAVOR], {"bank-savor": cand}, decided(cand, (0, "accept", "2026-11-01")), first, "2026-12-01")
        self.assertEqual(again, first)
        more = publish.catalog([SAVOR], {"bank-savor": cand},
                               decided(cand, (0, "accept", "2026-11-01"), (1, "accept", "2026-12-01")), first, "2026-12-01")
        self.assertEqual(more["publishedAt"], "2026-12-01")

    def test_the_same_rules_extracted_in_another_order_publish_the_same_bytes(self):
        choose = dict(categories=["gas", "dining"], selection="choose", picks=1, conditions=["Not online.", "Not at superstores."])
        one = candidate(rule(**choose), self.base, card_conditions=["B.", "A."])
        again = dict(choose, categories=["dining", "gas"], conditions=["Not at superstores.", "Not online."], rate=3.0)
        two = candidate(dict(self.base, rate=1.0), rule(**again), card_conditions=["A.", "B."])
        quick = dict(SAVOR, id="bank-quicksilver", name="Quicksilver")
        texts = []
        for cand, cards in ((one, [SAVOR, quick]), (two, [quick, SAVOR])):
            both = {"bank-savor": cand, "bank-quicksilver": dict(cand, cardId="bank-quicksilver")}
            decisions = {**decided(both["bank-savor"], (0, "accept", "2026-11-01"), (1, "accept", "2026-11-01")),
                         **decided(both["bank-quicksilver"], (0, "accept", "2026-11-01"), (1, "accept", "2026-11-01"))}
            texts.append(publish.dumps(publish.catalog(cards, both, decisions, None, "2026-11-01")))
        self.assertEqual(texts[0], texts[1])
        self.assertIn('"rate": 3,', texts[0])  # not 3.0
        self.assertLess(texts[0].index('"bank-quicksilver"'), texts[0].index('"bank-savor"'))

    def test_a_card_whose_candidate_is_missing_keeps_what_was_published(self):
        cand = candidate(self.dining)
        first = publish.catalog([SAVOR], {"bank-savor": cand}, decided(cand, (0, "accept", "2026-11-01")), None, "2026-11-01")
        self.assertEqual(publish.catalog([SAVOR], {}, {}, first, "2026-12-01"), first)  # a fresh clone has no cache/
        self.assertEqual(publish.catalog([], {}, {}, first, "2026-12-01")["cards"], [])  # but a card gone from the seed goes



class PublishTests(unittest.TestCase):
    def test_it_writes_the_file_from_the_seed_the_candidates_and_the_decisions_and_a_rerun_changes_nothing(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        seed, candidates, decisions, out = root / "seed.json", root / "candidates", root / "decisions.json", root / "out.json"
        seed.write_text(json.dumps({"seededFrom": "test", "cards": [SAVOR]}))
        candidates.mkdir()
        cand = candidate(rule())
        (candidates / "bank-savor.json").write_text(json.dumps(cand))
        decisions.write_text(json.dumps(decided(cand, (0, "accept", "2026-11-01"))))
        paths = dict(seed=seed, candidates=candidates, decisions=decisions, out=out)
        written = publish.publish(**paths, today="2026-11-01")
        text = out.read_text(encoding="utf-8")
        self.assertEqual((json.loads(text), [r["evidence"]["quote"] for r in written["cards"][0]["rules"]]),
                         (written, ["Earn unlimited 3% cash back on dining."]))
        publish.publish(**paths, today="2026-12-01")
        self.assertEqual(out.read_text(encoding="utf-8"), text)


if __name__ == "__main__":
    unittest.main()
