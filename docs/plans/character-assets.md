# Character assets: imported bodies, faces, armor and reusable parts

**Status:** overview and proposed plan, 2026-10-22. The import library (below, "Done") is built; CA1 to CA5 are proposals waiting for the owner's priorities. The [roadmap](../roadmap.md) stays the single plan; the mesh editor detail is in [mesh editor](mesheditor.md).

## What the main character can do today

| Area | Today | Where |
| --- | --- | --- |
| Procedural ranger | Body from `CharacterSpec`; face presets as data (`spec.FacePreset`, mods add more); data-driven hair; clothing; armor sets as rigid pieces fitted to the procedural body and bound to joints; per-material cel styles. One skinned mesh per profile. | `character/`, `game/Profile.zig` |
| Body styles | `procedural`, `captain_test` (a bundled rigged GLB) and `imported_glb`. | `Profile.BodyStyle` |
| Imported bodies | A GLB with a humanoid skeleton is retargeted onto the game's skeleton by bone name. A GLB without one (or with unknown bone names) is now **auto-rigged** (`character/AutoRig.zig`): the 21 joints are fitted into the mesh's bounds and each vertex is weighted to its two nearest bones. That works for a standing T- or A-pose figure; a model sculpted in an action pose stays in that pose. | `App.importCharacterGlb`, `Retarget.zig`, `AutoRig.zig` |
| Imported mesh tools | Component list grouped from the source meshes and materials, each with a surface role (armor, skin, eyes, energy, neutral), palette recolour and hide. Vertex tools: select, sculpt, paint, cel pens, lattice, joint weights, extrude, split and **tear off as a part** (saved to `saves/parts/part-N.hwmesh`, not yet usable anywhere). | `ui/Screens.zig` (`drawImportedComponents`), `game/MeshTools.zig`, `asset/MeshEdit.zig` |
| **What an imported body cannot do** | It replaces the whole procedural mesh, so no game face, hair, helmet, armor or clothing is drawn on it; torn-off parts cannot be attached to anything. | |

## Done (2026-10-22): the upload library

Every GLB uploaded from the Parts panel joins a library in `saves/imports/<name>/` (source GLB, component sidecar, saved vertex edits), named after the file. The panel's **MESH** row steps through the uploads with **<** and **>** (the chosen one goes on the character) and **DELETE MESH** removes one after a confirming second press. Import results, good or bad, show in the panel itself; before this they went to the HUD status line, which is hidden while the designer is open, so a refused file looked like nothing happened. A single import from before the library is moved into it on first start.

## Proposed

**CA1. Sockets on any body (S).** Measure the imported mesh per game joint: where each bone runs, how thick the mesh is around it (from the vertices it moves), and the head's size and facing. Store these "sockets" with the import. Everything below hangs things on sockets, so faces, armor and parts fit any body, imported or procedural.

**CA2. The game face on an imported body (M).** Split the procedural head (face, eyes, hair, helmet) into its own piece bound to the head joint. On an imported body, hide the imported head's components and draw the game head at the head socket, scaled to fit, with every face preset, hairstyle and helmet working as on a ranger. A per-import switch: KEEP MESH FACE or USE GAME FACE. A finer version (keeping the imported helmet but swapping only the face) needs the head split by selection with the vertex tools first.

**CA3. Procedural armor on an imported body (M).** Fit each armor set's rigid pieces to the imported sockets instead of the procedural body's radii, so the GEAR tab works on imported bodies. Per slot, choose the imported mesh's own piece or the game's (for example game shoulder plates over an imported torso).

**CA4. Reusable parts (M).** A torn-off part is saved with a name, its joint, its placement relative to the socket and its materials, in `saves/parts/<name>/`, with a stable id. A PARTS tab lists them; any part attaches to any character's socket (imported or procedural), can be recoloured with the palette and cel pens, and is saved in the profile. Later the same parts could be placed in the world as props or block prefabs.

**CA5. One designer panel (S).** The Parts panel becomes tabs: LIBRARY (uploads), COMPONENTS (today's list), FACE, ARMOR, PARTS (attachments) and VERTEX TOOLS, with the live preview kept on the left.

## Decisions needed

1. Order: suggested CA1, then CA2 (face) and CA3 (armor), then CA4 (parts), with CA5 alongside.
2. Parts: shared by everyone on this machine (a library on disk, like uploads) or owned per ranger (in their `Kit`)? Suggested: shared library, with each profile saving which parts it wears.
3. Face swap: replace the whole imported head, or only the face area of it?

## Not checked

The upload library has not been used by hand through the macOS file picker (it was checked by scripted captures with files placed in the library). Auto-rig quality on more models than the two tried (one standing mecha rigged cleanly, one action-posed warrior stays crouched).
