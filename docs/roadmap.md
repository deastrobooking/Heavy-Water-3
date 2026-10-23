# Heavy Water development plan

Engine tooling is native Zig: physics, asset compilation, navigation, and other engine systems are written in Zig rather than bound from C/C++ libraries. Mach (platform, GPU) is the foundation layer.

Heavy Water is a sci-fi exploration and engineering game that may grow into a reusable engine and creator platform. This roadmap is the single planning document. The MVP is a complete local play loop: fight through Hive-occupied wilds, expose its allies inside a captured Earth city, and preserve shared story progress alongside each player's private kit. Detroit is the first liberation loop; New York City is also captured and follows once Detroit is proven. The synthetic humanoid warriors fight beside humanity and help lead its future as trusted partners. Solar, ocean and other-planet plans remain later content until this loop is complete. Problems should constrain the player without prescribing a single solution. Engine features should arrive through runnable slices.

## 1. Engine bootstrap — implemented

- Pinned Mach/compiler pair and local bootstrap launcher.
- Mach window, free camera and action input.
- Fixed-step timing and synchronized render snapshots.
- Indexed terrain, 1,000 instanced objects, depth, texture and directional light.
- Debug HUD, optional CPU frustum culling, and bounded smoke run.
- Deterministic generation and initial scalar machine graph tests.
- Explicit ownership and limits documented.

## 2. Procedural test world — implemented

1. Generational chunk handles; active (3×3), render (5×5), and generation (7×7) radii.
2. One background worker, per-slot cancellation tokens checked per terrain row, and a per-frame GPU upload byte budget.
3. Continuous world-space biome masks, slope-aware scatter, and `(seed, generator, chunk, local_id)` object identity.
4. `tools/benchmark.py`: fixed fly-through with interval/CPU percentiles, upload, residency, and pool-allocation counters.

Acceptance evidence: seam tests (including negative coordinates), a fixed 49-slot CPU pool and 25-slot GPU pool that never grow, generation off the render thread, and a test that unloads and regenerates a chunk with an identical fingerprint. See [validation](validation.md).

## 3. Interaction and assets — implemented

1. `asset-compiler` runs in the build graph: glTF 2.0 (`.gltf`/`.glb`) → versioned `HWMS` runtime models with submeshes and materials. The app embeds and validates them.
2. Typed generational mesh, material, and body handles through one `Catalog`; the renderer resolves handles each frame.
3. `physics/Physics.zig` is the engine API; `BoxWorld.zig` is a small built-in backend (axis-aligned boxes, no rotation). No backend type crosses the API, so the solver can grow without touching gameplay.
4. Walking character with ground and box collision, step-up, jump, and prop pushing; exact triangle-accurate terrain queries.
5. Picking (crates via physics raycast, relics by stable ID, terrain occlusion), pickup/carry/throw, and one tool: the salvage cutter.
6. JSON save format v1 with seed, generator, and content versions; atomic writes; reject-before-apply loading.

Acceptance evidence: a headless test walks to a crate, carries and drops it, saves, disturbs the world, and reloads the crate's exact position. Another removes a relic, verifies regeneration still yields the same ID, and restores the removal from a save. The real app grabs a crate and round-trips a save in smoke mode. See [validation](validation.md).

Known limits: boxes do not rotate, stacking is soft, and there is no continuous collision for fast throws. Physics stays native Zig; rigid-body rotation, a broadphase, and CCD will be built in `physics/` when machines and vehicles need them.

## 4. Machines — implemented

1. Typed power and signal ports per device kind, with defaults for unconnected inputs.
2. Power networks (union-find) with supply/demand satisfaction and brownout; double-buffered signals with one step of latency per hop.
3. Sensors (button, proximity), controllers (latch, logic graph), actuators (linear, kinematic), and generators.
4. Fixed-step, allocation-free, physics-independent machine simulation; kinematic physics bodies that carry props and the player.
5. Versioned JSON blueprints, validated at build time by `asset-compiler` and again at load; machine state in saves.
6. Vehicle: oriented rigid bodies (quaternion orientation, box inertia, sample-point contacts with sequential impulses), a raycast-suspension vehicle, and seat/motor/steering devices. The rover blueprint drives through the same power network as the door and elevator.

Acceptance evidence: headless tests walk into the closed door, press its button, wait for it to open, walk through, save, disturb, and reload it open. Another rides the elevator from the ground to the landing by its call button and sends it back from the top. Both machines use the same device kinds and APIs. See [validation](validation.md).

The rover was added only after the door and elevator worked, as planned. A headless test enters it, drives it more than 4 m on motor power, exits, verifies the parking brake, and reloads its pose. Physics tests hold it on a 20° slope in both headings and roll it freely when released.

## 5. Creation — implemented

1. Build tool: pause-menu **BUILD** opens a fixed 4×4 inventory with STRUCTURES, KITS, and BLUEPRINTS tabs. Select an item to equip it; the inventory holds at most sixteen items per tab, so it does not become a scrolling list. The floating-platform card opens the editor for a 16 m horizontal or vertical square and its height from the aimed surface (1 m or 10 m steps, −1,000 to +1,200 m). Placement keeps 0.5 m grid snapping, quarter-turn rotation, surface or terrain-footprint snapping, a green or red preview, overlap and player rejection, removal, and the ordinary machine save path. The separate block tool now has free creative placement: C on keyboard or X on a pad toggles the mode; the player's material strip stays visible, LT places, RT removes, and unsupported blocks can float. Normal block mode continues to charge each player's own kit.
2. Wire tool: connect any output to a compatible input on the same machine, cycling valid port pairs; disconnect a device's inputs. Every edit goes through `Blueprint.connect` / `addDevice` / `removeDevice`, the same checks the file format uses. Live machines `reconfigure` and keep their state.
3. Loose devices form one editable workshop machine, so they can be wired together.
4. Save format v4 stores the whole world: each machine's full (possibly edited) blueprint document, origin, yaw, and state, plus every crate. Loading validates everything, including body capacity, with a dry run before rebuilding.

Acceptance evidence: headless tests build a generator, button, latch, and lamp from the palette, wire them in the world, light the lamp with the button, reload the circuit into a fresh session with the lamp lit, and remove a device (dropping its wires). They also place a rotated door on the grid, refuse an overlapping second one, and remove it.

5. Prefabs: P captures the aimed machine (a workshop circuit is recentred onto its lowest device) under a unique name, adds it to the build palette after the built-ins, stores it in the world save (format v5), and exports it to `saves/prefabs/<name>.json`. Valid files there are imported into every session; invalid ones are skipped with the validation error logged.
6. Inspection: I shows the aimed machine's name, slot, power networks (supply, demand, satisfaction), each device's live outputs, and its wires.

Acceptance evidence: a headless test captures a four-device circuit, places a copy that works independently (its lamp lights, the original's does not), inspects the copy's network and outputs, rewires the copy without changing the prefab, and restores the prefab library from a save. A manual run imported one valid prefab file and skipped a broken one with `InvalidDeviceParameters`.

7. Between machines: `transmitter` and `receiver` devices share a world signal bus of 64 channels. Transmitters publish after each machine step (the largest value wins per channel), and receivers on any machine read the previous step's bus. Channels live in blueprints (validated 1–64) and change in-world with `[` / `]`. Power stays per machine.

Acceptance evidence for the bus: a headless test presses a workshop button whose latch feeds a transmitter, and a separately placed machine's receiver lights its own lamp. Retuning the transmitter darkens the lamp, channels wrap from 1 to 64, and the channel survives a save round trip.

Deferred: editing a prefab's parts and numeric parameters in place (today a prefab is edited by placing it, rewiring or retuning it, and capturing it again).

## Player character — implemented

A customizable, nameable ranger-engineer: the creator on a new game (F4 any time), name and appearance palettes, a procedurally generated skinned ranger (`src/character/`: lofted body, layered clothing, sci-fi armor suits, spring-bone hair) with a procedural gait and lumen accents, third-person view (F2) with eye-origin aiming, and the profile in save format v6. Acceptance evidence: headless tests freeze input in the creator, confirm a named profile, target a crate from the eyes in third person, draw the avatar, and restore the profile from a save.

## Menus, GUI and conversations — implemented

A resolution-independent GUI canvas replaces the text panels: title and pause menus, settings saved to `saves/settings.json`, controls, a graphical HUD, customization with palette swatches, a market shop, the tinker's suit upgrades and armor wardrobe, and branching data-driven conversations with the three keepers and pedestrians. Keyboard, mouse and P1's controller all navigate. Suit upgrades, owned suits and story flags save with the world. **MAX PROGRESSION TEST MODE** is a settings toggle for late-game coverage: it temporarily maxes player kits and shared unlocks, holds a complete pre-test world snapshot for rollback, and blocks world/ranger saves while active. Objective flags are left intact so it does not skip existing campaign beats. Acceptance: headless tests cover menu navigation, settings clamping, dialogue validation, flag-gated branches and one-time gifts, upgrade and suit purchases that change nothing on failure, the Sandbox stall-greeting flow, and every screen laid out inside the window. A Metal smoke drives pause → settings → resume and a conversation into the upgrade panel. Captures (`-Dshowcase=18..28`) cover each screen. Guests' split views have their own HUD and stall panel, and all 32 gameplay keys can be rebound. Audio is in: Mach `sysaudio` output, a lock-free native mixer, 27 synthesized sounds and loops, a director that turns gameplay, UI and dialogue into sound with guests placed in stereo, four volume settings, and a packaged MP3 player on the title screen, gameplay HUD and pause menu. Packaged tracks live in `assets/Music/`; keyboard, controller and mouse can skip or pause them, with no custom folder access. Next: reverb and occlusion, and conversations and tinker panels for guests.

## Space travel and arcade battle arenas — active planning track

The user has directed work on alternate space-fighter models, an upgrade path, Solar travel, and orbital battle arenas. The attached arcade-shooter feature list is recorded and phased in [space combat](plans/space-combat.md). Existing Scalari fighters and giant motherships are design inputs only; they are not yet playable ships or bosses. Fighter-frame progression is in place, and the first bounded orbital flight trial is playable from Battle Arenas. Destroyed enemy fighters now award per-player Kit scrap, gold, parts, faction salvage and combat XP; pet fighter takedowns credit their owner. Aircraft frame unlocks use those currencies and require combat ranks 2–6. In open-world HUDs, all active local players now have GPS-style latitude and longitude readouts, anchored to their playable city or expedition region. Next: tune fighter rewards through play, validate trial controls by hand, then build the first Brood combat arena. Solar route travel remains later work.

## Flight: the Kestrel and the air war — implemented

The fabricable Kestrel VTOL fighter flies with wing aerodynamics, lift jets, and mouse-aim fly-by-wire. A Brood carrier and a metallic Hive command carrier circle beyond the Hive nests; the synthetic ship launches armored robot fighters while the Brood bays send wasps, dragonflies and beetle bombers. The flyers dogfight with lead pursuit, dragonflies jink under missile lock, and bombers raid market plazas that ground rangers and Kestrel pilots can defend. Ground Hive nests now reinforce faster and hold larger squads to increase pressure during travel. Three successful drops drain a stall's stock until dawn. The Aircraft fabricator tab sells hull armor, a larger missile rack, stronger engines, gun cooling and four persistent paint finishes. Marked tower-roof pads provide additional landing and boarding points. Both carriers now have moving, walkable dorsal decks: the Kestrel can land on them, pilots can dismount, and the deck carries rangers along the carrier circuit; the player can continue the staged weak-point assault from the landed fighter. Cannons and lock-on missiles, flak, staged carrier weak points, crash debris and reward caches, a flight HUD with lock reticle and assault objective, and turbine sounds complete it. Acceptance:
- **Arcade flight pass:** keyboard A/D and Q/E steer as well as bank/pitch while mouse aim remains available; S cuts throttle and brakes; Left Alt is a dedicated air brake; Shift gives the Kestrel an eight-second high-thrust afterburner reserve, and the player can boost suit/free flight to 416/440 m/s. The dodge button triggers a full evasive barrel roll that absorbs incoming projectile damage during the move. Controller B dodges on foot and brakes in flight; its brake input no longer also starts a dash or roll. Both Controls tabs include flight and combat guides. The gamepad right trigger and bumper now fire and lock/release the Kestrel's weapons while piloting. Missile lock/release and the carrier weak-point campaign remain the combat loop. The current playable fighter is the atmospheric Kestrel; Scalari fighter meshes are not flyable yet, and spacefighter flight and orbital encounters remain planned with the Solar frontier.
- **Flight tests:** vertical takeoff and resting on the gear; wingborne cruise at a small angle of attack with a capped top speed; turning to the aim and leveling; climbing on afterburner; crash damage; the hover-to-flight transition.
- **Air war tests:** carriers launching wasps that attack and hit the jet; flak; cannons downing a wasp; a locked missile damaging a carrier.
- **Command ship test:** the robotic Hive carrier launches armored robot fighters.
- **Carrier assault tests:** four turrets gate four launch bays, which gate the core; core failure starts the debris crash, and the reward is issued at impact.
- **Moving carrier decks:** the dorsal deck is a kinematic support that follows the carrier and is removed after the crash lands.
- **Collision tests:** Kestrel ramming damage and rebound against wasps/carriers; wasps steer apart at close range.
- **Wing tests:** interceptor damage and bomber raids defended or lost after three plaza strikes; ranger and Kestrel shots share the flyer hit path.
- **Progression tests:** purchases persist and measurably change hull capacity, thrust, missile capacity and cannon cooling; Aircraft tab layout stays inside the UI bounds.
- **Smoke:** fabricates the Kestrel, lifts off, and downs a wasp.

Next:
- continue air-war playtesting and tuning;
- extend phase 14 with clips for the remaining traversal states, glTF animation import and named attachments (GPU skinning is done); tune trooper pacing in the planned hand-play pass.

## Wildkin heroes, the Heroes menu and the Starbowl arena — implemented

26 collectible animal and insect heroes, the Scalari's runaway experiments, are built procedurally onto the shared skeleton, from a hedgehog speedster to a butterfly mage. Each has three of 78 new powers, made from thirteen mechanics, and passives; winged heroes fly. Heroes wait in the city, the wilds and the mountain caves under beams of light. Meeting one adds them to the roster, their form to the creator, and their card to Pause > HEROES, where any present player can become them. The Starbowl is a floating four-player arena with scaling Hive waves, loot after every wave, saved best-wave records, and an arena champion every third wave. See [The Wildkin](wildkin.md).

Acceptance:
- **Tests:**
  - every form builds a clean, weighted, walking character;
  - one hero per form, with unique names and powers;
  - every one of the 78 powers has an effect on a squad of bots;
  - every hero can be met somewhere;
  - the roster round-trips by name;
  - the menu chooses only unlocked heroes for present players;
  - the arena's waves grow, pay out, and open and close the bowl.
- **Smoke:** aims at and meets a city hero, plays as them through the Heroes menu, fires all three powers, then clears and is paid for a Starbowl wave and leaves.
- **Captures:** `-Dshowcase=48` to `51` (lineups of all 26), `52` (the Heroes screen), `53` (the Starbowl).

Next:
- per-hero animation flourishes (tail sway, wing beats);
- better faces for snouted forms;
- hero voice barks;
- an arena boss every fifth wave;
- guests picking heroes from their own pads;
- a hero gallery viewer.

## Team saves: every player on their own — implemented

- **Kits:** each of the four players has a kit of their own (`game/Kit.zig`): wallet, suit upgrades, owned suits, armor and weapons with tiers, held pickups and health cells, and pets with their experience. The team shares only the world and story (`Progress`): flags, the hero roster, world pickups, the garage and Kestrel, and the arena record. Pickups go to whoever reaches them; arena waves pay every present player; guests trade from their own wallets and fight with their own weapons.
- **Saves:** save format 13 stores every known player's character and kit. Format 12 saves migrate into P1. A guest who leaves and rejoins comes back as themselves.
- **Ranger files:** every save writes each player's ranger file, `saves/rangers/<NAME>.json`. FOUR PLAYER SETUP > LOAD NEXT SAVED RANGER seats any saved ranger, so players can play as teammates or bring a character to another world. Wildkin forms are still chosen in the Heroes menu.

Acceptance: tests for kit purchases and round-trips, team progress and format 12 migration, the save's members, a guest trading from and fighting with their own kit, a departed guest's wallet surviving save and load, and ranger files; the smoke saves and restores P1 and P2 kits and round-trips P2's ranger file; capture `-Dshowcase=54` shows each seat's character and scrap.

Next, toward the city-liberation loop:
- city liberation state: each city's Hive grip, with the wild zones around it and the collaborators inside it;
- evidence and informants in the canopy district that reveal Hive alliances (scientists, officials);
- loot rarities and per-player gear drops for the hack-and-slash zones.

## Bio-synth pets and armor detail — implemented

- **Pets:** four collared bio-synth pets wait on the meadow ring: GARU the plasma hound, SKYE the chitin falcon, MOSS the root golem and LUMI the lumen moth. Break a collar to free one. It follows P1, fights the Hive (pounce, dive dart, ground slam, lumen zap), levels up as the party downs bots near it, and does a trick when petted. The moth mends. One pet is out at a time; petting it with others freed brings out the next. Freed pets and their levels are saved. The bodies are animated cel puppets.
- **Pets page:** the pause menu shows the active pet's XP bar and upgrade milestones, the rescue roster and wildlife distances, explains energy-net capture, opens the world map directly in wildlife tracking mode, and shows whether the field droid is built or which salvage it costs.
- **Armor:** each suit has its own two-tone scheme with the outfit colour showing. Every suit gains lit lumen strips, knee and elbow cops, a lit buckle and an open-face headset; the hardsuit and vanguard add a collar ring, a sternum core light and a back power pack (twin thrusters on the vanguard).
- **Faces:** smoothed face shading removes the cel shadow band that read as a beard on every jaw.

Acceptance: tests for pet levels and damage, ring placement, following and fighting (every species downs a trooper; the moth mends), puppet parts, pet save round-trip and rejection, suit detail (lit strips, power pack standing off the back, the vanguard's farthest) and jaw shading; the smoke frees a pet through the real pick, sees it follow and fight a trooper down; captures `-Dshowcase=16`, `17` (armor) and `58`, `59` (pets).

Next:
- pets for guests;
- pet commands (stay, fetch a pickup);
- per-pet voice chirps.

## Frontier wildlife, Scalari machines and a robot companion — first slice started

The wilds gain a catch-and-companion loop alongside the existing starter animal pet. Four existing animal species now appear 48–80 m from spawn, flee an approaching ranger, and can be snared with two energy-net hits before interaction catches them alive. Fresh captures separately grant 100 combat XP, 60 pet XP, 15 scrap, two parts and two lumen shards. A low-threat Scalari prospector, scout and stinger patrol arrives close to spawn. Enemy takedowns auto-credit combat XP and personal salvage to the nearest active player; nearby ground loot also auto-collects within a forgiving 3.5 m radius. A fabricator uses Scalari salvage components to build a second, robotic helper that fights beside the animal companion and levels from combat. Health, capture state, and helper rewards still need an in-game playthrough and tuning before this slice is complete.

The Scalari are synthetic AI overlords in transforming combat frames. They created the Hive's insect castes as slave workers and warriors. Combat should mix distinct machine drone roles with engineered insects and machine-insect hybrids, while Hive relay spires provide the local command and reinforcement source. Keep species, drone chassis, loot, capture rules, and companion behavior in small data-driven game modules rather than adding per-creature special cases to `Sandbox`.

**Wilds wayfinding and combat cadence:** the map marks live surface nests, cave mouths, unmet Wildkin, catchable wildlife, active fights, and travel points. Its tracking row cycles through nests, caves, Wildkin and capturable wildlife; the selected target centers and highlights on the map, with a bearing and distance on the HUD. Surface nests now field up to ten units, including five troopers, while cave nests can sustain eight ground enemies. City bomber assaults bring six Scalari ground fighters. The renderer supports sixteen nearby ground fighters and keeps eight character slots for Wildkin. Nests continue spawning while alive, and units outside the active area are reclaimed to free slots for later encounters. The renewable miner/scout Wilds patrol remains on a 42-second cooldown. Next: play-test city and cave combat density and tune performance and encounter pacing.

First playable slice, contained in the existing Frontier:
1. **Started:** energy-net weakening/capture gates, fleeing wildlife and separate capture rewards are in `game/Pets.zig` and `game/Frontier.zig`. Still validate net aim, escaping, co-op ownership, and the real encounter flow.
2. **Started:** existing Scalari scout, miner, stinger, titan roles now have a hybrid melee class with personal parts and XP. Add broader drone/insect behaviors and tune field encounters.
3. **Started:** a fabricator recipe, following/combat behavior, health, combat XP levels, and per-player Kit/save fields exist for one field droid. Add a player-facing upgrade interface and review balance.
4. **Open:** run and inspect a Frontier smoke route that catches an animal, earns automatic takedown salvage, builds the droid, and uses both helpers; add migration and round-trip coverage.

**Hive villains and city assaults — first modular slice:** surface Hive spires now render as field bases with workshops, relay pylons, assembly aprons and a command mast; their existing nest health, waves, rewards and story flags still define the raid objective. The character creator's **HIVE FORGE** panel exposes swappable Scalari frame modules, seven palettes (including silver, moss steel and amber carapace), and two material-layer styles: brushed metal with dark articulated joints and trim struts, or insectoid carapace with overlapping shell plates, compound optics, antennae and talon details. Closing the panel applies that design to Scalari titans in the current session. Showcases 82–84 review the forge and each finish. The first three bomber plaza raids now bring one siege frame and two Scalari escorts to ground level alongside the carrier's insect attack. The current design is session-only; named presets, asset-library parts, additional frame roles and invasion aftermath belong to follow-up work. Still needed: inspect the forge and robot silhouette in a fresh capture, play through a full wild-base raid and a city assault, and tune unit health/damage against the existing player and helper kit.

Defer a broad biome roster, multiple robot chassis, robot programming, and colony-scale production until this first field loop is playable and tuned.

## Nature: ground, water, foliage and footing — implemented

The terrain, rivers and plants get their own shading stages over the cel shader, and the ground now matters underfoot.
- **Ground:** world-space grass drift and tufts, stone strata on steep faces (and on the mountain panorama and cave walls), snow on the flats with blue shadows and sun glints. No textures, no chunk seams.
- **Water:** rivers ripple downstream, mirror the sky, glint, and foam along the banks; broad, slow caustic highlights help the surface read in motion; waterfalls streak white. Blended, drawn last.
- **Foliage:** grass, native shrubs and three luminous wildflowers join grassland ferns; broadleaf, needleleaf, willow, engineered redwood, copper-fan, moon-cascade and star-blossom trees sway in gusting wind. Redwood tops reach 152.4 m (500 ft), and the other giant forms rise roughly 96–150 m. The eight forest species use bounded, deterministic L-system grammars to build a shared branch skeleton. Needleleaf and old-growth pine use whorled conifer grammars with radial needle sprays; deciduous crowns use ovate, lanceolate, scale, fan, cascade and blossom leaf profiles. Bark structure and foliage are separate meshes. Branch taper and gameplay-distance crown coverage remain under visual tuning.
- **Night flora:** leaf flecks retain each species' pigment as they emit light: crimson redwood, red ember blossom, blue moonbell, gold sunspear, and the violet, teal, green and cyan tree and plant palettes.
- **Scatter:** faceted boulders on high, steep and dry ground; snow thins the flora and frosts trees and stones. Towering tree forms are deliberately rare beside low native ground cover. Former blue cube salvage nodes are now harvestable broadleaf saplings, 6.1–18.3 m (20–60 ft) tall. Candidate IDs remain stable; scatter generator version 8 migrates generator-5 through generator-7 saves without moving saved object IDs.
- **Footing:** rivers can be waded and swum; underwater movement follows camera aim in 3D, with ascend/descend controls and a stamina-powered 18 m/s burst. Snow is slow and slides, marsh and sand drag, the hoverboard is quicker on snow. Footsteps crunch on snow and splash in water; falling in splashes.

Acceptance: tests for ground cover and footing, the river surface, boulder meshes and placement, runner speed and stopping on each ground, the wade-to-swim transition, and ground-voiced footsteps; a clean Metal-validated smoke; captures `-Dshowcase=36` (river and waterfall), `41` (a range from the foothills) and `48` (meadow).

Nature review cameras are also available: `-Dshowcase=71` ground cover, `72` forest silhouettes, `73` terrain overview, `74` a close pine view, and `75` a close moon-cascade view. Showcase 62 provides the staged species lineup in fixed midday light. The bounded L-system forest fits each crown to trunk height and grows foliage along secondary branches and twig tips. Deciduous species use distinct leaf profiles and selected crowns have a denser recursive branch tier. The main stem now sweeps through the crown as one connected mesh, and successive branch tiers rotate around it. Crossed conifer needle sprays attach at three points along secondary boughs. The latest lineup has more distinct crowns, though regular gameplay views still need review. Showcase 71 has been moved off the tree at the stage origin, and 73 uses daylight for terrain review. `python3 tools/benchmark.py --nature` records terrain and scatter generation percentiles, visible nature counts, submitted triangles and CPU frame percentiles. The 600-frame benchmark passes, but high submitted triangle count makes distance-based tree LOD a priority; measurements are in [validation](validation.md). The city uses the shared native shrubs and flowers in its roof planters and a new generated hanging-vine mesh on selected stone facades; showcase 89 reviews garden scale. Nature-specific review and regression guards are tracked in [the nature upgrade plan](plans/nature-upgrade.md).

Detailed upgrade plan for terrain, ground cover, grass and trees: [nature upgrade](plans/nature-upgrade.md).

Next:
- review the trees in regular gameplay at several distances, tune sparse crowns, and add distance-based branch and foliage LOD before extending the shared skeleton to canopy Arbors;
- complete frame-480 captures for showcases 71–73 and capture the 62/70 nature baseline set;
- footprints and wakes;
- shoreline wetness and reeds;
- snowfall and rain with the day cycle: designed as a global four-season calendar plus deterministic weather in [weather and seasons](plans/weather-seasons.md) (planned, not built);
- boulder colliders for climbing.

## Mountain ranges and cave dungeons — implemented

Four seeded mountain ranges, peaks of 160–260 m with snow on their summits, stand 1.3–1.7 km from the hub. Rivers cut passes through them, and a far panorama keeps them on the horizon. Each range holds up to two cave dungeons: a mouth in the mountainside opens into a descending tree of chambers and tunnels. Halls and caches hold loot, lumen crystals light the chambers, and a Hive nest with troopers guards each heart. The caves are meshed watertight from a distance field. The streamed terrain opens over their mouths, and physics treats cave air as hollow, so players, troopers, drops and rays all work underground.

Acceptance:
- **Tests:**
  - the ranges keep clear of the hub, reach real peaks and open passes for rivers;
  - the panorama stays under the real ground;
  - every cave system has a mouth, chambers under 7 m of rock, and a heart below its mouth;
  - cave meshes have walkable floors and ceilings at every chamber;
  - the cave mesh covers every dropped heightfield triangle at the mouth;
  - a player walks in through a mouth with the full Sandbox step, stays under the slope, and stands on the floor of the first chamber.
- **Smoke:** walks P1 into the first cave with the real simulation step. It also reports the systems, the background-built meshes and the colliders.
- **Captures:** `-Dshowcase=41` to `44`: a range from the foothills, a cave mouth, the first chamber, and a heart chamber with its nest.

Next:
- steeper mouths with an overhang (they read as slots on gentle flanks; mouths now carry an ancient gate, doorways mark each tunnel, and halls hold collapsed labs, all visual dressing: see [validation](validation.md));
- interior lighting beyond the per-view cave blend (point lights at crystals and veins) and audio reverb underground; the sun no longer lights cave interiors;
- cave puzzles from the shrine solver;
- the Landscape authoring path's cave plans, joined to this runtime.

## Fighting, energy firearms and classes — implemented

The beam saber is a melee weapon: a ten-cut named chain (Crosscut, Return Slash, Rising Phoenix, Falling Star, Phantom Step, Skywheel Flip, Twin Vortex, Comet Thrust, Meteor Break and Nova Arc) with distinct rigged blade paths, flip/spin poses, queued presses, a charged wave, a guard that parries bolts back, knockback, stun, lunges and bolts cut from the air. Four energy firearms join the fabricator: the sniper rifle (scoped, piercing beam), the machine gun (heat), the heavy rifle (piercing, charged) and the energy bazooka (arcing orb, burst, detonation). Players are Rangers (tech specials) or Synthetics (powers), each with energy and three specials. Bodies take aim, swing, guard and cast poses, and weapons are drawn in hand.

Acceptance:
- **Tests:** one hit per unit per cut, a queued backhand, a charged wave and a parry window; a sniper beam that pierces exactly one unit and scopes; machine-gun rate and overheat, heavy-rifle charge and bazooka burst; each class's specials, their energy and cooldowns, and the overshield soaking damage; the rig's hand sweeping across the front.
- **Smoke:** fabricates the saber and sniper through the panel, lands a three-cut combo with P1's rig, pierces two drones, and throws a grenade and a slam.
- **Captures:** `-Dshowcase=37` to `40` (saber, sniper, machine gun, lumen lance) and `-Dcharacter-showcase=5` (a Synthetic).

Next:
- hand-play tuning of damage, energy costs and cooldowns;
- dedicated weapon meshes (the held weapons are block assemblies) and a lance and slam effect pass;
- per-bone hitboxes for the Hive (the blade tests unit spheres).

## Frontier: vehicles, pickups, the Hive and weapons — implemented

Hover cars built by your generator (`src/vehicle/`) fly on momentum-theory fans with a ride-height flight computer, and three designs are fabricable. 62 seeded pickups (lumen shards, rotor cores, Hive alloy, vital cells) feed a fabricator for cars, suits, armor accents and weapons. Three Hive nests in new outskirts send drones and sentinels that patrol, hunt with line of sight, and shoot back. The `combat/` weapons are connected through a weapon tool, and players have health and respawns.

Acceptance:
- **Generator tests:** watertight meshes, textbook aerodynamics and nozzle values, closed-form mass properties, energy-conserving spin.
- **Flight tests:** hover level at ride height, cruise and boost caps, following rolling hills at speed, holding altitude over gaps, wall stops.
- **Gameplay tests:** pickups collected once, recipes paid exactly, nests that wake, spawn, hunt, shoot and fall, and shots that destroy drones. The saber cuts only in front, and the shield absorbs.
- **Smoke:** fabricates a car and a blaster through the panel, flies the car, and downs a drone, under Metal validation.

Since then: guests carry the party's weapons on their controllers, saves keep car positions, and Hive troopers on foot join each nest. The racer pass adds a seeded elevated sprint circuit with ramps, two jump gaps, eight ordered gates, two charge pads, a finite boost capacitor, and a static collider shared by the road mesh. A tessellated vertical loop now uses signed magnetic adhesion, track-relative attitude, and tangent-aligned propulsion to carry cars over its inverted crown. Vehicle silhouettes also include a splitter, side-intake louvers, canopy spines, and a rear diffuser.

Next:
- guests' conversations and car piloting;
- nest assault events and a Hive progression across the map;
- hand-tune the three racer silhouettes, paint and lighting in the running game;
- tune loop entry speed and boost timing by hand, then add more ramp and loop variants;
- split-screen race HUD and multiplayer starts with independent vehicle controls and lap state.

## Traversal and local co-op — implemented

Starfall's traversal verbs are ported to metres, seconds and the fixed step. They cover buffered and coyote jumps, wall slides, wall jumps, jump-started climbing, ledge hang and mantle, rolls, stomps, swimming volumes, and traversal kits: grapple, hover jet, flight, hoverboard and Energy Skate. A regular jump takes off first; holding jump does not immediately engage air assist, which requires releasing and pressing jump again while airborne. Energy Skate has terrain-resistant high-speed movement, a boosted jump and fuel-powered air assist. The current traversal pass raises on-foot sprint to 15.5 m/s, improves long-jump launch and air carry, strengthens directional wall jumps, and raises Energy Skate sprint to 30 m/s. Rolling sunmeadow patches bring original lime, gold and blue-green grass silhouettes into the procedural lowland palette; the existing generated Arbor trunks remain full triangle-mesh collision and have grown to 510 m and 400 m. Armor has joint-bound luminous roller runners; saber color follows the player's accent and its elemental charged crescent scales with weapon tier. Up to four local players share one window in split screen. The macOS GameController bridge handles drop-in join and leave, and F6 adds a keyboard-less guest for testing.

Each view streams its own terrain under one shared per-frame upload budget, and each player's own body is hidden only in their own first-person view. Guests can move, climb, grapple, and press buttons, and proximity sensors see all players.

Acceptance evidence: headless tests cover the traversal verbs and the climb gate. Another test has three guests join, move and look independently while P1 stands still, open the powered door from its button, leave, and rejoin beside P1 after a save round trip. A layout test tiles one to four views. A ReleaseSafe smoke run with Metal validation exercises four, two and one views. See [validation](validation.md).

Limits: guests do not build, wire, carry, drive, salvage, or persist. Players do not collide with each other. Only macOS controllers are read. The canopy benchmark measures one view; split-screen CPU cost has no benchmark yet.

## Canopy world

The game's direction is set in [world and systems](world.md): Arbors 300–600 m tall, a canopy city of grafted towers and bridge roads, painterly cel shading, and three braided play styles (explore, engineer, grow) over a procedural city the player extends. The phases below build it. Each is a runnable slice with headless acceptance tests, native Zig throughout.

## 6. Canopy foundations — implemented for the single-Arbor test world

Make the engine able to hold a vertical world and look like one.

1. Done: static triangle-mesh colliders with a BVH, and oriented boxes built from them. The character climbs a 15° mesh ramp, is stopped by an 80° wall, and stands on and climbs a 5° deck; crates rest on mesh floors; rigid bodies settle on tilted mesh decks; wheels, picking, and placement see meshes.
2. Level of detail for tall placed content is done: a `Prop` may carry a `lod` mesh handle and `lod_distance`; beyond that distance the renderer substitutes a coarse proxy instead of the full mesh (`World.Prop.effectiveMesh`, exercised by `StreamingScene.gatherProps`). The test Arbor swaps to an 8-segment, ring-only trunk silhouette beyond 450 m, with a headless test confirming the proxy is under a tenth the vertex count and spans the same height. Still open: streaming (residency eviction) for tall content. Phase 6 introduced one resident test Arbor; phase 7 expands the bounded fixture grove to three resident trees, with detail switching but no eviction.
3. Done: toon ramp, rim light, depth silhouette outlines, aerial haze, and warm/cool day/night lighting. A twenty-minute cycle derives from the saved world tick and appears on the HUD; powered lamps (including vehicle-mounted lamps) and ranger accents publish emissive material values. Direct lighting fades through twilight without a face-lighting flip. Emission is surface brightness, not local light casting or bloom.
4. Done: a hand-authored test Arbor (`procedural/TestArbor.zig`) 100 m from the spawn, with a 320 m tapered trunk, a 2.5-turn spiral ramp with a curb, a branch platform at 40 m, a 14 m bridge road descending 5.7° to a tower top at 36 m, and render mesh and colliders from one description. The walk acceptance passes headlessly: up the ramp without dropping below its surface, onto the platform (±0.3 m), and down the bridge to the tower top (±0.1 m). Rendering switched to reversed, infinite-far depth with a height-aware haze so the tree is visible above the ground haze.

Acceptance: the headless full-ramp/platform/bridge walk passes. The `--canopy` benchmark renders up close and at 1 km, exercises both LODs, and passes the 16.667 ms render CPU P99 budget (0.926 ms on the recorded Apple M3 Pro run). Presentation interval P99 was 21.074 ms; whole-command-buffer GPU time is measured, but that historical canopy run predates the timing hook. Visual art-direction approval remains open. Multiple-Arbor residency remains deferred as described above.

## 7. Arbor genome — implemented as a bounded grove

Implemented: validated genome v1 and Arbor generator v1; bounded seeded space colonization; phyllotactic scaffolds, tropisms, flat shelves, colored bark, foliage clusters, and lumen; full/proxy meshes and woody mesh colliders from one parent-before-child skeleton. The grove adds 420 m narrow and 340 m spreading Arbors beside the preserved test Arbor. Each skeleton doubles as a vascular graph with a root supply and branch limits.

Sap taps and a ready-wired sap beacon are in the build palette. All machines prepare demand before tree allocation, then apply power and movement. Nearby wood determines attachment, regular generators offset demand, idle/disabled/detached taps take no share, and lamps and tree lumen dim under brownout. Saves record the Arbor generator and content version 4.

Acceptance tests cover same-seed reproduction, measurable silhouette changes, parent/mesh validity, generated shelf walking, shared brownouts across separate machines, independent trees, and reconnection after save/load. The build interaction test places a powered beacon at a trunk, inspects its tree ID, and rejects remote placement. See [Arbor genomes and sap](arbors.md) and [validation](validation.md).

Limits: three fixed resident trees; conservative allocation without redistribution after branch bottlenecks; no runtime grafting or growth, in-game genome editor, pipes, or tree residency eviction yet.

## 8. Canopy city — implemented as a bounded district

Implemented: a versioned six-plaza graph around the resident grove, three generated towers, 14 m bridge roads with vine cables and lane/walkway markings, trunk-ring plazas and spurs, and market canopies. Validation runs before geometry installation and checks reachability, grades at most 6%, road/terrain/trunk/plaza clearance, approaches, and market bays. Tool 4 previews, builds, and removes player spans between stable plaza IDs. Elevated prefab placement and vehicle exit use the deck beneath them. Save v7/content v5 (now v8/v6, see phase 9) persists bridge edges alongside existing machines and taps, staging collision allocations before replacing the live world.

Acceptance: continuous walking and powered rover driving around the complete loop; elevated rover placement and exit; two-click bridge creation/removal; traversal and save/load of an added bridge; invalid graph and allocation-failure rejection without mutation. See [canopy city](city.md) and [validation](validation.md).

Limits: fixed topology with seeded variation, one resident district, at most four added spans, decorative suspension and markets. Runtime woody grafting/growth remains deferred from phase 7; generated trunk walkways are static. The legacy test-Arbor approach retains its original steeper grade outside the new road solver.

## 9. Living city — implemented as a bounded district

Implemented:

- **Routing:** the district is a routing graph (plazas and roads, including player bridges) with shortest routes, right-hand lanes and walkways.
- **Traffic:** three cars reuse the rover's vehicle physics, with an autopilot that yields in its lane and breaks deadlocks. Their headlamps brighten at night.
- **Pedestrians:** eight use the character controller on the walkways.
- **Closing bridges:** removing an occupied bridge closes it to new traffic and removes it once empty.
- **Markets:** stalls at the three towers buy salvaged parts for scrap and sell kits of three new market blueprints. Kits place, use up and refund, and stock sells out and restocks at dawn.
- **Metro first slice:** a static light-rail loop now follows the plaza roads, with luminous paired tracks, outboard supports, and boarding platforms at the South, North, and West market towers. The three stations are selectable destinations on the world map; arrivals land on a clear station platform.
- **Saves:** format 8 and content 6 save the wallet, stall stock, market day and kit machines.

Acceptance evidence, all with the real Sandbox:

- A minute of free traffic in which every car reaches at least three plazas and nothing needs recovering.
- A car crosses a new 0 → 3 bridge while the bridge reports occupied.
- A car bound 1 → 0 → 3 has the bridge closed mid-trip, reroutes 0 → 5 → 4 → 3 and arrives, and the closed bridge disappears once its pedestrians have crossed, with zero recoveries.
- A market run salvages a part, opens a stall, sells, buys a kit to sell-out, places, refuses capture, refunds, closes when walking away, round-trips a save, and restocks at the next dawn.

See [canopy city](city.md) and [validation](validation.md).

**New York City travel slice — implemented; liberation content planned:** the world map reaches a seeded Hudson-side NYC landing district east of Detroit, with its own terrain and vegetation seed, twenty large stone-and-glass skyline landmarks with planted roofs, a safe on-foot arrival, and a destination-specific map view. Chicago has a separate fast-travel landing on terrain sampled from its imported heightmap. Antarctica has a bounded terrain landing and globe marker, a blue ice albedo and glacial lighting pass, towering non-colliding approach ramparts with a wide blue-lit north exit (`-Dshowcase=85`), and two animated visual scorpion patrols. It remains a foothold for the future Subglacial Hive campaign: walls are scenery and patrols do not yet participate in combat. These city entries are footholds: connected, walkable skyways, full city meshes, missions, bosses, discoveries, shops, interiors, and liberation state remain future work. Finish Detroit's city loop first; then expand the other Earth cities before extending intercity transit. The Antarctic base and its robot-rescue campaign are also planned content.

**Terrain locations, sky-city styles, and deep bases — first mountain slice active:** `assets/CitiesUSA/` owns the Detroit, NYC, Chicago, and LA source rasters. `procedural/TerrainSites.zig` maps 10 Himalayan peaks, 6 alien strongholds, and 24 US city entries to biome/faction recipes, hazards, traversal hooks, enemy roles, bosses, and facility archetypes; Phoenix, Seattle-Tacoma, St. Louis, and Charlotte have no local PNG yet. The Earth globe now plots all 24 city sites, 10 mountains, and 6 strongholds with separate marker styles and city-biome colors. Detroit, NYC, Chicago, K2, Cloudwater Basin within K2, and Antarctica are playable travel destinations; the remaining markers are catalog planning points. `procedural/Interiors.zig` holds connected room grammars for sky cities, Scalari mechworks, Hive broodworks, mountain vaults, and engineered-drake roosts. K2's imported terrain and snow/ice biome feed the shared mesh/collision sampler, a six-room Black-Summit Works connects into existing cave collision and encounter systems, and the Scalari guards/Titan award per-player materials and combat XP. Cloudwater adds a local art-led basin recipe and a safe map stop without altering the cave campaign. Other location recipes and the multi-level Interiors grammars remain authoring data; their bases, enemy behaviors, and mission mechanics are not live.

Next, manually smoke the K2 landing-to-heart route and the Cloudwater Basin fast-travel, stream and grove in an interactive session; also verify boss defeat and saved completion state, then tune what play reveals. Add another terrain site after that review. For cities, preserve the existing 2,500–3,500 ft eco-skyline scale while extending walkable suspension skyways, gardens, public venues, and elevators beyond the Detroit/NYC footholds. Keep the Earth city liberation loop ahead of later planetary expansion.

**Immediate 3D helpers — implemented:** `engine/Scene3D.zig` provides bounded per-frame model, box and sphere commands over Catalog handles and `World.Prop`, plus normalized screen rays and nearest bounds-sphere picking for editor selection. The existing publisher uses it for core district geometry and the NYC landmark set; showcase 78 reviews the real Mach-rendered output. The picker is an editor convenience and does not replace gameplay physics. This is not a Raylib port and does not change asset loading or introduce a scene graph.

Next metropolitan slice: grow this canopy hub into an Earth city region with a dense downtown and public venue block, residential suburbs, farms, then a clear wilds edge. Build the first mall/arcade/music venue around a traversable maintenance tunnel and subway platform, and make the light-rail stations and rooftop parkour routes usable together. After the other Earth city regions and a spaceport exist, extend the same transit modules into high-speed intercity and port links. Do not represent disconnected cities or a spaceport as travel destinations before their playable arrival areas exist.

Also implemented:

- **Rootsong:** the signal bus limited to trees that share roots. Root groups come from overlapping root reach, and root sender and listener devices must be within 4 m of wood.
- **Plaza priority:** first come, first served, with the deadlock breaker as a backstop.
- **Guest trading:** guests trade with the shared wallet.

Further acceptance evidence:

- **Rootsong:** a song from the test Arbor lights a lamp at the root-sharing narrow Arbor but not at the separate spreading Arbor or away from wood, and it survives save/load.
- **Plaza priority:** a car waits two seconds at the edge of a plaza another car is inside, then continues to its goal with no deadlock broken.
- **Guest trading:** a guest sells parts and buys a kit at a stall while its movement is frozen, and B closes the stall.

Remaining polish, not blocking: bioluminescent city lighting beyond lamps and headlamps, and traffic lights.

## 10. Rootdeep and shrines — implemented as two verified shrines

Implemented:

- **Generation:** two shrines on seeded flat sites on the forest floor. Each is a chain of rooms whose doors open on logic over button latches and crate plates (the new `plate` device kind).
- **Verification:** a seeded generate-and-verify loop accepts only candidates that a breadth-first solver proves solvable and non-trivial, then keeps the one with the longest shortest solution of six.
- **Compilation:** each shrine compiles into an ordinary validated blueprint plus world crates.
- **World rules:** shrines are protected from editing, have a reset button, and save completion in format 9.
- **Reward:** opening the seed vault adds a Rootsong blueprint to the palette, which feeds the engineering and Rootsong loops.

Acceptance evidence:

- 300 seeds all verified solvable with legal plan replays and valid blueprints; the median shortest solution is 8 actions and the maximum 16.
- A headless test plays each placed shrine's own plan in the real Sandbox by walking, aiming, pressing buttons, and carrying crates onto plates through real doors. After every action, each door's actual state must match the puzzle model. Both shrines complete, grant their rewards, and keep completion through save/load; reset restores crates, latches, and doors.

See [Rootdeep shrines](rootdeep.md).

Limits: two straight room chains, crate-only plates, blueprint rewards (no genome fragments yet), no Rootdeep streaming or special terrain, and free flight can bypass walls.

## 11. Mods — implemented as mod API 1

Implemented:

- **Packages:** versioned mod packages (`mods/<name>/mod.json`, format 1) with validated blueprints and an optional WebAssembly script module, installed all-or-nothing.
- **Public API:** a constrained API (version 1) of data plus `script` devices. A script device calls a mod's pure `fn(a, b, c, d, time) f32` export with fuel, memory and depth limits and no imports.
- **Runtime:** a native Zig WebAssembly interpreter, chosen after a written [evaluation](scripting.md) that compared logic graphs, embedded C runtimes, a custom language, native plugins, and a JIT.
- **Supporting changes:** dimmable lamps (`on` is a 0–1 level), and saves (format 10) that record installed mods and degrade gracefully when one is missing.
- **Example:** the `glowworks` mod, built by the build graph.

Acceptance evidence:

- The Zig-compiled example module runs in the interpreter and matches native results.
- Twelve kinds of invalid package are rejected with reasons, including path traversal and foreign scripts.
- In the world, a modded breathing lamp follows its script one step behind, like logic.
- Duplicate mods and changed designs under a mod's name are refused.
- A save made with the mod loads into a world without it, reports the mod, and the lamp revives when the mod is installed.

See [mods](mods.md).

Not in API 1: mod-defined genomes, shrines, wares, or assets; host imports; dependencies; full package reload. Development Wasm reload is available with `-Dhot-reload=true`.

## 12. Scale — implemented within the pinned Mach

Implemented:

- **Workloads:** repeatable 10K/100K/1M workloads (`tools/benchmark.py --scale N`) on the streaming route.
- **Culling and LOD:** per-cell CPU culling and LOD (960 cells, never per object), and per-instance frustum culling on the GPU in the vertex stage.
- **Submission:** merged ranged instanced draws (about 29 per frame).
- **Streaming:** instance data under its own per-frame upload budget, with the CPU copy freed once resident.
- **Reports:** CPU and presentation percentiles, objects submitted, draws and visible-cell percentiles, generation time, GPU and CPU bytes, and peak process footprint.

Acceptance evidence: all three workloads pass every check in 600 measured frames. Render CPU p99 is flat (1.27/1.21/1.28 ms) from 10K to 1M, presentation p99 is about 21 ms throughout, and the 1M field is resident by frame 30 under a 2 MiB/frame budget. Peak footprint is about 1 GiB at 1M; isolation runs attribute about 380 MB to driver geometry storage for drawn instances. See [scale](scale.md).

Blocked by the pinned Mach, pending a decision to update or fork it:

- GPU-compacted culling (no shader atomics);
- indirect submission (indirect draws panic `unimplemented`);
- Per-pass GPU timing (Metal benchmark reports whole-command-buffer duration; timestamp queries remain unimplemented).

## Sky city — content pass

The district is rebuilt as a sky city held up by steel:

- **Bridges:** five steel bridge styles plus the vine spurs. The six roads are assigned styles by span length, and players choose a style with Tab.
- **Supports:** braced pole piers under every non-suspension road, and braced legs under the free-standing plazas.
- **Skyline:** about twenty seeded, validated megatowers (modern, rounded eco, Gothic and industrial) with roof gardens, stone-and-glass material variety, hanging ivy, and a cable-supported, level skyway network joining the high-rises through roof gardens and sky collars (rebuilt 2026-10-23 after it had silently disappeared); lower factory blocks stay in the ground city, and one sky-lobby tower sits beside each tower plaza.
- **Night lighting:** window columns, spire beacons, lit rails, and cable light strings.
- **Saves:** district generator 2 and save format 12 (bridge styles and the sprint course best lap).

Acceptance evidence:

- The clear deck envelope holds for every style on every road and on 0 → 3, across seeds.
- Towers and piers reach the ground, outside plazas.
- The skyline is plentiful and clear of every road, buildable route, plaza, trunk, and the spawn area.
- A player stands on every style's lanes and walkways, and styles survive save/load.
- The complete walk and drive loops cross all styles.
- Frames were captured from fixed viewpoints and reviewed by eye, by day and at dusk (see [city](city.md#the-sky-city)).

## Next level — phases 13–16

The next phases close the gaps to a production engine, in this order. [Engine alignment](plans/alignment.md) records how each outside suggestion was weighed against the codebase. Native Zig is kept: C-library physics, audio, and animation were declined on 2026-10-01.

### 13. Asset pipeline — slices 1–5 implemented (identity, packs, background loading, development reload, GLB trace/modules and static importer hardening)

- **Identity:** stable GUID asset references (`AssetRef`) with `.meta` sidecars holding the GUID, source hash, importer version, and typed import settings.
- **Build output:** a manifest with dependencies, and content packs.
- **Runtime:** a registry, async loading with progress and per-frame GPU budgets, and hot reload by GUID with generation-bumped handles.
- **3D authoring:** the host `asset-compiler` converts static `.gltf`/`.glb` geometry into HWMS; `trace` maps source identity and scene parts, and `split` exports selected-scene primitives. `modifiers`, `modifier-list`, and `modifier-edit` generate, inspect, and revise source-linked component labels, surface roles, palette colors and transforms; `preview-modified` renders edits with CPU-skinned bind or compatible procedural-run poses. Character Designer's in-game **IMPORTED PARTS** window edits components and can import a user-selected binary GLB. It maps recognized humanoid bone names to the game's run tracks and bakes a retargeted preview, then saves the GLB and editable sidecar under `saves/`. Since HWMS is static, gameplay still uses a baked pose; live imported skeleton/clip playback, animation-channel import, in-game relabeling and shape transforms remain open. Missing normals are generated, and GLB structure is validated.
- **Mesh editing and generated-character tools:** modifier reliability and incremental preview (M0–M3), the imported-mesh vertex core and persistence (E1/E2), the VERTEX TOOLS viewport (E3/E4), and stylization S1–S5 (symmetric painting, gradients and filters, face/edge gizmos, topology operations, and weight painting) are implemented. The 2026-10-20 owner direction makes the next character-editor priority a generator-backed overlay on the native Ranger; the generated character remains the source of truth and edits must preserve the existing four-player render budget ([product boundary](plans/mesh-editor.md#owner-clarification-generator-overlay-and-battle-performance-2026-10-20), [engineering and performance gates](plans/mesheditor.md#native-character-generator-overlay-and-performance-gate-2026-10-20)). Imported-GLB editing remains a secondary workflow. The 2026-10-22 upload library (switch and delete uploads, auto-rig for meshes without a skeleton) and face design pass (twelve faces, eye shapes, face marks, eye colours) are done; [character assets](plans/character-assets.md) plans the next steps: sockets on any body (CA1), the game face on the face area of an imported head (CA2), procedural armor on imported bodies (CA3), a shared team library of reusable parts (CA4) and a tabbed designer (CA5). Touch and pen input, static-mesh import, a parts library, auto-weights and texture painting (S6, after the texture path) follow. The texture reuse feature map ([texture authoring](plans/texture-authoring.md)) starts with a runtime texture asset, mirror/repeat and triplanar mapping, and seeded fractal variation before texture painting and bake.

Remaining: model modules are not yet accepted by Mod API 1 or placed/crafted in-game; texture, audio, scene and animation resources need their runtime paths. Acceptance: renames keep identity; only changed sources reimport; invalid references are rejected without mutation; a 64-asset pack loads within the frame budget; a model edited on disk swaps in a running session. See [plan](plans/asset-pipeline.md).

### 14. Skeletal animation — in progress

Progress: keyed walk, run and climb clips with a crossfading traversal controller; GPU dual-quaternion skinning from a 64-joint uniform palette per character (one dynamic-offset bind group, `-Dcpu-skinning` keeps the CPU path); offline GLB skin trace/preview; an in-game import path that maps rig bone names onto all 21 humanoid joints and retargets the live pose onto the import's own proportions; and crossfaded motion and action transitions, a landing dip, idle breathing and speed-matched strides. `HWMS` remains static and glTF animation channels are not imported. The Captain source has 65 joints, so preserve its full rig and use the CPU path initially rather than truncating to the GPU palette. Remaining: runtime `HWSK`/`HWAN` import and live retargeting, sockets, and per-bone hitboxes. Webcam animation capture is a later consumer of this foundation; see [user animation capture](plans/animation-capture.md).


- **Import:** glTF skins and clips into `HWSK` and `HWAN`.
- **Runtime:** allocation-free pose sampling and blending, GPU skinning from a 64-bone uniform palette (with a CPU fallback), and `Player.Motion` mapped to clips as data.
- **Attachments:** sockets for attachments and per-bone hitboxes for combat.
- **First content:** the generated ranger (`src/character/`) already supplies a skeleton, skin weights, rigid armor bindings and CPU skinning; this phase adds imported clips, blending, GPU skinning (done) and sockets on top of it.

Acceptance: exact import round trips, pose-math reference tests, the controller selecting the right clip for every traversal state, a carried crate held at the hand socket within 1 cm, and render CPU within budget with 20 animated characters. See [plan](plans/skeletal-animation.md).

### 15. Scene graph and JSON scenes — planned

- **Nodes:** fixed-size, trivially copyable nodes in parent-before-child order, with typed component arrays.
- **Format:** JSON scenes whose `_ref` fields resolve through the registry, with staged hydration.
- **Placement:** anchors to plazas, shrines, and Arbors; prefabs with overrides; hot reload by node ID.
- **Spawn content:** the hard-coded spawn content moves into `scenes/spawn.json`.

Acceptance: byte-identical round trips, rejection without mutation, every existing spawn test passing on the spawn scene, and live edits applying in a running session. See [plan](plans/scenes.md).

### 16. UDP networking — not planned (local desktop product, 2026-10-15)

- **Topology and transport:** a listen server with up to three remote guests, over native `std.Io` UDP with reliable and unreliable channels.
- **Join and snapshots:** joining through the save format, and delta-compressed snapshots at 30 Hz.
- **Responsiveness:** prediction and reconciliation for the local player, and interpolation for everything else.
- **Authority:** server validation of every action, and a deterministic simulated link for tests.

Acceptance:

- Exactly-once reliable delivery at 150 ms, 5% loss, and 20 ms jitter.
- Under 64 kbit/s per client.
- Predicted positions within 5 cm of the server 99% of the time.
- Invalid client actions refused.
- A two-process loopback session that opens the powered door on both sides.

See [plan](plans/networking.md).

## Landscape authoring — isolated generation foundation implemented

The importer emits validated `HWMH` v1 assets, and `.pgm` sidecars preserve GUIDs, source hashes, importer versions, and validated physical settings. A typed registry reference can resolve a decoded heightmap. Procedural shaping provides biome classification, bounded terrain stamps, deterministic temple pads, and cave route plans. `Landscape.generateChunk` and `Landscape.terrainSurface` use the same shaped-height source; headless tests verify adjacent chunk seams and agreement with the generated triangle mesh.

This isolated path is not yet bound through `Catalog` into the active streamer, `Terrain.surface`, renderer, physics, or Sandbox. Temple/cave plans do not yet produce in-world meshes or colliders. Keep the current world as default until an opt-in scene proves those runtime paths together. Next: manifest/Catalog binding, then pass one immutable landscape context through streaming and gameplay before building a playable biome/temple/cave slice with the existing blueprint validator and shrine solver. See [Heightmapped Landscapes](plans/landscapes.md).

## Next

Phases 1–13 have runnable slices. The game layer has also grown well beyond the phases: menus and conversations, procedural audio, hover cars and the Kestrel fighter, the Hive on the ground and in the air, fabrication and progression. The ordered plan for what comes next is [next steps](plans/next-steps.md). The gameplay reachability review and ordered gameplay stages (G0–G6) are in [gameplay next steps](plans/gameplay-next-steps.md). The current user-directed visual priority is the [character and environment pass](plans/visual-direction.md). The first Ranger face, neck, field-harness, and helmet-fit slice is implemented; differentiated armor and the Frontier material, foliage, and city-composition pass remain next.

**Order of work from 2026-10-23 (owner):** organize first (done 2026-10-23: pending work committed, docs aligned, the course skip fixed, [playtest checklist](playtest.md) written); then **feel**: hitstop, per-view camera shake, damage numbers, controller rumble and enemy wind-up telegraphs with melee parries (built 2026-10-23, each with a settings switch), then tuning from the owner's playtest results, with cheap measured performance fixes alongside (2026-10-23: the one-pass flora gather landed with identical output but no measurable frame-time change; a block edit fell from 15.6 to 2.3 ms by fixing the collider build, so moving remeshing to a worker is deferred; the four-player frontier view is GPU-bound at about 17 ms p50 and 21.8 ms p99, so forest level of detail is the performance item that matters next; prop bucketing and a shorter suite remain); then **graphics**, starting with real sun shadow maps (two cascades per view, crisp cel edges, measured in four-player), sap-flora sway, a sky dome with clouds, and the palette, haze and grass items in [visual direction](plans/visual-direction.md). Items 1 to 5 below keep their detail.

0. **Restore a green suite and explicit save floor — complete 2026-10-14:** the tabbed Character Designer is covered by the layout test; the save loader explicitly supports formats 13–25 and has a checked-in round-trip fixture for every supported version. The one-command gate passed 440/440 on default and Zig 0.17, plus the default Metal smoke. **Re-established 2026-10-21:** terrain-heightmap commits had left the suite red (8, then 10 failures); it returned to green at 516/516, and the scripted smoke now fails the run when a check fails. Save format 26 adds ranger discovery claims, 27 sculpted-terrain tiles, 28 player-built blocks, 29 per-player block stock, 30 crops, 31 fighter frame progression, 32 face details, 33 structures and 34 player-placed living-sap flora. The current save fixtures cover formats 13–34; the latest recorded full suite was 551/551 before formats 31–34 (see [validation](validation.md)). Details and remaining gates are in the [technical review](plans/next-steps.md#technical-review--2026-10-14).
1. **Bound the forest's GPU cost:** four 2026-10-21 runs measured 5.58 million submitted triangles and a median Metal GPU p99 of 12.44 ms, below the 16.67 ms target. The older 12.25 million / 19.69 ms result did not reproduce; reconcile the benchmark draw-set difference, then keep distance LOD ahead of more crown detail. See [validation](validation.md#nature-benchmark-rebaseline--2026-10-21) and [the nature plan](plans/nature-upgrade.md).
2. **Play, measure and tune:** the four-player frontier benchmark has a recorded passing baseline. Refresh it after material changes and complete the hands-on flight, combat, controller, co-op and audio checklist. Fix or file the findings.
3. **Finish the first Earth city liberation loop (per city: three sub-missions, one boss battle, ten item discoveries; Detroit's content approved 2026-10-22, plan in [city content](plans/city-content.md)):** the Foundry Ledger, Windsor Gate and Bile Archive investigations have playable paths with shared story flags and per-player rewards. The Collaborators' Titan can be fought at the west Windsor bridge after all three reports and a cleared Frontier; defeating it rewards each present player's `Kit` and records Detroit free if the Frontier stays clear. All ten optional landmarks now have targetable pickups with personal rewards in `Kit` or shared keepsake flags in `Progress`. Eight of them now sit in gate cages opened by a short platformer course matched to their method; the bell tower and sky lobby keepsakes are their landmark climbs. The Foundry yard gate is solid while shut, a load mid-fight brings back only the fighters still standing, and pedestrians flee city fights. Liberation dressing, four-player interaction checks, controller play and hands-on tuning remain. Complete Detroit before widening to another city. Detailed gates are in [next steps](plans/next-steps.md).
4. **Co-op completeness:** allow guests to drive/fly, talk, fabricate and earn their own progress through the complete local loop.
5. **Content and visual polish** (the specialized asset studios for characters, vehicles, nature and cities, with touch and pen drawing, are planned in [asset studio](plans/asset-studio.md); the vehicle studio's headless core is implemented, the in-game panel and custom designs are not): prioritize issues found by hands-on play; keep capture and benchmark evidence with changes.
   - **Detroit, NYC and Chicago terrain:** supplied landform rasters shape all three playable regions, with deliberately heightened relief and a soft blend into seeded wilds. The coast/rivers are approximate because the PNGs have no geographic metadata; full city footprints, water bodies and ground scatter still need hands-on tuning. An LA raster remains for a later region. The world map has a rotatable Earth view with Detroit, Chicago, and NYC travel markers; LA is shown as a future destination.
   - **Canopy city gardens:** Detroit's generated towers now have open rooftop planting beds filled with shared native shrubs and flowers, trailing vines on selected stone facades, kiosk pergolas and seating. Skyway terraces gain benches beside their planted beds. The close art-review camera is `-Dshowcase=89`. These are visual assets on the existing seeded layout; player-built city editing, planting gameplay, and comparable districts for NYC and Chicago remain open.
   - **Wilds dressing slice:** mountain trailheads now get authored cabin/barn farmsteads, cave cache rooms get rootbound sanctuaries, and a cave wave can roll one rare Scalari hybrid/stinger. These are visual scene assets plus an encounter variation; building entry, farm gameplay, loot tables for the rare unit, and hands-on route tuning remain open.
   - **Hive siege dressing:** living surface nests now use a fortified biomineral base with an elongated egg tower, perimeter walls, and corner laser emplacements. Three installations ring Detroit Arbor Reach and four ring New York's playable arrival; they are siege landmarks, while living wild nests remain the combat objectives. Turret firing and city liberation progression still need gameplay wiring.
6. **Later content:** ocean cities, the Solar frontier and the multi-world arena campaign remain authored plans/catalogs. Their human and cetacean settlements, carrier assault, local planetary flight, stations, mining colonies, Gaia and democracy systems are not playable yet. Build them after the Earth loop proves the shared runtime and save contracts. The [Project Helios habitat plan](plans/space-habitat-network.md) puts space construction behind staged resource, power, thermal, pressure, radiation, and rotation demonstrations; Helios-20 is a speculative reference, not a game milestone commitment. An early procedural habitat cylinder and Rand Corporation's Mother construction ark can now be reviewed in showcase 66, but there is no orbital gameplay or construction loop yet. The 0.5c drive and Gaia globe remain clearly labeled science-fiction exceptions. See [ocean cities](plans/ocean-cities.md), [Solar democracy](plans/solar-democracy.md), and [planetary frontier](plans/planetary-frontier.md).
7. **Automation, strategy and defense (user-directed 2026-10-22; BS1–BS4 implemented, BS5 ore and drills next):** modular structure definitions, robot loot, turrets, shield generators and missile launchers, then mining and farming bases with drones and a per-player command view; first slice is the defendable outpost ([plan](plans/automation-and-defense.md)).
7a. **Fantasy flora (user-directed 2026-10-22):** twelve glowing living-sap species grow wild by biome; FF1 (meshes), FF2 (wild placement) and FF3 (night-gated shader glow with the existing wind sway) are implemented. The FF3 nature benchmark recorded GPU p99 19.057 ms, above the 16.7 ms budget; repeat under an idle display session. Next: FF4 placeable plants, then FF5 four-player measurement and combat-readability review ([plan](plans/fantasy-flora.md)).
7b. **Grow systems (planned, user-directed):** a global season calendar and weather ([weather and seasons](plans/weather-seasons.md)), and a shared-settlement layer of city planning, building, farming, terraforming and mining on ground claims and Arbor shelves ([settlement and building](plans/settlement-building.md)). Both are time-boxed against the MVP gate; the weather plan needs no save change and goes first. Structures are planned as a chunked block grid with styles (castle, dungeon, eco city, farm), prefabs, platformer blocks and heightfield terrain sculpting for all four players ([block building](plans/block-building.md)); it is a separate track from the Detroit loop. BT0 to BT5, the farming part of BT6, BT7 and the creative block mode are done: terrain sculpting (key 6, player 1) and blocks (key 7) in castle, dungeon, eco city and farm styles plus platformer mechanisms (springs, boost strips, crumbling blocks, hazards, checkpoints, plates and gates, movers), with starter prefabs, restyling and copy and paste, that all four players build from their own kits; crops on tilled soil harvest into hay blocks. Building tips, measurements and a hands-on checklist are in the plan; nothing of it has been played by hand yet.
8. **Engine work:** Mach `main` evaluation, then phase 14 skeletal animation when a gameplay need justifies it. Phase 15 (scenes) remains deferred; phase 16 (networking) is not planned because the product is a local desktop four-player game (a later exchange with the sibling web engine is in [interchange](plans/interchange.md)). Gameplay-systems candidates from the Unreal-style feature review (ability core, behavior trees, compiled logic graphs, cinematic tracks, ragdolls) are ordered in [engine features](plans/engine-features.md); the ability core and behavior trees go first (owner decision, 2026-10-15), then compiled logic graphs and cinematic tracks.

Landscape authoring has an isolated foundation and awaits runtime integration. Open decisions and follow-ups:

- **Mach:** update or fork it for indirect draws, shader atomics, timestamp queries, and texture-to-buffer copies (phase 12). The plan is to evaluate the current Mach `main` on a branch before phase 14 ([alignment](plans/alignment.md#mach-tracking)).
- **Economy:** whether building should cost resources (phase 9 markets are additive today).
- **Mod API 2:** host imports, mod-defined genomes, shrines and wares, and saved script state (phase 11).
- **Content and design:** destination, encounter, and faction art direction beyond the current character and environment pass.

Lighting (the cel pipeline, shadows through the canopy, clustered lumen lights, postprocessing) should develop alongside measurable scenes, serving the painterly direction rather than physically based realism. Long-term research remains World Genome, civilization archaeology, Machine DNA, procedural graph compilation, and solver-verified dungeons. None is represented as implemented by this bootstrap.

## Mobility, interiors and input follow-up — 2026-10-05

Free-flight traversal now shares character collision queries with walking, including terrain and rigid-body floors/ceilings. Oriented vehicle boxes now run SAT contacts against one another in addition to terrain, meshes and axis-aligned bodies. Controller setup has an in-game remapping screen, saved settings, device discovery labels, analog trigger tuning, generic macOS HID discovery, native preset file pickers, and eight portable JSON preset slots. Windows/Linux backends and OS-hidden vendor interfaces remain open work; website hosting for the exported JSON remains separate.

`procedural/Interiors.zig` establishes connected room-module graphs for residences, shops, factories, enemy bases and dungeons. Those maps are deterministic and tested, but still need room mesh/collider construction, building entry/exit transitions, streaming, doors, minimap presentation, AI and loot population. Use the smallest interior slice needed to complete the first city's investigation and liberation loop; the larger ocean-city interior remains later content described in [Ocean cities](plans/ocean-cities.md).

## Multi-world arena campaign — design foundation — 2026-10-05

`procedural/Worlds.zig` defines three campaign destinations, 21 city-region records (eleven for the Frontier and five each for Hive and Gaia), one capital per world, bounded four-player arena concepts, reward budgets, Gaia's Earth-scale/shell metadata, and independent deterministic world/arena seeds. The two ocean-city records are design metadata only. The Hive Homeworld records the Scalarians as its ancient founders; the Obsidian Coil is the final-boss capital. `vehicle/ScalariMeshes.zig` provides three fighter and two mothership shell/glow meshes, registered under stable generated asset GUIDs. `docs/plans/planetary-frontier.md` sets the cooperative combat/extraction loop, city route, modular ship-design path, real-time outpost strategy, save boundaries, and delivery gates. City/world data and Scalari art assets exist, but no new destination, city, or Scalari ship is playable yet.
