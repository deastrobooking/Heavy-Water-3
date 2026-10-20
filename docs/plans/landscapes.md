# Heightmapped Landscapes

## Goal

Let designers start from a real elevation raster, then shape it into a deterministic playable landscape with distinct biomes, temple sites, and cave routes. Imported terrain must have one authoritative sampler shared by mesh generation, physics, placement, and gameplay queries. The existing canopy district remains unchanged until an opt-in landscape scene passes those contracts.

## Current Slice: City Heightmaps in the Playable World

Implemented in Zig:

- `asset-compiler heightmap <source> <output.hwmh> [world-width world-depth elevation base-height]` imports ASCII P2 and binary P5 PGM rasters, plus 16-bit grayscale non-interlaced PNG rasters. Eight- and sixteen-bit PGM sources are normalized to 16-bit samples.
- `.pgm` and `*_heightmap_16bit.png` assets participate in the existing sidecar flow: `zig build import` assigns/preserves GUIDs, hashes the source, and stores validated physical dimensions/elevation settings; `asset-compiler compile` checks freshness before emitting `HWMH`.
- `HWMH` format v1 stores dimensions, physical width/depth, base elevation, relief, and little-endian samples. The decoder validates the header, settings, and bounded dimensions.
- `procedural/Heightmap.zig` supplies centered, bilinear world-space sampling; raster row zero maps to negative Z.
- `procedural/Landscape.zig` layers fixed-capacity smooth stamps (plateau, basin, mound, mountain, ridge), classifies wetland/meadow/forest/alpine, and chooses deterministic buildable temple pads and cave entrances/routes from a world seed. Mountain stamps use a sharper smooth radial profile than mounds; neither creates a discontinuity at the stamp edge.
- `Landscape.generateChunk` meshes map-backed 128 m chunks; `Landscape.terrainSurface` uses the same shaped-height samples and the exact triangle split to return matching heights and face normals. Tests check map-edge seams and triangle-interior agreement.

Example:

```sh
python3 tools/zig.py build heightmap -- assets/source/heightmaps/valley.pgm .zig-cache/valley.hwmh 2048 2048 640 -20
```

Detroit and New York now use the supplied grayscale rasters in live chunk generation, `Terrain.surface`, and scattered ground object placement, so terrain collision, props, and rendered ground agree. The rasters have no georeferencing; Detroit is centered around the existing Detroit arrival at a 120 km square with 380 m relief, while the New York raster is aligned to a low coastal pixel around the Hudson Reach arrival at a 160 km square with 700 m relief. These elevations intentionally exaggerate the source shapes for a playable, Hive-terraformed future. Both maps blend to seeded terrain over the outer 9 km. New York streams in a distinct region about 250 km east of Detroit, within the current world coordinate limit. Los Angeles and Chicago maps remain source assets awaiting their own playable regions. The map binding is currently a built-in read-only runtime module rather than a user-selectable scene reference. Water rendering does not yet use map data. Temple and cave outputs remain placement/route data only; they are not yet meshes or colliders.

## Integration Slices

1. **Generalized runtime binding:** include sidecar-backed heightmaps in the generated manifest and expose them through explicit scene/landscape references instead of built-in city bindings.
2. **One terrain source:** extend the current shared city height sampler to scatter, vegetation placement, and other ground consumers. Keep seeded terrain as the default fallback and prove agreement through worker, physics, picking, props, and vehicles.
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
