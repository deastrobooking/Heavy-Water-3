//! Ducted lift fan: ring-wing duct (NACA section revolved), spinner hub,
//! support struts, and a rotor whose blades follow a constant-pitch helix
//!   beta(r) = atan( P / (2 pi r) )
//! with chord taper and cosine-spaced radial stations.
//!
//! Local frame: axis +Y = intake (air flows down -Y, thrust is +Y),
//! fan center at origin. Place with a Transform.

const std = @import("std");
const m = @import("../character/math.zig");
const mesh_mod = @import("../character/mesh.zig");
const airfoil = @import("airfoil.zig");
const prims = @import("prims.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Transform = m.Transform;
const Mesh = mesh_mod.Mesh;
const Allocator = std.mem.Allocator;

pub const FanSpec = struct {
    /// Duct inner radius at the rotor plane.
    radius: f32 = 0.30,
    duct_chord: f32 = 0.20,
    duct_section: airfoil.Naca4 = airfoil.Naca4.fromDigits("6412"),
    hub_radius: f32 = 0.075,
    blades: u8 = 7,
    /// Geometric pitch (m of advance per revolution).
    pitch: f32 = 0.22,
    root_chord: f32 = 0.085,
    tip_chord: f32 = 0.055,
    blade_section: airfoil.Naca4 = airfoil.Naca4.fromDigits("4408"),
    tip_gap: f32 = 0.004,
    stations: usize = 8,
    profile_points: usize = 14,
    segments: u32 = 48,
    struts: u8 = 3,

    pub fn bladeAngle(s: FanSpec, r: f32) f32 {
        return std.math.atan(s.pitch / (m.tau * r));
    }
    pub fn diskArea(s: FanSpec) f32 {
        return m.pi * (s.radius * s.radius - s.hub_radius * s.hub_radius);
    }
};

/// Duct = airfoil revolved with its chord along the axis and suction side
/// facing inward (inward "lift" is what gives ducted fans extra thrust).
pub fn buildDuct(gpa: Allocator, mesh: *Mesh, s: FanSpec, xf: Transform) !void {
    const n = 20;
    var loop: [2 * n - 2]Vec2 = undefined;
    s.duct_section.outline(n, &loop);
    var prof: [2 * n - 2]Vec2 = undefined;
    const t_max = s.duct_section.t * s.duct_chord;
    for (loop, &prof) |p, *q| q.* = .{
        .x = s.radius + t_max * 0.55 - p.y * s.duct_chord, // r: suction side (+y) inward
        .y = (0.45 - p.x) * s.duct_chord, // h: leading edge up at the intake
    };
    try prims.lathe(gpa, mesh, &prof, s.segments, xf, .paint_accent);
}

/// Spinner hub: ellipsoidal nose, cylindrical body, tail cone.
pub fn buildHub(gpa: Allocator, mesh: *Mesh, s: FanSpec, xf: Transform) !void {
    const r = s.hub_radius;
    var prof: [18]Vec2 = undefined;
    // from bottom tip (on axis) up to top tip (on axis); closing edge lies on the axis
    for (0..18) |i| {
        const t = @as(f32, @floatFromInt(i)) / 17.0;
        if (t < 0.3) {
            const k = t / 0.3; // tail cone
            prof[i] = .{ .x = r * k, .y = -0.16 + 0.10 * k };
        } else if (t < 0.6) {
            const k = (t - 0.3) / 0.3;
            prof[i] = .{ .x = r, .y = -0.06 + 0.07 * k };
        } else {
            const a = (t - 0.6) / 0.4 * (m.pi / 2.0); // elliptic nose
            prof[i] = .{ .x = r * @cos(a), .y = 0.01 + 0.06 * @sin(a) };
        }
    }
    try prims.lathe(gpa, mesh, &prof, s.segments / 2, xf, .metal);
}

/// All blades of the rotor. It spins about local +Y, so a renderer animates
/// it by rotating the whole rotor part about its pivot.
pub fn buildRotor(gpa: Allocator, mesh: *Mesh, s: FanSpec, xf: Transform) !void {
    const n = s.profile_points;
    const ring = 2 * n - 2;
    const loop = try gpa.alloc(Vec2, ring);
    defer gpa.free(loop);
    s.blade_section.outline(n, loop);
    const r0 = s.hub_radius * 0.9;
    const r1 = s.radius - s.tip_gap;

    for (0..s.blades) |b| {
        const phi = @as(f32, @floatFromInt(b)) / @as(f32, @floatFromInt(s.blades)) * m.tau;
        const rh = Vec3.init(@cos(phi), 0, @sin(phi));
        const th = Vec3.init(-@sin(phi), 0, @cos(phi)); // direction of rotation
        const ax = Vec3.unit_y;
        const first = mesh.vertexCount();
        for (0..s.stations) |i| {
            // cosine spacing: more stations near root & tip where geometry changes fastest
            const u = 0.5 * (1 - @cos(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(s.stations - 1)) * m.pi));
            const r = m.lerp(r0, r1, u);
            const beta = s.bladeAngle(r);
            const c = m.lerp(s.root_chord, s.tip_chord, u);
            // LE leads the rotation and sits higher (toward the intake)
            const chord_dir = th.scale(-@cos(beta)).add(ax.scale(-@sin(beta)));
            const thick_dir = th.scale(-@sin(beta)).add(ax.scale(@cos(beta)));
            for (loop) |p| {
                const local = rh.scale(r).add(chord_dir.scale((p.x - 0.35) * c)).add(thick_dir.scale(p.y * c));
                _ = try mesh.addVertex(gpa, .{ .pos = xf.transformPoint(local), .material = .carbon, .region = .garment });
            }
        }
        try mesh.stitchRings(gpa, first, @intCast(s.stations), @intCast(ring), true, false);
        for ([_]usize{ 0, s.stations - 1 }) |row| {
            var cen = Vec3.zero;
            for (0..ring) |k| cen = cen.add(mesh.vertices.items[first + row * ring + k].pos);
            const ci = try mesh.addVertex(gpa, .{ .pos = cen.scale(1.0 / @as(f32, @floatFromInt(ring))), .material = .carbon, .region = .garment });
            try mesh.capRing(gpa, first + @as(u32, @intCast(row * ring)), @intCast(ring), ci, row != 0);
        }
    }
}

/// Struts joining hub to duct (below the rotor, also act as stator vanes).
pub fn buildStruts(gpa: Allocator, mesh: *Mesh, s: FanSpec, xf: Transform) !void {
    for (0..s.struts) |i| {
        const phi = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(s.struts)) * m.tau;
        const d = Vec3.init(@cos(phi), 0, @sin(phi));
        const a = d.scale(s.hub_radius * 0.8).add(Vec3.init(0, -0.07, 0));
        const b = d.scale(s.radius + 0.01).add(Vec3.init(0, -0.07, 0));
        try prims.strut(gpa, mesh, xf.transformPoint(a), xf.transformPoint(b), xf.rotation.rotate(Vec3.unit_y), 0.012, 0.045, .metal);
    }
}

test "blade pitch angle: constant helix pitch" {
    const s: FanSpec = .{};
    // tan(beta) * 2 pi r must equal the pitch at every radius
    var r: f32 = 0.08;
    while (r < 0.3) : (r += 0.02) try std.testing.expectApproxEqRel(s.pitch, @tan(s.bladeAngle(r)) * m.tau * r, 1e-4);
}

test "fan parts are watertight" {
    const gpa = std.testing.allocator;
    const s: FanSpec = .{};
    inline for (.{ buildDuct, buildHub, buildRotor, buildStruts }) |f| {
        var mesh: Mesh = .{};
        defer mesh.deinit(gpa);
        try f(gpa, &mesh, s, .{ .rotation = m.Quat.fromEuler(0.2, 0.5, 0.1) });
        try airfoil.expectWatertight(&mesh);
    }
}
