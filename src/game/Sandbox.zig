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
const Vehicle = @import("../physics/Vehicle.zig");
const R = Physics.Rotation;
const Player = @import("Player.zig");
const Save = @import("Save.zig");
const Build = @import("Build.zig");
const Sandbox = @This();

/// The interactive session: a walking player, physical crates, placed machines (a powered
/// door, an elevator, a drivable rover, and a player-built workshop circuit), three tools
/// (hands, build, wire), and versioned saves that describe the whole world.
pub const max_crates = 32;
pub const max_machines = 16;
pub const max_prefabs = 16;
pub const reach: f32 = 6;
pub const hold_distance: f32 = 2.2;
pub const spawn: Physics.Vec3 = .{ 0, 0, -58 };
/// Default world: crate layout relative to the spawn point (a row, plus one stacked).
const crate_offsets = [_]Physics.Vec3{ .{ -2.2, 0, 6 }, .{ 0, 0, 6 }, .{ 2.2, 0, 6 }, .{ 0, 1, 6 }, .{ -1.1, 0, 9 }, .{ 1.1, 0, 9 } };
/// Default world: machine placements relative to the spawn point.
const Placement = struct { blueprint: enum { powered_door, elevator, rover }, offset: [2]f32 };
const placements = [_]Placement{
    .{ .blueprint = .powered_door, .offset = .{ 9, 10 } },
    .{ .blueprint = .elevator, .offset = .{ -10, 8 } },
    .{ .blueprint = .rover, .offset = .{ -6, -3 } },
};
pub const chase_distance: f32 = 7.5;

pub const DeviceRef = struct { machine: u8, device: u8 };
pub const Target = union(enum) {
    none,
    prop: u32,
    relic: struct { ref: Modifications.ObjectRef, position: Physics.Vec3 },
    device: DeviceRef,
    /// A machine's static structure.
    structure: u8,
};
pub const Actions = packed struct {
    /// Tool primary: grab/press/enter (hands), place (build), connect (wire).
    interact: bool = false,
    /// Tool secondary: salvage a relic (hands), remove (build), disconnect (wire).
    secondary: bool = false,
    toggle_mode: bool = false,
    reset: bool = false,
    /// Palette item (build) or port pair (wire).
    next_item: bool = false,
    rotate: bool = false,
    /// Capture the aimed machine as a prefab (build or wire tool).
    capture: bool = false,
    /// Step the aimed transmitter or receiver's channel down or up (any tool).
    channel_down: bool = false,
    channel_up: bool = false,
    /// 0 = unchanged, 1 hands, 2 build, 3 wire.
    select_tool: u2 = 0,
};
const NearbyChunk = struct { key: Key, count: usize, objects: [Scatter.capacity]Scatter.Object };
/// A machine slot: its own editable blueprint copy, runtime, placement, and bodies.
/// `machine.blueprint` points at `blueprint`, so slots must not be copied while active.
pub const Placed = struct {
    active: bool = false,
    blueprint: Blueprint = .{},
    machine: Machine = undefined,
    yaw: u2 = 0,
    workshop: bool = false,
    devices: [Blueprint.max_devices]Physics.Body = @splat(.none),
    parts: [Blueprint.max_parts]Physics.Body = @splat(.none),
    /// Vehicle blueprints: the chassis rigid body and wheels. Parts and devices ride on it.
    vehicle: ?Vehicle = null,
};

// Physics user data: crates are their slot index; machine bodies set the top bit.
const machine_flag: u32 = 1 << 31;
const part_flag: u32 = 1 << 30;
const chassis_flag: u32 = 1 << 29;

seed: u64,
catalog: *const Catalog,
physics: Physics,
player: Player = .{},
crates: [max_crates]Physics.Body = @splat(.none),
machines: [max_machines]Placed = @splat(.{}),
/// Slot of the machine that holds loose devices placed from the palette.
workshop: ?u8 = null,
/// Button pressed during the last step; the machines see it on the next step.
press: ?DeviceRef = null,
/// World signal bus written by transmitters last step, read by receivers this step.
bus: Machine.Bus = @splat(0),
/// Vehicle machine the player is driving.
seated: ?u8 = null,
driver_input: Machine.Controls = .{},
held: ?u32 = null,
target: Target = .none,
modifications: Modifications = .{},
nearby_center: ?Key = null,
nearby: [9]NearbyChunk = undefined,
tick: u64 = 0,
tools: Build.State = .{},
/// Player-captured blueprints, placeable from the build palette after the built-ins.
prefabs: [max_prefabs]Blueprint = undefined,
prefab_count: usize = 0,
/// Prefab captured this step, for the application to export to disk.
exported: ?usize = null,
/// Short status text for the HUD (uppercase-safe), shown until `notice_until`.
notice: [64]u8 = undefined,
notice_len: usize = 0,
notice_until: u64 = 0,

/// Initializes in place: physics keeps a pointer to `seed` for terrain queries.
pub fn init(self: *Sandbox, seed: u64, catalog: *const Catalog, camera: *Camera) !void {
    self.* = .{ .seed = seed, .catalog = catalog, .physics = undefined };
    self.physics = .init(.{ .context = &self.seed, .sample = groundSample });
    const half = self.crateHalf();
    for (crate_offsets) |offset| {
        const x = spawn[0] + offset[0];
        const z = spawn[2] + offset[2];
        const y = Terrain.surface(seed, x, z).height + half[1] + offset[1] * (half[1] * 2 + 0.05) + 0.02;
        _ = try self.spawnCrate(.{ x, y, z }, .{ 0, 0, 0 });
    }
    for (placements) |placement| {
        const bp = switch (placement.blueprint) {
            .powered_door => catalog.content.powered_door,
            .elevator => catalog.content.elevator,
            .rover => catalog.content.rover,
        };
        const x = spawn[0] + placement.offset[0];
        const z = spawn[2] + placement.offset[1];
        _ = try self.spawnMachine(null, bp.*, self.groundOrigin(bp, x, z, 0), 0, false);
    }
    self.resetPlayer(camera);
}

pub fn say(self: *Sandbox, comptime fmt: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&self.notice, fmt, args) catch self.notice[0..];
    self.notice_len = text.len;
    self.notice_until = self.tick + 3 * 60;
}

pub fn noticeText(self: *const Sandbox) []const u8 {
    return if (self.tick < self.notice_until) self.notice[0..self.notice_len] else "";
}

/// Adds a validated prefab; an existing name is kept, not duplicated.
pub fn addPrefab(self: *Sandbox, bp: Blueprint) !usize {
    for (self.prefabs[0..self.prefab_count], 0..) |*existing, i| if (std.mem.eql(u8, existing.name(), bp.name())) return i;
    if (self.prefab_count == max_prefabs) return error.TooManyPrefabs;
    self.prefabs[self.prefab_count] = bp;
    self.prefab_count += 1;
    return self.prefab_count - 1;
}

pub fn crateHalf(self: *const Sandbox) Physics.Vec3 {
    return self.catalog.mesh(self.catalog.content.crate).?.model.halfExtents();
}

pub fn crateLive(self: *const Sandbox, index: usize) bool {
    return self.physics.valid(self.crates[index]);
}

pub fn spawnCrate(self: *Sandbox, position: Physics.Vec3, velocity: Physics.Vec3) !u32 {
    const slot = for (self.crates, 0..) |c, i| {
        if (!self.physics.valid(c)) break i;
    } else return error.TooManyCrates;
    try self.spawnCrateAt(slot, position, velocity);
    return @intCast(slot);
}

fn spawnCrateAt(self: *Sandbox, slot: usize, position: Physics.Vec3, velocity: Physics.Vec3) !void {
    self.crates[slot] = try self.physics.createBody(.{ .half_extents = self.crateHalf(), .position = position, .velocity = velocity, .mass = 20, .user = @intCast(slot) });
}

pub fn removeCrate(self: *Sandbox, index: u32) void {
    if (self.held == index) self.release();
    self.physics.destroyBody(self.crates[index]);
    self.crates[index] = .none;
}

pub fn machineCount(self: *const Sandbox) usize {
    var n: usize = 0;
    for (self.machines) |placed| n += @intFromBool(placed.active);
    return n;
}

pub fn yawRotation(yaw: u2) R.Quat {
    return R.axisAngle(.{ 0, 1, 0 }, @as(f32, @floatFromInt(yaw)) * std.math.pi / 2.0);
}

/// Box half extents after a quarter-turn yaw.
pub fn turnedHalf(size: [3]f32, yaw: u2) Physics.Vec3 {
    return if (yaw % 2 == 1) .{ size[2] / 2, size[1] / 2, size[0] / 2 } else .{ size[0] / 2, size[1] / 2, size[2] / 2 };
}

/// Origin on the highest terrain under a blueprint's rotated structure footprint, so the
/// foundation never floats; parts are authored to extend below the origin. Vehicles get
/// their spawn height above their ride height.
pub fn groundOrigin(self: *const Sandbox, bp: *const Blueprint, x: f32, z: f32, yaw: u2) Physics.Vec3 {
    if (bp.vehicle) |v| {
        const wheel = v.wheels[0];
        return .{ x, Terrain.surface(self.seed, x, z).height + wheel.radius + wheel.rest - wheel.offset[1] + 0.1, z };
    }
    const bounds = Build.footprint(bp, yaw);
    var y = -std.math.inf(f32);
    var sx = bounds.lo[0];
    while (sx <= bounds.hi[0]) : (sx += 1) {
        var sz = bounds.lo[2];
        while (sz <= bounds.hi[2]) : (sz += 1) y = @max(y, Terrain.surface(self.seed, x + sx, z + sz).height);
    }
    return .{ x, if (std.math.isFinite(y)) y else Terrain.surface(self.seed, x, z).height, z };
}

fn deviceUser(m: usize, d: usize) u32 {
    return machine_flag | @as(u32, @intCast(m)) << 8 | @as(u32, @intCast(d));
}

/// Places a copy of `bp` in a machine slot (a free one when `slot` is null) with bodies for
/// its structure and physical devices, or a chassis for vehicles.
pub fn spawnMachine(self: *Sandbox, slot: ?usize, bp: Blueprint, origin: Physics.Vec3, yaw: u2, workshop: bool) !u8 {
    const m = slot orelse for (self.machines, 0..) |placed, i| {
        if (!placed.active) break i;
    } else return error.TooManyMachines;
    const placed = &self.machines[m];
    std.debug.assert(!placed.active);
    placed.* = .{ .active = true, .blueprint = bp, .yaw = yaw, .workshop = workshop };
    placed.machine = .init(&placed.blueprint, origin);
    placed.machine.rotation = yawRotation(yaw);
    errdefer self.removeMachine(@intCast(m));
    if (bp.vehicle) |v| {
        const rigid = try self.physics.createRigid(.{ .half_extents = halve(v.size), .position = origin, .orientation = placed.machine.rotation, .mass = v.mass, .user = machine_flag | chassis_flag | @as(u32, @intCast(m)) << 8 | v.seat });
        var wheels: [Vehicle.max_wheels]Vehicle.Wheel = undefined;
        for (v.wheels[0..v.wheel_count], wheels[0..v.wheel_count]) |def, *w| w.* = .{ .mount = def.offset, .radius = def.radius, .rest = def.rest, .driven = def.driven, .steered = def.steered };
        placed.vehicle = .init(rigid, .{ .stiffness = v.stiffness, .damping = v.damping, .grip = v.grip, .max_force = v.max_force, .max_brake = v.max_brake, .max_steer = v.max_steer }, wheels[0..v.wheel_count]);
        return @intCast(m);
    }
    for (bp.parts[0..bp.part_count], 0..) |part, i| {
        placed.parts[i] = try self.physics.createBody(.{ .half_extents = turnedHalf(part.size, yaw), .position = placed.machine.worldOffset(part.offset), .motion = .static, .user = machine_flag | part_flag | @as(u32, @intCast(m)) << 8 | @as(u32, @intCast(i)) });
    }
    for (0..bp.device_count) |d| try self.createDeviceBody(m, d);
    return @intCast(m);
}

fn createDeviceBody(self: *Sandbox, m: usize, d: usize) !void {
    const placed = &self.machines[m];
    const def = placed.blueprint.devices[d];
    if (!def.hasBody() or placed.vehicle != null) return;
    placed.devices[d] = try self.physics.createBody(.{
        .half_extents = turnedHalf(def.size, placed.yaw),
        .position = placed.machine.devicePosition(d),
        .motion = if (def.kind == .actuator) .kinematic else .static,
        .user = deviceUser(m, d),
    });
}

pub fn removeMachine(self: *Sandbox, m: u8) void {
    const placed = &self.machines[m];
    if (!placed.active) return;
    if (self.seated == m) self.seated = null;
    for (placed.devices ++ placed.parts) |body| self.physics.destroyBody(body);
    if (placed.vehicle) |v| self.physics.destroyRigid(v.rigid);
    if (self.workshop == m) self.workshop = null;
    if (self.tools.wire_from) |w| if (w.machine == m) {
        self.tools.wire_from = null;
    };
    placed.* = .{};
}

/// Adds a validated device to the workshop machine (creating it at `point` if needed).
pub fn addWorkshopDevice(self: *Sandbox, def: Blueprint.DocDevice, point: Physics.Vec3) !DeviceRef {
    const m = self.workshop orelse blk: {
        var bp: Blueprint = .{};
        try bp.setName("workshop");
        const slot = try self.spawnMachine(null, bp, point, 0, true);
        self.workshop = slot;
        break :blk slot;
    };
    const placed = &self.machines[m];
    var local = def;
    local.offset = R.sub(point, placed.machine.origin);
    const d = try placed.blueprint.addDevice(local);
    placed.machine.reconfigure();
    self.createDeviceBody(m, d) catch |err| {
        placed.blueprint.removeDevice(d) catch {};
        placed.machine.reconfigure();
        return err;
    };
    return .{ .machine = m, .device = d };
}

/// Removes one workshop device; later devices shift down and their bodies are re-tagged.
pub fn removeWorkshopDevice(self: *Sandbox, ref: DeviceRef) !void {
    const placed = &self.machines[ref.machine];
    self.physics.destroyBody(placed.devices[ref.device]);
    try placed.blueprint.removeDevice(ref.device);
    placed.machine.removeDevice(ref.device);
    placed.machine.reconfigure();
    const count = placed.blueprint.device_count;
    std.mem.copyForwards(Physics.Body, placed.devices[ref.device..count], placed.devices[ref.device + 1 .. count + 1]);
    placed.devices[count] = .none;
    for (placed.devices[ref.device..count], ref.device..) |body, d| self.physics.setUser(body, deviceUser(ref.machine, d));
    if (self.tools.wire_from) |w| if (w.machine == ref.machine) {
        self.tools.wire_from = null;
    };
    if (count == 0) self.removeMachine(ref.machine);
}

pub fn halve(size: [3]f32) Physics.Vec3 {
    return .{ size[0] / 2, size[1] / 2, size[2] / 2 };
}

fn groundSample(context: ?*const anyopaque, x: f32, z: f32) Physics.GroundSample {
    const seed: *const u64 = @ptrCast(@alignCast(context.?));
    const s = Terrain.surface(seed.*, x, z);
    return .{ .height = s.height, .normal = s.normal };
}

pub fn resetPlayer(self: *Sandbox, camera: *Camera) void {
    self.release();
    self.seated = null;
    camera.* = .{ .yaw = 0, .pitch = -0.2 };
    self.player = .{ .feet = .{ spawn[0], Terrain.surface(self.seed, spawn[0], spawn[2]).height, spawn[2] }, .mode = self.player.mode };
    if (self.player.mode == .fly) {
        self.player.feet[1] += 20;
    }
    camera.position = self.player.eye();
}

pub fn step(self: *Sandbox, camera: *Camera, input: Input, actions: Actions, dt: f32) !void {
    if (actions.reset) self.resetPlayer(camera);
    if (actions.toggle_mode and self.seated == null) self.player.setMode(if (self.player.mode == .walk) .fly else .walk, camera.*);
    if (actions.select_tool != 0 and self.seated == null) Build.selectTool(self, @enumFromInt(actions.select_tool - 1));
    var primary = actions.interact;
    if (self.seated != null) {
        if (primary) self.exitVehicle(camera) else self.driver_input = .{ .throttle = input.forward, .steer = input.right, .brake = @floatFromInt(@intFromBool(input.jump)) };
        primary = false;
    }
    if (self.seated == null) self.player.step(&self.physics, camera, input, dt);
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
    if (self.seated) |m| {
        self.followVehicle(m, camera);
        self.target = .none;
        return;
    }
    self.refreshNearby(camera.position);
    // Build and wire tools reach farther and ignore relics.
    const hands = self.tools.tool == .hands;
    self.target = self.pick(camera.position, camera.forward(), if (hands) reach else Build.build_reach, hands);
    if (actions.channel_down or actions.channel_up) Build.adjustChannel(self, if (actions.channel_up) 1 else -1);
    switch (self.tools.tool) {
        .hands => {
            if (primary) {
                if (self.held != null) self.release() else switch (self.target) {
                    .prop => |i| self.hold(i),
                    .device => |d| switch (self.machines[d.machine].blueprint.devices[d.device].kind) {
                        .button => self.press = d,
                        .seat => self.enterVehicle(d.machine, camera),
                        else => {},
                    },
                    else => {},
                }
            }
            if (actions.secondary) switch (self.target) {
                .relic => |relic| _ = try self.modifications.remove(relic.ref),
                else => {},
            };
        },
        .build, .wire => try Build.update(self, camera.*, primary, actions),
    }
}

pub fn enterVehicle(self: *Sandbox, machine: u8, camera: *Camera) void {
    self.release();
    self.seated = machine;
    self.driver_input = .{};
    const pose = self.physics.rigidPose(self.machines[machine].vehicle.?.rigid).?;
    camera.yaw = R.yaw(pose.orientation);
    camera.pitch = -0.25;
    self.followVehicle(machine, camera);
}

/// Steps out to the vehicle's left, onto the terrain.
pub fn exitVehicle(self: *Sandbox, camera: *Camera) void {
    const m = self.seated orelse return;
    self.seated = null;
    const placed = &self.machines[m];
    const pose = self.physics.rigidPose(placed.vehicle.?.rigid).?;
    const side = R.add(pose.position, R.rotate(pose.orientation, .{ -(placed.blueprint.vehicle.?.size[0] / 2 + 1.2), 0, 0 }));
    self.player = .{ .feet = .{ side[0], Terrain.surface(self.seed, side[0], side[2]).height, side[2] }, .mode = .walk };
    camera.pitch = -0.2;
    camera.position = self.player.eye();
}

/// Seats the player and places the chase camera behind and above the chassis.
fn followVehicle(self: *Sandbox, m: u8, camera: *Camera) void {
    const placed = &self.machines[m];
    const v = placed.blueprint.vehicle.?;
    const seat = placed.machine.devicePosition(v.seat);
    self.player.feet = .{ seat[0], seat[1] - 0.5, seat[2] };
    self.player.velocity = .{ 0, 0, 0 };
    self.player.grounded = false;
    self.player.support = .none;
    const pose = self.physics.rigidPose(placed.vehicle.?.rigid).?;
    const f = camera.forward();
    var eye = math.vec3(pose.position[0] - f.x() * chase_distance, pose.position[1] + 1.5 - f.y() * chase_distance, pose.position[2] - f.z() * chase_distance);
    const ground = Terrain.surface(self.seed, eye.x(), eye.z()).height + 0.6;
    if (eye.y() < ground) eye = math.vec3(eye.x(), ground, eye.z());
    camera.position = eye;
}

/// Advances every machine one fixed step, then drives actuator bodies to their new positions
/// through velocity so physics pushes whatever they touch, and feeds vehicle controls.
fn stepMachines(self: *Sandbox, dt: f32) void {
    const previous = self.bus;
    self.bus = @splat(0);
    defer for (&self.machines) |*placed| if (placed.active) placed.machine.transmit(&self.bus);
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        var env: Machine.Environment = .{ .player_feet = self.player.feet, .bus = &previous };
        if (self.press) |p| if (p.machine == m) {
            env.pressed = p.device;
        };
        if (placed.vehicle) |*vehicle| {
            const driving = self.seated == @as(u8, @intCast(m));
            const pose = self.physics.rigidPose(vehicle.rigid).?;
            placed.machine.origin = pose.position;
            placed.machine.rotation = pose.orientation;
            if (driving) env.controls = self.driver_input;
            placed.machine.step(env, dt);
            const v = placed.blueprint.vehicle.?;
            const out = placed.machine.outputs;
            // An empty seat sets the parking brake.
            const brake = if (driving) out[v.seat][3] else 1;
            vehicle.step(&self.physics, .{ .drive = out[v.motor][2], .steer = out[v.steering][1], .brake = brake }, dt);
            continue;
        }
        placed.machine.step(env, dt);
        const bp = &placed.blueprint;
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

pub fn release(self: *Sandbox) void {
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

/// Nearest crate, machine device or structure, or (when `relics`) uncollected relic along
/// the view ray within `max_distance`. Terrain and machine structure occlude what is behind.
pub fn pick(self: *const Sandbox, eye: math.Vec3, forward: math.Vec3, max_distance: f32, relics: bool) Target {
    const origin: Physics.Vec3 = .{ eye.x(), eye.y(), eye.z() };
    const dir: Physics.Vec3 = .{ forward.x(), forward.y(), forward.z() };
    var best: Target = .none;
    var best_distance = self.terrainDistance(origin, dir, max_distance);
    const ignore: Physics.Body = if (self.held) |i| self.crates[i] else .none;
    if (self.physics.raycast(origin, dir, best_distance, ignore)) |hit| {
        best_distance = hit.distance;
        // Crates carry their slot; machine devices and vehicle chassis (→ seat) carry machine
        // and device; structure parts carry their machine.
        const machine: u8 = @intCast((hit.user >> 8) & 0xFF);
        best = if (hit.user & machine_flag == 0) .{ .prop = hit.user } else if (hit.user & part_flag != 0) .{ .structure = machine } else .{ .device = .{ .machine = machine, .device = @intCast(hit.user & 0xFF) } };
    }
    if (relics) for (self.nearby) |chunk| for (chunk.objects[0..chunk.count]) |object| {
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

fn terrainDistance(self: *const Sandbox, origin: Physics.Vec3, dir: Physics.Vec3, max_distance: f32) f32 {
    var t: f32 = 0;
    while (t < max_distance) : (t += 0.1) {
        if (origin[1] + dir[1] * t < Terrain.surface(self.seed, origin[0] + dir[0] * t, origin[2] + dir[2] * t).height) return t;
    }
    return max_distance;
}

pub fn cratePosition(self: *const Sandbox, index: u32) Physics.Vec3 {
    return self.physics.position(self.crates[index]).?;
}

pub fn findDevice(self: *const Sandbox, machine: usize, id: []const u8) ?DeviceRef {
    const d = self.machines[machine].blueprint.findDevice(id) orelse return null;
    return .{ .machine = @intCast(machine), .device = d };
}

pub fn devicePosition(self: *const Sandbox, ref: DeviceRef) Physics.Vec3 {
    const placed = &self.machines[ref.machine];
    return self.physics.position(placed.devices[ref.device]) orelse placed.machine.devicePosition(ref.device);
}

/// Render view of crates, machines, and (with the build or wire tool) previews and wires.
pub fn publishProps(self: *const Sandbox, out: []World.Prop) usize {
    var n: usize = 0;
    for (0..max_crates) |i| {
        if (!self.crateLive(i)) continue;
        if (n == out.len) return n;
        const index: u32 = @intCast(i);
        const glow: f32 = if (self.held == index) 1.35 else if (self.target == .prop and self.target.prop == index) 1.18 else 1;
        out[n] = .{ .mesh = self.catalog.content.crate, .transform = .{ .position = self.cratePosition(index) }, .tint = .{ glow, glow, glow, 1 } };
        n += 1;
    }
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        const bp = &placed.blueprint;
        if (placed.vehicle) |vehicle| {
            n = self.publishVehicle(placed, vehicle, m, out, n);
            continue;
        }
        const rotation = placed.machine.rotation;
        const structure_glow: f32 = if (self.tools.tool == .build and self.target == .structure and self.target.structure == m) 1.25 else 1;
        for (bp.parts[0..bp.part_count]) |part| {
            if (n == out.len) return n;
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = placed.machine.worldOffset(part.offset) }, .tint = .{ part.color[0] * structure_glow, part.color[1] * structure_glow, part.color[2] * structure_glow, 1 }, .size = part.size, .rotation = rotation };
            n += 1;
        }
        for (bp.devices[0..bp.device_count], 0..) |def, d| {
            if (!def.hasBody()) continue;
            if (n == out.len) return n;
            const targeted = self.target == .device and self.target.device.machine == m and self.target.device.device == d;
            const selected = if (self.tools.wire_from) |w| w.machine == m and w.device == d else false;
            var glow: f32 = if (selected) 1.6 else if (targeted) 1.3 else structure_glow;
            // Unpowered generators and actuators render dim; lamps glow when lit.
            if ((def.kind == .generator and placed.machine.outputs[d][0] == 0) or (def.kind == .actuator and placed.machine.satisfaction(d) == 0)) glow *= 0.45;
            if (def.kind == .lamp) glow *= if (placed.machine.outputs[d][2] > 0) 1.8 else 0.35;
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = self.devicePosition(.{ .machine = @intCast(m), .device = @intCast(d) }) }, .tint = .{ def.color[0] * glow, def.color[1] * glow, def.color[2] * glow, 1 }, .size = def.size, .rotation = rotation };
            n += 1;
        }
    }
    return Build.publish(self, out, n);
}

/// Chassis parts and devices follow the rigid pose; wheels follow the suspension and spin.
fn publishVehicle(self: *const Sandbox, placed: *const Placed, vehicle: Vehicle, m: usize, out: []World.Prop, start: usize) usize {
    var n = start;
    const pose = self.physics.rigidPose(vehicle.rigid).?;
    const frame: Machine = blk: {
        var copy = placed.machine;
        copy.origin = pose.position;
        copy.rotation = pose.orientation;
        break :blk copy;
    };
    const bp = &placed.blueprint;
    const glow: f32 = if (self.target == .device and self.target.device.machine == m) 1.2 else 1;
    for (bp.parts[0..bp.part_count]) |part| {
        if (n == out.len) return n;
        out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = frame.worldOffset(part.offset) }, .tint = .{ part.color[0] * glow, part.color[1] * glow, part.color[2] * glow, 1 }, .size = part.size, .rotation = pose.orientation };
        n += 1;
    }
    for (bp.devices[0..bp.device_count], 0..) |def, d| {
        if (!def.visible()) continue;
        if (n == out.len) return n;
        out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = frame.devicePosition(d) }, .tint = def.color, .size = def.size, .rotation = pose.orientation };
        n += 1;
    }
    for (0..vehicle.wheel_count) |i| {
        if (n == out.len) return n;
        const wheel = vehicle.wheelPose(&self.physics, i);
        const r = vehicle.wheels[i].radius;
        out[n] = .{ .mesh = self.catalog.content.wheel, .transform = .{ .position = wheel.position }, .tint = .{ 1, 1, 1, 1 }, .size = .{ 0.32, r * 2, r * 2 }, .rotation = wheel.orientation };
        n += 1;
    }
    return n;
}

pub fn save(self: *const Sandbox, allocator: std.mem.Allocator, camera: Camera) ![]u8 {
    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var crates: [max_crates]Save.PropState = undefined;
    var crate_count: usize = 0;
    for (0..max_crates) |i| {
        if (!self.crateLive(i)) continue;
        crates[crate_count] = .{ .id = @intCast(i), .position = self.cratePosition(@intCast(i)), .velocity = self.physics.velocity(self.crates[i]).? };
        crate_count += 1;
    }
    var machines: [max_machines]Save.MachineState = undefined;
    var machine_count: usize = 0;
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        var state: Save.MachineState = .{
            .slot = @intCast(m),
            .blueprint = try placed.blueprint.toDoc(arena),
            .origin = placed.machine.origin,
            .yaw = placed.yaw,
            .workshop = placed.workshop,
            .states = placed.machine.states(),
        };
        if (placed.vehicle) |vehicle| {
            const pose = self.physics.rigidPose(vehicle.rigid).?;
            const motion = self.physics.rigidVelocity(vehicle.rigid).?;
            state.body = .{ .position = pose.position, .orientation = pose.orientation, .linear = motion.linear, .angular = motion.angular };
        }
        machines[machine_count] = state;
        machine_count += 1;
    }
    return Save.encode(allocator, .{
        .seed = self.seed,
        .tick = self.tick,
        .player = .{ .feet = self.player.feet, .yaw = camera.yaw, .pitch = camera.pitch, .mode = self.player.mode },
        .props = crates[0..crate_count],
        .collected = self.modifications.slice(),
        .machines = machines[0..machine_count],
        .prefabs = prefabs: {
            const docs = try arena.alloc(Blueprint.Doc, self.prefab_count);
            for (docs, self.prefabs[0..self.prefab_count]) |*doc, *bp| doc.* = try bp.toDoc(arena);
            break :prefabs docs;
        },
    });
}

/// Rebuilds the world from a save. Every blueprint is re-validated, every machine state is
/// restored into a scratch copy, and body capacity is checked before anything is torn down;
/// on any error the session is unchanged.
pub fn restore(self: *Sandbox, allocator: std.mem.Allocator, bytes: []const u8, camera: *Camera) !void {
    const parsed = try Save.decode(allocator, bytes, self.seed, max_crates, max_machines);
    defer parsed.deinit();
    const doc = parsed.value;
    const blueprints = try allocator.alloc(Blueprint, doc.machines.len);
    defer allocator.free(blueprints);
    var bodies: usize = doc.props.len;
    var rigids: usize = 0;
    var workshops: usize = 0;
    for (doc.machines, blueprints) |state, *bp| {
        bp.* = try Blueprint.fromDoc(state.blueprint);
        if ((state.body != null) != (bp.vehicle != null)) return error.MachineMismatch;
        var scratch = Machine.init(bp, state.origin);
        try scratch.restore(state.states);
        workshops += @intFromBool(state.workshop);
        if (bp.vehicle != null) {
            rigids += 1;
        } else {
            bodies += bp.part_count;
            for (bp.devices[0..bp.device_count]) |d| bodies += @intFromBool(d.hasBody());
        }
    }
    if (bodies > Physics.max_bodies or rigids > Physics.max_rigids or workshops > 1) return error.InvalidSave;
    if (doc.prefabs.len > max_prefabs) return error.InvalidSave;
    var prefabs: [max_prefabs]Blueprint = undefined;
    for (doc.prefabs, prefabs[0..doc.prefabs.len]) |source, *bp| bp.* = try Blueprint.fromDoc(source);

    // Validated: tear down and rebuild.
    self.release();
    self.seated = null;
    self.tools = .{};
    for (0..max_machines) |m| self.removeMachine(@intCast(m));
    for (0..max_crates) |i| if (self.crateLive(i)) self.removeCrate(@intCast(i));
    for (doc.props) |p| try self.spawnCrateAt(p.id, p.position, p.velocity);
    for (doc.machines, blueprints) |state, bp| {
        const m = try self.spawnMachine(state.slot, bp, state.origin, @intCast(state.yaw), state.workshop);
        const placed = &self.machines[m];
        try placed.machine.restore(state.states);
        if (state.workshop) self.workshop = m;
        if (placed.vehicle) |vehicle| {
            const body = state.body.?;
            self.physics.setRigidState(vehicle.rigid, .{ .position = body.position, .orientation = body.orientation }, body.linear, body.angular);
        }
        for (bp.devices[0..bp.device_count], 0..) |def, d| {
            if (def.kind == .actuator) self.physics.setTransform(placed.devices[d], placed.machine.devicePosition(d), .{ 0, 0, 0 });
        }
    }
    @memcpy(self.prefabs[0..doc.prefabs.len], prefabs[0..doc.prefabs.len]);
    self.prefab_count = doc.prefabs.len;
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
    try run(&sandbox, &camera, .{}, .{ .secondary = true }, 1);
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

test "rover: enter from its side, drive forward on machine power, exit, park, and reload its pose" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    const m: u8 = 2;
    const rigid = sandbox.machines[m].vehicle.?.rigid;
    try run(&sandbox, &camera, .{}, .{}, 120);
    const parked = sandbox.physics.rigidPose(rigid).?;
    // Settled on four wheels, aligned with the terrain it parked on (the spawn area slopes).
    const ground_normal = Terrain.surface(sandbox.seed, parked.position[0], parked.position[2]).normal;
    try std.testing.expect(R.dot(R.rotate(parked.orientation, .{ 0, 1, 0 }), ground_normal) > 0.98);
    try std.testing.expect(R.length(sandbox.physics.rigidVelocity(rigid).?.linear) < 0.02);
    for (sandbox.machines[m].vehicle.?.state[0..4]) |w| try std.testing.expect(w.contact);

    // Walk up beside it, aim at the chassis, and get in.
    try standAt(&sandbox, &camera, .{ parked.position[0] - 3, Terrain.surface(sandbox.seed, parked.position[0] - 3, parked.position[2]).height, parked.position[2] });
    aimAt(&camera, parked.position);
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target == .device and sandbox.target.device.machine == m);
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 1);
    try std.testing.expectEqual(@as(?u8, m), sandbox.seated);

    // Two seconds of throttle moves it forward along its heading.
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 120);
    const moved = sandbox.physics.rigidPose(rigid).?;
    const heading = R.rotate(parked.orientation, .{ 0, 0, 1 });
    try std.testing.expect(R.dot(R.sub(moved.position, parked.position), heading) > 4);
    try std.testing.expect(sandbox.machines[m].machine.network(sandbox.machines[m].machine.blueprint.vehicle.?.motor).?.demand > 0);

    // Exit: the parking brake stops it and the player stands beside it, outside the chassis.
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 180);
    try std.testing.expectEqual(@as(?u8, null), sandbox.seated);
    try std.testing.expect(R.length(sandbox.physics.rigidVelocity(rigid).?.linear) < 0.1);
    try std.testing.expect(sandbox.player.grounded);
    const stopped = sandbox.physics.rigidPose(rigid).?;
    const offset = R.inverseRotate(stopped.orientation, R.sub(sandbox.player.feet, stopped.position));
    try std.testing.expect(@abs(offset[0]) > 1.1 + sandbox.player.shape.radius - 0.01);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    sandbox.physics.setRigidState(rigid, parked, .{ 0, 0, 0 }, .{ 0, 0, 0 });
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    // Loading rebuilds the world, so the chassis has a new handle.
    try std.testing.expectEqualDeep(stopped, sandbox.physics.rigidPose(sandbox.machines[m].vehicle.?.rigid).?);
}
