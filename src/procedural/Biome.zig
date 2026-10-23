const std = @import("std");
const Noise = @import("Noise.zig");
const Seed = @import("Seed.zig");
const Region = @import("../world/Region.zig");
const ChunkKey = @import("../world/ChunkKey.zig");
const Cloudwater = @import("Cloudwater.zig");
const CityHeightmaps = @import("CityHeightmaps.zig");
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

/// What covers the ground at a spot: the biome mix, how much bare alpine rock shows on steep
/// high faces, and how much snow lies above the snowline. Terrain colour and the gameplay
/// footing (`Kind`) both come from this, so what a player sees underfoot is what they walk on.
pub const Cover = struct {
    weights: Weights,
    exposed: f32,
    snow: f32,

    pub fn kind(self: Cover) Kind {
        if (self.snow > 0.5) return .snow;
        if (self.exposed > 0.45) return .rock;
        const w = self.weights;
        if (w.arid > w.meadow and w.arid > w.wetland) return .sand;
        if (w.wetland > w.meadow) return .marsh;
        return .grass;
    }
};

/// The footing a cover gives: snow slows and slides, marsh and sand drag a little.
pub const Kind = enum { grass, sand, marsh, rock, snow };

/// Altitude and exposed steep faces transition through alpine stone into permanent snow.
pub fn cover(seed: u64, x: f32, z: f32, height: f32, slope: f32) Cover {
    const key = ChunkKey.fromPosition(x, z);
    const k2 = Region.k2.contains(key.x, key.z);
    const alpine = std.math.clamp((height - 12) / 24, 0, 1);
    const exposed = std.math.clamp((slope - 0.72) / 0.9, 0, 1) * alpine;
    // The great ranges carry their snow higher, on their peaks rather than their flanks.
    const range = @import("Mountains.zig").sample(seed, x, z).influence;
    const local_snow = Noise.value(seed ^ 0x534e4f57, x / 260, z / 260);
    const snowline = if (k2) @as(f32, 4160) + (local_snow - 0.5) * 115 else 27 + range * 165 + (local_snow - 0.5) * 9;
    var snow = if (k2) @max(0.72, std.math.clamp((height - snowline) / 90, 0, 1)) else std.math.clamp((height - snowline) / 8, 0, 1) * (0.75 + exposed * 0.25);
    if (k2) {
        // The sheltered Cloudwater bowl keeps rock shelves and hardy tree pockets below its
        // locally raised snowline; the surrounding K2 glacier retains its permanent ice cover.
        const bowl_snowline = 4510 + (local_snow - 0.5) * 78;
        const sheltered_snow = @max(0.24, std.math.clamp((height - bowl_snowline) / 125, 0, 1));
        const mix = Cloudwater.basinWeight(x, z);
        snow = snow * (1 - mix) + sheltered_snow * mix;
    }
    return .{ .weights = sample(seed, x, z), .exposed = exposed, .snow = snow };
}

/// The cover of the generated terrain at (x, z), with height and slope measured exactly as the
/// chunk mesh measures them.
pub fn coverAt(seed: u64, x: f32, z: f32) Cover {
    const nx = CityHeightmaps.heightAt(seed, x - 0.5, z) - CityHeightmaps.heightAt(seed, x + 0.5, z);
    const nz = CityHeightmaps.heightAt(seed, x, z - 0.5) - CityHeightmaps.heightAt(seed, x, z + 0.5);
    return cover(seed, x, z, CityHeightmaps.heightAt(seed, x, z), @sqrt(nx * nx + nz * nz));
}

pub fn terrainColor(seed: u64, x: f32, z: f32, height: f32, slope: f32) [3]f32 {
    const c = cover(seed, x, z, height, slope);
    var base = c.weights.color();
    const hills = sunmeadowWeight(seed, x, z, height, slope);
    const sunmeadow = [3]f32{ 0.33, 0.67, 0.22 };
    for (&base, sunmeadow) |*channel, hill_channel| channel.* = channel.* * (1 - hills) + hill_channel * hills;
    const key = ChunkKey.fromPosition(x, z);
    const k2 = Region.k2.contains(key.x, key.z);
    const rock = if (k2) [3]f32{ 0.31, 0.39, 0.45 } else [3]f32{ 0.42, 0.48, 0.49 };
    const snow_color = if (k2) [3]f32{ 0.68, 0.84, 0.94 } else [3]f32{ 0.86, 0.91, 0.94 };
    const ice = [3]f32{ 0.28, 0.52, 0.67 };
    var result: [3]f32 = undefined;
    for (&result, 0..) |*channel, i| {
        const alpine_color = base[i] * (1 - c.exposed) + rock[i] * c.exposed;
        const bare = if (k2) alpine_color * 0.28 + ice[i] * 0.72 else alpine_color;
        channel.* = bare * (1 - c.snow) + snow_color[i] * c.snow;
    }
    return if (k2) Cloudwater.terrainColor(seed, x, z, result, c.snow, slope) else result;
}

/// Bright rolling upland pockets, blended into ordinary meadows so the style stays native to
/// the world. The palette and grass species are original and do not depend on a named franchise.
pub fn sunmeadowWeight(seed: u64, x: f32, z: f32, height: f32, slope: f32) f32 {
    const meadow = sample(seed, x, z).meadow;
    // The plain around the city sits near 113 m: full strength up to 150 m, none above 210 m.
    const lowland = 1 - std.math.clamp((height - 150) / 60, 0, 1);
    const gentle = 1 - std.math.clamp((slope - 0.12) / 0.48, 0, 1);
    const rolling = Noise.value(seed ^ 0x53554e4d4541444f, x / 180, z / 180);
    const patch = std.math.clamp((rolling - 0.37) * 3.1, 0, 1);
    return std.math.clamp(meadow * lowland * gentle * patch, 0, 1);
}

/// How strongly the glowing living-sap flora (`SapFlora.zig`) grows here, 0 to 1: patchy meadows
/// and wet ground on gentle land below the highlands, thinning to nothing on steep, high or dry ground.
pub fn sapMeadowWeight(seed: u64, x: f32, z: f32, height: f32, slope: f32) f32 {
    const w = sample(seed, x, z);
    // The plain around the city sits near 113 m; full strength up to 150 m, none above 210 m.
    const lowland = 1 - std.math.clamp((height - 150) / 60, 0, 1);
    const gentle = 1 - std.math.clamp((slope - 0.14) / 0.5, 0, 1);
    const rolling = Noise.value(seed ^ 0x53415046_4c4f5241, x / 260, z / 260);
    const patch = std.math.clamp((rolling - 0.40) * 3.4, 0, 1);
    return std.math.clamp((w.meadow * 0.8 + w.wetland) * lowland * gentle * patch, 0, 1);
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

test "footing follows the cover: snow above the snowline, the biome's ground below" {
    const snowy = cover(42, 10, 20, 400, 0.2);
    try std.testing.expectEqual(Kind.snow, snowy.kind());
    try std.testing.expectEqual(Kind.rock, (Cover{ .weights = .{ .arid = 0, .meadow = 1, .wetland = 0 }, .exposed = 0.8, .snow = 0 }).kind());
    try std.testing.expectEqual(Kind.sand, (Cover{ .weights = .{ .arid = 0.7, .meadow = 0.3, .wetland = 0 }, .exposed = 0, .snow = 0 }).kind());
    try std.testing.expectEqual(Kind.marsh, (Cover{ .weights = .{ .arid = 0, .meadow = 0.3, .wetland = 0.7 }, .exposed = 0, .snow = 0 }).kind());
    try std.testing.expect(cover(42, 10, 20, -3, 0.1).kind() != .snow);
}

test "cover is measured on the same height the chunk mesh uses" {
    const h = CityHeightmaps.heightAt(7, 0, 0);
    const a = coverAt(7, 0, 0);
    const nx = CityHeightmaps.heightAt(7, -0.5, 0) - CityHeightmaps.heightAt(7, 0.5, 0);
    const nz = CityHeightmaps.heightAt(7, 0, -0.5) - CityHeightmaps.heightAt(7, 0, 0.5);
    const b = cover(7, 0, 0, h, @sqrt(nx * nx + nz * nz));
    try std.testing.expectEqual(b.kind(), a.kind());
}

test "the sap-meadow weight is bounded, patchy, and zero on steep or high ground" {
    var any_high = false;
    var any_zero = false;
    for (0..40) |zi| for (0..40) |xi| {
        const x = @as(f32, @floatFromInt(xi)) * 37 - 700;
        const z = @as(f32, @floatFromInt(zi)) * 37 - 700;
        const w = sapMeadowWeight(7, x, z, 113, 0.05);
        try std.testing.expect(w >= 0 and w <= 1);
        any_high = any_high or w > 0.4;
        any_zero = any_zero or w == 0;
        try std.testing.expectEqual(@as(f32, 0), sapMeadowWeight(7, x, z, 260, 0.05));
        try std.testing.expectEqual(@as(f32, 0), sapMeadowWeight(7, x, z, 113, 0.8));
    };
    try std.testing.expect(any_high and any_zero);
}
