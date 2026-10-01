//! Inverse kinematics: analytic two-bone IK (arms, legs) and a look-at
//! helper for heads/eyes. Works directly on Pose global/local rotations.

const std = @import("std");
const m = @import("math.zig");
const skel_mod = @import("skeleton.zig");
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Skeleton = skel_mod.Skeleton;
const Pose = skel_mod.Pose;

fn safeAcos(x: f32) f32 {
    return std.math.acos(m.clamp(x, -1, 1));
}

/// Analytic two-bone IK (law of cosines).
///   upper/mid/end: e.g. thigh, shin, foot.
///   target: where `end` should go.  pole: a point the middle joint bends toward
///   (in front of the knee, behind the elbow).  weight: 0..1 blend with FK.
/// Requires `pose.global` to be current; leaves it current for the chain.
pub fn solveTwoBone(skel: *const Skeleton, pose: *Pose, upper: u16, mid: u16, end: u16, target: Vec3, pole: Vec3, weight: f32) void {
    const a = pose.global[upper].translation;
    const b = pose.global[mid].translation;
    const c = pose.global[end].translation;
    const lab = a.distance(b);
    const lcb = b.distance(c);
    const lat = m.clamp(target.distance(a), 1e-4, (lab + lcb) * 0.9999);

    const ac = c.sub(a).normalize();
    const ab = b.sub(a).normalize();
    const at = target.sub(a).normalizeOr(ac);

    // current & desired interior angles
    const ac_ab_0 = safeAcos(ac.dot(ab));
    const ba_bc_0 = safeAcos(a.sub(b).normalize().dot(c.sub(b).normalize()));
    const ac_ab_1 = safeAcos((lcb * lcb - lab * lab - lat * lat) / (-2 * lab * lat));
    const ba_bc_1 = safeAcos((lat * lat - lab * lab - lcb * lcb) / (-2 * lab * lcb));

    // bend axis from the pole so straight rest limbs bend the right way
    const axis0 = ac.cross(pole.sub(a)).normalizeOr(ac.cross(ab).normalizeOr(Vec3.anyPerpendicular(ac)));
    const axis1 = ac.cross(at).normalizeOr(axis0);

    const q_bend_a = Quat.fromAxisAngle(axis0, ac_ab_1 - ac_ab_0);
    const q_bend_b = Quat.fromAxisAngle(axis0, ba_bc_1 - ba_bc_0);
    const q_aim = if (ac.cross(at).length() < 1e-6) Quat.identity else Quat.fromAxisAngle(axis1, safeAcos(ac.dot(at)));

    const ga = pose.global[upper].rotation;
    const gb = pose.global[mid].rotation;
    var new_a = q_aim.mul(q_bend_a).mul(ga).normalize();
    var new_b = q_aim.mul(q_bend_a).mul(q_bend_b).mul(gb).normalize();

    // swing the solved chain about the a->target axis so the knee faces the pole
    {
        const b_new = a.add(q_aim.mul(q_bend_a).rotate(b.sub(a)));
        const axis = at;
        const bp = b_new.sub(a).reject(axis);
        const pp = pole.sub(a).reject(axis);
        if (bp.length() > 1e-5 and pp.length() > 1e-5) {
            const bn = bp.normalize();
            const pn = pp.normalize();
            const ang = std.math.atan2(bn.cross(pn).dot(axis), bn.dot(pn));
            const q_twist = Quat.fromAxisAngle(axis, ang);
            new_a = q_twist.mul(new_a).normalize();
            new_b = q_twist.mul(new_b).normalize();
        }
    }

    if (weight < 1) {
        new_a = Quat.slerp(ga, new_a, weight);
        new_b = Quat.slerp(gb, new_b, weight);
    }
    pose.setGlobalRotation(skel, upper, new_a);
    refresh(skel, pose, upper);
    pose.setGlobalRotation(skel, mid, new_b);
    refresh(skel, pose, mid);
    refresh(skel, pose, end);
}

/// Recompute one joint's global from its parent (cheap partial FK).
pub fn refresh(skel: *const Skeleton, pose: *Pose, j: u16) void {
    const parent = skel.parents.items[j];
    pose.global[j] = if (parent == skel_mod.no_parent) pose.local[j] else pose.global[@intCast(parent)].compose(pose.local[j]);
}

/// Rotate joint `j` so that its `local_fwd` axis points at `target`,
/// limited to `max_angle` radians away from the current orientation.
pub fn lookAt(skel: *const Skeleton, pose: *Pose, j: u16, local_fwd: Vec3, target: Vec3, max_angle: f32, weight: f32) void {
    const g = pose.global[j];
    const cur = g.rotation.rotate(local_fwd).normalize();
    const want = target.sub(g.translation).normalizeOr(cur);
    const ang = safeAcos(cur.dot(want));
    const axis = cur.cross(want);
    if (axis.length() < 1e-6) return;
    const clamped = @min(ang, max_angle) * weight;
    const q = Quat.fromAxisAngle(axis, clamped);
    pose.setGlobalRotation(skel, j, q.mul(g.rotation));
    refresh(skel, pose, j);
}

test "two-bone IK reaches a reachable target and bends toward the pole" {
    const gpa = std.testing.allocator;
    var skel: Skeleton = .{};
    defer skel.deinit(gpa);
    _ = try skel.addBone(gpa, "root", skel_mod.no_parent, Vec3.zero);
    const thigh = try skel.addBone(gpa, "thigh", 0, Vec3.init(0, 1.0, 0));
    const shin = try skel.addBone(gpa, "shin", @intCast(thigh), Vec3.init(0, 0.55, 0));
    const foot = try skel.addBone(gpa, "foot", @intCast(shin), Vec3.init(0, 0.1, 0));
    var pose = try Pose.init(gpa, &skel);
    defer pose.deinit(gpa);

    const target = Vec3.init(0.1, 0.35, 0.25);
    const pole = Vec3.init(0, 0.6, 2.0); // knee forward
    solveTwoBone(&skel, &pose, thigh, shin, foot, target, pole, 1.0);
    pose.updateGlobal(&skel);
    try std.testing.expect(pose.global[foot].translation.approxEq(target, 1e-3));
    try std.testing.expect(pose.global[shin].translation.z > 0.05); // knee bent forward
    // bone lengths preserved
    try std.testing.expectApproxEqAbs(@as(f32, 0.45), pose.global[shin].translation.distance(pose.global[thigh].translation), 1e-4);
}

test "look-at turns forward axis toward target" {
    const gpa = std.testing.allocator;
    var skel: Skeleton = .{};
    defer skel.deinit(gpa);
    _ = try skel.addBone(gpa, "head", skel_mod.no_parent, Vec3.init(0, 1.5, 0));
    var pose = try Pose.init(gpa, &skel);
    defer pose.deinit(gpa);
    lookAt(&skel, &pose, 0, Vec3.unit_z, Vec3.init(1, 1.5, 1), m.pi, 1);
    const f = pose.global[0].rotation.rotate(Vec3.unit_z);
    try std.testing.expect(f.approxEq(Vec3.init(1, 0, 1).normalize(), 1e-4));
}
