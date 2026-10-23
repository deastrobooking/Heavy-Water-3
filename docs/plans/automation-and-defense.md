# Automation, strategy and defense: modular structures, mining and farming bases, drones, turrets

**Status:** BS1–BS4 are implemented as of 2026-10-22 (tool registry, loot table, structure definitions, defense behaviours with raids); BS5 (ore, drills, shared stockpile) is next; behavior modules, mining, drones and command view remain planned. The [roadmap](../roadmap.md) stays the single plan. This extends [settlement building](settlement-building.md) (the shared stockpile, the hourly integer economy, claims) and [block building](block-building.md) (blocks, prefabs, platformer parts), and replaces their open "mining" and "light simulation" sketches with a first slice.

**Owner request (2026-10-22):** make the existing building tools modular so users can build their own; make parts and scrap easy to get, especially from fighting robots; build mining bases and mining drones, and farming bases and drones, so production is automated; add Civilization-style strategy play in 3D with its own GUI controls; add protective prefabs (turrets, shield generators, missile launchers).

**Where it sits in the MVP loop** ([AGENTS.md](../../AGENTS.md)): wilds are hack-and-slash with loot; cities are exploration. This track gives the wilds a reason to be fought over (robots drop what outposts need; outposts need defending) and gives loot a second use. It does not change the city liberation loop, so it is a separate track like building was. Whether to promote it into the MVP loop section is the owner's call.

## What exists to build on

| Need | Existing piece | Gap |
| --- | --- | --- |
| Placing things | `Build.zig` (machines, 16 max), `BlockTool.zig` (block grid, styles, prefabs, clipboard and structure library), `BridgeTool`, `TerrainTool`, wiring | Structure entries now join the block palette. The legacy tools still have distinct controls and capacity rules; the registry work is a routing refactor, not yet a unified validation/cost/preview contract. |
| Architectural glazing | `Materials.zig` includes eight glass color swatches; `Blocks.Shape.pane` is a thin, rotatable, colliding panel | The scene pipeline is opaque. Glass is currently tinted architectural color, without view-through transparency, reflections or window frames. A true transparent pass needs separate pane meshes, per-view sorting and depth-write rules before these can be called optically transparent. |
| User-made pieces | Block prefabs (`build/Prefabs.zig`, `captureBox`), machine blueprints (`Blueprint.Doc`, P to capture) | Blocks and machines cannot be captured together; prefabs have no behaviour and no stats. |
| Behaviour | Machine devices (generator, sap tap, plate, motor, lamp, logic, script) and signals | No weapon, shield, drill, drone bay or storage device. |
| Defense | Ranger special `sentry` (20 s zapper), `Combat.hurt`, `Enemies` | No placed, persistent defense; enemies never attack structures. |
| Materials | Per-player `Wallet` (scrap, parts, gold, kits), loot tables, pickups, `Fabricator` costs; arena waves pay scrap | No ore, shared automated stockpile or powered production yet. |
| Production | `Farm.zig` (crops on tilled soil, hay to the harvester's kit) | No machines that produce on their own; no drones that haul or harvest. |
| Strategy UI | Pause menu, `Screens.zig` panels, four-player viewports | No command view, selection or orders. |

## Design

### 1. Structure definitions: the modular layer

One data type, a **structure**, replaces the per-tool palettes. A structure is a name, a stable id, a footprint of block cells (the block prefab format), zero or more attached **modules**, and its stats. Modules are a closed set of Zig behaviours configured by data (no scripting needed, so saves and mods stay safe):

| Module | Does | Key data |
| --- | --- | --- |
| `turret` | Shoots the nearest Hive or robot unit in range | range, damage, rate, ammo cost |
| `launcher` | Fires homing missiles at ground or air targets | range, damage, reload, missiles held |
| `shield` | A dome that absorbs enemy projectiles and melee on structures inside it | radius, hit points, recharge, power |
| `drill` | Produces ore from the node beneath it | node kind, rate |
| `bay` | Holds and launches drones of one kind | drone kind, count |
| `store` | Holds materials for the settlement | capacity |
| `field` | Grows crops over its area (the `Farm` crops, automated) | area, crop |
| `power` | Gives and uses power (sap tap, generator, solar) | output, draw |
| `workshop` | Turns materials into other materials or ammo | recipe |

Players make their own in three ways, in this order of build: (a) **capture** a built block-and-machine arrangement as a structure (extending `captureBox`, P) and attach modules in a small panel; (b) **author** a structure file in `saves/structures/<id>.json` (shareable, validated like mod content, with the same limits and errors); (c) mods add structures the same way (`mods.md`). Starter structures (below) are the same files, so everything players can do, the starter set does too. A structure's cost is the sum of its blocks plus its module costs, so custom designs are paid for honestly.

The existing tools become **tool modules** over one registry: each declares its key, its palette source (blocks, structures, machines), its validate and apply steps and its input handlers. This is a refactor with no new behaviour first (BS1), so nothing visible changes while the registry replaces the hard-coded lists.

### 2. Materials: easy to get, two sources

- **Fight robots (personal):** every Scalari robot and Hive unit gets a drop table: scrap most kills, parts sometimes, with elites and carriers paying more. Drops go to the killer's own `Wallet` (a personal reward, per [AGENTS.md](../../AGENTS.md)). Targets: a few kills fund a turret; a wave fights an outpost's worth. Numbers are tuned in play, in one table (`Loot` data), not spread through combat code.
- **Mine (shared):** surface **ore veins** (new seeded pickup nodes, visible glow, 1 to 3 per region near the city and in caves) can be mined by hand with the hands tool (a few seconds, personal) or by a **drill structure** (automatic, shared). Ore turns to scrap and parts at a **workshop**, or is spent directly on structures.
- **Materials:** scrap, parts, ore, hay (food), power as a rate. Four stored materials keep the first slice small.

### 3. Automation: bases and drones

- **Mining base:** a drill on an ore vein, a store, a bay of miner drones and power. The drill makes ore each settlement hour; drones visibly shuttle ore from the drill to the store; an unattended base keeps producing (derived from the saved tick, so a reload agrees).
- **Farming base:** a field structure (extends `Farm.zig`: sprinklers and a harvester drone), growing hay and food over the global season calendar; harvesting by drone sends hay to the store.
- **Drones:** miner, harvester and hauler as one `Drone` kind with a task (mine, harvest, haul, repair), a fixed pool (for example 32 per settlement), simple state machines (go, work, return) and no pathfinding beyond straight lines over the terrain at first. Only drones near a player are simulated as moving bodies; the rest advance as numbers. Hive units target drones and structures, so bases need defending.
- **Stockpile:** one shared team stockpile (decided 2026-10-15), withdrawn by anyone, with every withdrawal logged per player. Personal wallets stay personal; a player contributes by an explicit action.

### 4. Defense: protective prefabs

Starter structures built from the modules above, sold at the fabricator for scrap and parts:

- **Sentry turret** (small): short range, fast, cheap; the stand-in for the ranger special that lasts.
- **Heavy turret:** longer range and damage, needs power.
- **Shield generator:** a dome (radius 12 to 24 m) that absorbs projectiles until its hit points run out, then recharges; needs power; shows its remaining strength as a ring.
- **Missile launcher:** homing missiles, long range, slow reload, ammo from the store.
- **Wall and gate sections** from the block grid (already exist) form the perimeter.

Structures get **hit points and repair**; **Hive raids** (timed waves from nearby nests, scaled by settlement size and shown on the map with a warning) target the nearest structure or drone. Destroyed structures leave rubble that refunds part of their cost. Defenses that run out of power or ammo stop, which is why the economy matters.

### 5. Strategy GUI (Civilization in 3D)

Four players, one screen each, so the command view is per player and does not take the whole game:

- **Command view (toggle, default Tab-M or a pad chord):** the camera lifts to an orbit view over the settlement, with the world still running. A cursor selects structures and drones; a left panel lists structures; a top bar shows the stockpile (ore, scrap, parts, hay, power) with the per-hour income; a bottom bar shows the selection's data and orders.
- **Orders:** place from the structure palette, assign drones to a bay or a task, set a rally point, toggle a structure on or off, repair, demolish (refund part). Orders are validated, then applied, so a refused order changes nothing.
- **Alerts and map:** raid warnings, "out of power", "store full" and "drone lost" as a list with a jump button; the existing world map shows structures and claims.
- **Controls:** mouse and keyboard, and a pad cursor with the same actions (guests included), reusing the guest build routing already in place for blocks.
- **In-game guide:** a STRATEGY page in HOW TO PLAY, kept in step with the controls table.

## Build order

Each step is small, playable in the real game, and proven by a test or a smoke stage ([AGENTS.md](../../AGENTS.md)); each updates the docs it touches.

| Step | Deliverable | Proved by |
| --- | --- | --- |
| BS1 | **Done 2026-10-22.** **Tool registry refactor:** one list of placeable things and tool modules; `BlockTool`, `Build`, bridge and terrain tools register into it. No behaviour change. | Existing suite unchanged; smoke stages for each tool still pass. |
| BS2 | **Done 2026-10-22.** **Loot tables:** scrap and parts drops by enemy kind, personal wallet, shown in the HUD and a drops line. | Test: a kill pays its table; the arena and capture rewards unchanged. |
| BS3 | **Done 2026-10-22 (data, placement, capture, files; no behaviours yet).** **Structure definitions:** the data type, validation and limits, block footprint plus modules, starter structure files, capture-as-structure (P) with a module panel. | Round-trip and limit tests; a captured structure places and refunds correctly. |
| BS4 | **Done 2026-10-22 (turret, launcher, shield, power; raid and structure hit points).** **Defense modules:** turret, launcher and shield as structures with hit points, power and ammo; enemies attack structures; a small raid. | Tests per module (targets, damage, shield absorb and recharge); smoke: a raid is held by a turret and a shield. |
| BS5 | **Ore and drills:** ore veins, hand mining, the drill module, the shared stockpile (save format bump, round-trip test). | Hourly production test (a reload agrees with the saved tick); smoke mines and spends ore. |
| BS6 | **Drones:** miner, hauler and harvester, the bay module, a farming base on `Farm.zig`. | Task state-machine tests; smoke runs a mining base for a simulated hour. |
| BS7 | **Command view and orders:** camera, selection, panels, orders, alerts, pad cursor, STRATEGY guide page. | Layout test at 720p and 640x480; capture review; guest pad routing test. |
| BS8 | **Polish and balance:** costs, rates, raid sizes, hands-on checklist, benchmarks (structures and drones on screen in four-player split screen). | Recorded numbers. |

## Risks

- **Scope.** This is as large as the whole building track. BS1 to BS4 (a defendable outpost) are a complete slice on their own; BS5 to BS7 (automation and the command view) follow only after that slice is played.
- **Four-player cost.** Many drones and structures in four viewports can exceed the render budget; drones off screen advance as numbers, structures are instanced props, and BS8 measures it.
- **Save size.** Structures, drones and the stockpile must stay under the 4 MiB cap: fixed caps checked at load, run-length data, and one format bump per step.
- **Module state.** Large arrays go on the heap (Mach copies module state on an 8 MB stack).
- **Balance.** Free-form structures can break the economy; costs derive from parts, and limits (turrets per claim, power draw) cap stacking.

## Decisions (owner, 2026-10-22)

1. **First slice:** the defendable outpost (BS1 to BS4). Economy and drones (BS5 to BS7) follow once it has been played.
2. **Stockpile:** one shared team stockpile for automated output; robot drops and hand-mined loot stay in each player's own wallet.
3. **Command view:** a per-player orbit camera over the live world, with selection, panels and orders, usable by all four players in their own viewport.
4. **Authoring:** capture in game (P) plus module panel, and the same format as shareable data files that mods can also add.
