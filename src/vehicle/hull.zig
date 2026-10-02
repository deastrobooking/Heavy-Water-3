//! Faceted wedge hull ("hyper-car" body) as a piecewise-linear loft of
//! chamfered half-sections.
//!
//! Every station is an 8-point half polygon (mirrored across x = 0):
//!
//!        7 crown
//!   6 ___/          roof edge (chamfer)
//!   5 \             upper side (tumblehome)
//!     4 >           shoulder crease (widest line)
//!   3 /             belt (side-intake recess lives here)
//!   2 |             sill
//!   1 \__ 0         floor edge -> keel
//!
//! Parameters are tabulated at knots along u in [0, 1] (tail -> nose) and
//! interpolated LINEARLY: knots become hard design lines, which is what
//! makes the wedge read as a single sharp "Countach" stroke. Each
//! (strip, knot-interval) pair is meshed as its own panel, so panels are
//! flat-shaded across creases yet smooth within, and still watertight.
//!
//! Frame: +Z forward (nose), +Y up, origin at the footprint center, y = 0
//! at the lowest point of the body.

const std = @import("std");
const m = @import("../character/math.zig");
const mesh_mod = @import("../character/mesh.zig");
const Vec3 = m.Vec3;
const Mesh = mesh_mod.Mesh;
const Material = mesh_mod.Material;
const Allocator = std.mem.Allocator;

pub const n_knots = 9;
pub const n_points = 8; // per half section
pub const n_strips = n_points - 1;

/// Each row: values at the knots `u`. Heights/widths in meters.
pub const HullSpec = struct {
    length: f32 = 4.70,
    u: [n_knots]f32 = .{ 0.00, 0.08, 0.22, 0.38, 0.48, 0.60, 0.74, 0.88, 1.00 },
    y_bot: [n_knots]f32 = .{ 0.32, 0.20, 0.16, 0.16, 0.16, 0.16, 0.16, 0.18, 0.26 },
    y_sill: [n_knots]f32 = .{ 0.42, 0.33, 0.30, 0.30, 0.30, 0.30, 0.30, 0.31, 0.32 },
    y_belt: [n_knots]f32 = .{ 0.62, 0.56, 0.50, 0.48, 0.48, 0.48, 0.46, 0.41, 0.36 },
    y_sh: [n_knots]f32 = .{ 0.84, 0.86, 0.84, 0.80, 0.76, 0.71, 0.64, 0.54, 0.42 },
    y_up: [n_knots]f32 = .{ 0.90, 0.94, 0.93, 0.99, 1.05, 0.81, 0.69, 0.58, 0.45 },
    y_roof: [n_knots]f32 = .{ 0.93, 0.98, 1.00, 1.10, 1.13, 0.84, 0.71, 0.60, 0.46 },
    w_floor: [n_knots]f32 = .{ 0.78, 0.84, 0.86, 0.80, 0.80, 0.80, 0.84, 0.76, 0.52 },
    w_sill: [n_knots]f32 = .{ 0.90, 0.98, 0.98, 0.84, 0.86, 0.88, 0.97, 0.88, 0.60 },
    w_belt: [n_knots]f32 = .{ 0.94, 1.01, 1.00, 0.82, 0.88, 0.93, 1.00, 0.91, 0.65 },
    w_sh: [n_knots]f32 = .{ 0.95, 1.03, 1.03, 0.97, 0.96, 0.97, 1.01, 0.94, 0.70 },
    w_up: [n_knots]f32 = .{ 0.82, 0.87, 0.84, 0.66, 0.62, 0.82, 0.90, 0.86, 0.64 },
    w_roof: [n_knots]f32 = .{ 0.70, 0.74, 0.66, 0.50, 0.47, 0.72, 0.82, 0.80, 0.58 },
    roof_chamfer: f32 = 0.03,
    crown: f32 = 0.015,
    /// Subdivisions per knot interval (smoothness within a panel).
    subdiv: u32 = 3,
    /// Cabin glass spans these knot indices [start, end).
    glass_knots: [2]usize = .{ 3, 5 },
    /// Windshield (roof strip glass) knot interval.
    windshield_knot: usize = 4,
    /// Side intake recess (carbon) knot interval.
    intake_knot: usize = 2,
};

pub fn lerpTable(spec: HullSpec, table: [n_knots]f32, u: f32) f32 {
    if (u <= spec.u[0]) return table[0];
    for (1..n_knots) |i| {
        if (u <= spec.u[i]) {
            const t = (u - spec.u[i - 1]) / (spec.u[i] - spec.u[i - 1]);
            return m.lerp(table[i - 1], table[i], t);
        }
    }
    return table[n_knots - 1];
}

pub fn zOf(spec: HullSpec, u: f32) f32 {
    return (u - 0.5) * spec.length;
}

/// The 8 half-section points (x >= 0) at parameter u.
pub fn section(spec: HullSpec, u: f32) [n_points]Vec3 {
    const z = zOf(spec, u);
    const L = struct {
        s: HullSpec,
        u: f32,
        fn f(self: @This(), t: [n_knots]f32) f32 {
            return lerpTable(self.s, t, self.u);
        }
    }{ .s = spec, .u = u };
    const y_roof = L.f(spec.y_roof);
    return .{
        Vec3.init(0, L.f(spec.y_bot), z),
        Vec3.init(L.f(spec.w_floor), L.f(spec.y_bot), z),
        Vec3.init(L.f(spec.w_sill), L.f(spec.y_sill), z),
        Vec3.init(L.f(spec.w_belt), L.f(spec.y_belt), z),
        Vec3.init(L.f(spec.w_sh), L.f(spec.y_sh), z),
        Vec3.init(L.f(spec.w_up), L.f(spec.y_up), z),
        Vec3.init(L.f(spec.w_roof), y_roof - spec.roof_chamfer, z),
        Vec3.init(0, y_roof + spec.crown, z),
    };
}

/// Point on the hull surface: strip k (0..6) at fraction s across it, at u,
/// on side +1 (left, +X) or -1.
pub fn surfacePoint(spec: HullSpec, u: f32, side: f32, k: usize, s: f32) Vec3 {
    const sec = section(spec, u);
    const p = sec[k].lerp(sec[k + 1], s);
    return Vec3.init(p.x * side, p.y, p.z);
}

/// Outward normal of strip k at u (finite differences on the surface).
pub fn surfaceNormal(spec: HullSpec, u: f32, side: f32, k: usize) Vec3 {
    const du: f32 = 0.002;
    const a = surfacePoint(spec, @max(u - du, 0), side, k, 0.5);
    const b = surfacePoint(spec, @min(u + du, 1), side, k, 0.5);
    const c = surfacePoint(spec, u, side, k, 0.0);
    const d = surfacePoint(spec, u, side, k, 1.0);
    // across-strip x along-length; mirroring flips orientation
    return d.sub(c).cross(b.sub(a)).scale(side).normalize();
}

pub fn panelMaterial(spec: HullSpec, strip: usize, knot: usize) Material {
    const cabin = knot >= spec.glass_knots[0] and knot < spec.glass_knots[1];
    return switch (strip) {
        0, 1 => .carbon,
        2 => if (knot == spec.intake_knot) .carbon else .paint,
        3 => .paint,
        4 => .paint,
        5 => if (cabin) .glass else .paint,
        6 => if (knot == spec.windshield_knot) .glass else .paint,
        else => .paint,
    };
}

/// Build the watertight hull.
pub fn buildHull(gpa: Allocator, mesh: *Mesh, spec: HullSpec) !void {
    for ([_]f32{ 1, -1 }) |side| {
        for (0..n_strips) |k| {
            for (0..n_knots - 1) |knot| {
                const mat = panelMaterial(spec, k, knot);
                const rows = spec.subdiv + 1;
                const first = mesh.vertexCount();
                for (0..rows) |r| {
                    const t = @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(spec.subdiv));
                    const u = m.lerp(spec.u[knot], spec.u[knot + 1], t);
                    for (0..2) |e| {
                        const p = surfacePoint(spec, u, side, k, @floatFromInt(e));
                        _ = try mesh.addVertex(gpa, .{ .pos = p, .uv = .{ .x = @floatFromInt(e), .y = u }, .material = mat, .region = .garment });
                    }
                }
                // Rows advance toward the nose (+Z); columns go up the section.
                // Right side (x<0) mirrors, reversing orientation.
                try mesh.stitchRings(gpa, first, @intCast(rows), 2, false, side < 0);
            }
        }
    }
    // end caps: tail (u=0) faces -Z, nose (u=1) faces +Z
    for ([_]f32{ 0, 1 }) |u| {
        const sec = section(spec, u);
        const mat: Material = if (u == 0) .paint_accent else .paint;
        var loop: [2 * n_points - 2]Vec3 = undefined;
        var c = Vec3.zero;
        for (0..n_points) |i| loop[i] = sec[i];
        for (1..n_points - 1) |i| {
            const p = sec[n_points - 1 - i];
            loop[n_points - 1 + i] = Vec3.init(-p.x, p.y, p.z);
        }
        for (loop) |p| c = c.add(p);
        c = c.scale(1.0 / @as(f32, @floatFromInt(loop.len)));
        const first = mesh.vertexCount();
        for (loop) |p| _ = try mesh.addVertex(gpa, .{ .pos = p, .material = mat, .region = .garment });
        const ci = try mesh.addVertex(gpa, .{ .pos = c, .material = mat, .region = .garment });
        try mesh.capRing(gpa, first, @intCast(loop.len), ci, u == 0);
    }
    mesh.computeNormals(); // panels share no vertices -> creases stay hard
}

test "hull is watertight and car-sized" {
    const gpa = std.testing.allocator;
    var mesh: Mesh = .{};
    defer mesh.deinit(gpa);
    const spec: HullSpec = .{};
    try buildHull(gpa, &mesh, spec);
    try @import("airfoil.zig").expectWatertight(&mesh);
    const bb = mesh.bounds();
    try std.testing.expectApproxEqAbs(spec.length, bb.max.z - bb.min.z, 1e-3);
    try std.testing.expect(bb.max.y < 1.2 and bb.max.x > 1.0);
    // wedge: nose lower than the roof peak
    try std.testing.expect(section(spec, 1)[7].y < section(spec, 0.48)[7].y - 0.5);
}

test "surface normal points outward" {
    const spec: HullSpec = .{};
    const n = surfaceNormal(spec, 0.5, 1, 3);
    try std.testing.expect(n.x > 0.5);
    const nr = surfaceNormal(spec, 0.5, -1, 3);
    try std.testing.expect(nr.x < -0.5);
    try std.testing.expect(surfaceNormal(spec, 0.5, 1, 6).y > 0.5);
}
