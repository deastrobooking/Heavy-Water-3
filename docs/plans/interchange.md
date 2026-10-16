# Player and asset interchange with the sibling web engine

**Status:** requirements only, 2026-10-15. The standard itself is written after feature freeze, as the owner decided; this page records what to keep true until then so the standard is cheap to build.

## Direction

Heavy Water is a local desktop game for up to four players on one machine. A separate web game engine for the same series exists. Eventually the two should exchange **objects and money**, load **our characters in their online game and arena (and the reverse)**, and import and export **player stats**. The choice now is purely to optimize the desktop local game: online play, accounts and networking are not part of this product, and [phase 16](networking.md) is not planned.

## What exists to build on

- **Per-player documents.** Each team member is saved as a `MemberState` holding a `Profile.Doc` and a `Kit.Doc` (loadout, wallet, XP, field droid, pets), separate from shared world progress ([architecture](../architecture.md#saves)). This separation is the starting point for a player passport.
- **Versioned saves.** Every document carries a format version and content version, with validators that reject without mutating.
- **Creations as recipes.** The [asset studio](asset-studio.md) stores designs as small versioned recipes with a content hash, and the bake can export glTF binary, which web engines read natively.

## Constraints to keep now (cheap)

1. **Stable string ids** for items, abilities, affixes (the [ability core](engine-features.md) E1) and creations. A document meant to leave the game must not contain array indices or enum ordinals, which change when content is added.
2. **Derived values are not stored.** Stats are computed from base attributes and modifiers, so an imported document cannot smuggle in a stat the rules would not produce.
3. **One wallet per player, with named currencies,** inside that player's `Kit`; exchange rates and sinks live outside the simulation.
4. **Separable per-player data.** Keep personal rewards in `Kit` and shared state in `Progress` (already a project rule), so a passport never has to untangle them.
5. **Versioned with an explicit supported range.** The save loader's rolling window silently drops old formats ([next steps](next-steps.md#technical-review--2026-10-14), R2); an interchange standard needs a stated minimum version, not a moving one.
6. **Validate before applying,** the same rule as loads and purchases.

## Open questions for the standard

- **Trust.** The web game is online and this one is local, so an import is untrusted input. Options include signed passports or server-side validation on the web side. Decide with the web engine's owner.
- **Money.** Which currencies map to which, exchange rates, and whether transfers are one-way or reversible.
- **Characters.** How Wildkin forms, rangers and Synthetics map to the other game's characters; how stats are normalized between the two games.
- **Items.** How rarity and affixes translate, and what happens to an item the other game does not know.
- **Privacy and ownership.** What a passport may reveal.

## Trigger

The owner declares feature freeze. Then write the standard: a v1 schema, converters in both directions, checked-in fixtures, and round-trip tests, using the constraints above. Until then, do not build transport, accounts or conversion.
