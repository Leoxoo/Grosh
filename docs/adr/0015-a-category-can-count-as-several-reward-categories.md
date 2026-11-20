# A category can count as several Reward categories, and earns the best of them

One of the user's categories can count as more than one Reward category: Travel as both Travel and Airlines, because what the user files there is sometimes a flight and sometimes a hotel or a rental car. Its Rewards as is a list, set on a screen of its own that lists every Reward category with its icon and a checkmark on each it counts as. A menu was tried first, but each tap saves and moves the category between sections of the Reward categories list, which closed the menu or left its checkmarks behind. A purchase in it earns, with each Card, the best rate among those Reward categories, and the Card picker names the one that won ("Airlines", beside its rate). The Bonuses add up rule (a card's Base plus each Bonus over it) still applies within that one Reward category; rates of two different Reward categories are never added together, since a single purchase is either a flight or a hotel, never both.

For a top-spend rate, a purchase is split evenly between its category's Reward categories (a leftover cent goes to the first): the app can't tell which one the issuer will see. Counting it in full toward each would make a Reward category the top one when it may not be: $500 of Travel counting as Travel and Airlines would put both above $400 of Dining, though the issuer may have seen $250 of each. An even split keeps the Card's total spending what was really spent and gives no Reward category more than its share. Counting it toward only the first, or toward whichever earns the Card most, was simpler to state but picks one side for no reason the user can see.

Everything else never sits beside another Reward category: picking it clears the others, and picking another clears it. A category with none of its own still follows its parent's, or is Everything else at the top level.

Stores from before keep their single Rewards as: it is still read from where it was stored (`Category.singleRewardsAs`), copied into the list once when the store opens, and cleared, so the list is the only copy from then on. The list is a stored `[String]` of Reward category ids, optional like every field (ADR-0001), so an older store opens without a migration plan.

The rewards catalog is not affected: its Rules already name several catalog categories each, and the map from the user's categories to Reward categories lives only in the app (`RewardsPrefill` starts it, the user changes it).

## Considered options

- **Add the rates of every Reward category the category counts as.** Overstates what a purchase earns: a flight bought with a card that pays 5% on airlines and 3% on hotels earns 5%, not 8%.
- **A join model between Category and Reward category.** The fixed Reward categories are not models, so it would need a row per fixed id too; a list of ids on the category is what the screens and the earning rules read, in one place.
- **Keep one Reward category and let the user duplicate the category instead (Travel – flights, Travel – hotels).** Works today, but asks the user to split their own history to answer a question about cards.
