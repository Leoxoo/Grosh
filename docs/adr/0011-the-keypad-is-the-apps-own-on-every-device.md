# The Keypad is the app's own on every device, and amounts are typed as written

Every amount is typed on one Keypad the app draws itself: a wide-keyed, Liquid Glass calculator pad that stands in for the keyboard on iPhone and is docked below the form on iPad and Mac. This reverses an earlier step that put the iPhone's own number pad under a floating row of operators. That system pad looked, sounded and swiped away like any keyboard, but it couldn't carry the calculator's keys, the decimal point or the app's look in one place, and it differed from the Mac's. On iPhone the pad still behaves like a keyboard, sliding up and swiping away like one.

We also dropped cents-first entry (typing 1, 2, 3 gave 1.23, with a 00 key). Amounts are now typed the way they're written, with the decimal point typed by hand, and shown while typing without padded zeros (6, 6.3); everywhere else an amount keeps two decimals so columns line up. Cents-first was quicker only when every amount had cents. A typed amount never sets its own sign: the category does. Only a balance, which has no category, can be typed below zero, with a leading minus.

The cost is that the system's keyboard behaviours the app now draws itself, its key-click sound among them, are the app's to keep up with as iOS changes.
