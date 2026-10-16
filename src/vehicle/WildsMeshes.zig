//! Modular rural buildings and an ancient-tech shrine for the mountain Wilds.
const std = @import("std");
const m = @import("../character/math.zig");
const cm = @import("../character/mesh.zig");
const prims = @import("prims.zig");
const Designs = @import("Designs.zig");
const RenderMesh = @import("../render/Mesh.zig");
const Vec3 = m.Vec3;
const Allocator = std.mem.Allocator;

const farm_palette: Designs.Palette = .{
    .paint = .{ 0.48, 0.27, 0.13 },
    .accent = .{ 0.16, 0.21, 0.19 },
    .lights = .{ 1.0, 0.56, 0.19 },
};
const temple_palette: Designs.Palette = .{
    .paint = .{ 0.5, 0.58, 0.58 },
    .accent = .{ 0.2, 0.3, 0.33 },
    .lights = .{ 0.24, 0.94, 0.88 },
};

fn finish(a: Allocator, mesh: *cm.Mesh, palette: Designs.Palette) !RenderMesh {
    mesh.computeNormals();
    return Designs.renderMesh(a, mesh, palette);
}

fn box(a: Allocator, mesh: *cm.Mesh, center: Vec3, half: Vec3, mat: cm.Material) !void {
    try prims.box(a, mesh, center, Vec3.unit_x, Vec3.unit_y, Vec3.unit_z, half, mat);
}

/// Compact timber cabin with a covered porch, peaked roof, windows, and a warm entry lamp.
pub fn cabin(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    try box(a, &mesh, Vec3.init(0, 2.2, 0), Vec3.init(4.8, 2.2, 4), .paint);
    try box(a, &mesh, Vec3.init(0, 4.55, 0), Vec3.init(5.25, 0.25, 4.5), .metal);
    for ([_]f32{ -1, 1 }) |side| {
        try prims.strut(a, &mesh, Vec3.init(0, 7.4, -4.6), Vec3.init(side * 5.8, 4.7, -4.6), Vec3.unit_z, 0.42, 0.34, .paint_accent);
        try prims.strut(a, &mesh, Vec3.init(side * 5.8, 4.7, -4.6), Vec3.init(0, 7.4, 4.6), Vec3.unit_z, 0.42, 0.34, .paint_accent);
        try box(a, &mesh, Vec3.init(side * 2.35, 3.0, 4.1), Vec3.init(1.0, 1.0, 0.12), .glass);
        // Porch posts and the broad timber verandah make the entrance readable at a distance.
        try prims.strut(a, &mesh, Vec3.init(side * 3.8, 0, 6.8), Vec3.init(side * 3.8, 4.7, 6.8), Vec3.unit_z, 0.34, 0.34, .metal);
    }
    try box(a, &mesh, Vec3.init(0, 0.3, 6.0), Vec3.init(4.4, 0.3, 2.8), .paint_accent);
    try box(a, &mesh, Vec3.init(0, 2.0, 4.16), Vec3.init(0.8, 1.75, 0.16), .metal);
    try box(a, &mesh, Vec3.init(1.2, 4.8, 0), Vec3.init(0.42, 1.45, 0.42), .metal);
    return finish(a, &mesh, farm_palette);
}

/// A high-shouldered field barn with open hay loft, sliding doors, and a tin roof.
pub fn barn(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    try box(a, &mesh, Vec3.init(0, 3.5, 0), Vec3.init(6.5, 3.5, 5.2), .paint_accent);
    try box(a, &mesh, Vec3.init(0, 6.7, 0), Vec3.init(6.9, 0.25, 5.6), .metal);
    for ([_]f32{ -1, 1 }) |side| {
        try prims.strut(a, &mesh, Vec3.init(0, 10.3, -5.8), Vec3.init(side * 7.4, 6.8, -5.8), Vec3.unit_z, 0.5, 0.38, .paint);
        try prims.strut(a, &mesh, Vec3.init(side * 7.4, 6.8, -5.8), Vec3.init(0, 10.3, 5.8), Vec3.unit_z, 0.5, 0.38, .paint);
        try box(a, &mesh, Vec3.init(side * 2.05, 2.7, 5.34), Vec3.init(2.0, 2.65, 0.18), .paint);
        try box(a, &mesh, Vec3.init(side * 6.25, 4.0, 0), Vec3.init(0.22, 3.3, 0.22), .metal);
        try box(a, &mesh, Vec3.init(side * 3.25, 7.8, -5.42), Vec3.init(1.25, 0.85, 0.12), .glass);
    }
    try box(a, &mesh, Vec3.init(0, 5.45, 5.38), Vec3.init(0.16, 2.9, 0.16), .metal);
    try box(a, &mesh, Vec3.init(0, 2.85, 5.4), Vec3.init(0.12, 2.55, 0.22), .metal);
    return finish(a, &mesh, farm_palette);
}

/// Where the signal gem hovers over the temple, in the mesh's own (unscaled) space.
pub const temple_crown = Vec3.init(0, 8.0, 0);
const temple_radius: f32 = 5.9;
const column_count = 7;
const Vec2 = m.Vec2;

/// A closed rectangular ring section revolved about +Y at `at`: a band, rail or step.
fn band(a: Allocator, mesh: *cm.Mesh, at: Vec3, radius: f32, half_w: f32, half_h: f32, mat: cm.Material) !void {
    const loop = [_]Vec2{
        .{ .x = radius - half_w, .y = -half_h }, .{ .x = radius + half_w, .y = -half_h },
        .{ .x = radius + half_w, .y = half_h },  .{ .x = radius - half_w, .y = half_h },
    };
    try prims.lathe(a, mesh, &loop, 28, .{ .translation = at }, mat);
}

/// A solid drum tapering from `r0` at `y0` to `r1` at `y1`.
fn drum(a: Allocator, mesh: *cm.Mesh, at: Vec3, r0: f32, r1: f32, y0: f32, y1: f32, segments: u32, mat: cm.Material) !void {
    const loop = [_]Vec2{ .{ .x = 0, .y = y0 }, .{ .x = r0, .y = y0 }, .{ .x = r1, .y = y1 }, .{ .x = 0, .y = y1 } };
    try prims.lathe(a, mesh, &loop, segments, .{ .translation = at }, mat);
}

/// A thin torus ring, tilted about X then Z: one hoop of the instrument's gimbal.
fn gimbal(a: Allocator, mesh: *cm.Mesh, center: Vec3, radius: f32, tube: f32, tilt_x: f32, tilt_z: f32, mat: cm.Material) !void {
    var loop: [8]Vec2 = undefined;
    for (&loop, 0..) |*p, i| {
        const angle = @as(f32, @floatFromInt(i)) / loop.len * m.tau;
        p.* = .{ .x = radius + tube * @cos(angle), .y = tube * @sin(angle) };
    }
    const rotation = m.Quat.fromAxisAngle(Vec3.unit_z, tilt_z).mul(m.Quat.fromAxisAngle(Vec3.unit_x, tilt_x));
    try prims.lathe(a, mesh, &loop, 28, .{ .translation = center, .rotation = rotation }, mat);
}

/// A column with a flared foot, tapering shaft and a wide capital, ringed by glyph bands.
fn column(a: Allocator, mesh: *cm.Mesh, at: Vec3, height: f32) !void {
    const loop = [_]Vec2{
        .{ .x = 0, .y = 0 },    .{ .x = 0.95, .y = 0 },                .{ .x = 0.95, .y = 0.35 },        .{ .x = 0.62, .y = 0.55 },
        .{ .x = 0.5, .y = height * 0.6 }, .{ .x = 0.42, .y = height - 0.7 }, .{ .x = 0.78, .y = height - 0.5 }, .{ .x = 0.78, .y = height },
        .{ .x = 0, .y = height },
    };
    try prims.lathe(a, mesh, &loop, 10, .{ .translation = at }, .paint);
    for ([_]f32{ 0.28, 0.5 }) |f| try band(a, mesh, at.add(Vec3.init(0, height * f, 0)), 0.5, 0.045, 0.07, .emissive);
}

/// A resonator coil: stacked metal discs with a glowing band between each, and a lit antenna.
fn resonator(a: Allocator, mesh: *cm.Mesh, at: Vec3) !void {
    try drum(a, mesh, at, 1.0, 0.8, 0, 0.5, 12, .paint_accent);
    var y: f32 = 0.5;
    for (0..5) |k| {
        const r = 0.78 - @as(f32, @floatFromInt(k)) * 0.07;
        try drum(a, mesh, at, r, r, y, y + 0.22, 12, .metal);
        try drum(a, mesh, at, r - 0.1, r - 0.1, y + 0.22, y + 0.4, 12, .emissive);
        y += 0.4;
    }
    try box(a, mesh, at.add(Vec3.init(0, y + 0.5, 0)), Vec3.init(0.08, 0.5, 0.08), .metal);
    try box(a, mesh, at.add(Vec3.init(0, y + 1.05, 0)), Vec3.init(0.2, 0.2, 0.2), .emissive);
}

/// An ancient temple that is also a laboratory: terraced circular sanctuary around a glass
/// reaction chamber and gimbal rings, a peristyle of glyph-banded columns crowned with crystal
/// antennae, resonator coils and instrument benches inside, a pylon gate at the front (+Z) and a
/// broken arc of standing stelae behind.
pub fn caveTemple(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    const origin = Vec3.zero;
    // Three terraces and a stair.
    try drum(a, &mesh, origin, 7.8, 7.4, 0, 0.5, 28, .metal);
    try drum(a, &mesh, origin, 6.8, 6.5, 0.5, 1.0, 28, .paint_accent);
    try drum(a, &mesh, origin, 5.6, 5.4, 1.0, 1.4, 28, .paint);
    for (0..3) |k| {
        const f: f32 = @floatFromInt(k);
        try box(a, &mesh, Vec3.init(0, 0.2 + f * 0.2, 7.5 - f * 0.8), Vec3.init(2.2 - f * 0.2, 0.2 + f * 0.2, 0.45), .paint_accent);
    }
    // Inlaid floor: two glowing rings and radial circuit lines, leaving the entrance clear.
    try band(a, &mesh, Vec3.init(0, 1.42, 0), 4.5, 0.08, 0.03, .emissive);
    try band(a, &mesh, Vec3.init(0, 1.42, 0), 2.7, 0.06, 0.03, .emissive);
    for (0..9) |k| {
        const angle = (@as(f32, @floatFromInt(k)) + 0.5) / 9.0 * m.tau;
        if (@sin(angle) > 0.8) continue;
        const dir = Vec3.init(@cos(angle), 0, @sin(angle));
        const lift = Vec3.init(0, 1.43, 0);
        try prims.strut(a, &mesh, dir.scale(1.6).add(lift), dir.scale(4.5).add(lift), Vec3.unit_y, 0.1, 0.05, .emissive);
    }
    // The reaction chamber: plinth, glass cylinder around a floating core, capped spindle.
    try drum(a, &mesh, origin, 1.5, 1.2, 1.4, 2.2, 16, .paint_accent);
    try drum(a, &mesh, origin, 0.9, 0.6, 2.2, 3.2, 12, .metal);
    try drum(a, &mesh, origin, 0.75, 0.75, 3.2, 6.0, 16, .glass);
    const core = [_]Vec2{ .{ .x = 0, .y = 3.7 }, .{ .x = 0.42, .y = 4.65 }, .{ .x = 0, .y = 5.6 } };
    try prims.lathe(a, &mesh, &core, 8, .{}, .emissive);
    try drum(a, &mesh, origin, 0.6, 0.35, 6.0, 6.7, 12, .metal);
    for ([_]f32{ 0, 1, 2 }) |k| {
        try gimbal(a, &mesh, Vec3.init(0, 4.65, 0), 1.35 + k * 0.5, 0.06 + k * 0.01, 0.5 + k * 0.55, k * 0.9 - 0.4, if (k == 1) .emissive else .metal);
    }
    // Peristyle: columns on a circle with a gap at the entrance, joined by glowing lintels.
    var tops: [column_count]Vec3 = undefined;
    for (0..column_count) |k| {
        const angle = std.math.pi / 2.0 + (@as(f32, @floatFromInt(k)) + 0.5) / column_count * m.tau;
        const height: f32 = if (k % 2 == 0) 7.6 else 6.6;
        const at = Vec3.init(@cos(angle) * temple_radius, 1.4, @sin(angle) * temple_radius);
        try column(a, &mesh, at, height);
        tops[k] = at.add(Vec3.init(0, height, 0));
        const spire: f32 = if (k % 2 == 0) 2.6 else 1.6;
        try prims.strut(a, &mesh, tops[k], tops[k].add(Vec3.init(0, spire, 0)), Vec3.unit_z, 0.16, 0.16, .metal);
        try box(a, &mesh, tops[k].add(Vec3.init(0, spire + 0.22, 0)), Vec3.init(0.2, 0.28, 0.2), .emissive);
    }
    for (1..column_count) |k| {
        const from = tops[k - 1].add(Vec3.init(0, 0.3, 0));
        const to = tops[k].add(Vec3.init(0, 0.3, 0));
        try prims.strut(a, &mesh, from, to, Vec3.unit_y, 0.7, 0.55, .metal);
        try prims.strut(a, &mesh, from.add(Vec3.init(0, 0.34, 0)), to.add(Vec3.init(0, 0.34, 0)), Vec3.unit_y, 0.16, 0.08, .emissive);
    }
    // Resonator coils and instrument benches inside the ring.
    for ([_]f32{ -1, 1 }) |side| {
        try resonator(a, &mesh, Vec3.init(side * 3.4, 1.4, -2.4));
        try box(a, &mesh, Vec3.init(side * 3.3, 1.9, 2.0), Vec3.init(0.9, 0.5, 0.55), .paint_accent);
        try box(a, &mesh, Vec3.init(side * 3.3, 2.43, 2.0), Vec3.init(0.95, 0.04, 0.6), .glass);
        try box(a, &mesh, Vec3.init(side * 3.3, 2.0, 2.56), Vec3.init(0.7, 0.06, 0.03), .emissive);
        try prims.strut(a, &mesh, Vec3.init(side * 3.3, 2.5, 1.7), Vec3.init(side * 3.3, 3.5, 1.45), Vec3.unit_x, 1.1, 0.07, .carbon);
        try prims.strut(a, &mesh, Vec3.init(side * 3.3, 2.55, 1.66), Vec3.init(side * 3.3, 3.45, 1.43), Vec3.unit_x, 0.9, 0.04, .emissive);
    }
    // The pylon gate: two leaning towers and a glyph lintel.
    for ([_]f32{ -1, 1 }) |side| {
        try prims.strut(a, &mesh, Vec3.init(side * 2.7, 1.4, 7.0), Vec3.init(side * 1.6, 9.4, 7.0), Vec3.unit_z, 0.95, 0.75, .paint);
        try prims.strut(a, &mesh, Vec3.init(side * 2.2, 2.0, 6.62), Vec3.init(side * 1.45, 8.6, 6.62), Vec3.unit_z, 0.12, 0.06, .emissive);
    }
    try box(a, &mesh, Vec3.init(0, 9.0, 7.0), Vec3.init(1.55, 0.35, 0.5), .metal);
    for ([_]f32{ -0.8, 0, 0.8 }) |x| try box(a, &mesh, Vec3.init(x, 9.0, 6.47), Vec3.init(0.22, 0.14, 0.03), .emissive);
    // Standing stelae in a broken arc behind the sanctuary.
    for (0..5) |k| {
        const f: f32 = @floatFromInt(k);
        const angle = -std.math.pi / 2.0 + (f - 2.0) * 0.5;
        const at = Vec3.init(@cos(angle) * 8.6, 0, @sin(angle) * 8.6);
        const lean = (f - 2.0) * 0.12;
        const tall = 4.6 + @as(f32, @floatFromInt((k * 5) % 3)) * 1.4;
        try prims.strut(a, &mesh, at, at.add(Vec3.init(lean * tall, tall, 0)), Vec3.unit_z, 1.1, 0.45, .paint);
        try prims.strut(a, &mesh, at.add(Vec3.init(lean * 1.2 + 0.05, 1.2, 0.27)), at.add(Vec3.init(lean * (tall - 0.6), tall - 0.6, 0.27)), Vec3.unit_z, 0.1, 0.04, .emissive);
    }
    return finish(a, &mesh, temple_palette);
}

test "the temple is a lit, rounded lab, not a box" {
    const a = std.testing.allocator;
    const mesh = try caveTemple(a);
    defer mesh.deinit(a);
    var lo = Vec3.init(1e9, 1e9, 1e9);
    var hi = Vec3.init(-1e9, -1e9, -1e9);
    for (mesh.vertices) |v| {
        const p = Vec3.init(v.position[0], v.position[1], v.position[2]);
        try std.testing.expect(std.math.isFinite(p.x) and std.math.isFinite(p.y) and std.math.isFinite(p.z));
        lo = Vec3.init(@min(lo.x, p.x), @min(lo.y, p.y), @min(lo.z, p.z));
        hi = Vec3.init(@max(hi.x, p.x), @max(hi.y, p.y), @max(hi.z, p.z));
    }
    for (mesh.indices) |i| try std.testing.expect(i < mesh.vertices.len);
    // It stands on the ground; the leaning stelae sink a hand's breadth into it.
    try std.testing.expect(lo.y < 0.01 and lo.y > -0.3);
    // Taller than the old pavilion, and the gem sits above the chamber, inside the ring of antennae.
    try std.testing.expect(hi.y > 10 and hi.y < 14);
    try std.testing.expect(temple_crown.y > 6.7 and temple_crown.y < hi.y);
    try std.testing.expect(hi.x - lo.x < 24 and hi.z - lo.z < 24);
    // Detail: far more geometry than the old twelve boxes, and a real share of it glowing.
    try std.testing.expect(mesh.vertices.len > 3000);
    var lit: usize = 0;
    for (mesh.vertices) |v| {
        if (v.color[1] > 0.8 and v.color[0] < 0.4) lit += 1;
    }
    try std.testing.expect(lit * 20 > mesh.vertices.len);
}
