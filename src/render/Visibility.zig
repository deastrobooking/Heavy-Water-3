const math = @import("mach").math;
const std = @import("std");

/// Conservative sphere/frustum test using the WebGPU clip volume: -w <= x,y <= w, 0 <= z <= w.
pub fn sphereVisible(vp: math.Mat4x4, center: [3]f32, radius: f32) bool {
    const r0 = vp.row(0);
    const r1 = vp.row(1);
    const r2 = vp.row(2);
    const r3 = vp.row(3);
    const planes = [_]math.Vec4{ r3.add(&r0), r3.sub(&r0), r3.add(&r1), r3.sub(&r1), r2, r3.sub(&r2) };
    for (planes) |p| {
        const distance = p.x() * center[0] + p.y() * center[1] + p.z() * center[2] + p.w();
        const normal_length = @sqrt(p.x() * p.x() + p.y() * p.y() + p.z() * p.z());
        if (distance < -radius * normal_length) return false;
    }
    return true;
}

/// The six frustum planes as (normal, distance) with unit normals pointing inward, for the
/// vertex stage's per-instance culling: a sphere is outside when dot(n, c) + d < −r.
pub fn frustumPlanes(vp: math.Mat4x4) [6][4]f32 {
    const r0 = vp.row(0);
    const r1 = vp.row(1);
    const r2 = vp.row(2);
    const r3 = vp.row(3);
    const raw = [_]math.Vec4{ r3.add(&r0), r3.sub(&r0), r3.add(&r1), r3.sub(&r1), r2, r3.sub(&r2) };
    var out: [6][4]f32 = undefined;
    for (raw, &out) |p, *o| {
        const n = @sqrt(p.x() * p.x() + p.y() * p.y() + p.z() * p.z());
        const k: f32 = if (n > 0) 1 / n else 0;
        o.* = .{ p.x() * k, p.y() * k, p.z() * k, p.w() * k };
    }
    return out;
}

test "normalized planes agree with the sphere test" {
    const Camera = @import("../world/Camera.zig");
    const c: Camera = .{ .position = math.vec3(10, 20, -30), .yaw = 0.7, .pitch = -0.2 };
    const vp = c.viewProjection(1.6);
    const ps = frustumPlanes(vp);
    var seed: u32 = 1;
    for (0..500) |_| {
        seed = seed *% 1664525 +% 1013904223;
        const center: [3]f32 = .{ @as(f32, @floatFromInt(seed % 400)) - 190, @as(f32, @floatFromInt(seed / 400 % 100)), @as(f32, @floatFromInt(seed / 40000 % 400)) - 200 };
        var inside = true;
        for (ps) |p| inside = inside and p[0] * center[0] + p[1] * center[1] + p[2] * center[2] + p[3] >= -2;
        try std.testing.expectEqual(sphereVisible(vp, center, 2), inside);
    }
}

test "frustum rejects outside spheres but keeps intersecting ones" {
    try std.testing.expect(sphereVisible(math.Mat4x4.ident, .{ 0, 0, 0.5 }, 0.1));
    try std.testing.expect(!sphereVisible(math.Mat4x4.ident, .{ 3, 0, 0.5 }, 0.1));
    try std.testing.expect(sphereVisible(math.Mat4x4.ident, .{ 1.05, 0, 0.5 }, 0.1));
    try std.testing.expect(!sphereVisible(math.Mat4x4.ident, .{ 0, 0, -1 }, 0.1));
}
