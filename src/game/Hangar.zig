//! The Kestrel fighter in the world. Once fabricated it stands on a pad beside the garage; P1
//! boards it by clicking it and flies with mouse aim: the chase camera orbits with the mouse,
//! and the flight computer flies toward where the camera points (`vehicle/jet.zig`). W/S set
//! the throttle, A/D roll, Space/E and Q climb and sink while hovering, Shift lights the
//! afterburner. The jet probes the real world for its gear, the floor and walls. A wrecked jet
//! throws its pilot clear and is rebuilt on its pad. Saves keep where it was left.
const std = @import("std");
const math = @import("mach").math;
const Physics = @import("../physics/Physics.zig");
const Camera = @import("../world/Camera.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Input = @import("../engine/Input.zig");
const jet = @import("../vehicle/jet.zig");
const airfoil = @import("../vehicle/airfoil.zig");
const dyn = @import("../vehicle/dynamics.zig");
const ShipMeshes = @import("../vehicle/ShipMeshes.zig");
const Garage = @import("Garage.zig");
const Progress = @import("Progress.zig");
const m = @import("../character/math.zig");
const Hangar = @This();

/// Kestrel mass, aero area, camera and parked height; handling edits stay in one place.
pub const tuning = .{
    .chase_distance = 24.0,
    .rest_height = 1.45,
    .mass = 6500.0,
    .inertia = m.Vec3.init(32_000, 46_000, 16_000),
    .wing_area = 3.2,
};
pub const chase_distance: f32 = tuning.chase_distance;
/// The Kestrel stands this far above its pad on its gear (COM height).
pub const rest_height: f32 = tuning.rest_height;

fighter: ?jet.Fighter = null,
piloting: bool = false,

pub fn padPosition(seed: u64, spawn: Physics.Vec3) Physics.Vec3 {
    const pad = Garage.padPosition(seed, spawn, .courier);
    const x = pad[0] + 16;
    const z = pad[2] + 4;
    return .{ x, Terrain.surface(seed, x, z).height, z };
}

pub fn config(levels: [Progress.kestrel_upgrade_count]u8) jet.Config {
    const engine: f32 = @floatFromInt(levels[@intFromEnum(Progress.KestrelUpgrade.engine)]);
    const armor: f32 = @floatFromInt(levels[@intFromEnum(Progress.KestrelUpgrade.armor)]);
    return .{
        .aero = airfoil.WingAero.init(airfoil.Naca4.fromDigits("2408"), tuning.wing_area),
        .thrust = 58_000 * (1 + engine * 0.12),
        .afterburner = 95_000 * (1 + engine * 0.12),
        .hull_max = 300 + armor * 75,
    };
}

pub fn massProps() dyn.MassProps {
    return .{ .mass = tuning.mass, .com = m.Vec3.zero, .inertia = m.Mat3.diag(tuning.inertia) };
}

/// Rolls the Kestrel out onto its pad (or puts it where it was left).
pub fn place(self: *Hangar, seed: u64, spawn: Physics.Vec3, at: ?Physics.Vec3, yaw: f32) void {
    self.placeWithLevels(seed, spawn, at, yaw, @splat(0));
}

pub fn placeWithLevels(self: *Hangar, seed: u64, spawn: Physics.Vec3, at: ?Physics.Vec3, yaw: f32, levels: [Progress.kestrel_upgrade_count]u8) void {
    const pad = padPosition(seed, spawn);
    const p = at orelse Physics.Vec3{ pad[0], pad[1] + rest_height, pad[2] };
    self.fighter = jet.Fighter.init(massProps(), config(levels), m.Vec3.init(p[0], p[1], p[2]), if (at != null) yaw else std.math.pi);
    self.piloting = false;
}

pub fn applyLevels(self: *Hangar, levels: [Progress.kestrel_upgrade_count]u8) void {
    const f = &(self.fighter orelse return);
    const old_max = f.hull_max;
    f.cfg = config(levels);
    f.hull_max = f.cfg.hull_max;
    f.hull = @min(f.hull_max, f.hull + (f.hull_max - old_max));
}

fn probe(physics: *const Physics, from: m.Vec3, dir: m.Vec3, reach: f32) ?jet.Hit {
    const hit = physics.castRay(.{ from.x, from.y, from.z }, .{ dir.x, dir.y, dir.z }, reach, .none) orelse return null;
    return .{ .distance = hit.distance, .normal = m.Vec3.init(hit.normal[0], hit.normal[1], hit.normal[2]) };
}

pub fn controls(input: Input, camera: Camera) jet.Input {
    const f = camera.forward();
    return .{
        .aim = m.Vec3.init(f.x(), f.y(), f.z()),
        .throttle = input.forward,
        .roll = input.right,
        .climb = std.math.clamp(input.up + @as(f32, if (input.jump) 1 else 0), -1, 1),
        .afterburner = input.fast,
    };
}

/// Steps the jet: flown when piloted, otherwise parked (gear holds it, the computer levels).
pub fn step(self: *Hangar, physics: *const Physics, input: jet.Input, dt: f32) void {
    const f = &(self.fighter orelse return);
    // Unpiloted, the jet idles: engine off, wings levelled, and the lift jets let it down gently.
    const in: jet.Input = if (self.piloting) input else .{ .aim = f.forward(), .steer = false, .climb = if (f.grounded) 0 else -0.6 };
    if (!self.piloting) f.throttle = 0;
    f.step(dt, in, physics, probe);
}

pub fn pick(self: *const Hangar, eye: Physics.Vec3, dir: Physics.Vec3, reach: f32) ?f32 {
    const f = self.fighter orelse return null;
    if (self.piloting) return null;
    const o = f.body.toBody(m.Vec3.init(eye[0], eye[1], eye[2]).sub(f.body.pos));
    const d = f.body.toBody(m.Vec3.init(dir[0], dir[1], dir[2]));
    const hit = Physics.rayBox(.{ o.x, o.y, o.z }, .{ d.x, d.y, d.z }, .{ 0, 0, 0 }, .{ 4, 1.6, 7 }) orelse return null;
    return if (hit.distance <= reach) hit.distance else null;
}

pub fn board(self: *Hangar, camera: *Camera) void {
    const f = self.fighter orelse return;
    self.piloting = true;
    camera.yaw = f.heading();
    camera.pitch = 0.05;
}

/// Climbs out to the left onto the floor below (or drops from the air).
pub fn leave(self: *Hangar, physics: *const Physics) ?Physics.Vec3 {
    if (!self.piloting) return null;
    self.piloting = false;
    const f = self.fighter orelse return null;
    const side = f.body.pointWorld(m.Vec3.init(5.5, 0, 0));
    const floor = physics.castRay(.{ side.x, side.y + 2, side.z }, .{ 0, -1, 0 }, 10, .none);
    return .{ side.x, if (floor) |hit| hit.point[1] + 0.01 else side.y, side.z };
}

/// Chase camera behind the camera's aim (mouse orbit), above the jet.
pub fn follow(self: *const Hangar, seed: u64, camera: *Camera) ?Physics.Vec3 {
    if (!self.piloting) return null;
    const f = self.fighter orelse return null;
    const pos = f.body.pos;
    const fwd = camera.forward();
    var eye = math.vec3(pos.x - fwd.x() * chase_distance, pos.y + 5 - fwd.y() * chase_distance, pos.z - fwd.z() * chase_distance);
    const ground = Terrain.surface(seed, eye.x(), eye.z()).height + 1;
    if (eye.y() < ground) eye = math.vec3(eye.x(), ground, eye.z());
    camera.position = eye;
    return .{ pos.x, pos.y - 1, pos.z };
}

/// Cannon muzzles in the world.
pub fn guns(self: *const Hangar) [2]Physics.Vec3 {
    const f = self.fighter.?;
    var out: [2]Physics.Vec3 = undefined;
    for (&out, ShipMeshes.kestrel_guns) |*o, g| {
        const p = f.body.pointWorld(g);
        o.* = .{ p.x, p.y, p.z };
    }
    return out;
}

fn flatGround(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
    return .{ .height = 0, .normal = .{ 0, 1, 0 } };
}

test "the Kestrel rests on its pad, is boarded, lifts off on its jets and flies where aimed" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var hangar: Hangar = .{};
    hangar.place(0, .{ 0, 0, 0 }, .{ 0, rest_height, 0 }, 0);
    for (0..120) |_| hangar.step(&physics, .{}, 1.0 / 60.0);
    try std.testing.expect(hangar.fighter.?.grounded);
    try std.testing.expect(hangar.pick(.{ 0, 1.5, -12 }, .{ 0, 0, 1 }, 20) != null);
    var camera: Camera = .{};
    hangar.board(&camera);
    try std.testing.expect(hangar.pick(.{ 0, 1.5, -12 }, .{ 0, 0, 1 }, 20) == null);
    // Lift off vertically, then fly forward on afterburner.
    for (0..60 * 3) |_| hangar.step(&physics, controls(.{ .jump = true }, camera), 1.0 / 60.0);
    try std.testing.expect(hangar.fighter.?.body.pos.y > 8);
    for (0..60 * 6) |_| hangar.step(&physics, controls(.{ .fast = true }, camera), 1.0 / 60.0);
    const f = hangar.fighter.?;
    try std.testing.expect(f.airspeed() > 60 and f.body.pos.z > 100);
    try std.testing.expect(hangar.follow(0, &camera) != null);
    try std.testing.expect(hangar.leave(&physics) != null and !hangar.piloting);
}

test "Kestrel armor and engine levels measurably change hull and thrust" {
    var levels: [Progress.kestrel_upgrade_count]u8 = @splat(0);
    levels[@intFromEnum(Progress.KestrelUpgrade.engine)] = 2;
    levels[@intFromEnum(Progress.KestrelUpgrade.armor)] = 1;
    const base = config(@splat(0));
    const tuned = config(levels);
    try std.testing.expect(tuned.thrust > base.thrust);
    try std.testing.expect(tuned.afterburner > base.afterburner);
    try std.testing.expectEqual(@as(f32, 375), tuned.hull_max);
    var hangar: Hangar = .{};
    hangar.placeWithLevels(1, .{ 0, 0, 0 }, null, 0, levels);
    try std.testing.expectEqual(@as(f32, 375), hangar.fighter.?.hull_max);
    hangar.fighter.?.hull = 200;
    levels[@intFromEnum(Progress.KestrelUpgrade.armor)] = 2;
    hangar.applyLevels(levels);
    try std.testing.expectEqual(@as(f32, 275), hangar.fighter.?.hull);
    try std.testing.expectEqual(@as(f32, 450), hangar.fighter.?.hull_max);
}
