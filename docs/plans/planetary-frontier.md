# Planetary frontier: arenas, ships and colony strategy

## Goal

Grow the current Arbor frontier into a three-destination campaign. Each destination contains several bounded, open arena regions sized for four local players, plus distinct encounter and construction sites. Players fight Hive forces, recover materials and design custom ships, then use the recovered supplies to establish and defend planetary outposts through a real-time strategy layer.

The two destinations added by this plan are the Hive Homeworld and **Gaia**, an artificial planet housing a human colony beyond Jupiter. The existing Arbor Frontier remains the party's shipyard, tutorial space and first source of parts. The Hive Homeworld is also the Scalari homeworld: the Scalarians are an ancient synthetic AI civilization that left Earth and engineered insects into the first Hive castes. This is one destination and one connected history, not a separate Scalari planet.

The initial catalog lives in `src/procedural/Worlds.zig`. It names the destinations, city regions, each world's capital, and arena concepts; it sets local arena bounds and reward targets and derives stable seeds from a campaign seed. The Arbor Frontier catalog now has seven city concepts: its five canopy/river regions plus Pelaglass and Sonorous Reef. The underwater paired-city design is in [the ocean-cities plan](ocean-cities.md). The Scalari ship meshes live in `src/vehicle/ScalariMeshes.zig` and are registered in the asset catalog. This is authored content groundwork: city geometry, ship spawning, travel, missions, and saves are not connected yet.

The separate Solar System level sequence—including bounded moon landing zones, the first mining and settlement arc, and the asteroid-belt mission—is designed in [Solar democracy](solar-democracy.md#level-designs-first-solar-prospecting-arc). It is not runtime content and does not change this three-destination Arbor/Hive/Gaia campaign plan.

## Session loop

1. Choose a destination and mission from the shipyard's route table.
2. Land a four-player party in a 1–2 km playable region. The area is an open environment with multiple approaches, landmarks, caches, and extraction routes rather than a closed wave arena.
3. Complete a combat or exploration objective and collect physical loot. All local players can contribute; shared party inventory prevents player four from being locked out of ship construction.
4. Extract or return to the local command site. Spend materials and fabrication data on ship modules, new chassis rules, and planetary structures.
5. Place an outpost, run it in real time, gather local resources, and defend it from counterattacks. Its output opens more mission sites and supplies the next expedition.

The default combat contract is cooperative PvE. Damage between players and competitive arena rules can be a separate opt-in mode after the co-op loop works.

The first campaign route is: restore the Frontier launch pad and recover a drive core; use the new ship to reach the Hive Homeworld; explore its five city regions and recover a colony distress archive; then open the Gaia route, visit its five city regions, and repair its geodesic spine. Gaia's recovered records reveal the Scalari capital's defense network. Players return to the Hive Homeworld, break the capital shield, defeat the Throne Serpent and confront the Scalari Sovereign at the Obsidian Coil. The three destinations remain revisitable, so materials and outposts support several valid ship builds instead of one irreversible mission chain.

## Destinations

| Destination | Identity and play space | Primary materials | Strategic role |
| --- | --- | --- | --- |
| Arbor Frontier | Existing canopy city, Rootdeep, shrines and Hive outskirts. Expand the current area into a few authored encounter basins without replacing its hub. | Lumen, rotor cores, recovered fabrication data, some Hive alloy | Safe shipyard, tutorials, first outposts and the route map |
| Hive Homeworld | Chitin shelves, brood tunnels, sulfur vents, resin rivers, carrier landing scars and enormous living structures. Arenas emphasize nests, salvage convoys and assaults on brood infrastructure. | Hive alloy, brood enzymes, rotor cores, alien fabrication data | High-threat source of living ship systems and the campaign's Hive objectives |
| Gaia | Earth-radius artificial planet with a rotating surface, human colony biomes and a giant geodesic enclosure. Its inner shell is designed to leave about one mile of sky above nominal sea level; terrain and towers must remain within that envelope. Its visual identity mixes early pressure-era industrial craft with advanced additive-built megastructure: riveted service gantries and copper/brass instrumentation support printed-composite ribs, ceramic shell panels and green civic terraces. The colony is located beyond Jupiter and reached by campaign fast travel. | Geodesic alloy, colony fabrication data, terraforming cultures, recovered human tech | Human-built ship systems, industrial habitat construction and restoration of the colony |

## Cities and capitals

Hive Homeworld and Gaia each have five major city regions. The Arbor Frontier has those five original canopy and river regions plus the two planned ocean cities. These are large authored regions with connected interiors, routes into their surrounding biome, and nearby outpost sites; they are not isolated menu missions. The names and hooks below are stable campaign IDs in `Worlds.zig`, while their geometry remains future work.

| Destination | City regions |
| --- | --- |
| Arbor Frontier | Arboris Reach (canopy market and shipyard route); Rootdeep Ward (seed vaults and machine shrines); Crownfall (high observatory); Bridgewell (bridge foundries and vehicle routes); Solace Basin (river locks and frontier landing zone); Pelaglass (human pressure-dome city); Sonorous Reef (fully submerged cetacean city) |
| Hive Homeworld / Scalari homeworld | Varkhoss (Scalari ruins and origin records); Nacre Spindle (resin industry); Sable Crucible (armor forge); Threxian Fold (modified-insect brood districts); Broodheart (Hive command nexus) |
| Gaia | Meridian Habitat (first landing terraces); Aster Vale (farms and pollinator forest); Faraday Deep (science district and shell relay); Equator Garden (climate reserve); Jovian Gate (cargo and orbital port) |

Each world also has a distinct capital-base site. Crown Harbor is the Arbor party's home base. Concord Spire is Gaia's colony command center. **The Obsidian Coil**, a Scalari throne-base built around the Hive command heart, is the final campaign capital. The Scalari Sovereign is the final boss. Keep this final battle as a bespoke multi-stage 3D encounter: disable exterior shield relays, fight through the capital's interior modules, assault the Throne Serpent's exposed systems, then duel the Sovereign in the throne chamber. These stages are design targets, not implemented gameplay.

## Scalari fleet design

The Scalarians should read as an ancient synthetic civilization whose hard-surface engineering echoes a dragon: horned prow armor, layered scale-like plates, transformable wing frames, segmented mechanical tails and bright sensor/reactor slits. Their silhouettes stay mechanically plausible as 3D aircraft and capital ships, with joints, lift/drive hardware and weapon mounts visible under the armor. Use restrained cel-shaded materials so shape reads before glow.

| Ship | Role | Palette and signature |
| --- | --- | --- |
| Ember Wyrm | Agile interceptor | Crimson and obsidian plates with ember-orange eyes and engine glow |
| Void Lance | Long-range strike fighter | Amethyst armor, black underbody and acid-green systems; forward lance rails |
| Dreadclaw | Heavy fighter / bomber | Black-violet armor, orange plating, green targeting light and paired cannons |
| Throne Serpent | Scalari command mothership and endgame boss craft | Red-black armor, violet reactor marks, dorsal scale rows and broad scythe wings |
| Worldcoil Ark | Expedition / Hive foundry mothership | Purple-green armor, orange hangar wells, brood-transfer bays and cargo capacity |

These five complete 3D shell-and-glow meshes are currently generated and registered as assets. The next vehicle slice should give each chassis a typed flight profile, colliders, damage zones, weapons and deployment rules; do not make a render-only ship look playable before it can be piloted or fought.

The Hive is an insect-derived civilization engineered as the Scalarians' labor force and warrior caste. The Scalarians are synthetic AI overlords in modular, transforming frames with plated dragon silhouettes. Existing wasps and Brood carriers express the Hive's insect-derived forms; hybrid soldiers can combine insect bodies with Scalari control and weapon systems while remaining distinct from fully synthetic Scalari units.

## Planet feature packs

Each destination assembles the same bounded-region runtime from typed feature modules in `src/procedural/Worlds.zig`: traversal, hazards, city systems, enemy roles, and objective verbs. A feature pack is authored data only until a mission instantiates it; the current catalog does not make these planetary regions playable.

| Destination | Movement and environmental pressure | Interactive city modules | Combat and mission identity |
| --- | --- | --- | --- |
| Arbor Frontier | Canopy parkour, bridge-to-bridge grapples, pressure-lock transitions, river surges and leaking domes | Walk-in interiors, root lifts and bridges, pressure locks, current lanes, civilian rescue | Hive skirmishers, burrowers, brutes, screamers and carriers; expose collaborators, restore utilities, destroy nests and stabilize domes |
| Hive Homeworld | Chitin wall climbs, narrow brood tunnels, resin floods, spore bursts and sulfur vents | Living doors with power or pressure controls, resin pipes that can be rerouted, vats that can be sabotaged, captive-lineage rescue | Hive role combinations mixed with Scalari duelists, lancers and interceptors; cut production and rescue captives before the capital siege |
| Gaia | Colony rooftops, shell walkways and active fabrication yards; climate fronts, shell breaches and local micro-meteor events | Walk-in habitats, tram lines, climate controls, repairable geodesic cells, material lifts, robot print cells and evacuation systems | Mixed Hive infiltrators, Scalari units and rogue colony drones; expose infiltration, protect or redirect builder swarms, evacuate civilians, restore climate and shell integrity |

The modules should create short, readable interactions with world-state consequences: rerouting a resin pipe changes a hazard lane; repairing a shell cell closes a breach and opens a walkway; restoring an ocean pressure lock makes a building and its swim route safe. Keep these interactions authored as small subsystem interfaces that plug into the shared objective and save contracts, rather than planet-specific copies of the city or mission loop. City interiors should support entry, traversal, combat or conversation, and a persistent result before returning to the exterior route.

### Gaia habitat industry and builder swarms

The construction skyline should communicate a working colony: foundries, feedstock silos, cargo lifts, pressure-rated gantries, orbital docks and modular yards surround neighborhoods instead of reducing the city to decorative towers. A robotic print crew is a small interacting system built from swappable roles: surveyors mark the next stable anchors; frame printers lay geodesic ribs; skin drones apply pressure panels; weld/repair units close seams and patch damage; haulers keep each crew supplied. Show progress one bounded shell cell or habitat module at a time, with visible material and power links. Keep autonomous work deterministic and local to the active region; a swarm is an objective-scale crew, not a simulation of millions of independent bots.

Player interactions should reuse the shared city-module/objective contract: reroute feedstock, restore a power relay, set a safe print order, defend a crew from Hive or Scalari attack, free a disabled bot, or choose whether to prioritize a public walkway, habitat seal or industrial expansion. Success changes the local structure and opens a useful route or service; failure pauses work and may leave a readable hazard, such as an exposed edge or unfinished pressure cell. Let planting decks, orchards, wetland filters and shaded commons occupy completed frames, with nature integrated into city utilities as well as vistas. Copper, brass, enamel signs, exposed fasteners, analog gauges and steam-like vent plumes provide early industrial character; the actual shell remains high-performance printed composite, ceramic, glass and alloy. Use broad cel-shaded silhouettes, hand-painted sky and planetary views, warm industrial lights against cool twilight, and monumental framing for an original 1980s space-epic feeling without quoting a particular film or franchise.

This is a design and interaction contract only. Current Gaia records describe city identities and shell scale; no fabrication-yard geometry, builder swarm, settlement economy or player-driven construction loop is implemented yet.

The settings row **MAX PROGRESSION TEST MODE** unlocks the current game's highest player and team progression for late-game system checks. It holds a full pre-test world snapshot in memory, never writes a world or ranger save while enabled, and restores that baseline when turned off. It leaves objective-completion flags alone so it does not skip existing campaign beats. Planet travel and planetary mission logic remain unavailable until those slices are implemented.

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

1. **Campaign and Scalari art foundation (current slice):** stable world/arena IDs, named city-region records, a capital per world, Gaia dimensions, reward budgets, Scalari history, and five registered Scalari ship meshes. Test city counts, capital uniqueness, final-boss placement, mesh construction and seed stability.
2. **Frontier arena vertical slice:** make one existing Hive basin a selectable four-player mission with physical loot, extraction, stable IDs and save/restore. Keep the Arbor city as the shared hub.
3. **Ship design and flight:** build the typed modular blueprint, validate composition, generate a rotatable 3D preview, derive physical values and persist blueprints. Bring one Scalari fighter into the existing 6DOF flight and damage systems as the enemy-ship integration test.
4. **Planetary RTS slice:** one command hub, extractor, power graph, fabricator and turret in that Frontier arena; defend against a seeded Hive raid and save the result.
5. **Hive Homeworld and Scalari cities:** add the first arena and five city regions, brood objectives, Scalari fighter roles and mothership encounter staging using shared runtime/save contracts.
6. **Gaia:** add local tangent sectors, geodesic shell cells, colony arena and five city regions, materials and terraforming/building objectives. Validate shell clearance against terrain and structures.
7. **Frontier city regions and capitals:** connect the seven Arbor city regions, including the planned Pelaglass/Sonorous Reef underwater pair, to bounded terrain/hubs and give each destination capital its command-base role. See the [ocean-cities plan](ocean-cities.md).
8. **Final capital siege:** unlock the Obsidian Coil after Hive and Gaia story arcs; implement shield relays, the Throne Serpent systems, and the Scalari Sovereign's multi-stage boss encounter.
9. **More regions and networking:** grow each world to additional arenas, then implement remote four-player sessions with the existing networking plan.

## Acceptance gates

- Same campaign/world/arena seed reproduces terrain, POI, loot IDs and enemy schedule; changing one world's generator does not alter another.
- A four-local-player run can start, fight, collect, extract, build and save/reload one arena without player count changing the saved loot identity.
- Two different valid ship blueprints produce distinct silhouettes and measurable handling values; invalid graphs and unaffordable fabrication change neither inventory nor saved blueprint state.
- The RTS slice gathers, spends and persists resources; power loss disables structures; a deterministic raid can be won or can damage a recoverable outpost.
- Gaia's local sectors stay in bounded f32 coordinates, show a rotating sky/shell reference, and reject geometry outside the one-mile design envelope.
- Hive Homeworld and Gaia expose five stable city IDs each; Arbor Frontier exposes seven including two ocean-city concepts. Every destination has one capital; the Obsidian Coil final-boss route cannot unlock before the Hive and Gaia campaign gates are complete.
- Record Debug/ReleaseSafe tests, a four-player smoke, render/simulation budgets, and a manual controller pass for every milestone.

## Explicitly not in the first slice

Planet-wide seamless traversal, orbital mechanics, interstellar distances in the renderer, online multiplayer, player-vs-player combat, a full RTS tech tree, autonomous civilization simulation, and complete continents are later work. The first playable goal is one small arena that joins combat loot, a custom ship blueprint, a defensible outpost and persistent four-player co-op.
