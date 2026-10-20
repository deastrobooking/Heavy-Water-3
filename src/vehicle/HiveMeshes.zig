//! Procedural meshes for the Hive and for pickups, built from the vehicle primitives: lathed
//! bodies, ducted fans and struts. Each Hive model comes as a dark shell plus a separate
//! emissive part (eyes, rings) so the game can make the glow pulse or flash on hits.
const std = @import("std");
const m = @import("../character/math.zig");
const cm = @import("../character/mesh.zig");
const prims = @import("prims.zig");
const fan = @import("fan.zig");
const Designs = @import("Designs.zig");
const RenderMesh = @import("../render/Mesh.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Allocator = std.mem.Allocator;

pub const Pair = struct { shell: RenderMesh, glow: RenderMesh };

const hive: Designs.Palette = .{ .paint = .{ 0.13, 0.11, 0.13 }, .accent = .{ 0.32, 0.08, 0.1 }, .lights = .{ 1, 0.15, 0.12 } };

fn finish(a: Allocator, shell: *cm.Mesh, glow: *cm.Mesh) !Pair {
    return finishPalette(a, shell, glow, hive);
}

fn finishPalette(a: Allocator, shell: *cm.Mesh, glow: *cm.Mesh, palette: Designs.Palette) !Pair {
    shell.computeNormals();
    glow.computeNormals();
    const s = try Designs.renderMesh(a, shell, palette);
    errdefer s.deinit(a);
    return .{ .shell = s, .glow = try Designs.renderMesh(a, glow, palette) };
}

/// An ellipsoid-ish pod revolved about +Y: `r` radius, `h` half height, `points` profile points.
fn pod(a: Allocator, mesh: *cm.Mesh, center: Vec3, r: f32, h: f32, material: cm.Material) !void {
    var prof: [14]Vec2 = undefined;
    for (&prof, 0..) |*p, i| {
        const t = @as(f32, @floatFromInt(i)) / 13.0 * m.pi - m.pi / 2.0;
        p.* = .{ .x = r * @cos(t), .y = h * @sin(t) };
    }
    try prims.lathe(a, mesh, &prof, 24, .{ .translation = center }, material);
}

/// Hive drone: a pod hanging under one ducted fan, two claw struts and a red eye.
pub fn drone(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const spec: fan.FanSpec = .{ .radius = 0.42, .duct_chord = 0.16, .hub_radius = 0.07, .segments = 32 };
    try fan.buildDuct(a, &shell, spec, .{ .translation = Vec3.init(0, 0.25, 0) });
    try fan.buildHub(a, &shell, spec, .{ .translation = Vec3.init(0, 0.25, 0) });
    try fan.buildStruts(a, &shell, spec, .{ .translation = Vec3.init(0, 0.25, 0) });
    try pod(a, &shell, Vec3.init(0, -0.15, 0), 0.32, 0.28, .paint);
    for ([_]f32{ 1, -1 }) |side| {
        try prims.strut(a, &shell, Vec3.init(side * 0.2, -0.3, 0.05), Vec3.init(side * 0.34, -0.72, 0.22), Vec3.unit_z, 0.05, 0.05, .paint_accent);
    }
    try pod(a, &glow, Vec3.init(0, -0.12, 0.28), 0.09, 0.07, .emissive);
    return finish(a, &shell, &glow);
}

/// Hive sentinel: a heavy disc on three ducts with a glowing band and a cannon.
pub fn sentinel(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    try pod(a, &shell, Vec3.zero, 1.1, 0.45, .paint);
    const spec: fan.FanSpec = .{ .radius = 0.38, .duct_chord = 0.16, .hub_radius = 0.07, .segments = 28 };
    for (0..3) |i| {
        const angle = @as(f32, @floatFromInt(i)) * m.tau / 3.0;
        const at = Vec3.init(@sin(angle) * 1.45, 0.05, @cos(angle) * 1.45);
        try fan.buildDuct(a, &shell, spec, .{ .translation = at });
        try fan.buildHub(a, &shell, spec, .{ .translation = at });
        try prims.strut(a, &shell, at.scale(0.55), at.scale(0.82), Vec3.unit_y, 0.12, 0.1, .paint_accent);
    }
    try prims.strut(a, &shell, Vec3.init(0, -0.15, 0.6), Vec3.init(0, -0.2, 1.7), Vec3.unit_y, 0.18, 0.18, .metal);
    // Glowing band around the rim and the cannon's muzzle.
    var band: [8]Vec2 = undefined;
    for (&band, 0..) |*p, i| {
        const t = @as(f32, @floatFromInt(i)) / 8.0 * m.tau;
        p.* = .{ .x = 1.06 + 0.05 * @cos(t), .y = 0.05 * @sin(t) };
    }
    try prims.lathe(a, &glow, &band, 32, .{}, .emissive);
    try pod(a, &glow, Vec3.init(0, -0.2, 1.72), 0.1, 0.1, .emissive);
    return finish(a, &shell, &glow);
}

pub const spire_height: f32 = 26;

/// A Hive nest: a twisted dark spire over a corrupted ring, with glowing rings up its length.
pub fn spire(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    // Spire profile: a broad foot narrowing to a spike.
    var prof: [12]Vec2 = undefined;
    prof[0] = .{ .x = 0, .y = 0 };
    for (1..11) |i| {
        const t = @as(f32, @floatFromInt(i - 1)) / 9.0;
        prof[i] = .{ .x = 4.2 * std.math.pow(f32, 1 - t, 1.6) + 0.25, .y = t * spire_height };
    }
    prof[11] = .{ .x = 0, .y = spire_height + 2 };
    // Profile runs up the outside: reverse it so the loop winds the lathe outward.
    std.mem.reverse(Vec2, &prof);
    try prims.lathe(a, &shell, &prof, 7, .{}, .paint);
    // Buttress claws around the foot.
    for (0..5) |i| {
        const angle = @as(f32, @floatFromInt(i)) * m.tau / 5.0;
        const d = Vec3.init(@sin(angle), 0, @cos(angle));
        try prims.strut(a, &shell, d.scale(3.2).add(Vec3.init(0, 6, 0)), d.scale(8.5), Vec3.unit_y, 0.6, 0.9, .paint_accent);
    }
    // Corrupted ground disc.
    var disc = [_]Vec2{ .{ .x = 0, .y = 0.05 }, .{ .x = 0, .y = 0.2 }, .{ .x = 12, .y = 0.08 }, .{ .x = 12, .y = 0.0 } };
    std.mem.reverse(Vec2, &disc);
    try prims.lathe(a, &shell, &disc, 24, .{}, .paint_accent);
    // Glowing rings.
    for ([_]f32{ 4, 10, 16, 21 }) |y| {
        const t = y / spire_height;
        const r = 4.2 * std.math.pow(f32, 1 - t, 1.6) + 0.35;
        var ring: [8]Vec2 = undefined;
        for (&ring, 0..) |*p, i| {
            const k = @as(f32, @floatFromInt(i)) / 8.0 * m.tau;
            p.* = .{ .x = r + 0.12 * @cos(k), .y = y + 0.22 * @sin(k) };
        }
        try prims.lathe(a, &glow, &ring, 24, .{}, .emissive);
    }
    return finish(a, &shell, &glow);
}

/// A fortified Hive installation grown around an elongated egg tower. Its walls are
/// biomineral ribs over a metal frame; corner emplacements carry outward-facing lasers.
pub fn base(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);

    // Central egg, rooted into the courtyard and narrowing to a sealed crown.
    var egg: [17]Vec2 = undefined;
    for (&egg, 0..) |*p, i| {
        const t = @as(f32, @floatFromInt(i)) / 16.0;
        const round = @sqrt(@max(0, 1 - std.math.pow(f32, 2 * t - 1, 2)));
        p.* = .{ .x = 13.5 * round * (0.68 + 0.42 * t), .y = 3 + 31 * t };
    }
    try prims.lathe(a, &shell, &egg, 24, .{}, .paint);
    // Tall reinforcing ribs make the organic shell read as engineered architecture.
    for (0..12) |i| {
        const angle = @as(f32, @floatFromInt(i)) * m.tau / 12;
        const x = @sin(angle);
        const z = @cos(angle);
        try prims.strut(a, &shell, Vec3.init(x * 7.5, 1, z * 7.5), Vec3.init(x * 12.5, 31, z * 12.5), Vec3.unit_y, 0.48, 0.62, .paint_accent);
    }
    // Four uneven growth bands bind the shell to the rib cage.
    for ([_]f32{ 7, 14, 22, 29 }) |y| {
        const t = (y - 3) / 31;
        const r = 13.5 * @sqrt(@max(0, 1 - std.math.pow(f32, 2 * t - 1, 2))) * (0.68 + 0.42 * t) + 0.32;
        var band: [8]Vec2 = undefined;
        for (&band, 0..) |*p, i| {
            const k = @as(f32, @floatFromInt(i)) / 8 * m.tau;
            p.* = .{ .x = r + 0.18 * @cos(k), .y = y + 0.28 * @sin(k) };
        }
        try prims.lathe(a, &glow, &band, 32, .{}, .emissive);
    }

    // Heavy perimeter walls, with a broad gate on the near side.
    const wall = [_][2]Vec3{
        .{ Vec3.init(-36, 5, -36), Vec3.init(-12, 5, -36) },
        .{ Vec3.init(12, 5, -36), Vec3.init(36, 5, -36) },
        .{ Vec3.init(-36, 5, 36), Vec3.init(36, 5, 36) },
        .{ Vec3.init(-36, 5, -12), Vec3.init(-36, 5, 36) },
        .{ Vec3.init(36, 5, -36), Vec3.init(36, 5, 36) },
    };
    for (wall) |ends| try prims.strut(a, &shell, ends[0], ends[1], Vec3.unit_y, 2.2, 5.2, .metal);
    // Tower-like bastions at the corners and fixed laser cannons trained outward.
    for ([_]f32{ -1, 1 }) |xside| for ([_]f32{ -1, 1 }) |zside| {
        const x = xside * 36;
        const z = zside * 36;
        try pod(a, &shell, Vec3.init(x, 7.2, z), 4.8, 3.2, .paint_accent);
        const outward = Vec3.init(xside, 0.05, zside).normalize();
        try prims.strut(a, &shell, Vec3.init(x, 8.5, z).add(outward.scale(2)), Vec3.init(x, 8.5, z).add(outward.scale(9)), Vec3.unit_y, 0.8, 0.8, .metal);
        try pod(a, &glow, Vec3.init(x, 8.5, z).add(outward.scale(9.1)), 0.95, 0.85, .emissive);
        // Emitter slit on each wall-facing bastion.
        try pod(a, &glow, Vec3.init(x, 9.7, z), 1.45, 0.22, .emissive);
    };
    // Lit seams along the walls and a broken-open gate threshold.
    for ([_][2]Vec3{
        .{ Vec3.init(-36, 10.5, -36), Vec3.init(-12, 10.5, -36) },
        .{ Vec3.init(12, 10.5, -36), Vec3.init(36, 10.5, -36) },
        .{ Vec3.init(-36, 10.5, 36), Vec3.init(36, 10.5, 36) },
        .{ Vec3.init(-36, 10.5, -36), Vec3.init(-36, 10.5, 36) },
        .{ Vec3.init(36, 10.5, -36), Vec3.init(36, 10.5, 36) },
    }) |ends| try prims.strut(a, &glow, ends[0], ends[1], Vec3.unit_y, 0.18, 0.18, .emissive);
    return finishPalette(a, &shell, &glow, .{ .paint = .{ 0.12, 0.115, 0.13 }, .accent = .{ 0.34, 0.22, 0.29 }, .lights = .{ 1, 0.16, 0.34 } });
}

/// A faceted gem (two pyramids) for pickups: 0.5 m tall, centred at the origin.
pub fn gem(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    const n = 6;
    const top = Vec3.init(0, 0.3, 0);
    const bottom = Vec3.init(0, -0.3, 0);
    for (0..n) |i| {
        const a0 = @as(f32, @floatFromInt(i)) / n * m.tau;
        const a1 = @as(f32, @floatFromInt(i + 1)) / n * m.tau;
        const p0 = Vec3.init(@cos(a0) * 0.2, 0, @sin(a0) * 0.2);
        const p1 = Vec3.init(@cos(a1) * 0.2, 0, @sin(a1) * 0.2);
        for ([_][3]Vec3{ .{ top, p1, p0 }, .{ bottom, p0, p1 } }) |tri| {
            const vertex_base = mesh.vertexCount();
            for (tri) |p| _ = try mesh.addVertex(a, .{ .pos = p, .material = .emissive });
            try mesh.addTri(a, vertex_base, vertex_base + 1, vertex_base + 2);
        }
    }
    mesh.computeNormals();
    const white: Designs.Palette = .{ .paint = .{ 1, 1, 1 }, .accent = .{ 1, 1, 1 }, .lights = .{ 1, 1, 1 } };
    return Designs.renderMesh(a, &mesh, white);
}

test "hive meshes and the gem build with sensible sizes" {
    const a = std.testing.allocator;
    inline for (.{ drone, sentinel, spire, base }) |build| {
        const pair = try build(a);
        defer pair.shell.deinit(a);
        defer pair.glow.deinit(a);
        try std.testing.expect(pair.shell.indices.len > 0 and pair.glow.indices.len > 0);
        for (pair.shell.vertices) |v| for (v.position) |c| try std.testing.expect(std.math.isFinite(c) and @abs(c) < 48);
    }
    const g = try gem(a);
    defer g.deinit(a);
    // Six sides, two pyramids: 12 triangles.
    try std.testing.expectEqual(@as(usize, 36), g.indices.len);
}
