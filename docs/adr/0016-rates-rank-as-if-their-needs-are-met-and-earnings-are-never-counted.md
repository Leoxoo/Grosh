# Rates rank as if their Needs are met, and what a Card earned is never counted

Rewards in Grosh are informative only: they tell the user which Card to pay with, and the app never counts what a Card earned. A transaction doesn't record how it was paid (Apple Pay or the physical card), whether a quarter was activated, or where a cap stands, so any total of rewards earned would often be wrong, and the user would rightly blame the app. #198 (Rewards earned totals) is dropped for this reason.

Since nothing is counted, a rate that Needs something the app can't see (a way of paying, a store, an activated quarter) is no longer left out. Wherever Cards are ranked (Best Card's tiles and card lists, the Expense Card picker), it competes with every other rate as if what it Needs is done, and shows what it Needs beside it ("2% · with Apple Pay"). Apple Card's 2% with Apple Pay therefore ranks on every Reward category, flagged. A rate that Needs a store is listed with its store but is never a Best Card tile's card, because the tile stands for every purchase in its Reward category, not one shop's. Caps are not Needs: they stay in a rate's details.

This replaces #163's and #192's "Apple Pay and merchant rates are shown, never earned".

## Considered options

- **Leave out rates the app can't confirm (#163 as first decided).** Exact, but it hides the answer the user most needs: an Apple Card paid with Apple Pay often beats the card the app recommends.
- **Record how each transaction was paid, so rates could be counted.** More to enter on every purchase, and still wrong whenever the user forgets, so totals would remain unreliable.
