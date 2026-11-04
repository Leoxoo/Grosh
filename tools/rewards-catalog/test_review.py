"""Offline tests for review.py: python3 -m unittest discover -s tools/rewards-catalog"""

import copy
import json
import tempfile
import unittest
from pathlib import Path

import extract
import review

PROPOSAL = {
    "categories": ["dining"], "selection": "fixed", "picks": None, "hasOtherChoices": False, "rate": 3, "unit": "percent",
    "capAmount": None, "capPeriod": None, "requires": [], "validFrom": None, "validTo": None, "firstMonths": None,
    "conditions": [], "quote": "Earn unlimited 3% cash back on dining.",
}
URL = "https://x.test/savor"


def rule(**changes) -> dict:
    return extract.candidate_rule(dict(PROPOSAL, **changes), URL, "hash-1", "page")


def candidate(*rules, card_id: str = "bank-savor", warnings=()) -> dict:
    return {"cardId": card_id, "status": "ok", "rules": list(rules), "warnings": list(warnings), "cardConditions": []}


class ReviewCase(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / "review-decisions.json"
        self.dining, self.base = rule(), rule(categories=["everything-else"], rate=1, quote="1% on all other purchases.")

    def decide(self, cand: dict, index: int, decision: str) -> dict:
        return review.decide(cand, review.rule_key(cand["cardId"], cand["rules"][index]), decision, self.path, "2026-11-01")

    def accepted(self, cand: dict) -> list[dict]:
        return review.accepted_rules(cand, review.load_decisions(self.path))


class AcceptedRulesTests(ReviewCase):
    def test_only_rules_a_person_accepted_come_back(self):
        cand = candidate(self.dining, self.base)
        self.decide(cand, 0, "accept")
        self.assertEqual(self.accepted(cand), [self.dining])  # the base rate is still waiting, so it doesn't move on

    def test_a_rejected_rule_never_comes_back(self):
        cand = candidate(self.dining, self.base)
        self.decide(cand, 0, "accept")
        self.decide(cand, 1, "reject")
        self.assertEqual(self.accepted(cand), [self.dining])
        self.decide(cand, 0, "reject")  # a person can change their mind
        self.assertEqual(self.accepted(cand), [])

    def test_a_re_extraction_that_changes_the_rule_does_not_inherit_the_accept(self):
        self.decide(candidate(self.dining), 0, "accept")
        for changed in (rule(rate=4, quote="Earn unlimited 4% cash back on dining."), rule(capAmount=6000, capPeriod="year"),
                        rule(conditions=["Excluding superstores."]), rule(quote="Earn unlimited 3% cash back on dining!"),
                        rule(requires=["activation"]), rule(validTo="2026-12-31"),
                        extract.candidate_rule(PROPOSAL, "https://x.test/other-page", "hash-1", "page"),
                        extract.candidate_rule(PROPOSAL, URL, "hash-1", "manual")):
            self.assertEqual(self.accepted(candidate(changed)), [], changed)

    def test_the_same_rule_from_a_page_that_churned_keeps_its_decision(self):
        self.decide(candidate(self.dining), 0, "accept")
        again = copy.deepcopy(self.dining)
        again["evidence"]["pageHash"], again["rate"] = "hash-2", 3.0  # the page's menus changed; the model said 3.0
        self.assertEqual(self.accepted(candidate(again)), [again])

    def test_the_same_rule_listed_in_another_order_keeps_its_decision(self):
        first = rule(selection="choose", picks=1, categories=["gas", "dining"], conditions=["Not at superstores.", "Not online."])
        self.decide(candidate(first), 0, "accept")
        again = rule(selection="choose", picks=1, categories=["dining", "gas"], conditions=["Not online.", "Not at superstores."])
        self.assertEqual(self.accepted(candidate(again)), [again])

    def test_a_decision_belongs_to_one_card(self):
        self.decide(candidate(self.dining), 0, "accept")
        self.assertEqual(self.accepted(candidate(self.dining, card_id="bank-savor-one")), [])  # two cards sharing a page


class DecideTests(ReviewCase):
    def test_the_saved_file_says_what_was_decided_in_words(self):
        self.decide(candidate(self.dining), 0, "accept")
        saved = json.loads(self.path.read_text())
        key = review.rule_key("bank-savor", self.dining)
        self.assertEqual(saved, {"bank-savor": {key: {"decision": "accept", "decidedAt": "2026-11-01",
                                                      "rule": "3% on dining", "quote": "Earn unlimited 3% cash back on dining."}}})

    def test_undoing_a_decision_puts_the_rule_back_in_the_queue(self):
        cand = candidate(self.dining)
        self.decide(cand, 0, "accept")
        self.decide(cand, 0, "undo")
        self.assertEqual((self.accepted(cand), review.load_decisions(self.path)), ([], {}))

    def test_nonsense_is_refused(self):
        cand = candidate(self.dining)
        with self.assertRaisesRegex(ValueError, "accept, reject or undo"):
            self.decide(cand, 0, "maybe")
        with self.assertRaisesRegex(ValueError, "no longer"):  # the page was re-extracted since it was shown
            review.decide(cand, "0123456789abcdef", "accept", self.path, "2026-11-01")
        self.assertFalse(self.path.exists())


class CardReviewTests(ReviewCase):
    def test_each_rule_shows_its_quote_source_warnings_and_decision(self):
        capped = rule(capUnknown=True, quote="Earn unlimited 3% cash back on dining, up to a cap.")
        cand = candidate(self.dining, capped, warnings=["dining earns 3 and 4 with nothing to tell them apart"])
        self.decide(cand, 0, "reject")
        view = review.card_review(cand, review.load_decisions(self.path))
        first, second = view["rules"]
        self.assertEqual((first["key"], first["decision"], first["quote"], first["url"], first["warnings"]),
                         (review.rule_key("bank-savor", self.dining), "reject", "Earn unlimited 3% cash back on dining.", URL, []))
        self.assertEqual((second["decision"], second["warnings"]),
                         (None, ["the page says there is a cap but doesn't state the amount"]))
        self.assertEqual(first["rule"], self.dining)
        self.assertEqual(view["warnings"], ["dining earns 3 and 4 with nothing to tell them apart"])  # the card's, shown with its rules
        self.assertEqual(view["counts"], {"waiting": 1, "accept": 0, "reject": 1})

    def test_a_rule_in_words_says_who_picks_how_many_and_its_cap(self):
        choice = rule(categories=["gas", "online-shopping"], selection="choose", picks=1, hasOtherChoices=True,
                      capAmount=2500, capPeriod="quarter")
        self.assertEqual(review.describe(choice),
                         "3% in the category the cardholder chooses: gas, online shopping (and others), up to $2,500 per quarter")
        self.assertEqual(review.describe(rule(unit="per-dollar", rate=1.5, categories=["everything-else"])), "1.5x on everything else")

    def test_the_review_totals_every_cards_counts(self):
        one, two = (review.card_review(candidate(self.dining, card_id=i), {}) for i in ("a", "b"))
        self.assertEqual(review.summarize([one, two]), {"cards": 2, "waiting": 2, "accept": 0, "reject": 0})

    def test_hand_entered_rules_wait_for_review_too_and_say_when_the_page_did_not_confirm_them(self):
        card = {"id": "bank-savor", "name": "Savor", "sourceUrl": URL}
        entry = {"rules": [PROPOSAL, dict(PROPOSAL, categories=["everything-else"], rate=1, quote="1% on all other purchases.")]}
        cand = extract.manual_candidate(card, entry, "Savor\nEarn unlimited 3% cash back on dining.\n", "hash-1")
        view = review.card_review(cand, {})
        self.assertEqual([(r["decision"], r["warnings"]) for r in view["rules"]],
                         [(None, []), (None, ["hand-entered, and the saved page doesn't confirm the quote: check it on the page"])])
        self.assertEqual(self.accepted(cand), [])  # hand-entered isn't the same as accepted



class EditTests(ReviewCase):
    PAGE = "Earn unlimited 3% cash back on dining and takeout, up to $6,000 per year. 1% on all other purchases."

    def edit(self, cand: dict, index: int, changes: dict, page: str | None = PAGE) -> dict:
        key = review.rule_key(cand["cardId"], cand["rules"][index])
        return review.edit(cand, key, changes, page, self.path, "2026-11-02")

    def test_an_edit_is_accepted_and_replaces_the_rule_in_the_catalog(self):
        wrong = rule(quote="Earn unlimited 3% cash back on dining and takeout, up to $6,000 per year.")
        cand = candidate(wrong)
        self.edit(cand, 0, {"capAmount": 6000, "capPeriod": "year"})
        [published] = self.accepted(cand)
        self.assertEqual((published["capAmount"], published["capPeriod"], published["verified"]), (6000, "year", "page"))
        row = review.card_review(cand, review.load_decisions(self.path))["rules"][0]
        self.assertEqual((row["decision"], row["edited"], row["rule"]["capAmount"], row["original"]["capAmount"]), ("accept", True, 6000, None))

    def test_an_edit_the_quote_does_not_back_is_refused_and_nothing_is_saved(self):
        cand = candidate(rule(quote="Earn unlimited 3% cash back on dining and takeout, up to $6,000 per year."))
        with self.assertRaises(ValueError) as refused:
            self.edit(cand, 0, {"categories": ["groceries"]})
        self.assertIn("groceries", str(refused.exception))
        with self.assertRaises(ValueError):
            self.edit(cand, 0, {"quote": "anything"})  # the quote is the evidence: never edited
        self.assertEqual(review.load_decisions(self.path), {})

    def test_accepting_or_undoing_drops_the_edit(self):
        wrong = rule(quote="Earn unlimited 3% cash back on dining and takeout, up to $6,000 per year.")
        cand = candidate(wrong)
        self.edit(cand, 0, {"capAmount": 6000, "capPeriod": "year"})
        self.assertEqual(self.accepted(cand)[0]["capAmount"], 6000)
        self.decide(cand, 0, "accept")
        self.assertEqual(self.accepted(cand), [wrong])



def calendar_rule() -> dict:
    """A quarter read from the page's calendar (extract.calendar_rules)."""
    quarter = rule(categories=[], selection="rotating", rate=5, quote="Earn 5% in rotating bonus categories each quarter.",
                   capAmount=1500, capPeriod="quarter")
    return dict(quarter, categories=["groceries", "dining"], merchants=["American Red Cross®"], validFrom="2026-10-01",
                validTo="2026-12-31", verified="calendar", evidence=dict(quarter["evidence"], quote="OCT-DEC\n2026\nGrocery Stores"))


class CalendarRuleTests(ReviewCase):
    def test_a_quarter_in_words_says_its_dates_categories_and_merchants(self):
        self.assertEqual(review.describe(calendar_rule()),
                         "5% in rotating bonus categories from 2026-10-01 to 2026-12-31: groceries, dining "
                         "(also at American Red Cross®), up to $1,500 per quarter")

    def test_it_says_where_it_came_from_and_cannot_be_fixed(self):
        cand = candidate(calendar_rule())
        (row,) = review.card_review(cand, {})["rules"]
        self.assertTrue(any("quarterly calendar" in w for w in row["warnings"]))
        with self.assertRaisesRegex(ValueError, "quarterly calendar"):
            review.edit(cand, row["key"], {"rate": 4}, None, self.path, "2026-11-01")
        self.assertFalse(self.path.exists())


class CardOptionTests(ReviewCase):
    def test_turning_stacking_on_and_off_saves_only_what_is_on(self):
        path = self.path.with_name("card-options.json")
        self.assertEqual(review.set_option("bank-savor", "bonusesStack", True, path, "2026-11-02"),
                         {"bank-savor": {"bonusesStack": True, "setAt": "2026-11-02"}})
        self.assertEqual(review.load_options(path), {"bank-savor": {"bonusesStack": True, "setAt": "2026-11-02"}})
        self.assertEqual(review.set_option("bank-savor", "bonusesStack", False, path, "2026-11-03"), {})

    def test_an_unknown_option_or_value_is_refused(self):
        path = self.path.with_name("card-options.json")
        for name, value in (("autoPilot", True), ("bonusesStack", "yes")):
            with self.assertRaises(ValueError):
                review.set_option("bank-savor", name, value, path)
        self.assertFalse(path.exists())


def quarter_rule(quote: str = "Earn 5% Cashback Bonus at Restaurants, January 1 to March 31, 2027, on up to $1,500 in purchases.", **changes) -> dict:
    """A rule read from a calendar, as extract.calendar_rules makes it."""
    made = extract.candidate_rule({**PROPOSAL, "categories": ["dining"], "selection": "rotating", "rate": 5, "validFrom": "2027-01-01",
                                   "validTo": "2027-03-31", "quote": quote}, URL, "hash-1", "calendar")
    return {**made, "merchants": [], **changes}


class RuleKeyTests(unittest.TestCase):
    def key(self, rule_: dict) -> str:
        return review.rule_key("bank-savor", rule_)

    def test_a_quarter_keeps_its_key_when_its_calendar_rewords_it(self):
        reworded = quarter_rule("Earn 5% Cashback Bonus at Restaurants, now to March 31, 2027, on up to $1,500 in purchases when you activate.")
        self.assertEqual(self.key(reworded), self.key(quarter_rule()))

    def test_a_quarter_gets_a_new_key_when_what_it_says_changes(self):
        for changes in ({"validFrom": "2027-04-01"}, {"validTo": "2027-06-30"}, {"rate": 3}, {"categories": ["gas"]}, {"merchants": ["Amazon"]}):
            self.assertNotEqual(self.key(quarter_rule(**changes)), self.key(quarter_rule()), changes)

    def test_other_rules_keep_the_keys_they_have_always_had(self):
        self.assertEqual(self.key(rule()), "65d69ab1e23eefef")  # worked out before quarter rules changed: decisions are saved under these
        dated = rule(categories=[], selection="rotating", rate=5, validFrom="2026-01-01", validTo="2026-03-31")
        self.assertEqual(self.key(dated), "7d299cb843cd417c")

    def test_a_rule_read_from_a_page_still_changes_key_with_its_quote(self):
        self.assertNotEqual(self.key(rule(quote="Earn 3% cash back on dining.")), self.key(rule()))


class QuarterStatusTests(ReviewCase):
    def setUp(self) -> None:
        super().setUp()
        self.next_quarter = rule(categories=["groceries"], selection="rotating", rate=5, validFrom="2027-01-01", validTo="2027-03-31")

    def test_a_quarter_rule_nobody_has_decided_on_is_waiting(self):
        status = review.quarter_status(candidate(self.dining, self.next_quarter), "", {}, "2026-12-24")
        self.assertEqual(status["waiting"], ["5% in rotating bonus categories from 2027-01-01 to 2027-03-31: groceries"])

    def test_a_decided_quarter_is_not_waiting_and_an_undated_rotating_rule_is_no_quarter(self):
        undated = rule(categories=[], selection="rotating", rate=5)
        cand = candidate(undated, self.next_quarter)
        self.decide(cand, 1, "accept")
        status = review.quarter_status(cand, "", review.load_decisions(self.path), "2026-12-24")
        self.assertEqual((status["waiting"], status["decided"], status["rotating"]), ([], 1, True))

    def test_a_quarter_that_has_ended_no_longer_waits(self):
        status = review.quarter_status(candidate(self.next_quarter), "", {}, "2027-04-01")
        self.assertEqual((status["waiting"], status["decided"]), ([], 0))

    def test_a_quarter_marked_coming_soon_on_the_page_is_said_unless_it_has_ended(self):
        page = "JAN-MAR\n2027\nComing Soon\nAPR-JUN\n2027\nComing Soon"
        status = review.quarter_status(candidate(self.dining), page, {}, "2027-04-01")
        self.assertEqual(status["comingSoon"], [{"start": "2027-04-01", "end": "2027-06-30"}])

    def test_a_candidate_that_lost_its_rotating_rule_says_so(self):
        self.assertFalse(review.quarter_status(candidate(self.dining), "", {}, "2026-12-24")["rotating"])



if __name__ == "__main__":
    unittest.main()
