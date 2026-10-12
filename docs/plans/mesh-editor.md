# Standalone Mesh Editor

## Current status

There is **no standalone graphical editor in the game or repository yet**. `asset-compiler modifier-list`, `modifier-edit`, and `preview-modified` are command-line tools. They can inspect and revise the Captain modifier sidecar and render a PNG, but they do not open a Mach window, select geometry by clicking, or provide interactive tools. Do not describe those commands as the standalone editor.

The source-linked modifier model is a useful foundation: the GLB remains immutable; disconnected triangle islands have source-derived IDs; labels, surface roles, palette colors, and per-part scale/offset are stored in JSON; and the compiler can preview or bake them. The GLB viewer/compiler can CPU-skin bind and compatible procedural-run previews, but runtime meshes still use static HWMS.

## Product boundary

Build a separate desktop authoring app using Mach, launched independently of the game and without starting the world simulation. Reuse the GLB reader, modifier model, CPU preview, runtime mesh renderer, and file formats. It is a focused asset tool, not a general polygon modeler.

The first useful window contains:

- a 3D viewport with orbit, pan, zoom, fit-to-model, and a grid/axis;
- an outliner for imported scene nodes and primitives, plus a part list for editable disconnected islands;
- click selection with a visible part highlight and camera-space bounds;
- a properties panel for part name, semantic surface role, color, scale, and offset;
- shared skin, eye, armor, and energy palettes;
- Save As, preview pose, and revert controls, with source GLB read-only.

Start with ray picking against the CPU model. Add face/edge/vertex selection, gizmos, GPU ID picking, materials/textures, and rig editing in later slices. Preserve selection by source path and component ID, not by array position. One drag or property edit should be one undo step. A session can begin as the existing source-hash-linked sidecar; a larger project folder is not a prerequisite.

## Build slices

1. **Visible standalone shell:** a `mesh-editor` build target and Mach window that opens a chosen GLB, frames the model, reports import diagnostics, and shows node/primitive/part lists. No game world or save state is loaded.
2. **Select and modify:** click an island in the viewport or its stable-ID row; update labels, surface roles, colors, and transforms in a draft; preview the bind pose immediately; save to a new modifier file.
3. **Undo and package:** undo/redo and dirty-state prompts; source-hash validation; export/compile preview; explicit diagnostics for unsupported textures, morphs, and rig features.
4. **Rig preview:** inspect bones, weights, and imported clips using the runtime skeleton/animation formats; edits remain compatible with the game.

## First-slice acceptance

- Launch the standalone app from its own build target without launching gameplay.
- Open the bundled Captain GLB and show its geometry and selectable islands.
- Select the authored pauldron visually, change its label/color/proportion, and see the preview update.
- Save to a separate source-linked file, close/reopen it, and retain the edit; reject a changed source or changed island set without losing the working document.
- Keep the regular game and asset build working; run a Metal validation capture of the editor viewport.

## Not part of the first editor

Full sculpting/topology authoring, UV authoring, material graphs, animation authoring, live webcam capture, and cloud processing. Animation capture is planned separately in [animation capture](animation-capture.md).
