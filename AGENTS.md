# Heavy Water: agent guide

For Codex, Claude Code and any other coding agent. Read this first, then the doc it points you to. The docs are the source of truth; this file only says how to work and what to build first.

## What this is

A native Zig game on a project-owned fork of Mach (`vendor/mach`; Metal on macOS), for up to four local players. Procedural canopy-city world, a cel-shaded look, engine systems written in Zig. Pillars and tone: [docs/world.md](docs/world.md). Plan: [docs/roadmap.md](docs/roadmap.md) (the single plan). What exists: [docs/architecture.md](docs/architecture.md). Evidence and known gaps: [docs/validation.md](docs/validation.md).

## MVP guidance

Build the smallest playable slice that proves the game, then deepen it. Do not widen scope.

**The MVP loop** (the user's direction; edit this section if it changes):
1. **Wilds are hack-and-slash.** Fast, readable fights against Hive waves, nests and cave dungeons, with loot for each player. Pets and Wildkin heroes fight alongside.
2. **Sanctuary cities are exploration.** Find upgrades, trade, talk, and uncover the Hive's alliances with scientists and governments.
3. **Freeing a city needs both:** break the Hive outside, expose its allies inside. Earth's cities first; the Colonies later.
4. **Four players, each their own progress.** Every player keeps their own character, gear, wallet and pets (`game/Kit.zig`). The team shares only the world and story (`game/Progress.zig`). Any player can play as a teammate's saved ranger or any Wildkin hero.

**Rules for scope:**
- Prefer finishing one city's liberation loop end to end over adding a second city, planet or mode.
- A feature is done when a player can use it in the real game and a test or smoke stage proves it, not when the module compiles.
- Frame new content by where it lives: wilds content is combat, loot and per-player rewards; city content is exploration, upgrades and the conspiracy story.
- Never put a personal reward in a shared wallet or shared progress. If it belongs to one player, it goes in their `Kit`.
- Defer: networking, planets beyond Earth, mod ecosystem growth, new engine phases, and anything the loop above does not need. Roadmap phases 14–16 (skeletal animation, scene graph, UDP) are not MVP blockers. The Zig 0.17 migration below is a separate platform track: it never blocks MVP work and MVP work never blocks it, so keep the default pair green and keep both tracks in small, separate changes.
- Say what you did not verify. Report test failures with their output; do not hide skipped steps.

## Zig-first platform and the 0.17 migration

Heavy Water is Zig-first: engine systems are Zig, the build is Zig, and the platform is the Mach fork. The goal is to move to new Zig releases quickly, and to fix Mach in the fork and contribute the fixes upstream, without ever leaving the game unbuildable. The full process is [docs/plans/engine-update-process.md](docs/plans/engine-update-process.md); the fork's patch inventory is [vendor/mach/FORK.md](vendor/mach/FORK.md); measured gaps and dated results are in [docs/plans/alignment.md](docs/plans/alignment.md#mach-tracking).

**Toolchain channels** (`tools/zig.py` holds every pin and checksum):

| Channel | Zig | Status |
| --- | --- | --- |
| default (`mach`) | `0.16.0-dev.3142+5ccfeb926`, the compiler Mach nominates | The shipping pair and required validation target. The 2026-10-14 gate passes `build check`, all 440 headless tests, and the Metal smoke. |
| `HEAVYWATER_ZIG_CHANNEL=0.17` | `0.17.0` stable | Migration target. Opt-in. The 2026-10-14 gate passes `build check` and all 440 headless tests; Linux Vulkan/OpenGL and Windows D3D12 cross-compiles also pass. Asset build and Metal smoke passed in the 2026-10-10 candidate matrix; 0.17 smoke was not rerun on 2026-10-14. Adoption pending. |
| `HEAVYWATER_ZIG_CHANNEL=0.18-dev` | `0.18.0-dev.146+35accc06e` snapshot | Early warning. Opt-in. Passes on macOS and Linux Vulkan; Windows targets fail in Zig's own translate-C. |

**Where 0.17 stands** (candidate matrix, 2026-10-10; dated re-gates in [alignment](docs/plans/alignment.md#mach-tracking)): `build check`, all 440 headless tests, and Linux Vulkan/OpenGL plus Windows D3D12 cross-compiles pass as of 2026-10-14. `build assets` and the Metal smoke passed in the 2026-10-10 matrix; the 2026-10-14 gate did not rerun the 0.17 smoke. Not done: benchmarks, any run on Linux or Windows (they are compile-only here), and the adoption change itself (Mach and root `build.zig.zon` metadata, the `tools/zig.py` default pin, docs, in one change). Windows OpenGL fails for reasons unrelated to the migration.
- **C headers are translated by the build system.** Zig 0.17 removed `@cImport`, and the compiler rejects the builtin even in a dead branch. Each header set is a wrapper header in `vendor/mach/src/c/` plus a translate-C step in `vendor/mach/build.zig` (`addCImports`), exposed as a `c_<name>` module. Add new C bindings the same way; never write `@cImport`.
- **Dependencies live in the repository.** `mach_objc` is vendored at `vendor/mach-objc` and `vulkan-zig` at `vendor/vulkan-zig`, each with provenance in its notes. Never edit the ignored `zig-pkg/`.
- **Cross-compile checks catch what macOS cannot see.** Linux and Windows code is not analyzed on a macOS build, so reflection and std changes there only show up with `-Dtarget=...`. The commands are in [docs/building-and-testing.md](docs/building-and-testing.md).

**Rules that keep the default pair working until 0.17 is adopted:**
- **Never move the default pair piecemeal.** Adopt a new pair only when the game, tools and backends build together, and change `build.zig.zon` (Mach metadata and `minimum_zig_version`), the `tools/zig.py` pin and the docs in one change. Do not raise `minimum_zig_version` speculatively.
- **Gate on version, shim in one place.** Where Zig's API differs between 0.16 and 0.17, branch on `builtin.zig_version.minor >= 17` and put the difference in a shim, not at every call site: `src/compat/` for the game (`meta.Int` to `@Int`, enum reflection) and `vendor/mach/src/meta_compat.zig` for Mach (struct, union and enum field reflection, `is_debug`) and `vendor/mach-objc/src/meta_compat.zig` for the Objective-C bindings (function parameters, struct fields, declarations). Known differences already handled: `std.meta.Int` and `@Int`, reflection through `field_names`, `field_types` and `field_values` instead of `.fields`, `StaticBitSet` `.initEmpty()` and `.empty`, array-repeat syntax, and 3D vector layout. Reuse a shim before writing a new one.
- **Write new code the 0.17 way where both compilers allow it.** No new `@cImport`. No direct `@typeInfo(...).fields` loops in game code; go through the shim. Prefer the standard generated-file build API over custom build steps. When a std API changed, read the std source for both channels (`.tools/zig-aarch64-macos-0.16.0-dev.3142+5ccfeb926/lib/std` and `.tools/zig-aarch64-macos-0.17.0/lib/std`).
- **After touching reflection, bitsets, `@Int` or build scripts**, run both `python3 tools/zig.py build check` (must pass) and the 0.17 check (must keep passing), and cross-compile Linux and Windows if you touched platform code. Changes under `vendor/mach-objc` also need the default-pair tests and the Metal smoke run, since they run in the macOS window code.
- **Say exactly which gates ran.** The adoption bar is the full matrix: `build check`, asset compilation, headless tests, the Metal smoke run, the cross-compile targets and benchmarks. Report what passed, what was compile-only and what was not run; do not call a channel "compatible" or "adopted" before the adoption change lands.

**Working on the Mach fork** (`vendor/mach`):
- The fork is the engine work branch. Engine changes go there, never in `zig-pkg/`. Keep upstream's license files, and record every local patch in `FORK.md` with its subsystem, validation evidence and the condition for dropping it.
- **Write patches to be upstreamed:** one concern per patch, minimal and focused, validated on every backend you can build (Metal runs here; Vulkan, OpenGL and D3D12 are compile-checked only, and say so). Do not mix a compatibility fix with a feature.
- **Importing upstream:** follow the process doc: record the exact upstream revision, fetch into an isolated checkout, map each local patch onto the candidate, never overwrite the fork wholesale.
- **Proposing upstream:** reduce to a small reproduction first, check current upstream, and keep the issue or pull-request draft in the repository (outline in the process doc). Opening an external issue or pull request is outward-facing: do it only when the user asks, then link it in `FORK.md`.
- **Known engine gaps** the game needs: shader atomics, timestamp queries, texture-to-buffer readback, reclaimable staging pages (indirect draws are done). Metal command-buffer GPU durations are now exposed for benchmarks; per-pass timestamp queries remain an engine gap. These are the first upstream candidates.
- **Mach's WGSL compiler** and Mach's single-threaded module state are the sharpest edges; see the rendering rules below.

**Several agents may work at once** ([alignment](docs/plans/alignment.md#working-alongside-other-agents)): keep edits to shared files (`Sandbox.zig`, `App.zig`, `build.zig`, `tests.zig`, `roadmap.md`) small, and use a separate git worktree and branch when work overlaps. Do not revert changes you did not make; the working tree often holds another agent's or the user's uncommitted work, so stage only your own files.

## Tooling

Run everything from the repository root through the pinned launcher. Never use a system `zig`.

```sh
python3 tools/zig.py build check                        # compile the app (Debug)
python3 tools/zig.py build test --summary all           # headless suite, about 3.5 minutes
MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300   # scripted smoke
python3 tools/zig.py build -Doptimize=ReleaseFast       # reinstall zig-out/bin/heavy-water
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check     # migration gate (passes)
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check -Dtarget=x86_64-linux-gnu -Dmach_gpu_backend=vulkan   # Linux compile check; also x86_64-windows with d3d12
```

- `build run` and `build test` use the build cache. Only `build` (any `-Doptimize`) updates the installed `zig-out/bin/heavy-water`, so reinstall it before handing the game to the user.
- Captures and benchmarks need a visible, unlocked screen (see [docs/building-and-testing.md](docs/building-and-testing.md)). If one stalls, check `ioreg -n Root -d1 -a | grep -c CGSSessionScreenIsLocked`.
- The full checklist for "done" is in [docs/building-and-testing.md](docs/building-and-testing.md#before-a-change-is-done). New files' tests only run once imported from `src/tests.zig`.

## Zig rules for this repository

The default compiler is `0.16.0-dev.3142+5ccfeb926`, pinned by Mach, and the code is being moved to 0.17. Models often write older or newer Zig than either. Do not trust memory for the standard library:

- **Read the real std source before using an API.** It is under `.tools/zig-*/lib/std/`. Match what you read, not what you remember (I/O, formatting, `ArrayList`, `std.Io` and reflection have all changed). If an API differs between the two channels, use the shim rules above.
- **Never hide allocations.** Take an explicit `std.mem.Allocator`. Per-frame and per-request work uses fixed-capacity storage or an arena. The frame path must not allocate engine arrays.
- **Errors:** error unions with `defer` and `errdefer`; no sentinel values for failure. A rejected load or purchase must leave state unchanged (validate first, then apply).
- **`comptime`** for configuration and tables; no macros, no C-style tricks.
- **Native Zig only.** Engine systems (physics, navigation, assets, audio) are written in Zig. Do not bind Jolt, Recast or other C/C++ libraries, and do not add C interop tiers. The Objective-C gamepad bridge in `src/platform/` is the existing exception, and the platform libraries Mach already links are Mach's.
- **Data layout:** use struct-of-arrays (`MultiArrayList`) when iterating many entities by one or two fields in a hot loop. Otherwise keep the existing fixed arrays; do not rewrite working code for layout alone.
- **Module state is small.** Mach copies module state on the main thread's 8 MB stack. A large inline array in `App`, `World` or `Renderer` overflows in Debug first. Put big arrays on the heap and run one Debug launch after changing module state.
- **Match the surrounding code:** naming, comment density and idiom. Comments say why, not what.

## Rendering rules

- WGSL goes through Mach's compiler, which lacks `cross`, `pow` and `reflect` (the shared prelude in `src/render/scene.wgsl` defines substitutes), cannot negate swizzles, allows one entry point per stage per module, and reserves `patch`. Build modules by splicing onto the shared prelude, as `Renderer.zig` does.
- Run every rendering change under `MTL_DEBUG_LAYER=1` and look at a capture. A clean compile proves nothing about how it looks.

## Working agreements

- **Docs move with code.** Update every affected doc in the same change; `docs/roadmap.md` is the single plan and `docs/validation.md` records results, failures and what was not measured.
- **Commit only when asked.** The user commits or asks for a commit. When asked, commit everything that belongs to the change, with a message that explains why.
- **Ask before large creative decisions.** The creative bible is [docs/world.md](docs/world.md). Small defaults are yours to pick and mention.
- **Saves are contracts.** Changing what a save means bumps `Save.format_version`, migrates the previous format, and gets a round-trip test.
- **Tests must be able to fail.** For a bug fix, add a regression test and confirm it fails without the fix.
