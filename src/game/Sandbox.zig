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
const Blueprint = @import("../machine/Blueprint.zig");
const Machine = @import("../machine/Machine.zig");
const Player = @import("Player.zig");
const Save = @import("Save.zig");
const Sandbox = @This();

/// The interactive test session: a walking player, physical crates, a pickup, one tool
/// (the salvage cutter, which removes relics), placed machines (a powered door and an
/// elevator), and versioned saves of every change.
pub const max_crates = 16;
pub const max_machines = 4;
pub const reach: f32 = 6;
pub const hold_distance: f32 = 2.2;
pub const spawn: Physics.Vec3 = .{ 0, 0, -58 };
/// Crate layout relative to the spawn point: a row, plus one stacked on the middle crate.
const crate_offsets = [_]Physics.Vec3{ .{ -2.2, 0, 6 }, .{ 0, 0, 6 }, .{ 2.2, 0, 6 }, .{ 0, 1, 6 }, .{ -1.1, 0, 9 }, .{ 1.1, 0, 9 } };
/// Machine placements relative to the spawn point.
const Placement = struct { blueprint: enum { powered_door, elevator }, offset: [2]f32 };
const placements = [_]Placement{ .{ .blueprint = .powered_door, .offset = .{ 9, 10 } }, .{ .blueprint = .elevator, .offset = .{ -10, 8 } } };

pub const DeviceRef = struct { machine: u8, device: u8 };
pub const Target = union(enum) {
    none,
    prop: u32,
    relic: struct { ref: Modifications.ObjectRef, position: Physics.Vec3 },
    device: DeviceRef,
};
pub const Actions = packed struct {
    /// Grab or drop a crate, or press a button.
    interact: bool = false,
    salvage: bool = false,
    toggle_mode: bool = false,
    reset: bool = false,
};
const NearbyChunk = struct { key: Key, count: usize, objects: [Scatter.capacity]Scatter.Object };
/// A blueprint instance plus the physics bodies that represent it.
pub const Placed = struct {
    machine: Machine,
    devices: [Blueprint.max_devices]Physics.Body = @splat(.none),
    parts: [Blueprint.max_parts]Physics.Body = @splat(.none),
};

// Physics user data: crates are their index; machine bodies set the top bit.
const machine_flag: u32 = 1 << 31;
const part_flag: u32 = 1 << 30;

seed: u64,
catalog: *const Catalog,
physics: Physics,
player: Player = .{},
crates: [max_crates]Physics.Body = @splat(.none),
crate_count: u32 = 0,
machines: [max_machines]Placed = undefined,
machine_count: usize = 0,
/// Button pressed during the last step; the machines see it on the next step.
press: ?DeviceRef = null,
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
        self.crates[i] = try self.physics.createBody(.{ .half_extents = half, .position = .{ x, y, z }, .mass = 20, .user = @intCast(i) });
    }
    self.crate_count = crate_offsets.len;
    for (placements) |placement| {
        const bp = switch (placement.blueprint) {
            .powered_door => catalog.content.powered_door,
            .elevator => catalog.content.elevator,
        };
        try self.place(bp, spawn[0] + placement.offset[0], spawn[2] + placement.offset[1]);
    }
    self.resetPlayer(camera);
}

/// Places a blueprint with its origin on the highest terrain under its structure, so the
/// foundation never floats; parts are authored to extend below the origin.
pub fn place(self: *Sandbox, bp: *const Blueprint, x: f32, z: f32) !void {
    if (self.machine_count == max_machines) return error.TooManyMachines;
    var lo: [2]f32 = .{ 0, 0 };
    var hi: [2]f32 = .{ 0, 0 };
    for (bp.parts[0..bp.part_count]) |part| for ([_]usize{ 0, 2 }, 0..) |axis, k| {
        lo[k] = @min(lo[k], part.offset[axis] - part.size[axis] / 2);
        hi[k] = @max(hi[k], part.offset[axis] + part.size[axis] / 2);
    };
    var y = -std.math.inf(f32);
    var sx = lo[0];
    while (sx <= hi[0]) : (sx += 1) {
        var sz = lo[1];
        while (sz <= hi[1]) : (sz += 1) y = @max(y, Terrain.surface(self.seed, x + sx, z + sz).height);
    }
    const m = self.machine_count;
    const placed = &self.machines[m];
    placed.* = .{ .machine = .init(bp, .{ x, y, z }) };
    errdefer for (placed.devices ++ placed.parts) |body| self.physics.destroyBody(body);
    for (bp.parts[0..bp.part_count], 0..) |part, i| {
        placed.parts[i] = try self.physics.createBody(.{ .half_extents = halve(part.size), .position = .{ x + part.offset[0], y + part.offset[1], z + part.offset[2] }, .motion = .static, .user = machine_flag | part_flag | @as(u32, @intCast(m)) << 8 | @as(u32, @intCast(i)) });
    }
    for (bp.devices[0..bp.device_count], 0..) |def, d| {
        if (!def.hasBody()) continue;
        placed.devices[d] = try self.physics.createBody(.{
            .half_extents = halve(def.size),
            .position = placed.machine.devicePosition(d),
            .motion = if (def.kind == .actuator) .kinematic else .static,
            .user = machine_flag | @as(u32, @intCast(m)) << 8 | @as(u32, @intCast(d)),
        });
    }
    self.machine_count += 1;
}

fn halve(size: [3]f32) Physics.Vec3 {
    return .{ size[0] / 2, size[1] / 2, size[2] / 2 };
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
    self.stepMachines(dt);
    if (self.held) |i| {
        // Spring the held crate toward a point in front of the eye; physics still resolves contacts.
        const body = self.crates[i];
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
    if (actions.interact) {
        if (self.held != null) self.release() else switch (self.target) {
            .prop => |i| self.hold(i),
            .device => |d| if (self.machines[d.machine].machine.blueprint.devices[d.device].kind == .button) {
                self.press = d;
            },
            else => {},
        }
    }
    if (actions.salvage) switch (self.target) {
        .relic => |relic| _ = try self.modifications.remove(relic.ref),
        else => {},
    };
}

/// Advances every machine one fixed step, then drives actuator bodies to their new positions
/// through velocity so physics pushes whatever they touch.
fn stepMachines(self: *Sandbox, dt: f32) void {
    for (self.machines[0..self.machine_count], 0..) |*placed, m| {
        var env: Machine.Environment = .{ .player_feet = self.player.feet };
        if (self.press) |p| if (p.machine == m) {
            env.pressed = p.device;
        };
        placed.machine.step(env, dt);
        const bp = placed.machine.blueprint;
        for (bp.devices[0..bp.device_count], 0..) |def, d| {
            if (def.kind != .actuator) continue;
            const goal = placed.machine.devicePosition(d);
            const now = self.physics.position(placed.devices[d]).?;
            self.physics.setVelocity(placed.devices[d], .{ (goal[0] - now[0]) / dt, (goal[1] - now[1]) / dt, (goal[2] - now[2]) / dt });
        }
    }
    self.press = null;
}

fn hold(self: *Sandbox, index: u32) void {
    self.held = index;
    self.physics.setGravityScale(self.crates[index], 0);
}

fn release(self: *Sandbox) void {
    if (self.held) |i| self.physics.setGravityScale(self.crates[i], 1);
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

/// Nearest crate, machine device, or uncollected relic along the view ray within reach.
/// Terrain and machine structure occlude everything behind them.
pub fn pick(self: *const Sandbox, eye: math.Vec3, forward: math.Vec3) Target {
    const origin: Physics.Vec3 = .{ eye.x(), eye.y(), eye.z() };
    const dir: Physics.Vec3 = .{ forward.x(), forward.y(), forward.z() };
    var best: Target = .none;
    var best_distance = self.terrainDistance(origin, dir);
    const ignore: Physics.Body = if (self.held) |i| self.crates[i] else .none;
    if (self.physics.raycast(origin, dir, best_distance, ignore)) |hit| {
        best_distance = hit.distance;
        best = if (hit.user & machine_flag == 0) .{ .prop = hit.user } else if (hit.user & part_flag != 0) .none else .{ .device = .{ .machine = @intCast((hit.user >> 8) & 0xFF), .device = @intCast(hit.user & 0xFF) } };
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

pub fn cratePosition(self: *const Sandbox, index: u32) Physics.Vec3 {
    return self.physics.position(self.crates[index]).?;
}

pub fn findDevice(self: *const Sandbox, machine: usize, id: []const u8) ?DeviceRef {
    const d = self.machines[machine].machine.blueprint.findDevice(id) orelse return null;
    return .{ .machine = @intCast(machine), .device = d };
}

pub fn devicePosition(self: *const Sandbox, ref: DeviceRef) Physics.Vec3 {
    const placed = &self.machines[ref.machine];
    return self.physics.position(placed.devices[ref.device]) orelse placed.machine.devicePosition(ref.device);
}

/// Render view of crates, machine structure, and device bodies.
pub fn publishProps(self: *const Sandbox, out: []World.Prop) usize {
    var n: usize = 0;
    for (0..self.crate_count) |i| {
        if (n == out.len) return n;
        const index: u32 = @intCast(i);
        const glow: f32 = if (self.held == index) 1.35 else if (self.target == .prop and self.target.prop == index) 1.18 else 1;
        out[n] = .{ .mesh = self.catalog.content.crate, .transform = .{ .position = self.cratePosition(index) }, .tint = .{ glow, glow, glow, 1 } };
        n += 1;
    }
    for (self.machines[0..self.machine_count], 0..) |*placed, m| {
        const bp = placed.machine.blueprint;
        for (bp.parts[0..bp.part_count], 0..) |part, i| {
            if (n == out.len) return n;
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = self.physics.position(placed.parts[i]).? }, .tint = part.color, .size = part.size };
            n += 1;
        }
        for (bp.devices[0..bp.device_count], 0..) |def, d| {
            if (!def.hasBody()) continue;
            if (n == out.len) return n;
            var glow: f32 = if (self.target == .device and self.target.device.machine == m and self.target.device.device == d) 1.3 else 1;
            // Unpowered generators and actuators render dim.
            if ((def.kind == .generator and placed.machine.outputs[d][0] == 0) or (def.kind == .actuator and placed.machine.satisfaction(d) == 0)) glow *= 0.45;
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = self.physics.position(placed.devices[d]).? }, .tint = .{ def.color[0] * glow, def.color[1] * glow, def.color[2] * glow, 1 }, .size = def.size };
            n += 1;
        }
    }
    return n;
}

pub fn save(self: *const Sandbox, allocator: std.mem.Allocator, camera: Camera) ![]u8 {
    var crates: [max_crates]Save.PropState = undefined;
    for (crates[0..self.crate_count], 0..) |*p, i| p.* = .{ .id = @intCast(i), .position = self.cratePosition(@intCast(i)), .velocity = self.physics.velocity(self.crates[i]).? };
    var machines: [max_machines]Save.MachineState = undefined;
    for (machines[0..self.machine_count], self.machines[0..self.machine_count]) |*state, *placed| {
        state.* = .{ .blueprint = placed.machine.blueprint.name(), .states = placed.machine.states() };
    }
    return Save.encode(allocator, .{
        .seed = self.seed,
        .tick = self.tick,
        .player = .{ .feet = self.player.feet, .yaw = camera.yaw, .pitch = camera.pitch, .mode = self.player.mode },
        .props = crates[0..self.crate_count],
        .collected = self.modifications.slice(),
        .machines = machines[0..self.machine_count],
    });
}

/// Validates the whole document, including machine state, before applying anything; on any
/// error the session is unchanged.
pub fn restore(self: *Sandbox, allocator: std.mem.Allocator, bytes: []const u8, camera: *Camera) !void {
    const parsed = try Save.decode(allocator, bytes, self.seed, self.crate_count);
    defer parsed.deinit();
    const doc = parsed.value;
    if (doc.machines.len != self.machine_count) return error.MachineMismatch;
    var restored: [max_machines]Machine = undefined;
    for (doc.machines, self.machines[0..self.machine_count], 0..) |state, placed, m| {
        if (!std.mem.eql(u8, state.blueprint, placed.machine.blueprint.name())) return error.MachineMismatch;
        restored[m] = placed.machine;
        try restored[m].restore(state.states);
    }
    self.release();
    for (doc.props) |p| self.physics.setTransform(self.crates[p.id], p.position, p.velocity);
    for (self.machines[0..self.machine_count], restored[0..self.machine_count]) |*placed, machine| {
        placed.machine = machine;
        const bp = machine.blueprint;
        for (bp.devices[0..bp.device_count], 0..) |def, d| {
            if (def.kind == .actuator) self.physics.setTransform(placed.devices[d], machine.devicePosition(d), .{ 0, 0, 0 });
        }
    }
    self.modifications.clear();
    for (doc.collected) |ref| _ = try self.modifications.remove(ref);
    self.player = .{ .feet = doc.player.feet, .mode = doc.player.mode };
    camera.yaw = doc.player.yaw;
    camera.pitch = std.math.clamp(doc.player.pitch, -1.5, 1.5);
    camera.position = self.player.eye();
    self.tick = doc.tick;
    self.target = .none;
    self.press = null;
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
    const start = sandbox.cratePosition(1);

    // Walk forward until the middle crate blocks the player.
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 150);
    try std.testing.expect(sandbox.player.feet[2] < start[2]);
    // Look slightly down at the crate and pick it up.
    camera.pitch = -0.35;
    try run(&sandbox, &camera, .{}, .{}, 2);
    try std.testing.expect(sandbox.target == .prop);
    const picked = sandbox.target.prop;
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 1);
    try std.testing.expectEqual(@as(?u32, picked), sandbox.held);

    // Turn around over half a second, carry it, and drop it behind the spawn.
    camera.pitch = 0;
    for (0..30) |_| {
        camera.yaw += std.math.pi / 30.0;
        try run(&sandbox, &camera, .{}, .{}, 1);
    }
    try std.testing.expectEqual(@as(?u32, picked), sandbox.held);
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 90);
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 180);
    try std.testing.expectEqual(@as(?u32, null), sandbox.held);
    const dropped = sandbox.cratePosition(picked);
    try std.testing.expect(dropped[2] < start[2] - 3);
    const rest = Terrain.surface(sandbox.seed, dropped[0], dropped[2]).height;
    try std.testing.expect(dropped[1] >= rest + 0.39);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);

    // Disturb the world, then reload the saved state.
    sandbox.physics.setTransform(sandbox.crates[picked], .{ 50, 40, 50 }, .{ 0, 0, 0 });
    _ = try sandbox.modifications.remove(.{ .x = 0, .z = 0, .id = 7 });
    sandbox.player.feet = .{ 100, 100, 100 };
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expectEqualDeep(dropped, sandbox.cratePosition(picked));
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

/// Points the camera at a world position.
fn aimAt(camera: *Camera, point: Physics.Vec3) void {
    const dx = point[0] - camera.position.x();
    const dy = point[1] - camera.position.y();
    const dz = point[2] - camera.position.z();
    camera.yaw = std.math.atan2(dx, dz);
    camera.pitch = std.math.atan2(dy, @sqrt(dx * dx + dz * dz));
}

fn standAt(sandbox: *Sandbox, camera: *Camera, feet: Physics.Vec3) !void {
    sandbox.player = .{ .feet = feet };
    camera.position = sandbox.player.eye();
    try run(sandbox, camera, .{}, .{}, 30);
}

test "powered door blocks, opens from its button, lets the player through, and reloads open" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    const door = sandbox.findDevice(0, "door").?;
    const button = sandbox.findDevice(0, "button").?;
    const origin = sandbox.machines[0].machine.origin;

    // Closed: walking toward the doorway from the -z side stops at the door.
    try standAt(&sandbox, &camera, .{ origin[0], origin[1] + 0.1, origin[2] - 3 });
    camera.yaw = 0;
    camera.pitch = 0;
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 90);
    try std.testing.expect(sandbox.player.feet[2] < origin[2] - 0.2);

    // Press the button: latch → logic → actuator, then 2.9 m at 1.5 m/s.
    aimAt(&camera, sandbox.devicePosition(button));
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target == .device and sandbox.target.device.device == button.device);
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 150);
    try std.testing.expectApproxEqAbs(@as(f32, 1), sandbox.machines[0].machine.state[door.device], 0.0001);
    try std.testing.expectApproxEqAbs(origin[0] + 2.9, sandbox.devicePosition(door)[0], 0.001);

    // Walk through the open doorway.
    camera.yaw = 0;
    camera.pitch = 0;
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 90);
    try std.testing.expect(sandbox.player.feet[2] > origin[2] + 1);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    // Close it by hand, then reload: the door and its latch come back open.
    try sandbox.machines[0].machine.restore(&[_]f32{0} ** 6);
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expectEqual(@as(f32, 1), sandbox.machines[0].machine.state[door.device]);
    try std.testing.expectApproxEqAbs(origin[0] + 2.9, sandbox.devicePosition(door)[0], 0.001);
    // Stepping keeps it open: the restored latch still drives the target.
    try run(&sandbox, &camera, .{}, .{}, 30);
    try std.testing.expectEqual(@as(f32, 1), sandbox.machines[0].machine.state[door.device]);
}

test "elevator carries the player to the landing with the same machine APIs" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    const platform = sandbox.findDevice(1, "platform").?;
    const call_low = sandbox.findDevice(1, "call_low").?;
    const origin = sandbox.machines[1].machine.origin;

    // Stand on the platform and press the call button on its post.
    try standAt(&sandbox, &camera, .{ origin[0], origin[1] + 0.3, origin[2] });
    try std.testing.expect(sandbox.player.support.eql(sandbox.machines[1].devices[platform.device]));
    aimAt(&camera, sandbox.devicePosition(call_low));
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target == .device);
    // 3.9 m at 1.2 m/s ≈ 3.25 s plus signal latency.
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 220);
    try std.testing.expectApproxEqAbs(@as(f32, 1), sandbox.machines[1].machine.state[platform.device], 0.0001);
    try std.testing.expectApproxEqAbs(origin[1] + 4.2, sandbox.player.feet[1], 0.05);
    try std.testing.expect(sandbox.player.grounded);

    // Step off onto the landing; it holds the player when the platform leaves.
    camera.yaw = std.math.pi / 2.0;
    camera.pitch = 0;
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 45);
    try std.testing.expect(sandbox.player.feet[0] > origin[0] + 1.7);
    const call_high = sandbox.findDevice(1, "call_high").?;
    aimAt(&camera, sandbox.devicePosition(call_high));
    try run(&sandbox, &camera, .{}, .{}, 1);
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 240);
    try std.testing.expectEqual(@as(f32, 0), sandbox.machines[1].machine.state[platform.device]);
    try std.testing.expectApproxEqAbs(origin[1] + 4.2, sandbox.player.feet[1], 0.05);
}
