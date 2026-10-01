# Heightmapped Landscapes

## Goal

Let designers start from a real elevation raster, then shape it into a deterministic playable landscape with distinct biomes, temple sites, and cave routes. Imported terrain must have one authoritative sampler shared by mesh generation, physics, placement, and gameplay queries. The existing canopy district remains unchanged until an opt-in landscape scene passes those contracts.

## Current Slice: Import and Authoring Primitives

Implemented in Zig:

- `asset-compiler heightmap <source.pgm> <output.hwmh> [world-width world-depth elevation base-height]` imports ASCII P2 and binary P5 PGM grayscale rasters. Eight- and sixteen-bit sources are normalized to 16-bit samples.
- `.pgm` assets participate in the existing sidecar flow: `zig build import` assigns/preserves GUIDs, hashes the source, and stores validated physical dimensions/elevation settings; `asset-compiler compile` checks freshness before emitting `HWMH`.
- `HWMH` format v1 stores dimensions, physical width/depth, base elevation, relief, and little-endian samples. The decoder validates the header, settings, and bounded dimensions.
- `procedural/Heightmap.zig` supplies centered, bilinear world-space sampling; raster row zero maps to negative Z.
- `procedural/Landscape.zig` layers fixed-capacity smooth stamps (plateau, basin, mound, ridge), classifies wetland/meadow/forest/alpine, and chooses deterministic buildable temple pads and cave entrances/routes from a world seed.
- `Landscape.generateChunk` meshes map-backed 128 m chunks; `Landscape.terrainSurface` uses the same shaped-height samples and the exact triangle split to return matching heights and face normals. Tests check map-edge seams and triangle-interior agreement.

Example:

```sh
python3 tools/zig.py build heightmap -- assets/source/heightmaps/valley.pgm .zig-cache/valley.hwmh 2048 2048 640 -20
```

`PGM` is the dependency-free first import format. PNG/TIFF conversion is not implemented; RGB images such as `assets/Earth.png` are not elevation data. The registry has typed heightmap references, but no source heightmap is yet included in the app manifest or bound by `Catalog`. Map-backed generation is not yet wired into the live `Terrain.surface`, streamer, renderer, physics, or Sandbox. Temple and cave outputs are placement/route data only; they are not yet meshes or colliders.

## Integration Slices

1. **Manifest and runtime binding:** include a chosen sidecar-backed heightmap in the generated manifest, let `Catalog` own/bind the decoded map, and load it through an explicit scene/landscape reference.
2. **One terrain source:** introduce an immutable landscape context consumed by the streamer, `Terrain.surface`, physics, picking, placement, props, and vehicles. Keep the current seeded terrain as the default fallback. The isolated map mesher/query already agrees; prove agreement through the real worker and gameplay paths before opting in a scene.
3. **Biome composition and erosion:** combine imported elevation with deterministic noise, moisture, slope, and authored biome masks; support terraces, saddles, river basins, ridges, and erosion passes with versioned settings. Keep stamps bounded and reproducible.
4. **Temples and caves:** place temples only on validated pads with access routes and clearance, then compile them through the existing blueprint/shrine solver pipeline. Turn cave routes into bounded mesh/triangle-collider segments with entrances, chambers, branches, and exits; verify navigation and rescue/loot encounters headlessly.
5. **Playable landscape slice:** add one opt-in mountain/river biome map, a reachable solver-verified temple, and a cave loop to a new scene. Test walk, traversal, physics, save/load, deterministic regeneration, chunk boundaries, and memory limits before expanding the world.

## Acceptance

- P2/P5 importer tests cover 8/16-bit data, comments, malformed headers, overflow dimensions, and truncated rasters.
- Imported assets round-trip without changing a sample; world-space corner/center samples match expected heights.
- The same map, settings, seed, and generator version produce identical shaped samples, biome masks, and feature sites.
- A shaped temple pad meets the project build-placement slope limit and has a clear approach. Cave paths remain underground, connect their chambers, and have traversable slopes/clearance.
- For every tested position, physics height/normal agrees with the triangles generated for that chunk, including negative coordinates and adjacent map/chunk edges.
- The new landscape runs as an opt-in scene; the existing city fixture and acceptance suite remain unchanged.
