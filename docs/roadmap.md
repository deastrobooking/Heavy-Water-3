# Heavy Water development plan

The two supplied plans define a sci-fi exploration game that grows into a reusable engine and creator platform. Problems should constrain the player without prescribing a single solution. Engine features should arrive through runnable slices.

## 1. Engine bootstrap — implemented

- Pinned Mach/compiler pair and local bootstrap launcher.
- Mach window, free camera and action input.
- Fixed-step timing and synchronized render snapshots.
- Indexed terrain, 1,000 instanced objects, depth, texture and directional light.
- Debug HUD, optional CPU frustum culling, and bounded smoke run.
- Deterministic generation and initial scalar machine graph tests.
- Explicit ownership and limits documented.

The world is one bounded heightfield. There is no player collision, imported art, save format, audio, or machine gameplay yet.

## 2. Procedural test world — next

1. Chunk handles and bounded active/render/generation radii.
2. Background generation queue with cancellation and bounded upload budget.
3. Biome masks, slope-aware scatter, and deterministic chunk-local object IDs.
4. A fly-through streaming benchmark with frame percentiles and allocation counters.

Acceptance: move across chunk boundaries without cracks, unbounded memory growth, or synchronous generation stalls; unload and regenerate the same chunks reproducibly.

## 3. Interaction and assets

Add a versioned glTF-to-runtime asset path, mesh/material handles, a physics adapter, player collision, object picking, pickup, and one usable tool. Keep external physics handles behind engine APIs. Acceptance: walk through the terrain test world, interact with a physical object, and reload its saved modification.

## 4. Machines

Add typed ports, power and signal networks, sensors/controllers/actuators, fixed-step execution, and versioned blueprints. Acceptance: build a powered door and elevator with the same APIs; introduce a simple vehicle only after those work.

## 5–8. Creation and scale

5. Runtime object placement, snapping, prefab editing and machine inspection.
6. Procedural facilities with explicit requirements and solver validation.
7. Versioned mod packages and a constrained public API; evaluate WASM before selecting a scripting runtime.
8. Repeatable 10K/100K/1M workloads with GPU culling, LOD, indirect submission, streaming budgets, and CPU/GPU/memory percentile reports.

PBR, shadows, HDR, clustered lights, and postprocessing should develop alongside measurable scenes. Long-term research remains World Genome, civilization archaeology, Machine DNA, procedural graph compilation, and solver-verified dungeons. None is represented as implemented by this bootstrap.
