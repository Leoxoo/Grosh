# Tab roots put their title on the bar's row, in the large title's style

The first screen of each tab (Home, Transactions, Budgets, Account) shows its title in the large title's font on the row of the bar's buttons, as standard apps such as App Store's Today have it, not on a row of its own below them. It is a leading toolbar item without the glass background (`tabRootTitle`, `Grosh/Views/TabRootTitle.swift`). It fades as the list scrolls up, over the first 44 points (63 on Transactions, below), and moves down with a pull past the list's top. The bar's own small title is removed (`toolbar(removing: .title)`), except while selecting, when the bar shows the count. The content under the bar fades with the soft scroll edge effect rather than the band with a hard bottom edge iOS draws under an inline bar, which read as a row kept for a title that isn't there.

Transactions' pinned header (wallet, period strip, balances) is a `safeAreaBar`. It rises with the scroll as the title fades, 63 points, getting as much shorter, so the Total moves up into the title's place and the blur under the header rises with it, leaving the rows it uncovers clear; it moves down with the title on a pull. Once it has risen, the bar's leading item shows the Wallet selector in the same spot and the header's own is hidden, because the bar's row takes the taps on whatever lies under it: the Total stays one tap from the wallet choices. The scroll is read once, on the list itself, into an observable object that only the title and the header read, so the list isn't drawn again on every frame.

Beside "Transactions" at the large title's size the bar has room for two buttons, so on iPhone and iPad Filters is in the "…" menu, with Search beside it. Mac keeps a Filters button.

## Considered Options

- **The system large title (`navigationBarTitleDisplayMode(.large)`).** It sits on a row of its own below the buttons, lower than standard apps' titles, and on Transactions it slid across the pinned header on a pull.
- **The large title on the buttons' row (`toolbarTitleDisplayMode(.inlineLarge)`).** At rest it still sat below the buttons, reaching their row only part-way through a scroll.
- **Hiding the small title with an empty principal item.** It holds the bar's middle, so the leading title got half the bar and was cut to "Tr…".
- **Our own title row in the content, with the system bar hidden.** The buttons had to be our own copies of the toolbar's, which neither look nor behave like the system's.
