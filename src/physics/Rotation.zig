//! Small vector, quaternion, and 3×3 matrix helpers for rigid-body physics. Quaternions are
//! (x, y, z, w); matrices are row-major [3][3]. Kept dependency-free so physics has no
//! math-library coupling.
const std = @import("std");

pub const Vec3 = [3]f32;
pub const Quat = [4]f32;
pub const Mat3 = [3][3]f32;
pub const identity: Quat = .{ 0, 0, 0, 1 };

pub fn add(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}

pub fn sub(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

pub fn scale(a: Vec3, s: f32) Vec3 {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}

pub fn dot(a: Vec3, b: Vec3) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

pub fn length(a: Vec3) f32 {
    return @sqrt(dot(a, a));
}

pub fn normalize(a: Vec3) Vec3 {
    const l = length(a);
    return if (l > 1e-12) scale(a, 1 / l) else .{ 0, 0, 0 };
}

pub fn mul(a: Quat, b: Quat) Quat {
    return .{
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    };
}

pub fn conjugate(q: Quat) Quat {
    return .{ -q[0], -q[1], -q[2], q[3] };
}

pub fn normalizeQuat(q: Quat) Quat {
    const l = @sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
    return if (l > 1e-12) .{ q[0] / l, q[1] / l, q[2] / l, q[3] / l } else identity;
}

pub fn axisAngle(axis: Vec3, angle: f32) Quat {
    const n = normalize(axis);
    const s = @sin(angle / 2);
    return .{ n[0] * s, n[1] * s, n[2] * s, @cos(angle / 2) };
}

/// v' = q v q⁻¹, expanded for unit quaternions.
pub fn rotate(q: Quat, v: Vec3) Vec3 {
    const u: Vec3 = .{ q[0], q[1], q[2] };
    const t = scale(cross(u, v), 2);
    return add(add(v, scale(t, q[3])), cross(u, t));
}

pub fn inverseRotate(q: Quat, v: Vec3) Vec3 {
    return rotate(conjugate(q), v);
}

/// Integrates angular velocity (world space) over dt and renormalizes.
pub fn integrate(q: Quat, omega: Vec3, dt: f32) Quat {
    const dq = mul(.{ omega[0], omega[1], omega[2], 0 }, q);
    return normalizeQuat(.{ q[0] + dq[0] * dt / 2, q[1] + dq[1] * dt / 2, q[2] + dq[2] * dt / 2, q[3] + dq[3] * dt / 2 });
}

pub fn toMatrix(q: Quat) Mat3 {
    const x, const y, const z, const w = q;
    return .{
        .{ 1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w) },
        .{ 2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w) },
        .{ 2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y) },
    };
}

pub fn mulVec(m: Mat3, v: Vec3) Vec3 {
    return .{ dot(m[0], v), dot(m[1], v), dot(m[2], v) };
}

/// World-space inverse inertia R · diag(inv_local) · Rᵀ applied to v.
pub fn applyInverseInertia(q: Quat, inv_local: Vec3, v: Vec3) Vec3 {
    const local = inverseRotate(q, v);
    return rotate(q, .{ local[0] * inv_local[0], local[1] * inv_local[1], local[2] * inv_local[2] });
}

/// Heading angle about +Y of the body's local +Z axis (0 = facing +Z).
pub fn yaw(q: Quat) f32 {
    const f = rotate(q, .{ 0, 0, 1 });
    return std.math.atan2(f[0], f[2]);
}

test "quaternion rotation, matrix form, and integration agree" {
    const q = axisAngle(.{ 0, 1, 0 }, std.math.pi / 2.0);
    const v = rotate(q, .{ 0, 0, 1 });
    try std.testing.expectApproxEqAbs(@as(f32, 1), v[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v[2], 1e-6);
    const m = mulVec(toMatrix(q), .{ 0, 0, 1 });
    for (0..3) |i| try std.testing.expectApproxEqAbs(v[i], m[i], 1e-6);
    const back = inverseRotate(q, v);
    try std.testing.expectApproxEqAbs(@as(f32, 1), back[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), yaw(q), 1e-5);
    // One second at π/2 rad/s about Y in small steps reaches the same orientation.
    var r = identity;
    for (0..1000) |_| r = integrate(r, .{ 0, std.math.pi / 2.0, 0 }, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), yaw(r), 1e-3);
}
