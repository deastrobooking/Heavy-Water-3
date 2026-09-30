//! Time of day → light. The sun rises in the east (+X), peaks south of the zenith at noon, and
//! sets in the west; at night a cool, dim moon light comes from the opposite side. Colors are
//! chosen for the painterly direction: warm key, cool fill, golden low sun, violet dusk.
const std = @import("std");
const Sky = @This();

pub const Light = struct {
    /// Direction toward the light (sun by day, moon by night).
    direction: [3]f32,
    color: [3]f32,
    ambient_sky: [3]f32,
    ambient_ground: [3]f32,
    horizon: [3]f32,
    zenith: [3]f32,
    /// 0 at full day, 1 at full night; lumen glows more as it rises.
    night: f32,
};

fn mix(a: [3]f32, b: [3]f32, t: f32) [3]f32 {
    return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t };
}

fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
    const t = std.math.clamp((x - e0) / (e1 - e0), 0, 1);
    return t * t * (3 - 2 * t);
}

fn normalize(v: [3]f32) [3]f32 {
    const l = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return .{ v[0] / l, v[1] / l, v[2] / l };
}

/// Sun elevation sine for a time of day in [0, 1) (0.25 sunrise, 0.5 noon, 0.75 sunset).
pub fn sunElevation(time: f32) f32 {
    return @sin((time - 0.25) * 2 * std.math.pi);
}

pub fn at(time: f32) Light {
    const angle = (time - 0.25) * 2 * std.math.pi;
    // East → up → west, tilted toward the south (−Z) so noon light is not straight down.
    const sun = normalize(.{ @cos(angle), @sin(angle), -0.35 });
    const elevation = sun[1];
    const day = smoothstep(-0.12, 0.18, elevation);
    const low = 1 - smoothstep(0.05, 0.5, elevation);
    const sun_color = mix(.{ 1.0, 0.95, 0.84 }, .{ 1.0, 0.62, 0.36 }, low);
    const moon: [3]f32 = .{ 0.30, 0.38, 0.62 };
    const direction = if (elevation > -0.05) sun else normalize(.{ -sun[0], -sun[1], -sun[2] });
    const color = mix(.{ moon[0] * 0.35, moon[1] * 0.35, moon[2] * 0.35 }, .{ sun_color[0] * 1.05, sun_color[1] * 1.05, sun_color[2] * 1.05 }, day);
    const dusk = low * day;
    return .{
        .direction = direction,
        .color = color,
        .ambient_sky = mix(.{ 0.05, 0.07, 0.14 }, .{ 0.34, 0.44, 0.56 }, day),
        .ambient_ground = mix(.{ 0.02, 0.03, 0.05 }, .{ 0.20, 0.19, 0.14 }, day),
        .horizon = mix(mix(.{ 0.04, 0.06, 0.12 }, .{ 0.62, 0.78, 0.86 }, day), .{ 0.86, 0.56, 0.52 }, dusk * 0.6),
        .zenith = mix(.{ 0.01, 0.02, 0.06 }, .{ 0.30, 0.52, 0.80 }, day),
        .night = 1 - day,
    };
}

fn luminance(c: [3]f32) f32 {
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

test "sun rises east, peaks at noon, sets west; night is dark and cool with lumen weight" {
    try std.testing.expect(at(0.3).direction[0] > 0.5);
    try std.testing.expect(at(0.7).direction[0] < -0.5);
    const noon = at(0.5);
    const midnight = at(0.0);
    try std.testing.expect(noon.direction[1] > 0.9);
    try std.testing.expect(noon.night < 0.01 and midnight.night > 0.99);
    try std.testing.expect(luminance(noon.color) > 4 * luminance(midnight.color));
    try std.testing.expect(luminance(noon.ambient_sky) > luminance(midnight.ambient_sky));
    // Moonlight is bluer than it is red.
    try std.testing.expect(midnight.color[2] > midnight.color[0]);
    // Low sun is warmer (redder relative to blue) than noon sun.
    const low = at(0.28);
    try std.testing.expect(low.color[0] / low.color[2] > noon.color[0] / noon.color[2]);
    // Light always points above the horizon.
    for (0..48) |i| try std.testing.expect(at(@as(f32, @floatFromInt(i)) / 48).direction[1] > -0.06);
}
