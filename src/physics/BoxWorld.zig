//! Built-in physics backend: axis-aligned boxes without rotation, semi-implicit Euler,
//! positional contact resolution against the ground and each other, and Coulomb-style ground
//! friction. Kinematic bodies follow their velocity exactly and push dynamic bodies and the
//! character without being pushed back. It has no angular dynamics, continuous collision, restitution, or broadphase
//! (O(n²) over at most 128 bodies). Adequate for props and the character; not a rigid-body engine.
const std = @import("std");
const Handle = @import("../engine/Handle.zig");
const Physics = @import("Physics.zig");
const Vec3 = Physics.Vec3;
const BoxWorld = @This();

pub const iterations = 4;
const sleep_speed: f32 = 0.05;

pub const BodyState = struct {
    position: Vec3,
    velocity: Vec3,
    half: Vec3,
    inv_mass: f32,
    friction: f32,
    gravity_scale: f32 = 1,
    kinematic: bool = false,
    grounded: bool = false,
    user: u32,
};

ground: Physics.Ground,
bodies: Handle.Pool(Physics.BodyTag, BodyState, Physics.max_bodies) = .{},

pub fn create(self: *BoxWorld, desc: Physics.BodyDesc) !Physics.Body {
    for (desc.half_extents ++ desc.position ++ desc.velocity) |v| if (!std.math.isFinite(v)) return error.InvalidBody;
    for (desc.half_extents) |h| if (h <= 0) return error.InvalidBody;
    if (desc.motion == .dynamic and !(desc.mass > 0)) return error.InvalidBody;
    return self.bodies.add(.{
        .position = desc.position,
        .velocity = if (desc.motion == .static) .{ 0, 0, 0 } else desc.velocity,
        .half = desc.half_extents,
        .inv_mass = if (desc.motion == .dynamic) 1 / desc.mass else 0,
        .kinematic = desc.motion == .kinematic,
        .friction = desc.friction,
        .user = desc.user,
    });
}

pub fn destroy(self: *BoxWorld, body: Physics.Body) void {
    _ = self.bodies.remove(body);
}

pub fn step(self: *BoxWorld, dt: f32) void {
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = &self.bodies.items[i];
        if (b.inv_mass == 0 and !b.kinematic) continue;
        if (!b.kinematic) b.velocity[1] += Physics.gravity * b.gravity_scale * dt;
        for (0..3) |axis| b.position[axis] += b.velocity[axis] * dt;
        b.grounded = false;
    }
    for (0..iterations) |_| {
        self.solvePairs();
        self.solveGround();
    }
    live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = &self.bodies.items[i];
        if (b.inv_mass == 0 or !b.grounded) continue;
        // Friction removes up to μ·g·dt of horizontal speed per step.
        const speed = @sqrt(b.velocity[0] * b.velocity[0] + b.velocity[2] * b.velocity[2]);
        const reduced = @max(0, speed - b.friction * -Physics.gravity * dt);
        const scale = if (speed > 0) reduced / speed else 0;
        b.velocity[0] *= scale;
        b.velocity[2] *= scale;
        if (reduced < sleep_speed and @abs(b.velocity[1]) < sleep_speed) b.velocity = .{ 0, 0, 0 };
    }
}

fn solveGround(self: *BoxWorld) void {
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = &self.bodies.items[i];
        if (b.inv_mass == 0) continue;
        // Highest terrain under the footprint's corners and center supports the box.
        var support = -std.math.inf(f32);
        for ([_][2]f32{ .{ 0, 0 }, .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 } }) |c| {
            const s = self.ground.sample(self.ground.context, b.position[0] + c[0] * b.half[0], b.position[2] + c[1] * b.half[2]);
            support = @max(support, s.height);
        }
        const bottom = b.position[1] - b.half[1];
        if (bottom < support) {
            b.position[1] = support + b.half[1];
            if (b.velocity[1] < 0) b.velocity[1] = 0;
            b.grounded = true;
        }
    }
}

fn solvePairs(self: *BoxWorld) void {
    var outer = self.bodies.live.iterator(.{});
    while (outer.next()) |i| {
        var inner = self.bodies.live.iterator(.{});
        while (inner.next()) |j| {
            if (j <= i) continue;
            const a = &self.bodies.items[i];
            const b = &self.bodies.items[j];
            const total = a.inv_mass + b.inv_mass;
            if (total == 0) continue;
            var axis: usize = 0;
            var depth = std.math.inf(f32);
            for (0..3) |k| {
                const overlap = a.half[k] + b.half[k] - @abs(b.position[k] - a.position[k]);
                if (overlap <= 0) break;
                if (overlap < depth) {
                    depth = overlap;
                    axis = k;
                }
            } else {
                const sign: f32 = if (b.position[axis] >= a.position[axis]) 1 else -1;
                a.position[axis] -= sign * depth * a.inv_mass / total;
                b.position[axis] += sign * depth * b.inv_mass / total;
                // Remove approaching normal velocity (perfectly inelastic), mass-weighted.
                const approach = (b.velocity[axis] - a.velocity[axis]) * sign;
                if (approach < 0) {
                    a.velocity[axis] += sign * approach * a.inv_mass / total;
                    b.velocity[axis] -= sign * approach * b.inv_mass / total;
                }
                if (axis == 1) {
                    if (sign > 0) b.grounded = true else a.grounded = true;
                }
            }
        }
    }
}

pub fn raycast(self: *const BoxWorld, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Physics.Body) ?Physics.Hit {
    var best: ?Physics.Hit = null;
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const id = self.bodies.idAt(i);
        if (id.eql(ignore)) continue;
        const b = self.bodies.items[i];
        const hit = Physics.rayBox(origin, direction, b.position, b.half) orelse continue;
        if (hit.distance > max_distance or (best != null and hit.distance >= best.?.distance)) continue;
        best = .{ .body = id, .distance = hit.distance, .point = hit.point, .normal = hit.normal, .user = b.user };
    }
    return best;
}

pub fn moveCharacter(self: *BoxWorld, shape: Physics.Character, start: Vec3, displacement: Vec3, snap: bool) Physics.CharacterResult {
    var feet = start;
    // Sub-steps no longer than half the radius keep thin contacts from tunneling.
    const horizontal = @sqrt(displacement[0] * displacement[0] + displacement[2] * displacement[2]);
    // At least one pass, so a kinematic body moving into a standing character pushes it out.
    const steps: usize = @max(1, @as(usize, @intFromFloat(@min(64, @ceil(horizontal / (shape.radius * 0.5))))));
    for (0..steps) |_| {
        feet[0] += displacement[0] / @as(f32, @floatFromInt(steps));
        feet[2] += displacement[2] / @as(f32, @floatFromInt(steps));
        self.pushOut(shape, &feet);
    }
    var result: Physics.CharacterResult = .{ .feet = feet, .grounded = false, .hit_ceiling = false };
    const found = self.characterSupport(shape, feet);
    const support = found.height;
    const target = feet[1] + displacement[1];
    if (displacement[1] > 0) {
        const ceiling = self.characterCeiling(shape, feet);
        if (target + shape.height > ceiling) {
            result.feet[1] = @max(feet[1], ceiling - shape.height);
            result.hit_ceiling = true;
        } else result.feet[1] = target;
    } else result.feet[1] = target;
    // `snap` is the caller's decision (grounded and not jumping); platform carry may make displacement positive.
    if (result.feet[1] <= support or (snap and result.feet[1] - support <= shape.step)) {
        result.feet[1] = support;
        result.grounded = true;
        result.support = found.body;
    }
    return result;
}

/// Pushes the character's cylinder horizontally out of boxes it overlaps and nudges dynamic ones.
fn pushOut(self: *BoxWorld, shape: Physics.Character, feet: *Vec3) void {
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = &self.bodies.items[i];
        const top = b.position[1] + b.half[1];
        const bottom = b.position[1] - b.half[1];
        // Boxes low enough to step onto, or entirely overhead, do not block.
        if (feet[1] + shape.step >= top or feet[1] + shape.height <= bottom) continue;
        const cx = std.math.clamp(feet[0], b.position[0] - b.half[0], b.position[0] + b.half[0]);
        const cz = std.math.clamp(feet[2], b.position[2] - b.half[2], b.position[2] + b.half[2]);
        var dx = feet[0] - cx;
        var dz = feet[2] - cz;
        var distance = @sqrt(dx * dx + dz * dz);
        if (distance >= shape.radius) continue;
        if (distance < 1e-5) {
            // Center inside the footprint: leave through the nearest face.
            const ox = b.half[0] - @abs(feet[0] - b.position[0]);
            const oz = b.half[2] - @abs(feet[2] - b.position[2]);
            if (ox < oz) {
                dx = if (feet[0] >= b.position[0]) 1 else -1;
                dz = 0;
                feet[0] += dx * ox;
            } else {
                dx = 0;
                dz = if (feet[2] >= b.position[2]) 1 else -1;
                feet[2] += dz * oz;
            }
            distance = 0;
        } else {
            dx /= distance;
            dz /= distance;
        }
        const depth = shape.radius - distance;
        feet[0] += dx * depth;
        feet[2] += dz * depth;
        if (b.inv_mass > 0) {
            // Walking into a prop shoves it along the contact normal, capped at the push speed.
            const along = -(b.velocity[0] * dx + b.velocity[2] * dz);
            if (along < shape.push) {
                b.velocity[0] -= dx * (shape.push - along) * @min(1, b.inv_mass);
                b.velocity[2] -= dz * (shape.push - along) * @min(1, b.inv_mass);
            }
        }
    }
}

fn overlapsFootprint(shape: Physics.Character, feet: Vec3, b: BodyState) bool {
    const cx = std.math.clamp(feet[0], b.position[0] - b.half[0], b.position[0] + b.half[0]);
    const cz = std.math.clamp(feet[2], b.position[2] - b.half[2], b.position[2] + b.half[2]);
    return (feet[0] - cx) * (feet[0] - cx) + (feet[2] - cz) * (feet[2] - cz) < shape.radius * shape.radius;
}

/// Highest standable surface under the character: terrain (no body) or a box top within step reach.
fn characterSupport(self: *const BoxWorld, shape: Physics.Character, feet: Vec3) struct { height: f32, body: Physics.Body } {
    var support = self.ground.sample(self.ground.context, feet[0], feet[2]).height;
    var body: Physics.Body = .none;
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = self.bodies.items[i];
        const top = b.position[1] + b.half[1];
        if (top <= feet[1] + shape.step and top > support and overlapsFootprint(shape, feet, b)) {
            support = top;
            body = self.bodies.idAt(i);
        }
    }
    return .{ .height = support, .body = body };
}

fn characterCeiling(self: *const BoxWorld, shape: Physics.Character, feet: Vec3) f32 {
    var ceiling = std.math.inf(f32);
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = self.bodies.items[i];
        const bottom = b.position[1] - b.half[1];
        if (bottom >= feet[1] + shape.height - 0.01 and overlapsFootprint(shape, feet, b)) ceiling = @min(ceiling, bottom);
    }
    return ceiling;
}

fn flatGround(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
    return .{ .height = 0, .normal = .{ 0, 1, 0 } };
}

test "bodies fall, rest on the ground, stack, and stop sliding" {
    var physics = Physics.init(.{ .sample = flatGround });
    const a = try physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 3, 0 }, .velocity = .{ 2, 0, 0 } });
    const b = try physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0.9, 6, 0 } });
    for (0..240) |_| physics.step(1.0 / 60.0);
    const pa = physics.position(a).?;
    const pb = physics.position(b).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), pa[1], 0.01);
    try std.testing.expectEqual(@as(f32, 0), physics.velocity(a).?[0]);
    // b either stacked on a or settled beside it; it never interpenetrates or sinks.
    try std.testing.expect(pb[1] >= 0.49);
    const overlap_x = 1 - @abs(pb[0] - pa[0]);
    const overlap_y = 1 - @abs(pb[1] - pa[1]);
    try std.testing.expect(overlap_x <= 0.02 or overlap_y <= 0.02);
    try std.testing.expectError(error.InvalidBody, physics.createBody(.{ .half_extents = .{ 0, 1, 1 }, .position = .{ 0, 0, 0 } }));
}

test "raycast finds the nearest box face and respects ignore and range" {
    var physics = Physics.init(.{ .sample = flatGround });
    const near = try physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 1, 5 }, .motion = .static, .user = 7 });
    _ = try physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 1, 9 }, .motion = .static, .user = 8 });
    const hit = physics.raycast(.{ 0, 1, 0 }, .{ 0, 0, 1 }, 20, .none).?;
    try std.testing.expectEqual(@as(u32, 7), hit.user);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), hit.distance, 0.0001);
    try std.testing.expectEqual(@as(f32, -1), hit.normal[2]);
    try std.testing.expectEqual(@as(u32, 8), physics.raycast(.{ 0, 1, 0 }, .{ 0, 0, 1 }, 20, near).?.user);
    try std.testing.expect(physics.raycast(.{ 0, 1, 0 }, .{ 0, 0, 1 }, 4, .none) == null);
}

test "character is blocked by static boxes, steps onto low ones, and pushes dynamic props" {
    var physics = Physics.init(.{ .sample = flatGround });
    const shape: Physics.Character = .{};
    _ = try physics.createBody(.{ .half_extents = .{ 0.5, 2, 0.5 }, .position = .{ 0, 2, 3 }, .motion = .static });
    var feet: Physics.Vec3 = .{ 0, 0, 0 };
    for (0..120) |_| feet = physics.moveCharacter(shape, feet, .{ 0, -0.1, 0.1 }, true).feet;
    try std.testing.expect(feet[2] <= 2.5 - shape.radius + 0.001);
    try std.testing.expectEqual(@as(f32, 0), feet[1]);
    // A 0.3 m ledge is within step height.
    _ = try physics.createBody(.{ .half_extents = .{ 2, 0.15, 2 }, .position = .{ 10, 0.15, 0 }, .motion = .static });
    feet = .{ 7, 0, 0 };
    var result: Physics.CharacterResult = undefined;
    // Ledge spans x ∈ [8, 12]; stop on it at x = 11.
    for (0..40) |_| {
        result = physics.moveCharacter(shape, feet, .{ 0.1, -0.05, 0 }, true);
        feet = result.feet;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), feet[1], 0.0001);
    try std.testing.expect(result.grounded);
    const prop = try physics.createBody(.{ .half_extents = .{ 0.4, 0.4, 0.4 }, .position = .{ -5, 0.4, 1 } });
    feet = .{ -5, 0, 0 };
    for (0..30) |_| {
        feet = physics.moveCharacter(shape, feet, .{ 0, 0, 0.05 }, true).feet;
        physics.step(1.0 / 60.0);
    }
    try std.testing.expect(physics.position(prop).?[2] > 1.2);
}

test "kinematic platforms carry props, push the character, and ignore gravity" {
    var physics = Physics.init(.{ .sample = flatGround });
    const shape: Physics.Character = .{};
    const lift = try physics.createBody(.{ .half_extents = .{ 1, 0.1, 1 }, .position = .{ 0, 0.1, 0 }, .motion = .kinematic });
    const crate = try physics.createBody(.{ .half_extents = .{ 0.3, 0.3, 0.3 }, .position = .{ 0.5, 0.5, 0 } });
    physics.setVelocity(lift, .{ 0, 1, 0 });
    for (0..120) |_| physics.step(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(@as(f32, 2.1), physics.position(lift).?[1], 0.001);
    // The crate rides on top of the platform.
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), physics.position(crate).?[1], 0.02);
    // The character standing on the platform reports it as support.
    const on = physics.moveCharacter(shape, .{ -0.5, 2.2, 0 }, .{ 0, -0.1, 0 }, true);
    try std.testing.expect(on.grounded and on.support.eql(lift));
    // A door sliding into a still character pushes it out.
    const door = try physics.createBody(.{ .half_extents = .{ 1, 1, 0.1 }, .position = .{ 10, 1, 0 }, .motion = .kinematic });
    const pushed = physics.moveCharacter(shape, .{ 10.5, 0, 0.05 }, .{ 0, 0, 0 }, true);
    try std.testing.expect(@abs(pushed.feet[2]) >= 0.1 + shape.radius - 0.001);
    _ = door;
}
