//! Curves, rotation-minimizing frames and cross-section profiles.
//! These are the building blocks for lofting limbs, hair clumps and skirts.

const std = @import("std");
const m = @import("math.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;

// ---------------------------------------------------------------- Bezier
pub const CubicBezier = struct {
    p0: Vec3,
    p1: Vec3,
    p2: Vec3,
    p3: Vec3,

    pub fn eval(c: CubicBezier, t: f32) Vec3 {
        const u = 1 - t;
        const b0 = u * u * u;
        const b1 = 3 * u * u * t;
        const b2 = 3 * u * t * t;
        const b3 = t * t * t;
        return c.p0.scale(b0).add(c.p1.scale(b1)).add(c.p2.scale(b2)).add(c.p3.scale(b3));
    }
    /// First derivative (un-normalized tangent).
    pub fn derivative(c: CubicBezier, t: f32) Vec3 {
        const u = 1 - t;
        const d0 = c.p1.sub(c.p0).scale(3 * u * u);
        const d1 = c.p2.sub(c.p1).scale(6 * u * t);
        const d2 = c.p3.sub(c.p2).scale(3 * t * t);
        return d0.add(d1).add(d2);
    }
    /// Build a curve that leaves `start` along `dir_start` and arrives at `end`
    /// travelling along `dir_end`. Handle lengths are a fraction of the chord.
    pub fn fromEndpoints(start: Vec3, dir_start: Vec3, end: Vec3, dir_end: Vec3, handle: f32) CubicBezier {
        const chord = start.distance(end);
        return .{
            .p0 = start,
            .p1 = start.addScaled(dir_start.normalize(), chord * handle),
            .p2 = end.addScaled(dir_end.normalize(), -chord * handle),
            .p3 = end,
        };
    }
};

// ---------------------------------------------------------------- Catmull-Rom
/// Centripetal Catmull-Rom segment between p1 and p2 (alpha = 0.5 avoids
/// cusps and self-intersection, important for tight hair curls).
pub fn catmullRom(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, t: f32) Vec3 {
    const alpha: f32 = 0.5;
    const t0: f32 = 0;
    const t1 = t0 + std.math.pow(f32, @max(p0.distance(p1), 1e-5), alpha);
    const t2 = t1 + std.math.pow(f32, @max(p1.distance(p2), 1e-5), alpha);
    const t3 = t2 + std.math.pow(f32, @max(p2.distance(p3), 1e-5), alpha);
    const tt = m.lerp(t1, t2, t);
    const a1 = p0.scale((t1 - tt) / (t1 - t0)).add(p1.scale((tt - t0) / (t1 - t0)));
    const a2 = p1.scale((t2 - tt) / (t2 - t1)).add(p2.scale((tt - t1) / (t2 - t1)));
    const a3 = p2.scale((t3 - tt) / (t3 - t2)).add(p3.scale((tt - t2) / (t3 - t2)));
    const b1 = a1.scale((t2 - tt) / (t2 - t0)).add(a2.scale((tt - t0) / (t2 - t0)));
    const b2 = a2.scale((t3 - tt) / (t3 - t1)).add(a3.scale((tt - t1) / (t3 - t1)));
    return b1.scale((t2 - tt) / (t2 - t1)).add(b2.scale((tt - t1) / (t2 - t1)));
}

/// Sample a smooth curve through `pts` into `out` (out.len >= 2), uniform in parameter.
pub fn sampleCatmullRom(pts: []const Vec3, out: []Vec3) void {
    std.debug.assert(pts.len >= 2 and out.len >= 2);
    const segs = pts.len - 1;
    for (out, 0..) |*o, i| {
        const g = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(out.len - 1)) * @as(f32, @floatFromInt(segs));
        const s: usize = @min(@as(usize, @intFromFloat(@floor(g))), segs - 1);
        const t = g - @as(f32, @floatFromInt(s));
        const p0 = if (s == 0) pts[0].scale(2).sub(pts[1]) else pts[s - 1];
        const p3 = if (s + 2 >= pts.len) pts[segs].scale(2).sub(pts[segs - 1]) else pts[s + 2];
        o.* = catmullRom(p0, pts[s], pts[s + 1], p3, t);
    }
}

// ---------------------------------------------------------------- Frames
/// Orthonormal frame along a curve: tangent T, normal N, binormal B.
/// Cross-sections are placed in the N/B plane.
pub const Frame = struct {
    origin: Vec3,
    tangent: Vec3,
    normal: Vec3,
    binormal: Vec3,

    /// Map a 2D cross-section point (x along normal, y along binormal) to 3D.
    pub inline fn place(f: Frame, p: Vec2) Vec3 {
        return f.origin.addScaled(f.normal, p.x).addScaled(f.binormal, p.y);
    }
};

/// Rotation-minimizing frames via the double-reflection method
/// (Wang, Jüttler, Zheng, Liu 2008). Avoids the twisting/flipping of
/// Frenet frames, so lofted tubes never corkscrew.
/// `ref_normal` seeds the first normal (projected to be perpendicular).
pub fn rotationMinimizingFrames(points: []const Vec3, ref_normal: Vec3, out: []Frame) void {
    std.debug.assert(points.len == out.len and points.len >= 2);
    const n = points.len;
    // tangents by central differences
    for (0..n) |i| {
        const a = points[if (i == 0) 0 else i - 1];
        const b = points[if (i + 1 >= n) n - 1 else i + 1];
        out[i].origin = points[i];
        out[i].tangent = b.sub(a).normalizeOr(Vec3.unit_y);
    }
    const t0 = out[0].tangent;
    out[0].normal = ref_normal.reject(t0).normalizeOr(Vec3.anyPerpendicular(t0));
    out[0].binormal = t0.cross(out[0].normal);

    for (0..n - 1) |i| {
        const v1 = points[i + 1].sub(points[i]);
        const c1 = v1.dot(v1);
        if (c1 < 1e-12) {
            out[i + 1].normal = out[i].normal;
            out[i + 1].binormal = out[i + 1].tangent.cross(out[i + 1].normal);
            continue;
        }
        // reflect normal & tangent across the plane bisecting the step
        const rl = out[i].normal.sub(v1.scale(2.0 / c1 * v1.dot(out[i].normal)));
        const tl = out[i].tangent.sub(v1.scale(2.0 / c1 * v1.dot(out[i].tangent)));
        // second reflection aligns the reflected tangent with the true tangent
        const v2 = out[i + 1].tangent.sub(tl);
        const c2 = v2.dot(v2);
        const nrm = if (c2 < 1e-12) rl else rl.sub(v2.scale(2.0 / c2 * v2.dot(rl)));
        out[i + 1].normal = nrm.normalize();
        out[i + 1].binormal = out[i + 1].tangent.cross(out[i + 1].normal);
    }
}

// ---------------------------------------------------------------- Profiles
/// Superellipse |x/a|^n + |y/b|^n = 1, sampled at angle theta.
/// n = 2 -> ellipse, n > 2 -> boxier (good for torsos, thighs),
/// n < 2 -> pinched (good for hair clump tips and fingers).
pub fn superellipse(theta: f32, a: f32, b: f32, n: f32) Vec2 {
    const c = @cos(theta);
    const s = @sin(theta);
    const e = 2.0 / n;
    const sgn = struct {
        fn f(x: f32) f32 {
            return if (x < 0) -1.0 else 1.0;
        }
    }.f;
    return .{
        .x = a * sgn(c) * std.math.pow(f32, @abs(c), e),
        .y = b * sgn(s) * std.math.pow(f32, @abs(s), e),
    };
}

/// A keyframed scalar profile f(t), t in [0,1], with smooth (Hermite)
/// interpolation. Used for radius-along-limb, hem flare, hair taper, etc.
pub fn Profile(comptime N: usize) type {
    return struct {
        const Self = @This();
        t: [N]f32,
        v: [N]f32,

        pub fn eval(p: Self, x: f32) f32 {
            if (x <= p.t[0]) return p.v[0];
            if (x >= p.t[N - 1]) return p.v[N - 1];
            var i: usize = 0;
            while (i + 1 < N and x > p.t[i + 1]) : (i += 1) {}
            const k = m.smoothstep(p.t[i], p.t[i + 1], x);
            return m.lerp(p.v[i], p.v[i + 1], k);
        }
    };
}

/// Smooth 1D spline through knots (t[i], v[i]) using cubic Hermite segments
/// with Catmull-Rom (finite difference) tangents. Unlike `Profile`, the curve
/// does not flatten at every knot, so lofted silhouettes stay organic.
pub fn spline1D(ts: []const f32, vs: []const f32, x: f32) f32 {
    const n = ts.len;
    std.debug.assert(n == vs.len and n >= 2);
    if (x <= ts[0]) return vs[0];
    if (x >= ts[n - 1]) return vs[n - 1];
    var i: usize = 0;
    while (i + 2 < n and x > ts[i + 1]) : (i += 1) {}
    const t0 = ts[i];
    const t1 = ts[i + 1];
    const h = t1 - t0;
    const slope = struct {
        fn f(tt: []const f32, vv: []const f32, k: usize) f32 {
            const a = if (k == 0) 0 else k - 1;
            const b = @min(k + 1, tt.len - 1);
            return (vv[b] - vv[a]) / @max(tt[b] - tt[a], 1e-6);
        }
    }.f;
    const m0 = slope(ts, vs, i) * h;
    const m1 = slope(ts, vs, i + 1) * h;
    const s = (x - t0) / h;
    const s2 = s * s;
    const s3 = s2 * s;
    return (2 * s3 - 3 * s2 + 1) * vs[i] + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * vs[i + 1] + (s3 - s2) * m1;
}

/// Arc length of a polyline.
pub fn polylineLength(pts: []const Vec3) f32 {
    var len: f32 = 0;
    for (1..pts.len) |i| len += pts[i].distance(pts[i - 1]);
    return len;
}

// ---------------------------------------------------------------- tests
const testing = std.testing;

test "bezier endpoints and tangent" {
    const c = CubicBezier.fromEndpoints(Vec3.zero, Vec3.unit_y, Vec3.init(1, 1, 0), Vec3.unit_x, 0.4);
    try testing.expect(c.eval(0).approxEq(Vec3.zero, 1e-6));
    try testing.expect(c.eval(1).approxEq(Vec3.init(1, 1, 0), 1e-6));
    try testing.expect(c.derivative(0).normalize().approxEq(Vec3.unit_y, 1e-5));
}

test "rmf frames stay orthonormal and untwisted on a helix" {
    var pts: [64]Vec3 = undefined;
    for (&pts, 0..) |*p, i| {
        const t = @as(f32, @floatFromInt(i)) * 0.15;
        p.* = Vec3.init(@cos(t), t * 0.2, @sin(t));
    }
    var frames: [64]Frame = undefined;
    rotationMinimizingFrames(&pts, Vec3.unit_y, &frames);
    for (frames) |f| {
        try testing.expectApproxEqAbs(@as(f32, 0), f.tangent.dot(f.normal), 1e-3);
        try testing.expectApproxEqAbs(@as(f32, 1), f.normal.length(), 1e-3);
        try testing.expectApproxEqAbs(@as(f32, 1), f.binormal.length(), 1e-3);
    }
}

test "superellipse lies on its implicit curve" {
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const th = @as(f32, @floatFromInt(i)) * 0.4;
        const p = superellipse(th, 2, 1, 3.5);
        const v = std.math.pow(f32, @abs(p.x / 2), 3.5) + std.math.pow(f32, @abs(p.y / 1), 3.5);
        try testing.expectApproxEqAbs(@as(f32, 1), v, 1e-3);
    }
}

test "catmull-rom interpolates control points" {
    const pts = [_]Vec3{ Vec3.zero, Vec3.init(1, 0, 0), Vec3.init(1, 1, 0), Vec3.init(2, 1, 0) };
    var out: [7]Vec3 = undefined;
    sampleCatmullRom(&pts, &out);
    try testing.expect(out[0].approxEq(pts[0], 1e-5));
    try testing.expect(out[2].approxEq(pts[1], 1e-4));
    try testing.expect(out[6].approxEq(pts[3], 1e-4));
}
