//! Game-facing smooth ranger: skinned anatomy, fabric layers, rigid armor and a procedural gait.
//! The supplied character generator owns geometry; this adapter owns game appearance and pose.
const std = @import("std");
const Profile = @import("../game/Profile.zig");
const Player = @import("../game/Player.zig");
const gen = @import("character.zig");
const spec = @import("spec.zig");
const sk = @import("skeleton.zig");
const cm = @import("mesh.zig");
const m = @import("math.zig");
const Mesh = @import("../render/Mesh.zig");
const V = m.Vec3;
const Q = m.Quat;
const Ranger = @This();
pub const capacity = 16;
pub const Pose = struct { feet: [3]f32, yaw: f32, walk_phase: f32 = 0, walk_amount: f32 = 0, motion: Player.Motion = .idle, time: f32 = 0 };
pub const Draw = struct { profile: Profile, pose: Pose, id: u8 = 0 };
character: gen.Character,
instance: gen.Instance,
mesh: Mesh,
profile: Profile,

fn rgb(c: [4]f32, factor: f32) spec.Rgb {
    return .{ .r = c[0] * factor, .g = c[1] * factor, .b = c[2] * factor };
}
pub fn init(a: std.mem.Allocator, profile: Profile) !Ranger {
    const cloth = Profile.outfit_colors[profile.outfit];
    var garments = [_]spec.GarmentSpec{
        .{ .coverage = .long_sleeve, .color = rgb(cloth, 0.35), .neckline = .high },
        .{ .coverage = .leggings, .color = rgb(cloth, 0.32) },
        .{ .coverage = .gloves, .color = spec.Rgb.hex(0x18242c), .layer = 2, .looseness = 0.003 },
        .{ .coverage = .shoes, .color = spec.Rgb.hex(0x202c36), .layer = 3, .looseness = 0.009 },
        .{ .coverage = .long_sleeve, .color = rgb(cloth, 1), .layer = 3, .looseness = 0.013, .neckline = .v },
    };
    var ch = try gen.Character.build(a, .{
        .body = .{ .height = 1.8 * profile.height, .head_ratio = 7.5, .femininity = 0.3, .bust = 0.12, .shoulder_width = 1.10 * profile.build, .waist_width = 1.12 * profile.build, .hip_width = profile.build, .limb_thickness = 1.1 * profile.build, .head_width = 0.78, .jaw_sharpness = 0.4 },
        .skin = rgb(Profile.skin_tones[profile.skin], 1),
        .eyes = .{ .size = 0.15, .aspect = 0.55 },
        .hair = .{ .style = switch (profile.hair_style) {
            .short, .crest => .short_spiky,
            .ponytail => .twin_tails,
            .long => .long_straight,
            .hood => .bob,
        }, .color = rgb(Profile.hair_colors[profile.hair_color], 1), .ahoge = false, .chain_joints = 0, .length = 1.4, .volume = 0.7, .bang_count = 5 },
        .outfit = garments[0..if (profile.clothing == .field_jacket) 5 else 4],
        .detail = 0.7,
    });
    errdefer ch.deinit(a);
    // The generator consumes outfit specifications synchronously; never retain a stack slice.
    ch.spec.outfit = &.{};
    try equip(a, &ch, profile);
    var inst = try gen.Instance.init(a, &ch);
    errdefer inst.deinit(a);
    const vertices = try a.alloc(Mesh.Vertex, ch.mesh.vertices.items.len);
    errdefer a.free(vertices);
    const indices = try a.dupe(u32, ch.mesh.indices.items);
    var self: Ranger = .{ .character = ch, .instance = inst, .mesh = .{ .vertices = vertices, .indices = indices }, .profile = profile };
    for (self.mesh.vertices, self.character.mesh.vertices.items, self.character.color_index.items) |*v, source, color| {
        const c = self.character.palette.items[color];
        v.* = .{ .position = .{ source.pos.x, source.pos.y, source.pos.z }, .normal = .{ source.normal.x, source.normal.y, source.normal.z }, .uv = .{ 0, 0 }, .color = .{ c.r, c.g, c.b } };
    }
    self.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0 });
    return self;
}
pub fn deinit(self: *Ranger, a: std.mem.Allocator) void {
    self.mesh.deinit(a);
    self.instance.deinit(a);
    self.character.deinit(a);
}
pub fn sameAppearance(a: Profile, b: Profile) bool {
    // Names do not affect mesh generation.
    var x = a;
    var y = b;
    x.name_buffer = @splat(0);
    y.name_buffer = @splat(0);
    x.name_len = 0;
    y.name_len = 0;
    return std.meta.eql(x, y);
}
pub fn update(self: *Ranger, state: Pose) void {
    const p = &self.instance.pose;
    p.reset(&self.character.skeleton);
    const amount = std.math.clamp(state.walk_amount, 0, 1);
    const swing = @sin(state.walk_phase) * 0.65 * amount;
    const airborne = switch (state.motion) {
        .jump, .fall, .jet, .hover, .glide, .grapple_zip, .grapple_swing => true,
        else => false,
    };
    const climbing = state.motion == .climb or state.motion == .hang or state.motion == .wall_slide or state.motion == .mantle;
    inline for ([_]sk.Joint{ .upper_arm_l, .upper_arm_r }, [_]sk.Joint{ .lower_arm_l, .lower_arm_r }, [_]sk.Joint{ .thigh_l, .thigh_r }, [_]sk.Joint{ .shin_l, .shin_r }, .{ @as(f32, 1), @as(f32, -1) }) |arm, elbow, thigh, knee, side| {
        // Bring the generated A-pose down to relaxed arms beside the torso.
        p.rotateLocal(arm.idx(), Q.fromAxisAngle(V.unit_z, -side * (if (climbing) @as(f32, -1.1) else if (airborne) @as(f32, 0.35) else @as(f32, 0.76))));
        p.rotateLocal(arm.idx(), Q.fromAxisAngle(V.unit_x, -swing * side * 0.75 - 0.08));
        p.rotateLocal(elbow.idx(), Q.fromAxisAngle(V.unit_x, -0.15 - 0.3 * amount));
        p.rotateLocal(thigh.idx(), Q.fromAxisAngle(V.unit_x, swing * side - (if (airborne) @as(f32, 0.25) else @as(f32, 0))));
        p.rotateLocal(knee.idx(), Q.fromAxisAngle(V.unit_x, @max(0, -swing * side) * 1.2 + (if (airborne) @as(f32, 0.5) else @as(f32, 0))));
    }
    p.rotateLocal(sk.Joint.chest.idx(), Q.fromAxisAngle(V.unit_y, swing * 0.08));
    p.local[sk.Joint.hips.idx()].translation.y += @sin(state.time * 2) * 0.003 * (1 - amount);
    if (state.motion == .roll or state.motion == .dash or state.motion == .board) p.rotateLocal(sk.Joint.spine.idx(), Q.fromAxisAngle(V.unit_x, 0.35));
    p.updateGlobal(&self.character.skeleton);
    self.instance.skin(&self.character);
    for (self.mesh.vertices, self.instance.pos, self.instance.nrm) |*v, pos, normal| {
        v.position = .{ pos.x, pos.y, pos.z };
        v.normal = .{ normal.x, normal.y, normal.z };
    }
}

/// Smooth, closed ellipsoidal armor pieces, attached rigidly to a joint. Flexible fabric keeps
/// blended body weights underneath; panels do not stretch across elbows or knees.
fn plate(a: std.mem.Allocator, ch: *gen.Character, joint: sk.Joint, center: V, radii: V, color: spec.Rgb) !void {
    const rows = 10;
    const cols = 20;
    const base = ch.mesh.vertexCount();
    const palette: u8 = @intCast(ch.palette.items.len);
    try ch.palette.append(a, color);
    for (0..rows + 1) |r| for (0..cols) |c| {
        const latitude = m.pi * @as(f32, @floatFromInt(r)) / rows;
        const angle = m.tau * @as(f32, @floatFromInt(c)) / cols;
        const n = V.init(@sin(latitude) * @cos(angle), @cos(latitude), @sin(latitude) * @sin(angle));
        _ = try ch.mesh.addVertex(a, .{ .pos = center.add(V.init(n.x * radii.x, n.y * radii.y, n.z * radii.z)), .normal = V.init(n.x / radii.x, n.y / radii.y, n.z / radii.z).normalize(), .joints = .{ joint.idx(), 0, 0, 0 }, .material = .cloth_outer });
        try ch.color_index.append(a, palette);
    };
    try ch.mesh.stitchRings(a, base, rows + 1, cols, true, false);
}
fn equip(a: std.mem.Allocator, ch: *gen.Character, p: Profile) !void {
    const lm = ch.landmarks;
    const s = &ch.skeleton;
    const h = p.height;
    const w = p.build;
    const dark = spec.Rgb.hex(0x17242f);
    const metal = if (p.armor == .sentinel) spec.Rgb.hex(0xc1cbd0) else spec.Rgb.hex(0x71868e);
    const accent = rgb(Profile.accent_colors[p.accent], 1.2);
    // Face details have actual geometry, including eye whites, irises and brows.
    for ([_]f32{ -1, 1 }) |side| {
        const eye = V.init(side * lm.head_half_width * 0.42, lm.chin_y + 0.46 * lm.H, 0.43 * lm.H);
        try plate(a, ch, .head, eye, V.init(0.026 * h, 0.012 * h, 0.009 * h), spec.Rgb.hex(0xe2ddd1));
        try plate(a, ch, .head, eye.add(V.init(0, 0, 0.009 * h)), V.init(0.008 * h, 0.009 * h, 0.003 * h), spec.Rgb.hex(0x183e48));
        try plate(a, ch, .head, eye.add(V.init(0, 0.021 * h, -0.001 * h)), V.init(0.030 * h, 0.004 * h, 0.009 * h), rgb(Profile.hair_colors[p.hair_color], 0.5));
    }
    // Belt, boot cuffs and wrist seals bridge fabric transitions.
    try plate(a, ch, .hips, V.init(0, lm.waist_y - 0.08 * h, 0), V.init(lm.waist_half_width + 0.035, 0.035 * h, lm.waist_half_depth + 0.028), dark);
    if (p.armor != .none) {
        const bulk: f32 = if (p.armor == .sentinel) 1.15 else 1;
        const chest = s.worldPos(.chest);
        for ([_]f32{ -1, 1 }) |side| try plate(a, ch, .chest, chest.add(V.init(side * 0.09 * w, 0.005 * h, 0.075 * h)), V.init(0.105 * w, 0.16 * h, 0.09 * bulk * h), metal);
        try plate(a, ch, .chest, chest.add(V.init(0, 0.01 * h, -0.09 * h)), V.init(0.15 * w, 0.20 * h, 0.095 * h), dark);
        try plate(a, ch, .chest, chest.add(V.init(0, 0.06 * h, -0.185 * h)), V.init(0.038 * h, 0.10 * h, 0.012 * h), accent);
        try plate(a, ch, .chest, chest.add(V.init(0, 0.045 * h, 0.168 * h)), V.init(0.027 * h, 0.058 * h, 0.009 * h), accent);
        inline for ([_]sk.Joint{ .upper_arm_l, .upper_arm_r }, [_]sk.Joint{ .lower_arm_l, .lower_arm_r }, [_]sk.Joint{ .shin_l, .shin_r }, [_]sk.Joint{ .thigh_l, .thigh_r }, .{ @as(f32, 1), @as(f32, -1) }) |arm, forearm, shin, thigh, side| {
            const dir = V.init(lm.arm_dir_l.x * side, lm.arm_dir_l.y, 0);
            try plate(a, ch, arm, s.worldPos(arm).addScaled(dir, 0.04 * h), V.init(0.105 * w * bulk, 0.105 * h * bulk, 0.105 * h), metal);
            try plate(a, ch, forearm, s.worldPos(forearm).addScaled(dir, 0.12 * h).add(V.init(0, 0, 0.035 * h)), V.init(0.060 * w, 0.12 * h, 0.065 * h), metal);
            try plate(a, ch, shin, s.worldPos(shin).add(V.init(0, -0.02 * h, 0.055 * h)), V.init(0.071 * w, 0.09 * h, 0.055 * h), metal);
            if (p.armor == .sentinel) {
                try plate(a, ch, thigh, s.worldPos(thigh).add(V.init(side * 0.035 * w, -0.16 * h, 0.04 * h)), V.init(0.090 * w, 0.15 * h, 0.075 * h), metal);
                try plate(a, ch, shin, s.worldPos(shin).add(V.init(0, -0.21 * h, 0.025 * h)), V.init(0.061 * w, 0.16 * h, 0.069 * h), metal);
            }
        }
    }
    if (p.helmet == .sealed or p.hair_style == .hood) {
        // Conceal hair under the helmet/hood instead of allowing it to poke through.
        var write: usize = 0;
        var i: usize = 0;
        while (i < ch.mesh.indices.items.len) : (i += 3) {
            const tri = ch.mesh.indices.items[i..][0..3];
            if (ch.mesh.vertices.items[tri[0]].material == .hair) continue;
            @memcpy(ch.mesh.indices.items[write..][0..3], tri);
            write += 3;
        }
        ch.mesh.indices.shrinkRetainingCapacity(write);
        try plate(a, ch, .head, V.init(0, lm.chin_y + 0.56 * lm.H, -0.02 * h), V.init(lm.head_half_width + 0.024 * h, 0.56 * lm.H, 0.14 * h), if (p.helmet == .sealed) metal else rgb(Profile.outfit_colors[p.outfit], 0.7));
    }
    if (p.helmet != .open) {
        const center = V.init(0, lm.chin_y + 0.47 * lm.H, 0.105 * h);
        try plate(a, ch, .head, center, V.init(0.117 * h, 0.048 * h, 0.052 * h), dark);
        try plate(a, ch, .head, center.add(V.init(0, 0.012 * h, 0.036 * h)), V.init(0.103 * h, 0.024 * h, 0.022 * h), accent);
    }
}

test "ranger meshes are smooth, layered, weighted and animate without allocations" {
    const a = std.testing.allocator;
    var ranger = try init(a, .{});
    defer ranger.deinit(a);
    try std.testing.expect(ranger.mesh.vertices.len > 2000);
    const hand = ranger.character.skeleton.worldPos(.hand_l);
    ranger.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0, .walk_amount = 1, .walk_phase = 1.2 });
    try std.testing.expect(ranger.instance.pose.global[sk.Joint.hand_l.idx()].translation.sub(hand).length() > 0.1);
    for (ranger.mesh.vertices) |v| for (v.position ++ v.normal) |value| try std.testing.expect(std.math.isFinite(value));
    for (ranger.character.mesh.vertices.items) |v| {
        var total: f32 = 0;
        for (v.weights, v.joints) |weight, joint| {
            total += weight;
            if (weight > 0) try std.testing.expect(joint < ranger.character.skeleton.count());
        }
        try std.testing.expectApproxEqAbs(@as(f32, 1), total, 0.001);
    }
    var light = try init(a, .{ .armor = .none, .helmet = .open, .clothing = .undersuit });
    defer light.deinit(a);
    try std.testing.expect(light.mesh.indices.len < ranger.mesh.indices.len);
    var heavy = try init(a, .{ .armor = .sentinel, .helmet = .sealed });
    defer heavy.deinit(a);
    try std.testing.expect(heavy.mesh.indices.len > ranger.mesh.indices.len);
}
