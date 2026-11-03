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


if __name__ == "__main__":
    unittest.main()
