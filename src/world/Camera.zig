const std = @import("std");
const math = @import("mach").math;
const Input = @import("../engine/Input.zig");
const Camera = @This();
position: math.Vec3 = math.vec3(0, 27, -58),
yaw: f32 = 0,
pitch: f32 = -0.30,
fov: f32 = std.math.pi / 3.0,
near: f32 = 0.1,

pub fn look(self: *Camera, x: f32, y: f32) void {
    self.yaw = @mod(self.yaw + x * 0.0025, 2 * std.math.pi);
    self.pitch = std.math.clamp(self.pitch - y * 0.0025, -1.5, 1.5);
}

pub fn forward(self: Camera) math.Vec3 {
    return math.vec3(@sin(self.yaw) * @cos(self.pitch), @sin(self.pitch), @cos(self.yaw) * @cos(self.pitch));
}

pub fn move(self: *Camera, input: Input, dt: f32) void {
    const f = self.forward();
    const r = math.vec3(@cos(self.yaw), 0, -@sin(self.yaw));
    var delta = f.mulScalar(input.forward).add(&r.mulScalar(input.right)).add(&math.vec3(0, input.up, 0));
    const length = @sqrt(delta.dot(&delta));
    if (length > 0) delta = delta.divScalar(length);
    self.position = self.position.add(&delta.mulScalar(dt * (if (input.fast) @as(f32, 35) else 12)));
}

/// Reversed, infinite-far perspective: depth = near / z, so the near plane maps to 1 and
/// infinity to 0. With a float depth buffer this keeps precision across kilometers.
pub fn projection(self: Camera, aspect: f32) math.Mat4x4 {
    const y = 1 / @tan(self.fov / 2);
    return math.Mat4x4.init(&math.vec4(y / aspect, 0, 0, 0), &math.vec4(0, y, 0, 0), &math.vec4(0, 0, 0, self.near), &math.vec4(0, 0, 1, 0));
}

pub fn viewProjection(self: Camera, aspect: f32) math.Mat4x4 {
    const f = self.forward();
    const r = math.vec3(@cos(self.yaw), 0, -@sin(self.yaw));
    const u = f.cross(&r);
    const view = math.Mat4x4.init(&math.vec4(r.x(), r.y(), r.z(), -r.dot(&self.position)), &math.vec4(u.x(), u.y(), u.z(), -u.dot(&self.position)), &math.vec4(f.x(), f.y(), f.z(), -f.dot(&self.position)), &math.vec4(0, 0, 0, 1));
    return self.projection(aspect).mul(&view);
}

test "reversed infinite projection maps near to one, far toward zero, monotonically" {
    const c: Camera = .{};
    const p = c.projection(16.0 / 9.0);
    const n = p.mulVec(&math.vec4(0, 0, c.near, 1));
    try std.testing.expectApproxEqAbs(@as(f32, 1), n.z() / n.w(), 0.00001);
    var previous: f32 = 1;
    for ([_]f32{ 1, 10, 100, 1000, 5000 }) |z| {
        const d = p.mulVec(&math.vec4(0, 0, z, 1));
        const depth = d.z() / d.w();
        try std.testing.expect(depth < previous and depth > 0);
        previous = depth;
    }
    // Distinct depths at 1 km and 1.001 km in 32-bit float.
    const a = p.mulVec(&math.vec4(0, 0, 1000, 1));
    const b = p.mulVec(&math.vec4(0, 0, 1001, 1));
    try std.testing.expect(a.z() / a.w() != b.z() / b.w());
}

test "translated and rotated camera projects its forward direction to screen center" {
    const c: Camera = .{ .position = math.vec3(8, 3, -9), .yaw = 1.2, .pitch = 0.4 };
    const target = c.position.add(&c.forward().mulScalar(10));
    const clip = c.viewProjection(1.5).mulVec(&math.vec4(target.x(), target.y(), target.z(), 1));
    try std.testing.expectApproxEqAbs(@as(f32, 0), clip.x() / clip.w(), 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), clip.y() / clip.w(), 0.00001);
    try std.testing.expect(clip.z() > 0 and clip.z() < clip.w());
}
