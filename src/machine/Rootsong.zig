//! Rootsong: Arbors whose roots overlap form a root group, and Rootsong devices rooted in any
//! tree of a group share that group's channels. A tree's roots reach half its height from the
//! trunk, so tall trees far apart can still hear each other while isolated ones cannot.
const std = @import("std");
const R = @import("../physics/Rotation.zig");

pub const Tree = struct { origin: R.Vec3, height: f32 };
pub const reach_per_height: f32 = 0.5;

/// Group label per tree: the lowest tree index in its root-connected set.
pub fn groups(comptime n: usize, trees: [n]Tree) [n]u8 {
    var parent: [n]u8 = undefined;
    for (&parent, 0..) |*p, i| p.* = @intCast(i);
    for (0..n) |i| for (0..i) |j| {
        const d = R.sub(trees[i].origin, trees[j].origin);
        const apart = @sqrt(d[0] * d[0] + d[2] * d[2]);
        if (apart > (trees[i].height + trees[j].height) * reach_per_height) continue;
        const a = find(&parent, @intCast(i));
        const b = find(&parent, @intCast(j));
        parent[@max(a, b)] = @min(a, b);
    };
    var out: [n]u8 = undefined;
    for (&out, 0..) |*g, i| g.* = find(&parent, @intCast(i));
    return out;
}

fn find(parent: []u8, x: u8) u8 {
    var i = x;
    while (parent[i] != i) i = parent[i];
    return i;
}

test "overlapping roots join groups transitively; distant trees stay alone" {
    const g = groups(4, .{
        .{ .origin = .{ 0, 0, 0 }, .height = 300 },
        .{ .origin = .{ 250, 0, 0 }, .height = 300 }, // 250 m apart, reach 300: joined
        .{ .origin = .{ 520, 50, 0 }, .height = 300 }, // joined to 1, so to 0
        .{ .origin = .{ 0, 0, -400 }, .height = 200 }, // 400 m from 0, reach 250: alone
    });
    try std.testing.expectEqual([4]u8{ 0, 0, 0, 3 }, g);
}
