# Heavy Water

**A native Zig exploration, engineering, and world-building game for a wild, technological future Earth.** Built on Mach, Heavy Water brings together procedural Arbors, a living canopy city, hands-on machine building, and traversal across a vast vertical landscape.

> **Project status:** playable systems prototype in active development. The current build focuses on exploration, construction, machines, vehicles, local co-op, and a bounded procedural district. The Hive war and full combat campaign are still in development; see [the gameplay overview](docs/project-overview.md#what-you-can-do) for status.

## In the Current Build

- Explore the Rootdeep, climbable Arbors, shrines, towers, and a generated canopy district.
- Build and wire machines, drive a powered rover, add bridges, trade at markets, and save your world.
- Use grapple, hover, flight, wall jumps, dashes, and other traversal kits; play local split-screen with up to four players.
- Grow procedural trees and connect machines through sap power and Rootsong networks.
- Run on a native Zig engine using Mach for platform and GPU foundations.

The full gameplay guide, controls, and technical overview are in [Project Overview](docs/project-overview.md).

## Quick Start

Python 3.10+ is the only bootstrap prerequisite. From the repository root:

```sh
python3 tools/zig.py build run
```

The launcher downloads a checksum-verified Zig compiler into `.tools/` when needed and does not alter the system Zig or `PATH`. The first build fetches pinned Mach dependencies and requires an internet connection. On Windows, use `py tools/zig.py`.

```sh
python3 tools/zig.py build test       # headless tests
python3 tools/zig.py build check      # compile the application
python3 tools/zig.py build assets     # compile models and validate blueprints
python3 tools/zig.py build import     # after adding or changing a source asset: create/refresh its .meta sidecar (GUID, hash)
python3 tools/zig.py build mods       # build the example WebAssembly mod
python3 tools/zig.py build run -Dsmoke-frames=120
python3 tools/zig.py build run -Dhot-reload=true  # watch models, built-in blueprints and mod Wasm
python3 tools/zig.py build run -Dreload-smoke=true -Dsmoke-frames=600 -Doptimize=ReleaseSafe
python3 tools/benchmark.py --canopy
python3 tools/benchmark.py --pack 64    # background-load an 80 MiB pack of 64 meshes during measurement
```

`run` needs a graphical desktop and GPU; headless tests do not open a window. More benchmark and showcase commands are in [Scale Tests](docs/scale.md).

## Documentation

| Guide | What it covers |
| --- | --- |
| [Project Overview](docs/project-overview.md) | Gameplay, controls, local co-op, and the technical snapshot |
| [World and Systems](docs/world.md) | Setting, pillars, Arbors, and visual direction |
| [Development Roadmap](docs/roadmap.md) | Implemented milestones, acceptance evidence, and next work |
| [Architecture and Ownership](docs/architecture.md) | System boundaries, memory, threads, assets, physics, and rendering |
| [Arbor Genomes and Sap](docs/arbors.md) | Procedural trees, Rootsong, and sap power |
| [Canopy City](docs/city.md) | District layout, bridges, traffic, and building |
| [Rootdeep Shrines](docs/rootdeep.md) | Generated puzzle design and verification |
| [Hive War Gameplay Direction](docs/gameplay_and_hive_war.md) | Faction, combat, companions, and strategy-game concepts |
| [Mods](docs/mods.md) | Mod packages and the constrained WebAssembly API |
| [Scale Tests](docs/scale.md) | Reproducible workload and performance methodology |
| [Validation](docs/validation.md) | Test results, platform coverage, and known limitations |
| [Heightmapped Landscapes](docs/plans/landscapes.md) | Heightmap import, biome shaping, and temple/cave generation plan |

Additional system plans live in [`docs/plans/`](docs/plans/), including scenes, the asset pipeline, animation, and engine alignment.

## Technology

- **Language:** Zig `0.16.0-dev.3142+5ccfeb926`, pinned for the selected Mach revision.
- **Platform and graphics:** [Mach](https://github.com/hexops/mach) with `sysgpu`.
- **Runtime systems:** native Zig procedural generation, physics, asset catalog, machine simulation, streaming, and mod interpreter.
- **Validation target:** Apple Silicon with Metal. Linux/Vulkan and Windows/D3D12 runtime testing remains future work.

Frame intervals include presentation pacing and are not GPU execution timings. The pinned Mach revision also has a known macOS programmatic-resize deadlock; see [Validation](docs/validation.md) before changing window behavior.
