# Heightmapped Landscapes

## Goal

Let designers start from a real elevation raster, then shape it into a deterministic playable landscape with distinct biomes, temple sites, and cave routes. Imported terrain must have one authoritative sampler shared by mesh generation, physics, placement, and gameplay queries. Separate named regions can add mapped landscapes without changing the existing canopy district.

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

Detroit, New York and Chicago use the supplied grayscale rasters in live chunk generation, `Terrain.surface`, and scattered ground object placement, so terrain collision, props, and rendered ground agree. Their source PNGs do not embed georeferencing, but the generation instructions provide the active geographic export bounds. `procedural/CityGeography.zig` is the shared coordinate record for globe markers and terrain anchors. The runtime maps those bounds to each city's downtown arrival: Detroit (42.3314, -83.0458), Lower Manhattan (40.7128, -74.0060), and Chicago (41.8781, -87.6298). Longitude maps west-to-east; Web Mercator latitude maps north-to-south, matching raster row zero at negative Z. This fixes the earlier guessed NYC/Chicago pixels and Detroit image-center anchor without re-exporting the rasters. The imported 120 km Detroit and 160 km NYC/Chicago square footprints and 380/700/550 m relief remain deliberate gameplay exaggerations rather than literal source scale. NYC currently assumes the wider bbox; selecting the tight alternate bbox requires new anchor fractions in `CityGeography.zig`. These four metro source rasters now live in `assets/CitiesUSA/`; LA is still source-only.

Antarctica has a 160 km square, 1,200 m-relief playable landing sourced from `antarctica_continent_heightmap_16bit.png`; it is anchored at the raster center and blends to seeded terrain over the outer 9 km. The corrected raster replaces a zero-valued spawn-center depression with an approximately 596 m center elevation at the current −200 m base and 1,200 m relief settings. Its arrival is at z −420 km, within the current world coordinate limit and separated from the North American regions. The continent raster has no georeferencing, so this is a playable subglacial-base sampling area rather than a literal continent-scale map. NYC, Chicago, Antarctica and K2 stream as distinct regions around Detroit. Los Angeles remains a source raster awaiting its playable region. The global equirectangular Earth maps in `assets/Earth/` are not yet connected to runtime globe rendering; the globe still draws a coarse procedural land outline. The map binding is currently a built-in read-only runtime module rather than a user-selectable scene reference. Water rendering does not yet use map data. Chicago and Antarctica have terrain-backed landings, but their city districts, missions, and liberation loops remain future work. The separate `Landscape` module's temple and cave route outputs remain placement data; K2's live cave mesh and colliders are implemented through the existing `Caves` system.

K2 is the first active mountain site. The 30 km imported raster is anchored to the K2 coordinate and streamed in its own Earth region about 380 km from Detroit. Its sampled height drives both terrain mesh and collision; the alpine-glacier palette keeps the landing snow- and ice-covered, with vegetation suppressed. The landing connects to the six-room Black-Summit Works below the glacier. It uses the existing cave mesh/collider and encounter path, with cyan-lit mechworks framing, Scalari guards, and a persistent Titan defeat that awards personal combat XP and Scalari materials. The globe includes K2 as an expedition marker. Other mountain and stronghold recipes remain catalog data; their terrain, bases, enemies, objectives, and rewards are not live yet.

`procedural/TerrainSites.zig` catalogs all ten mountain rasters, six alien-stronghold rasters, and 24 US city entries (four current metros plus the twenty-city manifest) with source coordinates, footprint/relief, biome identity, faction, hazards, traversal hooks, enemy-role rosters, named bosses, and facility archetypes. Thirty-six of those forty entries have source heightmaps in the checkout; Phoenix, Seattle-Tacoma, St. Louis, and Charlotte are in the city manifest but have no PNG yet. The recipes assign content for design and code generation; only K2 currently activates a mountain raster and encounter. `Interiors` provides connected district/base room graphs, but those grammars are still authoring data rather than rendered, collidable bases. Existing caves plus K2's authored six-room extension remain the only live mountain dungeon implementation.

## Integration Slices

1. **Generalized runtime binding:** include sidecar-backed heightmaps in the generated manifest and expose them through explicit scene/landscape references instead of built-in city bindings.
2. **One terrain source:** extend the current shared city height sampler to scatter, vegetation placement, and other ground consumers. Keep seeded terrain as the default fallback and prove agreement through worker, physics, picking, props, and vehicles.
3. **Biome composition and erosion:** combine imported elevation with deterministic noise, moisture, slope, and authored biome masks; support terraces, saddles, river basins, ridges, and erosion passes with versioned settings. Keep stamps bounded and reproducible.
4. **Temples and caves:** place temples only on validated pads with access routes and clearance, then compile them through the existing blueprint/shrine solver pipeline. Turn cave routes into bounded mesh/triangle-collider segments with entrances, chambers, branches, and exits; verify navigation and rescue/loot encounters headlessly.
5. **Playable landscape slice:** K2 now activates an imported mountain heightmap, alpine ice palette, six connected underground rooms, existing cave collision, Scalari guards, a persistent boss, and personal rewards. Next, smoke-test the complete landing-to-heart route and defeat/save behavior by hand, then use the same integration pattern for another site only after those checks pass.

## Acceptance

- P2/P5 importer tests cover 8/16-bit data, comments, malformed headers, overflow dimensions, and truncated rasters.
- Imported assets round-trip without changing a sample; world-space corner/center samples match expected heights.
- The same map, settings, seed, and generator version produce identical shaped samples, biome masks, and feature sites.
- A shaped temple pad meets the project build-placement slope limit and has a clear approach. Cave paths remain underground, connect their chambers, and have traversable slopes/clearance.
- For every tested position, physics height/normal agrees with the triangles generated for that chunk, including negative coordinates and adjacent map/chunk edges.
- The new landscape runs as an opt-in scene; the existing city fixture and acceptance suite remain unchanged.
