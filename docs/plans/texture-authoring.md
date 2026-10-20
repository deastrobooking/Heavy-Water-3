# Texture reuse and nature surface tools

**Status:** researched feature map, 2026-10-20. This records the intended feature set and order; it does not claim that any of the planned texture authoring tools are implemented. It supports the [asset studio](asset-studio.md) and [nature upgrade](nature-upgrade.md). The [roadmap](../roadmap.md) remains the single plan.

## Goal

Make the game's existing images go further. A small, curated set of albedo, normal, and mask sources should produce varied forest ground, bark, leaves, stone, snow, and ice through reusable mapping, seeded fractal detail, and material rules. The result must retain Heavy Water's painterly cel lighting and remain deterministic across chunks and machines.

The target is not to recreate Unity's complete editor. Adopt the surface and foliage workflows that solve our actual gaps, and keep their controls as simple presets, brushes, and sliders. A node graph can expose advanced combinations later.

## What Heavy Water has today

| Area | Current state |
| --- | --- |
| Mesh coordinates | `Mesh.Vertex` carries UVs. Meshes and the glTF reader can contain UV data. |
| Imported image textures | `Gltf.zig` reports images and texture counts but the runtime model keeps base-colour factors only; source texture images are not imported into the game's material path. |
| Runtime material | `Model.Material` stores a base colour and name. Instances primarily use colour tint and procedural shading. |
| Renderer texture bindings | The shared scene bind group has one sampled surface image (binding 1). It holds the 512×512 Antarctic glacier albedo and is used by special-case ice shading, not as a general material library. That ice path already samples world-space triplanar (three reads at a 256 m tile, `scene.wgsl`), so T1's projection modes have a working precedent to generalise. |
| Reusable surface variation | The cel shader already has seeded/world-space value noise for foliage, bark, terrain, and ice. There is no general material recipe, UV mirror mode, terrain weight painting, or material texture stack. |
| In-game editing | VERTEX TOOLS (mesh editor E1–E4, S1–S5) paints per-vertex colour, cel pens and skin weights with brushes, gradients (linear, radial, height, edge/cavity) and posterize, and edits geometry and topology. Its mirror symmetry is geometry-space, not mirrored image tiling, and nothing it does reads or writes an image texture; vertex colour stays the deferred-texturing source that a T4 bake would turn into a texture. |

Code references: [Mesh.zig](../../src/render/Mesh.zig), [Model.zig](../../src/asset/Model.zig), [Gltf.zig](../../src/asset/Gltf.zig), [Renderer.zig](../../src/render/Renderer.zig), [scene.wgsl](../../src/render/scene.wgsl), [MeshTools.zig](../../src/game/MeshTools.zig), and [MeshEdit.zig](../../src/asset/MeshEdit.zig).

## Research: useful ideas from other tools

| Tool | Existing workflow worth borrowing | Heavy Water adaptation |
| --- | --- | --- |
| Unity | Reusable Terrain Layer assets carry diffuse, normal and mask inputs plus terrain-space tile size/offset. Artists paint layers with texture brushes. Texture import supports repeat, clamp, and mirror wrap modes; terrain detail tools paint grass textures or instanced detail meshes with randomized size, colour, and placement. | Reusable `SurfaceRecipe` assets, repeat/mirror sampling, a terrain material brush, and the existing deterministic scatter system with artist-authored density rules. Keep a low fixed layer count and use our own chunk seams and save rules. |
| Unreal Engine | Material Functions package reusable operations; world-aligned textures avoid authored UV dependence; detail texturing layers a high-frequency diffuse/normal over a base; landscape layers support weight/height blending; Texture Graph supports reusable subgraphs and texture bombing to reduce obvious repeats. | Preset operations rather than an unrestricted graph first: UV/world/local projection, texture bombing from one source image, 2–3 octave procedural breakup, and height-aware material transitions. Keep functions compiled into the existing WGSL pipeline. |
| Godot | Standard materials expose primary and secondary albedo/normal detail, UV scale/offset, object-space or world-space triplanar projection, and seamless noise textures. Its docs call out that triplanar reads the source along three axes and costs more than ordinary UV sampling. | Offer triplanar for rocks, cliffs, and irregular trunks, with object-space mapping as the default for moving meshes. Use UV sampling for leaves and crisp authored details; make the higher sampling cost visible in the preview. |
| Blender | Texture Paint can tile strokes across image edges for seamless authoring; procedural Noise Texture exposes fractal detail, roughness, lacunarity, and distortion; Geometry Nodes packages reusable procedural operations. | Keep Blender as the recommended tool for complex UV authoring. Borrow a small seamless-tile review canvas and portable recipe parameters, not Blender's open-ended node/editor complexity. |

References: [Unity Terrain Layers](https://docs.unity3d.com/6000.0/Documentation/Manual/class-TerrainLayer.html), [Unity texture wrap modes](https://docs.unity3d.com/ja/current/ScriptReference/TextureImporter-wrapMode.html), [Unity grass and detail painting](https://docs.unity3d.com/cn/6000.0/Manual/terrain-Grass.html), [Unreal texturing material functions](https://dev.epicgames.com/documentation/unreal-engine/texturing-material-functions-in-unreal-engine), [Unreal Texture Graph](https://dev.epicgames.com/documentation/en-us/unreal-engine/getting-started-with-texture-graph-in-unreal-engine), [Unreal landscape layers](https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-material-expressions-in-unreal-engine), [Godot StandardMaterial3D](https://docs.godotengine.org/en/4.2/tutorials/3d/standard_material_3d.html), [Godot seamless NoiseTexture3D](https://docs.godotengine.org/en/stable/classes/class_noisetexture3d.html), [Blender texture tiling](https://docs.blender.org/manual/en/latest/sculpt_paint/texture_paint/tool_settings/tiling.html), and [Blender fractal Noise Texture](https://docs.blender.org/manual/id/4.0/modeling/geometry_nodes/texture/noise.html).

## Feature map

### T0 — Runtime texture and material assets

**Purpose:** let the renderer use more than the one hard-coded Antarctic image.

- Add versioned texture metadata for source identity, colour space, channel meaning, mip policy, and wrap mode. Albedo is sRGB; masks and normal data remain linear.
- Add a small `SurfaceRecipe` format that references images by stable asset GUID and stores tint, UV/world/object mapping, tiling, offset, rotation, and optional detail settings.
- Extend the asset loader and manifest so texture assets resolve before dependent material recipes. Keep the original image source immutable and the import/bake outputs reproducible.
- Replace the tint-alpha ice selector with a material/recipe choice. Keep an explicit fallback colour for missing or unsupported texture data.
- Import glTF base-colour textures for static models when supported; preserve a clear report for unsupported samplers, image formats, and extensions.

**Gate:** a single Antarctic ice surface and a single imported static model render through the normal material path, without changing existing untextured models or special character cel pens.

### T1 — Reuse one image without visible repetition

**Purpose:** make one tile cover large or irregular surfaces at several scales.

- UV operators: tile scale, offset, rotation, repeat, clamp, mirror-repeat per axis, and a preview of tile boundaries.
- Projection: authored UV, object-space triplanar, and world-space triplanar. Moving assets default to object-space mapping so the pattern follows the asset rather than sliding through the world.
- Seeded texture bombing: select a deterministic offset, rotation, and optional mirror for each UV/world-space cell; blend cell borders softly. This breaks obvious repeated motifs while still sampling the same source image.
- Add a coarse macro tint/noise layer and one fine detail layer. Fade fine detail with distance and use mipmaps; do not add unbounded texture lookups per pixel.
- Support image mirroring in both places artists expect it: mirror repeat in material sampling, and mirrored tile/edge strokes in a later 2D texture canvas.

**Gate:** rock, bark, and ice look continuous over a multi-chunk surface; a stationary world-space surface does not swim, and a moving prop keeps its texture attached.

### T2 — Fractal material breakup and natural blending

**Purpose:** make a few source tiles read as different natural surfaces rather than one repeated picture.

- Define deterministic fractal noise parameters: seed, base scale, octave count, lacunarity, amplitude falloff, and optional ridged/turbulence remap. Keep octave counts small and bounded.
- Use a low-frequency macro field for broad hue/value patches and one fine field for pores, leaf clumps, bark grain, or snow sparkle. Coordinate domains wrap or derive from chunk-stable integer cells to prevent precision loss at far world coordinates.
- Blend a small number of material roles with masks from surface slope, height, biome moisture/temperature, and optional hand-painted weights. Start with grass/soil/rock/moss/snow; keep shoreline wetness and erosion as later masks.
- Height blending should use a mask channel only where it improves natural transitions, such as moss over stone or snow over soil. Preserve the cel ramp and avoid adding generic PBR controls that the renderer cannot use.
- Add per-instance seeded hue, scale, and rotation variation to nature assets, sharing the same `SurfaceRecipe` rather than copying textures per species.

**Gate:** the same small source set makes recognizable grass, damp soil, mossy stone, bare rock, and snow transitions in a fixed daylight capture, without visible chunk seams or moiré.

### T3 — Terrain surface painting and automatic masks

**Purpose:** combine procedural distribution with direct art direction.

- Terrain material brush: paint, erase, smooth, sample, and limit strength. Use texture-shaped brushes, adjustable radius/falloff, undo, and mirrored strokes for symmetric test assets.
- Store weights in a versioned low-resolution chunk map or deterministic sparse stroke list. Choose the representation only after measuring save size, load time, and seam behavior across neighboring chunks.
- Layer procedural defaults under painted overrides. When the brush is not used, biome, slope, elevation, and moisture rules remain the source of coverage.
- Add surface preview views for layer weights, slope, biome masks, macro noise, and final composite. These are needed to diagnose placement and seams before adding more controls.
- Nature scatter uses compatible paint/mask values for grass, ferns, flowers, shrubs, and trees; retain stable instance IDs and generator-version migrations for saved removals.

**Gate:** a hand-painted path edge crosses a chunk seam cleanly, survives save/load, and does not cause existing deterministic scatter identities to move unexpectedly.

### T4 — Texture canvas and bake/export

**Purpose:** make or repair compact source images without replacing Blender or adding hidden runtime cost.

- Tile canvas with wrap preview, X/Y mirror painting, clone, stamp, soften, and seam diagnostics.
- A texture can be built from a source image plus deterministic noise/tint operations, then exported as a normal image file and a recipe. Do not require generated images at runtime.
- Mesh painting stays separate from terrain painting: UV-aware paint on a selected static mesh is a later editor tab. Bake to a CPU-generated texture with seam padding/dilation on save; never depend on GPU texture readback, which Mach does not expose today.
- Add normal/mask packing only after the runtime shader consumes those channels. Avoid exporting data that renders identically to the base-color-only path.

**Gate:** a repeatable recipe exports the same pixels for the same inputs and seed, and a baked mesh texture has no black/bleeding UV seams at mip levels.

## Suggested delivery order

| Priority | Slice | Why this order |
| --- | --- | --- |
| P0 | T0 minimal runtime path for one reusable albedo recipe | Current renderer has only one special-case image; texture operations cannot be exercised until resources and bindings are general. |
| P1 | T1 mirror/repeat, object/world triplanar, tiling controls, seeded per-cell variation | These provide the most reuse from one source image and directly cover the requested mirroring. |
| P2 | T2 bounded fractal noise and natural surface masks | Builds macro/micro variety on the runtime path before a complex editor UI exists. |
| P3 | T3 chunk-safe terrain paint weights and mask preview | Artists can art-direct the automatic material/scatter distribution. |
| P4 | T4 seamless texture canvas, UV mesh paint, CPU bake and texture export | Valuable authoring, but depends on runtime sampling, UV import, asset persistence, and seam handling. |

The nature studio should show a compact material card first: source images, mapping mode, world tile size, mirror toggle, macro/detail amount, and seed. An advanced view can expose octave and mask thresholds. Keep a preview of one tree bark section, one leaf cluster, a rock, and a 32 m terrain patch at near, mid, and far distances.

## Implementation constraints and deferred features

- Native Zig and WGSL only. No C/C++ image, terrain, or noise libraries.
- No frame-path allocations. Uploads and image processing happen during import, editing, or bake, not per frame.
- Determinism includes source asset GUID, recipe version, seed, world/chunk key, and instance ID. Changing generated terrain/scatter appearance must state whether it changes save-visible IDs.
- Bound material layers and texture samples. Unity's own terrain docs warn that layer count affects rendering cost; Godot explicitly notes triplanar's three texture reads. Make complexity measurable and expose an inexpensive fallback.
- Use local coordinates for moving tree and prop materials; use chunk-stable world coordinates only for fixed terrain surfaces. Avoid world-position float precision loss at Heavy Water's far-separated regions.
- Keep cel lighting, hand-picked palettes, and geometric leaf silhouettes first. Photoreal PBR layers, arbitrary user graphs, GPU texture painting, runtime texture readback, and AI texture generation are outside this feature map.
- Complex UV unwrap and texture painting can continue to use Blender until the native UV canvas has a complete export and mip-seam pipeline.
