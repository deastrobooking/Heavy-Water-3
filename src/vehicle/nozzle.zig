//! Rear propulsion nozzle: convergent-divergent profile sized from
//! isentropic flow. The exit/throat area ratio for a design exit Mach M:
//!
//!   A/A* = (1/M) * [ (2/(g+1)) * (1 + (g-1)/2 * M^2) ] ^ ((g+1) / (2(g-1)))
//!
//! The divergent cone half-angle sets the length. Also gives ideal
//! exit velocity for a thrust estimate.

const std = @import("std");
const m = @import("../character/math.zig");
const mesh_mod = @import("../character/mesh.zig");
const prims = @import("prims.zig");
const Vec2 = m.Vec2;
const Transform = m.Transform;
const Mesh = mesh_mod.Mesh;
const Allocator = std.mem.Allocator;

pub const NozzleSpec = struct {
    throat_radius: f32 = 0.07,
    inlet_radius: f32 = 0.12,
    exit_mach: f32 = 2.2,
    gamma: f32 = 1.4,
    /// Divergent half angle (15 deg is the classic conical compromise).
    half_angle: f32 = m.radians(15),
    convergent_len: f32 = 0.10,
    wall: f32 = 0.012,
    segments: u32 = 32,
};

pub fn areaRatio(mach: f32, g: f32) f32 {
    const t = (2.0 / (g + 1.0)) * (1.0 + 0.5 * (g - 1.0) * mach * mach);
    return std.math.pow(f32, t, (g + 1.0) / (2.0 * (g - 1.0))) / mach;
}

/// Ideal exit velocity from chamber temperature T0 (K), gas constant R:
///   v_e = sqrt( 2 g R T0/(g-1) * (1 - (p_e/p0)^((g-1)/g)) ),  p_e/p0 from M_e.
pub fn exitVelocity(mach: f32, g: f32, R: f32, T0: f32) f32 {
    const pr = std.math.pow(f32, 1.0 + 0.5 * (g - 1.0) * mach * mach, -g / (g - 1.0));
    return @sqrt(2.0 * g * R * T0 / (g - 1.0) * (1.0 - std.math.pow(f32, pr, (g - 1.0) / g)));
}

pub fn exitRadius(s: NozzleSpec) f32 {
    return s.throat_radius * @sqrt(areaRatio(s.exit_mach, s.gamma));
}

/// Nozzle wall revolved about local +Y. Local +Y is upstream; the jet exits
/// toward -Y. Orient with `xf`. The wall is a closed inner+outer profile.
pub fn buildNozzle(gpa: Allocator, mesh: *Mesh, s: NozzleSpec, xf: Transform) !void {
    const re = exitRadius(s);
    const div_len = (re - s.throat_radius) / @tan(s.half_angle);
    // inner contour from inlet (h = conv_len) through throat (h = 0) to exit (h = -div_len)
    const n = 12;
    var inner: [2 * n]Vec2 = undefined;
    for (0..n) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, n - 1);
        // cosine blend for a smooth convergent section
        const k = 0.5 - 0.5 * @cos(t * m.pi);
        inner[i] = .{ .x = m.lerp(s.inlet_radius, s.throat_radius, k), .y = m.lerp(s.convergent_len, 0, t) };
    }
    for (0..n) |i| {
        const t = @as(f32, @floatFromInt(i + 1)) / @as(f32, n);
        inner[n + i] = .{ .x = m.lerp(s.throat_radius, re, t), .y = -div_len * t };
    }
    // closed loop: inner contour down, then the outer wall back up
    var loop: [4 * n]Vec2 = undefined;
    for (inner, 0..) |p, i| loop[i] = p;
    for (0..2 * n) |i| {
        const p = inner[2 * n - 1 - i];
        loop[2 * n + i] = .{ .x = p.x + s.wall + 0.25 * s.wall * @as(f32, @floatFromInt(i)) / (2 * n), .y = p.y };
    }
    try prims.lathe(gpa, mesh, &loop, s.segments, xf, .metal);
}

test "isentropic area ratio" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), areaRatio(1.0, 1.4), 1e-5);
    // textbook value: M = 2, gamma = 1.4 -> 1.6875
    try std.testing.expectApproxEqAbs(@as(f32, 1.6875), areaRatio(2.0, 1.4), 1e-3);
}

test "nozzle is watertight" {
    const gpa = std.testing.allocator;
    var mesh: Mesh = .{};
    defer mesh.deinit(gpa);
    try buildNozzle(gpa, &mesh, .{}, .{});
    try @import("airfoil.zig").expectWatertight(&mesh);
}
