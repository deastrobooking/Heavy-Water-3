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

## Mesh colliders (phase 6)

- Debug unit suite: 69/69 passed. The BVH ray cast matches brute force over 300 random rays on a bumpy 800-triangle grid; oriented boxes face outward; mesh build cleans up on allocation failure. Acceptance: the character climbs a 15° ramp, resting on its uphill footprint sample (0.7 r × tan 15° above center, within 1 cm); it stops at a leaning 80° wall exactly one radius from the face above step height; it lands on a 5° deck at y = 3.0 (±5 cm) and climbs toward the high end; picking reports the deck mesh and user; placement overlap sees the deck until it is destroyed; a crate rests on a mesh floor at 3.4 m (±2 cm); a rigid box settles on a tilted deck.

## Test Arbor and depth (phase 6)

- Debug and ReleaseSafe unit suites: 71/71 passed, with no leaks under the testing allocator (every test Sandbox is deinitialized). New coverage: test Arbor geometry (ramp grade under 12%, platform, bridge ends, and tower meeting at 40 m and 36 m within 1 cm, valid render mesh); the reversed infinite projection (near → 1, monotonic toward 0, distinct depths at 1 km and 1.001 km); and the full walk acceptance: steered up the whole spiral ramp at sprint input without dropping more than 0.6 m below its surface, reaching platform height (±0.3 m), then down the bridge road to the tower top (±0.1 m), grounded.
- Found and fixed by the walk test: the ramp first reached 40 m only at the platform's center line and ran into the platform's side 0.8 m below its top. It now levels out for the last 8% of its sweep.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1` (reversed depth, the test Arbor drawn): no validation errors, clean exit. Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 0.8 ms).

Not yet verified by hand: how the tree reads on screen and at distance, and haze tuning.

## Canopy lighting and review (2026-09-30)

- Review found the renderer's time of day was never published, lamps and avatar accents never set the shader's emission channel, the twilight key changed direction while still bright, and the smoke circuit button press was overwritten by the door press. Those connections are fixed. The renderer now retains Mach's GPU error callback (which exits unsuccessfully), replacing a log-only override that could hide a failed render in successful smoke/benchmark exit codes.
- ReleaseSafe: **77/77 tests pass**, application compile passes. Added clock periodicity/large-tick/wrap checks, twilight continuity, and the canopy route. Extended existing integration tests to verify that save/load restores world time, a wired lamp publishes emission when powered and loses it after disconnection, and avatar lumen carries emission.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300`: all 300 frames complete, 383 simulation ticks, no Metal validation errors, exit 0. The smoke sweeps a complete lighting cycle, creates SORA, grabs a crate, round-trips a save, builds/wires/copies the workshop, confirms `Smoke lamp: lit=1`, and drives the rover 2.4 m.
- `python3 tools/benchmark.py --canopy --frames 300 --output .tools/canopy-benchmark.json`: all checks pass on Apple M3 Pro / Metal, ReleaseFast, default seed. 60 warm-up frames then 300 measured frames; 128 detailed-Arbor and 172 proxy-Arbor frames, 16 chunk crossings, 105 uploads, 80 evictions, no underfilled active-ring frames. Render CPU P50/P95/P99: **0.572 / 0.858 / 0.926 ms**. Presentation interval P50/P95/P99: **20.851 / 20.944 / 21.074 ms**. Peak upload 284,204 B within 327,680 B; peak 25 GPU terrain chunks; fixed pools remain at 2 CPU and 50 GPU allocations.
- Formatting and diff whitespace checks pass. Benchmark CLI help works with the new canopy option and separate default report path.

The benchmark measures render CPU submission cost and presentation intervals, not GPU execution time. Pixel-level appearance, outline thickness, color tuning, and manual day/night play remain unverified; no screenshot review was performed. The single test Arbor stays resident at both detail levels. Multi-Arbor residency, local lights, and bloom are not implemented by this change.

## Arbor genomes and sap (2026-09-30)

- ReleaseSafe suite: **85/85 tests pass**. New coverage includes deterministic bounded space colonization; genome validation; measurable narrow/broad silhouette differences; valid full/proxy/collision meshes; parent-before-child graph structure; allocation-failure cleanup; and landing/walking on a generated shelf at its rendered height. Existing full test-Arbor ramp/bridge walk remains passing.
- Sap coverage: proportional root sharing and branch limits, order-independent grants, independent trees, exclusion of local generator supply and detached/disabled/idle taps, continuous lamp brownout, and shared power across separate machines. The sandbox test saves overloaded beacons, removes a load and observes recovery, reloads and reconnects both to the same tree, rejects a generator-version mismatch without mutating the session, and verifies a remote copied tap supplies nothing. Tree lumen publishes reduced emission under overload.
- Build-tool acceptance: select the sap beacon from the palette, aim at terrain beside tree 1, obtain a valid preview, place it, receive full power, inspect its tree ID, then verify placement away from wood is invalid.
- ReleaseSafe application compile and `build assets` pass. All four blueprints, including `sap_beacon.json`, are validated and installed. Formatting, diff whitespace checks, and benchmark CLI help pass.
- **400-frame Metal validation smoke passes**, exit 0, no validation errors. It creates the player, grabs a crate, round-trips the save, builds/wires a lamp, drives the rover 3.3 m, views both generated Arbors, and reports `Smoke sap: tree 1 demand=300 W supply=150 W satisfaction=50%`. Final count: 509 simulation ticks, 861 submitted objects. The lighting cycle is swept across the run.

Apple M3 Pro / Metal, ReleaseFast, seed 310399555161; each canopy run has 60 warm-up and 300 measured frames:

| Route | CPU P50 / P95 / P99 (ms) | Presentation P99 (ms) | Detailed / proxy frames | Chunk crossings | Uploads / evictions |
| --- | --- | --- | --- | --- | --- |
| `--arbor 1` narrow crown | 0.561 / 0.744 / **0.868** | 20.987 | 174 / 126 | 14 | 95 / 70 |
| `--arbor 2` spreading crown | 0.580 / 0.789 / **0.898** | 20.976 | 174 / 126 | 16 | 102 / 77 |

Both reports pass all checks, including both LODs, the 16.667 ms render CPU budget, active-ring coverage (zero underfilled frames), and unthrottled presentation. Peak upload remains 284,204 B within 327,680 B; peak GPU terrain residency remains 25 chunks; terrain pools stay at 2 CPU and 50 GPU allocations. Reports are `.tools/canopy-1-benchmark.json` and `.tools/canopy-2-benchmark.json`.

These are submission and presentation measurements, not GPU execution timings or an art review. The three trees and both of their mesh detail levels remain resident; terrain-pool counters do not represent total process/GPU memory. No screenshot or manual visual approval was performed. Runtime grafting/growth, tree eviction, and allocation of unused flow after branch bottlenecks remain deferred. See [Arbor genomes and sap](arbors.md) for controls and content-v4 save compatibility.

## Upstream programmatic resize issue

A ReleaseSafe smoke run with Metal API validation reproduced a hang after setting `Core.windows.width/height` from the application thread. Sampling showed the main thread in `macOS.tick → NSWindow.setFrame_display_animate → windowDidResize → handleResize → windows.lock`. `tick` already owns that non-reentrant lock. The renderer and application then wait on the same collection lock. This is in the pinned Mach source, not a GPU validation error.

The experiment was terminated and the programmatic size change removed from the app. No dependency cache files were patched. The smoke sequence now exercises culling, an empty view, and HUD toggling. Initial sizing works. Before exposing a resolution selector, update or patch Mach with a tested callback/locking fix. Native drag-resize is a separate path and still needs manual validation.

## Remaining platform checks

- Manual camera capture/release, focus loss, minimization, live resizing, and high-DPI transitions.
- Windows/D3D12 and Linux/Vulkan runtime tests.
- Whole-process memory instrumentation: Mach's stock entrypoint currently omits module-container teardown.
- Deterministic screenshot regression tests and CPU/GPU percentile benchmarks.

## Packs and background loading (phase 13, slice 2) — 2026-10-01

- Debug suite: **159/159 tests pass**. The new tests cover:
  - **Packs:** round trip, blob verification, and five kinds of damaged table rejected.
  - **Loader:** 64 pack models load in the background with group progress reaching 1. A corrupted blob fails only its own asset with `HashMismatch`; a missing GUID fails with `UnknownAsset`; a generator job works; a bad pack header is refused on open.
  - **Catalog:** reserve and install, with double installs and unknown handles refused.
- The existing allocation-failure test caught a leak when a deferred build failed inside `loadSeeded`; fixed.
- `tools/benchmark.py --pack 64` (ReleaseFast, 600 measured frames): **all checks pass**.
  - The 80 MiB pack of 64 meshes was requested at frame 60, and all were decoded and installed by frame 64 and uploaded.
  - Render CPU P50/P95/P99 was 0.903/1.474/1.777 ms, presentation interval P99 21.297 ms, with zero underfilled frames.
  - The peak frame upload was 6.29 MB: the largest mesh going up alone, the allowed oversize case; every other frame stayed within the 4 MiB budget.
  - The first run failed `pack_uploaded`: 13 installs hit the 64-material pool limit. The stress code had also counted failed installs as installed. Both are fixed: the material pool is now 256, and only successful installs are counted.
- Smoke (`MTL_DEBUG_LAYER=1`, ReleaseSafe, 200 frames, including four split-screen views): no validation errors. Deferred meshes were ready 145 ms after start. The overview capture shows the Arbors and district drawn from deferred builds.

## Asset identity (phase 13, slice 1) — 2026-10-01

- Debug suite: **149/149 tests pass**. The new tests cover:
  - **GUIDs:** format, parse rejection, derived and random generation, JSON form.
  - **Sidecars:** identity and settings kept across re-import, stale-source and old-importer detection, invalid and unknown settings rejected, kind by source type.
  - **Registry:** atomic manifest load, duplicate GUIDs refused with no change, typed resolution with kind mismatch and unbound errors, reference JSON.
  - **Catalog:** every compiled and generated asset resolves by GUID, and every blueprint is reachable by GUID.
- The existing allocation-failure test of catalog load caught `loadManifest` turning out-of-memory into "invalid manifest"; fixed.
- Build behaviour, checked by hand:
  - The build fails without sidecars, and `zig build import` created all 10 (crate plus nine blueprints).
  - A second import changed nothing.
  - Editing `rover.json` without re-importing failed the build with "StaleMeta; run `zig build import`". Re-import refreshed the hash and kept GUID `275f5eab…`, and the source was then restored.

## Sky city — 2026-09-30

- Debug suite: **133/133 tests pass**. The new tests cover:
  - **Bridges:** the clear envelope for six styles on six roads plus 0 → 3 across three seeds, grounded supports clear of plazas, and light-string geometry.
  - **Skyline:** at least 12 towers per seed for four seeds, every tower clear of corridors, plazas, trunks and spawn, deterministic placement, and 0 → 3 still buildable.
  - **In the world:** every buildable style built at 0 → 3 and stood on at 12 lane and walkway points each, with styles kept through save/load.
  - **Capture:** BMP encoding.
  - **Regressions:** the existing walk and drive district loops, Arbor walks, bridge tool, traffic, and shrine tests all pass with the new geometry.
- Visual review from captured frames (`-Dshowcase`, `-Dcapture-frame`), an overview plus every road by day and at dusk. Two problems found this way were fixed: a showcase camera inside a skyscraper, and a skyline that went dark at night (window columns and road lighting added). The cable-stayed pylon was also thickened. Art-direction approval remains yours.
- Smoke, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300 frames: no validation errors, clean exit, 1,173 objects submitted.
- Benchmarks during this session ran with the window throttled by macOS, so only `presentation_unthrottled` failed. Render CPU P99 was 1.429 ms (canopy) and 1.527 ms (streaming), against 1.40 ms on the previous throttled run, with zero underfilled frames. Presentation numbers need a run with the window visible.

## Scale workloads — 2026-09-30

- Debug suite: **127/127 tests pass**. The new tests cover field determinism and cell sorting, bounds containment, budgeted streaming (20 frames at 64 KiB for 20K objects, with the CPU copy freed), frustum and distance culling, LOD selection, run merging and coverage, normalized frustum planes against the sphere test on 500 random spheres, and the process footprint.
- `tools/benchmark.py --scale` for 10K, 100K and 1M objects (ReleaseFast, 600 measured frames): **all checks pass**. See the results table in [scale](scale.md). Render CPU p99 is 1.271 / 1.213 / 1.281 ms and presentation p99 21.188 / 21.093 / 20.984 ms.
- Memory investigation at 1M:
  - The steady footprint was 1,006 MiB against 522 MiB without the field.
  - Skipping only the field's draws gave 742 MB, so about 380 MB is driver geometry storage for drawn instances.
  - The upload pattern changed the peak: 1.20 GB when uploading in one frame, 0.99 GB at 512 KiB per frame.
  - Uploads were moved from `queue.writeBuffer` to the frame encoder to share Mach's staging page.
- Not available: GPU execution time (Mach Metal has no timestamp queries), GPU-compacted culling and indirect draws (not implemented in the pinned Mach). Not measured: the visual result of the field at each LOD in the window.

## Mods and scripting — 2026-09-30

- Debug suite: **123/123 tests pass**. The new tests cover:
  - **Interpreter:** hand-assembled modules for control flow, memory, traps, fuel, depth, float conversion and float semantics; rejected imports, bad versions, and truncated or unbalanced bodies.
  - **Host:** the Zig-compiled `glowworks` module against native results, script-signature checks, and recovery from a starved fuel budget.
  - **Mod loader:** the example package, plus twelve rejected manifests or packages.
  - **World:** a breathing lamp tracks its script one step behind; duplicate installs, changed designs and missing mods are handled, and the save round-trips. The save test was also extended for v10 mods.
- Two bugs were found by tests while building it. The interpreter's loop branch re-entered the `loop` opcode, which broke branch depths. Script devices wrote their result to port 0 while `out` is port 4, as for logic.
- Interpreter cost (Apple M3 Pro, ReleaseFast / ReleaseSafe): `breathe` 802 / 836 ns per call (170 instructions); `majority` 374 / 408 ns (99 instructions); native `breathe` 5.6 ns. See the [scripting evaluation](scripting.md).
- Smoke, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 200 frames: the app installed `glowworks 1.0.0` from `mods/`; no validation errors, clean exit, 261 ticks for 200 frames (unthrottled).
- Canopy benchmark re-run with the window visible (300 measured frames, ReleaseSafe): **all checks pass**. Render CPU P50/P95/P99 0.675/1.061/1.142 ms, presentation interval P50/P99 20.842/21.1 ms, zero underfilled frames, 25 peak resident chunks, unchanged pools. This replaces the throttled presentation result recorded below.
- Not measured: official WebAssembly spec-suite conformance, and a mod placed and used by hand in the window.

## Rootsong, plaza priority, guest trading, Rootdeep shrines — 2026-09-30

- Debug suite: **115/115 tests pass**. The new tests cover:
  - **Rootsong:** root grouping, and a world test with a sender at the test Arbor and listeners at the narrow Arbor, the spreading Arbor, and away from wood.
  - **Traffic and trading:** plaza priority, and guest trading.
  - **Shrine generation:** 300 seeds verified with plan replay and blueprint validation, plus unsolvable, trivial and carry-versus-drop solver cases.
  - **Shrine playthrough:** both placed shrines played in the world from their verifier plans, with door states matched to the model after every action, then rewards, protections, reset and save/load.
- Shrine generation over 300 seeds: fallback shrine for about 1%. The median shortest solution is 8 actions (longest 16), and 187 of 300 need 8 or more. Keeping the longest of six verified candidates raised the median from 6.
- Two bugs were found by the in-world playthrough and fixed in the test's play method, not the game. Carrying a crate at eye height wedged it against the next divider wall; backing up swung it through the player. The test now carries crates overhead, clear of walls and above plate sensing height.
- ReleaseSafe step cost with city life and shrines, measured headlessly at spawn: full Sandbox step **0.130 ms** (physics 0.091, city life 0.043, machines 0.008).
- The free-traffic acceptance phase was lengthened from 60 s to 90 s, because plaza waits legitimately delay a car's third plaza on a long route.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 600 smoke frames: no validation errors, clean exit, both shrines logged with their verified plans.
- **Not representative:** during these final runs, the window was being throttled by macOS (presentation interval p95 about 1 s). The committed build behaved identically on the same run: 4,301 against 4,292 simulation ticks over 200 frames. The canopy benchmark therefore failed only its `presentation_unthrottled` check. Render CPU P50/P95/P99 was **1.021/1.232/1.399 ms**, with zero underfilled frames, 25 peak resident chunks, and unchanged pools. Presentation measurements need re-running with the window visible.
- Not measured: a controller-driven guest trading session in the window, and manual play of a shrine in the window.

## Living city: traffic, pedestrians, markets — 2026-09-30

- Debug suite: **108/108 tests pass**. New tests cover route choice with and without a bridge, replanning, lane and walkway offsets, and market stock, sell-out, dawn restock, prices and save validation. They also include the Sandbox traffic and market acceptance tests described in the [roadmap](roadmap.md), plus a save round trip for the v8 wallet and stock fields.
- Traffic acceptance: 3,600 free steps with every car upright on the deck and reaching at least three plazas, and pedestrians each moving more than 20 m without falling. Then a 0 → 3 bridge crossing (the bridge reported occupied), and a bridge closed mid-trip: the car reroutes 1 → 0 → 5 → 4 → 3 and reaches plaza 3. The closed bridge is removed after its last pedestrian crosses, with **zero recoveries** throughout.
- A first draft refused to remove occupied bridges. The test showed that a pedestrian can hold a 320 m bridge for over three minutes, so removal now closes the bridge and removes it once clear.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 600 smoke frames with city life enabled: no validation errors, clean exit. There were 3 cars and 8 pedestrians with 0 recoveries and 0 deadlocks broken, and 814 objects submitted at completion. The market logged day 0 stock.
- Canopy benchmark (narrow Arbor), ReleaseSafe, 900 measured frames with city life running: render CPU P50/P95/P99 **0.814/0.992/1.103 ms**, interval P99 20.994 ms. There were zero underfilled frames, peak residency was 25 chunks, and pools stayed at 2 CPU / 50 GPU allocations.
- Not measured: simulation cost per step for city life (the benchmark measures render CPU), a long soak for rare traffic deadlocks, and manual play of the trade panel in the window.

## Traversal and local co-op — 2026-09-30

- Debug suite: **103/103 tests pass**. New tests cover the controller (buffered versus dropped early jump, stomp bounce, roll collider height, climb gate and mantle onto a 3 m block, grapple zip to a static anchor, glide, triple-tap hover). They also cover co-op proximity sensing, split-screen tiling, and the four-player Sandbox acceptance. In that acceptance, three guests join, P1 stays put within 0.05 m while P2 walks, P3 strafes and P4 turns 2.8 rad, all four bodies are published with owner tags, and P3 presses the powered-door button and the door opens. A guest then leaves, and the save contains no guest data but loads with guests beside P1.
- The previous controller commit had broken three existing acceptance tests (the crate carry, the powered door, and the third-person character). Walking into the crate row or the closed door started a climb over it. Climbing now starts only from a jump into a wall; all three pass again.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: players went 1 → 4 → 2 → 1. Views 2–4 each created their own streaming pool (49 CPU / 25 GPU chunks) once. There were no validation errors and the exit was clean (code 0). P2 walked under its own input while P1 flew to the far Arbors. The rover displacement (1.3 m) matches the pre-change build on the same run (1.2 m).
- Single-view streaming benchmark after the change, ReleaseSafe, **900 measured frames**: render CPU P50/P99 **0.805/1.085 ms**, interval P99 20.976 ms. Peak upload was 284,204 B, peak residency 25 chunks, with zero underfilled frames and unchanged pool allocation counts (2 CPU, 50 GPU).
- Not measured: split-screen CPU/GPU cost as a benchmark, a physical controller test (no pad was attached to this machine; the pad path is covered by the `Gamepads` unit test and the same `Input` route the guests use), and a manual visual review of the split layouts.

## Canopy district milestone — 2026-09-30

- ReleaseSafe suite: **95/95 tests pass**, including all existing ramp, machine, sap, physics, streaming, and asset tests. The application compile check passes.
- District generator v1 reproduces its six-node layout across five tested seeds. Solver tests reject invalid anchors, duplicate/reversed spans, excessive grades, trunk collisions, disconnected graphs, road crossings, and insufficient terrain clearance. Junctions reserve room for trunk spurs and market bays.
- Movement acceptance uses the real fixed-step Sandbox and collision: the player walks **0 → 1 → 2 → 3 → 4 → 5 → 0** without falling below the road, and a machine-powered rover drives that same loop without resetting its pose between roads. Every plaza is reached; the rover stays upright and the player exits onto the deck. Additional walks cover both complete trunk-ring plazas and their spurs, plus a newly constructed **0 → 3** bridge through both plaza seams.
- Construction tests place and settle a rover on an elevated plaza, reject unsupported edge placement, select two visible bridge anchors, commit/cancel/remove, and preserve endpoints and collision through save/load. Invalid bridge deltas leave the session unchanged. Allocation-failure injection exercises each allocation during bridge restoration and verifies cleanup and preservation of the old bridge and session.
- Native Apple M3 Pro / Metal run with `MTL_DEBUG_LAYER=1`, ReleaseSafe, **500 frames**: completed with no validation errors, 635 simulation ticks, 681 submitted objects at completion, powered lamp lit, rover displacement 3.2 m, sap demand/supply 300/150 W (50%), bridge preview rendered, and bridge **0 → 3** rebuilt through a 38,074-byte in-memory save. User save files were not touched. This is runtime validation; visual art-direction review remains outstanding.
- Existing narrow-Arbor canopy benchmark, with the district resident: **300 measured frames**, 60 warm-up frames, ReleaseFast. Render CPU P50/P95/P99 **0.877/1.009/1.084 ms**; presentation interval P99 **20.983 ms**. Fourteen chunk crossings, 95 uploads, 70 evictions, peak 25 resident chunks, zero underfilled frames, and unchanged fixed pool allocation counts. All benchmark checks passed. This measures renderer CPU submission and presentation intervals, not GPU execution time or city simulation performance. Report: `.tools/city-canopy-benchmark.json`.
- New saves use format **7**, content **5**, district generator **1**; old formats/content are rejected. One district and three Arbors remain resident. Runtime woody grafting/growth, city streaming, traffic, trading, and manual visual review remain future work. The original test-Arbor entrance keeps its 10% bridge; the new district roads enforce the 6% limit.

## Fighting, energy firearms and classes — 2026-10-02

- Debug suite: **282/282 tests pass** (about 3 minutes). New tests:
  - The rig's hand sweeps across the front through a forehand and comes forward to aim.
  - A cut hits a trooper exactly once (forehand + backhand damage to 0.01), a mid-cut press queues the backhand, a full hold releases a charged wave, and the guard parries for 0.3 s and then blocks.
  - Blades cut each unit once per swing with knockback and stun; guards turn bolts into `deflected` events.
  - A sniper beam pierces exactly one unit and scopes to 0.3×; a bazooka orb bursts and stuns the unit beside its target.
  - Firearm rhythms: machine gun 13–15 shots a second until it overheats, sniper steadiness, heavy-rifle charge, bazooka detonation.
  - Specials: overshield soak, refusal while cooling down, grenade burst and stun, sentry zaps, phase-dash blink and stun, slam throw, lance damage and cast pose.
  - The profile class round-trips and defaults to Ranger for older documents. An old settings file with culling on C loads with special 2 moved to F7.
- Fixes found while testing:
  - The machine gun fired 12 a second, not 14, because the cooldown clamped to zero inside a step. It now carries the remainder.
  - Piercing shots hit the same unit again because they resumed inside its sphere; they now skip the unit slots they have passed.
  - The combat showcases first took the existing river viewpoint `-Dshowcase=36`; they are now 37–40.
- Native Metal smoke, ReleaseSafe, `MTL_DEBUG_LAYER=1`, 300 frames: `Smoke combat: saber and sniper made=true, saber cuts=3 trooper health 1616 stunned=true, sniper pierced=true, grenade burst=true, slam threw=true`. Every other stage was unchanged, with no validation messages. That run, unlocked, took 394 simulation ticks. Reruns after the screen locked took about 6,330, because macOS throttles presentation and each frame catches up more fixed steps; their results were otherwise the same.
- The Debug executable starts and runs, with no stack overflow from the new module state.
- Captures:
  - `-Dshowcase=37`: the forehand cut and overhead raise with blade trails, the blade leaving the right hand.
  - `-Dshowcase=38` and `40`: the first-person rifle and the lumen lance from the hand. The beams were first far too wide near the camera and were narrowed.
  - `-Dcharacter-showcase=5`: a Synthetic with lit eyes, collar, core and cheek seams. The cheek seams can read as tear streaks; art direction is yours.
- Not measured or checked by hand:
  - feel and balance (damage, energy, cooldowns, lunge strength);
  - the guest controls on a real controller;
  - the cost of posing a rig per armed player per step (one skeleton pose each, plus three per step while swinging);
  - the held weapons and slam or lance effects are block-and-gem placeholders.

## Debug executable stack overflow — 2026-10-01

- **Report:** running `zig-out/bin/heavy-water` (a Debug build) crashed at startup with a segmentation fault in Mach's `Modules.init`, at a stack address.
- **Cause:** Mach's entry point keeps every module's state by value on the main thread's 8 MB stack, and its `init` copies each module through a local. The overlay's inline vertex array (raised to 120,000 vertices for the GUI, 2.9 MB) sat inside the Renderer's state, so Debug builds, which keep those copies, overflowed. The smoke runs had all been ReleaseSafe or ReleaseFast, so they missed it.
- **Fix:** the overlay's vertices are now allocated on the heap when the renderer starts. A test caps the module-state sizes the suite can see (Sandbox under 1 MB, World under 256 KiB, Overlay under 4 KiB, Canvas under 256 KiB).
- **Verified:** the rebuilt Debug `zig-out/bin/heavy-water` starts, loads mods, opens audio and Metal, and runs for 25 s at the title screen. **270/270 tests pass.**
- **Follow-up:** run at least one smoke in Debug after state-size changes.

## Focused review: flight, air war and frontier — 2026-10-01

Review of the flight, air war, combat, garage and frontier code since the vehicle work began. Findings and outcomes:

- **Fixed (high):** a Kestrel left mid-flight kept its throttle and flew on unpiloted. Empty jets now cut the engine and let the lift jets lower them onto the gear. Test: a jet left at 30 m and 40 m/s settles onto its gear.
- **Fixed (medium):** the gear springs balanced at about 1 m of penetration, so parked jets rested on the hard-floor clamp rather than the gear. Each leg now carries a third of the weight at 10 cm. The same test checks the rest height.
- **Fixed (medium):** a shot could register on a carrier's launch bay even with a wasp nearer along the line, because the bay's 4 m allowance applied against any nearer hit. It now applies only past that carrier's own hull hit. Test: a wasp between the gun and a bay takes the shot, and the carrier is unharmed.
- **Fixed (low):** a stray no-op statement in `Frontier.stepSkies`.
- **Open (low):** a missile locked on a ground Hive unit tracks its slot index; if the unit dies and the slot is reused, the missile homes on the newcomer. See [next steps](plans/next-steps.md).
- **Open (docs):** the save-format description was stale (v10, without progress, cars or the fighter); it is rewritten in [architecture](architecture.md).
- **Checked, no change:**
  - The HUD projection's basis matches `Camera.move`'s right vector, and the up vector is forward × right. A capture with a live lock is still needed to confirm the reticle's side.
  - Wasps keep thinking after their carrier sleeps; with analytic avoidance that is bounded (14 at most).
  - Guests are in the wasps' target list with matching player indices.
- **Debug suite: 269/269 tests pass.**
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300 smoke frames: no validation errors, clean exit; frontier and flight stages passed (Kestrel fabricated, lifted off, wasp downed).

## Flight: the Kestrel and the air war — 2026-10-01

- Debug suite: **267/267 tests pass**. New tests:
  - **Flight:** a vertical takeoff from the gear on the lift jets; wingborne cruise holding altitude at −4° to 10° angle of attack, with the top speed under 300 m/s; mouse-aim turns to a 90° aim and levels the wings; an afterburner climb; crash damage; a hangar test that takes off, transitions and flies.
  - **Ship meshes:** they build at their intended lengths, and the Kestrel's fuselage and fins are closed solids.
  - **Air war:** carriers launch wasps that attack, hit the jet and draw flak; cannons down a wasp; a locked missile damages a carrier.
  - **Fabricator:** the Kestrel recipe.
- **Found and fixed:**
  - **Climb:** at 48 kN the fighter bled from 150 to 78 m/s in a turn-and-climb. Thrust is now 58/95 kN (about 0.9 thrust-to-weight).
  - **Cruise angle of attack:** a fast cruise on the cambered NACA 2408 wing sits just below zero incidence, so the test range was corrected.
  - **Fin winding:** the lofted fin was inside out (volume −0.28).
  - **Hover transition:** hover drift-bleed fought the engine and capped the jet near 24 m/s, at the lift jets' handover. It now bleeds only sideways drift while the engine pushes.
  - **Wasp cost:** each wasp cast a 120–170 m ray every step. A test sat at full CPU for over 11 minutes and the game would have paid it every frame. Avoidance is now analytic terrain samples plus a short structure ray every fourth step, and the suite is back to about 2 minutes.
  - **Air war placement:** carriers now circle beyond the nests and wake within 650 m, so the air war stays over the Hive's ground.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke flight` fabricated the Kestrel through the panel, lifted off, and downed a wasp with the cannons; carriers were at 264 m and 326 m. The first run reported no wasp downed because the smoke placed the wasp along a level line from the pad into rising ground; it now aims into open sky.
- **Captures:**
  - `-Dshowcase=33`: the Kestrel on its pad.
  - `-Dshowcase=34`: the Kestrel banking hard on afterburner beside a Brood carrier, with wasps in formation and the second carrier distant.
- **Not measured:** flying by hand, missile play, jet–ship collisions (not implemented), and frame cost with 12 wasps and two carriers awake.

## Guest weapons, Hive troopers, saved cars — 2026-10-01

- Debug suite: **258/258 tests pass**. New tests:
  - Troopers march out of a nest, stay on the ground, and hunt.
  - Saved car positions and headings round-trip, unowned designs stay absent, and collected pickups stay collected.
  - A guest fires the party's blaster with the trigger through `Sandbox.step` and downs a drone.
  - The combat tests now run per arsenal; a shield raised by any player absorbs.
- Two first versions of the guest test failed on placement, not code:
  - The drone sat under the slope along the guest's pitched aim.
  - The shot met the crate row beside the spawn.

  The debug traces showed the shot flying true, so the test now levels the aim and uses a nearer drone.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames** (screen unlocked): no validation errors, clean exit. `Smoke frontier` fabricated a car and a blaster, the car flew 19.5 m, and the drone went down; four-player stages ran with guest arsenals.
- **Captures:**
  - `-Dshowcase=32` (in flight) shows the Skimmer cruising 7 m over the terrain toward the city. Flown straight ahead, it stopped at a wall as designed.
  - `-Dshowcase=30` shows troopers in Hive plate advancing beside drones and a sentinel. The player lost 65% of their health in about 2.5 s standing still, so bolt damage was lowered and the spread widened; bolts are thinner too.
- **Not measured:** difficulty by hand, controller play, and skinning cost with eight troopers near P1.

## Frontier: hover cars, pickups, fabricator, the Hive and weapons — 2026-10-01

- **Generator code:** your vehicle generator modules (`hull`, `airfoil`, `prims`, `fan`, `nozzle`, `dynamics`) were added with their imports pointed at the character core. Their tests all passed the first time. The paste ended partway through the `dynamics` tests, so the energy test and a torque-direction test were finished here. `hover.zig` and `car.zig` were not in the paste and are written for this game.
- Debug suite: **255/255 tests pass**. New coverage:
  - **Vehicle geometry:** watertight hull, wing, fan and nozzle meshes; NACA and Helmbold values; the isentropic area ratio; closed-form box inertia; torus volume; energy-conserving torque-free spin.
  - **Hover:** momentum theory and its inverse; ground effect; lift shares balanced about an aft COM; settling level at ride height; cruise and boost caps; rolling hills at 45 m/s without touching; altitude hold over gaps; wall stops.
  - **Garage:** a built car hovers, all three designs lift themselves, and a car parks, is boarded, flown and left.
  - **Pickups and fabricator:** deterministic placement covering every kind; collect-once; drop expiry; recipes paid exactly and made once; first weapons alloy-free.
  - **Hive:** nest sites away from landmarks; dormant nests; woken nests spawning units that hunt, shoot and hit; strikes downing units and nests; a destroyed nest stops spawning.
  - **Combat:** weapon selection and cycling; a blaster shot destroying a drone; the saber cutting only in front; shield absorption; regeneration; restoring a downed player; health from vital cells.
  - **Saves and screens:** progress round-trips with inventory, picked IDs and owned cars, armor and weapons, and every screen, including the fabricator, lays out inside the window.
- **Fixed during the work:**
  - **Momentum theory:** four 0.6 m fans at 60 kW lift only about 7 kN; a 1.1 t car needs about 280 kW per fan, so fans now have 300 kW.
  - **Aft COM:** the COM sits 0.42 m aft, so equal lift per fan pitched the car up and it drifted backward. Lift is now shared by lever arm, plus a trim integral.
  - **Glow-mesh leak:** a glow mesh leaked when the catalog failed partway through; the allocation-failure test caught it.
  - **Top speed:** boosting reached 91 m/s; drag now includes fan ram drag.
  - **Ground loss:** at speed, a pad dipping into a slope lost the ground (its ray started underground) and the car sank. Rays now start 2 m up, there is a 0.9 s look-ahead probe and a hard keel floor.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke frontier` fabricated a Skimmer and a blaster through the panel, the car flew 19.5 m in 2 s, and 3 nests and 62 pickups were placed. That run reported "drone downed=false" because the smoke gave the drone 30 health against a 22-damage shot; the test was corrected to 15. This smoke ran before the hover floor and drag fix, the sound cues and the new dialogue.
- **Not re-run:** the screen locked partway through, so later smoke and capture runs could not render (`CGSSessionScreenIsLocked`; the app idles in its event loop). Re-run `-Dsmoke-frames=300` under Metal validation and the `-Dshowcase=29..32` captures once the session is unlocked.
- **Visual review** (`-Dshowcase=29..31`): the three cars hover on their pads with light strips and wings; the nest spire glows, drones and a sentinel hunt and fire red bolts, and the player's health drops; the fabricator panel shows tabs, cost chips and inventory. The first flight capture showed the 91 m/s top speed and the ground loss, both fixed above.
- **Not measured:**
  - frame cost of the Hive and the hover probes at full load;
  - flying the car by hand;
  - guests' weapons (not implemented);
  - listening to the new sounds.

## Audio — 2026-10-01

- Debug and ReleaseSafe suites: **216/216 tests pass**. New tests:
  - Synthesis: every sound is finite, audible and peak-limited, generation is deterministic, and loops join without a jump.
  - Mixer: one-shots end, pan, respect muted buses, and steal voices oldest-first; loops fade smoothly; a full ring drops commands.
  - Director: each event sounds once, the first frame only starts loops, guests are attenuated and panned, dialogue blips, and a paused world stays quiet.
  - Volume settings clamp and round-trip.
- A ReleaseSafe smoke crashed with an integer overflow on the CoreAudio thread on its first callback. The cause was `@min(chunk, frames - done)`: with a comptime bound of 256, Zig narrows the result to `u9`, so `n * 2` overflowed at 512. The fix widens it to `usize`. Debug had not tripped it in the runs tried; the mixer's own ReleaseSafe tests passed because they never went through the device path.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames** with audio on: CoreAudio at 48 kHz stereo f32, no validation errors, clean exit, every stage including four players and the GUI pass.
- Levels from `zig build sounds`: interface sounds around −10 to −16 dBFS RMS, effects around −13 to −17, loops around −13 to −19 before their gains. In the mix, the canopy pad sits near −26 dBFS under footsteps near −20.
- Not measured: listening (nobody has heard it yet; the WAVs are for that), latency, behaviour when the output device changes mid-session, and CPU cost on the audio thread.

## Guest HUD and rebindable controls — 2026-10-01

- Debug suite: **212/212 tests pass**. New tests:
  - Bindings swap conflicting keys, refuse reserved keys, and round-trip by name, ignoring unknown names.
  - The controls screen captures a key, swaps conflicts, cancels with Escape, and resets.
  - Settings round-trip with a rebound key.
  - The screen layout test now also draws a four-player split screen with a guest trading.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**, including four players with the new guest HUD: no validation errors, clean exit.
- Visual review: `-Dshowcase=27` (four players, P3 at Maro's stall) and `-Dshowcase=28` (controls while rebinding). Two fixes came from it:
  - Ware names showed underscores in the guest stall panel.
  - The interaction prompt showed through behind the pause menu.
- Not measured: rebinding by hand in the window, and controller play.

## Menus, GUI and conversations — 2026-10-01

- Debug suite: **210/210 tests pass**. New coverage:
  - Canvas wrapping, hits and measurement.
  - Scaled overlay text.
  - Menu navigation: disabled CONTINUE and LOAD are skipped, sub-screens return to their entry, quit is confirmed.
  - Settings clamping, round trip, and per-field clamping of a wild value.
  - Dialogue: the built-in file validates, branches follow flags, a gift is given once, panels end the conversation, and malformed data is rejected with a reason.
  - Purchases: upgrades and suits change nothing on failure, and progress round-trips, including shorter level lists from older saves.
  - Creator skips clothing that is not owned.
  - The Sandbox stall test now greets Maro and opens trade from his reply.
  - Every screen and every conversation node lays out inside a 1280×720 canvas.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke GUI` drives pause → settings → resume (closed), Maro's first greeting into the upgrades panel, buys fuel tank level 1, and closes every panel.
- Visual review from `-Dshowcase=18..26` captures:
  - The clock overlapped the scrap count: the wallet panel is wider.
  - The vitals panel overlapped the dialogue box: vitals hide under panels.
  - The player blocked the keeper: the conversation camera is now over the shoulder.
  - The wardrobe panel covered the character: it moved to the left and narrowed.
- A code review then found eight hardening items, all fixed:
  - Clicks are limited to the top layer.
  - Load failures show on the title screen.
  - Settings are written once on leaving their screen.
  - Upgrade levels are saved as a list, so adding an upgrade keeps old saves loading.
  - A wild settings value clamps instead of resetting every setting.
  - Purchase errors are worded for players.
  - Number keys only pick existing replies.
  - Fixed limits now follow the content: the clothing mask, the reply line buffer, and pedestrian conversations picked in file order.
- Not measured: manual play with a physical controller, split-screen GUI for guests (P1 only), and art-direction approval of the screens.

## Character generator and sci-fi armor — 2026-10-01

- The user-supplied procedural character generator (`src/character/`) replaced the block avatar for players, guests, pedestrians and stall keepers. Three new clothing types (exo rig, hardsuit, vanguard) are built from eight hard-surface armor coverages.
- Debug suite: **195/195 tests pass**. New tests:
  - Every armor vertex is rigidly bound to one joint.
  - Armor vertex counts grow exo rig < hardsuit = vanguard. The vanguard cuirass stands further from the chest than the hardsuit's, and the exo rig has none.
  - Two forearm plate vertices keep their distance within 1e-4 m through a walk pose.
  - Segment gaps split a span continuously.
- Fixes found while integrating:
  - The hair-removal index compaction used an aliasing `@memcpy` and aborted under a sealed helmet. It now uses `copyForwards`.
  - Two tests assumed block avatars, and the four-player Sandbox count also overflowed on owner-0 pedestrians. Both now count one character prop per player.
  - A heavy-armor test compared against a sealed helmet that also removes hair. It now compares like with like, and checks that the sealed helmet leaves no hair triangles.
- Visual review: `-Dshowcase=16/17` captures. Two jagged edges, on the faulds top and the cuirass bottom, followed body-region borders as stair steps. Both are now single continuous cuts across belly and hips. Art-direction approval remains yours.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, Debug, **300 smoke frames** with the armor lineup: no validation errors, clean exit.
- Not measured: CPU skinning cost with many armored characters (an armored body has about 3.5K more vertices), and a manual review of the creator cycling clothing in the window.

## Rivers, waterfalls, mountains and snow — 2026-10-02

- Seeded terrain now transitions from a smooth hub valley to ridged highlands. Exposed alpine rock and snow use elevation and slope masks.
- Rivers carve continuous channels and stream as blue world-space ribbons. Periodic seeded drops add vertical waterfall curtains; geometry is generated with each terrain chunk, including across chunk boundaries.
- World generator version is 4 because the terrain and water generation changed; saves from prior generator versions are rejected. Profile and content data are unaffected.
- ReleaseSafe tests and app checks: **276/276 pass**. New coverage checks waterfall drop height, river mesh indices, snow coloration, terrain sampling against the rendered ground mesh, and existing district/building/bridge clearances.
- Four-player native Metal smoke passed with terrain streaming, save/restore, construction and rover checks. `-Dshowcase=36` captures the river and waterfall viewpoint for visual review.

## Development asset reload (phase 13, slice 3) — 2026-10-01

- Baseline review: 159 ReleaseSafe tests and the application compile passed. Fixed index-only loader tickets that could access reused slots, checked pack indices before worker access, and replaced an unlocked telemetry read with a mutex-protected snapshot.
- Expanded suite: **165/165 tests pass** in Debug and ReleaseSafe; application compile checks pass. The final Debug run also verifies changed Wasm bytecode changes live output while a subsequent malformed edit retains the working module. New coverage includes stale loader tickets, repeated model replacement without pool growth, generation exhaustion, external glTF buffer edits, source/settings changes, unchanged-scan counters, wrong GUID rejection, missing-file recovery, staged script replacement and invalid-module recovery, live door state, locally edited machine preservation, rejected physical layout changes and resized crate colliders.
- ReleaseSafe model reload smoke: `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dreload-smoke=true -Dsmoke-frames=600 -Doptimize=ReleaseSafe`. Passed all 600 frames, including four split-screen views, machine building, in-memory save/restore, city traffic and rover driving. The isolated fixture's material changed, generation advanced 2 → 3, stale handle failed, and the GPU accepted the replacement **848 ms** after the source edit. No Metal validation errors. Initially macOS was not rendering the test window; bringing it forward allowed frame progression before the timed edit.
- Full-watch ReleaseSafe smoke (`-Dhot-reload=true -Dsmoke-frames=300`) also completed: crate, all nine built-in blueprints and the installed Glowworks script staged successfully; four-player views, building and save/restore remained functional.
- The smoke writes only an isolated fixture under `zig-out/reload-smoke`; tracked asset sources and sidecars are untouched. Physical blueprint layout edits, vehicle edits, path moves and package manifest changes require restart. Live heightmaps and generated geometry remain future work.

## Ground flora and canopy trees

- Scatter remains deterministic by seed, chunk and candidate ID. Generator version 3 adds sparse broadleaf, needleleaf and willow trees among grass, ferns and wildflowers. Each streamed chunk groups the new forms into instanced mesh draws; slope filters, biome thinning and stable removal IDs remain in place.
- Mesh-generation tests check the three ground-plant forms, shared trunk, and distinct canopy silhouettes; deterministic scatter coverage finds all six species across a fixed 100-chunk sample. `python3 tools/zig.py build test check -Doptimize=ReleaseSafe --summary all` passed **273/273 tests** and the application compile check.
- `caffeinate -d -u -t 60 python3 tools/zig.py build run -Dsmoke-frames=180 -Dcapture-frame=100 -Dcharacter-showcase=4 -Doptimize=ReleaseSafe` completed on Apple M3 Pro. Smoke logs confirmed four-player split-screen, streamed chunks, save round-trip, and generator version 3; frame 100 was captured at 2560×1600.

## Faces and skyline architecture

- Ranger profiles now select masculine or feminine presentation in the creator. The game bakes analytic eye, iris, brow, and mouth decals into a denser face mesh, while head and body proportions vary with the selected presentation. Legacy profile JSON without the new field defaults to masculine.
- Skyline towers add inset glass bays and open observatory crowns. District generator version 3 records the updated architecture rules. Tests assert glass detailing, deterministic placement, and district clearance. The ReleaseSafe 273-test run and four-player runtime smoke above passed with this upgrade.
