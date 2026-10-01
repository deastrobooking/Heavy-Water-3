# Phase 13: asset pipeline

**Goal:** every asset has a stable identity, imports only when it changes, loads without stalling a frame, and reloads while the game runs.

## Today

- **Build-time compiler:** `asset-compiler` runs in the build graph. glTF compiles to versioned `HWMS` models, and blueprints are validated. Zig's build cache already skips unchanged inputs.
- **Embedding:** the compiled outputs are embedded in the executable with `@embedFile`, and `Catalog` registers them at startup.
- **Lookup:** typed generational handles (`MeshHandle`, `MaterialHandle`) index the catalog. Content is found through hard-coded fields (`catalog.content.crate`) or blueprint names.
- **Implemented:** GUID sidecars, runtime registry, pack format, background loading and opt-in source reload. The slices below record shipped scope and deviations.

## Design

### Identity: GUIDs and typed references

- Every source asset has a 128-bit GUID, written as 32 lowercase hex characters, which never changes once assigned.
- `AssetRef(Kind)` holds a GUID, where `Kind` is model, material, blueprint, texture, animation, scene, or audio. It serializes as `"crate": "a3f1…"` in JSON.
- A reference resolves through the registry to the existing typed handle. Handles stay the fast runtime path; GUIDs are the persistent path used in saves, scenes, mods, and network messages.
- Built-in content gets GUIDs too, so `catalog.content.*` becomes resolved references rather than special cases.

### Sidecars

Each source file `X` gets a sidecar `X.meta` next to it:

```json
{
  "format": 1,
  "guid": "a3f1c0de9b8e4f7aa1d2c3b4e5f60718",
  "kind": "model",
  "source_hash": "blake3:…",
  "importer": { "name": "gltf", "version": 2 },
  "settings": { "scale": 1.0, "up": "y", "lod_distances": [120, 450], "recompute_normals": false }
}
```

- **Creation:** `zig build import` creates missing sidecars with new GUIDs and refreshes hashes. A normal build fails with a clear message if a sidecar is missing. GUIDs are created deliberately and committed, never silently by every build.
- **Freshness:** `source_hash` and the importer version decide whether the output is stale outside the build cache, for hot reload and in mod packages.
- **Settings:** each importer has typed, validated import settings. An unknown setting is an error.

### Registry and packs

- **Manifest:** the build writes a manifest (`assets.manifest`, JSON plus a binary form) mapping GUID to kind, name, output path, hash, and dependencies (a model depends on its materials and textures).
- **Packs:** content outside the core set ships in a pack (`zig-out/assets/*.hwpack`), a versioned table of contents plus aligned blobs, instead of being embedded. Core assets needed before the first frame stay embedded.
- **Runtime lookup:** `Registry` resolves a GUID to a handle, owns load states, and refuses unknown GUIDs and kind mismatches.
- **Mods:** a mod package's manifest lists the GUIDs it provides, and the same validation applies. A GUID collision with the game or another mod rejects the mod, as name collisions do today.

### Async loading

- **States:** a load request returns a handle at once, with state `queued → loading → ready | failed`, plus `isReady(handle)` and `progress(group)`.
- **Threading:** a loader worker thread (the same pattern as the terrain `Streamer`) reads and decodes into staging memory. GPU upload happens on the render thread under a per-frame byte budget, sharing the terrain budget so a frame never stalls.
- **Groups:** load groups ("district", "shrine 0", "character set") report combined progress for loading screens and streaming.
- **Failure:** a failed load leaves the handle invalid and logs the reason; nothing crashes.

### Hot reload (development builds)

- **Watching:** a watcher polls source hashes (for sources with sidecars) about once a second and reruns the importer for changed sources.
- **Swapping:** the new output replaces the entry for the same GUID. The handle's generation is bumped, so stale handles fail safely, and users re-resolve by GUID. Swaps happen between frames under the render mutex.
- **Data assets:** blueprints, scenes (phase 15), and mod scripts reload the same way. A live machine keeps its state where the device layout is unchanged.

## Slices

1. **GUIDs, sidecars, manifest — implemented (2026-10-01).** Implemented:
   - **Code:** `Guid`, `Meta` (sidecar format, checks, `refresh`), `Registry` (manifest, binding, typed `Ref`), `zig build import`, sidecar checks in `asset-compiler compile`, and a build-generated, embedded `assets.manifest`.
   - **Content:** the crate and all nine blueprints have sidecars. Generated meshes resolve under derived GUIDs, and the catalog refuses to load with any unbound entry.

   Changes from the original plan:
   - **Saves:** saves already embed full blueprint documents and never refer to built-in content by path, so moving them to GUIDs was unnecessary. They will adopt references when scenes (phase 15) and networking (phase 16) need them.
   - **Shaders:** stay embedded source, not assets, until hot reload needs them.
   - **Missing sidecars:** a missing sidecar is reported by the Zig build cache as `file_hash FileNotFound` before the compiler can print its own instruction. A stale sidecar gets the full message.
2. **Packs and the async loader — implemented (2026-10-01).** Implemented:
   - **Packs:** `Pack` (the `HWPK` v1 format: a GUID table with offsets, sizes, and Blake3 hashes, plus 16-byte-aligned blobs). The table is validated on open, and each blob is verified on load.
   - **Loader:** `Loader`, a worker thread for pack entries, embedded bytes, and generator functions, with tickets, states, groups, progress, and stats.
   - **Catalog:** `Catalog.reserve` and `install` (handles valid before content arrives; installed under the render mutex).
   - **Renderer:** `StreamingScene.uploadMeshes` uploads under the `-Dasset-upload-kib` budget (default 4 MiB). One oversized mesh may go alone, so none starves, and split-screen views share the primary's GPU meshes.
   - **Deferred meshes:** the generated Arbor full and proxy meshes and the district mesh are now built by the loader. They are ready about 100–150 ms after start.

   Measured, and changes from the original plan:
   - **Deferral saves little today:** those builds take about 1 ms each in release, so moving them saves little startup time. The mechanism is what packs and hot reload use.
   - **Stress benchmark:** the planned 64 meshes of 10K–1M vertices would make a pack of roughly 600 MB per run, so the benchmark (`tools/benchmark.py --pack 64`) uses 1K–128K vertices (an 80 MiB pack).
   - **No shipped pack yet:** today's only compiled model (the crate) is core content and stays embedded. A content pack ships when there is content beyond the core set.
   - **Material pool:** the catalog's material pool (one per installed submesh) was raised from 64 to 256 after the stress run hit `PoolFull`.
3. **Hot reload — implemented (2026-10-01).** `-Dhot-reload=true` watches manifest model/blueprint sources and installed mod Wasm modules on a worker, including external glTF buffers and model scale settings. Results swap in `App.publish` under the render mutex. Models reuse their catalog slot with a new generation and staged materials; blueprint data updates retain state in compatible unmodified live machines; scripts retain their registered names with newly validated bytecode. Invalid edits preserve the working asset.

   Scope and deviations:
   - Mesh handles bump generations. Blueprint pointers remain stable, and script names stay registered; these systems do not use generational handles.
   - Physical layout/ID/kind changes and vehicle edits require restart. Locally edited machines and captured prefabs remain independent.
   - Development reload permits stale source hashes without writing `.meta`; the next build still requires `build import`. Changed importer versions are rejected until supported by the executable.
   - Watches follow known paths; a live rename requires a manifest rebuild/restart. Heightmaps, generated assets, textures, shaders, mod manifests and mod blueprints are outside this slice.
   - `-Dreload-smoke=true -Dsmoke-frames=600` edits an isolated crate fixture under `zig-out/reload-smoke`, checks stale-handle rejection and the changed material, and requires GPU readiness within two seconds. The Metal validation run completed in 848 ms.

## Acceptance

- Renaming or moving a source file keeps its GUID. Saves, scenes, and mods still resolve, and a test renames a fixture asset.
- Changing only import settings or the importer version reimports. An unchanged source does not, with counters asserted in a test.
- Unknown GUIDs, kind mismatches, colliding mod GUIDs, missing sidecars, and malformed settings are rejected before any state changes.
- Loading a pack of at least 64 assets (meshes of 10K–1M vertices) never pushes a measured frame over the render-CPU budget, with uploads within budget. Progress is monotonic and reaches 1.
- In a smoke run, editing a fixture model on disk swaps it within two seconds without a validation error. Stale handles fail safely, and re-resolved handles draw the new mesh.

## Risks

- **Generation bumps:** code that caches handles across frames must re-resolve. Mitigation: the generation check already exists, so stale use fails loudly in tests.
- **Concurrent swaps:** hot reload while the catalog is read on two threads. Mitigation: swap only under the render mutex, between snapshots, as `App.publish` already does.

**Out of scope:** an editor UI, texture compression, and audio import (textures and audio arrive when their systems do).
