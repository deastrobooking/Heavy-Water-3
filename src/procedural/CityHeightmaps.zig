//! Approximate, exaggerated terrain profiles for playable city regions with heightmap sources.
const Heightmap = @import("Heightmap.zig");
const Noise = @import("Noise.zig");
const Mountains = @import("Mountains.zig");
const CityGeography = @import("CityGeography.zig");
const Region = @import("../world/Region.zig");
const ChunkKey = @import("../world/ChunkKey.zig");

const detroit_bytes = @embedFile("../assets/detroit_terrain.hwmh");
const nyc_bytes = @embedFile("../assets/nyc_terrain.hwmh");
const chicago_bytes = @embedFile("../assets/chicago_terrain.hwmh");
const antarctica_bytes = @embedFile("../assets/antarctica_terrain.hwmh");
const k2_bytes = @embedFile("../assets/k2_terrain.hwmh");
const detroit_map = Heightmap.view(detroit_bytes) catch unreachable;
const nyc_map = Heightmap.view(nyc_bytes) catch unreachable;
const chicago_map = Heightmap.view(chicago_bytes) catch unreachable;
const antarctica_map = Heightmap.view(antarctica_bytes) catch unreachable;
const k2_map = Heightmap.view(k2_bytes) catch unreachable;

const detroit_center = Region.detroit.arrival;
const nyc_center = Region.new_york.arrival;
const chicago_center = Region.chicago.arrival;
const antarctica_center = Region.antarctica.arrival;
const k2_center = Region.k2.arrival;
// Source row zero is north, mapping to negative Z in Heightmap.sample.
const detroit_anchor_x = (CityGeography.detroit_raster_anchor.anchor_u - 0.5) * detroit_map.settings.world_width;
const detroit_anchor_z = (CityGeography.detroit_raster_anchor.anchor_v - 0.5) * detroit_map.settings.world_depth;
const nyc_anchor_x = (CityGeography.new_york_raster_anchor.anchor_u - 0.5) * nyc_map.settings.world_width;
const nyc_anchor_z = (CityGeography.new_york_raster_anchor.anchor_v - 0.5) * nyc_map.settings.world_depth;
const chicago_anchor_x = (CityGeography.chicago_raster_anchor.anchor_u - 0.5) * chicago_map.settings.world_width;
const chicago_anchor_z = (CityGeography.chicago_raster_anchor.anchor_v - 0.5) * chicago_map.settings.world_depth;
// This continent raster has no georeferencing; use its center as the subglacial Hive landing.
const antarctica_anchor_x: f32 = 0;
const antarctica_anchor_z: f32 = 0;
const k2_anchor_x = (CityGeography.k2_raster_anchor.anchor_u - 0.5) * k2_map.settings.world_width;
const k2_anchor_z = (CityGeography.k2_raster_anchor.anchor_v - 0.5) * k2_map.settings.world_depth;
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
    if (Region.k2.contains(key.x, key.z)) {
        const mx = x - k2_center[0] + k2_anchor_x;
        const mz = z - k2_center[1] + k2_anchor_z;
        if (sampleMap(k2_map, mx, mz)) |height| return blendToFallback(k2_map, mx, mz, height, seed, x, z);
    }
    const dx = x - detroit_center[0] + detroit_anchor_x;
    const dz = z - detroit_center[1] + detroit_anchor_z;
    // The four procedural mountain ranges ring the hub (1.3 to 1.7 km out, nothing beyond 2.6 km).
    // The raster replaced the noise terrain they were added to, so lay them back on top: their
    // caves, nests and the cave tests were authored against this relief.
    if (sampleMap(detroit_map, dx, dz)) |height| return blendToFallback(detroit_map, dx, dz, height, seed, x, z) + Mountains.height(seed, x, z);
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
