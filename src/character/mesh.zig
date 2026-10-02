//! Skinned triangle mesh container plus topology helpers used by every generator.

const std = @import("std");
const m = @import("math.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Allocator = std.mem.Allocator;

/// Body regions. Every body vertex carries one; clothing selects by region.
pub const Region = enum(u8) {
    head,
    face,
    neck,
    chest,
    belly,
    hips,
    upper_arm_l,
    lower_arm_l,
    hand_l,
    upper_arm_r,
    lower_arm_r,
    hand_r,
    thigh_l,
    shin_l,
    foot_l,
    thigh_r,
    shin_r,
    foot_r,
    hair,
    garment,
};
pub const RegionSet = std.EnumSet(Region);

/// Material slots; a renderer maps these to toon ramps / colors.
pub const Material = enum(u8) {
    skin,
    hair,
    eye_white,
    iris,
    cloth_top,
    cloth_bottom,
    cloth_outer,
    shoes,
    accent,
    /// Hard-surface armor plates (rigidly bound, segmented).
    armor,
    // hard-surface (vehicles, props)
    paint,
    paint_accent,
    glass,
    carbon,
    metal,
    emissive,
    rubber,
};

pub const max_influences = 4;

/// GPU-ready vertex (extern => stable layout, upload as-is).
pub const Vertex = extern struct {
    pos: Vec3,
    normal: Vec3 = Vec3.zero,
    uv: Vec2 = .{},
    joints: [max_influences]u16 = .{ 0, 0, 0, 0 },
    weights: [max_influences]f32 = .{ 1, 0, 0, 0 },
    region: Region = .garment,
    material: Material = .skin,
    _pad: [2]u8 = .{ 0, 0 },
};

/// Up to two-bone blend, the common case for lofted parts.
pub const SkinBlend = struct {
    a: u16,
    b: u16 = 0,
    wb: f32 = 0, // weight of b; a gets 1 - wb

    pub fn apply(s: SkinBlend, v: *Vertex) void {
        v.joints = .{ s.a, s.b, 0, 0 };
        v.weights = .{ 1 - s.wb, s.wb, 0, 0 };
    }
};

pub const Mesh = struct {
    vertices: std.ArrayList(Vertex) = .empty,
    indices: std.ArrayList(u32) = .empty,

    pub fn deinit(self: *Mesh, gpa: Allocator) void {
        self.vertices.deinit(gpa);
        self.indices.deinit(gpa);
    }

    pub fn vertexCount(self: *const Mesh) u32 {
        return @intCast(self.vertices.items.len);
    }

    pub fn addVertex(self: *Mesh, gpa: Allocator, v: Vertex) !u32 {
        const idx = self.vertexCount();
        try self.vertices.append(gpa, v);
        return idx;
    }

    /// Counter-clockwise winding = front face.
    pub fn addTri(self: *Mesh, gpa: Allocator, a: u32, b: u32, c: u32) !void {
        try self.indices.appendSlice(gpa, &.{ a, b, c });
    }

    pub fn addQuad(self: *Mesh, gpa: Allocator, a: u32, b: u32, c: u32, d: u32) !void {
        try self.addTri(gpa, a, b, c);
        try self.addTri(gpa, a, c, d);
    }

    /// Connect `rows` consecutive rings of `cols` vertices starting at `base`.
    /// Rings must be laid out ring-major. With `closed`, each ring wraps around.
    /// `flip` reverses winding (use when the ring orientation produces inward faces).
    pub fn stitchRings(self: *Mesh, gpa: Allocator, base: u32, rows: u32, cols: u32, closed: bool, flip: bool) !void {
        const seg_cols = if (closed) cols else cols - 1;
        var r: u32 = 0;
        while (r + 1 < rows) : (r += 1) {
            var c: u32 = 0;
            while (c < seg_cols) : (c += 1) {
                const c1 = if (c + 1 == cols) 0 else c + 1;
                const a = base + r * cols + c;
                const b = base + r * cols + c1;
                const cc = base + (r + 1) * cols + c1;
                const d = base + (r + 1) * cols + c;
                if (flip) try self.addQuad(gpa, a, d, cc, b) else try self.addQuad(gpa, a, b, cc, d);
            }
        }
    }

    /// Fan-cap a closed ring with a center vertex.
    pub fn capRing(self: *Mesh, gpa: Allocator, ring_base: u32, cols: u32, center: u32, flip: bool) !void {
        var c: u32 = 0;
        while (c < cols) : (c += 1) {
            const c1 = (c + 1) % cols;
            if (flip) try self.addTri(gpa, center, ring_base + c1, ring_base + c) else try self.addTri(gpa, center, ring_base + c, ring_base + c1);
        }
    }

    /// Area-weighted smooth vertex normals.
    pub fn computeNormals(self: *Mesh) void {
        const vs = self.vertices.items;
        for (vs) |*v| v.normal = Vec3.zero;
        var i: usize = 0;
        while (i + 2 < self.indices.items.len) : (i += 3) {
            const ia = self.indices.items[i];
            const ib = self.indices.items[i + 1];
            const ic = self.indices.items[i + 2];
            const n = vs[ib].pos.sub(vs[ia].pos).cross(vs[ic].pos.sub(vs[ia].pos));
            vs[ia].normal = vs[ia].normal.add(n);
            vs[ib].normal = vs[ib].normal.add(n);
            vs[ic].normal = vs[ic].normal.add(n);
        }
        for (vs) |*v| v.normal = v.normal.normalizeOr(Vec3.unit_y);
    }

    /// Append another mesh (indices are rebased).
    pub fn append(self: *Mesh, gpa: Allocator, other: *const Mesh) !void {
        const base = self.vertexCount();
        try self.vertices.appendSlice(gpa, other.vertices.items);
        try self.indices.ensureUnusedCapacity(gpa, other.indices.items.len);
        for (other.indices.items) |idx| self.indices.appendAssumeCapacity(idx + base);
    }

    /// Sort weights descending and renormalize to sum 1. Call after any
    /// generator writes more than two influences.
    pub fn normalizeWeights(self: *Mesh) void {
        for (self.vertices.items) |*v| {
            // insertion sort (4 elements)
            var i: usize = 1;
            while (i < max_influences) : (i += 1) {
                var j = i;
                while (j > 0 and v.weights[j] > v.weights[j - 1]) : (j -= 1) {
                    std.mem.swap(f32, &v.weights[j], &v.weights[j - 1]);
                    std.mem.swap(u16, &v.joints[j], &v.joints[j - 1]);
                }
            }
            var sum: f32 = 0;
            for (v.weights) |w| sum += w;
            if (sum < m.eps) {
                v.weights = .{ 1, 0, 0, 0 };
            } else for (&v.weights) |*w| {
                w.* /= sum;
            }
        }
    }

    pub fn bounds(self: *const Mesh) struct { min: Vec3, max: Vec3 } {
        var lo = Vec3.splat(std.math.floatMax(f32));
        var hi = Vec3.splat(-std.math.floatMax(f32));
        for (self.vertices.items) |v| {
            lo = lo.min(v.pos);
            hi = hi.max(v.pos);
        }
        return .{ .min = lo, .max = hi };
    }

    /// Wavefront OBJ text (positions, normals, uvs; one group per material).
    pub fn writeObj(self: *const Mesh, gpa: Allocator, out: *std.ArrayList(u8)) !void {
        try out.print(gpa, "# animegen procedural mesh: {d} verts, {d} tris\n", .{ self.vertices.items.len, self.indices.items.len / 3 });
        for (self.vertices.items) |v| try out.print(gpa, "v {d:.5} {d:.5} {d:.5}\n", .{ v.pos.x, v.pos.y, v.pos.z });
        for (self.vertices.items) |v| try out.print(gpa, "vn {d:.4} {d:.4} {d:.4}\n", .{ v.normal.x, v.normal.y, v.normal.z });
        for (self.vertices.items) |v| try out.print(gpa, "vt {d:.4} {d:.4}\n", .{ v.uv.x, v.uv.y });
        inline for (std.meta.fields(Material)) |f| {
            const mat: Material = @enumFromInt(f.value);
            var wrote_header = false;
            var i: usize = 0;
            while (i + 2 < self.indices.items.len) : (i += 3) {
                const a = self.indices.items[i];
                if (self.vertices.items[a].material != mat) continue;
                if (!wrote_header) {
                    try out.print(gpa, "g {s}\nusemtl {s}\n", .{ f.name, f.name });
                    wrote_header = true;
                }
                const b = self.indices.items[i + 1];
                const c = self.indices.items[i + 2];
                try out.print(gpa, "f {d}/{d}/{d} {d}/{d}/{d} {d}/{d}/{d}\n", .{ a + 1, a + 1, a + 1, b + 1, b + 1, b + 1, c + 1, c + 1, c + 1 });
            }
        }
    }
};

/// Outline ("inverted hull") normals: average the normals of every vertex that
/// shares a position. Lofted parts have UV seams/duplicated verts; extruding
/// along split normals tears the outline open. Writes one normal per vertex.
pub fn computeOutlineNormals(gpa: Allocator, mesh: *const Mesh, out: []Vec3) !void {
    std.debug.assert(out.len == mesh.vertices.items.len);
    const Key = struct { x: i32, y: i32, z: i32 };
    var map: std.AutoHashMapUnmanaged(Key, Vec3) = .empty;
    defer map.deinit(gpa);
    const q: f32 = 1e4; // 0.1 mm quantization
    const keyOf = struct {
        fn f(p: Vec3, qq: f32) Key {
            return .{ .x = @intFromFloat(@round(p.x * qq)), .y = @intFromFloat(@round(p.y * qq)), .z = @intFromFloat(@round(p.z * qq)) };
        }
    }.f;
    for (mesh.vertices.items) |v| {
        const gop = try map.getOrPut(gpa, keyOf(v.pos, q));
        if (!gop.found_existing) gop.value_ptr.* = Vec3.zero;
        gop.value_ptr.* = gop.value_ptr.*.add(v.normal);
    }
    for (mesh.vertices.items, 0..) |v, i| {
        out[i] = (map.get(keyOf(v.pos, q)) orelse v.normal).normalizeOr(v.normal);
    }
}

test "stitch + normals on a cylinder point outward" {
    const gpa = std.testing.allocator;
    var mesh: Mesh = .{};
    defer mesh.deinit(gpa);
    const cols = 12;
    for (0..3) |r| for (0..cols) |c| {
        const th = @as(f32, @floatFromInt(c)) / cols * m.tau;
        _ = try mesh.addVertex(gpa, .{ .pos = Vec3.init(@cos(th), @floatFromInt(r), -@sin(th)) });
    };
    try mesh.stitchRings(gpa, 0, 3, cols, true, false);
    mesh.computeNormals();
    for (mesh.vertices.items) |v| {
        const radial = Vec3.init(v.pos.x, 0, v.pos.z);
        try std.testing.expect(v.normal.dot(radial) > 0.5);
    }
}
