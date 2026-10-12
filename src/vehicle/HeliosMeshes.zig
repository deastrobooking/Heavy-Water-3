//! Rotating habitat hardware and the Rand Corporation's Mother construction ark.
//! These are early art assets, not structurally validated vehicle designs. +Z is the long axis.
const std = @import("std");
const m = @import("../character/math.zig");
const cm = @import("../character/mesh.zig");
const prims = @import("prims.zig");
const Designs = @import("Designs.zig");
const RenderMesh = @import("../render/Mesh.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Allocator = std.mem.Allocator;

pub const Pair = struct { shell: RenderMesh, glow: RenderMesh };
const axis_z = Quat.fromAxisAngle(Vec3.unit_x, m.pi * 0.5);
const habitat_palette: Designs.Palette = .{
    .paint = .{ 0.55, 0.61, 0.64 },
    .accent = .{ 0.11, 0.20, 0.25 },
    .lights = .{ 0.20, 0.93, 0.78 },
};
const mother_palette: Designs.Palette = .{
    .paint = .{ 0.62, 0.32, 0.12 },
    .accent = .{ 0.12, 0.20, 0.26 },
    .lights = .{ 1.0, 0.57, 0.20 },
};

fn finish(a: Allocator, shell: *cm.Mesh, glow: *cm.Mesh, palette: Designs.Palette) !Pair {
    shell.computeNormals();
    glow.computeNormals();
    const solid = try Designs.renderMesh(a, shell, palette);
    errdefer solid.deinit(a);
    return .{ .shell = solid, .glow = try Designs.renderMesh(a, glow, palette) };
}

fn revolve(a: Allocator, mesh: *cm.Mesh, profile: []const Vec2, segments: u32, origin: Vec3, mat: cm.Material) !void {
    try prims.lathe(a, mesh, profile, segments, .{ .translation = origin, .rotation = axis_z }, mat);
}

fn ring(a: Allocator, mesh: *cm.Mesh, radius: f32, z: f32, width: f32, depth: f32, origin: Vec3, mat: cm.Material) !void {
    const loop = [_]Vec2{
        .{ .x = radius - width, .y = z - depth },
        .{ .x = radius + width, .y = z - depth },
        .{ .x = radius + width, .y = z + depth },
        .{ .x = radius - width, .y = z + depth },
    };
    try revolve(a, mesh, &loop, 64, origin, mat);
}

fn drum(a: Allocator, shell: *cm.Mesh, glow: *cm.Mesh, origin: Vec3, radius: f32, length: f32, panel_count: u32, rows: u32, mother: bool) !void {
    const half = length * 0.5;
    const hull = [_]Vec2{
        .{ .x = radius * 0.86, .y = -half },
        .{ .x = radius, .y = -half + radius * 0.16 },
        .{ .x = radius, .y = half - radius * 0.16 },
        .{ .x = radius * 0.86, .y = half },
        .{ .x = 0, .y = half },
        .{ .x = 0, .y = -half },
    };
    try revolve(a, shell, &hull, 56, origin, .paint);

    // Replaceable shield cassettes stand off the pressure hull. Their gaps expose the
    // structural hoops and service lights instead of reading as one featureless tin can.
    const sectors = panel_count;
    const columns = rows;
    for (0..sectors) |sector| {
        const angle = @as(f32, @floatFromInt(sector)) / @as(f32, @floatFromInt(sectors)) * m.tau;
        const radial = Vec3.init(@cos(angle), @sin(angle), 0);
        const tangent = Vec3.init(-@sin(angle), @cos(angle), 0);
        for (0..columns) |column| {
            const z = -half + (asF32(column) + 0.5) * length / asF32(columns);
            const panel_center = origin.add(radial.scale(radius + 1.8)).add(Vec3.init(0, 0, z));
            const tangential = radius * m.tau / asF32(sectors) * 0.43;
            const axial = length / asF32(columns) * 0.43;
            try prims.box(a, shell, panel_center, radial, tangent, Vec3.unit_z, Vec3.init(2.2, tangential, axial), if ((sector + column) % 5 == 0) .paint_accent else .paint);
        }
        // Continuous amber/teal seams make the drum's repeating pressure cells readable.
        if (sector % 2 == 0) {
            const p = [_]Vec3{
                origin.add(radial.scale(radius + 4.5)).add(Vec3.init(0, 0, -half + 8)),
                origin.add(radial.scale(radius + 4.5)).add(Vec3.init(0, 0, half - 8)),
            };
            try prims.lightStrip(a, glow, &p, radial, if (mother) 1.8 else 1.0, 0.32, .emissive);
        }
    }

    const hoop_step = length / 10;
    for (0..11) |i| {
        const z = -half + asF32(i) * hoop_step;
        try ring(a, shell, radius + 3.2, z, if (i == 0 or i == 10) 4 else 2.0, if (i == 0 or i == 10) 3.0 else 1.4, origin, .metal);
        if (i % 2 == 0) try ring(a, glow, radius + 5.5, z, 0.7, 0.36, origin, .emissive);
    }

    // Two open structural end rings expose the central nonrotating access spine.
    for ([_]f32{ -half, half }) |z| {
        try ring(a, shell, radius + 5, z, 7, 5, origin, .paint_accent);
        try ring(a, glow, radius + 13, z, 0.9, 0.45, origin, .emissive);
        for (0..12) |spoke| {
            const angle = asF32(spoke) / 12 * m.tau;
            const outer = origin.add(Vec3.init(@cos(angle) * radius, @sin(angle) * radius, z));
            const inner = origin.add(Vec3.init(@cos(angle) * 12, @sin(angle) * 12, z));
            try prims.strut(a, shell, inner, outer, Vec3.unit_z, if (mother) 4.2 else 2.6, if (mother) 3.2 else 2.0, .metal);
        }
    }

    // A clear visual cue for the axial nonrotating transfer/service spine.
    try revolve(a, shell, &.{ .{ .x = 10, .y = -half - 48 }, .{ .x = 10, .y = half + 48 }, .{ .x = 0, .y = half + 48 }, .{ .x = 0, .y = -half - 48 } }, 32, origin, .metal);
    try ring(a, glow, 10.7, -half - 34, 0.8, 1.4, origin, .emissive);
    try ring(a, glow, 10.7, half + 34, 0.8, 1.4, origin, .emissive);

    // Mirror/light collector booms, deliberately outside the rotating drum envelope.
    for ([_]f32{ -1, 1 }) |side| {
        const x = side * (radius + 34);
        try prims.strut(a, shell, origin.add(Vec3.init(side * (radius + 12), 0, 0)), origin.add(Vec3.init(x, 0, 0)), Vec3.unit_z, 3.0, 2.6, .metal);
        for ([_]f32{ -0.34, 0.34 }) |v| {
            const center = origin.add(Vec3.init(x, v * length, 0));
            try prims.strut(a, shell, origin.add(Vec3.init(x, 0, 0)), center, Vec3.unit_z, 2.8, 2.2, .metal);
            // Face the collector sheets outward along X; edge-on panels read as stray rods.
            try prims.box(a, shell, center, Vec3.unit_z, Vec3.unit_y, Vec3.unit_x, Vec3.init(length * 0.12, length * 0.12, 1.3), .glass);
            const stripe = [_]Vec3{ center.add(Vec3.init(side * 2, 0, -length * 0.10)), center.add(Vec3.init(side * 2, 0, length * 0.10)) };
            try prims.lightStrip(a, glow, &stripe, Vec3.unit_y, 0.8, 0.6, .emissive);
        }
    }
}

fn asF32(value: anytype) f32 {
    return @floatFromInt(value);
}

/// A standalone rotating habitat drum with spaced shielding, pressure hoops, axial access,
/// collector booms, and end-spoke structure. Dimensions are art-scale placeholders.
pub fn habitatCylinder(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    try drum(a, &shell, &glow, Vec3.zero, 56, 360, 40, 10, false);
    const palette: Designs.Palette = habitat_palette;
    return finish(a, &shell, &glow, palette);
}

/// The Rand Corporation's traveling habitat and construction ark. The central habitat drum
/// shares its silhouette with the standalone cylinder; industrial yards, radiators and paired
/// building booms distinguish the Mother as a mobile factory and carrier.
pub fn motherArk(a: Allocator) !Pair {
    var shell: cm.Mesh = .{};
    defer shell.deinit(a);
    var glow: cm.Mesh = .{};
    defer glow.deinit(a);
    const origin = Vec3.zero;
    try drum(a, &shell, &glow, origin, 88, 560, 48, 12, true);

    // Command and navigation crown at the forward end; low profile preserves the drum's silhouette.
    var bow: [10]Vec2 = undefined;
    for (&bow, 0..) |*p, i| {
        const t = asF32(i) / 9;
        p.* = .{ .x = 42 * @sin(t * m.pi * 0.78), .y = 214 + t * 94 };
    }
    try revolve(a, &shell, &bow, 48, origin, .paint_accent);
    const bridge = [_]Vec3{ Vec3.init(-22, 8, 278), Vec3.init(-14, 15, 314), Vec3.init(14, 15, 314), Vec3.init(22, 8, 278) };
    try prims.lightStrip(a, &glow, &bridge, Vec3.unit_y, 3.0, 1.0, .emissive);

    // Twin construction gantries, with nested tool heads and a visible habitat section in work.
    for ([_]f32{ -1, 1 }) |side| {
        const shoulder = Vec3.init(side * 72, 2, 84);
        const elbow = Vec3.init(side * 178, 18, 58);
        const wrist = Vec3.init(side * 246, 18, 18);
        try prims.strut(a, &shell, shoulder, elbow, Vec3.unit_y, 16, 13, .metal);
        try prims.strut(a, &shell, elbow, wrist, Vec3.unit_y, 11, 9, .paint_accent);
        try ring(a, &shell, 13, wrist.z, 3, 6, Vec3.init(wrist.x, wrist.y, 0), .metal);
        for ([_]f32{ -1, 1 }) |jaw| try prims.strut(a, &shell, wrist.add(Vec3.init(jaw * 8, -4, 0)), wrist.add(Vec3.init(jaw * 18, -24, -8)), Vec3.unit_z, 4, 3, .paint);
        const rail = [_]Vec3{ elbow.add(Vec3.init(0, 11, 0)), wrist.add(Vec3.init(0, 11, 0)) };
        try prims.lightStrip(a, &glow, &rail, Vec3.unit_y, 1.2, 0.55, .emissive);

        // Four rectangular thermal radiators are hinged off the aft factory shoulders.
        const radiator_center = Vec3.init(side * 138, -74, -130);
        try prims.strut(a, &shell, Vec3.init(side * 94, -24, -115), radiator_center, Vec3.unit_z, 6, 5, .metal);
        for (0..4) |panel| {
            const y = -104 + asF32(panel) * 20;
            const c = Vec3.init(side * 177, y, -130);
            try prims.strut(a, &shell, radiator_center, c, Vec3.unit_z, 4.0, 3.0, .metal);
            try prims.box(a, &shell, c, Vec3.unit_z, Vec3.unit_y, Vec3.unit_x, Vec3.init(34, 8.0, 2), .glass);
            const stripe = [_]Vec3{ c.add(Vec3.init(side * 2.4, 0, -30)), c.add(Vec3.init(side * 2.4, 0, 30)) };
            try prims.lightStrip(a, &glow, &stripe, Vec3.unit_y, 0.7, 0.35, .emissive);
        }

        // Cargo cassettes and one tug socket make the supply/assembly role legible.
        for (0..3) |crate| {
            const z = -30 - asF32(crate) * 38;
            try prims.box(a, &shell, Vec3.init(side * 102, -19, z), Vec3.unit_x, Vec3.unit_y, Vec3.unit_z, Vec3.init(17, 14, 15), if (crate % 2 == 0) .paint else .paint_accent);
            try ring(a, &glow, 6, z, 0.5, 0.45, Vec3.init(side * 102, -19, 0), .emissive);
        }
    }

    // Four protected pulse-drive bells are mounted aft of the nonrotating spine.
    for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sy| {
        const at = Vec3.init(sx * 36, sy * 36, -304);
        const profile = [_]Vec2{ .{ .x = 9, .y = 0 }, .{ .x = 13, .y = -18 }, .{ .x = 18, .y = -40 }, .{ .x = 0, .y = -40 }, .{ .x = 0, .y = 0 } };
        try revolve(a, &shell, &profile, 24, at, .metal);
        try ring(a, &glow, 14, -342, 1.8, 1, Vec3.init(at.x, at.y, 0), .emissive);
    };

    const spine = [_]Vec3{ Vec3.init(0, 14, -285), Vec3.init(0, 23, -210), Vec3.init(0, 27, -70), Vec3.init(0, 24, 100), Vec3.init(0, 19, 260) };
    try prims.lightStrip(a, &glow, &spine, Vec3.unit_y, 5, 1.3, .emissive);
    return finish(a, &shell, &glow, mother_palette);
}
