# Next steps

**Goal:** turn the systems built so far into a game loop worth playing end to end, then return to the engine phases that unlock the next tier.

The systems now in place:
- menus, conversations and progression;
- hover cars and the Kestrel fighter;
- the Hive on the ground and in the air;
- fabrication;
- procedural audio.

This plan orders the work. The [roadmap](../roadmap.md) stays the record of what is implemented.

## Where things stand

| Area | State |
| --- | --- |
| Exploration and engineering | Arbors, district, shrines, machines, bridges, markets. Mature. |
| Player and co-op | Traversal kit, four-player split screen, guest HUD and weapons. Guests cannot drive, fly, talk or fabricate. |
| GUI and conversations | Title, pause, settings, rebindable keys, customization, shops, three keepers, pedestrians. |
| Vehicles | Three hover cars and the Kestrel, from the procedural vehicle generator. Flying has not been checked by hand. |
| The Hive | Three nests (drones, sentinels, troopers), two Brood carriers with wasp swarms. Difficulty only roughly tuned. |
| Progression | 62 pickups, fabricator (cars, the fighter, suits, armor, weapons), suit upgrades, vital cells, story flags. |
| Audio | Synthesized sounds and loops, positional cues, four volume buses. Nobody has listened to it yet. |
| Engine phases | 1–13 done; 14 (skeletal animation), 15 (scenes), 16 (networking) planned. |

## Known gaps from review

- **Missile lock on a reused slot:** a missile locked on a ground Hive unit tracks the unit's slot index. If the unit dies and the slot is reused, the missile homes on the newcomer. Give units a generation number and lock by (slot, generation).
- **No ship collisions:** the Kestrel passes through wasps and carriers, and wasps pass through each other.
- **Reticle side unconfirmed:** confirm the HUD lock reticle's side with a capture during a live lock.
- **Frame cost unmeasured:** no measurement of frame cost under full frontier load (12+ wasps, 2 carriers, 6 troopers, 4 players, CPU skinning of up to 24 characters).
- **Guests:** they can't pilot, talk, or open the fabricator.
- **Save versioning:** saves grew through optional fields under format v11. When a field changes meaning, bump the format and say so in the migration notes.

## Milestones

### A. Play, measure, tune (first)

The game has had no hands-on pass since vehicles and the Hive arrived. Everything after this depends on what that reveals.

1. **Frontier benchmark:** `tools/benchmark.py --frontier` flies a scripted Kestrel run past a carrier with wasps up, a ground fight at a nest, and four players.
   - **Reports:** render CPU P50/P95/P99, simulation step time, skinning time, and audio-thread load.
   - **Budgets:** the simulation step under 4 ms and skinning under 3 ms in ReleaseFast.
2. **Hand-play checklist (yours):**
   - fly each car and the Kestrel (takeoff, transition, dogfight, landing);
   - fight at a nest with each weapon;
   - play co-op with a controller;
   - listen through every sound.

   Record findings in `docs/validation.md`.
3. **Tuning pass:** set values from the playtest:
   - wasp turn rate and accuracy, carrier flak, and nest spawn timers;
   - weapon damage, recipe costs and pickup counts;
   - car and jet handling.

   Keep the values in one tuning table per module.
4. **Correctness fixes:** generation-checked missile locks, and a capture test for the lock reticle.

Acceptance: the benchmark meets its budgets on the M3 Pro; the playtest checklist is complete with every issue fixed or filed; no known correctness bugs remain open.

### B. Air war depth

1. **Collisions:** the Kestrel against wasps and carriers (hull spheres; ramming damages both), and wasps keep apart (separation steering).
2. **Carrier assault:**
   - Destroying its four flak turrets exposes the bays.
   - Destroying the bays opens the core.
   - Each stage shows on the HUD, and the carrier falls in a scripted crash with debris.
3. **Hive wing variety:** dragonfly interceptors (fast, fragile, missile-dodging) and beetle bombers that raid the market plazas, which rangers on foot and in the air defend.
4. **Kestrel progression:** fabricator upgrades (armor, a bigger missile rack, engine, gun cooling) and paint schemes in customization, plus landing pads on tower roofs.

Acceptance: tests for collisions and assault stages; a bomber raid can be won and lost; upgrades change the flight model measurably in tests.

### C. The Hive as a campaign

1. **Corruption:** an unbroken nest spreads tinted corruption across the terrain over market days, and new nests seed at its edge (bounded).
2. **Story beats** through conversation flags:
   - Tavi's scouting leads to the first nest;
   - Ines warns of the sap the Hive steals;
   - Maro builds the Kestrel blueprint after the first carrier sighting.

   Then an end state when both carriers and all nests fall, and a quest log in the pause menu.
3. **Trooper quality:** cover-seeking, melee at close range, and grenades. They need proper animation (phase 14).

Acceptance: a new save plays from first conversation to the last carrier, with the story flags driving every step and the quest log always showing the next goal.

### D. Co-op completeness

1. **Guests in vehicles:** a second seat in hover cars (gunner with the arsenal) and guests flying their own Kestrel (one per fabricated fighter; fabricate more).
2. **Guests elsewhere:** they can talk with keepers and use the fabricator from their split view (panels sized for quadrants).
3. **Party HUD:** teammates' health and positions on each view's edge.

Acceptance: a four-player run can fabricate, fly and fight with every player active; split-screen panel layouts pass the screen-bounds test at quadrant size.

### E. Engine phases (resume)

1. **Mach `main` evaluation**, then **phase 14, skeletal animation** ([plan](skeletal-animation.md)). It replaces the procedural gait with clips: rangers, keepers, pedestrians and troopers, plus wing-beat and leg clips for the insect ships.
2. **Phase 15, scenes** ([plan](scenes.md)): author nests, carrier circuits, raids and shrines as JSON scenes, so content no longer lives in code.
3. **Phase 16, networking** ([plan](networking.md)): online co-op over the same player and arsenal model as split screen.

### F. Content and polish (continuous)

- **Audio assets:** an `audio` asset kind and streamed music, keeping the synthesized set as the fallback.
- **Art-direction pass:** vehicle and ship materials, nest and carrier silhouettes, the HUD style, and cel-shading tuning.
- **Onboarding:** a guided first ten minutes (meet Maro, salvage, fabricate a blaster, first drone).
- **Accessibility:** subtitles for all audio cues, and colorblind-safe pickup and threat colors.

## Order and sizing

| Order | Milestone | Rough size | Why now |
| --- | --- | --- | --- |
| 1 | A. Play, measure, tune | Small | Everything else depends on what playing reveals; frame budgets guard the rest. |
| 2 | B. Air war depth (collisions, assault) | Medium | The newest system has the most obvious gaps. |
| 3 | C. Hive campaign | Medium–large | Turns the systems into a game with a goal. |
| 4 | E. Mach evaluation, then phase 14 | Large | Troopers and ships need animation; it is the next engine unlock. |
| 5 | D. Co-op completeness | Medium | Best done after vehicles and panels settle. |
| 6 | E. Phases 15–16 | Large | Content authoring and online play build on all of the above. |
| — | F. Content and polish | Continuous | Alongside every milestone. |

## Risks

- **Frame cost.** CPU skinning (24 characters), many probes, and wasps all scale with content. Mitigation: milestone A's benchmark budgets, and GPU skinning in phase 14.
- **Tuning without play.** Values are set from tests and captures, not feel. Mitigation: hand-play in milestone A before adding depth.
- **Monolithic modules.** `Sandbox.zig` (about 3,300 lines) and `App.zig` (about 1,400) keep growing. Mitigation: continue the `Frontier`, `Garage`, `Hangar` and `Skies` pattern, and move showcase and smoke code out of `App.zig` into `game/Showcase.zig` in milestone A.
- **Test time.** The catalog allocation-failure test grows with every generated mesh (the suite takes about 2 minutes). Mitigation: cache generated vehicle meshes across that test's iterations, or sample failure points.
