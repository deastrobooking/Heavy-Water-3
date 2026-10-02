//! Hover cars in the world. Fabricated designs park on the garage pads beside the spawn and
//! hover idle there; P1 boards one by clicking it and flies it with the hover flight computer
//! (`vehicle/hover.zig`), which probes the real world (terrain, decks, Arbors, towers) through
//! physics ray casts for ride height, skids and walls. The chase camera follows the car and can
//! be orbited with the mouse; it eases back behind the car while flying. Saves keep each car's
//! position and heading; a car without one parks on its pad.
const std = @import("std");
const math = @import("mach").math;
const Physics = @import("../physics/Physics.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Catalog = @import("../asset/Catalog.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Material = @import("../render/Material.zig");
const Designs = @import("../vehicle/Designs.zig");
const hover = @import("../vehicle/hover.zig");
const m = @import("../character/math.zig");
const Input = @import("../engine/Input.zig");
const R = Physics.Rotation;
const Garage = @This();

pub const max_cars = Designs.count;
pub const chase_distance: f32 = 9;
pub const Car = struct { design: Designs.Design, flyer: hover.HoverCar };

cars: [max_cars]?Car = @splat(null),
/// The car P1 is flying.
piloting: ?u8 = null,

/// Garage pads: a row beside the spawn, one per design.
pub fn padPosition(seed: u64, spawn: Physics.Vec3, design: Designs.Design) Physics.Vec3 {
    const x = spawn[0] + 16 + @as(f32, @floatFromInt(@intFromEnum(design))) * 7;
    const z = spawn[2] - 4;
    return .{ x, Terrain.surface(seed, x, z).height, z };
}

/// Parks `design` on its pad (replacing any copy already flying).
pub fn park(self: *Garage, seed: u64, spawn: Physics.Vec3, catalog: *const Catalog, design: Designs.Design) void {
    self.place(seed, spawn, catalog, design, null, 0);
}

/// Puts `design` where it was left (its COM at `at`, facing `yaw`), or on its pad.
pub fn place(self: *Garage, seed: u64, spawn: Physics.Vec3, catalog: *const Catalog, design: Designs.Design, at: ?Physics.Vec3, yaw: f32) void {
    const i = @intFromEnum(design);
    if (self.piloting == @as(?u8, @intCast(i))) self.piloting = null;
    const asset = catalog.content.cars[i];
    const pad = padPosition(seed, spawn, design);
    const s = Designs.spec(design);
    const com = asset.physical.mass.com;
    var flyer = hover.HoverCar.init(asset.physical.mass, .{
        .pads = padsFromCom(s.pad_pos, com),
        .fan_radius = s.fan.radius,
        .disk_area = s.fan.diskArea(),
        .fan_power = s.fan_power,
        .cruise_thrust = s.cruise_thrust,
        .boost_thrust = s.boost_thrust,
        .ride_height = s.ride_height,
        .skid_depth = com.y,
        .half_length = s.hull.length * 0.5,
    }, if (at) |p| m.Vec3.init(p[0], p[1], p[2]) else m.Vec3.init(pad[0], pad[1] + com.y + s.ride_height, pad[2]), if (at != null) yaw else 0);
    flyer.ride = 0.6;
    self.cars[i] = .{ .design = design, .flyer = flyer };
}

fn padsFromCom(pads: [4]m.Vec3, com: m.Vec3) [4]m.Vec3 {
    var out: [4]m.Vec3 = undefined;
    for (&out, pads) |*o, p| o.* = p.sub(com);
    return out;
}

fn probe(physics: *const Physics, from: m.Vec3, dir: m.Vec3, reach: f32) ?hover.Hit {
    const hit = physics.castRay(.{ from.x, from.y, from.z }, .{ dir.x, dir.y, dir.z }, reach, .none) orelse return null;
    return .{ .distance = hit.distance, .normal = m.Vec3.init(hit.normal[0], hit.normal[1], hit.normal[2]) };
}

/// Maps P1's movement keys to the flight computer: W/S thrust, A/D turn, jump or E climb,
/// Q descend, sprint boosts.
pub fn controls(input: Input) hover.Input {
    return .{
        .forward = input.forward,
        .turn = -input.right,
        .lift = std.math.clamp(input.up + @as(f32, if (input.jump) 1 else 0), -1, 1),
        .boost = input.fast,
    };
}

/// Steps every car: the piloted one with `pilot`, parked ones idling low on their pads.
pub fn step(self: *Garage, physics: *const Physics, pilot: hover.Input, dt: f32) void {
    for (&self.cars, 0..) |*slot, i| if (slot.*) |*c| {
        const input: hover.Input = if (self.piloting == @as(?u8, @intCast(i))) pilot else .{};
        c.flyer.step(dt, input, physics, probe);
    };
}

pub fn origin(c: *const Car, catalog: *const Catalog) m.Vec3 {
    const com = catalog.content.cars[@intFromEnum(c.design)].physical.mass.com;
    return c.flyer.body.pointWorld(com.neg());
}

/// Nearest car hit by a ray (an oriented box around the body), within `reach`.
pub const Pick = struct { car: u8, distance: f32 };
pub fn pick(self: *const Garage, eye: Physics.Vec3, dir: Physics.Vec3, reach: f32) ?Pick {
    var best: ?Pick = null;
    for (self.cars, 0..) |slot, i| {
        const c = slot orelse continue;
        if (self.piloting == @as(?u8, @intCast(i))) continue;
        const body = &c.flyer.body;
        // Ray into the car's frame (centered on the COM).
        const o = body.toBody(m.Vec3.init(eye[0], eye[1], eye[2]).sub(body.pos));
        const d = body.toBody(m.Vec3.init(dir[0], dir[1], dir[2]));
        const half = m.Vec3.init(1.7, 0.7, c.flyer.cfg.half_length);
        const hit = Physics.rayBox(.{ o.x, o.y, o.z }, .{ d.x, d.y, d.z }, .{ 0, 0, 0 }, .{ half.x, half.y, half.z }) orelse continue;
        if (hit.distance > reach) continue;
        if (best == null or hit.distance < best.?.distance) best = .{ .car = @intCast(i), .distance = hit.distance };
    }
    return best;
}

pub fn board(self: *Garage, i: u8, camera: *Camera) void {
    const c = &(self.cars[i] orelse return);
    self.piloting = i;
    c.flyer.ride = c.flyer.cfg.ride_height;
    camera.yaw = c.flyer.heading();
    camera.pitch = -0.22;
}

/// Leaves the car to its left, onto the floor below (or into the air over a gap).
pub fn leave(self: *Garage, physics: *const Physics) ?Physics.Vec3 {
    const i = self.piloting orelse return null;
    self.piloting = null;
    const c = &(self.cars[i] orelse return null);
    const body = &c.flyer.body;
    const side = body.pointWorld(m.Vec3.init(2.3, 0, 0));
    c.flyer.ride = 0.6;
    const floor = physics.castRay(.{ side.x, side.y + 1, side.z }, .{ 0, -1, 0 }, 6, .none);
    return .{ side.x, if (floor) |hit| hit.point[1] + 0.01 else side.y, side.z };
}

/// Chase camera behind and above the car; the player rides along at the car's COM.
pub fn follow(self: *const Garage, seed: u64, camera: *Camera, dt: f32) ?Physics.Vec3 {
    const i = self.piloting orelse return null;
    const c = self.cars[i] orelse return null;
    const pos = c.flyer.body.pos;
    // Ease the camera behind the car while it moves.
    const speed = c.flyer.body.vel.length();
    if (speed > 2) {
        const target = c.flyer.heading();
        var delta = @mod(target - camera.yaw + std.math.pi, 2 * std.math.pi) - std.math.pi;
        delta *= @min(1, dt * 2.2);
        camera.yaw += delta;
    }
    const f = camera.forward();
    var eye = math.vec3(pos.x - f.x() * chase_distance, pos.y + 2.2 - f.y() * chase_distance, pos.z - f.z() * chase_distance);
    const ground = Terrain.surface(seed, eye.x(), eye.z()).height + 0.8;
    if (eye.y() < ground) eye = math.vec3(eye.x(), ground, eye.z());
    camera.position = eye;
    return .{ pos.x, pos.y - 0.5, pos.z };
}

fn quat(q: m.Quat) [4]f32 {
    return .{ q.x, q.y, q.z, q.w };
}

/// Body, four spinning rotors and the emissive light strips per car.
pub fn publish(self: *const Garage, catalog: *const Catalog, out: []World.Prop) usize {
    var n: usize = 0;
    for (self.cars) |slot| {
        const c = slot orelse continue;
        if (n + 6 > out.len) break;
        const asset = catalog.content.cars[@intFromEnum(c.design)];
        const body = &c.flyer.body;
        const o = origin(&c, catalog);
        out[n] = .{ .mesh = asset.body, .transform = .{ .position = .{ o.x, o.y, o.z } }, .tint = .{ 1, 1, 1, 1 }, .rotation = quat(body.rot) };
        out[n + 1] = .{ .mesh = asset.lights, .transform = .{ .position = .{ o.x, o.y, o.z } }, .tint = Material.emissive(.{ 1, 1, 1, 1 }, 0.9), .rotation = quat(body.rot) };
        n += 2;
        for (asset.physical.pivots, 0..) |pivot, k| {
            const p = body.pointWorld(pivot.sub(asset.physical.mass.com));
            // Diagonal pairs counter-rotate so their torques cancel.
            const spin = if (k == 0 or k == 3) c.flyer.rotor_angle else -c.flyer.rotor_angle;
            const r = body.rot.mul(m.Quat.fromAxisAngle(m.Vec3.unit_y, spin));
            out[n] = .{ .mesh = asset.rotor, .transform = .{ .position = .{ p.x, p.y, p.z } }, .tint = .{ 1, 1, 1, 1 }, .rotation = quat(r) };
            n += 1;
        }
    }
    return n;
}

test "parked cars hover on their pads, a pilot flies one away, and leaving sets it down" {
    var catalog: Catalog = undefined;
    try catalog.load(std.testing.allocator);
    defer catalog.deinit(std.testing.allocator);
    var physics = Physics.init(.{ .context = null, .sample = flatGround });
    defer physics.deinit();
    var garage: Garage = .{};
    const spawn: Physics.Vec3 = .{ 0, 0, 0 };
    garage.park(0, spawn, &catalog, .skimmer);
    for (0..120) |_| garage.step(&physics, .{}, 1.0 / 60.0);
    const parked = garage.cars[0].?.flyer.body.pos;
    try std.testing.expect(garage.cars[0].?.flyer.up().y > 0.99);
    var camera: Camera = .{};
    // Aim at it from a few metres away and board.
    const eye: Physics.Vec3 = .{ parked.x, parked.y, parked.z - 6 };
    const hit = garage.pick(eye, .{ 0, 0, 1 }, 10).?;
    try std.testing.expectEqual(@as(u8, 0), hit.car);
    garage.board(0, &camera);
    for (0..180) |_| garage.step(&physics, controls(.{ .forward = 1 }), 1.0 / 60.0);
    const flown = garage.cars[0].?.flyer.body.pos;
    try std.testing.expect(flown.z > parked.z + 10);
    try std.testing.expect(garage.follow(0, &camera, 1.0 / 60.0) != null);
    const feet = garage.leave(&physics).?;
    try std.testing.expect(garage.piloting == null);
    try std.testing.expect(@abs(feet[0] - flown.x) > 1.5 or @abs(feet[2] - flown.z) > 1.5);
    var props: [16]World.Prop = undefined;
    try std.testing.expectEqual(@as(usize, 6), garage.publish(&catalog, &props));
}

fn flatGround(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
    return .{ .height = 0, .normal = .{ 0, 1, 0 } };
}
