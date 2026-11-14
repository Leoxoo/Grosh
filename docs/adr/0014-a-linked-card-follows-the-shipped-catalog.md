# A linked Card follows the catalog the app ships

A Card linked to the rewards catalog stores which catalog card it is, not a copy of its rates to show. Its rates come from whatever catalog the app has, bundled now and downloaded later, so an app update that brings a newer catalog gives every linked Card its new quarters and corrected rates without the user doing anything. Nothing is fetched while the app runs.

The user's changes sit on top as **Edited rates**: a rate they changed, added or removed replaces the catalog's for that Card alone, and every rate they left alone keeps following the catalog. Each Edited rate can be reset to the catalog's. **Change catalog card** links the Card to another entry and removes what was set for the old one (its Edited rates, Activated quarters and Your choice) once the user confirms.

The Card also keeps the rates its entry last had, used only when a newer catalog no longer has that entry (a discontinued card): it then shows those rates, marked "No longer in the catalog", with its Edited rates still on top.

## Considered options

- **Copy the rates into the Card when it is linked.** Simpler to read and edit, but the Card would never see a new rotating quarter or a corrected rate, and rotating cards change every three months.
- **Detach the Card from the catalog on its first edit.** The same problem, triggered by a single fix to one rate.
