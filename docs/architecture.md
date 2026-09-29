# Foundation decisions

## Boundaries

`App.zig` is the composition root. Mach provides platform, input events, typed objects, math, graphics, and scheduling. `engine/` owns timing, input actions, and typed handles; `world/` owns camera, chunk keys, streaming, and procedural modifications; `asset/` owns glTF import, the runtime model format, and the catalog; `physics/` exposes the physics API; `render/` owns GPU resources and presentation; `game/` holds the player, the interactive `Sandbox` session, and saves. Procedural generation, asset compilation, physics, gameplay, saves, and machine graph evaluation all run without a window.

The game selects the seed. Static content comes from streamed chunk recipes, not the world collection. The renderer does not import the game: the app publishes `World.Prop` values (catalog mesh handle, transform, tint), the `Modifications` removal set, and preformatted HUD lines. `render/StreamingScene.zig` draws one terrain mesh per resident chunk plus one shared relic mesh and one shared vegetation mesh; mesh/material handles and content loading belong to the next asset milestone.

## Chunk streaming

`world/Streamer.zig` owns a fixed pool of 49 CPU payload slots (generation radius 3). Each slot has a state (`empty → queued → generating → ready`, or `canceling`) and an atomic token. A handle is `(slot, token)`; any requeue, eviction, or cancel increments the token, so stale handles fail validation instead of reading recycled data.

Only the render thread calls `plan()`. It evicts slots outside the generation radius and queues missing keys ring by ring from the center. One worker thread takes the nearest queued slot, releases the mutex, and fills the payload in place. Terrain generation checks the slot token once per row and abandons stale work. A `generating` slot that falls out of range becomes `canceling` and is not reused until the worker acknowledges it, so the worker never writes into a slot the planner has reassigned.

A ready payload is immutable until the next `plan()`. `StreamingScene` keeps 25 persistent GPU chunk buffers (render radius 2), fills them nearest-first, and stops when the frame's upload byte budget would be exceeded. Resident chunks whose handle changes or that leave the render radius are released immediately. Generation never runs on the render thread.

## Mach modules, collections, and threading

The registered modules are `Core`, `App`, `World`, and `Renderer`. `World.objects` is `mach.Objects(.{}, Renderable)` with Mach-managed IDs and storage. It contains translation/uniform scale and material tint. Collection access uses `lock` / `unlock` and batched iteration.

Startup: `Core.init → World.init (loads the catalog) → App.init (spawns the sandbox) → Renderer.init → App.start → Core.main`. Shutdown: `App.stop → Renderer.deinit → World.deinit`, so GPU copies are released before the catalog's CPU models.

Application thread: consume events into edge-triggered actions → sample held keys → apply mouse look → run each 60 Hz step (player, held-object spring, physics, picking, then grab/salvage) → `Core.snapshotStart` → publish camera, props, changed removals, and HUD → `Core.snapshotEnd`. Quicksave and quickload do synchronous file I/O on the application thread between steps; rendering continues.

Mach holds its render mutex while invoking `Renderer.render`. The publisher writes render state only inside that same mutex. Static instances are copied before the application thread starts. There is no shared mutable camera access during rendering. Dynamic worlds will need versioned render snapshots or `Core.snapshotObjects` instead of the current one-time instance copy.

The fixed-step clock limits catch-up to eight steps and accounts for discarded time. Camera movement is normalized, mouse rotation is independent of timestep, focus loss clears input, and pitch is clamped. Render interpolation and replay input capture remain future work.

## Assets and handles

`engine/Handle.zig` provides `Handle(Tag)` (16-bit index, 16-bit generation; generation 0 is never issued) and a fixed-capacity `Pool`. Mesh, material, and physics body handles are distinct types.

`asset_compiler` is a host executable in the build graph. It imports glTF with `asset/Gltf.zig`, bakes node transforms, merges primitives into submeshes by material, and writes `asset/Model.zig`'s `HWMS` format v1: a header, materials (base color, name), submesh ranges, 44-byte vertices, and `u32` indices, little-endian. The app embeds the output. `Model.decode` validates magic, version, vertex layout, exact length, index and submesh ranges, and finite floats before allocating anything visible. A layout change bumps `format_version`; the decoder never guesses.

`asset/Catalog.zig` registers the built-in relic and plant meshes and each compiled model, assigning one material handle per submesh, and exposes named content handles. It is immutable after `World.init`, so both threads read it without locks. `StreamingScene` uploads each catalog mesh once and resolves handles per draw; props are drawn once per submesh with instance tint × material base color.

## Physics and interaction

Gameplay calls only `physics/Physics.zig`: bodies are `Physics.Body` handles, and descriptors, hits, ground samples, and character results are engine types. `BoxWorld.zig` is the built-in backend: axis-aligned boxes without rotation, semi-implicit Euler, four positional solver iterations against the ground and each other (O(n²), 128 bodies), Coulomb-style ground friction, and slab raycasts. The character is an upright cylinder swept in sub-steps of half its radius. It is pushed out of boxes, steps onto surfaces up to 0.4 m, snaps down slopes, and shoves dynamic boxes it walks into. Restitution, rotation, and continuous collision are out of scope; a heavier backend can replace this file without changing callers.

`procedural/Terrain.zig` answers height and face-normal queries on the exact triangles `Chunk.fill` renders, so collision matches the visible ground. Physics receives it through a `Ground` callback, independent of whether a chunk is streamed in.

`game/Sandbox.zig` owns the physics world, player, six supply crates, held-object state, and the `Modifications` set. A held crate keeps colliding: gravity is suspended and a velocity spring pulls it toward a point 2.2 m ahead, and it drops if wedged more than 4 m away. Picking casts the view ray 6 m against physics bodies and against relic boxes regenerated for the 3×3 chunks around the eye, occluded by terrain. The salvage cutter records a relic's `(chunk, local_id)` in `Modifications`, a sorted, bounded set; the renderer filters regenerated scatter against it.

## Saves

`game/Save.zig` writes JSON format v1: format, seed, generator version, content version, tick, player pose and mode, crate positions/velocities by stable prop ID, and removed relic IDs. Writes go to a temporary file and are renamed over `saves/quicksave.json`. Loading parses and validates everything (versions, seed, ID ranges, duplicates, finite values) before touching the session, so a rejected save changes nothing. Procedural content is never stored; it is regenerated from seed and generator version, and the saved deltas are applied on top.

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
| Asset catalog (CPU models, material table) | World | Loaded in `World.init`; freed in `World.deinit` after the renderer |
| GPU copies of catalog meshes | StreamingScene | Uploaded on first render; released in shutdown |
| Physics bodies, player, crates, modifications | App's Sandbox (fixed capacity) | Application |
| Save encode/decode buffers | App, supplied allocator | Freed before the key handler returns |
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
