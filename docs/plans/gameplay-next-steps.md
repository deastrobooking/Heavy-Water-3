# Gameplay review and next steps

Review pass dated 2026-10-19. Read-only: code and docs were read; nothing was built or run, so "reachable" means a code path exists, not that it was played.

## Review findings

**Reachable and playable today** (one seeded world, 7 fast-travel entries):
- Detroit Arbor Reach: spawn, plazas, market, metro stations, Rootdeep shrines 1 and 2.
- Wilds loop: combat (11 weapons), 3 powers per class, 10 enemy kinds, nests, Brood-carrier air war, loot, 4 pet species, Wildkin heroes, droid companion, Starbowl arena, caves with nests and heroes, hover cars, Kestrel, raceway.
- Per-player Kit and shared Progress, keeper trade/upgrades/wardrobe, fabricator, flag-gated dialogue (3 named NPCs), one linear Hive quest chain.
- New York: arrival foothold only (terrain patch, 5 landmark boxes). No missions, shops, boss, discoveries or occupation.

**Exists only as data or docs (not reachable):**
- Pelaglass and Sonorous Reef (underwater): catalog records in `src/procedural/Worlds.zig`, design in `docs/plans/ocean-cities.md`. No ocean terrain, water rendering, swim/buoyancy, meshes or travel entry. Only a breath timer exists (`Player.zig`).
- Hive Homeworld, Gaia, solar planets, Stormwake siege, other Frontier cities: records in `Worlds.zig`/`SolarSystem.zig`, which nothing in the game imports.
- Interiors: `Interiors.zig` makes room graphs only. No meshes, doors, colliders or population.
- City-loop content (3 sub-missions, boss, 10 discoveries, liberation state): documentation only (`docs/plans/city-content.md`).
- Dead or orphan code: `src/ai/Hive.zig` (duplicates `game/Enemies.zig`), `src/game/SuperMobility.zig` (sonic dash/flight/warp, own tests only).

**Structural cause:** there is one hard-coded seed plus a one-off NYC chunk-range salt, and the travel list is hard-coded in three places (`Sandbox.travel_labels` ~4041, `Menu.map_items`, `Screens.zig` world map). There is no region abstraction, so every new place is a special case.

**Bug found and fixed in G0 (2026-10-19):** the New York region range was written for 64 m chunks, so the arrival and landmarks got Detroit terrain, and physics ignored the regional seed anyway. Cave collision inside the region still uses the world-seed layout.

**Verification gaps:** the smoke never calls `fastTravel` (travel and NYC are unit-tested only); the hands-on checklist (flight, combat, controller, co-op, audio) has no recorded results; guests cannot drive/talk/fabricate; Linux/Windows not rerun since 2026-10-10.

**Doc drift:** occupation/liberation is documented (uncommitted `Story.md`/`world.md`/`roadmap.md` edits) but absent from `src/`; stale "sanctuary" wording remains in roadmap "Next" item 3 and `next-steps.md`; `Save.zig` header says v12; roadmap has duplicate bullets and double-numbered items; AGENTS.md test count is stale.

## Recommended order
Roadmap (`docs/roadmap.md:5`) gates ocean/planet content behind a finished Detroit loop. Keep that order, but build the region abstraction early because it unblocks the underwater city and everything else.

**G0. Trust the base (small). In progress:** the New York terrain/collision bug is fixed and travel is in the smoke (see [validation](../validation.md)); hands-on checklist, doc drift and the orphan modules remain. Confirm/fix the NYC seed mismatch with a regression test. Add `fastTravel` to a smoke stage. Run the hands-on checklist and record it in `docs/validation.md`. Fix doc drift above. Delete or wire `ai/Hive.zig` and `SuperMobility.zig` (decide with user).

**G1. Region abstraction. In progress:** terrain seeds, bounds, arrival and map title come from one table (`src/world/Region.zig`); the map menu rows are generated from `Sandbox.travel_menu_labels`. Still hand-edited per destination: `travel_labels`, `travelPoint` and `travelArrival` in `Sandbox`. One `Region` type (seed, terrain/biome, spawn, arrival kind, label) that drives chunk streaming, physics ground and the travel list from one table. Move Detroit and NYC onto it, remove the hard-coded 7-entry lists, and derive menu/map rows from it. Reuse `Worlds.zig` records as the data source. Done when adding a destination is one table row and the smoke visits every region.

**G2. Detroit liberation loop (the MVP gate).** Per `docs/plans/city-content.md` C0–C6: discovery system, occupation/liberation state in `Progress`, first sub-mission, then remaining sub-missions, boss, 10 discoveries, evidence/informants dialogue in `conversations.json`. Needs approval of the Detroit names/boss that are still proposals.

**G3. Interiors.** Wire `Interiors.zig`: meshes, colliders, doors/entry-exit, enemy and loot population. Required by city exploration and cave dungeons.

**G4. New York loop.** Draft its content (deliberately undrafted today), reuse G2 systems.

**G5. Underwater cities (Pelaglass, Sonorous Reef).** Ocean/shelf region, water rendering, swim and buoyancy, pressure-dome arrival, city meshes, Tideborn/Neri, underwater Hive encounters, travel entry. Mostly new engine work, which is why it follows G1–G3. If the user wants it sooner, a thin vertical slice (one dome, swim, one encounter) can follow G1 directly.

**G6. Co-op completeness.** Guests drive, fly, talk, fabricate.

**Later:** Colonies, Hive Homeworld, Gaia, solar travel, weather/seasons, settlement, asset studios.

## Critical files
`src/game/Sandbox.zig`, `src/App.zig`, `src/ui/Menu.zig`, `src/ui/Screens.zig`, `src/procedural/Chunk.zig`, `src/procedural/Worlds.zig`, `src/procedural/Interiors.zig`, `src/game/Progress.zig`, `src/game/QuestLog.zig`, `src/game/conversations.json`, `docs/plans/city-content.md`, `docs/plans/ocean-cities.md`, `docs/roadmap.md`.

## Verification (per stage, per AGENTS.md)
`python3 tools/zig.py build check` and the 0.17 check; `build test` (output to file, grep summary); Metal smoke with `MTL_DEBUG_LAYER=1` and a capture for visual work; reinstall with `build -Doptimize=ReleaseFast`; update `docs/validation.md`. A feature counts as done only when a player can use it in the real game and a test or smoke stage proves it.
