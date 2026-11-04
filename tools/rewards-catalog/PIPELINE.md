# Rewards catalog pipeline

How Grosh gets credit card reward rules without a server, and keeps them current.

## Goal and non-goals

The app ships a **rewards catalog**: for each known card, its fee, its flat earn rate and its category rules (3% dining, 5% on rotating categories up to a cap...). Adding a Card in Grosh can start from a catalog entry.

- The catalog is built **offline**, in this repo, and shipped as one static JSON file. The app never scrapes (ADR 0001: no backend).
- Nothing reaches the app unreviewed. A script *proposes*; a person *accepts* each rule on the review page, and the decisions are committed and merged in a pull request.
- We ship facts we re-verified ourselves. We never ship card art or another site's compiled data.

## The shape of a run

```
seed ──► fetch ──► extract ──► validate ──► diff ──► review ──► publish
```

Each stage reads files and writes files, so any stage can be rerun alone and a failed run resumes where it stopped.

| Stage | Reads | Writes | Notes |
|---|---|---|---|
| **Seed** | CardPin CSV | `catalog-seed.json` | One-off. `build_seed.py`. Every card starts `verified: false`. |
| **Fetch** | each card's `sourceUrl`, and its `calendarUrl` if it has one | `fetch-state.json` (committed), `cache/<id>/latest.txt`, `previous.txt`, `calendar.txt` (not committed) | `fetch.py`, built. Details below. |
| **Extract** | cached text | `cache/candidates/<id>.json` (not committed) | `extract.py`, built, not yet run against a real model. Details below. |
| **Validate** | candidates | pass/fail per candidate | Deterministic checks, below. A failing candidate is dropped, never "fixed". |
| **Diff** | candidates vs. `catalog.json` | `report.md` | Classifies each card: unchanged, changed, new, page gone, extraction failed. |
| **Review** | candidates | `review-decisions.json` (committed) | `review.py` and each card's view on the page, built. Accept, reject or fix each rule; only accepted rules move on. Details below. |
| **Publish** | seed, candidates, `review-decisions.json` | `rewards-catalog.json` (committed) | `publish.py` and the **Publish catalog** button in the page's Run panel, built. Only accepted rules; versioned, sorted, byte-stable so the PR diff shows only real changes. Details below. |

## The fetch stage (`fetch.py`)

```
python3 tools/rewards-catalog/fetch.py [--issuer chase] [--only ID ...] [--limit N]
python3 -m unittest discover -s tools/rewards-catalog      # offline tests
```

- **Standard library only.** One page per distinct URL (cards that share a page, like the two Expedia cards, fetch once).
- **Hashes the visible text**, not the HTML, so a changed script bundle or tracking id isn't a change. `fetch-state.json` holds each card's hash and is committed, so a run on any machine knows what changed; the page text lives in `cache/`, which isn't.
- **A card can have a calendar page.** `calendar-pages.json` (`{card id: url}`) names a page of its own for a card's quarterly calendar; `build_seed.py` copies it to the card as `calendarUrl`. It is read right after the card's page (once per distinct URL, with no conditional request), saved as `cache/<id>/calendar.txt`, and hashed apart: `hash` stays the card page's and `calendarHash` is the calendar's, with `calendarUrl` and `calendarStatus` beside them. `fetch.pages_hash` joins the two, and that is what extraction compares, so a changed calendar makes the card `changed` and it extracts again, even when its own page is the same. A card with no calendar page has none of these fields and its `pages_hash` is its `hash`. A calendar that wasn't read keeps its last text and hash, and the card's outcome says why; the card's own status doesn't change.
- **A calendar page may be JSON.** Discover's page (`www.discover.com/credit-cards/cash-back/cashback-calendar.html`) has no calendar in its HTML, only a "not working" message that a script hides. The script builds the calendar from `card.discover.com/cardissuer/public/rewards/offer/v1/offer-categories`, so that is its `calendarUrl`. A `calendar` fetch accepts a JSON reply and saves its sentences (`data_text`, one a line); a card page that answers JSON is still "not a web page". The `offers.json` the page also names is old (2020–2021).
- **Polite:** identifies itself in the User-Agent, obeys robots.txt, waits one second between requests to a host, retries server errors and dropped connections twice with a growing delay, and sends `If-None-Match` / `If-Modified-Since` when it has a cached copy.
- **Each card ends in one status:**

  | Status | Meaning |
  |---|---|
  | `new`, `unchanged`, `changed` | Page read. `changed` says how many lines differ, to tell a rate change from page churn. |
  | `needs-browser` | Under 400 characters of text: a script builds the page, or a bot wall answered. |
  | `refused` | 401, 403 or 429. |
  | `robots` | robots.txt says no. |
  | `gone` | 404 or 410. |
  | `failed` | Network error, timeout, server error, or an unreadable robots.txt. |

- **Validators belong to a URL.** The saved ETag / Last-Modified are sent only back to the page they came from. When a card's `sourceUrl` changes, the new page is read in full (an earlier version asked the new URL "has it changed since the old page?" and got a false "not modified").
- **Failure never erases:** a card that didn't fetch keeps its last hash.
- **Exit code 1 only if more than 25% of cards are `failed` or `gone`.** `refused`, `robots` and `needs-browser` are expected outcomes to report, not signs that the run broke.
- Not built yet: a headless browser for `needs-browser` pages.

### One page at a time

Pages are fetched one at a time, never in parallel. Each card's result prints as it finishes, and `fetch-state.json` is saved after every page, so stopping a run loses nothing. Pick what to fetch:

```
fetch.py --only ID [ID ...]   # specific cards
fetch.py --issuer chase       # one issuer
fetch.py --missing            # never fetched, or saved text missing: resumes an interrupted run
fetch.py --retry              # last fetch failed or found the page gone
```

A card whose `sourceUrl` or `calendarUrl` changed since it was fetched is picked up by `--missing` and `--retry` too; `--missing` also picks up a card whose `calendar.txt` isn't saved, and `--retry` one whose calendar page failed. A wrong or moved page URL is fixed in `url-overrides.json` (`{card id: url}`); `build_seed.py` applies it, so rebuilding the seed keeps the fix.

### Fetch status after retries (2026-10-20, 166 cards)

| Result | Cards | Notes |
|---|---|---|
| Read | 138 | Real rate text, for example "Earn unlimited 3% cash back on food and fun". 9 of these come from embedded page data (below), marked `"embedded": true` in `fetch-state.json`. |
| `needs-browser` | 4 | The two Schwab-branded Amex cards ("unable to authorize your request") and the two Amazon cards (a "continue shopping" check page). Bot walls, so a browser is unlikely to help; use the issuers' own pages instead. |
| `failed` | 12 | Timeouts: the United cards (theexplorercard.com), E*TRADE (2 Morgan Stanley cards), PenFed (3), Air France. Retrying here didn't help; try `--retry` from your own network. |
| `refused` | 11 | LATAM, LifeMiles, Amtrak, Best Western, Virgin, Expedia. |
| `gone` | 1 | `barclays-carnival-world-mastercard`: **needs-info** (below). |

The 3 earlier `gone` pages (two TD, one Walmart) now fetch from corrected URLs.

**Needs a decision from you (needs-info, #158), checked 2026-11-01.** Both cards are marked in `needs-info.json` (`{card id: what is needed}`), which `build_seed.py` applies as a `needsInfo` field on the seed card; the web page shows it as a "needs info" chip in the card list and the text at the top of the card. #158 offers needs-info only for Carnival; Green is marked the same way because no page the fetcher can read states its rates, and the ticket is where you decide.

- `barclays-carnival-world-mastercard`: the card no longer exists. Barclays replaced it with the Carnival Rewards Mastercard on September 1, 2026 and moved its cardholders over (FunPoints became Carnival Rewards points), as reported by card-news sites; Barclays' own FAQ wasn't found. The old page is a 404. The new card's page (`https://cards.barclaycardus.com/banking/cards/carnival-rewards-mastercard/`) fetches and states its rates (up to 6x on Carnival, 2x restaurants and groceries, 1x everything else), but it is a different card with different rates and never names the old one, so swapping its URL in would fail "the page names the card". Decide whether to mark this card `discontinued` (the seed has no override for that yet) or replace it with the Carnival Rewards Mastercard (a new id).
- `american-express-green`: closed to new applicants in July 2026 and renamed the American Express Classic Green Card in August; Amex took down its card page, and `.../card/green/` now redirects to the generic card listing. Its own pages that are left don't give the fetcher its rates: the referral page (`https://www.americanexpress.com/en-us/referral/personal/american-express-green-card`) is read as `ok` and names the card, but its 3X rates are only in its page data, which `fetch.py` reads only for thin pages (this page has a "10% back" line on its visible text, so a "no rate in the text" rule wouldn't catch it either); the cardmember benefits page (`https://global.americanexpress.com/card-benefits/view-all/amex-green`) is a browser-built `needs-browser` page that shows the rates only behind a click. The URL is left as it was.

`american-express-rakuten` now uses the card's own page, `https://rakuten.imprint.co/`. Imprint runs the card and First Electronic Bank issues it under an American Express license; Amex has no page for it. That page states the rates: an extra 4% on Rakuten purchases up to $10,000 a year, 10% on Rakuten dining, 2% on groceries and restaurants, 1% on everything else. The seed lists it as a business card, but it's a personal card (not changed: the seed has no override for that). The Walmart OnePay card uses OnePay's help article, not a Synchrony or Walmart product page. Amex Everyday's URL pointed at a sign-in "Benefits Dashboard" and now uses its card page.

### Pages built in the browser: embedded data, not a browser

Many issuer pages ship almost no visible text, but carry their sentences (and rates) as data inside the HTML. When a page's visible text is under 400 characters, `fetch.py` also reads:

- `<meta>` descriptions (`description`, `og:description`, `twitter:description`);
- JSON script tags (`application/json`, `application/ld+json`, such as Next.js's `__NEXT_DATA__`);
- JSON a script assigns to `window` (`window.X = {...}`), including JSON held inside a string, as Amex's `__INITIAL_STATE__` does.

Only prose is kept: strings of two or more words that read as sentences, once each, up to 200,000 characters. This recovered AAA, Alaska Atmos and four Amex pages without a browser, in standard-library Python.

Limits to know before the extract stage:

- **Mixed content.** Amex's state holds marketing for many cards, so a card's page can contain other cards' rates. Extraction must keep only this card's rules, which is why "the page names the card" is a validation check and a quote that is another card's is rejected (check 13 of the extract stage).
- **Wrong pages still read as "ok".** The embedded text of `american-express-green` is Amex's generic card listing (its page redirects there; see needs-info above). `american-express-rakuten` used to be the Rakuten shopping site's labels and now uses the card's own page. A fetch that ends on a different page than it asked for should be flagged; not built yet.
- **Hashes are noisier.** A page that flips between thin and full text changes its hash, and embedded data can include build ids. `changed` reports how many lines differ, to tell churn from a rate change.
- **A headless browser** is now only worth building for what this can't reach. Nothing is left that clearly needs one: the 4 `needs-browser` pages are bot walls.

### First full run (2026-10-20, 166 cards)

| Result | Cards | Notes |
|---|---|---|
| Read | 112 | Pages include real rate text (for example "Earn unlimited 3% cash back on food and fun"). |
| `failed` | 27 | Timeouts, connections closed without a reply, and truncated bodies. About 10 more were this sandbox refusing hosts it didn't list, which won't happen on your Mac. |
| `needs-browser` | 13 | Alaska, AAA, American Express (some pages), Schwab, Rakuten, U.S. Bank SkyPass. |
| `refused` | 11 | LATAM, Amtrak, Best Western, Expedia, LifeMiles, Virgin. |
| `gone` | 3 | Two TD and one Walmart page moved: their `sourceUrl` needs fixing by hand. |

- Asking for gzip made 10 issuers' pages arrive cut off mid-stream; asking for uncompressed pages fixed 9 of them, so the fetcher does that.
- The failed, refused and needs-browser pages are the work left for fetching: retry later, find a better URL, or add a headless browser. The extract stage can start on the 112 pages that read fine.

## The extract stage (`extract.py`)

```
python3 tools/rewards-catalog/extract.py --only capital-one-savor     # one card
python3 tools/rewards-catalog/extract.py --issuer "capital one"       # one issuer
python3 tools/rewards-catalog/extract.py                              # every fetched page
```

Start the model server first (for LM Studio: Developer tab, Start Server, model loaded). Settings come from what the web page last saved, and flags override them: `--base-url`, `--model`, `--max-tokens`, `--timeout`, `--extra-body`, `--prompt-suffix`, `--response-mode`, `--token-field`, `--temperature`; the key comes from `LLM_API_KEY` or the saved settings. The script checks the server answers, accepts the key, and lists the model before it starts (only when a card needs the model).

For each card it splits the cached page text into chunks of about 12,000 characters (repeating three lines between chunks) and asks the model only about chunks that contain something rate-shaped (`3%`, `2X`, "per $1"). A chunk over 1,500 characters that the model answers with no rules at all is asked again in pieces of about 1,500 characters: qwen/qwen3.8-27b answered Blue Cash Everyday's whole 5,151-character rates section with an empty list in 3 seconds (2026-11-01) and its first 24 lines with 4 rules. That is 5 more calls on that page; a long chunk that really states no rule costs its pieces too. It writes `cache/candidates/<id>.json`: the accepted `rules`, the `rejected` proposals with the reason each failed, and the model id, prompt version and page hash. A card whose page, model and prompt are unchanged is skipped; `--force` redoes it.

**Statuses:** `ok`; `no-rules` (the page states no rate for the card); `wrong-page` (the page doesn't name the card, so the model isn't asked at all); `failed` (the model's reply couldn't be read after one retry, so the result is incomplete and isn't treated as done).

**Checks on every proposed rule** (`validate_rule`, none of which trusts the model):

1. every category is in the catalog list, unit is `percent` or `per-dollar`, the rate is a number above 0 and up to 10;
2. the quote appears on the page word for word (ignoring case, spacing, curly quotes and ®/™ marks), and is at most 600 characters: the sentence that states the rate (or two, a base rate and its boost), not the page around it. Hand-entered rules too: Customized Cash's used to quote 2,135 characters, from the page's title through its menu;
3. the rate appears in the quote as a whole number (13% is not 3%), and the quote has a `%` for percent or points, miles or X for per-dollar;
4. the quote uses a word for its category (for example "grocer", "restaurant", "all other"), which catches a rate filed under the wrong category. Brand names are not category words (a rate "on Lyft rides" is one company's promotion, not a transit rate). A base rate (`everything-else`) may leave out "all other" if the quote names no other category (Apple Card's "Get 2% Daily Cash back when you use Apple Card with Apple Pay"), but never if the quote talks about a quarter, activating, enrolling, rotating or "different places": that's a rotating bonus, not the base;
5. a cap needs an amount and a period, and both appear in the quote (`$6,000`, `6K` and `6000` match; "year" or "annual"; `cycle` is a "billing cycle");
6. every **condition** (an exclusion or restriction on the rate, such as "excluding superstores like Walmart® and Target®") is the page's own sentence, word for word. Conditions are never paraphrased, so what a person sees is what the issuer wrote. A rule with a condition that isn't on the page is rejected whole, since showing the rate without its restriction would overstate it;
7. a rule where the cardholder chooses or the card picks (`selection` of `choose` or `top-spend`) needs a quote that says so ("of your choice", "top eligible category"), and every category it lists must be mentioned on the page;
8. a `requires` tag (`apple-pay`, `activation`, `issuer-booking`, `preferred-rewards-tier`) is accepted only if the quote or a condition has words that back it ("Apple Pay", "activate", "booked through", "Preferred Rewards" or a table row's "75% rewards bonus"), and a `tier` only if they name it ("Platinum Honors");
9. `validFrom` / `validTo` are accepted only if the quote or a condition gives that date's month and year, so a period can't be made up.
10. `firstMonths` (a rate only for the first N months after opening, such as a first-year bonus) is accepted only if the quote or a condition says "first year", "first 12 months" or similar for that length;
11. a `rotating` rule's quote must say the categories change ("quarter", "rotating", "bonus categories", "different places"), and any category it does name must be in the quote;
12. a **tier boost** (Bank of America's "up to 75% more", which turns 1.5 points into 2.62 at Platinum Honors) must be labelled as one, `requires: ["preferred-rewards-tier"]`, or it is rejected: it is never a base rate. A rate is a boost when the sentence of the quote that states it talks of Preferred Rewards, a rewards bonus or an Honors tier (not "plus any Preferred Rewards tiered bonus", which is the base rate naming the boost on top, and not a card named "Sapphire Preferred"), or when the quote is a cell of a tier table's row ("Platinum Honors", "75% rewards bonus", ..., "2.62 points on All other purchases"; the "No rewards bonus" row is the base). A cell broken across two lines, as in the calculator's "2.62 points" / "per $1 spent on all other purchases", is read as one cell, the same way a sentence broken across lines is. A base rate is judged on its own sentence, so "Earn unlimited 1.5 points ... Or, enroll in Preferred Rewards ... 2.62 points" keeps its 1.5.
13. the quote is **this card's**, not another card's on the same page (`CardPage`, below).

**Other cards on the same page.** Discover's page lists ten "Discover it" cards, each under its own heading, and the same sentence often sits under several of them ("Earn 5% ... when you activate" under Cash Back, Student, Secured and NHL; "Earn 1.5x miles ..." only under the two Miles cards). Card names are read from the page: the capitalized words just before "Card" ("Discover it Miles Credit Card"), compared by their distinctive words (the issuer's name and words every card uses, such as "Credit", "Cash Back" or "Visa Signature", don't count). A name is **this card's** if it adds no word to the card's name ("Discover it Cash Back" for Discover It) or adds words only in front of it ("Air Canada Aeroplan" for Aeroplan); **another card's** if it shares a word with this card or its issuer and is neither this card's nor a shorter form of one of the page's names for it ("IHG One Rewards" is a short form of "IHG One Rewards Traveler", "Discover it Miles" is another card). A rule is rejected when:

- its quote names another card ("... with the Discover it Miles Card"), wherever it sits; or
- every place the quote sits under a heading, that heading is another card's. A heading is a short line with no numbers that ends with a card's name, and it covers the 12 lines below it (or up to the next heading), so a footer isn't part of the last card's section. A place under no heading says nothing either way; one place under this card's heading keeps the rule. A footnote ("Footnote 2:" and the two lines after it) sits where its marker does: the lines that end in " 2". Discover's footnote 2, "You will earn 2% cash back on your first $1000 in combined purchases at gas stations ... and restaurants", is marked only in the Chrome cards' sections, so it is Chrome's. Other footnote styles (‡, superscripts) aren't followed yet.
- its rate is in the unit this card's page doesn't use for its own rates: a percent on a points or miles card, or points, miles or X on a cash-back card, when at least two thirds of the page's rate sentences that use one unit use the card's own (the seed's `rewardKind`). Bank of America's Business Advantage Travel Rewards page (points) carries a calculator for all three Business Advantage cards under no heading the checks can read, and its "Earn 2.00% on dining purchases." is Customized Cash's. The seed's kind alone can't decide it: Chase's points cards say "5% cash back" and Citi's cash-back cards "5 points per $1", and on those pages the other unit is the majority, so the rule says nothing. A quote under another card's heading is reported as that, first. On the cached pages (2026-11-01) this marks 136 more of 2,317 rate sentences, on 8 pages: Amex's card lists (Blue Cash rates on the Everyday and Green pages), the three Business Advantage cards' calculators, and points restatements of a percent the page also gives (U.S. Bank Smartly's "2 Points for every $1", Chase Ink Premier's "tracked as points"), where no rate is lost.

A page that never names the card more exactly than its family (Barclays only ever says "Breeze Easy Visa"; the catalog calls it "Breeze") can't say which of its cards is this one, so nothing is rejected on it for this reason. Rate sentences that are another card's are also left out of the follow-up questions and the "rate sentences aren't in the result" warning. On the cached pages (2026-11-01), 135 of 1,894 rate lines are another card's, all on pages that describe several cards (Amex's card lists, the Hilton, Wyndham, AAA and AAdvantage families, Citi's comparison tables, Discover). On Discover's page that includes Discover it Chrome's "2% cash back at gas stations and restaurants", which `bench/expected.json` had listed for Discover It (the Cash Back card) and no longer does.

A rule that fails any check is listed as rejected, never edited. Before the checks, a few relabelings that change nothing about what the page says are applied: a rotating bonus the model filed as "top-spend", "choose" or the base rate is retyped as `rotating` (only when the quote says the categories change, such as "bonus categories" or "different places you shop each quarter", and not who picks them; "each quarter" alone, as in a cap, doesn't count); and the same rule found twice (the model words a quote a little differently in each part of a page) is kept once, with its conditions and requirements combined. One tidy-up happens before the checks: a `fixed` rule that lists several categories (the model likes "3% on dining, groceries and streaming") becomes one rule per category with the same quote, each checked on its own, and each keeps only the conditions that are about it or name no category. **Card-wide conditions** (`cardConditions`: sentences that limit several of a card's rates, such as Capital One's note that digital wallets may not earn the higher rate) must also be on the page word for word; one that isn't is dropped and listed under `rejected`, and the card's rules are kept.

### What "accepted" and "rejected" mean

**Accepted means supported, not true.** The checks prove a rule is well-formed and grounded in the page: the quote is on the page word for word, the numbers and words it relies on are in that quote, and its category, cap, dates and requirements are things the quote says. They cannot prove the model read the page correctly, so every accepted rule still needs a person to look at it before it ships (the review stage). What they are good at is stopping the model from inventing things: a rate that isn't in its quote, a quote it made up, a category the sentence doesn't mention, a cap or date it guessed.

**Rejected means the model proposed something the page doesn't back.** Each rejection is kept with its reason, which is how the page tells you what the model got wrong. On Chase Freedom Flex, the first full read produced:

| Model proposed | Verdict | Why |
|---|---|---|
| 3% dining, 3% drugstores, 1% on all other purchases, 5% on travel through Chase Travel | accepted | each quote is on the page and says what the rule says |
| 5% "in that quarter's bonus categories", filed under dining, then gas, then travel, then transit, then online shopping | all five rejected | the sentence names none of those categories, so no single category is backed (it is a rotating rule) |
| 1.5% on everything else | rejected | 1.5 is not in the quote it gave |
| A "see chase.com/RewardsCategoryFAQs" sentence as a card-wide condition | rejected | not on the page word for word (the page has extra text after it) |
| 2% on transit, "on Lyft rides... through September 30, 2027" | **accepted, wrongly** | the quote is real and the model's reading was wrong: it is one company's promotion. Fixed by dropping brand names from the category words. |

**Where a wrong reading can still get through**, and what is done about it:

- A quote that really is on the page but means something else (the Lyft case). Each such hole gets a check once it is seen; the brand-name and base-rate checks above came from this.
- Two accepted rules that contradict each other. These are **flagged, not removed**: a card whose rules show two rates for the same thing with nothing to tell them apart (two base rates, say) gets a `warnings` entry, shown on the page as "check: N things to look at". Every rate is on the page, but they can't all be right.
- A card where every rate on the page was found but the base rate was not. That is flagged too ("no rate for all other purchases was found"), since the model sometimes skips a plain "1% on all other purchases" sentence.
- Rules for a different card on a shared page, where the page doesn't make it plain: a quote under no card's heading, or a page that never names the card exactly. Rules that sit under another card's heading, name another card, or state their rate in the unit the card's page doesn't use for its own are rejected (check 13).
- Conditions attached to the wrong rate. A script can't check that; it is for the reviewer.
- A rate the page states that the result doesn't have. After the chunks, each **rate sentence** (a percent or X next to "earn", "cash back", "points" or "miles") that the result doesn't cover is sent to the model on its own (up to 6), the longest first and each checked again just before it is sent, and any still not covered is flagged: "N rate sentence(s) on the page aren't in the result, e.g. ...". A sentence is covered when an accepted rule quotes it, or when the result gives a rate it states to every category it names, since pages state each rate several times (a heading, the sentence under it, an FAQ) and a rule keeps one quote. A heading cut short that names no category ("3% Cash Back at U.S.") is covered by any rule at its rate. The longest go first because a sentence carries the cap its heading leaves out: on Blue Cash Everyday (2026-11-01) the model returned nothing for the chunk, and asked in page order the six follow-ups went to the 3% headings and sentences, a heading gave a second gas rule with no cap, and the 1% base rate was never asked about. Once the sentences are rules, their headings are covered and cost nothing. A tier table's boost cell ("1.87 points on All other purchases" in the Gold row) and an "up to 75% more" sentence are neither sent nor flagged: read alone, a cell has lost the row that makes it a boost, and "75% more" is the size of a boost, not a rate. Sentences end at a full stop, even one followed by footnote marks ("(then 1%).‡"), but not after an abbreviation like "U.S." ("3% Cash Back on gas at U.S. Gas Stations" is one heading), and at the end of a line unless the next line starts in lower case, so a menu or heading doesn't run into the sentence after it.

**Blue Cash Everyday, confirmed (#160).** qwen/qwen3.8-27b, prompt version 8, page fetched 2026-11-01: one call, 56 seconds, 4 rules, nothing rejected, no warnings. It found 3% at U.S. supermarkets, on U.S. online retail purchases and at U.S. gas stations (each capped at $6,000 a year) and 1% on other eligible purchases, every quote from the page's "Rewards" section. The old warning reported headings as missing rates: the page's text runs menus, tiles ("3%" / "CASH BACK" / "On Groceries") and headings into the next sentence, and on this result it would have flagged 6 such run-ons and FAQ restatements. The card is in `bench/expected.json`.

### Odd earning rules

| Case | How a rule says it |
|---|---|
| Needs a way of paying (Apple Card's 2% with Apple Pay) | `requires: ["apple-pay"]` |
| Needs activation or booking through the issuer | `requires: ["activation"]` or `["issuer-booking"]` |
| The cardholder picks the categories (Bank of America Customized Cash) | `selection: "choose"`, the eligible `categories`, `picks`, and `hasOtherChoices: true` if the page lists choices outside the catalog list |
| The card applies the rate to the top-spend category (Citi Custom Cash) | `selection: "top-spend"`, same fields |
| Bonus categories the issuer changes every quarter (Discover, Chase Freedom Flex) | `selection: "rotating"`, `categories: []` (the page rarely names them), the rate, the cap, and `requires: ["activation"]` where the page says to activate. If a page names this period's categories with dates, they go in `categories` with `validFrom` / `validTo`. |
| A rate for a stated period | `validFrom` / `validTo` |

| A higher rate for a banking relationship tier (Bank of America Preferred Rewards: 2.62 points at Platinum Honors where everyone else earns 1.5) | its own rule beside the base rate, with `requires: ["preferred-rewards-tier"]` and `tier` (`gold`, `platinum`, `platinum-honors`, `diamond-honors`) when the page names it; null when it doesn't |

Not handled: caps shared between categories, and rates at one named store (the catalog skips those). The page's own sentence about them can still ride along in `conditions`.

### Questions only the cardholder can answer

Some things about a rule depend on the person, not the card. The catalog doesn't guess them; each rule lists what it `needs`, and the app asks (a Settings screen or the card editor, still to be designed). `needs` is **worked out from the rule**, never taken from the model, and each card's candidate carries the union as `needs`.

| Question id | A rule needs it when | What the app asks |
|---|---|---|
| `choice-categories` | `selection` is `choose` | Which category did you choose on this card? |
| `account-opened` | `firstMonths` is set (a first-year rate) | When did you open this card? |
| `pays-with-apple-pay` | `requires` has `apple-pay` | Do you usually pay with Apple Pay? |
| `preferred-rewards-tier` | `requires` has `preferred-rewards-tier` | Which Bank of America Preferred Rewards tier are you in? |

`top-spend` rules (Citi Custom Cash) need no answer, because Grosh can work out the top category from the user's own expenses in the statement period. A tier boost is not the base rate, so a card with only boosts for all other purchases still gets the "no rate for all other purchases" warning, and a boost beside the base is not "two rates with nothing to tell them apart". Bank of America's first-year 6% is supported by the schema (`firstMonths: 12`) but **not entered**: none of the pages we have states it, so there's no quote to take.

### Hand-entered cards and rules

- `removed-cards.json` (`{card id: why}`) leaves cards out of the seed: the Morgan Stanley and Schwab versions of Blue Cash Preferred and Platinum, since the cards they copy are already in it. `build_seed.py` stops on an id that isn't in the CSV.
- `extra-cards.json` adds cards CardPin lacks (Apple Card so far) to the seed; `build_seed.py` merges them, gives each the same id scheme as every card, and stops on a missing field or an id clash.
- `needs-info.json` (`{card id: what is needed}`) marks cards waiting on a person's decision (Carnival World and Green, above): `build_seed.py` copies the text into the card's `needsInfo` field and stops on an id that isn't in the CSV. The committed seed was marked by applying the file directly, since the CSV isn't committed; a test checks the two agree.
- `manual-rules.json` (`{card id: {rules: [...], cardConditions: [...]}}`) holds rules a person writes in the same shape as the model's. They run through the same checks without needing the page, and `extract.py` needs no LM Studio for them. A rule whose quote is found on the cached page is `verified: "page"`; one the page can't confirm (no page, or the page says something else) is `verified: "manual"` and should be re-checked at review. Apple Card's two rules are in there, both `"page"`.
- **Citi Custom Cash and Bank of America Customized Cash are entered**, from pages that state their rules: Citi's featured-cards page (its own card page now says Citi stopped accepting applications on May 28, 2026, so the FAQ on `citi.com/usc/Multi/Featured/default.htm` is the page that still has the rules) and Bank of America's "Categories & Exclusions" page. Citi's 5% is a `top-spend` rule over seven catalog categories with a $500 cap per billing cycle (`capPeriod: "cycle"`) and `hasOtherChoices` for home improvement, fitness clubs and live entertainment. Bank of America's 3% is a `choose` rule (gas, online shopping, dining, travel, drug stores; home improvement is outside the list) with a $2,500 combined quarterly cap, next to a 2% grocery rule and a 1% base rate. Its card-wide condition ("Merchants, not Bank of America, categorize and submit purchases ...") and the online-shopping exclusion are the page's own sentences. All were checked against the cached pages: `verified: "page"`.
- Citi Custom Cash is **closed to new applicants** but still held by existing cardholders, so it stays in the catalog. There's no field for "closed to new applicants" yet.
- Not entered: Bank of America's Preferred Rewards boost on Customized Cash (up to 5.25% on the choice category; the schema has it now, but the card's cached page doesn't state it, so there's no quote), Citi's extra 4% on Citi Travel bookings, and Bank of America's first-year 6% offer. Pages disagree on the last one, so it needs a decision before it goes in.

**What I measured on the 138 fetched pages, without a model:** 8 are `wrong-page` (for example `u-s-bank-business-leverage`, `wells-fargo-attune`), 130 would be sent to the model, and that takes about 339 model calls: 50 pages need one call, 32 need two, and the three big Amex pages need 18 each. With a 7B model on a Mac expect a full run to take on the order of an hour or more; it can be stopped and resumed, since each card is saved as it finishes.

**Not done, and worth knowing:**

- **Run against the real model on Capital One Savor.** With `k2-horizon-7b-uno-uncensored` and settings that switch its reasoning off, it takes about 12 seconds and returns the 5% travel rule (tagged `issuer-booking`), the 1% base rate, the 3% rules for dining, groceries and streaming (the superstore exclusion on groceries only), and the digital-wallet sentence as a card-wide condition. One card is not a benchmark: run a few more issuers before trusting the numbers.
- **Mixed pages.** Amex pages hold other cards' marketing. The prompt tells the model to take only this card's rates, and a quote under another card's heading or naming another card is rejected (check 13), but a quote the page doesn't place under any card's heading still passes. Review Amex candidates by hand.
- **Conditions come from the same chunk as the rate.** A footnote far from its headline, in another 12,000-character chunk, is missed, and the rule looks unrestricted. A second pass that hunts for footnotes is the fix if this shows up in real runs. Whether a condition really belongs to the rate, and not to a neighbouring one, can't be checked automatically; that's for the reviewer.
- **Rotating categories** (Discover 5%, Freedom Flex) carry `validFrom` / `validTo`, but only when the page names the months and the year. Pages that say "this quarter" give the extractor nothing to date.
- **Quarterly calendars are read, not asked about.** After the model's rules, `quarters.read_calendar` reads a calendar laid out one item a line (a month range such as "OCT-DEC" or "October – December", its year on the next line or in a heading such as "Your 5% quarterly cash back 2026 calendar", then the quarter's names, one a line or split by "|", up to its "Activate ..." line), or a quarter said in one sentence ("Earn 5% Cashback Bonus at Restaurants, Entertainment and Utilities, now to December 31, 2026, on up to $1,500 in purchases when you activate."; its end date says which quarter, and dates that aren't a whole quarter are left out). A card with a calendar page is read from that page instead of its own, and the rule's evidence points there. For each quarter that names something and hasn't ended, the card's undated rotating rule gets a copy with that quarter's dates (`validFrom` / `validTo`) and categories (`extract.calendar_rules`): the rate, cap, activation and conditions are the rotating rule's, plus a bracketed note under a name ("Grocery Stores (excluding Walmart® and Target®)"). A name that is no category (American Red Cross®, Amazon: brands aren't category words) goes in `merchants`. Its quote is the calendar's own lines, which usually name no rate, so it is marked `verified: "calendar"`, the quote checks don't apply, and it can be accepted or rejected but not fixed. A quarter listed two ways (two calendars on one page that disagree) is a card warning. No model is asked: the layout says which names go with which quarter, which a model reading the run of text has to guess. On Freedom Flex (2026-11-02) this gives Oct–Dec 2026 (groceries, dining, also American Red Cross®) and Jan–Mar 2027 (groceries, streaming); the page's second, older calendar says "Coming Soon" for October, which names nothing. Discover's calendar is a page of its own; on the reply of 2026-11-03 this gives Discover It Oct–Dec 2026 (dining, entertainment, utilities). It names no 2027 quarter yet, and the $1,500 cap in its sentence isn't read: the rate and cap are still the rotating rule's.
- **Chunks with no rate in them aren't sent**, so a footnote-only chunk holding a card-wide condition can be skipped on big pages.
- **Category words** are a guess at what a quote about a category says. Valid rules the list misses show up in `rejected` as "quote doesn't mention ...", and the fix is to add the word to `CATEGORIES`.

## The review stage (`review.py`)

Passing the checks means a rule is supported by its page, not that it is right, so every rule waits for a person. Clicking a card on the page opens its view. **In the app** shows the card as the app will use it: one line per rate, best first and the base rate last, with its cap and requirements in plain words, the app's default categories each rate covers (`APP_CATEGORIES`), and what the app will ask the cardholder; accepted rules are what gets published, waiting ones are faded and rejected ones left out. Below it, **Review** lists each rule (model-read and hand-entered alike) with what it says, its quote, its source URL, its conditions and its warnings. **Accept**, **Reject**, **Fix…** and **Undo** are saved per rule as soon as they're clicked. The cards table counts each card's rules still waiting, and can show only those cards.

- **Fixing a rule.** **Fix…** changes its categories, rate, unit, cap, requirements or tier (`review.EDITABLE`), never its quote: the quote is the evidence. The fixed rule must pass the same checks against the saved page as a proposal (a hand-entered rule the page doesn't confirm is checked as it was entered), or nothing is saved and the reason is shown. A fix is saved whole under `edited` in the rule's decision and counts as accepted; publishing takes it in place of the extracted rule. Accept or Undo drops the fix.
- **Bonuses add up** is a switch on each card's view, off for every card until a person turns it on (`card-options.json`, committed: `{card id: {bonusesStack: true, setAt}}`; `review.CARD_OPTIONS`). On, the app gives a purchase the base rate plus what every bonus covering it adds over the base, instead of the best single rate. Freedom Flex's terms say each bonus is "additional ... on top of the 1%", so in a quarter whose categories include dining, dining earns 1% + 4% (the quarter) + 2% (dining) = 7%. Pages rarely say outright that two bonuses combine, so a person decides; the view lists the page's sentences that say a bonus is on top of the base (`extract.stacking_quotes`) and, with the switch on, each place a quarter's bonus meets a category's bonus, with its total. The switch changes no rule.
- **Hand-entered cards never ask the model.** Their rules come from `manual-rules.json`, so "extract" only re-checks them against the page; the button says so. Take a card out of `manual-rules.json` to have the model read its page.

- **Warnings.** A rule's own: hand-entered and not confirmed by the saved page (`verified: "manual"`), read from the quarterly calendar (`verified: "calendar"`), or a cap the page mentions without an amount (`capUnknown`). The card's warnings from the extract stage (two rates for one thing, no base rate, rate sentences the result missed) are about its rules taken together, so they are shown above the card's rules.
- **Hand-entered rules are reviewed too.** `manual-rules.json` is a person's reading of a page, which is not the same as a second person checking it.
- **Where decisions live.** `review-decisions.json`, next to this file and committed (`cache/` isn't): `{card id: {rule key: {decision, decidedAt, rule, quote, edited?}}}`. `rule` and `quote` are there so a pull request's diff reads as "accepted 3% on dining", not a hash.
- **The key is the exact rule.** It is a hash of the card id and everything the rule says: rate, unit, categories, selection, cap, dates, `firstMonths`, tier, requirements, conditions, the quote, the source URL, and whether the page confirmed it. A re-extraction that changes any of that makes a new rule, which waits for review; it never inherits the old accept. Left out: the page's hash (a page whose menus churned but whose rule is the same keeps its decision), the derived `needs`, the order of lists, and 3 vs 3.0. The same rule on two cards that share a page is reviewed once per card.
- **Old decisions stay.** A decision whose rule is gone from the candidate is kept and does nothing; if a later extraction brings back that exact rule, its decision applies again.
- **What moves on.** `review.accepted_rules(candidate)` returns only the candidate's rules a person accepted, in the candidate's order. Rejected rules and rules still waiting are left out. The publish step (#162) builds the catalog from this and nothing else.
- Not reviewed: card-wide conditions (`cardConditions`). They are the issuer's sentences, checked word for word against the page, and are shown on the panel for reading only.

## The publish stage (`publish.py`)

```
python3 tools/rewards-catalog/publish.py        # or Publish catalog in the page's Run panel
```

Reads `catalog-seed.json`, `cache/candidates/`, `review-decisions.json` and `card-options.json`, and writes `rewards-catalog.json` beside this file: the one file the app bundles (#163). It is committed, so a pull request shows exactly which rules ship.

- **Only accepted rules** (`review.accepted_rules`). Rejected rules and rules still waiting are left out.
- **A card with no accepted rule is left out**, not listed with an empty rule list. Its facts are CardPin's and nobody has checked them, and we ship only what we re-verified. So every card in the file is verified, `verified` isn't written, and `verifiedAt` is the latest day one of its rules was accepted. No decisions exist yet, so the file would hold no cards; it isn't committed until it has some.
- **The shape**, one card shown (every key is always there, `null` when it doesn't apply, so a Swift `Codable` reader needs only optionals; dates are `YYYY-MM-DD` strings):

  ```json
  {
    "formatVersion": 1,
    "publishedAt": "2026-11-01",
    "cards": [
      {
        "id": "capital-one-savor", "name": "Savor", "issuer": "Capital One", "network": "Visa",
        "isBusiness": false, "annualFee": 0, "rewardKind": "cashback", "rewardProgram": null, "baseEarnRate": 1,
        "discontinued": false, "sourceUrl": "https://www.capitalone.com/credit-cards/savor/",
        "verifiedAt": "2026-11-01",
        "cardConditions": ["..."], "bonusesStack": false,
        "rules": [
          {
            "categories": ["dining"], "selection": "fixed", "picks": null, "hasOtherChoices": false,
            "rate": 3, "unit": "percent", "capAmount": null, "capPeriod": null, "capUnknown": false,
            "requires": [], "validFrom": null, "validTo": null, "firstMonths": null, "tier": null,
            "needs": [], "conditions": [], "merchants": [],
            "evidence": {"quote": "Earn unlimited 3% cash back on dining ...", "url": "https://www.capitalone.com/credit-cards/savor/"}
          }
        ]
      }
    ]
  }
  ```

  The file itself has its keys in alphabetical order. `bonusesStack` is the card's switch (above): when it is true, a purchase earns the base rate plus what each matching rule adds over it (a dated quarter's rule matches only between its `validFrom` and `validTo`); when false, the best single rate. `merchants` is only filled on a quarter read from a calendar. `baseEarnRate` is the seed's, unchecked; where a card has an accepted rule for `everything-else`, that rule is the checked one.
- **Left out**, because only the checks and the review needed them: the page's hash, a rule's `verified` (`page`, `manual` or `calendar`), the seed's `sourceHost` and `verified`, and the candidate's model, prompt version, warnings, rejections and costs.
- **Stable.** Cards in id order, rules in a fixed order, a rule's categories, requirements, needs and conditions sorted (they are sets), 3.0 written as 3, keys sorted, two-space indents. `publishedAt` changes only when the cards do, so publishing again with nothing new leaves the file byte for byte the same.
- **`formatVersion`** goes up only for a change an older app can't read (a field renamed or retyped). Adding a field doesn't need it.
- **Failure never deletes.** `cache/` isn't committed, so a fresh clone has no candidates: a card with no candidate keeps the entry it was last published with. A card gone from the seed leaves the file.
- **Not handled:** a card re-extracted with changed rules publishes only the rules still accepted, so its new rules are missing from the file until someone reviews them. Publish after reviewing, not between extracting and reviewing.

## The web page (`ui.py`)

```
python3 tools/rewards-catalog/ui.py        # then open http://127.0.0.1:8765
```

A small local page, standard library only, that drives the same code as `fetch.py` and `extract.py` on the same files. In the app's Browser pane, the `rewards-catalog` entry in `.claude/launch.json` starts it.

- **Model panel:** the server's address, its API key (a password field), and a model box that lists what the server has (or take any id); **Test model** asks it a trivial question using the real output schema and reports the time, tokens, and how many were spent reasoning; **More settings** holds the page size sent per request, the reply limit, the time limit, extra request fields (JSON, such as `{"reasoning_effort": "none"}`), and text added to every prompt. Settings are saved in `cache/ui-settings.json`, and `extract.py` on the command line uses them as its defaults (flags override).
- **Run:** fetch (never fetched, retry failed, ticked, all) or extract (what needs it, ticked, redo all), one job at a time, with a progress bar, the card and the part of its page being sent, a live log, and **Stop** (it stops between cards, or between parts of a card). A card is "needs extracting" when it has no result for the chosen model and the current prompt version, so switching models marks every card again.
- **Cards:** every card with its fetch status, extraction status, rule count, model, and the questions it asks the user; search, issuer and status filters; click a card for a drawer with the page's rate-looking lines, every rule in plain words with the quote it came from, what was rejected and why, and any error. **Try the model on this page** shows the model's raw reply and what the checks make of each rule, without saving anything.
- **Review:** every rule waiting for a decision (or all, accepted or rejected), with Accept, Reject and Undo; see the review stage above. **Publish catalog** writes `rewards-catalog.json` from the accepted rules (the publish stage above).
- **Safe to leave running:** it listens on `127.0.0.1` only, refuses requests whose Host isn't local, and refuses POSTs without an `X-Requested-With` header, so a web page you visit can't drive it. It never puts page text into markup (text is set with `textContent`).

### Speed, and what was learned about `flint` (`rec serve`)

**What makes a run slow** is mostly the model's thinking, not the page. On the Savor chunk: `k2-horizon-7b-uno-uncensored` with reasoning off took 12 seconds and 403 tokens; `flint` took 189 seconds and 17,831 tokens, 79,878 characters of it reasoning. At about 339 model calls, that is the difference between a few hours and most of a day.

**Done:**

- **Prompt order.** The unchanging rules now come first and the card's name and page text last, so a server that caches the start of a prompt (rec's `flint` has a prefix cache; LM Studio and vLLM do too) reads the 3,000-odd characters of rules once and not for every card. Prompt version 5. (Before this the card's name was the first line, so no two requests shared a prefix.) The page shows each card's prompt tokens and how many were cached, for servers that report it (`flint` does).
- **Per-card cost** (calls, seconds, prompt tokens and cached ones, reply tokens and reasoning ones) is saved in each candidate and shown in the log, the table and the card's drawer, so a change can be measured.
- **Function-calling mode** (`tool`), for servers that don't take `response_format`.

**What `rec`'s server does and doesn't accept** (read from its own code, `rec_mlx/server.py`): it keeps only these request fields and silently drops everything else (logging "Ignoring unsupported request field" once in the terminal running `rec serve`): `model`, `messages`, `tools`, `tool_choice` (only `auto` or `none`), `stream`, `stream_options`, `temperature`, `top_p`, `top_k`, `max_tokens`, `max_completion_tokens`, `seed`, `stop`, `frequency_penalty` (0 only), `repetition_penalty` (1 only), `presence_penalty`, `logprobs`, `min_p` (0 only), `store` (false only), `grammar` (`none` or `flint`), `parallel_tool_calls`.

- **No `response_format`**, so a JSON schema is never enforced there, and `flint` drifted from the field names (`category` for `categories`). Its own constraint (`--grammar flint`, on by default) applies to the schemas of tools offered with the request, which is why the `tool` mode exists.
- **No thinking switch.** Twelve guesses at the field name (`enable_thinking`, `thinking_budget_tokens`, `reasoning_effort`, `reasoning.max_tokens`, `chat_template_kwargs` and others) changed nothing, and the allowed list above explains why. The "Limit thinking" budget in the model settings panel you showed is not something this server reads from a request.
- **One request at a time.** Its scheduler is not batched (`is_batchable = False`; requests queue on one worker), so sending several at once wouldn't make a run faster.

**Not done:** a thinking budget (cut the reasoning at N tokens, close it, and let the model answer) would need the server to continue an assistant turn from raw text, which its chat API doesn't offer. A model that doesn't reason (k2 with `reasoning_effort: "none"`) is the practical speedup today.

## Why issuers' different sites are survivable

Fetching is the same for everyone. The only issuer-specific work is turning a page into rules, and that is the part that breaks when a site is redesigned. Two ways to do it:

1. **Per-issuer adapters** (CSS selectors, regexes). Precise and free to run, but 16 issuers means 16 things to repair after every redesign.
2. **One generic extractor** (an LLM reading the page text, asked for structured rules). Survives redesigns and can hallucinate.

**Plan: use the generic extractor, running a local model through LM Studio, and make hallucination harmless with validation.** Adapters stay an option for a single issuer that the generic extractor keeps getting wrong.

### The model: any OpenAI-compatible server

- The extract stage talks to any server that speaks the OpenAI chat completions API: LM Studio (the default, `http://localhost:1234/v1`), a local server such as `rec serve` for the `flint` model (`http://127.0.0.1:11500/v1`), vLLM, OpenAI itself. Set the address, model and **API key** (sent as `Authorization: Bearer ...`) on the web page; the command line reads the same saved settings, and takes the key from `LLM_API_KEY` (never a flag, so it stays out of shell history). Other environment variables: `LLM_BASE_URL`, `LLM_MODEL` (the older `LM_STUDIO_URL` and `LM_STUDIO_MODEL` still work).
- **The key is a secret.** It is saved in `cache/ui-settings.json`, which is not committed and is created readable only by you; the page never gets it back (it only learns that one is set), it isn't written into logs or error messages, and the page can remove it. Don't paste it into a file in the repo.
- **Servers differ**, so the page has settings for the three things that most often do: how the reply's shape is requested (`json_schema` sends the schema, as LM Studio and OpenAI accept; `tool` offers one function, `report_rules`, whose arguments are the schema, and reads the answer from its call; `json_object` and `prompt` describe the shape in the prompt instead, for servers with neither; the checks on the reply are the same), the name of the reply-limit field (`max_tokens`, or `max_completion_tokens` for newer OpenAI models), and the temperature (leave it empty for models that accept only their default). A server with no model list (HTTP 404) is taken on trust, and a 401 or 403 says the key was refused.
- It requests structured output (`response_format` with a JSON schema) at temperature 0, so replies parse without cleanup.
- Local models are weaker than hosted ones, so **validation carries more of the load**: expect more candidates to be dropped, and treat "extraction failed" as a normal outcome, not an error.
- Long pages are split into chunks that fit the model's context window, and results are merged. Only pages whose hash changed are extracted.
- The model is a setting, not code. Default: `k2-horizon-7b-uno-uncensored`. Small (7B) models drop and garble more, so before trusting it, run it on a handful of cached pages against hand-checked answers and see how often its candidates pass validation. Swap models by changing the setting.
- Every candidate records the model id and prompt version that produced it, so a rerun with a different model is a visible diff.
- Extraction runs on the maintainer's Mac, not in CI (hosted runners have no model). CI can still do fetch and change detection.
- **Reasoning models.** `k2-horizon-7b-uno-uncensored` thinks before it answers, and the thinking counts against the reply limit. At 3,000 tokens it used all of them on reasoning (13,871 characters, 86 seconds) and returned an empty reply, which showed up as a failed card with `the reply was 0 characters`. Sending `{"reasoning_effort": "none"}` with each request turns the thinking off: the same page then takes 12 seconds and 403 tokens. Other tries had no effect on this model: `reasoning_effort: "low"`, `chat_template_kwargs: {enable_thinking: false}`, and `/no_think` at the end of the prompt. The reply limit now defaults to 8,000 tokens and the time limit to 600 seconds. A model that doesn't reason needs none of this.

### Validation (what makes it trustworthy)

A candidate rule is kept only if all of these hold:

- It matches the schema, and its rate is in a sane range (0 to 10%, or a points multiplier up to 10x).
- Its `quote` appears **verbatim** in the cached page text, and the rate's number appears inside that quote. This is the check that kills hallucinated numbers.
- Its category is in the catalog's fixed category list (below).
- Its caps and dates, if any, also appear in the quote.
- The page still names the card (the card's name is in the page text), so a redirect to a different card or a "page not found" never passes.

### Failure never deletes

A fetch that fails, a page that vanished or an extraction that fails validation leaves the card's last accepted rules alone and only marks it stale. A card's `verifiedAt` ages visibly. The app shows "last verified <date>" and flags anything older than six months.

## Data model (catalog)

```
Card   id, name, issuer, network, isBusiness, annualFee, rewardKind,
       rewardProgram, baseEarnRate, discontinued, sourceUrl, verified,
       verifiedAt, cardConditions[] (the issuer's sentences that limit several rates), bonusesStack, rules[]
Rule   categories[], selection (fixed | choose | top-spend | rotating), picks, hasOtherChoices,
       rate, unit (percent | per-dollar), capAmount, capPeriod (month | quarter | year | cycle),
       requires[] (apple-pay | activation | issuer-booking | preferred-rewards-tier), validFrom, validTo, firstMonths,
       tier (gold | platinum | platinum-honors | diamond-honors; only with preferred-rewards-tier),
       needs[] (choice-categories | account-opened | pays-with-apple-pay | preferred-rewards-tier; derived),
       conditions[] (the issuer's own sentences, verbatim), merchants[] (a calendar quarter's names that are no category),
       verified (page | manual | calendar),
       evidence { url, quote, pageHash }
```

- `validFrom` / `validTo` exist for **rotating categories** (Discover, Chase Freedom Flex): they are the reason the cadence below has a quarterly run.
- **Catalog categories** are a fixed list of what issuers name (`CATEGORIES` in extract.py, prompt version 10): dining, groceries, gas, EV charging, travel, airlines, hotels, transit, streaming, entertainment, drugstores, online shopping, home improvement, fitness, phone & internet, utilities, wholesale clubs, department stores, everything else. Travel covers airlines and hotels: a quote naming travel with either is travel. A Grosh category is the user's own, so the app maps each of the user's categories to one of these rather than the catalog guessing the user's names; `APP_CATEGORIES` is the starting map for the default category tree (Restaurants and Café to dining, Petrol to gas...), shown in each card's view.

## Making reruns reliable

- **Idempotent.** The same inputs produce the same files, sorted and with stable formatting. A rerun with no site changes produces an empty diff.
- **Isolated per card.** One bad page logs an error and the run continues. The run exits non-zero only if the failure rate passes a threshold (say 25%), which means the pipeline itself broke, not one site.
- **Polite.** Obey robots.txt, identify the tool in the User-Agent, one request per second per host, public pages only, no logins, no CAPTCHA workarounds.
- **Cached.** The fetch stage stores page text and a hash, so extraction and validation can be rerun and debugged without hitting a site again.
- **Pinned.** The extractor prompt is versioned in the repo, and the LM Studio model id is recorded with every candidate and in `report.md`. A prompt or model change is a reviewable diff, and its effect is visible by rerunning on cached pages.

## Cadence

| When | What |
|---|---|
| Monthly, on the maintainer's Mac (LM Studio running) | Full run: fetch every card, extract the changed ones, open a PR with `report.md`. |
| Monthly, in CI (optional) | Fetch and change detection only, no extraction. Opens an issue listing pages that changed, as a reminder to do the local run. |
| Quarterly, a week before it starts | Re-run only cards with rotating rules, so the new quarter's categories are in before the quarter begins: `python3 tools/rewards-catalog/ui.py`, then **Refresh rotating cards** in the Run panel. |
| On demand | A command-line flag to run a single issuer or card. |

**Refresh rotating cards** fetches the cards whose Candidate has a rotating rule, through the normal fetch, then extracts those whose page, model or prompt changed. LM Studio is only needed if one did: an unchanged page asks no model, because a new run could only reword rules a person has already decided on. A card with an undated rotating rule and no quarter rules gets them from its saved page, or its saved calendar page if it has one (`extract.add_calendar_rules`), since a calendar is read, not asked about. A changed calendar page is a changed card, so it is extracted again like a changed page. A card with no Candidate yet isn't known to rotate, so extract it first.

The job's log ends with where each card stands, for the quarters that haven't ended:

- **Waiting for review**: each quarter rule with no Decision, and a last line naming those cards. Accept them in the card's view, then publish; nothing reaches the catalog before that.
- **Coming Soon**: the page marks the quarter that way and no calendar on it names the quarter (`quarters.coming_soon`). The issuer hasn't said yet, so this is not a failure: run the refresh again nearer the quarter.
- **No quarter rules**: the page (for Discover It, its calendar page) names no quarter ahead.
- **Errors**, in red: a page that couldn't be read (what's shown is from the saved copy) or a failed extraction. A rotating rule that a new extraction lost is a warning, to check on the card.

## Build order

1. **Seed** (this step): `build_seed.py` produces `catalog-seed.json`.
2. **Fetch and change detection only** (done). No extraction yet. "This issuer page changed" is already a useful, reliable signal, and it proves the fetching holds up on all 16 issuers.
3. **Extract and validate** (built; waiting on a first run with a real model). Try the biggest issuers first (Chase, American Express, Citi, Capital One) and see how often the generic extractor passes validation.
4. **Scheduled run and PR.**
5. **App side.** Bundle `rewards-catalog.json`, add "start from catalog" to the Card editor, and add the user's category mapping. This step needs its own glossary terms and likely an ADR before code.

## Known issues in the seed

- `currency` mixes `USD` (cash back) with reward-program names: BANK_OF_AMERICA, CHASE, CITI, AMERICAN_EXPRESS (bank points) and airline and hotel programs. The program list is: AEROPLAN, ALASKA, AMERICAN, AMERICAN_EXPRESS, AMTRAK, ANA, AVIANCA, AVIOS, BANK_OF_AMERICA, BARCLAYS, BEST_WESTERN, BREEZE, CAPITAL_ONE, CARNIVAL, CATHAY_PACIFIC, CHASE, CHOICE, CITI, DELTA, EMIRATES, EXPEDIA, FLYING_BLUE, FRONTIER, HAWAIIAN, HILTON, HYATT, IHG, JETBLUE, KOREAN, LATAM, LUFTHANSA, MARRIOTT, PENFED, SOUTHWEST, SPIRIT, UNITED, US_BANK, VIRGIN, WELLS_FARGO, WYNDHAM, plus USD.
- `universalCashbackPercent` is a percent for cash-back cards but a multiplier (1 point per dollar) for points cards. The seed's `rewardKind` records which.
- `sourceUrl` is not always the issuer's: co-brand cards point at the partner (Hilton, Amazon, Walmart, Expedia, E*TRADE, Schwab). Those pages may lag or omit the issuer's terms, so the extractor reports which host it read.
- `isAnnualFeeWaived` is dropped: its meaning is unclear (first year? ever?) and we shouldn't ship a guess.
- Several cards are listed twice for different sign-up offers; the seed keeps one row per card.
- The summary I first made of the CSV suggested some issuer values were wrong (Air France KLM under Bank of America, Business Altitude under U.S. Bank). Both are real: Bank of America and U.S. Bank issue those cards. The `FIRST` issuer (co-brand airline cards) is the one to check by hand.
