//! Art-led high alpine basin inside the playable K2 region. All masks and cuts use world-space
//! coordinates so terrain, collision, water and scatter agree across streamed chunk boundaries.
const std = @import("std");
const Noise = @import("Noise.zig");
const Region = @import("../world/Region.zig");

pub const arrival: [2]f32 = .{ Region.k2.arrival[0] + 800, Region.k2.arrival[1] + 600 };
pub const grove_center: [2]f32 = .{ arrival[0] - 110, arrival[1] + 145 };

const basin_inner_radius: f32 = 1180;
const basin_outer_radius: f32 = 2200;
const stream_start: f32 = Region.k2.arrival[0] + 80;
const stream_end: f32 = Region.k2.arrival[0] + 1820;
const stream_half_width: f32 = 10.5;
const channel_half_width: f32 = 27;
const bed_depth: f32 = 9;
const water_depth: f32 = 6.6;
const fall_x = [_]f32{
    Region.k2.arrival[0] + 360,
    Region.k2.arrival[0] + 840,
    Region.k2.arrival[0] + 1320,
};
const fall_drop = [_]f32{ 7.5, 6.5, 8 };

pub fn falls() []const f32 {
    return &fall_x;
}

pub fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0, 1);
    return t * t * (3 - 2 * t);
}

/// The basin keeps a broad, sheltered core and eases into the surrounding K2 glacier.
pub fn basinWeight(x: f32, z: f32) f32 {
    const dx = x - arrival[0];
    const dz = z - arrival[1];
    const radius = @sqrt(dx * dx + dz * dz);
    return 1 - smoothstep(basin_inner_radius, basin_outer_radius, radius);
}

pub fn isSheltered(x: f32, z: f32) bool {
    return basinWeight(x, z) > 0.04;
}

pub fn groveWeight(x: f32, z: f32) f32 {
    const dx = x - grove_center[0];
    const dz = z - grove_center[1];
    const radius = @sqrt(dx * dx + dz * dz);
    return 1 - smoothstep(68, 195, radius);
}

fn streamStartWeight(x: f32) f32 {
    return smoothstep(stream_start - 90, stream_start + 30, x) * (1 - smoothstep(stream_end - 30, stream_end + 100, x));
}

pub fn streamCenterZ(_: u64, x: f32) f32 {
    const local_x = x - Region.k2.arrival[0];
    const broad = @sin(local_x / 260 + 0.55) * 17;
    const meander = (Noise.value(0x434c4f5544574154, local_x / 180, 0.31) - 0.5) * 12;
    return Region.k2.arrival[1] + 600 + broad + meander;
}

pub fn streamHalfWidth(x: f32) f32 {
    const end = @min(smoothstep(stream_start, stream_start + 90, x), 1 - smoothstep(stream_end - 90, stream_end, x));
    return stream_half_width * end;
}

pub fn streamActive(x: f32) bool {
    return x >= stream_start and x <= stream_end;
}

pub fn streamContains(seed: u64, x: f32, z: f32) bool {
    if (!streamActive(x)) return false;
    const half = streamHalfWidth(x);
    return half > 0 and @abs(z - streamCenterZ(seed, x)) <= half;
}

pub fn cumulativeFalls(x: f32) f32 {
    var drop: f32 = 0;
    for (fall_x, fall_drop) |at, depth| drop += depth * smoothstep(at - 3, at + 3, x);
    return drop;
}

/// Carves a narrow stream bed with three authored icefall steps into the imported K2 raster.
/// The edge fades at both ends and where the basin meets exposed high glacier.
pub fn carve(seed: u64, x: f32, z: f32, base: f32) f32 {
    if (!streamActive(x)) return base;
    const dist = @abs(z - streamCenterZ(seed, x));
    if (dist >= channel_half_width) return base;
    const across = 1 - smoothstep(0, channel_half_width, dist);
    const basin = basinWeight(x, z);
    const amount = (bed_depth + cumulativeFalls(x)) * across * streamStartWeight(x) * basin;
    return base - amount;
}

/// Level of the animated water surface from the already-carved stream-bed height.
pub fn waterLevel(bed: f32) f32 {
    return bed + water_depth;
}

pub fn isFall(seed: u64, x: f32, z: f32) ?usize {
    if (!streamContains(seed, x, z)) return null;
    for (fall_x, 0..) |at, i| if (@abs(x - at) <= 1.1) return i;
    return null;
}

/// World-space albedo recipe: icy blue channels, weathered slate faces, pale marble shelves,
/// snow pockets and three scales of soft mineral grain derived from the clay reference colors.
pub fn terrainColor(seed: u64, x: f32, z: f32, base: [3]f32, snow: f32, slope: f32) [3]f32 {
    const influence = basinWeight(x, z);
    if (influence <= 0) return base;

    const broad = Noise.value(seed ^ 0x4d4152424c4531, x / 92, z / 92);
    const grain = Noise.value(seed ^ 0x49434547524149, x / 18, z / 18);
    const fleck = Noise.value(seed ^ 0x4d494e4552414c, x / 5.5, z / 5.5);
    const strata = smoothstep(0.37, 0.66, 0.58 * broad + 0.3 * grain + 0.12 * fleck);
    const rock_face = smoothstep(0.08, 0.72, slope);
    const slate = [3]f32{ 0.24, 0.34, 0.42 };
    const marble = [3]f32{ 0.72, 0.79, 0.81 };
    const blue_ice = [3]f32{ 0.29, 0.55, 0.68 };
    const snow_color = [3]f32{ 0.82, 0.91, 0.96 };
    var local: [3]f32 = undefined;
    for (&local, 0..) |*channel, i| {
        const mineral = slate[i] * (1 - strata) + marble[i] * strata;
        const weathered = blue_ice[i] * (1 - rock_face) + mineral * rock_face;
        const mottled = weathered * (0.92 + 0.14 * grain + 0.08 * fleck);
        channel.* = mottled * (1 - snow * 0.86) + snow_color[i] * snow * 0.86;
    }
    return .{
        base[0] * (1 - influence) + local[0] * influence,
        base[1] * (1 - influence) + local[1] * influence,
        base[2] * (1 - influence) + local[2] * influence,
    };
}

test "Cloudwater basin is local and has a stable, sheltered stop and golden grove" {
    try std.testing.expectApproxEqAbs(@as(f32, 1), basinWeight(arrival[0], arrival[1]), 0.0001);
    try std.testing.expect(basinWeight(arrival[0] + 2500, arrival[1]) == 0);
    try std.testing.expect(isSheltered(grove_center[0], grove_center[1]));
    try std.testing.expect(groveWeight(grove_center[0], grove_center[1]) == 1);
    try std.testing.expect(groveWeight(arrival[0] + 600, arrival[1] + 600) == 0);
}

test "Cloudwater channel cuts a continuous bed and keeps three authored icefall drops" {
    const seed: u64 = 42;
    const x = fall_x[0] - 40;
    const z = streamCenterZ(seed, x);
    try std.testing.expect(carve(seed, x, z, 100) < 100);
    try std.testing.expectEqual(@as(f32, 100), carve(seed, x, z + 60, 100));
    try std.testing.expectApproxEqAbs(fall_drop[0], cumulativeFalls(fall_x[0] + 4) - cumulativeFalls(fall_x[0] - 4), 0.01);
    try std.testing.expect(streamContains(seed, fall_x[1], streamCenterZ(seed, fall_x[1])));
    try std.testing.expect(!streamContains(seed, Region.k2.arrival[0] - 100, streamCenterZ(seed, Region.k2.arrival[0] - 100)));
}
