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

## 2. Procedural test world — implemented

1. Generational chunk handles; active (3×3), render (5×5), and generation (7×7) radii.
2. One background worker, per-slot cancellation tokens checked per terrain row, and a per-frame GPU upload byte budget.
3. Continuous world-space biome masks, slope-aware scatter, and `(seed, generator, chunk, local_id)` object identity.
4. `tools/benchmark.py`: fixed fly-through with interval/CPU percentiles, upload, residency, and pool-allocation counters.

Acceptance evidence: seam tests (including negative coordinates), a fixed 49-slot CPU pool and 25-slot GPU pool that never grow, generation off the render thread, and a test that unloads and regenerates a chunk with an identical fingerprint. See [validation](validation.md).

Still absent: player collision, imported art, save format, audio, and machine gameplay.

## 3. Interaction and assets — next

Add a versioned glTF-to-runtime asset path, mesh/material handles, a physics adapter, player collision, object picking, pickup, and one usable tool. Keep external physics handles behind engine APIs. Acceptance: walk through the terrain test world, interact with a physical object, and reload its saved modification.

## 4. Machines

Add typed ports, power and signal networks, sensors/controllers/actuators, fixed-step execution, and versioned blueprints. Acceptance: build a powered door and elevator with the same APIs; introduce a simple vehicle only after those work.

## 5–8. Creation and scale

5. Runtime object placement, snapping, prefab editing and machine inspection.
6. Procedural facilities with explicit requirements and solver validation.
7. Versioned mod packages and a constrained public API; evaluate WASM before selecting a scripting runtime.
8. Repeatable 10K/100K/1M workloads with GPU culling, LOD, indirect submission, streaming budgets, and CPU/GPU/memory percentile reports.

PBR, shadows, HDR, clustered lights, and postprocessing should develop alongside measurable scenes. Long-term research remains World Genome, civilization archaeology, Machine DNA, procedural graph compilation, and solver-verified dungeons. None is represented as implemented by this bootstrap.
