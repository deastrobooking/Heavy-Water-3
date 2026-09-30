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

## Canopy world

The game's direction is set in [world and systems](world.md): Arbors 300–600 m tall, a canopy city of grafted towers and bridge roads, painterly cel shading, and three braided play styles (explore, engineer, grow) over a procedural city the player extends. The phases below build it. Each is a runnable slice with headless acceptance tests, native Zig throughout.

## 6. Canopy foundations — next

Make the engine able to hold a vertical world and look like one.

1. Done: static triangle-mesh colliders with a BVH, and oriented boxes built from them. The character climbs a 15° mesh ramp, is stopped by an 80° wall, and stands on and climbs a 5° deck; crates rest on mesh floors; rigid bodies settle on tilted mesh decks; wheels, picking, and placement see meshes.
2. Level of detail for tall placed content is done: a `Prop` may carry a `lod` mesh handle and `lod_distance`; beyond that distance the renderer substitutes a coarse proxy instead of the full mesh (`World.Prop.effectiveMesh`, exercised by `StreamingScene.gatherProps`). The test Arbor swaps to an 8-segment, ring-only trunk silhouette beyond 450 m, with a headless test confirming the proxy is under a tenth the vertex count and spans the same height. Still open: streaming (residency eviction) for tall content once more than one Arbor exists — today the single test Arbor is always resident, only its detail level changes.
3. Painterly cel-shading pass: toon ramp, rim light, silhouette outlines, aerial haze, day/night with emissive lumen.
4. Done: a hand-authored test Arbor (`procedural/TestArbor.zig`) 80 m from the spawn, with a 320 m tapered trunk, a 2.5-turn spiral ramp with a curb, a branch platform at 40 m, a 14 m bridge road descending 5.7° to a tower top at 36 m, and render mesh and colliders from one description. The walk acceptance passes headlessly: up the ramp without dropping below its surface, onto the platform (±0.3 m), and down the bridge to the tower top (±0.1 m). Rendering switched to reversed, infinite-far depth with a height-aware haze so the tree is visible above the ground haze.

Acceptance: walk up a trunk ramp onto a branch platform and across an angled bridge, and render the test Arbor within frame budget at 1 km and up close.

## 7. Arbor genome

Genome-driven procedural mega-trees: versioned genes (phyllotaxis, apical dominance, tropisms, platform tendency, vascular capacity, lumen), space-colonization branching, trunk and branch meshes with colliders, flattened platforms, and each tree's vascular graph. Sap taps draw from their tree's capacity, extending machine power networks to trees. Acceptance: the same seed grows the same tree; different genomes give measurably different silhouettes; taps on one tree brown out together.

## 8. Canopy city

A district layout graph (Arbors and grafted towers as nodes, bridge roads as edges); a bridge-road generator (the 14 m standard section, vine-cable suspension, trunk plazas, market bays); a tower generator; and solver validation (every district reachable, grades at most 6%, clearances kept) before anything appears. Player-built bridges, taps, and grafts persist as world deltas over the generated city. Acceptance: a generated district passes the solver, can be driven and walked end to end, and a player-added bridge survives save and load.

## 9. Living city

Traffic on bridge lane graphs (reusing the vehicle), pedestrians on walkway graphs, shops that trade parts and blueprints, bioluminescent day/night, and Rootsong (the machine signal bus limited to trees that share roots). Acceptance: traffic reroutes around a removed bridge and shops restock over a day.

## 10. Rootdeep and shrines

The wild forest floor under the city, and shrines: seed-vault facilities built from the machine kit and verified solvable by a solver before they appear. Acceptance: every generated shrine is solvable by the verifier, and completing one yields a blueprint or genome fragment usable in the other loops.

## 11–12. Mods and scale — later

11. Versioned mod packages and a constrained public API; evaluate a native Zig WASM runtime before selecting a scripting approach.
12. Repeatable 10K/100K/1M workloads with GPU culling, LOD, indirect submission, streaming budgets, and CPU/GPU/memory percentile reports.

Lighting (the cel pipeline, shadows through the canopy, clustered lumen lights, postprocessing) should develop alongside measurable scenes, serving the painterly direction rather than physically based realism. Long-term research remains World Genome, civilization archaeology, Machine DNA, procedural graph compilation, and solver-verified dungeons. None is represented as implemented by this bootstrap.
