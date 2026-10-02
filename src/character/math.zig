//! Core linear algebra for the character system.
//!
//! Conventions (used everywhere in this library):
//!   * Right-handed, +Y up, character faces +Z, character's left is +X.
//!   * Mat4 is column-major (`m[col][row]`), matching GPU uniform layout,
//!     so a Mat4 can be uploaded to a shader as-is.
//!   * Quaternions are unit quaternions (x, y, z, w) rotating vectors as q * v * q^-1.

const std = @import("std");

pub const eps: f32 = 1e-6;
pub const pi: f32 = std.math.pi;
pub const tau: f32 = 2.0 * std.math.pi;

pub inline fn clamp(x: f32, lo: f32, hi: f32) f32 {
    return @max(lo, @min(hi, x));
}
pub inline fn saturate(x: f32) f32 {
    return clamp(x, 0, 1);
}
pub inline fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
pub inline fn invLerp(a: f32, b: f32, x: f32) f32 {
    return if (@abs(b - a) < eps) 0 else (x - a) / (b - a);
}
/// Hermite smoothstep, C1 continuous.
pub inline fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
    const t = saturate(invLerp(e0, e1, x));
    return t * t * (3 - 2 * t);
}
/// Quintic smootherstep, C2 continuous (nicer for weight blends).
pub inline fn smootherstep(e0: f32, e1: f32, x: f32) f32 {
    const t = saturate(invLerp(e0, e1, x));
    return t * t * t * (t * (t * 6 - 15) + 10);
}
pub inline fn radians(deg: f32) f32 {
    return deg * (pi / 180.0);
}

// ---------------------------------------------------------------- Vec2
pub const Vec2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,

    pub inline fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
    pub inline fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub inline fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub inline fn scale(a: Vec2, s: f32) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }
    pub inline fn dot(a: Vec2, b: Vec2) f32 {
        return a.x * b.x + a.y * b.y;
    }
    pub inline fn length(a: Vec2) f32 {
        return @sqrt(a.dot(a));
    }
};

// ---------------------------------------------------------------- Vec3
pub const Vec3 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub const zero: Vec3 = .{};
    pub const one: Vec3 = .{ .x = 1, .y = 1, .z = 1 };
    pub const unit_x: Vec3 = .{ .x = 1 };
    pub const unit_y: Vec3 = .{ .y = 1 };
    pub const unit_z: Vec3 = .{ .z = 1 };

    pub inline fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }
    pub inline fn splat(s: f32) Vec3 {
        return .{ .x = s, .y = s, .z = s };
    }
    pub inline fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub inline fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub inline fn mul(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }
    pub inline fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    pub inline fn neg(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = -a.y, .z = -a.z };
    }
    /// a + b * s (fused-style helper used heavily in generators).
    pub inline fn addScaled(a: Vec3, b: Vec3, s: f32) Vec3 {
        return .{ .x = a.x + b.x * s, .y = a.y + b.y * s, .z = a.z + b.z * s };
    }
    pub inline fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
    pub inline fn lengthSq(a: Vec3) f32 {
        return a.dot(a);
    }
    pub inline fn length(a: Vec3) f32 {
        return @sqrt(a.dot(a));
    }
    pub inline fn distance(a: Vec3, b: Vec3) f32 {
        return a.sub(b).length();
    }
    pub fn normalize(a: Vec3) Vec3 {
        const l = a.length();
        return if (l < eps) Vec3.zero else a.scale(1.0 / l);
    }
    /// Normalize with an explicit fallback for degenerate input.
    pub fn normalizeOr(a: Vec3, fallback: Vec3) Vec3 {
        const l = a.length();
        return if (l < eps) fallback else a.scale(1.0 / l);
    }
    pub inline fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return a.add(b.sub(a).scale(t));
    }
    pub inline fn min(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = @min(a.x, b.x), .y = @min(a.y, b.y), .z = @min(a.z, b.z) };
    }
    pub inline fn max(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = @max(a.x, b.x), .y = @max(a.y, b.y), .z = @max(a.z, b.z) };
    }
    /// Remove the component of `a` along unit vector `n`.
    pub inline fn reject(a: Vec3, n: Vec3) Vec3 {
        return a.sub(n.scale(a.dot(n)));
    }
    /// Mirror across the YZ plane (character's left <-> right).
    pub inline fn mirrorX(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = a.y, .z = a.z };
    }
    /// Any unit vector perpendicular to unit `n` (branchless-ish, Duff et al. 2017).
    pub fn anyPerpendicular(n: Vec3) Vec3 {
        const s: f32 = if (n.z >= 0) 1.0 else -1.0;
        const a = -1.0 / (s + n.z);
        const b = n.x * n.y * a;
        return Vec3.init(1.0 + s * n.x * n.x * a, s * b, -s * n.x);
    }
    pub fn approxEq(a: Vec3, b: Vec3, tol: f32) bool {
        return @abs(a.x - b.x) <= tol and @abs(a.y - b.y) <= tol and @abs(a.z - b.z) <= tol;
    }
};

pub const Vec4 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,
    pub inline fn init(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }
    pub inline fn xyz(a: Vec4) Vec3 {
        return .{ .x = a.x, .y = a.y, .z = a.z };
    }
};

// ---------------------------------------------------------------- Quat
pub const Quat = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 1,

    pub const identity: Quat = .{};

    pub fn fromAxisAngle(axis: Vec3, angle: f32) Quat {
        const a = axis.normalize();
        const h = angle * 0.5;
        const s = @sin(h);
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s, .w = @cos(h) };
    }
    /// Intrinsic rotation: yaw (Y), then pitch (X), then roll (Z).
    pub fn fromEuler(pitch: f32, yaw: f32, roll: f32) Quat {
        const qy = fromAxisAngle(Vec3.unit_y, yaw);
        const qx = fromAxisAngle(Vec3.unit_x, pitch);
        const qz = fromAxisAngle(Vec3.unit_z, roll);
        return qy.mul(qx).mul(qz);
    }
    /// Shortest-arc rotation taking unit `from` onto unit `to`.
    pub fn fromTo(from: Vec3, to: Vec3) Quat {
        const d = from.dot(to);
        if (d < -1.0 + 1e-6) {
            // 180 degrees: rotate about any perpendicular axis.
            return fromAxisAngle(Vec3.anyPerpendicular(from), pi);
        }
        const c = from.cross(to);
        const q: Quat = .{ .x = c.x, .y = c.y, .z = c.z, .w = 1.0 + d };
        return q.normalize();
    }
    /// Rotation whose local +Z maps to `forward` and +Y is as close to `up` as possible.
    pub fn lookRotation(forward: Vec3, up: Vec3) Quat {
        const f = forward.normalize();
        const r = up.cross(f).normalizeOr(Vec3.anyPerpendicular(f));
        const u = f.cross(r);
        return Mat3.fromColumns(r, u, f).toQuat();
    }
    pub inline fn mul(a: Quat, b: Quat) Quat {
        return .{
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        };
    }
    pub inline fn conjugate(q: Quat) Quat {
        return .{ .x = -q.x, .y = -q.y, .z = -q.z, .w = q.w };
    }
    pub inline fn dot(a: Quat, b: Quat) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    }
    pub fn normalize(q: Quat) Quat {
        const l = @sqrt(q.dot(q));
        if (l < eps) return identity;
        const s = 1.0 / l;
        return .{ .x = q.x * s, .y = q.y * s, .z = q.z * s, .w = q.w * s };
    }
    /// Rotate a vector: v' = v + 2w(u x v) + 2u x (u x v).
    pub fn rotate(q: Quat, v: Vec3) Vec3 {
        const u = Vec3.init(q.x, q.y, q.z);
        const t = u.cross(v).scale(2.0);
        return v.add(t.scale(q.w)).add(u.cross(t));
    }
    pub fn nlerp(a: Quat, b0: Quat, t: f32) Quat {
        const b = if (a.dot(b0) < 0) Quat{ .x = -b0.x, .y = -b0.y, .z = -b0.z, .w = -b0.w } else b0;
        const q: Quat = .{
            .x = lerp(a.x, b.x, t),
            .y = lerp(a.y, b.y, t),
            .z = lerp(a.z, b.z, t),
            .w = lerp(a.w, b.w, t),
        };
        return q.normalize();
    }
    pub fn slerp(a: Quat, b0: Quat, t: f32) Quat {
        var b = b0;
        var d = a.dot(b);
        if (d < 0) {
            d = -d;
            b = .{ .x = -b.x, .y = -b.y, .z = -b.z, .w = -b.w };
        }
        if (d > 0.9995) return nlerp(a, b, t);
        const theta = std.math.acos(d);
        const s = @sin(theta);
        const wa = @sin((1 - t) * theta) / s;
        const wb = @sin(t * theta) / s;
        return .{
            .x = a.x * wa + b.x * wb,
            .y = a.y * wa + b.y * wb,
            .z = a.z * wa + b.z * wb,
            .w = a.w * wa + b.w * wb,
        };
    }
};

// ---------------------------------------------------------------- Mat3
pub const Mat3 = extern struct {
    /// Column-major: m[col][row].
    m: [3][3]f32,

    pub fn fromColumns(c0: Vec3, c1: Vec3, c2: Vec3) Mat3 {
        return .{ .m = .{
            .{ c0.x, c0.y, c0.z },
            .{ c1.x, c1.y, c1.z },
            .{ c2.x, c2.y, c2.z },
        } };
    }
    pub fn col(a: Mat3, i: usize) Vec3 {
        return Vec3.init(a.m[i][0], a.m[i][1], a.m[i][2]);
    }
    pub const identity: Mat3 = .{ .m = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } } };
    pub const zero: Mat3 = .{ .m = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } } };

    pub fn diag(d: Vec3) Mat3 {
        return .{ .m = .{ .{ d.x, 0, 0 }, .{ 0, d.y, 0 }, .{ 0, 0, d.z } } };
    }
    /// a * b^T (outer product).
    pub fn outer(a: Vec3, b: Vec3) Mat3 {
        return fromColumns(a.scale(b.x), a.scale(b.y), a.scale(b.z));
    }
    pub fn fromQuat(q: Quat) Mat3 {
        return fromColumns(q.rotate(Vec3.unit_x), q.rotate(Vec3.unit_y), q.rotate(Vec3.unit_z));
    }
    pub fn mulVec(a: Mat3, v: Vec3) Vec3 {
        return a.col(0).scale(v.x).add(a.col(1).scale(v.y)).add(a.col(2).scale(v.z));
    }
    pub fn mul(a: Mat3, b: Mat3) Mat3 {
        return fromColumns(a.mulVec(b.col(0)), a.mulVec(b.col(1)), a.mulVec(b.col(2)));
    }
    pub fn add(a: Mat3, b: Mat3) Mat3 {
        var r: Mat3 = undefined;
        inline for (0..3) |c| inline for (0..3) |k| {
            r.m[c][k] = a.m[c][k] + b.m[c][k];
        };
        return r;
    }
    pub fn scale(a: Mat3, s: f32) Mat3 {
        var r: Mat3 = undefined;
        inline for (0..3) |c| inline for (0..3) |k| {
            r.m[c][k] = a.m[c][k] * s;
        };
        return r;
    }
    pub fn transpose(a: Mat3) Mat3 {
        var r: Mat3 = undefined;
        inline for (0..3) |c| inline for (0..3) |k| {
            r.m[c][k] = a.m[k][c];
        };
        return r;
    }
    pub fn trace(a: Mat3) f32 {
        return a.m[0][0] + a.m[1][1] + a.m[2][2];
    }
    pub fn determinant(a: Mat3) f32 {
        return a.col(0).dot(a.col(1).cross(a.col(2)));
    }
    /// Inverse via the adjugate (rows of the inverse are cross products of columns).
    pub fn inverse(a: Mat3) Mat3 {
        const c0 = a.col(0);
        const c1 = a.col(1);
        const c2 = a.col(2);
        const det = c0.dot(c1.cross(c2));
        if (@abs(det) < 1e-20) return identity;
        const inv_det = 1.0 / det;
        const r0 = c1.cross(c2).scale(inv_det);
        const r1 = c2.cross(c0).scale(inv_det);
        const r2 = c0.cross(c1).scale(inv_det);
        return fromColumns(r0, r1, r2).transpose();
    }
    /// Robust rotation-matrix -> quaternion (Shepperd's method).
    pub fn toQuat(a: Mat3) Quat {
        const m00 = a.m[0][0];
        const m11 = a.m[1][1];
        const m22 = a.m[2][2];
        const tr = m00 + m11 + m22;
        var q: Quat = undefined;
        if (tr > 0) {
            const s = @sqrt(tr + 1.0) * 2.0;
            q = .{ .w = 0.25 * s, .x = (a.m[1][2] - a.m[2][1]) / s, .y = (a.m[2][0] - a.m[0][2]) / s, .z = (a.m[0][1] - a.m[1][0]) / s };
        } else if (m00 > m11 and m00 > m22) {
            const s = @sqrt(1.0 + m00 - m11 - m22) * 2.0;
            q = .{ .w = (a.m[1][2] - a.m[2][1]) / s, .x = 0.25 * s, .y = (a.m[1][0] + a.m[0][1]) / s, .z = (a.m[2][0] + a.m[0][2]) / s };
        } else if (m11 > m22) {
            const s = @sqrt(1.0 + m11 - m00 - m22) * 2.0;
            q = .{ .w = (a.m[2][0] - a.m[0][2]) / s, .x = (a.m[1][0] + a.m[0][1]) / s, .y = 0.25 * s, .z = (a.m[2][1] + a.m[1][2]) / s };
        } else {
            const s = @sqrt(1.0 + m22 - m00 - m11) * 2.0;
            q = .{ .w = (a.m[0][1] - a.m[1][0]) / s, .x = (a.m[2][0] + a.m[0][2]) / s, .y = (a.m[2][1] + a.m[1][2]) / s, .z = 0.25 * s };
        }
        return q.normalize();
    }
};

// ---------------------------------------------------------------- Mat4
pub const Mat4 = extern struct {
    /// Column-major: m[col][row]. Translation lives in m[3].
    m: [4][4]f32,

    pub const identity: Mat4 = .{ .m = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    } };

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = undefined;
        inline for (0..4) |c| {
            inline for (0..4) |row| {
                var s: f32 = 0;
                inline for (0..4) |k| s += a.m[k][row] * b.m[c][k];
                r.m[c][row] = s;
            }
        }
        return r;
    }
    pub fn transformPoint(a: Mat4, p: Vec3) Vec3 {
        return .{
            .x = a.m[0][0] * p.x + a.m[1][0] * p.y + a.m[2][0] * p.z + a.m[3][0],
            .y = a.m[0][1] * p.x + a.m[1][1] * p.y + a.m[2][1] * p.z + a.m[3][1],
            .z = a.m[0][2] * p.x + a.m[1][2] * p.y + a.m[2][2] * p.z + a.m[3][2],
        };
    }
    pub fn transformVector(a: Mat4, v: Vec3) Vec3 {
        return .{
            .x = a.m[0][0] * v.x + a.m[1][0] * v.y + a.m[2][0] * v.z,
            .y = a.m[0][1] * v.x + a.m[1][1] * v.y + a.m[2][1] * v.z,
            .z = a.m[0][2] * v.x + a.m[1][2] * v.y + a.m[2][2] * v.z,
        };
    }
    /// Full homogeneous transform (needed for projection).
    pub fn transformVec4(a: Mat4, v: Vec4) Vec4 {
        var r: [4]f32 = undefined;
        inline for (0..4) |row| {
            r[row] = a.m[0][row] * v.x + a.m[1][row] * v.y + a.m[2][row] * v.z + a.m[3][row] * v.w;
        }
        return .{ .x = r[0], .y = r[1], .z = r[2], .w = r[3] };
    }
    pub fn translation(t: Vec3) Mat4 {
        var r = identity;
        r.m[3] = .{ t.x, t.y, t.z, 1 };
        return r;
    }
    pub fn fromTRS(t: Vec3, q: Quat, s: Vec3) Mat4 {
        const x2 = q.x + q.x;
        const y2 = q.y + q.y;
        const z2 = q.z + q.z;
        const xx = q.x * x2;
        const xy = q.x * y2;
        const xz = q.x * z2;
        const yy = q.y * y2;
        const yz = q.y * z2;
        const zz = q.z * z2;
        const wx = q.w * x2;
        const wy = q.w * y2;
        const wz = q.w * z2;
        return .{ .m = .{
            .{ (1 - (yy + zz)) * s.x, (xy + wz) * s.x, (xz - wy) * s.x, 0 },
            .{ (xy - wz) * s.y, (1 - (xx + zz)) * s.y, (yz + wx) * s.y, 0 },
            .{ (xz + wy) * s.z, (yz - wx) * s.z, (1 - (xx + yy)) * s.z, 0 },
            .{ t.x, t.y, t.z, 1 },
        } };
    }
    /// Inverse of an affine rigid/scaled transform (general 4x4 inverse via cofactors).
    pub fn inverse(a: Mat4) Mat4 {
        const m = a.m;
        var inv: [16]f32 = undefined;
        const s = [16]f32{
            m[0][0], m[0][1], m[0][2], m[0][3],
            m[1][0], m[1][1], m[1][2], m[1][3],
            m[2][0], m[2][1], m[2][2], m[2][3],
            m[3][0], m[3][1], m[3][2], m[3][3],
        };
        inv[0] = s[5] * s[10] * s[15] - s[5] * s[11] * s[14] - s[9] * s[6] * s[15] + s[9] * s[7] * s[14] + s[13] * s[6] * s[11] - s[13] * s[7] * s[10];
        inv[4] = -s[4] * s[10] * s[15] + s[4] * s[11] * s[14] + s[8] * s[6] * s[15] - s[8] * s[7] * s[14] - s[12] * s[6] * s[11] + s[12] * s[7] * s[10];
        inv[8] = s[4] * s[9] * s[15] - s[4] * s[11] * s[13] - s[8] * s[5] * s[15] + s[8] * s[7] * s[13] + s[12] * s[5] * s[11] - s[12] * s[7] * s[9];
        inv[12] = -s[4] * s[9] * s[14] + s[4] * s[10] * s[13] + s[8] * s[5] * s[14] - s[8] * s[6] * s[13] - s[12] * s[5] * s[10] + s[12] * s[6] * s[9];
        inv[1] = -s[1] * s[10] * s[15] + s[1] * s[11] * s[14] + s[9] * s[2] * s[15] - s[9] * s[3] * s[14] - s[13] * s[2] * s[11] + s[13] * s[3] * s[10];
        inv[5] = s[0] * s[10] * s[15] - s[0] * s[11] * s[14] - s[8] * s[2] * s[15] + s[8] * s[3] * s[14] + s[12] * s[2] * s[11] - s[12] * s[3] * s[10];
        inv[9] = -s[0] * s[9] * s[15] + s[0] * s[11] * s[13] + s[8] * s[1] * s[15] - s[8] * s[3] * s[13] - s[12] * s[1] * s[11] + s[12] * s[3] * s[9];
        inv[13] = s[0] * s[9] * s[14] - s[0] * s[10] * s[13] - s[8] * s[1] * s[14] + s[8] * s[2] * s[13] + s[12] * s[1] * s[10] - s[12] * s[2] * s[9];
        inv[2] = s[1] * s[6] * s[15] - s[1] * s[7] * s[14] - s[5] * s[2] * s[15] + s[5] * s[3] * s[14] + s[13] * s[2] * s[7] - s[13] * s[3] * s[6];
        inv[6] = -s[0] * s[6] * s[15] + s[0] * s[7] * s[14] + s[4] * s[2] * s[15] - s[4] * s[3] * s[14] - s[12] * s[2] * s[7] + s[12] * s[3] * s[6];
        inv[10] = s[0] * s[5] * s[15] - s[0] * s[7] * s[13] - s[4] * s[1] * s[15] + s[4] * s[3] * s[13] + s[12] * s[1] * s[7] - s[12] * s[3] * s[5];
        inv[14] = -s[0] * s[5] * s[14] + s[0] * s[6] * s[13] + s[4] * s[1] * s[14] - s[4] * s[2] * s[13] - s[12] * s[1] * s[6] + s[12] * s[2] * s[5];
        inv[3] = -s[1] * s[6] * s[11] + s[1] * s[7] * s[10] + s[5] * s[2] * s[11] - s[5] * s[3] * s[10] - s[9] * s[2] * s[7] + s[9] * s[3] * s[6];
        inv[7] = s[0] * s[6] * s[11] - s[0] * s[7] * s[10] - s[4] * s[2] * s[11] + s[4] * s[3] * s[10] + s[8] * s[2] * s[7] - s[8] * s[3] * s[6];
        inv[11] = -s[0] * s[5] * s[11] + s[0] * s[7] * s[9] + s[4] * s[1] * s[11] - s[4] * s[3] * s[9] - s[8] * s[1] * s[7] + s[8] * s[3] * s[5];
        inv[15] = s[0] * s[5] * s[10] - s[0] * s[6] * s[9] - s[4] * s[1] * s[10] + s[4] * s[2] * s[9] + s[8] * s[1] * s[6] - s[8] * s[2] * s[5];
        var det = s[0] * inv[0] + s[1] * inv[4] + s[2] * inv[8] + s[3] * inv[12];
        if (@abs(det) < 1e-12) return identity;
        det = 1.0 / det;
        var r: Mat4 = undefined;
        inline for (0..4) |c| {
            inline for (0..4) |row| r.m[c][row] = inv[c * 4 + row] * det;
        }
        return r;
    }
    pub fn lookAt(eye: Vec3, target: Vec3, up: Vec3) Mat4 {
        const f = target.sub(eye).normalize();
        const s = f.cross(up).normalize();
        const u = s.cross(f);
        return .{ .m = .{
            .{ s.x, u.x, -f.x, 0 },
            .{ s.y, u.y, -f.y, 0 },
            .{ s.z, u.z, -f.z, 0 },
            .{ -s.dot(eye), -u.dot(eye), f.dot(eye), 1 },
        } };
    }
    /// OpenGL-style clip space (z in [-1,1]).
    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / @tan(fovy * 0.5);
        return .{ .m = .{
            .{ f / aspect, 0, 0, 0 },
            .{ 0, f, 0, 0 },
            .{ 0, 0, (far + near) / (near - far), -1 },
            .{ 0, 0, (2 * far * near) / (near - far), 0 },
        } };
    }
};

// ---------------------------------------------------------------- Transform
/// Translation/rotation/scale; composes like a scene-graph node.
pub const Transform = struct {
    translation: Vec3 = Vec3.zero,
    rotation: Quat = Quat.identity,
    scale: Vec3 = Vec3.one,

    pub const identity: Transform = .{};

    pub fn toMat4(t: Transform) Mat4 {
        return Mat4.fromTRS(t.translation, t.rotation, t.scale);
    }
    pub fn transformPoint(t: Transform, p: Vec3) Vec3 {
        return t.rotation.rotate(p.mul(t.scale)).add(t.translation);
    }
    /// parent * child (child expressed in parent's space). Assumes uniform scale.
    pub fn compose(parent: Transform, child: Transform) Transform {
        return .{
            .translation = parent.transformPoint(child.translation),
            .rotation = parent.rotation.mul(child.rotation).normalize(),
            .scale = parent.scale.mul(child.scale),
        };
    }
    pub fn inverse(t: Transform) Transform {
        const inv_rot = t.rotation.conjugate();
        const inv_scale = Vec3.init(1 / t.scale.x, 1 / t.scale.y, 1 / t.scale.z);
        return .{
            .translation = inv_rot.rotate(t.translation.neg()).mul(inv_scale),
            .rotation = inv_rot,
            .scale = inv_scale,
        };
    }
};

// ---------------------------------------------------------------- tests
const testing = std.testing;

test "quat rotate matches axis-angle" {
    const q = Quat.fromAxisAngle(Vec3.unit_y, pi / 2.0);
    const v = q.rotate(Vec3.unit_z);
    try testing.expect(v.approxEq(Vec3.unit_x, 1e-5));
}

test "quat fromTo" {
    const a = Vec3.init(0, 1, 0);
    const b = Vec3.init(1, 1, 0).normalize();
    try testing.expect(Quat.fromTo(a, b).rotate(a).approxEq(b, 1e-5));
    // antiparallel edge case
    try testing.expect(Quat.fromTo(a, a.neg()).rotate(a).approxEq(a.neg(), 1e-5));
}

test "lookRotation maps +Z to forward" {
    const fwd = Vec3.init(1, 0.3, -0.2).normalize();
    const q = Quat.lookRotation(fwd, Vec3.unit_y);
    try testing.expect(q.rotate(Vec3.unit_z).approxEq(fwd, 1e-4));
}

test "mat4 inverse round trip" {
    const m = Mat4.fromTRS(Vec3.init(1, 2, 3), Quat.fromEuler(0.3, 1.1, -0.4), Vec3.splat(2));
    const p = Vec3.init(0.5, -1, 4);
    const back = m.inverse().transformPoint(m.transformPoint(p));
    try testing.expect(back.approxEq(p, 1e-4));
}

test "transform compose equals matrix product" {
    const a: Transform = .{ .translation = Vec3.init(1, 0, 0), .rotation = Quat.fromAxisAngle(Vec3.unit_z, 0.7) };
    const b: Transform = .{ .translation = Vec3.init(0, 2, 0), .rotation = Quat.fromAxisAngle(Vec3.unit_x, -0.4) };
    const p = Vec3.init(0.3, 0.2, 0.1);
    const via_t = a.compose(b).transformPoint(p);
    const via_m = a.toMat4().mul(b.toMat4()).transformPoint(p);
    try testing.expect(via_t.approxEq(via_m, 1e-5));
    try testing.expect(a.inverse().transformPoint(a.transformPoint(p)).approxEq(p, 1e-5));
}
