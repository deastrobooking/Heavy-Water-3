const Seed = @import("Seed.zig");

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

pub fn height(seed: u64, x: f32, z: f32) f32 {
    return value(seed, x * 0.028, z * 0.028) * 13 + value(Seed.mix(seed), x * 0.09, z * 0.09) * 3 - 7;
}
