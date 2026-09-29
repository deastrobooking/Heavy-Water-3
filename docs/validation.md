# Local validation

Host: Apple M3 Pro, macOS 26.5.1, Metal. Compiler and Mach revision are pinned in `build.zig.zon`.

- Debug unit suite: 10/10 passed. Covers fixed-step stall accounting, projection depth and camera orientation, seed hashing, shared chunk seams, same/different seeds, allocation-failure cleanup, frustum boundaries, and signal graph validation.
- ReleaseSafe unit suite and application compile pass.
- ReleaseFast application builds and installs.
- Initial Debug smoke completed 120 submitted frames with 1,000 objects and clean shutdown.
- Final ReleaseSafe smoke completed all three scripted stages and 16 frames with `MTL_DEBUG_LAYER=1`; Metal API validation reported no errors. The final camera view submitted 732 of 1,000 objects with CPU culling enabled, and shutdown returned exit code 0.

The HUD reports render-callback interval, submitted instance count, draw count, seed, and culling state. No GPU timing or representative throughput claim has been established. Screen capture was unavailable in this session, so pixel-level visual inspection and manual keyboard/mouse interaction remain unverified.

## Upstream programmatic resize issue

A ReleaseSafe smoke run with Metal API validation reproduced a hang after setting `Core.windows.width/height` from the application thread. Sampling showed the main thread in `macOS.tick → NSWindow.setFrame_display_animate → windowDidResize → handleResize → windows.lock`. `tick` already owns that non-reentrant lock. The renderer and application then wait on the same collection lock. This is in the pinned Mach source, not a GPU validation error.

The experiment was terminated and the programmatic size change removed from the app. No dependency cache files were patched. The smoke sequence now exercises culling, an empty view, and HUD toggling. Initial sizing works. Before exposing a resolution selector, update or patch Mach with a tested callback/locking fix. Native drag-resize is a separate path and still needs manual validation.

## Remaining platform checks

- Manual camera capture/release, focus loss, minimization, live resizing, and high-DPI transitions.
- Windows/D3D12 and Linux/Vulkan runtime tests.
- Whole-process memory instrumentation: Mach's stock entrypoint currently omits module-container teardown.
- Deterministic screenshot regression tests and CPU/GPU percentile benchmarks.
