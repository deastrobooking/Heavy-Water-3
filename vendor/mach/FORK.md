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
- **Metal diagnostics (`sysgpu/metal.zig`, `sysgpu/queue.zig`):** expose completed command-buffer GPU duration through the queue for benchmark sampling, using `MTLCommandBuffer.GPUStartTime` and `GPUEndTime`. This reports whole-command-buffer duration; per-pass timestamp queries remain a separate gap. Validation on 2026-10-14: four fixed-seed nature benchmarks each collected 596–598 samples; the full gate passed 440/440 tests on Zig 0.16 and 0.17 plus the Metal smoke; Zig 0.17 Linux Vulkan/OpenGL and Windows D3D12 cross-compiles passed. Drop when upstream Mach exposes a comparable completed-command-buffer GPU duration API and the benchmark uses it.
- Shader (SPIR-V code generator): emit `exp`, `exp2`, `log` and `log2` as GLSL.std.450 instructions (27, 29, 28, 30). Upstream panics with "TODO: implement Unary Intrinsic exp", so `scene.wgsl` (height haze uses `exp`) could not build on the Vulkan backend. Validated 2026-10-11: every Heavy Water WGSL module (scene, terrain, water, foliage, skinned, hull, outline, overlay, capture) now generates SPIR-V, HLSL and MSL in a headless harness; no SPIR-V validator or Vulkan device was available, so the output is unvalidated. Drop when upstream implements these intrinsics.
- **Metal depth-only render passes (`sysgpu/metal.zig`):** `RenderPassEncoder.init` sliced `desc.color_attachments.?` before looping, so a pass with no color attachments (a shadow map) panicked on null. It now loops over an empty slice. The Vulkan, OpenGL and D3D12 encoders already unwrap inside a zero-iteration loop and were not changed. Validated 2026-10-23 by Heavy Water's sun-shadow pass under `MTL_DEBUG_LAYER=1` (exit 0, no validation messages; showcases 73, 30 and 113 captured), with 644/644 headless tests and the 0.17 `build check` passing. Not compiled for other targets, since the change is in the Metal-only file. Drop when upstream handles a null color attachment list in the Metal encoder.

The Zig 0.16 build passes. The 2026-10-14 gate passes `build check` and all 440 headless tests on Zig 0.16 and 0.17; default Metal smoke also passes. Zig 0.17 asset compilation, smoke and cross-compiles passed in the 2026-10-10 candidate matrix and were not rerun on 2026-10-14; see [engine alignment](../../docs/plans/alignment.md#mach-tracking). The 0.18 development snapshot passes on macOS and Linux Vulkan but fails to translate the Windows headers. The default pin has not moved: adoption is a separate change. Do not describe the fork as adopted on 0.17 until that lands.

## Vendored dependencies

- **`mach_objc`** is vendored at `vendor/mach-objc`, referenced by path from this package's `build.zig.zon`, so it can be ported to Zig 0.17 in the repository instead of in the ignored package cache. Upstream base: <https://pkg.hexops.org/pkg/hexops/mach-objc/7713665ce8c6797c117c57b85522b892381c0f18.tar.gz> (package hash `mach_objc-0.0.0-pF1e0q9ADQDM7s0Vg40-m_hjLWZC3dju9OsrcWUGQ19G`). Upstream licenses are retained. Local changes: `src/meta_compat.zig` (reflection over function parameters, struct fields and declarations that works on 0.16 and 0.17) used by `objc.zig` and `system.zig`. Validation: default-pair build, tests and Metal smoke pass; the 0.17 build passes. These patches are candidates to send upstream.

## Zig 0.17 patches in the engine

Each is small and independent, in the order they would be sent upstream.
- **`@cImport` replaced by build-system translate-C** (`build.zig` `addCImports` and `cImport`, wrapper headers in `src/c/`). Each former `@cImport` is now a `c_<name>` module (FreeType, kb-text-shape, Opus, X11, Wayland, ALSA, JACK, PulseAudio, PipeWire, D3D12, OpenGL on Windows and Linux). Include paths mirror what the old module got from its library dependencies, the Windows GNU workarounds moved into `cImport`, and the X11 header package also feeds Wayland (it carries `xkbcommon`). This works on 0.16 and 0.17, so no version-gated source files are needed. The dead spirv-cross and spirv-tools helpers in `sysgpu/shader/CodeGen.zig`, which no dependency provided headers for, were removed.
- **Reflection** goes through `src/meta_compat.zig` (struct, union and enum fields; `is_debug` for the renamed optimize modes), including the Linux dynamic-library loaders in X11, Wayland, PipeWire, JACK, PulseAudio and ALSA and `Audio.zig`.
- **Vector storage:** `math/vec.zig` stores `Vec2` as a regular Zig struct, like `Vec3`, because Zig 0.17 rejects compiler vectors inside `extern struct`. `Vec2.gpu()` continues to convert to the explicit GPU ABI type. Required when enabling Mach's bundled Fira Sans renderer; validated with the default compiler and 0.17 `build check`.
- **Standard library renames:** `Allocator.dupeZ` to `dupeSentinel(.., 0)`, `fmt.bufPrintZ` to `bufPrintSentinel(.., 0)`, and the managed `std.AutoArrayHashMap` to the unmanaged form in `sysgpu/vulkan.zig`. All of these work on both compilers.
- **OpenGL backend fix (separate from compatibility):** `sysgpu/opengl.zig` imported `opengl/c.zig` but used `c.GLenum` and friends, which never existed because the file exports the C namespace as `c`. It now imports `.c`. The Linux OpenGL backend compiles on both channels with this. Windows OpenGL still fails (`std.DynLib` is unsupported there, and a WGL entry point is mis-spelled).

## Local validation

Run Heavy Water builds from the repository root through `tools/zig.py`. The root package resolves `mach` from this directory; do not patch the ignored `zig-pkg/` cache.
