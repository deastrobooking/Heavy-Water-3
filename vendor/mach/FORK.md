# Heavy Water Mach fork

This directory is the project-owned Mach engine source used by Heavy Water. It is based on upstream Mach commit `7ed0d504a9569fd4ad840ecb10ead16b90a8926e` (Mach 0.5.0), previously fetched as the pinned package dependency.

The source is checked into this repository so engine changes are reviewable, reproducible, and tested with the game. Preserve the upstream MIT and Apache 2.0 license files. Keep changes focused on engine support Heavy Water uses, and record each custom change here with the affected subsystem and validation evidence.

## Fork goals

- Migrate the engine and its build scripts to Zig 0.17, then track Zig 0.18 development as it stabilizes.
- Keep the game-facing Mach API small and stable where practical.
- Add the measured GPU and memory capabilities listed in [engine alignment](../../docs/plans/alignment.md#mach-tracking): indirect draws, shader atomics, timestamp queries, texture readback, and reclaimable staging memory.
- Validate each engine change with the Heavy Water build, headless tests, and macOS Metal smoke runs.

## Upstream provenance

- Upstream project: <https://code.hexops.org/hexops/mach>
- Base commit: `7ed0d504a9569fd4ad840ecb10ead16b90a8926e`
- Upstream package version: 0.5.0
- Upstream licenses: `LICENSE`, `LICENSE-APACHE`, and `LICENSE-MIT`

## Heavy Water changes

- Package the fork as `0.5.0-heavywater.1` and resolve it from the repository's `vendor/mach` path.
- Replace the removed custom build-info step with the standard generated-file API.
- Forward `zig build run -- ...` arguments through the public passthrough API on Zig 0.17 while retaining the existing route for the pinned compiler.
- Use a checked-in iOS simulator helper instead of a custom build step removed in Zig 0.17.
- Keep the 0.17 and recorded 0.18 compiler pins available for build compatibility work.
- Add Metal render-pass indirect draw calls, argument records, bounds/usage validation, and a Heavy Water `GpuMesh.drawIndexedIndirect` helper. This is the first GPU capability slice; Vulkan, OpenGL, and D3D12 dispatch still report it as unsupported.

The Zig 0.16 build currently passes. The Zig 0.17/0.18 port is in progress: the build graph configures, asset tools compile, and the engine/game compile reaches Mach's module metadata. The remaining blockers are Mach's `@cImport` usage across platform, shader, audio and font modules, and old `Type.StructField` reflection in Mach's module system. Zig 0.17/0.18 also required updates for array repeats, static bitsets, and 3D vector layout. Do not describe the fork as compatible with either preview until `build check` passes.

## Local validation

Run Heavy Water builds from the repository root through `tools/zig.py`. The root package resolves `mach` from this directory; do not patch the ignored `zig-pkg/` cache.
