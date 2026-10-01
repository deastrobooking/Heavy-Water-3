//! Spring bones: verlet-integrated joint chains for hair, skirts, ribbons and
//! accessories, with capsule collision against the body.
//!
//! Each chain is a run of joints [j0, j1, ..., jn] where j0's *position* comes
//! from animation (its parent is e.g. the head or hips) and the rotations of
//! j0..j(n-1) are simulated. Particles live at joint positions.

const std = @import("std");
const m = @import("math.zig");
const skel_mod = @import("skeleton.zig");
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Skeleton = skel_mod.Skeleton;
const Pose = skel_mod.Pose;
const Allocator = std.mem.Allocator;

/// Capsule between two joints' current positions (a == b gives a sphere).
/// `offset_a/b` are in the joint's local frame (so a sphere can sit in front of
/// the chest, etc.).
pub const Collider = struct {
    a: u16,
    b: u16,
    radius: f32,
    offset_a: Vec3 = Vec3.zero,
    offset_b: Vec3 = Vec3.zero,
};

pub const Params = struct {
    /// Pull toward the animated rest direction per step (0 = rope, 1 = rigid).
    stiffness: f32 = 0.08,
    /// Velocity damping per step.
    damping: f32 = 0.12,
    gravity: Vec3 = Vec3.init(0, -9.81, 0),
    /// Fraction of gravity applied (hair floats a little, skirts hang).
    gravity_scale: f32 = 0.5,
    /// Particle collision radius.
    radius: f32 = 0.01,
};

pub const Chain = struct {
    joints: []u16,
    lengths: []f32,
    pos: []Vec3,
    prev: []Vec3,
    params: Params,

    pub fn init(gpa: Allocator, skel: *const Skeleton, joints: []const u16, params: Params) !Chain {
        std.debug.assert(joints.len >= 2);
        const js = try gpa.dupe(u16, joints);
        errdefer gpa.free(js);
        const lens = try gpa.alloc(f32, joints.len);
        errdefer gpa.free(lens);
        lens[0] = 0;
        for (1..joints.len) |i| lens[i] = skel.rest_world.items[js[i]].distance(skel.rest_world.items[js[i - 1]]);
        const pos = try gpa.alloc(Vec3, joints.len);
        errdefer gpa.free(pos);
        const prev = try gpa.alloc(Vec3, joints.len);
        for (js, 0..) |j, i| {
            pos[i] = skel.rest_world.items[j];
            prev[i] = pos[i];
        }
        return .{ .joints = js, .lengths = lens, .pos = pos, .prev = prev, .params = params };
    }

    pub fn deinit(c: *Chain, gpa: Allocator) void {
        gpa.free(c.joints);
        gpa.free(c.lengths);
        gpa.free(c.pos);
        gpa.free(c.prev);
    }

    /// Snap particles to the current animated pose (call on teleport/spawn).
    pub fn reset(c: *Chain, pose: *const Pose) void {
        for (c.joints, 0..) |j, i| {
            c.pos[i] = pose.global[j].translation;
            c.prev[i] = c.pos[i];
        }
    }

    /// Advance the simulation and write rotations back into `pose`.
    /// Call once per frame AFTER the animation pose has been written (chain
    /// joints' local rotations reset to their animated values) and
    /// `pose.updateGlobal` has run — stiffness pulls toward that animated pose.
    pub fn step(c: *Chain, skel: *const Skeleton, pose: *Pose, dt: f32, colliders: []const Collider) void {
        const p = c.params;
        const n = c.joints.len;
        // root follows animation exactly
        c.pos[0] = pose.global[c.joints[0]].translation;
        c.prev[0] = c.pos[0];

        // Animated (target) positions: walk the chain with each segment's rest
        // offset rotated by the *animated* parent rotation.
        var target_prev = c.pos[0];
        var parent_rot = pose.global[c.joints[0]].rotation;
        for (1..n) |i| {
            const rest_off = skel.rest_local.items[c.joints[i]].translation;
            const target = target_prev.add(parent_rot.rotate(rest_off));
            // verlet
            const vel = c.pos[i].sub(c.prev[i]).scale(1 - p.damping);
            c.prev[i] = c.pos[i];
            var x = c.pos[i].add(vel).add(p.gravity.scale(p.gravity_scale * dt * dt));
            x = x.lerp(target, p.stiffness);
            // length constraint (inextensible)
            x = c.pos[i - 1].add(x.sub(c.pos[i - 1]).normalizeOr(target.sub(target_prev).normalize()).scale(c.lengths[i]));
            // collisions
            for (colliders) |col| x = pushOut(x, p.radius, col, pose);
            // re-apply length after collision
            x = c.pos[i - 1].add(x.sub(c.pos[i - 1]).normalizeOr(Vec3.unit_y.neg()).scale(c.lengths[i]));
            c.pos[i] = x;
            target_prev = target;
            parent_rot = pose.global[c.joints[i]].rotation;
        }

        // Write back: rotate each joint so its child points at the simulated particle.
        for (0..n - 1) |i| {
            const j = c.joints[i];
            const child = c.joints[i + 1];
            const g = pose.global[j];
            const cur_dir = g.rotation.rotate(skel.rest_local.items[child].translation).normalize();
            const sim_dir = c.pos[i + 1].sub(g.translation).normalize();
            const delta = Quat.fromTo(cur_dir, sim_dir);
            pose.setGlobalRotation(skel, j, delta.mul(g.rotation));
            // update this joint and its direct chain child so the next iteration sees fresh globals
            const parent = skel.parents.items[j];
            pose.global[j] = if (parent == skel_mod.no_parent) pose.local[j] else pose.global[@intCast(parent)].compose(pose.local[j]);
            pose.global[child] = pose.global[j].compose(pose.local[child]);
        }
    }
};

/// Closest point on segment ab to p.
pub fn closestOnSegment(p: Vec3, a: Vec3, b: Vec3) Vec3 {
    const ab = b.sub(a);
    const t = m.saturate(p.sub(a).dot(ab) / @max(ab.dot(ab), 1e-12));
    return a.addScaled(ab, t);
}

fn pushOut(x: Vec3, r: f32, col: Collider, pose: *const Pose) Vec3 {
    const ga = pose.global[col.a];
    const gb = pose.global[col.b];
    const a = ga.transformPoint(col.offset_a);
    const b = gb.transformPoint(col.offset_b);
    const c = closestOnSegment(x, a, b);
    const d = x.sub(c);
    const dist = d.length();
    const min_d = col.radius + r;
    if (dist >= min_d) return x;
    return c.add(d.normalizeOr(Vec3.unit_z).scale(min_d));
}

test "chain hangs under gravity and keeps segment lengths" {
    const gpa = std.testing.allocator;
    var skel: Skeleton = .{};
    defer skel.deinit(gpa);
    _ = try skel.addBone(gpa, "root", skel_mod.no_parent, Vec3.init(0, 2, 0));
    // horizontal chain sticking out along +X
    _ = try skel.addBone(gpa, "c0", 0, Vec3.init(0, 2, 0));
    _ = try skel.addBone(gpa, "c1", 1, Vec3.init(0.3, 2, 0));
    _ = try skel.addBone(gpa, "c2", 2, Vec3.init(0.6, 2, 0));
    var pose = try Pose.init(gpa, &skel);
    defer pose.deinit(gpa);
    var chain = try Chain.init(gpa, &skel, &.{ 1, 2, 3 }, .{ .stiffness = 0.0, .damping = 0.2, .gravity_scale = 1 });
    defer chain.deinit(gpa);
    for (0..600) |_| {
        pose.updateGlobal(&skel);
        chain.step(&skel, &pose, 1.0 / 60.0, &.{});
    }
    pose.updateGlobal(&skel);
    const tip = pose.global[3].translation;
    // with zero stiffness the chain swings down to hang vertically
    try std.testing.expect(tip.y < 1.45);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), pose.global[2].translation.distance(pose.global[1].translation), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), tip.distance(pose.global[2].translation), 1e-3);
}

test "collider pushes particle out of capsule" {
    const gpa = std.testing.allocator;
    var skel: Skeleton = .{};
    defer skel.deinit(gpa);
    _ = try skel.addBone(gpa, "a", skel_mod.no_parent, Vec3.zero);
    _ = try skel.addBone(gpa, "b", 0, Vec3.init(0, 1, 0));
    var pose = try Pose.init(gpa, &skel);
    defer pose.deinit(gpa);
    const out = pushOut(Vec3.init(0.05, 0.5, 0), 0.0, .{ .a = 0, .b = 1, .radius = 0.2 }, &pose);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), out.x, 1e-5);
}
