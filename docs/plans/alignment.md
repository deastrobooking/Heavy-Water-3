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
| Track Mach `main` on code.hexops.org | Pinned to `7ed0d504` with its nominated Zig, upgraded only as a tested pair. | See "Mach tracking" below |
| Don't build an editor or visual scripting yet | Agreed. JSON scenes, hot reload, and the showcase/capture tools stand in for an editor. | Agreed |
| Forward renderer with shadow mapping and instancing | Cel-shaded forward renderer with instancing, culling, and LOD exists; there are no shadows yet. | Lighting work continues alongside content |

## Mach tracking

The pinned Mach lacks capabilities measured or needed during development:

| Missing in `7ed0d504` (Metal) | Found during | Needed for |
| --- | --- | --- |
| `drawIndexedIndirect` (panics "unimplemented") | Phase 12 | GPU-driven culling and submission |
| Shader atomics (`atomicAdd` and others unimplemented in the WGSL compiler) | Phase 12 | GPU compaction, GPU particles |
| Timestamp queries (TODO) | Phase 12 | GPU timing in benchmark reports |
| `copyTextureToBuffer` (panics) | Sky city | Captures; worked around with a compute copy |
| Fixed 64 MiB staging pages that never shrink | Phase 12 | Memory budgets |

**Plan:** before phase 14's GPU skinning, evaluate the current Mach `main` on code.hexops.org with its nominated Zig, on a branch:

1. Check the gaps in the table above.
2. Run the full test suite, smoke, and benchmarks.
3. Record any API breakage.

Adopt the upgrade only if everything passes. Otherwise stay pinned and keep the workarounds. Patching the dependency cache in place remains off-limits; a fork would be a deliberate decision. Phases 13–16 are designed to work on the current pin.

## Principles kept

- **Native Zig:** engine systems are written in Zig, with no C or C++ libraries. The platform bridge (`gamepad.m`) is the only system-API exception.
- **Validated before anything changes:** all data is validated before it is applied. Loaders stage work and reject without mutating, as saves, mods, and bridges do today.
- **Runnable slices:** every phase arrives as a runnable slice with headless acceptance tests, smoke coverage with Metal validation, and benchmark evidence where performance is involved.
- **Docs move with code:** documentation changes in the same change as the code, and `roadmap.md` stays the single plan.

## Working alongside other agents

Several agents may work in this repository at once. Each phase lands as new modules first, and edits to shared files (`Sandbox.zig`, `App.zig`, `build.zig`, `tests.zig`, `roadmap.md`) are kept small and made only when no other agent is editing those files. When agents overlap, work happens in a separate git worktree and branch, and the user merges.
