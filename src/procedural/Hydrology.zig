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
    const distance = @abs(z - centerZ(seed, nearest, x));
    if (distance >= channel_width) return base;
    const t = 1 - distance / channel_width;
    const weight = t * t * (3 - 2 * t);
    const bed = level(seed, nearest, x) - 1.35;
    return @min(base, base + (bed - base) * weight);
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
