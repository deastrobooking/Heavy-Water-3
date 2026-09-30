# Foundation decisions

## Boundaries

`App.zig` is the composition root. Mach provides platform, input events, typed objects, math, graphics, and scheduling. `engine/` owns timing, input actions, and typed handles; `world/` owns camera, chunk keys, streaming, and procedural modifications; `asset/` owns glTF import, the runtime model format, and the catalog; `machine/` owns devices, blueprints, and machine simulation; `physics/` exposes the physics API; `render/` owns GPU resources and presentation; `game/` holds the player, the interactive `Sandbox` session, and saves. Procedural generation, asset compilation, physics, gameplay, saves, and machine graph evaluation all run without a window.

The game selects the seed. Static content comes from streamed chunk recipes, not the world collection. The renderer does not import the game: the app publishes `World.Prop` values (catalog mesh handle, transform, tint), the `Modifications` removal set, and preformatted HUD lines. `render/StreamingScene.zig` draws one terrain mesh per resident chunk plus one shared relic mesh and one shared vegetation mesh; mesh/material handles and content loading belong to the next asset milestone.

## Test Arbor

`procedural/TestArbor.zig` describes the phase 6 measuring stick relative to a trunk-base origin: a 320 m trunk tapering from 22 m to 10 m radius (buried 14 m), a 150-step spiral ramp 4 m wide with an outer curb that climbs for 92% of its 2.5 turns and runs level onto the platform, a 30 × 14 m branch platform at 40 m, a 14 m-wide bridge road descending 4 m over 40 m, and a 20 m tower whose top is 36 m. `renderMesh` produces one vertex-colored mesh (registered in the catalog), and `createColliders` builds the trunk and ramp as mesh colliders and the rest as oriented boxes, all from the same description. The Sandbox places it 80 m from the spawn, with the ramp's foot on the terrain. Its colliders are tagged as world geometry, which occludes picking without becoming a target. The Sandbox now takes an allocator for collider storage and frees it in `deinit`.

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

Gameplay calls only `physics/Physics.zig`: bodies are `Physics.Body` handles, and descriptors, hits, ground samples, and character results are engine types. `BoxWorld.zig` is the built-in backend: axis-aligned dynamic, kinematic, and static boxes without rotation, semi-implicit Euler, four positional solver iterations against the ground and each other (O(n²), 128 bodies), Coulomb-style ground friction, and slab raycasts. The character is an upright cylinder swept in sub-steps of half its radius. It is pushed out of boxes (including kinematic ones moving into it), steps onto surfaces up to 0.4 m, snaps to supports within step height when the caller asks, reports the body it stands on, and shoves dynamic boxes it walks into. Kinematic bodies move only by the velocity set on them, ignore gravity and the ground, and push dynamic bodies without being pushed back; the player adds its support body's velocity to its own, which is how it rides lifts.

`physics/Rigid.zig` adds oriented rigid boxes (`Physics.Rigid` handles, eight at most) for bodies that must rotate. It has quaternion orientation, box inertia, force and torque accumulation, and linear and angular damping. Contacts come from sample points: the rigid box's 26 corner, edge-midpoint, and face-center points tested against terrain and every nearby axis-aligned box, plus each box's corners tested against the rigid box. Velocities are solved with eight iterations of sequential impulses (accumulated normal impulse, two-axis Coulomb friction), then positions are corrected along contact normals, split with dynamic boxes by mass. It handles resting, tipping, sliding, walls, and shoving props; edge-edge crossings between sample points can be missed. The character treats rigid boxes as walls. `castRay` finds the nearest terrain, box, or rigid surface and reports that surface's velocity. `physics/Rotation.zig` holds the vector and quaternion math.

`physics/TriangleMesh.zig` is the static mesh collider: triangles with precomputed normals (degenerate slivers dropped) and a bounding-volume hierarchy (median split on the longest axis, four triangles per leaf), queried by ray (Möller–Trumbore, two-sided), box overlap, and closest point. `Physics.createMesh` owns one per handle (64 at most), with storage from a caller-supplied allocator that `destroyMesh` or `Physics.deinit` frees. `createBox` builds an oriented static box as twelve outward-facing triangles; angled decks and walls use it. Every consumer sees meshes:

- Triangles with a normal Y of at least 0.6 are floors; steeper ones are walls.
- The character stands on the highest floor hit by five downward rays (center and four points at 0.7 r) within step height.
- Wall triangles push it out horizontally at three heights on its axis.
- Upward rays set ceilings.
- Dynamic boxes rest on floors under their footprint.
- Rigid-body sample points up to 0.3 m behind a face get contacts along its normal.
- Picking (`Hit.mesh`), surface rays for wheels, and placement overlap all include meshes.

Dynamic boxes are not yet pushed out of mesh walls.

`physics/Vehicle.zig` is a raycast vehicle over one rigid chassis, built only on the public API. Each wheel casts along the chassis' down axis. The spring-damper force pushes along the ground normal, so a pitched chassis leaks no tangential force. Tire forces combine drive (fading to zero at `max_speed`), brake, and rolling resistance longitudinally with lateral grip. Both cancel sliding velocity using the true effective mass at the contact (`rigidEffectiveMass`, so forces below the center of mass cannot overshoot into roll) plus gravity's pull along the contact plane (so a braked vehicle holds on slopes). The result is clamped to a friction circle of grip × load and applied at a point raised toward the center of mass (`roll_influence`). Surface velocity is subtracted, so wheels work on moving platforms. Restitution, rotation, and continuous collision are out of scope for now; they will be added to the native Zig backend, and callers will not change.

`procedural/Terrain.zig` answers height and face-normal queries on the exact triangles `Chunk.fill` renders, so collision matches the visible ground. Physics receives it through a `Ground` callback, independent of whether a chunk is streamed in.

`game/Sandbox.zig` owns the physics world, player, six supply crates, held-object state, and the `Modifications` set. A held crate keeps colliding: gravity is suspended and a velocity spring pulls it toward a point 2.2 m ahead, and it drops if wedged more than 4 m away. Picking casts the view ray 6 m against physics bodies and against relic boxes regenerated for the 3×3 chunks around the eye, occluded by terrain. The salvage cutter records a relic's `(chunk, local_id)` in `Modifications`, a sorted, bounded set; the renderer filters regenerated scatter against it.

## Canopy district

`procedural/District.zig` generates and validates the six-node road loop, towers, market bays, and trunk-ring spurs. Stable plaza IDs anchor player additions. Shared `Piece` descriptions generate both the immutable catalog mesh and static collision; added bridges reuse block render instances. `game/BridgeTool.zig` selects visible anchors, previews validation, and commits through `Sandbox.addBridge`. Four player spans are the storage limit. The generated layout stays resident with the grove. See [canopy city](city.md) for geometry rules and current limits.

## Creation tools

`game/Build.zig` implements the build and wire tools on top of the Sandbox. With either tool active, picking reaches 14 m and ignores relics.

- Build: the view ray's first surface is snapped to a 0.5 m grid. Crates and loose devices sit on the surface found by a downward ray, and prefabs use a terrain-footprint origin or sample an elevated deck across their rotated footprint (`footprint`: parts, bodied devices, both ends of actuator travel, or chassis and wheels). The preview is valid when the above-ground box overlaps no body (`Physics.overlapsBox`; rigid bodies by bounding sphere) and not the player. Placing a loose device adds it to the workshop machine (created on first use, removed when empty). Removing a workshop device destroys its body, removes it from the blueprint and machine, and re-tags later device bodies (`Physics.setUser`). Removing a structure or a prefab device removes the whole machine; a driven vehicle cannot be removed.
- Bridge: key 4 selects stable plaza markers within 1 km, with ray occlusion. Selection skips the chosen source marker so a nearby source cannot mask the destination. Both preview and commit call the district validator; right-click cancels or removes a nearby player span.
- Wire: `candidates` lists output→input pairs on the same machine with matching kinds and a free signal input. Tab cycles them, and a click applies `Blueprint.connect` and `reconfigure`. Wires render as thin bars (power yellow, signal cyan) only while the wire tool is active.

- Capture: P copies the aimed machine's blueprint into `Sandbox.prefabs` (16 at most) under the first free `<base>_<n>` name. Workshop circuits are recentred: device offsets are centred in XZ on the grid and raised so the lowest device bottom sits at the origin. The palette is the built-in items followed by prefabs, and placing a prefab spawns an independent machine. The Sandbox flags each capture, and the application exports it (it owns file I/O) as a blueprint JSON file under `saves/prefabs/`. It imports that directory at startup and after a quickload, through the full blueprint parser.
- Inspect: `Build.inspect` formats the aimed machine's identity, networks, device outputs, and wires into fixed lines, and the renderer draws them in a right-hand panel.

Wires between different machines are rejected; signals cross machines through transmitter and receiver pairs on the bus instead. `[` / `]` retune the aimed one.

## Player character

`game/Profile.zig` holds the name (validated, stored uppercase for the bitmap font) and appearance: proportions plus indices into fixed palettes. `game/Creator.zig` edits a draft through abstract keys (testable without a window). A name is required, and Escape only works after a first confirmation. The application maps window keys onto those abstract keys while the creator is open, and the creator's lines render in the right-hand panel. `game/Avatar.zig` builds the visible body from scaled, rotated blocks, with limbs swinging from hip and shoulder pivots by a walk phase that advances with ground speed; the visor and belt use the glowing accent.

The avatar appears in your own view in third person (F2) and in the creator, on foot only. It is always published for the other split-screen views (see local co-op below). The third-person camera sits 4 m behind and 0.3 m above the eyes, kept above the terrain. Aiming, picking, holding, and building still start at the eyes, so the same target is chosen in either view. While the creator is open, input and tools are frozen and the camera faces the character.

## Traversal

`game/Player.zig` ports Starfall's traversal verbs to metres, seconds and the fixed step. Every timer, resource and attachment belongs to one `Player`, so four players never share state. Movement still goes through `Physics.moveCharacter` in substeps of at most 0.18 m, so a dash or zip cannot tunnel through thin decks. The verbs:

- Jumps use a 0.18 s buffer and 0.16 s of coyote time, with variable height on release.
- On walls you get wall slides, two wall jumps per landing, and climbing on its own energy bar. Climbing starts only from a jump into the wall: Starfall climbs on any push, but here walking into a closed door or a crate row must stop you.
- A ledge hang (F, up to 2.5 s) leads to a mantle that lifts clear of the edge before moving onto it.
- Grounded rolls lower the collider to 0.95 m. A stomp slams down and bounces on landing.
- Swimming uses optional authored water volumes, with breath.
- Four traversal kits: grapple (with a hover jet), hover jet, flight (glide, jet, air dash) and hoverboard (boost, ground-following). They share fuel, and three quick jump taps toggle hover.

The grapple only anchors to static mesh colliders beyond 3 m. It re-checks that surface every step and releases when the anchor disappears (for example, a removed bridge) or the line is blocked. Headless tests cover the jump buffer, stomp, roll, the climb and mantle, the grapple zip, the glide, and hover toggling.

Keyboard edges (Space, Ctrl, X, G, B) latch in `Input` until a fixed step consumes them. `Input.merge` folds a controller driving P1 into the keyboard state.

## Local co-op and split screen

`engine/Gamepads.zig` polls up to four controllers once per frame through `platform/gamepad.m`. Mach's pinned platform layer has no controller API, so this small Objective-C bridge reads Apple's GameController extended profile and keeps each pad in a stable slot. Sticks use a radial dead zone. Button edges stay latched until the fixed step consumes them, and a disconnect clears the command. On other platforms `poll` returns no pads.

`Sandbox.guests` holds three drop-in `Guest` players. Each has its own `Player`, `Camera`, first- or third-person view, profile (a distinct accent and outfit), gait and target. Guests step after P1 and before the machines, so proximity sensors see them through `Machine.Environment.other_feet`. Their hands pick along their own eye ray and can press buttons. Tools, carrying, vehicles and saves stay with P1.

Every walking body is published as props tagged with `World.Prop.owner` (1–4). Each view hides only its own owner in first person, so everyone sees everyone else. Split-screen layout lives in `render/Layout.zig`.

The renderer draws every view in one depth-cleared pass, each with its own viewport and scissor, camera uniform, bind group, and instance buffer. Every view also has its own `StreamingScene`, and therefore its own terrain streamer, which matters because players can be kilometres apart. Views 2–4 create their scene when first shown and keep it until shutdown. Their catalog meshes are borrowed from view 1 rather than uploaded again.

All views share one per-frame terrain upload budget, with a different view getting first claim each frame. The outline pass runs once over the shared depth buffer, so the seams between views draw as ink dividers. The HUD places P1's lines and panel inside P1's view, and each guest's status in its own view and accent colour.

## Saves

`game/Save.zig` writes JSON format v7: format, seed, generator version, content version, tick, player pose and mode, every crate by slot, removed relic IDs, and every machine by slot with its full blueprint document (as edited in the world), origin, quarter-turn yaw, workshop flag, per-device state, and for vehicles the chassis pose and velocities, plus the captured prefab library as blueprint documents, the player's profile, Arbor/district generator versions, and player bridge endpoint pairs. The save therefore describes the whole built world; the default layout is only the new-game state. Older formats are rejected, not migrated. Content version 2 added the door and elevator; version 3 added the rover. Whether the player is seated is not saved: loading leaves the player standing. Writes go to a temporary file and are renamed over `saves/quicksave.json`. Loading parses and validates everything (versions, seed, slot ranges, duplicates, finite values, each blueprint through `fromDoc`, machine state restored into scratch machines, at most one workshop, and physics body and rigid capacity, and district graph validation) before tearing down and rebuilding the session. Bridge colliders are allocated into staging first, with cleanup on failure, so a rejected save changes nothing. Procedural content is never stored; it is regenerated from seed and generator version, and the saved deltas are applied on top.

## Coordinates and GPU layout

World space is left-handed, +Y up, forward +Z. Mach matrices use column storage, column vectors, and `projection × view × model`. Perspective depth is reversed and infinite-far: depth = near / z (1 at the near plane, toward 0 at infinity), with a greater-than depth test and a clear to 0. With a 32-bit float depth buffer, this keeps distinct depths at 1 km and 1.001 km. Tests enforce the convention and its monotonicity.

GPU vertices contain packed position, normal, UV, and linear vertex color (44 bytes). Instances contain translation/uniform scale, tint, per-axis stretch, and a rotation quaternion (64 bytes). The shader stretches, then rotates, then scales and translates; normals are divided by the stretch (the inverse transpose of a diagonal scale) and rotated. Mach's native WGSL compiler does not implement the `cross` builtin, so the shader defines its own. The camera uniform is a 4×4 matrix plus padded eye position (80 bytes).

Opaque terrain and scatter share a pipeline with a depth32 attachment. Each visible terrain chunk uses one indexed draw; relics and vegetation each use one indexed instanced draw. A color-only silhouette pass samples the stored reversed depth attachment before the HUD's separate color-only pass. The depth texture has attachment and texture-binding usage; its outline bind group is recreated on resize. Fog is height-aware haze: ground haze reaches full strength by about 380 m (hiding the streamed terrain's edge) but fades with world height (e-folding 90 m), and a separate aerial term tints everything with distance (e-folding 2.2 km). Tall content stays visible above the ground haze. The two-texel checker texture is generated at startup; the bitmap HUD uses fixed CPU storage and requires no font dependency. Shaders are embedded beside their renderer source; shader reload remains future work.

`engine/Sky.zig` derives a twenty-minute day from `Sandbox.tick`, already persisted in save format v6. Integer reduction before float conversion preserves within-day precision even for long sessions. `App.publish` transfers time of day under the render mutex. The shader combines a soft toon ramp, rim lighting, hemispheric fill, and sky-colored haze; the directional key fades to zero before swapping between sun and moon at the horizon. The opaque instance tint's fourth component is `1 + emission` (0..1 strength), packed by `Material.emissive`; powered lamps and avatar lumen use it. This is emissive surface shading, without local light casting or bloom. Smoke mode sweeps the lighting cycle by rendered frame index without modifying saved world ticks.

The canopy benchmark aims at the test Arbor while moving from 30 m to beyond 1 km and back, counting detailed and proxy LOD frames. Its CPU P99 budget is 16.667 ms; presentation intervals are recorded separately and are not GPU timings. Mach's default GPU error callback is retained so invalid rendering fails smoke and benchmark processes.

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
| Physics bodies, player, crates, machines, modifications | App's Sandbox (fixed capacity) | Application |
| Parsed blueprints | Catalog (fixed capacity, parsed from embedded validated JSON) | Application |
| Save encode/decode buffers | App, supplied allocator | Freed before the key handler returns |
| GPU meshes, uniform and instance buffers, texture, sampler, pipelines | Renderer | Created lazily on render thread; released in shutdown |
| Split-screen views 2–4: StreamingScene, streamer thread, 49 payloads, 25 GPU chunk pairs, per-view uniform/instance buffers | Renderer, heap allocator | Created the first time that view is shown; kept (never regrown) until shutdown |
| Guest players and controller state | App's Sandbox and Gamepads (fixed capacity) | Application; guests are session-only |
| Depth texture and view | Renderer | Recreated on framebuffer resize; view released before texture |
| Camera and simulation clock | App's Engine | Application |
| Static, visible, and HUD CPU arrays | Renderer | Fixed capacity, no per-frame growth |
| Machine nodes and values | Graph | Fixed capacity, caller-owned |

Mach's standard entrypoint supplies `std.heap.c_allocator`. Engine mesh APIs accept explicit allocators; allocation tests use `std.testing.allocator`. The frame path does not allocate engine CPU arrays, but Mach snapshots, GPU command encoders, staging uploads, and drivers can allocate. No zero-allocation claim is made for the full application.

Shutdown follows Mach's examples: signal Core exit, join the app thread, release renderer resources, then allow Core to destroy its platform resources. The pinned Mach entrypoint explicitly leaves module-container deinitialization disabled upstream, so process-lifetime collection allocations are currently reclaimed by process exit. A custom entrypoint plus upstream lifecycle audit is required before repeated engine create/destroy cycles or whole-process leak accounting.

## Deterministic generation

Generator version 2 uses an explicit wrapping SplitMix64 hash, signed lattice coordinates, smooth value noise, and two height octaves. Heights, normals, and biome weights sample global coordinates, including samples beyond chunk edges, so seams need no stitching. Adjacent chunk positions and normals are tested at negative coordinates. Chunk keys are clamped to ±4096 because terrain uses f32 world positions; floating origins come later.

Biome weights (arid, meadow, wetland) come from one continuous low-frequency moisture field with no per-chunk normalization. Scatter evaluates 192 candidates per chunk from a chunk seed. A candidate's `local_id` is its candidate index, so rejected candidates leave gaps rather than shifting later IDs. Slope limits are 0.88 (relics) and 0.94 (vegetation) on the surface normal's Y component; arid regions thin vegetation. An object's stable identity is `(seed, generator version, chunk key, local_id)`, which is what saved modifications will reference.

The same seed/version/build reproduces this scene. Cross-architecture floating-point bit identity is not promised. Saves persist seed, generator version, content version, and modifications; old worlds never silently use a new generator.

## Machines

`machine/Device.zig` defines device kinds and a fixed, typed port table for each: power or signal, input or output, and a default value for unconnected signal inputs.

| Kind | Role | Ports |
| --- | --- | --- |
| generator | source | out `power`; in `enable` (default 1) |
| button | sensor | out `pressed` (1 for the step after a press) |
| proximity | sensor | out `present` (player feet inside its box) |
| latch | controller | in `toggle` (rising edge); out `state` |
| logic | controller | in `a`–`d`; out `out` (last node of its graph) |
| actuator | actuator | in `power`, `target` (0..1); out `position` |
| seat | sensor (vehicles) | out `occupied`, `throttle`, `steer`, `brake` from the driver |
| motor | actuator (vehicles) | in `power`, `throttle`; out `drive` = throttle × satisfaction; draws watts × \|throttle\| |
| steering | controller (vehicles) | in `command`; out `angle` (clamped −1..1) |
| lamp | actuator | in `power`, `on`; out `lit` (on and supplied); draws watts while on |
| transmitter | bus | in `in`; publishes it on its channel after the step |
| receiver | bus | out `out` = its channel's value from the previous step |

`machine/Blueprint.zig` parses JSON blueprint format v1 (the optional `vehicle` section and vehicle device kinds were added compatibly): a name, static structure parts (offset, size, color), devices (id, kind, offset, size, color, and kind-specific `watts`, `speed`, `travel`, or logic `nodes`), and wires as `["device.port", "device.port"]`. It validates everything: format, names, capacities (24 devices, 16 parts, 48 wires, 64 logic nodes), finite values, positive sizes, parameters per kind, logic graphs (inputs in range, references only to earlier nodes), port existence, output→input direction, matching port kinds, and at most one driver per signal input. Devices may set `"body": true` to get a pickable static body regardless of kind; workshop devices do. The same checks back runtime editing: `addDevice`, `connect`, `disconnectInputs`, and `removeDevice` (which drops the device's wires, compacts the logic-node table, and shifts later indices). `toDoc` converts back to the document shape for saves. A `vehicle` section (chassis size and mass, suspension, grip, force, brake, steering, 3–6 wheels) requires exactly one seat, motor, and steering device and forbids actuators, buttons, and proximity sensors; those kinds are rejected outside vehicles. The result is a fixed-capacity value with resolved indices. `asset-compiler` runs the same validation on `assets/source/blueprints/*.json` during the build, so an invalid machine fails the build.

`machine/Machine.zig` is one placed blueprint. Each fixed step it copies outputs to a previous buffer, and every signal input reads that buffer, giving one step of latency per hop, determinism independent of device order, and permitted wiring cycles. Power ports are joined into networks by union-find at instancing. Each step, a network sums generator supply and the rated watts of actuators that are still moving. Satisfaction is 0 without supply, otherwise `min(1, supply / demand)`, and actuators move at rated speed times satisfaction (brownout). Persistent state is one float per device (latch value, actuator position); `restore` validates ranges. A machine has a frame (`origin`, `rotation`): identity for placed structures, the chassis pose for vehicles. Device positions and proximity regions are frame-relative. Transmitters and receivers carry a channel (1–64, required for them and forbidden for other kinds). The Sandbox keeps a world `Bus`: every machine steps against the previous step's bus, then `transmit` writes each transmitter's input (the largest value wins per channel). That is one step of latency across machines, independent of machine order. After an edit, `reconfigure` rebuilds drivers and networks while keeping per-device state; `removeDevice` shifts the per-device arrays to match the blueprint. The machine has no physics dependency beyond the rotation math.

`machine/Graph.zig` is the controller evaluator shared by logic devices: constants, inputs, add, multiply, and greater-than, evaluated in order into caller storage without allocating.

`game/Sandbox.zig` places each blueprint with its origin on the highest terrain under its structure. It creates static bodies for parts, generators, and buttons and a kinematic body for each actuator, steps machines before physics, and drives each actuator body by setting the velocity that reaches the machine's position this step. Physics user data tags machine bodies so picking can resolve a device. Pressing a button is delivered on the next machine step. The test world has a powered door (button → latch → logic OR proximity → door actuator, 200 W generator) and an elevator (two call buttons → logic OR → latch → platform actuator, 250 W generator), built from the same device kinds.

Machines live in 16 fixed slots. Each slot owns its blueprint copy (the machine points at it), so rewiring one door never changes another. Static machines may be rotated by quarter turns: part and device bodies use swapped half extents, and rendering passes the frame rotation.

Vehicle blueprints get a rigid chassis and a `Vehicle` instead of static bodies. Each step, the Sandbox copies the chassis pose into the machine frame, gives the seat the driver's controls when occupied, steps the machine, and feeds the motor's `drive`, the steering `angle`, and the seat's `brake` to the vehicle. An empty seat holds the parking brake. Picking the chassis targets its seat; entering switches to a chase camera, and exiting places the player beside the chassis.

## Rendering growth path

Preserve the CPU world / presentation boundary. Introduce mesh/material handles, a dense GPU scene table, compute frustum culling, and indirect instance counts before adding HZB and projected-size LOD. Add a pass graph when shadow/HDR/postprocessing resource dependencies exist. Replace fixed capacities with explicit, budgeted persistent buffers and per-frame staging only when the workload requires it.

Performance work should record CPU/GPU timing separately, allocation counts, and P50/P95/P99 across fixed-seed scenes. The current HUD is diagnostic instrumentation, not the 10K/100K/1M-object benchmark planned in roadmap phase 8.


## Genome Arbors and shared sap

`procedural/Arbor.zig` grows a bounded, deterministic parent-before-child skeleton from a validated versioned genome and seed. The immutable catalog loads two seeded Arbor assets before rendering starts. Their full/proxy meshes, woody collision, flat shelves, and vascular edges derive from the same nodes; foliage is render-only. `World.init` supplies the selected world seed to the catalog. The sandbox creates the corresponding static colliders and publishes the meshes with a 600 m LOD distance. The test Arbor remains as the original traversal fixture.

`Machine.prepare` snapshots signals and evaluates regular supply and consumer demand. The sandbox resolves sap taps to nearby wood, determines unmet network demand across connected enabled taps, and calls `machine/Sap.zig` for every tree. Allocation accumulates demand along ancestor paths and grants each request the tightest edge fraction. `Machine.finish` then resolves satisfaction and advances devices once. This preserves signal-hop latency and prevents machine iteration order from reserving the entire tree supply for the first tap. No per-step heap allocation is required. The policy is conservative; spare flow is not redistributed after branch limits.

Blueprint v1 adds the `sap_tap` kind with generator-compatible `power`/`enable` ports. Lamps now report continuous satisfaction as their `lit` output. The build preview requires sap devices to be near wood, inspection names the attached tree/node, and the sandbox reports tree demand/supply. Attachments and power outputs are derived state; saved machine poses and blueprints rebuild them. Save documents record the Arbor generator version; content v4 prevents older geometry from silently changing under saved players. Three tree assets/colliders remain resident; this is a bounded grove, not multi-tree streaming.
