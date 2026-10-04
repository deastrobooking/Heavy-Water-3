//! Bone hierarchy, forward kinematics and skinning (linear blend + dual quaternion).
//!
//! Rest pose convention: every bone's rest *rotation* is identity and its rest
//! translation is its offset from the parent, in model space. This keeps the
//! generator simple (bones are just points), makes inverse-bind matrices pure
//! translations, and means a pose rotation is "rotate this joint about its pivot
//! in the parent's frame" — exactly what IK and procedural animation want.

const std = @import("std");
const m = @import("math.zig");
const mesh_mod = @import("mesh.zig");
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Mat4 = m.Mat4;
const Transform = m.Transform;
const Allocator = std.mem.Allocator;

pub const no_parent: i16 = -1;

/// Fixed humanoid joints. These always occupy the first indices of a
/// Skeleton; dynamic chains (hair, skirt, ribbons) are appended after.
pub const Joint = enum(u16) {
    root,
    hips,
    spine,
    chest,
    neck,
    head,
    shoulder_l,
    upper_arm_l,
    lower_arm_l,
    hand_l,
    shoulder_r,
    upper_arm_r,
    lower_arm_r,
    hand_r,
    thigh_l,
    shin_l,
    foot_l,
    toe_l,
    thigh_r,
    shin_r,
    foot_r,
    toe_r,

    pub inline fn idx(j: Joint) u16 {
        return @intFromEnum(j);
    }
};
pub const humanoid_joint_count = @typeInfo(Joint).@"enum".fields.len;

pub const Skeleton = struct {
    names: std.ArrayList([]const u8) = .empty,
    parents: std.ArrayList(i16) = .empty,
    rest_local: std.ArrayList(Transform) = .empty,
    rest_world: std.ArrayList(Vec3) = .empty,
    inv_bind: std.ArrayList(Mat4) = .empty,

    pub fn deinit(s: *Skeleton, gpa: Allocator) void {
        s.names.deinit(gpa);
        s.parents.deinit(gpa);
        s.rest_local.deinit(gpa);
        s.rest_world.deinit(gpa);
        s.inv_bind.deinit(gpa);
    }

    pub fn count(s: *const Skeleton) usize {
        return s.parents.items.len;
    }

    /// Add a bone at a model-space rest position. Parents must be added first,
    /// which guarantees parent index < child index (single-pass FK).
    pub fn addBone(s: *Skeleton, gpa: Allocator, name: []const u8, parent: i16, world_pos: Vec3) !u16 {
        const idx: u16 = @intCast(s.count());
        std.debug.assert(parent < @as(i16, @intCast(idx)));
        const parent_pos = if (parent == no_parent) Vec3.zero else s.rest_world.items[@intCast(parent)];
        try s.names.append(gpa, name);
        try s.parents.append(gpa, parent);
        try s.rest_local.append(gpa, .{ .translation = world_pos.sub(parent_pos) });
        try s.rest_world.append(gpa, world_pos);
        try s.inv_bind.append(gpa, Mat4.translation(world_pos.neg()));
        return idx;
    }

    pub fn worldPos(s: *const Skeleton, j: Joint) Vec3 {
        return s.rest_world.items[j.idx()];
    }

    pub fn indexOf(s: *const Skeleton, name: []const u8) ?u16 {
        for (s.names.items, 0..) |n, i| if (std.mem.eql(u8, n, name)) return @intCast(i);
        return null;
    }
};

/// Animated state for one skeleton instance.
pub const Pose = struct {
    local: []Transform,
    global: []Transform,

    pub fn init(gpa: Allocator, skel: *const Skeleton) !Pose {
        const local = try gpa.dupe(Transform, skel.rest_local.items);
        errdefer gpa.free(local);
        const global = try gpa.alloc(Transform, local.len);
        var p: Pose = .{ .local = local, .global = global };
        p.updateGlobal(skel);
        return p;
    }
    pub fn deinit(p: *Pose, gpa: Allocator) void {
        gpa.free(p.local);
        gpa.free(p.global);
    }
    pub fn reset(p: *Pose, skel: *const Skeleton) void {
        @memcpy(p.local, skel.rest_local.items);
        p.updateGlobal(skel);
    }

    /// Forward kinematics. Linear pass because parents precede children.
    pub fn updateGlobal(p: *Pose, skel: *const Skeleton) void {
        for (skel.parents.items, 0..) |parent, i| {
            p.global[i] = if (parent == no_parent) p.local[i] else p.global[@intCast(parent)].compose(p.local[i]);
        }
    }

    /// Rotate joint `j` by `q` (applied in its parent's frame, on top of current).
    pub fn rotateLocal(p: *Pose, j: u16, q: Quat) void {
        p.local[j].rotation = q.mul(p.local[j].rotation).normalize();
    }

    /// Set a joint's *global* rotation by solving for the local rotation.
    /// Requires `global` of the parent to be current.
    pub fn setGlobalRotation(p: *Pose, skel: *const Skeleton, j: u16, q_world: Quat) void {
        const parent = skel.parents.items[j];
        const parent_rot = if (parent == no_parent) Quat.identity else p.global[@intCast(parent)].rotation;
        p.local[j].rotation = parent_rot.conjugate().mul(q_world).normalize();
    }

    /// Skinning matrices = global * inverse_bind, ready for a GPU uniform/SSBO.
    pub fn skinMatrices(p: *const Pose, skel: *const Skeleton, out: []Mat4) void {
        for (out, 0..) |*o, i| o.* = p.global[i].toMat4().mul(skel.inv_bind.items[i]);
    }

    /// Skinning as dual quaternions (rigid part only; scale ignored).
    pub fn skinDualQuats(p: *const Pose, skel: *const Skeleton, out: []DualQuat) void {
        for (out, 0..) |*o, i| {
            const g = p.global[i];
            // global * translation(-rest_world): rotation R, translation G(-rest).
            const t = g.transformPoint(skel.rest_world.items[i].neg());
            o.* = DualQuat.fromRT(g.rotation, t);
        }
    }
};

// ---------------------------------------------------------------- Dual quaternions
/// Unit dual quaternion: real part = rotation, dual part = 0.5 * t * r.
/// Blending DQs instead of matrices removes the "candy-wrapper" volume loss
/// at twisting joints (forearms, waist) that linear blend skinning suffers from.
pub const DualQuat = struct {
    real: Quat,
    dual: Quat,

    pub fn fromRT(r: Quat, t: Vec3) DualQuat {
        const tq: Quat = .{ .x = t.x, .y = t.y, .z = t.z, .w = 0 };
        const d = tq.mul(r);
        return .{ .real = r, .dual = .{ .x = 0.5 * d.x, .y = 0.5 * d.y, .z = 0.5 * d.z, .w = 0.5 * d.w } };
    }
    pub fn translation(dq: DualQuat) Vec3 {
        const t = dq.dual.mul(dq.real.conjugate());
        return Vec3.init(2 * t.x, 2 * t.y, 2 * t.z);
    }
    pub fn transformPoint(dq: DualQuat, p: Vec3) Vec3 {
        return dq.real.rotate(p).add(dq.translation());
    }
};

fn quatScaleAdd(acc: Quat, q: Quat, w: f32) Quat {
    return .{ .x = acc.x + q.x * w, .y = acc.y + q.y * w, .z = acc.z + q.z * w, .w = acc.w + q.w * w };
}

// ---------------------------------------------------------------- CPU skinning
/// Linear blend skinning. GPU shaders do the same thing per vertex; this CPU
/// version is used for previews, collision proxies and tests.
pub fn skinLinear(verts: []const mesh_mod.Vertex, mats: []const Mat4, out_pos: []Vec3, out_nrm: []Vec3) void {
    for (verts, 0..) |v, i| {
        var p = Vec3.zero;
        var n = Vec3.zero;
        for (0..mesh_mod.max_influences) |k| {
            const w = v.weights[k];
            if (w == 0) continue;
            const mm = mats[v.joints[k]];
            p = p.addScaled(mm.transformPoint(v.pos), w);
            n = n.addScaled(mm.transformVector(v.normal), w);
        }
        out_pos[i] = p;
        out_nrm[i] = n.normalizeOr(v.normal);
    }
}

/// Dual quaternion skinning with antipodality correction.
pub fn skinDualQuat(verts: []const mesh_mod.Vertex, dqs: []const DualQuat, out_pos: []Vec3, out_nrm: []Vec3) void {
    for (verts, 0..) |v, i| {
        // Rigid armor plates, facial details and most interior vertices have one joint.
        // Avoid a four-slot blend, normalization and square root for this common case.
        if (v.weights[1] == 0 and v.weights[2] == 0 and v.weights[3] == 0) {
            const dq = dqs[v.joints[0]];
            out_pos[i] = dq.real.rotate(v.pos).add(DualQuat.translation(dq));
            out_nrm[i] = dq.real.rotate(v.normal);
            continue;
        }
        if (v.weights[2] == 0 and v.weights[3] == 0) {
            const pivot = dqs[v.joints[0]].real;
            var w1 = v.weights[1];
            const second = dqs[v.joints[1]];
            if (pivot.dot(second.real) < 0) w1 = -w1;
            const w0 = v.weights[0];
            var real = quatScaleAdd(.{ .w = 0 }, pivot, w0);
            real = quatScaleAdd(real, second.real, w1);
            var dual = quatScaleAdd(.{ .w = 0 }, dqs[v.joints[0]].dual, w0);
            dual = quatScaleAdd(dual, second.dual, w1);
            const len = @sqrt(real.dot(real));
            const inv = if (len < m.eps) 1.0 else 1.0 / len;
            const blended: DualQuat = .{
                .real = .{ .x = real.x * inv, .y = real.y * inv, .z = real.z * inv, .w = real.w * inv },
                .dual = .{ .x = dual.x * inv, .y = dual.y * inv, .z = dual.z * inv, .w = dual.w * inv },
            };
            out_pos[i] = blended.transformPoint(v.pos);
            out_nrm[i] = blended.real.rotate(v.normal);
            continue;
        }
        const pivot = dqs[v.joints[0]].real;
        var real: Quat = .{ .w = 0 };
        var dual: Quat = .{ .w = 0 };
        for (0..mesh_mod.max_influences) |k| {
            var w = v.weights[k];
            if (w == 0) continue;
            const dq = dqs[v.joints[k]];
            if (dq.real.dot(pivot) < 0) w = -w; // keep blend in one hemisphere
            real = quatScaleAdd(real, dq.real, w);
            dual = quatScaleAdd(dual, dq.dual, w);
        }
        const len = @sqrt(real.dot(real));
        const inv = if (len < m.eps) 1.0 else 1.0 / len;
        const blended: DualQuat = .{
            .real = .{ .x = real.x * inv, .y = real.y * inv, .z = real.z * inv, .w = real.w * inv },
            .dual = .{ .x = dual.x * inv, .y = dual.y * inv, .z = dual.z * inv, .w = dual.w * inv },
        };
        out_pos[i] = blended.transformPoint(v.pos);
        out_nrm[i] = blended.real.rotate(v.normal);
    }
}

// ---------------------------------------------------------------- tests
const testing = std.testing;

test "FK rotates child about parent pivot" {
    const gpa = testing.allocator;
    var skel: Skeleton = .{};
    defer skel.deinit(gpa);
    const a = try skel.addBone(gpa, "a", no_parent, Vec3.zero);
    const b = try skel.addBone(gpa, "b", @intCast(a), Vec3.init(0, 1, 0));
    _ = try skel.addBone(gpa, "c", @intCast(b), Vec3.init(0, 2, 0));
    var pose = try Pose.init(gpa, &skel);
    defer pose.deinit(gpa);
    pose.rotateLocal(b, Quat.fromAxisAngle(Vec3.unit_z, m.pi / 2.0));
    pose.updateGlobal(&skel);
    // c was 1 above b; after +90deg about Z it is 1 to the -X of b.
    try testing.expect(pose.global[2].translation.approxEq(Vec3.init(-1, 1, 0), 1e-5));
}

test "LBS and DQS agree for a single rigid influence" {
    const gpa = testing.allocator;
    var skel: Skeleton = .{};
    defer skel.deinit(gpa);
    _ = try skel.addBone(gpa, "root", no_parent, Vec3.zero);
    _ = try skel.addBone(gpa, "arm", 0, Vec3.init(1, 0, 0));
    var pose = try Pose.init(gpa, &skel);
    defer pose.deinit(gpa);
    pose.rotateLocal(1, Quat.fromAxisAngle(Vec3.unit_y, 0.8));
    pose.local[0].translation = Vec3.init(0, 3, 0);
    pose.updateGlobal(&skel);

    var mats: [2]Mat4 = undefined;
    var dqs: [2]DualQuat = undefined;
    pose.skinMatrices(&skel, &mats);
    pose.skinDualQuats(&skel, &dqs);
    const verts = [_]mesh_mod.Vertex{.{ .pos = Vec3.init(2, 0.5, 0.25), .normal = Vec3.unit_x, .joints = .{ 1, 0, 0, 0 } }};
    var p1: [1]Vec3 = undefined;
    var n1: [1]Vec3 = undefined;
    var p2: [1]Vec3 = undefined;
    var n2: [1]Vec3 = undefined;
    skinLinear(&verts, &mats, &p1, &n1);
    skinDualQuat(&verts, &dqs, &p2, &n2);
    try testing.expect(p1[0].approxEq(p2[0], 1e-4));
    try testing.expect(n1[0].approxEq(n2[0], 1e-4));
}
