const std = @import("std");
const ChunkKey = @import("ChunkKey.zig");
const Seed = @import("../procedural/Seed.zig");

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

    pub fn contains(self: Region, cx: i32, cz: i32) bool {
        return cx >= self.chunks[0] and cz >= self.chunks[1] and cx <= self.chunks[2] and cz <= self.chunks[3];
    }

    pub fn seed(self: Region, world: u64) u64 {
        return Seed.mix(world ^ self.salt);
    }
};

/// Chunks are 128 m, so these bounds are in those units; the arrival must lie inside them.
pub const new_york: Region = .{ .title = "NEW YORK CITY / HUDSON REACH", .salt = 0x4e4557594f524b, .chunks = .{ 9, -3, 12, 0 }, .arrival = .{ 1320, -180 } };
pub const all = [_]*const Region{&new_york};
pub const default_title = "DETROIT / ARBOR REACH";

pub fn at(cx: i32, cz: i32) ?*const Region {
    for (all) |r| if (r.contains(cx, cz)) return r;
    return null;
}

/// The terrain seed of the chunk that owns (cx, cz).
pub fn seedAt(world: u64, cx: i32, cz: i32) u64 {
    return if (at(cx, cz)) |r| r.seed(world) else world;
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
        try std.testing.expect(seedAt(42, key.x, key.z) != 42);
    }
    try std.testing.expectEqual(@as(u64, 42), seedAt(42, 0, 0));
}

test "regions do not overlap" {
    for (all, 0..) |a, i| for (all[i + 1 ..]) |b| {
        try std.testing.expect(a.chunks[2] < b.chunks[0] or b.chunks[2] < a.chunks[0] or a.chunks[3] < b.chunks[1] or b.chunks[3] < a.chunks[1]);
    };
}
