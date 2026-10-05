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
| Progression | 62 pickups, fabricator (cars, the fighter, suits, armor, ten weapons), suit upgrades, vital cells, story flags. |
| Fighting | Timed saber combos with guard and parry, four energy firearms, Ranger and Synthetic classes with three specials each. Untuned by hand. |
| Audio | Synthesized sounds and loops, positional cues, four volume buses. Nobody has listened to it yet. |
| Engine phases | 1–13 done; 14 (skeletal animation), 15 (scenes), 16 (networking) planned. |

## Known gaps from review

- **Missile lock on a reused slot:** fixed by giving each spawned ground Hive unit a generation number and checking `(slot, generation)` when resolving missile and HUD targets.
- **Reticle capture:** verified in milestone A with a live Kestrel lock; see `-Dshowcase=45` in the capture guide.
- **Frontier frame cost measured:** `tools/benchmark.py --frontier` scripts four local players through ground and air combat, then reports simulation-stage, character-skinning, render CPU, presentation, and audio callback percentiles. The M3 Pro ReleaseFast run meets render, skinning, and audio budgets; simulation P99 improved from 7.11 ms to 6.72 ms but still exceeds its 4 ms target. Projectile terrain raycasts are optimized; the next profile pass should target remaining wasp and Hive AI spikes.
- **Guests:** they can't pilot, talk, or open the fabricator.
- **Save versioning:** saves are at format v12, which persists the seeded sprint course's best lap. When a field changes meaning, bump the format and record it in the migration notes.

## Milestones

### A. Play, measure, tune (first)

The game has had no hands-on pass since vehicles and the Hive arrived. Everything after this depends on what that reveals.

1. **Frontier benchmark:** `tools/benchmark.py --frontier` flies a scripted Kestrel run past a carrier with wasps up, a ground fight at a nest, and four players.
   - **Reports:** frontier route reports simulation stages, character skinning, audio callbacks, render CPU and presentation P50/P95/P99, and active combat counts.
   - **Budgets:** simulation P99 under 4 ms and character skinning P99 under 3 ms in ReleaseFast; renderer under 16.667 ms; audio callback below its real-time budget.
2. **Hand-play checklist (yours):**
   - fly each car and the Kestrel (takeoff, transition, dogfight, landing);
   - fight at a nest with each weapon, the saber combo and guard, and both classes' specials;
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

### B. Air war depth

1. **Collisions — complete:** the Kestrel collides with wasps and carrier hull spheres; ramming damages both sides and resolves aircraft penetration. Wasps steer apart at close range. Regression tests and a Metal smoke are recorded in validation.
2. **Carrier assault — complete:**
   - Destroying its four flak turrets exposes the bays.
   - Destroying the bays opens the core.
   - Each stage shows on the HUD, and the carrier falls in a scripted crash with debris.
3. **Hive wing variety — complete:** dragonfly interceptors (fast, fragile, missile-dodging) and beetle bombers that raid the market plazas, which rangers on foot and in the air defend. Ground and air weapons can shoot them; three successful bomb drops drain the plaza's stock until dawn, while destroying the bomber defends the market.
4. **Kestrel progression — complete:** fabricator upgrades (armor, a bigger missile rack, engine, gun cooling), selectable paint schemes in the Aircraft tab, and marked landing pads on all three tower roofs. Upgrade levels persist and change hull capacity, thrust, missile capacity and gun cooling.

Acceptance: tests for collisions and assault stages; a bomber raid can be won and lost; upgrades change the flight model measurably in tests.

### C. The Hive as a campaign

1. **Corruption — complete:** living surface nests stain a bounded area that expands each market day; destroyed nests stop spreading. Up to three combat spires seed at the advancing edge on later market days. Their parent links and destruction state survive saves, and a saved first-spread beat announces the campaign.
2. **Story beats and quest log — complete:**
   - Tavi's scouting leads to the first nest;
   - Ines warns of the sap the Hive steals;
   - Maro grants the Kestrel blueprint after the first carrier sighting.
   - The pause-menu quest log shows the next objective and the campaign end state triggers when both carriers and every nest fall.
3. **Trooper quality — implemented:** wounded troopers seek nearby blocked positions, close for a guard-aware melee strike, and throw dodgeable grenades. Cover, melee and throw actions drive the existing skinned rig; reusable locomotion clips and the animation asset pipeline remain in phase 14. Manual pacing and readability checks remain in milestone A.

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
