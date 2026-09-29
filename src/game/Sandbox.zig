const std = @import("std");
const math = @import("mach").math;
const Physics = @import("../physics/Physics.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Scatter = @import("../procedural/Scatter.zig");
const Catalog = @import("../asset/Catalog.zig");
const Key = @import("../world/ChunkKey.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Modifications = @import("../world/Modifications.zig");
const Input = @import("../engine/Input.zig");
const Player = @import("Player.zig");
const Save = @import("Save.zig");
const Sandbox = @This();

/// The interactive test session: a walking player, physical crates, a pickup, one tool
/// (the salvage cutter, which removes relics), and versioned saves of every change.
pub const max_props = World.max_props;
pub const reach: f32 = 6;
pub const hold_distance: f32 = 2.2;
pub const spawn: Physics.Vec3 = .{ 0, 0, -58 };
/// Crate layout relative to the spawn point: a row, plus one stacked on the middle crate.
const crate_offsets = [_]Physics.Vec3{ .{ -2.2, 0, 6 }, .{ 0, 0, 6 }, .{ 2.2, 0, 6 }, .{ 0, 1, 6 }, .{ -1.1, 0, 9 }, .{ 1.1, 0, 9 } };

pub const Target = union(enum) {
    none,
    prop: u32,
    relic: struct { ref: Modifications.ObjectRef, position: Physics.Vec3 },
};
pub const Actions = packed struct {
    grab: bool = false,
    salvage: bool = false,
    toggle_mode: bool = false,
    reset: bool = false,
};
const NearbyChunk = struct { key: Key, count: usize, objects: [Scatter.capacity]Scatter.Object };

seed: u64,
catalog: *const Catalog,
physics: Physics,
player: Player = .{},
props: [max_props]Physics.Body = @splat(.none),
prop_count: u32 = 0,
held: ?u32 = null,
target: Target = .none,
modifications: Modifications = .{},
nearby_center: ?Key = null,
nearby: [9]NearbyChunk = undefined,
tick: u64 = 0,

/// Initializes in place: physics keeps a pointer to `seed` for terrain queries.
pub fn init(self: *Sandbox, seed: u64, catalog: *const Catalog, camera: *Camera) !void {
    self.* = .{ .seed = seed, .catalog = catalog, .physics = undefined };
    self.physics = .init(.{ .context = &self.seed, .sample = groundSample });
    const half = catalog.mesh(catalog.content.crate).?.model.halfExtents();
    for (crate_offsets, 0..) |offset, i| {
        const x = spawn[0] + offset[0];
        const z = spawn[2] + offset[2];
        const y = Terrain.surface(seed, x, z).height + half[1] + offset[1] * (half[1] * 2 + 0.05) + 0.02;
        self.props[i] = try self.physics.createBody(.{ .half_extents = half, .position = .{ x, y, z }, .mass = 20, .user = @intCast(i) });
    }
    self.prop_count = crate_offsets.len;
    self.resetPlayer(camera);
}

fn groundSample(context: ?*const anyopaque, x: f32, z: f32) Physics.GroundSample {
    const seed: *const u64 = @ptrCast(@alignCast(context.?));
    const s = Terrain.surface(seed.*, x, z);
    return .{ .height = s.height, .normal = s.normal };
}

pub fn resetPlayer(self: *Sandbox, camera: *Camera) void {
    self.release();
    camera.* = .{ .yaw = 0, .pitch = -0.2 };
    self.player = .{ .feet = .{ spawn[0], Terrain.surface(self.seed, spawn[0], spawn[2]).height, spawn[2] }, .mode = self.player.mode };
    if (self.player.mode == .fly) {
        self.player.feet[1] += 20;
    }
    camera.position = self.player.eye();
}

pub fn step(self: *Sandbox, camera: *Camera, input: Input, actions: Actions, dt: f32) !void {
    if (actions.reset) self.resetPlayer(camera);
    if (actions.toggle_mode) self.player.setMode(if (self.player.mode == .walk) .fly else .walk, camera.*);
    self.player.step(&self.physics, camera, input, dt);
    if (self.held) |i| {
        // Spring the held crate toward a point in front of the eye; physics still resolves contacts.
        const body = self.props[i];
        const p = self.physics.position(body).?;
        const f = camera.forward();
        const goal = camera.position.add(&f.mulScalar(hold_distance));
        var v: Physics.Vec3 = .{ (goal.x() - p[0]) * 12, (goal.y() - p[1]) * 12, (goal.z() - p[2]) * 12 };
        const speed = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (speed > 15) v = .{ v[0] * 15 / speed, v[1] * 15 / speed, v[2] * 15 / speed };
        self.physics.setVelocity(body, v);
        // Drop it if something wedges it far from the hold point.
        const gap = goal.sub(&math.vec3(p[0], p[1], p[2]));
        if (gap.dot(&gap) > 4 * 4) self.release();
    }
    self.physics.step(dt);
    self.tick += 1;
    self.refreshNearby(camera.position);
    self.target = self.pick(camera.position, camera.forward());
    if (actions.grab) {
        if (self.held != null) self.release() else if (self.target == .prop) self.hold(self.target.prop);
    }
    if (actions.salvage) switch (self.target) {
        .relic => |relic| _ = try self.modifications.remove(relic.ref),
        else => {},
    };
}

fn hold(self: *Sandbox, index: u32) void {
    self.held = index;
    self.physics.setGravityScale(self.props[index], 0);
}

fn release(self: *Sandbox) void {
    if (self.held) |i| self.physics.setGravityScale(self.props[i], 1);
    self.held = null;
}

/// Regenerates scatter for the 3×3 chunks around the eye when the eye changes chunk.
/// Deterministic, so it agrees with what the streamer renders without sharing its buffers.
fn refreshNearby(self: *Sandbox, eye: math.Vec3) void {
    const center = Key.fromPosition(eye.x(), eye.z());
    if (self.nearby_center) |c| if (Key.eql(c, center)) return;
    self.nearby_center = center;
    for (&self.nearby, 0..) |*chunk, i| {
        chunk.key = .{ .x = center.x + @as(i32, @intCast(i % 3)) - 1, .z = center.z + @as(i32, @intCast(i / 3)) - 1 };
        chunk.count = if (chunk.key.valid()) Scatter.generate(self.seed, chunk.key, &chunk.objects) else 0;
    }
}

/// Nearest crate or uncollected relic along the view ray within reach, occluded by terrain.
pub fn pick(self: *const Sandbox, eye: math.Vec3, forward: math.Vec3) Target {
    const origin: Physics.Vec3 = .{ eye.x(), eye.y(), eye.z() };
    const dir: Physics.Vec3 = .{ forward.x(), forward.y(), forward.z() };
    var best: Target = .none;
    var best_distance = self.terrainDistance(origin, dir);
    const ignore: Physics.Body = if (self.held) |i| self.props[i] else .none;
    if (self.physics.raycast(origin, dir, best_distance, ignore)) |hit| {
        best = .{ .prop = hit.user };
        best_distance = hit.distance;
    }
    for (self.nearby) |chunk| for (chunk.objects[0..chunk.count]) |object| {
        if (object.kind != .relic) continue;
        const ref = Modifications.ObjectRef.of(chunk.key, object.local_id);
        const s = object.transform.scale;
        const p = object.transform.position;
        // Relic cube spans y ∈ [0, 2] × scale in model space.
        const hit = Physics.rayBox(origin, dir, .{ p[0], p[1] + s, p[2] }, .{ 0.5 * s, s, 0.5 * s }) orelse continue;
        if (hit.distance >= best_distance or self.modifications.contains(ref)) continue;
        best = .{ .relic = .{ .ref = ref, .position = p } };
        best_distance = hit.distance;
    };
    return best;
}

fn terrainDistance(self: *const Sandbox, origin: Physics.Vec3, dir: Physics.Vec3) f32 {
    var t: f32 = 0;
    while (t < reach) : (t += 0.1) {
        if (origin[1] + dir[1] * t < Terrain.surface(self.seed, origin[0] + dir[0] * t, origin[2] + dir[2] * t).height) return t;
    }
    return reach;
}

pub fn propPosition(self: *const Sandbox, index: u32) Physics.Vec3 {
    return self.physics.position(self.props[index]).?;
}

/// Render view of the crates. Crate models are centered, so translation is the body center.
pub fn publishProps(self: *const Sandbox, out: []World.Prop) usize {
    const count = @min(out.len, self.prop_count);
    for (out[0..count], 0..) |*prop, i| {
        const index: u32 = @intCast(i);
        const glow: f32 = if (self.held == index) 1.35 else if (self.target == .prop and self.target.prop == index) 1.18 else 1;
        prop.* = .{ .mesh = self.catalog.content.crate, .transform = .{ .position = self.propPosition(index) }, .tint = .{ glow, glow, glow, 1 } };
    }
    return count;
}

pub fn save(self: *const Sandbox, allocator: std.mem.Allocator, camera: Camera) ![]u8 {
    var props: [max_props]Save.PropState = undefined;
    for (props[0..self.prop_count], 0..) |*p, i| p.* = .{ .id = @intCast(i), .position = self.propPosition(@intCast(i)), .velocity = self.physics.velocity(self.props[i]).? };
    return Save.encode(allocator, .{
        .seed = self.seed,
        .tick = self.tick,
        .player = .{ .feet = self.player.feet, .yaw = camera.yaw, .pitch = camera.pitch, .mode = self.player.mode },
        .props = props[0..self.prop_count],
        .collected = self.modifications.slice(),
    });
}

/// Validates the whole document first; on any error the session is unchanged.
pub fn restore(self: *Sandbox, allocator: std.mem.Allocator, bytes: []const u8, camera: *Camera) !void {
    const parsed = try Save.decode(allocator, bytes, self.seed, self.prop_count);
    defer parsed.deinit();
    const doc = parsed.value;
    self.release();
    for (doc.props) |p| self.physics.setTransform(self.props[p.id], p.position, p.velocity);
    self.modifications.clear();
    for (doc.collected) |ref| _ = try self.modifications.remove(ref);
    self.player = .{ .feet = doc.player.feet, .mode = doc.player.mode };
    camera.yaw = doc.player.yaw;
    camera.pitch = std.math.clamp(doc.player.pitch, -1.5, 1.5);
    camera.position = self.player.eye();
    self.tick = doc.tick;
    self.target = .none;
}

fn testSandbox(sandbox: *Sandbox, catalog: *Catalog, camera: *Camera) !void {
    try catalog.load(std.testing.allocator);
    errdefer catalog.deinit(std.testing.allocator);
    try sandbox.init(310399555161, catalog, camera);
}

fn run(sandbox: *Sandbox, camera: *Camera, input: Input, actions: Actions, steps: usize) !void {
    try sandbox.step(camera, input, actions, 1.0 / 60.0);
    for (1..steps) |_| try sandbox.step(camera, input, .{}, 1.0 / 60.0);
}

test "walk to a crate, carry it, drop it, save, disturb, and reload the modification" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);

    // Settle: the player stands on the terrain and crates rest without sinking.
    try run(&sandbox, &camera, .{}, .{}, 120);
    try std.testing.expect(sandbox.player.grounded);
    const ground = Terrain.surface(sandbox.seed, sandbox.player.feet[0], sandbox.player.feet[2]).height;
    try std.testing.expectApproxEqAbs(ground, sandbox.player.feet[1], 0.001);
    const start = sandbox.propPosition(1);

    // Walk forward until the middle crate blocks the player.
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 150);
    try std.testing.expect(sandbox.player.feet[2] < start[2]);
    // Look slightly down at the crate and pick it up.
    camera.pitch = -0.35;
    try run(&sandbox, &camera, .{}, .{}, 2);
    try std.testing.expect(sandbox.target == .prop);
    const picked = sandbox.target.prop;
    try run(&sandbox, &camera, .{}, .{ .grab = true }, 1);
    try std.testing.expectEqual(@as(?u32, picked), sandbox.held);

    // Turn around over half a second, carry it, and drop it behind the spawn.
    camera.pitch = 0;
    for (0..30) |_| {
        camera.yaw += std.math.pi / 30.0;
        try run(&sandbox, &camera, .{}, .{}, 1);
    }
    try std.testing.expectEqual(@as(?u32, picked), sandbox.held);
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 90);
    try run(&sandbox, &camera, .{}, .{ .grab = true }, 180);
    try std.testing.expectEqual(@as(?u32, null), sandbox.held);
    const dropped = sandbox.propPosition(picked);
    try std.testing.expect(dropped[2] < start[2] - 3);
    const rest = Terrain.surface(sandbox.seed, dropped[0], dropped[2]).height;
    try std.testing.expect(dropped[1] >= rest + 0.39);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);

    // Disturb the world, then reload the saved state.
    sandbox.physics.setTransform(sandbox.props[picked], .{ 50, 40, 50 }, .{ 0, 0, 0 });
    _ = try sandbox.modifications.remove(.{ .x = 0, .z = 0, .id = 7 });
    sandbox.player.feet = .{ 100, 100, 100 };
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expectEqualDeep(dropped, sandbox.propPosition(picked));
    try std.testing.expect(!sandbox.modifications.contains(.{ .x = 0, .z = 0, .id = 7 }));
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi), camera.yaw, 0.0001);

    // A save from another seed is rejected without changing the session.
    var other: Sandbox = undefined;
    var other_camera: Camera = .{};
    try other.init(42, &catalog, &other_camera);
    try std.testing.expectError(error.SeedMismatch, other.restore(std.testing.allocator, bytes, &other_camera));
}

test "salvage removes a relic by stable ID, survives regeneration, and round-trips through a save" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    sandbox.player.mode = .fly;

    // Find a relic in the spawn chunk and aim at it from two meters away.
    var objects: [Scatter.capacity]Scatter.Object = undefined;
    const key = Key.fromPosition(spawn[0], spawn[2]);
    const count = Scatter.generate(sandbox.seed, key, &objects);
    const relic = for (objects[0..count]) |o| {
        if (o.kind == .relic) break o;
    } else return error.SkipZigTest;
    const p = relic.transform.position;
    camera.position = math.vec3(p[0], p[1] + relic.transform.scale, p[2] - 2 - relic.transform.scale);
    camera.yaw = 0;
    camera.pitch = 0;
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target == .relic);
    try std.testing.expectEqual(relic.local_id, sandbox.target.relic.ref.id);
    try run(&sandbox, &camera, .{}, .{ .salvage = true }, 1);
    const ref = Modifications.ObjectRef.of(key, relic.local_id);
    try std.testing.expect(sandbox.modifications.contains(ref));
    // Once removed it can no longer be targeted.
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target != .relic or sandbox.target.relic.ref.id != relic.local_id);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    sandbox.modifications.clear();
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expect(sandbox.modifications.contains(ref));
    // Regeneration reproduces the same object at the same ID, so the removal still applies.
    var again: [Scatter.capacity]Scatter.Object = undefined;
    try std.testing.expectEqual(count, Scatter.generate(sandbox.seed, key, &again));
    try std.testing.expect(for (again[0..count]) |o| {
        if (o.local_id == relic.local_id) break std.meta.eql(o.transform.position, p);
    } else false);
}
