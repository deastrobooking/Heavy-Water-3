# Earth's ocean cities and the Tideborn

## Direction

Extend the Arbor Frontier toward the continental shelf without opening a new planet or changing the campaign's co-op loop. The first ocean region pairs two neighboring cities: **Pelaglass**, a human pressure-dome settlement, and **Sonorous Reef**, a fully submerged city inhabited by cetacean-adapted people. They share the same sea, energy grid, trade routes, and defense problem while keeping distinct architecture and ways of moving through space.

Keep the fiction hopeful and legible: bioengineering is a human choice made to live with the ocean, and the cetacean forms are people with names, work, homes, politics, and agency. Orcas and dolphins are not pets or enemy wildlife. Human and cetacean residents are partners; neither city's liberation is conditional on the other city's help.

## The paired cities

### Pelaglass — human pressure-dome city

Pelaglass is a chain of shallow-shelf domes, not one giant glass ball. Low, ribbed shells sit on basalt terraces and reef-grown foundations. Clear viewports, ceramic pressure collars, kelp gardens, and service gantries break the silhouette. Compact pressure locks connect domes to submerged transit tubes and open-water work platforms. Electrolysis supplies oxygen and hydrogen fuel; tidal turbines and geothermal vents add power. Water treatment and brine recovery are visible parts of daily life, not a magic infinite resource.

Its playable loop is city exploration: repair a failing electrolysis stack, trace a diverted power feed through shops and residential modules, find records showing that local officials sold pressure-seal designs to Scalari agents, then decide which public system to restore first. Pressure doors, pumps, lifts, service ladders, market stalls, garden tanks, and evidence consoles each use small reusable room modules.

### Sonorous Reef — fully submerged cetacean city

Sonorous Reef grows along a deep shelf canyon. Broad archways, hollow reef towers, nacreous resonator panels, kelp canopies, and warm lumen gardens make landmarks readable in blue water. Open plazas are shaped around safe current eddies; homes and council halls use calm pockets behind reef baffles. Routes use current streams, vertical shafts, bubble-lift stations, and marked sonar beacons rather than roads.

The residents are humanoid descendants of human volunteers whose genomes were adapted for pressure tolerance, long dives, and marine communication. Dolphin and orca traits vary across people; the city's culture is mixed, civic, and technologically sophisticated. Sonar carries public announcements and art, but private spaces use directional resonators and visual signs so every interaction does not become a loud ping.

## Playable champion

The first champion is an original orca-form Tideborn, **Neri Tidebreak** (working name), a rescue diver and reef defender. Neri is a person, not a talking animal. Their silhouette uses the killer whale's countershading, powerful tail, rounded forehead, and compact dorsal fin translated into a practical humanoid swimmer's body and expressive face. Pressure-rated woven gear, ceramic joint guards, and a lumen sonar harness show how the form works in city life.

Combat verbs should make underwater movement feel distinct while reusing the existing combat loop:

- **Sonar sweep:** a controlled pulse reveals hidden routes, weak points, mines, and cloaked Hive units; in combat it briefly staggers light bots.
- **Tidebreak charge:** a short, steerable burst that builds speed in water and knocks a line of enemies aside, with a turn-cost so it rewards route choice.
- **Resonance guard:** a focused sound barrier that catches incoming bolts from the front and returns a weaker pulse; it spends energy and cannot be held indefinitely.

The powers are local swim/combat effects, not a new elemental damage system. The whole team benefits from revealed targets and opened routes; Neri's damage, upgrades, and rewards still belong to that player's `Kit`.

**Initial tuning targets:** Sonar Sweep costs 20 energy, cools down for 6 seconds, and marks enemies and carrier weak points within 50 m for 5 seconds; it interrupts small units for at most 0.6 seconds and never stuns carrier parts. Tidebreak Charge costs 25 energy with a 4 second cooldown and converts its 0.7 second steering window into a 20–24 m/s burst; hitting a light bot pushes it aside, while heavy units and carrier hulls stop the dash safely. Resonance Guard costs 30 energy, cools down for 10 seconds, and protects a frontal arc for 1.0 second; it absorbs one normal volley and releases a short-range push, but does not negate blast, rear, or carrier-core damage. These are first-playtest values, not promises of final balance.

## Open-ocean surfing and carrier combat

The shelf cities open onto a bounded but broad ocean arena, **Stormwake Carrier Siege**, now recorded as a Frontier encounter concept. At the surface, rolling swells form rideable paths. A surf burst accelerates along the wave face, lets the player carve around incoming fire, and launches from a crest into a short aerial arc. A sharp turn trades speed for control; diving off the wave breaks targeting and enters the underwater swim loop. Sonar from below reveals carrier hull weak points and torpedo paths.

This is a powered traversal skill, not a passive board cruise: chain wave rides, dolphin kicks, underwater boosts, and crest launches to cross several hundred meters, dodge strafes, and choose an attack angle. Wave lanes should be authored or deterministically sampled, clearly visible in swell, foam, and lumen wake effects, and wide enough for split-screen groups to read. Controls need direct pitch, yaw, and vertical swim input, with a fast boost that has a clear recovery window. Current and wave forces provide momentum but never take control away from the player.

**Prototype movement targets, subject to playtesting:** neutral human suit swimming 6–8 m/s, Tideborn cruising 9–12 m/s, a short kick boost peaking near 24 m/s, and a clean wave ride holding 22–30 m/s. A crest launch should preserve forward speed for roughly one second, then hand off to normal air movement. Braking, a hard carve, or submerging deliberately spends speed. These speeds let a player cross an 800 m radius arena in tens of seconds while keeping aircraft faster and relevant. Keep acceleration visible: camera lean, tail kick, board spray, sound pitch and the growing wake tell the player when momentum is building.

Surfing should reuse the hoverboard's existing traversal choice where practical, with an explicit water-surface contact mode; it must not require a board to use the regular swim controls. Jump rises off a crest, the existing dodge/boost becomes the short kick burst in water, and pitch input controls dive/climb. Releasing direction should coast under water drag instead of stopping instantly. A successful wave carve builds a small boost reserve, capped at one stored charge, so the player is rewarded for clean lines without making infinite boost chains.

Keep the control vocabulary familiar: left stick/WASD steers, camera look sets the swim/surf aim, jump launches from a crest, dodge/boost kicks forward, and the character's three power inputs remain on Z/C/H or the mapped controller equivalents. Surf mode is selected with the existing traversal cycle. A player can swim and fight without surfing, and a player who does not own or select the orca form still has access to the wave route.

For a fair four-player encounter, surface currents and swell lanes repeat on a deterministic broad pattern, telegraph their direction, and never force a player out of an objective. Arena edges turn swimmers back with visible shelf walls and current ribbons. A knocked-back player floats to a marked recovery buoy rather than drifting out of bounds. Human suit reserve should comfortably support a full attack-and-return route (prototype target: 90 seconds); low reserve warns and points to the nearest refill, while zero reserve raises the player to the surface and disables diving temporarily instead of killing them. Tideborn do not need air reserve but share current, stun, and recovery rules.

The large target is a Hive Brood Carrier using its existing flying-carrier silhouette and staged defenses, escorted by Scalari aircraft. The carrier skims above the waves: its upper deck launches wasp fighters, its armored belly protects brood bays and torpedo organs, and its exposed core is the final target. Carrier damage progresses by disabled subsystems, not one oversized health bar. A Scalari command aircraft coordinates the escort until its signal array is broken.

Four local players can choose overlapping roles: fly the Kestrel to draw off the escort; surf the wave face to board a deck ramp or hit the upper bays; dive beneath the hull to expose brood bays and evade deck fire; or remain in the water to mark weak points and clear torpedoes for the others. Every role has an exit and recovery route, and the encounter remains completable if one player stays in the city or fights from the water. The Brood Carrier, wasps and Kestrel already exist as aerial systems, but surf traversal, ocean carrier staging, surface combat, and swim-to-air handoffs do not.

### Encounter flow

1. **Find the carrier:** the Pelaglass sonar mast identifies its patrol lane. Players launch from an ocean-facing dock; a refill buoy is the safe reset point.
2. **Open the approach:** destroy or evade the Scalari escort and the Brood carrier's four flak turrets. Turrets use the existing carrier's first assault stage. Surfing reaches the top deck; a deep dive reaches the belly while the Kestrel pulls wasps away.
3. **Break the bays:** disable the four glowing launch bays. Each destroyed bay reduces the next wasp reinforcement group. Sonar marks the current weak point for the whole team, but only a player who gets an attack angle can damage it.
4. **Expose and hit the core:** a successful bay clear opens the underside. Players ride the wake or use a current shaft to reach it; a marked pulse window gives divers a short, readable attack interval. Reuse the existing core stage and crash event where possible.
5. **Recover and claim:** a falling carrier creates a broad evacuation window, not a sudden lethal splash. Loot lands on a buoyant wreck platform and nearby recovery buoys. Each player gets their own drops; the carrier defeat and story evidence are shared.

The city systems make alternate approaches viable: repairing electrolysis powers refill buoys and restores human suit reserve; restoring the sonar mast reveals the patrol lane and weak-point window; disabling the Scalari signal craft removes escort reinforcements; exposing the supply deal advances shared story state. No one city fixture should be a hard prerequisite for entering combat—the player can still launch with a basic suit and local sonar pings.

**Role and pacing targets:** one complete assault should take about 4–7 minutes for a four-player party, with 20–40 second movement legs and no hold-to-wait phase. A turret/bay should take a small team 8–15 seconds of successful exposure to disable. Boarding or attacking from below is a choice, not a sequence that all four players must repeat. Scale wasp pressure and part durability with party size; do not scale carrier size, travel distance, or simultaneous required objectives.

## Underwater movement and interaction

An ocean slice needs bounded three-dimensional movement: swim in all axes, buoyancy and drag, readable acceleration, current lanes, and stable landing on floors and structures. Human Rangers use a pressure suit with a finite reserve and reachable refill stations; Tideborn breathe underwater. Keep the HUD simple: depth, reserve, and a clear warning before a human must surface or refill. Pressure itself is a location rule with safe transitions through locks and elevators, not a hidden damage timer.

Sonar should reveal authored silhouettes and interactable routes for a short time rather than paint a cluttered radar. Water visibility uses close, middle, and far layers with lights and silhouettes to preserve navigation. Use the same interaction prompt and modular fixture IDs as the planned interior system for pressure doors, valves, lifts, evidence, shops, and power relays.

## Enemy roles and story conflict

Hive units are adapted to the seafloor and remain visibly insect-derived:

- **Needlefin:** a fast, darting flanker that attacks from kelp and canyon edges.
- **Bell mine:** a drifting proximity mine that blocks a route until disarmed or destroyed.
- **Anchorback:** a heavy crab-like bruiser that pins players and attacks pressure infrastructure.
- **Brood siphon:** a stationary nest device that drains local power and grows defenders until disabled.

Scalari forces use pressure-rated technology and disciplined formations, visually separate from living Hive chitin:

- **Trident diver:** an armored infantry shooter that guards objective approaches.
- **Lance eel:** a fast submersible with a telegraphed straight-line energy lance.
- **Abyssal survey craft:** a small command sub that deploys sonar decoys and calls reinforcements until its signal mast is disabled.

The first conflict uses both factions without merging them into one enemy. Hive brood occupies the outer reef and sabotages power. Scalari operators exploit the chaos to seize the electrolysis and sonar network. Freeing Pelaglass exposes the supply deal; clearing Sonorous Reef gives the team a route to disable the underwater spore site and Scalari signal craft. The cities remain explorable sanctuaries, with combat centered on the adjacent wild water and targeted incursions.

## Delivery sequence

1. **Campaign catalog and art guide:** stable city records for Pelaglass and Sonorous Reef; one bounded shelf region; silhouettes/material families for dome, reef, Tideborn gear, Hive and Scalari units.
2. **Swim and surf traversal slice:** a test tank that opens into a wave lane, with human suit reserve, Tideborn 3D swimming, buoyancy, currents, crest launches, carving, underwater boosts, and swim-to-surface transitions.
3. **One city block:** build a Pelaglass dome room and a Sonorous Reef plaza from reusable structural and interaction modules. Open a pressure lock, restore a power relay, use a shop, and collect one story record.
4. **Underwater combat slice:** implement Neri Tidebreak's playable form and three powers, then Needlefin, Bell mine, Anchorback, Trident diver and one Scalari signal craft. Use the existing per-player rewards and Hive combat events where possible.
5. **Stormwake carrier siege:** stage an existing Brood Carrier over the ocean arena with Scalari aircraft support; let swimmers surface-surf, dive beneath it, and attack hull subsystems while Kestrel pilots handle the escort.
6. **Paired liberation loop:** restore Pelaglass's electrolysis grid, expose the Scalari deal, clear the nearby Hive nest, disable the signal craft and carrier support, and save shared story progress plus each player's own loot.

## Limits and acceptance

This is campaign and feature design plus stable city-catalog data. Underwater locomotion, ocean terrain and water rendering, both city meshes, Tideborn bodies, enemy roles, and the liberation loop are not implemented by adding the catalog entries.

The first playable slice is done when a four-local-player party can enter both cities, move between dry/pressurized and open-water zones, use an airlock and city fixture, fight the two factions, play as Neri, and finish one city/outside combat loop. The carrier milestone additionally needs a complete surface-surf/dive/air-support loop against subsystem weak points. Add headless tests for buoyancy, surf momentum and recovery, reserve boundaries, enemy damage/guard behavior, room interaction state, and save round-trips before calling the feature complete. Capture the scene in ReleaseSafe with Metal validation and hand-play it at city, canyon and open-ocean distances.
