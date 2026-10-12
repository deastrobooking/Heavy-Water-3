//! Seeded, chunk-independent rivers. Channels flow east through a gently meandering valley;
//! periodic level drops become short waterfall curtains in the streamed chunk mesh.
const std = @import("std");
const Seed = @import("Seed.zig");
const Noise = @import("Noise.zig");

pub const lane_spacing: f32 = 1000;
pub const lane_offset: f32 = 500;
pub const channel_width: f32 = 10;
pub const water_width: f32 = 7.2;
pub const fall_period: f32 = 1400;
pub const fall_drop: f32 = 4.5;
const detroit_lane: i64 = 0;
const detroit_full_width_half: f32 = 170;
const belle_isle_half_x: f32 = 245;
const belle_isle_half_z: f32 = 68;

/// Detroit's river is a wide local waterway, tapering back into the ordinary seeded channel
/// outside the city region. Other river lanes and distant worlds retain their original banks.
fn detroitFactor(lane: i64, x: f32) f32 {
    if (lane != detroit_lane) return 0;
    const distance = @abs(x);
    if (distance <= 620) return 1;
    if (distance >= 1000) return 0;
    const t = (1000 - distance) / 380;
    return t * t * (3 - 2 * t);
}

pub fn channelHalfWidth(lane: i64, x: f32) f32 {
    return channel_width + (detroit_full_width_half - channel_width) * detroitFactor(lane, x);
}

pub fn surfaceHalfWidth(lane: i64, x: f32) f32 {
    return water_width * 0.5 + (detroit_full_width_half - water_width * 0.5) * detroitFactor(lane, x);
}

/// Cross-river half-width of Belle Isle at this point along the river. Zero outside the island.
pub fn belleIsleHalfWidth(x: f32) f32 {
    const t = x / belle_isle_half_x;
    if (@abs(t) >= 1) return 0;
    return belle_isle_half_z * @sqrt(1 - t * t);
}

fn islandCarveFactor(x: f32, z: f32, center: f32) f32 {
    const nx = x / belle_isle_half_x;
    const nz = (z - center) / belle_isle_half_z;
    const radius = @sqrt(nx * nx + nz * nz);
    if (radius <= 1) return 0;
    if (radius >= 1.2) return 1;
    const t = (radius - 1) / 0.2;
    return t * t * (3 - 2 * t);
}

pub fn centerZ(seed: u64, lane: i64, x: f32) f32 {
    const lane_seed = Seed.mix(seed ^ @as(u64, @bitCast(lane)) ^ 0x5249564552);
    const phase = Seed.unit(lane_seed) * 6.2831853;
    const broad = @sin(x / 185 + phase) * 25;
    const fine = (Noise.value(lane_seed, x / 90, 0.31) - 0.5) * 18;
    return lane_offset + @as(f32, @floatFromInt(lane)) * lane_spacing + broad + fine;
}

/// Flow level decreases downstream and takes a distinct seeded drop at waterfall sites.
pub fn level(seed: u64, lane: i64, x: f32) f32 {
    const lane_seed = Seed.mix(seed ^ @as(u64, @bitCast(lane)) ^ 0x464c4f57);
    const phase = @floor(Seed.unit(lane_seed) * fall_period / 4) * 4;
    const event = @floor((x + phase) / fall_period);
    const bedrock = Noise.baseHeight(seed, x, centerZ(seed, lane, x));
    const rolling = (Noise.value(lane_seed, x / 420, 0.7) - 0.5) * 0.45;
    return bedrock - 1.15 - x * 0.0004 + rolling - event * fall_drop;
}

pub fn carvedHeight(seed: u64, x: f32, z: f32, base: f32) f32 {
    const nearest: i64 = @intFromFloat(@round((z - lane_offset) / lane_spacing));
    const center = centerZ(seed, nearest, x);
    const distance = @abs(z - center);
    const width = channelHalfWidth(nearest, x);
    if (distance >= width) return base;
    const t = 1 - distance / width;
    const weight = t * t * (3 - 2 * t) * islandCarveFactor(x, z, center);
    const bed = level(seed, nearest, x) - 1.35;
    return @min(base, base + (bed - base) * weight);
}

/// The river surface over (x, z), or null on dry ground. Waterfall curtains are not included.
pub fn waterAt(seed: u64, x: f32, z: f32) ?f32 {
    const nearest: i64 = @intFromFloat(@round((z - lane_offset) / lane_spacing));
    const center = centerZ(seed, nearest, x);
    if (@abs(z - center) > surfaceHalfWidth(nearest, x)) return null;
    if (nearest == detroit_lane and islandCarveFactor(x, z, center) == 0) return null;
    return level(seed, nearest, x);
}

pub fn color() [3]f32 {
    return .{ 0.12, 0.57, 0.68 };
}

test "river channels and flow are continuous at chunk boundaries and drop at falls" {
    const z = centerZ(42, 0, 128);
    try std.testing.expectApproxEqAbs(z, centerZ(42, 0, 128.001), 0.01);
    try std.testing.expect(carvedHeight(42, 128, z, 80) < 80);
    const lane_seed = Seed.mix(42 ^ 0x464c4f57);
    const phase = @floor(Seed.unit(lane_seed) * fall_period / 4) * 4;
    const event_x = fall_period - phase;
    try std.testing.expectApproxEqAbs(fall_drop, level(42, 0, event_x - 0.01) - level(42, 0, event_x + 0.01), 0.1);
}

test "the river surface lies over the carved channel and nowhere else" {
    const x: f32 = 1500; // Outside Detroit's local wide-water segment.
    const z = centerZ(42, 0, x);
    const surface = waterAt(42, x, z).?;
    const bed = carvedHeight(42, x, z, Noise.baseHeight(42, x, z));
    try std.testing.expect(surface > bed + 1);
    try std.testing.expect(waterAt(42, x, z + water_width) == null);
}

test "Detroit has a wide river around a dry Belle Isle and a narrow channel beyond the city" {
    const x: f32 = 0;
    const center = centerZ(42, 0, x);
    try std.testing.expect(surfaceHalfWidth(0, x) > 150);
    try std.testing.expect(waterAt(42, x, center + 100) != null);
    try std.testing.expect(waterAt(42, x, center) == null);
    try std.testing.expectApproxEqAbs(Noise.baseHeight(42, x, center), carvedHeight(42, x, center, Noise.baseHeight(42, x, center)), 0.0001);
    try std.testing.expectApproxEqAbs(water_width * 0.5, surfaceHalfWidth(0, 1500), 0.0001);
    try std.testing.expectApproxEqAbs(channel_width, channelHalfWidth(1, 0), 0.0001);
}
