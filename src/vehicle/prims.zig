//! Primitive hard-surface builders: oriented boxes, struts, light strips,
//! and surfaces of revolution (lathe) with automatic winding.

const std = @import("std");
const m = @import("../character/math.zig");
const mesh_mod = @import("../character/mesh.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Transform = m.Transform;
const Mesh = mesh_mod.Mesh;
const Material = mesh_mod.Material;
const Allocator = std.mem.Allocator;

/// Box with orthonormal axes (ax, ay, az) and half extents. Faceted:
/// 4 unshared verts per face so normals stay crisp.
pub fn box(gpa: Allocator, mesh: *Mesh, center: Vec3, ax: Vec3, ay: Vec3, az: Vec3, half: Vec3, mat: Material) !void {
    const axes = [3]Vec3{ ax.scale(half.x), ay.scale(half.y), az.scale(half.z) };
    // each face: normal axis k, sign s; tangent axes u, v chosen so u x v = n
    for (0..3) |k| {
        for ([_]f32{ 1, -1 }) |s| {
            const n = axes[k].scale(s);
            var u = axes[(k + 1) % 3];
            const v = axes[(k + 2) % 3];
            if (s < 0) u = u.neg();
            const c = center.add(n);
            const nn = n.normalize();
            const base = mesh.vertexCount();
            const corners = [4]Vec3{ c.sub(u).sub(v), c.add(u).sub(v), c.add(u).add(v), c.sub(u).add(v) };
            for (corners, 0..) |p, i| _ = try mesh.addVertex(gpa, .{
                .pos = p,
                .normal = nn,
                .uv = .{ .x = @floatFromInt(i & 1), .y = @floatFromInt(i >> 1) },
                .material = mat,
                .region = .garment,
            });
            try mesh.addQuad(gpa, base, base + 1, base + 2, base + 3);
        }
    }
}

/// Rectangular strut from `a` to `b`; `up` orients the cross-section.
pub fn strut(gpa: Allocator, mesh: *Mesh, a: Vec3, b: Vec3, up: Vec3, width: f32, height: f32, mat: Material) !void {
    const az = b.sub(a).normalize();
    const ax = up.cross(az).normalizeOr(Vec3.anyPerpendicular(az));
    const ay = az.cross(ax);
    try box(gpa, mesh, a.lerp(b, 0.5), ax, ay, az, Vec3.init(width * 0.5, height * 0.5, a.distance(b) * 0.5), mat);
}

/// Light strip: a chain of thin struts following a polyline, lifted along `up`.
pub fn lightStrip(gpa: Allocator, mesh: *Mesh, pts: []const Vec3, up: Vec3, width: f32, thickness: f32, mat: Material) !void {
    for (1..pts.len) |i| try strut(gpa, mesh, pts[i - 1], pts[i], up, width, thickness, mat);
}

/// Shoelace signed area of a closed 2D loop.
pub fn signedArea(loop: []const Vec2) f32 {
    var a: f32 = 0;
    for (loop, 0..) |p, i| {
        const q = loop[(i + 1) % loop.len];
        a += p.x * q.y - q.x * p.y;
    }
    return 0.5 * a;
}

/// Revolve a closed profile (r, h) about the local +Y axis, then place it
/// with `xf`. Winding is chosen from the profile's orientation so the
/// result is always outward-facing (watertight if the loop is closed).
/// Profiles that touch the axis (r = 0) work too: those faces degenerate.
pub fn lathe(gpa: Allocator, mesh: *Mesh, profile: []const Vec2, segments: u32, xf: Transform, mat: Material) !void {
    const first = mesh.vertexCount();
    for (0..segments) |si| {
        const phi = @as(f32, @floatFromInt(si)) / @as(f32, @floatFromInt(segments)) * m.tau;
        const c = @cos(phi);
        const s = @sin(phi);
        for (profile, 0..) |p, k| {
            const local = Vec3.init(p.x * c, p.y, p.x * s);
            _ = try mesh.addVertex(gpa, .{
                .pos = xf.transformPoint(local),
                .uv = .{ .x = @as(f32, @floatFromInt(si)) / @as(f32, @floatFromInt(segments)), .y = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(profile.len)) },
                .material = mat,
                .region = .garment,
            });
        }
    }
    // rings = angular segments (closed), cols = profile points (closed loop)
    const flip = signedArea(profile) < 0;
    try mesh.stitchRings(gpa, first, segments, @intCast(profile.len), true, flip);
    // close the seam between the last and first angular segment
    const cols: u32 = @intCast(profile.len);
    const last = first + (segments - 1) * cols;
    var k: u32 = 0;
    while (k < cols) : (k += 1) {
        const k1 = (k + 1) % cols;
        const a = last + k;
        const b = last + k1;
        const cc = first + k1;
        const d = first + k;
        if (flip) try mesh.addQuad(gpa, a, d, cc, b) else try mesh.addQuad(gpa, a, b, cc, d);
    }
}

test "lathe torus is watertight for either profile orientation" {
    const gpa = std.testing.allocator;
    const af = @import("airfoil.zig");
    for ([_]bool{ false, true }) |rev| {
        var loop: [32]Vec2 = undefined;
        for (&loop, 0..) |*p, i| {
            const t = @as(f32, @floatFromInt(if (rev) 31 - i else i)) / 32 * m.tau;
            p.* = .{ .x = 1 + 0.3 * @cos(t), .y = 0.3 * @sin(t) };
        }
        var mesh: Mesh = .{};
        defer mesh.deinit(gpa);
        try lathe(gpa, &mesh, &loop, 48, .{ .translation = Vec3.init(1, 2, 3) }, .metal);
        try af.expectWatertight(&mesh);
        // torus volume 2 pi^2 R r^2
        const dyn = @import("dynamics.zig");
        try std.testing.expectApproxEqRel(2 * m.pi * m.pi * 1 * 0.09, dyn.massProperties(&mesh, 1).mass, 0.02);
    }
}

test "box is watertight with exact volume" {
    const gpa = std.testing.allocator;
    const af = @import("airfoil.zig");
    var mesh: Mesh = .{};
    defer mesh.deinit(gpa);
    const q = Quat.fromEuler(0.4, 1.0, -0.3);
    try box(gpa, &mesh, Vec3.init(1, 2, 3), q.rotate(Vec3.unit_x), q.rotate(Vec3.unit_y), q.rotate(Vec3.unit_z), Vec3.init(0.5, 1, 2), .metal);
    try af.expectWatertight(&mesh);
    const dyn = @import("dynamics.zig");
    try std.testing.expectApproxEqRel(@as(f32, 8), dyn.massProperties(&mesh, 1).mass, 1e-4);
}
