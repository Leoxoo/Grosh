"""Reading a card page's quarterly bonus calendar into dated quarters, each with the names it lists.

Chase Freedom Flex's page (2026-11-01) lays its calendar out one item a line:

    OCT-DEC
    2026
    CURRENT Quarter
    Grocery Stores
    (excluding Walmart® and Target®)*Opens offer details overlay
    Dining
    American Red Cross®*Opens offer details overlay
    Activate starting September 15, 2026

and, further down, again as "Your 5% quarterly cash back 2026 calendar" / "July – September" / "Gas Stations | Public
Transit | ...". A model reading that as one run of text has to guess which names go with which quarter; the layout
says it, so no model is asked. extract.calendar_rules turns the quarters into dated rotating rules.

Discover's calendar (2026-11-03) says each quarter in one sentence instead:

    Earn 5% Cashback Bonus at Restaurants, Entertainment and Utilities, now to December 31, 2026, on up to $1,500 in purchases when you activate.
"""

import re
from dataclasses import dataclass

MONTHS = ("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
QUARTER_ENDS = {1: "03-31", 4: "06-30", 7: "09-30", 10: "12-31"}  # a quarter's first month, and its last day
_MONTH = r"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?"
# "OCT-DEC", "October – December", "Jan - Mar 2027": a line that is only a month range, maybe with its year.
_LABEL = re.compile(rf"^{_MONTH}\s*[-–—]\s*{_MONTH}(?:,?\s+(20\d\d))?$", re.I)
_YEAR = re.compile(r"^(20\d\d)$")
_CALENDAR_YEAR = re.compile(r"\b(20\d\d)\b.*\bcalendar\b|\bcalendar\b.*\b(20\d\d)\b", re.I)
_STATUS = re.compile(r"^(?:previous|current|next|this) quarter$", re.I)
# What ends a quarter's list: its activation line, "Coming Soon" (nothing named yet), or the next quarter.
_END = re.compile(r"^(?:activat|coming soon)", re.I)
_LINK = re.compile(r"\*?\s*Opens (?:offer details overlay|in a new window|overlay)\s*$", re.I)
MAX_LINES = 10  # a quarter's list is a few lines; past this it isn't a calendar
# "Earn ... at <names>, now to December 31, 2026, on up to ...": the running quarter says "now", the others its first day.
_SENTENCE = re.compile(rf"^Earn .+? at (.+?), (?:now|{_MONTH} \d{{1,2}}) to {_MONTH} (\d{{1,2}}), (20\d\d), on up to ", re.I)
_NAME_BREAK = re.compile(r",\s+and\s+|,\s+|\s+and\s+")


@dataclass(frozen=True)
class Quarter:
    start: str  # "2026-10-01"
    end: str  # "2026-12-31"
    names: tuple[str, ...]  # as the calendar lists them: "Grocery Stores", "Dining", "American Red Cross®"
    notes: tuple[str, ...]  # a line in brackets, with the name it is about: "Grocery Stores (excluding Walmart® and Target®)"
    quote: str  # the calendar's lines for the quarter, word for word


def _sentence_quarter(line: str) -> Quarter | None:
    """The quarter a line says in one sentence, or None if it says none, or dates that aren't a calendar quarter."""
    match = _SENTENCE.match(line)
    if not match:
        return None
    names, opened, closed, day, year = match.groups()
    last = MONTHS.index(closed.lower()[:3]) + 1
    first = last - 2
    if QUARTER_ENDS.get(first) != f"{last:02d}-{int(day):02d}" or (opened and MONTHS.index(opened.lower()[:3]) + 1 != first):
        return None
    return Quarter(f"{year}-{first:02d}-01", f"{year}-{QUARTER_ENDS[first]}", tuple(_NAME_BREAK.split(names)), (), line)


def read_calendar(text: str) -> list[Quarter]:
    """Every quarter a calendar on the page names something for, in page order, laid out one item a line or said
    in one sentence. A quarter with nothing named ("Coming Soon") and a month range that isn't a calendar quarter
    are left out, and so is a quarter whose year the page doesn't give: on its line, the line after, or a heading
    above ("2026 calendar")."""
    lines = [line.strip() for line in text.splitlines()]
    found: list[Quarter] = []
    heading_year = None
    for i, line in enumerate(lines):
        if match := _CALENDAR_YEAR.search(line):
            heading_year = int(match.group(1) or match.group(2))
        if quarter := _sentence_quarter(line):
            found.append(quarter)
            continue
        label = _LABEL.match(line)
        if not label:
            continue
        first, last = (MONTHS.index(label.group(n).lower()[:3]) + 1 for n in (1, 2))
        if first not in QUARTER_ENDS or last != first + 2:
            continue
        year, j = (int(label.group(3)) if label.group(3) else None), i + 1
        if year is None and j < len(lines) and _YEAR.match(lines[j]):
            year, j = int(lines[j]), j + 1
        year = year or heading_year
        if year is None:
            continue
        names: list[str] = []
        notes: list[str] = []
        last_line = j
        while j < len(lines) and j <= i + MAX_LINES and lines[j] and not _END.match(lines[j]) and not _LABEL.match(lines[j]):
            item = _LINK.sub("", lines[j]).strip()
            if item.startswith("(") and names:
                notes.append(f"{names[-1]} {item}")
            elif not _STATUS.match(item):
                names += [name.strip() for name in item.split("|") if name.strip()]
            j += 1
            last_line = j
        if names:
            found.append(Quarter(f"{year}-{first:02d}-01", f"{year}-{QUARTER_ENDS[first]}", tuple(names), tuple(notes),
                                 "\n".join(lines[i:last_line])))
    return found
