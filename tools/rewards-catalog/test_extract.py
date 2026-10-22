"""Offline tests for extract.py (no LM Studio needed): python3 -m unittest discover -s tools/rewards-catalog"""

import io
import json
import unittest

import extract
from extract import extract_card, normalize, validate_rule

CARD = {"id": "bank-savor", "name": "Savor Rewards", "issuer": "Bank", "rewardKind": "cashback", "sourceUrl": "https://x.test/savor"}
PAGE = "\n".join([
    "Savor® Rewards Credit Card",
    "Earn unlimited 3% cash back on dining, entertainment and popular streaming services.",
    "Earn 5% cash back on hotels and rental cars booked through Bank Travel.",
    "Earn 2X points on groceries at U.S. supermarkets on up to $6,000 per year in purchases.",
    "Earn 1% cash back on all other purchases.",
    "Earn unlimited 3% cash back at grocery stores (excluding superstores like Walmart® and Target®), on dining.",
    "Menu\nContact us\nPrivacy",
])
EXCLUSION = "Earn unlimited 3% cash back at grocery stores (excluding superstores like Walmart and Target), on dining."
PAGE_NORM = normalize(PAGE)
GROCERY_QUOTE = "Earn 2X points on groceries at U.S. supermarkets on up to $6,000 per year in purchases."


def rule(**overrides) -> dict:
    base = {
        "category": "dining", "rate": 3, "unit": "percent", "capAmount": None, "capPeriod": None, "conditions": [],
        "quote": "Earn unlimited 3% cash back on dining, entertainment and popular streaming services.",
    }
    return {**base, **overrides}


class ValidateRuleTests(unittest.TestCase):
    def check(self, **overrides) -> str | None:
        return validate_rule(rule(**overrides), PAGE_NORM)

    def test_accepts_a_rule_the_page_backs(self):
        self.assertIsNone(self.check())

    def test_accepts_a_cap_that_is_written_differently(self):
        self.assertIsNone(self.check(category="groceries", rate=2, unit="per-dollar", capAmount=6000, capPeriod="year", quote=GROCERY_QUOTE))

    def test_quote_must_be_on_the_page_whatever_the_spacing_or_marks(self):
        self.assertIsNone(self.check(category="travel", rate=5, quote="earn 5%  cash back on hotels and rental cars"))
        self.assertIsNone(validate_rule(rule(quote="Earn 3% cash back on “Dining”"), normalize("Earn 3% cash back on \"Dining\"®")))
        self.assertIn("not on the page", self.check(quote="Earn unlimited 3% cash back on everything."))

    def test_rate_must_be_in_the_quote(self):
        self.assertIn("not in the quote", self.check(rate=4))

    def test_a_longer_number_does_not_count_as_the_rate(self):
        page = normalize("Earn 13% cash back on dining.")
        self.assertIn("not in the quote", validate_rule(rule(quote="Earn 13% cash back on dining."), page))

    def test_category_must_fit_the_quote(self):
        self.assertIn("doesn't mention gas", self.check(category="gas"))
        self.assertIsNone(self.check(category="everything-else", rate=1, quote="Earn 1% cash back on all other purchases."))

    def test_category_words_must_start_a_word(self):
        page = normalize("Earn 3% cash back in Las Vegas.")
        self.assertIn("doesn't mention gas", validate_rule(rule(category="gas", quote="Earn 3% cash back in Las Vegas."), page))

    def test_unit_must_match_the_quote(self):
        self.assertIn("no points", self.check(unit="per-dollar"))
        self.assertIn("no %", self.check(unit="percent", category="groceries", rate=2, quote=GROCERY_QUOTE))

    def test_rate_range_and_types(self):
        for bad in (0, -1, 11, True, "3", None):
            self.assertIn("not a number", self.check(rate=bad), bad)

    def test_unknown_category_and_unit(self):
        self.assertIn("catalog's list", self.check(category="hotels"))
        self.assertIn("percent or per-dollar", self.check(unit="points"))

    def test_caps_need_both_parts_and_both_in_the_quote(self):
        groceries = dict(category="groceries", rate=2, unit="per-dollar", quote=GROCERY_QUOTE)
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
    """Answers each chunk with the next queued reply (the last repeats) and remembers what it was asked."""

    def __init__(self, *replies) -> None:
        self.replies = list(replies)
        self.asked: list[list[dict]] = []

    def __call__(self, messages: list[dict]) -> str:
        self.asked.append(messages)
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
        if isinstance(reply, Exception):
            raise reply
        return reply if isinstance(reply, str) else json.dumps({"rules": reply})


class ExtractCardTests(unittest.TestCase):
    def run_card(self, model, text=PAGE, card=CARD, **kwargs) -> dict:
        return extract_card(card, text, "hash1", model, "test-model", **kwargs)

    def test_keeps_valid_rules_and_lists_rejected_ones_with_reasons(self):
        made_up = rule(category="gas", rate=4, quote="Earn 4% cash back on gas.")
        result = self.run_card(FakeModel([rule(), made_up]))
        self.assertEqual(result["status"], "ok")
        self.assertEqual([r["category"] for r in result["rules"]], ["dining"])
        self.assertEqual(result["rules"][0]["evidence"], {"quote": rule()["quote"], "url": CARD["sourceUrl"], "pageHash": "hash1"})
        self.assertEqual(len(result["rejected"]), 1)
        self.assertIn("not on the page", result["rejected"][0]["reason"])
        self.assertEqual((result["model"], result["promptVersion"], result["pageHash"]), ("test-model", extract.PROMPT_VERSION, "hash1"))

    def test_conditions_are_kept_and_merged_across_chunks(self):
        with_condition = rule(category="groceries", quote=EXCLUSION, conditions=[EXCLUSION])
        without = rule(category="groceries", quote=EXCLUSION)
        result = self.run_card(FakeModel([without], [with_condition]), max_chars=150)
        grocery = [r for r in result["rules"] if r["category"] == "groceries"]
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
        reply = "```json\n" + json.dumps({"rules": [rule()]}) + "\n```"
        self.assertEqual(len(self.run_card(FakeModel(reply))["rules"]), 1)

    def test_wrong_shape_replies_are_failures(self):
        for reply in ('["x"]', '{"rules": "none"}', "{}"):
            self.assertEqual(self.run_card(FakeModel(reply))["status"], "failed", reply)


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

    def test_an_odd_reply_is_a_value_error(self):
        client, _ = self.client({"oops": 1})
        with self.assertRaises(ValueError):
            client.complete([])


if __name__ == "__main__":
    unittest.main()
