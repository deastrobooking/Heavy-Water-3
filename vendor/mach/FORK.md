# Heavy Water Mach fork

This directory is the project-owned Mach engine source used by Heavy Water. It is based on upstream Mach commit `7ed0d504a9569fd4ad840ecb10ead16b90a8926e` (Mach 0.5.0), previously fetched as the pinned package dependency.

The source is checked into this repository so engine changes are reviewable, reproducible, and tested with the game. Preserve the upstream MIT and Apache 2.0 license files. Keep changes focused on engine support Heavy Water uses, and record each custom change here with the affected subsystem and validation evidence.

Use the project's [Mach and Zig update process](../../docs/plans/engine-update-process.md) when importing an upstream revision or changing compiler pins. Keep candidate checkouts and downloaded toolchains under ignored `.tools/`; update this fork only after mapping its local patches onto the candidate source.

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
- Add render-pass indirect draw calls, shared argument records, bounds/usage validation, and a Heavy Water `GpuMesh.drawIndexedIndirect` helper. Metal, Vulkan, OpenGL, and D3D12 paths are implemented; D3D12 creates and owns its draw command signatures on each device.
- Validate with the root game build for Metal and x86_64 Windows/D3D12; Mach core backend builds for Vulkan and OpenGL also pass on the pinned compiler. Runtime GPU smoke testing still needs the corresponding host platforms.

The Zig 0.16 build passes. The Zig 0.17.0 build also passes `build check`, asset compilation, the 373 headless tests and the Metal-validated smoke run, and cross-compiles for Linux (Vulkan, OpenGL) and Windows (D3D12); see the candidate matrix in [engine alignment](../../docs/plans/alignment.md#mach-tracking). The 0.18 development snapshot passes on macOS and Linux Vulkan but fails to translate the Windows headers. The default pin has not moved: adoption is a separate change. Do not describe the fork as adopted on 0.17 until that lands.

## Vendored dependencies

- **`mach_objc`** is vendored at `vendor/mach-objc`, referenced by path from this package's `build.zig.zon`, so it can be ported to Zig 0.17 in the repository instead of in the ignored package cache. Upstream base: <https://pkg.hexops.org/pkg/hexops/mach-objc/7713665ce8c6797c117c57b85522b892381c0f18.tar.gz> (package hash `mach_objc-0.0.0-pF1e0q9ADQDM7s0Vg40-m_hjLWZC3dju9OsrcWUGQ19G`). Upstream licenses are retained. Local changes: `src/meta_compat.zig` (reflection over function parameters, struct fields and declarations that works on 0.16 and 0.17) used by `objc.zig` and `system.zig`. Validation: default-pair build, tests and Metal smoke pass; the 0.17 build passes. These patches are candidates to send upstream.

## Zig 0.17 patches in the engine

Each is small and independent, in the order they would be sent upstream.
- **`@cImport` replaced by build-system translate-C** (`build.zig` `addCImports` and `cImport`, wrapper headers in `src/c/`). Each former `@cImport` is now a `c_<name>` module (FreeType, kb-text-shape, Opus, X11, Wayland, ALSA, JACK, PulseAudio, PipeWire, D3D12, OpenGL on Windows and Linux). Include paths mirror what the old module got from its library dependencies, the Windows GNU workarounds moved into `cImport`, and the X11 header package also feeds Wayland (it carries `xkbcommon`). This works on 0.16 and 0.17, so no version-gated source files are needed. The dead spirv-cross and spirv-tools helpers in `sysgpu/shader/CodeGen.zig`, which no dependency provided headers for, were removed.
- **Reflection** goes through `src/meta_compat.zig` (struct, union and enum fields; `is_debug` for the renamed optimize modes), including the Linux dynamic-library loaders in X11, Wayland, PipeWire, JACK, PulseAudio and ALSA and `Audio.zig`.
- **Standard library renames:** `Allocator.dupeZ` to `dupeSentinel(.., 0)`, `fmt.bufPrintZ` to `bufPrintSentinel(.., 0)`, and the managed `std.AutoArrayHashMap` to the unmanaged form in `sysgpu/vulkan.zig`. All of these work on both compilers.
- **OpenGL backend fix (separate from compatibility):** `sysgpu/opengl.zig` imported `opengl/c.zig` but used `c.GLenum` and friends, which never existed because the file exports the C namespace as `c`. It now imports `.c`. The Linux OpenGL backend compiles on both channels with this. Windows OpenGL still fails (`std.DynLib` is unsupported there, and a WGL entry point is mis-spelled).

## Local validation

Run Heavy Water builds from the repository root through `tools/zig.py`. The root package resolves `mach` from this directory; do not patch the ignored `zig-pkg/` cache.
