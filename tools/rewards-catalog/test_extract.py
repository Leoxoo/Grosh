"""Offline tests for extract.py (no LM Studio needed): python3 -m unittest discover -s tools/rewards-catalog"""

import io
import json
import unittest

import extract
from extract import extract_card, manual_candidate, normalize, validate_rule

CARD = {"id": "bank-savor", "name": "Savor Rewards", "issuer": "Bank", "rewardKind": "cashback", "sourceUrl": "https://x.test/savor"}
CHOICE = "Earn 3% cash back in the category of your choice: gas, online shopping, dining, travel, drug stores or home improvement."
TOP = "Earn 5% cash back on your top eligible spend category each billing cycle, from restaurants, gas stations and grocery stores."
ROTATING = "Earn 5% cash back on gas stations from October 1 through December 31, 2026. Activate each quarter."
APPLE = "Get 2% Daily Cash back when you use Apple Card with Apple Pay."
BOOKED = "Earn 5% cash back on hotels and rental cars booked through Bank Travel."
EXCLUSION = "Earn unlimited 3% cash back at grocery stores (excluding superstores like Walmart and Target), on dining."
WALLETS = "Purchases made through mobile or digital wallets may not receive a higher percentage reward."
GROCERY_QUOTE = "Earn 2X points on groceries at U.S. supermarkets on up to $6,000 per year in purchases."
PAGE = "\n".join([
    "Savor® Rewards Credit Card",
    "Earn unlimited 3% cash back on dining, entertainment and popular streaming services.",
    BOOKED,
    GROCERY_QUOTE,
    "Earn 1% cash back on all other purchases.",
    "Earn unlimited 3% cash back at grocery stores (excluding superstores like Walmart® and Target®), on dining.",
    APPLE, CHOICE, TOP, ROTATING, WALLETS,
    "Menu\nContact us\nPrivacy",
])
PAGE_NORM = normalize(PAGE)


def rule(**overrides) -> dict:
    base = {
        "categories": ["dining"], "selection": "fixed", "picks": None, "hasOtherChoices": False,
        "rate": 3, "unit": "percent", "capAmount": None, "capPeriod": None, "requires": [],
        "validFrom": None, "validTo": None, "conditions": [],
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

    def test_the_prompt_names_the_card_and_carries_the_page(self):
        model = FakeModel([])
        self.run_card(model)
        user = model.asked[0][1]["content"]
        self.assertIn('"Savor Rewards"', user)
        self.assertIn("Earn 5% cash back on hotels", user)
        for word in ("choose", "top-spend", "apple-pay", "validFrom", "cardConditions"):
            self.assertIn(word, user)

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

        return extract.LMStudio("http://lm.test/v1/", "m", urlopen=urlopen), calls

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

    def test_an_odd_reply_is_a_value_error(self):
        client, _ = self.client({"oops": 1})
        with self.assertRaises(ValueError):
            client.complete([])


if __name__ == "__main__":
    unittest.main()
