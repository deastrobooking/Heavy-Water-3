# Solar frontier and Galactic Democratic Compact

**Status:** ordered eight-planet, twelve-moon, and Scalari mining-front data plus the campaign framework. One low-threat Scalari Prospector combat unit has been added near the Frontier nests. No planetary travel, transforming Kestrel modes, stations, mining production, or Compact voting is playable yet. Future orbital construction follows the staged capability gates in [Project Helios](space-habitat-network.md); that plan distinguishes the rotating-habitat physics from unverified megastructure engineering.

## Campaign frame

The first political institution is the **Solar Assembly**, a provisional compact for settlements that need shared convoy protection, fusion-drive standards, open transit lanes, and enforceable civil rights. Its charter can grow into the **Galactic Democratic Compact** only when independent peoples vote to join. “Galactic” is the aspiration; the eight-planet Solar System is the first proving ground.

Two chambers balance population and place: an **Assembly of Citizens** elected proportionally, and a **Council of Worlds and Habitats** with protected seats for planets, moons, free ports, and mobile habitats. A measure needs a 60% quorum and approval in both chambers. Emergency fleet authority expires unless both chambers renew it, and civilian inspectors can audit every carrier, campaign expense, and detention order.

Earth's Arbor Frontier is the shipyard and founding hub. Pelaglass and Sonorous Reef gain distinct delegations rather than being folded into a single human seat. Mars controls its water and terraforming policy. The Galilean moons share convoy defense but retain local resource rules. Titan, Enceladus, and Gaia's protected Saturn-space orbit negotiate ring access and migration rights. Triton's Free Port chooses whether to join after its crisis. Mercury, Venus, and Uranus start with research, industrial, and habitat councils whose residents contest who pays for distant security.

The Compact is not a benevolent empire. Its story tests consent, unequal influence, extraction, migration, and civil liberty during wartime. Hive brood communities are liberated from the Scalari system and invited to make their own choices; they do not become Compact property. Scalari civilians and defectors have individual rights, while the Sovereign's command regime remains accountable for its attacks. Elections, public evidence hearings, negotiated membership, and local votes create playable outcomes alongside action missions.

## Solar-system destination roster

`src/procedural/SolarSystem.zig` records the canonical eight planet orbits. The figures are metadata in AU and f64; regional gameplay never uses these values as renderer coordinates.

| Planet | Destination | Campaign hook |
| --- | --- | --- |
| Mercury | Terminator Foundries | Twilight crater cities, solar furnaces, rogue industrial automation |
| Venus | Cloudhaven | Floating pressure habitats, rare cloud chemistry, labor and planet-protection treaty |
| Earth | Arbor Frontier | Canopy shipyard, human pressure domes, and fully submerged cetacean city |
| Mars | Ares Commons | Canyon farms and lava-tube neighborhoods debate water and terraforming rights |
| Jupiter | Galilean League | Europa, Ganymede, Callisto, and Io coordinate convoy defense and contested resources |
| Saturn | Ringward Assembly | Titan, Enceladus, ring access, Gaia's protected transfer orbit |
| Uranus | Blueglass Stations | Remote habitats face a failing thermal grid and prolonged polar night |
| Neptune | Triton Free Port | Independence vote coincides with an intercepted Scalari courier |

Gaia remains an artificial globe in Saturn space, not a ninth planet. The Hive/Scalari homeworld remains interstellar. Its distance is handled by the same strategic route clock; it is never placed millions of light-years away in f32 simulation coordinates.

Visitable local-flight destinations include Luna; Phobos and Deimos; Io, Europa, Ganymede and Callisto; Titan and Enceladus; Titania and Oberon; and Triton. Each moon gets a bounded local region and a station/docking approach. The player selects a planet or moon from a chart, fast-travels there, then flies locally around its surface, moons, and stations. No continuous interplanetary flight, full orbit propagation, or absolute solar-system renderer is planned.

Candidate settlement arcs grow from prospecting and a landing/communications outpost into a local resource demonstration, a modular station, and then connected city districts where the site's resources, climate and logistics justify them. This is not a promise that every planet or moon has an economical mine or that every settlement becomes a city. Across the campaign, settlements may join into futuristic city-planets: connected urban belts and sealed surface, subsurface or orbital habitats adapted to each world's conditions. Terraformation is staged by regional projects and public votes, not an instant planet-wide toggle. Venus begins with floating pressure habitats; upper-atmosphere processing, sealed surface habitats, and long-term climate intervention remain separate speculative steps with resident consent and ecological consequences as mission choices.

### Gaia's printed city-world

Gaia establishes the campaign's signature habitat-building language: early industrial pressure infrastructure fused with robotic additive construction and deliberately integrated ecology. The silhouette layers huge fabrication halls, orbital cargo docks, foundries, cranes, pipe bridges and steel service gantries beneath a growing geodesic shell. Brass/copper valves, analog dials, enamel identifiers and riveted maintenance access give the industrial layer a tactile, early-steampunk ancestry; the pressure boundary and load-bearing structure remain visibly advanced printed composite, ceramic, glass and alloy. Forest canopies, agricultural terraces, wetlands and waterways fill planned shell cells and connect to life-support systems, so green space reads as essential civic infrastructure.

Treat each builder swarm as a readable, modular crew rather than background particle noise: survey, frame-print, panel-skin, inspect/repair and feedstock-haul roles have visible tools and a shared cell-level work target. A district grows through bounded modules that can be inspected, defended and repaired. Missions can restore the yard's power/feedstock, change the build queue, escort a haul, rescue stranded repair bots, or defend an exposed print crew; completion adds a traversable structure or service and can shift which civic needs are met first. Keep the visual composition grand and painterly, with saturated planetary dawns, warm furnace light and cool shell shadows, evoking the scale and earnest wonder of 1980s space epics through original Heavy Water shapes. This makes Gaia an industrial proving ground for station and habitat construction across the other worlds. It remains a design target until a local build site is playable.

## Fusion-pulse travel

Ship blueprints gain a **fusion-pulse drive** with a fictional strategic cruise rating of **0.5c**. It powers fast-travel transitions on the campaign chart; there is no continuous interplanetary cruise scene or orbit simulation. Within a planet/moon region, ships retain readable local m/s handling, can fly to orbital infrastructure, and dock at or build stations. Transit time can compress to a short departure/arrival sequence while leaving route choice, hazards, defense, and resource cost meaningful. The 0.5c rating is fictional game technology, not a claim about real fusion engineering or the transfer speeds used in the science-grounded habitat plan.

## Scalari mining droids

Scalari extraction fronts appear across the system because their off-world expansion is much older than Earth's colonies. Start with the light **Talus-class Prospector**: a four-legged, wing-finned machine with a swiveling sensor crest, paired drill arms, and a removable resource canister. It avoids fights, scans deposits, drills at a modest rate, and calls a guard unit if attacked. A separate hauler carries ore to a landing tender; neither is a combat robot in disguise. The current data contract sets the starter prospector to 45 health, four abstract resource units per minute, and only 2 defense damage. Its first mission verbs are scan, disable the drill, free trapped workers, and choose whether to seize or shut down the operation.

Use original high-energy transforming-mecha anime design language: bold readable silhouettes, articulated transformation joints, swept flight surfaces, layered mechanical armor, luminous reactor pathways, expressive posing, strong cel-shaded light/shadow blocks, and painterly planetary skies. Give the Kestrel a winged Colossus form with its own proportions and transformation logic. Scalari machine design should feel alien and industrial, with its own scale-like panels and sensor language.

## Kestrel transformation slice

Keep one saved ship, one damage state, and one crew across three mechanically distinct forms:

1. **Atmospheric jet:** the existing aerodynamic Kestrel, VTOL, afterburner, cannons, and missile lock.
2. **Vacuum interceptor:** wings articulate into a tighter radiator/drive posture; fusion pulse provides campaign fast travel, while local planet/moon flight and dogfights retain the fixed-step 6DOF flight computer and weapons.
3. **Winged Colossus:** the same Kestrel unfolds into a tall humanoid combat silhouette that keeps its swept wings, tail fins, canopy core, and twin pulse-drive back vents. Ground movement, jumps, melee, and ranged hardpoints require a dedicated mech controller, collision profile, animation, and readable attacks; this must not be represented as only a scaled-up jet mesh.

Transformations are explicit, interruptible state transitions. A selected form cannot bypass hull damage, weapon cooldown, or mode-specific exposure. The player can transform in flight with enough clearance; a landing transition checks room before changing collision shape. Transformation power comes from one heat/energy budget shared with drive boost and weapons. Start with the Kestrel only, then make ship modules and alternate chassis after the full Kestrel loop is playable.

## Delivery order

1. Surface the eight-planet/twelve-moon roster in a local campaign chart. Select a body, fast-travel there, and fly a bounded local region.
2. Build the first local dock and service station after the Earth liberation loop; add power, communications, cargo handling and repair before habitation. Keep later mining, refinery, greenhouse and habitat pieces behind site surveys, resource processing, thermal and life-support gates. Use the ordered habitat sequence in [Project Helios](space-habitat-network.md).
3. Bring the Prospector mining droid into one Scalari site with scan/drill/disable behavior, resource output, a readable vulnerability, and a mission result.
4. Add the Solar Assembly / Compact charter, representatives, public decision outcomes, and visible membership and crisis states.
5. Build Kestrel form states and a timed transform animation with continuity for position, attitude, hull, heat, and weapons.
6. Create the winged Colossus mesh, collision shape, locomotion, and melee/ranged combat. Prove one transformation, fight, and return-to-flight loop.
7. Add Venus's first staged terraforming project and expand one mining camp into a station/city district; repeat the modular contract around other worlds and moons.
8. Add the vacuum-interceptor camera/HUD and fast-travel arrival sequence for a destination. Continue the Scalari interstellar arc and Compact membership choices.

Acceptance for the first colony slice: fast travel selects a planet or moon; local flight reaches a station dock; a powered mining bay records output; one Scalari Prospector scans/drills and can be disabled; an upgrade/build choice persists; settlement autonomy affects the democratic charter. Acceptance for the first transforming-ship slice: all forms share one persistent Kestrel identity and hull; form switches preserve velocity safely; blocked mech deployment leaves state unchanged; robot mode supports terrain movement, jump, one melee attack and one ranged attack; returning to flight works; visual capture and Metal validation show folded, transition, and winged-mech silhouettes; a headless test covers each state transition and failed clearance.
