# Heavy Water: world and systems

This document sets the creative direction and the systems that express it. The [roadmap](roadmap.md) orders the work; [architecture](architecture.md) records what is built. When the three disagree, this document says what the game is for, and the other two say what exists.

## Premise

Generations ago, engineers gave the forest a job. They rewrote a family of giant trees, the **Arbors**, to pull groundwater up half a kilometer of living wood and concentrate the deuterium in it. Their sap is heavy water, the fuel of the city's fusion cells. People followed the fuel up the trunks. Today a city grows *with* the trees: districts carved into bark, glass towers grafted between trunks and braced by branches, and broad bridge roads strung across the gaps. Traffic, pedestrians, and market stalls cross hundreds of meters of open air.

Earth's settlements also reach beneath the waves. Human neighborhoods cluster in pressure domes powered by electrolysis, tidal currents, and geothermal vents. Cetacean-adapted people have their own fully submerged cities among shelf reefs and canyon gardens. The two cultures trade, build shared routes, and defend their homes together.

Below lies the **Rootdeep**, the wild forest floor where the first engineers' seed vaults and machine shrines still sleep. Above is the **Crown**, the sunlit canopy where the Arbors breathe.

Tone: *The Legend of Zelda* meets science-fiction anime. Wonder before menace, curiosity rewarded, ancient technology that feels alive. Nature and machine are partners, not enemies: every machine in the city runs on something a tree makes.

## Pillars

Three ways to play, braided so each feeds the others. None is a mode; the player moves between them freely.

- **Explore:** descend into the Rootdeep, climb trunks, glide between branches, and open shrines. Exploration finds blueprints, genome fragments, and parts.
- **Engineer:** tap sap, wire machines, build and repair bridges, doors, lifts, and vehicles. Engineering opens routes and powers what exploration found.
- **Grow:** guide the city and the trees themselves: graft new branches, plan bridge roads, raise districts. Growth creates new places to explore and new loads to engineer for.

A good session moves around the loop: a shrine yields a pump blueprint, the pump powers a new lift, the lift reaches a branch where a new district can take root.

## Two kinds of ground: the wilds and the sanctuary cities

The game changes pace at the city gates.
- **Outside the sanctuary cities** (the frontier, the mountain caves, the Hive-held zones), Heavy Water is a hack-and-slash. It is fast, readable fights against Hive waves, nests and carriers. Loot drops for each player to keep, and pets and heroes fight alongside. A player's power comes from what they find and fabricate out here.
- **Inside the sanctuary cities** (the canopy districts), the pace drops to exploring. Players find upgrades, shops and tinkers, talk to people, and uncover how the Hive holds the world: the alliances it has made with scientists and with governments. Evidence found in a city points to the collaborators, and the fights outside its walls are how the party breaks their grip.

**The arc:** free the cities of Earth one by one from the Hive and its human allies, and later the Colonies (Gaia and beyond, see the multi-world direction below). Each city is freed through both halves: the party clears the Hive from the wilds around it and exposes the alliance inside it.

**The team:** up to four players share one world and its story. Each keeps their own saved character, gear, wallet and pets, and any of them can play as a teammate's saved ranger or as any Wildkin hero the team has met.

## The player

The protagonist is the player's own ranger-engineer: named and customized, not a fixed hero. A new game opens the character creator, and it can be reopened at any time.

- Name: 1–20 letters, digits, spaces, or hyphens.
- Proportions: height 1.62–1.98 m, build 85–115%.
- Palettes chosen to suit the painterly direction: eight skin tones, eight hair colors, eight outfit colors, and five bioluminescent accents (the visor and belt glow like Arbor lumen).
- Hair: short, ponytail, long, crest (anime), or ranger hood.

- Clothing: undersuit, field jacket, exo rig, hardsuit, or vanguard. The field jacket has modeled utility pockets; the armor silhouettes use rigid plates rather than cloth shells.
- Armor style: none, scout, sentinel, rootweave (bark-green plates with lumen tracery), or skyguard (streamlined blue-green plates and light strips). Helmet: open, visor, or sealed; the visor is a curved wraparound shield with an inset lumen slit.
- Hardsuits carry luminous twin-roller heel runners and a personalized saber lumen accent. The Energy Skate traversal mode supports fast travel and superhuman air-assisted jumps across varied terrain; a charged saber cut releases a tier-scaled crescent wave.

- Suit upgrades from the south-market tinker: fuel tank, jet efficiency, sprint servos, stamina weave, grapple reel and salvage kit, three levels each, shared by the party. The armor suits (exo rig, hardsuit, vanguard) are bought from him too; the undersuit and field jacket are free.
- Conversations: keepers and locals talk in branching dialogue, remember what you have done (salvage, shrines, bridges, nests), and hint at the Rootdeep's waking machines.
- Pickups to find: lumen shards on the plazas and roads, rotor cores on high roofs and by the shrines, Hive alloy from the Hive, and vital cells that raise maximum health.
- The fabricator at the garage builds hover cars (Skimmer, Dart, Courier), armor suits and accents, and weapons from those pickups.
- The Hive is an engineered insect civilization: ancient Scalarians altered Earth's insects, left the planet, and founded the first Hive lineages on their homeworld. Three black spires field flying drones and burst-firing sentinels alongside three ground roles: troopers pressure players with bolts and grenades, skirmishers close quickly for light melee strikes, and bulwarks advance slowly with heavier armor and punishing close-range attacks. Breaking a spire stops its swarm.
- The Scalari have a distinct ground force: low-threat cyan scout bots and amber stingers form a renewable practice patrol near the spawn; a bio-titan waits near the distant nests as the first kaiju-scale mutant. Defeating units grants per-ranger combat XP, saved in that ranger's Kit; each 250 XP adds a level and 2 maximum health. The closest active ranger receives the takedown reward.
- In the skies beyond the nests, two Brood carriers (giant beetle ships) launch swarms of wasp fighters. The fabricated Kestrel, a VTOL fighter, takes the war to them. Scalari dragon-armor fighters and motherships are a separate, more advanced fleet.

Clothing, gear, and accent unlocks found while exploring are future growth for this system.

## The Arbors

### Anatomy and strata

| Stratum | Height | Character |
| --- | --- | --- |
| Rootdeep | 0–40 m | Buttress roots as wide as streets, fog, fungus light, ruins, wildlife, shrines |
| Trunkline | 40–300 m | The city proper: bark districts, grafted towers, bridge roads, transit |
| Crown | 300–600 m | Sky gardens, observatories, airship moorings, open light |

Target dimensions: trunks 40–100 m across at the base, 300–600 m tall, and crowns roughly 150–250 m in radius. A district is three to six Arbors plus the towers between them.

### Genome

Each Arbor grows from a **genome**: a small, versioned set of parameters that is deterministic per seed, like terrain. Genes are named after what they do in nature:

- **Phyllotaxis:** the angle between successive branches (the golden angle, 137.5°, by default), so branches spiral and do not shade each other.
- **Apical dominance:** how strongly the leader outgrows the side branches, which sets a tall and narrow versus a broad and spreading crown.
- **Tropisms:** phototropism (growth toward open sky) and gravitropism (branches sag with length, then curve up), which set the silhouette.
- **Platform tendency:** how often branches flatten into load-bearing shelves. These are the city's natural building sites.
- **Vascular capacity:** sap flow, and therefore how much power the tree can supply to taps.
- **Bark and lumen:** bark color and ridging, and the hue of the tree's bioluminescence.

Branching uses space colonization: the crown volume is seeded with attraction points and branches grow toward them, which gives natural gaps and light wells. Grafting lets the player add a growth target so the tree extends a branch toward a tower or a planned bridge anchor over in-game days.

The canopy should feel like a whole inhabited ecosystem at impossible scale: broad, layered crowns gathered around the branch skeleton, buttress roots and major limbs visible as structural supports, and bridges that appear woven, grafted, or grown between living anchors. Small ladders, ramps, patios, rope walks, and jump gaps turn the crown into a parkour route; luminous guide nodes and unobtrusive grapple rings make the route legible. Mix warm wood and leaf color with quiet ceramic, oxidized metal, glass, and restrained lumen accents. Keep the shapes painterly and original, with hand-shaped silhouettes and readable scale cues rather than copying any one film or artist.

### The heavy-water cycle

Roots draw groundwater, xylem lifts it, and specialized cells enrich deuterium into the sap. **Sap taps** are generators placed on a trunk or branch, and they draw from that tree's vascular network. A tree's vascular capacity is the supply for every tap on it, so an over-tapped tree browns out. That is the existing machine power network, extended from one machine to one tree. Over-tapping stresses the tree (dimmer lumen, slower growth), which gives a reason to spread load across Arbors and to build pipes between them.

## The canopy city

### Grafted towers

Modern skyscrapers rise between trunks, founded on buttress roots and braced by branches that grow into steel collars. Towers are procedural: a footprint, a floor-plate profile, facade modules, and anchor points where branches and bridges attach.

### Bridge roads

Bridge roads are the city's streets. A standard section, from edge to edge:

- Walkway with market bays: 3 m
- Two traffic lanes: 2 × 3.5 m
- Walkway with market bays: 3 m
- Rails and planters: 0.5 m each side

That is about 14 m of deck. Grades stay at 6% or less so vehicles and pedestrians share them comfortably. Long spans hang from **vine cables** (living suspension, thickened over years) between trunk and tower anchors. Junctions where roads meet a trunk become plazas wrapped around the bark. Shops are stalls and kiosks in the walkway bays, and they sell the parts and blueprints the other loops use.

### District life

Districts differ in purpose and mood: markets, workshops, gardens, residences, docks. Traffic follows lane graphs on the bridge roads, pedestrians follow walkway graphs, and both respond to what the player builds or breaks.

## The ocean cities

**Pelaglass** is a human city made of several small pressure domes connected by locks, tubes, work platforms, and kelp gardens. Its oxygen and hydrogen systems, water treatment, and tidal power are public infrastructure that players can explore and repair. **Sonorous Reef** is a separate, fully submerged city for cetacean-adapted people. Grown reef arches, resonator panels, current lanes, and lumen gardens shape public spaces for three-dimensional movement and sonar communication.

The Tideborn are humans who chose marine adaptations; orca- and dolphin-influenced bodies describe a range of people, not separate animal species. The first playable champion is Neri Tidebreak (working name), an orca-form rescue diver with a route-revealing sonar pulse, a steerable water charge, and a short-lived resonance guard. Hive brood occupies the outer reefs while Scalari pressure-suit teams target the cities' electrolysis and sonar networks. See the [ocean-cities plan](plans/ocean-cities.md) for the proposed movement, enemy roles, interaction modules, and first liberation slice.

## Mountains and caves

Beyond the hub's valley and its ridged highlands, four great ranges rise 1.3–1.7 km out. Their summits carry snow, and rivers have cut passes through them. The ranges are hollow. Cave dungeons open in their lower flanks: a mouth in the mountainside, then chambers and tunnels that branch and descend under the rock. Lumen crystals light the chambers, dead ends hold caches, and the deepest chamber is a heart where the Hive has grown a nest. Breaking a heart clears the cave.

## The Wildkin

The Scalari did not only remake insects. Long ago they carried Earth's animals off aboard the Worldcoil Ark to make soldiers of them, and failed in the best way. The animals woke up upright, clever and super-powered, with their own big hearts instead of orders. When the Ark broke apart over the Frontier, they scattered. A hedgehog who outruns sound, a gator who rolls like a boulder, a spider who weaves glowing webs, an owl who casts moonlight: 26 of them wait in the city, the wilds, the mountain caves and the sky arena, ready to join the party. Players collect them and play as any of them, alone or four together. The tone is for all ages: bright, heroic, funny, and still full of action and magic. The roster is in [The Wildkin](wildkin.md).

## Systems inspired by nature

Each system pairs a natural analogue with gameplay and with the engine piece it maps onto.

| Nature | In the game | Engine mapping |
| --- | --- | --- |
| Xylem and phloem | Sap grid: taps, pipes, tree capacity, brownouts | Machine power networks, extended to per-tree vascular graphs |
| Mycorrhizal networks | Rootsong: signals travel through roots between machines on channels | The transmitter/receiver signal bus, reskinned and later limited to trees that share roots |
| Phyllotaxis and space colonization | Every Arbor distinct, readable, and deterministic | Genome-driven procedural tree growth (new) |
| Tropisms and grafting | Players steer growth toward anchors | Growth targets persisted as world deltas |
| Spider silk and vines | Vine-cable suspension bridges | Bridge generator with tension and grade constraints |
| Bioluminescence | The city glows at night; lumen shows tree health | Emissive materials and a day/night cycle; lamps become lumen pods |
| Canopy gaps | Light wells and sky gardens where the crown opens | Space-colonization gaps as placement and lighting cues |
| Seed banks | Shrines: sealed vaults of the first engineers, solver-verified puzzles | Procedural facilities validated before they appear |
| Pollinators | Drones that tend the crown; some can be befriended or repaired | Machine-driven agents (later) |

## Visual direction

The target is grounded, hopeful science fantasy: painterly cel shading and panoramic natural forms with deliberate contours, broad readable color shapes, and engineered details that make physical sense. “Serious” means authored and credible, not grimdark. Keep the warmth and all-ages heroism while giving people and places adult proportions, useful construction, and stronger visual hierarchy. Human Rangers already use a 7.5-head proportion; the art pass should refine face construction, equipment fit, and presentation rather than inflate their heads. See the [character and environment visual pass](plans/visual-direction.md) for the current review and work order.

- Two- or three-step toon ramps with soft transitions, warm key light, and cool fill.
- Selective outlines at important silhouettes; avoid outlining every internal edge.
- Use distance haze to layer the panorama without washing out the playable city and its landmarks.
- Keep human Rangers adult and practical; preserve the intentionally more expressive animal silhouettes of the Wildkin.
- Give Frontier, Hive, and Scalari distinct material families and restrained accent colors.
- Let bark, steel, ceramic, fabric, chitin, water, and glass read differently through shape, color, and subtle surface variation.
- Make canopy routes look grown into the Arbors: layered connected foliage, branch-supported landings, vine and cable bridges, tiny terraces and ladders, with selective bioluminescent wayfinding and grappling points.
- Compose around a small number of landmarks and provide visible support, contact, and scale cues for buildings, trees, roads, and bridges.

## Scale, as engineering constraints

- The existing streamed terrain becomes the Rootdeep floor. Trees and the city are placed content on top of it and stream by height as well as by ground chunk.
- A 600 m tree seen from a kilometer away needs level of detail and impostors. Crowns need clustered foliage, not individual leaves.
- Positions stay f32 within the current bounded world. A floating origin is revisited only if the playable city outgrows about 10 km.
- Collision needs walkable curved surfaces (branch tops, trunk ramps) and angled decks. That calls for static triangle-mesh and oriented-box colliders in the native physics.

## Open questions

- Traversal verbs beyond walking, driving, and lifts: a glider, climbing, grapple vines?
- Threats: settled at the top level (the Hive outside, its human allies inside the cities). Still open: wildlife and ancient guardians in the Rootdeep, and blight on the trees.
- Economy: what shops trade, and whether sap is currency.
- How fast grafting and city growth run relative to a play session.

## Multi-world campaign direction

The Arbor Frontier remains the party's home shipyard. The campaign spans three destinations: the Arbor Frontier, the Hive Homeworld (also the Scalari homeworld), and Gaia, an Earth-radius artificial planet with a rotating surface and a geodesic enclosure about a mile above nominal sea level. Gaia is the terraformed human colony beyond Jupiter. Four local players enter a region together, fight or explore, gather world-stable materials, and extract to fabricate custom ships or establish a planetary outpost.

Hive Homeworld and Gaia begin with five named city regions each; the Arbor Frontier adds the underwater pair Pelaglass and Sonorous Reef to its five canopy and river regions. Each destination also has a capital base. The Hive/Scalari capital, the Obsidian Coil, hosts the final boss battle against the Scalari Sovereign. The other capital sites serve as the Frontier home base and Gaia's colony command center. Scalari fleet visuals now have a first procedural 3D mesh pass: three dragon-armored fighters and two motherships in red/black, purple/green and orange-accented palettes.

These are mission-sized open regions rather than complete planet surfaces generated at once. The first release loop should prove one four-player arena, a small custom ship design bay, and a command hub with resource extraction and defense. Cooperative PvE is the default; competitive rules and seamless globe-scale travel can follow later. See [Planetary frontier](plans/planetary-frontier.md) for city identities, typed per-world feature packs, Scalari ships, region sizes, the ship module grammar, Gaia's shell, the real-time strategy loop, save boundaries, and delivery gates. The city, world and feature-pack records in `src/procedural/Worlds.zig` are deterministic metadata, and the ship meshes are registered assets; destinations, city interiors, and new ships are not yet playable campaign content.

The solar campaign expands those bounded destinations across Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus and Neptune, with twelve named moons as local-flight stops. `src/procedural/SolarSystem.zig` stores orbit, settlement, governance, moon, and first Scalari mining-front records. A low-threat Scalari Prospector now appears by a distant Frontier nest as the first ground mining droid, but it does not yet produce campaign resources. Ships use a fictional 0.5c fusion-pulse drive for campaign fast travel, then fly locally around planets, moons, and stations at readable speeds. Gaia is a built globe in Saturn space, not an extra planet, and the Hive/Scalari homeworld remains interstellar. The [Solar Democracy plan](plans/solar-democracy.md) frames modular mining stations, staged terraforming (beginning with Venus), the Solar Assembly's evolution into a voluntary Galactic Democratic Compact, and the Kestrel's planned atmospheric, vacuum, and winged Colossus forms.

Gaia's visual identity is an industrial space epic where habitat-making is visible at city scale. Early pressure works, riveted steel, copper/brass service hardware, analog gauges, gantries, cranes and pipe bridges sit alongside advanced printed-composite ribs, ceramic panels and vast geodesic shells. The older machinery is a tactile cultural layer around credible life support and automated fabrication, not a replacement for it. Swarms of specialized construction robots survey, print, weld, skin and inspect the shell in discrete cells; material feed lines, foundries, docks and repair yards make the colony's industrial capacity legible. Forests, farms, waterways and rootlike green terraces thread through the frame as useful living infrastructure, including shaded civic commons inside the enclosure. Compose it with the scale, painterly planetary horizons, saturated twilight and analog warmth of original 1980s space epics, while keeping the designs distinctly Heavy Water. In play, a construction site should invite players to route materials and power, protect or redirect a robot crew, and see a bridge, shell cell or habitat module advance as a local objective resolves. This is a design target: Gaia currently has catalog metadata, not a playable industrial district or construction simulation.
