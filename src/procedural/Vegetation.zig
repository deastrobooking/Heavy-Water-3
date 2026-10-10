//! Compact generated meshes for ground flora and distinct canopy silhouettes.
const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const GenMesh = @import("../character/mesh.zig").Mesh;
const Seed = @import("Seed.zig");
pub const variant_count = 6;
pub const tree_first = 3;
pub const names = [_][]const u8{ "grass", "fern", "wildflower", "broadleaf", "needleleaf", "willow" };
/// Material base colours, by variant (scatter tints multiply them).
pub const colors = [variant_count][4]f32{ .{ 0.30, 0.56, 0.22, 1 }, .{ 0.22, 0.48, 0.25, 1 }, .{ 0.82, 0.34, 0.65, 1 }, .{ 0.18, 0.43, 0.20, 1 }, .{ 0.12, 0.34, 0.20, 1 }, .{ 0.25, 0.49, 0.30, 1 } };
pub const stone = [3]f32{ 0.56, 0.57, 0.55 };
fn vertex(a: std.mem.Allocator, out: *GenMesh, p: [3]f32, n: [3]f32) !u32 {
    return out.addVertex(a, .{ .pos = .init(p[0], p[1], p[2]), .normal = .init(n[0], n[1], n[2]) });
}
fn finish(a: std.mem.Allocator, out: *GenMesh) !Mesh {
    const vertices = try a.alloc(Mesh.Vertex, out.vertices.items.len);
    errdefer a.free(vertices);
    for (vertices, out.vertices.items) |*v, source| v.* = .{ .position = .{ source.pos.x, source.pos.y, source.pos.z }, .normal = .{ source.normal.x, source.normal.y, source.normal.z }, .uv = .{ source.uv.x, source.uv.y } };
    const indices = try a.dupe(u32, out.indices.items);
    return .{ .vertices = vertices, .indices = indices };
}
fn blade(a: std.mem.Allocator, out: *GenMesh, root: [3]f32, tip: [3]f32, width: f32, angle: f32) !void {
    const side = [3]f32{ @cos(angle) * width / 2, 0, @sin(angle) * width / 2 };
    const l = try vertex(a, out, .{ root[0] - side[0], root[1], root[2] - side[2] }, .{ @sin(angle), 0.2, -@cos(angle) });
    const r = try vertex(a, out, .{ root[0] + side[0], root[1], root[2] + side[2] }, .{ @sin(angle), 0.2, -@cos(angle) });
    const t = try vertex(a, out, tip, .{ @sin(angle), 0.2, -@cos(angle) });
    try out.addTri(a, l, t, r);
}
pub fn plant(a: std.mem.Allocator, variant: u8) !Mesh {
    if (variant >= tree_first) return error.InvalidPlant;
    var out: GenMesh = .{};
    errdefer out.deinit(a);
    try out.vertices.ensureTotalCapacity(a, if (variant == 1) 100 else 48);
    try out.indices.ensureTotalCapacity(a, if (variant == 1) 180 else 72);
    if (variant == 0) {
        for (0..9) |i| {
            const t = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 9;
            try blade(a, &out, .{ 0, 0, 0 }, .{ @sin(t) * 0.28, 0.5 + @as(f32, @floatFromInt(i % 4)) * 0.08, @cos(t) * 0.28 }, 0.09, t);
        }
    } else if (variant == 1) {
        for (0..6) |i| {
            const t = @as(f32, @floatFromInt(i)) * std.math.pi / 3;
            const y = 0.65 + @as(f32, @floatFromInt(i % 3)) * 0.1;
            try blade(a, &out, .{ 0, 0, 0 }, .{ @cos(t) * 0.05, y, @sin(t) * 0.05 }, 0.035, t);
            for (0..4) |j| {
                const h = 0.2 + @as(f32, @floatFromInt(j)) * 0.16;
                const side: f32 = if (j % 2 == 0) 1 else -1;
                try blade(a, &out, .{ @cos(t) * 0.03, h, @sin(t) * 0.03 }, .{ @cos(t) * 0.03 + side * 0.15, h + 0.06, @sin(t) * 0.03 + 0.06 }, 0.08, t);
            }
        }
    } else {
        for (0..5) |i| {
            const t = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 5;
            try blade(a, &out, .{ 0, 0, 0 }, .{ @cos(t) * 0.08, 0.62, @sin(t) * 0.08 }, 0.025, t);
            const l = try vertex(a, &out, .{ @cos(t) * 0.08 - 0.08, 0.72, @sin(t) * 0.08 }, .{ 0, 0.4, 1 });
            const m = try vertex(a, &out, .{ @cos(t) * 0.08, 0.76, @sin(t) * 0.08 }, .{ 0, 1, 0 });
            const r = try vertex(a, &out, .{ @cos(t) * 0.08 + 0.08, 0.72, @sin(t) * 0.08 }, .{ 0, 0.4, 1 });
            try out.addTri(a, l, m, r);
        }
    }
    const mesh = try finish(a, &out);
    out.deinit(a);
    return mesh;
}
fn ellipsoid(a: std.mem.Allocator, out: *GenMesh, center: [3]f32, radius: [3]f32, rows: usize, cols: usize) !void {
    const start: u32 = @intCast(out.vertices.items.len);
    for (0..rows + 1) |r| for (0..cols) |c| {
        const lat = std.math.pi * @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rows));
        const lon = 2 * std.math.pi * @as(f32, @floatFromInt(c)) / @as(f32, @floatFromInt(cols));
        const n = [3]f32{ @sin(lat) * @cos(lon), @cos(lat), @sin(lat) * @sin(lon) };
        _ = try vertex(a, out, .{ center[0] + n[0] * radius[0], center[1] + n[1] * radius[1], center[2] + n[2] * radius[2] }, .{ n[0] / radius[0], n[1] / radius[1], n[2] / radius[2] });
    };
    for (0..rows) |r| for (0..cols) |c| {
        const x: u32 = start + @as(u32, @intCast(r * cols + c));
        const y = start + @as(u32, @intCast(r * cols + (c + 1) % cols));
        try out.addQuad(a, x, y, y + @as(u32, @intCast(cols)), x + @as(u32, @intCast(cols)));
    };
}
fn cone(a: std.mem.Allocator, out: *GenMesh, base: f32, height: f32, radius: f32) !void {
    const start: u32 = @intCast(out.vertices.items.len);
    const sides = 12;
    for (0..2) |row| for (0..sides) |i| {
        const t = 2 * std.math.pi * @as(f32, @floatFromInt(i)) / sides;
        const r = if (row == 0) radius else 0.015;
        _ = try vertex(a, out, .{ @cos(t) * r, base + @as(f32, @floatFromInt(row)) * height, @sin(t) * r }, .{ @cos(t) * height, radius, @sin(t) * height });
    };
    for (0..sides) |i| {
        const x = start + @as(u32, @intCast(i));
        const y = start + @as(u32, @intCast((i + 1) % sides));
        try out.addQuad(a, x, y, y + sides, x + sides);
    }
}
pub fn tree(a: std.mem.Allocator, species: u8) !Mesh {
    if (species >= 3) return error.InvalidTree;
    var out: GenMesh = .{};
    errdefer out.deinit(a);
    try out.vertices.ensureTotalCapacity(a, 1200);
    try out.indices.ensureTotalCapacity(a, 4500);
    switch (species) {
        0 => {
            try ellipsoid(a, &out, .{ 0, 0.68, 0 }, .{ 0.36, 0.31, 0.36 }, 8, 12);
            try ellipsoid(a, &out, .{ 0.23, 0.72, 0.02 }, .{ 0.24, 0.22, 0.25 }, 7, 10);
            try ellipsoid(a, &out, .{ -0.23, 0.68, -0.04 }, .{ 0.24, 0.22, 0.24 }, 7, 10);
        },
        1 => {
            try cone(a, &out, 0.28, 0.7, 0.38);
            try cone(a, &out, 0.08, 0.66, 0.29);
            try cone(a, &out, 0, 0.55, 0.2);
        },
        2 => {
            try ellipsoid(a, &out, .{ 0, 0.77, 0 }, .{ 0.31, 0.18, 0.31 }, 7, 12);
            for (0..7) |i| {
                const t = 2 * std.math.pi * @as(f32, @floatFromInt(i)) / 7;
                const x = @cos(t) * 0.34;
                const z = @sin(t) * 0.34;
                try ellipsoid(a, &out, .{ x, 0.43, z }, .{ 0.09, 0.27, 0.09 }, 5, 8);
                try ellipsoid(a, &out, .{ x * 1.18, 0.20, z * 1.18 }, .{ 0.07, 0.18, 0.07 }, 5, 8);
            }
        },
        else => unreachable,
    }
    const mesh = try finish(a, &out);
    out.deinit(a);
    return mesh;
}
pub const boulder_count = 3;
pub const boulder_names = [boulder_count][]const u8{ "boulder_round", "boulder_tall", "boulder_slab" };

/// A faceted, lumpy boulder about one unit across that sits partly sunk into the ground. Every
/// facet has its own flat normal, so the stone reads as cut planes under the cel ramp.
pub fn boulder(a: std.mem.Allocator, shape: u8) !Mesh {
    if (shape >= boulder_count) return error.InvalidBoulder;
    const rows = 4;
    const cols = 7;
    const sizes = [boulder_count][3]f32{ .{ 0.62, 0.42, 0.55 }, .{ 0.45, 0.62, 0.42 }, .{ 0.78, 0.30, 0.62 } };
    const size = sizes[shape];
    const center = [3]f32{ 0, size[1] * 0.55, 0 };
    var ring: [rows + 1][cols][3]f32 = undefined;
    for (0..rows + 1) |r| for (0..cols) |c| {
        const lat = std.math.pi * @as(f32, @floatFromInt(r)) / rows;
        const lon = 2 * std.math.pi * (@as(f32, @floatFromInt(c)) + @as(f32, @floatFromInt(r % 2)) * 0.5) / cols;
        const pole = r == 0 or r == rows;
        const k = if (pole) 1 else 0.8 + 0.32 * Seed.unit(Seed.mix(@as(u64, shape) * 977 + r * 31 + c));
        ring[r][c] = .{ center[0] + @sin(lat) * @cos(lon) * size[0] * k, center[1] + @cos(lat) * size[1] * k, center[2] + @sin(lat) * @sin(lon) * size[2] * k };
    };
    const vertices = try a.alloc(Mesh.Vertex, rows * cols * 6);
    errdefer a.free(vertices);
    const indices = try a.alloc(u32, rows * cols * 6);
    var n: usize = 0;
    for (0..rows) |r| for (0..cols) |c| {
        const q = [4][3]f32{ ring[r][c], ring[r][(c + 1) % cols], ring[r + 1][(c + 1) % cols], ring[r + 1][c] };
        for ([2][3]usize{ .{ 0, 1, 2 }, .{ 0, 2, 3 } }) |tri| {
            const p0 = q[tri[0]];
            var p1 = q[tri[1]];
            var p2 = q[tri[2]];
            const e1 = [3]f32{ p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2] };
            const e2 = [3]f32{ p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2] };
            var normal = [3]f32{ e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
            const out = [3]f32{ (p0[0] + p1[0] + p2[0]) / 3 - center[0], (p0[1] + p1[1] + p2[1]) / 3 - center[1], (p0[2] + p1[2] + p2[2]) / 3 - center[2] };
            if (normal[0] * out[0] + normal[1] * out[1] + normal[2] * out[2] < 0) {
                std.mem.swap([3]f32, &p1, &p2);
                normal = .{ -normal[0], -normal[1], -normal[2] };
            }
            const length = @sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]);
            // Pole triangles collapse to a line: give them the outward direction instead.
            const reach = @sqrt(out[0] * out[0] + out[1] * out[1] + out[2] * out[2]);
            const unit = if (length > 1e-6) [3]f32{ normal[0] / length, normal[1] / length, normal[2] / length } else [3]f32{ out[0] / reach, out[1] / reach, out[2] / reach };
            for ([3][3]f32{ p0, p1, p2 }) |v| {
                vertices[n] = .{ .position = v, .normal = unit, .uv = .{ v[0] + v[2], v[1] } };
                indices[n] = @intCast(n);
                n += 1;
            }
        }
    };
    return .{ .vertices = vertices, .indices = indices };
}

pub fn trunk(a: std.mem.Allocator) !Mesh {
    var out: GenMesh = .{};
    errdefer out.deinit(a);
    try out.vertices.ensureTotalCapacity(a, 24);
    try out.indices.ensureTotalCapacity(a, 48);
    try cone(a, &out, 0, 1, 0.023);
    const mesh = try finish(a, &out);
    out.deinit(a);
    return mesh;
}
test "ground flora and canopy species have distinct geometry" {
    const a = std.testing.allocator;
    var flora: [3]Mesh = undefined;
    for (&flora, 0..) |*m, i| m.* = try plant(a, @intCast(i));
    defer for (flora) |m| m.deinit(a);
    try std.testing.expect(flora[0].vertices.len != flora[1].vertices.len);
    var trees: [3]Mesh = undefined;
    for (&trees, 0..) |*m, i| m.* = try tree(a, @intCast(i));
    defer for (trees) |m| m.deinit(a);
    try std.testing.expect(trees[0].vertices.len != trees[1].vertices.len and trees[1].vertices.len != trees[2].vertices.len);
}

test "boulders are closed faceted stones with outward flat normals, sunk into the ground" {
    const a = std.testing.allocator;
    for (0..boulder_count) |i| {
        const m = try boulder(a, @intCast(i));
        defer m.deinit(a);
        var lowest: f32 = 1;
        var highest: f32 = -1;
        for (m.vertices) |v| {
            lowest = @min(lowest, v.position[1]);
            highest = @max(highest, v.position[1]);
            try std.testing.expectApproxEqAbs(@as(f32, 1), @sqrt(v.normal[0] * v.normal[0] + v.normal[1] * v.normal[1] + v.normal[2] * v.normal[2]), 0.01);
        }
        try std.testing.expect(lowest < 0 and highest > 0.4);
    }
    try std.testing.expectError(error.InvalidBoulder, boulder(a, boulder_count));
}
