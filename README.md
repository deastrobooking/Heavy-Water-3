# Heavy Water

A native Zig engine (on Mach) for a science-fiction exploration and engineering game: *The Legend of Zelda* meets sci-fi anime, in a city that grows through genetically engineered trees 300–600 m tall. See [world and systems](docs/world.md).

The executable is an engine field test: an unbounded-feeling seeded terrain streamed in 128 m chunks by a background worker, continuous biome masks, slope-aware relic and vegetation scatter with stable chunk-local IDs, a free camera, depth testing, a checker texture, directional lighting, distance fog, CPU frustum culling, and an in-window metrics overlay. Create and name your ranger, then start on foot: walk the streamed terrain, pick up and carry physical supply crates (imported from glTF), remove relics with the salvage cutter, operate a generator-powered sliding door and an elevator, drive a battery-powered rover on raycast suspension, all built from data-driven machine blueprints. With the build tool you place crates, those machines, and loose devices (generators, buttons, latches, logic, lamps, radio transmitters and receivers) on a snapping grid; with the wire tool you connect their ports in the world. Capture any machine or circuit as a prefab to place copies, and inspect a machine's power networks, device outputs, and wires. Quicksave/quickload stores the whole world, including what you built, rewired, and captured. Every engine system is native Zig; Mach provides the platform and GPU layer.

The climbable test Arbor stands near spawn: follow its spiral ramp to a branch platform and cross the bridge to the tower. The world uses cel shading, rim light, depth silhouettes, and height-aware haze. A twenty-minute day/night cycle starts at 08:24; the HUD shows world time, and quickload restores it. Powered lamps and your ranger's lumen accents stay luminous after dusk (emissive surfaces, without local light casting or bloom).

Two additional Arbors now grow from versioned genomes: a narrow cyan tree and a spreading amber tree. Place **sap beacons** beside a trunk to power their lamps; multiple taps share the tree's supply and brown out together. See [Arbor genomes and sap](docs/arbors.md) for locations, controls, and the current limits. The grove now connects through a six-plaza canopy district with towers, trunk walkways, and vine-supported roads. Press **4** to build bridges between plaza markers; machines can be placed on elevated decks. See [canopy city](docs/city.md) for the route and construction controls. Saves now use format 7 and content version 5; older saves are rejected.

## Run

Python 3.10+ is the only bootstrap prerequisite. From this directory:

```sh
python3 tools/zig.py build run
```

The launcher downloads a checksum-verified compiler into `.tools/` when needed. It leaves your system Zig and PATH alone. Zig fetches the pinned Mach dependencies on the first build; an internet connection is required then. Windows users can use `py tools/zig.py`.

If you already use the exact compiler or anyzig, ordinary `zig build run` also works.

| Control | Action |
| --- | --- |
| W / A / S / D | Walk (or fly) |
| Space | Jump (buffered, with coyote time); hold in the air to use the traversal kit; three quick taps toggle hover. Jump into a wall to climb it; jump off a wall to wall-jump |
| Shift | Sprint / fly faster |
| Left Ctrl | Roll when running (hoverboard: boost; flight: air dash while held with Space) |
| X | Stomp in the air; bounces on landing |
| G | Grapple a static surface (grapple kit): zip, or swing from high anchors; again to release |
| B | Cycle traversal kit: grapple → hover jet → flight → hoverboard |
| F | Hold at a ledge to hang; again to mantle up |
| F6 | Add a guest player (P2–P4) beside you, or remove the last keyboard-added guest |
| V | Toggle walking and free flight |
| F2 | First- / third-person view |
| F4 | Character creator (also opens on a new game): arrows choose and change, type the name, Enter confirms, Escape cancels |
| Q / E | Descend / ascend (flight) |
| Left click, then mouse | Capture pointer and look |
| 1 / 2 / 3 / 4 | Hands / build tool / wire tool / bridge tool |
| Left click (captured), hands | Grab or drop a crate, press a machine button, or enter the rover; exit the rover while driving |
| Right click (captured), hands | Salvage cutter: remove the relic under the crosshair |
| Build tool | Tab next palette item, T rotate 90°, left click place (green preview), right click remove the crate, device, or machine under the crosshair |
| Wire tool | Left click a source device, then a target (Tab cycles valid port pairs), left click to connect; right click disconnects the aimed device's inputs or cancels |
| Bridge tool | Click two visible plaza markers to preview and build; right click cancels a selection or removes your aimed bridge |
| P (build or wire tool) | Capture the aimed machine as a prefab: added to the palette and exported to `saves/prefabs/<name>.json` |
| I | Toggle the inspection panel for the aimed machine |
| [ / ] | Change the aimed transmitter's or receiver's channel (1–64) |
| W / S, A / D (driving) | Throttle and reverse, steer |
| Space (driving) | Brake (an empty rover holds its parking brake) |
| F5 / F9 | Quicksave / quickload `saves/quicksave.json` |
| Escape | Release pointer |
| R | Return to spawn |
| C | Toggle CPU frustum culling (on initially) |
| F1 | Toggle metrics |
| Window close | Quit |

### Local co-op

Up to four players share one window. Each extra player gets a split-screen view: two players stack top and bottom, three put P3 across the bottom, and four use quadrants. On macOS, controllers with Apple's extended gamepad profile (Xbox, PlayStation, and MFi pads) are read through the GameController framework. The first three controllers belong to P2, P3 and P4, and a fourth controller also drives P1 alongside the keyboard.

| Pad | Action |
| --- | --- |
| Menu | Join or leave; disconnecting a pad also leaves |
| Left / right stick | Move / look |
| A | Jump (same traversal rules as Space) |
| B | Roll / boost / dash |
| X | Press the aimed button; hold to hang and mantle |
| Y | First- / third-person view |
| LB / RB | Grapple / cycle traversal kit |
| LT | Sprint |
| Left stick click | Stomp |
| Options | Respawn beside P1 |

Guests have the full traversal controller, their own camera, and hands that press machine buttons; proximity sensors see every player. Building, wiring, carrying crates, driving, salvage, and saving remain P1's. Guests are not written to saves; after a load they rejoin beside P1.

```sh
python3 tools/zig.py build test
python3 tools/zig.py build check
python3 tools/zig.py build assets        # compiled models and validated blueprints in zig-out/assets
python3 tools/zig.py build run -Doptimize=ReleaseSafe
python3 tools/zig.py build run -Dseed=42
python3 tools/zig.py build run -Dsmoke-frames=120
python3 tools/zig.py build -Doptimize=ReleaseFast
python3 tools/benchmark.py            # fixed fly-through route, writes .tools/streaming-benchmark.json
python3 tools/benchmark.py --canopy   # Test Arbor at close range and 1 km
python3 tools/benchmark.py --arbor 1  # Seeded narrow Arbor (2 selects the spreading Arbor)
```

Prefab blueprints in `saves/prefabs/*.json` are imported at startup and after a quickload. They use the same format as `assets/source/blueprints`, and invalid files are skipped with a logged reason.

`build` installs `zig-out/bin/heavy-water`; `run` executes directly from Zig's build cache. Smoke mode exits after the specified number of submitted frames and exercises flight, culling (including an empty view), HUD toggling, walking, grabbing a crate, an in-memory save/restore round trip, building and wiring a four-device lamp circuit, lighting the circuit before pressing the door button, driving the rover, rendering a full day/night cycle, visiting both generated Arbors, overloading two sap beacons on one tree, previewing a city bridge, and restoring its completed geometry from an in-memory save. Three guests join partway through, which exercises four-, two- and one-view split screen. It never writes the save file. Use 120 or more frames to give the simulation time to exercise all stages. It requires a graphical desktop and GPU. Tests do not open a window.

The benchmark flies a frame-indexed route across 40 chunk boundaries (60 warm-up frames, then `--frames` measured frames), and fails unless uploads stay within budget, GPU residency stays at 25 chunks, pools never grow, the 3×3 active ring is always resident, and the window was not throttled. The `--canopy` route stays aimed at the Arbor, verifies both mesh detail levels and a render CPU P99 under 16.667 ms, and crosses at least 12 chunk boundaries. These measurements do not measure GPU execution time. Keep the window visible while it runs. `-Dupload-budget-kib` (minimum 278, one chunk) bounds terrain bytes written to the GPU per frame.

## Pinned foundation

- Mach: [`7ed0d504a9569fd4ad840ecb10ead16b90a8926e`](https://code.hexops.org/hexops/mach/src/commit/7ed0d504a9569fd4ad840ecb10ead16b90a8926e/build.zig.zon), package hash in `build.zig.zon`.
- Mach nominated Zig: `2026.4.10-mach` = `0.16.0-dev.3142+5ccfeb926`.
- Generator version: `2`; default seed: `310399555161`.

The compiler matches this Mach revision's manifest. The [nomination history](https://machengine.org/docs/nominated-zig/) also lists newer compilers; upgrading the compiler and Mach must be a tested change together.

Local validation targets Apple Silicon / Metal. Linux/Vulkan and Windows/D3D12 are future runtime validation targets, even though Mach exposes those backends. Frame timing in the HUD measures the interval between render callbacks, including presentation pacing; it is not GPU execution time or a performance benchmark.

Known upstream limitation: programmatically changing window dimensions deadlocks in this Mach revision's macOS resize callback. This application does not change dimensions after startup. The renderer recreates its depth buffer when framebuffer dimensions change, but interactive drag-resize has not been validated here. See the [validation notes](docs/validation.md).

Read [world and systems](docs/world.md), [architecture and ownership](docs/architecture.md), and the [milestone roadmap](docs/roadmap.md).
