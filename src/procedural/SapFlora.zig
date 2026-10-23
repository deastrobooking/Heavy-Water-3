//! The living-sap flora set (docs/plans/fantasy-flora.md): twelve glowing grasses, flowers, bushes
//! and human-scale trees. Each species is two small meshes in real metres, a *body* (drawn
//! with its day colour) and a *glow* (drawn again with the instance tint alpha above 1, which the
//! scene shader turns into night-bright lumen, as the orbital hulls and the glowing flowers do).
//! Meshes are a pure function of the species, so every instance of one species shares them.
//!
//! The set is standalone: nothing here knows about scatter, biomes or the catalog yet. Heights obey
//! the combat rule of docs/world.md (grasses and flowers stay low, bushes below two metres).
const std = @import("std");
const enum_compat = @import("enum_compat");
const Mesh = @import("../render/Mesh.zig");
const GenMesh = @import("../character/mesh.zig").Mesh;
const Seed = @import("Seed.zig");

pub const Species = enum {
    glowblade,
    silk_reed,
    moonmoss,
    lumen_lily,
    starcup,
    driftpoppy,
    lantern_bush,
    crystal_bloom,
    sapfern,
    glowvine_tree,
    crystal_leaf_tree,
    sapwillow,
};
pub const count = enum_compat.fields(Species).len;
pub const Family = enum { grass, flower, bush, tree };

pub const Info = struct {
    name: []const u8,
    family: Family,
    /// Day colour of the body (instance tints multiply it) and the lumen colour of the glow parts.
    body: [3]f32,
    glow: [3]f32,
    /// Design height and radius in metres; a test keeps the built mesh within them.
    height: f32,
    radius: f32,
    /// Most triangles the body and glow together may use.
    triangles: u32,
};

pub fn info(s: Species) Info {
    return switch (s) {
        .glowblade => .{ .name = "glowblade grass", .family = .grass, .body = .{ 0.30, 0.58, 0.34 }, .glow = .{ 0.45, 1.0, 0.85 }, .height = 0.55, .radius = 0.30, .triangles = 260 },
        .silk_reed => .{ .name = "silk reed", .family = .grass, .body = .{ 0.55, 0.66, 0.42 }, .glow = .{ 0.95, 1.0, 0.75 }, .height = 0.58, .radius = 0.22, .triangles = 260 },
        .moonmoss => .{ .name = "moonmoss tuft", .family = .grass, .body = .{ 0.30, 0.50, 0.40 }, .glow = .{ 0.55, 0.90, 1.0 }, .height = 0.10, .radius = 0.34, .triangles = 700 },
        .lumen_lily => .{ .name = "lumen lily", .family = .flower, .body = .{ 0.88, 0.86, 0.92 }, .glow = .{ 1.0, 0.75, 0.30 }, .height = 0.56, .radius = 0.14, .triangles = 260 },
        .starcup => .{ .name = "starcup", .family = .flower, .body = .{ 0.62, 0.55, 0.88 }, .glow = .{ 0.60, 0.85, 1.0 }, .height = 0.26, .radius = 0.26, .triangles = 520 },
        .driftpoppy => .{ .name = "driftpoppy", .family = .flower, .body = .{ 0.95, 0.42, 0.55 }, .glow = .{ 1.0, 0.55, 0.85 }, .height = 0.50, .radius = 0.18, .triangles = 420 },
        .lantern_bush => .{ .name = "lantern bush", .family = .bush, .body = .{ 0.28, 0.46, 0.30 }, .glow = .{ 1.0, 0.78, 0.35 }, .height = 1.1, .radius = 0.62, .triangles = 1250 },
        .crystal_bloom => .{ .name = "crystal-bloom shrub", .family = .bush, .body = .{ 0.50, 0.58, 0.78 }, .glow = .{ 0.55, 0.95, 1.0 }, .height = 0.8, .radius = 0.55, .triangles = 160 },
        .sapfern => .{ .name = "sapfern thicket", .family = .bush, .body = .{ 0.24, 0.50, 0.32 }, .glow = .{ 0.65, 1.0, 0.55 }, .height = 0.8, .radius = 0.70, .triangles = 1500 },
        .glowvine_tree => .{ .name = "glowvine tree", .family = .tree, .body = .{ 0.36, 0.27, 0.22 }, .glow = .{ 0.55, 1.0, 0.70 }, .height = 7.0, .radius = 2.6, .triangles = 1200 },
        .crystal_leaf_tree => .{ .name = "crystal-leaf tree", .family = .tree, .body = .{ 0.72, 0.82, 0.90 }, .glow = .{ 0.60, 0.90, 1.0 }, .height = 9.0, .radius = 3.0, .triangles = 900 },
        .sapwillow => .{ .name = "sapwillow", .family = .tree, .body = .{ 0.40, 0.30, 0.24 }, .glow = .{ 1.0, 0.72, 0.35 }, .height = 9.2, .radius = 4.2, .triangles = 1500 },
    };
}

/// The two meshes of one species. Both are owned by the caller.
pub const Parts = struct {
    body: Mesh,
    glow: Mesh,

    pub fn deinit(self: Parts, a: std.mem.Allocator) void {
        self.body.deinit(a);
        self.glow.deinit(a);
    }
};

const Vec = [3]f32;

fn add(p: Vec, q: Vec) Vec {
    return .{ p[0] + q[0], p[1] + q[1], p[2] + q[2] };
}
fn sub(p: Vec, q: Vec) Vec {
    return .{ p[0] - q[0], p[1] - q[1], p[2] - q[2] };
}
fn scale(p: Vec, k: f32) Vec {
    return .{ p[0] * k, p[1] * k, p[2] * k };
}
fn lerp3(p: Vec, q: Vec, t: f32) Vec {
    return add(scale(p, 1 - t), scale(q, t));
}
fn dot(p: Vec, q: Vec) f32 {
    return p[0] * q[0] + p[1] * q[1] + p[2] * q[2];
}
fn cross(p: Vec, q: Vec) Vec {
    return .{ p[1] * q[2] - p[2] * q[1], p[2] * q[0] - p[0] * q[2], p[0] * q[1] - p[1] * q[0] };
}
fn normalize(p: Vec) Vec {
    const l = @sqrt(dot(p, p));
    return if (l < 1e-6) .{ 0, 1, 0 } else scale(p, 1 / l);
}

/// A mesh under construction: generation helpers over `GenMesh`.
const Builder = struct {
    a: std.mem.Allocator,
    out: GenMesh = .{},
    /// The colour every vertex added next gets (the mesh's vertex colour; the instance tint multiplies it).
    tone: Vec = .{ 1, 1, 1 },
    tones: std.ArrayList(Vec) = .empty,

    fn deinit(b: *Builder) void {
        b.out.deinit(b.a);
        b.tones.deinit(b.a);
    }

    fn vertex(b: *Builder, p: Vec, n: Vec) !u32 {
        try b.tones.append(b.a, b.tone);
        return b.out.addVertex(b.a, .{ .pos = .init(p[0], p[1], p[2]), .normal = .init(n[0], n[1], n[2]) });
    }

    fn tri(b: *Builder, x: u32, y: u32, z: u32) !void {
        try b.out.addTri(b.a, x, y, z);
    }

    /// A two-sided ribbon along `path` (at least two points) that narrows to a point, facing
    /// `facing` (the direction its flat side looks), `width` wide at the root.
    fn ribbon(b: *Builder, path: []const Vec, width: f32, facing: Vec) !void {
        const n = normalize(facing);
        var prev_l: u32 = 0;
        var prev_r: u32 = 0;
        for (path, 0..) |p, i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(path.len - 1));
            const next = if (i + 1 < path.len) path[i + 1] else p;
            const before = if (i > 0) path[i - 1] else p;
            const along = normalize(sub(next, before));
            const side = normalize(cross(along, n));
            const half = width * 0.5 * (1 - t);
            if (i + 1 == path.len) {
                const tip = try b.vertex(p, n);
                try b.tri(prev_l, tip, prev_r);
                try b.tri(prev_l, prev_r, tip);
            } else {
                const l = try b.vertex(sub(p, scale(side, half)), n);
                const r = try b.vertex(add(p, scale(side, half)), n);
                if (i > 0) {
                    try b.tri(prev_l, l, r);
                    try b.tri(prev_l, r, prev_r);
                    try b.tri(prev_l, r, l);
                    try b.tri(prev_l, prev_r, r);
                }
                prev_l = l;
                prev_r = r;
            }
        }
    }

    /// A single curved blade from `root` to `tip` bowed by `bend` along `lean`.
    fn blade(b: *Builder, root: Vec, tip: Vec, width: f32, bend: Vec, angle: f32) !void {
        const mid = add(lerp3(root, tip, 0.5), bend);
        const high = add(lerp3(root, tip, 0.8), scale(bend, 0.7));
        const facing: Vec = .{ -@sin(angle), 0.2, @cos(angle) };
        try b.ribbon(&.{ root, mid, high, tip }, width, facing);
    }

    /// A round swept stem of `sides` faces tapering from `r0` to `r1`; a flat cap closes the tip.
    fn tube(b: *Builder, start: Vec, end: Vec, r0: f32, r1: f32, sides: usize) !void {
        const axis = normalize(sub(end, start));
        const helper: Vec = if (@abs(axis[1]) < 0.9) .{ 0, 1, 0 } else .{ 1, 0, 0 };
        const u = normalize(cross(axis, helper));
        const w = cross(axis, u);
        const first: u32 = @intCast(b.out.vertices.items.len);
        for (0..sides) |i| {
            const ang = 2 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sides));
            const dir = add(scale(u, @cos(ang)), scale(w, @sin(ang)));
            _ = try b.vertex(add(start, scale(dir, r0)), dir);
            _ = try b.vertex(add(end, scale(dir, r1)), dir);
        }
        for (0..sides) |i| {
            const j = (i + 1) % sides;
            const a0 = first + @as(u32, @intCast(i * 2));
            const a1 = a0 + 1;
            const b0 = first + @as(u32, @intCast(j * 2));
            const b1 = b0 + 1;
            try b.out.addQuad(b.a, a0, b0, b1, a1);
        }
        const cap = try b.vertex(end, axis);
        for (0..sides) |i| {
            const j = (i + 1) % sides;
            try b.tri(first + @as(u32, @intCast(i * 2 + 1)), first + @as(u32, @intCast(j * 2 + 1)), cap);
        }
    }

    /// A UV-sphere squashed to `radius`, with `rows` rings of `cols` columns.
    fn ellipsoid(b: *Builder, center: Vec, radius: Vec, rows: usize, cols: usize) !void {
        const start: u32 = @intCast(b.out.vertices.items.len);
        for (0..rows + 1) |r| for (0..cols) |c| {
            const lat = std.math.pi * @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rows));
            const lon = 2 * std.math.pi * @as(f32, @floatFromInt(c)) / @as(f32, @floatFromInt(cols));
            const n: Vec = .{ @sin(lat) * @cos(lon), @cos(lat), @sin(lat) * @sin(lon) };
            _ = try b.vertex(.{ center[0] + n[0] * radius[0], center[1] + n[1] * radius[1], center[2] + n[2] * radius[2] }, normalize(.{ n[0] / radius[0], n[1] / radius[1], n[2] / radius[2] }));
        };
        for (0..rows) |r| for (0..cols) |c| {
            const x: u32 = start + @as(u32, @intCast(r * cols + c));
            const y = start + @as(u32, @intCast(r * cols + (c + 1) % cols));
            try b.out.addQuad(b.a, x, y, y + @as(u32, @intCast(cols)), x + @as(u32, @intCast(cols)));
        };
    }

    /// A four-sided crystal: a square base at `base` and a point `height` above it along `up`.
    fn crystal(b: *Builder, base: Vec, up: Vec, radius: f32, height: f32) !void {
        const axis = normalize(up);
        const helper: Vec = if (@abs(axis[1]) < 0.9) .{ 0, 1, 0 } else .{ 1, 0, 0 };
        const u = normalize(cross(axis, helper));
        const w = cross(axis, u);
        const tip = add(base, scale(axis, height));
        var corners: [4]Vec = undefined;
        for (&corners, 0..) |*c, i| {
            const ang = std.math.pi / 2.0 * @as(f32, @floatFromInt(i)) + std.math.pi / 4.0;
            c.* = add(base, add(scale(u, @cos(ang) * radius), scale(w, @sin(ang) * radius)));
        }
        for (0..4) |i| {
            const p = corners[i];
            const q = corners[(i + 1) % 4];
            const n = normalize(cross(sub(q, p), sub(tip, p)));
            const x = try b.vertex(p, n);
            const y = try b.vertex(q, n);
            const z = try b.vertex(tip, n);
            try b.tri(x, y, z);
        }
    }

    /// A flat diamond plate (a crystal leaf) centred on `center`, turned so its face looks along `facing`.
    fn plate(b: *Builder, center: Vec, facing: Vec, long: f32, wide: f32, spin: f32) !void {
        const n = normalize(facing);
        const helper: Vec = if (@abs(n[1]) < 0.9) .{ 0, 1, 0 } else .{ 1, 0, 0 };
        var u = normalize(cross(n, helper));
        var w = cross(n, u);
        const ru = add(scale(u, @cos(spin)), scale(w, @sin(spin)));
        w = add(scale(w, @cos(spin)), scale(u, -@sin(spin)));
        u = ru;
        const top = try b.vertex(add(center, scale(u, long)), n);
        const right = try b.vertex(add(center, scale(w, wide)), n);
        const bottom = try b.vertex(sub(center, scale(u, long)), n);
        const left = try b.vertex(sub(center, scale(w, wide)), n);
        try b.out.addQuad(b.a, top, right, bottom, left);
        // The back face, so a plate seen edge-on or from behind still reads.
        const back = scale(n, -1);
        // Set a hair behind the front so the two faces never fight over the same pixels.
        const behind = scale(n, -0.012);
        const t2 = try b.vertex(add(add(center, behind), scale(u, long)), back);
        const r2 = try b.vertex(add(add(center, behind), scale(w, wide)), back);
        const b2 = try b.vertex(sub(add(center, behind), scale(u, long)), back);
        const l2 = try b.vertex(sub(add(center, behind), scale(w, wide)), back);
        try b.out.addQuad(b.a, t2, l2, b2, r2);
    }

    fn finish(b: *Builder) !Mesh {
        const a = b.a;
        const vertices = try a.alloc(Mesh.Vertex, b.out.vertices.items.len);
        errdefer a.free(vertices);
        for (vertices, b.out.vertices.items, b.tones.items) |*v, s, tone| v.* = .{ .position = .{ s.pos.x, s.pos.y, s.pos.z }, .normal = .{ s.normal.x, s.normal.y, s.normal.z }, .uv = .{ 0, 0 }, .color = tone };
        const indices = try a.dupe(u32, b.out.indices.items);
        return .{ .vertices = vertices, .indices = indices };
    }
};

fn unit(species: Species, i: usize, salt: u64) f32 {
    return Seed.unit(Seed.mix(@as(u64, @intFromEnum(species)) * 0x9E3779B1 + i * 977 + salt));
}

fn around(i: usize, n: usize) f32 {
    return 2 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
}

fn ring(radius: f32, angle: f32, y: f32) Vec {
    return .{ @cos(angle) * radius, y, @sin(angle) * radius };
}

/// Builds both meshes of a species. The same species always gives the same meshes.
pub fn build(a: std.mem.Allocator, s: Species) !Parts {
    var body: Builder = .{ .a = a };
    errdefer body.deinit();
    var glow: Builder = .{ .a = a };
    errdefer glow.deinit();
    body.tone = info(s).body;
    glow.tone = info(s).glow;
    switch (s) {
        .glowblade => try glowblade(&body, &glow),
        .silk_reed => try silkReed(&body, &glow),
        .moonmoss => try moonmoss(&body, &glow),
        .lumen_lily => try lumenLily(&body, &glow),
        .starcup => try starcup(&body, &glow),
        .driftpoppy => try driftpoppy(&body, &glow),
        .lantern_bush => try lanternBush(&body, &glow),
        .crystal_bloom => try crystalBloom(&body, &glow),
        .sapfern => try sapfern(&body, &glow),
        .glowvine_tree => try glowvineTree(&body, &glow),
        .crystal_leaf_tree => try crystalLeafTree(&body, &glow),
        .sapwillow => try sapwillow(&body, &glow),
    }
    const body_mesh = try body.finish();
    errdefer body_mesh.deinit(a);
    const glow_mesh = try glow.finish();
    body.deinit();
    glow.deinit();
    return .{ .body = body_mesh, .glow = glow_mesh };
}

// ---------------------------------------------------------------- grasses

fn glowblade(body: *Builder, glow: *Builder) !void {
    const blades = 12;
    for (0..blades) |i| {
        const ang = around(i, blades) + unit(.glowblade, i, 1) * 0.3;
        const h = 0.38 + unit(.glowblade, i, 2) * 0.17;
        const reach = 0.12 + unit(.glowblade, i, 3) * 0.17;
        const root: Vec = ring(0.02, ang, 0);
        const tip: Vec = ring(reach, ang, h);
        const bend: Vec = .{ @cos(ang) * 0.05, 0.02, @sin(ang) * 0.05 };
        try body.blade(root, tip, 0.07, bend, ang);
        // The glowing tip: the top fifth of the same blade, a little wider so it sits proud.
        const from = add(lerp3(root, tip, 0.8), scale(bend, 0.7));
        try glow.blade(from, tip, 0.06, scale(bend, 0.1), ang);
    }
}

fn silkReed(body: *Builder, glow: *Builder) !void {
    for (0..7) |i| {
        const ang = around(i, 7) + unit(.silk_reed, i, 1) * 0.4;
        const h = 0.42 + unit(.silk_reed, i, 2) * 0.12;
        const root: Vec = ring(0.025, ang, 0);
        const tip: Vec = ring(0.04 + unit(.silk_reed, i, 3) * 0.12, ang, h);
        try body.blade(root, tip, 0.03, .{ @cos(ang) * 0.03, 0, @sin(ang) * 0.03 }, ang);
        // A soft seed-head on every other stem.
        if (i % 2 == 0) try glow.ellipsoid(add(tip, .{ 0, 0.02, 0 }), .{ 0.02, 0.05, 0.02 }, 3, 5);
    }
}

fn moonmoss(body: *Builder, glow: *Builder) !void {
    const cushions = 10;
    for (0..cushions) |i| {
        const ang = around(i, cushions) * 2.4 + unit(.moonmoss, i, 1);
        const r = if (i == 0) 0.0 else 0.08 + unit(.moonmoss, i, 2) * 0.22;
        const size = 0.06 + unit(.moonmoss, i, 3) * 0.05;
        const c: Vec = ring(r, ang, 0.012);
        try body.ellipsoid(c, .{ size, size * 0.62, size }, 3, 8);
        // A pale dot of glow on the crown of most cushions.
        if (i % 3 != 2) try glow.ellipsoid(add(c, .{ 0.0, size * 0.56, 0.0 }), .{ size * 0.3, size * 0.12, size * 0.3 }, 2, 6);
    }
}

// ---------------------------------------------------------------- flowers

fn lumenLily(body: *Builder, glow: *Builder) !void {
    const petal = body.tone;
    const stem_top: Vec = .{ 0.02, 0.44, 0 };
    body.tone = .{ 0.30, 0.55, 0.32 };
    try body.blade(.{ 0, 0, 0 }, stem_top, 0.03, .{ 0.02, 0, 0 }, 0);
    // Two long leaves low on the stem.
    for (0..2) |i| {
        const ang = around(i, 2) + 0.7;
        try body.blade(.{ 0, 0.02, 0 }, ring(0.16, ang, 0.22), 0.05, .{ 0, 0.03, 0 }, ang);
    }
    // A bell of six wide petals flaring out and up from the stem top.
    body.tone = petal;
    for (0..6) |i| {
        const ang = around(i, 6);
        const base = add(stem_top, ring(0.012, ang, 0));
        const mid = add(stem_top, ring(0.065, ang, 0.075));
        const tip = add(stem_top, ring(0.12, ang, 0.125));
        try body.ribbon(&.{ base, mid, tip }, 0.11, .{ @cos(ang), 0.3, @sin(ang) });
    }
    // The lit throat and three stamen tips.
    try glow.ellipsoid(add(stem_top, .{ 0, 0.05, 0 }), .{ 0.03, 0.045, 0.03 }, 3, 6);
    for (0..3) |i| try glow.ellipsoid(add(stem_top, ring(0.035, around(i, 3), 0.10)), .{ 0.012, 0.012, 0.012 }, 2, 4);
}

fn starcup(body: *Builder, glow: *Builder) !void {
    const petal = body.tone;
    const cups = 7;
    for (0..cups) |i| {
        const ang = around(i, cups) + unit(.starcup, i, 1) * 0.5;
        const r = if (i == 0) 0.0 else 0.10 + unit(.starcup, i, 2) * 0.13;
        const h = 0.13 + unit(.starcup, i, 3) * 0.10;
        const foot: Vec = ring(r, ang, 0);
        const head = add(foot, .{ 0, h, 0 });
        body.tone = .{ 0.30, 0.52, 0.34 };
        try body.blade(foot, head, 0.018, .{ 0, 0, 0 }, ang);
        body.tone = petal;
        for (0..5) |p| {
            const pa = around(p, 5) + ang;
            try body.ribbon(&.{ add(head, ring(0.01, pa, 0)), add(head, ring(0.035, pa, 0.025)), add(head, ring(0.05, pa, 0.045)) }, 0.04, .{ @cos(pa), 0.4, @sin(pa) });
        }
        try glow.ellipsoid(add(head, .{ 0, 0.012, 0 }), .{ 0.022, 0.014, 0.022 }, 2, 6);
    }
}

fn driftpoppy(body: *Builder, glow: *Builder) !void {
    const petal = body.tone;
    const top: Vec = .{ 0.03, 0.36, 0.01 };
    body.tone = .{ 0.30, 0.52, 0.30 };
    try body.blade(.{ 0, 0, 0 }, top, 0.028, .{ 0.03, 0, 0 }, 0.5);
    // Five broad petals that cup upward around a dark heart.
    body.tone = petal;
    for (0..5) |i| {
        const ang = around(i, 5) + 0.3;
        try body.ribbon(&.{ add(top, ring(0.01, ang, 0)), add(top, ring(0.07, ang, 0.035)), add(top, ring(0.115, ang, 0.095)) }, 0.15, .{ @cos(ang), 0.5, @sin(ang) });
    }
    body.tone = .{ 0.22, 0.12, 0.30 };
    try body.ellipsoid(add(top, .{ 0, 0.025, 0 }), .{ 0.03, 0.025, 0.03 }, 3, 6);
    // Motes of glow that drift above the flower.
    for (0..4) |i| {
        const h = 0.07 + @as(f32, @floatFromInt(i)) * 0.03;
        try glow.ellipsoid(add(top, ring(0.04 + unit(.driftpoppy, i, 1) * 0.07, around(i, 4) * 1.7, h)), .{ 0.014, 0.014, 0.014 }, 2, 5);
    }
}

// ---------------------------------------------------------------- bushes

fn lanternBush(body: *Builder, glow: *Builder) !void {
    // A woody frame of arching stems, leafy clumps along it, and glowing pods hung from drooping twigs.
    const leaf = body.tone;
    const stems = 6;
    for (0..stems) |i| {
        const ang = around(i, stems) + unit(.lantern_bush, i, 1) * 0.4;
        const out_r = 0.38 + unit(.lantern_bush, i, 2) * 0.16;
        const top_h = 0.82 + unit(.lantern_bush, i, 3) * 0.22;
        const start: Vec = ring(0.04, ang, 0);
        const end: Vec = ring(out_r, ang, top_h);
        body.tone = .{ 0.34, 0.26, 0.20 };
        try body.tube(start, end, 0.028, 0.012, 5);
        body.tone = leaf;
        try body.ellipsoid(add(end, .{ 0, -0.04, 0 }), .{ 0.22, 0.15, 0.22 }, 4, 7);
        // Two drooping twigs, each ending in a pod.
        for (0..2) |k| {
            const pa = ang + (@as(f32, @floatFromInt(k)) - 0.5) * 0.9;
            const from = lerp3(start, end, 0.65 + 0.15 * @as(f32, @floatFromInt(k)));
            const hang = add(from, ring(0.10, pa, -0.16));
            body.tone = .{ 0.34, 0.26, 0.20 };
            try body.tube(from, hang, 0.008, 0.004, 4);
            try glow.ellipsoid(add(hang, .{ 0, -0.05, 0 }), .{ 0.055, 0.075, 0.055 }, 4, 6);
        }
    }
}

fn crystalBloom(body: *Builder, glow: *Builder) !void {
    // A low mound of dark crystals ringed by tall, lit ones.
    body.tone = .{ 0.34, 0.38, 0.62 };
    for (0..6) |i| {
        const ang = around(i, 6) + unit(.crystal_bloom, i, 1) * 0.3;
        const base = ring(0.12, ang, 0);
        try body.crystal(base, .{ @cos(ang) * 0.35, 1, @sin(ang) * 0.35 }, 0.075, 0.38 + unit(.crystal_bloom, i, 2) * 0.12);
    }
    for (0..9) |i| {
        const ang = around(i, 9) + unit(.crystal_bloom, i, 3) * 0.3;
        const r = 0.22 + unit(.crystal_bloom, i, 4) * 0.16;
        const tall = 0.45 + unit(.crystal_bloom, i, 5) * 0.4;
        const lean = 0.30 + unit(.crystal_bloom, i, 6) * 0.25;
        try glow.crystal(ring(r * 0.6, ang, 0), .{ @cos(ang) * lean, 1, @sin(ang) * lean }, 0.05 + unit(.crystal_bloom, i, 7) * 0.03, tall);
    }
}

fn sapfern(body: *Builder, glow: *Builder) !void {
    const fronds = 9;
    for (0..fronds) |i| {
        const ang = around(i, fronds) + unit(.sapfern, i, 1) * 0.3;
        const reach = 0.45 + unit(.sapfern, i, 2) * 0.22;
        const h = 0.55 + unit(.sapfern, i, 3) * 0.2;
        const path = [_]Vec{ ring(0.02, ang, 0), ring(reach * 0.45, ang, h * 0.85), ring(reach * 0.85, ang, h), ring(reach, ang, h * 0.78) };
        try body.ribbon(&path, 0.17, .{ 0, 1, 0 });
        // Leaflets pair off the frond.
        for (1..4) |k| {
            const p = lerp3(path[k - 1], path[k], 0.5);
            const side = Vec{ -@sin(ang), 0, @cos(ang) };
            const len = 0.20 - 0.03 * @as(f32, @floatFromInt(k));
            try body.blade(p, add(p, add(scale(side, len), .{ 0, -0.04, 0 })), 0.075, .{ 0, 0.025, 0 }, ang);
            try body.blade(p, add(p, add(scale(side, -len), .{ 0, -0.04, 0 })), 0.075, .{ 0, 0.025, 0 }, ang);
        }
        // The glowing vein runs up the middle of the frond, just above it.
        var vein: [4]Vec = undefined;
        for (&vein, path) |*v, p| v.* = add(p, .{ 0, 0.01, 0 });
        try glow.ribbon(&vein, 0.03, .{ 0, 1, 0 });
    }
}

// ---------------------------------------------------------------- trees

fn glowvineTree(body: *Builder, glow: *Builder) !void {
    // A leaning trunk, four boughs, leaf crowns, and luminous vines hanging from the boughs.
    const bark: Vec = .{ 0.34, 0.25, 0.20 };
    const leaf: Vec = .{ 0.28, 0.52, 0.36 };
    const trunk_top: Vec = .{ 0.5, 5.2, 0.2 };
    body.tone = bark;
    try body.tube(.{ 0, -0.2, 0 }, trunk_top, 0.34, 0.16, 7);
    for (0..4) |i| {
        const ang = around(i, 4) + 0.5;
        const from = lerp3(.{ 0, 0, 0 }, trunk_top, 0.62 + 0.1 * @as(f32, @floatFromInt(i % 2)));
        const to = add(trunk_top, ring(1.6 + unit(.glowvine_tree, i, 1) * 0.5, ang, 0.9 + unit(.glowvine_tree, i, 2) * 0.7));
        body.tone = bark;
        try body.tube(from, to, 0.13, 0.05, 5);
        body.tone = leaf;
        try body.ellipsoid(add(to, .{ 0, 0.25, 0 }), .{ 1.05, 0.62, 1.05 }, 5, 8);
        // Three vines drop from each bough, ribbons several metres long.
        for (0..3) |k| {
            const t = 0.45 + 0.28 * @as(f32, @floatFromInt(k));
            const hook = lerp3(from, to, t);
            const drop = 2.2 + unit(.glowvine_tree, i * 3 + k, 3) * 1.3;
            const sway = ring(0.18, ang + @as(f32, @floatFromInt(k)), 0);
            try glow.ribbon(&.{ hook, add(hook, add(sway, .{ 0, -drop * 0.4, 0 })), add(hook, add(scale(sway, 1.6), .{ 0, -drop * 0.75, 0 })), add(hook, add(scale(sway, 1.2), .{ 0, -drop, 0 })) }, 0.30, .{ @cos(ang), 0, @sin(ang) });
        }
    }
    body.tone = leaf;
    try body.ellipsoid(add(trunk_top, .{ 0, 0.9, 0 }), .{ 1.7, 1.05, 1.7 }, 5, 9);
}

fn crystalLeafTree(body: *Builder, glow: *Builder) !void {
    // A pale, branching trunk carrying a cloud of glassy diamond plates; every fourth plate is lit.
    const wood: Vec = .{ 0.68, 0.74, 0.80 };
    const glass: Vec = .{ 0.76, 0.90, 0.96 };
    const top: Vec = .{ 0, 5.4, 0 };
    body.tone = wood;
    try body.tube(.{ 0, -0.2, 0 }, top, 0.30, 0.10, 7);
    var plate_index: usize = 0;
    for (0..7) |i| {
        const ang = around(i, 7) + unit(.crystal_leaf_tree, i, 1) * 0.4;
        const from = lerp3(.{ 0, 0, 0 }, top, 0.45 + 0.1 * @as(f32, @floatFromInt(i % 4)));
        const to = add(from, ring(1.9 + unit(.crystal_leaf_tree, i, 2) * 0.8, ang, 1.4 + unit(.crystal_leaf_tree, i, 3) * 1.2));
        body.tone = wood;
        try body.tube(from, to, 0.11, 0.04, 5);
        for (0..13) |k| {
            const t = 0.3 + 0.7 * @as(f32, @floatFromInt(k)) / 13.0;
            const base = lerp3(from, to, t);
            const jitter = Vec{ unit(.crystal_leaf_tree, plate_index, 4) - 0.5, unit(.crystal_leaf_tree, plate_index, 5) - 0.2, unit(.crystal_leaf_tree, plate_index, 6) - 0.5 };
            const c = add(base, scale(jitter, 1.5));
            const facing = normalize(.{ jitter[0] * 2, 1.2, jitter[2] * 2 });
            const spin = unit(.crystal_leaf_tree, plate_index, 7) * std.math.pi;
            const lit = plate_index % 4 == 0;
            body.tone = glass;
            try (if (lit) glow else body).plate(c, facing, 0.62, 0.34, spin);
            plate_index += 1;
        }
    }
    body.tone = glass;
    for (0..6) |i| {
        const c = add(top, ring(0.7 + unit(.crystal_leaf_tree, i, 8) * 0.9, around(i, 6), 0.5 + unit(.crystal_leaf_tree, i, 9) * 1.8));
        try glow.plate(c, normalize(.{ unit(.crystal_leaf_tree, i, 10) - 0.5, 1.3, unit(.crystal_leaf_tree, i, 11) - 0.5 }), 0.66, 0.36, unit(.crystal_leaf_tree, i, 12) * 3.0);
    }
    try body.plate(add(top, .{ 0, 3.1, 0 }), .{ 0, 1, 0.2 }, 0.7, 0.38, 0.6);
}

fn sapwillow(body: *Builder, glow: *Builder) !void {
    // A thick curving trunk and eight boughs that arch out and weep; a glowing vein of sap runs along each.
    const bark: Vec = .{ 0.40, 0.30, 0.24 };
    const leaf: Vec = .{ 0.42, 0.62, 0.34 };
    const bend: Vec = .{ 0.7, 0, 0.3 };
    body.tone = bark;
    try body.tube(.{ 0, -0.2, 0 }, .{ bend[0] * 0.5, 4.3, bend[2] * 0.5 }, 0.5, 0.34, 8);
    try body.tube(.{ bend[0] * 0.5, 4.3, bend[2] * 0.5 }, .{ bend[0], 8.2, bend[2] }, 0.34, 0.16, 8);
    const crown: Vec = .{ bend[0], 8.2, bend[2] };
    for (0..8) |i| {
        const ang = around(i, 8) + unit(.sapwillow, i, 1) * 0.3;
        const reach = 3.0 + unit(.sapwillow, i, 2) * 1.2;
        const arch_top = add(crown, ring(reach * 0.45, ang, 1.0));
        const mid = add(crown, ring(reach * 0.85, ang, 0.6));
        const low = add(crown, ring(reach, ang, -2.8 - unit(.sapwillow, i, 3) * 1.4));
        body.tone = bark;
        try body.tube(crown, arch_top, 0.12, 0.08, 5);
        try body.tube(arch_top, mid, 0.08, 0.05, 5);
        try body.tube(mid, low, 0.05, 0.02, 4);
        // A curtain of leaf ribbons along the arch and the drooping part.
        body.tone = leaf;
        for (0..9) |k| {
            const f = @as(f32, @floatFromInt(k)) / 9.0;
            const from = if (f < 0.4) lerp3(arch_top, mid, f / 0.4) else lerp3(mid, low, (f - 0.4) / 0.6);
            const drop = 1.3 + unit(.sapwillow, i * 9 + k, 4) * 1.1;
            try body.ribbon(&.{ from, add(from, .{ 0.03, -drop * 0.5, 0 }), add(from, .{ 0.06, -drop, 0.03 }) }, 0.7, .{ @cos(ang), 0.1, @sin(ang) });
        }
        // The sap vein: a thin bright strip beside the whole bough.
        const off: Vec = .{ 0, 0.06, 0 };
        try glow.ribbon(&.{ add(crown, off), add(arch_top, off), add(mid, off), add(low, off) }, 0.14, .{ 0, 1, 0 });
    }
}

// ---------------------------------------------------------------- tests

const Bounds = struct { lo: Vec, hi: Vec };

fn boundsOf(m: Mesh) Bounds {
    var b: Bounds = .{ .lo = .{ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32) }, .hi = .{ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32) } };
    for (m.vertices) |v| for (0..3) |i| {
        b.lo[i] = @min(b.lo[i], v.position[i]);
        b.hi[i] = @max(b.hi[i], v.position[i]);
    };
    return b;
}

fn validMesh(m: Mesh) !void {
    try std.testing.expect(m.indices.len % 3 == 0);
    for (m.indices) |i| try std.testing.expect(i < m.vertices.len);
    for (m.vertices) |v| {
        for (v.position ++ v.normal) |x| try std.testing.expect(std.math.isFinite(x));
        const l = v.normal[0] * v.normal[0] + v.normal[1] * v.normal[1] + v.normal[2] * v.normal[2];
        try std.testing.expect(l > 0.5 and l < 1.5);
    }
}

test "every species builds a body and a glow inside its height, radius and triangle budget" {
    const a = std.testing.allocator;
    inline for (enum_compat.fields(Species)) |f| {
        const s: Species = @enumFromInt(f.value);
        const i = info(s);
        const parts = try build(a, s);
        defer parts.deinit(a);
        try validMesh(parts.body);
        try validMesh(parts.glow);
        try std.testing.expect(parts.body.vertices.len > 0 and parts.glow.vertices.len > 0);
        const tris = (parts.body.indices.len + parts.glow.indices.len) / 3;
        try std.testing.expect(tris <= i.triangles);
        const bb = boundsOf(parts.body);
        const gb = boundsOf(parts.glow);
        const top = @max(bb.hi[1], gb.hi[1]);
        // Tall enough to read as itself, never above its design height by more than a fifth.
        try std.testing.expect(top >= i.height * 0.75 and top <= i.height * 1.2);
        // Rooted at the ground (a small sink below it for trunks and cushions is fine).
        try std.testing.expect(@min(bb.lo[1], gb.lo[1]) >= -0.3 and bb.lo[1] <= 0.15);
        const reach = @max(@max(@abs(bb.lo[0]), bb.hi[0]), @max(@abs(bb.lo[2]), bb.hi[2]));
        try std.testing.expect(reach <= i.radius * 1.25);
        // Glow sits on the plant: within the plant's own reach and height (plus a little).
        for ([_]usize{ 0, 2 }) |axis| try std.testing.expect(@max(@abs(gb.lo[axis]), gb.hi[axis]) <= i.radius * 1.25);
    }
}

test "heights keep to the combat rule by family and species differ from each other" {
    const a = std.testing.allocator;
    var seen: [count]usize = undefined;
    inline for (enum_compat.fields(Species), 0..) |f, k| {
        const s: Species = @enumFromInt(f.value);
        const parts = try build(a, s);
        defer parts.deinit(a);
        const top = @max(boundsOf(parts.body).hi[1], boundsOf(parts.glow).hi[1]);
        switch (info(s).family) {
            .grass, .flower => try std.testing.expect(top <= 0.62),
            .bush => try std.testing.expect(top <= 2.0 and top >= 0.7),
            .tree => try std.testing.expect(top >= 5.0 and top <= 12.5),
        }
        seen[k] = parts.body.vertices.len * 7919 + parts.glow.vertices.len;
        for (seen[0..k]) |other| try std.testing.expect(other != seen[k]);
    }
}

test "building a species twice gives identical meshes" {
    const a = std.testing.allocator;
    inline for (enum_compat.fields(Species)) |f| {
        const s: Species = @enumFromInt(f.value);
        const x = try build(a, s);
        defer x.deinit(a);
        const y = try build(a, s);
        defer y.deinit(a);
        try std.testing.expectEqualSlices(u32, x.body.indices, y.body.indices);
        try std.testing.expectEqualSlices(Mesh.Vertex, x.body.vertices, y.body.vertices);
        try std.testing.expectEqualSlices(Mesh.Vertex, x.glow.vertices, y.glow.vertices);
    }
}

test "every species has distinct day and glow colours and a name" {
    inline for (enum_compat.fields(Species)) |f| {
        const i = info(@enumFromInt(f.value));
        try std.testing.expect(i.name.len > 3);
        var same = true;
        for (i.body, i.glow) |b, g| same = same and @abs(b - g) < 0.02;
        try std.testing.expect(!same);
        // Glow colours are bright: at least one channel is near full.
        try std.testing.expect(@max(i.glow[0], @max(i.glow[1], i.glow[2])) >= 0.9);
    }
}
