# Scale workloads

`python3 tools/benchmark.py --scale N` flies the standard streaming route over a seeded field of N small objects and writes `.tools/scale-N-benchmark.json`. The run is repeatable: the same seed gives the same field, route, and counts. Run the 10K, 100K, and 1M workloads with the window visible.

```sh
python3 tools/benchmark.py --scale 10000
python3 tools/benchmark.py --scale 100000
python3 tools/benchmark.py --scale 1000000 --frames 600
```

## How the field renders

`render/Field.zig`:

- **Layout:** N objects with seeded positions, scale, yaw, and tint, set on the terrain over the route (x −768…1792, z −768…768). They are sorted into a 40 × 24 grid of 64 m cells, each with its own bounding sphere.
- **Culling and LOD (CPU, per cell):** each frame the CPU tests 960 cells, never individual objects. A cell is drawn if it is fully uploaded, within 1.4 km, and inside the frustum. Cells within 160 m use the crate model (24 triangles); farther cells use the block proxy (12 triangles).
- **Submission:** visible cells that are adjacent in the instance buffer with the same LOD merge into one instanced draw (a `first_instance` range). About 390 visible cells become about 29 draws.
- **Per-instance culling (GPU, vertex stage):** field instances carry a bounding radius in `stretch.w`. `scene.wgsl` tests it against six frustum planes in the frame uniform and collapses rejected instances behind the near plane, so they never rasterize. Other content has no radius and is unaffected.
- **Streaming:** instance data, 64 bytes per object, uploads once under its own per-frame budget (`--field-upload-kib`, default 2 MiB), in cell order; cells draw only once uploaded. When the field is resident, the CPU copy is freed.

## Results (Apple M3 Pro, ReleaseFast, 600 measured frames, 2026-09-30)

| Objects | Generate | Resident by frame | Objects submitted p50 / p99 | Draws p99 | Render CPU p50 / p95 / p99 | Presentation p99 | Peak process footprint |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 10,000 | 1 ms | 0 | 3,401 / 4,060 | 29 | 0.776 / 1.164 / 1.271 ms | 21.188 ms | 532 MiB |
| 100,000 | 9 ms | 3 | 33,870 / 40,554 | 29 | 0.723 / 1.142 / 1.213 ms | 21.093 ms | 538 MiB |
| 1,000,000 | 76 ms | 30 | 339,151 / 405,597 | 29 | 0.793 / 1.201 / 1.281 ms | 20.984 ms | 1,009 MiB |

All checks passed for all three:

- the field was resident before measuring started;
- objects were drawn;
- the CPU copy was freed;
- render CPU stayed under 16.667 ms;
- the terrain upload budget and pools held;
- the active ring stayed covered;
- presentation was unthrottled.

Render CPU cost does not grow with object count, because per-frame work is per cell. Presentation stayed at the display's pacing (about 20.8 ms) even at 1M, which suggests the GPU kept up, but it is not a GPU time measurement (see below).

**Memory at 1M:** about 1 GiB peak, against about 0.52 GiB for the same route without a field. Isolation runs attribute it as follows:

- About **380 MB** belongs to drawing: skipping just the field's draws removed it. This is the GPU driver's per-frame geometry storage, which grows with submitted triangles; Apple GPUs are tile-based and buffer transformed geometry.
- The rest is the 61 MiB instance buffer, Mach's 64 MiB staging pages (which never shrink), and allocator retention after the 130 MB generation buffers are freed.

Uploads go through the frame's command encoder. A separate queue write was measured to claim extra staging pages.

## What the pinned Mach cannot do yet

The roadmap's full scale target is GPU-driven culling with indirect submission and GPU timing. The pinned Mach (`7ed0d504`) blocks three pieces:

- **Indirect draws:** `drawIndexedIndirect` and `drawIndirect` panic `unimplemented` in sysgpu, so a GPU-compacted instance list cannot set its own draw count.
- **Shader atomics:** `atomicAdd`, `atomicLoad`, and `atomicStore` are unimplemented in Mach's WGSL compiler, so a compute pass cannot compact visible instances.
- **Timestamp queries:** these are a TODO in the Metal backend, so reports say `"gpu_time": "unavailable"` instead of estimating.

The cell grid with vertex-stage culling is the strongest design possible without them. With the 1M field it keeps CPU cost flat, but submits about 400K instances per frame; compaction would cut both the vertex work and the driver geometry memory. Lifting these limits means updating or forking Mach, a deliberate decision recorded in the [roadmap](roadmap.md).

## Limits

The field is a benchmark workload, not game content: one field on the streaming route, two LOD meshes, and no shadows or physics. CPU culling is single-threaded and per cell.
