# Mesh editor and importer: engineering design

**Status:** M0–M3 implemented, 2026-10-14; M4 is next. Later milestone designs remain planning. M1 adds v2 weld-cell metadata while preserving the v1 index-only analysis path. M3 keeps GPU index and submesh ranges stable by degenerating hidden triangle triplets in place.

**Audience:** low-level Zig game developers working in this repository. It assumes you know `std.mem.Allocator`, `extern struct` layout and the project rules in [AGENTS.md](../../AGENTS.md).

**Relationship to other docs:** [mesh-editor.md](mesh-editor.md) owns the product boundary and the user-facing slices. [asset-pipeline.md](asset-pipeline.md) and [skeletal-animation.md](skeletal-animation.md) own formats and runtime animation. [nature-upgrade.md](nature-upgrade.md) owns the tree and terrain upgrade that section 4.14 plugs into. This document owns the engineering design of the editor itself.

**How the code in this document was checked.** The blocks share one file, so a later block uses helpers from an earlier one (the vector helpers in 4.7 are used by 4.8, and `find` and `merge` in 4.4 by its test).

**Compile check.** Every Zig block labelled *compiled* is a standalone file that passed `zig test` on both the default compiler (`0.16.0-dev.3142+5ccfeb926`) and `HEAVYWATER_ZIG_CHANNEL=0.17` (15 of 15 tests each, across two files). The blocks are illustrations of the design, written against the repository's real data shapes; they are not committed code, and they do not import project modules. Blocks labelled *sketch* are not compiled. Findings are marked **by reading** when they come from reading the code and **reproduced** when a test demonstrates them.

## 1. Summary

What exists:
- A glTF 2.0 importer that bakes node transforms into a flat `HWMS` runtime model and can trace skins ([Gltf.zig](../../src/asset/Gltf.zig), 898 lines).
- A source-linked modifier document that splits a model into disconnected "islands" and lets an author relabel, recolor, scale, offset, hide and assign surfaces to them ([Modifiers.zig](../../src/asset/Modifiers.zig), 415 lines).
- A command-line authoring path (`asset-compiler modifiers`, `modifier-list`, `modifier-edit`, `preview-modified`, `compile-modified`).
- An in-game editor in the Character Designer that selects islands, cycles surfaces, paints palettes, hides parts and saves a sidecar ([Creator.zig](../../src/game/Creator.zig), [App.zig](../../src/App.zig)).

What does not exist: free-text labels in game, in-game scale and offset, picking in the viewport, gizmos, more than one imported asset, runtime skin data, and export. A standalone Mach viewport (`src/MeshEditor.zig`, 313 lines) was added in commit `77651ae` and deleted in `f4e7bea`; it is not in the tree.

Recommendation, in order: harden and test the modifier module first (section 6, M0 and M1), add reversible commands (M2), make previews incremental (M3), then add the library, viewport, gizmos, skin data and export. The incremental bake is implemented; M4 library and stale-source handling is next. Build the viewport inside the game, as one `MeshEditorState` struct that a thin standalone executable can wrap later. Section 4.14 evaluates a GPU work-graph pipeline for procedural trees: adopt its recipe-sized assets and adaptive level of detail through skeleton-driven instanced draws, and do not adopt the work-graph, GPU space-colonization or Zig-to-SPIR-V mechanisms yet.

## 2. Review of what exists

### 2.1 Data flow today

```text
 source.glb / .gltf
        |  Gltf.inspect          -> Trace (modules, skins, joints, notes)   [arena, read-only]
        |  Gltf.compile*         -> Model (HWMS)   node transforms baked, textures dropped
        v
   Model { mesh: Mesh{vertices, indices}, submeshes, materials, bounds }
        |  Modifiers.generate    -> Document (parts = disconnected islands, suggested labels)
        |  Modifiers.analyze     -> Analysis { vertex_parts[], components[] }   (recomputed per call)
        v
   Document  <--- edit(Edit)     one validated command at a time
        |  Modifiers.apply       source geometry: transforms + colour + hide      (offline importer)
        |  Modifiers.recolor     baked geometry:  colour + hide only               (in-game preview)
        v
   Model --encode--> HWMS bytes / .hwmesh     or     Catalog.replaceHandle(captain_test)
```

### 2.2 The runtime model (`HWMS` v1)

Source: [Model.zig](../../src/asset/Model.zig). Little-endian, no padding: magic, `format`, `vertex_stride`, counts, bounds, materials (`base_color [4]f32`, `name [24]u8`), submeshes (`first_index`, `index_count`, `material`), vertices, `u32` indices.

| Property | Value |
| --- | --- |
| Vertex | `Mesh.Vertex = extern struct { position [3]f32, normal [3]f32, uv [2]f32, color [3]f32 }`, 11 floats, 44 bytes |
| Limits | `max_vertices = 1 << 20`, `max_submeshes = 16`, `max_materials = 16` |
| Versioning | any layout change bumps `format_version`; old files are rejected, never reinterpreted |
| Skin data | none: skin weights and joints are discarded at import |
| Tests | round trip, version, truncation, range errors, and decode cleanup on allocation failure |

### 2.3 glTF importer

Source: [Gltf.zig](../../src/asset/Gltf.zig). The file header states the contract: `.gltf` (data URI or resolver-loaded buffers) and `.glb`; triangle primitives with `POSITION` and optional `NORMAL` and `TEXCOORD_0`; `u8`/`u16`/`u32` indices; node TRS or matrix transforms; `baseColorFactor` materials. Textures, skins, morph targets, sparse accessors and extensions are rejected or ignored explicitly in the normal compile path; skins are read for the trace and for the CPU pose preview.

| Entry point | Purpose |
| --- | --- |
| `inspect(arena, source) !Trace` | Source map: modules, skins, joints and parents, dependencies, import notes. `Trace.trace_format = 2` |
| `compile(allocator, source, resolver) !Model` | Static model with node transforms baked |
| `compileBindPosePreview`, `compilePosePreview(.., .bind or .run)` | CPU-skinned static preview: bind pose, or the gameplay run controller's pose evaluated on matching joint names |
| `compileModule(.., ModuleAddress)` | One `(node, primitive)` as its own model (the `split` command) |
| `mappedGameplayJointCount(trace)` | How many of the 7 gameplay run tracks matched joint names (the "RUN RETARGET n/7" status) |
| `externalBuffers`, `traceJson` | Buffer URIs to resolve; trace as JSON with provenance |

Observations (by reading):
- There is no vertex welding. Vertices are emitted as the accessors provide them, so any vertex that glTF duplicated (UV seams, hard edges, flat shading) stays a separate vertex.
- `JOINTS_0` and `WEIGHTS_0` are parsed into the preview path only; the compiled `Model` has nowhere to keep them.
- Vertex colour is not imported; colour comes from `baseColorFactor` per material, and the modifier bake later overwrites it per part.

### 2.4 The modifier document

Source: [Modifiers.zig](../../src/asset/Modifiers.zig).

```zig
pub const Part = struct {
    id: u32,                 // smallest source vertex index in the island: "stable for unchanged source"
    label: []const u8,
    surface: Surface = .armor,        // armor, skin, eyes, energy, neutral
    enabled: bool = true,
    center: [3]f32,
    vertex_count: u32,
    scale: [3]f32 = .{ 1, 1, 1 },
    offset: [3]f32 = .{ 0, 0, 0 },
    color: ?[3]f32 = null,            // per-part override of the surface palette
};
pub const Document = struct {
    format: u32 = format_version,
    weld_cell: ?f32 = null,  // absent in v1; v1 analysis remains index-only
    character_type: CharacterType = .captain,
    source_hash: []const u8,          // "blake3:" + 64 hex, from Meta.hashSource
    overall_scale: f32 = 1,
    skin_color, eye_color, armor_color, energy_color: [3]f32,
    parts: []Part,
};
pub const Edit = union(enum) { label, surface, color, scale, offset, palette };
```

Rules enforced today:

| Value | Rule | Error |
| --- | --- | --- |
| colour channel | finite, 0 to 1 | `InvalidPartColor` |
| part scale | each axis finite, 0.1 to 5 | `InvalidPartTransform` |
| part offset | each axis finite, at most 10 in magnitude | `InvalidPartTransform` |
| label | 1 to 80 bytes, no control characters | `InvalidModifiers` |
| `overall_scale` | finite, greater than 0, at most 100 | `InvalidModifiers` |
| source | `doc.source_hash` must equal the expected hash | `SourceChanged` |
| part set | every analysed island must have a part and the counts must match | `ComponentSetChanged` |

`edit` validates before it mutates, so a rejected command leaves the document unchanged. Part ids are source vertex ids, not list positions.

Analysis: `analyze` runs union-find over vertex indices (`merge` keeps the lower index as root, so the root is the island's smallest vertex index) and returns `vertex_parts` plus per-island count, centre and bounds. It allocates five scratch arrays of vertex length (parents, `f64` sums, mins, maxs, sizes) and frees them before returning; the two returned arrays (`vertex_parts`, `components`) are caller-owned.

The bake order for a vertex in `apply` is:

```text
position' = (center + (position - center) * part.scale) * doc.overall_scale + part.offset
color'    = part.color orelse palette[part.surface]
```

so `offset` is in output space, after the overall scale. `apply` then drops disabled triangles (`filteredIndices`, which also rewrites each submesh range), recomputes all normals with `recalcNormals` and recomputes bounds. `recolor` repeats the colour and filtering steps without any transform, because the in-game base mesh is already baked.

### 2.5 Command-line authoring

Source: [asset_compiler.zig](../../src/asset_compiler.zig).

| Command | Effect |
| --- | --- |
| `modifiers <src> <meta> <out.json>` | create an auto-labelled, source-hash-linked document |
| `modifier-list <json>` | print id, label, surface, vertex count and centre per part |
| `modifier-edit <in> <out> part <id> <property> <values..>` | one validated edit written to a different file (the tool refuses the same path) |
| `modifier-edit <in> <out> palette <slot> r g b` | palette edit |
| `preview-modified <src> <meta> <json> <png> [bind or run]` | render a PNG preview |
| `compile-modified <src> <meta> <json> <out.hwmesh> [bind or run]` | bake a game model |

`editModifiers` parses with `parseFromSliceLeaky` into an arena, so every string in a parsed document belongs to that arena.

### 2.6 The in-game editor

Sources: [Creator.zig](../../src/game/Creator.zig), [App.zig](../../src/App.zig), [Catalog.zig](../../src/asset/Catalog.zig).

- **State** lives in `Creator`: `imported_doc: ?*Modifiers.Document`, `imported_open`, `imported_selected`, `imported_filter` (6 surface filters), `imported_palette`, `imported_palette_variant`, `imported_status` (`ready`, `unsaved`, `saved`), bounded 64-command undo/redo history, and a 96-byte rig status string.
- **Keys:** up and down select, left and right cycle the surface, `p` cycles the palette, `c` paints, `h` hides, `z` undoes and `shift-z` redoes, escape or enter closes. Mouse hit areas map to the same methods; history position and undo/redo buttons are visible in the panel.
- **Files:** the bundled Captain document is `tools/captain/Captain.modifiers.json`; a user override is `saves/captain.modifiers.json`. One imported GLB lives at `saves/imported-character.glb` with `saves/imported-character.modifiers.json` beside it.
- **Limits:** source GLB at most 64 MiB, sidecar at most 1 MiB, the GLB picker (`hw_choose_open_glb`) exists on macOS only.
- **Import** (`importCharacterGlb`): `inspect`, reject if there is no skin, `compilePosePreview(.run)`, hash the source, `generate` the document into `mesh_library_arena`, write the GLB and sidecar, `encode` the model into `mesh_library_base`, queue it for install.
- **Install** (`installImportedCharacter`): `catalog.replaceHandle(allocator, &catalog.content.captain_test, model)`. The imported body type therefore **reuses the Captain's catalog handle**; importing replaces the Captain's mesh for the session.
- **Preview** (`applyMeshLibraryPreview`): when the dirty flag is set, decode the whole base model from `mesh_library_base`, run `recolor` (which calls `analyze`), then install the result.
- **Staleness** (`validMeshLibraryOverride`): a saved sidecar is accepted when `format`, `source_hash` and the part count match and every source part id appears in the override.

### 2.7 Test coverage that exists

| Area | Tests |
| --- | --- |
| `Model` | round trip and rejection cases; decode cleanup on allocation failure |
| `Gltf` | a crate compiles to two material submeshes; hostile inputs rejected |
| `Modifiers` | cube analysis/apply; rejected edit preservation; missing-component and filtered-index validation; allocation cleanup; welding fixture; v1/v2 analysis compatibility; reversible command values; bounded history, coalescing and rejected-command behavior |
| In-game editor | imported keyboard surface edit, undo to byte-identical sidecar state, and redo |

## 3. Findings

Severity is the effect on a user or developer, not the effort to fix.

| ID | Severity | Finding | Evidence |
| --- | --- | --- | --- |
| F1 | High | Island identity breaks on split vertices. `analyze` merges only by shared vertex index, and the importer does not weld, so a mesh exported with UV seams, hard edges or flat shading splits one shell into many islands (up to one per triangle for flat-shaded exports). Labels, hide and paint then act on fragments. The Captain asset is clean, so the shipped path does not show it. **By reading**; the contrast is **reproduced** by the welded-island example in section 4.4. | `Modifiers.analyze`, `merge`; no weld step in `Gltf.zig` |
| F2 | Medium | The bake path resolves `part` per vertex with a linear search: `findPart` and `componentById` inside the per-vertex loops of `apply` and `recolor`, and `findPart` per triangle in `filteredIndices`. Cost is O(vertices x parts); at the 1M vertex limit and a few hundred parts that is hundreds of millions of comparisons per edit. **By reading**; not measured. | `Modifiers.apply`, `recolor`, `filteredIndices` |
| F3 | Medium | Every preview refresh decodes the whole base model, re-runs `analyze` and a full-mesh recolour, then installs the result through `replaceHandle` (a full GPU re-upload), though one edit touches one part. | `App.applyMeshLibraryPreview` |
| F4 | Medium | There is no undo or redo, and `edit` is not invertible (it does not record the previous value). | `Modifiers.edit` |
| F5 | Medium | The importer discards source vertex colours and textures, and the bake overwrites `vertex.color` for every vertex (`.neutral` becomes white). Art authored with painted vertex colours or textures cannot survive the round trip. | `Gltf` header, `Modifiers.apply` |
| F6 | Medium | Imported characters share one catalog slot and one file path, so a second import replaces the first and the Captain's session mesh. This is structural (`content.captain_test`), not only a UI limit. | `App.installImportedCharacter` |
| F7 | Medium | Coverage is thin: one `Modifiers` test, no failure-path tests (rejected edit leaves the document unchanged, `ComponentSetChanged`, filtered indices and submesh ranges, allocation failure), and none for the in-game methods. The project rule is that tests must be able to fail. | section 2.7 |
| F8 | Low | The colour-resolution `switch` on `Surface` is written three times (`apply`, `recolor`, `triangleSurfaceColor`), so a new surface can be added in one and forgotten in another. | `Modifiers.zig` |
| F9 | Low | Label ownership is implicit. `generate` allocates each label individually and `deinit` frees them one by one, but a parsed document is owned by its parse arena and must not be passed to `deinit`; `edit(.label)` allocates a new label and abandons the old one. Every current caller uses an arena, so nothing leaks today. A future caller with a general-purpose allocator would leak or double free. | `Modifiers.edit`, `deinit`; `App`, `asset_compiler` |
| F10 | Low | `validMeshLibraryOverride` is O(parts squared), ignores `character_type`, and does not re-check the value ranges that `apply` checks. | `App.validMeshLibraryOverride` |
| F11 | Low | The sidecar does not record which pose or importer settings produced the geometry, so a change to the pose bake that moves centres cannot be detected; ids stay stable because indices do. | `App.importCharacterGlb` |
| F12 | Low | `format != format_version` is a hard reject with no migration path, which is fine for v1 and a trap for v2. | `Modifiers.apply`, `recolor` |
| F13 | Info | `recalcNormals` replaces all imported normals with area-weighted vertex normals; hard-edge shading from the source is lost, and split vertices stay unsmoothed across the seam. | `Modifiers.recalcNormals` |

## 4. Target design

### 4.1 Goals and non-goals

Goals:
- Edit an imported or generated static model in the game: select by clicking, move, scale, relabel, recolour, hide, undo, redo, save.
- Keep the sidecar as the source of truth and the source asset immutable and hash-linked.
- Keep every edit reversible, validated before it mutates, and cheap enough to preview on every pointer move.
- Carry skin data through unchanged so a rigged mesh stays rigged after edits.

Non-goals (use Blender): topology edits, UV unwrapping, sculpting, weight painting beyond inspection, complex rig authoring. Native Zig only; no C mesh libraries.

### 4.2 Layers

```text
 Source (immutable)     GLB bytes + Blake3 hash                       saves/imports/<id>/source.glb
 Pristine mesh          decoded once, never mutated                   Model (+ SkinData later)
 Analysis (cached)      welded island id per vertex, slots, CSR lists rebuilt only when the source changes
 Document               parts, palette, overall scale                 the sidecar; serialisable, validated
 History                bounded command ring, not persisted           undo and redo
 Bake                   pure function: pristine + document -> Model   incremental per part
 Installed model        what the renderer draws                       Catalog.replaceHandle under the render mutex
 Export                 edited GLB or HWMS                            section 4.13
```

Rule: only the Bake step produces a `Model`, and only the install step touches the catalog. The UI mutates the document through commands and marks parts dirty.

### 4.3 Reversible commands and history

An edit that carries its previous value needs no recomputation to undo. Continuous gestures (a drag, a slider) should coalesce into one history entry.

Design points:
- A command is a value (`union(enum)`), small, and copyable; history is a fixed array (no allocation after startup).
- `push` discards the redo tail and merges into the previous entry when `coalesce` accepts.
- Undo and redo return the command; the caller applies the `before` or `after` side through the same validated path as a fresh edit.
- History is not saved. The sidecar stores state, not the history, so a stale history can never disagree with a reopened document.

*Compiled* (tests included):

```zig
pub const Surface = enum { armor, skin, eyes, energy, neutral };

pub const Command = union(enum) {
    surface: struct { id: u32, before: Surface, after: Surface },
    scale: struct { id: u32, before: [3]f32, after: [3]f32 },
    offset: struct { id: u32, before: [3]f32, after: [3]f32 },
    hidden: struct { id: u32, before: bool, after: bool },

    /// Merges a continuous drag into the previous entry so one gesture is one undo step.
    pub fn coalesce(self: *Command, next: Command) bool {
        switch (self.*) {
            .scale => |*a| switch (next) {
                .scale => |b| if (a.id == b.id) {
                    a.after = b.after;
                    return true;
                },
                else => {},
            },
            .offset => |*a| switch (next) {
                .offset => |b| if (a.id == b.id) {
                    a.after = b.after;
                    return true;
                },
                else => {},
            },
            else => {},
        }
        return false;
    }
};

pub fn History(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        items: [capacity]T = undefined,
        /// Entries that exist; `cursor` of them are applied, the rest are redo.
        len: usize = 0,
        cursor: usize = 0,

        pub fn push(self: *Self, command: T) void {
            self.len = self.cursor; // a new edit discards the redo tail
            if (self.cursor > 0 and self.items[self.cursor - 1].coalesce(command)) return;
            if (self.cursor == capacity) {
                std.mem.copyForwards(T, self.items[0 .. capacity - 1], self.items[1..capacity]);
                self.cursor -= 1;
            }
            self.items[self.cursor] = command;
            self.cursor += 1;
            self.len = self.cursor;
        }
        /// The command to reverse, or null at the start of history.
        pub fn undo(self: *Self) ?T {
            if (self.cursor == 0) return null;
            self.cursor -= 1;
            return self.items[self.cursor];
        }
        /// The command to re-apply, or null at the end of history.
        pub fn redo(self: *Self) ?T {
            if (self.cursor == self.len) return null;
            defer self.cursor += 1;
            return self.items[self.cursor];
        }
    };
}

test "history: undo, redo, coalescing and redo-tail discard" {
    var history: History(Command, 4) = .{};
    history.push(.{ .scale = .{ .id = 7, .before = .{ 1, 1, 1 }, .after = .{ 1, 1.1, 1 } } });
    history.push(.{ .scale = .{ .id = 7, .before = .{ 1, 1.1, 1 }, .after = .{ 1, 1.4, 1 } } });
    try std.testing.expectEqual(@as(usize, 1), history.cursor); // the drag is one entry
    const undone = history.undo().?;
    try std.testing.expectEqual(@as(f32, 1.4), undone.scale.after[1]);
    try std.testing.expectEqual(@as(f32, 1), undone.scale.before[1]); // first `before` kept
    try std.testing.expect(history.undo() == null);
    try std.testing.expect(history.redo() != null);
    _ = history.undo();
    history.push(.{ .hidden = .{ .id = 2, .before = false, .after = true } });
    try std.testing.expect(history.redo() == null); // the old redo entry is gone
    for (0..10) |i| history.push(.{ .surface = .{ .id = @intCast(i), .before = .armor, .after = .skin } });
    try std.testing.expectEqual(@as(usize, 4), history.len); // bounded, oldest dropped
}
```

Tests that must be able to fail: remove the coalescing branch and the "drag is one entry" assertion fails; remove the two `self.len = self.cursor` assignments and the redo-tail assertion fails.

### 4.4 Analysis v2: welded, stable islands

Weld vertices that coincide, then union by triangles. Quantizing positions to a small cell (for example 0.1 mm for a human-scale model) treats a UV seam as one point. The id stays the smallest vertex index in the island, which matches today's ids for meshes that have no split vertices, so existing sidecars keep working.

Care points:
- Quantization cells can straddle a boundary, so two points a hair apart may fall in neighbouring cells and stay unwelded. For this use that is acceptable (an unwelded seam is the status quo); if it matters, also probe the 26 neighbouring cells.
- The weld map is built once per source, not per edit.
- Keep a `weld_cell` field in the sidecar (section 4.10) so the ids a sidecar was authored against can be reproduced.

*Compiled* (the second half of the test reproduces F1: without welding, the seam splits the shell):

```zig
fn find(parents: []u32, index: u32) u32 {
    var root = index;
    while (parents[root] != root) root = parents[root];
    var current = index;
    while (parents[current] != current) {
        const next = parents[current];
        parents[current] = root;
        current = next;
    }
    return root;
}

fn merge(parents: []u32, a: u32, b: u32) void {
    const ra = find(parents, a);
    const rb = find(parents, b);
    if (ra == rb) return;
    if (ra < rb) parents[rb] = ra else parents[ra] = rb;
}

fn quantize(position: [3]f32, cell: f32) [3]i32 {
    return .{
        @intFromFloat(@floor(position[0] / cell)),
        @intFromFloat(@floor(position[1] / cell)),
        @intFromFloat(@floor(position[2] / cell)),
    };
}

/// Island id per vertex, treating vertices at the same quantized position as one point, so UV
/// seams and hard edges do not split a shell. The id is the smallest vertex index in the island,
/// which matches `Modifiers.analyze` for meshes that have no split vertices.
pub fn weldedIslands(allocator: std.mem.Allocator, positions: []const [3]f32, indices: []const u32, cell: f32, out: []u32) !void {
    std.debug.assert(out.len == positions.len and cell > 0);
    const parents = try allocator.alloc(u32, positions.len);
    defer allocator.free(parents);
    for (parents, 0..) |*p, i| p.* = @intCast(i);

    // Weld first: every vertex joins the first vertex seen at its quantized position.
    var first_at: std.AutoHashMapUnmanaged([3]i32, u32) = .empty;
    defer first_at.deinit(allocator);
    for (positions, 0..) |position, i| {
        const entry = try first_at.getOrPut(allocator, quantize(position, cell));
        if (entry.found_existing) merge(parents, entry.value_ptr.*, @intCast(i)) else entry.value_ptr.* = @intCast(i);
    }
    var triangle: usize = 0;
    while (triangle + 2 < indices.len) : (triangle += 3) {
        merge(parents, indices[triangle], indices[triangle + 1]);
        merge(parents, indices[triangle], indices[triangle + 2]);
    }
    for (out, 0..) |*id, i| id.* = find(parents, @intCast(i));
}

test "welded islands: a UV seam does not split a shell, a gap does" {
    // Two triangles share an edge by position but not by index (a seam), a third is far away.
    const positions = [_][3]f32{
        .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, // triangle A
        .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 0 }, // triangle B shares two positions with A
        .{ 5, 0, 0 }, .{ 6, 0, 0 }, .{ 5, 1, 0 }, // triangle C is separate
    };
    const indices = [_]u32{ 0, 1, 2, 3, 4, 5, 6, 7, 8 };
    var ids: [9]u32 = undefined;
    try weldedIslands(std.testing.allocator, &positions, &indices, 0.0001, &ids);
    try std.testing.expectEqual(@as(u32, 0), ids[4]); // B joined A: id is the smallest index
    try std.testing.expectEqual(@as(u32, 6), ids[8]); // C stays alone
    // Without welding, the shared indices alone would leave A and B apart; confirm the contrast.
    var unwelded: [9]u32 = undefined;
    for (&unwelded, 0..) |*p, i| p.* = @intCast(i);
    var t: usize = 0;
    while (t + 2 < indices.len) : (t += 3) {
        merge(&unwelded, indices[t], indices[t + 1]);
        merge(&unwelded, indices[t], indices[t + 2]);
    }
    try std.testing.expect(find(&unwelded, 4) != find(&unwelded, 0));
}
```

For sidecars written before welding, keep reading them with the old analysis: if `weld_cell` is absent, use the vertex-index-only path so ids do not shift.

### 4.5 One bake, driven by slots and per-part vertex lists

Replace the three colour switches and the per-vertex linear searches with:
1. A **slot index**: sort the part ids once and resolve an id to its slot by binary search (F2, F8).
2. **Per-part vertex lists** in compressed row layout, so changing one part walks only that part's vertices (F3).
3. A single `partColor(doc, part)` function used by every path (F8).

*Compiled* (slot lookup, then the per-part vertex lists with an allocation-failure test):

```zig
pub const PartSlots = struct {
    ids: []const u32, // sorted ascending

    pub fn slotOf(self: PartSlots, id: u32) ?usize {
        var lo: usize = 0;
        var hi: usize = self.ids.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.ids[mid] == id) return mid;
            if (self.ids[mid] < id) lo = mid + 1 else hi = mid;
        }
        return null;
    }
};

test "part slots resolve ids in log time" {
    const slots: PartSlots = .{ .ids = &.{ 0, 14, 90, 4071 } };
    try std.testing.expectEqual(@as(?usize, 2), slots.slotOf(90));
    try std.testing.expectEqual(@as(?usize, null), slots.slotOf(91));
}
```

```zig
pub const PartVertices = struct {
    offsets: []u32, // parts + 1 entries; part `slot` owns vertices[offsets[slot]..offsets[slot + 1]]
    vertices: []u32,

    pub fn build(allocator: std.mem.Allocator, slot_of_vertex: []const u32, part_count: usize) !PartVertices {
        const offsets = try allocator.alloc(u32, part_count + 1);
        errdefer allocator.free(offsets);
        @memset(offsets, 0);
        for (slot_of_vertex) |slot| offsets[slot + 1] += 1;
        for (0..part_count) |i| offsets[i + 1] += offsets[i];
        const vertices = try allocator.alloc(u32, slot_of_vertex.len);
        errdefer allocator.free(vertices);
        const cursor = try allocator.dupe(u32, offsets[0..part_count]);
        defer allocator.free(cursor);
        for (slot_of_vertex, 0..) |slot, vertex| {
            vertices[cursor[slot]] = @intCast(vertex);
            cursor[slot] += 1;
        }
        return .{ .offsets = offsets, .vertices = vertices };
    }
    pub fn deinit(self: PartVertices, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.offsets);
    }
    pub fn of(self: PartVertices, slot: usize) []const u32 {
        return self.vertices[self.offsets[slot]..self.offsets[slot + 1]];
    }
};

test "part vertex lists group every vertex exactly once" {
    const slots = [_]u32{ 1, 0, 1, 2, 0, 1 };
    const lists = try PartVertices.build(std.testing.allocator, &slots, 3);
    defer lists.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u32, &.{ 1, 4 }, lists.of(0));
    try std.testing.expectEqualSlices(u32, &.{ 0, 2, 5 }, lists.of(1));
    try std.testing.expectEqualSlices(u32, &.{3}, lists.of(2));
    try std.testing.expectEqual(@as(usize, 6), lists.vertices.len);
}

test "part vertex lists clean up on allocation failure" {
    const slots = [_]u32{ 1, 0, 1, 2, 0, 1 };
    const Probe = struct {
        fn run(allocator: std.mem.Allocator, input: []const u32) !void {
            const lists = try PartVertices.build(allocator, input, 3);
            lists.deinit(allocator);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{@as([]const u32, &slots)});
}
```

*Sketch* (not compiled): the bake entry point and what a dirty-part update does.

```zig
pub const Bake = struct {
    pristine: *const Model,        // decoded once from the source; never mutated
    analysis: Analysis,            // vertex_parts, components (welded)
    slots: PartSlots,              // sorted part ids
    lists: PartVertices,           // per-part vertex lists
    out: Model,                    // the installed model's mesh: same vertex order as pristine
    // Slots follow ascending part id, which is how `generate` orders `Document.parts`.

    /// Re-bake one part. O(vertices in the part), no allocation.
    pub fn updatePart(self: *Bake, doc: Document, slot: usize) void {
        const part = doc.parts[slot];
        const component = self.analysis.components[slot];
        const color = partColor(doc, part);
        for (self.lists.of(slot)) |v| {
            const src = self.pristine.mesh.vertices[v].position;
            for (0..3) |axis| {
                self.out.mesh.vertices[v].position[axis] =
                    (component.center[axis] + (src[axis] - component.center[axis]) * part.scale[axis]) * doc.overall_scale + part.offset[axis];
            }
            self.out.mesh.vertices[v].color = color;
        }
        // Hidden parts: rewrite only this part's triangles in the index buffer (section 4.6),
        // normals: recompute for this part's triangles only, then upload the changed vertex range.
    }
};
```

Changing `overall_scale` or a palette entry dirties many parts; loop over them. The result must equal a full `apply` for any document; a property test asserts equality of positions, colours, indices and normals between the incremental path and a full bake over random edit sequences.

### 4.6 Hiding without re-filtering the whole index buffer

Today `filteredIndices` rebuilds the index buffer and rewrites submesh ranges on every change. Better: keep the pristine index buffer, group triangles by part once, and write each visible part's triangles into a part-ordered output buffer. Hiding a part then rewrites the tail of the buffer from that part on, or, if parts are stored in fixed capacity slots, only that part's range plus a degenerate-triangle fill. Choose the second form if the renderer needs stable ranges: degenerate triangles cost no fragments and keep `Submesh` ranges constant. Measure both against the preview budget before choosing.

### 4.7 Selection and picking

A click needs the nearest part under the cursor. CPU picking is enough and stays off the frame path (it runs on a click, not per frame).

Pipeline:
1. Build the pick ray from the camera: invert the view-projection for the cursor position.
2. Reject parts whose bounds (from `Analysis.components`) the ray misses (slab test).
3. Run Moeller-Trumbore against the surviving parts' triangles; keep the nearest `t`.
4. Map the triangle to its part through `vertex_parts[indices[3 * triangle]]`.

Two-sided intersection is deliberate: orbiting inside a hollow shell must still pick the back face. For parts above a few thousand triangles, build a bounding volume hierarchy lazily on first pick; do not build one for small parts.

*Compiled*:

```zig
pub const Vec = [3]f32;
fn sub(a: Vec, b: Vec) Vec {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn dot(a: Vec, b: Vec) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn cross(a: Vec, b: Vec) Vec {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

/// Moeller-Trumbore. Returns the ray parameter of the hit, or null. Two-sided on purpose: an
/// editor must pick a back face when the player orbits inside a hollow part.
pub fn rayTriangle(origin: Vec, direction: Vec, a: Vec, b: Vec, c: Vec) ?f32 {
    const edge1 = sub(b, a);
    const edge2 = sub(c, a);
    const p = cross(direction, edge2);
    const det = dot(edge1, p);
    if (@abs(det) < 1e-9) return null; // parallel or degenerate
    const inv = 1 / det;
    const to_origin = sub(origin, a);
    const u = dot(to_origin, p) * inv;
    if (u < 0 or u > 1) return null;
    const q = cross(to_origin, edge1);
    const v = dot(direction, q) * inv;
    if (v < 0 or u + v > 1) return null;
    const t = dot(edge2, q) * inv;
    return if (t > 1e-6) t else null;
}

pub const Hit = struct { triangle: usize, t: f32 };

pub fn pickNearest(positions: []const Vec, indices: []const u32, origin: Vec, direction: Vec) ?Hit {
    var best: ?Hit = null;
    var triangle: usize = 0;
    while (triangle * 3 + 2 < indices.len) : (triangle += 1) {
        const a = positions[indices[triangle * 3]];
        const b = positions[indices[triangle * 3 + 1]];
        const c = positions[indices[triangle * 3 + 2]];
        const t = rayTriangle(origin, direction, a, b, c) orelse continue;
        if (best == null or t < best.?.t) best = .{ .triangle = triangle, .t = t };
    }
    return best;
}

test "pick returns the nearest of two stacked triangles and misses outside" {
    const positions = [_]Vec{ .{ 0, 0, 0 }, .{ 2, 0, 0 }, .{ 0, 2, 0 }, .{ 0, 0, 1 }, .{ 2, 0, 1 }, .{ 0, 2, 1 } };
    const indices = [_]u32{ 0, 1, 2, 3, 4, 5 };
    const hit = pickNearest(&positions, &indices, .{ 0.25, 0.25, 5 }, .{ 0, 0, -1 }).?;
    try std.testing.expectEqual(@as(usize, 1), hit.triangle); // z = 1 is closer to the eye at z = 5
    try std.testing.expectApproxEqAbs(@as(f32, 4), hit.t, 1e-5);
    try std.testing.expect(pickNearest(&positions, &indices, .{ 5, 5, 5 }, .{ 0, 0, -1 }) == null);
}
```

### 4.8 Gizmos

A translate gizmo reports the closest point on an axis to the mouse ray; the offset delta is the change in that parameter since the drag began. Scale uses the same parameter relative to the part centre. Each pointer move produces one `offset` or `scale` command that coalesces into the drag's history entry (section 4.3). Snap by rounding the parameter to a step; hold a modifier for fine steps. Numeric fields give exact values and use the same commands.

Because the model is baked, part-local and world axes coincide for the first version. Rotation is out of scope until the format can hold it (the document has no rotation field; adding one is a format bump, section 4.10).

*Compiled*:

```zig
/// Parameter along the axis line (origin + s * axis) closest to the mouse ray. The gizmo adds the
/// difference between this value now and at drag start to the part offset.
pub fn axisParameter(axis_origin: Vec, axis: Vec, ray_origin: Vec, ray_dir: Vec) ?f32 {
    const w = sub(axis_origin, ray_origin);
    const a = dot(axis, axis);
    const b = dot(axis, ray_dir);
    const c = dot(ray_dir, ray_dir);
    const d = dot(axis, w);
    const e = dot(ray_dir, w);
    const denom = a * c - b * b;
    if (@abs(denom) < 1e-8) return null; // ray parallel to the axis: ignore this frame
    return (b * e - c * d) / denom;
}

test "axis drag follows the mouse along x" {
    // Camera above the origin looking down; the ray passes x = 2, so the closest axis point is 2.
    const s = axisParameter(.{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 2, 10, 0 }, .{ 0, -1, 0 }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 2), s, 1e-5);
    try std.testing.expect(axisParameter(.{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 5, 0 }, .{ 1, 0, 0 }) == null);
}
```

### 4.9 Viewport and where the editor lives

| Option | Shape | For | Against |
| --- | --- | --- | --- |
| A. In-game panel (recommended) | Extend the Character Designer: orbit camera, click pick, gizmos, history keys | one renderer, one asset path, preview is the real game model, no second module state | competes with the Designer's layout; needs a dedicated orbit camera and input mode |
| B. Standalone Mach window | A second executable with its own `App` | full-window canvas, can load any file | duplicates the module and input setup and the 8 MB stack concern; this was built once (`MeshEditor.zig`) and removed |

Recommendation: A, with the editor logic in one plain struct that owns no window:

```zig
// sketch
pub const MeshEditorState = struct {
    document: *Document,
    history: History(Command, 256) = .{},
    selected: ?usize = null,     // part slot
    hover: ?usize = null,
    gizmo: ?Gizmo = null,        // active drag
    dirty: DirtyParts,           // bitset or small list of slots needing a re-bake
    status: enum { ready, unsaved, saved, stale } = .ready,

    pub fn apply(self: *MeshEditorState, command: Command) !void { ... }   // validate, mutate, push, mark dirty
    pub fn undo(self: *MeshEditorState) !void { ... }
    pub fn redo(self: *MeshEditorState) !void { ... }
};
```

A thin standalone executable later wraps the same struct; nothing in it imports Mach windowing. This also makes the editor testable headless, which the in-game methods are not today (F7).

### 4.10 Library and the sidecar format (v2)

Replace the single slot with a library directory per imported asset:

```text
saves/imports/<id>/source.glb        immutable source
saves/imports/<id>/edit.json         sidecar v2 (the document)
saves/imports/index.json             id, display name, source hash, last opened
```

`<id>` is a `Guid` ([Guid.zig](../../src/asset/Guid.zig)); the source hash is `Meta.hashSource`. Catalog access must not use a fixed `content.captain_test` field per import; allocate catalog handles dynamically per library entry and bind the selected one to the preview. Changing which body types exist changes the player profile, so bump `Save.format_version`, migrate the old `imported_glb` slot into library entry zero, and add a round-trip test (see the save rules in [AGENTS.md](../../AGENTS.md)).

*Sketch*: sidecar v2. New fields are marked; v1 files parse by defaulting them.

```json
{
  "format": 2,
  "character_type": "captain",
  "source_hash": "blake3:3a1f...",
  "weld_cell": 0.0001,
  "pose": "run",
  "importer": 3,
  "overall_scale": 1.0,
  "skin_color": [0.78, 0.53, 0.39],
  "eye_color": [0.16, 0.78, 0.96],
  "armor_color": [0.22, 0.54, 0.68],
  "energy_color": [0.25, 0.9, 1.0],
  "parts": [
    {
      "id": 912,
      "label": "left shoulder plate",
      "surface": "armor",
      "enabled": true,
      "center": [0.21, 1.42, 0.0],
      "vertex_count": 1388,
      "fingerprint": { "vertices": 1388, "triangles": 2204, "bounds_hash": "9f2c1d70" },
      "scale": [1, 1, 1],
      "offset": [0, 0, 0],
      "color": null
    }
  ]
}
```

New fields and why: `weld_cell` (reproduce analysis, F1), `pose` and `importer` (detect a changed bake, F11), `fingerprint` per part (remap ids after a re-export, below).

Migration: read v1 by defaulting `weld_cell` to absent, `pose` to `"run"` for imported characters and `"bind"` for the Captain, `fingerprint` to null. Write v2 on save. Keep a test that loads a checked-in v1 fixture and compares the baked model with the previous baked output.

**Stale sources.** When the source hash differs, do not discard the user's edits and do not apply them blindly. Mark the entry `stale`, show the reason, and offer re-linking: match each saved part to a new island by `fingerprint` (vertex count, triangle count, and a hash of the bounds quantized to the weld cell), accept only unique matches, and list the rest for the user to resolve. Never replace the working file until the user confirms.

### 4.11 Rig integration (`HWSK`, `HWAN`)

The editor must not break skin data it does not edit. Rules:
1. **Order is sacred.** Part edits change positions and colours only; they never reorder, add or remove vertices, so `joints` and `weights` stay valid. Hiding rewrites indices, not vertices.
2. **Edits happen in bind space.** A part scale or offset is applied to the bind-pose position before skinning; the skin matrices then move the edited vertex as before.
3. **Skin vertex** per [skeletal-animation.md](skeletal-animation.md): the existing 44-byte vertex plus four `u16` joints and four unorm8 weights, 56 bytes. Weights must sum to exactly 255 so the GPU blend stays normalized.
4. **Validation at import**: reject non-finite or negative weights, a vertex with no influence, a joint index outside the skeleton, and a skeleton where a parent does not precede its child.
5. **The editor shows, but does not paint, weights**: a heat-map overlay for the selected joint, a joint picker and socket placement. Painting stays in Blender.

*Compiled* (layout checks the compiler enforces, skeleton validation and weight quantization):

```zig
/// Mesh.Vertex is 11 f32 = 44 bytes. HWSK v1 appends four joint indices and four unorm8 weights.
pub const SkinVertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    color: [3]f32,
    joints: [4]u16,
    weights: [4]u8,
};
comptime {
    std.debug.assert(@sizeOf(SkinVertex) == 44 + 8 + 4);
    std.debug.assert(@offsetOf(SkinVertex, "joints") == 44);
    std.debug.assert(@offsetOf(SkinVertex, "weights") == 52);
}

/// Parent-before-child is the invariant every pose and skin-matrix pass relies on.
pub fn validateSkeleton(parents: []const ?u16, joint_count: usize) !void {
    if (parents.len != joint_count or joint_count == 0 or joint_count > 1024) return error.InvalidSkeleton;
    for (parents, 0..) |parent, joint| {
        if (parent) |p| if (p >= joint) return error.InvalidSkeleton; // forward reference or self
    }
}

test "skeleton validation rejects cycles and forward references" {
    try validateSkeleton(&.{ null, 0, 1, 1 }, 4);
    try std.testing.expectError(error.InvalidSkeleton, validateSkeleton(&.{ null, 2, 1 }, 3));
    try std.testing.expectError(error.InvalidSkeleton, validateSkeleton(&.{ 0, null }, 2));
    try std.testing.expectError(error.InvalidSkeleton, validateSkeleton(&.{}, 0));
}
```

```zig
pub const SkinError = error{NoInfluence};

/// Four float weights to four unorm8 weights that sum to exactly 255 (largest remainder).
pub fn quantizeWeights(weights: [4]f32) SkinError![4]u8 {
    var total: f32 = 0;
    for (weights) |w| {
        if (!std.math.isFinite(w) or w < 0) return error.NoInfluence;
        total += w;
    }
    if (total <= 0) return error.NoInfluence;
    var result: [4]u8 = undefined;
    var remainder: [4]f32 = undefined;
    var sum: u32 = 0;
    for (weights, 0..) |w, i| {
        const scaled = w / total * 255;
        const whole = @floor(scaled);
        result[i] = @intFromFloat(whole);
        remainder[i] = scaled - whole;
        sum += result[i];
    }
    while (sum < 255) : (sum += 1) {
        var best: usize = 0;
        for (remainder, 0..) |r, i| if (r > remainder[best]) {
            best = i;
        };
        result[best] += 1;
        remainder[best] = -1;
    }
    return result;
}

test "quantized weights always sum to 255 and reject empty influence" {
    const q = try quantizeWeights(.{ 0.5, 0.3, 0.2, 0 });
    try std.testing.expectEqual(@as(u32, 255), @as(u32, q[0]) + q[1] + q[2] + q[3]);
    const third = try quantizeWeights(.{ 1, 1, 1, 0 });
    try std.testing.expectEqual(@as(u32, 255), @as(u32, third[0]) + third[1] + third[2] + third[3]);
    try std.testing.expectError(error.NoInfluence, quantizeWeights(.{ 0, 0, 0, 0 }));
    try std.testing.expectError(error.NoInfluence, quantizeWeights(.{ std.math.nan(f32), 1, 0, 0 }));
}
```

### 4.12 Ownership and allocation rules

- One owner per document. The simplest correct form is a document that owns an arena: labels and part storage live and die together, an edit never leaks, and a rejected edit leaves the document unchanged (validate, then allocate, then assign).
- Bound the arena's growth: label edits abandon the previous string until the arena is reset, so cap history (256 commands) and reset the arena by rebuilding the document on save.
- The frame path allocates nothing. Preview updates write into the already-installed model's vertex and index storage, then upload a changed range; installing a new `Model` through `replaceHandle` is reserved for topology-visible changes (hide or unhide) and for loading.

*Compiled*:

```zig
pub const MiniPart = struct { id: u32, label: []const u8 };

pub const OwnedDocument = struct {
    arena: std.heap.ArenaAllocator,
    parts: []MiniPart,

    pub fn init(gpa: std.mem.Allocator, labels: []const []const u8) !OwnedDocument {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        errdefer arena.deinit();
        const parts = try arena.allocator().alloc(MiniPart, labels.len);
        for (parts, labels, 0..) |*part, text, i| part.* = .{ .id = @intCast(i), .label = try arena.allocator().dupe(u8, text) };
        return .{ .arena = arena, .parts = parts };
    }
    pub fn deinit(self: *OwnedDocument) void {
        self.arena.deinit();
    }
    /// Validate first, then allocate, then assign: a rejected label leaves the document unchanged.
    pub fn setLabel(self: *OwnedDocument, id: u32, text: []const u8) !void {
        if (text.len == 0 or text.len > 80) return error.InvalidLabel;
        for (text) |c| if (c < 0x20) return error.InvalidLabel;
        for (self.parts) |*part| if (part.id == id) {
            part.label = try self.arena.allocator().dupe(u8, text);
            return;
        };
        return error.UnknownPart;
    }
};

test "owned document frees every label with one call" {
    var doc = try OwnedDocument.init(std.testing.allocator, &.{ "helmet", "chest" });
    defer doc.deinit();
    try doc.setLabel(1, "chest plate");
    try std.testing.expectEqualStrings("chest plate", doc.parts[1].label);
    try std.testing.expectError(error.InvalidLabel, doc.setLabel(1, ""));
    try std.testing.expectEqualStrings("chest plate", doc.parts[1].label);
    try std.testing.expectError(error.UnknownPart, doc.setLabel(9, "x"));
}
```

### 4.13 Export and the Blender round trip

Two outputs:
1. **Game model** (`HWMS`, `.hwmesh`): the existing `compile-modified` path, now driven by the same `Bake` as the in-game preview, so the two cannot diverge.
2. **Edited GLB**: a minimal writer (one JSON chunk, one binary chunk) emitting positions, normals, UVs, vertex colours, indices and, when present, `JOINTS_0` and `WEIGHTS_0` and the skin. This makes a Blender round trip possible. The edited GLB has a new hash, so it is a new asset: record the original `source_hash` as provenance in the new entry's sidecar, and never overwrite the source.

Round-trip acceptance: export, re-import, and the part count, per-part vertex counts and baked bounds match the pre-export model to within the weld cell.

### 4.14 Procedural recipe meshes: evaluating a GPU work-graph pipeline

**Proposal evaluated (2026-10-14).** A "high-performance hyper-realism" pipeline for procedural trees: GPU work graphs with mesh nodes generate geometry on the GPU with no CPU draw calls; space colonization runs on the GPU; compute kernels are written in Zig and compiled to SPIR-V or PTX; trees are kilobyte-scale procedural recipes instead of gigabytes of mesh; level of detail is continuous and tuned each frame to hold a target frame rate.

The goals are right for this project. The mechanism does not fit the engine it would run on. This section separates the two.

**Evidence gathered here** (macOS aarch64 host, the project's pinned compilers):

| Check | Result |
| --- | --- |
| `zig build-obj -target spirv64-vulkan` on `export fn kernel() callconv(.spirv_kernel) void {}` | The compiler aborted with exit code 245 and wrote an empty file, on the default channel and on 0.17. Same result for `spirv64-opencl` and for a vertex entry point. |
| `-target nvptx64-cuda`, a kernel that writes one float | Binary output is refused (`only '-femit-asm' is supported`). `-femit-asm` produced PTX (`.version 4.1`, `.target sm_52`) on 0.17, and failed on the default channel with `LLVM ERROR: .alias requires PTX version >= 6.3 and sm_30`. PTX runs only on NVIDIA CUDA hardware, which this host does not have. |
| Search of `vendor/mach/src` | No mesh-shader, work-graph or indirect-command-buffer API. `atomicAdd` is marked `unimplemented` in the shader front end (`sysgpu/shader/AstGen.zig`). `dispatchWorkgroupsIndirect` is declared, and compute pipelines exist (the capture pass uses one). |
| Engine facts already recorded | WGSL through Mach's compiler is the only shader path. Indirect draws exist in the fork. Shader atomics, timestamp queries and texture readback are known gaps ([alignment](alignment.md#mach-tracking)). |

Work graphs and mesh nodes are Direct3D 12 features (HLSL shader model 6.8, mesh nodes later). I did not verify them in this repository; that is from public API documentation as I know it, so check the current status before relying on it.

**Verdict, layer by layer:**

| Proposed | Verdict | Reason |
| --- | --- | --- |
| GPU work graphs and mesh nodes | Reject for now | A D3D12-only mechanism. The only backend this project runs and validates is Metal, and Mach exposes neither feature. Adopting it would fork the renderer by backend. |
| Space colonization on the GPU | Reject | Growth is a rare event (load, graft) on at most 192 nodes. The skeleton is gameplay data (sap taps, collision, attachment, saves), so the CPU needs it regardless. A GPU version needs atomics (unimplemented) and readback (a gap). CPU cost is bounded by the constants in `Arbor.grow`: 128 attractors, at most 192 nodes, 28 iterations, about 0.7 million distance tests in the worst case. That is arithmetic from the code, not a measurement; the nature plan's Phase 0 records the real time. |
| Compute kernels in Zig, compiled to SPIR-V or PTX | Defer | Measured above. The project's shaders are WGSL, spliced onto a shared prelude. Revisit when Zig's SPIR-V backend compiles a real kernel and Mach accepts SPIR-V or a Zig-to-WGSL path exists. |
| Kilobyte-scale recipes | **Adopt** | `Arbor.Genome` plus a seed already defines a whole tree. Extend the same idea to the forest species and store recipe, seed and graft deltas, not meshes. |
| Continuous, frame-specific level of detail | **Adopt, CPU-driven** | Per-segment ring sides chosen in the vertex stage, plus a governor on portable CPU frame time. Metal benchmark GPU duration is whole-command-buffer only and is not yet a live per-pass governor signal. |
| Zero CPU draw-call overhead | Not needed | Ranged instanced draws per cell already keep the call count low. Indirect draws exist but cannot be compacted without atomics. |

**What to build instead: skeleton-driven trees.** The memory and level-of-detail goals do not need work graphs. They need the skeleton, not a baked mesh, to be what ships to the GPU.

```text
 Recipe (Genome + seed + graft deltas, under 100 bytes)
        |  Arbor.grow                       CPU, load time or on a graft or editor change
        v
 Skeleton (<= 192 nodes, parent-before-child)  authoritative: physics, sap, attachment, saves
        |  pipe-model radii + parallel-transport frames
        v
 Segment records: one 64-byte Instance per branch segment (12 KB for a full Arbor)
        |  one ranged instanced draw per tree
        v
 branch.wgsl (vertex stage): ring math from the record, ring sides from distance + LOD bias
```

Why it works on the current engine:
- The record reuses `StreamingScene.Instance` (four `vec4`, 64 bytes), so the vertex layout and pipeline layout do not change. A new vertex stage is spliced in place of `vertex_main`, the way `foliage.wgsl` is.
- No storage buffers, atomics or compute are needed: the vertex stage reads only instance attributes.
- Collision keeps using the CPU skeleton and the existing `Detail.collision` mesh, so walkable surfaces do not change.
- The scene's shared vertex stage treats `stretch.w > 0` as a per-instance cull radius; the new stage reinterprets `stretch` as the end point and end radius, and must do its own culling.

**Budget arithmetic** (from the code, not measured): a full-detail Arbor today is about 190 tube edges of 26 vertices each plus leaf lobes of 252 vertices per leaf; with 40 leaves that is about 15,000 vertices and 80,000 indices, on the order of 1 MB at 44 bytes per vertex. The same tree as segment records is 192 x 64 = 12,288 bytes, about 80 times smaller, and the genome that regenerates it is under 100 bytes. The price is vertex-stage work every frame; that must be measured (milestone M9) before the baked path is retired.

*Compiled*: the 64-byte segment record, the frame quaternion, and the CPU reference for the vertex stage (ring vertices on circles perpendicular to the axis, and the level-of-detail snap that collapses extra ring vertices into zero-area triangles). Use this as the golden reference when the WGSL is written:

```zig
/// Same layout as `StreamingScene.Instance`: four vec4, 64 bytes, the vertex stage's instance
/// attributes at locations 3, 4, 6 and 7. A new vertex stage reinterprets the fields.
pub const Instance = extern struct { translation_scale: [4]f32, tint: [4]f32, stretch: [4]f32, rotation: [4]f32 };
comptime {
    std.debug.assert(@sizeOf(Instance) == 64);
}

pub const Segment = struct {
    start: [3]f32,
    end: [3]f32,
    r0: f32, // radius at the start ring (the parent's end radius at a fork)
    r1: f32, // radius at the end ring
    frame: [4]f32, // unit quaternion taking local +Y onto the segment axis
    tint: [4]f32,
};

pub fn pack(s: Segment) Instance {
    return .{
        .translation_scale = .{ s.start[0], s.start[1], s.start[2], s.r0 },
        .tint = s.tint,
        .stretch = .{ s.end[0], s.end[1], s.end[2], s.r1 },
        .rotation = s.frame,
    };
}

fn rotate(q: [4]f32, v: [3]f32) [3]f32 {
    // v' = v + 2w(q x v) + 2 q x (q x v), q = (x, y, z, w)
    const u: [3]f32 = .{ q[0], q[1], q[2] };
    const c1: [3]f32 = .{ u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0] };
    const c2: [3]f32 = .{ u[1] * c1[2] - u[2] * c1[1], u[2] * c1[0] - u[0] * c1[2], u[0] * c1[1] - u[1] * c1[0] };
    return .{ v[0] + 2 * (q[3] * c1[0] + c2[0]), v[1] + 2 * (q[3] * c1[1] + c2[1]), v[2] + 2 * (q[3] * c1[2] + c2[2]) };
}

/// Shortest rotation taking unit vector `a` onto unit vector `b`.
pub fn quatFromTo(a: [3]f32, b: [3]f32) [4]f32 {
    const d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    if (d < -0.999999) { // opposite: turn half a circle about any perpendicular axis
        const axis: [3]f32 = if (@abs(a[0]) < 0.9) .{ 0, a[2], -a[1] } else .{ -a[2], 0, a[0] };
        const n = @sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
        return .{ axis[0] / n, axis[1] / n, axis[2] / n, 0 };
    }
    const c: [3]f32 = .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
    const w = 1 + d;
    const n = @sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2] + w * w);
    return .{ c[0] / n, c[1] / n, c[2] / n, w / n };
}

/// The reference for the vertex stage: ring vertex `side` of `sides_active`, drawn from a mesh
/// with `sides_max` ring vertices. Extra vertices snap to an active one, so they collapse into
/// zero-area triangles; changing `sides_active` per instance is the continuous LOD knob.
pub fn ringVertex(inst: Instance, end_ring: bool, side: u32, sides_max: u32, sides_active: u32) [3]f32 {
    const snapped = (side * sides_active) / sides_max; // 0 .. sides_active - 1
    const angle = 2 * std.math.pi * @as(f32, @floatFromInt(snapped)) / @as(f32, @floatFromInt(sides_active));
    const radius = if (end_ring) inst.stretch[3] else inst.translation_scale[3];
    const local: [3]f32 = .{ @cos(angle) * radius, 0, @sin(angle) * radius };
    const around = rotate(inst.rotation, local);
    const centre = if (end_ring) inst.stretch[0..3].* else inst.translation_scale[0..3].*;
    return .{ centre[0] + around[0], centre[1] + around[1], centre[2] + around[2] };
}

test "segment instance is 64 bytes and its rings are circles perpendicular to the axis" {
    const axis: [3]f32 = .{ 1, 0, 0 };
    const s: Segment = .{ .start = .{ 0, 5, 0 }, .end = .{ 10, 5, 0 }, .r0 = 2, .r1 = 1, .frame = quatFromTo(.{ 0, 1, 0 }, axis), .tint = .{ 0.4, 0.3, 0.2, 1 } };
    const inst = pack(s);
    for (0..12) |i| {
        const p0 = ringVertex(inst, false, @intCast(i), 12, 12);
        const p1 = ringVertex(inst, true, @intCast(i), 12, 12);
        try std.testing.expectApproxEqAbs(@as(f32, 0), p0[0] - 0, 1e-4); // start ring lies in x = 0
        try std.testing.expectApproxEqAbs(@as(f32, 10), p1[0], 1e-4); // end ring lies in x = 10
        try std.testing.expectApproxEqAbs(@as(f32, 2), @sqrt((p0[1] - 5) * (p0[1] - 5) + p0[2] * p0[2]), 1e-4);
        try std.testing.expectApproxEqAbs(@as(f32, 1), @sqrt((p1[1] - 5) * (p1[1] - 5) + p1[2] * p1[2]), 1e-4);
    }
    // LOD: with 4 active sides out of 12, only 4 distinct ring positions remain.
    var distinct: u32 = 0;
    var seen: [12][3]f32 = undefined;
    for (0..12) |i| {
        const p = ringVertex(inst, false, @intCast(i), 12, 4);
        var duplicate = false;
        for (seen[0..distinct]) |q| {
            if (@abs(p[0] - q[0]) + @abs(p[1] - q[1]) + @abs(p[2] - q[2]) < 1e-4) duplicate = true;
        }
        if (!duplicate) {
            seen[distinct] = p;
            distinct += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 4), distinct);
}

test "frame quaternion handles the antiparallel case" {
    const q = quatFromTo(.{ 0, 1, 0 }, .{ 0, -1, 0 });
    const v = rotate(q, .{ 0, 1, 0 });
    try std.testing.expectApproxEqAbs(@as(f32, -1), v[1], 1e-5);
}
```

*Compiled*: area-preserving radii, so a limb thickens where limbs join, instead of the current `parent x 0.85` taper:

```zig
pub const none: u16 = 0xffff;

/// parents[i] < i or `none` (parent-before-child, as in Arbor). Leaves get `tip`; every interior
/// node gets sqrt(sum of its children's squared radii), so cross-section area is conserved.
pub fn pipeRadii(allocator: std.mem.Allocator, parents: []const u16, tip: f32, radii: []f32) !void {
    std.debug.assert(parents.len == radii.len and tip > 0);
    const area = try allocator.alloc(f32, parents.len);
    defer allocator.free(area);
    @memset(area, 0);
    var i = parents.len;
    while (i > 0) {
        i -= 1;
        radii[i] = if (area[i] == 0) tip else @sqrt(area[i]);
        if (parents[i] != none) area[parents[i]] += radii[i] * radii[i];
    }
}

test "pipe model conserves area and never thins toward the root" {
    // 0 is the root; 1 and 2 are its children; 3 and 4 are children of 1.
    const parents = [_]u16{ none, 0, 0, 1, 1 };
    var radii: [5]f32 = undefined;
    try pipeRadii(std.testing.allocator, &parents, 1.0, &radii);
    try std.testing.expectApproxEqAbs(@as(f32, 1), radii[2], 1e-6); // leaf
    try std.testing.expectApproxEqAbs(@sqrt(@as(f32, 2)), radii[1], 1e-6); // two unit leaves
    try std.testing.expectApproxEqAbs(@sqrt(@as(f32, 3)), radii[0], 1e-6); // sqrt(2 + 1)
    for (parents[1..], 1..) |p, child| try std.testing.expect(radii[p] >= radii[child]);
}
```

*Compiled*: the frame-time governor. Raising the bias is fast, lowering it is slow, and a dead band holds steady. It reads portable CPU time; the benchmark's Metal GPU duration is whole-command-buffer and asynchronous:

```zig
/// The governor reads portable CPU frame time. Raising the bias is fast, lowering it is slow, and
/// a dead band between the two holds steady, so detail never oscillates frame to frame. Metal's
/// whole-command-buffer GPU duration is benchmark-only and does not isolate this mesh pass.
pub const Governor = struct {
    bias: f32 = 0, // 0 = full detail; larger values mean coarser levels of detail
    pub const max_bias: f32 = 3;
    pub const target_ms: f32 = 16.667;

    pub fn update(self: *Governor, p99_ms: f32) void {
        if (!std.math.isFinite(p99_ms)) return;
        if (p99_ms > target_ms) {
            self.bias += 0.25; // over budget: react within a few frames
        } else if (p99_ms < target_ms * 0.8) {
            self.bias -= 0.02; // clear headroom: recover over seconds
        }
        self.bias = std.math.clamp(self.bias, 0, max_bias);
    }
    /// Active ring sides for a segment at `distance` metres: halves every doubling of distance
    /// beyond 20 m, shifted by the bias, never below 3.
    pub fn sides(self: Governor, sides_max: u32, distance: f32) u32 {
        const octaves = @max(0, std.math.log2(@max(distance, 1) / 20)) + self.bias;
        const scaled = @as(f32, @floatFromInt(sides_max)) / std.math.pow(f32, 2, octaves);
        return std.math.clamp(@as(u32, @intFromFloat(scaled)), 3, sides_max);
    }
};

test "governor rises fast, recovers slowly, holds in the dead band and clamps" {
    var g: Governor = .{};
    for (0..4) |_| g.update(20);
    try std.testing.expectApproxEqAbs(@as(f32, 1), g.bias, 1e-5);
    g.update(15); // inside the band: unchanged
    try std.testing.expectApproxEqAbs(@as(f32, 1), g.bias, 1e-5);
    g.update(10); // headroom: a small step down
    try std.testing.expectApproxEqAbs(@as(f32, 0.98), g.bias, 1e-5);
    for (0..100) |_| g.update(30);
    try std.testing.expectEqual(Governor.max_bias, g.bias);
    g.update(std.math.nan(f32)); // ignored
    try std.testing.expectEqual(Governor.max_bias, g.bias);
    const near: Governor = .{};
    try std.testing.expectEqual(@as(u32, 12), near.sides(12, 5));
    try std.testing.expect(near.sides(12, 400) < 12);
    try std.testing.expect(near.sides(12, 100000) >= 3);
}
```

**Recipe mode in the editor.** The mesh editor gains a second kind of document: a recipe. Sliders edit genes, the CPU regenerates the skeleton (milliseconds, off the frame path), and the segment records are re-uploaded (kilobytes). The preview is the runtime path, so what the editor shows is what ships. Genes are edited through the same reversible-command history as part edits (section 4.3), validated by the genome's own ranges before anything is assigned. A recipe file is a few hundred bytes of JSON. The mesh bake of section 4.13 produces the far-distance `HWMS` meshes and impostor source from the same recipe.

*Compiled*: a reversible gene edit with validate-then-assign. In the repository, enumerate genes through the reflection shims in `src/compat/`, never a direct `@typeInfo(...).fields` loop:

```zig
pub const Gene = enum { height, base_radius, crown_radius, apical_dominance, phototropism, gravitropism, platform_tendency, ridging };

/// A subset of `Arbor.Genome`, with the ranges `Genome.validate` enforces today.
pub const Genome = struct {
    height: f32 = 380,
    base_radius: f32 = 24,
    crown_radius: f32 = 190,
    apical_dominance: f32 = 0.45,
    phototropism: f32 = 0.35,
    gravitropism: f32 = 0.2,
    platform_tendency: f32 = 0.65,
    ridging: f32 = 0.12,

    pub fn get(self: Genome, gene: Gene) f32 {
        return switch (gene) {
            .height => self.height,
            .base_radius => self.base_radius,
            .crown_radius => self.crown_radius,
            .apical_dominance => self.apical_dominance,
            .phototropism => self.phototropism,
            .gravitropism => self.gravitropism,
            .platform_tendency => self.platform_tendency,
            .ridging => self.ridging,
        };
    }
    pub fn range(gene: Gene) [2]f32 {
        return switch (gene) {
            .height => .{ 300, 600 },
            .base_radius => .{ 20, 50 },
            .crown_radius => .{ 150, 250 },
            else => .{ 0, 1 },
        };
    }
    /// Validate first, then assign: a rejected value leaves the genome untouched.
    pub fn set(self: *Genome, gene: Gene, value: f32) !void {
        const r = range(gene);
        if (!std.math.isFinite(value) or value < r[0] or value > r[1]) return error.InvalidGenome;
        switch (gene) {
            .height => self.height = value,
            .base_radius => self.base_radius = value,
            .crown_radius => self.crown_radius = value,
            .apical_dominance => self.apical_dominance = value,
            .phototropism => self.phototropism = value,
            .gravitropism => self.gravitropism = value,
            .platform_tendency => self.platform_tendency = value,
            .ridging => self.ridging = value,
        }
    }
};

pub const GeneEdit = struct {
    gene: Gene,
    before: f32,
    after: f32,

    pub fn apply(self: GeneEdit, genome: *Genome) !void {
        try genome.set(self.gene, self.after);
    }
    pub fn revert(self: GeneEdit, genome: *Genome) !void {
        try genome.set(self.gene, self.before);
    }
};

test "gene edits validate, apply and revert exactly" {
    var genome: Genome = .{};
    const edit: GeneEdit = .{ .gene = .crown_radius, .before = genome.get(.crown_radius), .after = 230 };
    try edit.apply(&genome);
    try std.testing.expectEqual(@as(f32, 230), genome.crown_radius);
    try edit.revert(&genome);
    try std.testing.expectEqual(@as(f32, 190), genome.crown_radius);
    try std.testing.expectError(error.InvalidGenome, genome.set(.height, 900));
    try std.testing.expectError(error.InvalidGenome, genome.set(.ridging, std.math.nan(f32)));
    try std.testing.expectEqual(@as(f32, 380), genome.height); // unchanged after a rejected edit
}
```

**Open problems this design has to solve:**
- Fork junctions. A child ring starts at the parent's end radius under the pipe model, so a visible step is possible. Blend the first ring of a child toward the parent's radius and share the blended normal.
- Vertex throughput. Each segment draws a two-ring tube of up to 24 triangles; several hundred small trees multiply that. Measure triangles per frame with the benchmark rows added in M9 and tune ring counts per level of detail before widening the use.
- Capacity. Segment records need their own fixed pool and a per-frame cap; do not reuse the scatter instance cap.
- Distant trees stay baked meshes or impostors; the skeleton path serves near and mid range.

**Revisit the rejected mechanisms when** Mach gains shader atomics, indirect compute dispatch that the renderer can drive, and texture-to-buffer readback; or Zig's SPIR-V backend compiles a real kernel and Mach accepts SPIR-V. Then GPU-side mass generation (forests regrown in one dispatch) becomes worth re-measuring against the CPU baseline. A D3D12-only accelerator behind a capability check is a possible later option, never a requirement.

## 5. Interfaces to keep stable

| Interface | Why it must not drift |
| --- | --- |
| `Mesh.Vertex` layout (44 bytes) | `HWMS`, GPU vertex buffers, the importer and the bake all assume it |
| `Model` validation limits | `decode` rejects out-of-range files; the editor must stay inside them |
| `Modifiers.Part.id` meaning (smallest source vertex index) | saved sidecars refer to it; welding must reproduce it for unsplit meshes |
| `Catalog.replaceHandle` under the render mutex | the only safe way to swap a live model; the editor must not write into a model the renderer is drawing |
| sidecar `format` | bump on any field change, read the previous format, test the migration |

## 6. Step-by-step plan

Sizes: S under a day, M a few days, L about a week. Each milestone is shippable alone. Every milestone ends with: the headless suite, the default-pair check, the 0.17 check, the Metal smoke (`MTL_DEBUG_LAYER=1`) when rendering changes, a dated entry in [validation.md](../validation.md), and updates to [mesh-editor.md](mesh-editor.md) and [roadmap.md](../roadmap.md) in the same change.

### M0. Harden and measure what exists (S)

**Status: implemented, 2026-10-14.** `partColor` now owns palette resolution; sorted part slots and binary component lookup remove the per-vertex/per-triangle linear scans. Failure-path tests cover every edit variant, missing components, filtered submesh ranges, and allocation cleanup for `apply` and `recolor`. Run the synthetic baseline with `python3 tools/zig.py build modifier-bench`.

1. Extract `partColor(doc, part)` and call it from `apply`, `recolor` and `triangleSurfaceColor` (F8).
2. Add the sorted-slot lookup (example in 4.5) and use it in `apply`, `recolor` and `filteredIndices` (F2).
3. Add failure-path tests to `Modifiers.zig` (F7): a rejected `edit` of each kind leaves the document byte-identical; `ComponentSetChanged` when a part is missing; `filteredIndices` keeps submesh ranges contiguous and equal to the sum of visible triangles; `apply` and `recolor` clean up on allocation failure (`std.testing.checkAllAllocationFailures`).
4. Add a synthetic benchmark (a generated mesh with 100k and 1M vertices and 50 and 500 parts) that times `analyze`, `apply` and `recolor`, and record the numbers in validation.md. This is the baseline for F2 and F3; no claim in this document about speed is measured until it exists. **Done:** `modifier-bench` build step and dated baseline are recorded in validation.md.

Acceptance: all tests pass; the new tests fail when the corresponding validation is removed.

### M1. Weld-aware analysis (M)

**Status: implemented, 2026-10-14.** New documents are v2 and use a 0.1 mm weld cell. V1 documents with no `weld_cell` keep the original vertex-index-only analysis. The generated split-corner cube GLB imports as one island instead of six; the checked-in Captain v1 sidecar still applies unchanged.

1. Add weld-aware analysis behind a `weld_cell` parameter; keep the old behaviour when it is absent.
2. Add a fixture GLB with UV seams and hard edges (a small cube with split corners) and a test: the old analysis yields many islands, the welded analysis yields one per shell (this reproduces F1 against the real importer, not only the toy mesh).
3. Test id stability on an unsplit indexed shell. The Captain source does contain coincident split positions, so its welded ids differ; compatibility is tested by applying the checked-in v1 Captain sidecar through the legacy analysis path.
4. Write `weld_cell` into new sidecars; read v1 sidecars with the old analysis.

Acceptance: the Captain sidecar loads unchanged through v1 analysis; the seam fixture imports as one part, and unsplit geometry retains its ids.

### M2. Reversible commands and history (M)

**Status:** Implemented, 2026-10-14. `Modifiers.Command` stores before/after values for surface, color, visibility, palette, scale and offset; `History(64)` applies changes through validated edits, coalesces scale/offset updates, drops redo entries after a new edit, and evicts the oldest entry at capacity. The Character Designer exposes undo and redo through `z`, `shift-z`, panel buttons and a history counter.

1. Add `Command` and `History` (4.3) to `Modifiers.zig` or a new `MeshEditorState.zig`; `Modifiers.edit` stays the validated mutation primitive.
2. Make each `Edit` record the previous value (read it before mutating).
3. Wire undo and redo to keys (suggest `z` and `shift z`, not clashing with `p`, `c`, `h`) and to Designer buttons; show the history position in the status line.
4. Tests: every command kind undoes to a byte-identical document; redo restores; a rejected command leaves history unchanged; coalescing merges a drag.

Acceptance: edit, undo and redo in the running game; the saved sidecar after undo equals the one before the edit.

### M3. Incremental bake and preview (M)

**Status:** Implemented, 2026-10-14. `Modifiers.Bake` owns a pristine model clone, one analysis, sorted part slots, and compressed per-part vertex and triangle lists. `Creator` reports changed part ids (or a full invalidation for palette edits); the app updates only those cached part ranges and queues them for the renderer. The first preview builds the cache and uploads the full result. Hiding degenerates a part's triangle triplets to `(a, a, a)` while preserving index count and submesh ranges, so the GPU index buffer can be patched without rebuilding the mesh. The runtime editor currently changes appearance and visibility; offline scale/offset edits remain on the full bake path.

1. Build `PartSlots` and `PartVertices` once per analysis (4.5) and cache them with the analysis; invalidate only when the source changes.
2. Implement `Bake.updatePart`; keep a dirty list; per frame, re-bake dirty parts and upload the changed vertex ranges.
3. Hiding: choose the index strategy (4.6) by measuring both.
4. Test incremental edits against a full `recolor` after sequences of surface, palette-color and visibility changes; preserve positions, normals, bounds, index count and submesh ranges.

Acceptance: the M0 benchmark shows preview cost proportional to the edited part, not the mesh. **Met:** `Bake.updatePart` is benchmarked alongside full analyze/apply/recolor, and the in-game renderer patches only changed vertex runs and triangle triplets.

### M4. Library and stale-source handling (M)

1. Add the library directory and index (4.10); give each entry a `Guid`.
2. Replace the fixed `captain_test` slot with per-entry catalog handles; migrate the legacy `saves/imported-character.*` into entry zero.
3. Bump `Save.format_version` for the profile change; add the migration and a round-trip test.
4. Implement the stale state and fingerprint re-linking (4.10) with a test per outcome: unique match, ambiguous match, missing part.
5. Lift the macOS-only picker limitation or provide a path argument (`-Dimport=path`) so other platforms and tests can import.

Acceptance: two imported characters coexist; a changed source reports `stale` and keeps the user's edits.

### M5. Viewport: orbit, pick, highlight (L)

1. Add an orbit camera for the editor view (distance, yaw, pitch around the selected part or model centre).
2. Implement picking (4.7) on click; highlight the hovered and selected parts by an emissive tint in the preview instance, not by rewriting vertices.
3. Build bounding volume hierarchies lazily for large parts.
4. Tests: pick correctness (the example in 4.7 plus a seam fixture), no pick through a hidden part, picking cost on the 1M vertex synthetic mesh recorded.

Acceptance: click a shoulder plate and its row is selected; the capture (`-Dcharacter-showcase=46`) shows the highlight.

### M6. Gizmos and numeric transforms (M)

1. Implement translate and uniform or axis scale from 4.8 using the history commands.
2. Add numeric fields with the validation ranges from 2.4 and a visible clamp message.
3. Add snapping and a fine-step modifier.
4. Tests: axis parameter on known rays, drag coalescing, range clamping, and that a drag that ends in an invalid value restores the last valid one.

Acceptance: move and scale a part in the running game, undo it, save, reopen, and see the same model.

### M7. Skin data and weight inspection (L)

Depends on slice 1 of [skeletal-animation.md](skeletal-animation.md) (the `HWSK` and `HWAN` formats and the importer).
1. Extend the importer to keep `JOINTS_0` and `WEIGHTS_0` and the skeleton (4.11); validate as listed there.
2. Carry `SkinVertex` through analysis and bake without reordering.
3. Add the weight heat-map overlay and a joint picker; add socket placement stored in the sidecar.
4. Tests: weights sum to 255, edited parts keep joints and weights bit-identical, malformed skins are rejected, and a skinned preview matches the bind pose for an unedited document.

Acceptance: an imported, rigged model can be edited and still animates.

### M8. Export and round trip (M)

1. Route `compile-modified` through `Bake`.
2. Write the GLB exporter (4.13); round-trip test as specified.
3. Record provenance in the new entry's sidecar.

Acceptance: export, open in Blender, re-import, and the part set matches within the weld cell.

### M9. Skeleton-driven trees and recipe mode (L)

Depends on the nature plan's Phase 5a and 5b ([nature-upgrade.md](nature-upgrade.md)): pipe-model radii and smooth branch sweeps on the skeleton. Evaluation and design: section 4.14.
1. **Spike (S):** spliced `branch.wgsl` draws one Arbor's tubes from 64-byte segment records through Mach's WGSL compiler. Capture it beside the baked mesh in one frame, the two in different tints, and compare silhouettes. The CPU reference (`ringVertex`) is the unit-tested ground truth for the shader math.
2. Export `segments()` from the skeleton: pipe-model radii, parallel-transport frames, tint. Test: radii never thin toward the root, frames are unit quaternions, and the record count equals the node count minus one.
3. Add a `lod_bias` field to the frame uniform and the governor (4.14); log the bias in the benchmark report.
4. Add benchmark rows: segments drawn, triangles submitted, CPU p99 with the baked path versus the segment path, both over the canopy flythrough.
5. Add recipe mode to the editor: gene sliders, regenerate, re-upload, history, save a recipe file.
6. Keep the baked path behind a flag until the captures and the benchmark rows match; retire it only then.

Acceptance: the segment path matches the baked silhouette in capture, CPU p99 is no worse, per-tree memory is under 16 KB, and a recipe saves, reloads and regrows the identical skeleton (a fingerprint test over the node array).

## 7. Validation plan

| Layer | Check |
| --- | --- |
| Unit | every command, validation range and failure path; weld, pick, gizmo, slot, CSR and skin examples as real tests |
| Property | incremental bake equals full bake over random edits; undo then redo is the identity; weld ids equal unweld ids on unsplit meshes |
| Allocation | `checkAllAllocationFailures` on every builder that allocates (analysis, bake, CSR, export) |
| Fixtures | Captain GLB, a seam and hard-edge cube, a flat-shaded cube, a skinned two-bone fixture, a v1 sidecar |
| Integration | headless `MeshEditorState` driven by scripted commands (no window) |
| Rendering | `-Dcharacter-showcase=46` capture at frame 120 and a later frame; Metal validation clean |
| Compilers | default pair and `HEAVYWATER_ZIG_CHANNEL=0.17`; Linux and Windows cross-compile if platform code changes |

## 8. Performance budgets

No baseline is measured yet (M0 creates it). Targets to adopt once it exists:

| Operation | Target | Why |
| --- | --- | --- |
| Pointer-move preview of one edited part | well under one frame (16.667 ms CPU), allocation-free | edits must feel live |
| Pick on click | single-digit milliseconds on a 1M-vertex model | off the frame path, but must not stall |
| Full re-analysis (open, re-link) | acceptable as a one-off load, run off the main thread | analysis is O(vertices) |
| History | fixed memory, no allocation after startup | frame-path rule |
| Sidecar size | stay under the 1 MiB read cap or raise the cap deliberately | `readFileAlloc(.limited(1 << 20))` today |

## 9. Risks and open questions

| Risk | Mitigation |
| --- | --- |
| Welding changes ids for existing sidecars | keep the old analysis when `weld_cell` is absent; fixture test on the Captain sidecar |
| Catalog handle model blocks multiple imports | M4 designs dynamic handles first; do not build the library UI before it |
| Incremental bake drifts from full bake | property test in M3 gates merging |
| Quantized weld misses neighbouring-cell pairs | probe the 26 neighbours if fixtures show it; document the trade-off |
| Skin work depends on another phase | M7 is last and explicitly gated on the skeletal-animation importer slice |
| Two-sided picking selects hidden or backfaced parts unexpectedly | skip disabled parts; test with a hollow shell |

Decisions that need the project owner:
1. **Editor home:** in-game panel (recommended) or standalone window again.
2. **Textures and vertex colour:** keep dropping them (current), bake textures to vertex colour at import, or add a small texture path. This changes what artists can bring in.
3. **Library scope:** how many imported characters, and whether imports are per player (`Kit`) or shared.
4. **Rotation:** add per-part rotation to the sidecar (a format bump) or keep scale and offset only.
5. **Exporter priority:** whether the Blender round trip is needed before skin data.
6. **Tree rendering path:** adopt skeleton-driven trees (section 4.14) after the nature plan's Phase 5a and 5b, or keep baked meshes only. The work-graph mechanism itself is not recommended.

## 10. Reference

Files: [Modifiers.zig](../../src/asset/Modifiers.zig), [Gltf.zig](../../src/asset/Gltf.zig), [Model.zig](../../src/asset/Model.zig), [Catalog.zig](../../src/asset/Catalog.zig), [Meta.zig](../../src/asset/Meta.zig), [Guid.zig](../../src/asset/Guid.zig), [Creator.zig](../../src/game/Creator.zig), [App.zig](../../src/App.zig), [asset_compiler.zig](../../src/asset_compiler.zig), [Mesh.zig](../../src/render/Mesh.zig).

Commands used while writing this document:

```sh
python3 tools/zig.py test mesh_examples.zig                              # default pair: 10 of 10
python3 tools/zig.py test recipe_examples.zig                            # default pair: 5 of 5
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py test mesh_examples.zig  # 0.17: 10 of 10
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py test recipe_examples.zig  # 0.17: 5 of 5
python3 tools/zig.py build-obj -target spirv64-vulkan kernel.zig         # exit 245, empty output (section 4.14)
```
