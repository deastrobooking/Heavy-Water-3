# Fantasy flora: glowing, living-sap bushes, flowers, grasses and trees

**Status:** plan, 2026-10-22. Nothing here is built. The [roadmap](../roadmap.md) stays the single plan. This extends the existing flora generator ([nature upgrade](nature-upgrade.md), `procedural/Vegetation.zig`) and the building track ([block building](block-building.md), [automation and defense](automation-and-defense.md)).

**Owner decisions (2026-10-22):**
1. **Both places:** new species grow wild in the seeded biomes, and players can place the same plants as decoration (outposts, farms, cities).
2. **Look:** glowing, living-sap flora that fits the canopy and lumen world, not storybook or Hive-corrupted looks (those can be later sets).
3. **Overlap:** another session has uncommitted vegetation work in the tree (hill-meadow variants, `Biome`, `Scatter`, `Vegetation`). Generator edits start only after it lands, to avoid two sessions in one file. Until then this plan and the species designs are the work.

## What exists

| Piece | Today |
| --- | --- |
| Species | `Vegetation.variant_count` variants (18 on 2026-10-22): ground flora (grass, fern, wildflower), eight giant tree silhouettes (broadleaf, needleleaf, willow, redwood, manzanita-style, copper-fan, moon-cascade, star-blossom), three glowing flowers (ember blossom, moonbell, sunspear), plus hill-meadow additions in progress. Each has a base color, trees have a trunk color. |
| Meshes | Generated in Zig from blades, swept twigs and an L-system (`LSystem.zig`), one compact mesh per species, instanced. |
| Placement | `Scatter.generate`: 192 plant and relic candidates per 128 m chunk, a species chosen by biome weights (arid, meadow, wetland, sheltered grove, alpine), slope and road clearances. Candidate ids are stable, so saved removals survive. |
| Rules | Near-ground cover stays low and flowers legible so they do not hide combat ([world](../world.md)). A change to what a seed produces bumps `Seed.generator_version` with a migration. |

## The first set: living-sap flora

One art idea: **sap-lit plants**. Pale cel-lit bodies with luminous veins and tips that glow in the lumen colours (cyan, amber, magenta, lime), brighter at night, so a forest reads as the same living network as the Arbors. Every species has a daytime read (flat color, outline) and a night glow (emissive tint). Heights keep the combat rule: grasses and flowers stay below about 0.6 m, bushes below 2 m.

| Family | Species (working names) | Silhouette and glow |
| --- | --- | --- |
| Grasses | **Glowblade grass**, **silk reed**, **moonmoss tuft** | Blade clumps with glowing tips; tall reeds with pale seed-heads near water; flat moss cushions that pulse faintly on wet ground. |
| Flowers | **Lumen lily**, **starcup**, **driftpoppy** | A tall single bell with a lit throat; a ground carpet of small cups that all open at night; a loose poppy that sways and sheds a few glow motes. |
| Bushes | **Lantern bush**, **crystal-bloom shrub**, **sapfern thicket** | A rounded bush hung with glowing pods; a spiky shrub of translucent crystal petals; a dense fern mound with veined fronds. |
| Trees | **Glowvine tree**, **crystal-leaf tree**, **sapwillow** | A medium tree draped in luminous vines; a tree whose leaves are pale glassy plates catching light; a weeping willow with sap running bright down its limbs. |

About twelve species, so the variant count grows from 18 (and whatever the other session adds) to about 30. Giant canopy trees stay as they are; these fill the human-scale layer (grass to 12 m trees) that the world lacks.

## Placing them in the world (wild)

- **Biome rules:** a new weight family, "sap meadow", rises near Arbors, wet ground and sheltered groves; glowblade and starcup carpet it, lanterns and sapferns edge it, glowvine and sapwillow stand in it. Arid and alpine ground gets few. Cities get planters and roof gardens from the existing placement, not scatter.
- **Stable ids:** species are chosen inside the existing 192 candidate slots, so positions and ids do not move and saved removals keep working. Appearance changes, so `Seed.generator_version` is bumped with a migration like the earlier scatter changes, decided when the generator is touched.
- **Budgets:** the nature benchmark (`tools/benchmark.py --nature`, 83 vegetation instances and about 5.6 M triangles on 2026-10-21) is the gate: new species get a triangle budget each, grasses draw only near the player, and the four-player split screen is measured.

## Placing them as decoration (players)

- **A Plants entry in the block tool** (after structures): Tab to a species, click on the ground or a block to plant, T turns it, right click removes it and refunds. Each plant costs one block of a nature material in the builder's own stock (leaf, bloom or moss), so decorating is paid and bounded like building.
- **Data:** a `Decor` list (cell, species, turn, builder) in the world save, capped at 512 per world and 64 per chunk, drawn as instanced props (the farm crops are the pattern). One save format bump, a fixture, a round-trip test.
- **Style link:** a plant has a role like a block, so a restyle keeps the idea (a lantern bush in a castle becomes a glow-thatch bush on a farm) only if wanted; the first slice does not restyle.
- **Growth (optional, later):** young plants grow to full size over the global season clock, reusing the farm timer.

## Build order

| Step | Deliverable | Proved by |
| --- | --- | --- |
| FF0 | Wait for the other session's vegetation work to land; re-read `Vegetation`, `Scatter`, `Biome`. | Clean tree and a green suite. |
| FF1 | Species meshes and tables: names, colors, glow flags, heights, triangle budgets for the twelve species. | Tests: every mesh is valid, inside its height and triangle budget, deterministic by seed; a contact-sheet capture of all species by day and by night. |
| FF2 | Wild placement: sap-meadow weights, species choice inside existing candidates, generator version bump and migration. | Scatter tests (every species appears, ids unchanged, no placement on roads or the spawn), save migration test, forest captures day and night. |
| FF3 | Night glow and sway in the shader path (an emissive tint lane, a small wind sway), within the WGSL limits. | Capture under `MTL_DEBUG_LAYER=1`; nature benchmark within budget. |
| FF4 | Decoration: the Plants entry, `Decor` state, cost and refund, save format and fixture, guest building. | Place, remove, save, restore and four-player tests; smoke stage. |
| FF5 | Polish and measurement: four-player benchmark, combat-readability review, docs and the player guide. | Recorded numbers and a hands-on checklist. |

## Open points

- **Species list:** the twelve above are proposals; the owner can swap any before FF1.
- **Gameplay hooks:** harvesting sap petals or seeds for the economy (lumen, farm seeds) is not in this plan; it fits after the shared stockpile exists.
- **Later sets:** storybook and Hive-corrupted flora can reuse the same generator and the Plants entry.
