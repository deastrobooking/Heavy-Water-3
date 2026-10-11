const std = @import("std");
const Seed = @import("Seed.zig");
const Noise = @import("Noise.zig");
const Biome = @import("Biome.zig");
const Key = @import("../world/ChunkKey.zig");
const Transform = @import("../world/Transform.zig");
/// Relic and plant candidates per chunk, then boulder candidates after them. Boulders take the
/// local IDs above `candidates`, so the IDs of everything older (and saved removals) are unchanged.
pub const candidates = 192;
pub const boulder_candidates = 40;
pub const capacity = candidates + boulder_candidates;
pub const Kind = enum { relic, vegetation, boulder };
const Vegetation = @import("Vegetation.zig");
/// Stable identity is (world seed, generator version, chunk key, local candidate ID).
pub const Object = struct { local_id: u16, kind: Kind, variant: u8 = 0, transform: Transform, tint: [4]f32 };

pub fn allowed(normal_y: f32, kind: Kind) bool {
    return normal_y >= switch (kind) {
        .vegetation => @as(f32, 0.94),
        .relic => 0.88,
        .boulder => 0.55,
    };
}

pub fn generate(seed: u64, key: Key, output: *[capacity]Object) usize {
    const chunk_seed = Seed.at(seed ^ 0x53434154544552, key.x, key.z);
    var count: usize = 0;
    for (0..candidates) |i| {
        const h = Seed.mix(chunk_seed +% i);
        const x = @as(f32, @floatFromInt(key.x)) * Key.extent + Seed.unit(h) * 124 - 62;
        const z = @as(f32, @floatFromInt(key.z)) * Key.extent + Seed.unit(Seed.mix(h)) * 124 - 62;
        const kind: Kind = if (i % 7 == 0) .relic else .vegetation;
        const biome = Biome.sample(seed, x, z);
        const nx = Noise.height(seed, x - 0.5, z) - Noise.height(seed, x + 0.5, z);
        const nz = Noise.height(seed, x, z - 0.5) - Noise.height(seed, x, z + 0.5);
        if (!allowed(1 / @sqrt(nx * nx + 1 + nz * nz), kind)) continue;
        const chance = Seed.unit(Seed.mix(h +% 2));
        if (kind == .vegetation and chance > 0.85 - biome.arid * 0.65) continue;
        // Snow thins the flora to the hardy trees, and frosts what grows.
        const frost = if (kind == .vegetation) Biome.cover(seed, x, z, Noise.height(seed, x, z), @sqrt(nx * nx + nz * nz)).snow else 0;
        const choice = Seed.unit(Seed.mix(h +% 3));
        if (frost > 0.25 and choice <= 0.82 and Seed.unit(Seed.mix(h +% 5)) < frost) continue;
        const variant: u8 = if (kind == .relic) 0 else if (choice > 0.82) Vegetation.tree_first + @as(u8, @intCast(Seed.mix(h +% 4) % 3)) else if (choice > 0.70) 2 else if (choice > 0.48) 1 else 0;
        const color = biome.color();
        output[count] = .{
            .local_id = @intCast(i),
            .kind = kind,
            .variant = variant,
            .transform = .{ .position = .{ x, Noise.height(seed, x, z) - 0.03, z }, .scale = if (variant >= Vegetation.tree_first) 10 + Seed.unit(Seed.mix(h +% 1)) * 9 else 0.8 + Seed.unit(Seed.mix(h +% 1)) * 1.1 },
            .tint = if (kind == .relic) .{ 0.40, 0.72, 0.81, 1 } else if (variant == 2) .{ 1.15, 0.72, 1.12, 1 } else frosted(.{ color[0] * 0.8, color[1] * 1.3, color[2] * 0.9, 1 }, frost, Vegetation.colors[variant]),
        };
        count += 1;
    }
    for (0..boulder_candidates) |b| {
        const i = candidates + b;
        const h = Seed.mix(chunk_seed ^ 0x524f434b +% i);
        const x = @as(f32, @floatFromInt(key.x)) * Key.extent + Seed.unit(h) * 124 - 62;
        const z = @as(f32, @floatFromInt(key.z)) * Key.extent + Seed.unit(Seed.mix(h)) * 124 - 62;
        const nx = Noise.height(seed, x - 0.5, z) - Noise.height(seed, x + 0.5, z);
        const nz = Noise.height(seed, x, z - 0.5) - Noise.height(seed, x, z + 0.5);
        if (!allowed(1 / @sqrt(nx * nx + 1 + nz * nz), .boulder)) continue;
        const height = Noise.height(seed, x, z);
        const cover = Biome.cover(seed, x, z, height, @sqrt(nx * nx + nz * nz));
        // Rocky, high and dry ground carries the most stone; lush meadow the least.
        const alpine = std.math.clamp((height - 8) / 30, 0, 1);
        const chance = 0.12 + 0.35 * cover.weights.arid + 0.45 * alpine + 0.4 * cover.exposed;
        if (Seed.unit(Seed.mix(h +% 2)) > chance) continue;
        const size = Seed.unit(Seed.mix(h +% 1));
        // Mostly knee-high stones, with the odd boulder taller than a ranger.
        const scale = 0.5 + size * size * size * 3.2;
        const stone = Vegetation.stone;
        const earth = cover.weights.color();
        const shade = 0.85 + Seed.unit(Seed.mix(h +% 3)) * 0.3;
        var tint: [4]f32 = .{ 1, 1, 1, 1 };
        for (0..3) |c| tint[c] = (stone[c] * 0.75 + earth[c] * 0.25) * shade / stone[c];
        output[count] = .{
            .local_id = @intCast(i),
            .kind = .boulder,
            .variant = @intCast(Seed.mix(h +% 4) % Vegetation.boulder_count),
            .transform = .{ .position = .{ x, height - 0.05 * scale, z }, .scale = scale },
            .tint = frosted(tint, cover.snow * 0.8, stone ++ [_]f32{1}),
        };
        count += 1;
    }
    return count;
}

/// Mixes a tint toward frost white by `amount`. Tints multiply the material's `base` colour, so
/// the frost tint divides it back out.
fn frosted(tint: [4]f32, amount: f32, base: [4]f32) [4]f32 {
    if (amount <= 0) return tint;
    const frost = [3]f32{ 0.84, 0.89, 0.93 };
    var out = tint;
    for (0..3) |c| out[c] = tint[c] * (1 - amount) + frost[c] / base[c] * amount;
    return out;
}

test "scatter is stable, locally unique, bounded and slope aware" {
    var a: [capacity]Object = undefined;
    var b: [capacity]Object = undefined;
    const key: Key = .{ .x = -3, .z = 2 };
    const len = generate(42, key, &a);
    try std.testing.expect(len > 0);
    try std.testing.expectEqual(len, generate(42, key, &b));
    try std.testing.expectEqualSlices(Object, a[0..len], b[0..len]);
    for (a[0..len], 0..) |object, i| {
        try std.testing.expect(Key.eql(key, Key.fromPosition(object.transform.position[0], object.transform.position[2])));
        if (i > 0) try std.testing.expect(object.local_id > a[i - 1].local_id);
    }
    try std.testing.expect(!allowed(0.5, .vegetation));
    try std.testing.expect(allowed(1, .vegetation));
}

test "seeded scatter distributes all plant forms and three tree species reproducibly" {
    var first: [capacity]Object = undefined;
    var second: [capacity]Object = undefined;
    var species_mask: u8 = 0;
    for (0..10) |z| for (0..10) |x| {
        const key: Key = .{ .x = @as(i32, @intCast(x)) - 5, .z = @as(i32, @intCast(z)) - 5 };
        const count = generate(987654321, key, &first);
        try std.testing.expectEqual(count, generate(987654321, key, &second));
        try std.testing.expectEqualSlices(Object, first[0..count], second[0..count]);
        for (first[0..count]) |object| if (object.kind == .vegetation) {
            try std.testing.expect(object.variant < @import("Vegetation.zig").variant_count);
            species_mask |= @as(u8, 1) << @intCast(object.variant);
        };
    };
    try std.testing.expectEqual(@as(u8, 0x3f), species_mask);
}

test "boulders gather on high, steep and dry ground, after every older candidate" {
    var objects: [capacity]Object = undefined;
    var boulders: usize = 0;
    var kinds: [Vegetation.boulder_count]bool = @splat(false);
    for (0..12) |z| for (0..12) |x| {
        const key: Key = .{ .x = @as(i32, @intCast(x)) * 3 - 18, .z = @as(i32, @intCast(z)) * 3 - 18 };
        const n = generate(42, key, &objects);
        for (objects[0..n]) |o| if (o.kind == .boulder) {
            boulders += 1;
            kinds[o.variant] = true;
            try std.testing.expect(o.local_id >= candidates and o.local_id < capacity);
            try std.testing.expect(o.transform.scale >= 0.5 and o.transform.scale <= 3.8);
        } else try std.testing.expect(o.local_id < candidates);
    };
    try std.testing.expect(boulders > 50);
    for (kinds) |k| try std.testing.expect(k);
}
