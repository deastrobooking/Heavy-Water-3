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

test "frustum rejects outside spheres but keeps intersecting ones" {
    try std.testing.expect(sphereVisible(math.Mat4x4.ident, .{ 0, 0, 0.5 }, 0.1));
    try std.testing.expect(!sphereVisible(math.Mat4x4.ident, .{ 3, 0, 0.5 }, 0.1));
    try std.testing.expect(sphereVisible(math.Mat4x4.ident, .{ 1.05, 0, 0.5 }, 0.1));
    try std.testing.expect(!sphereVisible(math.Mat4x4.ident, .{ 0, 0, -1 }, 0.1));
}
