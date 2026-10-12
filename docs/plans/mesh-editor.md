# Standalone Mesh Editor

## Current status

The repository now has a first standalone graphical slice: `python3 tools/zig.py build mesh-editor` launches the Mach editor, while `build mesh-editor-build` compiles it without launching. It opens the source Captain GLB, lists its 74 disconnected islands, selects by click or arrow keys, edits labels/colors/scales, previews bind or compatible procedural-run poses, and saves the source-hash-linked modifier sidecar. `asset-compiler modifier-list`, `modifier-edit`, and `preview-modified` remain available for batch editing.

The source-linked modifier model is a useful foundation: the GLB remains immutable; disconnected triangle islands have source-derived IDs; labels, surface roles, palette colors, and per-part scale/offset are stored in JSON; and the compiler can preview or bake them. The GLB viewer/compiler can CPU-skin bind and compatible procedural-run previews, but runtime meshes still use static HWMS.

## Product boundary

Build a separate desktop authoring app using Mach, launched independently of the game and without starting the world simulation. Reuse the GLB reader, modifier model, CPU preview, runtime mesh renderer, and file formats. It is a focused asset tool, not a general polygon modeler.

The current window contains:

- a 3D viewport with Left/Right plus W/E orbit and wheel zoom;
- a clickable, keyboard-navigable list of disconnected islands;
- part rename (`R`, type, Enter), scale (`+`/`-`), color cycle (`C`), pose toggle (`P`), and sidecar save (`S`);
- a compatible procedural run-pose preview using the existing CPU skin path.

This is a first editing surface, not the complete authoring plan. It currently writes the Captain sidecar in place. It has no undo/redo, Save As, pan/gizmo, surface-role editor, dedicated palette controls, node/primitive tree, or visual component picking/highlight. The view does not edit the source GLB.

Start with ray picking against the CPU model. Add face/edge/vertex selection, gizmos, GPU ID picking, materials/textures, and rig editing in later slices. Preserve selection by source path and component ID, not by array position. One drag or property edit should be one undo step. A session can begin as the existing source-hash-linked sidecar; a larger project folder is not a prerequisite.

## Build slices

1. **Visible standalone shell — started:** Mach target opens the bundled Captain from the source GLB and shows the imported islands; the game simulation and saves are not started. General open-file selection and diagnostics remain.
2. **Select and modify — started:** list selection, label/color/scale edits, bind/run preview, and sidecar save work. Remaining: surface roles, per-axis offset/scale fields, viewport hit selection/highlights, draft/revert, Save As, and edit history.
3. **Undo and package:** undo/redo and dirty-state prompts; source-hash validation; export/compile preview; explicit diagnostics for unsupported textures, morphs, and rig features.
4. **Rig preview:** inspect bones, weights, and imported clips using the runtime skeleton/animation formats; edits remain compatible with the game.

## First-slice acceptance

- Launch the standalone app from its own build target without starting gameplay simulation.
- Open the bundled Captain GLB and show its geometry and selectable islands. **Met in the first slice.**
- Select an island by row, change its label/color/proportion, and see the preview update. **Met in the first slice.**
- Save to a separate source-linked file, close/reopen it, and retain the edit; reject changed source/island sets without losing the working document. **Still open:** save currently targets the bundled sidecar in place.
- Keep the regular game and asset build working; run a Metal validation capture of the editor viewport. **Editor capture passed 2026-10-12.**

## Review notes carried forward

- Auto labels and skin/eye guesses are spatial heuristics, not semantic truth. The bundled mesh is one fused primitive with a single base-color material, so authors should inspect labels and surface roles.
- Sidecar edits are guarded by the source hash and component IDs during compilation. Do not silently rebase them after the GLB changes; preserve a recovery copy and offer explicit remapping later.
- The modifier command interface still needs failure-path coverage: invalid edits must not replace the original file, and repeated labels/colors/transforms need round-trip checks.
- Keep the GLB immutable, all authoring allocations explicit, and failed edits transactional. Use native Zig/Mach only; no C/C++ mesh library.

## Not part of the first editor

Full sculpting/topology authoring, UV authoring, material graphs, animation authoring, live webcam capture, and cloud processing. Runtime GLB skeleton/clip import is still missing; the `P` preview is an offline static pose produced by CPU-skinning the GLB with the existing procedural run animation. Animation capture is planned separately in [animation capture](animation-capture.md).
