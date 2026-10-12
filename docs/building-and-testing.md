# Building and testing

How to build, run, test, benchmark and capture Heavy Water, and what to check before a change is called done. Every command runs from the repository root.

## Requirements

- **Python 3.10+:** the only bootstrap prerequisite.
- **Zig toolchain:** `tools/zig.py` downloads the Mach-pinned Zig compiler (`0.16.0-dev.3142+5ccfeb926`), checksum-verified, into `.tools/`. It never touches the system Zig or `PATH`. Run every build through it: `python3 tools/zig.py <args>` (on Windows, `py tools/zig.py`). Set `HEAVYWATER_ZIG_CHANNEL=0.17` or `HEAVYWATER_ZIG_CHANNEL=0.18-dev` to run compiler compatibility checks; both previews use separately cached, checksum-verified compilers.
- **Mach:** the engine library is the project-owned fork at `vendor/mach`, based on upstream `7ed0d504` (see [fork provenance and patch notes](../vendor/mach/FORK.md)). Third-party packages live in `zig-pkg/`; the first build needs an internet connection to fetch them.
- **A GPU desktop to run the game:** the game is developed and validated on macOS with Metal on Apple silicon (M3 Pro). Tests are headless and need no window.

## Build steps

| Command | What it does |
| --- | --- |
| `python3 tools/zig.py build` | Builds and installs the game to `zig-out/bin/heavy-water` (Debug unless `-Doptimize` is given). |
| `python3 tools/zig.py build run` | Builds and runs the game from the build cache (not the installed copy). |
| `python3 tools/zig.py build check` | Compiles the application without running it. |
| `python3 tools/zig.py build test` | Runs every deterministic test, headless. Add `--summary all` to see the pass count. |
| `python3 tools/zig.py build assets` | Compiles source assets (glTF models, blueprints, and the modifier-baked Captain preview) into `zig-out/assets/`. |
| `python3 tools/zig.py build import` | Creates missing `.meta` sidecars (new GUIDs) and refreshes source hashes under `assets/source`. Run it after adding or changing a source asset. |
| `zig-out/bin/asset-compiler trace <source.glb|source.gltf> <source.meta> <report.json>` | Writes a GUID/hash-linked inventory of scene parts, material slots, dependencies, authored/generated normals, skin joint names/hierarchy and importer gaps. Build the tool with `python3 tools/zig.py build` first. |
| `zig-out/bin/asset-compiler split <source.glb|source.gltf> <source.meta> <output-dir>` | Exports one validated `.hwmesh` per selected-scene node/mesh/primitive and writes `modules.json` with lineage, hashes, material names, normal provenance, counts and bounds. |
| `zig-out/bin/asset-compiler preview-bind <source.glb|source.gltf> <source.meta> <output.png> [bind|run]` | CPU-skins a diagnostic PNG using the GLB bind pose, or the game's procedural run pose retargeted by compatible humanoid joint names. This is an offline art preview; it does not import a rig/clip into the game or create a runtime asset. |
| `zig-out/bin/asset-compiler modifiers <source.glb|source.gltf> <source.meta> <modifiers.json>` | Generates a source-hash-linked Captain modifier document. Edit part labels/surfaces/colors/transforms and the shared skin/eye/armor/energy palette. |
| `zig-out/bin/asset-compiler preview-modified <source.glb|source.gltf> <source.meta> <modifiers.json> <output.png> [bind|run]` | Applies palette and per-part edits and renders a review image. A stale source or changed mesh-island set is rejected. |
| `zig-out/bin/asset-compiler compile-modified <source.glb|source.gltf> <source.meta> <modifiers.json> <output.hwmesh> [bind|run]` | Validates the GLB and modifier sidecar, bakes a selected static pose plus edits into a runtime HWMS mesh. |
| `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dcharacter-showcase=46 -Dcapture-frame=120` | Capture the bundled Captain mesh in the Creator on Metal for visual review. |
| `python3 tools/zig.py build mods` | Builds the example WebAssembly mod's scripts into `mods/`. |
| `python3 tools/zig.py build validate-mods [-- <dir>]` | Loads every mod under `mods/` (or one directory) as the game does and prints `file: key: reason` for each problem; non-zero exit on any rejection ([character content](mods.md#character-content)). |
| `python3 tools/zig.py build sounds` | Writes every synthesized sound to `zig-out/sounds/*.wav` for listening. |
| `python3 tools/zig.py build heightmap -- <in.pgm> <out.hwmh> [width depth elevation base]` | Imports a PGM heightmap to the runtime terrain format. |

For backend-specific development builds, pass `-Dmach_gpu_backend=metal`, `vulkan`, `opengl`, or `d3d12`. The default selects the platform backend. Each backend requires a supported target and its native platform libraries.

The fork carries compatibility paths for newer compilers. `HEAVYWATER_ZIG_CHANNEL=0.17` passes `build check`, `build assets`, `build test` and the Metal smoke run, and the Linux (Vulkan, OpenGL) and Windows (D3D12) targets cross-compile (`-Dtarget=x86_64-linux-gnu -Dmach_gpu_backend=vulkan`, `-Dtarget=x86_64-windows -Dmach_gpu_backend=d3d12`); the 0.18 snapshot passes on macOS and Linux Vulkan. The default stays on the proven Mach compiler until the adoption change lands; see the [Mach and Zig update process](plans/engine-update-process.md) and the candidate matrix in [engine alignment](plans/alignment.md#mach-tracking).

### Optimization modes

| Mode | Use it for |
| --- | --- |
| Debug (default) | Development builds; the slowest, with all safety checks. |
| `-Doptimize=ReleaseSafe` | Smoke runs and validation: fast, with safety checks (overflow and bounds panics). |
| `-Doptimize=ReleaseFast` | Performance benchmarks and selected captures; runtime safety checks are disabled, so this is not the automatic beta/release choice. |

Debug builds use far more stack, which hides size bugs from Release runs. Mach keeps every module's state on the main thread's 8 MB stack and copies it during startup, so a large inline array in `App`, `World` or `Renderer` overflows Debug first. Run at least one Debug launch after changing module state. The test "module states stay small" guards the sizes it can see.

## Running the game

```sh
python3 tools/zig.py build -Doptimize=ReleaseFast
./zig-out/bin/heavy-water
```

Run it from the repository root: the game reads and writes `saves/` (quicksave `saves/quicksave.json`, settings `saves/settings.json`, prefabs `saves/prefabs/`) and loads `mods/` relative to the working directory. An interactive build opens on the title screen.

### Game build options (`-D…`)

Options are compiled in, so changing one rebuilds.

| Option | Default | Meaning |
| --- | --- | --- |
| `-Dseed=N` | `0x4845415659` | World seed. |
| `-Daudio=false` | `true` | Run silent (skip the audio device). |
| `-Dsmoke-frames=N` | 0 | Scripted smoke run: exits after N rendered frames (see below). |
| `-Dbenchmark-frames=N` | 0 | Streaming benchmark route for N measured frames after 60 warm-up frames (use `tools/benchmark.py`). |
| `-Dbenchmark-canopy`, `-Dbenchmark-arbor=0..2` | off, 0 | Benchmark route aimed at an Arbor, close up to 1 km and back. |
| `-Dscale-objects=N` | 0 | Scale workload of N field objects. |
| `-Dpack-stress=N` | 0 | Write and stream a pack of N meshes during the benchmark. |
| `-Dshowcase=N` | 0 | Hold a fixed viewpoint or scene for review (table below). |
| `-Dcharacter-showcase=6..38` | 0 | Hairstyle review in the creator, in `Profile.HairStyle` order (6 = short, 30..38 = the anime cuts). |
| `-Dcharacter-showcase=40..43` | 0 | The `emberwear` example mod in the creator: 40 hair, face and ink cel style; 41 phoenix armor over a hardsuit; 42 sealed helmet; 43 second hairstyle on the exo rig. |
| `-Dcharacter-showcase=44..45` | 0 | Solar Mantle with the new crown braid and pilot helmet (44), or tempest sweep and recon helmet (45). |
| `-Dcharacter-showcase=1..5` | 0 | Character look in the creator, front view: scout, sentinel, unarmored masculine, unarmored feminine, Synthetic. |
| `-Dcharacter-view=0..5` | 0 | Character review camera around the avatar (with `-Dcharacter-showcase`): 0 front, 1 side, 2 back, 3 three-quarter, 4 face close-up, 5 face three-quarter close-up. The close-ups use the same frame as the creator's head zoom. |
| `-Dcharacter-pose=0..4` | 0 | Hold an arm pose for armor review: 1 aim, 2 overhead swing, 3 cast (arms raised), 4 guard. |
| `-Dcharacter-tweak=bits` | 0 | Review variations: 1 feminine, 2 height 0.9, 4 height 1.1, 8 open helmet, 16 sealed, 32 visor. |
| `-Dcharacter-face=N`, `-Dcharacter-hair-color=N` | 0 | Face style (1 = classic ... 6 = hero) and hair color (1-based); 0 keeps the default. |
| `-Dcel-style=0..3`, `-Dcel-debug=bits` | 0, 0 | Character look-dev: starting cel style (Heavy Water, Watercolor, Comic ink, Flat) and debug views (1 hide ink, 2 ramp bands, 4 face shadow mask). In any running build, F3 cycles the style, F8 toggles ink and F10 cycles normal, ramp bands and face mask (it logs the state). |
| `-Dcapture-frame=N` | 0 | Write rendered frame N to `zig-out/capture.bmp`, then exit. |
| `-Dcpu-skinning=true` | false | Skin characters on the CPU instead of the GPU palette pipeline (comparison and fallback). |
| `-Dhot-reload=true` | false | Watch model, blueprint and mod script sources and reload them live. |
| `-Dreload-smoke=true` | false | Reload test: edits an isolated crate fixture under `zig-out/reload-smoke` and checks the swap. |
| `-Dupload-budget-kib=N` | 384 | Terrain upload budget per frame (at least 322). |
| `-Dasset-upload-kib=N` | 4096 | Late catalog mesh upload budget per frame. |
| `-Dfield-upload-kib=N` | 2048 | Scale workload instance upload budget per frame. |

### Environment variables

| Variable | Effect |
| --- | --- |
| `MTL_DEBUG_LAYER=1` | Enables Metal API validation (macOS). Use it for every smoke run. |
| `MACH_FORCE_AUDIO_BACKEND=dummy` | Forces a Mach audio backend (for example a silent dummy). |
| `MACH_DEBUG_AUDIO=true` | Mach audio debugging output. |

## Tests

```sh
python3 tools/zig.py build test --summary all
```

- **Scope:** the latest recorded full run (2026-10-11) passed 419 tests. The suite is deterministic and headless, covering the engine, physics, generation, machines, saves, GUI layout, dialogue, audio synthesis and mixing, vehicles, flight, the Hive, weapons, melee, class specials, every Wildkin form and power, and the arena. Tests are registered in `src/tests.zig`; a new file's tests run only once it is imported there (or from a file that is).
- **Time:** expect about 3.5 minutes. The catalog allocation-failure test samples about 120 failure points across the catalog load; failing every allocation in turn is quadratic and took over 10 minutes. If the suite suddenly takes far longer, sample it before waiting: `sample <pid> 2` on macOS shows where the time goes. A slow suite once exposed expensive per-frame ray casts.
- **Release mode:** `-Doptimize=ReleaseSafe` runs the same suite optimized.

## Smoke runs

A smoke run plays a scripted session in a real window and exits. Always run it under Metal validation and in ReleaseSafe:

```sh
MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300
```

Over the frame budget it steps through ten stages, logging `Smoke …` lines:

- **Menus and panels:** pause, settings and a conversation, through the real input paths (`Smoke GUI`).
- **Maximum-progression test mode:** in Settings, turn on `MAX PROGRESSION TEST MODE` to unlock late-game kit/team progression for a session. It disables world and ranger saves; turn it off to restore the in-memory baseline before saving. The setting itself persists so the mode can also be enabled at startup.
- **Frontier:** fabricating a car and a blaster, flying the car, downing a drone (`Smoke frontier`).
- **Flight:** fabricating the Kestrel, lifting off, downing a wasp (`Smoke flight`).
- **Combat:** fabricating the saber and sniper rifle, a three-cut saber combo with P1's rig, a piercing sniper beam, an arc grenade and a kinetic slam (`Smoke combat`).
- **Caves:** walking P1 into the first cave with the real simulation step, and reporting the cave systems, background-built meshes and colliders (`Smoke caves`).
- **Heroes and arena:** meeting a city hero by aiming at them, playing as them through the Heroes menu, firing their three powers, and clearing and being paid for a Starbowl wave (`Smoke heroes`).
- **Character:** character creation.
- **Building:** crate carrying, machine building and wiring, prefab capture.
- **Saves:** in-memory save and restore. User save files are never touched.
- **Co-op:** four-player split screen with guests joining and leaving.
- **Vehicles:** the rover drive.
- **World:** sap flow, a bridge build, traffic and markets.

A good run ends with `Smoke complete: … frames` and no Metal validation messages. Check the `Smoke …` lines for the expected values (for example `drone downed=true`, `wasp downed=true`, `sniper pierced=true`).

The development reload smoke:

```sh
MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dreload-smoke=true -Dsmoke-frames=600 -Doptimize=ReleaseSafe
```

## Benchmarks

`tools/benchmark.py` builds ReleaseFast, flies a scripted route with the window visible, checks budgets, and writes a JSON report under `.tools/`.

| Command | Measures |
| --- | --- |
| `python3 tools/benchmark.py` | The streaming route (`.tools/streaming-benchmark.json`). |
| `python3 tools/benchmark.py --canopy [--arbor 1\|2]` | An Arbor up close, at 1 km and back: both LODs and the render CPU budget. |
| `python3 tools/benchmark.py --scale 10000\|100000\|1000000` | The scale workload (see [Scale Tests](scale.md)). |
| `python3 tools/benchmark.py --pack 64` | Streaming an 80 MiB pack of 64 meshes during measurement. |
| `python3 tools/benchmark.py --frontier` | Four-player ground and air combat: simulation stages, character preparation/skinning, render CPU, presentation intervals, and audio callbacks. |

Shared flags:
- `--frames N` (120–4096, default 600)
- `--seed N`
- `--upload-budget-kib`, `--asset-upload-kib`, `--field-upload-kib`
- `--timeout S`
- `--output PATH`

Reports cover:
- render CPU P50/P95/P99;
- the presentation interval;
- chunk residency, uploads and evictions;
- pool counts.

They do not measure GPU execution time; the pinned Mach path has no timestamp queries yet. Presentation intervals are not GPU timings. The frontier benchmark is available, with its latest recorded results and follow-up in [next steps](plans/next-steps.md) and [validation](validation.md).

## Showcases and captures

A showcase holds a fixed scene for art review; add `-Dcapture-frame=N` to save that frame and exit. Convert the BMP for viewing with `sips` (macOS):

```sh
python3 tools/zig.py build run -Doptimize=ReleaseFast -Dshowcase=34 -Dcapture-frame=120
sips -s format png zig-out/capture.bmp --out capture.png
```

| `-Dshowcase=` | Scene |
| --- | --- |
| 1–6 | Each district road by day |
| 7, 8 | City overview, by day and at dusk |
| 9 | Street level |
| 10–15 | Roads 1–6 at dusk |
| 64, 65 | Dusk close-ups of the two gem-set Arbor Rootway galleries |
| 66 | Early procedural orbital habitat cylinder beside Rand Corporation's Mother construction ark (art review only) |
| 67 | Wilds architecture lineup: cabin, barn, and cave sanctuary |
| 16, 17 | Armor lineup; hardsuit close-up (`-Dcharacter-showcase=30..33`: the four mecha armor sets over a hardsuit in the creator) |
| 18 | Title screen |
| 19 | Conversation with Maro |
| 20 | Suit upgrades |
| 21 | Market shop |
| 22 | Suit wardrobe |
| 23 | Character customization |
| 24, 25 | Pause menu; settings |
| 26 | HUD |
| 27 | Four-player split screen with a guest trading |
| 28 | Controls screen while rebinding |
| 29 | Garage with all three hover cars |
| 30 | A Hive nest under attack (drones, sentinel, troopers) |
| 31 | Fabricator |
| 32 | The Skimmer in flight |
| 33 | The Kestrel on its pad |
| 34 | A dogfight beside a Brood carrier |
| 35 | The carrier from above |
| 36 | A river and waterfall viewpoint |
| 37 | Saber combo on a trooper (third person) |
| 38 | Sniper rifle, first person |
| 39 | Machine gun firing, first person |
| 40 | A Synthetic channelling the lumen lance |
| 41 | A mountain range from the foothills (the far panorama) |
| 42 | A cave mouth on a mountainside |
| 43 | Inside a cave's first chamber |
| 44 | A cave's heart chamber and its Hive nest |
| 45 | Kestrel missile lock reticle, acquired on a ground drone |
| 54, 55 | Four-player setup; regional map and fast travel |
| 48–51 | The Wildkin, eight at a time, on the meadow |
| 52 | The Heroes screen |
| 53 | The Starbowl arena, wave 1, as Bolt Quill |
| 56 | The Heroes screen at 150% interface size, scrolled to BACK |
| 57 | The pause menu at 150% interface size, scrolled to its last item |
| 58, 59 | The four pets on the meadow: in their Hive collars; freed, in the ranger's colours |
| 60 | The bright, stepped Rootdeep temples and their luminous crowns |
| 62 | Giant redwoods and native flora under night lighting |
| 63 | Locomotion pose reel: sprint (frames 0–89), roll (90–179), dash (180–269), long jump (270–359), backflip (360–449), Superman flight (450 onward) |

Captures need a visible, unlocked screen. macOS stops presenting frames to a hidden window or a locked session, and the app then idles in its event loop without reaching the capture frame; check with `ioreg -n Root -d1 -a | grep -c CGSSessionScreenIsLocked`. Run one capture at a time: two app windows competing can stall both. macOS has no `timeout` command, so don't rely on one in scripts.

## Before a change is done

1. `python3 tools/zig.py build test --summary all`: every test passes.
2. `python3 tools/zig.py build check`: the app compiles, in Debug, the default.
3. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300`: a clean smoke with the expected `Smoke …` values.
4. For visual changes, capture the relevant showcase and look at it.
5. For changes to module state or startup, launch the Debug `zig-out/bin/heavy-water` once.
6. For performance-sensitive changes, run the matching benchmark.
7. Record results, including failures and what was not measured, in [validation](validation.md). Update the docs in the same change.

## Troubleshooting

- **A change works in tests or `build run` but not in the game you launch:** `build run` and `build test` run from the build cache and do not update `zig-out/bin/heavy-water`. Only `python3 tools/zig.py build` (with any `-Doptimize`) reinstalls it. Compare `ls -la zig-out/bin/heavy-water` with the date of your last change. For example, an Oct 5 install predated the Oct 6 controller change that put the energy gun on the right trigger and the saber on the right bumper.
- **Segmentation fault at startup in Mach `Modules.init` (Debug):** a stack overflow. A module state has grown too large; move big arrays to the heap (see Optimization modes).
- **A capture or smoke never finishes:** the screen is locked or the window is hidden, or a second instance is running. Check `ps aux | grep heavy-water`.
- **The test suite runs for many minutes:** sample the test process (`sample <pid> 2`) to find the hot spot before waiting longer.
- **`file_hash FileNotFound` during a build:** a source asset is missing its `.meta` sidecar. Run `python3 tools/zig.py build import`.
- **Audio device errors:** the game logs `Audio unavailable (…); running silent` and continues. Use `-Daudio=false` to skip the device.
- **`git push` fails with HTTP 400 on a large push:** raise the HTTP buffer with `git config http.postBuffer 524288000`.
