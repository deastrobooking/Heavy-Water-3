const std = @import("std");
const Camera = @import("../world/Camera.zig");
const math = @import("mach").math;
pub const warmup_frames = 60;

/// A frame-indexed outbound/return route crosses positive and negative chunk boundaries.
pub fn camera(frame: u64, length: u32) Camera {
    const t = std.math.clamp(@as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(@max(length -| 1, 1))), 0, 1);
    const travel = if (t < 0.5) t * 2 else (1 - t) * 2;
    return .{
        .position = math.vec3(-512 + travel * 2048, 42, -256 + travel * 512),
        .yaw = if (t < 0.5) 1.3258 else 1.3258 + std.math.pi,
        .pitch = -0.28,
    };
}

test "fly-through returns to the same origin independent of frame rate" {
    const a = camera(0, 360);
    const b = camera(359, 360);
    try std.testing.expectEqualDeep(a.position, b.position);
    try std.testing.expect(camera(180, 360).position.x() > 1500);
}
