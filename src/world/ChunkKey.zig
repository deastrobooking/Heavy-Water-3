const std = @import("std");
const Key = @This();
pub const extent: f32 = 128;
// Float terrain sampling remains useful in this bounded world; floating origins come later.
pub const limit: i32 = 4096;
x: i32,
z: i32,

pub fn fromPosition(x: f32, z: f32) Key {
    return .{ .x = coordinate(x), .z = coordinate(z) };
}

fn coordinate(value: f32) i32 {
    if (!std.math.isFinite(value)) return 0;
    return @intFromFloat(std.math.clamp(@floor((value + extent / 2) / extent), -@as(f32, limit), @as(f32, limit)));
}

pub fn eql(a: Key, b: Key) bool {
    return a.x == b.x and a.z == b.z;
}

pub fn distance(a: Key, b: Key) u32 {
    return @intCast(@max(@abs(@as(i64, a.x) - b.x), @abs(@as(i64, a.z) - b.z)));
}

pub fn valid(self: Key) bool {
    return @abs(@as(i64, self.x)) <= limit and @abs(@as(i64, self.z)) <= limit;
}

test "centered chunk boundaries handle negative space and nonfinite inputs" {
    try std.testing.expectEqual(Key{ .x = 0, .z = -1 }, fromPosition(-64, -64.01));
    try std.testing.expectEqual(Key{ .x = 1, .z = 0 }, fromPosition(64, 63.9));
    try std.testing.expectEqual(Key{ .x = 0, .z = limit }, fromPosition(std.math.nan(f32), 1e20));
}
