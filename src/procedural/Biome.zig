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
