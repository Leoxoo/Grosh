# Tab roots keep the system large title, without the small one

The first screen of each tab (Home, Transactions, Budgets, Account) uses the standard large title, which slides away as the content scrolls up, and leaves the bar bare once it has gone: no small title takes its place, except while selecting, when the bar shows the count (`tabRootTitle`, `Grosh/Views/TabRootTitle.swift`). Transactions uses it too, rather than an inline title of its own, so the four tabs look alike. Its pinned header (wallet, period strip, balances) is a `safeAreaBar`, which moves up into the title's place as the title slides away and fades the rows scrolling under it as the system bar does. The cost is that the large title sits on a row below the toolbar buttons, a little lower than App Store's Today.

## Considered Options

- **The large title on the buttons' row (`toolbarTitleDisplayMode(.inlineLarge)`).** Rejected: it doesn't move with the content, but cross-fades into the small title.
- **Our own title row in the content, with the system bar hidden.** It sat on the buttons' row and scrolled away, as Today's does, but the buttons had to be our own copies of the toolbar's, which neither look nor behave like the system's.
