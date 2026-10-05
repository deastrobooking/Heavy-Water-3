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
        const g = world.ground.at(p) orelse continue;
        if (p[1] < g.height) {
            out[n] = .{ .point = p, .normal = g.normal, .depth = (g.height - p[1]) * g.normal[1], .other = null };
            n += 1;
        }
    };
    // Sample points behind a mesh face (within 0.3 m) are pushed out along the face normal.
    var meshes = world.meshes.live.iterator(.{});
    var candidates: [32]u32 = undefined;
    while (meshes.next()) |mi| {
        const mesh = &world.meshes.items[mi].mesh;
        var outside = false;
        for (0..3) |k| outside = outside or body.position[k] + radius < mesh.lo[k] or body.position[k] - radius > mesh.hi[k];
        if (outside) continue;
        for ([_]f32{ -1, 0, 1 }) |sx| for ([_]f32{ -1, 0, 1 }) |sy| for ([_]f32{ -1, 0, 1 }) |sz| {
            if (sx == 0 and sy == 0 and sz == 0) continue;
            if (n == out.len) return n;
            const p = body.toWorld(.{ sx * body.half[0], sy * body.half[1], sz * body.half[2] });
            const count = mesh.overlap(R.sub(p, .{ 0.3, 0.3, 0.3 }), R.add(p, .{ 0.3, 0.3, 0.3 }), &candidates);
            var deepest: ?Contact = null;
            for (candidates[0..count]) |t| {
                const tri = mesh.triangles[t];
                const c = @import("TriangleMesh.zig").closestPoint(tri, p);
                const behind = -R.dot(R.sub(p, c), tri.normal);
                if (behind <= 0 or behind > 0.3 or R.length(R.sub(p, c)) > behind + 1e-4) continue;
                if (deepest == null or behind > deepest.?.depth) deepest = .{ .point = p, .normal = tri.normal, .depth = behind, .other = null };
            }
            if (deepest) |contact| {
                out[n] = contact;
                n += 1;
            }
        };
    }
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

pub const PairContact = struct { point: Vec3, normal: Vec3, depth: f32 };

/// Separating-axis test for two oriented boxes. The returned normal points from `a` to `b`.
/// Face normals and edge cross products make this exact for box overlap, including rotated cars.
pub fn pairContact(a: State, b: State) ?PairContact {
    const a_axes = [_]Vec3{
        R.rotate(a.orientation, .{ 1, 0, 0 }),
        R.rotate(a.orientation, .{ 0, 1, 0 }),
        R.rotate(a.orientation, .{ 0, 0, 1 }),
    };
    const b_axes = [_]Vec3{
        R.rotate(b.orientation, .{ 1, 0, 0 }),
        R.rotate(b.orientation, .{ 0, 1, 0 }),
        R.rotate(b.orientation, .{ 0, 0, 1 }),
    };
    const delta = R.sub(b.position, a.position);
    var best_depth = std.math.inf(f32);
    var best_axis: Vec3 = .{ 0, 1, 0 };
    for (a_axes ++ b_axes) |axis| if (!separated(a, b, delta, axis, &best_depth, &best_axis)) return null;
    for (a_axes) |aa| for (b_axes) |ba| {
        const axis = R.cross(aa, ba);
        if (R.dot(axis, axis) < 1e-8) continue;
        if (!separated(a, b, delta, axis, &best_depth, &best_axis)) return null;
    };
    if (R.dot(delta, best_axis) < 0) best_axis = R.scale(best_axis, -1);
    const pa = supportPoint(a, best_axis);
    const pb = supportPoint(b, R.scale(best_axis, -1));
    return .{ .point = R.scale(R.add(pa, pb), 0.5), .normal = best_axis, .depth = best_depth };
}

fn separated(a: State, b: State, delta: Vec3, axis_in: Vec3, depth: *f32, best: *Vec3) bool {
    const length_sq = R.dot(axis_in, axis_in);
    if (length_sq < 1e-8) return true;
    const axis = R.scale(axis_in, 1 / @sqrt(length_sq));
    const ra = projectedRadius(a, axis);
    const rb = projectedRadius(b, axis);
    const overlap = ra + rb - @abs(R.dot(delta, axis));
    if (overlap <= 0) return false;
    if (overlap < depth.*) {
        depth.* = overlap;
        best.* = axis;
    }
    return true;
}

fn projectedRadius(body: State, axis: Vec3) f32 {
    const x = R.rotate(body.orientation, .{ 1, 0, 0 });
    const y = R.rotate(body.orientation, .{ 0, 1, 0 });
    const z = R.rotate(body.orientation, .{ 0, 0, 1 });
    return body.half[0] * @abs(R.dot(axis, x)) + body.half[1] * @abs(R.dot(axis, y)) + body.half[2] * @abs(R.dot(axis, z));
}

fn supportPoint(body: State, direction: Vec3) Vec3 {
    const local = R.inverseRotate(body.orientation, direction);
    const point: Vec3 = .{
        if (@abs(local[0]) < 1e-4) 0 else if (local[0] >= 0) body.half[0] else -body.half[0],
        if (@abs(local[1]) < 1e-4) 0 else if (local[1] >= 0) body.half[1] else -body.half[1],
        if (@abs(local[2]) < 1e-4) 0 else if (local[2] >= 0) body.half[2] else -body.half[2],
    };
    return body.toWorld(point);
}

/// Resolves one rigid-rigid contact using angular effective mass and a split positional correction.
/// The small backend uses zero restitution; vehicle impacts should not add energy.
pub fn solvePair(a: *State, b: *State, contact: PairContact) void {
    const inv_total = a.inv_mass + b.inv_mass;
    if (inv_total <= 0) return;
    const correction = @max(0, contact.depth - slop) * 0.8 / inv_total;
    a.position = R.sub(a.position, R.scale(contact.normal, correction * a.inv_mass));
    b.position = R.add(b.position, R.scale(contact.normal, correction * b.inv_mass));

    const ra = R.sub(contact.point, a.position);
    const rb = R.sub(contact.point, b.position);
    const relative = R.sub(b.pointVelocity(contact.point), a.pointVelocity(contact.point));
    const closing = R.dot(relative, contact.normal);
    if (closing >= 0) return;
    const kn = effectiveMass(a.*, ra, contact.normal) + effectiveMass(b.*, rb, contact.normal);
    if (kn <= 1e-8) return;
    const impulse = R.scale(contact.normal, -closing / kn);
    a.linear = R.sub(a.linear, R.scale(impulse, a.inv_mass));
    b.linear = R.add(b.linear, R.scale(impulse, b.inv_mass));
    a.angular = R.sub(a.angular, R.applyInverseInertia(a.orientation, a.inv_inertia, R.cross(ra, impulse)));
    b.angular = R.add(b.angular, R.applyInverseInertia(b.orientation, b.inv_inertia, R.cross(rb, impulse)));
}
