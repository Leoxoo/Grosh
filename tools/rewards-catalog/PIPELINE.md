# Rewards catalog pipeline

How Grosh gets credit card reward rules without a server, and keeps them current.

## Goal and non-goals

The app ships a **rewards catalog**: for each known card, its fee, its flat earn rate and its category rules (3% dining, 5% on rotating categories up to a cap...). Adding a Card in Grosh can start from a catalog entry.

- The catalog is built **offline**, in this repo, and shipped as one static JSON file. The app never scrapes (ADR 0001: no backend).
- Nothing reaches the app unreviewed. A script *proposes*; a person *accepts* by merging a pull request.
- We ship facts we re-verified ourselves. We never ship card art or another site's compiled data.

## The shape of a run

```
seed ──► fetch ──► extract ──► validate ──► diff ──► review (PR) ──► publish
```

Each stage reads files and writes files, so any stage can be rerun alone and a failed run resumes where it stopped.

| Stage | Reads | Writes | Notes |
|---|---|---|---|
| **Seed** | CardPin CSV | `catalog-seed.json` | One-off. `build_seed.py`. Every card starts `verified: false`. |
| **Fetch** | each card's `sourceUrl` | `fetch-state.json` (committed), `cache/<id>/latest.txt`, `previous.txt` (not committed) | `fetch.py`, built. Details below. |
| **Extract** | cached text | `cache/candidates/<id>.json` (not committed) | `extract.py`, built, not yet run against a real model. Details below. |
| **Validate** | candidates | pass/fail per candidate | Deterministic checks, below. A failing candidate is dropped, never "fixed". |
| **Diff** | candidates vs. `catalog.json` | `report.md` | Classifies each card: unchanged, changed, new, page gone, extraction failed. |
| **Review** | `report.md` | a PR | Only changes need eyes. Merging is the acceptance. |
| **Publish** | accepted `catalog.json` | `rewards-catalog.json` | Versioned, sorted, byte-stable so the PR diff shows only real changes. |

## The fetch stage (`fetch.py`)

```
python3 tools/rewards-catalog/fetch.py [--issuer chase] [--only ID ...] [--limit N]
python3 -m unittest discover -s tools/rewards-catalog      # offline tests
```

- **Standard library only.** One page per distinct URL (cards that share a page, like the two Expedia cards, fetch once).
- **Hashes the visible text**, not the HTML, so a changed script bundle or tracking id isn't a change. `fetch-state.json` holds each card's hash and is committed, so a run on any machine knows what changed; the page text lives in `cache/`, which isn't.
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
fetch.py --missing            # never fetched: resumes an interrupted run
fetch.py --retry              # last fetch failed or found the page gone
```

A card whose `sourceUrl` changed since it was fetched is picked up by `--missing` and `--retry` too. A wrong or moved page URL is fixed in `url-overrides.json` (`{card id: url}`); `build_seed.py` applies it, so rebuilding the seed keeps the fix.

### Fetch status after retries (2026-10-20, 166 cards)

| Result | Cards | Notes |
|---|---|---|
| Read | 138 | Real rate text, for example "Earn unlimited 3% cash back on food and fun". 9 of these come from embedded page data (below), marked `"embedded": true` in `fetch-state.json`. |
| `needs-browser` | 4 | The two Schwab-branded Amex cards ("unable to authorize your request") and the two Amazon cards (a "continue shopping" check page). Bot walls, so a browser is unlikely to help; use the issuers' own pages instead. |
| `failed` | 12 | Timeouts: the United cards (theexplorercard.com), E*TRADE (2 Morgan Stanley cards), PenFed (3), Air France. Retrying here didn't help; try `--retry` from your own network. |
| `refused` | 11 | LATAM, LifeMiles, Amtrak, Best Western, Virgin, Expedia. |
| `gone` | 1 | `barclays-carnival-world-mastercard`: Barclays removed the page and I found no official replacement, so it needs a URL from you. |

The 3 earlier `gone` pages (two TD, one Walmart) now fetch from corrected URLs. The Walmart OnePay card uses OnePay's help article, not a Synchrony or Walmart product page. Amex Everyday's URL pointed at a sign-in "Benefits Dashboard" and now uses its card page.

### Pages built in the browser: embedded data, not a browser

Many issuer pages ship almost no visible text, but carry their sentences (and rates) as data inside the HTML. When a page's visible text is under 400 characters, `fetch.py` also reads:

- `<meta>` descriptions (`description`, `og:description`, `twitter:description`);
- JSON script tags (`application/json`, `application/ld+json`, such as Next.js's `__NEXT_DATA__`);
- JSON a script assigns to `window` (`window.X = {...}`), including JSON held inside a string, as Amex's `__INITIAL_STATE__` does.

Only prose is kept: strings of two or more words that read as sentences, once each, up to 200,000 characters. This recovered AAA, Alaska Atmos and four Amex pages without a browser, in standard-library Python.

Limits to know before the extract stage:

- **Mixed content.** Amex's state holds marketing for many cards, so a card's page can contain other cards' rates. Extraction must keep only rules whose quote names the card, which is why "the page names the card" is a validation check.
- **Wrong pages still read as "ok".** The embedded text of `american-express-green` is Amex's generic card listing (its page redirects there, so the Green card page has moved) and `american-express-rakuten` is the Rakuten shopping site's labels, not card terms. Both need correct URLs from you. A fetch that ends on a different page than it asked for should be flagged; not built yet.
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

Start LM Studio's server (Developer tab, Start Server) with the model loaded first. Settings: `--base-url` / `LM_STUDIO_URL` (default `http://localhost:1234/v1`) and `--model` / `LM_STUDIO_MODEL` (default `k2-horizon-7b-uno-uncensored`). The script checks the server answers and lists the model before it starts.

For each card it splits the cached page text into chunks of about 12,000 characters (repeating three lines between chunks), asks the model only about chunks that contain something rate-shaped (`3%`, `2X`, "per $1"), and writes `cache/candidates/<id>.json`: the accepted `rules`, the `rejected` proposals with the reason each failed, and the model id, prompt version and page hash. A card whose page, model and prompt are unchanged is skipped; `--force` redoes it.

**Statuses:** `ok`; `no-rules` (the page states no rate for the card); `wrong-page` (the page doesn't name the card, so the model isn't asked at all); `failed` (the model's reply couldn't be read after one retry, so the result is incomplete and isn't treated as done).

**Checks on every proposed rule** (`validate_rule`, none of which trusts the model):

1. every category is in the catalog list, unit is `percent` or `per-dollar`, the rate is a number above 0 and up to 10;
2. the quote appears on the page word for word (ignoring case, spacing, curly quotes and ®/™ marks);
3. the rate appears in the quote as a whole number (13% is not 3%), and the quote has a `%` for percent or points, miles or X for per-dollar;
4. the quote uses a word for its category (for example "grocer", "restaurant", "all other"), which catches a rate filed under the wrong category. A base rate may leave out "all other" if the quote names no other category (Apple Card's "Get 2% Daily Cash back when you use Apple Card with Apple Pay");
5. a cap needs an amount and a period, and both appear in the quote (`$6,000`, `6K` and `6000` match; "year" or "annual"; `cycle` is a "billing cycle");
6. every **condition** (an exclusion or restriction on the rate, such as "excluding superstores like Walmart® and Target®") is the page's own sentence, word for word. Conditions are never paraphrased, so what a person sees is what the issuer wrote. A rule with a condition that isn't on the page is rejected whole, since showing the rate without its restriction would overstate it;
7. a rule where the cardholder chooses or the card picks (`selection` of `choose` or `top-spend`) needs a quote that says so ("of your choice", "top eligible category"), and every category it lists must be mentioned on the page;
8. a `requires` tag (`apple-pay`, `activation`, `issuer-booking`) is accepted only if the quote or a condition has words that back it ("Apple Pay", "activate", "booked through");
9. `validFrom` / `validTo` are accepted only if the quote or a condition gives that date's month and year, so a period can't be made up.
10. `firstMonths` (a rate only for the first N months after opening, such as a first-year bonus) is accepted only if the quote or a condition says "first year", "first 12 months" or similar for that length.

A rule that fails any check is listed as rejected, never edited. **Card-wide conditions** (`cardConditions`: sentences that limit several of a card's rates, such as Capital One's note that digital wallets may not earn the higher rate) must also be on the page word for word; one that isn't is dropped and listed under `rejected`, and the card's rules are kept.

### Odd earning rules

| Case | How a rule says it |
|---|---|
| Needs a way of paying (Apple Card's 2% with Apple Pay) | `requires: ["apple-pay"]` |
| Needs activation or booking through the issuer | `requires: ["activation"]` or `["issuer-booking"]` |
| The cardholder picks the categories (Bank of America Customized Cash) | `selection: "choose"`, the eligible `categories`, `picks`, and `hasOtherChoices: true` if the page lists choices outside the catalog list |
| The card applies the rate to the top-spend category (Citi Custom Cash) | `selection: "top-spend"`, same fields |
| Only for a stated period (rotating 5% categories) | `validFrom` / `validTo`, with `requires: ["activation"]` where the page says to activate |

Not handled: relationship boosts (Bank of America Preferred Rewards), caps shared between categories, and rates at one named store (the catalog skips those). The page's own sentence about them can still ride along in `conditions`.

### Questions only the cardholder can answer

Some things about a rule depend on the person, not the card. The catalog doesn't guess them; each rule lists what it `needs`, and the app asks (a Settings screen or the card editor, still to be designed). `needs` is **worked out from the rule**, never taken from the model, and each card's candidate carries the union as `needs`.

| Question id | A rule needs it when | What the app asks |
|---|---|---|
| `choice-categories` | `selection` is `choose` | Which category did you choose on this card? |
| `account-opened` | `firstMonths` is set (a first-year rate) | When did you open this card? |
| `pays-with-apple-pay` | `requires` has `apple-pay` | Do you usually pay with Apple Pay? |

`top-spend` rules (Citi Custom Cash) need no answer, because Grosh can work out the top category from the user's own expenses in the statement period. Not modeled yet: Bank of America's Preferred Rewards tier (a percentage boost by tier, which the cached pages don't state). Bank of America's first-year 6% is supported by the schema (`firstMonths: 12`) but **not entered**: none of the pages we have states it, so there's no quote to take.

### Hand-entered cards and rules

- `extra-cards.json` adds cards CardPin lacks (Apple Card so far) to the seed; `build_seed.py` merges them, gives each the same id scheme as every card, and stops on a missing field or an id clash.
- `manual-rules.json` (`{card id: {rules: [...], cardConditions: [...]}}`) holds rules a person writes in the same shape as the model's. They run through the same checks without needing the page, and `extract.py` needs no LM Studio for them. A rule whose quote is found on the cached page is `verified: "page"`; one the page can't confirm (no page, or the page says something else) is `verified: "manual"` and should be re-checked at review. Apple Card's two rules are in there, both `"page"`.
- **Citi Custom Cash and Bank of America Customized Cash are entered**, from pages that state their rules: Citi's featured-cards page (its own card page now says Citi stopped accepting applications on May 28, 2026, so the FAQ on `citi.com/usc/Multi/Featured/default.htm` is the page that still has the rules) and Bank of America's "Categories & Exclusions" page. Citi's 5% is a `top-spend` rule over seven catalog categories with a $500 cap per billing cycle (`capPeriod: "cycle"`) and `hasOtherChoices` for home improvement, fitness clubs and live entertainment. Bank of America's 3% is a `choose` rule (gas, online shopping, dining, travel, drug stores; home improvement is outside the list) with a $2,500 combined quarterly cap, next to a 2% grocery rule and a 1% base rate. Its card-wide condition ("Merchants, not Bank of America, categorize and submit purchases ...") and the online-shopping exclusion are the page's own sentences. All were checked against the cached pages: `verified: "page"`.
- Citi Custom Cash is **closed to new applicants** but still held by existing cardholders, so it stays in the catalog. There's no field for "closed to new applicants" yet.
- Not entered: Bank of America's Preferred Rewards boost (up to 5.25% on the choice category), Citi's extra 4% on Citi Travel bookings, and Bank of America's first-year 6% offer. Pages disagree on the last one, so it needs a decision before it goes in.

**What I measured on the 138 fetched pages, without a model:** 8 are `wrong-page` (for example `u-s-bank-business-leverage`, `wells-fargo-attune`), 130 would be sent to the model, and that takes about 339 model calls: 50 pages need one call, 32 need two, and the three big Amex pages need 18 each. With a 7B model on a Mac expect a full run to take on the order of an hour or more; it can be stopped and resumed, since each card is saved as it finishes.

**Not done, and worth knowing:**

- It has run against the real model once, on Capital One Savor: 5 rules, all correct, none rejected, and (with prompt version 2) the right exclusions, though the digital-wallet sentence landed on the 1% rule instead of the higher ones. That motivated `cardConditions`. Prompt version 3, with selection, requirements, dates and card conditions, has not been tried against the model yet. Rerun `--only capital-one-savor` and read the candidate file.
- **Mixed pages.** Amex pages hold other cards' marketing. The prompt tells the model to take only this card's rates, but a quote about a different card would still pass the checks. Review Amex candidates by hand.
- **Conditions come from the same chunk as the rate.** A footnote far from its headline, in another 12,000-character chunk, is missed, and the rule looks unrestricted. A second pass that hunts for footnotes is the fix if this shows up in real runs. Whether a condition really belongs to the rate, and not to a neighbouring one, can't be checked automatically; that's for the reviewer.
- **Rotating categories** (Discover 5%, Freedom Flex) carry `validFrom` / `validTo`, but only when the page names the months and the year. Pages that say "this quarter" give the extractor nothing to date.
- **Chunks with no rate in them aren't sent**, so a footnote-only chunk holding a card-wide condition can be skipped on big pages.
- **Category words** are a guess at what a quote about a category says. Valid rules the list misses show up in `rejected` as "quote doesn't mention ...", and the fix is to add the word to `CATEGORIES`.

## Why issuers' different sites are survivable

Fetching is the same for everyone. The only issuer-specific work is turning a page into rules, and that is the part that breaks when a site is redesigned. Two ways to do it:

1. **Per-issuer adapters** (CSS selectors, regexes). Precise and free to run, but 16 issuers means 16 things to repair after every redesign.
2. **One generic extractor** (an LLM reading the page text, asked for structured rules). Survives redesigns and can hallucinate.

**Plan: use the generic extractor, running a local model through LM Studio, and make hallucination harmless with validation.** Adapters stay an option for a single issuer that the generic extractor keeps getting wrong.

### Local model (LM Studio)

- The extract stage talks to LM Studio's OpenAI-compatible server (default `http://localhost:1234/v1`, configurable). No API key, no cost per page, and page text never leaves the machine.
- It requests structured output (`response_format` with a JSON schema) at temperature 0, so replies parse without cleanup.
- Local models are weaker than hosted ones, so **validation carries more of the load**: expect more candidates to be dropped, and treat "extraction failed" as a normal outcome, not an error.
- Long pages are split into chunks that fit the model's context window, and results are merged. Only pages whose hash changed are extracted.
- The model is a setting, not code. Default: `k2-horizon-7b-uno-uncensored`. Small (7B) models drop and garble more, so before trusting it, run it on a handful of cached pages against hand-checked answers and see how often its candidates pass validation. Swap models by changing the setting.
- Every candidate records the model id and prompt version that produced it, so a rerun with a different model is a visible diff.
- Extraction runs on the maintainer's Mac, not in CI (hosted runners have no model). CI can still do fetch and change detection.

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
       verifiedAt, cardConditions[] (the issuer's sentences that limit several rates), rules[]
Rule   categories[], selection (fixed | choose | top-spend), picks, hasOtherChoices,
       rate, unit (percent | per-dollar), capAmount, capPeriod (month | quarter | year | cycle),
       requires[] (apple-pay | activation | issuer-booking), validFrom, validTo, firstMonths,
       needs[] (choice-categories | account-opened | pays-with-apple-pay; derived),
       conditions[] (the issuer's own sentences, verbatim), verified (page | manual),
       evidence { url, quote, pageHash }
```

- `validFrom` / `validTo` exist for **rotating categories** (Discover, Chase Freedom Flex): they are the reason the cadence below has a quarterly run.
- **Catalog categories** are a small fixed list: dining, groceries, gas, travel, transit, streaming, drugstores, online shopping, utilities, everything else. A Grosh category is the user's own, so the app maps each of the user's categories to one of these once per Card, rather than the catalog guessing the user's names.

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
| Quarterly, a week before it starts | Re-run only cards with rotating rules, so the new quarter's categories are in before the quarter begins. |
| On demand | A command-line flag to run a single issuer or card. |

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
