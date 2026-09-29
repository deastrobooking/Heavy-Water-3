# Assets

Terrain, relic and vegetation meshes, the checker texture, and debug glyphs are generated in code. WGSL lives in `src/render/` and is embedded by the renderer.

`source/` holds authored glTF 2.0 content. The build runs `asset-compiler` (from `src/asset_compiler.zig`) on each source file and embeds the resulting `HWMS` runtime model; `zig build assets` also installs them in `zig-out/assets/` for inspection.

Supported input: `.gltf` with base64 data-URI or relative external buffers, and `.glb`; triangle primitives with `POSITION` and `NORMAL` (float), optional `TEXCOORD_0`; `u8`/`u16`/`u32` or absent indices; node TRS or matrix transforms (baked, including mirrored ones); `baseColorFactor` per material. Textures, skins, morph targets, sparse and normalized accessors, required extensions, and URIs outside the source directory are rejected.

`source/blueprints/` holds machine blueprints (JSON format v1, documented in [architecture](../docs/architecture.md#machines)). The build validates each one with `asset-compiler`, and an invalid blueprint fails the build.

- `source/blueprints/powered_door.json`: a wall with a doorway, a 200 W generator, a button (on the −z face) that toggles a latch, a proximity sensor on the +z side, a logic OR, and a sliding door actuator.
- `source/blueprints/elevator.json`: a base, a 4.2 m landing tower, a 250 W generator, call buttons at the bottom and top, a logic OR into a latch, and a platform actuator with 3.9 m of travel.
- `source/crate.gltf`: the supply crate (1.06 × 0.8 × 1.06 m), two materials (`hull`, `band`), one planar and one interleaved buffer view.

Changing the runtime layout means bumping `Model.format_version`. Changing what shipped content means (IDs, dimensions) means bumping `Catalog.content_version`, which invalidates saves.
