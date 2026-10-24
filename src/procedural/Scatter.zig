const std = @import("std");
const Seed = @import("Seed.zig");
const Chunk = @import("Chunk.zig");
const CityHeightmaps = @import("CityHeightmaps.zig");
const Biome = @import("Biome.zig");
const Cloudwater = @import("Cloudwater.zig");
const Region = @import("../world/Region.zig");
const Key = @import("../world/ChunkKey.zig");
const Transform = @import("../world/Transform.zig");
/// Relic and plant candidates per chunk, then boulder candidates after them. Boulders take the
/// local IDs above `candidates`, so the IDs of everything older (and saved removals) are unchanged.
pub const candidates = 192;
pub const boulder_candidates = 40;
/// The living-sap flora has its own candidates after the boulders, so every older id stays put.
pub const sap_candidates = 240;
pub const capacity = candidates + boulder_candidates + sap_candidates;
pub const Kind = enum { relic, vegetation, boulder };
const Vegetation = @import("Vegetation.zig");
const SapFlora = @import("SapFlora.zig");
const District = @import("District.zig");
/// Tall trees stay this far (beyond half the deck width) from district roads and plazas, so no
/// trunk or crown pokes through a deck. Skipped candidates keep their IDs, so saves are unaffected.
const road_clearance: f32 = 26;
/// Nothing is placed on top of the spawn point (the same point as `Sandbox.spawn`; scatter cannot
/// import the game layer): relics reach 18 m across and would block the first workshop. Relics
/// just beyond the clearing stay as the early salvage; trees need a wider berth.
const spawn_xz: [2]f32 = .{ 0, -58 };
const spawn_clearing: f32 = 24;
const spawn_relic_clearing: f32 = 12;
fn nearSpawn(x: f32, z: f32, radius: f32) bool {
    const dx = x - spawn_xz[0];
    const dz = z - spawn_xz[1];
    return dx * dx + dz * dz < radius * radius;
}
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
    const regional_seed = Chunk.regionalSeed(seed, key.x, key.z);
    const antarctic = Region.antarctica.contains(key.x, key.z);
    const alpine_glacier = Region.k2.contains(key.x, key.z);
    const lunar = Region.moon.contains(key.x, key.z);
    const chunk_seed = Seed.at(regional_seed ^ 0x53434154544552, key.x, key.z);
    var count: usize = 0;
    for (0..candidates) |i| {
        const h = Seed.mix(chunk_seed +% i);
        const x = @as(f32, @floatFromInt(key.x)) * Key.extent + Seed.unit(h) * 124 - 62;
        const z = @as(f32, @floatFromInt(key.z)) * Key.extent + Seed.unit(Seed.mix(h)) * 124 - 62;
        // The ordinary relic marker is a young tree. Leave lunar ground to rocks, mined veins,
        // and authored structures rather than generating foliage-shaped salvage on the Moon.
        if (lunar) continue;
        const kind: Kind = if (i % 7 == 0) .relic else .vegetation;
        // The subglacial approach is a wind-carved ice sheet; preserve salvage, clear the forest.
        if (antarctic and kind == .vegetation) continue;
        const ground = CityHeightmaps.heightAt(seed, x, z);
        if (alpine_glacier and kind == .vegetation and (!Cloudwater.isSheltered(x, z) or ground > 4660)) continue;
        if (kind == .relic and nearSpawn(x, z, spawn_relic_clearing)) continue;
        const biome = Biome.sample(regional_seed, x, z);
        const nx = CityHeightmaps.heightAt(seed, x - 0.5, z) - CityHeightmaps.heightAt(seed, x + 0.5, z);
        const nz = CityHeightmaps.heightAt(seed, x, z - 0.5) - CityHeightmaps.heightAt(seed, x, z + 0.5);
        if (!allowed(1 / @sqrt(nx * nx + 1 + nz * nz), kind)) continue;
        const chance = Seed.unit(Seed.mix(h +% 2));
        if (kind == .vegetation and chance > 0.85 - biome.arid * 0.65) continue;
        // Snow thins the flora to the hardy trees, and frosts what grows.
        const frost = if (kind == .vegetation) Biome.cover(regional_seed, x, z, ground, @sqrt(nx * nx + nz * nz)).snow else 0;
        const choice = Seed.unit(Seed.mix(h +% 3));
        if (frost > 0.25 and choice <= 0.82 and Seed.unit(Seed.mix(h +% 5)) < frost) continue;
        const hill_style = Biome.sunmeadowWeight(regional_seed, x, z, ground, @sqrt(nx * nx + nz * nz));
        // Long grass and fern fronds are sparse floor accents; rounded shrubs and flowering
        // natives carry most of the understory so their silhouettes do not read like tree leaves.
        const sheltered = alpine_glacier and Cloudwater.isSheltered(x, z);
        const variant: u8 = if (kind == .relic) 0 else if (hill_style > 0.3 and choice < 0.17) 15 else if (hill_style > 0.3 and choice < 0.28) 16 else if (hill_style > 0.3 and choice < 0.35) 17 else if (choice < 0.07) 0 else if (choice < 0.15) 1 else if (sheltered and Cloudwater.groveWeight(x, z) > 0.2 and choice > 0.69) 11 else if (sheltered and choice > 0.90) 14 else if (choice > 0.985) Vegetation.tree_variants[@intCast(Seed.mix(h +% 4) % Vegetation.tree_count)] else if (choice > 0.96 and biome.arid < 0.58) 14 else if (choice > 0.88) 2 else if (choice > 0.66) 8 + @as(u8, @intCast(Seed.mix(h +% 6) % 3)) else if (choice > 0.25) 7 else 8 + @as(u8, @intCast(Seed.mix(h +% 6) % 3));
        if (Vegetation.isTree(variant) and (nearSpawn(x, z, spawn_clearing) or District.nearRoad(seed, x, z, road_clearance))) continue;
        const color = biome.color();
        const shade = 0.84 + 0.28 * Seed.unit(Seed.mix(h +% 5));
        const tint: [4]f32 = if (variant < 6) .{ color[0] * 0.8 / Vegetation.colors[variant][0], color[1] * 1.3 / Vegetation.colors[variant][1], color[2] * 0.9 / Vegetation.colors[variant][2], 1 } else if (variant == 6) .{ shade, shade * 0.48, shade * 0.55, 1 } else .{ shade * (0.8 + 0.2 * color[0]), shade * (0.85 + 0.15 * color[1]), shade * (0.8 + 0.2 * color[2]), 1 };
        output[count] = .{
            .local_id = @intCast(i),
            .kind = kind,
            .variant = variant,
            .transform = .{ .position = .{ x, ground - 0.03, z }, .scale = if (kind == .relic) 6.1 + Seed.unit(Seed.mix(h +% 1)) * 12.2 else if (alpine_glacier and Vegetation.isTree(variant)) 30 + Seed.unit(Seed.mix(h +% 1)) * 24 else if (Vegetation.isRedwood(variant)) 132 + Seed.unit(Seed.mix(h +% 1)) * 20.4 else if (Vegetation.isTree(variant)) 96 + Seed.unit(Seed.mix(h +% 1)) * 54 else if (variant == 14) 6 + Seed.unit(Seed.mix(h +% 1)) * 12 else if (variant == 7) 1.3 + Seed.unit(Seed.mix(h +% 1)) * 1.2 else if (variant == 0) 0.55 + Seed.unit(Seed.mix(h +% 1)) * 0.55 else if (variant == 1) 0.7 + Seed.unit(Seed.mix(h +% 1)) * 0.65 else if (variant >= 15) 0.8 + Seed.unit(Seed.mix(h +% 1)) * 0.8 else 0.8 + Seed.unit(Seed.mix(h +% 1)) * 1.1 },
            .tint = if (kind == .relic) .{ shade, shade, shade, 1 } else if (alpine_glacier and variant == 11 and Cloudwater.groveWeight(x, z) > 0.2) .{ 1.8 * shade, 1.1 * shade, 0.55 * shade, 1 } else if (variant == 2) .{ 1.15, 0.72, 1.12, 1 } else frosted(tint, frost, Vegetation.colors[variant]),
        };
        count += 1;
    }
    for (0..boulder_candidates) |b| {
        const i = candidates + b;
        const h = Seed.mix(chunk_seed ^ 0x524f434b +% i);
        const x = @as(f32, @floatFromInt(key.x)) * Key.extent + Seed.unit(h) * 124 - 62;
        const z = @as(f32, @floatFromInt(key.z)) * Key.extent + Seed.unit(Seed.mix(h)) * 124 - 62;
        const nx = CityHeightmaps.heightAt(seed, x - 0.5, z) - CityHeightmaps.heightAt(seed, x + 0.5, z);
        const nz = CityHeightmaps.heightAt(seed, x, z - 0.5) - CityHeightmaps.heightAt(seed, x, z + 0.5);
        if (!allowed(1 / @sqrt(nx * nx + 1 + nz * nz), .boulder)) continue;
        const height = CityHeightmaps.heightAt(seed, x, z);
        const cover = Biome.cover(regional_seed, x, z, height, @sqrt(nx * nx + nz * nz));
        // Rocky, high and dry ground carries the most stone; lush meadow the least.
        const alpine = std.math.clamp((height - 8) / 30, 0, 1);
        const chance = if (lunar) @as(f32, 0.68) else if (antarctic or alpine_glacier) @as(f32, 0.32) else 0.12 + 0.35 * cover.weights.arid + 0.45 * alpine + 0.4 * cover.exposed;
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
            .tint = if (lunar) .{ 0.78 * shade, 0.8 * shade, 0.84 * shade, 1 } else if (antarctic) .{ 0.5 * shade, 0.75 * shade, 0.98 * shade, -2 } else if (alpine_glacier) .{ 0.58 * shade, 0.78 * shade, 0.95 * shade, -2 } else frosted(tint, cover.snow * 0.8, stone ++ [_]f32{1}),
        };
        count += 1;
    }
    // The living-sap flora: glowing grasses, flowers, bushes and small trees in patchy meadows.
    if (!lunar and !antarctic and !alpine_glacier) for (0..sap_candidates) |j| {
        const i = candidates + boulder_candidates + j;
        const h = Seed.mix(chunk_seed ^ 0x534150464c4f5241 +% i);
        const x = @as(f32, @floatFromInt(key.x)) * Key.extent + Seed.unit(h) * 124 - 62;
        const z = @as(f32, @floatFromInt(key.z)) * Key.extent + Seed.unit(Seed.mix(h)) * 124 - 62;
        const ground = CityHeightmaps.heightAt(seed, x, z);
        const nx = CityHeightmaps.heightAt(seed, x - 0.5, z) - CityHeightmaps.heightAt(seed, x + 0.5, z);
        const nz = CityHeightmaps.heightAt(seed, x, z - 0.5) - CityHeightmaps.heightAt(seed, x, z + 0.5);
        if (!allowed(1 / @sqrt(nx * nx + 1 + nz * nz), .vegetation)) continue;
        const slope = @sqrt(nx * nx + nz * nz);
        const weight = Biome.sapMeadowWeight(regional_seed, x, z, ground, slope);
        // Snow thins them but does not stop them: lumen-lit plants glowing through the snow is the look.
        const snow = Biome.cover(regional_seed, x, z, ground, slope).snow;
        if (Seed.unit(Seed.mix(h +% 2)) > weight * 0.9 * (1 - 0.5 * snow)) continue;
        const biome = Biome.sample(regional_seed, x, z);
        const species = SapFlora.choose(biome.meadow, biome.wetland, Seed.unit(Seed.mix(h +% 3)));
        if (SapFlora.isTree(species) and (nearSpawn(x, z, spawn_clearing) or District.nearRoad(seed, x, z, road_clearance))) continue;
        const shade = 0.9 + 0.2 * Seed.unit(Seed.mix(h +% 5));
        output[count] = .{
            .local_id = @intCast(i),
            .kind = .vegetation,
            .variant = SapFlora.variantOf(species),
            .transform = .{ .position = .{ x, ground - 0.03, z }, .scale = SapFlora.info(species).height * (0.8 + 0.5 * Seed.unit(Seed.mix(h +% 4))) },
            .tint = .{ shade, shade, shade, 1 },
        };
        count += 1;
    };
    return count;
}

/// The centre of the richest living-sap meadow within about 700 m of the origin (the sum of the
/// weights around each grid point), for review views and tests.
pub fn sapMeadowSpot(seed: u64) [2]f32 {
    var best: [2]f32 = .{ 0, 0 };
    var best_sum: f32 = -1;
    var zi: i32 = -20;
    while (zi <= 20) : (zi += 1) {
        var xi: i32 = -20;
        while (xi <= 20) : (xi += 1) {
            const x = @as(f32, @floatFromInt(xi)) * 36;
            const z = @as(f32, @floatFromInt(zi)) * 36;
            var sum: f32 = 0;
            for ([_]f32{ -18, 0, 18 }) |dz| for ([_]f32{ -18, 0, 18 }) |dx| {
                const px = x + dx;
                const pz = z + dz;
                const key = Key.fromPosition(px, pz);
                const regional = Chunk.regionalSeed(seed, key.x, key.z);
                const ground = CityHeightmaps.heightAt(seed, px, pz);
                const sx = CityHeightmaps.heightAt(seed, px - 0.5, pz) - CityHeightmaps.heightAt(seed, px + 0.5, pz);
                const sz = CityHeightmaps.heightAt(seed, px, pz - 0.5) - CityHeightmaps.heightAt(seed, px, pz + 0.5);
                sum += Biome.sapMeadowWeight(regional, px, pz, ground, @sqrt(sx * sx + sz * sz));
            };
            // Stay off the spawn clearing and the district: they carry no wild plants.
            if (sum > best_sum and !nearSpawn(x, z, 60)) {
                best_sum = sum;
                best = .{ x, z };
            }
        }
    }
    return best;
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

test "seeded scatter distributes all native flora and four canopy species reproducibly" {
    var first: [capacity]Object = undefined;
    var second: [capacity]Object = undefined;
    var species_mask: u32 = 0;
    for (0..10) |z| for (0..10) |x| {
        const key: Key = .{ .x = @as(i32, @intCast(x)) - 5, .z = @as(i32, @intCast(z)) - 5 };
        const count = generate(987654321, key, &first);
        try std.testing.expectEqual(count, generate(987654321, key, &second));
        try std.testing.expectEqualSlices(Object, first[0..count], second[0..count]);
        for (first[0..count]) |object| if (object.kind == .vegetation) {
            if (SapFlora.speciesOf(object.variant) != null) continue;
            try std.testing.expect(object.variant < @import("Vegetation.zig").variant_count);
            species_mask |= @as(u32, 1) << @intCast(object.variant);
        };
    };
    try std.testing.expectEqual((@as(u32, 1) << Vegetation.variant_count) - 1, species_mask);
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
        } else if (SapFlora.speciesOf(o.variant) == null) try std.testing.expect(o.local_id < candidates);
    };
    try std.testing.expect(boulders > 50);
    for (kinds) |k| try std.testing.expect(k);
}

test "tall trees keep clear of district roads and plazas but still grow beside them" {
    const seed: u64 = 7;
    try std.testing.expect(District.nearRoad(seed, 140, -80, 0));
    var trees: usize = 0;
    var output: [capacity]Object = undefined;
    var x: i32 = -3;
    while (x <= 4) : (x += 1) {
        var z: i32 = -2;
        while (z <= 4) : (z += 1) {
            for (output[0..generate(seed, .{ .x = x, .z = z }, &output)]) |o| {
                if (o.kind != .vegetation or !Vegetation.isTree(o.variant)) continue;
                trees += 1;
                try std.testing.expect(!District.nearRoad(seed, o.transform.position[0], o.transform.position[2], road_clearance));
            }
        }
    }
    try std.testing.expect(trees > 0);
}

test "living-sap flora grows in its own candidates, every species appears, trees keep off roads" {
    const seed: u64 = 42;
    var objects: [capacity]Object = undefined;
    var seen: [SapFlora.count]bool = @splat(false);
    var total: usize = 0;
    var trees: usize = 0;
    var ids: [capacity]bool = undefined;
    for (0..18) |zi| for (0..18) |xi| {
        const key: Key = .{ .x = @as(i32, @intCast(xi)) - 9, .z = @as(i32, @intCast(zi)) - 9 };
        const n = generate(seed, key, &objects);
        ids = @splat(false);
        for (objects[0..n]) |o| {
            try std.testing.expect(!ids[o.local_id]);
            ids[o.local_id] = true;
            const species = SapFlora.speciesOf(o.variant) orelse continue;
            total += 1;
            seen[@intFromEnum(species)] = true;
            try std.testing.expectEqual(Kind.vegetation, o.kind);
            try std.testing.expect(o.local_id >= candidates + boulder_candidates and o.local_id < capacity);
            const height = SapFlora.info(species).height;
            try std.testing.expect(o.transform.scale >= height * 0.79 and o.transform.scale <= height * 1.31);
            if (SapFlora.isTree(species)) {
                trees += 1;
                try std.testing.expect(!District.nearRoad(seed, o.transform.position[0], o.transform.position[2], road_clearance));
                try std.testing.expect(!nearSpawn(o.transform.position[0], o.transform.position[2], spawn_clearing));
            }
        }
    };
    try std.testing.expect(total > 400);
    try std.testing.expect(trees > 10 and trees < total / 3);
    for (seen) |x| try std.testing.expect(x);
    // No living-sap plant on the ice sheet, and the same chunk twice gives the same plants.
    const ice: Key = .{ .x = Region.antarctica.chunks[0] + 1, .z = Region.antarctica.chunks[1] + 1 };
    for (objects[0..generate(seed, ice, &objects)]) |o| try std.testing.expect(SapFlora.speciesOf(o.variant) == null);
    var again: [capacity]Object = undefined;
    const key: Key = .{ .x = -2, .z = 3 };
    const first = generate(seed, key, &objects);
    try std.testing.expectEqual(first, generate(seed, key, &again));
    try std.testing.expectEqualSlices(Object, objects[0..first], again[0..first]);
}

test "the review spot is a rich sap meadow that actually grows plants" {
    const seed: u64 = 42;
    const spot = sapMeadowSpot(seed);
    const centre = Key.fromPosition(spot[0], spot[1]);
    var objects: [capacity]Object = undefined;
    var near: usize = 0;
    // The spot may sit near a chunk edge: look at the chunk and its eight neighbours.
    for ([_]i32{ -1, 0, 1 }) |dk| for ([_]i32{ -1, 0, 1 }) |dj| {
        const key: Key = .{ .x = centre.x + dk, .z = centre.z + dj };
        for (objects[0..generate(seed, key, &objects)]) |o| {
            if (SapFlora.speciesOf(o.variant) == null) continue;
            const dx = o.transform.position[0] - spot[0];
            const dz = o.transform.position[2] - spot[1];
            if (dx * dx + dz * dz < 60 * 60) near += 1;
        }
    };
    try std.testing.expect(near >= 12);
}
