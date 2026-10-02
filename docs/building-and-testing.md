# Building and testing

How to build, run, test, benchmark and capture Heavy Water, and what to check before a change is called done. Every command runs from the repository root.

## Requirements

- **Python 3.10+:** the only bootstrap prerequisite.
- **Zig toolchain:** `tools/zig.py` downloads the pinned Zig compiler (`0.16.0-dev.3142+5ccfeb926`), checksum-verified, into `.tools/`. It never touches the system Zig or `PATH`. Run every build through it: `python3 tools/zig.py <args>` (on Windows, `py tools/zig.py`).
- **Mach:** the engine library is pinned in `build.zig.zon` (Mach `7ed0d504`, with `core` and `sysaudio` enabled). Its packages live in `zig-pkg/`; the first build needs an internet connection to fetch them.
- **A GPU desktop to run the game:** the game is developed and validated on macOS with Metal on Apple silicon (M3 Pro). Tests are headless and need no window.

## Build steps

| Command | What it does |
| --- | --- |
| `python3 tools/zig.py build` | Builds and installs the game to `zig-out/bin/heavy-water` (Debug unless `-Doptimize` is given). |
| `python3 tools/zig.py build run` | Builds and runs the game from the build cache (not the installed copy). |
| `python3 tools/zig.py build check` | Compiles the application without running it. |
| `python3 tools/zig.py build test` | Runs every deterministic test, headless. Add `--summary all` to see the pass count. |
| `python3 tools/zig.py build assets` | Compiles source assets (glTF models, blueprints) into `zig-out/assets/`. |
| `python3 tools/zig.py build import` | Creates missing `.meta` sidecars (new GUIDs) and refreshes source hashes under `assets/source`. Run it after adding or changing a source asset. |
| `python3 tools/zig.py build mods` | Builds the example WebAssembly mod's scripts into `mods/`. |
| `python3 tools/zig.py build sounds` | Writes every synthesized sound to `zig-out/sounds/*.wav` for listening. |
| `python3 tools/zig.py build heightmap -- <in.pgm> <out.hwmh> [width depth elevation base]` | Imports a PGM heightmap to the runtime terrain format. |

### Optimization modes

| Mode | Use it for |
| --- | --- |
| Debug (default) | Development builds; the slowest, with all safety checks. |
| `-Doptimize=ReleaseSafe` | Smoke runs and validation: fast, with safety checks (overflow and bounds panics). |
| `-Doptimize=ReleaseFast` | Playing, benchmarks and captures. |

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
| `-Dcharacter-showcase=1..3` | 0 | Character look (scout, sentinel, unarmored) in the creator, front view. |
| `-Dcapture-frame=N` | 0 | Write rendered frame N to `zig-out/capture.bmp`, then exit. |
| `-Dhot-reload=true` | false | Watch model, blueprint and mod script sources and reload them live. |
| `-Dreload-smoke=true` | false | Reload test: edits an isolated crate fixture under `zig-out/reload-smoke` and checks the swap. |
| `-Dupload-budget-kib=N` | 320 | Terrain upload budget per frame (at least 278). |
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

- **Scope:** the suite (270 tests at the last count) is deterministic and headless. It covers the engine, physics, generation, machines, saves, GUI layout, dialogue, audio synthesis and mixing, vehicles, flight and the Hive. Tests are registered in `src/tests.zig`; a new file's tests run only once it is imported there (or from a file that is).
- **Time:** expect about 2 minutes, most of it the catalog allocation-failure test (it loads the whole catalog 500 times with injected failures). If the suite suddenly takes far longer, sample it before waiting: `sample <pid> 2` on macOS shows where the time goes. A slow suite once exposed expensive per-frame ray casts.
- **Release mode:** `-Doptimize=ReleaseSafe` runs the same suite optimized.

## Smoke runs

A smoke run plays a scripted session in a real window and exits. Always run it under Metal validation and in ReleaseSafe:

```sh
MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300
```

Over the frame budget it steps through ten stages, logging `Smoke …` lines:

- **Menus and panels:** pause, settings and a conversation, through the real input paths (`Smoke GUI`).
- **Frontier:** fabricating a car and a blaster, flying the car, downing a drone (`Smoke frontier`).
- **Flight:** fabricating the Kestrel, lifting off, downing a wasp (`Smoke flight`).
- **Character:** character creation.
- **Building:** crate carrying, machine building and wiring, prefab capture.
- **Saves:** in-memory save and restore. User save files are never touched.
- **Co-op:** four-player split screen with guests joining and leaving.
- **Vehicles:** the rover drive.
- **World:** sap flow, a bridge build, traffic and markets.

A good run ends with `Smoke complete: … frames` and no Metal validation messages. Check the `Smoke …` lines for the expected values (for example `drone downed=true`, `wasp downed=true`).

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

They do not measure GPU execution time; Mach has no timestamp queries yet. A frontier benchmark (wasps, carriers, troopers, four players) is planned; see [next steps](plans/next-steps.md).

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
| 16, 17 | Armor lineup; hardsuit close-up |
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

- **Segmentation fault at startup in Mach `Modules.init` (Debug):** a stack overflow. A module state has grown too large; move big arrays to the heap (see Optimization modes).
- **A capture or smoke never finishes:** the screen is locked or the window is hidden, or a second instance is running. Check `ps aux | grep heavy-water`.
- **The test suite runs for many minutes:** sample the test process (`sample <pid> 2`) to find the hot spot before waiting longer.
- **`file_hash FileNotFound` during a build:** a source asset is missing its `.meta` sidecar. Run `python3 tools/zig.py build import`.
- **Audio device errors:** the game logs `Audio unavailable (…); running silent` and continues. Use `-Daudio=false` to skip the device.
- **`git push` fails with HTTP 400 on a large push:** raise the HTTP buffer with `git config http.postBuffer 524288000`.
