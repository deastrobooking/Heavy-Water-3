//! Engine physics API. Game code talks only to this file; backend types and handles never
//! escape it, so the native Zig backend can grow (rotation, broadphase, CCD) or be replaced
//! without touching gameplay. The current backend is intentionally small: see BoxWorld.zig.
const std = @import("std");
const Handle = @import("../engine/Handle.zig");
const Backend = @import("BoxWorld.zig");
pub const Rotation = @import("Rotation.zig");
pub const Quat = Rotation.Quat;
const Physics = @This();

pub const Vec3 = [3]f32;
pub const BodyTag = struct {};
pub const Body = Handle.Handle(BodyTag);
pub const max_bodies = 256;
pub const RigidTag = struct {};
/// Oriented rigid box with rotation (vehicles). Separate from `Body`, which never rotates.
pub const Rigid = Handle.Handle(RigidTag);
pub const max_rigids = 8;
pub const RigidDesc = struct {
    half_extents: Vec3,
    position: Vec3,
    orientation: Quat = Rotation.identity,
    linear: Vec3 = .{ 0, 0, 0 },
    angular: Vec3 = .{ 0, 0, 0 },
    mass: f32,
    friction: f32 = 0.7,
    user: u32 = 0,
};
pub const Pose = struct { position: Vec3, orientation: Quat };
pub const MeshTag = struct {};
/// Static triangle-mesh collider (trunks, ramps, decks). Oriented boxes are built as meshes.
pub const MeshCollider = Handle.Handle(MeshTag);
pub const max_meshes = 64;
/// Triangles whose normal has at least this Y component are floors; steeper ones are walls.
pub const walkable_normal_y: f32 = 0.6;
pub const TriangleMesh = @import("TriangleMesh.zig");
pub const Motion6 = struct { linear: Vec3, angular: Vec3 };
/// A solid surface hit by `castRay`, with the surface's own velocity at that point.
pub const SurfaceHit = struct { distance: f32, point: Vec3, normal: Vec3, velocity: Vec3 };
pub const gravity: f32 = -9.81;

/// Kinematic bodies move only by the velocity set on them and are never pushed.
pub const Motion = enum { dynamic, kinematic, static };
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
    /// Open space under the heightfield (caves): where it answers true, a point is in the air
    /// whatever the terrain height above it, and mesh colliders are its only floors and walls.
    hollow: ?*const fn (context: ?*const anyopaque, p: Vec3) bool = null,

    /// The terrain under `p`, or null where `p` is in hollow space.
    pub fn at(self: Ground, p: Vec3) ?GroundSample {
        if (self.hollow) |h| if (h(self.context, p)) return null;
        return self.sample(self.context, p[0], p[2]);
    }
};
/// Exactly one of `body`, `rigid`, or `mesh` is set.
pub const Hit = struct { body: Body = .none, rigid: Rigid = .none, mesh: MeshCollider = .none, distance: f32, point: Vec3, normal: Vec3, user: u32 };
/// Upright cylinder with its origin at the feet.
pub const Character = struct { radius: f32 = 0.35, height: f32 = 1.8, step: f32 = 0.4, push: f32 = 2.5 };
/// `support` is the body stood on, or `.none` on terrain or in the air.
pub const CharacterResult = struct { feet: Vec3, grounded: bool, hit_ceiling: bool, support: Body = .none };
pub const BoxHit = struct { distance: f32, point: Vec3, normal: Vec3 };

backend: Backend,

pub fn init(ground: Ground) Physics {
    return .{ .backend = .{ .ground = ground } };
}

/// Builds a static mesh collider; its triangle and BVH storage come from `allocator` and are
/// freed by `destroyMesh` or `deinit`.
pub fn createMesh(self: *Physics, allocator: std.mem.Allocator, positions: []const Vec3, indices: []const u32, user: u32) !MeshCollider {
    var mesh = try TriangleMesh.build(allocator, positions, indices);
    errdefer mesh.deinit();
    return self.backend.meshes.add(.{ .mesh = mesh, .user = user });
}

/// A static oriented box (an angled deck or wall) as a twelve-triangle mesh.
pub fn createBox(self: *Physics, allocator: std.mem.Allocator, center: Vec3, half: Vec3, rotation: Quat, user: u32) !MeshCollider {
    var positions: [8]Vec3 = undefined;
    var indices: [36]u32 = undefined;
    TriangleMesh.boxGeometry(center, half, rotation, &positions, &indices);
    return self.createMesh(allocator, &positions, &indices, user);
}

pub fn destroyMesh(self: *Physics, mesh: MeshCollider) void {
    if (self.backend.meshes.get(mesh)) |entry| {
        entry.mesh.deinit();
        _ = self.backend.meshes.remove(mesh);
    }
}

/// Frees every mesh collider (bodies and rigid bodies own no heap memory).
pub fn deinit(self: *Physics) void {
    var live = self.backend.meshes.live.iterator(.{});
    while (live.next()) |i| self.destroyMesh(self.backend.meshes.idAt(i));
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

/// Updates a box after its source mesh is reimported. Its centre, velocity and handle stay.
pub fn resizeBody(self: *Physics, body: Body, half: Vec3) void {
    if (self.backend.bodies.get(body)) |b| b.half = half;
}

/// Re-tags a body (game code renumbers devices after edits).
pub fn setUser(self: *Physics, body: Body, user: u32) void {
    if (self.backend.bodies.get(body)) |b| b.user = user;
}

/// True if an axis-aligned box overlaps any body or rigid body (rigid bodies by bounding
/// sphere). Used to reject placements; terrain is not considered.
pub fn overlapsBox(self: *const Physics, center: Vec3, half: Vec3) bool {
    var live = self.backend.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = self.backend.bodies.items[i];
        var hit = true;
        for (0..3) |k| hit = hit and @abs(b.position[k] - center[k]) < b.half[k] + half[k];
        if (hit) return true;
    }
    var rigid = self.backend.rigids.live.iterator(.{});
    while (rigid.next()) |i| {
        const r = self.backend.rigids.items[i];
        var hit = true;
        for (0..3) |k| hit = hit and @abs(r.position[k] - center[k]) < r.radius() + half[k];
        if (hit) return true;
    }
    var meshes = self.backend.meshes.live.iterator(.{});
    var scratch: [1]u32 = undefined;
    while (meshes.next()) |i| {
        if (self.backend.meshes.items[i].mesh.overlap(Rotation.sub(center, half), Rotation.add(center, half), &scratch) > 0) return true;
    }
    return false;
}

pub fn setVelocity(self: *Physics, body: Body, vel: Vec3) void {
    if (self.backend.bodies.get(body)) |b| b.velocity = vel;
}

/// 0 suspends gravity (a held object); 1 restores it.
pub fn setGravityScale(self: *Physics, body: Body, scale: f32) void {
    if (self.backend.bodies.get(body)) |b| b.gravity_scale = scale;
}

pub fn createRigid(self: *Physics, desc: RigidDesc) !Rigid {
    return self.backend.createRigid(desc);
}

pub fn destroyRigid(self: *Physics, rigid: Rigid) void {
    _ = self.backend.rigids.remove(rigid);
}

pub fn rigidPose(self: *const Physics, rigid: Rigid) ?Pose {
    const r = self.backend.rigids.getConst(rigid) orelse return null;
    return .{ .position = r.position, .orientation = r.orientation };
}

pub fn rigidVelocity(self: *const Physics, rigid: Rigid) ?Motion6 {
    const r = self.backend.rigids.getConst(rigid) orelse return null;
    return .{ .linear = r.linear, .angular = r.angular };
}

pub fn rigidPointVelocity(self: *const Physics, rigid: Rigid, point: Vec3) ?Vec3 {
    const r = self.backend.rigids.getConst(rigid) orelse return null;
    return r.pointVelocity(point);
}

pub fn rigidMass(self: *const Physics, rigid: Rigid) ?f32 {
    const r = self.backend.rigids.getConst(rigid) orelse return null;
    return 1 / r.inv_mass;
}

/// Mass a force at `point` along unit `direction` effectively accelerates, including the
/// rotation it induces: 1 / (1/m + n·((I⁻¹(r×n))×r)).
pub fn rigidEffectiveMass(self: *const Physics, rigid: Rigid, point: Vec3, direction: Vec3) ?f32 {
    const r = self.backend.rigids.getConst(rigid) orelse return null;
    const arm = Rotation.sub(point, r.position);
    const angular = Rotation.applyInverseInertia(r.orientation, r.inv_inertia, Rotation.cross(arm, direction));
    return 1 / (r.inv_mass + Rotation.dot(direction, Rotation.cross(angular, arm)));
}

/// Teleports a rigid body (loading saves, placing vehicles).
pub fn setRigidState(self: *Physics, rigid: Rigid, pose: Pose, linear: Vec3, angular: Vec3) void {
    if (self.backend.rigids.get(rigid)) |r| {
        r.position = pose.position;
        r.orientation = Rotation.normalizeQuat(pose.orientation);
        r.linear = linear;
        r.angular = angular;
    }
}

/// Accumulates a world-space force applied at a world-space point until the next step.
pub fn addForceAt(self: *Physics, rigid: Rigid, force: Vec3, point: Vec3) void {
    if (self.backend.rigids.get(rigid)) |r| {
        r.force = Rotation.add(r.force, force);
        r.torque = Rotation.add(r.torque, Rotation.cross(Rotation.sub(point, r.position), force));
    }
}

/// Nearest solid surface (terrain, boxes, rigid bodies except `ignore`) along a normalized ray.
pub fn castRay(self: *const Physics, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Rigid) ?SurfaceHit {
    return self.backend.castRay(origin, direction, max_distance, ignore);
}

/// Raycast dynamic and mesh geometry without sampling the terrain heightfield.
/// Use only when the caller has a conservative proof that the segment stays above ground.
pub fn castRayObjects(self: *const Physics, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Rigid) ?SurfaceHit {
    return self.backend.castRayObjects(origin, direction, max_distance, ignore);
}

pub fn step(self: *Physics, dt: f32) void {
    self.backend.step(dt);
}

/// Nearest body hit along a normalized direction, ignoring `ignore`.
pub fn raycast(self: *const Physics, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Body) ?Hit {
    return self.backend.raycast(origin, direction, max_distance, ignore);
}

/// Sweeps a character through bodies and ground; dynamic bodies it walks into are pushed.
/// With `snap`, the character stays on any support within step height (walking downhill, riding lifts).
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
