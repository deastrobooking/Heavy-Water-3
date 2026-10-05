# Planetary frontier: arenas, ships and colony strategy

## Goal

Grow the current Arbor frontier into a three-destination campaign. Each destination contains several bounded, open arena regions sized for four local players, plus distinct encounter and construction sites. Players fight Hive forces, recover materials and design custom ships, then use the recovered supplies to establish and defend planetary outposts through a real-time strategy layer.

The two destinations added by this plan are the Hive Homeworld and **Gaia**, an artificial planet housing a human colony beyond Jupiter. The existing Arbor Frontier remains the party's shipyard, tutorial space and first source of parts.

The initial catalog lives in `src/procedural/Worlds.zig`. It names the destinations and arena concepts, sets local arena bounds and reward targets, and derives stable seeds from a campaign seed. It is metadata for the next implementation work: it does not yet generate these regions or connect them to travel, gameplay, or saves.

## Session loop

1. Choose a destination and mission from the shipyard's route table.
2. Land a four-player party in a 1–2 km playable region. The area is an open environment with multiple approaches, landmarks, caches, and extraction routes rather than a closed wave arena.
3. Complete a combat or exploration objective and collect physical loot. All local players can contribute; shared party inventory prevents player four from being locked out of ship construction.
4. Extract or return to the local command site. Spend materials and fabrication data on ship modules, new chassis rules, and planetary structures.
5. Place an outpost, run it in real time, gather local resources, and defend it from counterattacks. Its output opens more mission sites and supplies the next expedition.

The default combat contract is cooperative PvE. Damage between players and competitive arena rules can be a separate opt-in mode after the co-op loop works.

The first campaign route is: restore the Frontier launch pad and recover a drive core; use the new ship to reach the Hive Homeworld; recover a colony distress archive from the Hive brood network; then open the Gaia route and repair its geodesic spine. Both destinations remain revisitable, so materials and outposts support several valid ship builds instead of one irreversible mission chain.

## Destinations

| Destination | Identity and play space | Primary materials | Strategic role |
| --- | --- | --- | --- |
| Arbor Frontier | Existing canopy city, Rootdeep, shrines and Hive outskirts. Expand the current area into a few authored encounter basins without replacing its hub. | Lumen, rotor cores, recovered fabrication data, some Hive alloy | Safe shipyard, tutorials, first outposts and the route map |
| Hive Homeworld | Chitin shelves, brood tunnels, sulfur vents, resin rivers, carrier landing scars and enormous living structures. Arenas emphasize nests, salvage convoys and assaults on brood infrastructure. | Hive alloy, brood enzymes, rotor cores, alien fabrication data | High-threat source of living ship systems and the campaign's Hive objectives |
| Gaia | Earth-radius artificial planet with a rotating surface, human colony biomes and a giant geodesic enclosure. Its inner shell is designed to leave about one mile of sky above nominal sea level; terrain and towers must remain within that envelope. The colony is located beyond Jupiter and is reached through orbital travel. | Geodesic alloy, colony fabrication data, terraforming cultures, recovered human tech | Human-built ship systems, strategic construction and restoration of the colony |

Gaia's 24-hour rotation is the initial Earthlike design target, subject to tuning. The shell is an interior landmark and traversal boundary, not a single monolithic mesh: represent it as stable geodesic cells and stream visible cells near the active region. A failed cell can become a repair or combat objective. Keep Earth-scale radius and travel metadata out of f32 gameplay positions.

## Four-player arena contract

- Every region supports one to four local players and works in the current split-screen renderer. Co-op objectives scale enemy pressure and reward count with party size, but do not multiply required travel distance.
- A playable region targets a 1.3–1.7 km diameter with a central objective, at least two approach routes, 4–8 points of interest, optional caches, an extraction site and 2–8 legal outpost sites.
- Keep the arena finite even when its planet is globe-sized. Generate terrain and collision in a local tangent frame centered on the landing zone. Store the sector by stable world/region ID and integer grid coordinates; do not simulate absolute Earth-radius XYZ values.
- Seed each world, arena, terrain layer, loot table, enemy director and structure layout from independent hashes of the campaign seed. Changes in Gaia generation must not reshuffle Hive caches or invalidate Frontier pickups.
- Objectives should use existing systems where they fit: destroy/disable a Hive nest, restore a shrine or machine, recover cargo, defend an extractor, repair shell relays, and extract with a data core.
- Each loot item has a world-stable ID and its collected state belongs to that world's save. Temporary enemy drops may remain unsaved. Four-player collection feeds one shared campaign inventory until a later design explicitly needs per-player ownership.

## Ship design and fabrication

The design bay turns recovered modules into a saved ship blueprint. Use the pasted ship-grammar idea—core, wings, engines, weapon hardpoints, shields and utility modules—but keep it inside the existing Zig simulation and `vehicle/` mesh/physics pipeline. Do not add a parallel ECS or a second game loop.

The composition pass should place modules from typed 3D attachment points, reject disconnected or overlapping layouts, and derive mass, center of mass, inertia, thrust, steering torque, hull integrity and energy capacity from module data. Validate symmetry or a declared asymmetric handling profile, minimum control authority, hardpoint clearance and resource cost before fabrication. Build a rotatable 3D preview from the same blueprint that produces the flight mesh. Ship seeds vary shape within the selected module recipe; players retain control over meaningful parts and weapon roles.

Arena rewards unlock new module families rather than directly granting unbounded stats. Frontier rotor cores establish reliable drives; Hive enzymes unlock bio-reactive frames and repair; Gaia's geodesic alloy unlocks light but durable hulls, shield lattices and settlement equipment. A fabricated blueprint is persistent campaign content; arena ships and mission damage have separate runtime state.

Ship flight, combat, and previews remain fully 3D. Use the existing fixed-step Zig physics and rigid-body types for six-degree-of-freedom motion, collisions, and inertial handling; keep Mach as the platform/rendering layer and do not add a parallel ECS.

## Planetary strategy layer

Begin with a small co-op command view attached to an in-world command hub. Pause is optional; the strategic simulation should be real time by default. The world keeps simulating while players place buildings and assign jobs.

Initial building set:

- **Command hub:** territory anchor, build queue and local spawn/extraction point.
- **Extractor:** gathers the arena's main resource from a marked node.
- **Power unit and relay:** power sources and a short-range graph, reusing machine power rules where possible.
- **Fabricator:** turns ore and data into ship modules, ammunition and structures.
- **Habitat:** increases population/worker capacity and offers a safe respawn.
- **Defense turret:** uses existing projectile and enemy target code; requires power and ammunition.
- **Landing pad:** stores a fabricated ship and enables departure.

Players gather resources in third person, then can take different jobs: one explores, one builds defenses, one pilots/escorts, and one operates the command view. Structures occupy validated sites with explicit costs, power demand and health. Hive threats target extractors and relays first; successful defense produces supplies, while losing a site creates a recoverable reclaim mission instead of deleting the campaign.

Use bounded structure and agent pools, fixed-step simulation, seeded spawn schedules and event queues. Reuse `game/Build.zig`, `machine/Blueprint.zig`, `machine/Machine.zig`, `game/Enemies.zig` and `game/Progress.zig` where appropriate. Keep arena rendering and simulation snapshots compatible with the existing render mutex and split-screen views.

## World travel and persistence

Treat the current save as the Arbor Frontier's world state. Add a campaign envelope containing campaign seed, unlocked destinations, saved ship blueprints, shared fabrication inventory and a small index of world records. Each world record owns its seed, generator versions, collected stable loot IDs, structures, local objective flags and last safe landing point. Loading one arena must not erase another world's progress.

Travel proceeds from shipyard to orbit to a named region. Initially, transitions may be explicit load screens; seamless planetary entry is not a requirement. A mission can load its bounded region and restore the command hub, loot, structures and enemy director from that world's record.

World ID, arena ID, generator version and campaign-save format must be validated before applying state. Continue to use f64 or integer geography for planet coordinates and f32 only for the local arena frame. Gaia geodesic cells use face/cell IDs, not one giant high-resolution sphere mesh.

## Delivery sequence

1. **Catalog and design foundation (current slice):** deterministic world and arena metadata, destination seeds, Gaia dimensional rules, reward budgets and this design contract. Test identity stability and four-player arena bounds.
2. **Frontier arena vertical slice:** make one existing Hive basin a selectable 4-player mission with physical loot, extraction, stable IDs and save/restore. Keep the Arbor city as the shared hub.
3. **Ship design bay:** typed modular blueprint, composition validation, preview mesh, derived physics values, player-facing part selection and blueprint persistence. Start with a small module family.
4. **Planetary RTS slice:** one command hub, extractor, power graph, fabricator and turret in that Frontier arena; defend against a seeded Hive raid and save the result.
5. **Hive Homeworld:** add its first arena, resource sources, brood objective and a ship part set; use the same runtime arena and save contracts.
6. **Gaia:** add local tangent sectors, geodesic shell cells, colony arena, materials and terraforming/building objectives. Validate shell clearance against terrain and structures.
7. **More regions and networking:** grow each world to multiple arenas, then implement remote four-player sessions with the existing networking plan.

## Acceptance gates

- Same campaign/world/arena seed reproduces terrain, POI, loot IDs and enemy schedule; changing one world's generator does not alter another.
- A four-local-player run can start, fight, collect, extract, build and save/reload one arena without player count changing the saved loot identity.
- Two different valid ship blueprints produce distinct silhouettes and measurable handling values; invalid graphs and unaffordable fabrication change neither inventory nor saved blueprint state.
- The RTS slice gathers, spends and persists resources; power loss disables structures; a deterministic raid can be won or can damage a recoverable outpost.
- Gaia's local sectors stay in bounded f32 coordinates, show a rotating sky/shell reference, and reject geometry outside the one-mile design envelope.
- Record Debug/ReleaseSafe tests, a four-player smoke, render/simulation budgets, and a manual controller pass for every milestone.

## Explicitly not in the first slice

Planet-wide seamless traversal, orbital mechanics, interstellar distances in the renderer, online multiplayer, player-vs-player combat, a full RTS tech tree, autonomous civilization simulation, and complete continents are later work. The first playable goal is one small arena that joins combat loot, a custom ship blueprint, a defensible outpost and persistent four-player co-op.
