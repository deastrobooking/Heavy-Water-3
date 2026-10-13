# Local validation

Host: Apple M3 Pro, macOS 26.5.1, Metal. Compiler and Mach revision are pinned in `build.zig.zon`.

## Smooth GPU-drawn character eyes — 2026-10-12

- Moved eye whites, irises, pupils, highlights and upper eyelid ink from coarse head-vertex color interpolation to SDF drawing in the GPU-skinned character fragment shader. Eye geometry and both iris colors travel with each character's skinned vertices, so the existing eye customization is retained. Brows, nose and mouth remain baked face marks.
- **Checked:** `python3 tools/zig.py build check` passed. A ReleaseSafe close-up capture (`-Dcharacter-showcase=3 -Dcharacter-view=4 -Dcapture-frame=120`, Metal API Validation enabled) completed on Apple M3 Pro without Metal validation messages; `zig-out/eyes-review.png` was inspected and shows smooth iris boundaries and highlights.
- **Not checked:** headless tests, hands-on creator/gameplay review, CPU-skinned custom characters, Zig 0.17, Linux/Windows builds or runtime, and performance benchmarks. Mach's current WGSL compiler rejects derivative built-ins here, so smoothing uses a fixed UV-space edge band rather than screen-scaled derivatives.

## Detroit Riverfront, Belle Isle, and Windsor crossings — 2026-10-12

- Widened only Detroit's lane-zero river reach, fading it back to the regular channel beyond the city; terrain remains above water across Belle Isle and the streamed water ribbon splits around the island.
- Added an industrial promenade and ferry pavilion, park paths/fixtures on Belle Isle, two static road bridges toward Windsor, and two pedestrian approach spans linking the island to both banks. They share the district mesh/collider, while existing player-built bridge anchors and IDs remain unchanged.
- Bumped district generator to v7 and save format to v23. District generator 3–6 saves migrate with their plaza and player bridge identities retained.
- Added hydrology regression coverage for broad Detroit water, dry island terrain, and the narrow channel outside Detroit.
- Increased the terrain upload budget default to 384 KiB (minimum 322 KiB) to fit the split river-water buffers.
- **Checked:** `python3 tools/zig.py build -Doptimize=ReleaseFast` passed with the default pinned compiler and installed `zig-out/bin/heavy-water`; `git diff --check` passed.
- **Not checked:** headless tests, Metal capture or visual inspection, walking/driving the spans, vehicle clearance, save migration round-trip, benchmarks, Zig 0.17, Linux/Windows compilation or runtime. River width, bank approaches, and bridge height need in-game review.

## Detroit Arbor Reach and native pines — 2026-10-12

- Named the first city Detroit, Michigan, and show Detroit / Arbor Reach on the world map. The procedural skyline now mixes modern canopy towers, warm-windowed Gothic civic spires, and broad industrial factories with flues, service piping, hazard lamps, and transfer gantries; the industrial belt is a deliberate Hive foothold.
- Added a smaller layered pine mesh, scaled to 6–18 m and seeded through lower-arid forest and parkland scatter. Existing giant tree forms remain unchanged.
- Bumped the district generator to v6, scatter/world generator to v9, and save format to v22. District-generator-3 through -5 and scatter-generator-5 through -8 saves migrate while preserving plaza, bridge, and collected-object identities.
- **Checked:** `git diff --check` only.
- **Not checked:** build, tests, Metal capture or visual inspection, seed coverage for city silhouettes, hands-on routes, save migration round-trip, benchmarks, Zig 0.17, Linux/Windows compilation or runtime. Gothic/factory composition and pine scale need in-game review.

## Rootdeep shrine presentation and campaign beacon — 2026-10-12

- Replaced the stepped exterior shrine crowns and monumental piers with open rootwork arches, dark stone thresholds, inset lumen channels, and suspended ember/teal crystal crowns. Puzzle interiors, collision, solver, rewards, and saves are unchanged.
- Restored an outdoor sky beacon for the active campaign destination. It appears within 1,250 m and hides at close approach (34 m), and advances through Tavi, the first surface spire, Ines, a Brood carrier, Maro/the fabricator, remaining nests, and remaining carriers.
- **Checked:** `git diff --check` only.
- **Not checked:** build, tests, Metal capture or visual inspection, hands-on objective progression, benchmark, Zig 0.17, Linux/Windows compilation or runtime. The beacon and shrine silhouette need review in-game.

## Steampunk Arbor Rootways — 2026-10-12

- Added a reusable covered approach at each of the two outer Arbor ring plazas. Riveted bronze ribs and portal frames enclose the pedestrian/road path, paired metro rails pass through the crown, and five inset colored gems per side are published with night-responsive emission.
- Kept tree and plaza geometry intact: the gallery reaches the root-ring approach and frames its portal; it does not cut a physical opening through the living trunk.
- Bumped district generator version to 5 and save format to 21. District-generator-3 and -4 saves migrate with stable bridge endpoints.
- **Checked:** default `python3 tools/zig.py build check`, ReleaseSafe Metal capture `MTL_DEBUG_LAYER=1 ... build run -Dshowcase=64 -Dcapture-frame=120`, and `git diff --check` passed. `zig-out/rootway-review.png` was inspected; the rail and amber ceiling lights read through the gallery and the three gem hues are visible along both walls. Metal API Validation reported no errors.
- **Not checked:** headless tests, hands-on gallery traversal, Zig 0.17, Linux/Windows builds or runtime.

## Rootway gallery clearance cleanup — 2026-10-12

- Corrected gallery rib dimensions: the cross-section rotation follows each arch segment's local Y axis, so its length now belongs on Y. Previously the corridor-length Z dimension made each arch segment span the full gallery and stack across neighboring ribs, cluttering the walkable road. Opened the portal arch to 16.8 m wide and 11 m high, above the road and elevated rail clearance.
- The fixed geometry feeds both the resident city render mesh and static collider. Bumped the district generator to v8 and save format to 24; district-generator-3 through -7 saves migrate without changing bridge anchors or removals.
- **Checked:** `python3 tools/zig.py build check`, ReleaseSafe Metal capture `MTL_DEBUG_LAYER=1 ... build run -Dshowcase=64 -Dcapture-frame=120 -Daudio=false`, and `git diff --check` passed on Apple M3 Pro. The new `zig-out/rootway-v8-review.png` capture was inspected: the route stays clear and ribs now read as separate arches rather than stacked slabs. Metal API Validation reported no errors.
- **Not checked:** headless tests, hands-on traversal and Linux/Windows runtime.

## Canopy metro first slice — 2026-10-12

- Added `procedural/Metro.zig`: paired elevated guide rails and ties over the six plaza roads, outboard supports, and boarding platforms at the three market towers. These reuse the district's render/collision piece pipeline; station decks are walkable.
- Added South, North and West Line destinations to the per-player world map and fast-travel flow. Station arrivals use a nearby clear platform point. The UI map shows all six current destinations and party markers.
- Bumped district generator version to 4 and save format to 20; generator-3 worlds migrate while preserving their saved bridges. Scatter generator 8 and its generator-5 through -7 save migrations remain supported.
- **Checked:** default `python3 tools/zig.py build check`, `python3 tools/zig.py build -Doptimize=ReleaseFast`, and `git diff --check` passed; the installed executable was refreshed. ReleaseSafe captures `-Dshowcase=8` and `-Dshowcase=55` completed on Apple M3 Pro with Metal API Validation enabled and no reported errors; `zig-out/metro-city-review.png` and `zig-out/metro-map-review.png` were inspected.
- **Not checked:** headless tests, manual station arrival/reachability, rail traversal, moving train behavior, downtown/suburb/farm generation, subway/venue interiors, high-speed intercity rail, spaceport arrivals, or Linux/Windows/Zig 0.17.

## Harvestable young trees — 2026-10-11

- Replaced the repeated blue cube salvage markers with small broadleaf trees that combine a leafy crown and trunk in one mesh. Their generated heights range from 6.1 to 18.3 m (20–60 ft); the giant tree scale is unchanged. They remain harvestable for parts, with a tree-sized interaction target.
- Bumped scatter generator version to 8 and save format to 19. Generator-5, -6 and -7 saves migrate while preserving candidate IDs and collected-object removals.
- **Checked:** `python3 tools/zig.py build check` and `git diff --check` passed. `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 120 python3 tools/zig.py build run -Dshowcase=62 -Dcapture-frame=120 -Daudio=false -Doptimize=ReleaseSafe` completed on Apple M3 Pro with no Metal validation messages. `zig-out/sapling-review.png` was inspected; the blue blocks are replaced by tree silhouettes.
- **Not checked:** headless tests, hands-on harvest reach and reward flow, Zig 0.17, Linux/Windows builds or runtime.

## Forward flight and expanded jet fuel — 2026-10-11

- Holding forward and tapping dodge three times within 0.92 seconds launches into sustained forward flight. Flight cruises at 32 m/s, reaches 52 m/s with sprint, uses jump/ascend to climb, and reaches 76 m/s during chained dash bursts. Each flight dash uses 18 fuel before efficiency upgrades.
- Increased the base fuel reserve from 100 to 240 and each of the three fuel-tank upgrade levels from +30 to +100, for 540 maximum (620 for winged heroes). Fuel efficiency applies to sustained flight and its dash bursts.
- Updated the upgrade description and movement documentation. The gesture works through the existing keyboard dodge binding and controller dodge button while forward is held.
- **Checked:** default pinned `python3 tools/zig.py build check`, `python3 tools/zig.py build -Doptimize=ReleaseFast`, and `git diff --check` passed; the installed executable was refreshed.
- **Not checked:** headless tests, hands-on keyboard/controller timing, flight steering against terrain, fuel depletion/recharge feel, gameplay smoke, Metal capture, benchmarks, Zig 0.17, Linux/Windows builds or runtime.


## Character silhouette and fantasy canopy expansion — 2026-10-11

- Added two built-in hair cuts (crown braid and tempest sweep), pilot and recon helmet profiles, and the fabricable Solar Mantle armor set. New enum choices are appended to preserve existing saved tags; the helmet cycle reads its length from reflection.
- Added copper-fan, moon-cascade and star-blossom giant trees alongside the existing four forms, each with its own trunk and leaf pigment. Raised crown mesh tessellation and added a repeatable character showcase for reviewing the new armor, helmet and hair combinations. Scatter generator version 7 preserves candidate IDs; save format 18 migrates generator-5 and generator-6 worlds.
- **Checked:** default pinned `python3 tools/zig.py build check`, `python3 tools/zig.py build -Doptimize=ReleaseFast`, and `git diff --check` passed; the installed executable was refreshed. ReleaseSafe captures for `-Dshowcase=62` and `-Dcharacter-showcase=44..45` completed on Apple M3 Pro with Metal API Validation enabled and no reported validation errors. The tree lineup and character captures were visually inspected. The first character capture exposed oversized pilot helmet temple pods, which were reduced before the final captures.
- **Not checked:** headless tests, full gameplay smoke, benchmark, Zig 0.17, Linux/Windows compilation or runtime, old-save round-trip at runtime, and hands-on creator browsing. The first captured lineup remains visually dense and partly dark; clean close-ups of individual tree silhouettes and helmet fit still need review.

## Nearby loot, visible wild encounters and capture rewards — 2026-10-11

- Ground pickups now auto-collect within 3.5 m horizontally and 3.5 m vertically. Enemy takedowns immediately credit the nearest present player's Kit with XP and materials, so ranged kills no longer leave required salvage behind; Scalari pay scrap and parts, Hive units pay alloy and sometimes lumen. Hive drops remain for the no-player case.
- Four net-capturable animals now spawn 48–80 m from the starting point, within the near-body rendering range, and flee over terrain when approached. The practice patrol starts about 45 m from spawn with a low-damage prospector droid, followed by scout and stinger roles.
- A fresh pet capture separately grants 100 combat XP, 60 pet XP, 15 scrap, two parts and two lumen shards to that player's kit.
- **Checked:** `git diff --check`, `python3 tools/zig.py build check`, and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed with the pinned macOS compiler; the optimized executable was refreshed.
- **Not checked:** headless tests, Metal smoke/capture, hands-on play (including net aiming, capture interaction and reward display), benchmarks, Zig 0.17, Linux/Windows compilation or runtime. Prior uncommitted work in the tree is still present and was not altered as part of this feature.

## Running, dodge, dash and jump gestures — 2026-10-11

- Ground dodge now starts a short low roll even from a standstill; the previous minimum-speed gate made it appear unresponsive. An air dodge gives a brief evade, and a second tap upgrades it to the powered dash. The double-tap window is 0.42 seconds, and paired taps can chain up to four boosts. Sprint plus forward and jump launches the extended long jump; backward movement plus jump launches the backflip. Added separate sprint, roll, dash, long-jump and backflip poses, including timed rotation through the backflip.
- Documented keyboard and controller gestures and added showcase 63 to review each locomotion pose.
- **Checked:** `python3 tools/zig.py build check` passed on the pinned default compiler. ReleaseSafe Metal captures `-Dshowcase=63 -Dcapture-frame=400` and `-Dshowcase=28 -Dcapture-frame=120` completed on Apple M3 Pro with Metal API Validation enabled and no validation messages. `zig-out/movement-review.png` and `zig-out/controls-movement-review.png` were inspected; the backflip reads clearly mid-rotation, and the gesture guide fits on the Controls screen.
- **Not checked:** headless tests, full gameplay smoke, hands-on keyboard/controller timing, chain exhaustion and stamina behavior, Linux/Windows runtime, Zig 0.17, or benchmarks. The capture validates rendered poses, not live input feel or collision outcomes.

## Frontier wildlife, Scalari hybrid and field droid — 2026-10-11

- Added territorial retaliation for the four seeded wild companion species. The energy net deals nonlethal damage; two hits weaken and snare an animal at 24% vitality for eight seconds, and interaction catches it into that player's Kit. A close uncaught animal can swipe for 8 damage. The capture timer, co-op ownership and best encounter distances still need in-game tuning.
- Added a Scalari machine-insect hybrid melee role with its own health, speed and attack values, a character profile, XP and personal salvage. Its first instance appears near the existing distant Scalari nest. Existing Scalari scout, stinger, titan and miner remain distinct.
- Added a buildable field droid in the fabricator's Companions tab. It runs with the animal pet, follows, fires at nearby ground enemies, has independent health and combat-XP levels, and is saved per player. Scalari takedowns award the owner's parts. Save format 16 stores droid ownership and XP; formats 12–15 default those fields. Format 17 migrates generator-5 saves to the expanded flora while preserving candidate IDs.
- **Checked:** `python3 tools/zig.py build check` passed on the default pinned compiler; `git diff --check` passed.
- **Not checked:** tests, Metal smoke, performance, screenshots/art review, Zig 0.17, Linux, Windows, and the complete in-game capture-to-fabrication progression. This change has only had the macOS Debug compile check.

## Character ink hull cost and post-overhaul platform gate — 2026-10-11

ReleaseFast, Apple M3 Pro, Metal, silent, default pair, 600 measured frames (`tools/benchmark.py`, new `--cel-debug 1` flag hides the ink hull, same as F8):

| Route | Ink | Views | Render CPU p50 / p99 | Presentation interval p50 |
| --- | --- | --- | --- | --- |
| Frontier (four players, guests visible) | on | 4 | 3.18 / 4.46 ms | 20.85 ms |
| Frontier | off | 4 | 3.29 / 4.70 ms | 20.85 ms |
| Streaming (one view, no other characters in frame) | on | 1 | 0.36 / 0.56 ms | 20.85 ms |
| Streaming | off | 1 | 0.33 / 0.51 ms | 20.85 ms |

Findings: with four characters the ink hull adds no measurable CPU cost (the on/off difference is inside run-to-run noise, and ink-on was lower). Character skinning is 0.07 ms p50 either way. The presentation interval is identical in every run, including the empty one-view route, so it is set by display pacing, not rendering; **GPU time of the hull is not measured** (Mach has no timestamp queries). The hull is a second indexed draw per visible character, and `Characters.draw` already skips characters that are not visible, so no distance cut was added. Not measured: a true one-character route (the benchmark has only one view with no other characters, or four views); a lone character is drawn only in the creator. The frontier run also reports `simulation_step_budget` failing at p99 4.04 ms against a 4.0 ms budget with ink on and off, unrelated to rendering.

Platform gate results for the same commit are in [engine alignment](plans/alignment.md#post-overhaul-gate-on-main-1fe9e13-2026-10-11).

## Anime face and head proportions — 2026-10-11

- **Changed:** `HeadSpec` and the comptime `face_presets` table (six faces, with the new `hero`), keyframed head profile, short neck, 5.9 to 6.5 head ratio for humans, larger eyes, tapered brow strokes, flat nose with a shadow mark, adjustable mouth, `hand_scale` and `foot_scale`. `Profile.FaceStyle` gained `hero` at the end; no save format change (the tag is stored by name, old saves default to `classic`).
- **Checked:** `python3 tools/zig.py build check` (default pair) and `HEAVYWATER_ZIG_CHANNEL=0.17 build check` pass. `build test`: 369 of 377 pass; the 8 failures (armor suits count, asset Meta sidecar, Save format rejection, Sandbox controller, Profile hair-style wrap, Creator height, Screens layout, Enemies nest) fail identically on the unmodified base commit and are not from this change. New tests that pass: head profile ordering and head-ratio range for every preset, preset and `FaceStyle` order, hero versus classic proportions, face decal brow, nose and mouth placement, and the `FaceStyle` JSON round trip with a legacy document. ReleaseSafe Metal smoke (300 frames, validation layer) passed. ReleaseFast captures with `-Dcharacter-showcase=3` and `4` for classic, hero, soft, angular, alien and heroic were inspected.
- **Not checked:** the other platforms, benchmarks, helmet and hair fit across all styles (the visor and hair generators scale with head height and were only seen on the short hairstyle), profile and three-quarter views, and Wildkin visuals (they keep their own head ratio, neck and hand scale, only the tests exercise them). Captures are at creator distance, where the mouth and brows are only a few pixels.

## GLB source trace and modular export — 2026-10-11

- The repository already had a static glTF/GLB-to-HWMS converter. Added `asset-compiler trace` to validate sidecars and report GUID/hash provenance, stable node/mesh/primitive addresses, material slots, buffer/image dependencies and features outside the static importer.
- Added `asset-compiler split` to bake each selected-scene node/mesh/primitive into an independent HWMS model and write `modules.json` with source identity, content hash, material, triangle count and bounds. The bundled crate fixture exported two modules: hull (12 triangles) and band (12 triangles), with expected distinct bounds.
- `python3 tools/zig.py build check` and `python3 tools/zig.py build` passed on the pinned compiler; the game and host asset compiler were installed. Manual `trace` and `split` commands completed on `assets/source/crate.gltf`; output is under ignored `zig-out/`.
- Headless tests and cross-compiles were not run. Mod API 1 still cannot load or place exported model modules; texture maps, animation, audio and scene import are also outside this first static-model step.

## Importer expansion review — 2026-10-11

- glTF primitives without authored normals now import with deterministic area-weighted normals computed from transformed triangle faces. Trace and split manifests identify generated normals. The GLB reader rejects a mismatched declared file length, misaligned chunks, non-JSON first chunks, and duplicate JSON/BIN chunks.
- `python3 tools/zig.py build import` refreshed the crate sidecar to glTF importer version 2, retaining its GUID. `python3 tools/zig.py build check` and `python3 tools/zig.py build` passed on the pinned compiler.
- Manual CLI review used a temporary copy of the crate with NORMAL removed: trace and split completed, both modules were exported, and all 48 output vertex normals were finite and unit length. A 12-byte malformed GLB was rejected with `InvalidGlbLength`.
- The headless suite, Metal smoke/capture, Zig 0.17 and cross-compiles were not run. No runtime or Mod API model installation was added. Additional formats, mesh optimization/LOD/meshlets, and guessed semantic labels were deferred; the current exporter preserves literal source primitive boundaries and stable hashes.

## Jeweled armor customization — 2026-10-11

- Added three armor unlocks to the fabricator and creator: Gem Aegis, Starforge and Deep Prism. All fit both existing body presentations. The player can customize the saved gemstone color (six options) and cut (three options); these appearance choices do not affect combat stats. New profile fields default for old saves, so no save version change was needed.
- `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed on the pinned default Zig/Mach pair; the installed `zig-out/bin/heavy-water` was refreshed. The creator line-count expectation was updated for the two added appearance rows; tests were not run.
- `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 90 python3 tools/zig.py build run -Dshowcase=61 -Dcapture-frame=120 -Daudio=false -Doptimize=ReleaseSafe` completed and the capture `zig-out/gem-armor-review.png` was inspected. Metal API Validation produced no reported errors. The ruby setting and customization controls are visible; the creator obscures part of the lineup, so all three silhouettes still need a clean visual review.
- Headless tests, full smoke, Zig 0.17, cross-compiles, benchmarks and Linux/Windows runtime checks were not run for this increment.

## Energy net and greatblade — 2026-10-11

- Added a fabricable energy net. Its fast lattice shot reaches 120 m/s, damages every Hive flyer intersecting a broad capture corridor, and briefly freezes survivors for 1.45 seconds so they are easier to hit again. It has a 1.1-second firing cooldown and a distinct cyan lattice visual. The existing firearm shots still damage flyers through the shared Skies shot path.

## Starter companion, pet growth and air support — 2026-10-11

- Enlarged the energy-net lattice and its flyer hit corridor by 15%.
- New games, new local players, empty ranger files, and older empty saves receive the level-one plasma hound. Pet experience remains individually saved and now increases both damage and maximum health; each pet shows its current level and health in the HUD.
- Companion targeting now includes Hive flyers within 28 m as well as ground enemies. Pet strikes damage and stagger flyers, bring them down for alloy, and award nearby companions XP. Hostile melee units can damage pets; companions recover health outside combat.
- Default Zig/Mach build verification is in progress. Headless tests, smoke, visual capture, and other compiler/platform checks have not been run.
- Expanded the held saber into an oversized, curved, segmented plasma blade with a white-hot center and accent-colored outer facets. The animated swing trail is wider, longer, and uses the player's weapon accent; the damage sweep reach now matches the larger silhouette.
- `python3 tools/zig.py build check` passed on the default Zig 0.16/Mach pair.
- `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 90 python3 tools/zig.py build run -Dshowcase=37 -Dcapture-frame=120 -Daudio=false -Doptimize=ReleaseSafe` completed on Apple M3 Pro with Metal API Validation enabled and no validation messages. Capture `zig-out/energy-blade-review.png` was inspected. The blade reads at a dramatically larger scale; the showcase image shows the held silhouette more clearly than its active swing, so the swing's pose and feel still need hands-on review.
- Headless tests, full smoke, Zig 0.17, cross-compiles, benchmarks, and Linux/Windows runtime checks were not run. Flyer net damage and snare behavior were reviewed in code but were not separately exercised in a gameplay run.

## Fantasy forest and species-colored bioluminescence — 2026-10-11

- Added procedural redwoods reaching 152.4 m (500 ft), with a dark-crimson crown and matching species trunk; broadleaf, needleleaf and willow forms scale to 96–150 m. These giant trees are sparse so native grass, ferns, manzanita and ember, moonbell and sunspear flowers remain the forest-floor layer. Scatter generator version 6 records the changed distribution and scale; prior generator versions are rejected rather than silently regenerated.
- Leaf flecks preserve each plant's own pigment at night: crimson redwood, red ember blossom, blue moonbell, gold sunspear, and the existing green and cyan plants. Grassy low-slope ground keeps its scattered glow patches; snow and steep rock remain masked out.
- `python3 tools/zig.py build check` passed on the default Zig 0.16/Mach pair. `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 120 python3 tools/zig.py build run -Dshowcase=62 -Dcapture-frame=120 -Daudio=false -Doptimize=ReleaseSafe` completed on Apple M3 Pro with Metal API Validation enabled and no validation messages. Capture `zig-out/flora-review.png` was visually inspected for tree silhouettes and night pigments.
- Headless tests, full smoke, Zig 0.17, cross-compiles, benchmarks, and Linux/Windows runtime checks were not run for this flora pass.

## Controller interaction and D-pad routing — 2026-10-11

- Reviewed the controller factory mapping and preset example. The factory layout already assigns all 16 standardized physical inputs; A is jump and X is contextual interact. The actual gameplay gap was P1 routing: D-pad edges were only used in UI, while guests already used left/right for weapon cycling and up/down for specials.
- P1 now gets the same gameplay D-pad functions: left/right cycle owned weapons; up/down trigger specials 1/2, with up+RB for special 3. Menus and trade panels keep their existing D-pad navigation.
- X remains separate from jump and now handles relic salvage as well as existing contextual use: talk/trade, hero recruitment, vehicle boarding/exit, device buttons, and machine inspection when aimed at a structure. Mouse salvage is preserved. HUD prompts identify X for these targets, and the mapping screen calls out interaction/discovery/mantling.
- Updated the portable preset example to match the real factory mapping and documented the button roles.
- `python3 tools/zig.py build check` passed on the default Zig/Mach channel. Headless tests, smoke, other compiler channels and cross-compiles were not run.

## Contextual vehicle boarding and smooth saber moves — 2026-10-11

- Nearby parked vehicles now remain interact targets when the aim ray lands on terrain, generic scenery or a bridge. The forgiving proximity radius is 6.5 m, boarding works from any selected tool, and the target prompt names X as the left face button. Semantic nearby targets such as a person, kiosk, device or jet keep priority.
- Replaced segmented held-blade pieces and block-built saber waves with generated curved blade, inner-spine and 64-segment crescent meshes. The third quick cut fires a smaller weak wave; the held charge remains the stronger, longer-reaching wave. Dash attacks slash through, ascending attacks rise, falling/stomp attacks cut down, neutral air attacks spin, and attack+dodge throws a piercing saber that returns to its owner.
- **Checked:** `python3 tools/zig.py build check` passed on the pinned default compiler. A ReleaseSafe Metal API Validation capture (`-Dshowcase=37 -Dcapture-frame=120`) completed twice on Apple M3 Pro with no reported validation errors; the smooth crescent shape and updated blade were inspected in `zig-out/saber-mesh-review.png`.
- **Not checked:** headless tests, full smoke, benchmarks, controller-in-hand boarding, move timing/target damage during gameplay, Zig 0.17, cross-compiles or Linux/Windows runtime. Compile-only vehicle reach and combat behavior still need direct input verification.

## Vehicle boarding prompt and keyboard interaction — 2026-10-11

- Parked garage cars remain interactable within 6.5 meters if the aim ray misses their chassis or is occluded by terrain. This also keeps the boarding prompt visible while standing beside a car.
- The existing `I` investigate key now performs contextual interaction; it still toggles the inspection panel when aimed at a structure. Vehicle prompts list `I`, controller `X`, and mouse click.
- The default Zig/Mach `build check` and installed `build` passed. `git diff --check` passed. Headless tests, smoke, Metal visual review, and other compiler/platform checks were not run.

## Ranger hairstyles — 2026-10-11

- Expanded the character creator from five hair entries to eleven: short, ponytail, long, crest, hood, bob, twin tails, bun, braids, curls and undercut. Ponytail, paired braid, bun, curly, cropped and mohawk silhouettes now have separate procedural generation paths. New enum tags are appended so existing profile JSON names remain valid.
- The pinned Debug check and ReleaseFast build passed; `zig-out/bin/heavy-water` was reinstalled. A Metal API Validation ReleaseSafe character preview for braids completed on Apple M3 Pro and was visually inspected. Headless tests were not run.

## Anime action hair — 2026-10-11

- Added data-driven hair (`hair_style.zig`, `hair_library.zig`): fat tapered clumps rooted on the scalp ellipsoid, a per-style hairline, `validate`, and `HairSpec.custom` for modded styles. Short and crest are now data; nine new styles (spiky_hero, widow_flame, fringe_spikes, super_flare, flip_bob, pilot_sweep, big_fringe, topknot, spike_tail). Profile gained `hair_spike`, `hair_volume`, `hair_length` (creator rows). New fields default on old saves and round-trip in a Profile test; `Save.format_version` was not bumped because nothing existing changes meaning (same policy as the face and boot additions).
- Tests: every definition validates, builds finite vertices with in-range joints, roots sit on the scalp, extents are bounded, the styles produce different meshes, adjustments change height, and a wider head still fits. Pinned `build check` passed; ReleaseSafe Metal captures of short and the nine new styles were inspected (all read as distinct, spiky or swept, not a cap). Not reviewed: side and back views, non-brown colours, spring chains moving (`sway` clumps only move when `chain_joints` > 0, which the game sets to 0), the remaining procedural styles' cap look, 0.17 channel and cross-compiles.

## Anime hair shading — 2026-10-11

- Ranger hair now bakes a broad broken highlight band plus narrow comb-strand glints into its vertex colors. This runs on GPU-skinned game characters; the CPU preview's existing cel light, face-shadow map, SDF facial decals and silhouette ink remain unchanged.
- Pinned Debug check and ReleaseFast build passed; `zig-out/bin/heavy-water` was reinstalled. `MTL_DEBUG_LAYER=1` ReleaseSafe braid character preview completed on Apple M3 Pro and was inspected. Headless tests were not run; close-up readability, other hair colors and moving-light response remain unreviewed.

## Solar-system roster, fusion-pulse travel and democratic campaign — 2026-10-11

- Added `procedural/SolarSystem.zig`, cataloging Mercury through Neptune, twelve visitable moon concepts, settlement/governance hooks, and one Scalari mining front per planet. Added a low-threat Scalari Talus Prospector enemy near the distant surface nest, with a compact drill rendering, 45 health, 20 XP and 2 scrap on defeat. Its mining-site records specify 4 abstract resource units/minute; a functioning mining economy is not connected.
- Fusion-pulse drive rating is fictional 0.5c for fast travel between bodies. The selected campaign scope is local flight around a planet/moon and its stations; continuous interplanetary flight and orbital mechanics are out of scope. Planet-scale metadata does not enter local physics or rendering. Gaia remains a constructed globe in Saturn space, and the Hive/Scalari homeworld stays interstellar.
- Updated the Solar Assembly / voluntary Galactic Democratic Compact framework and campaign plan for mining stations, staged city-planet growth, Venus terraforming, and an original winged transforming-mecha art direction.
- This is catalog/design groundwork plus one unverified ground enemy. No Kestrel form transition, mech locomotion/combat, mining production simulation, station building, space HUD, planetary fast-travel UI, or democracy interaction is playable. No build, tests, smoke or benchmark was run; compilation and behavior are unverified.

## Weapon visuals, suit runners and Energy Skate — 2026-10-11

- Saber blades use each player's profile accent. Charged waves use the saber slot's weapon element, and render as 14 overlapping facets forming a broad colored crescent with a white-hot inner edge. Mk III increases speed, radius, lifetime and pierce count.
- Hardsuits add joint-bound shoulder shells and luminous twin-roller heel runners. Energy Skate uses low-traction board movement on all current ground types, 16/23 m/s walk/sprint speeds, a 1.52× base jump and fuel-consuming air assist. It has a run animation pose and a distinct sound cue.
- No build, tests, smoke, visual capture or hands-on controller check was run for this pass. Zig compilation and the in-game look/feel remain unverified.

## Planet feature packs and maximum-progression test setting — 2026-10-11

- `Worlds.zig` now catalogs per-destination traversal, hazards, interactive city systems, enemy roles and mission objectives for Arbor Frontier, Hive Homeworld and Gaia. This remains typed design data; it does not add planetary travel or playable regions.
- Settings has a persistent `MAX PROGRESSION TEST MODE` toggle. Runtime test unlocks max out each player's gear, upgrades, combat level, pets and materials, plus team vehicles, aircraft, hero roster and Kestrel progression. Objective-completion flags remain untouched so the story can still be played in sequence.
- The application holds a full serialized pre-test world snapshot in memory, restores it when the toggle is turned off, and refuses world/ranger quicksaves while the toggle is on. Existing save data is not modified by enabling or exercising the mode.
- Build, tests and smoke were not run for this pass. Zig syntax, UI fit, unlock coverage, restore behavior and save blocking remain unverified.

## Chained dashes, Scalari practice patrol and ranger combat levels — 2026-10-11

- Dodge double-taps now start a 42 m/s directional dash on ground or in air. Further double-taps chain up to four bursts inside a 1.35-second window; single-dodge ground roll and board boost behavior remain available.
- Added low-health melee-only Scalari scout and stinger roles. A patrol near the spawn replenishes at 16-second intervals up to three active units; a Scalari bio-titan with 1,850 health and a heavy melee attack is placed beside a distant surface nest.
- Combat XP is stored in each player's Kit and ranger file/save shape. Every 250 XP advances a level, up to 50, and adds 2 maximum health. The nearest active player gets XP on a takedown; Scalari defeats also award personal scrap. Save format 14 reads formats 12 and 13 with their existing migration/default rules.
- Added cyan low-profile scout drone rendering, amber stinger and oversized titan character profiles, separate Scalari reward handling, and updated combat/world docs.
- No build, tests, smoke, benchmark, save round-trip, dash handling check or visual review was run. These changes are implementation-only and remain unverified on macOS.

## Long jumps and energy martial combat — 2026-10-11

- Sprint-jump now launches a long-jump motion with forward carry. An airborne stomp sets a short landing pulse; combat turns it into a 92-damage radial energy kick with push/stun and colored impact effects.
- Hands-tool attacks with no world target chain two energy punches into a roundhouse. The alternate input guards and briefly parries. The Ranger gets strike/kick poses; punch, kick and landing effects use the profile accent. Existing four-step chained dash remains available to set up an airborne finisher.
- The first pinned Debug check exposed a missing armor enum value plus syntax/name errors in the Scalari practice-patrol count and drone render local; these were corrected. `python3 tools/zig.py build check` and the ReleaseFast build both passed, rebuilding `zig-out/bin/heavy-water`.
- Headless tests, Metal capture, and hands-on combat were not run. Enemy hit feel, control conflicts and animation quality remain unverified.

## Starter Skimmer access and cockpit silhouette — 2026-10-11

- Worlds with no vehicle now receive a Skimmer in the garage, including existing saves with no fabricated ride. Boarding reports the drive/flight controls: W/S thrust, A/D steer, Space/E ascend, Q descend, Shift boost; click or controller interact to exit.
- The generated hovercar now has a raised panoramic canopy and swept nose canards. The Skimmer uses a deep blue shell, dark composite accents and cyan flight lighting. The existing four-fan hover controller supports close-to-ground driving and vertical flight.
- The pinned Debug check and ReleaseFast build passed; `zig-out/bin/heavy-water` was reinstalled. A Metal API Validation ReleaseSafe showcase capture completed on an Apple M3 Pro, and the refreshed model was visually inspected. Headless tests and hands-on driving/flight were not run.

## City modules and enemy damage audit — 2026-10-11

- Interior room roles now map to reusable fixture modules and local interaction anchors (exit, trade, evidence, power, alarm, loot, unlock, and Hive heart). This is a data contract for the runtime; rendering, entry transitions, doors, population, and actual interactions remain open.
- The district now composes a canopy parkour route at each market tower from reusable ladder, patio, ramp, mini-bridge, jump-gap, and grapple-anchor pieces. These are included in the same district render/collision mesh. Their placement and traversability have not been visually reviewed or hand-played.
- Hive damage is now fully held in each archetype's `Stats`: projectile burst values plus melee damage, guarded melee damage, grenade damage/radius/fuse/cooldown. Existing values are unchanged. Static rates at uninterrupted firing are drone 3.85 damage/s (5 every 1.3 s), sentinel 8.57 (three 8-damage bolts every 2.8 s), trooper 6.67 (two 6-damage bolts every 1.8 s), skirmisher 2.0 (3 every 1.5 s) plus 14.63 point-blank melee (12 every 0.82 s), and bulwark 2.5 (6 every 2.4 s) plus 15.76 point-blank melee (26 every 1.65 s). Trooper's 24-damage grenade adds up to 3.43 averaged over its 7 s cooldown at the blast center. These sources stack when multiple attacks connect.
- A correctly facing guard reduces bolts and grenade damage to 25%; it halves melee damage (trooper 18→9, skirmisher 12→6, bulwark 26→13). Player health regenerates after 5 quiet seconds at 10/s. These are code-derived rates, not measured encounter DPS or a manual balance verdict.
- Generated Arbor foliage now uses larger irregular eight-facet clusters, and the canopy course palette shifts toward warm grown decking, green structural rails, and lumen grappling markers. This changes render geometry and color only; the Metal art-review capture and hands-on route check have not been run.
- Build, tests, and smoke were not run for this pass, as requested; compile and runtime integration remain unverified.

## Ocean city catalog and feature plan — 2026-10-11

- Added stable Frontier city IDs for Pelaglass (human pressure-dome habitat) and Sonorous Reef (fully submerged cetacean city), an `ocean_shelf` biome descriptor, and distinct city roles. Frontier's expected catalog count is now seven; Hive Homeworld and Gaia remain five each. The campaign-wide data test was updated to expect 17 city records.
- Added the Stormwake Carrier Siege arena descriptor and encounter kind for open-ocean combat, plus [the ocean-cities design](plans/ocean-cities.md) covering wave surfing, underwater movement, carrier subsystem assaults, the paired-city liberation loop, original orca-form Tideborn champion Neri Tidebreak (working name), and separate Hive and Scalari roles.
- This is catalog and design groundwork only. No build, tests, smoke, ocean renderer, underwater movement, city geometry, or carrier encounter implementation was run or verified.

## Scalari campaign foundation — 2026-10-05

- The campaign catalog now has three destinations, five stable city-region IDs and one capital per destination. Validation enforces the city count, unique IDs/capitals and the single final-boss site at the Scalari Obsidian Coil; the Hive Homeworld records the Scalarians as its ancient founders.
- Five procedural Scalari ship assets are built and registered under generated GUIDs: Ember Wyrm, Void Lance, Dreadclaw, Throne Serpent and Worldcoil Ark. Their shell/glow geometry test checks non-empty indexed meshes and finite 3D vertices. The final mothership geometry uses one full-span armored wing assembly.
- `-Dshowcase=47` presents the three fighters and two motherships together for in-game visual review.
- `python3 tools/zig.py build test --summary all` passed **331/331 Debug tests**. After the mothership mesh review, the targeted Scalari/vehicle run passed **36/36 tests**; `python3 tools/zig.py build check --summary all` passed the full application compile, and `git diff --check` passed.
- ReleaseSafe Metal art-review capture: `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dshowcase=47 -Dcapture-frame=90 -Daudio=false -Doptimize=ReleaseSafe` exited cleanly on Apple M3 Pro. It rendered all five ships in one 3D frame with no Metal validation messages; the review image is `zig-out/scalari_fleet.png`.
- City descriptions and ship meshes are authoring foundations only. City environments, capital interiors, playable Scalari flight/combat and final-boss gameplay remain unimplemented.

## Collision, interiors and shareable controller profiles — 2026-10-05

- Free-flight movement now passes through the character collision controller. Regression coverage checks landing on terrain and a rigid platform. Rigid boxes also resolve oriented SAT contacts against each other, while characters can stand on or be stopped by rigid-body floors and ceilings.
- Controller setup captures button mappings, adjusts axis sources/inversion and analog thresholds, and stores eight versioned JSON slots. macOS adds generic HID discovery and native JSON file dialogs; imported files are validated before becoming active and are copied into the chosen slot. Exported JSON can be uploaded to a community website. No website endpoint is part of this game repository.
- Interior generation now produces connected deterministic room-module graphs for residences, shops, factories, enemy bases and dungeons. Room rendering, entry transitions, doors, population and loot remain to be integrated into gameplay.
- `python3 tools/zig.py build test check --summary all` passed: **330/330 Debug tests** and the full application compile check. The latest world-catalog source also passes `python3 tools/zig.py test src/procedural/Worlds.zig` (**2/2**, including its Seed dependency).
- ReleaseSafe Metal smoke: `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dsmoke-frames=120 -Doptimize=ReleaseSafe` completed all nine scripted stages, including saber/sniper combat, caves, four-player split-screen, building, save/restore and city traffic, with no Metal validation errors. The smoke also exposed and fixed an invalid tagged-union read in its weapon-fabrication loop.
- No physical unfamiliar HID controller or native import/export dialog was available for a hands-on run. Linux and Windows controller backends remain unimplemented.

Bootstrap (phase 1):

- Debug unit suite: 10/10 passed. Covers fixed-step stall accounting, projection depth and camera orientation, seed hashing, shared chunk seams, same/different seeds, allocation-failure cleanup, frustum boundaries, and signal graph validation.
- ReleaseSafe unit suite and application compile pass.
- ReleaseFast application builds and installs.
- Initial Debug smoke completed 120 submitted frames with 1,000 objects and clean shutdown.
- Final ReleaseSafe smoke completed all three scripted stages and 16 frames with `MTL_DEBUG_LAYER=1`; Metal API validation reported no errors. The final camera view submitted 732 of 1,000 objects with CPU culling enabled, and shutdown returned exit code 0.

The HUD reports render-callback interval, submitted instance count, draw count, seed, and culling state. No GPU timing or representative throughput claim has been established. Screen capture was unavailable in this session, so pixel-level visual inspection and manual keyboard/mouse interaction remain unverified.

## Procedural streaming (phase 2)

- Debug and ReleaseSafe unit suites: 20/20 passed. New coverage: chunk key boundaries (negative, NaN, out of range), planner bounds and center priority, handle invalidation on recycle, canceled generation, in-flight slots held until the worker acknowledges cancellation, unload/regenerate producing an identical terrain and scatter fingerprint with no new pool allocations, allocation-failure cleanup, biome normalization, scatter stability and slope limits, percentile ranks, and the fly-through route.
- ReleaseSafe 120-frame smoke with `MTL_DEBUG_LAYER=1`: no Metal validation errors, clean exit.
- ReleaseFast benchmark, 600 measured frames, default budget: interval P50/P95/P99 20.8/21.0/21.1 ms (presentation-paced), render-thread CPU P99 about 1.1 ms, 40 chunk crossings, 225 uploads, 200 evictions, peak upload 278 KiB of a 320 KiB budget, peak 25 resident chunks, 0 frames with the active 3×3 ring missing, pool allocations fixed at 2 CPU and 50 GPU buffers.
- One benchmark run reported an interval P95 of about 1 s with normal CPU times, which is macOS throttling an occluded window. The benchmark now fails such runs (`presentation_unthrottled`).

Interval timing is presentation pacing, not GPU execution time. Visual seam inspection at chunk borders is still manual.

## Interaction and assets (phase 3)

- Debug and ReleaseSafe unit suites: 36/36 passed. New coverage: typed handle pools; terrain queries matching rendered vertices and triangle interiors in a negative chunk; runtime model round trip, version, truncation, index, and allocation-failure rejection; glTF compile of the crate (two materials, interleaved view), baked node rotation and translation, out-of-range accessors, and unsafe external URIs; catalog load and allocation failure; box settling, stacking, friction, and raycasts; the character blocked by walls, stepping onto a ledge, and pushing a prop; save round trip with a seed above 2^53, and rejection of mismatched seed, generator, format, prop ranges, and truncated JSON; atomic save file write and read.
- Headless acceptance tests (`game/Sandbox.zig`): walk until a crate blocks the player, pick it up, turn and carry it 7.5 m, drop it, save, disturb the crate, relic set, and player, then reload the crate's exact position. A save from another seed is rejected. Salvage a relic by stable ID; it can no longer be targeted; regeneration yields the same object at that ID; the removal survives a save round trip.
- ReleaseSafe 150-frame smoke with `MTL_DEBUG_LAYER=1`: flight, empty view, walk mode, grab of crate 1 (`held=1`), and an in-memory save/restore of 1.4 KB; no Metal validation errors, clean exit.
- The streaming benchmark still passes every check after the renderer moved to catalog handles: interval P99 21.1 ms, render CPU P99 1.2 ms.

Not yet verified by hand: mouse-driven grabbing and salvaging, the on-screen crate model and crosshair, and F5/F9 against the real `saves/` directory. The code paths are covered by the tests above, but no screenshots or interactive session were taken.

## Machines (phase 4, door and elevator)

- Debug and ReleaseSafe unit suites: 44/44 passed. New coverage: port tables; blueprint parsing and rejection of wrong format, direction, port kind, multiple drivers, unknown ports, duplicate IDs, bad parameters, zero sizes, missing or cyclic logic, and malformed JSON; latch-driven actuators with two-hop latency and a mid-travel reversal; brownout sharing (two 100 W actuators on 100 W move at half speed); disabled generators; logic combining a proximity sensor; state restore validation; kinematic platforms carrying a crate, a character reporting its platform as support, and a door pushing a still character; the save round trip with machine state; and the catalog loading the shipped blueprints.
- Headless acceptance (`game/Sandbox.zig`): the closed door blocks the player; the button opens it in 150 steps to exactly 2.9 m of travel; the player walks through; a saved open state survives a manual close and reload, and stays open after stepping. The elevator carries a standing player from the platform to 4.2 m (±0.05 m), the player steps onto the landing, and the top call button sends the platform down while the player stays on the landing.
- Build-time validation: rewiring `toggle.state` to `platform.power` in `elevator.json` fails the build with `PortKindMismatch`.
- ReleaseSafe 150-frame smoke with `MTL_DEBUG_LAYER=1`: two machines placed, crate grabbed, 1.7 KB in-memory save round trip, door button pressed; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 1.2 ms).

Not yet verified by hand: how the machines look on screen, placement on steep terrain (foundations extend 1.1 m below the origin, and deeper slopes can leave gaps), and pressing buttons with the mouse.

## Vehicle (phase 4, completed)

- Debug and ReleaseSafe unit suites: 53/53 passed. New coverage: quaternion rotation, matrix form, and integration; a tilted rigid box falling and settling flat on its largest face; a sliding rigid box shoving a crate; a fast rigid box stopped by a static wall; rigid boxes blocking the character; surface rays reporting platform velocity; the rover settling at its computed ride height (±3 cm), accelerating straight, turning more than 0.5 rad while upright, and braking to a stop; staying put without throttle; losing wheel contact in the air; holding on a 20° slope with brakes, both nose-up and sideways (drift under 0.02 m over 4 s); rolling freely when released; seat, motor, and steering outputs, including a 50 W supply halving a 100 W motor's drive; frame-relative device positions; and vehicle blueprint validation.
- Headless acceptance (`game/Sandbox.zig`): the rover settles aligned with sloped terrain on four wheels, is entered by aiming at its chassis, moves more than 4 m forward in 2 s on motor power (with nonzero network demand), stops under the parking brake after exit with the player standing outside the chassis, and its pose survives a save round trip exactly.
- Fixed while testing: tires that cancelled only velocity let a parked rover creep down slopes at 0.15 m/s. Tire forces sized with a quarter of the vehicle mass overshot into roll oscillation. Suspension pushing along the chassis axis leaked downhill force. Each fix has a regression test above.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: three machines, crate grab, 2.4 KB save round trip, door button, then the rover driven 3.5 m; no Metal validation errors, clean exit. The first GPU run found that Mach's WGSL compiler lacks `cross`; the shader now defines it.
- Streaming benchmark: all checks pass (interval P99 21.2 ms, render CPU P99 1.5 ms).

Not yet verified by hand: driving feel, chase-camera comfort, rendered wheel spin and steering, and collisions between the rover and machine structures at speed.

## Creation tools (phase 5, first slice)

- Debug and ReleaseSafe unit suites: 58/58 passed. New coverage: runtime blueprint edits under the file format's rules (multiple drivers, kind mismatch, direction, duplicate IDs, vehicle-only kinds); document round trips including wires and body flags; device removal shifting wires and compacting logic nodes; live machine reconfiguration keeping state; lamps lit only when switched and supplied; save v4 with embedded blueprints, yaw, and slot validation.
- Headless acceptance (`game/Build.zig`): generator, button, latch, and lamp placed from the palette on the 0.5 m grid; three wires made by aiming and clicking; a fourth refused because the lamp input is already driven; the button lights the lamp; a fresh session restored from the save has the same circuit with the lamp lit; removing the latch drops its wires, darkens the lamp, and re-tagged bodies still pick correctly. A quarter-turned door is placed on the grid with its travel mapped from +X to −Z, a second overlapping door is refused, and aiming at its structure removes it.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: a four-device, three-wire workshop circuit built through the tool APIs, alongside the earlier stages; no Metal validation errors, clean exit. The whole-world save is now about 22 KB.
- Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 0.9 ms).

Not yet verified by hand: mouse-driven placement feel, preview visibility, wire bar readability, and F5/F9 of a built world through the real `saves/` directory.

## Prefabs and inspection (phase 5)

- Debug and ReleaseSafe unit suites: 59/59 passed. New headless acceptance: capture a generator, button, latch, and lamp circuit (named `circuit_1`, lowest device on the origin), place a copy that is its own machine, light only the copy's lamp with its button, inspect the copy (`NET 0 SUPPLY 200 W DEMAND 25 W 100%`, `lit 1.00`), rewire the copy while the prefab keeps its three wires, and restore the prefab library into a fresh session from the save.
- Manual library run: `saves/prefabs` holding a renamed elevator blueprint and a lamp with 0 W imported one prefab and logged `prefab broken.json: InvalidDeviceParameters`. The test files were removed afterwards.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: the smoke circuit is captured and a quarter-turned copy placed; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass (interval P99 21.4 ms, render CPU P99 0.9 ms).

Not yet verified by hand: pressing P and I in the running game, exporting a prefab file from a live capture, and the panel's legibility.

## Signal bus (phase 5)

- Debug and ReleaseSafe unit suites: 61/61 passed. New coverage: a sender machine's latched button carried over channel 7 to another machine's lamp; channel validation (0 and non-bus kinds rejected); and the in-world acceptance test (workshop button → latch → transmitter lights a separately placed beacon's lamp, retuning darkens it, channels wrap 1 ↔ 64, and the channel persists through a save).
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1` and the streaming benchmark: unchanged and passing (interval P99 21.3 ms, render CPU P99 1.0 ms).

## Player character

- Debug and ReleaseSafe unit suites: 65/65 passed. New coverage: name validation, typing, and the length cap; palette wrapping and proportion clamps; profile document validation; creator flow (name required, typing only in the name field, Escape only after a first confirmation, panel text); avatar proportions, hood parts, facing, glowing accents, and opposite leg swing; and the in-world test (frozen input in the creator, third-person camera behind the eyes while the crate stays targeted, avatar parts drawn, profile restored from a save).
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: a character named SORA with a ponytail created through the window-key path, then the crate grab done in third person; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass.

Not yet verified by hand: how the avatar and palettes look on screen, and the creator's usability.

## Mesh colliders (phase 6)

- Debug unit suite: 69/69 passed. The BVH ray cast matches brute force over 300 random rays on a bumpy 800-triangle grid; oriented boxes face outward; mesh build cleans up on allocation failure. Acceptance: the character climbs a 15° ramp, resting on its uphill footprint sample (0.7 r × tan 15° above center, within 1 cm); it stops at a leaning 80° wall exactly one radius from the face above step height; it lands on a 5° deck at y = 3.0 (±5 cm) and climbs toward the high end; picking reports the deck mesh and user; placement overlap sees the deck until it is destroyed; a crate rests on a mesh floor at 3.4 m (±2 cm); a rigid box settles on a tilted deck.

## Test Arbor and depth (phase 6)

- Debug and ReleaseSafe unit suites: 71/71 passed, with no leaks under the testing allocator (every test Sandbox is deinitialized). New coverage: test Arbor geometry (ramp grade under 12%, platform, bridge ends, and tower meeting at 40 m and 36 m within 1 cm, valid render mesh); the reversed infinite projection (near → 1, monotonic toward 0, distinct depths at 1 km and 1.001 km); and the full walk acceptance: steered up the whole spiral ramp at sprint input without dropping more than 0.6 m below its surface, reaching platform height (±0.3 m), then down the bridge road to the tower top (±0.1 m), grounded.
- Found and fixed by the walk test: the ramp first reached 40 m only at the platform's center line and ran into the platform's side 0.8 m below its top. It now levels out for the last 8% of its sweep.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1` (reversed depth, the test Arbor drawn): no validation errors, clean exit. Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 0.8 ms).

Not yet verified by hand: how the tree reads on screen and at distance, and haze tuning.

## Canopy lighting and review (2026-09-30)

- Review found the renderer's time of day was never published, lamps and avatar accents never set the shader's emission channel, the twilight key changed direction while still bright, and the smoke circuit button press was overwritten by the door press. Those connections are fixed. The renderer now retains Mach's GPU error callback (which exits unsuccessfully), replacing a log-only override that could hide a failed render in successful smoke/benchmark exit codes.
- ReleaseSafe: **77/77 tests pass**, application compile passes. Added clock periodicity/large-tick/wrap checks, twilight continuity, and the canopy route. Extended existing integration tests to verify that save/load restores world time, a wired lamp publishes emission when powered and loses it after disconnection, and avatar lumen carries emission.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300`: all 300 frames complete, 383 simulation ticks, no Metal validation errors, exit 0. The smoke sweeps a complete lighting cycle, creates SORA, grabs a crate, round-trips a save, builds/wires/copies the workshop, confirms `Smoke lamp: lit=1`, and drives the rover 2.4 m.
- `python3 tools/benchmark.py --canopy --frames 300 --output .tools/canopy-benchmark.json`: all checks pass on Apple M3 Pro / Metal, ReleaseFast, default seed. 60 warm-up frames then 300 measured frames; 128 detailed-Arbor and 172 proxy-Arbor frames, 16 chunk crossings, 105 uploads, 80 evictions, no underfilled active-ring frames. Render CPU P50/P95/P99: **0.572 / 0.858 / 0.926 ms**. Presentation interval P50/P95/P99: **20.851 / 20.944 / 21.074 ms**. Peak upload 284,204 B within 327,680 B; peak 25 GPU terrain chunks; fixed pools remain at 2 CPU and 50 GPU allocations.
- Formatting and diff whitespace checks pass. Benchmark CLI help works with the new canopy option and separate default report path.

The benchmark measures render CPU submission cost and presentation intervals, not GPU execution time. Pixel-level appearance, outline thickness, color tuning, and manual day/night play remain unverified; no screenshot review was performed. The single test Arbor stays resident at both detail levels. Multi-Arbor residency, local lights, and bloom are not implemented by this change.

## Arbor genomes and sap (2026-09-30)

- ReleaseSafe suite: **85/85 tests pass**. New coverage includes deterministic bounded space colonization; genome validation; measurable narrow/broad silhouette differences; valid full/proxy/collision meshes; parent-before-child graph structure; allocation-failure cleanup; and landing/walking on a generated shelf at its rendered height. Existing full test-Arbor ramp/bridge walk remains passing.
- Sap coverage: proportional root sharing and branch limits, order-independent grants, independent trees, exclusion of local generator supply and detached/disabled/idle taps, continuous lamp brownout, and shared power across separate machines. The sandbox test saves overloaded beacons, removes a load and observes recovery, reloads and reconnects both to the same tree, rejects a generator-version mismatch without mutating the session, and verifies a remote copied tap supplies nothing. Tree lumen publishes reduced emission under overload.
- Build-tool acceptance: select the sap beacon from the palette, aim at terrain beside tree 1, obtain a valid preview, place it, receive full power, inspect its tree ID, then verify placement away from wood is invalid.
- ReleaseSafe application compile and `build assets` pass. All four blueprints, including `sap_beacon.json`, are validated and installed. Formatting, diff whitespace checks, and benchmark CLI help pass.
- **400-frame Metal validation smoke passes**, exit 0, no validation errors. It creates the player, grabs a crate, round-trips the save, builds/wires a lamp, drives the rover 3.3 m, views both generated Arbors, and reports `Smoke sap: tree 1 demand=300 W supply=150 W satisfaction=50%`. Final count: 509 simulation ticks, 861 submitted objects. The lighting cycle is swept across the run.

Apple M3 Pro / Metal, ReleaseFast, seed 310399555161; each canopy run has 60 warm-up and 300 measured frames:

| Route | CPU P50 / P95 / P99 (ms) | Presentation P99 (ms) | Detailed / proxy frames | Chunk crossings | Uploads / evictions |
| --- | --- | --- | --- | --- | --- |
| `--arbor 1` narrow crown | 0.561 / 0.744 / **0.868** | 20.987 | 174 / 126 | 14 | 95 / 70 |
| `--arbor 2` spreading crown | 0.580 / 0.789 / **0.898** | 20.976 | 174 / 126 | 16 | 102 / 77 |

## Hive air-wing variety (step 7)

- Added distinct dragonfly interceptor and beetle bomber meshes, type-specific speed, turn rate, hull strength and missile jinking. Carriers now launch a varied wing; bombers select the three market plazas as raid targets.
- Rangers on foot can hit flyers with their aimed blaster and firearm shots; the Kestrel retains its cannon and missile defense. Three successful bomb drops clear that stall's stock until dawn; destroying the bomber records a defended raid.
- Debug unit suite: **295/295 passed**. The focused Skies cases cover interceptor fragility, a ranger projectile defending a bomber raid, and the raid's three-hit loss condition.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300`: passed on Apple M3 Pro / Metal with no validation errors. All 300 frames completed; the smoke exercised the existing flight, four-player split-screen, market, and world-rendering paths with the new ship meshes registered.

## Kestrel progression (step 8)

- Aircraft tab adds three-level armor, missile rack, engine and gun-cooling upgrades, plus four paint finishes. Upgrade tiers cost shared scrap and parts; finishes save with player progress. Marked landing pads are published on each tower roof.
- Focused progression suite: 169/169 passed before the Aircraft-tab bounds case was added. Coverage includes purchase/refusal behavior, paint selection and save round trips, measurable hull/thrust changes, missile capacity, and cannon heat recovery.
- ReleaseSafe application compile and 300-frame Metal smoke pass on Apple M3 Pro with MTL_DEBUG_LAYER=1; no validation errors. The updated 300-frame smoke completed with 1,295 submitted objects and 394 simulation ticks.
- Debug unit suite: **299/299 passed**, including the Aircraft-tab bounds assertion.

## Hive campaign: corruption spread and seeded spires (step 9)

- Living surface nests spread a purple terrain stain that expands with the saved market day and stops at a fixed radius. Destroyed nests no longer spread corruption.
- The first new market day records the `corruption_seen` story flag. Up to three combat nests seed beyond a living surface nest on later market days; parent links, seeded locations and destroyed states rebuild from saved progression flags.
- Regression tests cover spread timing and cap, deterministic seed locations, seeded-nest population cap and market restock notice behavior. Debug unit suite: **301/301 passed**.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=120`: passed on Apple M3 Pro / Metal with no validation errors; 120 frames completed with 862 submitted objects and 170 simulation ticks. This smoke starts on market day 0 and does not exercise later corruption growth.

## Hive campaign: story beats and quest log (step 10)

- Tavi's scout mark unlocks after corruption appears; a surface-nest kill advances that lead. Ines's Hive-sap warning follows the scout flag. A nearby Brood carrier records the sighting; Maro then grants the saved Kestrel blueprint. The fabricator refuses the Kestrel until that blueprint is received.
- The pause menu's Quest Log shows the active objective, saved story milestones and remaining nests/carriers. A saved campaign-complete flag is set when every nest and both carriers are destroyed.
- Regression tests cover keeper dialogue gates, Kestrel blueprint gating, objective progression (including saves that already own the Kestrel), quest-menu navigation, and screen bounds. Debug unit suite: **306/306 passed**.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=120`: passed on Apple M3 Pro / Metal with no validation errors; 120 frames completed with 862 submitted objects and 169 simulation ticks. The staged Kestrel flight fixture supplies the blueprint reward directly. The smoke covers startup and split-screen, not a manual campaign play-through.

## Trooper tactics and skeletal actions (step 11)

- Wounded troopers search 16 grounded positions around their target and hold the nearest point whose line of sight is blocked by world geometry. If no cover is found, they keep advancing.
- Troopers close inside 2.5 m for a committed melee strike; a facing guard reduces its damage. At 7–24 m they throw a magenta grenade toward the player's predicted position. It has a 1.25 s fuse and 4.2 m blast radius; solid geometry blocks blast damage.
- The renderer maps cover, melee wind-up/strike, and grenade launch to dedicated poses on the existing skinned rig. Strike timing drives shoulder, elbow, chest and hip joints; cover folds the legs and guards the torso.
- Regression tests cover obstruction-based cover selection, the close-range attack, grenade launch and blast, dodging, skinned strike/cover poses, key interpolation and loop seams, weighted clip blending, traversal-state mapping, and walk/run/climb crossfades. Debug unit suite: **313/313 passed**.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=120`: clean exit on Apple M3 Pro / Metal with no validation errors; 120 frames, 862 submitted objects. This smoke covers general character rendering and split-screen but does not stage trooper tactics. Manual combat balance and animation readability still need a hands-on playtest.
- Controller smoke after the walk/run/climb crossfade change: same command, clean Metal validation, 120 frames, 862 submitted objects and 172 simulation ticks, including four-player split-screen.

Both reports pass all checks, including both LODs, the 16.667 ms render CPU budget, active-ring coverage (zero underfilled frames), and unthrottled presentation. Peak upload remains 284,204 B within 327,680 B; peak GPU terrain residency remains 25 chunks; terrain pools stay at 2 CPU and 50 GPU allocations. Reports are `.tools/canopy-1-benchmark.json` and `.tools/canopy-2-benchmark.json`.

These are submission and presentation measurements, not GPU execution timings or an art review. The three trees and both of their mesh detail levels remain resident; terrain-pool counters do not represent total process/GPU memory. No screenshot or manual visual approval was performed. Runtime grafting/growth, tree eviction, and allocation of unused flow after branch bottlenecks remain deferred. See [Arbor genomes and sap](arbors.md) for controls and content-v4 save compatibility.

## Upstream programmatic resize issue

A ReleaseSafe smoke run with Metal API validation reproduced a hang after setting `Core.windows.width/height` from the application thread. Sampling showed the main thread in `macOS.tick → NSWindow.setFrame_display_animate → windowDidResize → handleResize → windows.lock`. `tick` already owns that non-reentrant lock. The renderer and application then wait on the same collection lock. This is in the pinned Mach source, not a GPU validation error.

The experiment was terminated and the programmatic size change removed from the app. No dependency cache files were patched. The smoke sequence now exercises culling, an empty view, and HUD toggling. Initial sizing works. Before exposing a resolution selector, update or patch Mach with a tested callback/locking fix. Native drag-resize is a separate path and still needs manual validation.

## Remaining platform checks

- Manual camera capture/release, focus loss, minimization, live resizing, and high-DPI transitions.
- Windows/D3D12 and Linux/Vulkan runtime tests.
- Whole-process memory instrumentation: Mach's stock entrypoint currently omits module-container teardown.
- Deterministic screenshot regression tests and CPU/GPU percentile benchmarks.

## Packs and background loading (phase 13, slice 2) — 2026-10-01

- Debug suite: **159/159 tests pass**. The new tests cover:
  - **Packs:** round trip, blob verification, and five kinds of damaged table rejected.
  - **Loader:** 64 pack models load in the background with group progress reaching 1. A corrupted blob fails only its own asset with `HashMismatch`; a missing GUID fails with `UnknownAsset`; a generator job works; a bad pack header is refused on open.
  - **Catalog:** reserve and install, with double installs and unknown handles refused.
- The existing allocation-failure test caught a leak when a deferred build failed inside `loadSeeded`; fixed.
- `tools/benchmark.py --pack 64` (ReleaseFast, 600 measured frames): **all checks pass**.
  - The 80 MiB pack of 64 meshes was requested at frame 60, and all were decoded and installed by frame 64 and uploaded.
  - Render CPU P50/P95/P99 was 0.903/1.474/1.777 ms, presentation interval P99 21.297 ms, with zero underfilled frames.
  - The peak frame upload was 6.29 MB: the largest mesh going up alone, the allowed oversize case; every other frame stayed within the 4 MiB budget.
  - The first run failed `pack_uploaded`: 13 installs hit the 64-material pool limit. The stress code had also counted failed installs as installed. Both are fixed: the material pool is now 256, and only successful installs are counted.
- Smoke (`MTL_DEBUG_LAYER=1`, ReleaseSafe, 200 frames, including four split-screen views): no validation errors. Deferred meshes were ready 145 ms after start. The overview capture shows the Arbors and district drawn from deferred builds.

## Asset identity (phase 13, slice 1) — 2026-10-01

- Debug suite: **149/149 tests pass**. The new tests cover:
  - **GUIDs:** format, parse rejection, derived and random generation, JSON form.
  - **Sidecars:** identity and settings kept across re-import, stale-source and old-importer detection, invalid and unknown settings rejected, kind by source type.
  - **Registry:** atomic manifest load, duplicate GUIDs refused with no change, typed resolution with kind mismatch and unbound errors, reference JSON.
  - **Catalog:** every compiled and generated asset resolves by GUID, and every blueprint is reachable by GUID.
- The existing allocation-failure test of catalog load caught `loadManifest` turning out-of-memory into "invalid manifest"; fixed.
- Build behaviour, checked by hand:
  - The build fails without sidecars, and `zig build import` created all 10 (crate plus nine blueprints).
  - A second import changed nothing.
  - Editing `rover.json` without re-importing failed the build with "StaleMeta; run `zig build import`". Re-import refreshed the hash and kept GUID `275f5eab…`, and the source was then restored.

## Sky city — 2026-09-30

- Debug suite: **133/133 tests pass**. The new tests cover:
  - **Bridges:** the clear envelope for six styles on six roads plus 0 → 3 across three seeds, grounded supports clear of plazas, and light-string geometry.
  - **Skyline:** at least 12 towers per seed for four seeds, every tower clear of corridors, plazas, trunks and spawn, deterministic placement, and 0 → 3 still buildable.
  - **In the world:** every buildable style built at 0 → 3 and stood on at 12 lane and walkway points each, with styles kept through save/load.
  - **Capture:** BMP encoding.
  - **Regressions:** the existing walk and drive district loops, Arbor walks, bridge tool, traffic, and shrine tests all pass with the new geometry.
- Visual review from captured frames (`-Dshowcase`, `-Dcapture-frame`), an overview plus every road by day and at dusk. Two problems found this way were fixed: a showcase camera inside a skyscraper, and a skyline that went dark at night (window columns and road lighting added). The cable-stayed pylon was also thickened. Art-direction approval remains yours.
- Smoke, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300 frames: no validation errors, clean exit, 1,173 objects submitted.
- Benchmarks during this session ran with the window throttled by macOS, so only `presentation_unthrottled` failed. Render CPU P99 was 1.429 ms (canopy) and 1.527 ms (streaming), against 1.40 ms on the previous throttled run, with zero underfilled frames. Presentation numbers need a run with the window visible.

## Scale workloads — 2026-09-30

- Debug suite: **127/127 tests pass**. The new tests cover field determinism and cell sorting, bounds containment, budgeted streaming (20 frames at 64 KiB for 20K objects, with the CPU copy freed), frustum and distance culling, LOD selection, run merging and coverage, normalized frustum planes against the sphere test on 500 random spheres, and the process footprint.
- `tools/benchmark.py --scale` for 10K, 100K and 1M objects (ReleaseFast, 600 measured frames): **all checks pass**. See the results table in [scale](scale.md). Render CPU p99 is 1.271 / 1.213 / 1.281 ms and presentation p99 21.188 / 21.093 / 20.984 ms.
- Memory investigation at 1M:
  - The steady footprint was 1,006 MiB against 522 MiB without the field.
  - Skipping only the field's draws gave 742 MB, so about 380 MB is driver geometry storage for drawn instances.
  - The upload pattern changed the peak: 1.20 GB when uploading in one frame, 0.99 GB at 512 KiB per frame.
  - Uploads were moved from `queue.writeBuffer` to the frame encoder to share Mach's staging page.
- Not available: GPU execution time (Mach Metal has no timestamp queries), GPU-compacted culling and indirect draws (not implemented in the pinned Mach). Not measured: the visual result of the field at each LOD in the window.

## Mods and scripting — 2026-09-30

- Debug suite: **123/123 tests pass**. The new tests cover:
  - **Interpreter:** hand-assembled modules for control flow, memory, traps, fuel, depth, float conversion and float semantics; rejected imports, bad versions, and truncated or unbalanced bodies.
  - **Host:** the Zig-compiled `glowworks` module against native results, script-signature checks, and recovery from a starved fuel budget.
  - **Mod loader:** the example package, plus twelve rejected manifests or packages.
  - **World:** a breathing lamp tracks its script one step behind; duplicate installs, changed designs and missing mods are handled, and the save round-trips. The save test was also extended for v10 mods.
- Two bugs were found by tests while building it. The interpreter's loop branch re-entered the `loop` opcode, which broke branch depths. Script devices wrote their result to port 0 while `out` is port 4, as for logic.
- Interpreter cost (Apple M3 Pro, ReleaseFast / ReleaseSafe): `breathe` 802 / 836 ns per call (170 instructions); `majority` 374 / 408 ns (99 instructions); native `breathe` 5.6 ns. See the [scripting evaluation](scripting.md).
- Smoke, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 200 frames: the app installed `glowworks 1.0.0` from `mods/`; no validation errors, clean exit, 261 ticks for 200 frames (unthrottled).
- Canopy benchmark re-run with the window visible (300 measured frames, ReleaseSafe): **all checks pass**. Render CPU P50/P95/P99 0.675/1.061/1.142 ms, presentation interval P50/P99 20.842/21.1 ms, zero underfilled frames, 25 peak resident chunks, unchanged pools. This replaces the throttled presentation result recorded below.
- Not measured: official WebAssembly spec-suite conformance, and a mod placed and used by hand in the window.

## Rootsong, plaza priority, guest trading, Rootdeep shrines — 2026-09-30

- Debug suite: **115/115 tests pass**. The new tests cover:
  - **Rootsong:** root grouping, and a world test with a sender at the test Arbor and listeners at the narrow Arbor, the spreading Arbor, and away from wood.
  - **Traffic and trading:** plaza priority, and guest trading.
  - **Shrine generation:** 300 seeds verified with plan replay and blueprint validation, plus unsolvable, trivial and carry-versus-drop solver cases.
  - **Shrine playthrough:** both placed shrines played in the world from their verifier plans, with door states matched to the model after every action, then rewards, protections, reset and save/load.
- Shrine generation over 300 seeds: fallback shrine for about 1%. The median shortest solution is 8 actions (longest 16), and 187 of 300 need 8 or more. Keeping the longest of six verified candidates raised the median from 6.
- Two bugs were found by the in-world playthrough and fixed in the test's play method, not the game. Carrying a crate at eye height wedged it against the next divider wall; backing up swung it through the player. The test now carries crates overhead, clear of walls and above plate sensing height.
- ReleaseSafe step cost with city life and shrines, measured headlessly at spawn: full Sandbox step **0.130 ms** (physics 0.091, city life 0.043, machines 0.008).
- The free-traffic acceptance phase was lengthened from 60 s to 90 s, because plaza waits legitimately delay a car's third plaza on a long route.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 600 smoke frames: no validation errors, clean exit, both shrines logged with their verified plans.
- **Not representative:** during these final runs, the window was being throttled by macOS (presentation interval p95 about 1 s). The committed build behaved identically on the same run: 4,301 against 4,292 simulation ticks over 200 frames. The canopy benchmark therefore failed only its `presentation_unthrottled` check. Render CPU P50/P95/P99 was **1.021/1.232/1.399 ms**, with zero underfilled frames, 25 peak resident chunks, and unchanged pools. Presentation measurements need re-running with the window visible.
- Not measured: a controller-driven guest trading session in the window, and manual play of a shrine in the window.

## Living city: traffic, pedestrians, markets — 2026-09-30

- Debug suite: **108/108 tests pass**. New tests cover route choice with and without a bridge, replanning, lane and walkway offsets, and market stock, sell-out, dawn restock, prices and save validation. They also include the Sandbox traffic and market acceptance tests described in the [roadmap](roadmap.md), plus a save round trip for the v8 wallet and stock fields.
- Traffic acceptance: 3,600 free steps with every car upright on the deck and reaching at least three plazas, and pedestrians each moving more than 20 m without falling. Then a 0 → 3 bridge crossing (the bridge reported occupied), and a bridge closed mid-trip: the car reroutes 1 → 0 → 5 → 4 → 3 and reaches plaza 3. The closed bridge is removed after its last pedestrian crosses, with **zero recoveries** throughout.
- A first draft refused to remove occupied bridges. The test showed that a pedestrian can hold a 320 m bridge for over three minutes, so removal now closes the bridge and removes it once clear.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 600 smoke frames with city life enabled: no validation errors, clean exit. There were 3 cars and 8 pedestrians with 0 recoveries and 0 deadlocks broken, and 814 objects submitted at completion. The market logged day 0 stock.
- Canopy benchmark (narrow Arbor), ReleaseSafe, 900 measured frames with city life running: render CPU P50/P95/P99 **0.814/0.992/1.103 ms**, interval P99 20.994 ms. There were zero underfilled frames, peak residency was 25 chunks, and pools stayed at 2 CPU / 50 GPU allocations.
- Not measured: simulation cost per step for city life (the benchmark measures render CPU), a long soak for rare traffic deadlocks, and manual play of the trade panel in the window.

## Traversal and local co-op — 2026-09-30

- Debug suite: **103/103 tests pass**. New tests cover the controller (buffered versus dropped early jump, stomp bounce, roll collider height, climb gate and mantle onto a 3 m block, grapple zip to a static anchor, glide, triple-tap hover). They also cover co-op proximity sensing, split-screen tiling, and the four-player Sandbox acceptance. In that acceptance, three guests join, P1 stays put within 0.05 m while P2 walks, P3 strafes and P4 turns 2.8 rad, all four bodies are published with owner tags, and P3 presses the powered-door button and the door opens. A guest then leaves, and the save contains no guest data but loads with guests beside P1.
- The previous controller commit had broken three existing acceptance tests (the crate carry, the powered door, and the third-person character). Walking into the crate row or the closed door started a climb over it. Climbing now starts only from a jump into a wall; all three pass again.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: players went 1 → 4 → 2 → 1. Views 2–4 each created their own streaming pool (49 CPU / 25 GPU chunks) once. There were no validation errors and the exit was clean (code 0). P2 walked under its own input while P1 flew to the far Arbors. The rover displacement (1.3 m) matches the pre-change build on the same run (1.2 m).
- Single-view streaming benchmark after the change, ReleaseSafe, **900 measured frames**: render CPU P50/P99 **0.805/1.085 ms**, interval P99 20.976 ms. Peak upload was 284,204 B, peak residency 25 chunks, with zero underfilled frames and unchanged pool allocation counts (2 CPU, 50 GPU).
- Not measured: split-screen CPU/GPU cost as a benchmark, a physical controller test (no pad was attached to this machine; the pad path is covered by the `Gamepads` unit test and the same `Input` route the guests use), and a manual visual review of the split layouts.

## Canopy district milestone — 2026-09-30

- ReleaseSafe suite: **95/95 tests pass**, including all existing ramp, machine, sap, physics, streaming, and asset tests. The application compile check passes.
- District generator v1 reproduces its six-node layout across five tested seeds. Solver tests reject invalid anchors, duplicate/reversed spans, excessive grades, trunk collisions, disconnected graphs, road crossings, and insufficient terrain clearance. Junctions reserve room for trunk spurs and market bays.
- Movement acceptance uses the real fixed-step Sandbox and collision: the player walks **0 → 1 → 2 → 3 → 4 → 5 → 0** without falling below the road, and a machine-powered rover drives that same loop without resetting its pose between roads. Every plaza is reached; the rover stays upright and the player exits onto the deck. Additional walks cover both complete trunk-ring plazas and their spurs, plus a newly constructed **0 → 3** bridge through both plaza seams.
- Construction tests place and settle a rover on an elevated plaza, reject unsupported edge placement, select two visible bridge anchors, commit/cancel/remove, and preserve endpoints and collision through save/load. Invalid bridge deltas leave the session unchanged. Allocation-failure injection exercises each allocation during bridge restoration and verifies cleanup and preservation of the old bridge and session.
- Native Apple M3 Pro / Metal run with `MTL_DEBUG_LAYER=1`, ReleaseSafe, **500 frames**: completed with no validation errors, 635 simulation ticks, 681 submitted objects at completion, powered lamp lit, rover displacement 3.2 m, sap demand/supply 300/150 W (50%), bridge preview rendered, and bridge **0 → 3** rebuilt through a 38,074-byte in-memory save. User save files were not touched. This is runtime validation; visual art-direction review remains outstanding.
- Existing narrow-Arbor canopy benchmark, with the district resident: **300 measured frames**, 60 warm-up frames, ReleaseFast. Render CPU P50/P95/P99 **0.877/1.009/1.084 ms**; presentation interval P99 **20.983 ms**. Fourteen chunk crossings, 95 uploads, 70 evictions, peak 25 resident chunks, zero underfilled frames, and unchanged fixed pool allocation counts. All benchmark checks passed. This measures renderer CPU submission and presentation intervals, not GPU execution time or city simulation performance. Report: `.tools/city-canopy-benchmark.json`.
- New saves use format **7**, content **5**, district generator **1**; old formats/content are rejected. One district and three Arbors remain resident. Runtime woody grafting/growth, city streaming, traffic, trading, and manual visual review remain future work. The original test-Arbor entrance keeps its 10% bridge; the new district roads enforce the 6% limit.

## Team saves: every player on their own — 2026-10-10

- **What changed:**
  - personal progression moved from the shared `Progress` into a per-player `Kit` (wallet included);
  - save format 13 stores every known player, and format 12 migrates into P1;
  - each save writes a ranger file per player;
  - FOUR PLAYER SETUP can seat any saved ranger;
  - pets became per player;
  - guests can meet heroes, free pets and pet any pet;
  - the setup screen widened to show each seat's character and scrap.
- **Tests:** **371/371 pass**, plus the app check.
  - Updated to the new rules: a guest trades from their own wallet and fires their own blaster.
  - The four-player test now checks that P4's kit and character survive a save and load after P4 leaves.
  - New: kit purchases and round-trips, team progress with format 12 migration, save members (duplicate slots rejected), and ranger files.
- **A bug the tests caught:** saving read each seat's profile through a by-value accessor, so the saved name was a slice into a temporary. `profileOf` now returns a pointer.
- **Smoke:** the Metal-validated ReleaseSafe smoke passed every stage. The new `Smoke team` line read: each player's kit restored to their seat=true, P2 ranger file round trip=true. That run was throttled (2,175 ticks).
- **Capture:** `-Dshowcase=54` first showed seat names overlapping the pad status in the 400-unit panel. The party panel is now 560 wide, with columns for character, scrap and pad.
- **Not checked:**
  - LOAD NEXT SAVED RANGER by hand, with real files and controllers;
  - two seats playing the same ranger file. It is prevented only among present players, and a second team could still diverge a file: the last save wins.

## Pets and armor detail — 2026-10-10

- **Captures reviewed and fixed:**
  - The armor lineup (`-Dshowcase=16`, `17`) showed a dark band on every jaw that read as a beard. It was the cel shadow on downward-facing jaw normals; faces now shade from a smoothed sphere.
  - The suits read as plain bodysuits. They now have distinct palettes, lit strips, cops, buckles, headsets, collar rings, core lights and power packs.
  - Pet captures (`58`, `59`): the moth's and falcon's wings were edge-on from the front, and are now pitched to face the eye. The moth's wings sat dark in their own shadow and now glow softly. The lineup moved to the open meadow, clear of spawn crates and buildings.
- **Tests:** **370/370 pass**, plus the app check.
  - New: pet levels and damage; spots on the ring and apart; every species follows, then attacks a trooper until it falls (and the moth mends); puppets use their part meshes and the golem stands tallest; the pet save round-trips and rejects unknown or unfreed pets; suits carry lit strips and a back pack standing off by suit; jaw normals.
  - The old test-only `Companion.zig` is removed; `Pets` replaces it.
- **Smoke:** the Metal-validated ReleaseSafe smoke (300 frames, 395 ticks) passed every stage. The new `Smoke pets` line read: freed GARU=true, followed within 1.8 m, fought a trooper down and learned=true.
- **Not checked:**
  - hand play: pet pacing next to a running ranger, attack readability in a big fight, and swapping pets by petting;
  - pets on bridges and in caves (the ground lookup takes the deck below, but this is untested);
  - the frame cost of up to five puppets (about 40 props each).

## Nature pass: ground, water, foliage and footing — 2026-10-10

- **What changed:**
  - terrain, foliage and water have their own shading stages (`terrain.wgsl`, `foliage.wgsl`, `water.wgsl`), spliced onto the scene shader's shared prelude;
  - the mountain panorama and caves are shaded as terrain (they had shown the props' checker);
  - boulders are added as new scatter candidates, and snow thins and frosts plants;
  - rivers can be waded and swum; snow, marsh and sand change footing;
  - footsteps are voiced by the ground, with new `crunch` and `splash` sounds.
- **Tests:** **364/364 pass**, plus the app check. New tests cover:
  - footing kinds from cover;
  - the river surface over its channel;
  - boulder meshes (closed, outward normals, sunk) and placement (IDs above the old candidates, sizes, all shapes);
  - runner speed on grass, snow, marsh and in shallows, and the longer slide to a stop on snow;
  - wading, then floating into a swim, then walking out;
  - ground-voiced footfalls and the fall-in splash.
- **Smoke:** Metal-validated ReleaseSafe smoke runs (`MTL_DEBUG_LAYER=1`, 300 frames) passed every stage with the three new pipelines. The first ran 399 ticks; the final run was throttled by macOS (8,062 ticks) but clean.
- **Mach WGSL compiler, newly hit:** `reflect` is unimplemented (written out as `reflected`), and `patch` is reserved.
- **Captures** (`-Dshowcase=36`, `41`, `42`, `48`), reviewed and retuned:
  - River water at grazing angles washed out to grey stripes. Fixed: the reflection is bluer and capped, and ripples are gentler and fade with distance.
  - Meadow colour patches were too strong; they are now subtler.
  - The mountain panorama showed the props' checker. Fixed: the landscape meshes use the terrain stage.
  - Stone strata aliased into moiré on the distant ranges and striped the low riverbanks grey. Fixed: bands fade by 260 m, and low steep ground stays earthy.
  - Close up, the strata were too regular. Each bed now has its own tone and crack.
  - Final captures show clean snow caps, earthy banks, natural rock beds by the cave mouth, and soft meadow grass.
- **Frontier benchmark** (window visible, before the cheaper ground lookup):
  - presentation p50/p95 **20.84 / 21.01 ms**, unchanged;
  - render CPU p50/p99 **2.35 / 3.83 ms**;
  - simulation p95/p99 **3.57 / 4.07 ms**: p99 is just over the 4 ms budget, so `simulation_step_budget` failed.
  - `Sandbox.surroundings` then stopped taking five extra height samples per player per step and reuses the terrain sample's normal.
  - Two reruns after that were throttled (presentation p95 above 1.3 s), so the effect is **not yet measured**.
- **Not checked:**
  - the wind sway and water motion in a live window;
  - GPU time of the new stages (the pinned Mach has no timestamp queries; presentation did not slow);
  - hand play of wading, swimming and snow footing.

## GPU skinning and the air-war budget — 2026-10-10

- **GPU skinning (phase 14 slice 2):** characters are skinned in a vertex stage (`render/skin.wgsl`) from a per-character dual-quaternion palette; see the [plan](plans/skeletal-animation.md). The skinned module reuses the scene shader's fragment stage. `-Dcpu-skinning` keeps the CPU path. The GPU and CPU captures of `-Dshowcase=49` look identical.
- **Air war:** terrain ray casts march adaptively (stride from the terrain clearance, 5 cm to 6 m, then 14 bisection steps) instead of a fixed small step, and the wasps' structure check casts against objects only (the terrain check already ran separately).
- **Verification:** **357/357 tests pass**, plus the app check. A new test matches GPU-style palette skinning to the CPU skin for four species in two poses (under 1e-4 m, normals within 0.999). The Metal-validated ReleaseSafe smoke (`MTL_DEBUG_LAYER=1`, 400 ticks) passes every stage.
- **Frontier benchmark** (`tools/benchmark.py --frontier --frames 600`, M3 Pro, ReleaseFast, window visible), before → after:
  - simulation p50/p95/p99: 3.55 / 6.27 / 6.72 → **2.15 / 3.57 / 3.99 ms** (budget 4 ms: now passes);
  - air war mean 2.09 → **0.11 ms** (wasps 0.63 → 0.03, air projectiles 0.68 → 0.04);
  - character skinning p50/p99: 0.86 / 2.05 → **0.08 / 0.15 ms**; character prepare p99 **0.19 ms**;
  - render CPU p50/p95/p99 **2.56 / 3.83 / 4.48 ms**; presentation interval p95 20.94 ms.
- The largest stages are now physics (0.79 ms mean, 1.82 max) and Hive AI (0.29 mean, 1.00 max); p99 sits just under budget, so either can push it over as content grows.
- A run with the window occluded or the screen locked is throttled by macOS (presentation p95 above 1 s) and fails `presentation_unthrottled` and `active_ring_covered`; keep the window visible when benchmarking.

## Controller weapons, controller start and scrolling GUIs — 2026-10-10

- **Right trigger and right bumper:** the energy gun and saber were routed correctly in code, but the installed `zig-out/bin/heavy-water` dated from Oct 5, before the Oct 6 controller change; `build run` and tests never reinstall it. It is reinstalled now. A new test drives a raw controller sample through the real mapping and P1 routing into a full Sandbox step: the right trigger fires energy-gun bolts and the right bumper swings the saber. P1's pad weapon routing is now one shared function (`Sandbox.padWeapons`). The build doc's troubleshooting covers stale installs.
- **Starting from a controller:** Start now begins from the title and finishes the creator, as well as pausing. Menus repeat when the D-pad or left stick is held.
- **Scrolling GUIs:** panels and menus scroll when taller than the screen, following the selection, with the right stick and mouse wheel scrolling freely. The Heroes screen keeps its natural layout at small widths instead of overlapping.
- **Verification:** **356/356 tests pass**, plus the app check. New tests cover canvas scrolling (follows focus, stays within the content, no scroll when it fits, hits shift with content) and the held D-pad.
- **Captures:** `-Dshowcase=56` (Heroes at 150%, scrolled to BACK) and `57` (pause menu at 150%, scrolled to its last item).
- **Not checked:** a hand pass with a physical controller (repeat timing, stick thresholds) was not possible in this session.
- **Review pass, the same day:**
  - The baseline was 353/353 tests and the app check, with a clean Metal smoke.
  - The three newest commits (armor coverage, controller intro weapons, fast travel) read correctly. Fast travel searches for a safe, unoccupied arrival (mesh colliders included) and changes nothing when none fits.
  - The frontier benchmark fails `simulation_step_budget`: simulation p95 6.27 ms against 4 ms, mostly the air war (2.1 ms mean: wasps and air projectiles). Character skinning p99 is 2.05 ms and render CPU p99 3.26 ms.
  - Long smoke runs while the window is occluded log tens of thousands of ticks (macOS throttling); unlocked, focused reruns log about 390.

## Review, Wildkin heroes and the Starbowl — 2026-10-05

- **Project review baseline:** 331/331 Debug tests, the app check, and the Metal smoke all passed before any change. The review read the most recent and riskiest changes (controller HID bridge, presets, rigid-body pairs, flight collision, menus). Issues found and fixed:
  - **Phantom pads:** `gamepad.m` matched HID devices to GameController pads by manufacturer against `vendorName` (which holds the device name), so a supported pad could appear twice, as two players. It now asks `GCController.supportsHIDDevice` (macOS 11+), with a product-name fallback.
  - **Stuck triggers:** on HID pads whose right stick reports on Z/Rz (0–255), those axes were also read as triggers, about 0.5 at rest and above the 0.15 threshold, holding sprint and fire down. Z/Rz are now triggers only when the pad has separate Rx/Ry axes.
  - **Off-thread dialogs:** preset export/import ran `NSSavePanel`/`NSOpenPanel` on Mach's app thread, but AppKit requires the main thread. They now run synchronously on the main queue.
  - **Preset string ownership:** `PadPreset.parse` could return strings aliasing the input buffer, which `loadSlot` frees first. It now always copies (regression test added).
  - **Flag limit:** `Progress` kept at most 48 story flags and silently dropped the rest; nests, carriers, caves and conversations can exceed that. Raised to 96 (test added).
  - Untyped HID name properties are type-checked before use.
  - **Noted, not changed:** `SuperMobility`, `Companion` (since replaced by `Pets`) and `QuestLog` logic exist but are only referenced from tests (the quest log screen draws from `QuestLog`, but nothing drives the other two in play). The rigid-body pair contacts and character rigid floors read correctly.
- **After the expansion:** **340/340 tests pass** (Debug), plus the app check.
- **Metal smoke** (ReleaseSafe, `MTL_DEBUG_LAYER=1`, 300 frames, unlocked, 391 ticks): `Smoke heroes: met ROOK BANDIT joined=true, played as them=true, powers used 3/3; arena entered=true wave 1 bots 2, cleared and paid=true, left=true`. Every other stage was unchanged and there were no validation messages.
  - An earlier run of the same build logged 71,259 ticks because the window was throttled during a long run; an immediate rerun with the screen confirmed unlocked logged 391.
- **Debug launch:** the Debug executable starts and builds its background meshes.
- **Captures:** `-Dshowcase=48` to `53`. Fixes from looking at them:
  - The first lineups showed dark bodies (the human undersuit covered the fur); Wildkin now wear a bright tank and shorts.
  - The lineup was wider than the view.
  - Long hero names overflowed their cards.
  - The arena floor was blown out white.
  - The scorpion's tail curled down instead of arching over its back (bend sign for a backward chain).
- **Not done or not measured:**
  - power balance and arena difficulty by hand;
  - guests choosing heroes from their own pads (the Heroes screen assigns any present player from P1's input);
  - per-form animation (tails and wings are rigid);
  - faces under snouts and beaks are simple;
  - the Starbowl has no boss;
  - cost of 32 skinned characters at once.

## Mountain ranges and cave dungeons — 2026-10-02

- Debug suite: **288/288 tests pass** (about 3.5 minutes). New tests:
  - **Ranges:** clear of the hub, peaks over 120 m, nothing added on river centre lines.
  - **Panorama:** below the real ground and facing up.
  - **Cave layout:** an open mouth; chambers under at least 7 m of rock; hollow above every chamber floor and solid below; the heart no higher than the mouth; deterministic.
  - **Cave mesh:** a ray down from each chamber finds an upward floor within 0.6 m of its floor height, and every covered chamber has a ceiling.
  - **Mouth coverage:** the cave mesh covers every dropped heightfield sample at the mouth. It first covered 95 of 105; ground quads that only touched the hole were being dropped, and are now kept.
  - **Walk-in:** the full Sandbox walks a player through the first mouth. The player stays under the slope, stands on the floor of the first chamber, and sets `cave_0_found`; the collider is built on approach.
- **World generator version 5:** saves from version 4 are rejected because the terrain changed. The Save, Enemies and nest-count tests were updated for this.
- Native Metal smoke, ReleaseSafe, `MTL_DEBUG_LAYER=1`, 300 frames, unlocked screen, 394 simulation ticks:
  - `Smoke caves: 6 cave systems in 4 ranges (highest spine ground 287 m), 6 meshes ready; walked in underground=true grounded=true 60.9 m under the slope, 1 colliders built`.
  - The frontier stage now reports 9 nests and 114 pickups.
  - No validation messages.
- Captures (`-Dshowcase=41` to `44`):
  - **Fixes from review:** the first captures had snow down to the cave mouths, so the range snowline was raised. They also showed a ragged hole around the mouth (the coverage bug above). The far panorama's edges were grown onto the foothills.
  - **Now:** snow-capped ranges on the horizon from the foothills. A dark mouth with a rock rim. A cave chamber with rough walls, a tunnel onward and crystals. The heart chamber's nest, whose troopers engaged the player.
- **Not measured or open:**
  - the added cost of mountain sampling in every terrain query, and of cave tests in rays near the ranges (no benchmark run);
  - collider build time on approach (a hitch, once per system);
  - mouths on gentle flanks read as slots rather than arches;
  - the sun still lights cave walls;
  - the panorama's far edges show as thin outlines against the sky beyond the streamed terrain.

## Fighting, energy firearms and classes — 2026-10-02

- Debug suite: **282/282 tests pass** (about 3 minutes). New tests:
  - The rig's hand sweeps across the front through a forehand and comes forward to aim.
  - A cut hits a trooper exactly once (forehand + backhand damage to 0.01), a mid-cut press queues the backhand, a full hold releases a charged wave, and the guard parries for 0.3 s and then blocks.
  - Blades cut each unit once per swing with knockback and stun; guards turn bolts into `deflected` events.
  - A sniper beam pierces exactly one unit and scopes to 0.3×; a bazooka orb bursts and stuns the unit beside its target.
  - Firearm rhythms: machine gun 13–15 shots a second until it overheats, sniper steadiness, heavy-rifle charge, bazooka detonation.
  - Specials: overshield soak, refusal while cooling down, grenade burst and stun, sentry zaps, phase-dash blink and stun, slam throw, lance damage and cast pose.
  - The profile class round-trips and defaults to Ranger for older documents. An old settings file with culling on C loads with special 2 moved to F7.
- Fixes found while testing:
  - The machine gun fired 12 a second, not 14, because the cooldown clamped to zero inside a step. It now carries the remainder.
  - Piercing shots hit the same unit again because they resumed inside its sphere; they now skip the unit slots they have passed.
  - The combat showcases first took the existing river viewpoint `-Dshowcase=36`; they are now 37–40.
- Native Metal smoke, ReleaseSafe, `MTL_DEBUG_LAYER=1`, 300 frames: `Smoke combat: saber and sniper made=true, saber cuts=3 trooper health 1616 stunned=true, sniper pierced=true, grenade burst=true, slam threw=true`. Every other stage was unchanged, with no validation messages. That run, unlocked, took 394 simulation ticks. Reruns after the screen locked took about 6,330, because macOS throttles presentation and each frame catches up more fixed steps; their results were otherwise the same.
- The Debug executable starts and runs, with no stack overflow from the new module state.
- Captures:
  - `-Dshowcase=37`: the forehand cut and overhead raise with blade trails, the blade leaving the right hand.
  - `-Dshowcase=38` and `40`: the first-person rifle and the lumen lance from the hand. The beams were first far too wide near the camera and were narrowed.
  - `-Dcharacter-showcase=5`: a Synthetic with lit eyes, collar, core and cheek seams. The cheek seams can read as tear streaks; art direction is yours.
- Not measured or checked by hand:
  - feel and balance (damage, energy, cooldowns, lunge strength);
  - the guest controls on a real controller;
  - the cost of posing a rig per armed player per step (one skeleton pose each, plus three per step while swinging);
  - the held weapons and slam or lance effects are block-and-gem placeholders.

## Debug executable stack overflow — 2026-10-01

- **Report:** running `zig-out/bin/heavy-water` (a Debug build) crashed at startup with a segmentation fault in Mach's `Modules.init`, at a stack address.
- **Cause:** Mach's entry point keeps every module's state by value on the main thread's 8 MB stack, and its `init` copies each module through a local. The overlay's inline vertex array (raised to 120,000 vertices for the GUI, 2.9 MB) sat inside the Renderer's state, so Debug builds, which keep those copies, overflowed. The smoke runs had all been ReleaseSafe or ReleaseFast, so they missed it.
- **Fix:** the overlay's vertices are now allocated on the heap when the renderer starts. A test caps the module-state sizes the suite can see (Sandbox under 1 MB, World under 256 KiB, Overlay under 4 KiB, Canvas under 256 KiB).
- **Verified:** the rebuilt Debug `zig-out/bin/heavy-water` starts, loads mods, opens audio and Metal, and runs for 25 s at the title screen. **270/270 tests pass.**
- **Follow-up:** run at least one smoke in Debug after state-size changes.

## Focused review: flight, air war and frontier — 2026-10-01

Review of the flight, air war, combat, garage and frontier code since the vehicle work began. Findings and outcomes:

- **Fixed (high):** a Kestrel left mid-flight kept its throttle and flew on unpiloted. Empty jets now cut the engine and let the lift jets lower them onto the gear. Test: a jet left at 30 m and 40 m/s settles onto its gear.
- **Fixed (medium):** the gear springs balanced at about 1 m of penetration, so parked jets rested on the hard-floor clamp rather than the gear. Each leg now carries a third of the weight at 10 cm. The same test checks the rest height.
- **Fixed (medium):** a shot could register on a carrier's launch bay even with a wasp nearer along the line, because the bay's 4 m allowance applied against any nearer hit. It now applies only past that carrier's own hull hit. Test: a wasp between the gun and a bay takes the shot, and the carrier is unharmed.
- **Fixed (low):** a stray no-op statement in `Frontier.stepSkies`.
- **Open (low):** a missile locked on a ground Hive unit tracks its slot index; if the unit dies and the slot is reused, the missile homes on the newcomer. See [next steps](plans/next-steps.md).
- **Open (docs):** the save-format description was stale (v10, without progress, cars or the fighter); it is rewritten in [architecture](architecture.md).
- **Checked, no change:**
  - The HUD projection's basis matches `Camera.move`'s right vector, and the up vector is forward × right. A capture with a live lock is still needed to confirm the reticle's side.
  - Wasps keep thinking after their carrier sleeps; with analytic avoidance that is bounded (14 at most).
  - Guests are in the wasps' target list with matching player indices.
- **Debug suite: 269/269 tests pass.**
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300 smoke frames: no validation errors, clean exit; frontier and flight stages passed (Kestrel fabricated, lifted off, wasp downed).

## Flight: the Kestrel and the air war — 2026-10-01

- Debug suite: **267/267 tests pass**. New tests:
  - **Flight:** a vertical takeoff from the gear on the lift jets; wingborne cruise holding altitude at −4° to 10° angle of attack, with the top speed under 300 m/s; mouse-aim turns to a 90° aim and levels the wings; an afterburner climb; crash damage; a hangar test that takes off, transitions and flies.
  - **Ship meshes:** they build at their intended lengths, and the Kestrel's fuselage and fins are closed solids.
  - **Air war:** carriers launch wasps that attack, hit the jet and draw flak; cannons down a wasp; a locked missile damages a carrier.
  - **Fabricator:** the Kestrel recipe.
- **Found and fixed:**
  - **Climb:** at 48 kN the fighter bled from 150 to 78 m/s in a turn-and-climb. Thrust is now 58/95 kN (about 0.9 thrust-to-weight).
  - **Cruise angle of attack:** a fast cruise on the cambered NACA 2408 wing sits just below zero incidence, so the test range was corrected.
  - **Fin winding:** the lofted fin was inside out (volume −0.28).
  - **Hover transition:** hover drift-bleed fought the engine and capped the jet near 24 m/s, at the lift jets' handover. It now bleeds only sideways drift while the engine pushes.
  - **Wasp cost:** each wasp cast a 120–170 m ray every step. A test sat at full CPU for over 11 minutes and the game would have paid it every frame. Avoidance is now analytic terrain samples plus a short structure ray every fourth step, and the suite is back to about 2 minutes.
  - **Air war placement:** carriers now circle beyond the nests and wake within 650 m, so the air war stays over the Hive's ground.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke flight` fabricated the Kestrel through the panel, lifted off, and downed a wasp with the cannons; carriers were at 264 m and 326 m. The first run reported no wasp downed because the smoke placed the wasp along a level line from the pad into rising ground; it now aims into open sky.
- **Captures:**
  - `-Dshowcase=33`: the Kestrel on its pad.
  - `-Dshowcase=34`: the Kestrel banking hard on afterburner beside a Brood carrier, with wasps in formation and the second carrier distant.
- **Not measured:** flying by hand, missile play, jet–ship collisions (not implemented), and frame cost with 12 wasps and two carriers awake.

## Guest weapons, Hive troopers, saved cars — 2026-10-01

- Debug suite: **258/258 tests pass**. New tests:
  - Troopers march out of a nest, stay on the ground, and hunt.
  - Saved car positions and headings round-trip, unowned designs stay absent, and collected pickups stay collected.
  - A guest fires the party's blaster with the trigger through `Sandbox.step` and downs a drone.
  - The combat tests now run per arsenal; a shield raised by any player absorbs.
- Two first versions of the guest test failed on placement, not code:
  - The drone sat under the slope along the guest's pitched aim.
  - The shot met the crate row beside the spawn.

  The debug traces showed the shot flying true, so the test now levels the aim and uses a nearer drone.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames** (screen unlocked): no validation errors, clean exit. `Smoke frontier` fabricated a car and a blaster, the car flew 19.5 m, and the drone went down; four-player stages ran with guest arsenals.
- **Captures:**
  - `-Dshowcase=32` (in flight) shows the Skimmer cruising 7 m over the terrain toward the city. Flown straight ahead, it stopped at a wall as designed.
  - `-Dshowcase=30` shows troopers in Hive plate advancing beside drones and a sentinel. The player lost 65% of their health in about 2.5 s standing still, so bolt damage was lowered and the spread widened; bolts are thinner too.
- **Not measured:** difficulty by hand, controller play, and skinning cost with eight troopers near P1.

## Frontier: hover cars, pickups, fabricator, the Hive and weapons — 2026-10-01

- **Generator code:** your vehicle generator modules (`hull`, `airfoil`, `prims`, `fan`, `nozzle`, `dynamics`) were added with their imports pointed at the character core. Their tests all passed the first time. The paste ended partway through the `dynamics` tests, so the energy test and a torque-direction test were finished here. `hover.zig` and `car.zig` were not in the paste and are written for this game.
- Debug suite: **255/255 tests pass**. New coverage:
  - **Vehicle geometry:** watertight hull, wing, fan and nozzle meshes; NACA and Helmbold values; the isentropic area ratio; closed-form box inertia; torus volume; energy-conserving torque-free spin.
  - **Hover:** momentum theory and its inverse; ground effect; lift shares balanced about an aft COM; settling level at ride height; cruise and boost caps; rolling hills at 45 m/s without touching; altitude hold over gaps; wall stops.
  - **Garage:** a built car hovers, all three designs lift themselves, and a car parks, is boarded, flown and left.
  - **Pickups and fabricator:** deterministic placement covering every kind; collect-once; drop expiry; recipes paid exactly and made once; first weapons alloy-free.
  - **Hive:** nest sites away from landmarks; dormant nests; woken nests spawning units that hunt, shoot and hit; strikes downing units and nests; a destroyed nest stops spawning.
  - **Combat:** weapon selection and cycling; a blaster shot destroying a drone; the saber cutting only in front; shield absorption; regeneration; restoring a downed player; health from vital cells.
  - **Saves and screens:** progress round-trips with inventory, picked IDs and owned cars, armor and weapons, and every screen, including the fabricator, lays out inside the window.
- **Fixed during the work:**
  - **Momentum theory:** four 0.6 m fans at 60 kW lift only about 7 kN; a 1.1 t car needs about 280 kW per fan, so fans now have 300 kW.
  - **Aft COM:** the COM sits 0.42 m aft, so equal lift per fan pitched the car up and it drifted backward. Lift is now shared by lever arm, plus a trim integral.
  - **Glow-mesh leak:** a glow mesh leaked when the catalog failed partway through; the allocation-failure test caught it.
  - **Top speed:** boosting reached 91 m/s; drag now includes fan ram drag.
  - **Ground loss:** at speed, a pad dipping into a slope lost the ground (its ray started underground) and the car sank. Rays now start 2 m up, there is a 0.9 s look-ahead probe and a hard keel floor.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke frontier` fabricated a Skimmer and a blaster through the panel, the car flew 19.5 m in 2 s, and 3 nests and 62 pickups were placed. That run reported "drone downed=false" because the smoke gave the drone 30 health against a 22-damage shot; the test was corrected to 15. This smoke ran before the hover floor and drag fix, the sound cues and the new dialogue.
- **Not re-run:** the screen locked partway through, so later smoke and capture runs could not render (`CGSSessionScreenIsLocked`; the app idles in its event loop). Re-run `-Dsmoke-frames=300` under Metal validation and the `-Dshowcase=29..32` captures once the session is unlocked.
- **Visual review** (`-Dshowcase=29..31`): the three cars hover on their pads with light strips and wings; the nest spire glows, drones and a sentinel hunt and fire red bolts, and the player's health drops; the fabricator panel shows tabs, cost chips and inventory. The first flight capture showed the 91 m/s top speed and the ground loss, both fixed above.
- **Not measured:**
  - frame cost of the Hive and the hover probes at full load;
  - flying the car by hand;
  - guests' weapons (not implemented);
  - listening to the new sounds.

## Audio — 2026-10-01

- Debug and ReleaseSafe suites: **216/216 tests pass**. New tests:
  - Synthesis: every sound is finite, audible and peak-limited, generation is deterministic, and loops join without a jump.
  - Mixer: one-shots end, pan, respect muted buses, and steal voices oldest-first; loops fade smoothly; a full ring drops commands.
  - Director: each event sounds once, the first frame only starts loops, guests are attenuated and panned, dialogue blips, and a paused world stays quiet.
  - Volume settings clamp and round-trip.
- A ReleaseSafe smoke crashed with an integer overflow on the CoreAudio thread on its first callback. The cause was `@min(chunk, frames - done)`: with a comptime bound of 256, Zig narrows the result to `u9`, so `n * 2` overflowed at 512. The fix widens it to `usize`. Debug had not tripped it in the runs tried; the mixer's own ReleaseSafe tests passed because they never went through the device path.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames** with audio on: CoreAudio at 48 kHz stereo f32, no validation errors, clean exit, every stage including four players and the GUI pass.
- Levels from `zig build sounds`: interface sounds around −10 to −16 dBFS RMS, effects around −13 to −17, loops around −13 to −19 before their gains. In the mix, the canopy pad sits near −26 dBFS under footsteps near −20.
- Not measured: listening (nobody has heard it yet; the WAVs are for that), latency, behaviour when the output device changes mid-session, and CPU cost on the audio thread.

## Guest HUD and rebindable controls — 2026-10-01

- Debug suite: **212/212 tests pass**. New tests:
  - Bindings swap conflicting keys, refuse reserved keys, and round-trip by name, ignoring unknown names.
  - The controls screen captures a key, swaps conflicts, cancels with Escape, and resets.
  - Settings round-trip with a rebound key.
  - The screen layout test now also draws a four-player split screen with a guest trading.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**, including four players with the new guest HUD: no validation errors, clean exit.
- Visual review: `-Dshowcase=27` (four players, P3 at Maro's stall) and `-Dshowcase=28` (controls while rebinding). Two fixes came from it:
  - Ware names showed underscores in the guest stall panel.
  - The interaction prompt showed through behind the pause menu.
- Not measured: rebinding by hand in the window, and controller play.

## Menus, GUI and conversations — 2026-10-01

- Debug suite: **210/210 tests pass**. New coverage:
  - Canvas wrapping, hits and measurement.
  - Scaled overlay text.
  - Menu navigation: disabled CONTINUE and LOAD are skipped, sub-screens return to their entry, quit is confirmed.
  - Settings clamping, round trip, and per-field clamping of a wild value.
  - Dialogue: the built-in file validates, branches follow flags, a gift is given once, panels end the conversation, and malformed data is rejected with a reason.
  - Purchases: upgrades and suits change nothing on failure, and progress round-trips, including shorter level lists from older saves.
  - Creator skips clothing that is not owned.
  - The Sandbox stall test now greets Maro and opens trade from his reply.
  - Every screen and every conversation node lays out inside a 1280×720 canvas.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke GUI` drives pause → settings → resume (closed), Maro's first greeting into the upgrades panel, buys fuel tank level 1, and closes every panel.
- Visual review from `-Dshowcase=18..26` captures:
  - The clock overlapped the scrap count: the wallet panel is wider.
  - The vitals panel overlapped the dialogue box: vitals hide under panels.
  - The player blocked the keeper: the conversation camera is now over the shoulder.
  - The wardrobe panel covered the character: it moved to the left and narrowed.
- A code review then found eight hardening items, all fixed:
  - Clicks are limited to the top layer.
  - Load failures show on the title screen.
  - Settings are written once on leaving their screen.
  - Upgrade levels are saved as a list, so adding an upgrade keeps old saves loading.
  - A wild settings value clamps instead of resetting every setting.
  - Purchase errors are worded for players.
  - Number keys only pick existing replies.
  - Fixed limits now follow the content: the clothing mask, the reply line buffer, and pedestrian conversations picked in file order.
- Not measured: manual play with a physical controller, split-screen GUI for guests (P1 only), and art-direction approval of the screens.

## Character generator and sci-fi armor — 2026-10-01

- The user-supplied procedural character generator (`src/character/`) replaced the block avatar for players, guests, pedestrians and stall keepers. Three new clothing types (exo rig, hardsuit, vanguard) are built from eight hard-surface armor coverages.
- Debug suite: **195/195 tests pass**. New tests:
  - Every armor vertex is rigidly bound to one joint.
  - Armor vertex counts grow exo rig < hardsuit = vanguard. The vanguard cuirass stands further from the chest than the hardsuit's, and the exo rig has none.
  - Two forearm plate vertices keep their distance within 1e-4 m through a walk pose.
  - Segment gaps split a span continuously.
- Fixes found while integrating:
  - The hair-removal index compaction used an aliasing `@memcpy` and aborted under a sealed helmet. It now uses `copyForwards`.
  - Two tests assumed block avatars, and the four-player Sandbox count also overflowed on owner-0 pedestrians. Both now count one character prop per player.
  - A heavy-armor test compared against a sealed helmet that also removes hair. It now compares like with like, and checks that the sealed helmet leaves no hair triangles.
- Visual review: `-Dshowcase=16/17` captures. Two jagged edges, on the faulds top and the cuirass bottom, followed body-region borders as stair steps. Both are now single continuous cuts across belly and hips. Art-direction approval remains yours.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, Debug, **300 smoke frames** with the armor lineup: no validation errors, clean exit.
- Not measured: CPU skinning cost with many armored characters (an armored body has about 3.5K more vertices), and a manual review of the creator cycling clothing in the window.

## Rivers, waterfalls, mountains and snow — 2026-10-02

- Seeded terrain now transitions from a smooth hub valley to ridged highlands. Exposed alpine rock and snow use elevation and slope masks.
- Rivers carve continuous channels and stream as blue world-space ribbons. Periodic seeded drops add vertical waterfall curtains; geometry is generated with each terrain chunk, including across chunk boundaries.
- World generator version is 4 because the terrain and water generation changed; saves from prior generator versions are rejected. Profile and content data are unaffected.
- ReleaseSafe tests and app checks: **276/276 pass**. New coverage checks waterfall drop height, river mesh indices, snow coloration, terrain sampling against the rendered ground mesh, and existing district/building/bridge clearances.
- Four-player native Metal smoke passed with terrain streaming, save/restore, construction and rover checks. `-Dshowcase=36` captures the river and waterfall viewpoint for visual review.

## Frontier correctness and renderer baseline — 2026-10-03

- Ground Hive missile and HUD references now include a per-spawn generation. Replacing a dead unit in the same slot invalidates its old lock instead of redirecting the missile to the replacement. Regression coverage checks slot generation increments, stale HUD lock rejection, new candidate identity, and a missile retaining its course after its target slot is reused.
- Debug suite: **290/290 tests pass**.
- Native Apple M3 Pro / Metal, ReleaseFast streaming benchmark, 600 measured frames: all checks pass. Render CPU P50/P95/P99 **5.87/6.44/6.85 ms**; 40 chunk crossings, 225 uploads, 200 evictions; peak terrain upload **299.4 KiB / 320 KiB**; peak 25 resident chunks; **0 underfilled frames**.
- This route does not stress the full frontier encounter. Simulation, 24-character skinning, and audio-thread costs remain unmeasured; the documented `--frontier` benchmark and hands-on flight/combat/audio checklist are still outstanding.

## Playtest checklist, automated smoke — 2026-10-03

- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300 frames with audio enabled: clean completion, no Metal validation messages, 395 simulation ticks. The run fabricated and flew the Skimmer 18.7 m; fabricated the Kestrel, lifted off and downed a wasp with its cannon; exercised saber, sniper, grenade and slam combat; and ran four local players through split-screen and co-op movement.
- This smoke did not fly all three car types, dogfight and land the Kestrel, exercise every firearm and guard/parry action, use a physical controller, or listen through the sound set. Those hands-on checks remain open; audio-device startup is verified, sound quality is not.

## Four-player frontier combat and performance — 2026-10-04

- `tools/benchmark.py --frontier --frames 600` now runs four local players, scripts 360 ground-fight and 390 air-combat simulation ticks, records weapon-fire and target counts, and measures simulation stages, character skinning, rendering, presentation, and CoreAudio callbacks.
- Apple M3 Pro / Metal, ReleaseFast: render CPU P50/P95/P99 **1.76 / 2.72 / 3.03 ms**; character skinning **0.86 / 1.79 / 2.05 ms**; simulation **3.55 / 6.27 / 6.72 ms**; presentation interval **20.85 / 20.91 / 20.93 ms**. Four views remained covered, with zero underfilled frames and peak terrain upload **299.4 KiB / 320 KiB**.
- Audio callback P99 was **0.197 ms**, or **1.85%** of its real-time budget. All render, character, streaming, combat-coverage, and audio checks pass. The 4 ms simulation P99 target still fails.
- Profiling isolated terrain queries in projectile raycasts as a repeated air-war cost. Airborne segments proven above the hub's conservative height bound now raycast bodies and meshes without marching the terrain; ground-level and mountain-region shots retain full terrain collision. The detailed projectile-stage mean fell from **1.37 ms** in the 240-frame profile to **0.91 ms** in its 240-frame comparison; the full 600-frame run measured **0.70 ms** mean and **2.25 ms** maximum. Wasp terrain look-ahead also reuses its samples for one fixed step.

## Balance tuning foundation — 2026-10-03

- Gathered the current encounter and balance values into named module tables: Hive stats and spawn pacing (`Enemies`), wasp/carrier/Kestrel combat (`Skies`), player damage and survivability (`Combat`, `Weapon`, `Firearms`), pickup placement counts (`Collectibles`), per-car handling (`Designs`), and Kestrel mass/camera values (`Hangar`). Fabricator recipes were already a single table; hover and jet flight parameters remain grouped in their `Config` structs.
- No numeric balance values changed. The deterministic tests and scripted smoke verify actions complete, but cannot tell whether wasps feel fair, handling is satisfying, or recipe pacing is too long. Actual balance edits remain pending the hands-on checklist above.
- Debug suite: **290/290 tests pass**. ReleaseSafe 300-frame smoke with Metal validation and audio also passed after the refactor.

## Missile lock reticle capture — 2026-10-03

- Added `-Dshowcase=45`, which stages the Kestrel above the canopy, spawns a ground drone ahead, holds missile lock, and captures the normal flight HUD. Reproduce with `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 90 python3 tools/zig.py build run -Dshowcase=45 -Dcapture-frame=120 -Doptimize=ReleaseSafe`.
- The captured frame shows the red target box and `LOCK` label on the target inside the flight view. The generation-checked lock lifecycle is covered by the 290-test suite above; the showcase verifies the reticle projection in a live render.

## Kestrel ramming and wasp spacing — 2026-10-03

- Kestrel contact uses the carrier's hull spheres and a 5 m aircraft collision radius; wasps use their 3.2 m hit radius. Impact damage scales with relative speed above 18 m/s and has a short repeat-hit cooldown. Contacts move the Kestrel clear and rebound only inward velocity. Wasps steer away inside 16 m.
- Regression tests cover aircraft separation/rebound and hull loss, deterministic close-range separation vectors, and ram damage to both the Kestrel and each target type.
- Debug suite: **293/293 tests pass**. ReleaseSafe application check passes. Native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300-frame smoke completed with all stages passing and no Metal validation messages.

## Brood carrier assault — 2026-10-03

- Carrier damage now advances through four flak turrets, four launch bays, and an exposed underside core. Cannons and lock-on missiles target the active stage's individual hit volumes; intact stages shield later parts. The flight HUD reports the nearest carrier objective, active weak points receive bright target markers, and destroyed turrets stop firing.
- Core failure starts a scripted descent with a tumbling carrier and repeated debris bursts. The carrier defeat flag and reward cache trigger when it reaches the ground; the event remains deterministic and testable.
- Debug suite: **294/294 tests pass**, including the complete turret → bay → core → impact sequence. ReleaseSafe app check passes. Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, 300-frame smoke completed with all stages passing and no validation messages.
- Visual review: `-Dshowcase=34` at frame 120 shows the Kestrel, active turret markers, and persistent `BROOD 1 FLAK TURRETS 4/4` HUD objective.

## Development asset reload (phase 13, slice 3) — 2026-10-01

- Baseline review: 159 ReleaseSafe tests and the application compile passed. Fixed index-only loader tickets that could access reused slots, checked pack indices before worker access, and replaced an unlocked telemetry read with a mutex-protected snapshot.
- Expanded suite: **165/165 tests pass** in Debug and ReleaseSafe; application compile checks pass. The final Debug run also verifies changed Wasm bytecode changes live output while a subsequent malformed edit retains the working module. New coverage includes stale loader tickets, repeated model replacement without pool growth, generation exhaustion, external glTF buffer edits, source/settings changes, unchanged-scan counters, wrong GUID rejection, missing-file recovery, staged script replacement and invalid-module recovery, live door state, locally edited machine preservation, rejected physical layout changes and resized crate colliders.
- ReleaseSafe model reload smoke: `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dreload-smoke=true -Dsmoke-frames=600 -Doptimize=ReleaseSafe`. Passed all 600 frames, including four split-screen views, machine building, in-memory save/restore, city traffic and rover driving. The isolated fixture's material changed, generation advanced 2 → 3, stale handle failed, and the GPU accepted the replacement **848 ms** after the source edit. No Metal validation errors. Initially macOS was not rendering the test window; bringing it forward allowed frame progression before the timed edit.
- Full-watch ReleaseSafe smoke (`-Dhot-reload=true -Dsmoke-frames=300`) also completed: crate, all nine built-in blueprints and the installed Glowworks script staged successfully; four-player views, building and save/restore remained functional.
- The smoke writes only an isolated fixture under `zig-out/reload-smoke`; tracked asset sources and sidecars are untouched. Physical blueprint layout edits, vehicle edits, path moves and package manifest changes require restart. Live heightmaps and generated geometry remain future work.

## Wildkin anatomy and held weapon shapes — 2026-10-11

- Added joint-bound family details to all non-human forms: mammal paws, claws and a small bib; reptile/amphibian belly bands and toe claws; bird bibs and talons; and insect/arachnid thorax and limb plates. Existing species-specific heads, tails and wings remain in place.
- Held weapons now select the shared block, gem and spike meshes for individual parts. Saber blades and selected rifle barrels use tapered geometry; grips, rails and other mechanical parts retain their block shapes. No combat damage or balance values changed.
- `python3 tools/zig.py build check` passed on the default Zig 0.16/Mach pair.
- ReleaseSafe Metal art captures for `-Dshowcase=48` and `-Dshowcase=37` completed with `MTL_DEBUG_LAYER=1` on Apple M3 Pro. No Metal validation errors appeared. The lineup capture shows new paws clearly, though the heroes face away and the busy city backdrop limits face/material review. The saber capture still reads as a straightforward energy bar; this pass does not claim a finished weapon art direction.
- Headless tests, smoke, 0.17 checks, cross-compiles, benchmarks, and Linux/Windows runtime checks were not run for this visual pass.

## Character appearance options and Scalari palette crash — 2026-10-11

- Expanded human hair choices to 24 cuts and styles, including short and long curl patterns, fades, coils, afro, locs, swept-back and shag shapes, plus oversized nova and alien crown spikes. Hair color has 14 choices, with a separate optional highlight color and automatic lumen highlights for synthetic characters.
- Added five face shapes and five boot designs to the persistent character profile and creator. Older profiles use classic face, no explicit hair highlight, and trail runner boots by default.
- Fixed the startup crash in `Ranger.suitTones`: two Scalari enemy profiles selected accent index 5 even though the palette has indices 0–4. Both now use index 4.
- `python3 tools/zig.py build check` and `python3 tools/zig.py build` passed on the default Zig 0.16/Mach pair. `git diff --check` passed.
- A ReleaseSafe Metal showcase capture was attempted for the nova spike style but did not finish compiling in the available session; no visual capture was inspected. Tests, smoke, Zig 0.17, cross-compiles, benchmarks, and Linux/Windows runtime checks were not run for this pass.

## Ground flora and canopy trees

- Scatter remains deterministic by seed, chunk and candidate ID. Generator version 3 adds sparse broadleaf, needleleaf and willow trees among grass, ferns and wildflowers. Each streamed chunk groups the new forms into instanced mesh draws; slope filters, biome thinning and stable removal IDs remain in place.
- Mesh-generation tests check the three ground-plant forms, shared trunk, and distinct canopy silhouettes; deterministic scatter coverage finds all six species across a fixed 100-chunk sample. `python3 tools/zig.py build test check -Doptimize=ReleaseSafe --summary all` passed **273/273 tests** and the application compile check.
- `caffeinate -d -u -t 60 python3 tools/zig.py build run -Dsmoke-frames=180 -Dcapture-frame=100 -Dcharacter-showcase=4 -Doptimize=ReleaseSafe` completed on Apple M3 Pro. Smoke logs confirmed four-player split-screen, streamed chunks, save round-trip, and generator version 3; frame 100 was captured at 2560×1600.

## Faces and skyline architecture

- Ranger profiles now select masculine or feminine presentation in the creator. The game bakes analytic eye, iris, brow, and mouth decals into a denser face mesh, while head and body proportions vary with the selected presentation. Legacy profile JSON without the new field defaults to masculine.
- Skyline towers add inset glass bays and open observatory crowns. District generator version 3 records the updated architecture rules. Tests assert glass detailing, deterministic placement, and district clearance. The ReleaseSafe 273-test run and four-player runtime smoke above passed with this upgrade.

## Hover racer and elevated sprint circuit — 2026-10-04

- The seeded elevated circuit uses the same generated route for its render mesh, ordered checkpoint gates, charge pads, and static physics collider. The road includes ramp grades, two mesh gaps, and a tessellated vertical loop; racers carry a finite boost capacitor that recharges over time and at pads. The garage HUD reports charge, gate progress, and lap time.
- Racer meshes add a front splitter, side intake louvers, canopy spines, and a three-fin diffuser. The course and collider raycast, checkpoint order, boost depletion/recharge, and app integration are covered by the test suite.
- Signed magnetic normal force and a track-relative attitude controller keep the vehicle aligned through the inverted crown. A regression test holds a racer on the inverted frame; loop geometry tests verify closure, crown orientation, and mesh density.
- Full Debug test suite passed. `python3 tools/zig.py build check --cache-dir .zig-cache-loop-check` passed. A ReleaseSafe 180-frame smoke run on Apple M3 Pro completed all stages, including hover-car fabrication and driving, four-player split-screen, save/restore, and city traffic.
- The smoke initializes the circuit but does not drive a complete loop at speed. Entry speed, boost timing, and sustained high-speed stability still need hands-on tuning.

## Persistent sprint-course best lap — 2026-10-05

- Save format 12 stores the best completed sprint lap, validates it as a finite non-negative time, restores it with the world, and displays `PB --` until a lap is recorded. The save document regression covers time round-trip and rejects negative values.
- Format 11 saves migrate with an empty best-lap record; earlier save formats remain rejected.
- Best laps update only when all ordered gates are crossed and the finish gate is reached. P1's explicit quicksave persists the record; split-screen race starts and separate player records remain future work.

## Gameplay menus, terrain map, and travel review — 2026-10-09

- Fast travel preserves traversal selection and suit resources, clears motion and guest interaction edges, and searches a bounded ground neighborhood for a gentle slope and full standing-body clearance. Obstructed destinations either find a nearby arrival or leave player/camera state unchanged.
- Menu Back restores the parent screen and row. Travel availability is shared by mouse hit handling and keyboard/controller navigation. Controller input remains in the menu route for the entire update that closes a menu.
- Map markers remain visible at the boundary with compass/off-screen labels; clustered labels are separated. Destination framing, three zoom levels, horizontal distance, and ground altitude are available.
- `python3 tools/zig.py build test check --summary all`: **353/353 tests passed**, application compile passed. Coverage includes obstructed and fully blocked travel, nested menu navigation, disabled travel, clustered/off-screen markers, and map layouts at 640×480, 853×480, and 1280×720 across every zoom and framing mode.
- Native Apple M3 Pro / Metal: `python3 tools/zig.py build run -Daudio=false -Dsmoke-frames=120` completed 120 frames and 199 simulation ticks, including co-op, vehicle motion, and save/restore stages.
- `python3 tools/zig.py build run -Daudio=false -Dshowcase=55 -Dcapture-frame=3`: captured and inspected the map, separated four-player labels, elevation/distance rows, and framing control. Local preview: `zig-out/map-review.png` (generated, not tracked).
- Physical controller playtest remains pending: judge jump buffering/coyote-time feel, grapple release, landings, camera transitions, and held-button behavior across menus. Automated traversal tests and scripted smoke do not establish subjective handling quality or hardware-specific input behavior.

## Character cel shading and ink — 2026-10-11

**What changed:** the GPU-skinned character path now has per-material cel ramps, the face shadow map on faces, a hard specular band and rim on armor and hair, emissive accent strips, and an inverted-hull ink outline (see [architecture](architecture.md)). `CelStyle` holds all tunables with four presets.

**Checked:**
- `python3 tools/zig.py build check` passes. `build test`: new tests for `CelStyle` (presets validate, bad values rejected, GPU table round-trips every material), `toon.shadeCel` (ramp ordering per material, hard specular on armor only, face map overrides N.L) and `toon.hullWidth` (equals `outlineWidth`, thinner on faces, zero for eyes) pass, as does the existing GPU-versus-CPU skinning test with the larger vertex.
- ReleaseSafe Metal captures under `MTL_DEBUG_LAYER=1` of `-Dcharacter-showcase=1` and `2` (scout and sentinel), before and after, with no validation messages. Ink reads on the silhouette and on armor plate edges; the ramp view (`-Dcel-debug=2`) shows lit, shadow and deep bands and a clean face terminator; `-Dcel-style=2` (Comic ink) gives visibly heavier lines.

The face mask view (`-Dcel-debug=4`, showcase 3) shows a clean vertical terminator with the nose wedge.

**Not checked:** the Watercolor and Flat presets were not captured; hair and Wildkin and beasts were not reviewed closely; four-player split-screen ink widths (the view pixel height is per view but only one view was captured); dusk and night; Vulkan, OpenGL and D3D12 (compile-only for the shared Zig, WGSL not compiled there); the 0.17 channel; benchmarks (the hull doubles skinned-character draws). Ink on thin geometry such as hair strands can look busy at distance. The CPU-skinned fallback path (`-Dcpu-skinning`) still uses the scene ramp and has no ink.

## Mecha armor sets and ShapeSpec review — 2026-10-11

- New: `character/armor.zig` (data-driven sets, `ArmorSetDef.validate`, rigid fitted pieces), `ShapeSpec` on hard garments, four sets (mobile_suit, buster, iron_titan, battle_plate), 16-bit armor ownership masks, four fabricator recipes. Saves: armor is stored by tag name, old tags unchanged, so `Save.format_version` is not bumped; Profile and Kit round-trip tests cover the new tags. A save with a new tag will not load in an older build.
- Tests: armor finite/rigid/winding/bounded for every set at two body sizes, fit test (fails if fitting is disabled; checked by mutation), shapes differ, determinism, validation errors, shell fin test, Ranger builds every armor over undersuit and hardsuit with open and sealed helmets while walking.
- Looked at: ReleaseFast Metal captures `-Dcharacter-showcase=30..33` (front only, creator panel overlaps the left). Not looked at: back and side views, women, the 0.9 and 1.1 heights visually, MTL_DEBUG_LAYER capture, extreme poses (pauldrons can sink into the chest when arms are raised, since plates bind to one joint). Linux, Windows and the 0.17 channel were not run.

## Mod character content is drawn (2026-10-11)

- **Changed:** `CharacterContent` schemas now map 1:1 to `ClumpDef`/`CapDef`, `FacePreset`/`HeadSpec`, `ArmorSetDef`/`Piece`/`ShapeSpec` and `CelStyle`, with per-key diagnostics from the real validators. `Ranger.initContent` draws a profile's mod face, hair (`HairSpec.custom`) and armor set; each character id has its own cel table.
- **Checked at integration:** `build check`, `build validate-mods` (emberwear and glowworks ok), `build test`: 407 of 412 pass on the base commit and 414 of 419 with this change; five pre-existing failures were recorded (armor suits count, asset Meta sidecar, Sandbox controller, Screens layout, Enemies nest). New passing tests cover: mod armor, hair and face change the mesh; missing mod and no registry fall back to the built-in mesh bit for bit; entries that stopped validating fall back; every struct field round-trips from JSON; about 50 bad values are rejected with file, key and code; a rejected mod leaves the registry unchanged; `sameAppearance` sees mod ids. ReleaseSafe Metal smoke (300 frames, validation layer) passed. ReleaseSafe captures `-Dcharacter-showcase=40` and `41` were inspected: flame crest spikes, Ember Eyes face, ink outlines, phoenix finned pauldrons and gold trim all draw.
- **Not checked:** `-Dcharacter-showcase=42` and `43`; split-screen with two players on different cel styles; Linux, Windows and the 0.17 channel (the dynamic offset on the cel bind group is new); palettes are listed but not drawn; the face limits in `CharacterContent.zig` are mine, chosen to contain every built-in preset.

## Creator framing and armor fit follow-up — 2026-10-11

- Merged the remaining Claude creator pass: responsive creator rows and section headers, automatic head close-ups on face/hair/helmet fields, reusable camera framing for character review captures, fitted visor placement based on the generated head, a sealed-helmet jaw guard, and small mecha plate proportion adjustments.
- `python3 tools/zig.py build check` passes on the default pinned Zig/Mach pair. The latest full headless suite passes 419/419; the initial run surfaced three test expectation/setup issues, corrected in `Meta.zig`, `Sandbox.zig`, and `Enemies.zig`, then rerun cleanly.
- ReleaseSafe Metal smoke passed 300 frames with `MTL_DEBUG_LAYER=1`. Creator face and armor captures rendered under Metal validation. Linux/Windows runtime checks were not run. Benchmark status is recorded with the follow-up results below.

## Integrated creator follow-up and refreshed frontier gate — 2026-10-11

- `python3 tools/zig.py build check`: passed on the default pinned Zig/Mach pair.
- `python3 tools/zig.py build test --summary all`: **419/419 passed**. Three test assumptions exposed by the first integrated run were corrected: importer version tracks the active glTF importer, the gun test selects the Weapon tool, and the nest test disables the independent Scalari training patrol.
- `MTL_DEBUG_LAYER=1 ... build run -Doptimize=ReleaseSafe -Dsmoke-frames=300`: passed on Apple M3 Pro / Metal, 300 frames, no Metal validation errors.
- Creator captures for a face close-up and the Battle Plate armor rendered under Metal validation. The full armor view reads clearly from the back; the large Super Flare hairstyle occludes much of the rear head, as designed. The creator panel remains visible in capture mode.
- `python3 tools/benchmark.py --frontier --frames 600`: all checks passed on the default pair, ReleaseFast, four views, Apple M3 Pro / Metal. Simulation P50/P95/P99: **2.430 / 3.337 / 3.967 ms**; character skinning P99: **0.129 ms**; render CPU P99: **4.799 ms**; presentation interval P50/P95/P99: **20.845 / 20.937 / 20.989 ms**; audio callback P99: **0.198 ms (1.86% of its real-time budget)**. Uploads stayed within budget (306,572 / 327,680 bytes), with no underfilled frames. GPU execution time remains unavailable.
- Linux and Windows runtime checks were not run. Their compile-only results are tracked separately in the engine alignment document; this follow-up did not change platform code.

## GLB skin preview and rig trace — 2026-10-12

- Added `asset-compiler preview-bind` for native Zig CPU evaluation of GLB skin weights and inverse-bind matrices, rendered to a diagnostic PNG. It supports the authored bind pose and the game's procedural run pose retargeted by compatible humanoid joint names. The resulting preview model is static and does not import a rig or animation into the game.
- Added joint names, indices, inverse-bind accessor references, and nearest joint-parent links to the GLB trace.
- Generated `assets/Characters/Test+Chroma (1).glb.meta` with the normal importer command, then ran `trace` and both preview poses. The report found one `Armature` skin with 65 joints rooted at `mixamorig:Hips`, zero animation clips, and each preview used 5,688 vertices / 10,064 triangles. Images: `zig-out/test-chroma-bind.png` and `zig-out/test-chroma-run.png`.
- `python3 tools/zig.py build` passed on the default pinned compiler. The normal `asset-compiler compile` rejects this skinned source with `SkinsUnsupported`, as intended until the runtime skin importer is implemented.
- **Not checked:** the game renderer, Metal validation, imported animated clips, root-motion handling, mesh editing, or mod installation. This is an offline asset-review tool slice, not a rigged-character integration.

## Captain mesh modifier authoring — 2026-10-12

- Added `asset/Modifiers.zig`: it splits a compiled mesh into disconnected triangle islands, assigns conservative position-based labels/surface suggestions, validates source identity and component IDs, and supports palette colors plus per-island scale/offset edits. The generated `tools/captain/Captain.modifiers.json` preserves the Captain type choice and an authored pauldron adjustment. The asset has 74 disconnected islands despite being one GLB primitive.
- `asset-compiler preview-modified` applied the Captain modifier file to both the bind pose and the compatible procedural run pose. Review images: `zig-out/captain-modified-bind.png` and `zig-out/captain-modified-run.png`.
- **Checked:** `python3 tools/zig.py build check` passed; `python3 tools/zig.py build` passed and installed the executable; the full headless target ran **407/420 passing, 13 failing**, with one reported allocation leak. The new modifier regression test passed (it is absent from the failing-test list).
- Existing suite failures observed in that run: Ranger sprint-to-run expectation; Catalog allocation-failure cleanup; Save character-content decoding; Sandbox salvage, canopy walk, bridge walk, city traffic, and Rootdeep interaction; Build circuit, bus-channel, and rover placement; Profile hairstyle wrap; Player grapple/flight fuel; Pets meadow spacing. Representative output: `expected .run, found .sprint`; several traversal assertions exceeded their step bounds; Save decode recursed through `CharacterContent.loadOne` until `InvalidCharacterContent`. These failures were not compared against a clean base revision, so their pre-existing status is unknown.
- **Not checked:** in-game Captain selection, runtime imported-rig rendering/animation, Metal validation, or mod installation. The mesh has one base-color material and no textures/UVs or semantic part names, so auto labels and eye/skin assignments need author review. Captain is available to the modifier authoring profile, not yet the playable Creator type picker.

## Third-person camera collision — 2026-10-12

- Third-person camera placement now raycasts from just outside the player capsule toward its desired position and shortens the arm before solid world geometry. This covers building, tree and cave colliders; terrain height still clamps the final camera position above open ground.
- Added a regression test with a wall collider in the camera path. `python3 tools/zig.py build check` passed; `python3 tools/zig.py build test --summary all` reported **408/421 passed, 13 failed**, one allocation leak. The new camera test passes; the same 13 failures listed above remain.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300` passed on Apple M3 Pro / Metal with 300 frames and 395 simulation ticks. ReleaseFast executable was rebuilt. Metal validation ran, but no dedicated visual capture was inspected for the camera transition.
- At the time of this camera change, the Captain modifier tool was still offline and the mesh was absent from Creator. The follow-up below connects a baked static preview to the playable selector; live skeletal animation remains unsupported.

## Captain test mesh in Creator — 2026-10-12

- Added `asset-compiler compile-modified`, which validates the GLB metadata and source hash, applies `Captain.modifiers.json`, and bakes the selected bind pose into a HWMS runtime asset. The build generates the Captain asset from the original GLB and modifier sidecar and installs it with the other compiled assets.
- Added a `CHARACTER MODEL` field in Creator. `CAPTAIN GLB (STATIC POSE)` selects the imported mesh for both the Creator preview and the player's saved character; the regular procedural ranger remains the default. The model is scaled to character height and hides correctly in first-person view.
- Save format 25 records the body style. Older profile documents default to the procedural body.
- **Checked:** `python3 tools/zig.py build check`, `python3 tools/zig.py build assets`, and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed on the default Zig/Mach pair. Builds generated the source-hash-validated, modifier-baked Captain HWMS (74 islands, 5,688 vertices) and rebuilt the installed executable. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dcharacter-showcase=46 -Dcapture-frame=120` captured the Creator and Captain on Apple M3 Pro / Metal; the imported model is clearly visible at character scale and Metal API validation reported no errors.
- **Not checked:** headless tests, Linux/Windows or 0.17 builds, and imported skeleton animation. This is a static bind-pose mesh; the source has no clips. Capture: `zig-out/capture.bmp`.

## Powered flight, jump combos, and modern UI type — 2026-10-12

- Free-flight mode now drives the visible ranger with a fast, camera-pitched flight vector through character collision. The traversal button exits to walking; keyboard toggle also lands at the current character position. The animation pitches the body from the hips and points both arms into flight. Sprint flight reaches 55 m/s; hands-off powered flight cruises forward at 28 m/s.
- Jump input now combines with dodge: forward + jump + dash launches a longer leap, back + jump performs a backflip, and the dash burst no longer replaces the jump animation. Triple forward dodges during a jump press do not accidentally enter sustained flight. Control labels state these combinations and identify the flight exit button.
- Replaced the 3×5 bitmap overlay glyphs with Mach's bundled Fira Sans, rasterized once into an alpha atlas. Text now retains lowercase, uses smooth linear sampling, and scales fractionally with the UI.
- **Checked:** `python3 tools/zig.py build check` and `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check` passed. ReleaseSafe captures for `-Dshowcase=63 -Dcapture-frame=450` (flight pose) and `-Dshowcase=25 -Dcapture-frame=120` (settings text) ran with `MTL_DEBUG_LAYER=1` and were inspected; no Metal validation messages appeared. The text capture is crisp and readable at 2560×1600.
- The final `python3 tools/zig.py build -Doptimize=ReleaseFast` reinstall passed. The control screen's gesture hint names forward+shift+jump for long jump, dash+jump for the boost leap, and back+jump for the flip.
- **Not checked:** controller handling by hand, gameplay feel for dash-jump timing, the complete smoke stages, or headless tests. The flight capture is a pose review, not a control simulation.

## Detroit road and Rootway clearance review — 2026-10-12

- Tall procedural trees now keep 26 m clear of the district road decks and plazas, without changing stable scatter candidate IDs. Spawn clearings also exclude large salvage props and trees that covered the opening workshop.
- Corrected Rootway rib orientation and widened/raised its arch so repeated cross-section ribs frame the road instead of filling the gallery. Matching collision bounds leave the passage open. Metro stop canopies no longer use plaza-level columns across traffic approaches. Salvage footprints that overlap shrine rooms are omitted from the nearby scene so they cannot cover controls.
- Bumped the district generator to 8 and save format to 24; district generators 3–7 migrate with plaza and player-bridge IDs preserved. Extended the supported save window to format 12 so the documented wallet migration remains available.
- **Checked:** `python3 tools/zig.py build check` passed; all **423 headless tests** passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=64 -Dcapture-frame=120` captured and visually inspected the Rootway gallery on Apple M3 Pro / Metal. The road is clear through the ribs, and Metal API validation reported no errors. The 300-frame Metal smoke completed all nine stages, including city traffic and save round-trip; traffic and shrine-interaction regression tests passed.
- **Not checked:** Linux/Windows runtime, cross-compilation, performance benchmarks, or the 0.17 channel in this review.

## Startup title background stability — 2026-10-12

- The title camera now holds an elevated city panorama rather than orbiting through giant Arbor canopies. Gameplay simulation, pickup collection, combat, and the day cycle pause while the title is open, so the background cannot advance or change under the menu.
- **Checked:** `python3 tools/zig.py build check` passed. A 120-frame title-menu capture ran on Apple M3 Pro / Metal with `MTL_DEBUG_LAYER=1` and was inspected; the city remains framed behind the menu and no Metal API validation errors appeared.
- **Not checked:** screen-recorded temporal flicker measurement; the local display capture interface was unavailable. The title camera and gameplay state are now held stable in code.

## Mountain Wilds farmsteads and cave sanctuaries — 2026-10-12

- Added generated cabin, field barn, and rootbound sanctuary meshes to the runtime asset catalog. Seeded farmsteads appear on the cityward approach to mountain cave mouths with low crop beds; cave cache rooms carry the sanctuary and a hue-matched signal crystal. The cave heart and Hive nest layout are unchanged.
- Cave waves still cap at four active ground enemies. Each cave rolls once for an 18% rare spawn chance, choosing a Scalari hybrid or stinger in a regular trooper slot; both reuse the existing combat, loot, XP, and rendering paths.
- **Checked:** default `python3 tools/zig.py build check` passed. ReleaseSafe showcase capture with `MTL_DEBUG_LAYER=1` (`-Dshowcase=67 -Dcapture-frame=120 -Daudio=false`) completed on Apple M3 Pro / Metal; the cabin, barn, and sanctuary lineup was inspected in `zig-out/wilds-assets-review.png`, and no Metal API validation errors were reported. `git diff --check` passed.
- **Not checked:** headless tests (not run), in-cave placement during gameplay, farm route visibility across seeds, rare-spawn probability in a playthrough, collision/entry for the buildings, hands-on cave combat, benchmarks, Zig 0.17, Linux/Windows compilation or runtime.

## Wilds map markers and recurring Scalari patrols — 2026-10-12

- The world map now marks active surface nests, cave entrances, unmet Wildkin in the Wilds, catchable wildlife not yet owned by a local player, active enemy groups, and travel points. A compact legend identifies each icon; destination names remain in the selectable list, and player markers retain their labels. The default scale includes the starting ring of surface nests.
- Open-ground exploration beyond 235 m from the starter patrol can draw a Scalari miner and scout pair near the player. The pair does not appear near a live surface nest, below terrain in caves, or more than 5 m above ground. After it is cleared, another pair can arrive after 42 seconds; an ignored pair is removed after players leave its 210 m leash for 14 seconds. The starter practice route remains in its original nest slot, so saved nest identities and arena indexing do not move.
- **Checked:** `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed on the default pinned Zig/Mach pair; the latter rebuilt the installed executable. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=68 -Dcapture-frame=120` captured the map on Apple M3 Pro / Metal; the capture was inspected, the destination labels no longer crowd activity markers, and Metal API validation reported no errors. `git diff --check` passed.
- **Not checked:** headless tests, in-game encounter cadence or balance, multiplayer sharing, Zig 0.17, Linux/Windows compilation or runtime, and benchmarks.

## Arcade Kestrel handling — 2026-10-12

- Keyboard steering now deflects the fly-by-wire aim while banking/pitch controls remain active; mouse aim remains supported. Reverse input applies a strong air brake. Shift boost drains a 2.6-second reserve, which recharges at 0.55 seconds per second when released; holding it after depletion keeps moderate engine thrust. The dodge binding starts a 0.85-second barrel roll, which absorbs flak and stinger hits and prevents ram damage to the Kestrel while preserving target ram damage.
- Updated the boarding prompt, Controls label, and flight HUD with steering, boost reserve, and roll state. Existing cannon/missile lock and release fire remain unchanged. No playable spacefighter or orbital combat scene exists yet; this pass only changes the atmospheric Kestrel.
- **Checked:** `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed; the latter rebuilt the installed executable. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=34 -Dcapture-frame=120` captured the Kestrel dogfight HUD on Apple M3 Pro / Metal; the image was inspected and Metal API validation reported no errors. `git diff --check` passed.
- **Not checked:** headless tests, hands-on keyboard/controller flight, barrel-roll animation/evade timing, boost/brake feel, Zig 0.17, Linux/Windows compilation or runtime, and benchmarks.

## CLI mesh modifier authoring — 2026-10-12

- Expanded the source-hash-linked Captain modifier document into a usable headless authoring flow. `modifier-list` exposes stable island IDs and spatial context; `modifier-edit` writes one validated change to a separate document and supports part labels, material roles, explicit colors, per-island scale/offset, and shared skin/eye/armor/energy palettes. Invalid values are rejected before output; exact same-path input/output is rejected.
- **Checked:** `python3 tools/zig.py build check`, `python3 tools/zig.py build install`, and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed on the default compiler; ReleaseFast reinstalled the game. The generated Captain is still 74 islands / 5,688 vertices. Manually listed all IDs, edited label 912, changed the armor palette and scaled that pauldron in separate output documents, then rendered `zig-out/Captain.custom.png`; image inspected successfully. An out-of-range scale and an input-equals-output edit were both rejected. `git diff --check` passed.
- **Not checked:** headless tests, a graphical Mach viewport (there is no standalone GUI target yet), click/face selection, undo/redo, editing a live rig or textures, 0.17, Linux/Windows, or an in-game custom modifier install. This is command-line sidecar authoring only.

## Mesh editor, runtime rigs, and animation capture status — 2026-10-12

- At that earlier review point, the modifier work had added offline CLI commands but no standalone editor. The next section records the editor implementation added afterward. [The editor plan](plans/mesh-editor.md) tracks remaining work.
- Corrected the rig status: the GLB trace and CPU bind/run preview understand skin data for review; `HWMS` remains static and runtime gameplay still uses the game's procedural rig. Captain's source has 65 joints, one more than the current GPU palette; preserve it and start with CPU skinning for imported rigs. [Skeletal animation](plans/skeletal-animation.md) records the integration boundary.
- Added a staged design for user animation capture: begin from repeatable local video, turn pose tracks into editable canonical motion, then add local webcam capture behind a platform boundary. The repository currently has no webcam/video input. [Animation capture](plans/animation-capture.md) records privacy, quality limits, and dependencies.
- **Checked:** documentation/source status review only; no code or platform build changed in this clarification.
- **Not checked:** any visual editor, runtime imported rig, camera capture, pose estimator, or video-to-animation prototype.

## Standalone mesh editor first UI — 2026-10-12

- Added `src/MeshEditor.zig` as an independent Mach app and `mesh-editor` / `mesh-editor-build` build steps. It loads the source Captain GLB plus its sidecar without starting gameplay simulation, lists all 74 disconnected islands, and supports list/click selection, rename, component scale/color, sidecar save, orbit/zoom and bind versus compatible procedural-run pose preview.
- Added `Catalog.replaceHandle` for transactional preview mesh replacement with a generation bump, so edited geometry uploads as a new mesh while the renderer rejects stale handles.
- **Checked:** `python3 tools/zig.py build mesh-editor-build`, `python3 tools/zig.py build check`, `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build mesh-editor-build`, and `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check` passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build mesh-editor -Dcapture-frame=3` passed; captured frame 3 at 2880×1800 and inspected it. The front-view Captain mesh and editor panels were visible, and Metal emitted no validation errors. The editor opens the source GLB and uses `Modifiers.apply` against the source-linked sidecar for its viewport. `git diff --check` passed.
- **Not checked:** interactive rename/color/scale behavior during a live session, regular-game `build check`, headless tests, runtime imported skeletal rendering, glTF animation-channel import, retargeted authored clips, webcam/video input, or pose estimation. The run-pose toggle is still an offline CPU-skinned static preview; `HWMS` contains no rig. No modifier sidecar was edited during validation.

## Imported components in Character Designer — 2026-10-12

- The separate editor target was replaced with an **IMPORTED PARTS** window in the game's Character Designer. It browses all 74 Captain mesh islands across surface categories; supports changing a component's surface role, painting or clearing it from a palette, hiding/restoring it, and adjusting skin/eye/armor/energy RGB values.
- The editor loads a saved override from `saves/captain.modifiers.json` or falls back to the checked-in import recipe. **SAVE LIBRARY** writes only to the save path. Preview refresh starts from an immutable copy of the build-baked mesh and changes colors/component indices under the render mutex, avoiding repeated transforms and stale GPU mesh generations.
- Removed the separate `mesh-editor` application/build steps. Offline `asset-compiler` commands remain for GLB import, advanced transforms and diagnostics; runtime skeletal import and webcam capture remain future work.
- **Checked:** default `python3 tools/zig.py build check` and `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check` passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dcharacter-showcase=46 -Dcapture-frame=120` captured the Character Designer at 2560×1600 on Apple M3 Pro / Metal; I inspected the component browser, RGB controls, Back and Save buttons, and saw no Metal validation errors. `python3 tools/zig.py build -Doptimize=ReleaseFast` rebuilt `zig-out/bin/heavy-water`. `git diff --check` passed.
- **Not checked:** headless tests, hands-on component edits, saved override behavior across a full restart, Linux/Windows, live runtime rig/clip import, and webcam capture.

## In-game GLB character import and controller retarget preview — 2026-10-12

- Added an **IMPORT GLB** action inside Character Designer → **IMPORTED PARTS**. On macOS, the file panel reads a binary GLB up to 64 MB. Skinned GLBs are imported through the native CPU skin preview, and recognized Blender/Mixamo/Unity-style humanoid joint names map to the game's locomotion run tracks. The panel reports the mapped track count.
- The imported controller pose is currently baked into the game's static character mesh. Source GLB and appearance sidecar persist under `saves/imported-character.glb` and `saves/imported-character.modifiers.json`, then reload at startup. A new import replaces that one imported-character slot; it does not overwrite the bundled Captain source.
- **Checked:** default `python3 tools/zig.py build check`, `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check`, and `git diff --check` passed.
- **Not checked:** no interactive file-picker import, screenshot/capture, restart persistence check, headless tests, Linux/Windows targets, authored glTF animation clips, or live skeletal gameplay playback. The renderer/gameplay asset is still HWMS static geometry; unsupported joint names do not receive locomotion motion, and external-buffer `.gltf` is not accepted by this picker.
