const std = @import("std");
const Noise = @import("Noise.zig");
const Seed = @import("Seed.zig");
pub const Weights = struct {
    arid: f32,
    meadow: f32,
    wetland: f32,

    pub fn color(self: Weights) [3]f32 {
        const sand = [3]f32{ 0.65, 0.40, 0.22 };
        const green = [3]f32{ 0.28, 0.47, 0.29 };
        const marsh = [3]f32{ 0.15, 0.39, 0.43 };
        var result: [3]f32 = undefined;
        for (&result, 0..) |*v, i| v.* = sand[i] * self.arid + green[i] * self.meadow + marsh[i] * self.wetland;
        return result;
    }
};

/// Altitude and exposed steep faces transition through alpine stone into permanent snow.
pub fn terrainColor(seed: u64, x: f32, z: f32, height: f32, slope: f32) [3]f32 {
    const weights = sample(seed, x, z);
    const base = weights.color();
    const alpine = std.math.clamp((height - 12) / 24, 0, 1);
    const exposed = std.math.clamp((slope - 0.72) / 0.9, 0, 1) * alpine;
    // The great ranges carry their snow higher, on their peaks rather than their flanks.
    const range = @import("Mountains.zig").sample(seed, x, z).influence;
    const snowline = 27 + range * 165 + (Noise.value(seed ^ 0x534e4f57, x / 260, z / 260) - 0.5) * 9;
    const snow = std.math.clamp((height - snowline) / 8, 0, 1) * (0.75 + exposed * 0.25);
    const rock = [3]f32{ 0.42, 0.48, 0.49 };
    const snow_color = [3]f32{ 0.86, 0.91, 0.94 };
    var result: [3]f32 = undefined;
    for (&result, 0..) |*channel, i| {
        const alpine_color = base[i] * (1 - exposed) + rock[i] * exposed;
        channel.* = alpine_color * (1 - snow) + snow_color[i] * snow;
    }
    return result;
}

/// Continuous world-space moisture mask. No chunk-local normalization or thresholds at seams.
pub fn sample(seed: u64, x: f32, z: f32) Weights {
    const moisture = Noise.value(Seed.mix(seed ^ 0x42494f4d45), x / 220, z / 220);
    const arid = std.math.clamp((0.5 - moisture) * 3, 0, 1);
    const wetland = std.math.clamp((moisture - 0.5) * 3, 0, 1);
    return .{ .arid = arid, .meadow = 1 - arid - wetland, .wetland = wetland };
}

test "biome weights are normalized and produce multiple regions" {
    var min: f32 = 1;
    var max: f32 = 0;
    for (0..100) |i| {
        const w = sample(42, @as(f32, @floatFromInt(i)) * 89 - 4000, 123);
        try std.testing.expectApproxEqAbs(@as(f32, 1), w.arid + w.meadow + w.wetland, 0.00001);
        try std.testing.expect(w.arid >= 0 and w.meadow >= 0 and w.wetland >= 0);
        min = @min(min, w.arid);
        max = @max(max, w.arid);
    }
    try std.testing.expect(max - min > 0.5);
}

test "terrain color adds exposed alpine rock and persistent snow above the snowline" {
    const low = terrainColor(42, 10, 20, -3, 0.1);
    const snowy = terrainColor(42, 10, 20, 70, 0.4);
    try std.testing.expect(snowy[0] > low[0]);
    try std.testing.expect(snowy[1] > low[1]);
}
