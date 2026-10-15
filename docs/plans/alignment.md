# Engine alignment and next-level plan

Phases 1–12 and the sky-city content pass each have a tested, runnable version. The next four phases close the gaps between Heavy Water and a production engine. In the order they will be built:

| Phase | Plan | Why first |
| --- | --- | --- |
| 13 | [Asset pipeline](asset-pipeline.md) | Stable asset identity, incremental import, async loading, and hot reload. Every later phase references assets by ID. |
| 14 | [Skeletal animation](skeletal-animation.md) | Real animated characters with bone attachments, replacing block avatars, and hitboxes for combat. |
| 15 | [Scene graph and JSON scenes](scenes.md) | Authored levels and prefabs as transform hierarchies, with asset references resolved through phase 13. |
| 16 | [UDP networking](networking.md) | Online play on the existing deterministic fixed step and the four-player model. |

## Review of external advice (2026-10-01)

Two outside summaries proposed "Unreal-like" upgrades for a Mach game. Each point was checked against this codebase.

| Advice | Status here | Decision |
| --- | --- | --- |
| Asset pipeline: GUID references, `.meta` sidecars, async loading | Partial. `asset-compiler` runs in the build graph and the build cache skips unchanged inputs. Typed generational handles exist, but no stable IDs, sidecars, runtime registry, or async or hot loading. | Adopt as phase 13 |
| Skeletal animation and attachments | Missing. The importer rejects skins, and avatars are block-built. | Adopt as phase 14 |
| Scene hierarchy and JSON serialization | Partial. Saves are complete JSON world documents, but there is no authored, hierarchical scene format. | Adopt as phase 15 |
| UDP networking and interpolation | Missing. There is local four-player co-op on a deterministic 60 Hz fixed step. | Adopt as phase 16 |
| C interop for physics (Jolt, Bullet, PhysX), audio (FMOD, Wwise), animation | Conflicts with the project rule. Physics (boxes, rigid bodies, triangle meshes, vehicles, characters) and scripting (WebAssembly) are already native Zig. | **Declined, native Zig kept** (decided 2026-10-01) |
| Zig 0.16 `std.Io` threaded explicitly | Done. File, network, and timing I/O take an `io` parameter. | No work |
| Unmanaged `ArrayList` (`.empty`, explicit allocator) | Done throughout. | No work |
| "Juicy Main" (`main(init: std.process.Init)`) | Done where we own `main` (`asset-compiler`). The game's entry point belongs to Mach. | Adopt for every new tool (importer, server) |
| Track Mach `main` on code.hexops.org | Now held as a project-owned fork in `vendor/mach`, based on `7ed0d504`. | See "Mach tracking" below |
| Don't build an editor or visual scripting yet | Agreed. JSON scenes, hot reload, and the showcase/capture tools stand in for an editor. | Agreed |
| Forward renderer with shadow mapping and instancing | Cel-shaded forward renderer with instancing, culling, and LOD exists; there are no shadows yet. | Lighting work continues alongside content |

A second review, of Unreal-style gameplay, rendering, tooling, physics, animation and networking features, is in [engine features](engine-features.md) (2026-10-14): adopt a small ability core, behavior trees, compiled logic graphs, cinematic tracks and ragdolls; reject virtualized geometry, global illumination and dynamic-library live coding.

## Mach tracking

### Zig 0.17 and 0.18 toolchain gate (2026-10-10)

The Mach package is now checked into `vendor/mach` from upstream base commit `7ed0d504a9569fd4ad840ecb10ead16b90a8926e`, with its upstream licenses retained. The root package resolves it as a local path dependency, and `vendor/mach/FORK.md` records provenance and patch goals. The first fork changes modernize argument forwarding, generated build metadata, and the iOS simulator runner while preserving the default Zig 0.16 build.

Compatibility checks are available through `tools/zig.py` using `HEAVYWATER_ZIG_CHANNEL=0.17` and `HEAVYWATER_ZIG_CHANNEL=0.18-dev`. The 0.18 channel is pinned to `0.18.0-dev.146+35accc06e` so the check is reproducible. The results table below is the current state.

**Zig 0.17 candidate matrix (2026-10-10, macOS aarch64, fork at base `7ed0d504` plus local patches).** The `@cImport` removal was the last blocker: each C header set is now a wrapper header in `vendor/mach/src/c/` translated by the build system (`addCImports` in `vendor/mach/build.zig`) into a `c_<name>` module, the same way on every channel. `mach_objc` is vendored at `vendor/mach-objc`, and the OpenGL backend's `c` namespace and the generated Vulkan loader were fixed along the way. Results:

| Gate | Default (0.16-dev) | 0.17.0 | 0.18.0-dev.146 |
| --- | --- | --- | --- |
| `build check`, macOS (Metal) | pass | pass | pass |
| Asset compilation | pass | pass | not run |
| Headless tests | 373/373 | 373/373 | not run |
| Metal-validated smoke (300 frames) | clean | clean | not run |
| Cross compile, Linux Vulkan | pass | pass | pass |
| Cross compile, Linux OpenGL | pass | pass | not run |
| Cross compile, Windows D3D12 | pass | pass | **fail**: Zig 0.18-dev's translate-C rejects its own bundled AVX512 headers while translating the Windows headers |
| Cross compile, Windows OpenGL | fail (apparently pre-existing; not rebuilt on the old tree to confirm) | fail (apparently pre-existing; not rebuilt on the old tree to confirm) | not run |
| Benchmarks | not run | not run | not run |

Cross compiles only prove that the code compiles; none of the Linux or Windows paths has run, and no Linux or Windows host was available. Windows OpenGL fails on `std.DynLib` being unsupported there and a mis-spelled WGL entry point, neither apparently caused by the migration (the old tree was not rebuilt to confirm). **Decision pending:** Zig 0.17 passes every gate that can run here, but the adoption change (root and Mach `build.zig.zon` metadata, the `tools/zig.py` default pin, docs) has not been made, and benchmarks and a Linux or Windows runtime check are outstanding. Earlier in the day the 0.17 check stopped at 134 errors (121 in `mach_objc`, 12 `@cImport` sites, 1 more reflection use).

The pinned Mach lacks capabilities measured or needed during development:

| Capability gap in `7ed0d504` (Metal) | Found during | Status and need |
| --- | --- | --- |
| `drawIndexedIndirect` | Phase 12 | Metal, Vulkan, OpenGL, and D3D12 implementations are now in `vendor/mach`: public 16/20-byte argument layouts, alignment/bounds/usage checks, and a `GpuMesh` helper. GPU-generated command buffers still depend on shader atomics. |
| Shader atomics (`atomicAdd` and others unimplemented in the WGSL compiler) | Phase 12 | GPU compaction, GPU particles |
| Timestamp queries (TODO) | Phase 12 | GPU timing in benchmark reports |
| `copyTextureToBuffer` (panics) | Sky city | Captures; worked around with a compute copy |
| Fixed 64 MiB staging pages that never shrink | Phase 12 | Memory budgets |

**Plan:** the project-owned fork is the engine work branch. Indirect draws now work on all four local backends. Implement shader atomics next, then timing, readback, and reclaimable staging pages. Before phase 14's GPU skinning, also compare against current Mach `main` on code.hexops.org with its nominated Zig, following the [update process](engine-update-process.md):

1. Check the gaps in the table above.
2. Run the full test suite, smoke, and benchmarks.
3. Record any API breakage.

Adopt upstream changes only if everything passes and preserve Heavy Water's engine patches. Draft focused maintainer proposals for features or compatibility fixes that belong in Mach or Zig; record links and remove corresponding local patches when upstream includes them. The ignored dependency cache remains off-limits; engine work belongs in `vendor/mach`. Phases 13–16 are designed to work on the current pin.

### Re-gate on main 1eac838 (2026-10-14)

Re-run after the nature, L-system forest and mesh-editor commits (macOS aarch64, Apple M3 Pro, Metal; the fork unchanged).

| Gate | Default pair | 0.17.0 |
| --- | --- | --- |
| `build check` | pass | pass |
| Headless tests | 435 of 439 | 435 of 439 |
| Metal-validated smoke (300 frames) | clean | not run |
| Nature benchmark (600 frames, ReleaseFast) | pass; CPU p99 2.976 ms; 12,248,988 submitted triangles | not run |
| Frontier benchmark (600 frames, ReleaseFast) | pass; simulation p99 2.815 ms, skinning p99 0.101 ms, render CPU p99 4.879 ms | not run |
| Cross compiles, Linux and Windows | not re-run | not re-run |

The same four tests fail on both channels, so they are not migration regressions: `asset.Catalog` deferred meshes (expects 5 pending, finds 6), `game.Save` round trip (a format 12 document, below the loader's current minimum of 13), `game.Creator` draft edit (`body_style` moved the field order) and `ui.Screens` layout (35 fields, a 25-row window). Causes and fixes are in the [technical review](next-steps.md#technical-review--2026-10-14). GPU time was unavailable at this re-gate; the later Metal command-buffer timing follow-up is below. Adoption still needs the full matrix: 0.17 smoke and benchmarks, the cross compiles, and the adoption change itself.

### Validation gate after suite and save fixes (2026-10-14)

The new `python3 tools/validation_gate.py` passed: default and Zig 0.17 `build check`, **440/440 headless tests on both**, and the default 300-frame Metal-validated smoke. The smoke and Linux/Windows cross-compiles were not run on Zig 0.17. The 2026-10-10 candidate matrix above remains the latest 0.17 asset-build, smoke and cross-compile evidence.

### Metal command-buffer GPU timing (2026-10-14)

Added completed-command-buffer GPU duration sampling to the vendored Metal queue using `GPUStartTime` and `GPUEndTime`, and exposed the latest sample count and duration to the benchmark. This reports whole-command-buffer time, not per-pass timings; non-Metal backends return no sample. Four 600-frame nature runs recorded 596–598 samples each; median run-level GPU p50/p95/p99 were **12.199/17.969/19.729 ms**, with p99 ranging **19.354–20.009 ms**. The nature route's p99 exceeds the 16.7 ms budget, so tree LOD remains the next rendering task. Default and 0.17 checks, 440/440 tests on each, default Metal smoke, and 0.17 Linux Vulkan/OpenGL plus Windows D3D12 cross-compiles passed; Linux and Windows were compile-only. See [validation](../validation.md#metal-command-buffer-gpu-timing--2026-10-14).

### Post-overhaul gate on main 1fe9e13 (2026-10-11)

The character overhaul (HeadSpec, armor, hair styles, CelStyle, CharacterContent, `skin_lit`/`skin_hull` WGSL) was first checked only on the default pair. Re-run on 0.17.0 and the cross targets:

| Gate | Result |
| --- | --- |
| 0.17 `build check` | Pass. |
| 0.17 `build test` | Initially did not compile: `Ranger.zig` test used `std.meta.fields` (removed in 0.17). Fixed with `enum_compat.fields`. After the fix 414 of 419 pass; the five failures are the same five as on the default pair (Ranger armor suit counts, Meta sidecar, Sandbox controller, Screens layout, Enemies nest), so they are not migration regressions. |
| Default pair `build test` | 414 of 419 pass; the same five failures. |
| 0.17 cross-compile `check` | Pass: Linux x86_64 Vulkan, Linux x86_64 OpenGL, Windows x86_64 D3D12 (compile-only; nothing run). |
| WGSL through Mach's compiler | All nine modules (scene, terrain, water, foliage, skinned, hull, outline, overlay, capture, spliced as `Renderer.zig` does) parse, analyze and generate MSL, HLSL and SPIR-V in a headless harness. SPIR-V found a real gap hidden by the Metal-only run: Mach's generator panicked on `exp` (used by `scene.wgsl` haze). Fixed in the fork (see FORK.md). GLSL (OpenGL) could not be exercised standalone: it needs runtime bindings and spirv-cross. No SPIR-V validator or Vulkan/D3D12/GL device was available, so non-Metal output is unvalidated. The debug allocator also reports a double-free diagnostic in Mach's SPIR-V `emitFn` (`toOwnedSlice`) for scene, terrain and water; not investigated. |
| Not run | Metal smoke on 0.17, 0.18 snapshot, Linux/Windows execution. |

## Principles kept

- **Native Zig:** engine systems are written in Zig, with no C or C++ libraries. The platform bridge (`gamepad.m`) is the only system-API exception.
- **Validated before anything changes:** all data is validated before it is applied. Loaders stage work and reject without mutating, as saves, mods, and bridges do today.
- **Runnable slices:** every phase arrives as a runnable slice with headless acceptance tests, smoke coverage with Metal validation, and benchmark evidence where performance is involved.
- **Docs move with code:** documentation changes in the same change as the code, and `roadmap.md` stays the single plan.

## Working alongside other agents

Several agents may work in this repository at once. Each phase lands as new modules first, and edits to shared files (`Sandbox.zig`, `App.zig`, `build.zig`, `tests.zig`, `roadmap.md`) are kept small and made only when no other agent is editing those files. When agents overlap, work happens in a separate git worktree and branch, and the user merges.
