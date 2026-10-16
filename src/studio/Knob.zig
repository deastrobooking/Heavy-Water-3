//! Macro knobs: one 0 to 1 slider that drives several parameters through small piecewise-linear
//! curves, so "longer" lengthens a hull and moves its fans together. A knob only maps numbers;
//! the studio validates the result before anything is applied.
const std = @import("std");

pub const MapPoint = struct { at: f32, value: f32 };
/// `param` is the caller's parameter index (a studio's `Param` ordinal).
pub const Mapping = struct { param: u8, points: [3]MapPoint };
pub const max_mappings = 4;

name: []const u8,
mappings: [max_mappings]?Mapping = @splat(null),

const Knob = @This();

/// Writes every mapped parameter for a knob position into `params`. The position clamps to 0..1;
/// a non-finite position or a mapping that points past `params` is refused before any write.
pub fn apply(self: Knob, position: f32, params: []f32) error{InvalidKnob}!void {
    if (!std.math.isFinite(position)) return error.InvalidKnob;
    const t = std.math.clamp(position, 0, 1);
    for (self.mappings) |maybe| if (maybe) |m| {
        if (m.param >= params.len) return error.InvalidKnob;
    };
    for (self.mappings) |maybe| if (maybe) |m| {
        params[m.param] = if (t <= m.points[1].at) lerp(m.points[0], m.points[1], t) else lerp(m.points[1], m.points[2], t);
    };
}

fn lerp(a: MapPoint, b: MapPoint, t: f32) f32 {
    if (b.at <= a.at) return b.value;
    return a.value + (b.value - a.value) * std.math.clamp((t - a.at) / (b.at - a.at), 0, 1);
}

test "a knob drives several parameters, clamps its input and refuses bad input without writing" {
    const knob: Knob = .{ .name = "length", .mappings = .{
        .{ .param = 0, .points = .{ .{ .at = 0, .value = 3.5 }, .{ .at = 0.5, .value = 4.5 }, .{ .at = 1, .value = 5.5 } } },
        .{ .param = 1, .points = .{ .{ .at = 0, .value = 1.0 }, .{ .at = 0.5, .value = 1.6 }, .{ .at = 1, .value = 1.8 } } },
        null,
        null,
    } };
    var params = [_]f32{ 0, 0 };
    try knob.apply(0.5, &params);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), params[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), params[1], 1e-5);
    try knob.apply(7, &params); // clamps to 1
    try std.testing.expectApproxEqAbs(@as(f32, 5.5), params[0], 1e-5);
    const before = params;
    try std.testing.expectError(error.InvalidKnob, knob.apply(std.math.nan(f32), &params));
    try std.testing.expectEqualSlices(f32, &before, &params);
    var small = [_]f32{0};
    try std.testing.expectError(error.InvalidKnob, knob.apply(0.5, &small));
    try std.testing.expectEqual(@as(f32, 0), small[0]);
}
