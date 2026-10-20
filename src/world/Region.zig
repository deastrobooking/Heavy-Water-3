const std = @import("std");
const ChunkKey = @import("ChunkKey.zig");
const Seed = @import("../procedural/Seed.zig");
const Worlds = @import("../procedural/Worlds.zig");

/// A named place with its own terrain seed on the shared streaming grid. Everything outside every
/// region is the world's default (Detroit and its wilds). Adding a place with its own ground is one
/// row here; terrain, scatter, collision and the map read it through `seedAt` and `at`.
pub const Region = struct {
    /// Map title.
    title: []const u8,
    /// XORed into the world seed, then mixed, to give the region independent terrain and flora.
    salt: u64,
    /// Inclusive chunk bounds (min x, min z, max x, max z).
    chunks: [4]i32,
    /// Where fast travel lands, in world metres.
    arrival: [2]f32,
    /// Null means the region is part of the terrain fallback, not a travel destination.
    travel_label: ?[]const u8 = null,
    /// The default region owns terrain not covered by a destination-specific region.
    is_default: bool = false,

    pub fn contains(self: Region, cx: i32, cz: i32) bool {
        if (self.is_default) return true;
        return cx >= self.chunks[0] and cz >= self.chunks[1] and cx <= self.chunks[2] and cz <= self.chunks[3];
    }

    pub fn seed(self: Region, world: u64) u64 {
        return if (self.is_default) world else Seed.mix(world ^ self.salt);
    }
};

fn cityRegion(comptime id: Worlds.CityId) Region {
    inline for (Worlds.cities) |city| if (city.id == id) {
        const data = city.region orelse @compileError("city has no playable region data");
        return .{ .title = data.title, .salt = data.salt, .chunks = data.chunks, .arrival = data.arrival, .travel_label = data.travel_label, .is_default = id == .arboris_reach };
    };
    @compileError("unknown city region");
}

/// Playable regional data is authored with its city in `Worlds.zig`; catalog-only cities are
/// intentionally absent until they have terrain and a safe arrival.
pub const detroit = cityRegion(.arboris_reach);
pub const new_york = cityRegion(.hudson_reach);
pub const all = blk: {
    var count: usize = 0;
    for (Worlds.cities) |city| if (city.region != null) {
        count += 1;
    };
    var regions: [count]Region = undefined;
    var index: usize = 0;
    for (Worlds.cities) |city| if (city.region) |data| {
        regions[index] = .{
            .title = data.title,
            .salt = data.salt,
            .chunks = data.chunks,
            .arrival = data.arrival,
            .travel_label = data.travel_label,
            .is_default = city.id == .arboris_reach,
        };
        index += 1;
    };
    break :blk regions;
};
pub const default_index = blk: {
    for (all, 0..) |region, index| if (region.is_default) break :blk index;
    @compileError("the playable region catalog needs one default region");
};
pub const default_title = all[default_index].title;

pub fn at(cx: i32, cz: i32) *const Region {
    for (&all) |*region| if (!region.is_default and region.contains(cx, cz)) return region;
    return &all[default_index];
}

/// The terrain seed of the chunk that owns (cx, cz).
pub fn seedAt(world: u64, cx: i32, cz: i32) u64 {
    return at(cx, cz).seed(world);
}

/// The terrain seed that owns world position (x, z).
pub fn seedAtPosition(world: u64, x: f32, z: f32) u64 {
    const key = ChunkKey.fromPosition(x, z);
    return seedAt(world, key.x, key.z);
}

test "every region contains its own arrival and gets an independent seed" {
    for (all) |r| {
        const key = ChunkKey.fromPosition(r.arrival[0], r.arrival[1]);
        try std.testing.expect(r.contains(key.x, key.z));
        if (r.is_default) {
            try std.testing.expectEqual(@as(u64, 42), seedAt(42, key.x, key.z));
        } else try std.testing.expect(seedAt(42, key.x, key.z) != 42);
    }
    try std.testing.expectEqual(@as(u64, 42), seedAt(42, 0, 0));
}

test "regions do not overlap" {
    for (all, 0..) |a, i| for (all[i + 1 ..]) |b| {
        if (a.is_default or b.is_default) continue;
        try std.testing.expect(a.chunks[2] < b.chunks[0] or b.chunks[2] < a.chunks[0] or a.chunks[3] < b.chunks[1] or b.chunks[3] < a.chunks[1]);
    };
}
