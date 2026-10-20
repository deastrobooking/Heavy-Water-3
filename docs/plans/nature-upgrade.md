# Nature upgrade: terrain, ground cover, grass and trees

**Status:** in progress, 2026-10-14. Phase 0 review cameras and benchmark instrumentation are implemented; the 600-frame benchmark passes. A first L-system slice drives the eight streamed tree species and separates bark branches from foliage. A second pass fits crowns to bole height, adds foliage clusters along secondary branches, and improves the nature review views. Frame-120 captures of 71–73 are now daylight-visible; 71 cleanly frames open ground and low plants, while 72/73 show more connected branching but still reveal spindly giant silhouettes at distance. The 62/70 capture set, frame-480 captures, regression guards and Arbor integration remain open. Re-measured 2026-10-14: the nature route submits 12,248,988 triangles (1,855,985 on 2026-10-13) with the same 551 visible vegetation instances and unchanged CPU time. Benchmark GPU p99 is 19.690 ms, so forest level of detail (phases 5d and 5f) now comes before further crown detail ([technical review](next-steps.md#technical-review--2026-10-14)). [Roadmap](../roadmap.md) stays the single plan; this document is the detailed breakdown behind its "Nature" section.

**Audience:** engineers and coding agents working in this repository. Every step names the files it touches, the tests that must exist, and the capture or measurement that proves it.

The reusable flora generator also supplies a trailing vine for Detroit's roof gardens and selected stone facades. It is placed from the seeded skyline layout rather than ground scatter, so these city assets do not change scatter candidate identities or saved removals. `-Dshowcase=89` is the close review view.

## 1. Goal and what "best in class" means here

Best in class for this game is not photorealism. [Visual direction](visual-direction.md) and [world](../world.md) set the target: fantasy anime sci-fi realism, cel-lit, painterly, no texture stack, no bloom. The nature bar is therefore:

1. **Credible construction.** Terrain has believable erosion, drainage and strata. Trees have a real skeleton with tapering limbs and connected, clustered foliage. Ground is covered with grass, not bare vertex colour.
2. **Readable silhouettes at every distance.** A giant tree reads as one connected form from 30 m and from 1 km. Low contrast at distance, richer near the player.
3. **Dense near the player, cheap far away.** Millions of grass blades within sight, drawn through a bounded, allocation-free frame path.
4. **Deterministic and saveable.** Worlds stay a pure function of seed, generator version and chunk key. Collision, placement and rendering share one height function.
5. **Combat-safe.** Near-ground cover stays low and legible (see [world](../world.md): "Keep near-ground silhouettes low and flowers legible so they do not obscure combat or movement").

## 2. Constraints that shape every phase

These come from [AGENTS.md](../../AGENTS.md) and the code; the plan does not break them.

- **Native Zig only.** No C/C++ terrain, foliage or noise libraries. Shaders are WGSL through Mach's compiler.
- **Mach WGSL limits.** No `cross`, `pow` or `reflect` (substitutes live in the shared prelude of [scene.wgsl](../../src/render/scene.wgsl)), no negated swizzles, one entry point per stage per module, `patch` is reserved. New stages are spliced onto the prelude the way [Renderer.zig](../../src/render/Renderer.zig) already does for foliage, water and terrain.
- **Mach engine gaps.** No shader atomics (so no GPU-compacted culling), per-pass timestamp queries, or texture-to-buffer readback. Metal benchmark reports now include whole-command-buffer GPU duration; other backends do not. Indirect draws exist. See [scale](../scale.md). Plan around CPU cell planning plus shader-side per-instance rejection, which is what [Field.zig](../../src/render/Field.zig) already does.
- **Module state is small.** Mach copies module state on the 8 MB main-thread stack. Large arrays go on the heap, and every phase that adds state runs one Debug launch.
- **Frame path never allocates.** Fixed-capacity storage or arenas only.
- **Saves are contracts.** Anything that changes what a seed produces bumps `Seed.generator_version`; anything that changes a grown tree bumps `Arbor.generator_version`. Both are recorded in saves ([Save.zig](../../src/game/Save.zig)). Each phase below states its save impact.
- **Shared working tree.** Keep edits to `App.zig`, `Sandbox.zig`, `build.zig`, `tests.zig` and `roadmap.md` small. Stage only your own files.
- **Both compiler channels.** Default pair stays green. After touching reflection, bitsets, `@Int` or build scripts, also run the 0.17 check. Use the shims in `src/compat/`.

## 3. Review of the current systems

Facts below were read from the code on 2026-10-13. Where something is unverified it is marked **verify**.

### 3.1 Terrain

| Aspect | Current state | Source |
| --- | --- | --- |
| Height function | Value noise with smoothstep interpolation: broad (0.012 scale, 11 m), detail (0.045, 4 m, faded in with distance from the hub), a ridge layer (power 2.15 of a folded value noise) and `Mountains.height`, then carved by `Hydrology.carvedHeight`. No fractal octave stack, no domain warp, no derivative-damped erosion look. | [Noise.zig](../../src/procedural/Noise.zig) |
| One source of truth | `Noise.height` feeds the chunk mesh, `Terrain.surface` (exact triangle split, so collision matches the render), scatter and biome. This is the design's best property and must survive. | [Terrain.zig](../../src/procedural/Terrain.zig), [Chunk.zig](../../src/procedural/Chunk.zig) |
| Mesh | 128 m chunks, 64 cells, 2 m vertex spacing, 4,225 terrain vertices per chunk. Vertex normals come from four extra `Noise.height` samples at ±0.5 m per vertex. | [Chunk.zig](../../src/procedural/Chunk.zig) |
| View range | Render radius 2 chunks (25 chunks, about 256 m each way), generation radius 3. Haze hides the streamed edge at about 320 m. A separate far panorama mesh carries the mountain ranges. | [Streamer.zig](../../src/world/Streamer.zig), [scene.wgsl](../../src/render/scene.wgsl) |
| Materials | Three biome weights (arid, meadow, wetland) from one low-frequency moisture field (220 m), baked to one vertex colour, plus alpine rock and snow. The terrain shader adds world-space value-noise drift, strata and snow glints. No temperature, no slope or curvature materials beyond `exposed`, no soil, scree, moss, sand-bank or wet-ground materials. | [Biome.zig](../../src/procedural/Biome.zig), [terrain.wgsl](../../src/render/terrain.wgsl) |
| Water | Rivers are seeded east-flowing lanes with a meander and periodic waterfall drops; Detroit widens its lane. They are not drainage-driven, so terrain does not flow toward them. | [Hydrology.zig](../../src/procedural/Hydrology.zig) |
| Heightmap tools | PGM import, stamps, temple and cave sites exist as an isolated foundation, not used by the default world. | [landscapes.md](landscapes.md), [Landscape.zig](../../src/procedural/Landscape.zig) |

Verdict: structurally sound, visually thin. Smooth-lattice value noise produces rounded, grid-faint, texture-less hills. There is no erosion read, no flow-shaped valleys, and ground colour has too few degrees of freedom.

### 3.2 Scatter and ground cover

- Per chunk: 192 uniform-random candidates, then 40 boulder candidates ([Scatter.zig](../../src/procedural/Scatter.zig)). One in seven candidates is a relic. Of the vegetation candidates, 7% are grass tufts, 8% ferns, 1.5% giant trees (one of eight forms) and 2.5% pines, before slope and biome rejection.
- **Result: about 20 grass and fern instances per 128 m chunk (16,384 m²), roughly one tuft per 800 m².** The ground has effectively no grass; what reads as meadow is vertex colour plus shader tufts in [terrain.wgsl](../../src/render/terrain.wgsl). This is the largest gap against the goal.
- Placement is white noise: no spacing rule, no clustering into groves and clearings, no density fields, no niche rules per species beyond arid and snow.
- Stable identity is `(seed, generator version, chunk key, local candidate id)`, and saved removals reference it. Any change to candidate semantics invalidates saved removals.
- Instances are 64-byte records (translation and scale, tint, colour, stretch, rotation) in [StreamingScene.zig](../../src/render/StreamingScene.zig). Culling is per-object sphere on the CPU and optional per-instance frustum rejection in the vertex stage.

### 3.3 Grass and low flora

- Grass is mesh variant 0: nine single triangles (blades) per tuft, no thickness, no bend in geometry, flat shading ([Vegetation.zig](../../src/procedural/Vegetation.zig)). Wind is a vertex-stage sway by height squared with a per-plant phase ([foliage.wgsl](../../src/render/foliage.wgsl)).
- There is no grass LOD, no density fade, no player or vehicle interaction and no terrain-tinted colour (tint is a per-instance multiply).

### 3.4 Trees

Two systems:

**Scattered forest trees** (`Vegetation.tree`, eight species, scale 96 to 152 m):
- Crowns are stacks of smooth ellipsoids (`ellipsoid(...)`), so they read as discs and balloons. Trunks are one thin cone (recently a tapered, flared bole with limbs on the deciduous species).
- One mesh per species at every distance. I found no distance LOD in the scattered-flora draw path (**verify** against the benchmark before relying on this). The tree mesh builder reserves 16,000 vertices, and the pine species fills most of that (not yet measured; Phase 0 records exact counts).
- Species differ in colour and silhouette recipe but there are no per-instance shape variants beyond scale and yaw.

**Arbors** (`Arbor.grow`, the city trees):
- Space colonization with `max_nodes = 192`, a fixed 13 m step, 128 attractors and 28 iterations ([Arbor.zig](../../src/procedural/Arbor.zig)). The skeleton drives rendering, collision, sap taps and grafting, so changing growth changes gameplay data.
- Meshing: one straight 12-sided tube per node, no spline smoothing and no junction blending. Radius is `parent × 0.85` per step with a floor, not an area-preserving pipe model. Foliage is one ellipsoid per terminal node (now three lobes). Shelves are boxes.
- LOD: full, proxy and collision details exist. Detail and proxy frame counts are benchmarked.
- Recent fixes (2026-10-13, committed): branches keep 45% of the parent heading and reject steps that double back; tips carry three rounder lobes.

### 3.5 Lighting and atmosphere

- Cel ramp with hemispheric ambient, rim light and height-aware haze ([scene.wgsl](../../src/render/scene.wgsl)). **There are no shadows and no ambient occlusion.** Trees do not shade the ground or each other, which is the largest remaining "flat" cue after grass density. See [alignment](alignment.md): "there are no shadows yet".
- Night flora emission is shared and species-coloured.

### 3.6 Verification tooling

- Showcases 62 (flora review), 70 (test Arbor), 36, 41 and 48 cover nature. Until 2026-10-13 a fixed-view showcase could be overwritten by the simulation step and capture a dark close-up depending on frame timing; `App.zig` now re-applies the showcase pose after the sim steps. Phase 0 builds on that.
- The nature benchmark isolates terrain chunk fill and scatter generation CPU costs, and reports visible instances, submitted triangles and CPU frame percentiles. It does not isolate grass or tree mesh generation, and the GPU has no timestamp-query support.

## 4. Principles for the upgrade

1. **Keep the single height function.** Every terrain change lands in `Noise.height` (and what it calls) so mesh, collision, scatter and biome stay in agreement. Keep the exact triangle contract in `Terrain.surface`.
2. **Procedural first, textures later or never.** Continue the no-texture-stack rule: vertex colour, packed weights, world-space procedural detail.
3. **Generate on worker threads, draw from fixed buffers.** New per-chunk data (grass patches, tree placements) is produced where scatter is produced now and stored in preallocated pools.
4. **Measure before and after.** Every phase records numbers in [validation](../validation.md).
5. **Spike unknown engine features before designing on them.** Section 5 lists three spikes (shadow depth pass, `discard`, off-screen target for impostors).
6. **One version bump per phase that changes the world.** Batch world-changing edits inside a phase so a player migrates once.

## 5. Spikes (do first, each is one small throwaway change)

| Spike | Question | How to answer it | Decides |
| --- | --- | --- |
| S1 Depth pass | Can the pinned Mach create a depth texture, render depth-only from the sun, and sample it with a comparison sampler on Metal? | Add a throwaway pass in a scratch branch that renders the terrain into a 1024² depth texture and samples it in `terrain.wgsl` under `MTL_DEBUG_LAYER=1`. | Phase 6 shadow maps vs analytic canopy shadow |
| S2 Discard | Does Mach's WGSL compiler accept `discard`, and does alpha-to-coverage exist? | Compile a one-line `discard` in a copy of the foliage fragment stage and capture. | Leaf-card silhouettes (cutout) vs pure geometry leaves |
| S3 Off-screen render | Can a mesh be rendered to a texture at load for baked impostors? | Render one tree to a 256² target and sample it on a quad. | Distant tree impostors vs low-poly LOD meshes |

Record each result in [alignment](alignment.md#mach-tracking) under the Mach gaps. If a spike fails, it becomes an upstream candidate and the plan uses the fallback named in its phase.

## 6. Phased plan

Order is chosen so each phase is shippable alone and unlocks the next. Sizes: S under a day, M a few days, L about a week of focused work.

### Phase 0. Baselines and guards (S)

Purpose: make every later claim measurable.

1. Add showcases to [App.zig](../../src/App.zig) `showcase()`: **71** ground-level grass view (eye at 1.7 m, target 30 m ahead), **72** forest mid-distance (eye 12 m up, 150 m back), **73** terrain overview over 5×5 chunks at dusk. Keep each edit to a few lines and place the stage via `Terrain.surface`.
2. Add a `-Dnature-benchmark` route to the benchmark flythrough that reports: terrain `Chunk.fill` p50/p99 ms, scatter `generate` p50/p99 ms, visible instance counts by kind, triangles submitted, and CPU frame p99. The report writer in [Renderer.zig](../../src/render/Renderer.zig) already emits JSON; add keys, do not reformat existing ones.
3. Add tests that pin current behaviour so later phases show intent: scatter density per kind over 25 chunks, terrain height bounds, chunk-edge seam equality for height, normal and colour.
4. Capture 71, 72, 73 and the existing 62, 70 at frame 120 and 480; store the PNGs outside the repo and record dimensions, build mode and numbers in [validation](../validation.md).

Status (2026-10-14): showcases and benchmark instrumentation are implemented. The 600-frame benchmark passes and its measurements are recorded in [validation](../validation.md). Review found showcase 71 inside a giant trunk/canopy and the original 72 dominated by oversized oval foliage. The eight streamed species now share bounded L-system skeletons; the branch/foliage split fixes green-tinted bark. The follow-up fits each species' crown to the one-unit bole, adds small foliage clusters along secondary branch tiers and terminal twigs, and moves the 72 camera farther back with a steeper view. Daylight frame-120 captures now exist for 71–73: 71 clearly shows open ground and low plants, 72 shows fuller connected crowns at mid distance, and 73 shows the terrain in daylight. The 72/73 views still show spindly giant silhouettes at distance; species shape and LOD work remain. A current 62 review, both 70 captures, frame-480 captures for 71–73, and the requested scatter-density, terrain-bounds and chunk-seam regression guards remain open.

Follow-up pass (2026-10-15): the separate giant Arbor generator now grows with 448 attraction points, a 640-node cap and 8.5 m branch steps, then adds short deterministic twigs to primary and secondary limbs. Every non-trunk limb carries two broad overlapping foliage masses and terminal twigs carry six; Arbor generator version 3 migrates version-1 and version-2 saves because saves do not store Arbor node references. The isolated heightmap authoring path also has a sharper smooth mountain stamp alongside mound, basin, plateau and ridge tools. A frame-120 Metal capture confirms a fuller crown without API validation messages; foliage still reads as rounded clumps, so leaf shape and branching variation need another art pass. Tests and longer performance checks remain open.

Acceptance: numbers recorded; the new tests pass on the default pair and the 0.17 channel.

### Phase 1. Terrain height: from value noise to eroded-looking relief (M)

Purpose: remove the rounded, lattice-faint hills and gain believable ridge, valley and slope structure without breaking determinism or collision.

1. In [Noise.zig](../../src/procedural/Noise.zig) add `gradient(seed, x, z) -> {value, dx, dz}`: 2D gradient noise (hashed unit gradients on a lattice, quintic interpolation) returning analytic partial derivatives. Keep `value` unchanged so biome and snowline fields do not shift.
2. Add `fbmEroded(seed, x, z, octaves, lacunarity, gain)`: sum gradient-noise octaves where each octave's amplitude is damped by `1 / (1 + dot(d_acc, d_acc))`, with `d_acc` the accumulated derivative. This is the derivative-damped technique that yields erosion-like valleys and flat, sediment-like floors without running a simulation, so it stays chunk-independent.
3. Add a low-frequency domain warp: displace `(x, z)` by two gradient-noise samples at about 1/600 scale, amplitude 60 to 120 m, before sampling `fbmEroded`. This breaks the lattice alignment.
4. Replace `baseHeight`'s `broad + detail + ridges` with: warped `fbmEroded` for the main relief (6 octaves, lacunarity 2.0, gain 0.5), a ridged layer for the existing mountain-foot ridges (keep the `relief` mask from hub distance so the hub stays flat), then `+ Mountains.height` as now. Keep `Hydrology.carvedHeight` as the last step.
5. Keep the hub contract: [Terrain.zig](../../src/procedural/Terrain.zig) `hub_height_upper_bound` (44 m) documents a strict bound that the district placement relies on. Recompute the true bound with a sweep test over the hub clearance, update the constant and its comment, and keep a test that fails if the bound is exceeded.
6. Normals: add `Noise.heightWithGradient` returning height and analytic slope for the fractal part, and use it in `Chunk.fill` to replace the four ±0.5 m finite-difference samples per vertex when `Hydrology` and `Mountains` do not modify the point. This cuts roughly four of five height evaluations per vertex. Retain the finite-difference path for carved, mountain and cave-adjacent points; add a test that the two agree within tolerance where both apply.
7. Cost control: octave count is a `comptime` constant. Measure `Chunk.fill` p99 before and after with the Phase 0 benchmark. Budget: no more than a 1.5× increase in chunk generation time, or cut octaves.
8. Update tests: `surface matches rendered chunk vertices` (Terrain.zig), chunk-seam tests (Chunk.zig), mountain and cave clearance tests, district flatness tests. Add a regression test that two adjacent chunk meshes share identical edge heights and normals.
9. Bump `Seed.generator_version`. Follow the existing migration path in [Save.zig](../../src/game/Save.zig) (the decode already branches on generator mismatch); add a round-trip test for a save from the previous generator.

Acceptance: capture 73 and 41 show valley and ridge structure and no lattice alignment; collision tests pass; chunk generation within budget; district and city captures unchanged in layout.

Risks: city and Detroit placement depend on flat hub heights; cave and mountain mouths depend on clearance. Mitigation: the `relief` mask keeps the hub unchanged, and the tests in step 8 fail loudly.

### Phase 2. Terrain materials, biomes and rivers (M)

Purpose: ground that reads as soil, grass, moss, scree, sand, rock and snow in believable places.

1. Extend `Biome` with temperature (latitude-free: a low-frequency noise field plus altitude lapse) and add a fourth axis to the weight set (for example `forest`) so cover has more than arid, meadow and wetland. Keep `Weights` normalized; update the normalization test.
2. Add terrain-derived inputs to cover: **curvature** (Laplacian from the same finite differences) and a **flow proxy** (low-pass of height difference), giving `soil` in concavities, `scree` below steep rock, `moss` on shaded north-facing slopes and wet ground near rivers.
3. Pack material weights into the vertex. `Mesh.Vertex` carries `color` (vec3) and `uv`; terrain does not use `uv` for texturing (the shader works in world space). Pack four extra weights into `uv` (two channels, 16 bits each, or use `uv` plus the unused alpha channel in an existing field after reading the vertex layout; **verify** against `Mesh.Vertex` before choosing). Keep colour as the base albedo so existing far and panorama passes still work.
4. In [terrain.wgsl](../../src/render/terrain.wgsl) blend per-material procedural looks using the packed weights: macro variation (existing broad noise), two scales of cellular or gradient noise for soil grain and pebbles, strata on steep faces (already present), moss as a green multiplicative tint with a fine-noise breakup, wet darkening within a distance field of rivers. Add a **normal perturbation** from the derivative of the near-detail noise so the cel ramp picks up ground bumps (fade out by 110 m as the existing `near` term does).
5. Rivers: keep `Hydrology.carvedHeight` (straight lanes) for the Detroit contract. Add a second pass for non-Detroit lanes: replace the sinusoidal meander with a domain-warped lane centre and add short **tributary** carves using a hashed lattice of branch points (each a deterministic curved channel merging into the nearest lane). All of it is analytic in `(x, z)`, so it stays chunk-independent. Add wetness and bank materials from the river distance field.
6. Water shader stays; add foam at carved-bank intersections using the same distance field.
7. Tests: weight normalization with four axes, curvature continuity across chunk seams, river carve identical on both sides of a chunk edge, footing kind unchanged where gameplay depends on it (`Biome.Kind` tests).
8. Save impact: footing may change where biome changes; covered by the Phase 1 generator bump if both phases ship before release. If Phase 2 ships alone, bump again.

Acceptance: capture 73, 36 (river) and 48 (meadow) show visible soil, moss, scree and wet banks; the shader stays within the current terrain fragment cost (report CPU and whole-command-buffer GPU p99, and check the capture frame rate by eye).

### Phase 3. Ecology-driven scatter (M)

Purpose: forests, groves, clearings and understory that look designed, not sprinkled.

1. Replace uniform candidates with **jittered-grid blue-noise** per chunk: a 12 m grid (about 114 cells per chunk) with a per-cell hashed offset, guaranteeing minimum spacing and removing clumping artifacts. The `local_id` becomes the cell index, which is stable per seed. Keep boulder candidates as a separate stream.
2. Add **density fields** in `Biome` or a new `Ecology.zig`: `forest(seed, x, z)` (low-frequency noise at about 300 m, thresholded to make groves and clearings, scaled by moisture and slope), `understory(x, z)` (higher near tree density), `edge(x, z)` (gradient of the forest field for shrubs on forest edges). Evaluate in world space so chunk seams match.
3. Species **niches**: table of `{ species, moisture_min, moisture_max, altitude_min, altitude_max, slope_max, cluster_bias }`. Choose by weighted sample from the species whose niche contains the cell, not by one `choice` threshold. This replaces the hard-coded `choice > 0.985` chain in [Scatter.zig](../../src/procedural/Scatter.zig).
4. Layers: canopy (giant trees, rare), sub-canopy (young trees, pines 6 to 18 m), shrubs, ground cover. Keep the "towering trees are rare" design rule from [roadmap](../roadmap.md): density targets per 128 m chunk, for example 1 to 3 giants, 6 to 12 young trees and pines in forest cells.
5. **Per-instance variation**: random yaw, a small lean, and non-uniform `stretch` (±12%) for every tree so repeats do not read as clones. The instance record already has `rotation` and `stretch`.
6. Keep the road and spawn clearing rules (`road_clearance`, `spawn_clearing`) and extend with a **trail** rule so worn paths stay open.
7. **Save impact:** this changes `local_id` semantics, so saved removals (`Modifications`) keyed by `(chunk, local_id)` no longer refer to the same objects. Bump the generator version and, in the migration, drop saved scatter removals with a one-line note in the load log. Add a migration test. Harvestable saplings are separate content; verify they are unaffected (`relic` kind).
8. Tests: minimum-spacing property over 100 chunks, density per kind within the target range, stability (two runs equal), slope and road rejection still hold, chunk-edge neighbours never place overlapping objects.

Acceptance: capture 72 shows groves with clearings and layered understory; benchmark reports instance counts per kind within the design targets.

### Phase 4. Grass system (L)

Purpose: dense, wind-swept, interactive grass over the whole near field, within a fixed, allocation-free budget.

Design: a **GPU-generated patch** system. One small grass-patch mesh is drawn instanced per 4 m terrain cell. The vertex stage derives each blade's position, height, bend, tint and facing from a hash of the instance origin and vertex-stage blade index, so the CPU supplies only one 64-byte instance record per cell and no per-blade data.

1. **Patch mesh** in `Vegetation.zig`: `grassPatch(a, blade_count, segments)` builds `blade_count` blades (48 near, 24 mid) of seven vertices each (three quads tapering to a tip). Vertex attributes: `position.xz` = blade slot index encoded (not a world position), `position.y` = height fraction along the blade (0 to 1), `uv` = (side −1 or 1, blade index). Normals are authored for soft cel lighting: bend them 40% toward the up vector so blades shade like a lawn, not like cards.
2. **Instance generation**: per chunk, in the same worker that builds scatter, emit one instance per 4 m cell (32×32 = 1,024 per chunk, about 25,600 for 25 render chunks): `translation_scale.xyz` = cell centre with the terrain height from `Terrain.surface`, `.w` = cell size; `tint` = terrain cover colour (so grass picks up biome tint), `color` = density in `.x` (from the meadow, forest-floor and wetness fields), blade height in `.y`; `rotation` unused. Reject cells that are steep, snowy, river water, road or district. Store them in a fixed pool owned by the streamer, **on the heap**.
3. **New WGSL stage** `grass.wgsl` spliced like `foliage.wgsl`:
   - Blade index → hash → position inside the cell, yaw, height (0.25 to 0.7 m, scaled by density), width (taper to the tip).
   - Bend: a quadratic Bezier from root to tip using the wind vector; reuse the gust model from `foliage.wgsl` and extract it into the shared prelude so trees and grass share one wind.
   - **Distance LOD in the shader**: blades beyond 25 m are dropped by index (collapse to the existing "behind near plane" trick used for culling) so density thins smoothly to 25% at 70 m and 0 at 110 m; terrain shader tufts take over beyond. Scale blade width up as density thins to keep cover.
   - Colour: root-to-tip gradient from `tint`, darker at the root (cheap contact shading), a slow low-frequency tint drift (reuse `vnoise`), a sun-facing warm rim.
   - **Trample**: a uniform array of up to 8 `pushers` (`xyz` position, radius) written per frame from the player, vehicles and large creatures; blades within radius bend away and flatten. Source them from `Sandbox` the same way it publishes other per-frame view data.
4. **CPU planning**: extend the cell planner pattern from [Field.zig](../../src/render/Field.zig): per frame, for each of the 25 chunks, add that chunk's cell runs to the instance buffer only for cells within 120 m, then draw as ranged instanced draws sorted by LOD ring (near patch with 48 blades, mid patch with 24). Keep the per-frame instance cap in a constant and assert it.
5. **Budgets** (state them in the plan so they are tested): at most 6,000 patch instances drawn per frame, at most 48 blades per near patch, so at most 288,000 near blades and about 2 million vertices. If the Phase 0 benchmark shows CPU p99 over 16.667 ms, drop the near blade count to 32 before touching anything else.
6. **Ground cover beyond grass**: reuse the patch system with other meshes selected by a per-instance mesh index: clover and tiny flowers (density modulated by the wildflower field), pebbles and leaf litter (forest floor), reeds near water (wetness field), dry brush (arid). Keep the height cap at 0.7 m, in line with the combat-readability rule.
7. **Retire** the old grass and fern tuft scatter variants (variants 0 and 1) from `Scatter` once the patch system covers them; keep ferns as scattered understory meshes in forests (Phase 3 layer rule). Variant ids stay reserved so `Vegetation.names` and saves remain valid.
8. **Tests:** patch mesh index and vertex counts and finite values; cell instance generation is deterministic and respects rejections; the draw plan never exceeds the instance cap over a long synthetic route; `grass.wgsl` compiles through Mach (a build test that splices and creates the shader module); the trample uniform packing round-trips.
9. **Validation:** Metal-validated smoke; captures 71 (ground-level), 62 and 48; a benchmark row for grass patch count, blades, vertices and CPU p99.

Acceptance: ground-level capture shows continuous grass with wind and trample; far field transitions without a visible band; budgets hold.

Risks: vertex-bound cost on the M3 Pro; the benchmark reports whole-command-buffer GPU time but cannot isolate grass. Mitigation: density and blade-count levers are constants, and compare fixed-seed GPU percentiles before and after.

### Phase 5. Trees v2 (L)

Purpose: trees whose silhouette, branching and foliage clustering look grown, at three levels of detail.

**5a. Bounded L-system foundation — first slice implemented (2026-10-14):**
1. [LSystem.zig](../../src/procedural/LSystem.zig) defines one turtle interpreter and eight species grammars. Expansion is deterministic and capped at 4,096 symbols and 32 nested pushes; branch segments and terminal leaf anchors come from the same skeleton.
2. [Vegetation.zig](../../src/procedural/Vegetation.zig) builds each streamed tree's branches into its bark-tagged trunk mesh and emits small leaf fans around selected secondary-branch and terminal anchors. Crown height is normalized against the one-unit bole, while individual leaves stay separate from oversized continuous blobs. Deciduous species now select ovate, lanceolate, scale, fan, cascade or blossom silhouettes; conifers keep fine radial needle sprays. The generator runs while catalog meshes are built, never on the frame path.
3. Species-specific grammar, taper, droop, foliage density, branch spread and distance silhouettes remain tuning work. The daylight 72 capture confirms denser attached foliage at mid distance; the current 62 capture is dusk and too dark for art approval.
4. **Next:** adapt the shared branch representation to gameplay Arbors only after verifying sap/graft node identity and platform attachment behavior. Arbor remains on its current space-colonization generator until a migration and gameplay-preservation pass is planned.

**5b. Smooth sweep meshing:**
The first structural pass ends the straight bole just beyond the skeleton's first attachment and sizes the depth-zero branch chain from the same trunk taper. This removes the exposed pole through upper crowns while keeping child forks attached. Curved sweeps and blended fork normals remain open.
1. Replace the per-edge straight tube with a **per-branch sweep**: build a Catmull-Rom spline through the branch's node positions (a branch = a node chain until the next fork), generate rings with parallel-transport frames, taper along the spline, 5 to 12 radial segments by LOD.
2. At forks, start the child's first ring on the parent surface (offset along the parent normal by the parent radius) and blend vertex normals across the junction so no seam shows under the cel ramp.
3. **Root flare and buttresses** on the trunk base (a radial function of height and a hashed lobe count), and a slight trunk twist.
4. Bark parameterization: arc-length `v` and angular `u` in `uv` so the existing bark shader (`tag >= 20`) can follow the grain; keep the negative-UV sentinel scheme.
5. Keep the collision detail as the current low-poly tube (`Detail.collision`) so physics tests and walkable surfaces do not change; the visual mesh and collision mesh may diverge slightly within a stated tolerance, and a test asserts the maximum deviation.

**5c. Foliage v2:**
1. **Current:** compact polygon leaf fans are grouped around terminal and selected sub-terminal anchors from the shared skeleton. Species select ovate, lanceolate, scale, fan, cascade or blossom outlines; conifers use radial needle sprays. A wide lineup review exposed sparse crowns in most deciduous species, so willow, copper-fan, moon-cascade and star-blossom now use one additional recursive branch tier with fewer leaves per anchor to bound mesh growth. Recheck the capture before tuning leaf sizes or adding LOD; share this with Arbors only after the branch-attachment/save review in 5a.
2. **Soft cel lighting with cluster normals:** set every vertex normal in a cluster to a blend of the cluster's outward direction and the leaf plane normal (about 70% outward), so a crown shades as a few large volumes with a ragged edge, not as thousands of lit facets. This is the main way to get a painted-crown look under a three-band ramp.
3. **Per-cluster colour** from height in the crown, sun side and a hashed hue shift; add a subtle **interior darkening** (cheap ambient occlusion) by darkening clusters whose centre is closer to the crown centroid.
4. If S2 passes, optionally use alpha-cutout leaf textures procedurally generated in the shader (leaf outline from the fan's UV); otherwise keep geometry-only clusters.
5. Make the crowns **connected to the skeleton**: every cluster's anchor is a node position with a short stalk limb (the "avoid isolated green caps" rule in [world](../world.md)).

**5d. Forest tree species and variants:**
1. The eight scattered species now share the bounded L-system skeleton and branch/foliage output contract. Deciduous species have distinct leaf profiles; needleleaf and pine use radial two-sided needle sprays and separate whorled branch grammars. Pine and needleleaf alternate recursive branch whorls around the trunk instead of growing in one plane. Review species at `-Dshowcase=62`, pine close-up at `-Dshowcase=74`, and moon-cascade at `-Dshowcase=75`. The lineup previously showed several sparse crowns at a distance; verify close-up leaf attachment, then tune taper, whorl spacing, crown spread and needle density. Preserve names, palette and night-flora behaviour (`Vegetation.colors`, `trunk_colors`, `tree_variants`).
2. Build **four variants per species** at catalog load from different seeds (a fixed `variant_seed` table, deterministic). Scatter picks a variant by hash; the instance `variant` field already exists, so extend `tree_variants` into `(species, shape)` indexing with stable ids. Saves record `variant`, so keep old ids valid and append new ones.
3. Build **three LODs** per variant: `near` (full detail, 12,000 triangles or fewer for a giant), `mid` (about 25%, simplified sweeps and 40% fewer clusters, with clusters enlarged), `far` (about 300 triangles: trunk as a 4-sided taper and the crown as 6 to 10 large lobes). If S3 passes, add an impostor card ring beyond 700 m.
4. LOD selection by distance per **chunk cell**, as `Field.zig` does, so selection costs one test per cell, with a hysteresis band to avoid popping. Use the instance `stretch.w` radius so the vertex stage culls individual instances.
5. Retire the ellipsoid-stack crowns. Keep the old meshes behind a debug option for one release to compare captures.

**5f. Skeleton-driven rendering (optional, after 5a and 5b).** Instead of baking every tree to a mesh, ship the skeleton: one 64-byte instance per branch segment (about 12 KB for a full Arbor, against roughly 1 MB baked) and expand the tubes in a spliced vertex stage, with ring sides chosen per segment from distance and a frame-time governor. This reaches the memory and continuous-level-of-detail goals of a GPU work-graph pipeline without work graphs, which Mach does not expose; the evaluation, measurements, compiled reference code and milestone (M9) are in [mesheditor.md](mesheditor.md#414-procedural-recipe-meshes-evaluating-a-gpu-work-graph-pipeline). Keep baked meshes for the far level of detail.

**5e. Tests for Phase 5:** skeleton validity (acyclic, bounded, finite, parent-first) for every genome in a table; pipe-model radius monotonicity (parent radius is at least each child's); mesh finite and index-in-range for every species, variant and LOD (the test added on 2026-10-13 for broadleaf generalizes); triangle budgets per LOD; reproducibility; attachment queries return the same nodes after the generator change for a fixed fixture; collision mesh deviation bound; allocation-failure test for every mesh builder (`checkAllAllocationFailures`, as `Arbor.mesh` already does).

Acceptance: captures 70 and 62 at frames 120 and 480 show connected, tapering limbs, clustered crowns and four distinguishable variants per species; vertex budgets per LOD hold.

### Current review findings — 2026-10-14

- Side-view captures showed foliage disappearing on upright species because leaf-card planes used the branch tangent as their face normal. Leaf geometry now follows the twig along its long axis and rotates the face around that axis. Close moon-cascade capture 75 shows leaves attached along the branches; capture 62 shows willow, fan, cascade and blossom crowns at lineup distance.
- Added species-specific leaf profiles and an additional recursive fork tier to willow, copper-fan, moon-cascade and star-blossom. Redwood now uses balanced radial forks and a denser scale-leaf cluster for a fuller high crown.
- The main stem is now one connected ring sweep from a small root flare through the L-system's depth-zero branches. Transported frames and a shared ring at each axis point remove the bright seams between stacked trunk cylinders. Main-stem tiers rotate around the crown instead of repeating one branch wedge. The skeleton test checks that each child fork starts at its parent's endpoint; the mesh test checks finite geometry and valid indices across all eight species.
- Needleleaf has broader cluster coverage, and both conifers use two crossed needle planes per spray for side-view readability. A third spray anchor near each secondary branch base fills some bare bough gaps. The 600-frame nature benchmark passes, but its 12.25 million submitted triangles make distance-based foliage and branch LOD the next performance priority.
- Remaining review gaps: needleleaf and moon-cascade may still be sparse in the wide lineup, all crowns need regular-gameplay-distance review, and side-branch junctions remain separate tapered tubes. Capture 62 is a composition aid rather than an art-quality bar for fine leaf shapes.

### Phase 6. Lighting: shadows and occlusion within the cel look (M to L)

Purpose: ground contact and depth cues. Gate on spike S1.

**If S1 passes (shadow map):**
1. Add one directional-light **cascade** (about 160 m, 2048²) rendering terrain, trees and props depth-only; a second cascade (about 600 m, 1024²) if the cost allows. Re-render each cascade only when the sun or camera moves past a texel snap.
2. Sample with a 3×3 percentile-closer filter; quantize the result into the cel ramp (a hard band, not a soft penumbra) so shadows match the toon look. Use a normal-offset bias.
3. Trees receive and cast; grass receives only (cast off), to keep the cost bounded.

**If S1 fails (analytic fallback):**
1. A **canopy shadow field**: per chunk, a coarse grid (16×16 cells, 8 m) of canopy coverage computed in the scatter worker from tree positions and crown radii. The terrain and grass fragment stages sample it by world position (a small uniform or storage buffer indexed by chunk) and darken one cel band. Cheap, deterministic, good enough for forest floors.

**Either way:**
1. **Baked vertex ambient occlusion** in tree meshes (crown interior, trunk base) from the skeleton: occlusion is the density of nearby nodes and clusters within a radius, computed at generation.
2. **Terrain AO** from the heightfield: concavity from curvature (Phase 2), darkening in gullies.
3. Tests: bias constants, cascade matrix finite and stable, sampled shadow terms in [0, 1], and the canopy field is deterministic and seam-free. Capture 72 and 71 under dusk and midday lighting.

### Phase 7. Far field and atmosphere (M)

Purpose: the world reads beyond 256 m instead of fading into haze at 320 m.

1. **Terrain LOD rings**: beyond the 5×5 near chunks, draw coarser chunk meshes (spacing 4 m, then 8 m, then 16 m) out to about 2 km. Reuse `Chunk.fill` with a `lod` parameter that changes the vertex spacing but samples the same `Noise.height`, so shape agrees. Stitch seams with skirts or edge-vertex snapping to the coarser grid. Memory: increase the streamer ring counts in [Streamer.zig](../../src/world/Streamer.zig) with new pools sized as constants; do not enlarge module state on the stack.
2. **Far trees**: a sparse low-LOD instance layer beyond 400 m driven by the Phase 3 forest density field, drawn as the `far` LOD and fading in with dither or by tint toward haze.
3. **Atmosphere**: keep the height-aware haze, retune colours per time of day, add a thin distance-based desaturation and a sun-side glow. Do not add bloom ([visual direction](visual-direction.md)).
4. Tests: LOD height agreement with the near mesh at shared vertices (within tolerance), seam closure (no gap larger than a stated bound), pool capacity assertions, streaming never exceeds its budget over a long route.

Acceptance: capture 73 and 41 show continuous terrain to the far panorama; the benchmark shows streaming within budget.

### Phase 8. Living nature (S to M, repeatable)

- **Wind unification**: one shared wind function and a per-frame `WindState` uniform (direction, strength, gust phase) used by trees, grass and water ripples.
- **Weather and seasons** (full design in [weather and seasons](weather-seasons.md)): rain wetness (darken and add a specular band on terrain and bark), snowfall accumulation on flat tree surfaces and ground, autumn tint on a time-of-year parameter. These are the roadmap's "snowfall and rain with the day cycle" items.
- **Interaction**: footprints and wakes (roadmap Next), tree-hit shake from combat, harvest and graft animations on Arbors.
- **Wildlife and pollinators** attach to the Phase 3 ecology fields (habitat per species).

## 7. Cross-cutting work

### 7.1 Performance budgets

| Item | Budget | Measured by |
| --- | --- | --- |
| CPU frame p99 | 16.667 ms (existing budget) | benchmark JSON |
| `Chunk.fill` p99 | no more than 1.5× the Phase 0 baseline | Phase 0 benchmark |
| Grass | ≤ 6,000 patch instances, ≤ 48 blades per near patch | draw plan assertion |
| Trees | triangle caps per LOD (near 12k, mid 3k, far 300) | mesh tests |
| Terrain | 25 near chunks plus far rings within the declared pool sizes | streamer tests |
| GPU time | Metal whole-command-buffer duration p50/p95/p99 from completed command buffers; per-pass timing unavailable | benchmark report |

Upstream candidate: implement per-pass timestamp queries on the Metal backend in the fork, as already noted in [alignment](alignment.md#mach-tracking), so grass and shadow costs can be isolated instead of inferred from whole-command-buffer duration.

### 7.2 Save and generator versioning

| Phase | World-changing | Bump | Migration |
| --- | --- | --- | --- |
| 1 Terrain height | yes | `Seed.generator_version` | existing generator-mismatch path; round-trip test |
| 2 Materials and rivers | footing and carves | same bump if shipped with 1, else a new bump | as above |
| 3 Scatter ecology | `local_id` semantics | bump | drop saved scatter removals, with a log line and a test |
| 4 Grass | no (render only) | none | none |
| 5 Trees v2 | Arbor growth and variants | `Arbor.generator_version` | **decision needed**: reject old saves (`error.GeneratorMismatch`) vs a migration that re-resolves saved tap and graft node ids by nearest position within a tolerance |
| 6 to 8 | no | none | none |

Never silently change a generator without the bump; `docs/validation.md` records each decision.

### 7.3 Test strategy

- **Property tests** over many seeds and chunks: finiteness, bounds, seam equality, determinism, density ranges.
- **Golden numbers, not golden images**: record vertex and triangle counts per mesh and LOD; fail on unexpected jumps.
- **Allocation-failure tests** for every new mesh builder (`std.testing.checkAllAllocationFailures`).
- **Shader compile tests**: every new WGSL stage is spliced and compiled in a test so a Mach WGSL limitation fails in CI, not at runtime.
- **Captures**: every visual change gets a capture of the relevant showcase **at frame 120 and a later frame**, looked at, not just compiled. Use `MTL_DEBUG_LAYER=1`.
- **Cross-compile**: after touching shared code, run Linux (Vulkan) and Windows (D3D12) compile checks per [building and testing](../building-and-testing.md).

### 7.4 Documentation to update with each phase

[roadmap](../roadmap.md) (the Nature section's "Next" list points here), [architecture](../architecture.md) (terrain, scatter, foliage and shader sections), [world](../world.md) (Arbor and forest descriptions), [validation](../validation.md) (measured numbers and what was not run), and [building and testing](../building-and-testing.md) (new showcases and flags).

## 8. Decisions that need the project owner

Per [AGENTS.md](../../AGENTS.md), large creative and save-affecting choices are not made by an agent alone:

1. **Draw distance target.** Keep about 320 m with haze (cheapest), or push to about 2 km (Phase 7, a moderate memory and streaming cost). Recommendation: do Phase 7 after Phases 1 and 4.
2. **Shadows.** Adopt real shadow maps if S1 passes (Phase 6), or accept the analytic canopy shadow. Recommendation: shadow maps for the near cascade only.
3. **Arbor save compatibility** (Phase 5): reject old saves or write a node-id migration. Recommendation: migration by nearest node within a tolerance, with a test, because players have taps on trees.
4. **Grass height and density as gameplay.** Near cover is capped at 0.7 m for combat readability; confirm that is acceptable or set a graphics-option scale.
5. **Terrain character.** Derivative-damped fractal relief gives eroded, rugged land; confirm the desired mood (softer, more storybook hills are a gain and amplitude setting, not a code change).

## 9. Suggested order and checkpoints

1. Phase 0, then spikes S1 to S3 (a short, parallel-safe start).
2. Phase 4 (grass) first among the visible changes: the biggest visual jump per unit of risk, since it touches no saves.
3. Phase 1 and Phase 2 together (one generator bump), then Phase 3.
4. Phase 5 in slices: 5a and 5b for Arbors first (visible in showcase 70), then 5c, then 5d.
5. Phase 6, Phase 7, Phase 8 as the budget allows.

Checkpoint after each phase: default-pair `build check`, the headless suite, the Metal smoke under `MTL_DEBUG_LAYER=1`, the captures named in the phase, the 0.17 check, and a dated entry in [validation](../validation.md) saying what ran and what did not. Reinstall with `python3 tools/zig.py build -Doptimize=ReleaseFast` before handing the game over.

## 10. Risk register

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Grass vertex cost exceeds budget | medium | frame time | density and blade-count constants; shader-side index culling; per-LOD patch meshes |
| Terrain change breaks the hub, city or caves | medium | high | keep the `relief` mask, recompute and test `hub_height_upper_bound`, run district and cave tests, compare captures 7 and 42 |
| Mach lacks depth pass, `discard` or off-screen targets | unknown | design | spikes S1 to S3 with named fallbacks; log upstream candidates in `FORK.md` |
| Arbor regrowth invalidates saved taps and grafts | high | save compatibility | owner decision 3; migration test using a saved fixture |
| Scatter id change drops saved removals | certain if shipped | minor | explicit migration and log line |
| Module state overflow in Debug | low | crash | heap pools for grass cells and far chunks; one Debug launch per phase |
| Capture nondeterminism returns | low | misleading evidence | fixed showcase pose re-applied after sim steps (done 2026-10-13); capture two frames |
| Scope creep | medium | schedule | each phase is shippable alone; do not start Phase 6 to 8 before the earlier visuals land |

## 11. Definition of done for the whole upgrade

- A ground-level capture shows continuous wind-swept grass with trample, biome-tinted, with a smooth falloff to terrain shading.
- A forest capture shows groves, clearings, layered understory, four visible variants per species, connected tapered limbs and clustered crowns, with three LODs and no visible popping.
- Terrain captures show eroded ridge and valley structure, soil, moss, scree and wet banks, with no lattice alignment.
- Trees and ground carry shadow or occlusion cues in the cel style.
- All numbers in section 7.1 hold, recorded in [validation](../validation.md).
- Tests, Metal-validated smoke, the 0.17 check and cross-compiles pass; every skipped step is stated.
