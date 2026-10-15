# In-Game Imported Character Editor

Engineering design, defect review and milestone plan for this editor: [mesheditor](mesheditor.md).

## Product boundary

Keep routine imported-character customization in the game's Character Designer. The offline
`asset-compiler` remains the batch importer and diagnostic path; Blender remains appropriate for
topology, UVs, complex rig work, and other tasks that need a full DCC tool.

## Current slice

The Creator's **IMPORTED PARTS** window reads the source-linked Captain modifier document and
browses its 74 disconnected mesh islands by surface category. It supports component selection,
surface reassignment, per-component palette paint, show/hide, RGB palette adjustment for skin,
eyes, armor and energy, and saving a local override at `saves/captain.modifiers.json`. Edits
recolor or filter the build-baked mesh under the render mutex and appear in the live Captain
preview. The checked-in GLB and modifier recipe remain unchanged.

The editor can also import one user-selected binary GLB (`IMPORT GLB`). Successful imports now
register as the distinct `IMPORTED GLB` body type in Character Designer and select that type
immediately; the same live 3D character preview used by the Creator shows the imported pose while
the parts window is open. The parts window reports the rig mapping and component count, and the
preview updates when the source mesh is recolored or hidden. The bundled Captain remains a
separate body type. Imports are still a single replaceable user slot at
`saves/imported-character.glb`, so importing a second GLB replaces the first.

New generated sidecars are format 2 and save a weld cell so UV seams and hard edges do not split
one geometric shell into many editable parts. Existing format 1 sidecars keep their original
index-only part IDs and remain usable.

It traces the skin, maps
recognized Mixamo/Blender/Unity-style humanoid joint names to the game's run tracks, and evaluates
that controller pose into the imported preview. The source is stored at
`saves/imported-character.glb`; appearance edits are stored in
`saves/imported-character.modifiers.json`. The window reports mapped run tracks and labels the
result `STATIC IN GAME`: `HWMS` still discards skin data, so this is a retargeted static pose, not
live gameplay animation. Importing another GLB replaces the current imported-character slot.

The native Creator also has an armor RGB studio for the generator's metal, secondary and trim
channels. Each set keeps its authored defaults until a channel is changed; custom RGB values are
part of the player profile and feed the native procedural armor generator.

The component labels are importer heuristics and remain editable through the existing surface
roles and palettes; free text relabeling is not yet available in-game. Per-island shape transforms
remain in the offline modifier tool because the runtime mesh is baked. Runtime `HWSK`/`HWAN`
serialization and live controller-driven imported characters remain separate stages.

## Next slices

0. **Modifier reliability, welded islands and reversible edits (M0/M1/M2 complete):** shared palette resolution,
   sorted part-slot lookup, failure-path coverage, benchmark baseline, weld-aware analysis, the
   split-corner GLB fixture, v1 sidecar compatibility, fixed-capacity commands and in-game undo/redo
   are in place.
1. **Incremental bake and preview (M3 complete):** the preview caches source analysis and per-part
   vertex/triangle membership, then patches only dirty part ranges. Visibility edits degenerate
   triangle triplets in place, preserving GPU index count and submesh ranges. Next is **library and
   stale-source handling (M4)**.
2. **Library breadth:** replace the current single imported slot with a multi-asset browser. Keep
   per-asset names, source hashes, modifier documents and selectable character types; reject stale
   overrides without discarding them.
3. **Component authoring:** add component relabeling and basic size/offset controls
   with one reversible action per edit. Keep edits source-linked and offer export as a separate
   user copy.
4. **Rig integration:** replace the current controller-pose bake with runtime `HWSK`/`HWAN`
   import, live controller-driven animation, named sockets, and robust mapping controls.
5. **User animation:** bring file-based and later webcam capture review into the same in-game
   character workspace only after runtime skeleton and clip import work. Keep inference local and
   make captured clips editable before they can enter gameplay.

## Acceptance

- A user can choose the imported Captain body, browse its source-linked pieces by category, adjust
  appearance, hide or restore a part, and see the preview update without restarting.
- Saving and reopening preserves library appearance edits without altering the checked-in GLB or
  importer recipe.
- Imported-part edits can be undone and redone in the game; saving after undo writes the same
  sidecar state that existed before the edit.
- A stale source/component set is reported clearly and does not replace the user's working file.
- Routine library/color edits require no external application; advanced geometry and rig changes
  can be exported to Blender and reimported.

See [asset pipeline](asset-pipeline.md), [skeletal animation](skeletal-animation.md), and
[user animation capture](animation-capture.md) for importer and animation dependencies.
