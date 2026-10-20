//! Approximate, exaggerated terrain profiles for playable city regions with heightmap sources.
const Heightmap = @import("Heightmap.zig");
const Noise = @import("Noise.zig");
const Region = @import("../world/Region.zig");
const ChunkKey = @import("../world/ChunkKey.zig");

const detroit_bytes = @embedFile("../assets/detroit_terrain.hwmh");
const nyc_bytes = @embedFile("../assets/nyc_terrain.hwmh");
const chicago_bytes = @embedFile("../assets/chicago_terrain.hwmh");
const antarctica_bytes = @embedFile("../assets/antarctica_terrain.hwmh");
const detroit_map = Heightmap.view(detroit_bytes) catch unreachable;
const nyc_map = Heightmap.view(nyc_bytes) catch unreachable;
const chicago_map = Heightmap.view(chicago_bytes) catch unreachable;
const antarctica_map = Heightmap.view(antarctica_bytes) catch unreachable;

const detroit_center = Region.detroit.arrival;
const nyc_center = Region.new_york.arrival;
const chicago_center = Region.chicago.arrival;
const antarctica_center = Region.antarctica.arrival;
// These source PNGs have no embedded georeferencing, so map their documented export
// bounds to the downtown arrivals. The bounds are the active EPSG:4326 boxes in the
// terrain-generation instructions; row zero is north, matching Heightmap.sample's -Z.
// X is linear in longitude; Y uses Web Mercator because the export images use EPSG:3857.
// Detroit downtown (42.3314, -83.0458), bbox (-83.68, 42.05, -82.70, 42.75).
const detroit_anchor_x: f32 = 17657.14;
const detroit_anchor_z: f32 = 11920.73;
// Lower Manhattan / NYC downtown (40.7128, -74.0060), bbox (-74.45, 40.45, -73.55, 41.12).
const nyc_anchor_x: f32 = -1066.67;
const nyc_anchor_z: f32 = 17433.96;
// Chicago downtown (41.8781, -87.6298), bbox (-88.30, 41.50, -87.30, 42.24).
const chicago_anchor_x: f32 = 27232.0;
const chicago_anchor_z: f32 = -1519.90;
// This continent raster has no georeferencing; use its center as the subglacial Hive landing.
const antarctica_anchor_x: f32 = 0;
const antarctica_anchor_z: f32 = 0;
const blend_width: f32 = 9000;

pub fn heightAt(seed: u64, x: f32, z: f32) f32 {
    const key = ChunkKey.fromPosition(x, z);
    if (Region.new_york.contains(key.x, key.z)) {
        if (sampleMap(nyc_map, x - nyc_center[0] + nyc_anchor_x, z - nyc_center[1] + nyc_anchor_z)) |height| {
            return blendToFallback(nyc_map, x - nyc_center[0] + nyc_anchor_x, z - nyc_center[1] + nyc_anchor_z, height, seed, x, z);
        }
    }
    if (Region.chicago.contains(key.x, key.z)) {
        if (sampleMap(chicago_map, x - chicago_center[0] + chicago_anchor_x, z - chicago_center[1] + chicago_anchor_z)) |height| {
            return blendToFallback(chicago_map, x - chicago_center[0] + chicago_anchor_x, z - chicago_center[1] + chicago_anchor_z, height, seed, x, z);
        }
    }
    if (Region.antarctica.contains(key.x, key.z)) {
        if (sampleMap(antarctica_map, x - antarctica_center[0] + antarctica_anchor_x, z - antarctica_center[1] + antarctica_anchor_z)) |height| {
            return blendToFallback(antarctica_map, x - antarctica_center[0] + antarctica_anchor_x, z - antarctica_center[1] + antarctica_anchor_z, height, seed, x, z);
        }
    }
    const dx = x - detroit_center[0] + detroit_anchor_x;
    const dz = z - detroit_center[1] + detroit_anchor_z;
    if (sampleMap(detroit_map, dx, dz)) |height| return blendToFallback(detroit_map, dx, dz, height, seed, x, z);
    return fallbackHeight(seed, x, z);
}

fn sampleMap(map: Heightmap.View, x: f32, z: f32) ?f32 {
    return map.sample(x, z);
}

fn blendToFallback(map: Heightmap.View, x: f32, z: f32, mapped: f32, seed: u64, world_x: f32, world_z: f32) f32 {
    const half_x = map.settings.world_width * 0.5;
    const half_z = map.settings.world_depth * 0.5;
    const edge = @min(half_x - @abs(x), half_z - @abs(z));
    if (edge >= blend_width) return mapped;
    const fallback = fallbackHeight(seed, world_x, world_z);
    const t = @import("std").math.clamp(edge / blend_width, 0, 1);
    const weight = t * t * (3 - 2 * t);
    return fallback + (mapped - fallback) * weight;
}

fn fallbackHeight(seed: u64, x: f32, z: f32) f32 {
    return Noise.height(Region.seedAtPosition(seed, x, z), x, z);
}
