# Arbor genomes and sap

The world now contains the original climbable test Arbor plus two trees grown from the world seed. Each generated Arbor shares one branch skeleton between its render meshes, woody collider, tap attachment queries, and vascular network.

| Tree ID | Location (world X, Z) | Shape | Sap supply |
| --- | --- | --- | --- |
| 0 | 60, 22 | Original 320 m test Arbor and spiral ramp | 200 W |
| 1 | 240, 180 | 420 m narrow crown, cyan lumen | 150 W |
| 2 | -340, 300 | 340 m spreading crown, amber lumen | 300 W |

Use **V** to fly toward the new crowns; **Q/E** changes altitude and **Shift** speeds flight. The original ramp, platform, bridge, and tower remain walkable. Generated branch shelves have flat collision surfaces; clustered foliage has no collision.

## Try sap power

1. Press **2**, then **Tab** to select **sap beacon**. It contains a tap, an always-on controller, and a 150 W lumen lamp.
2. Place it on clear ground beside a trunk. The tap must be within 4 m of wood; green previews confirm valid placement. The cyan marker on tree 1 identifies its near-ground tap area.
3. Place a second beacon beside that same tree. Tree 1's 150 W capacity is shared by both 150 W loads, so each lamp receives 50% power. Remove either beacon to restore full power to the other.
4. Aim at a tap to see total tree demand, supplied watts, and satisfaction. **I** opens the machine inspection panel, including the attached tree and vascular-node IDs.
5. **F5/F9** saves/loads the built machines and their wiring. Attachments are resolved from physical positions again after loading.

The **sap tap** palette item is the loose 200 W-rated source for custom workshop circuits. Wire `power` to a lamp, motor, or actuator; `enable` is on unless wired to a signal. Separate machines tapping the same Arbor share its budget. Taps on branches also share the narrower upstream branch limits. Detached, disabled, and idle taps draw no sap. A network uses regular generator supply before asking for sap. Lamps expose partial power as partial brightness; tree lumen dims under load beyond available flow.

## Rootsong

Arbors whose roots overlap form a **root group**. A tree's roots reach half its height from its trunk, so two trees share roots when they are closer than half the sum of their heights. In the current grove, the test Arbor (320 m) and the narrow Arbor (420 m, about 240 m away) share one root group; the spreading Arbor stands alone.

- **Devices:** the palette's **root sender** and **root listener** carry a signal on a channel (1–64, `[` / `]` to retune) like transmitters and receivers. They only work within 4 m of wood, like a sap tap. A signal reaches only listeners rooted in the **same root group**, one step later, with the largest value winning per channel.
- **Unrooted devices** are silent, and listeners on another root group hear nothing.
- **Inspecting:** aim at a root device to see its channel and root group (or "unrooted"). The inspection panel shows the same.
- **Shrine rewards:** the Rootdeep shrines reward two Rootsong designs. **rootsong_hearth** is a sap-powered lamp that lights when it hears channel 1; **rootsong_call** is a button and latch driving a root sender. See [Rootdeep shrines](rootdeep.md).

Groups are computed once for the resident grove with union-find (`machine/Rootsong.zig`). Devices re-attach from their physical positions every step, so loading a save re-roots them. The acceptance test lights a listener lamp at the narrow Arbor from a sender at the test Arbor, while identical lamps at the spreading Arbor and far from wood stay dark. Retuning silences it, and the song survives save/load.

## Generation and limits

`procedural/Arbor.zig` defines genome version 1 and Arbor generator version 1. Genes control height, trunk radius, crown spread, phyllotaxis, apical dominance, phototropism, gravitropism, platform tendency, vascular capacity, bark/ridging, and lumen color. Named presets live in `asset/Catalog.zig`; they are grown with separate stable seeds derived from the world seed.

A tapered leader and phyllotactic scaffold seed bounded space colonization: 128 crown attraction points, at most 28 growth rounds and 192 nodes per Arbor. Points attract nearby branches and disappear when reached. Shelves flatten selected growth directions. Growth happens at load time; simulation allocates no memory for sap distribution. The full woody mesh supplies collision; the distance proxy reduces radial segments and omits thin branches and shelf details beyond 600 m while retaining foliage clusters.

Flow allocation is proportional and conservative: each request is limited by the most oversubscribed edge on its path to the root. It does not redistribute unused capacity after a branch bottleneck. This prevents overdraw and keeps results independent of machine iteration order, but can leave spare root capacity unused.

There are three fixed resident trees, not a streamed city. Grafting, genome editing in the game, growth over time, pipes, and tree residency eviction remain future work. Foliage is an initial faceted representation; appearance still needs manual art review.

Content version is now **4**. Saves record the Arbor generator version, and older content saves are rejected rather than loading the player into changed geometry. Existing save files are not migrated automatically.

## Reproduce the views

```sh
python3 tools/zig.py build test -Doptimize=ReleaseSafe
MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=400
python3 tools/benchmark.py --arbor 1 --frames 300
python3 tools/benchmark.py --arbor 2 --frames 300
```

The canopy routes view the chosen Arbor up close, beyond 1 km, and back. Reports use separate `.tools/canopy-1-benchmark.json` and `.tools/canopy-2-benchmark.json` paths. Keep the window visible for representative presentation timing; CPU submission timing is reported separately from presentation intervals.
