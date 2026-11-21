"""Offline tests for publish.py: python3 -m unittest discover -s tools/rewards-catalog"""

import json
import re
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import extract
import fetch
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
    return extract.candidate_rule(dict(PROPOSAL, **changes), URL, "hash-1", "page")


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
            "categories": ["dining"], "selection": "fixed", "rate": 3, "unit": "percent",  # what's null, false or empty is left out
            "evidence": {"quote": "Earn unlimited 3% cash back on dining.", "url": URL},  # no page hash, no "verified"
        }])

    def test_a_rule_a_person_added_is_published_even_for_a_card_with_no_candidate(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "decisions.json"
            review.add_rule(SAVOR, None, {"categories": ["dining"], "rate": 3, "unit": "percent", "quote": "Earn 3% on dining."}, None,
                            False, path, "2026-11-14")
            doc = publish.catalog([SAVOR], {}, review.load_decisions(path), None, "2026-11-15")
        (card,) = doc["cards"]
        self.assertEqual((card["verifiedAt"], [r["categories"] for r in card["rules"]]), ("2026-11-14", [["dining"]]))

    def test_a_fixed_rule_is_published_as_fixed_with_the_day_it_was_accepted(self):
        cand = candidate(self.dining)
        key = review.rule_key("bank-savor", self.dining)
        edited = {**self.dining, "rate": 4}
        decisions = {"bank-savor": {key: {"decision": "accept", "decidedAt": "2026-11-03", "edited": edited}}}
        (card,) = publish.catalog([SAVOR], {"bank-savor": cand}, decisions, None, "2026-11-15")["cards"]
        self.assertEqual(([r["rate"] for r in card["rules"]], card["verifiedAt"]), ([4], "2026-11-03"))

    def test_an_accepted_quarter_stays_published_when_its_calendar_rewords_it_as_it_begins(self):
        def quarter(said: str) -> dict:
            made = extract.candidate_rule({**PROPOSAL, "categories": ["dining"], "selection": "rotating", "rate": 5, "validFrom": "2027-01-01",
                                           "validTo": "2027-03-31", "quote": said}, URL, "hash-1", "calendar")
            return {**made, "merchants": []}

        before = candidate(quarter("Earn 5% Cashback Bonus at Restaurants, January 1 to March 31, 2027, on up to $1,500 in purchases."))
        after = candidate(quarter("Earn 5% Cashback Bonus at Restaurants, now to March 31, 2027, on up to $1,500 in purchases when you activate."))
        doc = publish.catalog([SAVOR], {"bank-savor": after}, decided(before, (0, "accept", "2026-12-20")), None, "2027-01-02")
        self.assertIn("now to March 31", doc["cards"][0]["rules"][0]["evidence"]["quote"])

    def test_a_card_carries_its_seed_facts_its_card_wide_conditions_and_the_day_its_last_rule_was_accepted(self):
        cand = candidate(self.dining, self.base, card_conditions=["Digital wallets may not earn the higher rate."])
        decisions = decided(cand, (0, "accept", "2026-10-30"), (1, "accept", "2026-11-01"))
        (card,) = publish.catalog([SAVOR], {"bank-savor": cand}, decisions, None, "2026-11-02")["cards"]
        self.assertEqual({k: v for k, v in card.items() if k != "rules"}, {
            "id": "bank-savor", "name": "Savor", "issuer": "Capital One", "network": "Mastercard", "isBusiness": False,
            "annualFee": 0, "rewardKind": "cashback", "rewardProgram": None, "baseEarnRate": 1, "discontinued": False,
            "sourceUrl": URL, "verifiedAt": "2026-11-01",
            "cardConditions": ["Digital wallets may not earn the higher rate."], "bonusesStack": False,
        })  # sourceHost is the URL's, and every published card is verified, so neither is written

    def test_a_card_whose_bonuses_add_up_says_so(self):
        cand = candidate(self.dining, self.base)
        decisions = decided(cand, (0, "accept", "2026-11-01"))
        options = {"bank-savor": {"bonusesStack": True, "setAt": "2026-11-01"}}
        (card,) = publish.catalog([SAVOR], {"bank-savor": cand}, decisions, None, "2026-11-02", options)["cards"]
        self.assertIs(card["bonusesStack"], True)

    def test_a_calendar_rule_carries_its_quarter_and_the_merchants_it_names(self):
        quarter = dict(rule(categories=[], selection="rotating", rate=5, quote="5% in rotating bonus categories each quarter."),
                       categories=["groceries", "dining"], validFrom="2026-10-01", validTo="2026-12-31",
                       merchants=["American Red Cross®"], verified="calendar")
        cand = candidate(quarter)
        (card,) = publish.catalog([SAVOR], {"bank-savor": cand}, decided(cand, (0, "accept", "2026-11-01")), None, "2026-11-02")["cards"]
        (published,) = card["rules"]
        self.assertEqual((published["categories"], published["validFrom"], published["validTo"], published["merchants"]),
                         (["dining", "groceries"], "2026-10-01", "2026-12-31", ["American Red Cross®"]))

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
            texts.append(fetch.json_text(publish.catalog(cards, both, decisions, None, "2026-11-01")))
        self.assertEqual(texts[0], texts[1])
        self.assertIn('"rate": 3,', texts[0])  # not 3.0
        self.assertLess(texts[0].index('"bank-quicksilver"'), texts[0].index('"bank-savor"'))

    def test_a_card_whose_candidate_is_missing_keeps_what_was_published(self):
        cand = candidate(self.dining)
        first = publish.catalog([SAVOR], {"bank-savor": cand}, decided(cand, (0, "accept", "2026-11-01")), None, "2026-11-01")
        self.assertEqual(publish.catalog([SAVOR], {}, {}, first, "2026-12-01"), first)  # a fresh clone has no cache/
        self.assertEqual(publish.catalog([], {}, {}, first, "2026-12-01")["cards"], [])  # but a card gone from the seed goes


    def published_first(self):
        cand = candidate(self.dining, self.base)
        decisions = decided(cand, (0, "accept", "2026-11-01"), (1, "accept", "2026-11-01"))
        return publish.catalog([SAVOR], {"bank-savor": cand}, decisions, None, "2026-11-01"), decisions

    def test_a_published_card_whose_new_candidate_failed_keeps_what_was_published_and_is_reported(self):
        first, decisions = self.published_first()
        for status in ("failed", "wrong-page"):
            failed = dict(candidate(), status=status)  # no rules: the page redirected, or the fetch or model failed
            kept = []
            doc = publish.catalog([SAVOR], {"bank-savor": failed}, decisions, first, "2026-12-01", kept=kept)
            self.assertEqual(doc, first, status)
            self.assertEqual([(k["id"], k["status"], len(k["lost"])) for k in kept], [("bank-savor", status, 2)])

    def test_a_published_card_whose_rule_was_reworded_keeps_its_old_entry_until_the_new_wording_is_accepted(self):
        first, decisions = self.published_first()
        reworded = candidate(rule(quote="Earn unlimited 3% cash back on dining, including delivery."), self.base)
        kept = []
        doc = publish.catalog([SAVOR], {"bank-savor": reworded}, decisions, first, "2026-12-01", kept=kept)
        self.assertEqual((doc, [len(k["lost"]) for k in kept]), (first, [1]))  # the new wording waits for review: nothing shrinks
        decisions = {**decisions, **decided(reworded, (0, "accept", "2026-12-01"), (1, "accept", "2026-11-01"))}
        kept = []
        doc = publish.catalog([SAVOR], {"bank-savor": reworded}, decisions, first, "2026-12-01", kept=kept)
        self.assertEqual(kept, [])
        self.assertEqual({r["evidence"]["quote"] for r in doc["cards"][0]["rules"]},
                         {"Earn unlimited 3% cash back on dining, including delivery.", "1% on all other purchases."})

    def test_rejecting_a_published_rule_on_purpose_drops_it_without_holding_the_card_back(self):
        first, _ = self.published_first()
        cand = candidate(self.dining, self.base)
        kept = []
        doc = publish.catalog([SAVOR], {"bank-savor": cand},
                              decided(cand, (0, "accept", "2026-11-01"), (1, "reject", "2026-12-01")), first, "2026-12-01", kept=kept)
        self.assertEqual((kept, [r["categories"] for r in doc["cards"][0]["rules"]]), ([], [["dining"]]))

    def test_a_card_with_no_candidate_keeps_its_old_entry_even_when_a_person_added_a_rule_since(self):
        first, decisions = self.published_first()
        extra = rule(categories=["gas"], quote="3% on gas.")
        added = {"bank-savor": {**decisions["bank-savor"], review.rule_key("bank-savor", extra): {
            "decision": "accept", "decidedAt": "2026-12-01", "added": extra}}}
        kept = []
        self.assertEqual(publish.catalog([SAVOR], {}, added, first, "2026-12-01", kept=kept), first)  # no cache/: the extracted rules aren't here to publish beside it
        self.assertEqual(kept, [])  # a fresh clone has no candidates, and saying so for every card would only be noise

    def test_a_card_never_published_is_not_held_back_by_a_failed_candidate(self):
        kept = []
        self.assertEqual(publish.catalog([SAVOR], {"bank-savor": dict(candidate(), status="failed")}, {}, None, "2026-12-01", kept=kept)["cards"], [])
        self.assertEqual(kept, [])

    def test_the_held_back_cards_are_said_in_a_line_each(self):
        first, decisions = self.published_first()
        kept = []
        publish.catalog([SAVOR], {"bank-savor": dict(candidate(), status="wrong-page")}, decisions, first, "2026-12-01", kept=kept)
        self.assertIn("Kept bank-savor as published (wrong-page)", publish.held_back(kept))
        self.assertEqual(publish.held_back([]), "")


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
        paths = SimpleNamespace(seed=seed, candidates=candidates, decisions=decisions, options=root / "options.json", catalog=out)
        written = publish.publish(paths, today="2026-11-01")
        text = out.read_text(encoding="utf-8")
        self.assertEqual((json.loads(text), [r["evidence"]["quote"] for r in written["cards"][0]["rules"]]),
                         (written, ["Earn unlimited 3% cash back on dining."]))
        publish.publish(paths, today="2026-12-01")
        self.assertEqual(out.read_text(encoding="utf-8"), text)



class AppShapeTests(unittest.TestCase):
    def test_a_published_rule_has_the_fields_of_the_apps_catalog_rule(self):
        swift = (Path(__file__).resolve().parents[3] / "Grosh" / "Domain" / "Rewards" / "RewardsCatalog.swift").read_text(encoding="utf-8")
        body = re.search(r"struct CatalogRule: .*?\n}\n", swift, re.S).group(0)
        stored = re.findall(r"^    var (\w+):", body, re.M)  # the rule's own fields (Evidence's are indented further)
        self.assertEqual(sorted(stored), sorted([*publish.RULE_FIELDS, "evidence"]),
                         "publish.RULE_FIELDS and CatalogRule in RewardsCatalog.swift must list the same fields")


class LeftOutTests(unittest.TestCase):
    def test_a_field_that_is_null_false_or_empty_is_left_out_and_one_that_has_a_value_stays(self):
        capped = publish.published_rule(rule(categories=["gas"], capAmount=1500.0, capPeriod="quarter", requires=["activation"],
                                             conditions=["Not at superstores."], firstMonths=12, hasOtherChoices=True))
        self.assertEqual({k: v for k, v in capped.items() if k != "evidence"}, {
            "categories": ["gas"], "selection": "fixed", "hasOtherChoices": True, "rate": 3, "unit": "percent", "capAmount": 1500,
            "capPeriod": "quarter", "requires": ["activation"], "firstMonths": 12, "needs": ["account-opened"],
            "conditions": ["Not at superstores."]})

    def test_a_rule_always_says_what_it_covers_at_which_rate_and_a_rate_of_zero_is_a_value(self):
        zero = publish.published_rule(dict(rule(), rate=0, categories=[]))
        self.assertEqual({k: zero[k] for k in ("categories", "selection", "rate", "unit")},
                         {"categories": [], "selection": "fixed", "rate": 0, "unit": "percent"})

    def test_a_catalog_published_before_fields_were_left_out_is_compared_by_what_it_says(self):
        cand = candidate(rule(), rule(categories=["everything-else"], rate=1, quote="1% on all other purchases."))
        decisions = decided(cand, (0, "accept", "2026-11-01"), (1, "accept", "2026-11-01"))
        first = publish.catalog([SAVOR], {"bank-savor": cand}, decisions, None, "2026-11-01")
        old = json.loads(json.dumps(first))
        for r in old["cards"][0]["rules"]:  # as the file was before: every field written
            r.update({f: r.get(f) for f in publish.RULE_FIELDS} | {"hasOtherChoices": False, "capUnknown": False, "requires": [],
                                                                   "needs": [], "conditions": [], "merchants": []})
        kept = []
        self.assertEqual(publish.catalog([SAVOR], {"bank-savor": cand}, decisions, old, "2026-12-01", kept=kept), first | {"publishedAt": "2026-12-01"})
        self.assertEqual(kept, [])


class PaidWithTests(unittest.TestCase):
    def test_a_rule_says_how_it_is_paid_and_at_which_merchants(self):
        proposal = {"categories": [], "selection": "fixed", "picks": None, "hasOtherChoices": False, "rate": 3, "unit": "percent", "capAmount": None,
                    "capPeriod": None, "requires": [], "validFrom": None, "validTo": None, "conditions": [], "quote": "3% through PayPal at Target and Amazon.",
                    "paysWith": "PayPal", "merchants": ["Target", "Amazon"]}
        published = publish.published_rule(extract.candidate_rule(proposal, "u", "h", "page"))
        self.assertEqual((published["paysWith"], published["merchants"], published.get("needs", [])), ("PayPal", ["Amazon", "Target"], []))


if __name__ == "__main__":
    unittest.main()
