# Heavy Water

A Zig/Mach 3D engine foundation for a procedural science-fiction exploration and engineering game.

The first executable is an engine field test: one seeded terrain chunk, 1,000 instanced relics, a free camera, depth testing, a checker texture, directional lighting, distance fog, optional CPU frustum culling, and an in-window metrics overlay. It is a rendering and simulation foundation; gameplay, physics, streaming, and editing come next.

## Run

Python 3.10+ is the only bootstrap prerequisite. From this directory:

```sh
python3 tools/zig.py build run
```

The launcher downloads a checksum-verified compiler into `.tools/` when needed. It leaves your system Zig and PATH alone. Zig fetches the pinned Mach dependencies on the first build; an internet connection is required then. Windows users can use `py tools/zig.py`.

If you already use the exact compiler or anyzig, ordinary `zig build run` also works.

| Control | Action |
| --- | --- |
| W / A / S / D | Move camera |
| Q / E | Descend / ascend |
| Shift | Faster movement |
| Left click, then mouse | Capture pointer and look |
| Escape | Release pointer |
| R | Reset camera |
| C | Toggle CPU frustum culling (off initially to submit all 1,000 objects) |
| F1 | Toggle metrics |
| Window close | Quit |

```sh
python3 tools/zig.py build test
python3 tools/zig.py build check
python3 tools/zig.py build run -Doptimize=ReleaseSafe
python3 tools/zig.py build run -Dseed=42
python3 tools/zig.py build run -Dsmoke-frames=120
python3 tools/zig.py build -Doptimize=ReleaseFast
```

`build` installs `zig-out/bin/heavy-water`; `run` executes directly from Zig's build cache. Smoke mode exits after the specified number of submitted frames and exercises camera changes, culling (including an empty view), and HUD toggling. Use at least 16 frames to exercise all stages. It requires a graphical desktop and GPU. Tests do not open a window.

## Pinned foundation

- Mach: [`7ed0d504a9569fd4ad840ecb10ead16b90a8926e`](https://code.hexops.org/hexops/mach/src/commit/7ed0d504a9569fd4ad840ecb10ead16b90a8926e/build.zig.zon), package hash in `build.zig.zon`.
- Mach nominated Zig: `2026.4.10-mach` = `0.16.0-dev.3142+5ccfeb926`.
- Generator version: `1`; default seed: `310399555161`.

The compiler matches this Mach revision's manifest. The [nomination history](https://machengine.org/docs/nominated-zig/) also lists newer compilers; upgrading the compiler and Mach must be a tested change together.

Local validation targets Apple Silicon / Metal. Linux/Vulkan and Windows/D3D12 are future runtime validation targets, even though Mach exposes those backends. Frame timing in the HUD measures the interval between render callbacks, including presentation pacing; it is not GPU execution time or a performance benchmark.

Known upstream limitation: programmatically changing window dimensions deadlocks in this Mach revision's macOS resize callback. This application does not change dimensions after startup. The renderer recreates its depth buffer when framebuffer dimensions change, but interactive drag-resize has not been validated here. See the [validation notes](docs/validation.md).

Read [architecture and ownership](docs/architecture.md) and the [milestone roadmap](docs/roadmap.md).
