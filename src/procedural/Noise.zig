const Seed = @import("Seed.zig");
const Hydrology = @import("Hydrology.zig");

pub fn value(seed: u64, x: f32, z: f32) f32 {
    const ix: i64 = @intFromFloat(@floor(x));
    const iz: i64 = @intFromFloat(@floor(z));
    const fx = x - @floor(x);
    const fz = z - @floor(z);
    const u = fx * fx * (3 - 2 * fx);
    const v = fz * fz * (3 - 2 * fz);
    const a = Seed.unit(Seed.at(seed, ix, iz));
    const b = Seed.unit(Seed.at(seed, ix + 1, iz));
    const c = Seed.unit(Seed.at(seed, ix, iz + 1));
    const d = Seed.unit(Seed.at(seed, ix + 1, iz + 1));
    return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v;
}

pub fn baseHeight(seed: u64, x: f32, z: f32) f32 {
    const distance = @sqrt(x * x + z * z);
    const edge = std.math.clamp((distance - 420) / 580, 0, 1);
    const relief = edge * edge * (3 - 2 * edge);
    const broad = value(seed, x * 0.012, z * 0.012) * 11;
    const detail = value(Seed.mix(seed), x * 0.045, z * 0.045) * 4 * relief;
    const ridge_signal = 1 - @abs(value(Seed.mix(seed ^ 0x4d4f554e5441494e), x * 0.009, z * 0.009) * 2 - 1);
    const ridges = std.math.pow(f32, ridge_signal, 2.15) * (15 + value(seed ^ 0x414c50494e45, x * 0.003, z * 0.003) * 24) * relief;
    return broad + detail + ridges - 11 + @import("Mountains.zig").height(seed, x, z);
}

pub fn height(seed: u64, x: f32, z: f32) f32 {
    return Hydrology.carvedHeight(seed, x, z, baseHeight(seed, x, z));
}

const std = @import("std");
