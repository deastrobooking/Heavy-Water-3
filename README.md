# Heavy Water

**A native Zig exploration, engineering, and world-building game for a wild, technological future Earth.** Built on Mach, Heavy Water brings together procedural Arbors, a living canopy city, hands-on machine building, and traversal across a vast vertical landscape.

## Build and run

From the repository root, build the installed executable and launch it:

```sh
python3 tools/zig.py build
./zig-out/bin/heavy-water
```

For Windows, use `py tools/zig.py build`. The launcher downloads the checksum-verified Zig compiler into `.tools/` when needed and does not change the system Zig or `PATH`. The first build fetches pinned Mach dependencies and requires an internet connection. For a development build that runs directly from the build cache, use `python3 tools/zig.py build run`.

The default compiler is the Zig revision required by the pinned Mach engine. To check newer compilers while preparing the engine update, run:

```sh
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check
HEAVYWATER_ZIG_CHANNEL=0.18-dev python3 tools/zig.py build check
```

On Windows, set the environment variable before `py tools/zig.py build check`. Zig 0.17.0 is a separately pinned stable compiler and currently passes the build, tests and Metal smoke run (the default has not moved yet); the 0.18 channel is a pinned development snapshot that passes on macOS but not yet for Windows targets. The project-owned engine source lives in `vendor/mach`.

> **Project status:** playable systems prototype in active development. The current build focuses on exploration, construction, machines, vehicles, local co-op, and a bounded procedural district. The Hive war and full combat campaign are still in development; see [the gameplay overview](docs/project-overview.md#what-you-can-do) for status.

## In the Current Build

- Explore the Rootdeep, climbable Arbors, shrines, towers, and a generated canopy district.
- Build and wire machines, drive a powered rover, add bridges, trade at markets, and save your world.
- Talk with stall keepers and locals in branching conversations; buy suit upgrades and armor suits from the south-market tinker; customize your ranger.
- Title, pause, settings (saved to `saves/settings.json`) and controls screens, driven by keyboard, mouse, or controller; every key can be rebound. Settings includes a reversible max-progression test mode that disables campaign and ranger saves while active.
- Procedural sound: synthesized footsteps, jets, wind, a canopy ambience, interface and dialogue sounds, mixed in native Zig, with volume controls.
- Drive and fly a starter Skimmer with ducted lift fans, a swept canopy, and cyan flight lighting; then build two specialized hover cars. Collect lumen shards, rotor cores, Hive alloy and vital cells to fabricate armor and weapons.
- Fight the Hive: drones and sentinels guard three nests in the outskirts; blaster, saber, bow with warp arrows, missiles, shield and giant blast.
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
zig-out/bin/asset-compiler trace assets/source/crate.gltf assets/source/crate.gltf.meta zig-out/crate.trace.json # inspect stable source/module lineage
zig-out/bin/asset-compiler split assets/source/crate.gltf assets/source/crate.gltf.meta zig-out/crate-parts # export individual HWMS mesh modules
python3 tools/zig.py build mods       # build the example WebAssembly mod
python3 tools/zig.py build sounds     # write the synthesized sounds to zig-out/sounds/*.wav
python3 tools/zig.py build run -Daudio=false  # run without opening an audio device
python3 tools/zig.py build run -Dsmoke-frames=120
python3 tools/zig.py build run -Dhot-reload=true  # watch models, built-in blueprints and mod Wasm
python3 tools/zig.py build run -Dreload-smoke=true -Dsmoke-frames=600 -Doptimize=ReleaseSafe
python3 tools/benchmark.py --canopy
python3 tools/benchmark.py --pack 64    # background-load an 80 MiB pack of 64 meshes during measurement
```

`run` needs a graphical desktop and GPU; headless tests do not open a window. The installed executable is `zig-out/bin/heavy-water`; run it from the repository root. Every build option, test, smoke run, benchmark, showcase and capture is documented in [Building and Testing](docs/building-and-testing.md).

## Documentation

| Guide | What it covers |
| --- | --- |
| [Project Overview](docs/project-overview.md) | Gameplay, controls, local co-op, and the technical snapshot |
| [World and Systems](docs/world.md) | Setting, pillars, Arbors, and visual direction |
| [Building and Testing](docs/building-and-testing.md) | Build steps and options, running, tests, smoke runs, benchmarks, showcases, captures, and troubleshooting |
| [Development Roadmap](docs/roadmap.md) | Implemented milestones, acceptance evidence, and next work |
| [Architecture and Ownership](docs/architecture.md) | System boundaries, memory, threads, assets, physics, and rendering |
| [Arbor Genomes and Sap](docs/arbors.md) | Procedural trees, Rootsong, and sap power |
| [Canopy City](docs/city.md) | District layout, bridges, traffic, and building |
| [Rootdeep Shrines](docs/rootdeep.md) | Generated puzzle design and verification |
| [Hive War Gameplay Direction](docs/gameplay_and_hive_war.md) | Faction, combat, companions, and strategy-game concepts |
| [Mods](docs/mods.md) | Mod packages and the constrained WebAssembly API |
| [Scale Tests](docs/scale.md) | Reproducible workload and performance methodology |
| [Validation](docs/validation.md) | Test results, platform coverage, and known limitations |
| [Next Steps](docs/plans/next-steps.md) | Ordered plan after the frontier and flight work: play and tune, air war depth, Hive campaign, co-op, engine phases |
| [Heightmapped Landscapes](docs/plans/landscapes.md) | Heightmap import, biome shaping, and temple/cave generation plan |
| [Mach and Zig Update Process](docs/plans/engine-update-process.md) | Importing newer engine/compiler versions, compatibility gates, and preparing upstream proposals |

Additional system plans live in [`docs/plans/`](docs/plans/), including scenes, the asset pipeline, animation, and engine alignment.

## Technology

- **Language:** Zig `0.16.0-dev.3142+5ccfeb926`, pinned for the selected Mach revision. Zig 0.17.0 and a pinned Zig 0.18.0-dev snapshot are available as opt-in channels; 0.17 passes the project's checks and adoption is pending.
- **Platform and graphics:** a project-owned [Mach fork](vendor/mach/FORK.md), based on upstream `7ed0d504`, with `sysgpu`.
- **Runtime systems:** native Zig procedural generation, physics, asset catalog, machine simulation, streaming, and mod interpreter.
- **Validation target:** Apple Silicon with Metal. Linux/Vulkan and Windows/D3D12 runtime testing remains future work.

Frame intervals include presentation pacing and are not GPU execution timings. The pinned Mach revision also has a known macOS programmatic-resize deadlock; see [Validation](docs/validation.md) before changing window behavior.
