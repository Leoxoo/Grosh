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
| **Fetch** | each card's `sourceUrl` | `cache/<id>/<date>.txt`, `.hash` | Conditional GET, robots.txt, rate limit, headless browser only for pages that need it. Stores the page's visible text, not the HTML. |
| **Extract** | cached text | `candidates/<id>.json` | Turns text into rule candidates, each with a verbatim `quote` from the page. Skipped when the page's hash hasn't changed. |
| **Validate** | candidates | pass/fail per candidate | Deterministic checks, below. A failing candidate is dropped, never "fixed". |
| **Diff** | candidates vs. `catalog.json` | `report.md` | Classifies each card: unchanged, changed, new, page gone, extraction failed. |
| **Review** | `report.md` | a PR | Only changes need eyes. Merging is the acceptance. |
| **Publish** | accepted `catalog.json` | `rewards-catalog.json` | Versioned, sorted, byte-stable so the PR diff shows only real changes. |

## Why issuers' different sites are survivable

Fetching is the same for everyone. The only issuer-specific work is turning a page into rules, and that is the part that breaks when a site is redesigned. Two ways to do it:

1. **Per-issuer adapters** (CSS selectors, regexes). Precise and free to run, but 16 issuers means 16 things to repair after every redesign.
2. **One generic extractor** (an LLM reading the page text, asked for structured rules). Survives redesigns, costs a little per changed page, and can hallucinate.

**Plan: use the generic extractor, and make hallucination harmless with validation.** The hash check means a page is only extracted when it changed, so cost stays small. Adapters stay an option for a single issuer that the generic extractor keeps getting wrong.

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
       verifiedAt, rules[]
Rule   category, rate, unit (percent | per-dollar), capAmount, capPeriod
       (month | quarter | year), rateAfterCap, validFrom, validTo,
       conditions, evidence { url, quote, fetchedAt, contentHash }
```

- `validFrom` / `validTo` exist for **rotating categories** (Discover, Chase Freedom Flex): they are the reason the cadence below has a quarterly run.
- **Catalog categories** are a small fixed list: dining, groceries, gas, travel, transit, streaming, drugstores, online shopping, utilities, everything else. A Grosh category is the user's own, so the app maps each of the user's categories to one of these once per Card, rather than the catalog guessing the user's names.

## Making reruns reliable

- **Idempotent.** The same inputs produce the same files, sorted and with stable formatting. A rerun with no site changes produces an empty diff.
- **Isolated per card.** One bad page logs an error and the run continues. The run exits non-zero only if the failure rate passes a threshold (say 25%), which means the pipeline itself broke, not one site.
- **Polite.** Obey robots.txt, identify the tool in the User-Agent, one request per second per host, public pages only, no logins, no CAPTCHA workarounds.
- **Cached.** The fetch stage stores page text and a hash, so extraction and validation can be rerun and debugged without hitting a site again.
- **Pinned.** Extractor prompt and model are versioned in the repo. A prompt change is a reviewable diff, and its effect is visible by rerunning on cached pages.

## Cadence

| When | What |
|---|---|
| Monthly (scheduled GitHub Action) | Full run: fetch every card, extract the changed ones, open a PR with `report.md`. |
| Quarterly, a week before it starts | Re-run only cards with rotating rules, so the new quarter's categories are in before the quarter begins. |
| On demand | `workflow_dispatch` for a single issuer or card. |

## Build order

1. **Seed** (this step): `build_seed.py` produces `catalog-seed.json`.
2. **Fetch and change detection only.** No extraction yet. "This issuer page changed" is already a useful, reliable signal, and it proves the fetching holds up on all 16 issuers.
3. **Extract and validate** for the biggest issuers first (Chase, American Express, Citi, Capital One), and see how often the generic extractor passes validation.
4. **Scheduled run and PR.**
5. **App side.** Bundle `rewards-catalog.json`, add "start from catalog" to the Card editor, and add the user's category mapping. This step needs its own glossary terms and likely an ADR before code.

## Known issues in the seed

- `currency` mixes `USD` (cash back) with reward-program names: BANK_OF_AMERICA, CHASE, CITI, AMERICAN_EXPRESS (bank points) and airline and hotel programs. The program list is: AEROPLAN, ALASKA, AMERICAN, AMERICAN_EXPRESS, AMTRAK, ANA, AVIANCA, AVIOS, BANK_OF_AMERICA, BARCLAYS, BEST_WESTERN, BREEZE, CAPITAL_ONE, CARNIVAL, CATHAY_PACIFIC, CHASE, CHOICE, CITI, DELTA, EMIRATES, EXPEDIA, FLYING_BLUE, FRONTIER, HAWAIIAN, HILTON, HYATT, IHG, JETBLUE, KOREAN, LATAM, LUFTHANSA, MARRIOTT, PENFED, SOUTHWEST, SPIRIT, UNITED, US_BANK, VIRGIN, WELLS_FARGO, WYNDHAM, plus USD.
- `universalCashbackPercent` is a percent for cash-back cards but a multiplier (1 point per dollar) for points cards. The seed's `rewardKind` records which.
- `sourceUrl` is not always the issuer's: co-brand cards point at the partner (Hilton, Amazon, Walmart, Expedia, E*TRADE, Schwab). Those pages may lag or omit the issuer's terms, so the extractor reports which host it read.
- `isAnnualFeeWaived` is dropped: its meaning is unclear (first year? ever?) and we shouldn't ship a guess.
- Several cards are listed twice for different sign-up offers; the seed keeps one row per card.
- The summary I first made of the CSV suggested some issuer values were wrong (Air France KLM under Bank of America, Business Altitude under U.S. Bank). Both are real: Bank of America and U.S. Bank issue those cards. The `FIRST` issuer (co-brand airline cards) is the one to check by hand.
