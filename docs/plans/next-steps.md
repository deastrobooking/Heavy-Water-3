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

The table and technical review below record the 2026-10-14 state before the follow-up fixes. The follow-up after the revised steps records the current gate results and completed items.

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
| Nature and forests | Eight L-system tree species (`LSystem.zig`), review showcases 71 to 75, and a nature benchmark. Phase 0 of the [nature plan](nature-upgrade.md) is done; terrain, grass and tree level of detail are not started. Forest geometry is 12.2 million submitted triangles on the benchmark route. |
| Mesh editor | Weld-aware source-linked modifiers, undo and redo, and an incremental in-game bake (M0 to M3 of [mesheditor](mesheditor.md)); one imported character slot, no picking or gizmos yet. |
| Planetary campaign | Three world descriptors, seventeen city-region concepts (including two ocean cities), three capitals, nine arena concepts and five Scalari ship assets are authored; world generation, flight/combat integration, ship-blueprint progression, RTS construction and world saves are not integrated. |
| Solar campaign | Eight planet and twelve moon records, Scalari mining fronts, governance hooks, and a voluntary Galactic Democratic Compact are authored; fast travel, local planet/moon flight, stations, transforming Kestrel forms and political interactions remain unimplemented. |
| Engine phases | 1–13 done; 14 (skeletal animation), 15 (scenes), 16 (networking) planned. |

## Known gaps from review

- **Missile lock on a reused slot:** fixed by giving each spawned ground Hive unit a generation number and checking `(slot, generation)` when resolving missile and HUD targets.
- **Reticle capture:** verified in milestone A with a live Kestrel lock; see `-Dshowcase=45` in the capture guide.
- **Frontier frame cost measured:** `tools/benchmark.py --frontier` scripts four local players through ground and air combat, then reports simulation-stage, character-skinning, render CPU, presentation, and audio callback percentiles. The latest recorded M3 Pro run (2026-10-10) reports simulation p95/p99 of 3.57 / 3.99 ms against the 4 ms target and skinning p99 of 0.15 ms. Physics and Hive AI are the largest remaining stages. This is a baseline, not a claim that later content has been profiled.
- **Guests:** they can't pilot, talk, or open the fabricator.
- **Save versioning:** saves are at format v26. The loader accepts formats 13 and newer; the floor changes only by policy, while content fields with defaults can migrate forward. See R2 in the [technical review](#technical-review--2026-10-14) and the save ownership notes in `architecture.md`.
- **Headless suite:** four tests fail on both compiler channels (435 of 439); see R1.

## Technical review — 2026-10-14

**Scope.** This review compares what the docs claim with what the code and the gates show today, and re-orders the next steps. Everything marked *measured* was run on 2026-10-14 on an Apple M3 Pro, macOS 26.5.1, Metal, ReleaseSafe for the smoke and ReleaseFast for the benchmarks. Items marked *by reading* come from reading code and have not been run.

### Verified state (measured)

| Gate | Default pair (`0.16.0-dev.3142`) | Zig 0.17.0 |
| --- | --- | --- |
| `build check` | pass | pass |
| Headless tests | **435 of 439** (4 fail) | **435 of 439** (the same 4) |
| Metal-validated smoke, 300 frames | complete, 1,858 submitted objects, no validation messages | not run |
| Nature benchmark, 600 frames | pass, all nine checks | not run |
| Frontier benchmark, 600 frames | pass, all checks | not run |
| Linux and Windows cross-compiles | not re-run (last pass 2026-10-10, before the nature and mesh-editor commits) | not re-run |

| Benchmark figure | 2026-10-14 | Budget or previous run |
| --- | --- | --- |
| Frontier simulation p99 | 2.815 ms | budget 4 ms (3.967 ms on 2026-10-11) |
| Frontier character skinning p99 | 0.101 ms | budget 3 ms |
| Frontier render CPU p99 | 4.879 ms | budget 16.667 ms |
| Presentation interval p99 | 20.955 ms frontier, 21.086 ms nature | 20.985 ms on 2026-10-13; this is not a GPU time |
| Nature CPU p50 / p95 / p99 | 1.432 / 2.654 / 2.976 ms | 2.856 ms p99 on 2026-10-13 |
| `Chunk.fill` p50 / p99 | 3.407 / 8.894 ms | 3.045 / 8.150 ms |
| Scatter p50 / p99 | 0.249 / 0.580 ms | 0.228 / 0.583 ms |
| Visible vegetation instances | 551 | 551 |
| **Submitted triangles** | **12,248,988** | **1,855,985** on 2026-10-13 |
| Peak terrain upload per frame | 328,940 bytes | budget 393,216 |
| Audio callback | not measured (the benchmark runs without an audio device) | |

### Findings

| ID | Finding | Evidence |
| --- | --- | --- |
| R1 | **The headless suite is red on both compilers and has been for days.** Four tests fail. Three are stale expectations and one is a real layout limit (table below). Eighteen of the latest twenty validation entries list tests as "not checked" (a text count of the *Not checked* lines), which is how the suite drifted. AGENTS.md and the alignment matrix still said 373 of 373. | measured |
| R2 | **Save compatibility is a rolling window that silently drops old formats.** `Save.decode` accepts formats from `format_version - 12` upward. At format 25 that is 13, so format 12 saves are already rejected, and every future bump drops one more. The docs disagreed with each other and with the code (v14, v17, v24, and "format 12 migrates"); the `Save.zig` header comment still says "v12 saves migrate". | by reading, plus the failing Save test |
| R3 | **Forest geometry grew about 6.6 times with no change in CPU time.** Submitted triangles went from 1.86 million to 12.25 million after the L-system foliage change, with the same 551 visible vegetation instances. CPU p99 and the presentation interval did not move. The larger geometry raises GPU-cost risk, but GPU time is unmeasured, so a GPU bottleneck is not established. I found no distance level of detail for scattered trees in the draw path. | measured, plus by reading |
| R4 | **The MVP gate has no content yet.** The roadmap's milestone B (investigate, expose the alliance, free the city) has story flags and a quest log, but no investigation or alliance content: `conversations.json` has no mention of evidence, alliances, scientists or governments. None of the last 25 commits (2026-10-11 onward) touches an investigation or liberation loop; they cover Detroit and the Rootways, wilds and cave content, character work, the mesh import and editor, and nature and trees, which are mostly user-directed visual and tooling tracks. | by reading |
| R5 | **The Character Designer has outgrown one panel.** `Profile.Field` has 35 entries (body style, armor RGB studio and cel style were added). At 720p the panel shows a scrolling 25-row window. | measured (the failing Screens test) |
| R6 | **Three tree generators now coexist.** Arbors use space colonization (`Arbor.zig`), the streamed forest uses L-system grammars (`LSystem.zig`), and the nature plan proposes a shared skeleton (Phase 5a). Arbor integration of the grammar needs attachment and save-compatibility review (`Arbor.generator_version`). | by reading, plus validation notes |
| R7 | **Hands-on checklist (milestone A) is still open.** No playtest results are recorded in `validation.md`. The benchmark baselines are refreshed above, but the flight, combat, controller, co-op and audio checks have not been done. | by reading |
| R8 | **Zig 0.17 adoption is still pending**, with the same bar as before: benchmarks, any Linux or Windows run, smoke on 0.17 and the adoption change. | by reading, plus the gates above |
| R9 | **Doc drift** in test counts, save versions, showcase and option lists, five broken anchors, and missing architecture coverage of the L-system forest and the mesh-editor bake. Fixed in this change (list below). | measured (link check) |

#### The four failing tests (R1, R5)

| Test | Failure | Cause | Fix |
| --- | --- | --- | --- |
| `asset.Catalog`: deferred meshes reserve handles at load and install once, later | expected 5, found 6 | `captain_test` became a deferred catalog mesh (commit `77651ae`); the expectation was not updated | derive the expected count from the pending list, or expect 6 |
| `game.Save`: save documents round-trip and reject mismatched or malformed input | `UnsupportedSaveFormat` for a format 12 document | the loader accepts 13 and newer (R2); the test still builds a format 12 save | settle the policy in step 1, then build the legacy fixture at the oldest supported format |
| `game.Creator`: creator edits a draft, requires a name… | height 1.0, expected 1.02 | `body_style` became the third `Profile.Field`, so five `down` presses now land on face style, not height | select `.height` directly (`c.field = .height`) instead of counting presses (by reading; not yet run) |
| `ui.Screens`: every screen lays out inside the window and records hits | 25 rows, expected 35 | the Designer panel scrolls a 25-row window at 720p, and the test asserts every field has a row | split the Designer into tabs; test each tab's visible rows and hit targets, and confirm every field is reachable across tabs |

### Revised next steps

Order is by what unblocks the rest. Sizes: S under a day, M a few days, L about a week.

| Order | Step | Size | Acceptance |
| --- | --- | --- | --- |
| 0 | **Complete — restore a green suite** (R1): fixed the three stale tests; the Screens test follows the tabbed contract in step 5. Added the one-command gate (`check`, `test`, then the smoke), which prints and requires green counts. | S | **Met:** 440 of 440 on default and 0.17; gate result recorded in validation |
| 1 | **Complete — explicit save-compatibility policy** (R2): `Save.min_supported_format` replaces the rolling `format_version - 12` window; checked-in fixture saves cover each supported format; the stale comment and architecture text are corrected. | S to M | **Met:** formats 13–25 each round-trip; future floor changes are deliberate and documented |
| 1b | **Ability core (E1) and behavior trees (E2)** from [engine features](engine-features.md), the owner's first priority (2026-10-15): per-player loot affixes on a tag, attribute and effect core, and reactive enemy trees. They serve the hack-and-slash loop. | M each | the acceptance in each phase |
| 2 | **Bound the forest's cost** (R3): add distance level of detail ([nature plan](nature-upgrade.md) phases 5d and 5f), then tune the triangle budget against the measured GPU time. Hold further crown detail until then. | M | nature-route GPU p99 under 16.7 ms on the recorded M3 Pro baseline; triangle count and LOD budgets recorded |
| 3 | **Milestone A hands-on pass** with the refreshed baselines above. | S | the checklist below is complete and findings are fixed or filed |
| 4 | **Milestone B: the investigation content slice** (R4). First deliverable is a short content spec for the first city's budget of three sub-missions, one boss battle and ten item discoveries: evidence items, the collaborator conversations, the flags and the quest-log entries, with the save ownership rules. Then build it. | M | the existing acceptance for milestone B |
| 5 | **Complete — split the Character Designer into tabs** (R5): Basics, Hair, Gear, Armor RGB and Style. | S to M | **Met:** every field is reachable across tabs at 720p and 640×480; the Screens test checks tab hits, row bounds and reachability |
| 6 | **Reconcile tree generators** (R6) before more tree work: one skeleton contract, an explicit decision on `Arbor.generator_version`, and the save migration choice already listed in the nature plan. | M | one documented contract; migration test if Arbors change |
| 7 | **Parallel tracks, user-directed:** the [nature plan](nature-upgrade.md) (grass is its next visible win), the mesh editor's M4 library ([mesheditor](mesheditor.md)), the specialized asset studios ([asset studio](asset-studio.md)), weather and seasons ([plan](weather-seasons.md)) and the shared settlement system for city planning, building, farming, terraforming and mining ([plan](settlement-building.md)), the remaining gameplay-systems phases in [engine features](engine-features.md), and the Zig 0.17 adoption change (a separate small change once the matrix is complete). After step 2 bounds forest cost, cap nature polish and mesh-editor work at one day per week combined until the investigation slice is playable; keep the Zig migration separate. | | per each plan |

### Doc alignment done in this change

- `AGENTS.md` and `alignment.md`: test counts and the 0.17 gate re-measured; the dated results are in the Mach tracking section.
- `architecture.md`: save format and supported window corrected; the L-system forest and the mesh-editor bake described.
- `building-and-testing.md`: showcases 71 to 75, the `modifier-bench` step, `-Dnature-benchmark`, `-Dbenchmark-frontier` and the `--nature` benchmark documented.
- `roadmap.md`: the Next list now starts with the green-suite and save-policy work.
- Five broken anchors fixed (`project-overview.md`, `visual-direction.md`).
- `validation.md`: a dated entry with the commands and what was not run.
- At the time of the review, source code was unchanged; the follow-up below records the later implementation.

### Follow-up — green suite and save floor — 2026-10-14

- Fixed the deferred Catalog count, selected Creator test fields directly instead of relying on enum order, and split the Character Designer into five clickable tabs. Field traversal remains continuous; each tab shows its own fields. The layout test checks every field at 720p and 640×480.
- Added `Save.min_supported_format = 13`, removed the implied format-12 migration expectation, and added checked-in fixtures for each supported format from 13 through 25. Every fixture decodes and round-trips; format 12 and future formats are rejected.
- Added `python3 tools/validation_gate.py`. It runs default check/tests and the 300-frame Metal smoke, then Zig 0.17 check/tests. It uses a temporary cache for the test runs so cached results cannot hide their counts.
- **Checked:** the gate passed on Apple M3 Pro / macOS 26.5.1 / Metal: default and Zig 0.17 **440/440**, default Metal smoke complete with no validation messages. A ReleaseSafe Character Designer capture was visually inspected after the tab change.
- **Not checked:** Zig 0.17 smoke, Linux/Windows builds or runtime, GPU frame time, or hands-on tab clicking. The smoke drives the existing scripted paths; tab reachability is covered by the layout test. Next: measure forest GPU cost and add distance LOD.

### Follow-up — forest GPU timing — 2026-10-14

- The Metal HUD attempt initialized but emitted no timing samples, and `xcrun xctrace` is unavailable with the installed Command Line Tools. Added a Metal queue measurement using `MTLCommandBuffer.GPUStartTime` and `GPUEndTime` after command-buffer completion; other backends return no sample and per-pass timing remains unavailable.
- Four 600-frame nature benchmark runs passed all checks, including the new Metal GPU timing collection gate. Median run-level GPU p50/p95/p99 were **12.199/17.969/19.729 ms** (596–598 samples per run); GPU p99 ranged **19.354–20.009 ms**. Median CPU p99 was **2.914 ms**, median presentation p99 **21.017 ms**, and each run submitted **12,248,988** triangles. The GPU p99 exceeds the 16.7 ms target; next implement and measure tree LOD against this fixed route.

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

The combat campaign foundation is playable and has an end state, but the world premise requires two connected halves: clear the Hive from the wilds and expose its human allies inside a Hive-occupied city. Complete that loop in the existing Frontier before making the other planet and ocean catalogs playable.

1. **Audit complete, 2026-10-21:** see [Detroit liberation loop audit](../validation.md#detroit-liberation-loop-audit--2026-10-21). The audit found no runtime evidence collection, exposure, boss completion or liberation path; shared flags already save with the world.
2. **Foundry Ledger fight/reward slice implemented, 2026-10-21:** Maro starts the case, three generated industrial checkpoints are recovered through normal hands targeting, and the quest log shows the page count. Maro's report sets shared `foundry_reported`; the targetable loading-dock console starts the steward and two-guard fight. Defeating the group sets `foundry_exposed`, opens a visible non-colliding gate, and grants Sprint Servos +1 to each active player's private `Kit`. Deterministic progression/save tests and the scripted combat smoke cover the path. The case remains draft content.
3. **Windsor Gate evidence and crossing stops implemented, 2026-10-21:** Ines starts the case; two bridge logs and one Gothic hall recording use normal aim/interact targeting and shared flags. Returning the full set exposes the councillor and opens both visual gates. The two safe Detroit-bank fast-travel stops are visible but disabled until exposure. Focused tests cover clue progression, report gating, map unlocks and arrivals; the full scripted smoke now visits both stops under Metal validation. Night is part of the dialogue, not a hard time-of-day condition.
4. **Bile Archive investigation implemented, 2026-10-21:** Tavi starts the Belle Isle case; three trace pickups reveal the seeded relay sequence, the archive opens through three controls, and reading/reporting the notes exposes the science ally. The report grants 60 pet XP to the active pet in each present player's `Kit`. The full scripted smoke collects clues, opens the archive, reports the notes, and checks two-player reward ownership under Metal validation.
5. **Titan and liberation path implemented, 2026-10-21:** after all three reports and a cleared Frontier, the west Windsor bridge wakes the existing Scalari Titan. One reinforcement wave and an exposed-core phase are driven by health thresholds. Defeating the full group awards each present player's `Kit`; shared progress marks Detroit free if the Frontier is still clear. Save/load restarts a live fight at phase one. The encounter has headless integration coverage and a scripted smoke path.
6. **Complete Detroit's content budget — discoveries implemented, 2026-10-21:** ten seeded landmark pickups now award per-ranger upgrades, armor, a companion, or transit scrap, while three shared keepsakes set team story flags. Personal claims live in each Kit and save at format 26. The boss does not require these optional finds. The existing method names describe their intended routes; this first pickup pass does not add a separate minigame for each method. The four-seat smoke verifies every personal reward, each shared flag and save/load. Add further visible city liberation dressing and improve the bridge arena's sightlines; showcase 97 shows nearby towers and canopy partly hide the Titan and ally pylons. Hands-on combat remains open.
7. **Scripted discovery coverage complete, 2026-10-21:** the Metal smoke aims at all ten locations with all four seats, checks each personal reward and shared flag, and round-trips the claims through save/load. Nearby marker props follow any present player. Still required before the milestone A sign-off: hands-on route visibility, controller interaction, co-op play and the combat checks listed there.

Content budget per city (owner, 2026-10-15): three sub-missions, one boss battle and ten item discoveries. Detroit's draft content and the build phases are in [city content](city-content.md).

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
3. **Phase 16, networking** ([plan](networking.md)): not planned (local desktop product, 2026-10-15). A later player and asset exchange with the sibling web engine is in [interchange](interchange.md).

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

Next performance review: refresh the fixed-seed frontier report on a visible, unlocked M3 Pro session, compare CPU stage P95/P99, presentation intervals and whole-command-buffer GPU time. Linux and Windows runtime performance is unmeasured; their existing checks are compile-only.

## Order and sizing

| Order | Milestone | Rough size | Why now |
| --- | --- | --- | --- |
| 0 | Technical review steps 0 and 1: green suite, save policy | Small | Four tests fail and old saves are dropped silently; every later gate depends on a trustworthy suite. |
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
