# Heavy Water development plan

Engine tooling is native Zig: physics, asset compilation, navigation, and other engine systems are written in Zig rather than bound from C/C++ libraries. Mach (platform, GPU) is the foundation layer.

Heavy Water is a sci-fi exploration and engineering game that grows into a reusable engine and creator platform. This roadmap is the single planning document. Problems should constrain the player without prescribing a single solution. Engine features should arrive through runnable slices.

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

1. Build tool: a palette of crates, prefab machines (powered door, elevator, rover), and loose devices (generator, button, latch, logic OR, lamp), with 0.5 m grid snapping, quarter-turn rotation, surface or terrain-footprint snapping, a green or red preview, overlap and player rejection, and removal.
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

A customizable, nameable ranger-engineer: the creator on a new game (F4 any time), name and appearance palettes, a block-built avatar with a walk cycle and lumen accents, third-person view (F2) with eye-origin aiming, and the profile in save format v6. Acceptance evidence: headless tests freeze input in the creator, confirm a named profile, target a crate from the eyes in third person, draw the avatar, and restore the profile from a save.

## Traversal and local co-op — implemented

Starfall's traversal verbs are ported to metres, seconds and the fixed step. They cover buffered and coyote jumps, wall slides, wall jumps, jump-started climbing, ledge hang and mantle, rolls, stomps, swimming volumes, and four traversal kits: grapple, hover jet, flight and hoverboard. Up to four local players share one window in split screen. The macOS GameController bridge handles drop-in join and leave, and F6 adds a keyboard-less guest for testing.

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

Acceptance: the headless full-ramp/platform/bridge walk passes. The `--canopy` benchmark renders up close and at 1 km, exercises both LODs, and passes the 16.667 ms render CPU P99 budget (0.926 ms on the recorded Apple M3 Pro run). Presentation interval P99 was 21.074 ms; GPU execution time and visual art-direction approval remain unmeasured. Multiple-Arbor residency remains deferred as described above.

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
- **Saves:** format 8 and content 6 save the wallet, stall stock, market day and kit machines.

Acceptance evidence, all with the real Sandbox:

- A minute of free traffic in which every car reaches at least three plazas and nothing needs recovering.
- A car crosses a new 0 → 3 bridge while the bridge reports occupied.
- A car bound 1 → 0 → 3 has the bridge closed mid-trip, reroutes 0 → 5 → 4 → 3 and arrives, and the closed bridge disappears once its pedestrians have crossed, with zero recoveries.
- A market run salvages a part, opens a stall, sells, buys a kit to sell-out, places, refuses capture, refunds, closes when walking away, round-trips a save, and restocks at the next dawn.

See [canopy city](city.md) and [validation](validation.md).

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
- GPU timing (no timestamp queries on Metal).

## Sky city — content pass

The district is rebuilt as a sky city held up by steel:

- **Bridges:** five steel bridge styles plus the vine spurs. The six roads are assigned styles by span length, and players choose a style with Tab.
- **Supports:** braced pole piers under every non-suspension road, and braced legs under the free-standing plazas.
- **Skyline:** seeded, validated skyscrapers, with a sky-lobby tower beside each tower plaza.
- **Night lighting:** window columns, spire beacons, lit rails, and cable light strings.
- **Saves:** district generator 2 and save format 11 (bridge styles).

Acceptance evidence:

- The clear deck envelope holds for every style on every road and on 0 → 3, across seeds.
- Towers and piers reach the ground, outside plazas.
- The skyline is plentiful and clear of every road, buildable route, plaza, trunk, and the spawn area.
- A player stands on every style's lanes and walkways, and styles survive save/load.
- The complete walk and drive loops cross all styles.
- Frames were captured from fixed viewpoints and reviewed by eye, by day and at dusk (see [city](city.md#the-sky-city)).

## Next level — phases 13–16

The next phases close the gaps to a production engine, in this order. [Engine alignment](plans/alignment.md) records how each outside suggestion was weighed against the codebase. Native Zig is kept: C-library physics, audio, and animation were declined on 2026-10-01.

### 13. Asset pipeline — slices 1–3 implemented (identity, packs, background loading, development reload)

- **Identity:** stable GUID asset references (`AssetRef`) with `.meta` sidecars holding the GUID, source hash, importer version, and typed import settings.
- **Build output:** a manifest with dependencies, and content packs.
- **Runtime:** a registry, async loading with progress and per-frame GPU budgets, and hot reload by GUID with generation-bumped handles.

Acceptance: renames keep identity; only changed sources reimport; invalid references are rejected without mutation; a 64-asset pack loads within the frame budget; a model edited on disk swaps in a running session. See [plan](plans/asset-pipeline.md).

### 14. Skeletal animation — planned

- **Import:** glTF skins and clips into `HWSK` and `HWAN`.
- **Runtime:** allocation-free pose sampling and blending, GPU skinning from a 64-bone uniform palette (with a CPU fallback), and `Player.Motion` mapped to clips as data.
- **Attachments:** sockets for attachments and per-bone hitboxes for combat.
- **First content:** a generated rigged ranger, so no external art is needed.

Acceptance: exact import round trips, pose-math reference tests, the controller selecting the right clip for every traversal state, a carried crate held at the hand socket within 1 cm, and render CPU within budget with 20 animated characters. See [plan](plans/skeletal-animation.md).

### 15. Scene graph and JSON scenes — planned

- **Nodes:** fixed-size, trivially copyable nodes in parent-before-child order, with typed component arrays.
- **Format:** JSON scenes whose `_ref` fields resolve through the registry, with staged hydration.
- **Placement:** anchors to plazas, shrines, and Arbors; prefabs with overrides; hot reload by node ID.
- **Spawn content:** the hard-coded spawn content moves into `scenes/spawn.json`.

Acceptance: byte-identical round trips, rejection without mutation, every existing spawn test passing on the spawn scene, and live edits applying in a running session. See [plan](plans/scenes.md).

### 16. UDP networking — planned

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

Phases 1–13 have runnable slices. The next milestone is the Mach `main` evaluation before phase 14 skeletal animation (rigged ranger, pose sampling and skinning). Phases 15–16 follow with scenes and networking. Landscape authoring has an isolated foundation and awaits runtime integration. Open decisions and follow-ups:

- **Mach:** update or fork it for indirect draws, shader atomics, timestamp queries, and texture-to-buffer copies (phase 12). The plan is to evaluate the current Mach `main` on a branch before phase 14 ([alignment](plans/alignment.md#mach-tracking)).
- **Economy:** whether building should cost resources (phase 9 markets are additive today).
- **Mod API 2:** host imports, mod-defined genomes, shrines and wares, and saved script state (phase 11).
- **Content and design:** the level and character design pass deferred earlier, and art-direction review.

Lighting (the cel pipeline, shadows through the canopy, clustered lumen lights, postprocessing) should develop alongside measurable scenes, serving the painterly direction rather than physically based realism. Long-term research remains World Genome, civilization archaeology, Machine DNA, procedural graph compilation, and solver-verified dungeons. None is represented as implemented by this bootstrap.
