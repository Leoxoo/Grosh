# A category can count as several Reward categories, and earns the best of them

One of the user's categories can count as more than one Reward category: Travel as both Travel and Airlines, because what the user files there is sometimes a flight and sometimes a hotel or a rental car. Its Rewards as is a list, set from one menu with a checkmark per Reward category. A purchase in it earns, with each Card, the best rate among those Reward categories, and the Card picker names the one that won ("5% · Airlines"). The Bonuses add up rule (a card's Base plus each Bonus over it) still applies within that one Reward category; rates of two different Reward categories are never added together, since a single purchase is either a flight or a hotel, never both.

For a top-spend rate, a purchase counts toward each of its category's Reward categories: the app can't tell which one the issuer will see, and counting it in each never makes a category the top one that couldn't be.

Everything else never sits beside another Reward category: picking it clears the others, and picking another clears it. A category with none of its own still follows its parent's, or is Everything else at the top level.

Stores from before keep their single Rewards as: it is still read from where it was stored (`Category.singleRewardsAs`), copied into the list once when the store opens, and cleared, so the list is the only copy from then on. The list is a stored `[String]` of Reward category ids, optional like every field (ADR-0001), so an older store opens without a migration plan.

The rewards catalog is not affected: its Rules already name several catalog categories each, and the map from the user's categories to Reward categories lives only in the app (`RewardsPrefill` starts it, the user changes it).

## Considered options

- **Add the rates of every Reward category the category counts as.** Overstates what a purchase earns: a flight bought with a card that pays 5% on airlines and 3% on hotels earns 5%, not 8%.
- **A join model between Category and Reward category.** The fixed Reward categories are not models, so it would need a row per fixed id too; a list of ids on the category is what the screens and the earning rules read, in one place.
- **Keep one Reward category and let the user duplicate the category instead (Travel – flights, Travel – hotels).** Works today, but asks the user to split their own history to answer a question about cards.
