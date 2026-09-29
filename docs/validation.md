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

## Machines (phase 4, door and elevator)

- Debug and ReleaseSafe unit suites: 44/44 passed. New coverage: port tables; blueprint parsing and rejection of wrong format, direction, port kind, multiple drivers, unknown ports, duplicate IDs, bad parameters, zero sizes, missing or cyclic logic, and malformed JSON; latch-driven actuators with two-hop latency and a mid-travel reversal; brownout sharing (two 100 W actuators on 100 W move at half speed); disabled generators; logic combining a proximity sensor; state restore validation; kinematic platforms carrying a crate, a character reporting its platform as support, and a door pushing a still character; the save round trip with machine state; and the catalog loading the shipped blueprints.
- Headless acceptance (`game/Sandbox.zig`): the closed door blocks the player; the button opens it in 150 steps to exactly 2.9 m of travel; the player walks through; a saved open state survives a manual close and reload, and stays open after stepping. The elevator carries a standing player from the platform to 4.2 m (±0.05 m), the player steps onto the landing, and the top call button sends the platform down while the player stays on the landing.
- Build-time validation: rewiring `toggle.state` to `platform.power` in `elevator.json` fails the build with `PortKindMismatch`.
- ReleaseSafe 150-frame smoke with `MTL_DEBUG_LAYER=1`: two machines placed, crate grabbed, 1.7 KB in-memory save round trip, door button pressed; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 1.2 ms).

Not yet verified by hand: how the machines look on screen, placement on steep terrain (foundations extend 1.1 m below the origin, and deeper slopes can leave gaps), and pressing buttons with the mouse.

## Vehicle (phase 4, completed)

- Debug and ReleaseSafe unit suites: 53/53 passed. New coverage: quaternion rotation, matrix form, and integration; a tilted rigid box falling and settling flat on its largest face; a sliding rigid box shoving a crate; a fast rigid box stopped by a static wall; rigid boxes blocking the character; surface rays reporting platform velocity; the rover settling at its computed ride height (±3 cm), accelerating straight, turning more than 0.5 rad while upright, and braking to a stop; staying put without throttle; losing wheel contact in the air; holding on a 20° slope with brakes, both nose-up and sideways (drift under 0.02 m over 4 s); rolling freely when released; seat, motor, and steering outputs, including a 50 W supply halving a 100 W motor's drive; frame-relative device positions; and vehicle blueprint validation.
- Headless acceptance (`game/Sandbox.zig`): the rover settles aligned with sloped terrain on four wheels, is entered by aiming at its chassis, moves more than 4 m forward in 2 s on motor power (with nonzero network demand), stops under the parking brake after exit with the player standing outside the chassis, and its pose survives a save round trip exactly.
- Fixed while testing: tires that cancelled only velocity let a parked rover creep down slopes at 0.15 m/s. Tire forces sized with a quarter of the vehicle mass overshot into roll oscillation. Suspension pushing along the chassis axis leaked downhill force. Each fix has a regression test above.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: three machines, crate grab, 2.4 KB save round trip, door button, then the rover driven 3.5 m; no Metal validation errors, clean exit. The first GPU run found that Mach's WGSL compiler lacks `cross`; the shader now defines it.
- Streaming benchmark: all checks pass (interval P99 21.2 ms, render CPU P99 1.5 ms).

Not yet verified by hand: driving feel, chase-camera comfort, rendered wheel spin and steering, and collisions between the rover and machine structures at speed.

## Creation tools (phase 5, first slice)

- Debug and ReleaseSafe unit suites: 58/58 passed. New coverage: runtime blueprint edits under the file format's rules (multiple drivers, kind mismatch, direction, duplicate IDs, vehicle-only kinds); document round trips including wires and body flags; device removal shifting wires and compacting logic nodes; live machine reconfiguration keeping state; lamps lit only when switched and supplied; save v4 with embedded blueprints, yaw, and slot validation.
- Headless acceptance (`game/Build.zig`): generator, button, latch, and lamp placed from the palette on the 0.5 m grid; three wires made by aiming and clicking; a fourth refused because the lamp input is already driven; the button lights the lamp; a fresh session restored from the save has the same circuit with the lamp lit; removing the latch drops its wires, darkens the lamp, and re-tagged bodies still pick correctly. A quarter-turned door is placed on the grid with its travel mapped from +X to −Z, a second overlapping door is refused, and aiming at its structure removes it.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: a four-device, three-wire workshop circuit built through the tool APIs, alongside the earlier stages; no Metal validation errors, clean exit. The whole-world save is now about 22 KB.
- Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 0.9 ms).

Not yet verified by hand: mouse-driven placement feel, preview visibility, wire bar readability, and F5/F9 of a built world through the real `saves/` directory.

## Prefabs and inspection (phase 5)

- Debug and ReleaseSafe unit suites: 59/59 passed. New headless acceptance: capture a generator, button, latch, and lamp circuit (named `circuit_1`, lowest device on the origin), place a copy that is its own machine, light only the copy's lamp with its button, inspect the copy (`NET 0 SUPPLY 200 W DEMAND 25 W 100%`, `lit 1.00`), rewire the copy while the prefab keeps its three wires, and restore the prefab library into a fresh session from the save.
- Manual library run: `saves/prefabs` holding a renamed elevator blueprint and a lamp with 0 W imported one prefab and logged `prefab broken.json: InvalidDeviceParameters`. The test files were removed afterwards.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: the smoke circuit is captured and a quarter-turned copy placed; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass (interval P99 21.4 ms, render CPU P99 0.9 ms).

Not yet verified by hand: pressing P and I in the running game, exporting a prefab file from a live capture, and the panel's legibility.

## Signal bus (phase 5)

- Debug and ReleaseSafe unit suites: 61/61 passed. New coverage: a sender machine's latched button carried over channel 7 to another machine's lamp; channel validation (0 and non-bus kinds rejected); and the in-world acceptance test (workshop button → latch → transmitter lights a separately placed beacon's lamp, retuning darkens it, channels wrap 1 ↔ 64, and the channel persists through a save).
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1` and the streaming benchmark: unchanged and passing (interval P99 21.3 ms, render CPU P99 1.0 ms).

## Player character

- Debug and ReleaseSafe unit suites: 65/65 passed. New coverage: name validation, typing, and the length cap; palette wrapping and proportion clamps; profile document validation; creator flow (name required, typing only in the name field, Escape only after a first confirmation, panel text); avatar proportions, hood parts, facing, glowing accents, and opposite leg swing; and the in-world test (frozen input in the creator, third-person camera behind the eyes while the crate stays targeted, avatar parts drawn, profile restored from a save).
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: a character named SORA with a ponytail created through the window-key path, then the crate grab done in third person; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass.

Not yet verified by hand: how the avatar and palettes look on screen, and the creator's usability.

## Upstream programmatic resize issue

A ReleaseSafe smoke run with Metal API validation reproduced a hang after setting `Core.windows.width/height` from the application thread. Sampling showed the main thread in `macOS.tick → NSWindow.setFrame_display_animate → windowDidResize → handleResize → windows.lock`. `tick` already owns that non-reentrant lock. The renderer and application then wait on the same collection lock. This is in the pinned Mach source, not a GPU validation error.

The experiment was terminated and the programmatic size change removed from the app. No dependency cache files were patched. The smoke sequence now exercises culling, an empty view, and HUD toggling. Initial sizing works. Before exposing a resolution selector, update or patch Mach with a tested callback/locking fix. Native drag-resize is a separate path and still needs manual validation.

## Remaining platform checks

- Manual camera capture/release, focus loss, minimization, live resizing, and high-DPI transitions.
- Windows/D3D12 and Linux/Vulkan runtime tests.
- Whole-process memory instrumentation: Mach's stock entrypoint currently omits module-container teardown.
- Deterministic screenshot regression tests and CPU/GPU percentile benchmarks.
