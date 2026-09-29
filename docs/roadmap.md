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

## 5. Creation — next

Runtime object placement, snapping, prefab editing, and machine inspection. The first slice: place blueprint instances and crates from an in-game palette with grid and surface snapping, wire and rewire device ports in-world with the same validation blueprints use, and save placed machines (not only their state) in the save file.

## 6–8. Facilities, mods, and scale — later

6. Procedural facilities with explicit requirements and solver validation.
7. Versioned mod packages and a constrained public API; evaluate a native Zig WASM runtime before selecting a scripting approach.
8. Repeatable 10K/100K/1M workloads with GPU culling, LOD, indirect submission, streaming budgets, and CPU/GPU/memory percentile reports.

PBR, shadows, HDR, clustered lights, and postprocessing should develop alongside measurable scenes. Long-term research remains World Genome, civilization archaeology, Machine DNA, procedural graph compilation, and solver-verified dungeons. None is represented as implemented by this bootstrap.
