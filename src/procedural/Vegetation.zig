//! Compact generated meshes for ground flora and distinct canopy silhouettes.
const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const GenMesh = @import("../character/mesh.zig").Mesh;
const Seed = @import("Seed.zig");
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
pub fn plant(a: std.mem.Allocator, variant: u8) !Mesh {
    if (variant >= variant_count or isTree(variant)) return error.InvalidPlant;
    var out: GenMesh = .{};
    errdefer out.deinit(a);
    try out.vertices.ensureTotalCapacity(a, if (variant == 1) 100 else if (variant == 7) 1800 else if (variant == 14) 900 else if (variant >= 8) 600 else 48);
    try out.indices.ensureTotalCapacity(a, if (variant == 1) 180 else if (variant == 7) 7200 else if (variant == 14) 2100 else if (variant >= 8) 2400 else 72);
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
                const width = 0.11 * (1 - tf * 0.045);
                try blade(a, &out, root, elbow, width, angle);
                try blade(a, &out, elbow, tip, width * 0.64, angle);
                for (0..3) |spray| {
                    const f = @as(f32, @floatFromInt(spray + 1)) * 0.23;
                    const side = if (spray % 2 == 0) @as(f32, 1) else -1;
                    const start = [3]f32{ elbow[0] * (1 - f), elbow[1] - f * 0.12, elbow[2] * (1 - f) };
                    const end = [3]f32{ start[0] + @cos(angle + side * 0.85) * 0.16, start[1] + 0.12, start[2] + @sin(angle + side * 0.85) * 0.16 };
                    try blade(a, &out, start, end, 0.055, angle + side * 0.6);
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
    try out.vertices.ensureTotalCapacity(a, 16000);
    try out.indices.ensureTotalCapacity(a, 100000);
    switch (species) {
        0 => {
            try ellipsoid(a, &out, .{ 0, 0.68, 0 }, .{ 0.36, 0.31, 0.36 }, 12, 20);
            try ellipsoid(a, &out, .{ 0.23, 0.72, 0.02 }, .{ 0.24, 0.22, 0.25 }, 12, 20);
            try ellipsoid(a, &out, .{ -0.23, 0.68, -0.04 }, .{ 0.24, 0.22, 0.24 }, 12, 20);
        },
        1 => {
            try cone(a, &out, 0.28, 0.7, 0.38);
            try cone(a, &out, 0.08, 0.66, 0.29);
            try cone(a, &out, 0, 0.55, 0.2);
        },
        2 => {
            try ellipsoid(a, &out, .{ 0, 0.77, 0 }, .{ 0.31, 0.18, 0.31 }, 12, 20);
            for (0..7) |i| {
                const t = 2 * std.math.pi * @as(f32, @floatFromInt(i)) / 7;
                const x = @cos(t) * 0.34;
                const z = @sin(t) * 0.34;
                try ellipsoid(a, &out, .{ x, 0.43, z }, .{ 0.09, 0.27, 0.09 }, 10, 16);
                try ellipsoid(a, &out, .{ x * 1.18, 0.20, z * 1.18 }, .{ 0.07, 0.18, 0.07 }, 10, 16);
            }
        },
        3 => {
            // A narrow crown above a long bare bole, built in irregular whorls like a redwood.
            for (0..6) |tier| {
                const y = 0.34 + @as(f32, @floatFromInt(tier)) * 0.105;
                const spread = 0.21 * (1 - @as(f32, @floatFromInt(tier)) * 0.12);
                const limbs: usize = if (tier < 2) 9 else 7;
                for (0..limbs) |j| {
                    const angle = 2 * std.math.pi * (@as(f32, @floatFromInt(j)) + @as(f32, @floatFromInt(tier % 2)) * 0.42) / @as(f32, @floatFromInt(limbs));
                    const wobble = 0.84 + Seed.unit(Seed.mix(tier * 17 + j)) * 0.28;
                    const center = .{ @cos(angle) * spread * wobble, y + 0.012 * @sin(angle * 3), @sin(angle) * spread * wobble };
                    const radius = 0.05 + spread * 0.4;
                    try ellipsoid(a, &out, center, .{ radius, radius * 0.62, radius * 0.78 }, 10, 16);
                }
            }
            // Close the whorls into the tall, continuous crown of a mature redwood.
            try ellipsoid(a, &out, .{ 0, 0.68, 0 }, .{ 0.12, 0.31, 0.12 }, 12, 20);
            try ellipsoid(a, &out, .{ 0, 0.91, 0 }, .{ 0.055, 0.13, 0.055 }, 10, 16);
        },
        4 => {
            // A copper fan crown: broad, overlapping leaves sit on distinct rising whorls.
            for (0..5) |tier| {
                const tf: f32 = @floatFromInt(tier);
                const y = 0.40 + tf * 0.105;
                const spread = 0.36 - tf * 0.045;
                for (0..7) |j| {
                    const angle = 2 * std.math.pi * (@as(f32, @floatFromInt(j)) + tf * 0.31) / 7;
                    const wobble = 0.90 + 0.12 * @sin(angle * 3 + tf);
                    const center = .{ @cos(angle) * spread * wobble, y + 0.04 * @sin(angle * 2), @sin(angle) * spread * wobble };
                    try ellipsoid(a, &out, center, .{ 0.19 - tf * 0.012, 0.075, 0.13 - tf * 0.008 }, 12, 20);
                }
            }
            try ellipsoid(a, &out, .{ 0, 0.78, 0 }, .{ 0.13, 0.29, 0.13 }, 12, 20);
        },
        5 => {
            // Moon cascade: a soft central crown with tiered hanging branch sprays.
            try ellipsoid(a, &out, .{ 0, 0.78, 0 }, .{ 0.38, 0.25, 0.36 }, 14, 24);
            for (0..9) |branch| {
                const angle = 2 * std.math.pi * @as(f32, @floatFromInt(branch)) / 9;
                const reach = 0.38 + 0.05 * @sin(angle * 2);
                for (0..4) |leaf| {
                    const t = @as(f32, @floatFromInt(leaf)) / 3;
                    const y = 0.68 - t * (0.42 + 0.05 * @sin(angle * 3));
                    const x = @cos(angle) * reach * t;
                    const z = @sin(angle) * reach * t;
                    const radius = 0.12 - t * 0.035;
                    try ellipsoid(a, &out, .{ x, y, z }, .{ radius, radius * 0.82, radius }, 12, 20);
                }
            }
        },
        6 => {
            // Star blossom: layered, open crowns of luminous petal clusters leave sky between them.
            for (0..4) |tier| {
                const tf: f32 = @floatFromInt(tier);
                const y = 0.47 + tf * 0.13;
                const spread = 0.33 - tf * 0.055;
                for (0..6) |j| {
                    const angle = 2 * std.math.pi * (@as(f32, @floatFromInt(j)) + tf * 0.5) / 6;
                    const x = @cos(angle) * spread;
                    const z = @sin(angle) * spread;
                    try ellipsoid(a, &out, .{ x, y, z }, .{ 0.14, 0.095, 0.14 }, 12, 20);
                    try ellipsoid(a, &out, .{ x * 1.2, y + 0.035, z * 1.2 }, .{ 0.075, 0.045, 0.075 }, 10, 16);
                }
            }
            try ellipsoid(a, &out, .{ 0, 0.78, 0 }, .{ 0.12, 0.30, 0.12 }, 12, 20);
        },
        7 => {
            // An old-growth pine with a high leader, descending whorls, and gaps between
            // its branch fans. The foliage shader adds fine needles and natural color breakup.
            for (0..9) |tier| {
                const tf: f32 = @floatFromInt(tier);
                const y = 0.19 + tf * 0.078;
                const reach = 0.68 * (1 - tf * 0.075);
                const boughs: usize = if (tier % 2 == 0) 9 else 8;
                for (0..boughs) |bough| {
                    const angle = 2 * std.math.pi * (@as(f32, @floatFromInt(bough)) + @as(f32, @floatFromInt(tier % 2)) * 0.46) / @as(f32, @floatFromInt(boughs));
                    const jitter = 0.91 + Seed.unit(Seed.mix(tier * 131 + bough)) * 0.18;
                    const root: [3]f32 = .{ @cos(angle) * 0.025, y, @sin(angle) * 0.025 };
                    const elbow: [3]f32 = .{ @cos(angle) * reach * 0.55 * jitter, y + 0.025, @sin(angle) * reach * 0.55 * jitter };
                    const tip: [3]f32 = .{ @cos(angle) * reach * jitter, y - 0.09, @sin(angle) * reach * jitter };
                    try blade(a, &out, root, elbow, 0.045 * (1 - tf * 0.035), angle);
                    try blade(a, &out, elbow, tip, 0.025, angle);
                    for (0..3) |spray| {
                        const t = 0.32 + @as(f32, @floatFromInt(spray)) * 0.22;
                        const side: f32 = if ((spray + tier) % 2 == 0) 1 else -1;
                        const at: [3]f32 = .{ elbow[0] + (tip[0] - elbow[0]) * t, elbow[1] + (tip[1] - elbow[1]) * t, elbow[2] + (tip[2] - elbow[2]) * t };
                        const twig_angle = angle + side * 0.78;
                        const twig: [3]f32 = .{ at[0] + @cos(twig_angle) * 0.15, at[1] + 0.09, at[2] + @sin(twig_angle) * 0.15 };
                        try blade(a, &out, at, twig, 0.018, twig_angle);
                        try ellipsoid(a, &out, .{ twig[0] * 1.08, twig[1] + 0.035, twig[2] * 1.08 }, .{ 0.055, 0.07, 0.055 }, 6, 9);
                    }
                }
            }
            try ellipsoid(a, &out, .{ 0, 0.60, 0 }, .{ 0.095, 0.28, 0.095 }, 10, 16);
            try ellipsoid(a, &out, .{ 0, 0.91, 0 }, .{ 0.035, 0.13, 0.035 }, 8, 12);
        },
        else => unreachable,
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
    try out.vertices.ensureTotalCapacity(a, 96);
    try out.indices.ensureTotalCapacity(a, 192);
    const radius = ([_]f32{ 0.035, 0.05, 0.04, 0.058, 0.046, 0.055, 0.043, 0.052 })[species];
    try cone(a, &out, 0, 1, radius);
    if (species == 3 or species == 7) for (0..9) |i| {
        const angle = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 9;
        const reach: f32 = if (species == 3) 0.22 else 0.17;
        try blade(a, &out, .{ 0, 0.025, 0 }, .{ @cos(angle) * reach, 0.13, @sin(angle) * reach }, 0.065, angle);
    };
    for (out.vertices.items) |*v| v.uv = .init(-20 - @as(f32, @floatFromInt(species)), v.pos.y);
    const mesh = try finish(a, &out);
    out.deinit(a);
    return mesh;
}

/// A young broadleaf tree for salvage sites: crown and trunk in one mesh so it can use the
/// solid-object pipeline. Its unit height is scaled to a 20–60 ft tree by the scatterer.
pub fn sapling(a: std.mem.Allocator) !Mesh {
    var crown = try tree(a, 0);
    defer crown.deinit(a);
    var bole = try trunk(a, 0);
    defer bole.deinit(a);

    const vertices = try a.alloc(Mesh.Vertex, crown.vertices.len + bole.vertices.len);
    errdefer a.free(vertices);
    const indices = try a.alloc(u32, crown.indices.len + bole.indices.len);
    errdefer a.free(indices);
    for (crown.vertices, 0..) |source, i| {
        vertices[i] = source;
        vertices[i].color = .{ 0.34, 0.68, 0.29 };
    }
    for (bole.vertices, 0..) |source, i| {
        vertices[crown.vertices.len + i] = source;
        vertices[crown.vertices.len + i].color = .{ 0.34, 0.20, 0.11 };
    }
    @memcpy(indices[0..crown.indices.len], crown.indices);
    for (bole.indices, 0..) |index, i| indices[crown.indices.len + i] = @intCast(crown.vertices.len + index);
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
