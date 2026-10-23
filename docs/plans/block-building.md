# Block building and terrain sculpting

**Status:** planned 2026-10-21, owner decisions below. BT0 to BT5, the farming part of BT6, BT7, and the creative block mode add-on are implemented: terrain sculpting (player 1) and a block grid in four styles plus platformer mechanisms, with starter prefabs, restyling, copy and paste, a course reachability check, and a free floating creative mode. Survival building still spends each player's own kit. Supersedes the structure and plot parts of [settlement and building](settlement-building.md), and reuses its claims, terrain edit layer (section 8) and economy.

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
| BT3 | Four-player build input, `Kit` block inventory, palette, fill and box tools | done 2026-10-21: pad chord for every player, 64 starter blocks per material, refunds to the remover, pick, box fill and clear up to 512 cells, palette strip per view. Open: earning blocks in the wilds, guests cannot sculpt terrain |
| BT4 | Style table, dungeon, eco city and farm styles, style swap, block prefabs | done 2026-10-21: role-based styles, ten starter prefabs, restyle a box, copy a box to a per-player clipboard and paste it. Open: the clipboard is not saved or shared as a file, prefabs have no doors, torches or other mechanisms yet (BT5 and BT6) |
| BT5 | Platformer blocks and hazards, reachability validator | done 2026-10-21: spring, boost strip, crumble, hazard, checkpoint, pressure plate and gate, mover; `Course.reachable`. Open: key doors and wiring blocks to the machine signal bus (since 2026-10-22 a plate opens the gates within 16 m for 8 s), a kill plane, crumble and gate state are not saved (a load restores them) |
| BT6 | Crops, spawner, chest, gate, strategy hooks | crops done 2026-10-21: seeds on tilled soil, three growth stages over three minutes, ripe harvest pays the harvester four hay, saved in format 30. Deferred, with reasons: a dungeon spawner and treasure chest only make sense in generated dungeons (a player-built chest that pays loot is an exploit), so they move to the Interiors dungeon work; castle gates are covered by plates and gates (BT5), a drawbridge that swings is not built; room roles and other strategy hooks wait for the settlement layer. Crops ignore seasons, weather and water for now |
| BT7 | Polish, benchmarks, hands-on checklist | done 2026-10-21: per-player building tips, the measurements and the checklist below |
| BT8 | Creative block mode | implemented: C on keyboard or X on a pad toggles free placement; LT places, RT removes, D-pad selects and rotates; cells may float without support. It reuses the block preview and material strip. |

## Measurements (2026-10-21, ReleaseSafe, Metal debug layer on, Apple Silicon)

From the smoke stage `smokeBuildBenchmark`:
- A 32 x 32 x 4 block chunk (3,584 blocks, 5,552 triangles after hidden faces are dropped, 542 KiB of mesh) meshes and builds its collider in 26 ms.
- One block edit re-meshes its whole chunk: 17.5 ms on that chunk, about one frame at 60 Hz. Small builds cost far less; a castle-sized chunk will hitch once per click.
- One full-size (radius 24 m) terrain dab: 0.02 ms of CPU. The visible cost is the streamer regenerating each touched chunk on its worker, which the existing terrain benchmarks measure (chunk fill p50 and p99).
- Not measured: GPU upload time of a re-meshed chunk, frame time while sculpting, Debug builds.

Follow-ups the numbers point to: mesh block chunks on a worker (as terrain chunks are) or re-mesh only the touched 16 m section, and rebuild only the collider triangles that changed.

## Hands-on checklist

None of the building has been played by hand. Each line is something a person should try and confirm:
1. Key 6, hold click on open ground: the ring follows the crosshair, the ground rises smoothly, the chunk does not blink while it rebuilds, you can walk on the mound. Tab through lower, level, smooth; [ and ] resize; right click undoes; T redoes.
2. Near a cave mouth the ring turns red and sculpting is refused.
3. Key 7: the tip appears; place, remove, turn and pick blocks; walk up a stair; jump on a ramp.
4. Shift-click two corners to fill a box; right-click two corners to clear it; the palette counts change for you only.
5. Shift+Tab through all five styles; lay each starter prefab; restyle a castle as a farm with Shift+T corners; copy with Shift+P corners and paste.
6. Platformer: spring height, boost direction after turning it with T, a crumble block falling and returning, hazard damage and recovery at a checkpoint, a plate opening a gate, riding a mover.
7. Farm: plant seeds on tilled soil, watch three stages, harvest gold crops for hay.
8. With a second pad: LT + D-pad left starts building, every control above works, the palette is in that player's view and spends their own blocks.
9. Creative blocks: press C / X while the block tool is active; place unsupported blocks, rotate them, and remove them. Confirm no blocks are charged while creative mode is on, then turn it off and confirm normal inventory costs resume.
10. Save, quit, load: terrain, blocks, crops and each player's block stock come back.
11. Build a large castle and note any hitch per click (expected around one frame on a full chunk).

Risks: terrain edit thread safety (do BT1 alone first); `Physics.max_meshes` of 64; the Canvas cap of 640 commands for palette UI; the 8 MB module-state stack; the 4 MiB save cap.

Remaining `Noise.height` direct use: `Mountains.panorama` builds the far skirt below the terrain on purpose and is left alone until sculpting can reach it.
