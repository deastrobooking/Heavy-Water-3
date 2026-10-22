//! Modular orbital-combat scenery and the synthetic Hive interceptor. +Z is forward, +Y up.
const std = @import("std");
const m = @import("../character/math.zig");
const cm = @import("../character/mesh.zig");
const prims = @import("prims.zig");
const airfoil = @import("airfoil.zig");
const Designs = @import("Designs.zig");
const RenderMesh = @import("../render/Mesh.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Allocator = std.mem.Allocator;

pub const Pair = struct { shell: RenderMesh, glow: RenderMesh };
const palette: Designs.Palette = .{ .paint = .{ 0.34, 0.4, 0.47 }, .accent = .{ 0.07, 0.12, 0.18 }, .lights = .{ 0.14, 0.62, 1.0 } };
const arena_palette: Designs.Palette = .{ .paint = .{ 0.2, 0.31, 0.4 }, .accent = .{ 0.045, 0.085, 0.13 }, .lights = .{ 0.12, 0.8, 1.0 } };
const planet_palette: Designs.Palette = .{ .paint = .{ 0.055, 0.2, 0.48 }, .accent = .{ 0.14, 0.48, 0.31 }, .lights = .{ 0.38, 0.72, 1.0 } };
const starwing_palette: Designs.Palette = .{ .paint = .{ 0.72, 0.84, 0.9 }, .accent = .{ 0.14, 0.37, 0.57 }, .lights = .{ 0.25, 0.95, 1.0 } };
const bulwark_palette: Designs.Palette = .{ .paint = .{ 0.48, 0.51, 0.47 }, .accent = .{ 0.32, 0.19, 0.09 }, .lights = .{ 1.0, 0.58, 0.18 } };
const lancer_palette: Designs.Palette = .{ .paint = .{ 0.24, 0.31, 0.38 }, .accent = .{ 0.055, 0.09, 0.14 }, .lights = .{ 0.22, 0.78, 1.0 } };
const station_palette: Designs.Palette = .{ .paint = .{ 0.54, 0.61, 0.66 }, .accent = .{ 0.11, 0.2, 0.27 }, .lights = .{ 0.23, 0.9, 1.0 } };

fn ellipsoid(a: Allocator, mesh: *cm.Mesh, center: Vec3, radii: Vec3, material: cm.Material) !void {
    var profile: [14]Vec2 = undefined;
    for (&profile, 0..) |*point, i| {
        const angle = @as(f32, @floatFromInt(i)) / 13 * m.pi - m.pi / 2;
        point.* = .{ .x = @cos(angle), .y = @sin(angle) };
    }
    try prims.lathe(a, mesh, &profile, 20, .{ .translation = center, .scale = radii }, material);
}

fn ellipsoidRotated(a: Allocator, mesh: *cm.Mesh, center: Vec3, radii: Vec3, rotation: Quat, material: cm.Material) !void {
    var profile: [14]Vec2 = undefined;
    for (&profile, 0..) |*point, i| {
        const angle = @as(f32, @floatFromInt(i)) / 13 * m.pi - m.pi / 2;
        point.* = .{ .x = @cos(angle), .y = @sin(angle) };
    }
    try prims.lathe(a, mesh, &profile, 24, .{ .translation = center, .rotation = rotation, .scale = radii }, material);
}

fn body(a: Allocator, mesh: *cm.Mesh, material: cm.Material) !void {
    const radii = [_]f32{ 0.12, 0.32, 0.5, 0.56, 0.49, 0.38, 0.27, 0.18 };
    var profile: [10]Vec2 = undefined;
    profile[0] = .{ .x = 0, .y = -4.8 };
    for (radii, 0..) |radius, i| profile[i + 1] = .{ .x = radius, .y = m.lerp(-4.8, 4.8, @as(f32, @floatFromInt(i)) / 7) };
    profile[9] = .{ .x = 0, .y = 4.8 };
    try prims.lathe(a, mesh, &profile, 24, .{ .rotation = Quat.fromAxisAngle(Vec3.unit_x, m.pi / 2) }, material);
}

fn finish(a: Allocator, shell: *cm.Mesh, glow: *cm.Mesh, colors: Designs.Palette) !Pair {
    shell.computeNormals();
    glow.computeNormals();
    const solid = try Designs.renderMesh(a, shell, colors);
    errdefer solid.deinit(a);
    return .{ .shell = solid, .glow = try Designs.renderMesh(a, glow, colors) };
}

/// Compact synthetic interceptor: armored nose, swept planar wings, paired cannons and twin ion drives.
pub fn robotFighter(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    try body(a, &shell, .paint);
    try ellipsoid(a, &shell, Vec3.init(0, 0.43, 2.6), Vec3.init(0.35, 0.2, 1.5), .glass);
    try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("0012"), .span = 7.4, .root_chord = 2.8, .tip_chord = 0.45, .sweep = m.radians(32), .dihedral = m.radians(2), .root_le = Vec3.init(0, -0.12, 0.9), .material = .paint_accent });
    for ([_]f32{ -1, 1 }) |side| {
        // Twin stabilizer fins and cannon rails make the machine silhouette distinct from Hive wings.
        try prims.strut(a, &shell, Vec3.init(side * 0.52, 0.1, -2.7), Vec3.init(side * 1.05, 1.15, -4.2), Vec3.unit_y, 0.34, 0.16, .paint_accent);
        try prims.strut(a, &shell, Vec3.init(side * 0.47, -0.22, 0.2), Vec3.init(side * 2.85, -0.2, 3.45), Vec3.unit_y, 0.16, 0.15, .metal);
        try ellipsoid(a, &glow, Vec3.init(side * 0.32, 0.08, -4.45), Vec3.init(0.23, 0.2, 0.32), .emissive);
        try ellipsoid(a, &glow, Vec3.init(side * 3.35, 0.02, -0.45), Vec3.init(0.13, 0.1, 0.24), .emissive);
    }
    try ellipsoid(a, &glow, Vec3.init(0, 0.36, 4.32), Vec3.init(0.22, 0.14, 0.25), .emissive);
    return finish(a, &shell, &glow, palette);
}

/// A faster, needle-winged robot pursuit craft with paired forward lance emitters.
pub fn robotLancer(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    try body(a, &shell, .paint);
    try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("0008"), .span = 6.8, .root_chord = 2.1, .tip_chord = 0.18, .sweep = m.radians(57), .dihedral = m.radians(1), .root_le = Vec3.init(0, -0.1, 0.1), .material = .paint_accent });
    for ([_]f32{ -1, 1 }) |side| {
        try prims.strut(a, &shell, Vec3.init(side * 0.43, -0.17, 1.0), Vec3.init(side * 0.54, -0.18, 6.8), Vec3.unit_y, 0.15, 0.12, .metal);
        try ellipsoid(a, &glow, Vec3.init(side * 0.36, 0.05, -4.45), Vec3.init(0.2, 0.18, 0.32), .emissive);
        try ellipsoid(a, &glow, Vec3.init(side * 0.54, -0.18, 6.7), Vec3.init(0.16, 0.13, 0.22), .emissive);
    }
    return finish(a, &shell, &glow, lancer_palette);
}

/// Two allied fighter frames for the player hangar: a nimble wing and a broad assault ship.
pub fn playerFrame(a: Allocator, heavy: bool) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    try body(a, &shell, .paint);
    if (heavy) {
        try ellipsoid(a, &shell, Vec3.init(0, 0, -0.3), Vec3.init(0.78, 0.72, 3.1), .paint_accent);
        try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("0018"), .span = 9.8, .root_chord = 4.6, .tip_chord = 2.1, .sweep = m.radians(22), .dihedral = m.radians(-2), .root_le = Vec3.init(0, -0.2, 0.1), .material = .paint });
        for ([_]f32{ -1, 1 }) |side| {
            try prims.strut(a, &shell, Vec3.init(side * 0.9, 0.14, 1), Vec3.init(side * 1.1, 0.18, 6.1), Vec3.unit_y, 0.3, 0.28, .metal);
            try ellipsoid(a, &glow, Vec3.init(side * 0.58, 0.06, -4.5), Vec3.init(0.3, 0.26, 0.38), .emissive);
            try ellipsoid(a, &glow, Vec3.init(side * 4.85, 0, 0.3), Vec3.init(0.18, 0.12, 0.3), .emissive);
        }
        return finish(a, &shell, &glow, bulwark_palette);
    }
    try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("0010"), .span = 10.8, .root_chord = 3.0, .tip_chord = 0.24, .sweep = m.radians(34), .dihedral = m.radians(7), .root_le = Vec3.init(0, 0, 1.2), .material = .paint_accent });
    try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("0008"), .span = 3.5, .root_chord = 1.1, .tip_chord = 0.4, .sweep = m.radians(20), .dihedral = m.radians(2), .root_le = Vec3.init(0, 0.05, 4.2), .material = .paint });
    for ([_]f32{ -1, 1 }) |side| {
        try ellipsoid(a, &glow, Vec3.init(side * 0.39, 0.05, -4.45), Vec3.init(0.22, 0.2, 0.36), .emissive);
        try ellipsoid(a, &glow, Vec3.init(side * 5.2, 0, 0.5), Vec3.init(0.12, 0.1, 0.25), .emissive);
    }
    return finish(a, &shell, &glow, starwing_palette);
}

pub fn playerStarwing(a: Allocator) !Pair {
    return playerFrame(a, false);
}

pub fn playerBulwark(a: Allocator) !Pair {
    return playerFrame(a, true);
}

/// Two colossal Hive carriers: a living brood citadel and a robotic modular forge ark.
pub fn mothership(a: Allocator, robotic: bool) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    if (robotic) {
        try ellipsoid(a, &shell, Vec3.init(0, 0, -8), Vec3.init(78, 24, 116), .metal);
        try ellipsoid(a, &shell, Vec3.init(0, 12, 16), Vec3.init(44, 15, 86), .paint_accent);
        try prims.strut(a, &shell, Vec3.init(0, 5, -118), Vec3.init(0, 8, 125), Vec3.unit_y, 9, 8, .paint);
        for ([_]f32{ -1, 1 }) |side| {
            // Four visible flight decks cantilever from the keel, framing a robotic carrier silhouette.
            for ([_]f32{ -1, 1 }) |row| {
                const z = row * 48;
                try prims.strut(a, &shell, Vec3.init(side * 30, -7, z), Vec3.init(side * 118, -16, z - 8), Vec3.unit_y, 8, 5, .paint_accent);
                try ellipsoid(a, &glow, Vec3.init(side * 100, -10, z - 8), Vec3.init(11, 1.1, 28), .emissive);
                try prims.strut(a, &shell, Vec3.init(side * 98, -14, z - 8), Vec3.init(side * 98, -14, z + 18), Vec3.unit_x, 4, 3, .metal);
            }
            for ([_]f32{ -68, 0, 68 }) |z| {
                const tower = Vec3.init(side * 48, 26, z);
                try ellipsoid(a, &shell, tower, Vec3.init(13, 9, 16), .metal);
                try prims.strut(a, &shell, tower, tower.add(Vec3.init(0, 12, 18)), Vec3.unit_y, 3.6, 3.2, .paint);
            }
            try ellipsoid(a, &glow, Vec3.init(side * 72, 7, -10), Vec3.init(3.2, 2.6, 54), .emissive);
        }
        for ([_]f32{ 78, 38, -2, -42, -82 }) |z| try ellipsoid(a, &glow, Vec3.init(0, -20, z), Vec3.init(13, 1.4, 15), .emissive);
        return finish(a, &shell, &glow, .{ .paint = .{ 0.27, 0.34, 0.42 }, .accent = .{ 0.045, 0.075, 0.11 }, .lights = .{ 0.12, 0.62, 1 } });
    }
    // Brood Crown: thorax and abdomen beneath overlapping carapace wings, mandibles and launch sacs.
    try ellipsoid(a, &shell, Vec3.init(0, 0, -27), Vec3.init(34, 23, 88), .paint);
    try ellipsoid(a, &shell, Vec3.init(0, 4, 52), Vec3.init(28, 22, 46), .paint_accent);
    try ellipsoid(a, &shell, Vec3.init(0, 4, 89), Vec3.init(18, 16, 22), .paint);
    for ([_]f32{ -1, 1 }) |side| {
        try ellipsoid(a, &shell, Vec3.init(side * 34, 19, -25), Vec3.init(36, 8, 86), .paint_accent);
        try ellipsoid(a, &shell, Vec3.init(side * 71, 15, -27), Vec3.init(38, 1.3, 58), .glass);
        try prims.strut(a, &shell, Vec3.init(side * 13, -11, 64), Vec3.init(side * 38, -34, 27), Vec3.unit_z, 5.5, 4.1, .paint_accent);
        try prims.strut(a, &shell, Vec3.init(side * 38, -34, 27), Vec3.init(side * 55, -44, -4), Vec3.unit_z, 3.8, 3.3, .paint);
        try prims.strut(a, &shell, Vec3.init(side * 18, -13, -18), Vec3.init(side * 51, -38, -50), Vec3.unit_z, 5.2, 3.8, .paint_accent);
        try prims.strut(a, &shell, Vec3.init(side * 51, -38, -50), Vec3.init(side * 63, -47, -83), Vec3.unit_z, 3.5, 3, .paint);
        try prims.strut(a, &shell, Vec3.init(side * 13, -7, 95), Vec3.init(side * 25, -14, 115), Vec3.unit_y, 4, 3.1, .metal);
        try ellipsoid(a, &glow, Vec3.init(side * 15, 8, 95), Vec3.init(4.6, 3.6, 4.2), .emissive);
    }
    for ([_]f32{ 62, 28, -8, -44, -78 }) |z| try ellipsoid(a, &glow, Vec3.init(0, -20, z), Vec3.init(15, 2.2, 17), .emissive);
    return finish(a, &shell, &glow, .{ .paint = .{ 0.31, 0.065, 0.045 }, .accent = .{ 0.12, 0.025, 0.035 }, .lights = .{ 1, 0.2, 0.075 } });
}

pub fn broodCrown(a: Allocator) !Pair {
    return mothership(a, false);
}

pub fn robotForgeArk(a: Allocator) !Pair {
    return mothership(a, true);
}

/// Civilian orbital service hub: a rotating habitation ring, four docking spurs, and solar wings.
pub fn orbitalServiceHub(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);

    try ellipsoid(a, &shell, Vec3.init(0, 0, 0), Vec3.init(15, 15, 28), .metal);
    try ellipsoid(a, &shell, Vec3.init(0, 0, 0), Vec3.init(9, 9, 30), .paint_accent);
    // Segment the habitat ring into structural bays so the silhouette reads at a distance.
    const ring_radius: f32 = 49;
    for (0..16) |i| {
        const angle = @as(f32, @floatFromInt(i)) * (2 * m.pi / 16);
        const next = @as(f32, @floatFromInt(i + 1)) * (2 * m.pi / 16);
        const p = Vec3.init(@cos(angle) * ring_radius, @sin(angle) * ring_radius, 0);
        const q = Vec3.init(@cos(next) * ring_radius, @sin(next) * ring_radius, 0);
        try prims.strut(a, &shell, p, q, Vec3.unit_z, 3.5, 3.5, .paint);
        if (i % 2 == 0) {
            try ellipsoid(a, &shell, p, Vec3.init(5.5, 5.5, 7), .paint_accent);
            try ellipsoid(a, &glow, p.add(Vec3.init(0, 0, 5.6)), Vec3.init(3.2, 3.2, 1.1), .emissive);
        }
        try prims.strut(a, &shell, Vec3.init(p.x * 0.36, p.y * 0.36, 0), p, Vec3.unit_z, 1.8, 1.8, .metal);
    }
    // Axial docking berths and approach beacons make the hub feel useful as a route stop.
    for ([_]f32{ -1, 1 }) |side| {
        const nose_z = side * 43;
        try prims.strut(a, &shell, Vec3.init(0, 0, side * 13), Vec3.init(0, 0, side * 61), Vec3.unit_y, 4.2, 4.2, .paint);
        try ellipsoid(a, &shell, Vec3.init(0, 0, nose_z), Vec3.init(9, 8, 12), .paint_accent);
        try ellipsoid(a, &glow, Vec3.init(0, 0, side * 59), Vec3.init(4.2, 2.4, 1.2), .emissive);
        for ([_]f32{ -1, 1 }) |wing| {
            const root = Vec3.init(wing * 12, 0, side * 4);
            const tip = Vec3.init(wing * 72, 0, side * 4);
            try prims.strut(a, &shell, root, tip, Vec3.unit_y, 2.4, 2.4, .metal);
            try ellipsoid(a, &shell, Vec3.init(wing * 48, 0, side * 4), Vec3.init(25, 1.2, 13), .paint_accent);
            for (0..5) |panel| {
                const x = wing * (@as(f32, @floatFromInt(panel)) * 10 + 30);
                try prims.strut(a, &shell, Vec3.init(x, 0.8, side * -8), Vec3.init(x, 0.8, side * 16), Vec3.unit_x, 0.7, 0.5, .metal);
            }
            try prims.lightStrip(a, &glow, &.{ root, tip }, Vec3.unit_y, 0.6, 0.7, .emissive);
        }
    }
    for ([_]f32{ -1, 1 }) |side| {
        try ellipsoid(a, &glow, Vec3.init(side * 13, 1, 0), Vec3.init(1.4, 1.4, 13), .emissive);
        try ellipsoid(a, &shell, Vec3.init(side * 14, 0, -15), Vec3.init(5, 5, 8), .metal);
    }
    return finish(a, &shell, &glow, station_palette);
}

/// Open 240 m square interception ring, with four service gates and emissive boundary rails.
pub fn interceptionRing(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const half: f32 = 120;
    const rail_y: f32 = 1.2;
    // Sparse truss edges leave the center open for flight and keep the combat bounds readable.
    for ([_]f32{ -1, 1 }) |side| {
        const x = side * half;
        try prims.strut(a, &shell, Vec3.init(x, 0, -half), Vec3.init(x, 0, half), Vec3.unit_y, 1.4, 1.2, .metal);
        try prims.strut(a, &shell, Vec3.init(-half, 0, x), Vec3.init(half, 0, x), Vec3.unit_y, 1.4, 1.2, .metal);
        try prims.lightStrip(a, &glow, &.{ Vec3.init(x, rail_y, -half), Vec3.init(x, rail_y, half) }, Vec3.unit_y, 1.2, 0.48, .emissive);
        try prims.lightStrip(a, &glow, &.{ Vec3.init(-half, rail_y, x), Vec3.init(half, rail_y, x) }, Vec3.unit_y, 1.2, 0.48, .emissive);
    }
    // Reinforced corner nodes tie the rails together and form unmistakable gate landmarks.
    for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sz| {
        const x = sx * half;
        const z = sz * half;
        try ellipsoid(a, &shell, Vec3.init(x, 0, z), Vec3.init(8, 3, 8), .metal);
        try prims.strut(a, &shell, Vec3.init(x, 0, z), Vec3.init(x, 18, z), Vec3.unit_z, 1.5, 1.5, .paint_accent);
        try prims.strut(a, &shell, Vec3.init(x - sx * 9, 18, z), Vec3.init(x + sx * 9, 18, z), Vec3.unit_z, 1.3, 1.3, .paint);
        try ellipsoid(a, &glow, Vec3.init(x, 18, z), Vec3.init(2.2, 2.2, 2.2), .emissive);
    };
    // Center beacon provides a distant orientation anchor without blocking the combat lane.
    try ellipsoid(a, &shell, Vec3.init(0, -16, 0), Vec3.init(12, 2, 12), .metal);
    try prims.strut(a, &shell, Vec3.init(0, -16, 0), Vec3.init(0, -2, 0), Vec3.unit_x, 1.1, 1.1, .paint_accent);
    try ellipsoid(a, &glow, Vec3.init(0, -1, 0), Vec3.init(2.4, 2.4, 2.4), .emissive);
    return finish(a, &shell, &glow, arena_palette);
}

/// Gaia's distant ocean world, used as the orbital arena's visual horizon.
pub fn planetBackdrop(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    var profile: [24]Vec2 = undefined;
    for (&profile, 0..) |*point, i| {
        const angle = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(profile.len - 1)) * m.pi - m.pi / 2;
        point.* = .{ .x = @cos(angle), .y = @sin(angle) };
    }
    try prims.lathe(a, &mesh, &profile, 64, .{}, .paint);
    // Broad low relief patches break the blue sphere into legible ocean and land at orbit scale.
    const land = [_]struct { lat: f32, lon: f32, width: f32, length: f32 }{
        .{ .lat = 0.42, .lon = -0.72, .width = 0.28, .length = 0.16 },
        .{ .lat = -0.08, .lon = -0.28, .width = 0.18, .length = 0.34 },
        .{ .lat = 0.26, .lon = 0.54, .width = 0.31, .length = 0.19 },
        .{ .lat = -0.46, .lon = 0.84, .width = 0.22, .length = 0.14 },
        .{ .lat = 0.72, .lon = 1.92, .width = 0.38, .length = 0.12 },
        .{ .lat = -0.58, .lon = -2.1, .width = 0.3, .length = 0.1 },
        .{ .lat = 0.02, .lon = 2.82, .width = 0.2, .length = 0.26 },
    };
    for (land) |patch| {
        const normal = Vec3.init(@cos(patch.lat) * @sin(patch.lon), @sin(patch.lat), @cos(patch.lat) * @cos(patch.lon));
        try ellipsoidRotated(a, &mesh, normal.scale(1.002), Vec3.init(patch.width, 0.009, patch.length), Quat.fromTo(Vec3.unit_y, normal), .paint_accent);
    }
    mesh.computeNormals();
    return Designs.renderMesh(a, &mesh, planet_palette);
}

test "orbital ring and synthetic interceptor build finite, nonempty meshes" {
    const allocator = std.testing.allocator;
    inline for (.{ robotFighter, interceptionRing }) |build| {
        const pair = try build(allocator);
        defer pair.shell.deinit(allocator);
        defer pair.glow.deinit(allocator);
        try std.testing.expect(pair.shell.indices.len > 0 and pair.glow.indices.len > 0);
        for (pair.shell.vertices) |vertex| for (vertex.position) |coordinate| try std.testing.expect(std.math.isFinite(coordinate));
        for (pair.glow.vertices) |vertex| for (vertex.position) |coordinate| try std.testing.expect(std.math.isFinite(coordinate));
    }
}
