//! Fully 3D Scalari dragon-armor aircraft. The fighters use swept armored wings, horned prow
//! plates, overlapping dorsal scales and segmented tails. Two large ark classes carry brood
//! bays and capital defenses. +Z is forward and +Y is up, matching ShipMeshes.zig.
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
pub const FighterClass = enum { ember_wyrm, void_lance, dreadclaw };
pub const fighter_count = @typeInfo(FighterClass).@"enum".fields.len;
pub const mothership_count = 2;

const Palette = struct { paint: [3]f32, accent: [3]f32, lights: [3]f32 };
const palettes = [_]Palette{
    // Ember Wyrm: Scalari war-caste crimson scales over obsidian armor.
    .{ .paint = .{ 0.52, 0.035, 0.055 }, .accent = .{ 0.035, 0.025, 0.04 }, .lights = .{ 1.0, 0.19, 0.055 } },
    // Void Lance: amethyst armor and acid-green reactor light.
    .{ .paint = .{ 0.19, 0.075, 0.34 }, .accent = .{ 0.025, 0.035, 0.045 }, .lights = .{ 0.48, 1.0, 0.12 } },
    // Dreadclaw: blackened violet plates with ember-orange and green systems.
    .{ .paint = .{ 0.11, 0.045, 0.16 }, .accent = .{ 0.38, 0.12, 0.035 }, .lights = .{ 0.57, 0.96, 0.08 } },
    .{ .paint = .{ 0.27, 0.025, 0.045 }, .accent = .{ 0.025, 0.02, 0.035 }, .lights = .{ 0.72, 0.13, 0.9 } },
    .{ .paint = .{ 0.16, 0.07, 0.26 }, .accent = .{ 0.04, 0.16, 0.075 }, .lights = .{ 1.0, 0.3, 0.045 } },
};

fn ellipsoid(a: Allocator, mesh: *cm.Mesh, center: Vec3, radii: Vec3, rotation: Quat, material: cm.Material) !void {
    var profile: [14]Vec2 = undefined;
    for (&profile, 0..) |*point, i| {
        const angle = @as(f32, @floatFromInt(i)) / 13.0 * m.pi - m.pi / 2.0;
        point.* = .{ .x = @cos(angle), .y = @sin(angle) };
    }
    try prims.lathe(a, mesh, &profile, 20, .{ .translation = center, .rotation = rotation, .scale = radii }, material);
}

fn body(a: Allocator, mesh: *cm.Mesh, radii: []const f32, z0: f32, z1: f32, material: cm.Material) !void {
    var profile: [20]Vec2 = undefined;
    profile[0] = .{ .x = 0, .y = z0 };
    for (radii, 0..) |radius, i| {
        profile[i + 1] = .{ .x = radius, .y = m.lerp(z0, z1, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(radii.len - 1))) };
    }
    profile[radii.len + 1] = .{ .x = 0, .y = z1 };
    try prims.lathe(a, mesh, profile[0 .. radii.len + 2], 28, .{ .rotation = Quat.fromAxisAngle(Vec3.unit_x, m.pi / 2) }, material);
}

fn finish(a: Allocator, shell: *cm.Mesh, glow: *cm.Mesh, palette: Palette) !Pair {
    shell.computeNormals();
    glow.computeNormals();
    const design_palette: Designs.Palette = .{ .paint = palette.paint, .accent = palette.accent, .lights = palette.lights };
    const solid = try Designs.renderMesh(a, shell, design_palette);
    errdefer solid.deinit(a);
    return .{ .shell = solid, .glow = try Designs.renderMesh(a, glow, design_palette) };
}

fn lightSpine(a: Allocator, glow: *cm.Mesh, scale: f32) !void {
    const points = [_]Vec3{ Vec3.init(0, 0.67 * scale, 4.5 * scale), Vec3.init(0, 0.58 * scale, 2 * scale), Vec3.init(0, 0.48 * scale, -1 * scale), Vec3.init(0, 0.34 * scale, -4 * scale) };
    try prims.lightStrip(a, glow, &points, Vec3.unit_y, 0.11 * scale, 0.06 * scale, .emissive);
}

fn fighter(a: Allocator, class: FighterClass) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const palette = palettes[@intFromEnum(class)];
    const radii = [_]f32{ 0.08, 0.27, 0.48, 0.72, 0.83, 0.88, 0.86, 0.79, 0.68, 0.54, 0.38, 0.2 };
    try body(a, &shell, &radii, -6.3, 6.3, .paint);
    // Six crown scales make the armored spine read clearly from above and at distance.
    for (0..6) |i| {
        const z = -3.7 + @as(f32, @floatFromInt(i)) * 1.28;
        const r: f32 = if (i < 2) 0.48 else 0.62;
        try ellipsoid(a, &shell, Vec3.init(0, 0.69, z), Vec3.init(r, 0.22, 0.7), Quat.identity, if (i % 2 == 0) .paint_accent else .paint);
    }
    // Two swept, talon-ended armored wings. The classes trade agility for span and protection.
    const span: f32 = switch (class) {
        .ember_wyrm => 8.6,
        .void_lance => 10.4,
        .dreadclaw => 13.2,
    };
    const root_chord: f32 = switch (class) {
        .ember_wyrm => 3.6,
        .void_lance => 4.4,
        .dreadclaw => 5.7,
    };
    const tip_chord: f32 = if (class == .dreadclaw) 1.15 else 0.45;
    const sweep: f32 = switch (class) {
        .ember_wyrm => 52,
        .void_lance => 38,
        .dreadclaw => 28,
    };
    try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("0010"), .span = span, .root_chord = root_chord, .tip_chord = tip_chord, .sweep = m.radians(sweep), .dihedral = m.radians(5), .root_le = Vec3.init(0, 0.05, 0.8), .material = .paint_accent });
    for ([_]f32{ -1, 1 }) |side| {
        // Horns sweep back from the brow; cheek plates and wing-root pauldrons frame a dragon skull.
        try prims.strut(a, &shell, Vec3.init(side * 0.42, 0.58, 4.8), Vec3.init(side * 0.73, 1.18, 3.35), Vec3.unit_y, 0.28, 0.24, .paint_accent);
        try ellipsoid(a, &shell, Vec3.init(side * 0.55, -0.14, 4.7), Vec3.init(0.34, 0.3, 1.0), Quat.fromAxisAngle(Vec3.unit_x, 0.25), .metal);
        try ellipsoid(a, &shell, Vec3.init(side * 1.25, 0.2, 0.75), Vec3.init(0.8, 0.33, 1.55), Quat.fromAxisAngle(Vec3.unit_y, side * 0.2), .paint);
        // Segmented tail armor and a forked rudder.
        for (0..4) |segment| {
            const z = -2.8 - @as(f32, @floatFromInt(segment)) * 0.76;
            try ellipsoid(a, &shell, Vec3.init(0, 0.05, z), Vec3.init(0.34 - 0.04 * @as(f32, @floatFromInt(segment)), 0.31, 0.47), Quat.identity, if (segment % 2 == 0) .paint_accent else .paint);
        }
        try prims.strut(a, &shell, Vec3.init(side * 0.12, 0.1, -5.0), Vec3.init(side * 0.78, 0.1, -6.15), Vec3.unit_y, 0.3, 0.15, .paint_accent);
        // Eye slit / sensor glow sits at the snout, visible from the front and side.
        try ellipsoid(a, &glow, Vec3.init(side * 0.29, 0.36, 5.55), Vec3.init(0.16, 0.1, 0.36), Quat.fromAxisAngle(Vec3.unit_y, side * 0.12), .emissive);
    }
    if (class == .void_lance) {
        // Forward lance rails are the signature weapon silhouette of the interceptor-bomber.
        for ([_]f32{ -1, 1 }) |side| try prims.strut(a, &shell, Vec3.init(side * 0.52, -0.25, 1.7), Vec3.init(side * 0.72, -0.3, 6.5), Vec3.unit_y, 0.16, 0.18, .metal);
    } else if (class == .dreadclaw) {
        // Heavy fighter carries paired dorsal cannons and thicker shoulder plates.
        for ([_]f32{ -1, 1 }) |side| {
            try prims.strut(a, &shell, Vec3.init(side * 0.82, 0.47, 1.0), Vec3.init(side * 1.15, 0.42, 5.8), Vec3.unit_y, 0.26, 0.24, .metal);
            try ellipsoid(a, &shell, Vec3.init(side * 2.2, 0.42, 0.25), Vec3.init(1.0, 0.4, 1.75), Quat.fromAxisAngle(Vec3.unit_y, side * 0.22), .paint_accent);
        }
    }
    try lightSpine(a, &glow, 1);
    return finish(a, &shell, &glow, palette);
}

pub fn emberWyrm(a: Allocator) !Pair {
    return fighter(a, .ember_wyrm);
}

pub fn voidLance(a: Allocator) !Pair {
    return fighter(a, .void_lance);
}

pub fn dreadclaw(a: Allocator) !Pair {
    return fighter(a, .dreadclaw);
}

fn ark(a: Allocator, worldcoil: bool) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const palette = palettes[if (worldcoil) 4 else 3];
    const radii = [_]f32{ 1, 4, 8, 12, 15, 17, 18, 18, 16, 13, 9, 5 };
    try body(a, &shell, &radii, -66, 61, .paint);
    // Long armored neck and skull-like command prow.
    try ellipsoid(a, &shell, Vec3.init(0, 0.8, 59), Vec3.init(12, 9, 18), Quat.identity, .paint_accent);
    try airfoil.buildWing(a, &shell, .{ .section = airfoil.Naca4.fromDigits("0014"), .span = if (worldcoil) 150 else 118, .root_chord = 56, .tip_chord = 12, .sweep = m.radians(if (worldcoil) 24 else 35), .dihedral = m.radians(3), .root_le = Vec3.init(0, 8, 9), .material = .paint_accent });
    for ([_]f32{ -1, 1 }) |side| {
        try prims.strut(a, &shell, Vec3.init(side * 7, 4, 67), Vec3.init(side * 13, 12, 47), Vec3.unit_y, 3.2, 2.4, .paint_accent);
        try ellipsoid(a, &glow, Vec3.init(side * 5, 1.2, 70), Vec3.init(2.1, 1.7, 2.8), Quat.identity, .emissive);
        // The armored wing's outer scythe and two side-mounted flak towers.
        try prims.strut(a, &shell, Vec3.init(side * 40, 6, 5), Vec3.init(side * 70, 11, -23), Vec3.unit_y, 4.2, 2.8, .metal);
        for ([_]f32{ 16, -24 }) |z| {
            const tower = Vec3.init(side * 14, 16, z);
            try ellipsoid(a, &shell, tower, Vec3.init(5, 2.8, 5), Quat.identity, .metal);
            try prims.strut(a, &shell, tower.add(Vec3.init(0, 1, 0)), tower.add(Vec3.init(0, 4, 8)), Vec3.unit_y, 1.5, 1.3, .metal);
        }
        // Hanging talons are both landing armor and city-scale docking pylons.
        try prims.strut(a, &shell, Vec3.init(side * 9, -8, 10), Vec3.init(side * 16, -19, -4), Vec3.unit_z, 2.4, 2.0, .paint_accent);
    }
    // Armored scale rows along the upper back, with four independent hangar/core glow wells.
    for (0..9) |i| {
        const z = -48 + @as(f32, @floatFromInt(i)) * 12;
        const r: f32 = 11.5 - 0.08 * @abs(z);
        try ellipsoid(a, &shell, Vec3.init(0, 15.8, z), Vec3.init(@max(3, r), 2.8, 6.5), Quat.identity, if (i % 2 == 0) .paint_accent else .paint);
    }
    for ([_]f32{ 22, -6, -34, -52 }) |z| {
        try ellipsoid(a, &glow, Vec3.init(0, -15.3, z), Vec3.init(5.5, 0.65, 7), Quat.identity, .emissive);
    }
    const spine = [_]Vec3{ Vec3.init(0, 17, -53), Vec3.init(0, 18.2, -25), Vec3.init(0, 18.5, 5), Vec3.init(0, 17.5, 35), Vec3.init(0, 12, 62) };
    try prims.lightStrip(a, &glow, &spine, Vec3.unit_y, 1.4, 0.9, .emissive);
    return finish(a, &shell, &glow, palette);
}

/// The Throne Serpent is the Scalari command carrier and the final-capital boss ship.
pub fn throneSerpent(a: Allocator) !Pair {
    return ark(a, false);
}

/// The Worldcoil Ark transports brood foundries, colony seed stock and an expedition fleet.
pub fn worldcoilArk(a: Allocator) !Pair {
    return ark(a, true);
}

test "Scalari fighter and mothership families build bounded full-3D shell and glow meshes" {
    const allocator = std.testing.allocator;
    inline for (.{ emberWyrm, voidLance, dreadclaw, throneSerpent, worldcoilArk }) |build| {
        const pair = try build(allocator);
        defer pair.shell.deinit(allocator);
        defer pair.glow.deinit(allocator);
        try std.testing.expect(pair.shell.indices.len > 0 and pair.glow.indices.len > 0);
        for (pair.shell.vertices) |vertex| for (vertex.position) |coordinate| {
            try std.testing.expect(std.math.isFinite(coordinate));
        };
        for (pair.glow.vertices) |vertex| for (vertex.position) |coordinate| {
            try std.testing.expect(std.math.isFinite(coordinate));
        };
    }
}
