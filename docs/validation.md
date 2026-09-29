# Local validation

Host: Apple M3 Pro, macOS 26.5.1, Metal. Compiler and Mach revision are pinned in `build.zig.zon`.

Bootstrap (phase 1):

- Debug unit suite: 10/10 passed. Covers fixed-step stall accounting, projection depth and camera orientation, seed hashing, shared chunk seams, same/different seeds, allocation-failure cleanup, frustum boundaries, and signal graph validation.
- ReleaseSafe unit suite and application compile pass.
- ReleaseFast application builds and installs.
- Initial Debug smoke completed 120 submitted frames with 1,000 objects and clean shutdown.
- Final ReleaseSafe smoke completed all three scripted stages and 16 frames with `MTL_DEBUG_LAYER=1`; Metal API validation reported no errors. The final camera view submitted 732 of 1,000 objects with CPU culling enabled, and shutdown returned exit code 0.

The HUD reports render-callback interval, submitted instance count, draw count, seed, and culling state. No GPU timing or representative throughput claim has been established. Screen capture was unavailable in this session, so pixel-level visual inspection and manual keyboard/mouse interaction remain unverified.

## Procedural streaming (phase 2)

- Debug and ReleaseSafe unit suites: 20/20 passed. New coverage: chunk key boundaries (negative, NaN, out of range), planner bounds and center priority, handle invalidation on recycle, canceled generation, in-flight slots held until the worker acknowledges cancellation, unload/regenerate producing an identical terrain and scatter fingerprint with no new pool allocations, allocation-failure cleanup, biome normalization, scatter stability and slope limits, percentile ranks, and the fly-through route.
- ReleaseSafe 120-frame smoke with `MTL_DEBUG_LAYER=1`: no Metal validation errors, clean exit.
- ReleaseFast benchmark, 600 measured frames, default budget: interval P50/P95/P99 20.8/21.0/21.1 ms (presentation-paced), render-thread CPU P99 about 1.1 ms, 40 chunk crossings, 225 uploads, 200 evictions, peak upload 278 KiB of a 320 KiB budget, peak 25 resident chunks, 0 frames with the active 3×3 ring missing, pool allocations fixed at 2 CPU and 50 GPU buffers.
- One benchmark run reported an interval P95 of about 1 s with normal CPU times, which is macOS throttling an occluded window. The benchmark now fails such runs (`presentation_unthrottled`).

Interval timing is presentation pacing, not GPU execution time. Visual seam inspection at chunk borders is still manual.

## Interaction and assets (phase 3)

- Debug and ReleaseSafe unit suites: 36/36 passed. New coverage: typed handle pools; terrain queries matching rendered vertices and triangle interiors in a negative chunk; runtime model round trip, version, truncation, index, and allocation-failure rejection; glTF compile of the crate (two materials, interleaved view), baked node rotation and translation, out-of-range accessors, and unsafe external URIs; catalog load and allocation failure; box settling, stacking, friction, and raycasts; the character blocked by walls, stepping onto a ledge, and pushing a prop; save round trip with a seed above 2^53, and rejection of mismatched seed, generator, format, prop ranges, and truncated JSON; atomic save file write and read.
- Headless acceptance tests (`game/Sandbox.zig`): walk until a crate blocks the player, pick it up, turn and carry it 7.5 m, drop it, save, disturb the crate, relic set, and player, then reload the crate's exact position. A save from another seed is rejected. Salvage a relic by stable ID; it can no longer be targeted; regeneration yields the same object at that ID; the removal survives a save round trip.
- ReleaseSafe 150-frame smoke with `MTL_DEBUG_LAYER=1`: flight, empty view, walk mode, grab of crate 1 (`held=1`), and an in-memory save/restore of 1.4 KB; no Metal validation errors, clean exit.
- The streaming benchmark still passes every check after the renderer moved to catalog handles: interval P99 21.1 ms, render CPU P99 1.2 ms.

Not yet verified by hand: mouse-driven grabbing and salvaging, the on-screen crate model and crosshair, and F5/F9 against the real `saves/` directory. The code paths are covered by the tests above, but no screenshots or interactive session were taken.

## Upstream programmatic resize issue

A ReleaseSafe smoke run with Metal API validation reproduced a hang after setting `Core.windows.width/height` from the application thread. Sampling showed the main thread in `macOS.tick → NSWindow.setFrame_display_animate → windowDidResize → handleResize → windows.lock`. `tick` already owns that non-reentrant lock. The renderer and application then wait on the same collection lock. This is in the pinned Mach source, not a GPU validation error.

The experiment was terminated and the programmatic size change removed from the app. No dependency cache files were patched. The smoke sequence now exercises culling, an empty view, and HUD toggling. Initial sizing works. Before exposing a resolution selector, update or patch Mach with a tested callback/locking fix. Native drag-resize is a separate path and still needs manual validation.

## Remaining platform checks

- Manual camera capture/release, focus loss, minimization, live resizing, and high-DPI transitions.
- Windows/D3D12 and Linux/Vulkan runtime tests.
- Whole-process memory instrumentation: Mach's stock entrypoint currently omits module-container teardown.
- Deterministic screenshot regression tests and CPU/GPU percentile benchmarks.
