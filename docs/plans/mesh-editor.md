# Mesh editor plan

Written for: the developer who owns the Captain and character tooling.

## Where it stands (reviewed 2026-10-12)

The mesh editor is a headless command set, not an editor yet.

- `asset/Modifiers.zig` splits a compiled mesh into triangle islands, labels them by position, and stores edits (part labels, surfaces, colour, scale, offset, palette) in a source-hash-linked JSON document. It has one unit test.
- `asset_compiler.zig` exposes `modifiers`, `modifier-list`, `modifier-edit`, `preview-modified` and `compile-modified`. It has no tests of its own, so the CLI paths are only checked by hand and by the `build assets` step.
- `asset/Gltf.zig` gained parsing for the Captain import. It has two tests.
- Nothing can be sculpted, painted, selected on screen or undone. Every change is a separate CLI run that rewrites a JSON file.
- The editor depends on source-hash matching, so any change to the source GLB invalidates the document. That is the right safety rule, but it means a re-export of the model loses edits silently until the author rebuilds them.

Review findings to fix before adding tools:

1. **No tests for the CLI paths.** `modifier-edit` validation (bad colours, unknown part IDs, out-of-range offsets) is what keeps a document valid. Add tests that call the same functions the CLI calls, and check that a rejected edit leaves the document unchanged.
2. **Labels and surfaces are guesses.** `suggestedSurface` and `suggestedLabel` use position alone. They are fine as defaults, but the editor must show them as suggestions the author can override.
3. **No undo.** Each edit overwrites the file. The editor needs a history of edits (see stage 2) before any brush tool exists.
4. **Mesh data is one base-colour material.** No UVs, no textures, no semantic groups. Sculpting needs stable vertex IDs across edits, which the current island IDs do not give.

## Goal

A simplified, friendly, Blender-style mesh editor for Heavy Water's artists: select, move, and sculpt with a few clear brushes, with undo and a live view. It writes the same source-linked modifier document the game already compiles, so nothing downstream changes. It is not a general modelling package. Scope is set by the MVP loop: the editor exists to make characters, creatures and props for the game, not to replace Blender.

## Stages

Each stage ends with a headless test, a rendered capture under `MTL_DEBUG_LAYER=1`, and an entry in [validation.md](../validation.md).

**Stage 0 — hardening (no new tools).** Add the CLI tests from finding 1. Record the source hash mismatch path as a test. Done when `build test` covers every modifier command.

**Stage 1 — read-only viewport.** Open a compiled mesh in a Mach window with orbit, zoom and wireframe toggles. Show island IDs and the surface colours. Selection is by island only. Done when an author can pick an island by clicking it and see its ID and label.

**Stage 2 — edits with undo.** Move the existing edits (label, surface, colour, transform) into the viewport. Keep a bounded history of edit commands. Each command is a `modifiers.edit` value, so undo is replaying the inverse. Save writes the document through the same validation the CLI uses. Done when undo and redo restore the document byte-for-byte.

**Stage 3 — sculpt brushes on a stable mesh.** Give each vertex a stable ID that survives a re-bake of an unchanged source. Store sculpt deltas as offsets from the source vertex, keyed by that ID. Ship four brushes first: grab, smooth, inflate and pinch, each with a radius and strength. A brush stroke is one undo step. Done when a stroke is saved, reloaded, and reproduces the same vertices.

**Stage 4 — friendly polish.** Symmetry across the centre plane, a mirror toggle, a simple material palette from the game's cel style, and one-key tool switching. Any further tool needs a clear use in the MVP loop before it is added.

## Rules

- Native Zig only. No external modelling library and no C++ mesh kernel.
- The editor writes the modifier document, never the source GLB. Source edits stay in the author's own tool.
- A failed edit leaves the document and history unchanged (validate first, then apply).
- Deltas and history use fixed or explicitly allocated storage. Nothing allocates on the frame path.
- A source-hash mismatch refuses the edit and says which file changed; it never silently rebases.

## Not in this plan

Animation and rigging, texture painting, UV unwrapping, importing or exporting formats other than GLB, and multi-user editing. Each needs its own plan.

## Open questions for the owner

1. Should sculpt deltas live in the modifier JSON, or in a sidecar file next to it? A sidecar keeps the modifier file readable; the JSON keeps one document per character.
2. Is symmetry a stage 4 default or an option from stage 3?
3. Who is the first author: a developer on the Captain, or an artist working alone? That changes how much of stage 1 needs keyboard-only use.
