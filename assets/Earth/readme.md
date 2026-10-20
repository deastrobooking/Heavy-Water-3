# Planetary & Urban Terrain Pipeline (`planet-earth-pipeline`)

A comprehensive, automated Python toolkit for fetching, processing, and normalizing global Digital Elevation Models (DEMs) into true 16-bit grayscale PNG heightmaps and scale-factor JSON manifests for custom game engines, graphics renderers, and 3D simulations.

---

## Features

* **Global & Regional Coverage:** Ingests data from USGS 3DEP (North America), PGC REMA v2 (Antarctica), and AWS Open Data Global Terrain Tiles (Worldwide/Asia/Europe).
* **Multi-Scale Pipelines:** Supports everything from 60km × 60km regional urban metro bounding boxes to full-planet equirectangular projections and high-relief mountain/alien stronghold biomes.
* **16-Bit Precision (`0 – 65535`):** Eliminates stair-stepping and terracing by utilizing the full unsigned integer range, mapping sub-meter vertical elevation profiles accurately.
* **Engine-Ready Manifests:** Automatically computes physical footprint dimensions and precise `z_to_x_ratio` multipliers, allowing shaders to apply correct real-world vertical displacement instantly.

---

## Directory Structure

When running the generator scripts, output files and JSON manifests are organized as follows:

```text
├── planet_earth_heightmaps/
│   ├── earth_topobathy_16bit.png       # Full crust relief (Mariana Trench to Everest)
│   ├── earth_land_only_16bit.png       # Landmasses only (Ocean clamped to 0)
│   ├── earth_land_mask_8bit.png        # Binary water/land mask (0/255)
│   └── planet_earth_manifest.json      # Global scale metrics & sea-level indices
│
├── top50_world_cities_heightmaps/
│   ├── 01_tokyo_16bit.png
│   ├── ...
│   └── top50_world_cities_manifest.json # Regional footprints & z-ratios
│
└── alien_strongholds_heightmaps/
    ├── 01_eye_of_the_sahara_16bit.png
    ├── ...
    └── alien_strongholds_manifest.json
Working with JSON ManifestsEvery batch script outputs a structured JSON manifest file (*_manifest.json) that links each generated 16-bit PNG heightmap to its exact physical world coordinates and scaling metrics.Example Manifest Schema (next20_us_cities_manifest.json or regional manifests)JSON{
  "01_seattle": {
    "name": "Seattle-Tacoma, WA",
    "file": "11_seattle_16bit.png",
    "center_lat": 47.6062,
    "center_lon": -122.3321,
    "clamped_floor_m": 0.0,
    "dem_min_elevation_m": 0.0,
    "dem_max_elevation_m": 1450.5,
    "vertical_relief_m": 1450.5,
    "footprint_width_m": 44782.12,
    "footprint_height_m": 44782.12,
    "z_to_x_ratio": 0.032389
  }
}
Key Fields for Your Engine:file: The filename of the 16-bit grayscale PNG texture.vertical_relief_m: The total vertical delta ($max - min$) represented between black (0) and white (65535) in the heightmap.z_to_x_ratio: The critical scaling factor. Multiplying your mesh's horizontal world width ($W$) by this ratio yields the exact vertical height ($H_z$) required for true 1:1 real-world proportion:$$\text{MaxDisplacement} = W \times \text{z\_to\_x\_ratio}$$Integrating Heightmaps in Your Engine (Shader Guide)To decode 16-bit PNG heightmaps without banding or quantization artifacts, load the texture as an R16Unorm (or integer format) in your graphics pipeline.WGSL Vertex Displacement Example (WebGPU)Code snippet@group(0) @binding(0) var heightMap: texture_2d<f32>;
@group(0) @binding(1) var heightSampler: sampler;

struct Uniforms {
    z_scale_factor: f32,
};
@group(0) @binding(2) var<uniform> uniforms: Uniforms;

@vertex
fn main(@location(0) position: vec3<f32>) -> @builtin(position) vec4<f32> {
    // Sample 16-bit height value from the red channel (normalized 0.0 to 1.0)
    let heightSample = textureSampleLevel(heightMap, heightSampler, position.xz, 0.0).r;
    
    // Displace vertex along the Y axis using the manifest's z_to_x_ratio
    var displacedPosition = position;
    displacedPosition.y += heightSample * uniforms.z_scale_factor;
    
    return vec4<f32>(displacedPosition, 1.0);
}
Global Equirectangular UV Mapping (Planet Earth)When mapping earth_land_only_16bit.png or earth_topobathy_16bit.png onto a 3D sphere, use standard Equirectangular UV mapping equations derived from geographic coordinates $(\text{lat}, \text{lon})$:Python# Convert Latitude/Longitude to UV Texture Coordinates [0.0, 1.0]
u = (longitude + 180.0) / 360.0
v = (90.0 - latitude) / 180.0

For global topobathy maps, consult `planet_earth_manifest.json` for the elevation range and sea-level encoding.

## Heavy Water integration status

The three metro rasters currently used by the game are stored at `assets/{detroit,nyc,chicago}_metro_heightmap_16bit.png`. Their export instructions specify geographic bounds, but the PNG files do not retain georeferencing metadata. The game records the active bounds and downtown anchor offsets in `src/procedural/CityHeightmaps.zig`; re-export is not needed to align the existing Detroit, NYC, or Chicago arrivals. If a raster is regenerated with a different bbox (including NYC's tighter alternate bbox), update those offsets too.

The global `earth_land_only_16bit.png`, `earth_topobathy_16bit.png`, and `earth_land_mask_8bit.png` are not currently sampled by the in-game globe, which still uses a coarse procedural land outline. `planet_earth_manifest.json` describes the global map's projection and elevation range; these files are not metro heightmaps and should not be substituted into the local terrain importer.
