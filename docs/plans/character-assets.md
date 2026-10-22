# Character assets: imported bodies, faces, armor and reusable parts

**Status:** plan, 2026-10-22. The import library and the face design pass (below, "Done") are built. The owner decided: parts are a shared library for the team, and the face swap replaces only the face area of an imported head. CA1 to CA5 are next, in the order below. The [roadmap](../roadmap.md) stays the single plan; the mesh editor detail is in [mesh editor](mesheditor.md).

## What the main character can do today

| Area | Today | Where |
| --- | --- | --- |
| Procedural ranger | Body from `CharacterSpec`; twelve face presets as data (`spec.FacePreset`, mods add more), each with its own eye shape, brows and resting mouth; face marks and eye colours per profile; data-driven hair; clothing; armor sets as rigid pieces fitted to the procedural body and bound to joints; per-material cel styles. One skinned mesh per profile. | `character/`, `game/Profile.zig` |
| Body styles | `procedural`, `captain_test` (a bundled rigged GLB) and `imported_glb`. | `Profile.BodyStyle` |
| Imported bodies | A GLB with a humanoid skeleton is retargeted onto the game's skeleton by bone name. A GLB without one (or with unknown bone names) is now **auto-rigged** (`character/AutoRig.zig`): the 21 joints are fitted into the mesh's bounds and each vertex is weighted to its two nearest bones. That works for a standing T- or A-pose figure; a model sculpted in an action pose stays in that pose. | `App.importCharacterGlb`, `Retarget.zig`, `AutoRig.zig` |
| Imported mesh tools | Component list grouped from the source meshes and materials, each with a surface role (armor, skin, eyes, energy, neutral), palette recolour and hide. Vertex tools: select, sculpt, paint, cel pens, lattice, joint weights, extrude, split and **tear off as a part** (saved to `saves/parts/part-N.hwmesh`, not yet usable anywhere). | `ui/Screens.zig` (`drawImportedComponents`), `game/MeshTools.zig`, `asset/MeshEdit.zig` |
| **What an imported body cannot do** | It replaces the whole procedural mesh, so no game face, hair, helmet, armor or clothing is drawn on it; torn-off parts cannot be attached to anything. | |

## Done (2026-10-22): the upload library

Every GLB uploaded from the Parts panel joins a library in `saves/imports/<name>/` (source GLB, component sidecar, saved vertex edits), named after the file. The panel's **MESH** row steps through the uploads with **<** and **>** (the chosen one goes on the character) and **DELETE MESH** removes one after a confirming second press. Import results, good or bad, show in the panel itself; before this they went to the HUD status line, which is hidden while the designer is open, so a refused file looked like nothing happened. A single import from before the library is moved into it on first start.

## Done (2026-10-22): face designs

- **Six new faces**, for twelve in all: youthful (round, big low eyes, ready smile), noble (long face, almond eyes, fine arched brows), rugged (square jaw, heavy level brows over small hooded eyes), fierce (narrow eyes with a steep lift, slashed brows), gentle (eyes drooping to the temple under worried brows) and stoic (level eyes and brows, a short flat mouth).
- **Eye shapes:** a preset now cuts the upper lid (`eye_lid`: 0 the round anime eye, higher a flatter lid slanting to the inner corner), arches or bows the brows (`brow_arch`), picks one or two catch-lights and shifts the resting smile. The existing six were tuned with them (angular and hero now have sharp lids, soft and alien rounder brows). The lid is drawn per fragment in `skin_lit.wgsl`, so it stays crisp in close-ups.
- **Face marks** (FACE MARK in the designer): freckles, a scar over the left eye, war paint, a beauty mark, tech seams and tear lines. War paint and tech seams take the player's lumen accent. They are drawn per fragment beside the eyes (the face mesh is too coarse across the face to carry dots and fine lines in vertex colours), from the spare `w` lanes of the eye vertex data, so no vertex layout changed.
- **Eye colour** (EYE COLOR): ten iris colours or the default. Synthetics keep lumen eyes.
- **Designer:** the second tab is now FACE/HAIR (face style, face mark, eye colour, then the hair rows), and those rows zoom to the head.
- **Mouth:** the resting mouth line is darker and wider so it reads at play distance, and the GPU path now uses the same resting smile as the CPU path (it used a fixed 0.3 before).
- Saves: format 32 stores the mark and eye colour in each profile; older saves load with none and the default eyes. Mod face presets accept `eye_lid`, `brow_arch`, `highlights` and `smile`.

The face is entirely a function of face UV (`toon.faceDecal` on the CPU, `draw_anime_eyes` and `draw_face_mark` in the shader). That is what CA2 builds on: any surface that gets face UVs can wear the game face.

## Next

**CA1. Sockets on any body (S).** Measure the imported mesh per game joint: where each bone runs, how thick the mesh is around it (from the vertices it moves), and the head's size and facing. Store these "sockets" with the import. Everything below hangs things on sockets, so faces, armor and parts fit any body, imported or procedural.

**CA2. The game face on the face area of an imported head (M).** Decided: only the face area is swapped; the imported head keeps its shape, hair, ears and helmet. From the head socket, project the front of the imported head onto a face frame (eye line, centre line, chin) and give those vertices face UVs, marking them as face vertices. The shader then draws the chosen face preset's eyes, brows, nose, mouth, marks and eye colour on them, lit by the face shadow map like a ranger's face. A FACE tab chooses KEEP MESH FACE or USE GAME FACE, the face preset, mark and eye colour, and nudges the frame (eye height, spacing, scale) for heads the fit gets wrong. The imported face's own sculpted eyes and nose stay in the geometry, so the swap also offers a SMOOTH FACE step (the existing relax brush, limited to the face area) for heads whose features fight the drawn ones. Dense heads look best; a coarse head limits nothing in the shader (the face is drawn per fragment) but its silhouette stays coarse.

**CA3. Procedural armor on an imported body (M).** Fit each armor set's rigid pieces to the imported sockets instead of the procedural body's radii, so the GEAR tab works on imported bodies. Per slot, choose the imported mesh's own piece or the game's (for example game shoulder plates over an imported torso).

**CA4. Reusable parts (M).** Decided: a shared library for the team. A torn-off part is saved with a name, its joint, its placement relative to the socket and its materials, in `saves/parts/<name>/`, with a stable id; every player on this machine sees the same parts. A PARTS tab lists them; any part attaches to any character's socket (imported or procedural), can be recoloured with the palette and cel pens, and each profile saves which parts it wears by id (a missing part is skipped, like a missing mod). Later the same parts could be placed in the world as props or block prefabs.

**CA5. One designer panel (S).** The Parts panel becomes tabs: LIBRARY (uploads), COMPONENTS (today's list), FACE, ARMOR, PARTS (attachments) and VERTEX TOOLS, with the live preview kept on the left.

## Order

CA1, then CA2 (face area) and CA3 (armor), then CA4 (parts), with CA5 alongside. Decided 2026-10-22: parts are a shared team library; the face swap covers the face area only.

## Not checked

Face designs: checked by headless tests (lid cut, every mark drawn where it belongs, colour packing, save round trip) and close-up captures of all twelve faces in both presentations and every mark; not checked at play distance in split screen, on Wildkin faces, or in the CPU-skinning fallback (`-Dcpu-skinning=true`), which draws the same marks from the Zig reference.

The upload library has not been used by hand through the macOS file picker (it was checked by scripted captures with files placed in the library). Auto-rig quality on more models than the two tried (one standing mecha rigged cleanly, one action-posed warrior stays crouched).
