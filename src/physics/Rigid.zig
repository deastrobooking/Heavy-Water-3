//! Oriented-box rigid bodies for the built-in backend: mass, box inertia, quaternion orientation,
//! force/torque accumulation, and contacts against the terrain and the axis-aligned boxes.
//!
//! Contacts come from sample points: the rigid box's corners, edge midpoints, and face centers
//! tested against terrain and boxes, plus each nearby box's corners tested against the rigid box.
//! Velocities are solved with sequential impulses (accumulated normal and two-axis friction),
//! then positions are corrected along contact normals. This handles resting, sliding, tipping,
//! and pushing props; it is not a general polyhedral contact generator (edge-edge crossings
//! between samples can be missed).
const std = @import("std");
const R = @import("Rotation.zig");
const Physics = @import("Physics.zig");
const BoxWorld = @import("BoxWorld.zig");
const Vec3 = R.Vec3;

pub const velocity_iterations = 8;
pub const max_contacts = 96;
const linear_damping: f32 = 0.02;
const angular_damping: f32 = 0.15;
const slop: f32 = 0.004;

pub const State = struct {
    position: Vec3,
    orientation: R.Quat,
    linear: Vec3 = .{ 0, 0, 0 },
    angular: Vec3 = .{ 0, 0, 0 },
    half: Vec3,
    inv_mass: f32,
    inv_inertia: Vec3,
    friction: f32,
    force: Vec3 = .{ 0, 0, 0 },
    torque: Vec3 = .{ 0, 0, 0 },
    user: u32,

    pub fn pointVelocity(self: State, point: Vec3) Vec3 {
        return R.add(self.linear, R.cross(self.angular, R.sub(point, self.position)));
    }

    pub fn toWorld(self: State, local: Vec3) Vec3 {
        return R.add(self.position, R.rotate(self.orientation, local));
    }

    pub fn radius(self: State) f32 {
        return R.length(self.half);
    }
};

pub fn init(desc: Physics.RigidDesc) State {
    const m = desc.mass;
    const w = desc.half_extents[0] * 2;
    const h = desc.half_extents[1] * 2;
    const d = desc.half_extents[2] * 2;
    return .{
        .position = desc.position,
        .orientation = R.normalizeQuat(desc.orientation),
        .linear = desc.linear,
        .angular = desc.angular,
        .half = desc.half_extents,
        .inv_mass = 1 / m,
        .inv_inertia = .{ 12 / (m * (h * h + d * d)), 12 / (m * (w * w + d * d)), 12 / (m * (w * w + h * h)) },
        .friction = desc.friction,
        .user = desc.user,
    };
}

const Contact = struct {
    point: Vec3,
    /// Points from the obstacle into the rigid body.
    normal: Vec3,
    depth: f32,
    /// Index of the axis-aligned box touched, if any.
    other: ?usize,
    t1: Vec3 = undefined,
    t2: Vec3 = undefined,
    normal_impulse: f32 = 0,
    tangent_impulse: [2]f32 = .{ 0, 0 },
};

pub fn step(world: *BoxWorld, body: *State, dt: f32) void {
    // Integrate forces.
    body.linear[1] += Physics.gravity * dt;
    body.linear = R.add(body.linear, R.scale(body.force, body.inv_mass * dt));
    body.angular = R.add(body.angular, R.scale(R.applyInverseInertia(body.orientation, body.inv_inertia, body.torque), dt));
    body.linear = R.scale(body.linear, 1 / (1 + linear_damping * dt));
    body.angular = R.scale(body.angular, 1 / (1 + angular_damping * dt));
    body.force = .{ 0, 0, 0 };
    body.torque = .{ 0, 0, 0 };

    // Velocity constraints at the current pose.
    var contacts: [max_contacts]Contact = undefined;
    const count = gather(world, body.*, &contacts);
    for (contacts[0..count]) |*c| {
        c.t1 = R.normalize(if (@abs(c.normal[1]) < 0.9) R.cross(c.normal, .{ 0, 1, 0 }) else R.cross(c.normal, .{ 1, 0, 0 }));
        c.t2 = R.cross(c.normal, c.t1);
    }
    for (0..velocity_iterations) |_| for (contacts[0..count]) |*c| solveContact(world, body, c);

    // Integrate positions.
    body.position = R.add(body.position, R.scale(body.linear, dt));
    body.orientation = R.integrate(body.orientation, body.angular, dt);

    // Positional correction: remove remaining penetration along contact normals.
    const after = gather(world, body.*, &contacts);
    var applied: Vec3 = .{ 0, 0, 0 };
    for (contacts[0..after]) |c| {
        const other_inv = if (c.other) |o| world.bodies.items[o].inv_mass else 0;
        const share = body.inv_mass / (body.inv_mass + other_inv);
        const needed = (c.depth - slop) * 0.8 * share - R.dot(applied, c.normal);
        if (needed > 0) applied = R.add(applied, R.scale(c.normal, needed));
        if (c.other) |o| if (other_inv > 0) {
            const b = &world.bodies.items[o];
            b.position = R.sub(b.position, R.scale(c.normal, @max(0, c.depth - slop) * 0.8 * (1 - share)));
        };
    }
    body.position = R.add(body.position, applied);
}

fn solveContact(world: *BoxWorld, body: *State, c: *Contact) void {
    const r = R.sub(c.point, body.position);
    const other: ?*BoxWorld.BodyState = if (c.other) |o| &world.bodies.items[o] else null;
    const other_inv = if (other) |o| o.inv_mass else 0;
    const other_velocity = if (other) |o| o.velocity else Vec3{ 0, 0, 0 };

    // Normal impulse (inelastic), accumulated and clamped non-negative.
    var v = R.sub(body.pointVelocity(c.point), other_velocity);
    const vn = R.dot(v, c.normal);
    const kn = effectiveMass(body.*, r, c.normal) + other_inv;
    const old = c.normal_impulse;
    c.normal_impulse = @max(0, old - vn / kn);
    applyImpulse(body, other, r, R.scale(c.normal, c.normal_impulse - old));

    // Friction on two tangent axes, clamped to the Coulomb box μ·jn.
    const limit = body.friction * c.normal_impulse;
    for ([_]Vec3{ c.t1, c.t2 }, 0..) |t, k| {
        v = R.sub(body.pointVelocity(c.point), if (other) |o| o.velocity else Vec3{ 0, 0, 0 });
        const vt = R.dot(v, t);
        const kt = effectiveMass(body.*, r, t) + other_inv;
        const prev = c.tangent_impulse[k];
        c.tangent_impulse[k] = std.math.clamp(prev - vt / kt, -limit, limit);
        applyImpulse(body, other, r, R.scale(t, c.tangent_impulse[k] - prev));
    }
}

fn effectiveMass(body: State, r: Vec3, n: Vec3) f32 {
    const rn = R.cross(r, n);
    return body.inv_mass + R.dot(n, R.cross(R.applyInverseInertia(body.orientation, body.inv_inertia, rn), r));
}

fn applyImpulse(body: *State, other: ?*BoxWorld.BodyState, r: Vec3, impulse: Vec3) void {
    body.linear = R.add(body.linear, R.scale(impulse, body.inv_mass));
    body.angular = R.add(body.angular, R.applyInverseInertia(body.orientation, body.inv_inertia, R.cross(r, impulse)));
    if (other) |o| if (o.inv_mass > 0) {
        o.velocity = R.sub(o.velocity, R.scale(impulse, o.inv_mass));
    };
}

/// Sample-point contacts against terrain and every axis-aligned box near the rigid body.
fn gather(world: *const BoxWorld, body: State, out: *[max_contacts]Contact) usize {
    var n: usize = 0;
    const radius = body.radius();
    for ([_]f32{ -1, 0, 1 }) |sx| for ([_]f32{ -1, 0, 1 }) |sy| for ([_]f32{ -1, 0, 1 }) |sz| {
        if (sx == 0 and sy == 0 and sz == 0) continue;
        if (n == out.len) return n;
        const p = body.toWorld(.{ sx * body.half[0], sy * body.half[1], sz * body.half[2] });
        const g = world.ground.sample(world.ground.context, p[0], p[2]);
        if (p[1] < g.height) {
            out[n] = .{ .point = p, .normal = g.normal, .depth = (g.height - p[1]) * g.normal[1], .other = null };
            n += 1;
        }
    };
    var live = world.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = world.bodies.items[i];
        if (R.length(R.sub(b.position, body.position)) > radius + R.length(b.half)) continue;
        // Rigid sample points inside the box: push out through the nearest box face.
        for ([_]f32{ -1, 0, 1 }) |sx| for ([_]f32{ -1, 0, 1 }) |sy| for ([_]f32{ -1, 0, 1 }) |sz| {
            if (sx == 0 and sy == 0 and sz == 0) continue;
            if (n == out.len) return n;
            const p = body.toWorld(.{ sx * body.half[0], sy * body.half[1], sz * body.half[2] });
            var axis: usize = 0;
            var depth = std.math.inf(f32);
            var inside = true;
            for (0..3) |k| {
                const d = b.half[k] - @abs(p[k] - b.position[k]);
                if (d <= 0) inside = false;
                if (d < depth) {
                    depth = d;
                    axis = k;
                }
            }
            if (!inside) continue;
            var normal: Vec3 = .{ 0, 0, 0 };
            normal[axis] = if (p[axis] >= b.position[axis]) 1 else -1;
            out[n] = .{ .point = p, .normal = normal, .depth = depth, .other = i };
            n += 1;
        };
        // Box corners inside the rigid body: push out through the rigid body's nearest face.
        for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sy| for ([_]f32{ -1, 1 }) |sz| {
            if (n == out.len) return n;
            const corner: Vec3 = .{ b.position[0] + sx * b.half[0], b.position[1] + sy * b.half[1], b.position[2] + sz * b.half[2] };
            const local = R.inverseRotate(body.orientation, R.sub(corner, body.position));
            var axis: usize = 0;
            var depth = std.math.inf(f32);
            var inside = true;
            for (0..3) |k| {
                const d = body.half[k] - @abs(local[k]);
                if (d <= 0) inside = false;
                if (d < depth) {
                    depth = d;
                    axis = k;
                }
            }
            if (!inside) continue;
            var face: Vec3 = .{ 0, 0, 0 };
            face[axis] = if (local[axis] >= 0) -1 else 1;
            out[n] = .{ .point = corner, .normal = R.rotate(body.orientation, face), .depth = depth, .other = i };
            n += 1;
        };
    }
    return n;
}

/// Ray against an oriented box, in the box's local frame.
pub fn rayCast(body: State, origin: Vec3, direction: Vec3) ?Physics.BoxHit {
    const lo = R.inverseRotate(body.orientation, R.sub(origin, body.position));
    const ld = R.inverseRotate(body.orientation, direction);
    const hit = Physics.rayBox(lo, ld, .{ 0, 0, 0 }, body.half) orelse return null;
    return .{ .distance = hit.distance, .point = body.toWorld(hit.point), .normal = R.rotate(body.orientation, hit.normal) };
}
