const std = @import("std");
pub const generator_version: u32 = 4;

/// SplitMix64 finalizer, explicitly wrapping and independent of std.Random versions.
pub fn mix(value: u64) u64 {
    var x = value +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

pub fn at(seed: u64, x: i64, z: i64) u64 {
    return mix(seed ^ mix(@bitCast(x)) ^ (mix(@bitCast(z)) *% 0x9e3779b97f4a7c15));
}

pub fn unit(value: u64) f32 {
    return @as(f32, @floatFromInt(value >> 40)) / 16777216.0;
}

test "seed hash has a stable golden value" {
    try std.testing.expectEqual(@as(u64, 0xe220a8397b1dcdaf), mix(0));
    try std.testing.expect(unit(mix(17)) >= 0 and unit(mix(17)) < 1);
}
