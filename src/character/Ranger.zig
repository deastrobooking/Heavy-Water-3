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
    var garments: [16]spec.GarmentSpec = undefined;
    const outfit_len = outfit(profile, &garments);
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
        .outfit = garments[0..outfit_len],
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

fn mix(a: [4]f32, b: spec.Rgb, t: f32) spec.Rgb {
    return .{ .r = a[0] + (b.r - a[0]) * t, .g = a[1] + (b.g - a[1]) * t, .b = a[2] + (b.b - a[2]) * t };
}

/// The garment list for a profile: an undersuit, then a jacket or a hard-surface armor suit.
/// Armor plates are rigid, domed, segmented shells from the character generator (see
/// `clothing.zig`), layered outside the suit so nothing clips.
pub fn outfit(profile: Profile, out: *[16]spec.GarmentSpec) usize {
    const cloth = Profile.outfit_colors[profile.outfit];
    const dark = spec.Rgb.hex(0x18242c);
    var n: usize = 0;
    const Add = struct {
        fn one(list: *[16]spec.GarmentSpec, count: *usize, g: spec.GarmentSpec) void {
            list[count.*] = g;
            count.* += 1;
        }
    };
    Add.one(out, &n, .{ .coverage = .long_sleeve, .color = rgb(cloth, 0.35), .neckline = .high });
    Add.one(out, &n, .{ .coverage = .leggings, .color = rgb(cloth, 0.32) });
    switch (profile.clothing) {
        .undersuit, .field_jacket => {
            Add.one(out, &n, .{ .coverage = .gloves, .color = dark, .layer = 2, .looseness = 0.003 });
            Add.one(out, &n, .{ .coverage = .shoes, .color = spec.Rgb.hex(0x202c36), .layer = 3, .looseness = 0.009 });
            if (profile.clothing == .field_jacket) Add.one(out, &n, .{ .coverage = .long_sleeve, .color = rgb(cloth, 1), .layer = 3, .looseness = 0.013, .neckline = .v });
        },
        .exo_rig, .hardsuit, .vanguard => {
            const heavy = profile.clothing == .vanguard;
            const steel = if (heavy) mix(cloth, spec.Rgb.hex(0x3b4650), 0.6) else mix(cloth, spec.Rgb.hex(0xc3ccd1), 0.55);
            const trim = mix(cloth, spec.Rgb.hex(0x22303a), 0.7);
            const bulge: f32 = if (heavy) 0.011 else 0.006;
            const lift: f32 = if (heavy) 0.006 else 0.002;
            Add.one(out, &n, .{ .coverage = .gauntlets, .color = trim, .layer = 2, .looseness = 0.004, .hard = true, .bulge = 0.003 });
            Add.one(out, &n, .{ .coverage = .sabatons, .color = trim, .layer = 3, .looseness = 0.010, .hard = true, .bulge = 0.004 });
            Add.one(out, &n, .{ .coverage = .vambraces, .color = steel, .layer = 3, .looseness = 0.004 + lift, .hard = true, .bulge = bulge, .segments = 2 });
            Add.one(out, &n, .{ .coverage = .greaves, .color = steel, .layer = 4, .looseness = 0.005 + lift, .hard = true, .bulge = bulge, .segments = 2 });
            Add.one(out, &n, .{ .coverage = .pauldrons, .color = steel, .layer = 4, .looseness = (if (profile.clothing == .exo_rig) @as(f32, 0.006) else 0.012) + lift, .hard = true, .bulge = bulge * 1.4, .segments = if (profile.clothing == .exo_rig) 1 else 2 });
            if (profile.clothing != .exo_rig) {
                Add.one(out, &n, .{ .coverage = .cuirass, .color = steel, .layer = 4, .looseness = 0.008 + lift, .hard = true, .bulge = bulge, .segments = 3, .neckline = .high });
                Add.one(out, &n, .{ .coverage = .faulds, .color = trim, .layer = 3, .looseness = 0.010 + lift, .hard = true, .bulge = bulge * 0.7, .segments = 2 });
                Add.one(out, &n, .{ .coverage = .cuisses, .color = steel, .layer = 3, .looseness = 0.004 + lift, .hard = true, .bulge = bulge, .segments = 2 });
            }
        },
    }
    return n;
}

/// Smooth, closed ellipsoidal armor pieces, attached rigidly to a joint. Flexible fabric keeps
/// blended body weights underneath; panels do not stretch across elbows or knees.
fn plate(a: std.mem.Allocator, ch: *gen.Character, joint: sk.Joint, center: V, radii: V, color: spec.Rgb) !void {
    try plateWithMaterial(a, ch, joint, center, radii, color, .cloth_outer);
}

fn plateWithMaterial(a: std.mem.Allocator, ch: *gen.Character, joint: sk.Joint, center: V, radii: V, color: spec.Rgb, material: cm.Material) !void {
    const rows = 10;
    const cols = 20;
    const base = ch.mesh.vertexCount();
    const palette: u8 = @intCast(ch.palette.items.len);
    try ch.palette.append(a, color);
    for (0..rows + 1) |r| for (0..cols) |c| {
        const latitude = m.pi * @as(f32, @floatFromInt(r)) / rows;
        const angle = m.tau * @as(f32, @floatFromInt(c)) / cols;
        const n = V.init(@sin(latitude) * @cos(angle), @cos(latitude), @sin(latitude) * @sin(angle));
        _ = try ch.mesh.addVertex(a, .{ .pos = center.add(V.init(n.x * radii.x, n.y * radii.y, n.z * radii.z)), .normal = V.init(n.x / radii.x, n.y / radii.y, n.z / radii.z).normalize(), .joints = .{ joint.idx(), 0, 0, 0 }, .material = material });
        try ch.color_index.append(a, palette);
    };
    try ch.mesh.stitchRings(a, base, rows + 1, cols, true, false);
}

/// Curved face shield with a camera-facing normal, narrower upper/lower corners, and a wrap at
/// the temples. Its separate palette entry lets the inset light slit read cleanly over the lens.
fn visorSurface(a: std.mem.Allocator, ch: *gen.Character, center: V, half_width: f32, half_height: f32, depth: f32, color: spec.Rgb, rows: u32, cols: u32) !void {
    const base = ch.mesh.vertexCount();
    const joint = sk.Joint.head.idx();
    const palette: u8 = @intCast(ch.palette.items.len);
    try ch.palette.append(a, color);
    for (0..rows + 1) |row| for (0..cols + 1) |column| {
        const v = @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(rows)) * 2 - 1;
        const u = @as(f32, @floatFromInt(column)) / @as(f32, @floatFromInt(cols)) * 2 - 1;
        const width_scale = 1 - 0.10 * v * v;
        const x = u * half_width * width_scale;
        const y = center.y + v * half_height;
        const z = center.z + depth * (1 - u * u);
        const normal = V.init(2 * depth * u / (half_width * width_scale), 0.18 * v, 1).normalize();
        _ = try ch.mesh.addVertex(a, .{ .pos = .{ .x = x, .y = y, .z = z }, .normal = normal, .joints = .{ joint, 0, 0, 0 }, .material = .armor });
        try ch.color_index.append(a, palette);
    };
    const stride = cols + 1;
    for (0..rows) |row| for (0..cols) |column| {
        const a0: u32 = base + @as(u32, @intCast(row)) * stride + @as(u32, @intCast(column));
        const b0 = a0 + 1;
        const d0 = a0 + stride;
        const c0 = d0 + 1;
        try ch.mesh.addTri(a, a0, b0, c0);
        try ch.mesh.addTri(a, a0, c0, d0);
    };
}

fn equip(a: std.mem.Allocator, ch: *gen.Character, p: Profile) !void {
    const lm = ch.landmarks;
    const s = &ch.skeleton;
    const h = p.height;
    const w = p.build;
    const dark = spec.Rgb.hex(0x17242f);
    const metal = switch (p.armor) {
        .sentinel => spec.Rgb.hex(0xc1cbd0),
        .rootweave => spec.Rgb.hex(0x66815a),
        .skyguard => spec.Rgb.hex(0x477b88),
        else => spec.Rgb.hex(0x71868e),
    };
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
    if (p.clothing == .field_jacket) {
        const chest = s.worldPos(.chest);
        const pocket = mix(Profile.outfit_colors[p.outfit], spec.Rgb.hex(0x1b2a32), 0.52);
        for ([_]f32{ -1, 1 }) |side| {
            try plate(a, ch, .chest, chest.add(V.init(side * 0.105 * h, -0.105 * h, 0.145 * h)), V.init(0.040 * h, 0.052 * h, 0.018 * h), pocket);
            try plate(a, ch, .chest, chest.add(V.init(side * 0.105 * h, -0.066 * h, 0.160 * h)), V.init(0.027 * h, 0.004 * h, 0.006 * h), accent);
        }
    }
    // A full armor suit already plates the limbs and torso; only its chest lights are added.
    const suited = p.clothing == .hardsuit or p.clothing == .vanguard;
    if (p.armor != .none and suited) {
        const chest = s.worldPos(.chest);
        try plate(a, ch, .chest, chest.add(V.init(0, 0.06 * h, -0.185 * h)), V.init(0.038 * h, 0.10 * h, 0.012 * h), accent);
        try plate(a, ch, .chest, chest.add(V.init(0, 0.045 * h, 0.17 * h)), V.init(0.027 * h, 0.058 * h, 0.009 * h), accent);
    }
    if (p.armor != .none and !suited) {
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
    switch (p.armor) {
        .rootweave => {
            const chest = s.worldPos(.chest);
            for ([_]f32{ -1, 1 }) |side| {
                try plateWithMaterial(a, ch, if (side > 0) .shoulder_l else .shoulder_r, s.worldPos(if (side > 0) .shoulder_l else .shoulder_r).add(V.init(side * 0.025 * h, 0, 0.035 * h)), V.init(0.13 * w, 0.075 * h, 0.105 * h), metal, .armor);
                try plateWithMaterial(a, ch, if (side > 0) .lower_arm_l else .lower_arm_r, s.worldPos(if (side > 0) .lower_arm_l else .lower_arm_r).add(V.init(side * 0.035 * h, 0, 0.025 * h)), V.init(0.070 * w, 0.16 * h, 0.065 * h), spec.Rgb.hex(0x425c3c), .armor);
                try plateWithMaterial(a, ch, .chest, chest.add(V.init(side * 0.065 * h, -0.035 * h, 0.153 * h)), V.init(0.012 * h, 0.13 * h, 0.010 * h), accent, .armor);
            }
        },
        .skyguard => {
            for ([_]f32{ -1, 1 }) |side| {
                const shoulder: sk.Joint = if (side > 0) .shoulder_l else .shoulder_r;
                const forearm: sk.Joint = if (side > 0) .lower_arm_l else .lower_arm_r;
                const shin: sk.Joint = if (side > 0) .shin_l else .shin_r;
                try plateWithMaterial(a, ch, shoulder, s.worldPos(shoulder).add(V.init(side * 0.045 * h, 0.015 * h, 0)), V.init(0.15 * w, 0.055 * h, 0.080 * h), metal, .armor);
                try plateWithMaterial(a, ch, forearm, s.worldPos(forearm).add(V.init(side * 0.022 * h, -0.025 * h, 0.026 * h)), V.init(0.046 * w, 0.14 * h, 0.036 * h), spec.Rgb.hex(0x31535f), .armor);
                try plateWithMaterial(a, ch, shin, s.worldPos(shin).add(V.init(0, -0.025 * h, 0.045 * h)), V.init(0.055 * w, 0.12 * h, 0.040 * h), metal, .armor);
                try plateWithMaterial(a, ch, forearm, s.worldPos(forearm).add(V.init(side * 0.018 * h, 0.035 * h, 0.061 * h)), V.init(0.008 * h, 0.085 * h, 0.006 * h), accent, .armor);
            }
        },
        else => {},
    }
    if (p.helmet == .sealed or p.hair_style == .hood) {
        // Conceal hair under the helmet/hood instead of allowing it to poke through.
        var write: usize = 0;
        var i: usize = 0;
        while (i < ch.mesh.indices.items.len) : (i += 3) {
            const tri = ch.mesh.indices.items[i..][0..3];
            if (ch.mesh.vertices.items[tri[0]].material == .hair) continue;
            // In-place compaction: source and destination overlap until the first removal.
            std.mem.copyForwards(u32, ch.mesh.indices.items[write..][0..3], tri);
            write += 3;
        }
        ch.mesh.indices.shrinkRetainingCapacity(write);
        try plate(a, ch, .head, V.init(0, lm.chin_y + 0.56 * lm.H, -0.02 * h), V.init(lm.head_half_width + 0.024 * h, 0.56 * lm.H, 0.14 * h), if (p.helmet == .sealed) metal else rgb(Profile.outfit_colors[p.outfit], 0.7));
    }
    if (p.helmet != .open) {
        const center = V.init(0, lm.chin_y + 0.47 * lm.H, 0.105 * h);
        try visorSurface(a, ch, center, 0.117 * h, 0.048 * h, 0.028 * h, dark, 8, 24);
        try visorSurface(a, ch, center.add(V.init(0, 0.020 * h, 0.006 * h)), 0.086 * h, 0.0045 * h, 0.030 * h, accent, 2, 20);
        for ([_]f32{ -1, 1 }) |side| {
            try plate(a, ch, .head, center.add(V.init(side * 0.112 * h, -0.004 * h, -0.004 * h)), V.init(0.012 * h, 0.055 * h, 0.018 * h), metal);
        }
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
    // Heavier armor adds plates for the same helmet; sealing the helmet replaces the hair.
    var heavy = try init(a, .{ .armor = .sentinel });
    defer heavy.deinit(a);
    try std.testing.expect(heavy.mesh.indices.len > ranger.mesh.indices.len);
    var sealed = try init(a, .{ .armor = .sentinel, .helmet = .sealed });
    defer sealed.deinit(a);
    for (sealed.character.mesh.indices.items) |i| try std.testing.expect(sealed.character.mesh.vertices.items[i].material != .hair);
}

test "armor suits are rigid, segmented plates that never stretch and grow with the suit" {
    const a = std.testing.allocator;
    var counts: [5]usize = undefined;
    var reach: [5]f32 = undefined;
    for (std.enums.values(Profile.Clothing), 0..) |clothing, k| {
        var r = try init(a, .{ .clothing = clothing, .armor = .none, .helmet = .open });
        defer r.deinit(a);
        var armor: usize = 0;
        var far: f32 = 0;
        const chest = r.character.skeleton.worldPos(.chest);
        for (r.character.mesh.vertices.items) |v| {
            if (v.material != .armor) continue;
            armor += 1;
            // Rigid: one joint at full weight.
            try std.testing.expectEqual(@as(f32, 1), v.weights[0]);
            try std.testing.expectEqual(@as(f32, 0), v.weights[1] + v.weights[2] + v.weights[3]);
            // How far the chest plate stands out in front, at chest height.
            if (@abs(v.pos.y - chest.y) < 0.04 and @abs(v.pos.x) < 0.05) far = @max(far, v.pos.z - chest.z);
        }
        counts[k] = armor;
        reach[k] = far;
        if (clothing == .hardsuit) {
            // Walking moves the plates without changing their shape: two vertices on the same
            // joint keep their distance exactly.
            var first: ?usize = null;
            var second: ?usize = null;
            for (r.character.mesh.vertices.items, 0..) |v, i| {
                if (v.material != .armor or v.joints[0] != sk.Joint.lower_arm_l.idx()) continue;
                if (first == null) first = i else if (second == null and r.mesh.vertices[i].position[1] != r.mesh.vertices[first.?].position[1]) second = i;
            }
            const p0 = r.mesh.vertices[first.?].position;
            const p1 = r.mesh.vertices[second.?].position;
            const before = V.init(p0[0] - p1[0], p0[1] - p1[1], p0[2] - p1[2]).length();
            r.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0, .walk_amount = 1, .walk_phase = 1.3 });
            const q0 = r.mesh.vertices[first.?].position;
            const q1 = r.mesh.vertices[second.?].position;
            try std.testing.expect(@abs(q0[1] - p0[1]) > 0.01); // the forearm moved
            try std.testing.expectApproxEqAbs(before, V.init(q0[0] - q1[0], q0[1] - q1[1], q0[2] - q1[2]).length(), 1e-4);
        }
    }
    // undersuit, field_jacket, exo_rig, hardsuit, vanguard
    try std.testing.expectEqual(@as(usize, 0), counts[0] + counts[1]);
    try std.testing.expect(counts[2] > 500 and counts[3] > counts[2]);
    try std.testing.expect(counts[4] >= counts[3] * 9 / 10);
    // The vanguard's heavier chest plate stands farther off the body than the hardsuit's; the
    // exo rig has none.
    try std.testing.expectEqual(@as(f32, 0), reach[2]);
    try std.testing.expect(reach[4] > reach[3]);
}

test "visor wraps around the face and field jacket adds modeled utility details" {
    const a = std.testing.allocator;
    var visor = try init(a, .{ .clothing = .field_jacket, .helmet = .visor, .armor = .none });
    defer visor.deinit(a);
    var open = try init(a, .{ .clothing = .field_jacket, .helmet = .open, .armor = .none });
    defer open.deinit(a);
    var undersuit = try init(a, .{ .clothing = .undersuit, .helmet = .open, .armor = .none });
    defer undersuit.deinit(a);

    const center_y = visor.character.landmarks.chin_y + 0.47 * visor.character.landmarks.H;
    var center_front = -std.math.inf(f32);
    var edge_front = -std.math.inf(f32);
    var visor_vertices: usize = 0;
    for (visor.character.mesh.vertices.items) |vertex| {
        if (vertex.material != .armor or @abs(vertex.pos.y - center_y) > 0.002) continue;
        visor_vertices += 1;
        try std.testing.expect(vertex.normal.z > 0.8);
        if (@abs(vertex.pos.x) < 0.015) center_front = @max(center_front, vertex.pos.z);
        if (@abs(vertex.pos.x) > 0.18) edge_front = @max(edge_front, vertex.pos.z);
    }
    try std.testing.expect(visor_vertices > 10);
    try std.testing.expect(center_front > edge_front + 0.01);
    try std.testing.expect(visor.character.mesh.vertices.items.len > open.character.mesh.vertices.items.len + 100);
    try std.testing.expect(visor.character.mesh.vertices.items.len > undersuit.character.mesh.vertices.items.len + 300);
}

test "rootweave and skyguard profiles generate distinct armor meshes and save values" {
    const a = std.testing.allocator;
    var scout = try init(a, .{ .armor = .scout, .helmet = .open, .clothing = .field_jacket });
    defer scout.deinit(a);
    var rootweave = try init(a, .{ .armor = .rootweave, .helmet = .open, .clothing = .field_jacket });
    defer rootweave.deinit(a);
    var skyguard = try init(a, .{ .armor = .skyguard, .helmet = .open, .clothing = .field_jacket });
    defer skyguard.deinit(a);

    try std.testing.expect(rootweave.mesh.vertices.len > scout.mesh.vertices.len);
    try std.testing.expect(skyguard.mesh.vertices.len > scout.mesh.vertices.len);
    try std.testing.expect(!Ranger.sameAppearance(rootweave.profile, skyguard.profile));
    try std.testing.expectEqualDeep(rootweave.profile, try Profile.fromDoc(rootweave.profile.toDoc()));
    try std.testing.expectEqualDeep(skyguard.profile, try Profile.fromDoc(skyguard.profile.toDoc()));
}
