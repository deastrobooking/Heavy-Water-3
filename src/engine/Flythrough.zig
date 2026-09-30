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

/// Keep the Arbor in view while crossing its LOD threshold in both directions.
/// The warm-up and endpoints sit beside the ramp; the midpoint is a 1 km vista.
pub fn canopyCamera(frame: u64, length: u32, origin: [3]f32) Camera {
    const t = std.math.clamp(@as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(@max(length -| 1, 1))), 0, 1);
    const travel = if (t < 0.5) t * 2 else (1 - t) * 2;
    const distance = 30 + 980 * travel;
    const eye_height = 44 + 56 * travel;
    const target_height = 40 + 120 * travel;
    return .{
        .position = math.vec3(origin[0], origin[1] + eye_height, origin[2] - distance),
        .yaw = 0,
        .pitch = std.math.atan2(target_height - eye_height, distance),
    };
}

test "canopy route frames the Arbor up close and at a kilometer, then returns" {
    const origin: [3]f32 = .{ 60, 12, 80 };
    const near = canopyCamera(0, 301, origin);
    const far = canopyCamera(150, 301, origin);
    try std.testing.expectEqualDeep(near, canopyCamera(300, 301, origin));
    try std.testing.expect(origin[2] - near.position.z() < 50);
    try std.testing.expect(origin[2] - far.position.z() >= 1000);
    try std.testing.expect(near.pitch < 0 and far.pitch > 0);
}
