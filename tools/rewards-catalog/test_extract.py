"""Offline tests for extract.py (no LM Studio needed): python3 -m unittest discover -s tools/rewards-catalog"""

import io
import json
import unittest
import urllib.error

import extract
from extract import extract_card, manual_candidate, normalize, validate_rule

CARD = {"id": "bank-savor", "name": "Savor Rewards", "issuer": "Bank", "rewardKind": "cashback", "sourceUrl": "https://x.test/savor"}
CHOICE = "Earn 3% cash back in the category of your choice: gas, online shopping, dining, travel, drug stores or home improvement."
TOP = "Earn 5% cash back on your top eligible spend category each billing cycle, from restaurants, gas stations and grocery stores."
ROTATING = "Earn 5% cash back on gas stations from October 1 through December 31, 2026. Activate each quarter."
APPLE = "Get 2% Daily Cash back when you use Apple Card with Apple Pay."
BOOKED = "Earn 5% cash back on hotels and rental cars booked through Bank Travel."
EXCLUSION = "Earn unlimited 3% cash back at grocery stores (excluding superstores like Walmart and Target), on dining."
FIRST_YEAR = "Earn 6% cash back in the category of your choice for the first year, then 3%."
WALLETS = "Purchases made through mobile or digital wallets may not receive a higher percentage reward."
GROCERY_QUOTE = "Earn 2X points on groceries at U.S. supermarkets on up to $6,000 per year in purchases."
PAGE = "\n".join([
    "Savor® Rewards Credit Card",
    "Earn unlimited 3% cash back on dining, entertainment and popular streaming services.",
    BOOKED,
    GROCERY_QUOTE,
    "Earn 1% cash back on all other purchases.",
    "Earn unlimited 3% cash back at grocery stores (excluding superstores like Walmart® and Target®), on dining.",
    APPLE, CHOICE, TOP, ROTATING, WALLETS, FIRST_YEAR,
    "Menu\nContact us\nPrivacy",
])
PAGE_NORM = normalize(PAGE)


def rule(**overrides) -> dict:
    base = {
        "categories": ["dining"], "selection": "fixed", "picks": None, "hasOtherChoices": False,
        "rate": 3, "unit": "percent", "capAmount": None, "capPeriod": None, "requires": [],
        "validFrom": None, "validTo": None, "firstMonths": None, "conditions": [],
        "quote": "Earn unlimited 3% cash back on dining, entertainment and popular streaming services.",
    }
    return {**base, **overrides}


def choice_rule(**overrides) -> dict:
    base = {"categories": ["gas", "online-shopping", "dining", "travel", "drugstores"], "selection": "choose",
            "picks": 1, "hasOtherChoices": True, "quote": CHOICE}
    return rule(**{**base, **overrides})


class ValidateRuleTests(unittest.TestCase):
    def check(self, **overrides) -> str | None:
        return validate_rule(rule(**overrides), PAGE_NORM)

    def test_accepts_a_rule_the_page_backs(self):
        self.assertIsNone(self.check())

    def test_accepts_a_cap_that_is_written_differently(self):
        self.assertIsNone(self.check(categories=["groceries"], rate=2, unit="per-dollar", capAmount=6000, capPeriod="year", quote=GROCERY_QUOTE))

    def test_quote_must_be_on_the_page_whatever_the_spacing_or_marks(self):
        self.assertIsNone(self.check(categories=["travel"], rate=5, quote="earn 5%  cash back on hotels and rental cars booked through bank travel."))
        self.assertIsNone(validate_rule(rule(quote="Earn 3% cash back on “Dining”"), normalize("Earn 3% cash back on \"Dining\"®")))
        self.assertIn("not on the page", self.check(quote="Earn unlimited 3% cash back on everything."))

    def test_without_a_page_only_the_page_free_checks_run(self):
        self.assertIsNone(validate_rule(rule(quote="Earn 3% cash back on dining at Zed's."), None))
        self.assertIn("not in the quote", validate_rule(rule(quote="Earn 4% cash back on dining."), None))

    def test_rate_must_be_in_the_quote(self):
        self.assertIn("not in the quote", self.check(rate=4))

    def test_a_longer_number_does_not_count_as_the_rate(self):
        page = normalize("Earn 13% cash back on dining.")
        self.assertIn("not in the quote", validate_rule(rule(quote="Earn 13% cash back on dining."), page))

    def test_category_must_fit_the_quote(self):
        self.assertIn("doesn't mention gas", self.check(categories=["gas"]))
        self.assertIsNone(self.check(categories=["everything-else"], rate=1, quote="Earn 1% cash back on all other purchases."))

    def test_a_base_rate_may_leave_out_all_other_if_it_names_no_other_category(self):
        self.assertIsNone(self.check(categories=["everything-else"], rate=2, requires=["apple-pay"], quote=APPLE))
        self.assertIn("doesn't mention everything-else", self.check(categories=["everything-else"], rate=3))

    def test_category_words_must_start_a_word(self):
        page = normalize("Earn 3% cash back in Las Vegas.")
        self.assertIn("doesn't mention gas", validate_rule(rule(categories=["gas"], quote="Earn 3% cash back in Las Vegas."), page))

    def test_unit_must_match_the_quote(self):
        self.assertIn("no points", self.check(unit="per-dollar"))
        self.assertIn("no %", self.check(unit="percent", categories=["groceries"], rate=2, quote=GROCERY_QUOTE))

    def test_rate_range_and_types(self):
        for bad in (0, -1, 11, True, "3", None):
            self.assertIn("not a number", self.check(rate=bad), bad)

    def test_unknown_category_and_unit(self):
        for bad in (["hotels"], [], "dining", ["dining", "dining"], [["dining"]]):
            self.assertIn("categories", self.check(categories=bad), bad)
        self.assertIn("percent or per-dollar", self.check(unit="points"))

    def test_caps_need_both_parts_and_both_in_the_quote(self):
        groceries = dict(categories=["groceries"], rate=2, unit="per-dollar", quote=GROCERY_QUOTE)
        self.assertIn("needs both", self.check(**groceries, capAmount=6000))
        self.assertIn("cap 5000", self.check(**groceries, capAmount=5000, capPeriod="year"))
        self.assertIn("period month", self.check(**groceries, capAmount=6000, capPeriod="month"))

    def test_a_condition_must_be_the_issuers_own_words(self):
        self.assertIsNone(self.check(conditions=[EXCLUSION]))  # the page has ® marks the model dropped
        self.assertIn("not on the page", self.check(conditions=["Excludes superstores like Walmart."]))
        self.assertIn("not on the page", self.check(conditions=[EXCLUSION, "Made up."]))

    def test_conditions_must_be_a_short_list_of_text(self):
        for bad in (None, "excluding Walmart", [""], [3], ["x"] * 6, ["a" * 401]):
            self.assertIn("condition", self.check(conditions=bad), bad)
        self.assertIn("condition", validate_rule({k: v for k, v in rule().items() if k != "conditions"}, PAGE_NORM))

    def test_not_a_rule(self):
        self.assertEqual(validate_rule("3% on dining", PAGE_NORM), "not an object")
        self.assertIn("no quote", self.check(quote=" "))


class SelectionTests(unittest.TestCase):
    def test_a_rule_the_cardholder_chooses(self):
        self.assertIsNone(validate_rule(choice_rule(), PAGE_NORM))

    def test_a_rule_the_card_applies_to_the_top_category(self):
        top = rule(categories=["dining", "gas", "groceries"], selection="top-spend", picks=1, rate=5, quote=TOP)
        self.assertIsNone(validate_rule(top, PAGE_NORM))

    def test_the_quote_must_say_who_chooses(self):
        self.assertIn("who chooses", validate_rule(choice_rule(quote=ROTATING, rate=5), PAGE_NORM))
        top = rule(categories=["dining", "gas"], selection="top-spend", picks=1, quote=CHOICE)
        self.assertIn("who chooses", validate_rule(top, PAGE_NORM))

    def test_every_choice_must_be_on_the_page(self):
        quote = "Earn 3% cash back in the category of your choice."
        page = normalize(quote)  # a page that never names the choices
        problem = validate_rule(choice_rule(categories=["gas", "dining"], quote=quote), page)
        self.assertIn("gas is not mentioned", problem)

    def test_shape_of_each_selection(self):
        cases = {
            "a fixed rule has one category": rule(categories=["dining", "gas"]),
            "a fixed rule has one category ": rule(picks=1),
            "a fixed rule has one category  ": rule(hasOtherChoices=True),
            "at least two choices": choice_rule(categories=["gas"], hasOtherChoices=False),
            "whole number from 1": choice_rule(picks=0),
            "more than the categories": choice_rule(categories=["gas", "dining"], hasOtherChoices=False, picks=3),
            "can't be one of": choice_rule(categories=["gas", "everything-else"]),
            "selection": rule(selection="random"),
            "hasOtherChoices": rule(hasOtherChoices="no"),
        }
        for expected, bad in cases.items():
            self.assertIn(expected.strip(), validate_rule(bad, PAGE_NORM), expected)


class RequiresAndDatesTests(unittest.TestCase):
    def check(self, **overrides) -> str | None:
        return validate_rule(rule(**overrides), PAGE_NORM)

    def test_a_requirement_must_be_said_in_the_quote_or_a_condition(self):
        booked = dict(categories=["travel"], rate=5, quote=BOOKED)
        self.assertIsNone(self.check(**booked, requires=["issuer-booking"]))
        self.assertIn("requires apple-pay", self.check(**booked, requires=["apple-pay"]))
        self.assertIsNone(self.check(**booked, requires=["apple-pay"], conditions=[APPLE]))

    def test_unknown_or_repeated_requirements(self):
        for bad in (["bitcoin"], ["apple-pay", "apple-pay"], "apple-pay", [3], None):
            self.assertIn("requires must be", self.check(requires=bad), bad)

    def test_a_period_needs_its_months_and_year_in_the_quote(self):
        gas = dict(categories=["gas"], rate=5, quote=ROTATING)
        self.assertIsNone(self.check(**gas, requires=["activation"], validFrom="2026-10-01", validTo="2026-12-31"))
        self.assertIn("year 2027", self.check(**gas, validFrom="2026-10-01", validTo="2027-12-31"))
        self.assertIn("month july", self.check(**gas, validFrom="2026-07-01"))
        self.assertIn("not a date", self.check(**gas, validFrom="Q4 2026"))

    def test_a_period_must_run_forwards(self):
        text = "Earn 5% on gas stations from December 2026 to October 2026."
        page = normalize(text)
        problem = validate_rule(rule(categories=["gas"], rate=5, quote=text, validFrom="2026-12-01", validTo="2026-10-31"), page)
        self.assertIn("after validTo", problem)

    def test_months_match_whole_words_only(self):
        text = "Earn 5% on gas stations in the market during 2026."
        problem = validate_rule(rule(categories=["gas"], rate=5, quote=text, validFrom="2026-03-01"), normalize(text))
        self.assertIn("month march", problem)


FREEDOM = "Activate each quarter to earn 5% cash back on up to $1,500 in combined purchases in that quarter's bonus categories."
DISCOVER = "Earn 5% cash back on everyday purchases at different places you shop each quarter, up to the quarterly maximum when you activate."
LYFT = "Earn 2% total cash back on Lyft rides with your card through September 30, 2027."


class WhatCountsAsWhatTests(unittest.TestCase):
    PAGE = normalize("\n".join([FREEDOM, DISCOVER, LYFT, "Earn 1% on all other purchases.", "Earn 5% on all purchases in the quarter.", "Earn 3% on Netflix."]))

    def check(self, **overrides):
        return validate_rule(rule(**overrides), self.PAGE)

    def test_a_bonus_rate_that_changes_is_never_the_base_rate(self):
        self.assertIn("doesn't mention everything-else", self.check(categories=["everything-else"], rate=5, quote=DISCOVER))
        self.assertIn("doesn't mention everything-else", self.check(categories=["everything-else"], rate=5, quote="Earn 5% on all purchases in the quarter."))
        self.assertIsNone(self.check(categories=["everything-else"], rate=1, quote="Earn 1% on all other purchases."))

    def test_a_rate_at_one_named_company_is_not_a_category_rate(self):
        self.assertIn("doesn't mention transit", self.check(categories=["transit"], rate=2, quote=LYFT))
        self.assertIn("doesn't mention streaming", self.check(categories=["streaming"], rate=3, quote="Earn 3% on Netflix."))

    def test_a_rotating_rate_is_its_own_kind(self):
        freedom = dict(categories=[], selection="rotating", rate=5, quote=FREEDOM, capAmount=1500, capPeriod="quarter", requires=["activation"])
        self.assertIsNone(self.check(**freedom))
        self.assertIsNone(self.check(categories=[], selection="rotating", rate=5, quote=DISCOVER, requires=["activation"]))
        self.assertEqual(extract.needs_of(rule(**freedom)), [])  # nobody has to answer anything: the issuer rotates them

    def test_a_card_with_a_rotating_rule_goes_through_extraction(self):
        page = "Savor Rewards\n" + FREEDOM + "\nEarn 1% on all other purchases.\n" + DISCOVER
        reply = [
            rule(categories=[], selection="rotating", rate=5, quote=FREEDOM, capAmount=1500, capPeriod="quarter", requires=["activation"]),
            rule(categories=[], selection="rotating", rate=5, quote=DISCOVER, requires=["activation"]),
            rule(categories=["everything-else"], rate=1, quote="Earn 1% on all other purchases."),
            rule(categories=["everything-else"], rate=5, quote=DISCOVER),  # the old mistake: a rotating bonus filed as the base
        ]
        result = extract_card(CARD, page, "h", FakeModel(reply), "m")
        self.assertEqual(result["status"], "ok")
        self.assertEqual([(r["selection"], r["rate"]) for r in result["rules"]], [("fixed", 1), ("rotating", 5), ("rotating", 5)])
        self.assertEqual(result["rejected"], [])  # the old mistake (a rotating bonus filed as the base) is retyped, not lost
        self.assertEqual(result["warnings"], [])  # the 5% is not a second base rate any more

    def test_a_rotating_rate_the_model_calls_top_spend_is_retyped(self):
        mislabeled = rule(categories=["dining", "gas"], selection="top-spend", picks=1, rate=5, quote=DISCOVER, requires=["activation"])
        fixed = extract.split_fixed(mislabeled)
        self.assertEqual([(p["selection"], p["categories"], p["picks"], p["hasOtherChoices"]) for p in fixed], [("rotating", [], None, False)])
        self.assertIsNone(self.check(**fixed[0]))

    def test_a_rotating_bonus_filed_as_the_base_rate_is_retyped(self):
        as_base = rule(categories=["everything-else"], rate=5, quote=DISCOVER, requires=["activation"])
        fixed = extract.split_fixed(as_base)
        self.assertEqual([(p["selection"], p["categories"]) for p in fixed], [("rotating", [])])
        self.assertIsNone(self.check(**fixed[0]))
        real_base = rule(categories=["everything-else"], rate=1, quote="Earn 1% on all other purchases.")
        self.assertEqual(extract.split_fixed(real_base), [real_base])

    def test_the_same_quote_seen_twice_is_one_rule_with_the_requirements_combined(self):
        first = rule(categories=["everything-else"], rate=2, quote=APPLE, requires=["apple-pay"])
        again = rule(categories=["everything-else"], rate=2, quote=APPLE, requires=[])
        page = PAGE + "\n" + APPLE
        for order in ((first, again), (again, first)):
            result = extract_card(CARD, page, "h", FakeModel([order[0]], [order[1]]), "m", max_chars=150)
            two = [r for r in result["rules"] if r["rate"] == 2]
            self.assertEqual([(r["requires"], r["needs"]) for r in two], [(["apple-pay"], ["pays-with-apple-pay"])])

    def test_a_base_rate_left_uncategorized_is_everything_else(self):
        base = rule(categories=[], rate=1, quote="Earn 1% on all other purchases.")
        self.assertEqual([p["categories"] for p in extract.split_fixed(base)], [["everything-else"]])
        dining = rule(categories=[], rate=3, quote="Earn 3% on dining.")
        self.assertEqual([p["categories"] for p in extract.split_fixed(dining)], [["dining"]])  # one named category: read from the quote

    def test_an_uncategorized_rule_is_read_from_its_quote(self):
        base = rule(categories=[], selection="choose", picks=1, hasOtherChoices=True, rate=1, quote="Earn unlimited 1% cash back on all other purchases.")
        self.assertEqual([(p["selection"], p["categories"]) for p in extract.split_fixed(base)], [("fixed", ["everything-else"])])
        travel = rule(categories=[], selection="rotating", rate=5, quote="Earn unlimited 5% cash back on hotels, vacation rentals and rental cars booked through Capital One Travel.")
        self.assertEqual([(p["selection"], p["categories"]) for p in extract.split_fixed(travel)], [("fixed", ["travel"])])
        bonus = rule(categories=[], selection="rotating", rate=5, quote=DISCOVER)
        self.assertEqual([(p["selection"], p["categories"]) for p in extract.split_fixed(bonus)], [("rotating", [])])  # says the categories change: stays rotating
        unclear = rule(categories=[], rate=3, quote="Earn 3% on dining.")
        self.assertEqual([p["categories"] for p in extract.split_fixed(unclear)], [["dining"]])

    def test_the_same_rule_worded_differently_is_one_rule_with_one_quote(self):
        a = rule(categories=["dining"], rate=3, quote="Earn 3% on dining at restaurants.")
        b = rule(categories=["dining"], rate=3, quote="You'll earn 3% Cash Back rewards on dining purchases.")
        page = PAGE + "\n" + a["quote"] + "\n" + b["quote"]
        result = extract_card(CARD, page, "h", FakeModel([a], [b]), "m", max_chars=150)
        self.assertEqual(len([r for r in result["rules"] if r["categories"] == ["dining"]]), 1)

    def test_the_same_rule_quoted_two_ways_is_still_one_rule(self):
        a = rule(categories=["dining"], rate=3, quote="Earn unlimited 3% cash back on dining, entertainment and popular streaming services.")
        b = rule(categories=["dining"], rate=3, quote=EXCLUSION)  # a different sentence on the page that says the same thing
        result = extract_card(CARD, PAGE, "h", FakeModel([a], [b]), "m", max_chars=150)
        self.assertEqual(len([r for r in result["rules"] if r["categories"] == ["dining"]]), 1)

    def test_a_cap_that_says_each_quarter_is_not_a_rotating_rate(self):
        capped = rule(categories=["dining", "gas"], selection="top-spend", picks=1, rate=2,
                      quote="Earn 2% cash back at gas stations and restaurants on up to $1,000 in combined purchases each quarter.")
        self.assertEqual(extract.split_fixed(capped), [capped])  # left as it was, so the checks reject it for what it is
        self.assertIn("who chooses", validate_rule(capped, normalize(capped["quote"])))

    def test_a_real_top_spend_or_choice_is_not_retyped(self):
        for selection, quote in (("top-spend", TOP), ("choose", CHOICE)):
            real = rule(categories=["dining", "gas"], selection=selection, picks=1, quote=quote)
            self.assertEqual(extract.split_fixed(real), [real])
        both = rule(categories=["dining", "gas"], selection="top-spend", picks=1, quote="Earn 5% on your top spend category each quarter.")
        self.assertEqual(extract.split_fixed(both), [both])  # it says who picks, so leave it
        self.assertEqual(extract.split_fixed(rule(quote=None, selection="choose", picks=1, categories=["gas", "dining"])), [rule(quote=None, selection="choose", picks=1, categories=["gas", "dining"])])

    def test_a_rotating_rule_must_say_the_categories_change(self):
        self.assertIn("categories change", self.check(categories=[], selection="rotating", rate=1, quote="Earn 1% on all other purchases."))

    def test_a_rotating_rule_may_name_this_periods_categories_if_the_quote_does(self):
        quote = "Earn 5% cash back on gas stations, this quarter's bonus category, from October 1 through December 31, 2026. Activate each quarter."
        page = PAGE_NORM + " " + normalize(quote)
        named = rule(categories=["gas"], selection="rotating", rate=5, quote=quote, requires=["activation"], validFrom="2026-10-01", validTo="2026-12-31")
        self.assertIsNone(validate_rule(named, page))
        self.assertIn("doesn't mention dining", validate_rule({**named, "categories": ["gas", "dining"]}, page))

    def test_rotating_rules_have_no_picks_or_everything_else_and_other_kinds_need_a_category(self):
        for bad in (dict(picks=1), dict(hasOtherChoices=True), dict(categories=["everything-else"])):
            self.assertIn("rotating rule has no", self.check(**{"categories": [], "selection": "rotating", "rate": 5, "quote": FREEDOM, **bad}))
        self.assertIn("categories must be", self.check(categories=[], selection="fixed"))
        self.assertIn("categories must be", self.check(categories=[], selection="choose", picks=1, hasOtherChoices=True))

    def test_the_output_schema_allows_a_rotating_rule_with_no_categories(self):
        self.assertIn("rotating", extract.RULE_SCHEMA["properties"]["selection"]["enum"])
        self.assertNotIn("minItems", extract.RULE_SCHEMA["properties"]["categories"])


class ReviewWarningTests(unittest.TestCase):
    def rules(self, *specs):
        return [extract.accepted_rule(rule(**spec), "u", "h", "page") for spec in specs]

    def test_two_rates_for_the_same_thing_are_flagged(self):
        base = dict(categories=["everything-else"], quote="Earn 1% on all other purchases.")
        warnings = extract.review_warnings(self.rules({**base, "rate": 1}, {**base, "rate": 5}))
        self.assertEqual(warnings, ["everything-else earns 1 and 5 with nothing to tell them apart"])

    def test_rates_with_something_to_tell_them_apart_are_not(self):
        base = dict(categories=["dining"])
        rules = self.rules({**base, "rate": 3}, {**base, "rate": 5, "requires": ["issuer-booking"]},
                           {**base, "rate": 6, "validFrom": "2026-10-01", "validTo": "2026-12-31"},
                           {**base, "rate": 4, "capAmount": 500, "capPeriod": "month"},
                           {"categories": [], "selection": "rotating", "rate": 5}, {"categories": [], "selection": "rotating", "rate": 2},
                           {"categories": ["everything-else"], "rate": 1, "quote": "Earn 1% on all other purchases."})
        self.assertEqual(extract.review_warnings(rules), [])

    def test_a_card_with_rates_but_no_base_rate_is_flagged(self):
        dining = self.rules({"categories": ["dining"], "rate": 3})
        self.assertEqual(extract.review_warnings(dining), ["no rate for all other purchases was found: check the page for what everything else earns"])
        both = self.rules({"categories": ["dining"], "rate": 3}, {"categories": ["everything-else"], "rate": 1, "quote": "Earn 1% on all other purchases."})
        self.assertEqual(extract.review_warnings(both), [])
        self.assertEqual(extract.review_warnings([]), [])  # nothing found is already no-rules

    def test_a_candidate_carries_its_warnings(self):
        reply = [rule(categories=["everything-else"], rate=1, quote="Earn 1% cash back on all other purchases."),
                 rule(categories=["everything-else"], rate=3, quote="Earn unlimited 3% cash back on everything else.")]
        page = PAGE + "\nEarn unlimited 3% cash back on everything else."
        result = extract_card(CARD, page, "h", FakeModel(reply), "m")
        self.assertEqual(result["warnings"], ["everything-else earns 1 and 3 with nothing to tell them apart"])
        self.assertEqual(len(result["rules"]), 2)  # a warning flags, it never removes


class FirstMonthsAndNeedsTests(unittest.TestCase):
    def check(self, **overrides) -> str | None:
        return validate_rule(choice_rule(**overrides), PAGE_NORM)

    def test_a_first_period_must_be_in_the_quote(self):
        year = dict(rate=6, quote=FIRST_YEAR)
        self.assertIsNone(self.check(**year, firstMonths=12))
        self.assertIn("first 6 months", self.check(**year, firstMonths=6))
        self.assertIn("first 12 months", self.check(rate=3, quote=CHOICE, firstMonths=12))

    def test_other_ways_to_say_first(self):
        for text, months in (("Earn 6% in your choice category for the first 12 months.", 12),
                             ("Earn 5% in your choice category during your first 6 months.", 6),
                             ("Earn 5% in your choice category during the first 2 years.", 24),
                             ("Earn 5% in your choice category for the first-year.", 12)):
            rate = 6 if "6%" in text else 5
            self.assertIsNone(validate_rule(choice_rule(rate=rate, quote=text, firstMonths=months), PAGE_NORM + ' ' + normalize(text)), text)

    def test_firstMonths_must_be_a_sane_whole_number(self):
        for bad in (0, -1, 61, 1.5, "12", True):
            self.assertIn("firstMonths must be", self.check(rate=6, quote=FIRST_YEAR, firstMonths=bad), bad)

    def test_needs_come_from_the_rule_not_the_model(self):
        self.assertEqual(extract.needs_of(choice_rule()), ["choice-categories"])
        self.assertEqual(extract.needs_of(choice_rule(firstMonths=12)), ["choice-categories", "account-opened"])
        self.assertEqual(extract.needs_of(rule(requires=["apple-pay"])), ["pays-with-apple-pay"])
        self.assertEqual(extract.needs_of(rule(requires=["activation"])), [])
        self.assertEqual(extract.needs_of({"selection": "fixed", "requires": []}), [])
        self.assertTrue(set(extract.needs_of(choice_rule(firstMonths=12, requires=["apple-pay"]))) <= set(extract.NEEDS))

    def test_a_candidate_lists_every_question_its_rules_ask(self):
        reply = [choice_rule(rate=6, quote=FIRST_YEAR, firstMonths=12), rule(), rule(categories=["everything-else"], rate=2,
                 requires=["apple-pay"], quote=APPLE)]
        result = extract_card(CARD, PAGE, "h", FakeModel(reply), "m")
        self.assertEqual(result["needs"], ["account-opened", "choice-categories", "pays-with-apple-pay"])
        by_rate = {r["rate"]: r for r in result["rules"]}
        self.assertEqual((by_rate[6]["firstMonths"], by_rate[6]["needs"]), (12, ["choice-categories", "account-opened"]))

    def test_hand_entered_rules_get_needs_too_even_without_the_field(self):
        legacy = {k: v for k, v in choice_rule().items() if k != "firstMonths"}
        result = manual_candidate(CARD, {"rules": [legacy]}, PAGE, "h")
        self.assertEqual((result["needs"], result["rules"][0]["firstMonths"]), (["choice-categories"], None))


class PageTextTests(unittest.TestCase):
    def test_numbers_in(self):
        numbers = extract.numbers_in("$6,000 or 6K, 1.5% and 3X")
        self.assertEqual(numbers, {6000.0, 1.5, 3.0})

    def test_name_on_page(self):
        self.assertTrue(extract.name_on_page("Blue Business Plus", "The Blue Business® Plus Credit Card from Amex"))
        self.assertTrue(extract.name_on_page("Delta SkyMiles Gold", "Gold Delta SkyMiles® card"))
        self.assertFalse(extract.name_on_page("Platinum", "The Gold Card"))

    def test_chunks_fit_overlap_and_lose_nothing(self):
        text = "\n".join(f"line {n:02d} " + "x" * 20 for n in range(30))
        chunks = extract.chunk_lines(text, max_chars=200, overlap=2)
        self.assertTrue(all(len(chunk) <= 200 for chunk in chunks))
        self.assertGreater(len(chunks), 1)
        for before, after in zip(chunks, chunks[1:]):
            self.assertEqual(before.splitlines()[-2:], after.splitlines()[:2])
        self.assertEqual({line for chunk in chunks for line in chunk.splitlines()}, set(text.splitlines()))

    def test_a_line_longer_than_a_chunk_is_split(self):
        chunks = extract.chunk_lines("y" * 250, max_chars=100)
        self.assertEqual([len(c) for c in chunks], [100, 100, 50])

    def test_only_chunks_that_could_state_a_rate_are_asked(self):
        self.assertTrue(extract.has_rates("Earn 3% back"))
        self.assertTrue(extract.has_rates("Get 2X points"))
        self.assertFalse(extract.has_rates("Menu\nContact us\nCall 1-800-555-0100"))


class FakeModel:
    """Answers each chunk with the next queued reply (the last repeats) and remembers what it was asked.
    A list reply is a list of rules; a dict is the whole reply."""

    def __init__(self, *replies) -> None:
        self.replies = list(replies)
        self.asked: list[list[dict]] = []

    def __call__(self, messages: list[dict]) -> str:
        self.asked.append(messages)
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
        if isinstance(reply, Exception):
            raise reply
        if isinstance(reply, list):
            reply = {"cardConditions": [], "rules": reply}
        return reply if isinstance(reply, str) else json.dumps(reply)


class ExtractCardTests(unittest.TestCase):
    def run_card(self, model, text=PAGE, card=CARD, **kwargs) -> dict:
        return extract_card(card, text, "hash1", model, "test-model", **kwargs)

    def test_keeps_valid_rules_and_lists_rejected_ones_with_reasons(self):
        made_up = rule(categories=["gas"], rate=4, quote="Earn 4% cash back on gas.")
        result = self.run_card(FakeModel([rule(), made_up]))
        self.assertEqual(result["status"], "ok")
        self.assertEqual([r["categories"] for r in result["rules"]], [["dining"]])
        self.assertEqual(result["rules"][0]["verified"], "page")
        self.assertEqual(result["rules"][0]["evidence"], {"quote": rule()["quote"], "url": CARD["sourceUrl"], "pageHash": "hash1"})
        self.assertEqual(len(result["rejected"]), 1)
        self.assertIn("not on the page", result["rejected"][0]["reason"])
        self.assertEqual((result["model"], result["promptVersion"], result["pageHash"]), ("test-model", extract.PROMPT_VERSION, "hash1"))

    def test_selection_requirements_and_dates_survive_into_the_rule(self):
        result = self.run_card(FakeModel([choice_rule(), rule(categories=["gas"], rate=5, quote=ROTATING, requires=["activation"],
                                                             validFrom="2026-10-01", validTo="2026-12-31")]))
        by_selection = {r["selection"]: r for r in result["rules"]}
        self.assertEqual((by_selection["choose"]["picks"], by_selection["choose"]["hasOtherChoices"]), (1, True))
        fixed = by_selection["fixed"]
        self.assertEqual((fixed["requires"], fixed["validFrom"], fixed["validTo"]), (["activation"], "2026-10-01", "2026-12-31"))

    def test_card_wide_conditions_are_kept_once_and_made_up_ones_are_dropped(self):
        reply = {"cardConditions": [WALLETS, "A sentence from nowhere."], "rules": [rule()]}
        result = self.run_card(FakeModel(reply), max_chars=150)
        self.assertEqual(result["cardConditions"], [WALLETS])
        self.assertEqual([r["cardCondition"] for r in result["rejected"] if "cardCondition" in r], ["A sentence from nowhere."] * len(result["rejected"]))
        self.assertTrue(all("not on the page" in r["reason"] for r in result["rejected"]))

    def test_conditions_are_kept_and_merged_across_chunks(self):
        with_condition = rule(categories=["groceries"], quote=EXCLUSION, conditions=[EXCLUSION])
        without = rule(categories=["groceries"], quote=EXCLUSION)
        result = self.run_card(FakeModel([without], [with_condition]), max_chars=150)
        grocery = [r for r in result["rules"] if r["categories"] == ["groceries"]]
        self.assertEqual([r["conditions"] for r in grocery], [[EXCLUSION]])

    def test_a_rule_with_a_made_up_condition_is_rejected_whole(self):
        result = self.run_card(FakeModel([rule(conditions=["Not on the page at all."])]))
        self.assertEqual((result["rules"], result["status"]), ([], "no-rules"))
        self.assertIn("condition", result["rejected"][0]["reason"])

    def test_a_fixed_rule_listing_several_categories_becomes_one_rule_each(self):
        grouped = rule(categories=["dining", "groceries"], quote=EXCLUSION, rate=3)
        result = self.run_card(FakeModel([grouped]))
        self.assertEqual([r["categories"] for r in result["rules"]], [["dining"], ["groceries"]])
        self.assertEqual({r["evidence"]["quote"] for r in result["rules"]}, {EXCLUSION})

    def test_each_split_category_is_checked_on_its_own(self):
        grouped = rule(categories=["dining", "gas"], quote=EXCLUSION, rate=3)  # the quote never mentions gas
        result = self.run_card(FakeModel([grouped]))
        self.assertEqual([r["categories"] for r in result["rules"]], [["dining"]])
        self.assertEqual([r["reason"] for r in result["rejected"]], ["quote doesn't mention gas"])

    def test_a_split_rule_keeps_only_the_conditions_about_each_category(self):
        about_groceries = "A supermarket, meat locker, freezer, dairy product store and specialty market. Excludes superstores like Walmart and Target."
        about_nothing = "Excludes superstores like Walmart and Target."
        grouped = rule(categories=["dining", "groceries", "streaming"], rate=3, conditions=[about_groceries, about_nothing])
        parts = {p["categories"][0]: p["conditions"] for p in extract.split_fixed(grouped)}
        self.assertEqual(parts["groceries"], [about_groceries, about_nothing])
        self.assertEqual(parts["dining"], [about_nothing])  # the supermarket sentence is not about dining
        self.assertEqual(parts["streaming"], [about_nothing])

    def test_choosing_every_listed_category_is_a_fixed_rule(self):
        everything = rule(categories=["dining", "groceries", "streaming"], selection="choose", picks=3, hasOtherChoices=True, quote=EXCLUSION, rate=3)
        parts = extract.split_fixed(everything)
        self.assertEqual([(p["categories"], p["selection"], p["picks"], p["hasOtherChoices"]) for p in parts],
                         [(["dining"], "fixed", None, False), (["groceries"], "fixed", None, False), (["streaming"], "fixed", None, False)])
        result = self.run_card(FakeModel([everything]))
        self.assertEqual([r["categories"] for r in result["rules"]], [["dining"], ["groceries"]])  # streaming isn't in that quote

    def test_a_real_choice_is_left_alone(self):
        real = choice_rule()  # picks 1 of 5
        self.assertEqual(extract.split_fixed(real), [real])
        top = rule(categories=["dining", "gas"], selection="top-spend", picks=1, quote=TOP, rate=5)
        self.assertEqual(extract.split_fixed(top), [top])
        for odd in (None, True, "3"):
            kept = rule(categories=["dining", "gas"], selection="choose", picks=odd)
            self.assertEqual(extract.split_fixed(kept), [kept])

    def test_only_fixed_rules_are_split(self):
        self.assertEqual(len(extract.split_fixed(choice_rule())), 1)
        self.assertEqual(len(extract.split_fixed(rule(categories=["dining"]))), 1)
        self.assertEqual(extract.split_fixed("not a rule"), ["not a rule"])
        self.assertEqual(extract.split_fixed(rule(categories="dining, gas"))[0]["categories"], "dining, gas")

    def test_the_prompt_names_the_card_and_carries_the_page(self):
        model = FakeModel([])
        self.run_card(model)
        user = model.asked[0][1]["content"]
        self.assertIn('"Savor Rewards"', user)
        self.assertIn("Earn 5% cash back on hotels", user)
        for word in ("choose", "top-spend", "apple-pay", "validFrom", "cardConditions"):
            self.assertIn(word, user)

    def test_everything_that_is_the_same_for_every_card_comes_first_so_servers_can_cache_it(self):
        import os
        a = extract.build_messages(CARD, "Earn 3% on dining.")
        b = extract.build_messages({**CARD, "name": "Another Card", "issuer": "Other Bank", "rewardKind": "points"}, "Earn 2X on gas.")
        self.assertEqual(a[0], b[0])  # the system message
        shared = os.path.commonprefix([a[1]["content"], b[1]["content"]])
        self.assertGreater(len(shared), 3000)  # all the rules
        self.assertNotIn("Savor", shared)
        self.assertLess(len(a[1]["content"]) - len(shared), 400)  # only the card line and the page text differ
        self.assertTrue(a[1]["content"].index('"Savor Rewards"') < a[1]["content"].index("Earn 3% on dining."))

    def test_the_same_rule_from_several_chunks_is_kept_once(self):
        model = FakeModel([rule()])
        result = self.run_card(model, max_chars=120)
        self.assertGreater(len(model.asked), 1)
        self.assertEqual(len(result["rules"]), 1)

    def test_a_page_that_does_not_name_the_card_gets_no_rules_and_no_questions(self):
        model = FakeModel([rule()])
        result = self.run_card(model, text=PAGE.replace("Savor", "Other"))
        self.assertEqual((result["status"], result["rules"]), ("wrong-page", []))
        self.assertEqual(model.asked, [])

    def test_a_page_with_no_rate_is_not_sent_to_the_model(self):
        model = FakeModel([rule()])
        result = self.run_card(model, text="Savor Rewards\nContact us\nMenu")
        self.assertEqual((result["status"], model.asked), ("no-rules", []))

    def test_a_model_that_finds_nothing_is_no_rules(self):
        self.assertEqual(self.run_card(FakeModel([]))["status"], "no-rules")

    def test_bad_json_is_retried_once_then_the_card_fails(self):
        retried = FakeModel("not json", [rule()])
        self.assertEqual(self.run_card(retried)["status"], "ok")
        self.assertEqual(len(retried.asked), 2)

        broken = FakeModel("not json")
        result = self.run_card(broken)
        self.assertEqual((result["status"], len(broken.asked)), ("failed", 2))

    def test_a_failed_card_says_why(self):
        result = self.run_card(FakeModel("I found some rates:"))
        self.assertEqual(result["status"], "failed")
        self.assertEqual(len(result["errors"]), 1)  # the same error twice is told once
        self.assertIn("I found some rates:", result["errors"][0])
        self.assertIn("characters and began", result["errors"][0])

        refused = self.run_card(FakeModel(OSError("LM Studio answered HTTP 400: bad schema")))
        self.assertEqual(refused["errors"], ["OSError: LM Studio answered HTTP 400: bad schema"])

    def test_an_unreachable_model_fails_the_card(self):
        self.assertEqual(self.run_card(FakeModel(OSError("refused")))["status"], "failed")

    def test_fenced_replies_are_read(self):
        reply = "```json\n" + json.dumps({"cardConditions": [], "rules": [rule()]}) + "\n```"
        self.assertEqual(len(self.run_card(FakeModel(reply))["rules"]), 1)

    def test_wrong_shape_replies_are_failures(self):
        for reply in ('["x"]', '{"rules": "none"}', "{}", '{"rules": [], "cardConditions": "none"}'):
            self.assertEqual(self.run_card(FakeModel(reply))["status"], "failed", reply)

    def test_a_reply_without_card_conditions_is_still_read(self):
        self.assertEqual(len(self.run_card(FakeModel(json.dumps({"rules": [rule()]})))["rules"]), 1)


class StatsTests(unittest.TestCase):
    def test_calls_are_totalled_including_what_a_server_leaves_out(self):
        calls = [
            {"seconds": 2.04, "usage": {"prompt_tokens": 100, "completion_tokens": 40, "prompt_tokens_details": {"cached_tokens": 60},
                                         "completion_tokens_details": {"reasoning_tokens": 25}}},
            {"seconds": 1.0, "usage": {"prompt_tokens": 50, "completion_tokens": 10}},
            {"seconds": 0.5},  # a call that failed before the server reported anything
        ]
        self.assertEqual(extract.summarize_calls(calls), {
            "calls": 3, "seconds": 3.5, "promptTokens": 150, "cachedTokens": 60, "replyTokens": 50, "reasoningTokens": 25})
        self.assertEqual(extract.summarize_calls([])["calls"], 0)

    def test_a_processed_card_carries_its_stats(self):
        import tempfile
        from pathlib import Path
        server = extract.ChatServer("http://x", "m", urlopen=lambda request, timeout: io.BytesIO(json.dumps({
            "choices": [{"message": {"content": json.dumps({"cardConditions": [], "rules": []})}}],
            "usage": {"prompt_tokens": 90, "completion_tokens": 7, "prompt_tokens_details": {"cached_tokens": 80}}}).encode()))
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            (cache / CARD["id"]).mkdir()
            (cache / CARD["id"] / "latest.txt").write_text(PAGE)
            events = []
            extract.process_cards([CARD], state={CARD["id"]: {"hash": "h"}}, manual={}, client=server, chunk_chars=12000, force=True,
                                  cache=cache, candidates=cache / "c", emit=events.append)
            saved = json.loads((cache / "c" / f"{CARD['id']}.json").read_text())
        self.assertEqual((saved["stats"]["calls"], saved["stats"]["promptTokens"], saved["stats"]["cachedTokens"]), (1, 90, 80))
        self.assertEqual(events[-1]["stats"], saved["stats"])


class ManualRulesTests(unittest.TestCase):
    APPLE_RULE = rule(categories=["everything-else"], rate=2, requires=["apple-pay"], quote=APPLE)

    def candidate(self, entry, text=PAGE):
        return manual_candidate(CARD, entry, text, "hash1")

    def test_a_rule_whose_quote_is_on_the_page_is_page_verified(self):
        result = self.candidate({"rules": [self.APPLE_RULE]})
        self.assertEqual((result["status"], result["model"], [r["verified"] for r in result["rules"]]), ("manual", "manual", ["page"]))

    def test_a_rule_the_page_cannot_confirm_is_kept_as_manual(self):
        for text in (None, "A page that says nothing about this card."):
            result = self.candidate({"rules": [self.APPLE_RULE]}, text)
            self.assertEqual([r["verified"] for r in result["rules"]], ["manual"], text)

    def test_a_choice_rule_is_page_verified_when_the_page_lists_the_choices_and_manual_when_it_cannot(self):
        entry = {"rules": [choice_rule()]}
        self.assertEqual([r["verified"] for r in self.candidate(entry)["rules"]], ["page"])
        self.assertEqual([r["verified"] for r in self.candidate(entry, None)["rules"]], ["manual"])
        bare = "Earn 3% cash back in the category of your choice."
        self.assertEqual([r["verified"] for r in self.candidate({"rules": [choice_rule(quote=bare)]}, bare)["rules"]], ["manual"])

    def test_a_rule_that_breaks_the_shape_rules_is_rejected_even_by_hand(self):
        bad = rule(rate=4, quote=APPLE)
        result = self.candidate({"rules": [bad]})
        self.assertEqual((result["rules"], result["status"]), ([], "no-rules"))
        self.assertIn("not in the quote", result["rejected"][0]["reason"])

    def test_card_conditions_say_whether_the_page_has_them(self):
        self.assertTrue(self.candidate({"rules": [self.APPLE_RULE], "cardConditions": [WALLETS]})["cardConditionsOnPage"])
        self.assertFalse(self.candidate({"rules": [self.APPLE_RULE], "cardConditions": ["Typed in."]})["cardConditionsOnPage"])
        self.assertFalse(self.candidate({"rules": [self.APPLE_RULE], "cardConditions": [WALLETS]}, None)["cardConditionsOnPage"])


class LMStudioTests(unittest.TestCase):
    def client(self, payload):
        calls = []

        def urlopen(request, timeout):
            calls.append(request)
            return io.BytesIO(json.dumps(payload).encode())

        return extract.ChatServer("http://lm.test/v1/", "m", urlopen=urlopen), calls

    def test_lists_models(self):
        client, _ = self.client({"data": [{"id": "a"}, {"id": "b"}]})
        self.assertEqual(client.models(), ["a", "b"])

    def test_asks_for_schema_constrained_output_at_temperature_zero(self):
        client, calls = self.client({"choices": [{"message": {"content": '{"rules": []}'}}]})
        self.assertEqual(client.complete([{"role": "user", "content": "hi"}]), '{"rules": []}')
        body = json.loads(calls[0].data)
        self.assertEqual((body["model"], body["temperature"]), ("m", 0))
        self.assertEqual(body["response_format"]["type"], "json_schema")
        self.assertEqual(calls[0].full_url, "http://lm.test/v1/chat/completions")

    def test_the_schema_asks_for_every_field_the_validator_reads(self):
        fields = set(extract.RULE_SCHEMA["properties"])
        self.assertEqual(fields, set(extract.RULE_SCHEMA["required"]))
        self.assertEqual(fields, set(rule()))
        self.assertNotIn("needs", fields)  # derived from the rule, never taken from the model

    def test_a_refused_request_carries_lm_studios_explanation(self):
        import urllib.error

        def refuse(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 400, "Bad Request", {}, io.BytesIO(b'{"error": "Invalid schema"}'))

        client = extract.ChatServer("http://lm.test/v1", "m", urlopen=refuse)
        with self.assertRaises(OSError) as raised:
            client.complete([])
        self.assertIn("HTTP 400", str(raised.exception))
        self.assertIn("Invalid schema", str(raised.exception))

    def test_an_empty_reply_says_why_and_what_to_try(self):
        for payload, expected in (
            ({"choices": [{"finish_reason": "length", "message": {"content": "", "reasoning_content": "Let me think " * 50}}],
              "usage": {"completion_tokens": 3000}}, ["'length'", f"3000 of {extract.DEFAULT_MAX_TOKENS}", "characters of reasoning", "raise the reply limit"]),
            ({"choices": [{"finish_reason": "stop", "message": {"content": None}}]}, ["'stop'", f"? of {extract.DEFAULT_MAX_TOKENS}", "empty reply"]),
        ):
            client, _ = self.client(payload)
            with self.assertRaises(ValueError) as raised:
                client.complete([])
            for fragment in expected:
                self.assertIn(fragment, str(raised.exception))

    def test_extra_fields_and_a_prompt_suffix_reach_the_request(self):
        calls = []

        def urlopen(request, timeout):
            calls.append(json.loads(request.data))
            return io.BytesIO(json.dumps({"choices": [{"message": {"content": "{}"}}]}).encode())

        client = extract.ChatServer("http://lm.test/v1", "m", urlopen=urlopen, max_tokens=123,
                                  extra_body={"reasoning_effort": "low", "model": "sneaky", "messages": []}, prompt_suffix=" /no_think ")
        client.complete([{"role": "system", "content": "s"}, {"role": "user", "content": "find rates"}])
        body = calls[0]
        self.assertEqual((body["reasoning_effort"], body["max_tokens"], body["model"]), ("low", 123, "m"))
        self.assertEqual([m["content"] for m in body["messages"]], ["s", "find rates\n\n/no_think"])

    def test_how_a_reply_ended_is_kept(self):
        client, _ = self.client({"choices": [{"finish_reason": "stop", "message": {"content": "{}"}}], "usage": {"completion_tokens": 2}})
        client.complete([])
        self.assertEqual(client.last_meta["finishReason"], "stop")
        self.assertEqual(client.last_meta["replyChars"], 2)

    def serve(self, **options):
        """A ChatServer whose requests are recorded as (url, headers, body)."""
        calls = []

        def urlopen(request, timeout):
            calls.append((request.full_url, {k.lower(): v for k, v in request.header_items()}, json.loads(request.data) if request.data else None))
            if request.full_url.endswith("/models"):
                return io.BytesIO(b'{"data": [{"id": "m"}]}')
            return io.BytesIO(json.dumps({"choices": [{"message": {"content": "{}"}}]}).encode())

        return extract.ChatServer("http://api.test/v1", "m", urlopen=urlopen, **options), calls

    def test_the_api_key_is_sent_as_a_bearer_token_on_every_request(self):
        client, calls = self.serve(api_key=" secret-token ")
        client.models()
        client.complete([{"role": "user", "content": "hi"}])
        self.assertEqual([c[1]["authorization"] for c in calls], ["Bearer secret-token"] * 2)

    def test_no_key_means_no_authorization_header(self):
        client, calls = self.serve()
        client.models()
        client.complete([{"role": "user", "content": "hi"}])
        self.assertTrue(all("authorization" not in c[1] for c in calls))

    def test_how_the_reply_shape_is_requested(self):
        schema_text = json.dumps(extract.SCHEMA)
        asks = {}
        for mode in extract.RESPONSE_MODES:
            client, calls = self.serve(response_mode=mode)
            client.complete([{"role": "system", "content": "s"}, {"role": "user", "content": "find rates"}])
            asks[mode] = calls[0][2]
        self.assertEqual(asks["json_schema"]["response_format"]["json_schema"]["schema"], extract.SCHEMA)
        self.assertNotIn(schema_text, asks["json_schema"]["messages"][-1]["content"])
        self.assertEqual(asks["json_object"]["response_format"], {"type": "json_object"})
        self.assertIn(schema_text, asks["json_object"]["messages"][-1]["content"])
        self.assertNotIn("response_format", asks["prompt"])
        self.assertIn(schema_text, asks["prompt"]["messages"][-1]["content"])
        self.assertEqual(asks["prompt"]["messages"][0]["content"], "s")

    def test_function_calling_mode_offers_one_strict_tool_and_reads_the_answer_from_its_call(self):
        calls = []

        def urlopen(request, timeout):
            calls.append(json.loads(request.data))
            message = {"content": None, "tool_calls": [{"type": "function", "function": {
                "name": "report_rules", "arguments": json.dumps({"cardConditions": [], "rules": []})}}]}
            return io.BytesIO(json.dumps({"choices": [{"finish_reason": "tool_calls", "message": message}]}).encode())

        client = extract.ChatServer("http://api.test/v1", "m", urlopen=urlopen, response_mode="tool")
        reply = client.complete([{"role": "system", "content": "s"}, {"role": "user", "content": "find rates"}])
        self.assertEqual(json.loads(reply), {"cardConditions": [], "rules": []})
        self.assertTrue(client.last_meta["viaTool"])
        body = calls[0]
        self.assertNotIn("response_format", body)
        function = body["tools"][0]["function"]
        self.assertEqual((function["name"], function["strict"], function["parameters"]), ("report_rules", True, extract.SCHEMA))
        self.assertNotIn("tool_choice", body)  # some servers accept only "auto"; the settings' extra fields can add one
        self.assertIn("by calling the report_rules function", body["messages"][-1]["content"])

    def test_function_calling_mode_falls_back_to_plain_text_and_other_tools_are_ignored(self):
        def serve(message):
            return extract.ChatServer("http://x", "m", response_mode="tool", urlopen=lambda r, timeout: io.BytesIO(
                json.dumps({"choices": [{"message": message}]}).encode()))

        self.assertEqual(serve({"content": '{"rules": []}'}).complete([{"role": "user", "content": "x"}]), '{"rules": []}')
        other = {"content": "", "tool_calls": [{"function": {"name": "something_else", "arguments": "{}"}}]}
        with self.assertRaises(ValueError):
            serve(other).complete([{"role": "user", "content": "x"}])

    def test_free_requests_ask_for_no_format_and_take_extra_fields_for_one_call(self):
        client, calls = self.serve(response_mode="tool", extra_body={"top_k": 5})
        client.complete([{"role": "user", "content": "hi"}], free=True, extra_body={"seed": 1})
        body = calls[0][2]
        self.assertTrue(all(k not in body for k in ("tools", "response_format")))
        self.assertEqual((body["top_k"], body["seed"], body["messages"][-1]["content"]), (5, 1, "hi"))
        client.complete([{"role": "user", "content": "hi"}], free=True)
        self.assertNotIn("seed", calls[1][2])

    def test_the_reply_limit_field_and_temperature_follow_the_settings(self):
        client, calls = self.serve(token_field="max_completion_tokens", max_tokens=77, temperature=None)
        client.complete([{"role": "user", "content": "hi"}])
        body = calls[0][2]
        self.assertEqual(body["max_completion_tokens"], 77)
        self.assertNotIn("max_tokens", body)
        self.assertNotIn("temperature", body)
        self.assertEqual(self.serve(temperature=0.3)[0].temperature, 0.3)

    def test_unknown_response_modes_and_token_fields_are_refused(self):
        with self.assertRaises(ValueError):
            extract.ChatServer("http://x", "m", response_mode="xml")
        with self.assertRaises(ValueError):
            extract.ChatServer("http://x", "m", token_field="limit")

    def test_a_model_list_may_be_a_bare_list(self):
        client = extract.ChatServer("http://x", "m", urlopen=lambda request, timeout: io.BytesIO(b'[{"id": "a"}]'))
        self.assertEqual(client.models(), ["a"])

    def http_error(self, code: int, body: bytes = b"nope"):
        def urlopen(request, timeout):
            raise urllib.error.HTTPError(request.full_url, code, "x", {}, io.BytesIO(body))

        return extract.ChatServer("http://api.test/v1", "m", urlopen=urlopen, api_key="secret-token")

    def test_check_server_tells_a_bad_key_from_a_missing_model_list_and_a_dead_server(self):
        for code in (401, 403):
            with self.assertRaises(extract.ServerProblem) as raised:
                extract.check_server(self.http_error(code))
            self.assertIn("API key", str(raised.exception))
            self.assertNotIn("secret-token", str(raised.exception))
        self.assertEqual(extract.check_server(self.http_error(404)), [])  # no model list: the model id is taken on trust

        def down(request, timeout):
            raise urllib.error.URLError("connection refused")

        with self.assertRaises(extract.ServerProblem) as raised:
            extract.check_server(extract.ChatServer("http://api.test/v1", "m", urlopen=down))
        self.assertIn("isn't answering", str(raised.exception))

        with self.assertRaises(extract.ServerProblem) as raised:
            extract.check_server(self.serve()[0].__class__("http://x", "other", urlopen=lambda r, timeout: io.BytesIO(b'{"data": [{"id": "m"}]}')))
        self.assertIn("has no model 'other'", str(raised.exception))

    def test_errors_carry_the_servers_words_and_status_but_never_the_key(self):
        with self.assertRaises(extract.ServerHTTPError) as raised:
            self.http_error(400, b'{"error": "bad schema"}').complete([{"role": "user", "content": "hi"}])
        self.assertEqual(raised.exception.code, 400)
        self.assertIn("bad schema", str(raised.exception))
        self.assertNotIn("secret-token", str(raised.exception))

    def test_an_odd_reply_is_a_value_error(self):
        client, _ = self.client({"oops": 1})
        with self.assertRaises(ValueError):
            client.complete([])


if __name__ == "__main__":
    unittest.main()
