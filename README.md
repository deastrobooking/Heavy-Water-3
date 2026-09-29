# Heavy Water

A Zig/Mach 3D engine foundation for a procedural science-fiction exploration and engineering game.

The executable is an engine field test: an unbounded-feeling seeded terrain streamed in 128 m chunks by a background worker, continuous biome masks, slope-aware relic and vegetation scatter with stable chunk-local IDs, a free camera, depth testing, a checker texture, directional lighting, distance fog, CPU frustum culling, and an in-window metrics overlay. You start on foot: walk the streamed terrain, pick up and carry physical supply crates (imported from glTF), remove relics with the salvage cutter, operate a generator-powered sliding door and an elevator built from data-driven machine blueprints, and quicksave/quickload all of it. Every engine system is native Zig; Mach provides the platform and GPU layer. Vehicles and in-game editing come next.

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
| Space | Jump |
| Shift | Sprint / fly faster |
| V | Toggle walking and free flight |
| Q / E | Descend / ascend (flight) |
| Left click, then mouse | Capture pointer and look |
| Left click (captured) | Grab or drop the crate, or press the machine button, under the crosshair |
| Right click (captured) | Salvage cutter: remove the relic under the crosshair |
| F5 / F9 | Quicksave / quickload `saves/quicksave.json` |
| Escape | Release pointer |
| R | Return to spawn |
| C | Toggle CPU frustum culling (on initially) |
| F1 | Toggle metrics |
| Window close | Quit |

```sh
python3 tools/zig.py build test
python3 tools/zig.py build check
python3 tools/zig.py build assets        # compiled models and validated blueprints in zig-out/assets
python3 tools/zig.py build run -Doptimize=ReleaseSafe
python3 tools/zig.py build run -Dseed=42
python3 tools/zig.py build run -Dsmoke-frames=120
python3 tools/zig.py build -Doptimize=ReleaseFast
python3 tools/benchmark.py            # fixed fly-through route, writes .tools/streaming-benchmark.json
```

`build` installs `zig-out/bin/heavy-water`; `run` executes directly from Zig's build cache. Smoke mode exits after the specified number of submitted frames and exercises flight, culling (including an empty view), HUD toggling, walking, grabbing a crate, and an in-memory save/restore round trip. It never writes the save file. Use at least 16 frames to exercise all stages. It requires a graphical desktop and GPU. Tests do not open a window.

The benchmark flies a frame-indexed route across 40 chunk boundaries (60 warm-up frames, then `--frames` measured frames), and fails unless uploads stay within budget, GPU residency stays at 25 chunks, pools never grow, the 3×3 active ring is always resident, and the window was not throttled. Keep the window visible while it runs. `-Dupload-budget-kib` (minimum 278, one chunk) bounds terrain bytes written to the GPU per frame.

## Pinned foundation

- Mach: [`7ed0d504a9569fd4ad840ecb10ead16b90a8926e`](https://code.hexops.org/hexops/mach/src/commit/7ed0d504a9569fd4ad840ecb10ead16b90a8926e/build.zig.zon), package hash in `build.zig.zon`.
- Mach nominated Zig: `2026.4.10-mach` = `0.16.0-dev.3142+5ccfeb926`.
- Generator version: `2`; default seed: `310399555161`.

The compiler matches this Mach revision's manifest. The [nomination history](https://machengine.org/docs/nominated-zig/) also lists newer compilers; upgrading the compiler and Mach must be a tested change together.

Local validation targets Apple Silicon / Metal. Linux/Vulkan and Windows/D3D12 are future runtime validation targets, even though Mach exposes those backends. Frame timing in the HUD measures the interval between render callbacks, including presentation pacing; it is not GPU execution time or a performance benchmark.

Known upstream limitation: programmatically changing window dimensions deadlocks in this Mach revision's macOS resize callback. This application does not change dimensions after startup. The renderer recreates its depth buffer when framebuffer dimensions change, but interactive drag-resize has not been validated here. See the [validation notes](docs/validation.md).

Read [architecture and ownership](docs/architecture.md) and the [milestone roadmap](docs/roadmap.md).
