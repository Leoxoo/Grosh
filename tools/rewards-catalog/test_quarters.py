"""Offline tests for quarters.py: python3 -m unittest discover -s tools/rewards-catalog"""

import unittest

import quarters

# Chase Freedom Flex's page, 2026-11-01: a calendar of three quarters, then a second one for the year.
CHASE = """Turn every day purchases into cash back.
JUL-SEP
2026
prEVIOUS Quarter
Gas Stations
Public Transit
Activation period closed
OCT-DEC
2026
CURRENT Quarter
Grocery Stores
(excluding Walmart® and Target®)*Opens offer details overlay
Dining
American Red Cross®*Opens offer details overlay
Activate starting
September 15, 2026
APR-JUN
2027
Coming Soon
Activate starting March 15, 2027
QUARTERLY CALENDAR
Your 5% quarterly cash back 2026 calendar
January – March
Norwegian Cruise Line® | Dining | the American Heart Association®
Activation period closed
October – December
Coming Soon"""

# Discover's calendar data, 2026-11-03, as fetch.data_text saves it: one sentence says a quarter's names and dates.
DISCOVER = """You activated to earn 5% Cashback Bonus at Grocery Stores, Wholesale Clubs, and Select Streaming Services, PARENT_ENROLLMENT_DATE to March 31, 2026, on up to $1,500 in purchases.
Earn 5% Cashback Bonus at Grocery Stores, Wholesale Clubs, and Select Streaming Services, January 1 to March 31, 2026, on up to $1,500 in purchases.
Grocery Stores, Wholesale Clubs, and Select Streaming Services
Earn 5% Cashback Bonus at Restaurants and Home Improvement Stores, April 1 to June 30, 2026, on up to $1,500 in purchases.
Restaurants and Home Improvement Stores
FIRST TIME EVER: Earn 5% on Entertainment
You activated to earn 5% Cashback Bonus at Restaurants, Entertainment and Utilities, PARENT_ENROLLMENT_DATE to December 31, 2026, on up to $1,500 in purchases.
Earn 5% Cashback Bonus at Restaurants, Entertainment and Utilities, now to December 31, 2026, on up to $1,500 in purchases when you activate.
September 01, 2026
Restaurants, Entertainment and Utilities"""


class ReadCalendarTests(unittest.TestCase):
    def test_each_quarter_gets_its_dates_and_the_names_listed_under_it(self):
        found = [(q.start, q.end, q.names) for q in quarters.read_calendar(CHASE)]
        self.assertEqual(found, [
            ("2026-07-01", "2026-09-30", ("Gas Stations", "Public Transit")),
            ("2026-10-01", "2026-12-31", ("Grocery Stores", "Dining", "American Red Cross®")),
            ("2026-01-01", "2026-03-31", ("Norwegian Cruise Line®", "Dining", "the American Heart Association®")),
        ])  # "Coming Soon" names nothing, so April and the second October are left out

    def test_a_note_in_brackets_goes_with_the_name_above_it(self):
        october = quarters.read_calendar(CHASE)[1]
        self.assertEqual(october.notes, ("Grocery Stores (excluding Walmart® and Target®)",))

    def test_the_quote_is_the_calendars_own_lines(self):
        october = quarters.read_calendar(CHASE)[1]
        self.assertTrue(october.quote.startswith("OCT-DEC\n2026\nCURRENT Quarter\nGrocery Stores"))
        self.assertIn(october.quote, CHASE)

    def test_the_year_can_be_on_the_label_or_only_in_a_heading(self):
        self.assertEqual(quarters.read_calendar("Jan - Mar 2027\nGrocery Stores")[0].start, "2027-01-01")
        self.assertEqual(quarters.read_calendar("January – March\nDining"), [])  # no year anywhere: no date to give

    def test_a_month_range_that_is_not_a_quarter_is_not_a_calendar(self):
        self.assertEqual(quarters.read_calendar("2026 calendar\nJan - Dec\nDining\nFeb - Apr\nGas"), [])

    def test_a_sentence_can_say_a_quarters_names_and_dates_on_one_line(self):
        found = [(q.start, q.end, q.names) for q in quarters.read_calendar(DISCOVER)]
        self.assertEqual(found, [
            ("2026-01-01", "2026-03-31", ("Grocery Stores", "Wholesale Clubs", "Select Streaming Services")),
            ("2026-04-01", "2026-06-30", ("Restaurants", "Home Improvement Stores")),
            ("2026-10-01", "2026-12-31", ("Restaurants", "Entertainment", "Utilities")),  # "now to": its end says which quarter
        ])

    def test_the_quote_of_a_quarter_in_a_sentence_is_that_sentence(self):
        october = quarters.read_calendar(DISCOVER)[-1]
        self.assertEqual(october.quote, "Earn 5% Cashback Bonus at Restaurants, Entertainment and Utilities, "
                                        "now to December 31, 2026, on up to $1,500 in purchases when you activate.")
        self.assertIn(october.quote, DISCOVER.splitlines())

    def test_a_sentence_about_dates_that_are_not_a_quarter_is_not_a_calendar(self):
        promotion = "Earn 5% Cashback Bonus at Best Buy, November 25 to December 31, 2026, on up to $1,500 in purchases."
        self.assertEqual(quarters.read_calendar(promotion), [])
        self.assertEqual(quarters.read_calendar(promotion.replace("November 25", "now").replace("December 31", "December 24")), [])


class ComingSoonTests(unittest.TestCase):
    def test_a_quarter_marked_coming_soon_is_listed_with_its_dates(self):
        found = [(q.start, q.end, q.names) for q in quarters.coming_soon(CHASE)]
        self.assertEqual(found, [("2027-04-01", "2027-06-30", ())])  # the second calendar's October is named by the first

    def test_two_calendars_marking_a_quarter_coming_soon_list_it_once(self):
        text = "APR-JUN\n2027\nComing Soon\nYour 2027 calendar\nApril – June\nComing Soon"
        self.assertEqual([q.start for q in quarters.coming_soon(text)], ["2027-04-01"])

    def test_a_quarter_that_says_nothing_is_not_coming_soon(self):
        self.assertEqual(quarters.coming_soon("APR-JUN\n2027\nActivate starting March 15, 2027"), [])

    def test_a_status_line_before_coming_soon_is_not_a_name(self):
        self.assertEqual(len(quarters.coming_soon("JAN-MAR\n2027\nNEXT Quarter\nComing Soon")), 1)

    def test_no_year_no_quarter(self):
        self.assertEqual(quarters.coming_soon("April – June\nComing Soon"), [])


if __name__ == "__main__":
    unittest.main()
