//! Ambient city life on the district graph. Cars are the same raycast vehicles players drive,
//! steered by an autopilot along the right-hand lane of each road on their route. Pedestrians
//! are the player's character controller walking the walkways. Both take the shortest route
//! over the current graph, so an added bridge becomes a shortcut, and a removed one is
//! routed around on the next replan.
//!
//! Rigid bodies do not collide with each other, and characters are not bodies, so cars yield:
//! they slow for anything in their lane ahead and stop short of it. Plazas are first come,
//! first served: a car waits at the edge while another car is inside. City life is ambient and
//! is not saved; loading a world respawns it in its initial state.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Vehicle = @import("../physics/Vehicle.zig");
const Blueprint = @import("../machine/Blueprint.zig");
const District = @import("../procedural/District.zig");
const Seed = @import("../procedural/Seed.zig");
const Player = @import("../game/Player.zig");
const Profile = @import("../game/Profile.zig");
const Avatar = @import("../game/Avatar.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Catalog = @import("../asset/Catalog.zig");
const Material = @import("../render/Material.zig");
const Routes = @import("Routes.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Life = @This();

pub const car_count = 3;
pub const walker_count = 8;
pub const cruise_speed: f32 = 9;
pub const walk_input: f32 = 0.3;
/// Within this horizontal distance of a plaza centre, a car has arrived there.
const arrive_radius: f32 = 8;
/// Blocked this long, a car stops yielding for a few seconds so two cars facing each other
/// in a plaza cannot wait forever (they pass through each other: rigids do not collide).
const deadlock_time: f32 = 6;
const car_colors = [_][4]f32{ .{ 0.78, 0.36, 0.22, 1 }, .{ 0.26, 0.52, 0.66, 1 }, .{ 0.86, 0.74, 0.34, 1 } };

pub const Car = struct {
    vehicle: Vehicle,
    from: u8,
    to: u8,
    goal: u8,
    path: Routes.Path = .{},
    /// Index of `to` within `path`.
    leg: usize = 1,
    trips: u32 = 0,
    blocked: f32 = 0,
    ignore_yield: f32 = 0,
    /// Bit per plaza reached, for acceptance tests and the HUD.
    visited: u8 = 0,
    /// Held on its brakes, off the route (tests, and a future traffic stop).
    parked: bool = false,
    /// Waiting at the edge of an occupied plaza.
    waiting: bool = false,
};

pub const Walker = struct {
    player: Player,
    camera: Camera = .{},
    profile: Profile,
    from: u8,
    to: u8,
    /// +1 walks the right walkway, −1 the left.
    side: f32,
    crossing: bool = false,
    legs: u32 = 0,
    walk_phase: f32 = 0,
    walk_amount: f32 = 0,
    check_timer: f32 = 0,
    check_feet: V = @splat(0),
};

seed: u64 = 0,
active: bool = false,
revision: u64 = 0,
cars: [car_count]?Car = @splat(null),
walkers: [walker_count]Walker = undefined,
/// Recoveries: flipped or fallen cars placed back on their lane, and pedestrians moved past
/// an obstruction. Zero in a healthy district.
resets: u32 = 0,
deadlocks: u32 = 0,
/// Times a car stopped at a plaza edge for a car already inside.
plaza_waits: u32 = 0,

fn pick(seed: u64, a: u64, b: u64) u64 {
    return Seed.mix(seed ^ Seed.mix(a *% 0x9E3779B97F4A7C15 +% b));
}

/// Spawns cars (as rigid capacity allows) at alternate plazas and pedestrians along the roads.
pub fn spawn(self: *Life, physics: *Physics, routes: *const Routes, seed: u64, spec: Blueprint.Vehicle, user: u32, revision: u64) void {
    self.* = .{ .seed = seed, .active = true, .revision = revision };
    for (&self.cars, 0..) |*slot, i| {
        const start: u8 = @intCast((1 + 2 * i) % District.node_count);
        const goal: u8 = @intCast((start + 3) % District.node_count);
        const path = routes.route(start, goal) orelse continue;
        var wheels: [Vehicle.max_wheels]Vehicle.Wheel = undefined;
        for (spec.wheels[0..spec.wheel_count], wheels[0..spec.wheel_count]) |def, *w| w.* = .{ .mount = def.offset, .radius = def.radius, .rest = def.rest, .driven = def.driven, .steered = def.steered };
        const rigid = physics.createRigid(.{ .half_extents = .{ spec.size[0] / 2, spec.size[1] / 2, spec.size[2] / 2 }, .position = .{ 0, 0, 0 }, .mass = spec.mass, .user = user }) catch break;
        slot.* = .{
            .vehicle = .init(rigid, .{ .stiffness = spec.stiffness, .damping = spec.damping, .grip = spec.grip, .max_force = spec.max_force, .max_brake = spec.max_brake, .max_steer = spec.max_steer }, wheels[0..spec.wheel_count]),
            .from = start,
            .to = path.nodes[1],
            .goal = goal,
            .path = path,
            .visited = @as(u8, 1) << @intCast(start),
        };
        placeCar(physics, routes, &slot.*.?);
    }
    for (&self.walkers, 0..) |*w, i| {
        const edge = routes.edges[i % District.base_edge_count];
        const t = 0.25 + 0.5 * Seed.unit(pick(seed, 7, i));
        const side: f32 = if (i % 2 == 0) 1 else -1;
        var feet = routes.along(edge.a, edge.b, t, side * Routes.walkway_offset);
        feet[1] = District.span(routes.layout, edge).point(t)[1] + 0.05;
        w.* = .{ .player = .{ .feet = feet }, .profile = pedestrian(seed, i), .from = edge.a, .to = edge.b, .side = side, .check_feet = feet };
    }
}

/// Removes the cars' rigid bodies.
pub fn despawn(self: *Life, physics: *Physics) void {
    for (&self.cars) |*slot| if (slot.*) |car| {
        physics.destroyRigid(car.vehicle.rigid);
        slot.* = null;
    };
    self.active = false;
}

pub fn rigidCount(self: *const Life) usize {
    var n: usize = 0;
    for (self.cars) |c| n += @intFromBool(c != null);
    return n;
}

fn pedestrian(seed: u64, i: usize) Profile {
    const h = pick(seed, 11, i);
    return .{
        .skin = @intCast(h % Profile.skin_tones.len),
        .hair_color = @intCast((h >> 8) % Profile.hair_colors.len),
        .hair_style = @enumFromInt((h >> 16) % 5),
        .outfit = @intCast((h >> 24) % Profile.outfit_colors.len),
        .accent = @intCast((h >> 32) % Profile.accent_colors.len),
        .height = 0.92 + 0.16 * Seed.unit(h >> 40),
        .build = 0.88 + 0.24 * Seed.unit(h >> 20),
    };
}

/// Puts a car on its current road's lane at the `from` plaza edge, facing `to`, at rest.
fn placeCar(physics: *Physics, routes: *const Routes, car: *Car) void {
    const a = routes.layout.nodes[car.from].position;
    const b = routes.layout.nodes[car.to].position;
    const start = R.add(R.add(a, R.scale(R.normalize(.{ b[0] - a[0], 0, b[2] - a[2] }), 6)), R.scale(Routes.right(a, b), Routes.lane_offset));
    const yaw = std.math.atan2(b[0] - a[0], b[2] - a[2]);
    physics.setRigidState(car.vehicle.rigid, .{ .position = .{ start[0], a[1] + 1.3, start[2] }, .orientation = R.axisAngle(.{ 0, 1, 0 }, yaw) }, @splat(0), @splat(0));
    car.blocked = 0;
}

/// Starts car `index` at plaza `from` on the shortest route to `goal`.
pub fn sendCar(self: *Life, physics: *Physics, routes: *const Routes, index: usize, from: u8, goal: u8) !void {
    const car = if (self.cars[index]) |*c| c else return error.NoCar;
    const path = routes.route(from, goal) orelse return error.Unreachable;
    if (path.len < 2) return error.AlreadyThere;
    car.* = .{ .vehicle = car.vehicle, .from = from, .to = path.nodes[1], .goal = goal, .path = path, .visited = @as(u8, 1) << @intCast(from) };
    placeCar(physics, routes, car);
}

pub fn park(self: *Life, index: usize) void {
    if (self.cars[index]) |*car| car.parked = true;
}

fn chooseGoal(self: *const Life, index: usize, car: *const Car) u8 {
    const h = pick(self.seed, 3 + index, car.trips);
    const offset: u8 = @intCast(1 + h % (District.node_count - 1));
    return (car.to + offset) % District.node_count;
}

/// Replans a car from the plaza it is heading to. If its road closed before it drove onto the
/// deck, it replans from the plaza it is leaving; a car already on a closed road crosses it.
fn replan(car: *Car, routes: *const Routes, position: V) void {
    const origin = if (routes.connected(car.from, car.to) or routes.onRoad(car.from, car.to, position)) car.to else car.from;
    const tail = routes.route(origin, car.goal) orelse routes.route(origin, origin).?;
    if (origin == car.to) {
        car.path.nodes[0] = car.from;
        @memcpy(car.path.nodes[1 .. 1 + tail.len], tail.slice());
        car.path.len = tail.len + 1;
        car.leg = 1;
    } else {
        car.path = tail;
        car.leg = @min(1, tail.len - 1);
        car.to = car.path.nodes[car.leg];
    }
}

/// One fixed step for every car and pedestrian. `others` are positions cars must yield to
/// (players, other vehicles); cars and pedestrians are added here. Call before `Physics.step`.
pub fn step(self: *Life, physics: *Physics, routes: *const Routes, revision: u64, others: []const V, dt: f32) void {
    if (!self.active) return;
    if (revision != self.revision) {
        self.revision = revision;
        for (&self.cars) |*slot| if (slot.*) |*car| replan(car, routes, physics.rigidPose(car.vehicle.rigid).?.position);
        // Pedestrians already on a closed road finish crossing; others choose another road.
        for (&self.walkers) |*w| if (!routes.connected(w.from, w.to) and !routes.onRoad(w.from, w.to, w.player.feet)) {
            w.to = w.from;
            w.crossing = true;
        };
    }
    var obstacles: [car_count + walker_count + 16]V = undefined;
    var n: usize = 0;
    for (others[0..@min(others.len, 16)]) |p| {
        obstacles[n] = p;
        n += 1;
    }
    for (self.cars) |slot| if (slot) |car| {
        obstacles[n] = physics.rigidPose(car.vehicle.rigid).?.position;
        n += 1;
    };
    for (self.walkers) |w| {
        obstacles[n] = w.player.feet;
        n += 1;
    }
    for (&self.cars, 0..) |*slot, i| if (slot.*) |*car| self.drive(car, i, physics, routes, obstacles[0..n], dt);
    for (&self.walkers, 0..) |*w, i| self.walk(w, i, physics, routes, dt);
}

fn drive(self: *Life, car: *Car, index: usize, physics: *Physics, routes: *const Routes, obstacles: []const V, dt: f32) void {
    if (car.parked) return car.vehicle.step(physics, .{ .brake = 1 }, dt);
    const pose = physics.rigidPose(car.vehicle.rigid).?;
    const p = pose.position;
    const nodes = routes.layout.nodes;
    // Recover a car that flipped or left the deck.
    if (R.rotate(pose.orientation, .{ 0, 1, 0 })[1] < 0.5 or p[1] < @min(nodes[car.from].position[1], nodes[car.to].position[1]) - 6) {
        self.resets += 1;
        return placeCar(physics, routes, car);
    }
    const target = nodes[car.to].position;
    var arrival = @sqrt((target[0] - p[0]) * (target[0] - p[0]) + (target[2] - p[2]) * (target[2] - p[2]));
    if (arrival < arrive_radius) {
        car.visited |= @as(u8, 1) << @intCast(car.to);
        if (car.to == car.goal) {
            // A new trip starts from this plaza.
            car.trips += 1;
            car.goal = self.chooseGoal(index, car);
            car.path = routes.route(car.to, car.goal) orelse routes.route(car.to, car.to).?;
            car.leg = 0;
        }
        if (car.leg + 1 < car.path.len) {
            car.from = car.path.nodes[car.leg];
            car.leg += 1;
            car.to = car.path.nodes[car.leg];
            arrival = routes.distance(car.from, car.to);
        }
    }
    const length = routes.distance(car.from, car.to);
    const t = routes.progress(car.from, car.to, p);
    const aim = routes.along(car.from, car.to, @min(1, t + 12 / length), Routes.lane_offset);
    const yaw = R.yaw(pose.orientation);
    var angle = std.math.atan2(aim[0] - p[0], aim[2] - p[2]) - yaw;
    while (angle > std.math.pi) angle -= 2 * std.math.pi;
    while (angle < -std.math.pi) angle += 2 * std.math.pi;
    const speed = car.vehicle.forwardSpeed(physics);
    var desired: f32 = if (arrival < 30 or @abs(angle) > 0.3) 4 else cruise_speed;
    // Yield to anything in the lane ahead, and wait outside a plaza another car is inside.
    const forward: V = .{ @sin(yaw), 0, @cos(yaw) };
    const side: V = .{ forward[2], 0, -forward[0] };
    var yielding = false;
    const at_edge = arrival > District.plaza_radius - 2 and arrival < District.plaza_radius + 8;
    const wait = car.ignore_yield == 0 and at_edge and self.plazaBusy(physics, routes, car.to, car);
    if (wait) {
        if (!car.waiting) self.plaza_waits += 1;
        desired = 0;
        yielding = true;
    }
    car.waiting = wait;
    if (car.ignore_yield > 0) car.ignore_yield = @max(0, car.ignore_yield - dt) else for (obstacles) |o| {
        const rel = R.sub(o, p);
        const ahead = R.dot(rel, forward);
        if (ahead < 0.5 or ahead > 16 or @abs(R.dot(rel, side)) > 2.4 or @abs(rel[1]) > 3) continue;
        desired = @min(desired, @max(0, (ahead - 5.5) * 0.9));
        yielding = true;
    }
    car.blocked = if (yielding and speed < 0.4) car.blocked + dt else 0;
    if (car.blocked > deadlock_time) {
        car.ignore_yield = 3;
        car.blocked = 0;
        self.deadlocks += 1;
    }
    const controls: Vehicle.Controls = if (desired < 0.3)
        .{ .brake = 1 }
    else
        .{ .drive = std.math.clamp((desired - speed) * 0.4, -0.5, 1), .steer = std.math.clamp(angle * 3, -1, 1) };
    car.vehicle.step(physics, controls, dt);
}

/// Whether a car other than `self_car` is inside plaza `node`.
fn plazaBusy(self: *const Life, physics: *const Physics, routes: *const Routes, node: u8, self_car: *const Car) bool {
    const center = routes.layout.nodes[node].position;
    for (&self.cars) |*slot| if (slot.*) |*other| {
        if (other == self_car) continue;
        if (horizontalDistance(physics.rigidPose(other.vehicle.rigid).?.position, center) < District.plaza_radius - 2) return true;
    };
    return false;
}

fn walk(self: *Life, w: *Walker, index: usize, physics: *Physics, routes: *const Routes, dt: f32) void {
    const length = routes.distance(w.from, w.to);
    const margin = (District.plaza_radius - 3) / @max(length, 1);
    const offset = w.side * Routes.walkway_offset;
    const f = w.player.feet;
    var aim: V = undefined;
    if (w.crossing) {
        // Across the plaza to the start of the next walkway.
        aim = routes.along(w.from, w.to, margin, offset);
        if (w.from == w.to) aim = routes.layout.nodes[w.to].position;
        if (horizontalDistance(aim, f) < 1.2) {
            w.crossing = false;
            if (w.from == w.to) self.nextRoad(w, index, routes);
        }
    } else {
        const t = routes.progress(w.from, w.to, f);
        aim = routes.along(w.from, w.to, @min(1 - margin, t + 3 / length), offset);
        if (t >= 1 - margin - 0.5 / length) self.nextRoad(w, index, routes);
    }
    w.camera.yaw = std.math.atan2(aim[0] - f[0], aim[2] - f[2]);
    w.camera.pitch = 0;
    w.player.step(physics, &w.camera, .{ .forward = walk_input }, dt);
    const ground = @sqrt(w.player.velocity[0] * w.player.velocity[0] + w.player.velocity[2] * w.player.velocity[2]);
    w.walk_phase = @mod(w.walk_phase + ground * dt * 2.4, 2 * std.math.pi);
    w.walk_amount = if (w.player.grounded) @min(1, ground / Player.walk_speed) else 0.3;
    // Every four seconds a pedestrian must have moved a metre; otherwise step past the snag.
    w.check_timer += dt;
    if (w.check_timer >= 4) {
        if (horizontalDistance(w.player.feet, w.check_feet) < 1) {
            self.resets += 1;
            w.player = .{ .feet = .{ aim[0], aim[1] + 0.05, aim[2] } };
        }
        w.check_timer = 0;
        w.check_feet = w.player.feet;
    }
}

/// At the end of a walkway: continue onto another road from this plaza (not straight back
/// unless it is a dead end), on a seeded walkway side.
fn nextRoad(self: *const Life, w: *Walker, index: usize, routes: *const Routes) void {
    var buffer: [Routes.max_edges]u8 = undefined;
    const options = routes.neighbors(w.to, &buffer);
    if (options.len == 0) return;
    const h = pick(self.seed, 101 + index, w.legs);
    w.legs += 1;
    var next = options[h % options.len];
    if (next == w.from and options.len > 1) next = options[(h + 1) % options.len];
    w.from = w.to;
    w.to = next;
    w.side = if ((h >> 12) & 1 == 0) 1 else -1;
    w.crossing = true;
}

fn horizontalDistance(a: V, b: V) f32 {
    return @sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[2] - b[2]) * (a[2] - b[2]));
}

/// Whether any car or pedestrian is on the deck of the road between plazas `a` and `b`.
pub fn occupies(self: *const Life, physics: *const Physics, routes: *const Routes, edge: District.Edge) bool {
    if (!self.active) return false;
    for (self.cars) |slot| if (slot) |car| {
        if (routes.onRoad(edge.a, edge.b, physics.rigidPose(car.vehicle.rigid).?.position)) return true;
    };
    for (self.walkers) |w| if (routes.onRoad(edge.a, edge.b, w.player.feet)) return true;
    return false;
}

/// Cars (chassis, cabin, lumen headlamps that brighten at night, wheels) and pedestrians.
pub fn publish(self: *const Life, physics: *const Physics, catalog: *const Catalog, night: f32, out: []World.Prop, start: usize) usize {
    var n = start;
    if (!self.active) return n;
    const block = catalog.content.block;
    for (self.cars, 0..) |slot, i| if (slot) |car| {
        const pose = physics.rigidPose(car.vehicle.rigid).?;
        const color = car_colors[i % car_colors.len];
        const lamp = Material.emissive(.{ 1.0, 0.92, 0.7, 1 }, 0.25 + 0.75 * night);
        const parts = [_]struct { offset: V, size: V, tint: [4]f32 }{
            .{ .offset = .{ 0, 0, 0 }, .size = .{ 2.2, 0.7, 3.6 }, .tint = color },
            .{ .offset = .{ 0, 0.6, -0.3 }, .size = .{ 1.9, 0.55, 2.0 }, .tint = .{ 0.2, 0.26, 0.3, 1 } },
            .{ .offset = .{ -0.7, 0.1, 1.82 }, .size = .{ 0.4, 0.18, 0.06 }, .tint = lamp },
            .{ .offset = .{ 0.7, 0.1, 1.82 }, .size = .{ 0.4, 0.18, 0.06 }, .tint = lamp },
        };
        for (parts) |part| {
            if (n == out.len) return n;
            out[n] = .{ .mesh = block, .transform = .{ .position = R.add(pose.position, R.rotate(pose.orientation, part.offset)) }, .tint = part.tint, .size = part.size, .rotation = pose.orientation };
            n += 1;
        }
        for (0..car.vehicle.wheel_count) |k| {
            if (n == out.len) return n;
            const wheel = car.vehicle.wheelPose(physics, k);
            const r = car.vehicle.wheels[k].radius;
            out[n] = .{ .mesh = catalog.content.wheel, .transform = .{ .position = wheel.position }, .tint = .{ 1, 1, 1, 1 }, .size = .{ 0.32, r * 2, r * 2 }, .rotation = wheel.orientation };
            n += 1;
        }
    };
    for (self.walkers) |w| {
        if (n >= out.len) return n;
        n += Avatar.build(w.profile, .{ .feet = w.player.feet, .yaw = w.camera.yaw, .walk_phase = w.walk_phase, .walk_amount = w.walk_amount }, block, out[n..]);
    }
    return n;
}
