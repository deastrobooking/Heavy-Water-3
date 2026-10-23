# City content plan: three sub-missions, one boss battle and ten item discoveries per city

**Status:** Detroit content approved by the owner as it stands, 2026-10-22 (proposed 2026-10-15; campaign direction updated 2026-10-19). The Foundry Ledger investigation and steward encounter, Windsor Gate investigation, Bile Archive investigation, first playable Collaborators' Titan/liberation path, and ten landmark discovery pickups are implemented. Since 2026-10-22, eight of the ten keepsakes sit in a cage of gates opened by a short platformer course matched to their method (stepping-stone pillars, a crumbling stair, a spring to a ledge, a mover ferry); the bell tower and sky lobby keepsakes remain their landmark climbs. Hands-on tuning remains. The owner has set Detroit and New York City as captured and directed synthetic humanoid warriors to lead their liberation alongside humanity. New York's detailed missions and rewards are intentionally deferred until Detroit's loop is proven. The [roadmap](../roadmap.md) stays the single plan; this is the detail behind milestone B in [next steps](next-steps.md).

**Audience:** the project owner (content), and engineers who will build it. Part 1 to 3 are content; part 4 onward is the technical plan.

## 1. The budget and what it means

Each city carries **three sub-missions, one boss battle and ten item discoveries**.

| Scope | Cities | Sub-missions | Boss battles | Item discoveries |
| --- | --- | --- | --- | --- |
| First city (Detroit Arbor Reach) | 1 | 3 | 1 | 10 |
| Arbor Frontier canopy and river cities | 5 | 15 | 5 | 50 |
| Plus the two ocean cities | 7 | 21 | 7 | 70 |
| All seventeen catalogued city regions (Frontier 7, Hive Homeworld 5, Gaia 5) | 17 | 51 | 17 | 170 |

The totals are plain arithmetic from the budget and the catalog in `procedural/Worlds.zig`. Per [AGENTS.md](../../AGENTS.md), finish **one** city's liberation loop end to end first; the other cities follow the template once it is proven.

**How a city is freed.** Both halves, as in [world](../world.md): the party breaks the Hive in the wilds around the city, and exposes the Hive's human allies inside it. The three sub-missions are the inside half; each exposes one ally. The boss battle is the city's climax and unlocks only when both halves are done. The ten discoveries reward exploring the city and the land around it, whether or not a mission points there.

**Where the pace sits.** Cities are exploration and conspiracy; the wilds are hack-and-slash ([world](../world.md)). The sub-missions are therefore mostly investigation with short combat set pieces, the boss is the one big fight inside a city, and the discoveries are about movement and curiosity.

## 2. Rules every city follows

1. **Exactly 3, 1 and 10.** A city's content table must contain exactly three sub-missions, one boss and ten discoveries; a test fails otherwise.
2. **One ally per sub-mission.** Each sub-mission exposes one distinct human ally of the Hive. [World](../world.md) names scientists and governments; this plan adds a third, industry, so every city has a government, a science and an industry thread.
3. **Evidence is shared, rewards are personal.** Exposing an ally and finding evidence change the shared story (`Progress`). Gear, upgrades, currency and cosmetics go to each player's own `Kit`. Never put a personal reward in shared progress ([AGENTS.md](../../AGENTS.md)).
4. **Every discovery uses a different way of moving or seeing.** Ten discoveries should not be ten walks to a marker. Use the traversal kit the game already has: gliding, grapple rings, swimming and diving, the canopy metro, the Rootway galleries, the sky lobbies, night routes, and the shrine puzzle solver.
5. **No dead ends for the story.** A mission can always be finished by a player who skipped the discoveries; discoveries are never required, but the boss unlock requires the three exposures.
6. **A short, readable objective at every step.** The quest log always shows the next goal, as it does today.
7. **Four players, no one left out.** Anything a mission requires can be done by any player; a second player present at a discovery gets their own reward.

## 3. Detroit Arbor Reach (the first city)

Detroit is "Detroit, Michigan reimagined as a canopy city" with six plazas (0 to 5), three keepers (Maro at plaza 1, Ines at plaza 3, Tavi at plaza 5), Gothic civic halls with clustered spires, a foundry and rail-yard industrial belt (an intentional Hive pressure point), the wide Detroit River with dry, wooded Belle Isle, two heavy bridges toward Windsor, Rootway galleries, a canopy metro, about twenty skyscrapers with sky lobbies, and two Rootdeep shrines below ([city](../city.md), [world](../world.md)). Lore anchor: Dr. Sergio Bile was the Hive's human ally a thousand years ago ([Story](../Story.md)); today's allies are his heirs in spirit.

**Playable slice, 2026-10-21:** Maro can start The Foundry Ledger; three deterministic manifest checkpoints appear beside generated industrial buildings, are recoverable through the normal hands target, and update the quest count. The collected flags persist in shared `Progress`. Once all three pages are recovered, Maro's report conversation sets `foundry_reported`; publishing at the targetable loading-dock console draws out a human steward and two Hive guards. Defeating the group sets `foundry_exposed`, awards Sprint Servos +1 to each active player's own `Kit`, and slides open a visible yard gate. Since 2026-10-22 the closed gate is solid (a static collider from Maro's case until the steward is exposed; a flier can still pass above it), each of the three fighters sets a shared flag when it goes down so a load brings back only those still standing (their health and positions are not saved), and pedestrians within 45 m of the fight turn back and hurry away; they do the same around the Titan.

Ines can start The Windsor Gate after the party has met her. Three deterministic records appear: a log at each bridge control tower and a recording outside the nearest Gothic civic hall. They use normal aim-and-interact targeting, persist as shared flags, and update the quest log. Returning the complete set to Ines sets `windsor_exposed` and animates open the two visual crossing gates. The world map then enables a safe fast-travel stop at each Detroit-side crossing; both rows are visible but disabled beforehand. Dialogue describes a night watch, but this first playable slice has no time-of-day lock, so evidence can be recovered at any hour. The gates are visual and do not change collision.

Tavi can start The Bile Archive after the party has met them. The institute, three deterministic traces, three color-coded relay controls, and Dr. Bile's notes appear on Belle Isle. Each trace reveals one relay symbol and its place in the sequence. The sequence is derived from the verified Rootdeep Shrine solver for the world seed. A wrong relay restarts the attempt; the partial input resets on save load, while collected traces and an opened vault remain in shared `Progress`. Reading the notes and reporting them to Tavi sets `bile_exposed`; each present player receives 60 pet XP for their active pet in their own `Kit`. The institute and its door are visual geometry, with access handled by the case interaction. The Collaborators' Titan can now be fought after the three reports and a cleared Frontier. Defeating it awards each present player and marks Detroit free when the Frontier remains clear.

The ten optional discoveries appear as glowing, targetable keepsakes around the seeded skyline and city landmarks: the tallest Gothic spire, a market terrace, the plaza 3 loading deck, plaza 5, Belle Isle, the east Windsor bridge, the river promenade, a metro stop, a Rootway gallery and a tower roof. Personal rewards claim independently in each player's `Kit`; the Rootmap, Arboretum Seed and Time Capsule set shared `Progress` flags once. The reward mapping follows the draft: fuel, sprint and jet upgrades, a grapple upgrade, a transit scrap voucher, Gem Aegis armor, and Lumi the moth, with scrap compensation at upgrade/ownership caps. Each marker uses the normal aim/interact flow. Method labels such as swim, glide, grapple and wiring remain design intent rather than separate challenge mechanics in this pass. Markers are temporary props; the skyline and bridge arena still need visual cleanup and hands-on review. **Approach challenges (2026-10-22):** `game/Challenges.zig` lays, from the seed, a five by five cage of gates around each ground-level keepsake and a course of city blocks beside it ending on a pressure plate that opens the cage for 8 s. Methods map to four courses, each ending on a plate 16 m up so the 9 m running jump cannot skip it even from the cage roof: service stairs and the gallery trail to a spiral tower of crumbling steps, the trail, the bridge rings and the dive to a spiral tower of stone steps (four steps rising 3 m around the plate column), the wiring puzzle and the glide to a spring on a 5 m pillar that throws you onto the plate's ledge, and the metro ride to a mover between a spiral tower and the plate column. Courses and cages keep off the plaza hubs, the lines to each bridge, the bridge decks and the Arbor spurs; a keepsake whose spot has no room moves to the nearest open spot on the same floor (the plaza 1 aisle, plaza 5, the metro station and the root gallery keepsakes move). Every course is checked finishable by `Course.reachable`. The challenge blocks are part of the city: not saved, never removable or refundable, rebuilt after every load. Fixed on the way: the loading-deck keepsake was placed 25 m from its plaza centre, past the 20 m deck, and floated 50 m above the ground; it now sits at 18.5 m.

### 3.1 Sub-missions (proposed)

Each mission has a giver among the existing keepers, so no new quest-giver system is needed. The ally names are placeholders.

| # | Mission | Ally exposed | Giver | Place | Outline |
| --- | --- | --- | --- | --- | --- |
| 1 | **The Foundry Ledger** | Industry: the foundry syndicate's steward, who sells sap and alloy to the brood | Maro (plaza 1) | the industrial belt, machine works and rail yards | Maro notices rotor cores going missing. Trace the shipments through three checkpoints, recover manifest pages from the machine works (a short fight against brood scavengers), and confront the steward at the loading dock. |
| 2 | **The Windsor Gate** | Government: a civic councillor who lets Hive carriers cross at night | Ines (plaza 3) | the two heavy Windsor bridges and the Gothic civic hall | Ines hears the toll gates open after dark. Watch the bridges at night, collect gate logs from the control towers, and record a closed session in the civic hall. |
| 3 | **The Bile Archive** | Science: an institute on Belle Isle that keeps Dr. Bile's bioengineering notes and trades with the Hive | Tavi (plaza 5) | Belle Isle, reached by glide or boat, and the institute vault | Tavi finds Rootdeep tracks leading to the island. Recover three trace fragments, use their ordered relay symbols to open the archive, read the notes, and expose the director. The relay order is seeded from a verified Shrine solver plan. |

Each mission ends with an **exposure scene** (a short cinematic, see [engine features](engine-features.md) E4) and sets one shared flag. Missions can be done in any order. Ending beats and rewards:

| Mission | Shared result | Personal reward (each player) |
| --- | --- | --- |
| The Foundry Ledger | the steward is exposed; the foundry yard opens | a suit upgrade from Maro |
| The Windsor Gate | the councillor is exposed; the Windsor bridge gates open for the party | a travel upgrade (fast-travel stops at both crossings) |
| The Bile Archive | the director is exposed; the Bile notes are read | 60 pet XP for each present player's active pet |

### 3.2 Boss battle (draft; first playable pass)

**The Collaborators' Titan.** When all three allies are exposed and the surface/cave nests and Brood carriers are down, approaching the west Windsor bridge wakes the existing Scalari Titan frame. Its saved `titan_started` flag survives loads; live enemies and phase restart after a load or long retreat. The encounter reuses the existing Titan combat state machine, calls two drones and a bulwark together at 66% health, then stuns the Titan for a 2.8-second core exposure at 34%. Three lit pylons echo the allies' colors. They and the bridge gate are visual markers without collision; there is no bespoke crane animation or behavior tree yet.

- **Why this boss:** it reuses assets the game already has (the Scalari titan frame and the Hive Forge kit) and ties the fight to the story: each exposed ally weakens one of the titan's three modules, so the investigation visibly pays off.
- **Implemented reward and outcome:** when the Titan and all spawned reinforcements are defeated, each present player's `Kit` receives 1200 combat XP, 120 scrap, 18 parts, and two rotor cores. If nests and carriers remain cleared, shared `Progress` records Detroit as free. The ten discoveries remain optional to the flag transition; they are implemented (eight caged behind platformer courses, two landmark climbs) and described above.
- **Future encounter work:** author a distinct crane-slam animation/attack and behavior-tree version only after the existing boss fight has been tested by hand; the current encounter does not use the planned ability core or behavior tree.
- **Alternatives for the owner:** a staged Brood carrier siege over the city (the carrier assault tech exists: flak turrets, bays, then the core) or the bio-titan kaiju-scale mutant; either could serve a later city so the cities do not repeat.
- **Reward:** the city's liberation outcome (shared) and a boss reward for each player's `Kit`.

### 3.3 Ten item discoveries (proposed)

Each discovery is a hidden object or place found by exploring. Names are placeholders. "Personal" goes to each player's `Kit`; "shared" sets a shared flag for the whole team.

| # | Discovery | Where | How you find it | Reward |
| --- | --- | --- | --- | --- |
| 1 | The Bell Tower cache | a Gothic spire | grapple and climb the spire | personal: a flight-cell upgrade |
| 2 | The undercroft stash | below the plaza 1 market | find the service stairs | personal: a suit upgrade |
| 3 | The sealed sap barrel | plaza 3 loading deck | a puzzle with machine wiring | personal: an energy upgrade |
| 4 | The scout's rootmap | plaza 5 | follow Tavi's chalk marks | shared: a Rootdeep route on the map |
| 5 | The arboretum seed | Belle Isle | glide across the river | shared: a tree species unlocked for the nature studio |
| 6 | The pylon relic | a Windsor bridge pylon | grapple rings under the deck | personal: a grapple upgrade |
| 7 | The riverfront time capsule | the promenade | dive and swim the river | shared: lore |
| 8 | The ghost station | the canopy metro | ride to a closed stop | personal: a travel item |
| 9 | The Rootway gem | a root gallery | follow the gallery's lumen trail | personal: a jeweled-armor gemstone |
| 10 | The collar chest | a sky lobby | reach it through a tower | personal: frees a pet |

Spread: five personal upgrades, two cosmetic or pet items, three shared (story or map). Discoveries 5 and 7 are optional lore; none is needed to finish a mission.

### 3.4 Liberation

Detroit is freed when: the three exposures are set, the surrounding nests and carriers are down, and the boss is defeated. The outcome is a shared story state, saved with the world, plus a visible change (the Hive stain recedes from the industrial belt) and each player's boss reward in their own `Kit`.

## 4. New York City and the other Earth cities (outlines)

These come from each region's role and exploration hook in `Worlds.zig`. They show that the template fits; they are not written content. Write each only when its turn comes.

| City | Role | Government thread | Science thread | Industry thread | Boss idea |
| --- | --- | --- | --- | --- | --- |
| **New York City: Hudson Reach** | Captured Hudson-side metropolis; dense towers, elevated green routes, river approaches and transit corridors under Hive occupation | Occupation permits and sealed evacuation routes | A research lab trading city records for Hive protection | Industrial docks and automated supply routes feeding the garrison | A Scalari occupation commander controlling linked skyline relays |
| Rootdeep Ward | seed vault: buried engineer vaults and machine shrines | a vault warden who sells access | a seed-bank archivist | tomb-salvage guild | a vault guardian machine |
| Crownfall | observatory over the mountain ranges | a listening-post officer | astronomers hiding signals | high-cable foundries | a Brood carrier siege (the observatory's sky) |
| Bridgewell | bridge foundries and vehicle test routes | a transit commissioner | an engineering lab | foundry contractors | a titan on the test route (a vehicle chase) |
| Solace Basin | river locks, waterworks and a landing zone | a water authority | a hydrology institute | lock and pump operators | a river-surge boss |
| Pelaglass and Sonorous Reef | the two ocean cities | follow the [ocean-cities plan](ocean-cities.md) | | | |

The New York hooks are campaign direction only; its mission names, boss encounter, ten discoveries and rewards are not drafted. The current NYC foothold is an arrival district, not a full city. Per [AGENTS.md](../../AGENTS.md), finish Detroit end to end before building New York's loop. Hive Homeworld and Gaia each have five catalogued regions (for example Varkhoss and Faraday Deep). Planets beyond Earth are deferred; the template applies when they are reached.

## 5. Technical plan

### 5.1 What exists to build on

- **Quest log.** `game/QuestLog.zig` derives the current objective from saved story flags and live war state with one chain of conditions (Tavi, the first spire, Ines, the carrier, Maro's Kestrel, the nests).
- **Flags.** `Progress` stores story flags as names with a hard cap of 96 (`max_flags`); about 30 literal flag names exist today plus indexed families such as `nest_N_down`. A city by this design needs roughly 20 to 25 more (three missions with a few flags each, two boss flags, liberation), so the first city fits, but the third would not.
- **Collected objects.** `Modifications` tracks collected and removed object ids (capacity 4,096), keyed by chunk and local id, which suits discoveries.
- **Conversations.** `conversations.json` has speakers (`maro`, `ines`, `tavi`, `local`) and conversations (three keepers and four walkers).
- **Collectibles.** `Collectibles.Kind` is `lumen_shard`, `rotor_core`, `hive_alloy`, `vital_cell`; discoveries are a new kind of object, not these.
- **Bosses and kits.** `Enemies.Kind` includes `scalari_titan`; `EnemyDesign` swaps seven modules and five palettes; the carrier assault has staged destruction.
- **Per-player and shared state.** `Kit` per player, `Progress` shared; saves are versioned with `Save.min_supported_format`.

### 5.2 Data model

A city is one validated table, so adding a city is data, not code. Sketch (not compiled):

```zig
pub const CityContent = struct {
    id: []const u8,                        // "detroit"
    missions: [3]Mission,
    boss: Boss,
    discoveries: [10]Discovery,            // exactly ten: the array length is the budget
};
pub const Mission = struct { id: []const u8, giver: []const u8, ally: Ally, steps: []const Step, shared_flag: []const u8 };
pub const Discovery = struct { id: []const u8, anchor: Anchor, how: Method, reward: Reward };
pub const Reward = union(enum) { personal: PersonalReward, shared_flag: []const u8 };
```

Fixed array lengths make "exactly 3, 1 and 10" a compile-time fact for built-in cities. Anchors name an existing generator anchor (a plaza, a landmark, a bridge pylon) so placement follows the seeded district and never floats or clips.

### 5.3 Phases

Sizes: S under a day, M a few days, L about a week.

**C0. Approve the content (owner, S).** Approve or change section 3, including the allies, the boss and the ten discoveries. Nothing below starts on unapproved content.

**C1. Data-driven city content and quest log (M).**
1. Add the `CityContent` table and a validator (counts, unique stable string ids, every flag name legal, every anchor resolves).
2. Replace the quest log's hard-coded chain for the city with a table-driven objective list; keep the existing Hive campaign objectives working unchanged.
3. Decide flag storage before the second city: raise `max_flags` or move per-city flags into a per-city bitset. Either changes the save: bump `Save.format_version`, migrate, add a round-trip test.

*Tests:* every shipped city has exactly 3, 1 and 10; ids are unique across cities; the quest log's next objective is correct for each saved state; the old objectives still read correctly.

**C2. The discovery system (M).**
1. A discovery object with a collection prompt, a banner, a sound, a map marker and a "found" state kept in the collected-object table.
2. Reward routing: personal rewards go to the collecting player's `Kit` (each present player gets their own copy for upgrades); shared rewards set a `Progress` flag.
3. Place Detroit's ten.

*Tests:* a collected discovery stays collected after a save round trip; a personal reward lands only in the right `Kit`; with two players present each gets theirs; every discovery is reachable from the spawn by the traversal kit (a reachability test over the seeded district); no two discoveries overlap.

**C3. Sub-mission 1 end to end (M).** The Foundry Ledger is now playable from Maro's conversation through three evidence checkpoints, the dock ambush, exposure, reward and quest log. Gate collision, per-fighter saved progress and civilian evacuation were added 2026-10-22; hands-on balance and polish remain. This proves the template for the remaining city content.

**C4. Sub-missions 2 and 3 (M each).** The Windsor Gate (night bridge observation, gate logs, the civic hall) and The Bile Archive (Belle Isle, the vault puzzle, the notes).

**C5. The boss battle (L).** Depends on the ability core and behavior trees ([engine features](engine-features.md) E1 and E2) for the three-phase fight and its effects. A first version can use the existing Scalari titan frame with a simple phase script, then move onto the behavior tree.

**C6. Liberation outcome (S to M).** The shared liberation state, the visible change in the district, the boss rewards, and the saved result. Add the end-to-end test that follows a save from the first conversation to liberation.

**C7. Cinematic beats (optional, M).** The exposure scenes and the boss introduction as short skippable sequences ([engine features](engine-features.md) E4); a rough budget of nine per city (an opening and an outcome for each mission, a boss introduction and defeat, and a liberation finale). Missions work without them, using dialogue and a banner.

**C8. The next city.** Copy the proven template for the next Earth city.

### 5.4 Validation and acceptance

- **Per city:** the count test (3, 1, 10); the save round trip; the reachability test; a real-game Metal smoke stage that completes a sub-mission and collects a discovery, with the result saying what was and was not checked ([validation](../validation.md)).
- **Acceptance for Detroit:** a new save can follow the objectives, expose all three allies, defeat the boss, and see Detroit liberated; each player keeps their own rewards; shared story state survives a reload.
- **Budgets:** the frontier benchmark's simulation p99 stays under 4 ms and render CPU under 16.667 ms with the boss fight active (2.815 ms and 4.879 ms in the 2026-10-14 baseline).

## 6. Risks

| Risk | Mitigation |
| --- | --- |
| The flag cap (96) runs out by the third city | decide the storage in C1; do not start the second city before it |
| Missions rely on features not built yet (boss tree, cinematics) | C3 to C4 use dialogue and banners; the boss starts on the existing titan frame |
| Ten discoveries become ten marker walks | rule 4: a different movement or sense for each, reviewed per city |
| Creative drift from the lore | every named person, place and boss is approved in C0 and recorded here |
| Four-player fairness in rewards | rewards are per player by rule 3, with a two-player test |
| Scope against other tracks | this is the MVP gate; the asset studios and nature plan are time-boxed against it ([next steps](next-steps.md)) |

## 7. Decisions for the project owner

1. **Approved 2026-10-22:** Detroit's section 3 as it stands (the three allies, the Collaborators' Titan, the ten discoveries). `CityContent.detroit.draft` is false.
2. **What counts as an "item discovery":** a physical item you pick up, a place you find, or either (this plan allows either).
3. **Reward routing:** each present player gets a personal reward copy (this plan), or only the player who found it.
4. **Boss reuse:** the same titan frame with different modules in each city, or a different boss type per city (carrier, bio-titan, vault guardian).
5. **Capitals:** whether the home bases and the final capital (Crown Harbor, Concord Spire, the Obsidian Coil) count as cities with this budget or have their own plans.
6. **Ocean cities:** whether Pelaglass and Sonorous Reef follow the same budget or the [ocean-cities plan](ocean-cities.md).

## 8. Reference

Sources read: [Story.md](../Story.md), [world.md](../world.md), [city.md](../city.md), [gameplay_and_hive_war.md](../gameplay_and_hive_war.md), [planetary-frontier.md](planetary-frontier.md), [QuestLog.zig](../../src/game/QuestLog.zig), [Progress.zig](../../src/game/Progress.zig), [Collectibles.zig](../../src/game/Collectibles.zig), [Enemies.zig](../../src/game/Enemies.zig), [EnemyDesign.zig](../../src/game/EnemyDesign.zig), [Worlds.zig](../../src/procedural/Worlds.zig), [conversations.json](../../src/game/conversations.json).
