//! Rigs an unrigged humanoid mesh onto the game's skeleton, so a static GLB (a sculpt, a kitbash,
//! a store model without bones) can be imported as a playable character.
//!
//! The game's 21 joints are laid inside the mesh's bounds at humanoid proportions: hips about
//! half-way up, shoulders at four fifths, legs straight down. Arms follow the mesh: when it is
//! much wider than tall at shoulder height it is a T-pose and the arm joints run out sideways to
//! the hands; otherwise they hang in the game's A-pose. Each vertex is then weighted to its two
//! nearest bones (by distance to the bone segment). `Retarget` turns the pivots' directions onto
//! the game's rest pose, so a T-pose's arms come down like any imported rig's.
//!
//! Assumes glTF conventions: +y up, the character facing +z, so its left side is +x.
const std = @import("std");
const Model = @import("../asset/Model.zig");
const skeleton = @import("skeleton.zig");

const J = skeleton.Joint;
const V = [3]f32;
pub const joint_count = skeleton.humanoid_joint_count;

pub const Error = error{ EmptyMesh, FlatMesh, OutOfMemory };

/// Where the auto-rig put each joint, in the mesh's units, and whether it read a T-pose.
pub const Fit = struct { pivots: [joint_count]V, t_pose: bool };

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

/// Lay the joints inside the mesh's bounds.
pub fn fit(vertices: []const @import("../render/Mesh.zig").Vertex) Error!Fit {
    if (vertices.len == 0) return error.EmptyMesh;
    var lo: V = @splat(std.math.inf(f32));
    var hi: V = @splat(-std.math.inf(f32));
    for (vertices) |v| for (0..3) |a| {
        lo[a] = @min(lo[a], v.position[a]);
        hi[a] = @max(hi[a], v.position[a]);
    };
    const h = hi[1] - lo[1];
    if (!(h > 0) or !std.math.isFinite(h)) return error.FlatMesh;
    const cx = (lo[0] + hi[0]) / 2;
    const cz = (lo[2] + hi[2]) / 2;
    // How far the mesh reaches sideways around shoulder height: a T-pose's arms reach far out.
    var reach: f32 = 0;
    for (vertices) |v| {
        const t = (v.position[1] - lo[1]) / h;
        if (t > 0.72 and t < 0.9) reach = @max(reach, @abs(v.position[0] - cx));
    }
    const t_pose = reach > 0.32 * h;
    const at = struct {
        fn f(base: V, height: f32, x: f32, y: f32, z: f32) V {
            return .{ base[0] + x * height, base[1] + y * height, base[2] + z * height };
        }
    }.f;
    const base: V = .{ cx, lo[1], cz };
    var p: [joint_count]V = undefined;
    p[J.root.idx()] = base;
    p[J.hips.idx()] = at(base, h, 0, 0.53, 0);
    p[J.spine.idx()] = at(base, h, 0, 0.62, 0);
    p[J.chest.idx()] = at(base, h, 0, 0.72, 0);
    p[J.neck.idx()] = at(base, h, 0, 0.85, 0);
    p[J.head.idx()] = at(base, h, 0, 0.91, 0);
    inline for (.{ 1.0, -1.0 }, .{ .{ J.shoulder_l, J.upper_arm_l, J.lower_arm_l, J.hand_l }, .{ J.shoulder_r, J.upper_arm_r, J.lower_arm_r, J.hand_r } }) |side, arm| {
        p[arm[0].idx()] = at(base, h, 0.07 * side, 0.81, 0);
        p[arm[1].idx()] = at(base, h, 0.15 * side, 0.81, 0);
        if (t_pose) {
            // Elbow half-way to the wrist; the wrist a hand's length in from the fingertips.
            const wrist = @max(reach - 0.09 * h, 0.3 * h);
            p[arm[2].idx()] = .{ cx + side * (0.15 * h + wrist) / 2, lo[1] + 0.81 * h, cz };
            p[arm[3].idx()] = .{ cx + side * wrist, lo[1] + 0.81 * h, cz };
        } else {
            p[arm[2].idx()] = at(base, h, 0.21 * side, 0.64, 0);
            p[arm[3].idx()] = at(base, h, 0.26 * side, 0.49, 0);
        }
    }
    inline for (.{ 1.0, -1.0 }, .{ .{ J.thigh_l, J.shin_l, J.foot_l, J.toe_l }, .{ J.thigh_r, J.shin_r, J.foot_r, J.toe_r } }) |side, leg| {
        p[leg[0].idx()] = at(base, h, 0.09 * side, 0.50, 0);
        p[leg[1].idx()] = at(base, h, 0.09 * side, 0.27, 0);
        p[leg[2].idx()] = at(base, h, 0.09 * side, 0.05, 0);
        p[leg[3].idx()] = at(base, h, 0.09 * side, 0.02, 0.06);
    }
    return .{ .pivots = p, .t_pose = t_pose };
}

/// The far end of each joint's bone: the next joint down the chain, or a short tip for the ends.
fn tip(p: *const [joint_count]V, j: J) V {
    return switch (j) {
        .root, .hips => p[J.spine.idx()],
        .spine => p[J.chest.idx()],
        .chest => p[J.neck.idx()],
        .neck => p[J.head.idx()],
        .head => add(p[J.head.idx()], sub(p[J.head.idx()], p[J.neck.idx()])),
        .shoulder_l => p[J.upper_arm_l.idx()],
        .upper_arm_l => p[J.lower_arm_l.idx()],
        .lower_arm_l => p[J.hand_l.idx()],
        .hand_l => add(p[J.hand_l.idx()], scale(sub(p[J.hand_l.idx()], p[J.lower_arm_l.idx()]), 0.5)),
        .shoulder_r => p[J.upper_arm_r.idx()],
        .upper_arm_r => p[J.lower_arm_r.idx()],
        .lower_arm_r => p[J.hand_r.idx()],
        .hand_r => add(p[J.hand_r.idx()], scale(sub(p[J.hand_r.idx()], p[J.lower_arm_r.idx()]), 0.5)),
        .thigh_l => p[J.shin_l.idx()],
        .shin_l => p[J.foot_l.idx()],
        .foot_l => p[J.toe_l.idx()],
        .toe_l => add(p[J.toe_l.idx()], sub(p[J.toe_l.idx()], p[J.foot_l.idx()])),
        .thigh_r => p[J.shin_r.idx()],
        .shin_r => p[J.foot_r.idx()],
        .foot_r => p[J.toe_r.idx()],
        .toe_r => add(p[J.toe_r.idx()], sub(p[J.toe_r.idx()], p[J.foot_r.idx()])),
    };
}

fn segmentDistance2(x: V, a: V, b: V) f32 {
    const ab = sub(b, a);
    const len2 = dot(ab, ab);
    const t = if (len2 == 0) 0 else std.math.clamp(dot(sub(x, a), ab) / len2, 0, 1);
    const d = sub(x, add(a, scale(ab, t)));
    return dot(d, d);
}

/// Give `model` a skin bound to the game's skeleton. The mesh must not have one already.
pub fn apply(allocator: std.mem.Allocator, model: *Model) Error!Fit {
    std.debug.assert(model.skin == null);
    const f = try fit(model.mesh.vertices);
    // One bone per game joint below the root, in joint order.
    const bone_count = joint_count - 1;
    const bones = try allocator.alloc(Model.SkinBone, bone_count);
    errdefer allocator.free(bones);
    for (bones, 1..) |*b, j| b.* = .{ .ranger_joint = @intCast(j), .pivot = f.pivots[j] };
    const influences = try allocator.alloc(Model.SkinVertex, model.mesh.vertices.len);
    errdefer allocator.free(influences);
    var ends: [joint_count]V = undefined;
    for (&ends, 0..) |*e, j| e.* = tip(&f.pivots, @enumFromInt(j));
    for (model.mesh.vertices, influences) |v, *out| {
        // The two nearest bones; the nearer takes more of the weight.
        var best: [2]struct { bone: u8, d2: f32 } = .{ .{ .bone = 0, .d2 = std.math.inf(f32) }, .{ .bone = 0, .d2 = std.math.inf(f32) } };
        for (1..joint_count) |j| {
            const d2 = segmentDistance2(v.position, f.pivots[j], ends[j]);
            const bone: u8 = @intCast(j - 1);
            if (d2 < best[0].d2) {
                best[1] = best[0];
                best[0] = .{ .bone = bone, .d2 = d2 };
            } else if (d2 < best[1].d2) best[1] = .{ .bone = bone, .d2 = d2 };
        }
        const eps: f32 = 1e-6;
        var w0 = 1 / (best[0].d2 + eps);
        var w1 = if (best[1].d2 < best[0].d2 * 4) 1 / (best[1].d2 + eps) else 0;
        const total = w0 + w1;
        w0 /= total;
        w1 /= total;
        out.* = .{ .joints = .{ best[0].bone, best[1].bone, 0, 0 }, .weights = .{ w0, w1, 0, 0 } };
    }
    model.skin = .{ .vertices = influences, .bones = bones };
    return f;
}

fn testModel(allocator: std.mem.Allocator, points: []const V) !Model {
    const Mesh = @import("../render/Mesh.zig");
    const vertices = try allocator.alloc(Mesh.Vertex, points.len);
    for (vertices, points) |*v, p| v.* = .{ .position = p, .normal = .{ 0, 1, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1 } };
    const indices = try allocator.alloc(u32, 3);
    @memcpy(indices, &[_]u32{ 0, 1, 2 });
    return Model.fromMesh(allocator, .{ .vertices = vertices, .indices = indices }, Model.Material.named("body", .{ 1, 1, 1, 1 }));
}

test "an A-pose mesh gets hanging arms, a T-pose mesh arms out to its fingertips" {
    // A 2-unit-tall figure: feet, head top, and hands either at the hips or out at shoulder height.
    const a_pose = [_]V{ .{ 0, 0, 0 }, .{ 0, 2, 0 }, .{ 0.5, 1.0, 0 }, .{ -0.5, 1.0, 0 } };
    const t_pose = [_]V{ .{ 0, 0, 0 }, .{ 0, 2, 0 }, .{ 1.0, 1.62, 0 }, .{ -1.0, 1.62, 0 } };
    const a = try fit(&@as([4]@import("../render/Mesh.zig").Vertex, .{
        .{ .position = a_pose[0], .normal = .{ 0, 1, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1 } },
        .{ .position = a_pose[1], .normal = .{ 0, 1, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1 } },
        .{ .position = a_pose[2], .normal = .{ 0, 1, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1 } },
        .{ .position = a_pose[3], .normal = .{ 0, 1, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1 } },
    }));
    try std.testing.expect(!a.t_pose);
    try std.testing.expect(a.pivots[J.hand_l.idx()][1] < a.pivots[J.upper_arm_l.idx()][1]);
    var model = try testModel(std.testing.allocator, &t_pose);
    defer model.deinit(std.testing.allocator);
    const t = try apply(std.testing.allocator, &model);
    try std.testing.expect(t.t_pose);
    // Arms run out level, the left one to +x, the hand inside the fingertips.
    try std.testing.expectApproxEqAbs(t.pivots[J.upper_arm_l.idx()][1], t.pivots[J.hand_l.idx()][1], 1e-5);
    try std.testing.expect(t.pivots[J.hand_l.idx()][0] > 0.6 and t.pivots[J.hand_l.idx()][0] < 1.0);
    try std.testing.expect(t.pivots[J.hand_r.idx()][0] < -0.6);
    // The left fingertip vertex follows the left hand; the feet follow a leg.
    const skin = model.skin.?;
    try std.testing.expectEqual(@as(u8, J.hand_l.idx() - 1), skin.vertices[2].joints[0]);
    try std.testing.expectEqual(@as(u8, J.hand_r.idx() - 1), skin.vertices[3].joints[0]);
    const foot = skin.bones[skin.vertices[0].joints[0]].ranger_joint;
    try std.testing.expect(foot == J.foot_l.idx() or foot == J.foot_r.idx() or foot == J.toe_l.idx() or foot == J.toe_r.idx() or foot == J.shin_l.idx() or foot == J.shin_r.idx());
    for (skin.vertices) |v| try std.testing.expectApproxEqAbs(@as(f32, 1), v.weights[0] + v.weights[1], 1e-5);
}

test "an empty or flat mesh is refused" {
    try std.testing.expectError(error.EmptyMesh, fit(&.{}));
    const flat = [_]@import("../render/Mesh.zig").Vertex{.{ .position = .{ 0, 1, 0 }, .normal = .{ 0, 1, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1 } }};
    try std.testing.expectError(error.FlatMesh, fit(&flat));
}
