//! Static triangle-mesh collider with a bounding-volume hierarchy (median split on the longest
//! axis, up to four triangles per leaf). Built once; queried by rays, boxes, and points.
//! Triangles are one-sided for penetration (their front faces the counter-clockwise normal)
//! and two-sided for rays.
const std = @import("std");
const R = @import("Rotation.zig");
const Vec3 = R.Vec3;
const TriangleMesh = @This();

pub const leaf_size = 4;
pub const Triangle = struct { a: Vec3, b: Vec3, c: Vec3, normal: Vec3 };
const Node = struct {
    lo: Vec3,
    hi: Vec3,
    /// Leaf: first triangle and count. Inner: left child index (right is left + 1) and count 0.
    first: u32,
    count: u32,
};

allocator: std.mem.Allocator,
/// Owned allocations; `triangles` and `nodes` are their used prefixes.
triangle_storage: []Triangle,
node_storage: []Node,
triangles: []Triangle,
nodes: []Node,
lo: Vec3,
hi: Vec3,

pub const Hit = struct { distance: f32, point: Vec3, normal: Vec3, triangle: u32 };

pub fn build(allocator: std.mem.Allocator, positions: []const Vec3, indices: []const u32) !TriangleMesh {
    if (indices.len == 0 or indices.len % 3 != 0) return error.InvalidMesh;
    const count = indices.len / 3;
    const triangles = try allocator.alloc(Triangle, count);
    errdefer allocator.free(triangles);
    var kept: usize = 0;
    for (0..count) |t| {
        const ia = indices[t * 3];
        const ib = indices[t * 3 + 1];
        const ic = indices[t * 3 + 2];
        if (ia >= positions.len or ib >= positions.len or ic >= positions.len) return error.InvalidMesh;
        const a = positions[ia];
        const b = positions[ib];
        const c = positions[ic];
        for (a ++ b ++ c) |v| if (!std.math.isFinite(v)) return error.InvalidMesh;
        const n = R.cross(R.sub(b, a), R.sub(c, a));
        // Degenerate slivers cannot be collided with meaningfully.
        if (R.length(n) < 1e-9) continue;
        triangles[kept] = .{ .a = a, .b = b, .c = c, .normal = R.normalize(n) };
        kept += 1;
    }
    if (kept == 0) return error.InvalidMesh;
    const tris = triangles[0..kept];
    const nodes = try allocator.alloc(Node, 2 * kept);
    errdefer allocator.free(nodes);
    var used: usize = 1;
    split(tris, nodes, 0, 0, @intCast(kept), &used);
    return .{ .allocator = allocator, .triangle_storage = triangles, .node_storage = nodes, .triangles = tris, .nodes = nodes[0..used], .lo = nodes[0].lo, .hi = nodes[0].hi };
}

pub fn deinit(self: *TriangleMesh) void {
    self.allocator.free(self.node_storage);
    self.allocator.free(self.triangle_storage);
}

fn centroid(t: Triangle) Vec3 {
    return R.scale(R.add(R.add(t.a, t.b), t.c), 1.0 / 3.0);
}

fn split(tris: []Triangle, nodes: []Node, index: usize, first: u32, count: u32, used: *usize) void {
    var lo: Vec3 = @splat(std.math.inf(f32));
    var hi: Vec3 = @splat(-std.math.inf(f32));
    for (tris[first..][0..count]) |t| for ([_]Vec3{ t.a, t.b, t.c }) |p| for (0..3) |k| {
        lo[k] = @min(lo[k], p[k]);
        hi[k] = @max(hi[k], p[k]);
    };
    if (count <= leaf_size) {
        nodes[index] = .{ .lo = lo, .hi = hi, .first = first, .count = count };
        return;
    }
    var axis: usize = 0;
    for (1..3) |k| if (hi[k] - lo[k] > hi[axis] - lo[axis]) {
        axis = k;
    };
    const slice = tris[first..][0..count];
    std.mem.sort(Triangle, slice, axis, struct {
        fn less(a: usize, x: Triangle, y: Triangle) bool {
            return centroid(x)[a] < centroid(y)[a];
        }
    }.less);
    const left: u32 = @intCast(used.*);
    used.* += 2;
    nodes[index] = .{ .lo = lo, .hi = hi, .first = left, .count = 0 };
    const half = count / 2;
    split(tris, nodes, left, first, half, used);
    split(tris, nodes, left + 1, first + half, count - half, used);
}

fn rayBox(origin: Vec3, inverse: Vec3, lo: Vec3, hi: Vec3, max: f32) bool {
    var near: f32 = 0;
    var far = max;
    for (0..3) |k| {
        var t0 = (lo[k] - origin[k]) * inverse[k];
        var t1 = (hi[k] - origin[k]) * inverse[k];
        if (t0 > t1) std.mem.swap(f32, &t0, &t1);
        // NaN from 0 × ∞ (ray on a slab plane) is treated as inside.
        if (t0 > near) near = t0;
        if (t1 < far) far = t1;
        if (near > far) return false;
    }
    return true;
}

/// Möller–Trumbore; two-sided.
fn rayTriangle(origin: Vec3, dir: Vec3, t: Triangle) ?f32 {
    const e1 = R.sub(t.b, t.a);
    const e2 = R.sub(t.c, t.a);
    const p = R.cross(dir, e2);
    const det = R.dot(e1, p);
    if (@abs(det) < 1e-12) return null;
    const inv = 1 / det;
    const s = R.sub(origin, t.a);
    const u = R.dot(s, p) * inv;
    if (u < 0 or u > 1) return null;
    const q = R.cross(s, e1);
    const v = R.dot(dir, q) * inv;
    if (v < 0 or u + v > 1) return null;
    const distance = R.dot(e2, q) * inv;
    return if (distance >= 0) distance else null;
}

/// Nearest hit along a normalized ray within `max_distance`.
pub fn raycast(self: *const TriangleMesh, origin: Vec3, dir: Vec3, max_distance: f32) ?Hit {
    const inverse: Vec3 = .{ 1 / dir[0], 1 / dir[1], 1 / dir[2] };
    var best: ?Hit = null;
    var limit = max_distance;
    var stack: [64]u32 = undefined;
    var top: usize = 1;
    stack[0] = 0;
    while (top > 0) {
        top -= 1;
        const node = self.nodes[stack[top]];
        if (!rayBox(origin, inverse, node.lo, node.hi, limit)) continue;
        if (node.count == 0) {
            stack[top] = node.first;
            stack[top + 1] = node.first + 1;
            top += 2;
            continue;
        }
        for (self.triangles[node.first..][0..node.count], node.first..) |t, i| {
            const d = rayTriangle(origin, dir, t) orelse continue;
            if (d > limit) continue;
            limit = d;
            best = .{ .distance = d, .point = R.add(origin, R.scale(dir, d)), .normal = if (R.dot(t.normal, dir) > 0) R.scale(t.normal, -1) else t.normal, .triangle = @intCast(i) };
        }
    }
    return best;
}

/// Indices of triangles whose bounds overlap the box; returns how many were written.
pub fn overlap(self: *const TriangleMesh, lo: Vec3, hi: Vec3, out: []u32) usize {
    var n: usize = 0;
    var stack: [64]u32 = undefined;
    var top: usize = 1;
    stack[0] = 0;
    while (top > 0) {
        top -= 1;
        const node = self.nodes[stack[top]];
        var hit = true;
        for (0..3) |k| hit = hit and node.lo[k] <= hi[k] and node.hi[k] >= lo[k];
        if (!hit) continue;
        if (node.count == 0) {
            stack[top] = node.first;
            stack[top + 1] = node.first + 1;
            top += 2;
            continue;
        }
        for (self.triangles[node.first..][0..node.count], node.first..) |t, i| {
            var inside = true;
            for (0..3) |k| inside = inside and @min(t.a[k], t.b[k], t.c[k]) <= hi[k] and @max(t.a[k], t.b[k], t.c[k]) >= lo[k];
            if (!inside) continue;
            if (n == out.len) return n;
            out[n] = @intCast(i);
            n += 1;
        }
    }
    return n;
}

/// Closest point on a triangle (Ericson, Real-Time Collision Detection 5.1.5).
pub fn closestPoint(t: Triangle, p: Vec3) Vec3 {
    const ab = R.sub(t.b, t.a);
    const ac = R.sub(t.c, t.a);
    const ap = R.sub(p, t.a);
    const d1 = R.dot(ab, ap);
    const d2 = R.dot(ac, ap);
    if (d1 <= 0 and d2 <= 0) return t.a;
    const bp = R.sub(p, t.b);
    const d3 = R.dot(ab, bp);
    const d4 = R.dot(ac, bp);
    if (d3 >= 0 and d4 <= d3) return t.b;
    const vc = d1 * d4 - d3 * d2;
    if (vc <= 0 and d1 >= 0 and d3 <= 0) return R.add(t.a, R.scale(ab, d1 / (d1 - d3)));
    const cp = R.sub(p, t.c);
    const d5 = R.dot(ab, cp);
    const d6 = R.dot(ac, cp);
    if (d6 >= 0 and d5 <= d6) return t.c;
    const vb = d5 * d2 - d1 * d6;
    if (vb <= 0 and d2 >= 0 and d6 <= 0) return R.add(t.a, R.scale(ac, d2 / (d2 - d6)));
    const va = d3 * d6 - d5 * d4;
    if (va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0) return R.add(t.b, R.scale(R.sub(t.c, t.b), (d4 - d3) / ((d4 - d3) + (d5 - d6))));
    const denom = 1 / (va + vb + vc);
    return R.add(t.a, R.add(R.scale(ab, vb * denom), R.scale(ac, vc * denom)));
}

/// Twelve triangles of an oriented box, outward-facing, for static decks and walls.
pub fn boxGeometry(center: Vec3, half: Vec3, rotation: R.Quat, positions: *[8]Vec3, indices: *[36]u32) void {
    for (0..8) |i| {
        const local: Vec3 = .{ if (i & 1 != 0) half[0] else -half[0], if (i & 2 != 0) half[1] else -half[1], if (i & 4 != 0) half[2] else -half[2] };
        positions[i] = R.add(center, R.rotate(rotation, local));
    }
    // Faces: -X, +X, -Y, +Y, -Z, +Z with counter-clockwise outward winding.
    indices.* = .{ 0, 4, 6, 0, 6, 2, 1, 3, 7, 1, 7, 5, 0, 1, 5, 0, 5, 4, 2, 6, 7, 2, 7, 3, 0, 2, 3, 0, 3, 1, 4, 5, 7, 4, 7, 6 };
}

test "BVH ray casts match brute force and boxes face outward" {
    const allocator = std.testing.allocator;
    // A 20×20 grid of bumpy quads.
    var positions: [21 * 21]Vec3 = undefined;
    for (0..21) |z| for (0..21) |x| {
        const fx: f32 = @floatFromInt(x);
        const fz: f32 = @floatFromInt(z);
        positions[z * 21 + x] = .{ fx, @sin(fx * 0.7) * @cos(fz * 0.5), fz };
    };
    var indices: [20 * 20 * 6]u32 = undefined;
    for (0..20) |z| for (0..20) |x| {
        const a: u32 = @intCast(z * 21 + x);
        @memcpy(indices[(z * 20 + x) * 6 ..][0..6], &[_]u32{ a, a + 21, a + 1, a + 1, a + 21, a + 22 });
    };
    var mesh = try build(allocator, &positions, &indices);
    defer mesh.deinit();
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();
    for (0..300) |_| {
        const origin: Vec3 = .{ random.float(f32) * 24 - 2, 3 + random.float(f32) * 2, random.float(f32) * 24 - 2 };
        const dir = R.normalize(.{ random.float(f32) - 0.5, -0.4 - random.float(f32), random.float(f32) - 0.5 });
        var brute: ?f32 = null;
        for (mesh.triangles) |t| if (rayTriangle(origin, dir, t)) |d| {
            if (d <= 50 and (brute == null or d < brute.?)) brute = d;
        };
        const hit = mesh.raycast(origin, dir, 50);
        try std.testing.expectEqual(brute != null, hit != null);
        if (hit) |h| try std.testing.expectApproxEqAbs(brute.?, h.distance, 1e-4);
    }
    var buffer: [64]u32 = undefined;
    const n = mesh.overlap(.{ 4.2, -5, 4.2 }, .{ 4.8, 5, 4.8 }, &buffer);
    try std.testing.expect(n >= 2 and n <= 8);
    try std.testing.expectError(error.InvalidMesh, build(allocator, &positions, indices[0..4]));

    var box_positions: [8]Vec3 = undefined;
    var box_indices: [36]u32 = undefined;
    boxGeometry(.{ 1, 2, 3 }, .{ 1, 0.5, 2 }, R.axisAngle(.{ 1, 0, 0 }, 0.3), &box_positions, &box_indices);
    var box = try build(allocator, &box_positions, &box_indices);
    defer box.deinit();
    for (box.triangles) |t| try std.testing.expect(R.dot(t.normal, R.sub(centroid(t), .{ 1, 2, 3 })) > 0);
    const closest = closestPoint(box.triangles[0], .{ -10, 2, 3 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), closest[0], 1e-5);
}

fn buildProbe(allocator: std.mem.Allocator) !void {
    var positions: [8]Vec3 = undefined;
    var indices: [36]u32 = undefined;
    boxGeometry(.{ 0, 0, 0 }, .{ 1, 1, 1 }, R.identity, &positions, &indices);
    var mesh = try build(allocator, &positions, &indices);
    mesh.deinit();
}

test "mesh build cleans up on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, buildProbe, .{});
}
