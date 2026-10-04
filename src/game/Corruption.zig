//! Deterministic Hive corruption that grows from living surface nests as market days pass.
const std = @import("std");

pub const Tuning = struct {
    first_day: u64 = 1,
    initial_radius: f32 = 14,
    growth_per_day: f32 = 9,
    max_radius: f32 = 68,
    patch_spacing: f32 = 8,
    patch_depth: f32 = 0.045,
};
pub const tuning: Tuning = .{};

pub fn radius(day: u64) f32 {
    if (day < tuning.first_day) return 0;
    return @min(tuning.max_radius, tuning.initial_radius + @as(f32, @floatFromInt(day - tuning.first_day)) * tuning.growth_per_day);
}

/// Whether the Hive has stained this horizontal point around a nest.
pub fn covers(day: u64, dx: f32, dz: f32) bool {
    const r = radius(day);
    return r > 0 and dx * dx + dz * dz <= r * r;
}

test "corruption expands by market day, stops at dead nests, and has a hard radius cap" {
    try std.testing.expectEqual(@as(f32, 0), radius(0));
    try std.testing.expectEqual(tuning.initial_radius, radius(1));
    try std.testing.expect(radius(2) > radius(1));
    try std.testing.expectEqual(tuning.max_radius, radius(100));
    try std.testing.expect(covers(2, 0, 0));
    try std.testing.expect(!covers(2, radius(2) + 0.1, 0));
}
