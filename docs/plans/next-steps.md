# Next steps

**Goal:** turn the systems built so far into a game loop worth playing end to end, then return to the engine phases that unlock the next tier.

The systems now in place:
- menus, conversations and progression;
- hover cars and the Kestrel fighter;
- the Hive on the ground and in the air;
- fabrication;
- procedural audio.

The later-campaign direction includes the Solar frontier and voluntary Galactic Democratic Compact, anchored by a transforming, winged Kestrel. `procedural/SolarSystem.zig` now records all eight planet destinations, twelve moons, and Scalari mining fronts. The planned travel loop is fast travel between bodies plus local flight and stations; no transition or transforming form is playable yet. See [Solar democracy](solar-democracy.md). The underwater Frontier region is also planned: human pressure-dome and fully submerged cetacean cities, a playable orca-form Tideborn champion, swim traversal, and underwater Hive/Scalari encounters. Pelaglass and Sonorous Reef have stable catalog records, but no ocean terrain, movement, or city is playable. See [Ocean cities](ocean-cities.md). The existing campaign foundations for the Arbor Frontier, Hive/Scalari Homeworld, and Gaia are in [Planetary frontier](planetary-frontier.md).

This plan orders the work. The [roadmap](../roadmap.md) is the canonical feature plan and records what is implemented. Solar, ocean and planetary campaign material below remains a later-content direction; its catalogs and design documents do not move it ahead of the first Earth liberation loop.

## Where things stand

| Area | State |
| --- | --- |
| Exploration and engineering | Arbors, district, shrines, machines, bridges, markets. Mature. |
| Player and co-op | Traversal kit, four-player split screen, guest HUD and weapons. Guests cannot drive, fly, talk or fabricate. |
| GUI and conversations | Title, pause, settings, rebindable keys, customization, shops, three keepers, pedestrians. |
| Vehicles | Three hover cars and the Kestrel, from the procedural vehicle generator. Flying has not been checked by hand. |
| The Hive | Three nests (drones, sentinels, troopers), two Brood carriers with wasp swarms. Difficulty only roughly tuned. |
| Progression | 62 pickups, fabricator (cars, the fighter, suits, armor, ten weapons), suit upgrades, vital cells, story flags. |
| Wildkin and arena | 26 collectible heroes with 78 powers, the Heroes menu, and the Starbowl co-op arena. Untuned by hand. |
| Fighting | Timed saber combos with guard and parry, four energy firearms, Ranger and Synthetic classes with three specials each. Untuned by hand. |
| Audio | Synthesized sounds and loops, positional cues, four volume buses. Nobody has listened to it yet. |
| Planetary campaign | Three world descriptors, seventeen city-region concepts (including two ocean cities), three capitals, nine arena concepts and five Scalari ship assets are authored; world generation, flight/combat integration, ship-blueprint progression, RTS construction and world saves are not integrated. |
| Solar campaign | Eight planet and twelve moon records, Scalari mining fronts, governance hooks, and a voluntary Galactic Democratic Compact are authored; fast travel, local planet/moon flight, stations, transforming Kestrel forms and political interactions remain unimplemented. |
| Engine phases | 1–13 done; 14 (skeletal animation), 15 (scenes), 16 (networking) planned. |

## Known gaps from review

- **Missile lock on a reused slot:** fixed by giving each spawned ground Hive unit a generation number and checking `(slot, generation)` when resolving missile and HUD targets.
- **Reticle capture:** verified in milestone A with a live Kestrel lock; see `-Dshowcase=45` in the capture guide.
- **Frontier frame cost measured:** `tools/benchmark.py --frontier` scripts four local players through ground and air combat, then reports simulation-stage, character-skinning, render CPU, presentation, and audio callback percentiles. The latest recorded M3 Pro run (2026-10-10) reports simulation p95/p99 of 3.57 / 3.99 ms against the 4 ms target and skinning p99 of 0.15 ms. Physics and Hive AI are the largest remaining stages. This is a baseline, not a claim that later content has been profiled.
- **Guests:** they can't pilot, talk, or open the fabricator.
- **Save versioning:** saves are at format v14, which persists per-player loadouts (v13) and combat XP (v14). Formats 12 and 13 migrate with default XP. When a field changes meaning, bump the format and record it in the migration notes.

## Milestones

### A. Play, measure, tune (first)

The game has had no hands-on pass since vehicles and the Hive arrived. Everything after this depends on what that reveals.

1. **Frontier benchmark — refreshed 2026-10-11:** `tools/benchmark.py --frontier --frames 600` flies a scripted Kestrel run past a carrier with wasps up, a ground fight at a nest, and four players. This run passed all benchmark checks on the default pair. Simulation P99 was 3.967 ms against the 4 ms budget; character skinning P99 was 0.129 ms against 3 ms; render CPU P99 was 4.799 ms; audio callback P99 used 1.86% of its real-time budget. Re-run after material changes to simulation, rendering, audio, or content density.
   - **Reports:** frontier route reports simulation stages, character skinning, audio callbacks, render CPU and presentation P50/P95/P99, and active combat counts.
   - **Budgets:** simulation P99 under 4 ms and character skinning P99 under 3 ms in ReleaseFast; renderer under 16.667 ms; audio callback below its real-time budget.
2. **Hand-play checklist (yours):**
   - fly each car and the Kestrel (takeoff, transition, dogfight, landing);
   - fight at a nest with each weapon, the saber combo and guard, and both classes' specials;
   - double-tap dash on ground and in the air, chain all four boosts, then fight the Scalari practice patrol and distant bio-titan; confirm XP, level-up health, and saved per-player progression;
   - play co-op with a controller;
   - listen through every sound.

   Record findings in `docs/validation.md`.
3. **Tuning pass:** set values from the playtest:
   - wasp turn rate and accuracy, carrier flak, and nest spawn timers;
   - weapon damage, recipe costs and pickup counts;
   - car and jet handling.

   Keep the values in one tuning table per module.
4. **Correctness fixes — complete:** generation-checked missile locks with regression coverage, and a repeatable `-Dshowcase=45` capture of the live lock reticle.

Acceptance: the benchmark meets its budgets on the M3 Pro; the playtest checklist is complete with every issue fixed or filed; no known correctness bugs remain open.

### B. Finish the first Earth city liberation loop (MVP gate)

The combat campaign foundation is playable and has an end state, but the world premise requires two connected halves: clear the Hive from the wilds and expose its human allies inside a sanctuary city. Complete that loop in the existing Frontier before making the other planet and ocean catalogs playable.

1. Trace the current save, quest, dialogue, evidence/investigation, nest, carrier, and city interaction paths against the liberation loop. Write down only the concrete missing links before implementation.
2. Connect the city investigation outcome to persistent shared story progress. Keep personal loot, currency, gear, XP, and pet growth in each player's `Kit`.
3. Make the city and wilds objectives discoverable from the in-game quest UI, and make the liberation state survive save/load.
4. Add deterministic coverage for the complete state transition and save round trip, plus a real-game smoke stage that completes or reaches the final gate.

Acceptance: a new save can follow the intended city/wilds objectives, expose the alliance, defeat the local Hive force, and reach a clear liberation outcome; shared story state and personal rewards retain their ownership rules. Record any remaining hands-on-only checks in validation.

### C. Air war depth

1. **Collisions — complete:** the Kestrel collides with wasps and carrier hull spheres; ramming damages both sides and resolves aircraft penetration. Wasps steer apart at close range. Regression tests and a Metal smoke are recorded in validation.
2. **Carrier assault — complete:**
   - Destroying its four flak turrets exposes the bays.
   - Destroying the bays opens the core.
   - Each stage shows on the HUD, and the carrier falls in a scripted crash with debris.
3. **Hive wing variety — complete:** dragonfly interceptors (fast, fragile, missile-dodging) and beetle bombers that raid the market plazas, which rangers on foot and in the air defend. Ground and air weapons can shoot them; three successful bomb drops drain the plaza's stock until dawn, while destroying the bomber defends the market.
4. **Kestrel progression — complete:** fabricator upgrades (armor, a bigger missile rack, engine, gun cooling), selectable paint schemes in the Aircraft tab, and marked landing pads on all three tower roofs. Upgrade levels persist and change hull capacity, thrust, missile capacity and gun cooling.

Acceptance: tests for collisions and assault stages; a bomber raid can be won and lost; upgrades change the flight model measurably in tests.

### D. The Hive as a campaign

1. **Corruption — complete:** living surface nests stain a bounded area that expands each market day; destroyed nests stop spreading. Up to three combat spires seed at the advancing edge on later market days. Their parent links and destruction state survive saves, and a saved first-spread beat announces the campaign.
2. **Story beats and quest log — complete:**
   - Tavi's scouting leads to the first nest;
   - Ines warns of the sap the Hive steals;
   - Maro grants the Kestrel blueprint after the first carrier sighting.
   - The pause-menu quest log shows the next objective and the campaign end state triggers when both carriers and every nest fall.
3. **Trooper quality — implemented:** wounded troopers seek nearby blocked positions, close for a guard-aware melee strike, and throw dodgeable grenades. Cover, melee and throw actions drive the existing skinned rig; reusable locomotion clips and the animation asset pipeline remain in phase 14. Manual pacing and readability checks remain in milestone A.

Acceptance: a new save plays from first conversation to the last carrier, with the story flags driving every step and the quest log always showing the next goal.

### E. Co-op completeness

1. **Guests in vehicles:** a second seat in hover cars (gunner with the arsenal) and guests flying their own Kestrel (one per fabricated fighter; fabricate more).
2. **Guests elsewhere:** they can talk with keepers and use the fabricator from their split view (panels sized for quadrants).
3. **Party HUD:** teammates' health and positions on each view's edge.

Acceptance: a four-player run can fabricate, fly and fight with every player active; split-screen panel layouts pass the screen-bounds test at quadrant size.

### F. Engine phases (resume)

1. **Mach `main` evaluation**, then **phase 14, skeletal animation** ([plan](skeletal-animation.md)). It replaces the procedural gait with clips: rangers, keepers, pedestrians and troopers, plus wing-beat and leg clips for the insect ships.
2. **Phase 15, scenes** ([plan](scenes.md)): author nests, carrier circuits, raids and shrines as JSON scenes, so content no longer lives in code.
3. **Phase 16, networking** ([plan](networking.md)): online co-op over the same player and arsenal model as split screen.

### G. Content and polish (continuous)

- **Audio assets:** an `audio` asset kind and streamed music, keeping the synthesized set as the fallback.
- **Art direction:** the first human face, neck, restrained body cues, fitted field-jacket harness, and head-fitted helmet changes are in the [character and environment visual pass](visual-direction.md). The exo rig, hardsuit, and vanguard now use distinct coverage spans, plate profiles, and muted material palettes. Review their closer lineup capture and add front, side, and three-quarter character views; then improve Frontier terrain materials, foliage, roads, and city composition. Broaden to vehicles, Wildkin, Hive units, and Scalari after the anchors pass.
- **Remaining polish:** vehicle and ship materials, nest and carrier silhouettes, HUD style, and cel-shading tuning.
- **Onboarding:** a guided first ten minutes (meet Maro, salvage, fabricate a blaster, first drone).
- **Accessibility:** subtitles for all audio cues, and colorblind-safe pickup and threat colors.

### H. Planetary arena campaign (later content track)

The destination, city, capital and arena catalog is seeded and tested, and the Scalari ship meshes are registered. Build the playable campaign in this order:

1. Convert one existing Frontier Hive basin into a selectable four-player open arena with an objective, stable loot IDs, extraction and per-world save/restore.
2. Add a 3D modular ship design bay: typed attachment sockets, composition validation, a rotatable preview, derived mass/inertia/thrust/handling, fabrication costs and saved blueprints.
3. Add a real-time outpost loop to that arena: command hub, extractor, power, fabricator and defense turret; verify a seeded raid, resource flow, damage/recovery and persistence.
4. Build the first Hive Homeworld arena from the same content/runtime contracts, then add its five connected city regions and Scalari ship flight/combat roles.
5. Build Gaia's human colony arena and geodesic-shell objectives, followed by its five city regions and orbital route.
6. Connect the five Arbor Frontier city regions to the existing hub and surrounding exploration districts, then implement each capital's command-base role.
7. Unlock the final Obsidian Coil siege after the Hive and Gaia story arcs; stage the Scalari Sovereign and Throne Serpent boss fight in the Hive Homeworld capital.

Use local tangent coordinates for each surface arena and stable geodesic face/cell IDs for Gaia's sky enclosure. Ship control, construction, combat and previews remain fully 3D. The detailed [Planetary frontier plan](planetary-frontier.md) owns dimensions, resource roles and acceptance checks.

Acceptance: a four-local-player session completes combat → loot → extraction → ship fabrication → outpost defense and save/reload on the same arena, with a deterministic Debug test and a ReleaseSafe smoke.

## Review of external performance suggestions — 2026-10-11

The pasted search results are prompts to investigate, not project requirements. Apply them against measurements and the existing architecture:

| Suggestion | Project decision |
| --- | --- |
| Add Tracy / `ztracy` immediately | Defer. The current deterministic benchmark reports CPU stage percentiles, presentation intervals, callback cost, and memory/pool counters. First repeat the frontier baseline and use its stage profile to identify an unresolved question. Add a profiler only if the existing data cannot isolate it. GPU execution timing remains unavailable until the pinned Mach path gains timestamp queries. |
| Make `ReleaseFast` the default or production mode | Keep Debug as the default and ReleaseSafe for smoke/validation. ReleaseFast is the measured benchmark mode. Zig documents that Fast disables runtime safety checks; a beta packaging profile should be selected after release testing, not inferred from a performance tip. |
| Put all per-frame data in an arena | Do not generalize this. Hot paths already use fixed-capacity storage; the repository requires explicit allocators and no hidden frame allocations. Keep arenas for bounded request lifetimes where ownership is clear. Audit allocation behavior only when a measured frame path or memory report calls for it. |
| Replace game systems with Mach's ECS/archetypes | No built-in Mach ECS is present in this fork or game architecture. Keep the existing fixed arrays and focused Zig systems; evaluate a data-layout change only against an actual entity iteration bottleneck. |
| Use `extern struct` and alignment for components | Use ABI layout only at an actual C/GPU/file boundary. Native simulation structs should keep normal Zig layout; GPU records already have explicit, reviewed layouts. |
| GPU-cull every scene above a fixed visible-object count | The renderer already groups instanced draws, culls cells on CPU, and has conservative shader-side per-instance frustum culling; 10K/100K/1M scale workloads already exist. The proposed threshold is unsupported. Measure a representative gameplay scene first; consider compute culling only if CPU submission or GPU work is shown to be the limiting stage. |
| Preallocate vertex pools broadly | Existing terrain and instance pools are bounded and instrumented. Keep mesh uploads budgeted; add or resize pools only for a measured residency/upload issue. |
| Move tables to `comptime` for speed | Use compile-time data where it clarifies fixed configuration. Do not treat it as a runtime optimization without evidence. |

Next performance review: refresh the fixed-seed frontier report on a visible, unlocked M3 Pro session, compare CPU stage P95/P99 and presentation intervals, and keep GPU time explicitly marked unavailable. Linux and Windows runtime performance is unmeasured; their existing checks are compile-only.

## Order and sizing

| Order | Milestone | Rough size | Why now |
| --- | --- | --- | --- |
| 1 | A. Play, measure, tune | Small | Refresh the baseline and close hands-on correctness and tuning gaps. |
| 2 | B. First Earth city liberation loop | Medium | Completes the game's stated two-part MVP loop using the existing Frontier. |
| 3 | E. Co-op completeness | Medium | Broader vehicle, fabrication and conversation support makes the full party useful. |
| 4 | G. Content and polish | Continuous | Apply after playtest findings and alongside the MVP work. |
| Later | H. Planetary arena campaign | Large | Builds on the proven combat, rewards, persistence and city loop. |
| Deferred | F. Mach evaluation, then phase 14 | Large | Engine work follows an MVP need or a measured animation requirement. |
| Deferred | F. Phases 15–16 | Large | Scene authoring and networking are outside the current local MVP gate. |

## Risks

- **Frame cost.** CPU skinning (24 characters), many probes, and wasps all scale with content. Mitigation: milestone A's benchmark budgets; GPU skinning (done) removed most of the skinning cost.
- **Tuning without play.** Values are set from tests and captures, not feel. Mitigation: hand-play in milestone A before adding depth.
- **Monolithic modules.** `Sandbox.zig` and `App.zig` keep growing. Mitigation: keep new behavior in focused modules following the existing `Frontier`, `Garage`, `Hangar` and `Skies` pattern. Split older code only when a feature change gives a clear boundary and the move can stay behavior-preserving.
- **Test time.** The catalog allocation-failure test grows with every generated mesh (the suite takes about 2 minutes). Mitigation: cache generated vehicle meshes across that test's iterations, or sample failure points.
