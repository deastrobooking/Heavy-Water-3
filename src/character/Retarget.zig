//! Drives an imported humanoid skin from the game's procedural skeleton.
//!
//! The game animates its own humanoid (`skeleton.Joint`), whose rest pose is an A-pose with every
//! rest rotation identity, so a pose palette entry is that joint's world rotation and travel from
//! rest. An imported rig has its own proportions and bind pose (often a T-pose). Copying world
//! rotations onto it unchanged keeps a T-pose's arms horizontal through every swing, and moving
//! each joint by the game's travel opens gaps wherever limb lengths differ.
//!
//! The plan here, made once per imported model:
//! - each mapped game joint gets the source pivot it rotates about (the first skin bone mapped to
//!   it) and its nearest mapped ancestor;
//! - a bind correction per joint turns the source bone's bind direction onto the game's rest
//!   direction (T-pose arms come down to the A-pose), so the game's rotations apply as authored;
//! - each frame, the source skeleton is posed by forward kinematics over its own bone offsets,
//!   so proportions are the source's and joints stay connected; only the roots move by the game's
//!   travel, in model units.
const std = @import("std");
const skeleton = @import("skeleton.zig");
const Model = @import("../asset/Model.zig");

pub const joint_count = skeleton.humanoid_joint_count;
const J = skeleton.Joint;
const V = [3]f32;
const Q = [4]f32;

/// The bone each joint's bind direction is measured toward, when both are mapped.
fn directionChild(j: J) ?J {
    return switch (j) {
        .spine => .chest,
        .chest => .neck,
        .neck => .head,
        .shoulder_l => .upper_arm_l,
        .upper_arm_l => .lower_arm_l,
        .lower_arm_l => .hand_l,
        .shoulder_r => .upper_arm_r,
        .upper_arm_r => .lower_arm_r,
        .lower_arm_r => .hand_r,
        .thigh_l => .shin_l,
        .shin_l => .foot_l,
        .foot_l => .toe_l,
        .thigh_r => .shin_r,
        .shin_r => .foot_r,
        .foot_r => .toe_r,
        else => null,
    };
}

pub const Plan = struct {
    mapped: [joint_count]bool = @splat(false),
    /// Source pivot of each mapped joint, in model units.
    pivot: [joint_count]V = @splat(.{ 0, 0, 0 }),
    /// Nearest mapped ancestor in the game's hierarchy.
    parent: [joint_count]?u8 = @splat(null),
    /// Rotation taking the source bind pose onto the game's rest pose around this joint.
    bind: [joint_count]Q = @splat(.{ 0, 0, 0, 1 }),
    /// Distinct game joints driven by the import (root excluded).
    driven: usize = 0,

    /// `parents` and `rest` are the game skeleton's first `joint_count` entries (rest in metres).
    pub fn init(bones: []const Model.SkinBone, parents: []const i16, rest: []const V) Plan {
        var plan: Plan = .{};
        for (bones) |bone| if (bone.ranger_joint < joint_count and !plan.mapped[bone.ranger_joint]) {
            plan.mapped[bone.ranger_joint] = true;
            plan.pivot[bone.ranger_joint] = bone.pivot;
        };
        for (0..joint_count) |j| {
            if (!plan.mapped[j]) continue;
            if (j != 0) plan.driven += 1;
            var p = parents[j];
            while (p >= 0) : (p = parents[@intCast(p)]) if (plan.mapped[@intCast(p)]) {
                plan.parent[j] = @intCast(p);
                break;
            };
        }
        // Joints are ordered parents first, so an inherited correction is already computed.
        for (0..joint_count) |j| {
            if (!plan.mapped[j]) continue;
            const joint: J = @enumFromInt(j);
            if (joint == .root or joint == .hips) continue;
            if (directionChild(joint)) |child| if (plan.mapped[child.idx()]) {
                const from = sub(plan.pivot[child.idx()], plan.pivot[j]);
                const to = sub(rest[child.idx()], rest[j]);
                if (length(from) > 1e-6 and length(to) > 1e-6) {
                    plan.bind[j] = between(normalize(from), normalize(to));
                    continue;
                }
            };
            // Hands, feet ends and heads keep their parent's correction, so a corrected forearm
            // does not leave the hand pointing where the T-pose had it.
            if (plan.parent[j]) |p| plan.bind[j] = plan.bind[p];
        }
        return plan;
    }

    /// Writes one dual quaternion (real, dual) per skin bone into `out` from the game's pose
    /// palette (two entries per game joint). `unit` is model units per metre.
    pub fn pose(self: *const Plan, palette: []const Q, rest: []const V, unit: f32, bones: []const Model.SkinBone, out: []Q) void {
        var rot: [joint_count]Q = undefined;
        var pos: [joint_count]V = undefined;
        for (0..joint_count) |j| {
            if (!self.mapped[j]) continue;
            const q = palette[j * 2];
            const d = palette[j * 2 + 1];
            rot[j] = mul(q, self.bind[j]);
            if (self.parent[j]) |p| {
                pos[j] = add(pos[p], rotate(rot[p], sub(self.pivot[j], self.pivot[p])));
            } else {
                // A root of the mapped chain moves by the game joint's travel from rest.
                const t = translation(q, d);
                const moved = add(rotate(q, rest[j]), t);
                pos[j] = add(self.pivot[j], scale(sub(moved, rest[j]), unit));
            }
        }
        for (bones, 0..) |bone, b| {
            const j: usize = if (bone.ranger_joint < joint_count and self.mapped[bone.ranger_joint]) bone.ranger_joint else 0;
            const real = if (self.mapped[j]) rot[j] else Q{ 0, 0, 0, 1 };
            const at = if (self.mapped[j]) pos[j] else bone.pivot;
            const pivot = if (self.mapped[j]) self.pivot[j] else bone.pivot;
            const shift = sub(at, rotate(real, pivot));
            const dual = mul(.{ shift[0], shift[1], shift[2], 0 }, real);
            out[b * 2] = real;
            out[b * 2 + 1] = .{ dual[0] * 0.5, dual[1] * 0.5, dual[2] * 0.5, dual[3] * 0.5 };
        }
    }
};

fn translation(real: Q, dual: Q) V {
    const t = mul(dual, .{ -real[0], -real[1], -real[2], real[3] });
    return .{ 2 * t[0], 2 * t[1], 2 * t[2] };
}

fn mul(a: Q, b: Q) Q {
    return .{
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    };
}

fn rotate(q: Q, v: V) V {
    const r = mul(mul(q, .{ v[0], v[1], v[2], 0 }), .{ -q[0], -q[1], -q[2], q[3] });
    return .{ r[0], r[1], r[2] };
}

/// Shortest-arc rotation taking unit vector `a` onto unit vector `b`.
fn between(a: V, b: V) Q {
    const d = dot(a, b);
    if (d < -0.9999) {
        // Opposite: any perpendicular axis.
        const axis = normalize(if (@abs(a[0]) < 0.9) cross(a, .{ 1, 0, 0 }) else cross(a, .{ 0, 1, 0 }));
        return .{ axis[0], axis[1], axis[2], 0 };
    }
    const c = cross(a, b);
    const q: Q = .{ c[0], c[1], c[2], 1 + d };
    const l = @sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
    return .{ q[0] / l, q[1] / l, q[2] / l, q[3] / l };
}

fn add(a: V, b: V) V {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
fn sub(a: V, b: V) V {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn scale(a: V, s: f32) V {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}
fn dot(a: V, b: V) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn cross(a: V, b: V) V {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
fn length(a: V) f32 {
    return @sqrt(dot(a, a));
}
fn normalize(a: V) V {
    const l = length(a);
    return if (l > 1e-12) scale(a, 1 / l) else .{ 0, 1, 0 };
}

/// Applies bone `b`'s dual quaternion to point `p` (what the GPU skinning does for one influence).
fn apply(out: []const Q, b: usize, p: V) V {
    const real = out[b * 2];
    const t = translation(real, out[b * 2 + 1]);
    return add(rotate(real, p), t);
}

// ---- Tests ---------------------------------------------------------------------------------

const TestRig = struct {
    parents: [joint_count]i16,
    rest: [joint_count]V,
};

/// A minimal game skeleton: root > hips > spine > chest > shoulder_l > upper_arm_l > lower_arm_l
/// > hand_l, plus thigh_l > shin_l. Arms rest pointing down-left (an A-pose).
fn testRig() TestRig {
    var rig: TestRig = .{ .parents = @splat(-1), .rest = @splat(.{ 0, 0, 0 }) };
    const set = struct {
        fn f(r: *TestRig, j: J, parent: ?J, p: V) void {
            r.parents[j.idx()] = if (parent) |pj| @intCast(pj.idx()) else -1;
            r.rest[j.idx()] = p;
        }
    }.f;
    set(&rig, .root, null, .{ 0, 0, 0 });
    set(&rig, .hips, .root, .{ 0, 1, 0 });
    set(&rig, .spine, .hips, .{ 0, 1.2, 0 });
    set(&rig, .chest, .spine, .{ 0, 1.4, 0 });
    set(&rig, .shoulder_l, .chest, .{ 0.1, 1.45, 0 });
    set(&rig, .upper_arm_l, .shoulder_l, .{ 0.2, 1.45, 0 });
    set(&rig, .lower_arm_l, .upper_arm_l, .{ 0.4, 1.2, 0 });
    set(&rig, .hand_l, .lower_arm_l, .{ 0.6, 0.95, 0 });
    set(&rig, .thigh_l, .hips, .{ 0.1, 0.95, 0 });
    set(&rig, .shin_l, .thigh_l, .{ 0.1, 0.5, 0 });
    return rig;
}

fn identityPalette() [joint_count * 2]Q {
    var p: [joint_count * 2]Q = undefined;
    for (0..joint_count) |j| {
        p[j * 2] = .{ 0, 0, 0, 1 };
        p[j * 2 + 1] = .{ 0, 0, 0, 0 };
    }
    return p;
}

fn testBone(j: J, p: V) Model.SkinBone {
    return .{ .ranger_joint = @intCast(j.idx()), .pivot = p };
}

test "a source rig that matches the game's rest pose is the identity at rest" {
    const rig = testRig();
    const bones = [_]Model.SkinBone{ testBone(.hips, rig.rest[J.hips.idx()]), testBone(.upper_arm_l, rig.rest[J.upper_arm_l.idx()]), testBone(.lower_arm_l, rig.rest[J.lower_arm_l.idx()]), testBone(.hand_l, rig.rest[J.hand_l.idx()]) };
    const plan = Plan.init(&bones, &rig.parents, &rig.rest);
    try std.testing.expectEqual(@as(usize, 4), plan.driven);
    var out: [bones.len * 2]Q = undefined;
    const palette = identityPalette();
    plan.pose(&palette, &rig.rest, 1, &bones, &out);
    for (0..bones.len) |b| {
        const p = apply(&out, b, .{ 0.3, 1.3, 0.1 });
        for (p, [_]f32{ 0.3, 1.3, 0.1 }) |got, want| try std.testing.expectApproxEqAbs(want, got, 1e-5);
    }
}

test "a T-pose source arm comes down to the game's A-pose and keeps its own length" {
    const rig = testRig();
    // The source's arm sticks straight out along +x and is longer (0.35 per segment).
    const shoulder: V = .{ 0.2, 1.45, 0 };
    const elbow: V = .{ 0.55, 1.45, 0 };
    const wrist: V = .{ 0.9, 1.45, 0 };
    const bones = [_]Model.SkinBone{ testBone(.hips, .{ 0, 1, 0 }), testBone(.upper_arm_l, shoulder), testBone(.lower_arm_l, elbow), testBone(.hand_l, wrist) };
    const plan = Plan.init(&bones, &rig.parents, &rig.rest);
    var out: [bones.len * 2]Q = undefined;
    const palette = identityPalette();
    plan.pose(&palette, &rig.rest, 1, &bones, &out);
    // The elbow (driven by the upper arm bone) lands along the game's rest arm direction...
    const posed_elbow = apply(&out, 1, elbow);
    const game_dir = normalize(sub(rig.rest[J.lower_arm_l.idx()], rig.rest[J.upper_arm_l.idx()]));
    const got_dir = normalize(sub(posed_elbow, shoulder));
    for (game_dir, got_dir) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-4);
    // ...at the source's own length, and the forearm bone starts exactly where the upper arm ends.
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), length(sub(posed_elbow, shoulder)), 1e-4);
    const forearm_start = apply(&out, 2, elbow);
    for (posed_elbow, forearm_start) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
    // The hand keeps the forearm's correction instead of pointing back out sideways.
    const hand_tip = apply(&out, 3, .{ 1.0, 1.45, 0 });
    const wrist_at = apply(&out, 3, wrist);
    try std.testing.expect(hand_tip[1] < wrist_at[1]);
}

test "a bent game elbow bends the source forearm, and hips travel moves the chain in model units" {
    const rig = testRig();
    const bones = [_]Model.SkinBone{ testBone(.hips, .{ 0, 100, 0 }), testBone(.thigh_l, .{ 10, 95, 0 }), testBone(.shin_l, .{ 10, 50, 0 }) };
    const plan = Plan.init(&bones, &rig.parents, &rig.rest);
    var palette = identityPalette();
    // Hips rise 0.1 m; the source is in centimetres (unit 100).
    palette[J.hips.idx() * 2 + 1] = .{ 0, 0.05, 0, 0 };
    // Knee bends 90 degrees about x: rotate the shin about its own rest pivot.
    const s = @sqrt(0.5);
    const knee_rot: Q = .{ s, 0, 0, s };
    const knee = rig.rest[J.shin_l.idx()];
    const spun = rotate(knee_rot, knee);
    const t: V = .{ knee[0] - spun[0], knee[1] - spun[1] + 0.1, knee[2] - spun[2] };
    const dual = mul(.{ t[0], t[1], t[2], 0 }, knee_rot);
    palette[J.shin_l.idx() * 2] = knee_rot;
    palette[J.shin_l.idx() * 2 + 1] = .{ dual[0] * 0.5, dual[1] * 0.5, dual[2] * 0.5, dual[3] * 0.5 };
    var out: [bones.len * 2]Q = undefined;
    plan.pose(&palette, &rig.rest, 100, &bones, &out);
    // The hips (and the thigh hanging from them) rise 10 cm.
    try std.testing.expectApproxEqAbs(@as(f32, 110), apply(&out, 0, .{ 0, 100, 0 })[1], 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 105), apply(&out, 1, .{ 10, 95, 0 })[1], 1e-3);
    // The knee stays attached to the thigh, and the source shin (45 cm) now points along z.
    const knee_at = apply(&out, 2, .{ 10, 50, 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 60), knee_at[1], 1e-2);
    const ankle = apply(&out, 2, .{ 10, 5, 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 60), ankle[1], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 45), @abs(ankle[2] - knee_at[2]), 0.5);
}
