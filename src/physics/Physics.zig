//! Engine physics API. Game code talks only to this file; backend types and handles never
//! escape it, so an external engine (for example Jolt) can replace `Backend` without touching
//! gameplay. The built-in backend is intentionally small: see BoxWorld.zig for its limits.
const std = @import("std");
const Handle = @import("../engine/Handle.zig");
const Backend = @import("BoxWorld.zig");
const Physics = @This();

pub const Vec3 = [3]f32;
pub const BodyTag = struct {};
pub const Body = Handle.Handle(BodyTag);
pub const max_bodies = 128;
pub const gravity: f32 = -9.81;

pub const Motion = enum { dynamic, static };
pub const BodyDesc = struct {
    half_extents: Vec3,
    position: Vec3,
    velocity: Vec3 = .{ 0, 0, 0 },
    mass: f32 = 1,
    friction: f32 = 0.8,
    motion: Motion = .dynamic,
    /// Opaque to physics; lets game code map hits back to its own objects.
    user: u32 = 0,
};
pub const GroundSample = struct { height: f32, normal: Vec3 };
/// Static world geometry supplied by the engine (the streamed heightfield).
pub const Ground = struct {
    context: ?*const anyopaque = null,
    sample: *const fn (context: ?*const anyopaque, x: f32, z: f32) GroundSample,
};
pub const Hit = struct { body: Body, distance: f32, point: Vec3, normal: Vec3, user: u32 };
/// Upright cylinder with its origin at the feet.
pub const Character = struct { radius: f32 = 0.35, height: f32 = 1.8, step: f32 = 0.4, push: f32 = 2.5 };
pub const CharacterResult = struct { feet: Vec3, grounded: bool, hit_ceiling: bool };
pub const BoxHit = struct { distance: f32, point: Vec3, normal: Vec3 };

backend: Backend,

pub fn init(ground: Ground) Physics {
    return .{ .backend = .{ .ground = ground } };
}

pub fn createBody(self: *Physics, desc: BodyDesc) !Body {
    return self.backend.create(desc);
}

pub fn destroyBody(self: *Physics, body: Body) void {
    self.backend.destroy(body);
}

pub fn valid(self: *const Physics, body: Body) bool {
    return self.backend.bodies.valid(body);
}

pub fn position(self: *const Physics, body: Body) ?Vec3 {
    return if (self.backend.bodies.getConst(body)) |b| b.position else null;
}

pub fn velocity(self: *const Physics, body: Body) ?Vec3 {
    return if (self.backend.bodies.getConst(body)) |b| b.velocity else null;
}

pub fn halfExtents(self: *const Physics, body: Body) ?Vec3 {
    return if (self.backend.bodies.getConst(body)) |b| b.half else null;
}

/// Teleports a body (for loading saves); clears contacts and wakes it.
pub fn setTransform(self: *Physics, body: Body, pos: Vec3, vel: Vec3) void {
    if (self.backend.bodies.get(body)) |b| {
        b.position = pos;
        b.velocity = vel;
        b.grounded = false;
    }
}

pub fn setVelocity(self: *Physics, body: Body, vel: Vec3) void {
    if (self.backend.bodies.get(body)) |b| b.velocity = vel;
}

/// 0 suspends gravity (a held object); 1 restores it.
pub fn setGravityScale(self: *Physics, body: Body, scale: f32) void {
    if (self.backend.bodies.get(body)) |b| b.gravity_scale = scale;
}

pub fn step(self: *Physics, dt: f32) void {
    self.backend.step(dt);
}

/// Nearest body hit along a normalized direction, ignoring `ignore`.
pub fn raycast(self: *const Physics, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Body) ?Hit {
    return self.backend.raycast(origin, direction, max_distance, ignore);
}

/// Sweeps a character through bodies and ground; dynamic bodies it walks into are pushed.
pub fn moveCharacter(self: *Physics, shape: Character, feet: Vec3, displacement: Vec3, snap: bool) CharacterResult {
    return self.backend.moveCharacter(shape, feet, displacement, snap);
}

pub fn sampleGround(self: *const Physics, x: f32, z: f32) GroundSample {
    return self.backend.ground.sample(self.backend.ground.context, x, z);
}

/// Geometry helper shared by the backend and game-side picking of non-physical objects.
/// Slab test; a ray starting inside the box hits at distance 0.
pub fn rayBox(origin: Vec3, direction: Vec3, center: Vec3, half: Vec3) ?BoxHit {
    var near: f32 = 0;
    var far = std.math.inf(f32);
    var normal: Vec3 = .{ 0, 0, 0 };
    for (0..3) |k| {
        const lo = center[k] - half[k];
        const hi = center[k] + half[k];
        if (@abs(direction[k]) < 1e-8) {
            if (origin[k] < lo or origin[k] > hi) return null;
            continue;
        }
        var t0 = (lo - origin[k]) / direction[k];
        var t1 = (hi - origin[k]) / direction[k];
        var face: f32 = -1;
        if (t0 > t1) {
            std.mem.swap(f32, &t0, &t1);
            face = 1;
        }
        if (t0 > near) {
            near = t0;
            normal = .{ 0, 0, 0 };
            normal[k] = face;
        }
        far = @min(far, t1);
        if (near > far) return null;
    }
    return .{ .distance = near, .point = .{ origin[0] + direction[0] * near, origin[1] + direction[1] * near, origin[2] + direction[2] * near }, .normal = normal };
}
