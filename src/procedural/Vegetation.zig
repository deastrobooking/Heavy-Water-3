//! Compact generated meshes for ground flora and distinct canopy silhouettes.
const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const GenMesh = @import("../character/mesh.zig").Mesh;
const Seed = @import("Seed.zig");
const LSystem = @import("LSystem.zig");
pub const variant_count = 15;
pub const tree_first = 3;
pub const tree_count = 8;
pub const tree_variants = [_]u8{ 3, 4, 5, 6, 11, 12, 13, 14 };
pub const names = [_][]const u8{ "grass", "fern", "wildflower", "broadleaf", "needleleaf", "willow", "redwood", "manzanita", "ember_blossom", "moonbell", "sunspear", "copper_fan", "moon_cascade", "star_blossom", "pine" };
/// Material base colours, by variant (scatter tints multiply them).
pub const colors = [variant_count][4]f32{
    .{ 0.30, 0.56, 0.22, 1 }, .{ 0.22, 0.48, 0.25, 1 }, .{ 0.82, 0.34, 0.65, 1 },
    .{ 0.18, 0.43, 0.20, 1 }, .{ 0.12, 0.34, 0.20, 1 }, .{ 0.25, 0.49, 0.30, 1 },
    .{ 0.34, 0.055, 0.09, 1 }, .{ 0.25, 0.43, 0.22, 1 }, .{ 0.82, 0.12, 0.21, 1 },
    .{ 0.16, 0.42, 0.86, 1 }, .{ 0.92, 0.58, 0.12, 1 },
    .{ 0.46, 0.68, 0.34, 1 }, .{ 0.26, 0.55, 0.48, 1 }, .{ 0.52, 0.34, 0.68, 1 }, .{ 0.12, 0.31, 0.16, 1 },
};
pub const trunk_colors = [tree_count][4]f32{
    .{ 0.24, 0.15, 0.09, 1 }, .{ 0.21, 0.13, 0.08, 1 }, .{ 0.28, 0.19, 0.12, 1 }, .{ 0.76, 0.44, 0.48, 1 },
    .{ 0.42, 0.23, 0.11, 1 }, .{ 0.27, 0.19, 0.16, 1 }, .{ 0.34, 0.20, 0.28, 1 }, .{ 0.29, 0.20, 0.13, 1 },
};
pub fn treeIndex(variant: u8) ?u8 {
    for (tree_variants, 0..) |v, i| if (v == variant) return @intCast(i);
    return null;
}
pub fn isTree(variant: u8) bool {
    return treeIndex(variant) != null;
}
pub fn isRedwood(variant: u8) bool {
    return if (treeIndex(variant)) |species| species == 3 else false;
}
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

/// Round swept wood keeps scaled giant pine branches from reading as oversized grass blades.
fn twig(a: std.mem.Allocator, out: *GenMesh, start: [3]f32, end: [3]f32, root_radius: f32, tip_radius: f32) !void {
    const sides = 6;
    const axis_raw = [3]f32{ end[0] - start[0], end[1] - start[1], end[2] - start[2] };
    const length = @sqrt(axis_raw[0] * axis_raw[0] + axis_raw[1] * axis_raw[1] + axis_raw[2] * axis_raw[2]);
    if (length < 1e-5) return;
    const axis = [3]f32{ axis_raw[0] / length, axis_raw[1] / length, axis_raw[2] / length };
    const reference: [3]f32 = if (@abs(axis[1]) < 0.9) .{ 0, 1, 0 } else .{ 1, 0, 0 };
    const crossed = cross3(axis, reference);
    const crossed_length = @sqrt(crossed[0] * crossed[0] + crossed[1] * crossed[1] + crossed[2] * crossed[2]);
    const u = [3]f32{ crossed[0] / crossed_length, crossed[1] / crossed_length, crossed[2] / crossed_length };
    const v = cross3(axis, u);
    const base: u32 = @intCast(out.vertices.items.len);
    for (0..2) |ring| {
        const center = if (ring == 0) start else end;
        const radius = if (ring == 0) root_radius else tip_radius;
        for (0..sides) |side| {
            const angle = 2 * std.math.pi * @as(f32, @floatFromInt(side)) / sides;
            const normal = [3]f32{ u[0] * @cos(angle) + v[0] * @sin(angle), u[1] * @cos(angle) + v[1] * @sin(angle), u[2] * @cos(angle) + v[2] * @sin(angle) };
            _ = try vertex(a, out, .{ center[0] + normal[0] * radius, center[1] + normal[1] * radius, center[2] + normal[2] * radius }, normal);
        }
    }
    for (0..sides) |side| {
        const next = (side + 1) % sides;
        try out.addQuad(a, base + @as(u32, @intCast(side)), base + @as(u32, @intCast(next)), base + sides + @as(u32, @intCast(next)), base + sides + @as(u32, @intCast(side)));
    }
}

fn cross3(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
pub fn plant(a: std.mem.Allocator, variant: u8) !Mesh {
    if (variant >= variant_count or isTree(variant)) return error.InvalidPlant;
    var out: GenMesh = .{};
    errdefer out.deinit(a);
    try out.vertices.ensureTotalCapacity(a, if (variant == 1) 100 else if (variant == 7) 1800 else if (variant == 14) 9000 else if (variant >= 8) 600 else 48);
    try out.indices.ensureTotalCapacity(a, if (variant == 1) 180 else if (variant == 7) 7200 else if (variant == 14) 36000 else if (variant >= 8) 2400 else 72);
    if (variant == 0) {
        for (0..9) |i| {
            const t = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 9;
            try blade(a, &out, .{ 0, 0, 0 }, .{ @sin(t) * 0.28, 0.5 + @as(f32, @floatFromInt(i % 4)) * 0.08, @cos(t) * 0.28 }, 0.09, t);
        }
    } else if (variant == 1) {
        for (0..6) |i| {
            const t = @as(f32, @floatFromInt(i)) * std.math.pi / 3;
            const y = 0.52 + @as(f32, @floatFromInt(i % 3)) * 0.07;
            try blade(a, &out, .{ 0, 0, 0 }, .{ @cos(t) * 0.04, y, @sin(t) * 0.04 }, 0.028, t);
            for (0..4) |j| {
                const h = 0.16 + @as(f32, @floatFromInt(j)) * 0.12;
                const side: f32 = if (j % 2 == 0) 1 else -1;
                try blade(a, &out, .{ @cos(t) * 0.025, h, @sin(t) * 0.025 }, .{ @cos(t) * 0.025 + side * 0.09, h + 0.035, @sin(t) * 0.025 + 0.035 }, 0.045, t);
            }
        }
    } else if (variant == 2) {
        for (0..5) |i| {
            const t = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 5;
            try blade(a, &out, .{ 0, 0, 0 }, .{ @cos(t) * 0.08, 0.62, @sin(t) * 0.08 }, 0.025, t);
            const l = try vertex(a, &out, .{ @cos(t) * 0.08 - 0.08, 0.72, @sin(t) * 0.08 }, .{ 0, 0.4, 1 });
            const m = try vertex(a, &out, .{ @cos(t) * 0.08, 0.76, @sin(t) * 0.08 }, .{ 0, 1, 0 });
            const r = try vertex(a, &out, .{ @cos(t) * 0.08 + 0.08, 0.72, @sin(t) * 0.08 }, .{ 0, 0.4, 1 });
            try out.addTri(a, l, m, r);
        }
    } else if (variant == 7) {
        // Low, rounded native shrub clusters with open gaps so the silhouette reads as foliage.
        const centers = [9][3]f32{
            .{ 0, 0.24, 0 }, .{ 0.25, 0.34, 0.02 }, .{ -0.23, 0.33, 0.08 },
            .{ 0.04, 0.38, 0.25 }, .{ 0.0, 0.43, -0.24 }, .{ 0.35, 0.22, -0.18 },
            .{ -0.34, 0.24, -0.16 }, .{ 0.31, 0.2, 0.23 }, .{ -0.28, 0.2, 0.27 },
        };
        for (centers, 0..) |center, i| {
            const size = 0.16 + Seed.unit(Seed.mix(i + 7)) * 0.055;
            try ellipsoid(a, &out, center, .{ size, size * 0.72, size }, 5, 8);
        }
    } else if (variant == 14) {
        // A modest, irregularly layered pine: a visible bole, whorled branches, and open air
        // between needle sprays keep it readable at woodland scale instead of a solid cone.
        try cone(a, &out, 0, 1, 0.045);
        for (0..7) |tier| {
            const tf: f32 = @floatFromInt(tier);
            const y = 0.24 + tf * 0.095;
            const reach = 0.34 * (1 - tf * 0.105);
            const boughs: usize = if (tier < 3) 7 else 6;
            for (0..boughs) |bough| {
                const angle = 2 * std.math.pi * (@as(f32, @floatFromInt(bough)) + @as(f32, @floatFromInt(tier % 2)) * 0.45) / @as(f32, @floatFromInt(boughs));
                const root: [3]f32 = .{ @cos(angle) * 0.035, y, @sin(angle) * 0.035 };
                const elbow: [3]f32 = .{ @cos(angle) * reach * 0.68, y + 0.025, @sin(angle) * reach * 0.68 };
                const tip: [3]f32 = .{ @cos(angle) * reach, y - 0.105, @sin(angle) * reach };
                try twig(a, &out, root, elbow, 0.020 * (1 - tf * 0.045), 0.012);
                try twig(a, &out, elbow, tip, 0.012, 0.003);
                for (0..2) |spray| {
                    const f = 0.42 + @as(f32, @floatFromInt(spray)) * 0.28;
                    const side = if (spray % 2 == 0) @as(f32, 1) else -1;
                    const start = [3]f32{ elbow[0] * (1 - f), elbow[1] - f * 0.12, elbow[2] * (1 - f) };
                    const spray_tip = [3]f32{ start[0] + @cos(angle + side * 0.85) * 0.10, start[1] + 0.055, start[2] + @sin(angle + side * 0.85) * 0.10 };
                    try twig(a, &out, start, spray_tip, 0.006, 0.002);
                    try ellipsoid(a, &out, .{ spray_tip[0] * 1.04, spray_tip[1] + 0.02, spray_tip[2] * 1.04 }, .{ 0.022, 0.03, 0.022 }, 5, 8);
                }
            }
        }
    } else {
        // Flowering natives have a thin stem and a distinct six-petal luminous crown.
        try blade(a, &out, .{ 0, 0, 0 }, .{ 0, 0.62, 0 }, 0.035, 0);
        for (0..6) |i| {
            const angle = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 6;
            const center = [3]f32{ @cos(angle) * 0.105, 0.68 + 0.025 * @sin(angle * 2), @sin(angle) * 0.105 };
            try ellipsoid(a, &out, center, .{ 0.075, 0.045, 0.12 }, 5, 8);
        }
        try ellipsoid(a, &out, .{ 0, 0.69, 0 }, .{ 0.055, 0.06, 0.055 }, 5, 8);
    }
    const mesh = try finish(a, &out);
    out.deinit(a);
    return mesh;
}
/// Scattered leaf cards around `center`, each facing outward, so a crown has a ragged edge and
/// light and wood show between the leaves. Counter-clockwise corners match the outward normal.
fn leafCards(a: std.mem.Allocator, out: *GenMesh, center: [3]f32, radius: f32, count: usize, seed: u64) !void {
    for (0..count) |i| {
        const key = seed *% 1000 +% @as(u64, @intCast(i)) *% 7;
        const angle = Seed.unit(Seed.mix(key)) * 2 * std.math.pi;
        const lift = Seed.unit(Seed.mix(key + 1)) * 2 - 1;
        const band = @sqrt(1 - lift * lift);
        const dir = [3]f32{ @cos(angle) * band, lift, @sin(angle) * band };
        const reach = radius * (0.7 + 0.3 * Seed.unit(Seed.mix(key + 2)));
        const c = [3]f32{ center[0] + dir[0] * reach, center[1] + dir[1] * reach, center[2] + dir[2] * reach };
        // Leaf width follows tree height, while this radius controls only the twig-tip cluster.
        // Tying both to one value made sparse leaves scatter several metres apart on giant trees.
        const size = 0.0046 + 0.0014 * Seed.unit(Seed.mix(key + 3));
        const reference: [3]f32 = if (@abs(dir[1]) < 0.9) .{ 0, 1, 0 } else .{ 1, 0, 0 };
        const cu = cross3(dir, reference);
        const cu_length = @sqrt(cu[0] * cu[0] + cu[1] * cu[1] + cu[2] * cu[2]);
        const u = [3]f32{ cu[0] / cu_length * size, cu[1] / cu_length * size, cu[2] / cu_length * size };
        const v = [3]f32{ (dir[1] * u[2] - dir[2] * u[1]) * 0.6, (dir[2] * u[0] - dir[0] * u[2]) * 0.6, (dir[0] * u[1] - dir[1] * u[0]) * 0.6 };
        // Each leaf is a six-point fan with a rounded outline, not a square card.
        const hub = try vertex(a, out, c, dir);
        var ring: [6]u32 = undefined;
        for (&ring, 0..) |*index, k| {
            const t = 2 * std.math.pi * @as(f32, @floatFromInt(k)) / 6;
            const cs = @cos(t);
            const sn = @sin(t);
            index.* = try vertex(a, out, .{ c[0] + u[0] * cs + v[0] * sn, c[1] + u[1] * cs + v[1] * sn, c[2] + u[2] * cs + v[2] * sn }, dir);
        }
        for (0..6) |k| try out.addTri(a, hub, ring[k], ring[(k + 1) % 6]);
    }
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
/// Stem width at height `t` (0 at the ground, 1 at the crown): a root flare that sinks into the
/// soil, then a steady taper, so the bole reads as wood rather than a spike.
fn boleRadius(radius: f32, t: f32) f32 {
    return radius * (1 - 0.85 * t) + radius * 0.6 * @exp(-t * 14);
}

/// A tapered, flared bole from the ground to unit height. Rings share one profile, so bark
/// grain runs up the stem along its height.
fn bole(a: std.mem.Allocator, out: *GenMesh, radius: f32, sides: usize, rings: usize) !void {
    const base: u32 = @intCast(out.vertices.items.len);
    for (0..rings + 1) |r| {
        const t = @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings));
        const profile = boleRadius(radius, t);
        for (0..sides) |s| {
            const angle = 2 * std.math.pi * @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(sides));
            const n: [3]f32 = .{ @cos(angle), 0, @sin(angle) };
            _ = try vertex(a, out, .{ n[0] * profile, t, n[2] * profile }, n);
        }
    }
    for (0..rings) |r| for (0..sides) |s| {
        const next = (s + 1) % sides;
        const r0 = base + @as(u32, @intCast(r * sides));
        const r1 = r0 + @as(u32, @intCast(sides));
        try out.addQuad(a, r0 + @as(u32, @intCast(s)), r0 + @as(u32, @intCast(next)), r1 + @as(u32, @intCast(next)), r1 + @as(u32, @intCast(s)));
    };
}

fn cone(a: std.mem.Allocator, out: *GenMesh, base: f32, height: f32, radius: f32) !void {
    const start: u32 = @intCast(out.vertices.items.len);
    const sides = 24;
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
    if (species >= tree_count) return error.InvalidTree;
    var out: GenMesh = .{};
    errdefer out.deinit(a);
    const skeleton = try LSystem.generate(a, species);
    defer skeleton.deinit(a);
    for (skeleton.leaves, 0..) |tip, i| {
        try leafCards(a, &out, tip.position, LSystem.grammars[species].leaf_radius, LSystem.grammars[species].leaves_per_tip, @as(u64, species) * 0x10000 + @as(u64, @intCast(i)));
    }
    for (out.vertices.items) |*v| v.uv = .init(-10 - @as(f32, @floatFromInt(species)), 0);
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

pub fn trunk(a: std.mem.Allocator, species: u8) !Mesh {
    if (species >= tree_count) return error.InvalidTree;
    var out: GenMesh = .{};
    errdefer out.deinit(a);
    try out.vertices.ensureTotalCapacity(a, 8192);
    try out.indices.ensureTotalCapacity(a, 16384);
    const radius = ([_]f32{ 0.035, 0.05, 0.04, 0.058, 0.046, 0.055, 0.043, 0.052 })[species];
    try bole(a, &out, radius, 8, 6);
    const skeleton = try LSystem.generate(a, species);
    defer skeleton.deinit(a);
    for (skeleton.branches) |branch| try twig(a, &out, branch.start, branch.end, branch.root_radius, branch.tip_radius);
    for (out.vertices.items) |*v| v.uv = .init(-20 - @as(f32, @floatFromInt(species)), v.pos.y);
    const mesh = try finish(a, &out);
    const bark = trunk_colors[species];
    for (mesh.vertices) |*v| v.color = .{ bark[0], bark[1], bark[2] };
    out.deinit(a);
    return mesh;
}

/// A young broadleaf tree for salvage sites: crown and trunk in one mesh so it can use the
/// solid-object pipeline. Its unit height is scaled to a 20–60 ft tree by the scatterer.
pub fn sapling(a: std.mem.Allocator) !Mesh {
    var crown = try tree(a, 0);
    defer crown.deinit(a);
    var stem = try trunk(a, 0);
    defer stem.deinit(a);

    const vertices = try a.alloc(Mesh.Vertex, crown.vertices.len + stem.vertices.len);
    errdefer a.free(vertices);
    const indices = try a.alloc(u32, crown.indices.len + stem.indices.len);
    errdefer a.free(indices);
    for (crown.vertices, 0..) |source, i| {
        vertices[i] = source;
        vertices[i].color = .{ 0.34, 0.68, 0.29 };
    }
    for (stem.vertices, 0..) |source, i| {
        vertices[crown.vertices.len + i] = source;
        vertices[crown.vertices.len + i].color = .{ 0.34, 0.20, 0.11 };
    }
    @memcpy(indices[0..crown.indices.len], crown.indices);
    for (stem.indices, 0..) |index, i| indices[crown.indices.len + i] = @intCast(crown.vertices.len + index);
    return .{ .vertices = vertices, .indices = indices };
}

test "ground flora and canopy species have distinct geometry" {
    const a = std.testing.allocator;
    var flora: [3]Mesh = undefined;
    for (&flora, 0..) |*m, i| m.* = try plant(a, @intCast(i));
    defer for (flora) |m| m.deinit(a);
    try std.testing.expect(flora[0].vertices.len != flora[1].vertices.len);
    var trees: [tree_count]Mesh = undefined;
    for (&trees, 0..) |*m, i| m.* = try tree(a, @intCast(i));
    defer for (trees) |m| m.deinit(a);
    try std.testing.expect(trees[0].vertices.len != trees[1].vertices.len and trees[1].vertices.len != trees[2].vertices.len and trees[2].vertices.len != trees[3].vertices.len);
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

test "tree meshes are finite, bounded and index in range" {
    const a = std.testing.allocator;
    for (0..tree_count) |species| {
        const m = try tree(a, @intCast(species));
        defer m.deinit(a);
        for (m.vertices) |v| {
            for (v.position ++ v.normal) |f| try std.testing.expect(std.math.isFinite(f));
            for (v.position) |f| try std.testing.expect(@abs(f) < 3);
        }
        for (m.indices) |i| try std.testing.expect(i < m.vertices.len);
        try std.testing.expect(m.indices.len % 3 == 0);
    }
}
