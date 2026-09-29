const std = @import("std");
const Time = @This();
pub const fixed_dt: f32 = 1.0 / 60.0;
pub const max_steps = 8;
accumulator: f32 = 0,
tick: u64 = 0,
dropped_seconds: f32 = 0,

pub fn advance(self: *Time, elapsed: f32) u32 {
    if (!std.math.isFinite(elapsed) or elapsed <= 0) return 0;
    const accepted = @min(elapsed, 0.25);
    self.dropped_seconds += elapsed - accepted;
    self.accumulator += accepted;
    var steps: u32 = 0;
    while (self.accumulator >= fixed_dt and steps < max_steps) : (steps += 1) {
        self.accumulator -= fixed_dt;
        self.tick += 1;
    }
    if (self.accumulator >= fixed_dt) {
        const remainder = @mod(self.accumulator, fixed_dt);
        self.dropped_seconds += self.accumulator - remainder;
        self.accumulator = remainder;
    }
    return steps;
}

test "fixed step caps catch-up and accounts for discarded wall time" {
    var time: Time = .{};
    try std.testing.expectEqual(@as(u32, 2), time.advance(fixed_dt * 2));
    try std.testing.expectEqual(@as(u32, max_steps), time.advance(1));
    try std.testing.expect(time.accumulator < fixed_dt);
    try std.testing.expectApproxEqAbs(@as(f32, 1) + fixed_dt * 2, @as(f32, @floatFromInt(time.tick)) * fixed_dt + time.accumulator + time.dropped_seconds, 0.00001);
}
