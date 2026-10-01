//! Generic lofting: sweep a varying superellipse cross-section along a
//! centerline using rotation-minimizing frames, with optional domed end caps.
//! Every body part, skirt and hair clump in animegen is built by this one function.

const std = @import("std");
const m = @import("math.zig");
const curve = @import("curve.zig");
const mesh_mod = @import("mesh.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Mesh = mesh_mod.Mesh;
const Vertex = mesh_mod.Vertex;
const Allocator = std.mem.Allocator;

/// Cross-section at a point along the loft. `a` spans the frame normal,
/// `b` the binormal; `n` is the superellipse exponent; `offset` shifts the
/// section within the frame plane (e.g. push a chest forward).
pub const Section = struct {
    a: f32,
    b: f32,
    n: f32 = 2.0,
    offset: Vec2 = .{},
};

pub const Cap = enum { none, dome };

pub const Options = struct {
    cols: u32,
    /// Seeds frame orientation. Section `a` lies along this (projected) axis.
    ref_normal: Vec3,
    region: mesh_mod.Region = .garment,
    material: mesh_mod.Material = .skin,
    cap_start: Cap = .none,
    cap_end: Cap = .none,
    cap_rings: u32 = 4,
    /// Dome length as a fraction of min(a, b) of the end section.
    cap_length: f32 = 1.0,
};

pub const Result = struct {
    first_vertex: u32,
    vertex_count: u32,
};

/// Context (`ctx`) must provide:
///   fn section(ctx, t: f32) Section
///   fn skin(ctx, t: f32, p: Vec3) mesh_mod.SkinBlend
/// and may provide:
///   fn displace(ctx, t: f32, theta: f32, p: Vec3, frame: curve.Frame) Vec3
///   fn finish(ctx, v: *Vertex, t: f32, theta: f32) void   // region/uv/material tweaks
/// `t` is normalized arc length along the centerline (0..1); caps use 0 or 1.
pub fn loft(gpa: Allocator, mesh: *Mesh, centerline: []const Vec3, opts: Options, ctx: anytype) !Result {
    const rows = centerline.len;
    std.debug.assert(rows >= 2 and opts.cols >= 3);

    const frames = try gpa.alloc(curve.Frame, rows);
    defer gpa.free(frames);
    curve.rotationMinimizingFrames(centerline, opts.ref_normal, frames);

    // normalized arc-length parameter per row
    const ts = try gpa.alloc(f32, rows);
    defer gpa.free(ts);
    ts[0] = 0;
    for (1..rows) |i| ts[i] = ts[i - 1] + centerline[i].distance(centerline[i - 1]);
    const total = @max(ts[rows - 1], m.eps);
    for (ts) |*t| t.* /= total;

    const first = mesh.vertexCount();
    var ring_count: u32 = 0;

    const Ring = struct { frame: curve.Frame, t: f32, scale: f32 };
    const emitRing = struct {
        fn f(g: Allocator, msh: *Mesh, o: Options, c: anytype, r: Ring) !void {
            const sec = c.section(r.t);
            var col: u32 = 0;
            while (col < o.cols) : (col += 1) {
                const theta = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(o.cols)) * m.tau;
                const s2 = curve.superellipse(theta, sec.a * r.scale, sec.b * r.scale, sec.n);
                const off = sec.offset;
                var p = r.frame.place(.{ .x = s2.x + off.x, .y = s2.y + off.y });
                if (@hasDecl(@TypeOf(c.*), "displace")) p = c.displace(r.t, theta, p, r.frame);
                var v: Vertex = .{
                    .pos = p,
                    .uv = .{ .x = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(o.cols)), .y = r.t },
                    .region = o.region,
                    .material = o.material,
                };
                c.skin(r.t, p).apply(&v);
                if (@hasDecl(@TypeOf(c.*), "finish")) c.finish(&v, r.t, theta);
                _ = try msh.addVertex(g, v);
            }
        }
    }.f;

    // --- start dome (from near the tip toward the main body)
    if (opts.cap_start == .dome) {
        const sec = ctx.section(0);
        const len = @min(sec.a, sec.b) * opts.cap_length;
        var i: u32 = opts.cap_rings;
        while (i >= 1) : (i -= 1) {
            const phi = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(opts.cap_rings + 1)) * (m.pi / 2.0);
            var fr = frames[0];
            fr.origin = fr.origin.addScaled(fr.tangent, -@sin(phi) * len);
            try emitRing(gpa, mesh, opts, ctx, .{ .frame = fr, .t = 0, .scale = @cos(phi) });
            ring_count += 1;
        }
    }
    // --- main rings
    for (frames, ts) |fr, t| {
        try emitRing(gpa, mesh, opts, ctx, .{ .frame = fr, .t = t, .scale = 1 });
        ring_count += 1;
    }
    // --- end dome
    if (opts.cap_end == .dome) {
        const sec = ctx.section(1);
        const len = @min(sec.a, sec.b) * opts.cap_length;
        var i: u32 = 1;
        while (i <= opts.cap_rings) : (i += 1) {
            const phi = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(opts.cap_rings + 1)) * (m.pi / 2.0);
            var fr = frames[rows - 1];
            fr.origin = fr.origin.addScaled(fr.tangent, @sin(phi) * len);
            try emitRing(gpa, mesh, opts, ctx, .{ .frame = fr, .t = 1, .scale = @cos(phi) });
            ring_count += 1;
        }
    }

    try mesh.stitchRings(gpa, first, ring_count, opts.cols, true, false);

    // --- tips (single vertex closing each dome)
    if (opts.cap_start == .dome) {
        const sec = ctx.section(0);
        const fr = frames[0];
        var tip = fr.origin.addScaled(fr.tangent, -@min(sec.a, sec.b) * opts.cap_length);
        tip = fr.place(sec.offset).sub(fr.origin).add(tip);
        var v: Vertex = .{ .pos = tip, .uv = .{ .x = 0.5, .y = 0 }, .region = opts.region, .material = opts.material };
        ctx.skin(0, tip).apply(&v);
        if (@hasDecl(@TypeOf(ctx.*), "finish")) ctx.finish(&v, 0, 0);
        const ti = try mesh.addVertex(gpa, v);
        try mesh.capRing(gpa, first, opts.cols, ti, true);
    }
    if (opts.cap_end == .dome) {
        const sec = ctx.section(1);
        const fr = frames[rows - 1];
        var tip = fr.origin.addScaled(fr.tangent, @min(sec.a, sec.b) * opts.cap_length);
        tip = fr.place(sec.offset).sub(fr.origin).add(tip);
        var v: Vertex = .{ .pos = tip, .uv = .{ .x = 0.5, .y = 1 }, .region = opts.region, .material = opts.material };
        ctx.skin(1, tip).apply(&v);
        if (@hasDecl(@TypeOf(ctx.*), "finish")) ctx.finish(&v, 1, 0);
        const ti = try mesh.addVertex(gpa, v);
        try mesh.capRing(gpa, first + (ring_count - 1) * opts.cols, opts.cols, ti, false);
    }

    return .{ .first_vertex = first, .vertex_count = mesh.vertexCount() - first };
}

/// Sample `n` points along a straight or bent polyline (piecewise linear,
/// uniform in arc length). Handy for limb centerlines through joint positions.
pub fn resamplePolyline(gpa: Allocator, pts: []const Vec3, n: usize) ![]Vec3 {
    const out = try gpa.alloc(Vec3, n);
    const total = curve.polylineLength(pts);
    var seg: usize = 0;
    var seg_start: f32 = 0;
    for (out, 0..) |*o, i| {
        const target = total * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        while (seg + 2 < pts.len and seg_start + pts[seg + 1].distance(pts[seg]) < target) {
            seg_start += pts[seg + 1].distance(pts[seg]);
            seg += 1;
        }
        const seg_len = @max(pts[seg + 1].distance(pts[seg]), m.eps);
        o.* = pts[seg].lerp(pts[seg + 1], m.saturate((target - seg_start) / seg_len));
    }
    return out;
}

/// Skin a point by its arc-length coordinate `s` along a joint chain.
/// `pivots[k]` is the arc length of `joints[k]`'s pivot. Near each child pivot
/// the weight blends smoothly over +/- `width`.
pub fn chainSkin(joints: []const u16, pivots: []const f32, s: f32, width: f32) mesh_mod.SkinBlend {
    std.debug.assert(joints.len == pivots.len and joints.len >= 1);
    if (joints.len == 1) return .{ .a = joints[0] };
    // nearest child pivot boundary
    var best: usize = 1;
    var best_d: f32 = @abs(s - pivots[1]);
    for (2..pivots.len) |k| {
        const d = @abs(s - pivots[k]);
        if (d < best_d) {
            best_d = d;
            best = k;
        }
    }
    const b = pivots[best];
    const wb = m.smootherstep(b - width, b + width, s);
    return .{ .a = joints[best - 1], .b = joints[best], .wb = wb };
}

test "loft cylinder with domes is closed and outward" {
    const gpa = std.testing.allocator;
    var mesh: Mesh = .{};
    defer mesh.deinit(gpa);
    const Ctx = struct {
        fn section(_: *const @This(), _: f32) Section {
            return .{ .a = 0.5, .b = 0.5 };
        }
        fn skin(_: *const @This(), _: f32, _: Vec3) mesh_mod.SkinBlend {
            return .{ .a = 0 };
        }
    };
    const pts = [_]Vec3{ Vec3.zero, Vec3.init(0, 1, 0), Vec3.init(0, 2, 0) };
    const ctx: Ctx = .{};
    _ = try loft(gpa, &mesh, &pts, .{ .cols = 16, .ref_normal = Vec3.unit_x, .cap_start = .dome, .cap_end = .dome }, &ctx);
    mesh.computeNormals();
    // closed manifold: every edge used exactly twice
    var edges: std.AutoHashMapUnmanaged([2]u32, u32) = .empty;
    defer edges.deinit(gpa);
    var i: usize = 0;
    while (i < mesh.indices.items.len) : (i += 3) {
        for (0..3) |k| {
            const a = mesh.indices.items[i + k];
            const b = mesh.indices.items[i + (k + 1) % 3];
            const key = if (a < b) [2]u32{ a, b } else [2]u32{ b, a };
            const gop = try edges.getOrPut(gpa, key);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
        }
    }
    var it = edges.valueIterator();
    while (it.next()) |c| try std.testing.expectEqual(@as(u32, 2), c.*);
    // normals point away from the axis center
    for (mesh.vertices.items) |v| {
        const c = Vec3.init(0, m.clamp(v.pos.y, 0.5, 1.5), 0);
        try std.testing.expect(v.normal.dot(v.pos.sub(c)) > 0);
    }
}

test "chain skin blends at pivots" {
    const j = [_]u16{ 3, 4, 5 };
    const p = [_]f32{ 0, 1, 2 };
    const at_pivot = chainSkin(&j, &p, 1.0, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), at_pivot.wb, 1e-5);
    const mid = chainSkin(&j, &p, 0.5, 0.1);
    try std.testing.expectEqual(@as(u16, 3), mid.a);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mid.wb, 1e-5);
}
