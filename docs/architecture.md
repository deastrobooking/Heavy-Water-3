# Foundation decisions

## Boundaries

`App.zig` is the composition root. Mach provides platform, input events, typed objects, math, graphics, and scheduling. `engine/` owns timing and input actions, `world/` owns camera and world data, `render/` owns GPU resources and presentation, and `game/TestWorld.zig` supplies the initial content. Procedural generation and machine graph evaluation can run without a window.

The game selects the seed. Static content comes from streamed chunk recipes, not the world collection. The renderer does not import the game. `render/StreamingScene.zig` draws one terrain mesh per resident chunk plus one shared relic mesh and one shared vegetation mesh; mesh/material handles and content loading belong to the next asset milestone.

## Chunk streaming

`world/Streamer.zig` owns a fixed pool of 49 CPU payload slots (generation radius 3). Each slot has a state (`empty → queued → generating → ready`, or `canceling`) and an atomic token. A handle is `(slot, token)`; any requeue, eviction, or cancel increments the token, so stale handles fail validation instead of reading recycled data.

Only the render thread calls `plan()`. It evicts slots outside the generation radius and queues missing keys ring by ring from the center. One worker thread takes the nearest queued slot, releases the mutex, and fills the payload in place. Terrain generation checks the slot token once per row and abandons stale work. A `generating` slot that falls out of range becomes `canceling` and is not reused until the worker acknowledges it, so the worker never writes into a slot the planner has reassigned.

A ready payload is immutable until the next `plan()`. `StreamingScene` keeps 25 persistent GPU chunk buffers (render radius 2), fills them nearest-first, and stops when the frame's upload byte budget would be exceeded. Resident chunks whose handle changes or that leave the render radius are released immediately. Generation never runs on the render thread.

## Mach modules, collections, and threading

The registered modules are `Core`, `App`, `World`, and `Renderer`. `World.objects` is `mach.Objects(.{}, Renderable)` with Mach-managed IDs and storage. It contains translation/uniform scale and material tint. Collection access uses `lock` / `unlock` and batched iteration.

Startup: `Core.init → World.init → App.init → Renderer.init → App.start → Core.main`.

Application thread: consume events → map movement actions → advance 60 Hz simulation → `Core.snapshotStart` → publish camera/tick/debug switches → `Core.snapshotEnd`.

Mach holds its render mutex while invoking `Renderer.render`. The publisher writes render state only inside that same mutex. Static instances are copied before the application thread starts. There is no shared mutable camera access during rendering. Dynamic worlds will need versioned render snapshots or `Core.snapshotObjects` instead of the current one-time instance copy.

The fixed-step clock limits catch-up to eight steps and accounts for discarded time. Camera movement is normalized, mouse rotation is independent of timestep, focus loss clears input, and pitch is clamped. Render interpolation and replay input capture remain future work.

## Coordinates and GPU layout

World space is left-handed, +Y up, forward +Z. Mach matrices use column storage, column vectors, and `projection × view × model`. Perspective depth maps the near plane to 0 and the far plane to 1. Tests enforce this convention.

GPU vertices contain packed position, normal, UV, and linear vertex color (44 bytes). Instances contain translation/uniform scale and tint (32 bytes). The camera uniform is a 4×4 matrix plus padded eye position (80 bytes). Normals need no inverse transpose with positive uniform scale. Rotation and non-uniform scaling are not exposed yet.

Opaque terrain and scatter share a pipeline with a depth32 attachment. Each visible terrain chunk uses one indexed draw; relics and vegetation each use one indexed instanced draw. The HUD uses a separate color-only pass and one draw. The two-texel checker texture is generated at startup; the bitmap HUD uses fixed CPU storage and requires no font dependency. Shaders are embedded beside their renderer source for now; an asset compiler and shader reload will later consume `assets/`.

CPU culling tests chunk bounding spheres, then compacts surviving scatter instances into preallocated storage using conservative sphere/plane tests. Culling starts enabled.

## Ownership and allocators

| Resource | Owner | Lifetime |
| --- | --- | --- |
| Core windows, platform, device, queue, swapchain | Mach Core | Application |
| Typed world collection | Mach module system | Application |
| Streamer and 49 chunk payloads (~13.6 MiB) | Renderer's StreamingScene, supplied allocator | Two allocations at startup; freed after the worker joins |
| Streaming worker thread | Streamer | Started with the scene; canceled and joined in shutdown |
| 25 GPU chunk vertex/index buffer pairs (~6.8 MiB) | StreamingScene | Created on first render; recycled, never reallocated |
| Relic and vegetation CPU meshes | Renderer setup, explicit supplied allocator | Freed after GPU upload |
| GPU meshes, uniform and instance buffers, texture, sampler, pipelines | Renderer | Created lazily on render thread; released in shutdown |
| Depth texture and view | Renderer | Recreated on framebuffer resize; view released before texture |
| Camera and simulation clock | App's Engine | Application |
| Static, visible, and HUD CPU arrays | Renderer | Fixed capacity, no per-frame growth |
| Machine nodes and values | Graph | Fixed capacity, caller-owned |

Mach's standard entrypoint supplies `std.heap.c_allocator`. Engine mesh APIs accept explicit allocators; allocation tests use `std.testing.allocator`. The frame path does not allocate engine CPU arrays, but Mach snapshots, GPU command encoders, staging uploads, and drivers can allocate. No zero-allocation claim is made for the full application.

Shutdown follows Mach's examples: signal Core exit, join the app thread, release renderer resources, then allow Core to destroy its platform resources. The pinned Mach entrypoint explicitly leaves module-container deinitialization disabled upstream, so process-lifetime collection allocations are currently reclaimed by process exit. A custom entrypoint plus upstream lifecycle audit is required before repeated engine create/destroy cycles or whole-process leak accounting.

## Deterministic generation

Generator version 2 uses an explicit wrapping SplitMix64 hash, signed lattice coordinates, smooth value noise, and two height octaves. Heights, normals, and biome weights sample global coordinates, including samples beyond chunk edges, so seams need no stitching. Adjacent chunk positions and normals are tested at negative coordinates. Chunk keys are clamped to ±4096 because terrain uses f32 world positions; floating origins come later.

Biome weights (arid, meadow, wetland) come from one continuous low-frequency moisture field with no per-chunk normalization. Scatter evaluates 192 candidates per chunk from a chunk seed. A candidate's `local_id` is its candidate index, so rejected candidates leave gaps rather than shifting later IDs. Slope limits are 0.88 (relics) and 0.94 (vegetation) on the surface normal's Y component; arid regions thin vegetation. An object's stable identity is `(seed, generator version, chunk key, local_id)`, which is what saved modifications will reference.

The same seed/version/build reproduces this scene. Cross-architecture floating-point bit identity is not promised. A future save format must persist seed, generator version, content version, and modifications; old worlds must not silently use a new generator.

## Machine seed implementation

`machine/` provides an allocation-free, 128-node scalar graph with constants, addition, multiplication, and comparison. Nodes may refer only to earlier nodes, which establishes evaluation order and prevents cycles. It has tests for results, invalid references, and capacity. This library is not connected to objects or player interactions yet. It is not a sandbox, physical simulation, graph editor, or serialization format.

## Rendering growth path

Preserve the CPU world / presentation boundary. Introduce mesh/material handles, a dense GPU scene table, compute frustum culling, and indirect instance counts before adding HZB and projected-size LOD. Add a pass graph when shadow/HDR/postprocessing resource dependencies exist. Replace fixed capacities with explicit, budgeted persistent buffers and per-frame staging only when the workload requires it.

Performance work should record CPU/GPU timing separately, allocation counts, and P50/P95/P99 across fixed-seed scenes. The current HUD is diagnostic instrumentation, not the million-object benchmark from the long-term plan.
