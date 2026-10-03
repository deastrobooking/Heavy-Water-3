//! Flying ships, built from the vehicle primitives:
//!
//! - **Kestrel**, the player's fighter: a lathed fuselage, a glass canopy, swept delta wings
//!   and canards from the NACA wing builder, twin canted tail fins lofted from symmetric
//!   sections, side intakes, and twin convergent-divergent nozzles.
//! - **Hive wasp**, the small insect fighter: chitin thorax and head, a striped segmented
//!   abdomen, a stinger, tucked legs and compound eyes; its wing is a separate mesh drawn four
//!   times and flapped by the game.
//! - **Brood carrier**, the large insect ship: a 90 m beetle with raised wing cases (elytra),
//!   membrane wings, six legs and mandibles, flak turrets, and glowing launch bays (its weak
//!   points) and veins.
//!
//! Every model comes as a shell plus an emissive part. Frame: +Z forward, +Y up.
const std = @import("std");
const m = @import("../character/math.zig");
const cm = @import("../character/mesh.zig");
const prims = @import("prims.zig");
const airfoil = @import("airfoil.zig");
const nozzle = @import("nozzle.zig");
const Designs = @import("Designs.zig");
const RenderMesh = @import("../render/Mesh.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Transform = m.Transform;
const Allocator = std.mem.Allocator;

pub const Pair = struct { shell: RenderMesh, glow: RenderMesh };

pub const kestrel_palette: Designs.Palette = .{ .paint = .{ 0.78, 0.8, 0.84 }, .accent = .{ 0.16, 0.42, 0.78 }, .lights = .{ 0.4, 0.95, 1 } };
pub const hive_palette: Designs.Palette = .{ .paint = .{ 0.07, 0.06, 0.07 }, .accent = .{ 0.55, 0.11, 0.07 }, .lights = .{ 1, 0.18, 0.1 } };

/// Unit-sphere pod scaled to radii `r` at `center`, rotated by `q`.
fn ellipsoid(a: Allocator, mesh: *cm.Mesh, center: Vec3, r: Vec3, q: Quat, material: cm.Material) !void {
    var prof: [12]Vec2 = undefined;
    for (&prof, 0..) |*p, i| {
        const t = @as(f32, @floatFromInt(i)) / 11.0 * m.pi - m.pi / 2.0;
        p.* = .{ .x = @cos(t), .y = @sin(t) };
    }
    try prims.lathe(a, mesh, &prof, 20, .{ .translation = center, .rotation = q, .scale = r }, material);
}

/// A body of revolution along +Z from radius samples `r` spaced evenly from z0 (tail) to z1
/// (nose), flattened by `squash` (x, y scale).
fn fuselage(a: Allocator, mesh: *cm.Mesh, radii: []const f32, z0: f32, z1: f32, squash: [2]f32, material: cm.Material) !void {
    var prof: [24]Vec2 = undefined;
    const n = radii.len;
    // Closed on the axis at both ends: tail centre, the radii, nose centre.
    prof[0] = .{ .x = 0, .y = z0 };
    for (radii, 0..) |r, i| prof[i + 1] = .{ .x = r, .y = m.lerp(z0, z1, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1))) };
    prof[n + 1] = .{ .x = 0, .y = z1 };
    // Lathe about +Y, then turn +Y onto +Z; local z (which becomes -Y) carries the vertical squash.
    try prims.lathe(a, mesh, prof[0 .. n + 2], 24, .{ .rotation = Quat.fromAxisAngle(Vec3.unit_x, m.pi / 2.0), .scale = Vec3.init(squash[0], 1, squash[1]) }, material);
}

/// A tapered, swept fin lofted from symmetric sections: root chord at `base`, rising `height`
/// along `up_dir` (cant), tip shifted back by the sweep.
fn fin(a: Allocator, mesh: *cm.Mesh, base: Vec3, up_dir: Vec3, height: f32, root: f32, tip: f32, sweep: f32, material: cm.Material) !void {
    const section = airfoil.Naca4.fromDigits("0009");
    const n = 12;
    var loop: [2 * n - 2]Vec2 = undefined;
    section.outline(n, &loop);
    const side = up_dir.cross(Vec3.unit_z).normalizeOr(Vec3.unit_x);
    const first = mesh.vertexCount();
    for (0..2) |row| {
        const t: f32 = @floatFromInt(row);
        const chord = m.lerp(root, tip, t);
        const le = base.add(up_dir.scale(height * t)).add(Vec3.init(0, 0, -height * t * @tan(sweep)));
        for (loop) |p| {
            const pos = le.add(Vec3.init(0, 0, -p.x * chord)).add(side.scale(p.y * chord));
            _ = try mesh.addVertex(a, .{ .pos = pos, .material = material });
        }
    }
    // The section loop runs counter-clockwise seen from the root: wind so faces point out.
    try mesh.stitchRings(a, first, 2, loop.len, true, true);
    for ([_]u32{ 0, 1 }) |row| {
        var c = Vec3.zero;
        for (0..loop.len) |k| c = c.add(mesh.vertices.items[first + row * loop.len + k].pos);
        const ci = try mesh.addVertex(a, .{ .pos = c.scale(1.0 / @as(f32, loop.len)), .material = material });
        try mesh.capRing(a, first + row * @as(u32, loop.len), loop.len, ci, row == 1);
    }
}

fn finish(a: Allocator, shell: *cm.Mesh, glow: *cm.Mesh, p: Designs.Palette) !Pair {
    shell.computeNormals();
    glow.computeNormals();
    const s = try Designs.renderMesh(a, shell, p);
    errdefer s.deinit(a);
    return .{ .shell = s, .glow = try Designs.renderMesh(a, glow, p) };
}

// ---------------------------------------------------------------- Kestrel

pub const kestrel_length: f32 = 14;
/// Cannon muzzles (body frame, from the model origin).
pub const kestrel_guns = [2]Vec3{ Vec3.init(1.25, -0.15, 3.0), Vec3.init(-1.25, -0.15, 3.0) };

pub fn kestrel(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    // Fuselage, tail (z = -7) to nose (z = +7).
    const radii = [_]f32{ 0.62, 0.78, 0.92, 1.0, 1.05, 1.08, 1.06, 1.0, 0.92, 0.8, 0.62, 0.42, 0.22 };
    try fuselage(a, &shell, &radii, -7, 7, .{ 1.2, 0.82 }, .paint);
    try ellipsoid(a, &shell, Vec3.init(0, 0.72, 2.4), Vec3.init(0.55, 0.48, 1.7), Quat.identity, .glass);
    // Main delta wing and canards (uncambered placement, not inverted).
    try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("2408"), .span = 10.4, .root_chord = 5.4, .tip_chord = 1.3, .sweep = m.radians(44), .dihedral = m.radians(-3), .twist_root = m.radians(2), .twist_tip = 0, .inverted = false, .root_le = Vec3.init(0, -0.15, 2.2), .material = .paint });
    try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("0008"), .span = 3.8, .root_chord = 1.3, .tip_chord = 0.5, .sweep = m.radians(38), .dihedral = m.radians(4), .twist_root = 0, .twist_tip = 0, .inverted = false, .root_le = Vec3.init(0, 0.1, 5.4), .material = .paint_accent });
    // Twin canted tails.
    for ([_]f32{ 1, -1 }) |side| {
        const up_dir = Vec3.init(side * @sin(m.radians(20)), @cos(m.radians(20)), 0);
        try fin(a, &shell, Vec3.init(side * 0.75, 0.6, -3.4), up_dir, 2.6, 2.6, 1.1, m.radians(40), .paint_accent);
        // Side intakes.
        try prims.box(a, &shell, Vec3.init(side * 1.15, -0.25, 1.0), Vec3.unit_x, Vec3.unit_y, Vec3.unit_z, Vec3.init(0.32, 0.42, 1.5), .carbon);
        // Engines: nozzles exhausting backward.
        try nozzle.buildNozzle(a, &shell, .{ .throat_radius = 0.3, .inlet_radius = 0.42, .exit_mach = 1.8, .wall = 0.03, .segments = 24 }, .{ .translation = Vec3.init(side * 0.5, 0, -6.9), .rotation = Quat.fromAxisAngle(Vec3.unit_x, m.pi / 2.0) });
        // Glow: afterburner disks and wingtip lights.
        try ellipsoid(a, &glow, Vec3.init(side * 0.5, 0, -7.45), Vec3.init(0.36, 0.36, 0.08), Quat.identity, .emissive);
        try ellipsoid(a, &glow, Vec3.init(side * 5.15, -0.42, -2.3), Vec3.init(0.12, 0.08, 0.3), Quat.identity, .emissive);
    }
    // A cyan strip along the spine.
    try prims.lightStrip(a, &glow, &.{ Vec3.init(0, 0.86, 0.5), Vec3.init(0, 0.84, -2), Vec3.init(0, 0.7, -4.5) }, Vec3.unit_y, 0.06, 0.04, .emissive);
    return finish(a, &shell, &glow, kestrel_palette);
}

// ---------------------------------------------------------------- Hive wasp

pub const wasp_length: f32 = 7;
/// Wing roots (body frame): fore and hind pairs; x sign gives the side.
pub const wasp_wings = [4]Vec3{ Vec3.init(0.7, 0.7, 0.5), Vec3.init(-0.7, 0.7, 0.5), Vec3.init(0.6, 0.65, -0.3), Vec3.init(-0.6, 0.65, -0.3) };

pub fn wasp(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const id = Quat.identity;
    try ellipsoid(a, &shell, Vec3.zero, Vec3.init(0.95, 0.85, 1.25), id, .paint);
    try ellipsoid(a, &shell, Vec3.init(0, 0.15, 1.75), Vec3.init(0.72, 0.66, 0.66), id, .paint);
    // Striped abdomen, narrowing to the stinger.
    const segments = [_][2]f32{ .{ -1.55, 0.95 }, .{ -2.55, 0.9 }, .{ -3.4, 0.75 }, .{ -4.1, 0.55 } };
    for (segments, 0..) |seg, i| try ellipsoid(a, &shell, Vec3.init(0, -0.15 - 0.08 * @as(f32, @floatFromInt(i)), seg[0]), Vec3.init(seg[1], seg[1] * 0.85, 0.62), id, if (i % 2 == 0) .paint_accent else .paint);
    try prims.strut(a, &shell, Vec3.init(0, -0.5, -4.5), Vec3.init(0, -0.75, -5.4), Vec3.unit_y, 0.12, 0.12, .metal);
    // Mandibles and tucked legs.
    for ([_]f32{ 1, -1 }) |side| {
        try prims.strut(a, &shell, Vec3.init(side * 0.3, -0.2, 2.3), Vec3.init(side * 0.12, -0.45, 2.75), Vec3.unit_y, 0.08, 0.08, .paint_accent);
        for (0..3) |k| {
            const z = 0.6 - @as(f32, @floatFromInt(k)) * 0.6;
            const knee = Vec3.init(side * 1.1, -0.9, z - 0.2);
            try prims.strut(a, &shell, Vec3.init(side * 0.5, -0.6, z), knee, Vec3.unit_z, 0.07, 0.07, .paint);
            try prims.strut(a, &shell, knee, Vec3.init(side * 0.8, -1.4, z - 0.7), Vec3.unit_z, 0.06, 0.06, .paint);
        }
        // Compound eyes.
        try ellipsoid(a, &glow, Vec3.init(side * 0.48, 0.3, 2.05), Vec3.init(0.3, 0.38, 0.32), id, .emissive);
    }
    return finish(a, &shell, &glow, hive_palette);
}

/// Long-bodied, four-wing Hive interceptor; the cyan eye lamps make its role readable at range.
pub fn dragonfly(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const id = Quat.identity;
    try ellipsoid(a, &shell, Vec3.init(0, 0, -0.5), Vec3.init(0.55, 0.48, 2.6), id, .paint);
    try ellipsoid(a, &shell, Vec3.init(0, 0.1, 2), Vec3.init(0.72, 0.62, 0.86), id, .metal);
    try ellipsoid(a, &shell, Vec3.init(0, 0, -3), Vec3.init(0.36, 0.34, 1.6), id, .paint_accent);
    for ([_]f32{ -1, 1 }) |side| {
        try ellipsoid(a, &glow, Vec3.init(side * 0.48, 0.32, 2.3), Vec3.init(0.22, 0.24, 0.24), id, .emissive);
        try prims.strut(a, &shell, Vec3.init(side * 0.34, -0.3, 0.2), Vec3.init(side * 0.9, -0.8, -0.8), Vec3.unit_z, 0.08, 0.06, .metal);
        try prims.strut(a, &shell, Vec3.init(side * 0.9, -0.8, -0.8), Vec3.init(side * 1.3, -1, -1.8), Vec3.unit_z, 0.05, 0.04, .metal);
    }
    return finish(a, &shell, &glow, hive_palette);
}

/// Heavy plated bomber with a wide beetle carapace, ventral bomb pods and amber warning eyes.
pub fn beetleBomber(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const id = Quat.identity;
    try ellipsoid(a, &shell, Vec3.init(0, 0.1, 0), Vec3.init(2, 1.15, 2.45), id, .paint);
    try ellipsoid(a, &shell, Vec3.init(0, 0.62, -0.45), Vec3.init(1.65, 0.62, 1.55), id, .paint_accent);
    try ellipsoid(a, &shell, Vec3.init(0, -0.05, 2.35), Vec3.init(1.05, 0.78, 0.92), id, .metal);
    for ([_]f32{ -1, 1 }) |side| {
        try ellipsoid(a, &glow, Vec3.init(side * 0.72, 0.24, 2.95), Vec3.init(0.28, 0.3, 0.26), id, .emissive);
        try ellipsoid(a, &shell, Vec3.init(side * 1.22, -1.05, -0.4), Vec3.init(0.42, 0.56, 0.9), id, .metal);
        try prims.strut(a, &shell, Vec3.init(side * 0.9, -0.7, -0.7), Vec3.init(side * 1.55, -1.1, -1.7), Vec3.unit_z, 0.12, 0.08, .paint);
        try prims.strut(a, &shell, Vec3.init(side * 1.55, -1.1, -1.7), Vec3.init(side * 1.75, -1.5, -2.5), Vec3.unit_z, 0.07, 0.05, .paint);
    }
    return finish(a, &shell, &glow, hive_palette);
}

/// One wasp wing, rooted at the origin and reaching along +X: a thin veined membrane.
pub fn waspWing(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    try ellipsoid(a, &mesh, Vec3.init(2.1, 0, -0.35), Vec3.init(2.2, 0.03, 0.62), Quat.fromAxisAngle(Vec3.unit_y, 0.12), .glass);
    try prims.strut(a, &mesh, Vec3.zero, Vec3.init(4.1, 0.02, -0.25), Vec3.unit_y, 0.05, 0.05, .carbon);
    mesh.computeNormals();
    return Designs.renderMesh(a, &mesh, hive_palette);
}

// ---------------------------------------------------------------- Brood carrier

pub const carrier_length: f32 = 92;
/// Launch bays on the belly (weak points), body frame.
pub const carrier_bays = [4]Vec3{ Vec3.init(6, -10.5, 14), Vec3.init(-6, -10.5, 14), Vec3.init(6, -10.5, -10), Vec3.init(-6, -10.5, -10) };
/// Flak turrets on the back.
pub const carrier_turrets = [4]Vec3{ Vec3.init(7, 12, 22), Vec3.init(-7, 12, 22), Vec3.init(9, 11, -16), Vec3.init(-9, 11, -16) };
/// Hit volume: spheres along the body (centre, radius).
pub const carrier_hull = [_][2]Vec3{
    .{ Vec3.init(0, 0, 32), Vec3.init(11, 0, 0) },
    .{ Vec3.init(0, 0, 14), Vec3.init(15, 0, 0) },
    .{ Vec3.init(0, 0, -6), Vec3.init(16, 0, 0) },
    .{ Vec3.init(0, 0, -24), Vec3.init(13, 0, 0) },
    .{ Vec3.init(0, 0, 48), Vec3.init(7, 0, 0) },
};

pub fn carrier(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const id = Quat.identity;
    // Abdomen, thorax, head.
    try ellipsoid(a, &shell, Vec3.init(0, 0, -4), Vec3.init(16, 11, 30), id, .paint);
    try ellipsoid(a, &shell, Vec3.init(0, 1, 32), Vec3.init(11, 9, 11), id, .paint);
    try ellipsoid(a, &shell, Vec3.init(0, 0, 46), Vec3.init(7, 6, 7), id, .paint);
    // Elytra: two hard wing cases lifted open, and the membrane wings between them.
    for ([_]f32{ 1, -1 }) |side| {
        try ellipsoid(a, &shell, Vec3.init(side * 10, 9, -4), Vec3.init(12, 3.5, 33), Quat.fromAxisAngle(Vec3.unit_z, side * 0.35), .paint_accent);
        try ellipsoid(a, &shell, Vec3.init(side * 24, 8, 4), Vec3.init(20, 0.35, 8), Quat.fromAxisAngle(Vec3.unit_y, side * 0.35), .glass);
        // Mandibles.
        try prims.strut(a, &shell, Vec3.init(side * 4, -2, 51), Vec3.init(side * 1.5, -3, 58), Vec3.unit_y, 1.2, 1.4, .paint_accent);
        // Six legs, folded under.
        for (0..3) |k| {
            const z = 26 - @as(f32, @floatFromInt(k)) * 14;
            const knee = Vec3.init(side * 20, -6, z + 4);
            try prims.strut(a, &shell, Vec3.init(side * 8, -8, z), knee, Vec3.unit_z, 1.4, 1.4, .paint);
            try prims.strut(a, &shell, knee, Vec3.init(side * 16, -16, z - 4), Vec3.unit_z, 1.1, 1.1, .paint);
        }
        // Eyes.
        try ellipsoid(a, &glow, Vec3.init(side * 4.5, 2, 50), Vec3.init(2, 2.4, 2), id, .emissive);
        // Veins along the flanks.
        var vein: [6]Vec3 = undefined;
        for (&vein, 0..) |*p, i| {
            const z = -28 + @as(f32, @floatFromInt(i)) * 10;
            const t = z / 30;
            p.* = Vec3.init(side * 15.6 * @sqrt(@max(0.05, 1 - t * t)), -1, z - 4);
        }
        try prims.lightStrip(a, &glow, &vein, Vec3.unit_y, 0.5, 0.4, .emissive);
    }
    // Flak turrets: a dome and a twin barrel.
    for (carrier_turrets) |t| {
        try ellipsoid(a, &shell, t, Vec3.init(2.2, 1.5, 2.2), id, .metal);
        try prims.strut(a, &shell, t.add(Vec3.init(0, 0.6, 0)), t.add(Vec3.init(0, 1.4, 4.5)), Vec3.unit_y, 0.5, 0.5, .metal);
    }
    // Glowing launch bays on the belly.
    for (carrier_bays) |b| try ellipsoid(a, &glow, b, Vec3.init(3.2, 1.2, 5), id, .emissive);
    return finish(a, &shell, &glow, hive_palette);
}

test "ship meshes build at their intended sizes" {
    const a = std.testing.allocator;
    const Case = struct { build: *const fn (Allocator) anyerror!Pair, length: f32 };
    for ([_]Case{ .{ .build = kestrel, .length = kestrel_length }, .{ .build = wasp, .length = wasp_length }, .{ .build = carrier, .length = carrier_length } }) |c| {
        const pair = try c.build(a);
        defer pair.shell.deinit(a);
        defer pair.glow.deinit(a);
        var lo: f32 = std.math.inf(f32);
        var hi: f32 = -std.math.inf(f32);
        for (pair.shell.vertices) |v| {
            for (v.position) |x| try std.testing.expect(std.math.isFinite(x));
            lo = @min(lo, v.position[2]);
            hi = @max(hi, v.position[2]);
        }
        try std.testing.expect(hi - lo > c.length * 0.85 and hi - lo < c.length * 1.25);
        try std.testing.expect(pair.glow.indices.len > 0);
    }
    const wing = try waspWing(a);
    defer wing.deinit(a);
    try std.testing.expect(wing.indices.len > 0);
}

test "the Kestrel's parts are closed solids" {
    const a = std.testing.allocator;
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    const radii = [_]f32{ 0.6, 1, 0.8, 0.3 };
    try fuselage(a, &mesh, &radii, -5, 5, .{ 1.2, 0.8 }, .paint);
    try airfoil.expectWatertight(&mesh);
    var f: cm.Mesh = .{};
    defer f.deinit(a);
    try fin(a, &f, Vec3.zero, Vec3.unit_y, 2, 2, 1, 0.5, .paint);
    try airfoil.expectWatertight(&f);
}
