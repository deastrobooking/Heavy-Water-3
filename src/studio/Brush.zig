//! Brush on a one-dimensional control cage: a short array of values along a shape's length (the
//! hover car's nine hull stations), pulled together with a smooth falloff so one stroke moves a
//! whole region without creases. Results clamp to the caller's valid range, so a stroke can never
//! produce an invalid cage.
const std = @import("std");

/// Adds `delta` to the values within `radius` stations of `center` (in station units, so 4.5 is
/// halfway between stations 4 and 5), weighted by a smoothstep that is zero at the edge.
pub fn pullStations(values: []f32, center: f32, radius: f32, delta: f32, lo: f32, hi: f32) void {
    if (!std.math.isFinite(center) or !std.math.isFinite(radius) or !std.math.isFinite(delta) or radius <= 0) return;
    for (values, 0..) |*v, i| {
        const d = @abs(@as(f32, @floatFromInt(i)) - center);
        if (d >= radius) continue;
        const t = 1 - d / radius;
        const weight = t * t * (3 - 2 * t);
        v.* = std.math.clamp(v.* + delta * weight, lo, hi);
    }
}

test "a pull is strongest at the center, fades smoothly, leaves distant stations and clamps" {
    var cage: [9]f32 = @splat(1);
    pullStations(&cage, 4, 2.5, 0.3, 0.6, 1.5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.3), cage[4], 1e-6);
    try std.testing.expect(cage[3] > 1 and cage[3] < cage[4]); // nearer moves more
    try std.testing.expectApproxEqAbs(cage[3], cage[5], 1e-6); // symmetric about the center
    try std.testing.expectEqual(@as(f32, 1), cage[0]); // outside the radius
    try std.testing.expectEqual(@as(f32, 1), cage[8]);
    pullStations(&cage, 4, 2.5, 5, 0.6, 1.5); // a huge pull clamps instead of leaving the range
    try std.testing.expectEqual(@as(f32, 1.5), cage[4]);
    var untouched: [3]f32 = .{ 1, 1, 1 };
    pullStations(&untouched, 1, 2, std.math.nan(f32), 0.6, 1.5); // non-finite input is ignored
    try std.testing.expectEqualSlices(f32, &.{ 1, 1, 1 }, &untouched);
}
