//! One-call character assembly: spec -> skeleton + skinned mesh (body,
//! clothing, hair) + dynamic chains, plus the per-material palette.

const std = @import("std");
const m = @import("math.zig");
const mesh_mod = @import("mesh.zig");
const skel_mod = @import("skeleton.zig");
const spec_mod = @import("spec.zig");
const body = @import("body.zig");
const clothing = @import("clothing.zig");
const hair = @import("hair.zig");
const spring = @import("spring.zig");
const preview = @import("preview.zig");
const Vec3 = m.Vec3;
const Rgb = spec_mod.Rgb;
const Allocator = std.mem.Allocator;

pub const Character = struct {
    spec: spec_mod.CharacterSpec,
    landmarks: body.Landmarks,
    skeleton: skel_mod.Skeleton,
    mesh: mesh_mod.Mesh,
    /// Per-vertex color index into `palette` (garments each get their own color).
    color_index: std.ArrayList(u8) = .empty,
    palette: std.ArrayList(Rgb) = .empty,
    /// Spring-bone chains (hair, skirt) referencing skeleton joints.
    chains: std.ArrayList(spring.Chain) = .empty,
    /// Collision shapes the chains are pushed out of.
    colliders: std.ArrayList(spring.Collider) = .empty,

    pub fn build(gpa: Allocator, spec: spec_mod.CharacterSpec) !Character {
        const lm = body.computeLandmarks(spec);
        var c: Character = .{
            .spec = spec,
            .landmarks = lm,
            .skeleton = try body.buildSkeleton(gpa, spec, lm),
            .mesh = .{},
        };
        errdefer c.deinit(gpa);

        try c.colliders.appendSlice(gpa, &clothing.defaultColliders(lm));

        // 0 = skin
        try c.palette.append(gpa, spec.skin);
        try body.buildBody(gpa, &c.mesh, spec, lm, &c.skeleton);
        try c.tagNewVertices(gpa, 0);

        // garments, inner layers first
        for (spec.outfit) |g| {
            const color_idx: u8 = @intCast(c.palette.items.len);
            try c.palette.append(gpa, g.color);
            var piece: mesh_mod.Mesh = .{};
            defer piece.deinit(gpa);
            switch (g.kind) {
                .shell => try clothing.buildShell(gpa, &piece, &c.mesh, g, lm),
                .skirt => try clothing.buildSkirt(gpa, &piece, &c.mesh, &c.skeleton, &c.chains, &c.colliders, g, lm, spec),
            }
            try c.mesh.append(gpa, &piece);
            try c.tagNewVertices(gpa, color_idx);
        }

        // hair
        {
            const color_idx: u8 = @intCast(c.palette.items.len);
            try c.palette.append(gpa, spec.hair.color);
            var piece: mesh_mod.Mesh = .{};
            defer piece.deinit(gpa);
            try hair.buildHair(gpa, &piece, &c.skeleton, &c.chains, spec, lm);
            try c.mesh.append(gpa, &piece);
            try c.tagNewVertices(gpa, color_idx);
        }
        c.mesh.normalizeWeights();
        return c;
    }

    fn tagNewVertices(c: *Character, gpa: Allocator, idx: u8) !void {
        const n = c.mesh.vertices.items.len - c.color_index.items.len;
        try c.color_index.appendNTimes(gpa, idx, n);
    }

    pub fn deinit(c: *Character, gpa: Allocator) void {
        c.skeleton.deinit(gpa);
        c.mesh.deinit(gpa);
        c.color_index.deinit(gpa);
        c.palette.deinit(gpa);
        for (c.chains.items) |*ch| ch.deinit(gpa);
        c.chains.deinit(gpa);
        c.colliders.deinit(gpa);
    }
};

/// Per-instance animation state: pose, spring simulation, skinning output.
/// Typical frame:
///   inst.pose.reset(&ch.skeleton);           // or write your animation clip
///   ...set rotations / run IK...
///   inst.pose.updateGlobal(&ch.skeleton);
///   inst.simulate(ch, dt);                   // hair & skirt
///   inst.skin(ch);                           // -> inst.pos / inst.nrm
pub const Instance = struct {
    pose: skel_mod.Pose,
    dqs: []skel_mod.DualQuat,
    pos: []Vec3,
    nrm: []Vec3,

    pub fn init(gpa: Allocator, ch: *Character) !Instance {
        var pose = try skel_mod.Pose.init(gpa, &ch.skeleton);
        errdefer pose.deinit(gpa);
        const n = ch.mesh.vertices.items.len;
        const dqs = try gpa.alloc(skel_mod.DualQuat, ch.skeleton.count());
        errdefer gpa.free(dqs);
        const pos = try gpa.alloc(Vec3, n);
        errdefer gpa.free(pos);
        const nrm = try gpa.alloc(Vec3, n);
        const inst: Instance = .{ .pose = pose, .dqs = dqs, .pos = pos, .nrm = nrm };
        for (ch.chains.items) |*c| c.reset(&inst.pose);
        return inst;
    }
    pub fn deinit(i: *Instance, gpa: Allocator) void {
        i.pose.deinit(gpa);
        gpa.free(i.dqs);
        gpa.free(i.pos);
        gpa.free(i.nrm);
    }
    /// Step every spring chain, then refresh global transforms.
    pub fn simulate(i: *Instance, ch: *Character, dt: f32) void {
        for (ch.chains.items) |*c| c.step(&ch.skeleton, &i.pose, dt, ch.colliders.items);
        i.pose.updateGlobal(&ch.skeleton);
    }
    /// Dual-quaternion skin the mesh into `pos`/`nrm`.
    pub fn skin(i: *Instance, ch: *const Character) void {
        i.pose.skinDualQuats(&ch.skeleton, i.dqs);
        skel_mod.skinDualQuat(ch.mesh.vertices.items, i.dqs, i.pos, i.nrm);
    }
    /// Skinned data + head frame, ready for `preview.render`.
    pub fn posed(i: *const Instance) preview.Posed {
        const head = i.pose.global[skel_mod.Joint.head.idx()].rotation;
        return .{ .pos = i.pos, .nrm = i.nrm, .head_fwd = head.rotate(Vec3.unit_z), .head_left = head.rotate(Vec3.unit_x) };
    }
};

test "full character builds with clothes and hair" {
    const gpa = std.testing.allocator;
    var c = try Character.build(gpa, .{ .outfit = &spec_mod.school_uniform });
    defer c.deinit(gpa);
    try std.testing.expectEqual(c.mesh.vertices.items.len, c.color_index.items.len);
    try std.testing.expect(c.chains.items.len > 0);
    try std.testing.expect(c.skeleton.count() > skel_mod.humanoid_joint_count);
    for (c.mesh.indices.items) |i| try std.testing.expect(i < c.mesh.vertices.items.len);
}
