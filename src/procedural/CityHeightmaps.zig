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
// The NYC raster has open water at its image center. Anchor the Hudson Reach arrival to
// the nearby low coastal pixel (785, 1010), keeping the skyline on land.
const nyc_anchor_x: f32 = (785.0 / 2047.0 - 0.5) * 160000;
const nyc_anchor_z: f32 = (1010.0 / 2047.0 - 0.5) * 160000;
// The Chicago source has no georeferencing. Anchor the map near its lakefront at an
// approximate downtown pixel; this preserves the dark Lake Michigan shelf east of arrival.
const chicago_anchor_x: f32 = (1200.0 / 2047.0 - 0.5) * 160000;
const chicago_anchor_z: f32 = (1000.0 / 2047.0 - 0.5) * 160000;
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
    const dx = x - detroit_center[0];
    const dz = z - detroit_center[1];
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
