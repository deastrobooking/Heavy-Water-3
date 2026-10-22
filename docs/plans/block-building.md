# Block building and terrain sculpting

**Status:** planned 2026-10-21, owner decisions below. BT0 (terrain single-source cleanup), BT1 (terrain sculpting) and BT2 (castle block grid) are done, for player 1. Supersedes the structure and plot parts of [settlement and building](settlement-building.md), and reuses its claims, terrain edit layer (section 8) and economy.

**Owner decisions (2026-10-21):**
- A chunked block grid (Minecraft/Lego feel), not free-placed props. The existing machine Build tool stays for mechanisms (doors, lifts, logic) that snap into the grid.
- Terrain sculpting is heightfield brushes only (raise, lower, level, smooth, ramp, dig pit). No overhangs or tunnels.
- All four players build, each with a personal block inventory in `Kit`.
- Four styles in the MVP: castle, dungeon, eco city, farm.

## Why the current tool cannot do it
`game/Build.zig` places machines: 16 machines of up to 16 parts, one physics body per part, drawn as props (cap 2048). A castle needs thousands of cells. Terrain height is a pure function with no edit hook, `Streamer` has no per-chunk invalidate, there are four per-view streamers, and guests (players 2 to 4) cannot build or use menus.

## Design
- **Blocks:** 1 m cells in sparse 16x16x16 sections, heap allocated, with global caps checked before any write. A cell packs shape, material, style, rotation and flags into a `u32`. Shapes: cube, slab, ramp, stair, corner ramp, wall, half wall, pillar, arch, window, door frame, fence, roof wedge and corner.
- **Styles are data:** materials, shape variants, colour ramp and cel pen. Swapping a selection's style re-skins it. Prefabs are saved cell sets with stable string ids.
- **Meshing:** one mesh and one merged static collider per chunk column, built on the worker, uploaded as a partial patch (as `StreamingScene.patchMesh` does for edited meshes). Vertex colours only; no new shader.
- **Terrain edit layer:** a sparse per-chunk delta applied in one place after `CityHeightmaps.heightAt`, so the chunk mesh, `Terrain.surface`, physics ground, scatter and culling agree. Needs an immutable snapshot for the worker and `Streamer.invalidate` reaching all four streamers. Edits only inside claims and outside rivers, cave mouths, the district and shrines.
- **Platformer blocks:** spring, boost strip, moving block, crumble block, one-way platform, ladder, hazard, kill plane, per-player checkpoint, key door, plate, lever, timer, gate, drawbridge, trap dispenser. They use the existing signal bus and `Combat.hurt`.
- **Four players:** crosshair aim like `Build.preview`; guests need tool state, palette and ghost in their own viewport. Personal block stacks live in `Kit`; the settlement stockpile stays post-MVP.
- **Style features:** dungeon (cells, grates, torches, traps, spawner, chest, secret door; layouts from `Interiors` archetype `dungeon`), castle (walls, towers, gatehouse, portcullis, drawbridge, moat from a dig pit), eco city (living wood, glass, green roofs, solar leaf, walkways), farm (tilled plots, crops that grow by day, irrigation, barn, silo, harvest into `Kit`).

## Phases
| Phase | Deliverable | Status |
| --- | --- | --- |
| BT0 | Docs aligned; stray `Noise.height` callers (`Biome.coverAt`, flora review position) moved to `CityHeightmaps.heightAt`; its tests registered | done 2026-10-21 |
| BT1 | Terrain edit layer, `Streamer.invalidate`, raise/lower/level/smooth with the terrain tool (key 6), undo and redo, save format 27 | done 2026-10-21, for player 1; claims, ramp and pit brushes, and guest input are still open |
| BT2 | Block store, shapes, meshing and collider per chunk, place and remove, castle style | done 2026-10-21: cube, slab, ramp, stair; eight castle materials; meshing is on the main thread at edit time (not the worker); no undo beyond removing; blocks are free; player 1 only |
| BT3 | Four-player build input, `Kit` block inventory, palette, fill and box tools | planned |
| BT4 | Style table, dungeon, eco city and farm styles, style swap, block prefabs | planned |
| BT5 | Platformer blocks and hazards, reachability validator | planned |
| BT6 | Crops, spawner, chest, gate, strategy hooks | planned |
| BT7 | Polish, benchmarks, hands-on checklist | planned |

Risks: terrain edit thread safety (do BT1 alone first); `Physics.max_meshes` of 64; the Canvas cap of 640 commands for palette UI; the 8 MB module-state stack; the 4 MiB save cap.

Remaining `Noise.height` direct use: `Mountains.panorama` builds the far skirt below the terrain on purpose and is left alone until sculpting can reach it.
