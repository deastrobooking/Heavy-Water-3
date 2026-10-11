//! Game-facing smooth ranger: skinned anatomy, fabric layers, rigid armor and a procedural gait.
//! The supplied character generator owns geometry; this adapter owns game appearance and pose.
const std = @import("std");
const Profile = @import("../game/Profile.zig");
const Player = @import("../game/Player.zig");
const gen = @import("character.zig");
const spec = @import("spec.zig");
const sk = @import("skeleton.zig");
const Animation = @import("Animation.zig");
const cm = @import("mesh.zig");
const m = @import("math.zig");
const toon = @import("toon.zig");
const Beasts = @import("Beasts.zig");
const Mesh = @import("../render/Mesh.zig");
const V = m.Vec3;
const Q = m.Quat;
const Ranger = @This();
/// Skinned characters drawn at once: players 0–3, keepers 4–6, pedestrians 7–14, Hive troopers
/// 16–23, Wildkin heroes met in the world 24–31.
pub const capacity = 32;
/// What the upper body is doing on top of the gait: weapon use, throwing, a trooper's strike, or
/// a low cover posture. `action_t` advances timed actions from 0 to 1.
pub const Action = enum { none, aim, swing, guard, cast, throw, strike, kick, cover };
/// Saber arcs: forehand, backhand, overhead finisher, dash cut, aerial, charged wave.
pub const Arc = enum(u8) { forehand, backhand, overhead, dash, aerial, charged };
pub const Pose = struct {
    feet: [3]f32,
    yaw: f32,
    walk_phase: f32 = 0,
    walk_amount: f32 = 0,
    motion: Player.Motion = .idle,
    time: f32 = 0,
    action: Action = .none,
    action_t: f32 = 0,
    arc: Arc = .forehand,
    aim_pitch: f32 = 0,
};
pub const Draw = struct { profile: Profile, pose: Pose, id: u8 = 0 };
character: gen.Character,
instance: gen.Instance,
mesh: Mesh,
profile: Profile,
controller: Animation.Controller = .{},
last_pose: ?Pose = null,
last_blend: ?Animation.Blend = null,

fn rgb(c: [4]f32, factor: f32) spec.Rgb {
    return .{ .r = c[0] * factor, .g = c[1] * factor, .b = c[2] * factor };
}
pub fn init(a: std.mem.Allocator, profile: Profile) !Ranger {
    var garments: [16]spec.GarmentSpec = undefined;
    const outfit_len = outfit(profile, &garments);
    const feminine = profile.presentation == .feminine;
    // Synthetics: a cool porcelain sheen over the chosen tone, and eyes lit in the accent.
    const synthetic = profile.class == .synthetic and profile.species == .human;
    const wildkin = profile.species != .human;
    const lumen = Profile.accent_colors[profile.accent];
    const preset = facePreset(profile.face_style);
    var eyes = Beasts.eyes(profile.species, .{
        .size = (if (feminine) @as(f32, 0.22) else 0.20) * preset.eye_size_scale,
        .aspect = (if (feminine) @as(f32, 0.92) else 0.84) * preset.eye_aspect_scale,
        .spacing = if (feminine) 0.20 else 0.19,
        .height = (if (feminine) @as(f32, 0.46) else 0.455) + preset.eye_height_add,
        .tilt = preset.eye_tilt,
        .iris_color = if (synthetic) rgb(lumen, 1.35) else if (feminine) spec.Rgb.hex(0x4f91b4) else spec.Rgb.hex(0x667b82),
        .iris_dark = if (synthetic) rgb(lumen, 0.75) else spec.Rgb.hex(0x213946),
        .pupil_size = if (synthetic) 0.18 else if (feminine) 0.35 else 0.31,
        .highlight_count = if (profile.face_style == .heroic or profile.face_style == .hero or profile.face_style == .alien) 2 else 1,
        .brow_weight = preset.brow_weight,
        .brow_tilt = preset.brow_tilt,
        .brow_gap = preset.brow_gap,
        .nose_mark = preset.nose_mark,
        .mouth_width = preset.mouth_width,
    }, rgb(lumen, 1.2));
    if (profile.face_style == .alien) {
        eyes.pupil_size = 0.18;
        eyes.iris_color = rgb(lumen, 1.4);
        eyes.iris_dark = rgb(lumen, 0.66);
    }
    const hair_style: spec.HairStyle = switch (profile.hair_style) {
        .short => .short_spiky,
        .ponytail => .ponytail,
        .long => .long_straight,
        .crest => .mohawk,
        .hood, .bob => .bob,
        .twin_tails => .twin_tails,
        .bun => .bun,
        .braids => .braids,
        .curly => .curly,
        .undercut => .undercut,
        .short_curly => .short_curly,
        .curly_fade => .curly_fade,
        .curly_coils => .curly_coils,
        .afro => .afro,
        .long_curls => .long_curls,
        .textured_crop => .textured_crop,
        .locs => .locs,
        .swept_back => .swept_back,
        .layered_shag => .layered_shag,
        .nova_spike => .nova_spike,
        .alien_crown => .alien_crown,
        .crew_cut => .crew_cut,
        .side_part => .side_part,
    };
    var ch = try gen.Character.build(a, .{
        .body = bodySpec(profile),
        // Wildkin wear their coat where a human shows skin.
        .skin = if (wildkin) rgb(Profile.coat_colors[profile.coat], 1) else if (synthetic) mix(Profile.skin_tones[profile.skin], spec.Rgb.hex(0xe4eaef), 0.6) else rgb(Profile.skin_tones[profile.skin], 1),
        .eyes = eyes,
        .hair = .{ .style = hair_style, .color = rgb(Profile.hair_colors[profile.hair_color], 1), .ahoge = false, .chain_joints = 0, .length = 1.4, .volume = if (hair_style == .afro or hair_style == .alien_crown) 1.25 else 0.8, .spikiness = if (hair_style == .nova_spike or hair_style == .alien_crown) 0.95 else 0.35, .bang_count = if (hair_style == .nova_spike) 9 else 5 },
        .outfit = garments[0..outfit_len],
        .detail = 0.7,
    });
    errdefer ch.deinit(a);
    // The generator consumes outfit specifications synchronously; never retain a stack slice.
    ch.spec.outfit = &.{};
    try equip(a, &ch, profile);
    softenFace(&ch);
    var inst = try gen.Instance.init(a, &ch);
    errdefer inst.deinit(a);
    const vertices = try a.alloc(Mesh.Vertex, ch.mesh.vertices.items.len);
    errdefer a.free(vertices);
    const indices = try a.dupe(u32, ch.mesh.indices.items);
    var self: Ranger = .{ .character = ch, .instance = inst, .mesh = .{ .vertices = vertices, .indices = indices }, .profile = profile };
    for (self.mesh.vertices, self.character.mesh.vertices.items, self.character.color_index.items) |*v, source, color| {
        var c = self.character.palette.items[color];
        if (source.region == .face and source.uv.x >= 0 and source.uv.y >= 0) {
            const decal = toon.faceDecal(source.uv, self.character.spec.eyes, .{ .smile = if (wildkin) 0.55 else if (feminine) 0.38 else 0.12 }, 0.008);
            if (decal.alpha > 0) c = toon.mix(c, decal.color, decal.alpha);
        } else if (source.material == .hair) {
            const secondary_hair: ?spec.Rgb = if (profile.hair_highlight > 0)
                rgb(Profile.hair_colors[profile.hair_highlight - 1], 1)
            else if (synthetic)
                rgb(lumen, 1.25)
            else
                null;
            if (secondary_hair) |highlight| {
                const bands = @cos(source.uv.x * m.tau * 3 + @sin(source.uv.y * m.tau) * 0.35);
                const mask = smoothstep(0.70, 0.98, bands) * m.saturate(0.45 + 0.55 * @abs(source.normal.z));
                c = toon.mix(c, highlight, mask * 0.92);
            }
            // Bake the broad, broken hair glint into the vertex color so it survives the
            // GPU-skinned game path, which intentionally carries no character UV texture.
            const facing = m.saturate(0.35 + 0.65 * @abs(source.normal.z));
            const ring = toon.angelRing(source.uv, facing, 0.34, 0.075);
            const comb = m.smoothstep(0.78, 0.96, @cos(source.uv.x * m.tau * 5 + source.uv.y * 0.35)) * facing;
            const glint = toon.addc(c, spec.Rgb.init(0.22, 0.18, 0.15));
            c = toon.mix(c, glint, @max(ring * 0.72, comb * 0.62));
        }
        // Face UVs drive the CPU decal bake above; game characters use a neutral renderer UV so
        // the world checker texture is not sampled across skin and facial colors.
        v.* = .{ .position = .{ source.pos.x, source.pos.y, source.pos.z }, .normal = .{ source.normal.x, source.normal.y, source.normal.z }, .uv = .{ 0, 0 }, .color = .{ c.r, c.g, c.b } };
    }
    _ = self.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0 });
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
/// GPU skinning: a character's bind-pose vertex (model space) with its four joint influences.
/// The renderer uploads these once per appearance; each frame only the joint palette changes.
pub const SkinnedVertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    color: [3]f32,
    joints: [4]u8,
    weights: [4]f32,
    /// Cel shading: material index into the `CelStyle` table, 1 on face vertices that carry a
    /// face UV (the face shadow map reads it), two spare bytes.
    kind: [4]u8,
    /// Face UV (u across the face, v chin to crown); -1 where the vertex has none.
    face_uv: [2]f32,
};
/// Joints per character in the GPU palette (two vec4s, a dual quaternion, per joint).
pub const max_palette_joints = 64;
/// One character's palette in the uniform buffer, padded to the 256-byte dynamic-offset rule.
pub const palette_bytes = max_palette_joints * 32;
pub const Palette = [max_palette_joints * 2][4]f32;

/// Whether this character fits the GPU palette (otherwise it is skinned on the CPU).
pub fn gpuSkinnable(self: *const Ranger) bool {
    return self.character.skeleton.count() <= max_palette_joints;
}

/// The bind-pose mesh for GPU skinning: positions, normals and influences from the generator,
/// colours as baked for the CPU mesh (face decals included). The caller owns the slice.
pub fn skinnedVertices(self: *const Ranger, a: std.mem.Allocator) ![]SkinnedVertex {
    const out = try a.alloc(SkinnedVertex, self.mesh.vertices.len);
    for (out, self.character.mesh.vertices.items, self.mesh.vertices) |*o, source, baked| {
        var joints: [4]u8 = undefined;
        for (&joints, source.joints) |*j, s| j.* = @intCast(s);
        o.* = .{ .position = .{ source.pos.x, source.pos.y, source.pos.z }, .normal = .{ source.normal.x, source.normal.y, source.normal.z }, .color = baked.color, .joints = joints, .weights = source.weights, .kind = .{ @intFromEnum(source.material), @intFromBool(source.region == .face and source.uv.x >= 0 and source.uv.y >= 0), 0, 0 }, .face_uv = .{ source.uv.x, source.uv.y } };
    }
    return out;
}

/// Poses the skeleton for `state` and writes the joint dual quaternions into `palette` (real
/// part, then dual part, per joint), without touching the mesh. False when the pose is unchanged
/// since the last call (the palette already holds it).
pub fn posePalette(self: *Ranger, state: Pose, palette: *Palette) bool {
    if (!self.solvePose(state)) return false;
    self.instance.pose.skinDualQuats(&self.character.skeleton, self.instance.dqs);
    for (self.instance.dqs, 0..) |dq, j| {
        palette[j * 2] = .{ dq.real.x, dq.real.y, dq.real.z, dq.real.w };
        palette[j * 2 + 1] = .{ dq.dual.x, dq.dual.y, dq.dual.z, dq.dual.w };
    }
    return true;
}

/// The pose for `state` (clip blend, then actions), unless it is the one already solved.
fn solvePose(self: *Ranger, state: Pose) bool {
    const p = &self.instance.pose;
    const blend = self.controller.update(clipFor(state.motion, state.walk_amount), state.time);
    var key = state;
    const timed_pose = state.motion == .climb or state.motion == .hang or state.motion == .mantle or state.motion == .wall_slide;
    if (state.motion == .idle and state.action == .none) {
        // Keep the subtle idle breath while avoiding a re-skin on every 60 Hz frame.
        key.time = @floor(state.time * 12) / 12;
    } else if (!timed_pose) {
        key.time = 0;
    }
    if (self.last_pose) |previous| if (self.last_blend) |old_blend| {
        if (std.meta.eql(previous, key) and std.meta.eql(old_blend, blend)) return false;
    };
    poseSkeletonBlended(p, &self.character.skeleton, key, blend);
    self.last_pose = key;
    self.last_blend = blend;
    return true;
}

/// CPU skinning: poses and skins the whole mesh into `mesh` (the fallback, and what tests use).
pub fn update(self: *Ranger, state: Pose) bool {
    if (!self.solvePose(state)) return false;
    self.instance.skin(&self.character);
    for (self.mesh.vertices, self.instance.pos, self.instance.nrm) |*v, pos, normal| {
        v.position = .{ pos.x, pos.y, pos.z };
        v.normal = .{ normal.x, normal.y, normal.z };
    }
    return true;
}

/// Turns `joint` so the bone toward `child` points along `dir` (model frame).
fn pointBone(p: *sk.Pose, skel: *const sk.Skeleton, joint: sk.Joint, child: sk.Joint, dir: V) void {
    p.updateGlobal(skel);
    const from = p.global[joint.idx()].translation;
    const to = p.global[child.idx()].translation;
    const current = to.sub(from).normalizeOr(V.unit_z);
    const q = Q.fromTo(current, dir.normalizeOr(V.unit_z));
    p.setGlobalRotation(skel, joint.idx(), q.mul(p.global[joint.idx()].rotation));
}

/// Direction from azimuth `a` (0 ahead, + toward the character's left) and elevation `e`.
fn heading(a: f32, e: f32) V {
    return V.init(@sin(a) * @cos(e), @sin(e), @cos(a) * @cos(e));
}

/// Pitches a model-frame direction up by `pitch` (rotation about the left axis).
fn pitched(d: V, pitch: f32) V {
    return Q.fromAxisAngle(V.unit_x, -pitch).rotate(d);
}

/// Saber arm direction at progress `t` through `arc`.
pub fn swingDirection(arc: Arc, t: f32) V {
    const k = std.math.clamp(t, 0, 1);
    // Ease through the cut: fast in the middle.
    const e = k * k * (3 - 2 * k);
    const r = m.radians;
    return switch (arc) {
        .forehand => heading(m.lerp(r(-110), r(70), e), m.lerp(r(22), r(-12), e)),
        .backhand => heading(m.lerp(r(70), r(-100), e), m.lerp(r(-6), r(16), e)),
        .overhead => heading(m.lerp(r(-8), r(4), e), m.lerp(r(105), r(-45), e)),
        .dash => heading(m.lerp(r(-70), r(65), e), r(-4)),
        .aerial => heading(m.lerp(r(-150), r(150), e), r(-28)),
        .charged => heading(m.lerp(r(-150), r(130), e), m.lerp(r(10), r(-5), e)),
    };
}

/// The full procedural pose: the gait, then any combat action on the arms. Shared by the
/// renderer's skinned characters and the simulation's rigs, so blades hit where they are drawn.
pub fn poseSkeleton(p: *sk.Pose, skel: *const sk.Skeleton, state: Pose) void {
    const clip = clipFor(state.motion, state.walk_amount);
    poseSkeletonBlended(p, skel, state, .{ .from = clip, .to = clip, .alpha = 1 });
}

fn clipFor(motion: Player.Motion, amount: f32) Animation.ClipId {
    return switch (motion) {
        .idle => if (amount >= 0.08) .walk else .idle,
        .run => if (amount < 0.08) .idle else if (amount >= 0.78) .run else .walk,
        .sprint => if (amount < 0.08) .idle else .run,
        .climb, .hang, .mantle => .climb,
        .jump, .long_jump, .fall, .roll, .stomp, .wall_slide, .jet, .hover, .glide, .dash, .board, .grapple_zip, .grapple_swing, .swim => .air,
        .skate => if (amount < 0.08) .idle else .run,
    };
}

fn phaseFor(id: Animation.ClipId, state: Pose) f32 {
    return if (id == .climb) state.time * 3 else state.walk_phase;
}

fn applyBlend(p: *sk.Pose, blend: Animation.Blend, state: Pose) void {
    if (blend.from == blend.to) {
        const id = blend.to;
        Animation.apply(Animation.get(id), p, phaseFor(id, state), 1);
        return;
    }
    const alpha = std.math.clamp(blend.alpha, 0, 1);
    Animation.apply(Animation.get(blend.from), p, phaseFor(blend.from, state), 1 - alpha);
    Animation.apply(Animation.get(blend.to), p, phaseFor(blend.to, state), alpha);
}

fn poseSkeletonBlended(p: *sk.Pose, skel: *const sk.Skeleton, state: Pose, blend: Animation.Blend) void {
    p.reset(skel);
    const amount = std.math.clamp(state.walk_amount, 0, 1);
    const airborne = switch (state.motion) {
        .jump, .long_jump, .fall, .jet, .hover, .glide, .grapple_zip, .grapple_swing => true,
        else => false,
    };
    const climbing = state.motion == .climb or state.motion == .hang or state.motion == .wall_slide or state.motion == .mantle;
    applyBlend(p, blend, state);
    inline for ([_]sk.Joint{ .upper_arm_l, .upper_arm_r }, [_]sk.Joint{ .lower_arm_l, .lower_arm_r }, [_]sk.Joint{ .thigh_l, .thigh_r }, [_]sk.Joint{ .shin_l, .shin_r }, .{ @as(f32, 1), @as(f32, -1) }) |arm, elbow, thigh, knee, side| {
        // Bring the generated A-pose down to relaxed arms beside the torso.
        p.rotateLocal(arm.idx(), Q.fromAxisAngle(V.unit_z, -side * (if (climbing) @as(f32, -1.1) else if (airborne) @as(f32, 0.35) else @as(f32, 0.76))));
        p.rotateLocal(elbow.idx(), Q.fromAxisAngle(V.unit_x, -0.15 - 0.3 * amount));
        if (airborne) {
            p.rotateLocal(thigh.idx(), Q.fromAxisAngle(V.unit_x, -0.25));
            p.rotateLocal(knee.idx(), Q.fromAxisAngle(V.unit_x, 0.5));
        }
    }
    p.local[sk.Joint.hips.idx()].translation.y += @sin(state.time * 2) * 0.003 * (1 - amount);
    if (state.motion == .roll or state.motion == .dash or state.motion == .board or state.motion == .skate) p.rotateLocal(sk.Joint.spine.idx(), Q.fromAxisAngle(V.unit_x, 0.35));
    const t = std.math.clamp(state.action_t, 0, 1);
    switch (state.action) {
        .none => {},
        .aim => {
            pointBone(p, skel, .upper_arm_r, .lower_arm_r, pitched(V.init(-0.12, -0.3, 0.95), state.aim_pitch));
            pointBone(p, skel, .lower_arm_r, .hand_r, pitched(V.init(0.12, 0.04, 1), state.aim_pitch));
            pointBone(p, skel, .upper_arm_l, .lower_arm_l, pitched(V.init(0.32, -0.38, 0.87), state.aim_pitch));
            pointBone(p, skel, .lower_arm_l, .hand_l, pitched(V.init(-0.5, 0.06, 0.86), state.aim_pitch));
        },
        .swing => {
            const d = swingDirection(state.arc, t);
            // The torso turns into the cut.
            p.rotateLocal(sk.Joint.chest.idx(), Q.fromAxisAngle(V.unit_y, std.math.atan2(d.x, @max(d.z, 0.1)) * 0.35));
            pointBone(p, skel, .upper_arm_r, .lower_arm_r, d.add(V.init(-0.25, -0.1, 0)));
            pointBone(p, skel, .lower_arm_r, .hand_r, d);
        },
        .guard => {
            pointBone(p, skel, .upper_arm_r, .lower_arm_r, V.init(-0.25, 0.05, 0.95));
            pointBone(p, skel, .lower_arm_r, .hand_r, V.init(0.6, 0.55, 0.58));
        },
        .cast => {
            for ([_]sk.Joint{ .upper_arm_r, .upper_arm_l }, [_]sk.Joint{ .lower_arm_r, .lower_arm_l }, [_]sk.Joint{ .hand_r, .hand_l }, [_]f32{ -1, 1 }) |arm, fore, hand, side| {
                pointBone(p, skel, arm, fore, pitched(V.init(side * 0.12, 0.02, 1), state.aim_pitch));
                pointBone(p, skel, fore, hand, pitched(V.init(-side * 0.06, 0.04, 1), state.aim_pitch));
            }
        },
        .throw => {
            const d = heading(m.lerp(m.radians(-160), m.radians(-15), t), m.lerp(m.radians(65), m.radians(8), t));
            pointBone(p, skel, .upper_arm_r, .lower_arm_r, d);
            pointBone(p, skel, .lower_arm_r, .hand_r, d);
        },
        .strike => {
            // A compact wind-up, committed straight punch, then a short recovery. Curves are
            // authored in normalized clip time and drive the shoulder, elbow, torso and hips.
            const wind = 1 - smoothstep(0.05, 0.4, t);
            const drive = smoothstep(0.18, 0.48, t) * (1 - smoothstep(0.62, 1, t));
            p.rotateLocal(sk.Joint.chest.idx(), Q.fromAxisAngle(V.unit_y, -0.45 * wind + 0.18 * drive));
            p.local[sk.Joint.hips.idx()].translation.z += 0.12 * drive;
            pointBone(p, skel, .upper_arm_r, .lower_arm_r, V.init(-0.32 + 0.36 * drive, -0.18 + 0.07 * wind, 0.76 + 0.35 * drive));
            pointBone(p, skel, .lower_arm_r, .hand_r, V.init(-0.15 + 0.10 * drive, -0.04, 0.95));
            // The off hand guards the chest through the entire attack.
            pointBone(p, skel, .upper_arm_l, .lower_arm_l, V.init(0.35, -0.18, 0.76));
            pointBone(p, skel, .lower_arm_l, .hand_l, V.init(0.12, 0.12, 0.86));
        },
        .kick => {
            // A chambered guard hand balances the hip turn as the right boot snaps forward.
            p.rotateLocal(sk.Joint.chest.idx(), Q.fromAxisAngle(V.unit_y, -0.32 * (1 - t)));
            p.rotateLocal(sk.Joint.thigh_r.idx(), Q.fromAxisAngle(V.unit_x, -0.25 - 1.05 * smoothstep(0.12, 0.48, t)));
            p.rotateLocal(sk.Joint.shin_r.idx(), Q.fromAxisAngle(V.unit_x, 0.18 + 0.72 * smoothstep(0.2, 0.55, t)));
            p.rotateLocal(sk.Joint.thigh_l.idx(), Q.fromAxisAngle(V.unit_x, 0.18));
            pointBone(p, skel, .upper_arm_l, .lower_arm_l, V.init(0.3, 0.25, 0.75));
            pointBone(p, skel, .lower_arm_l, .hand_l, V.init(-0.1, 0.08, 0.9));
        },
        .cover => {
            // Low profile behind waist-high cover, with the helmet tucked and arms protecting
            // the core. The locomotion gait remains active while moving into the position.
            p.local[sk.Joint.hips.idx()].translation.y -= 0.18;
            p.rotateLocal(sk.Joint.spine.idx(), Q.fromAxisAngle(V.unit_x, 0.12));
            p.rotateLocal(sk.Joint.head.idx(), Q.fromAxisAngle(V.unit_x, -0.12));
            for ([_]sk.Joint{ .thigh_l, .thigh_r }, [_]sk.Joint{ .shin_l, .shin_r }, [_]f32{ -1, 1 }) |thigh, shin, side| {
                p.rotateLocal(thigh.idx(), Q.fromAxisAngle(V.unit_x, 0.24));
                p.rotateLocal(shin.idx(), Q.fromAxisAngle(V.unit_x, 0.55));
                const arm: sk.Joint = if (side > 0) .upper_arm_l else .upper_arm_r;
                const fore: sk.Joint = if (side > 0) .lower_arm_l else .lower_arm_r;
                const hand: sk.Joint = if (side > 0) .hand_l else .hand_r;
                pointBone(p, skel, arm, fore, V.init(side * 0.18, 0.4, 0.8));
                pointBone(p, skel, fore, hand, V.init(-side * 0.1, -0.05, 0.9));
            }
        },
    }
    p.updateGlobal(skel);
}

fn smoothstep(edge0: f32, edge1: f32, value: f32) f32 {
    const x = std.math.clamp((value - edge0) / (edge1 - edge0), 0, 1);
    return x * x * (3 - 2 * x);
}

/// The comptime face table row for a profile's face style (`spec.face_presets`, same order).
pub fn facePreset(style: Profile.FaceStyle) spec.FacePreset {
    return spec.face_presets[@intFromEnum(style)];
}

/// The body part of a profile's character spec (everything the skeleton depends on).
pub fn bodySpec(profile: Profile) spec.BodySpec {
    const feminine = profile.presentation == .feminine;
    // Wildkin forms scale height and build, and carry cartoon-heroic heads.
    const form = Beasts.scale(profile.species);
    const build = profile.build * form.build;
    const wildkin = profile.species != .human;
    const preset = facePreset(profile.face_style);
    const head: spec.HeadSpec = if (wildkin) .{ .cranium_width = 0.9, .jaw_taper = 0.2, .neck_length = 0.36, .neck_thickness = 1.0 } else if (feminine) preset.feminine else preset.masculine;
    return .{ .height = 1.8 * profile.height * form.height, .head_ratio = if (wildkin) Beasts.headRatio(profile.species) else preset.head_ratio, .femininity = if (feminine) 0.84 else 0.18, .bust = if (wildkin) 0.02 else if (feminine) 0.10 else 0.02, .shoulder_width = (if (feminine) @as(f32, 0.98) else 1.10) * build, .waist_width = (if (feminine) @as(f32, 0.94) else 1.12) * build, .hip_width = (if (feminine) @as(f32, 1.06) else 0.96) * build, .limb_thickness = (if (feminine) @as(f32, 0.98) else 1.08) * build, .head = head, .hand_scale = if (wildkin) 1.0 else 1.15, .foot_scale = if (wildkin) 1.0 else 1.1 };
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
    if (profile.species != .human) {
        // Wildkin wear bright hero suits that leave their fur, scales or feathers showing: a
        // tank top and shorts in the outfit colour, gloves and boots in the marking colour.
        const mark = Profile.coat_colors[profile.marking];
        Add.one(out, &n, .{ .coverage = .tank, .color = rgb(cloth, 1.15), .neckline = .crew });
        Add.one(out, &n, .{ .coverage = .shorts, .color = rgb(cloth, 0.75) });
        Add.one(out, &n, .{ .coverage = .gloves, .color = rgb(mark, 0.9), .layer = 2, .looseness = 0.003 });
        Add.one(out, &n, .{ .coverage = .shoes, .color = rgb(mark, 0.75), .layer = 3, .looseness = 0.009 });
    } else {
        Add.one(out, &n, .{ .coverage = .long_sleeve, .color = rgb(cloth, 0.35), .neckline = .high });
        Add.one(out, &n, .{ .coverage = .leggings, .color = rgb(cloth, 0.32) });
    }
    switch (profile.clothing) {
        .undersuit, .field_jacket => if (profile.species == .human) {
            Add.one(out, &n, .{ .coverage = .gloves, .color = dark, .layer = 2, .looseness = 0.003 });
            Add.one(out, &n, .{ .coverage = .shoes, .color = spec.Rgb.hex(0x202c36), .layer = 3, .looseness = 0.009 });
            if (profile.clothing == .field_jacket) Add.one(out, &n, .{ .coverage = .long_sleeve, .color = rgb(cloth, 1), .layer = 3, .looseness = 0.013, .neckline = .v });
        },
        .exo_rig, .hardsuit, .vanguard => {
            const extent: f32 = switch (profile.clothing) {
                .exo_rig => 0.72,
                .hardsuit => 1.0,
                .vanguard => 1.2,
                else => unreachable,
            };
            const bulge: f32 = switch (profile.clothing) {
                .exo_rig => 0.0025,
                .hardsuit => 0.004,
                .vanguard => 0.006,
                else => unreachable,
            };
            const lift: f32 = switch (profile.clothing) {
                .exo_rig => 0.001,
                .hardsuit => 0.002,
                .vanguard => 0.004,
                else => unreachable,
            };
            const tones = suitTones(profile);
            const steel = tones.plate;
            const trim = tones.trim;
            Add.one(out, &n, .{ .coverage = .gauntlets, .color = trim, .layer = 2, .looseness = 0.002, .hard = true, .bulge = 0.002 });
            Add.one(out, &n, .{ .coverage = .sabatons, .color = trim, .layer = 3, .looseness = 0.004, .hard = true, .bulge = 0.003 });
            Add.one(out, &n, .{ .coverage = .vambraces, .color = steel, .layer = 3, .looseness = 0.002 + lift, .hard = true, .bulge = bulge, .segments = 2, .coverage_extent = extent });
            Add.one(out, &n, .{ .coverage = .greaves, .color = steel, .layer = 4, .looseness = 0.002 + lift, .hard = true, .bulge = bulge, .segments = 2, .coverage_extent = extent });
            Add.one(out, &n, .{ .coverage = .pauldrons, .color = steel, .layer = 4, .looseness = 0.003 + lift, .hard = true, .bulge = bulge, .segments = if (profile.clothing == .exo_rig) 1 else 2, .coverage_extent = extent });
            if (profile.clothing != .exo_rig) {
                Add.one(out, &n, .{ .coverage = .cuirass, .color = steel, .layer = 4, .looseness = 0.003 + lift, .hard = true, .bulge = bulge, .segments = if (profile.clothing == .vanguard) 3 else 2, .neckline = .high });
                Add.one(out, &n, .{ .coverage = .faulds, .color = trim, .layer = 3, .looseness = 0.004 + lift, .hard = true, .bulge = bulge * 0.7, .segments = 2, .coverage_extent = extent });
                Add.one(out, &n, .{ .coverage = .cuisses, .color = steel, .layer = 3, .looseness = 0.002 + lift, .hard = true, .bulge = bulge, .segments = 2, .coverage_extent = extent });
            }
        },
    }
    return n;
}

/// A suit's two-tone scheme: each suit has its own identity, and the outfit colour always shows.
/// The exo rig is a light frame in the outfit colour over graphite; the hardsuit is ivory plate
/// with outfit-coloured secondary panels; the vanguard is gunmetal with outfit-coloured trim.
/// `glow` is the lumen of light strips and cores (over-bright, so it reads as lit).
pub const SuitTones = struct { plate: spec.Rgb, trim: spec.Rgb, glow: spec.Rgb };

pub fn suitTones(profile: Profile) SuitTones {
    const cloth = Profile.outfit_colors[profile.outfit];
    const glow = rgb(Profile.accent_colors[profile.accent], 1.55);
    return switch (profile.clothing) {
        .exo_rig => .{ .plate = mix(cloth, spec.Rgb.hex(0x9aa7ad), 0.35), .trim = spec.Rgb.hex(0x1c252b), .glow = glow },
        .hardsuit => .{ .plate = mix(cloth, spec.Rgb.hex(0xe9e5da), 0.78), .trim = mix(cloth, spec.Rgb.hex(0x2a343b), 0.3), .glow = glow },
        .vanguard => .{ .plate = mix(cloth, spec.Rgb.hex(0x3a464e), 0.72), .trim = mix(cloth, spec.Rgb.hex(0x0e1418), 0.45), .glow = glow },
        else => .{ .plate = rgb(cloth, 1), .trim = spec.Rgb.hex(0x18242c), .glow = glow },
    };
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

/// Low-profile chamfered fabric panel. The shallow convex front and closed edge make a pouch or
/// ID tab read as fitted kit instead of another round armor pod.
fn rotateXY(v: V, c: f32, s: f32) V {
    return V.init(c * v.x - s * v.y, s * v.x + c * v.y, v.z);
}

/// Front-most material surface at a model-space point. Fitted panels sample their built shell,
/// so jacket pouches and armor service plates follow the torso rather than floating over it.
fn surfaceZ(ch: *const gen.Character, x: f32, y: f32, material: cm.Material) ?f32 {
    const vertices = ch.mesh.vertices.items;
    const indices = ch.mesh.indices.items;
    var best = -std.math.inf(f32);
    var tri: usize = 0;
    while (tri + 2 < indices.len) : (tri += 3) {
        const a = vertices[indices[tri]];
        const b = vertices[indices[tri + 1]];
        const c = vertices[indices[tri + 2]];
        if (a.material != material or b.material != material or c.material != material) continue;
        if (a.normal.z < 0.25 or b.normal.z < 0.25 or c.normal.z < 0.25) continue;
        const denom = (b.pos.y - c.pos.y) * (a.pos.x - c.pos.x) + (c.pos.x - b.pos.x) * (a.pos.y - c.pos.y);
        if (@abs(denom) < 1e-8) continue;
        const wa = ((b.pos.y - c.pos.y) * (x - c.pos.x) + (c.pos.x - b.pos.x) * (y - c.pos.y)) / denom;
        const wb = ((c.pos.y - a.pos.y) * (x - c.pos.x) + (a.pos.x - c.pos.x) * (y - c.pos.y)) / denom;
        const wc = 1 - wa - wb;
        if (wa < -1e-4 or wb < -1e-4 or wc < -1e-4) continue;
        const z = wa * a.pos.z + wb * b.pos.z + wc * c.pos.z;
        best = @max(best, z);
    }
    return if (std.math.isFinite(best)) best else null;
}

fn fieldPanel(a: std.mem.Allocator, ch: *gen.Character, center: V, half_width: f32, half_height: f32, depth: f32, rotation: f32, color: spec.Rgb) !void {
    try fittedPanel(a, ch, center, half_width, half_height, depth, rotation, color, .cloth_top, .cloth_outer);
}

fn fittedPanel(a: std.mem.Allocator, ch: *gen.Character, center: V, half_width: f32, half_height: f32, depth: f32, rotation: f32, color: spec.Rgb, surface_material: cm.Material, panel_material: cm.Material) !void {
    const base = ch.mesh.vertexCount();
    const palette: u8 = @intCast(ch.palette.items.len);
    try ch.palette.append(a, color);
    const c = @cos(rotation);
    const s = @sin(rotation);
    const corner = @min(half_width, half_height) * 0.24;
    const outline = [_]V{
        V.init(-half_width + corner, -half_height, 0),
        V.init(half_width - corner, -half_height, 0),
        V.init(half_width, -half_height + corner, 0),
        V.init(half_width, half_height - corner, 0),
        V.init(half_width - corner, half_height, 0),
        V.init(-half_width + corner, half_height, 0),
        V.init(-half_width, half_height - corner, 0),
        V.init(-half_width, -half_height + corner, 0),
    };
    const add = struct {
        fn vertex(allocator: std.mem.Allocator, character: *gen.Character, pos: V, normal: V, color_index: u8, material: cm.Material) !void {
            _ = try character.mesh.addVertex(allocator, .{
                .pos = pos,
                .normal = normal,
                .joints = .{ sk.Joint.chest.idx(), 0, 0, 0 },
                .region = .garment,
                .material = material,
            });
            try character.color_index.append(allocator, color_index);
        }
    }.vertex;
    const lift = center.z;
    const center_surface = surfaceZ(ch, center.x, center.y, surface_material) orelse center.z;
    var surface: [8]f32 = undefined;
    for (outline, 0..) |p, i| {
        const offset = rotateXY(p, c, s);
        surface[i] = surfaceZ(ch, center.x + offset.x, center.y + offset.y, surface_material) orelse center_surface;
    }

    try add(a, ch, V.init(center.x, center.y, center_surface + lift + 0.004 * ch.landmarks.B), V.unit_z, palette, panel_material);
    for (outline, 0..) |p, i| {
        const offset = rotateXY(p, c, s);
        try add(a, ch, V.init(center.x + offset.x, center.y + offset.y, surface[i] + lift), V.unit_z, palette, panel_material);
    }
    for (outline, 0..) |p, i| {
        const offset = rotateXY(p, c, s);
        const n = rotateXY(V.init(p.x / half_width, p.y / half_height, 0), c, s).normalize();
        try add(a, ch, V.init(center.x + offset.x, center.y + offset.y, surface[i] + lift), n, palette, panel_material);
    }
    for (outline, 0..) |p, i| {
        const offset = rotateXY(p, c, s);
        const n = rotateXY(V.init(p.x / half_width, p.y / half_height, 0), c, s).normalize();
        try add(a, ch, V.init(center.x + offset.x, center.y + offset.y, surface[i] + lift - depth), n, palette, panel_material);
    }
    for (outline, 0..) |p, i| {
        const offset = rotateXY(p, c, s);
        try add(a, ch, V.init(center.x + offset.x, center.y + offset.y, surface[i] + lift - depth), V.unit_z.neg(), palette, panel_material);
    }
    try add(a, ch, V.init(center.x, center.y, center_surface + lift - depth), V.unit_z.neg(), palette, panel_material);

    const back_ring = base + 25;
    const back_center = base + 33;
    for (0..outline.len) |i| {
        const next: u32 = @intCast((i + 1) % outline.len);
        const front = base + 1 + @as(u32, @intCast(i));
        try ch.mesh.addTri(a, base, front, base + 1 + next);
        try ch.mesh.addQuad(a, base + 9 + @as(u32, @intCast(i)), base + 17 + @as(u32, @intCast(i)), base + 17 + next, base + 9 + next);
        try ch.mesh.addTri(a, back_center, back_ring + next, back_ring + @as(u32, @intCast(i)));
    }
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

fn gemstoneColor(stone: Profile.Gemstone) spec.Rgb {
    return switch (stone) {
        .lumen => spec.Rgb.hex(0x52f4fa),
        .ruby => spec.Rgb.hex(0xf52f49),
        .sapphire => spec.Rgb.hex(0x3978ff),
        .emerald => spec.Rgb.hex(0x38e878),
        .amethyst => spec.Rgb.hex(0xb66aff),
        .citrine => spec.Rgb.hex(0xffb932),
    };
}

/// A chest-set jewel with a raised table and individually colored radial facets.
fn gemstone(a: std.mem.Allocator, ch: *gen.Character, joint: sk.Joint, center: V, radius: f32, stone: Profile.Gemstone, cut: Profile.GemCut) !void {
    const base_color = gemstoneColor(stone);
    const base_channels = [4]f32{ base_color.r, base_color.g, base_color.b, 1 };
    const colors = [_]spec.Rgb{ mix(base_channels, spec.Rgb.hex(0xffffff), 0.48), base_color, mix(base_channels, spec.Rgb.hex(0x102033), 0.32) };
    const palette: [3]u8 = .{ @intCast(ch.palette.items.len), @intCast(ch.palette.items.len + 1), @intCast(ch.palette.items.len + 2) };
    try ch.palette.appendSlice(a, &colors);
    const facets: usize = switch (cut) { .brilliant => 8, .star => 5, .teardrop => 6 };
    const rx = radius * (if (cut == .teardrop) @as(f32, 0.78) else 1);
    const ry = radius * (if (cut == .teardrop) @as(f32, 1.25) else 0.82);
    const top = center.add(V.init(0, 0, radius * 0.32));
    for (0..facets) |i| {
        const segment: f32 = @floatFromInt(i);
        const next_segment: f32 = @floatFromInt(i + 1);
        const phase: f32 = if (cut == .star) @as(f32, std.math.pi) / 2.0 else 0;
        const a0 = phase + 2 * std.math.pi * segment / @as(f32, @floatFromInt(facets));
        const a1 = phase + 2 * std.math.pi * next_segment / @as(f32, @floatFromInt(facets));
        const p0 = center.add(V.init(@cos(a0) * rx, @sin(a0) * ry, 0));
        const p1 = center.add(V.init(@cos(a1) * rx, @sin(a1) * ry, 0));
        const shade = palette[i % 3];
        const v0 = try ch.mesh.addVertex(a, .{ .pos = top, .normal = V.unit_z, .joints = .{ joint.idx(), 0, 0, 0 }, .material = .armor });
        const v1 = try ch.mesh.addVertex(a, .{ .pos = p0, .normal = V.unit_z, .joints = .{ joint.idx(), 0, 0, 0 }, .material = .armor });
        const v2 = try ch.mesh.addVertex(a, .{ .pos = p1, .normal = V.unit_z, .joints = .{ joint.idx(), 0, 0, 0 }, .material = .armor });
        try ch.color_index.appendSlice(a, &.{ palette[0], shade, palette[(i + 1) % 3] });
        try ch.mesh.addTri(a, v0, v1, v2);
    }
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
        .gem_aegis => spec.Rgb.hex(0x9baebc),
        .starforge => spec.Rgb.hex(0x8d719f),
        .deep_prism => spec.Rgb.hex(0x397982),
        else => spec.Rgb.hex(0x71868e),
    };
    const accent = rgb(Profile.accent_colors[p.accent], 1.2);
    // Belt, boot cuffs and wrist seals bridge fabric transitions.
    try plate(a, ch, .hips, V.init(0, lm.waist_y - 0.08 * h, 0), V.init(lm.waist_half_width + 0.035, 0.035 * h, lm.waist_half_depth + 0.028), dark);
    if (p.clothing == .field_jacket) {
        const chest = s.worldPos(.chest);
        const B = lm.B;
        const cloth = Profile.outfit_colors[p.outfit];
        const pocket = mix(cloth, spec.Rgb.hex(0x8b9998), 0.45);
        const seam = mix(cloth, spec.Rgb.hex(0xd4bf91), 0.34);
        const harness = mix(cloth, spec.Rgb.hex(0x293640), 0.42);
        try fieldPanel(a, ch, V.init(chest.x - 0.18 * B, chest.y - 0.035 * B, 0.012 * B), 0.15 * B, 0.105 * B, 0.014 * B, 0, pocket);
        try fieldPanel(a, ch, V.init(chest.x - 0.18 * B, chest.y + 0.042 * B, 0.020 * B), 0.108 * B, 0.022 * B, 0.004 * B, 0, seam);
        try fieldPanel(a, ch, V.init(chest.x + 0.19 * B, chest.y - 0.025 * B, 0.012 * B), 0.11 * B, 0.042 * B, 0.008 * B, 0, pocket);
        try fieldPanel(a, ch, V.init(chest.x + 0.19 * B, chest.y - 0.025 * B, 0.018 * B), 0.055 * B, 0.008 * B, 0.003 * B, 0, seam);
        try fieldPanel(a, ch, V.init(chest.x - 0.11 * B, chest.y - 0.05 * B, 0.010 * B), 0.024 * B, 0.34 * B, 0.008 * B, -2.60, harness);
    }
    if (p.class == .synthetic and p.species == .human) {
        // Lit seams: a collar ring, a core light over the sternum and cheek lines.
        const seam = rgb(Profile.accent_colors[p.accent], 1.45);
        const neck = s.worldPos(.neck);
        try plate(a, ch, .neck, neck.add(V.init(0, 0.01 * h, 0.004 * h)), V.init(0.052 * w * h, 0.006 * h, 0.05 * h), seam);
        try plate(a, ch, .chest, s.worldPos(.chest).add(V.init(0, -0.02 * h, 0.178 * h)), V.init(0.02 * h, 0.02 * h, 0.008 * h), seam);
        if (p.helmet != .sealed) for ([_]f32{ -1, 1 }) |side| {
            try plate(a, ch, .head, V.init(side * 0.056 * h, lm.chin_y + 0.25 * lm.H, 0.084 * h), V.init(0.0035 * h, 0.028 * h, 0.004 * h), seam);
        };
    }
    if (p.clothing == .exo_rig or p.clothing == .hardsuit or p.clothing == .vanguard) try suitDetail(a, ch, p);
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
        .gem_aegis, .starforge, .deep_prism => {
            const chest = s.worldPos(.chest);
            const scale: f32 = if (p.presentation == .feminine) 0.94 else 1.08;
            for ([_]f32{ -1, 1 }) |side| {
                const shoulder: sk.Joint = if (side > 0) .shoulder_l else .shoulder_r;
                const forearm: sk.Joint = if (side > 0) .lower_arm_l else .lower_arm_r;
                const hip: sk.Joint = if (side > 0) .hips else .hips;
                if (p.armor == .gem_aegis) {
                    try plateWithMaterial(a, ch, shoulder, s.worldPos(shoulder).add(V.init(side * 0.025 * h, 0.005 * h, 0.012 * h)), V.init(0.105 * w * scale, 0.065 * h, 0.075 * h), metal, .armor);
                    try plateWithMaterial(a, ch, forearm, s.worldPos(forearm).add(V.init(0, 0, 0.035 * h)), V.init(0.052 * w, 0.12 * h, 0.046 * h), metal, .armor);
                } else if (p.armor == .starforge) {
                    try plateWithMaterial(a, ch, shoulder, s.worldPos(shoulder).add(V.init(side * 0.045 * h, 0.005 * h, 0.01 * h)), V.init(0.16 * w * scale, 0.08 * h, 0.095 * h), metal, .armor);
                    try plateWithMaterial(a, ch, hip, s.worldPos(.hips).add(V.init(side * 0.11 * h, -0.015 * h, 0.025 * h)), V.init(0.075 * w, 0.10 * h, 0.065 * h), metal, .armor);
                } else {
                    const shin: sk.Joint = if (side > 0) .shin_l else .shin_r;
                    try plateWithMaterial(a, ch, shoulder, s.worldPos(shoulder).add(V.init(side * 0.04 * h, 0.005 * h, 0.01 * h)), V.init(0.13 * w * scale, 0.075 * h, 0.09 * h), metal, .armor);
                    try plateWithMaterial(a, ch, forearm, s.worldPos(forearm).add(V.init(0, 0, 0.036 * h)), V.init(0.064 * w, 0.145 * h, 0.055 * h), metal, .armor);
                    try plateWithMaterial(a, ch, shin, s.worldPos(shin).add(V.init(0, -0.02 * h, 0.042 * h)), V.init(0.075 * w, 0.14 * h, 0.05 * h), metal, .armor);
                }
            }
            const jewel = chest.add(V.init(0, 0.045 * h, 0.177 * h));
            try plateWithMaterial(a, ch, .chest, jewel, V.init(0.071 * h, 0.071 * h, 0.014 * h), spec.Rgb.hex(0x263b4d), .metal);
            try gemstone(a, ch, .chest, jewel.add(V.init(0, 0, 0.015 * h)), 0.056 * h, p.gemstone, p.gem_cut);
            for ([_]f32{ -1, 1 }) |side| {
                const small = chest.add(V.init(side * 0.145 * h, 0.075 * h, 0.12 * h));
                try gemstone(a, ch, .chest, small, 0.022 * h, p.gemstone, .brilliant);
            }
        },
        else => {},
    }
    try bootDetails(a, ch, p, metal, accent);
    const wildkin = p.species != .human;
    if (p.helmet == .sealed or p.hair_style == .hood or wildkin) {
        // Conceal hair under the helmet/hood instead of allowing it to poke through. Wildkin
        // have fur, scales or feathers instead, built by `Beasts`.
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
        if (p.helmet == .sealed or p.hair_style == .hood) {
            const shell_center = V.init(0, lm.chin_y + 0.56 * lm.H, -0.02 * lm.H);
            const shell_radii = V.init(lm.head_half_width + 0.05 * lm.H, 0.55 * lm.H, 0.53 * lm.H);
            if (p.helmet == .sealed) {
                try plateWithMaterial(a, ch, .head, shell_center, shell_radii, metal, .armor);
            } else {
                try plate(a, ch, .head, shell_center, shell_radii, rgb(Profile.outfit_colors[p.outfit], 0.7));
            }
        }
    }
    // Wildkin show their faces: no visor, and their own features.
    if (wildkin) return Beasts.build(a, ch, p);
    if (p.helmet != .open) {
        const center = V.init(0, lm.chin_y + 0.47 * lm.H, 0.41 * lm.H);
        const visor_half_width = 0.65 * lm.head_half_width;
        try visorSurface(a, ch, center, visor_half_width, 0.09 * lm.H, 0.04 * lm.H, dark, 8, 24);
        try visorSurface(a, ch, center.add(V.init(0, 0.04 * lm.H, 0.004 * lm.H)), 0.72 * visor_half_width, 0.010 * lm.H, 0.044 * lm.H, accent, 2, 20);
        for ([_]f32{ -1, 1 }) |side| {
            try plateWithMaterial(a, ch, .head, center.add(V.init(side * visor_half_width, -0.01 * lm.H, -0.018 * lm.H)), V.init(0.035 * lm.H, 0.12 * lm.H, 0.045 * lm.H), metal, .armor);
        }
    }
}

fn bootDetails(a: std.mem.Allocator, ch: *gen.Character, p: Profile, metal: spec.Rgb, accent: spec.Rgb) !void {
    const s = &ch.skeleton;
    const h = 1.8 * p.height * Beasts.scale(p.species).height;
    const dark = spec.Rgb.hex(0x17242f);
    inline for ([_]sk.Joint{ .foot_l, .foot_r }, .{ @as(f32, 1), @as(f32, -1) }) |foot, side| {
        const ankle = s.worldPos(foot);
        const heel = ankle.add(V.init(0, -0.012 * h, -0.045 * h));
        switch (p.boot_style) {
            .trail_runner => {
                try plateWithMaterial(a, ch, foot, heel, V.init(0.065 * h, 0.026 * h, 0.09 * h), dark, .armor);
                try plateWithMaterial(a, ch, foot, heel.add(V.init(side * 0.045 * h, 0.008 * h, 0.012 * h)), V.init(0.009 * h, 0.012 * h, 0.055 * h), accent, .armor);
            },
            .field_boot => {
                try plateWithMaterial(a, ch, foot, ankle.add(V.init(0, -0.005 * h, -0.01 * h)), V.init(0.066 * h, 0.085 * h, 0.06 * h), dark, .armor);
                for ([_]f32{ -0.035, 0.012, 0.055 }) |y| try plateWithMaterial(a, ch, foot, ankle.add(V.init(side * 0.054 * h, y * h, 0.012 * h)), V.init(0.012 * h, 0.008 * h, 0.048 * h), metal, .armor);
            },
            .armored_sabatons => {
                try plateWithMaterial(a, ch, foot, ankle.add(V.init(0, -0.010 * h, 0.045 * h)), V.init(0.071 * h, 0.042 * h, 0.074 * h), metal, .armor);
                try plateWithMaterial(a, ch, foot, ankle.add(V.init(0, 0.022 * h, -0.025 * h)), V.init(0.068 * h, 0.043 * h, 0.057 * h), metal, .armor);
                try plateWithMaterial(a, ch, foot, ankle.add(V.init(side * 0.071 * h, 0.012 * h, 0.005 * h)), V.init(0.014 * h, 0.036 * h, 0.06 * h), accent, .armor);
            },
            .magstep => {
                try plateWithMaterial(a, ch, foot, heel.add(V.init(0, -0.026 * h, 0.025 * h)), V.init(0.073 * h, 0.019 * h, 0.11 * h), dark, .armor);
                try plateWithMaterial(a, ch, foot, heel.add(V.init(side * 0.057 * h, -0.027 * h, 0.025 * h)), V.init(0.009 * h, 0.012 * h, 0.105 * h), accent, .armor);
                try plateWithMaterial(a, ch, foot, ankle.add(V.init(0, -0.005 * h, -0.018 * h)), V.init(0.07 * h, 0.05 * h, 0.055 * h), metal, .armor);
            },
            .thruster => {
                try plateWithMaterial(a, ch, foot, heel.add(V.init(0, -0.006 * h, -0.015 * h)), V.init(0.086 * h, 0.07 * h, 0.078 * h), metal, .armor);
                try plateWithMaterial(a, ch, foot, heel.add(V.init(0, 0, -0.082 * h)), V.init(0.049 * h, 0.043 * h, 0.022 * h), dark, .armor);
                try plateWithMaterial(a, ch, foot, heel.add(V.init(0, 0, -0.097 * h)), V.init(0.03 * h, 0.026 * h, 0.009 * h), accent, .armor);
                try plateWithMaterial(a, ch, foot, ankle.add(V.init(side * 0.077 * h, -0.015 * h, 0.006 * h)), V.init(0.018 * h, 0.042 * h, 0.052 * h), accent, .armor);
            },
        }
    }
}

/// The hard-surface kit that turns a suit's shells into armor: lit lumen strips down the
/// forearms and shins, knee and elbow cops, a belt buckle, and an earpiece headset when the face
/// is open. The hardsuit and vanguard add a collar ring, a sternum plate with a core light and a
/// back power pack (the vanguard's with twin thrusters). Every piece is rigid `.armor` on its joint.
fn suitDetail(a: std.mem.Allocator, ch: *gen.Character, p: Profile) !void {
    const lm = ch.landmarks;
    const s = &ch.skeleton;
    const h = p.height;
    const t = suitTones(p);
    const heavy = p.clothing == .vanguard;
    const full = p.clothing != .exo_rig;
    const bulk: f32 = if (heavy) 1.25 else if (full) 1.1 else 1;
    inline for ([_]sk.Joint{ .lower_arm_l, .lower_arm_r }, [_]sk.Joint{ .shin_l, .shin_r }, .{ @as(f32, 1), @as(f32, -1) }) |forearm, shin, side| {
        const elbow = s.worldPos(forearm);
        const knee = s.worldPos(shin);
        // Lumen strips: down the outside of each forearm and the front of each shin.
        try plateWithMaterial(a, ch, forearm, elbow.add(V.init(side * 0.034 * h * bulk, -0.075 * h, 0.012 * h)), V.init(0.005 * h, 0.07 * h, 0.012 * h), t.glow, .armor);
        try plateWithMaterial(a, ch, shin, knee.add(V.init(0, -0.13 * h, 0.05 * h * bulk)), V.init(0.011 * h, 0.075 * h, 0.006 * h), t.glow, .armor);
        // Cops: a domed plate over each knee and behind each elbow.
        try plateWithMaterial(a, ch, shin, knee.add(V.init(0, 0.004 * h, 0.04 * h * bulk)), V.init(0.034 * h * bulk, 0.032 * h, 0.022 * h), t.plate, .armor);
        try plateWithMaterial(a, ch, forearm, elbow.add(V.init(side * 0.006 * h, 0, -0.03 * h * bulk)), V.init(0.026 * h * bulk, 0.03 * h, 0.02 * h), t.trim, .armor);
    }
    // Proto-human skate hardware: articulated heel housings, paired energy rollers and a
    // bright toe rail. The runners sit on the feet so the gait animation carries them naturally.
    inline for ([_]sk.Joint{ .foot_l, .foot_r }, .{ @as(f32, 1), @as(f32, -1) }) |foot, side| {
        const ankle = s.worldPos(foot);
        const heel = ankle.add(V.init(0, -0.012 * h, -0.045 * h));
        try plateWithMaterial(a, ch, foot, heel, V.init(0.07 * h * bulk, 0.035 * h, 0.11 * h), t.trim, .armor);
        inline for ([_]f32{ -1, 1 }) |lateral| {
            try plateWithMaterial(a, ch, foot, heel.add(V.init(lateral * 0.047 * h * bulk, -0.036 * h, -0.018 * h)), V.init(0.024 * h, 0.025 * h, 0.035 * h), t.plate, .armor);
            try plateWithMaterial(a, ch, foot, heel.add(V.init(lateral * 0.047 * h * bulk, -0.036 * h, -0.018 * h)), V.init(0.009 * h, 0.01 * h, 0.038 * h), t.glow, .armor);
        }
        try plateWithMaterial(a, ch, foot, heel.add(V.init(0, 0.018 * h, 0.05 * h)), V.init(0.045 * h * bulk, 0.012 * h, 0.014 * h), t.glow, .armor);
        // Side-facing ankle fins give the runner a directional silhouette.
        try plateWithMaterial(a, ch, foot, heel.add(V.init(side * 0.068 * h * bulk, 0.008 * h, 0)), V.init(0.012 * h, 0.025 * h, 0.075 * h), t.trim, .armor);
    }
    // Belt buckle.
    try plateWithMaterial(a, ch, .hips, V.init(0, lm.waist_y - 0.08 * h, lm.waist_half_depth + 0.03 + 0.012 * h), V.init(0.032 * h, 0.022 * h, 0.008 * h), t.glow, .armor);
    if (p.helmet == .open and p.species == .human) {
        // Headset: earpieces with lit rings, so an open face still reads as kit.
        for ([_]f32{ -1, 1 }) |side| {
            const ear = V.init(side * (lm.head_half_width + 0.004 * h), lm.chin_y + 0.42 * lm.H, -0.02 * lm.H);
            try plateWithMaterial(a, ch, .head, ear, V.init(0.012 * h, 0.034 * h, 0.03 * h), t.plate, .armor);
            try plateWithMaterial(a, ch, .head, ear.add(V.init(side * 0.009 * h, 0, 0)), V.init(0.004 * h, 0.02 * h, 0.018 * h), t.glow, .armor);
        }
    }
    if (!full) return;
    // Segmented shoulder shells extend the exo-rig into a readable, layered combat silhouette.
    inline for ([_]sk.Joint{ .upper_arm_l, .upper_arm_r }, .{ @as(f32, 1), @as(f32, -1) }) |arm, side| {
        const shoulder = s.worldPos(arm);
        try plateWithMaterial(a, ch, arm, shoulder.add(V.init(side * 0.012 * h, 0.045 * h, 0)), V.init(0.075 * h * bulk, 0.052 * h * bulk, 0.065 * h * bulk), t.plate, .armor);
        try plateWithMaterial(a, ch, arm, shoulder.add(V.init(side * 0.02 * h, 0.046 * h, 0.036 * h)), V.init(0.012 * h, 0.03 * h, 0.01 * h), t.glow, .armor);
    }
    const chest = s.worldPos(.chest);
    const neck = s.worldPos(.neck);
    // Collar ring.
    try plateWithMaterial(a, ch, .neck, neck.add(V.init(0, -0.012 * h, 0)), V.init(0.075 * h * bulk, 0.016 * h, 0.07 * h * bulk), t.trim, .armor);
    // Sternum plate on the cuirass, with a core light.
    const core_y = chest.y + 0.035 * h;
    const front = (surfaceZ(ch, 0, core_y, .armor) orelse chest.z + 0.15 * h) + 0.004 * h;
    try plateWithMaterial(a, ch, .chest, V.init(0, core_y, front - 0.004 * h), V.init(0.05 * h, 0.04 * h, 0.01 * h), t.trim, .armor);
    try plateWithMaterial(a, ch, .chest, V.init(0, core_y, front + 0.004 * h), V.init(0.018 * h, 0.018 * h, 0.006 * h), t.glow, .armor);
    // Power pack on the back, with lit vents; the vanguard's carries twin thrusters.
    const pack = chest.add(V.init(0, 0.01 * h, -0.13 * h - 0.02 * h * bulk));
    try plateWithMaterial(a, ch, .chest, pack, V.init(0.09 * h * bulk, 0.11 * h, 0.04 * h * bulk), t.trim, .armor);
    for ([_]f32{ -1, 1 }) |side| {
        try plateWithMaterial(a, ch, .chest, pack.add(V.init(side * 0.045 * h * bulk, 0.02 * h, -0.036 * h * bulk)), V.init(0.008 * h, 0.06 * h, 0.006 * h), t.glow, .armor);
        if (heavy) {
            try plateWithMaterial(a, ch, .chest, pack.add(V.init(side * 0.075 * h, -0.05 * h, -0.02 * h)), V.init(0.026 * h, 0.07 * h, 0.026 * h), t.plate, .armor);
            try plateWithMaterial(a, ch, .chest, pack.add(V.init(side * 0.075 * h, -0.12 * h, -0.02 * h)), V.init(0.018 * h, 0.012 * h, 0.018 * h), t.glow, .armor);
        }
    }
}

/// Cel shading puts a hard shadow band across anything facing down, and on a face that band lies
/// over the jaw and chin and reads as a beard. Anime faces avoid it by shading from a smoothed,
/// upward-leaning sphere: the face's normals are pulled most of the way (80%) onto one.
fn softenFace(ch: *gen.Character) void {
    const lm = ch.landmarks;
    const center = V.init(0, lm.chin_y + 0.5 * lm.H, -0.04 * lm.H);
    for (ch.mesh.vertices.items) |*v| {
        if ((v.region != .face and v.region != .head) or v.material != .skin) continue;
        const sphere = v.pos.sub(center).normalize().add(V.init(0, 1.0, 0)).normalize();
        v.normal = v.normal.scale(0.2).add(sphere.scale(0.8)).normalize();
    }
}

test "ranger meshes are smooth, layered, weighted and animate without allocations" {
    const a = std.testing.allocator;
    var ranger = try init(a, .{});
    defer ranger.deinit(a);
    try std.testing.expect(ranger.mesh.vertices.len > 2000);
    const hand = ranger.character.skeleton.worldPos(.hand_l);
    _ = ranger.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0, .walk_amount = 1, .walk_phase = 1.2 });
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

test "trooper strike and cover actions drive the skinned skeleton" {
    const a = std.testing.allocator;
    var ranger = try init(a, .{ .clothing = .vanguard, .armor = .sentinel, .helmet = .sealed });
    defer ranger.deinit(a);
    const skel = &ranger.character.skeleton;
    const rest_hand = skel.worldPos(.hand_r);
    _ = ranger.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0, .action = .strike, .action_t = 0.5 });
    const strike_hand = ranger.instance.pose.global[sk.Joint.hand_r.idx()].translation;
    try std.testing.expect(strike_hand.sub(rest_hand).length() > 0.2);
    const strike_hips = ranger.instance.pose.global[sk.Joint.hips.idx()].translation;
    _ = ranger.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0, .walk_amount = 0.4, .walk_phase = 1, .action = .cover });
    const cover_hips = ranger.instance.pose.global[sk.Joint.hips.idx()].translation;
    const cover_hand = ranger.instance.pose.global[sk.Joint.hand_r.idx()].translation;
    try std.testing.expect(cover_hips.y < strike_hips.y - 0.1);
    try std.testing.expect(cover_hand.sub(rest_hand).length() > 0.1);
    for (ranger.mesh.vertices) |v| for (v.position ++ v.normal) |value| try std.testing.expect(std.math.isFinite(value));
}

test "locomotion controller maps run sprint climb and airborne states" {
    try std.testing.expectEqual(Animation.ClipId.idle, clipFor(.idle, 0));
    try std.testing.expectEqual(Animation.ClipId.walk, clipFor(.run, 0.5));
    try std.testing.expectEqual(Animation.ClipId.run, clipFor(.run, 0.9));
    try std.testing.expectEqual(Animation.ClipId.run, clipFor(.sprint, 1));
    try std.testing.expectEqual(Animation.ClipId.climb, clipFor(.climb, 0));
    try std.testing.expectEqual(Animation.ClipId.climb, clipFor(.hang, 0));
    try std.testing.expectEqual(Animation.ClipId.air, clipFor(.fall, 0));
}

test "masculine and feminine ranger faces have fitted feature meshes and distinct proportions" {
    const a = std.testing.allocator;
    var masc = try init(a, .{ .armor = .none, .helmet = .open, .presentation = .masculine });
    defer masc.deinit(a);
    var fem = try init(a, .{ .armor = .none, .helmet = .open, .presentation = .feminine });
    defer fem.deinit(a);
    try std.testing.expectEqual(@as(f32, 0.18), masc.character.spec.body.femininity);
    try std.testing.expectEqual(@as(f32, 0.84), fem.character.spec.body.femininity);
    try std.testing.expect(!Ranger.sameAppearance(masc.profile, fem.profile));
    try std.testing.expect(masc.character.spec.body.head.jaw_taper != fem.character.spec.body.head.jaw_taper);
    try std.testing.expect(masc.character.spec.body.head.cranium_width != fem.character.spec.body.head.cranium_width);
    try std.testing.expectApproxEqAbs(@as(f32, 0.10), fem.character.spec.body.bust, 1e-6);
    try std.testing.expect(masc.character.spec.eyes.size != fem.character.spec.eyes.size);
    const male_eye = toon.faceDecal(.{ .x = 0.5 + masc.character.spec.eyes.spacing, .y = masc.character.spec.eyes.height }, masc.character.spec.eyes, .{}, 0.01);
    const female_eye = toon.faceDecal(.{ .x = 0.5 + fem.character.spec.eyes.spacing, .y = fem.character.spec.eyes.height }, fem.character.spec.eyes, .{}, 0.01);
    try std.testing.expect(male_eye.alpha > 0.99 and female_eye.alpha > 0.99);
    for ([_]Ranger{ masc, fem }) |ranger| {
        var face_front: f32 = 0;
        var face_count: usize = 0;
        for (ranger.mesh.vertices, ranger.character.mesh.vertices.items) |vertex, source| {
            try std.testing.expectEqual([2]f32{ 0, 0 }, vertex.uv);
            if (source.region != .face) continue;
            face_front += vertex.normal[2];
            face_count += 1;
        }
        try std.testing.expect(face_front / @as(f32, @floatFromInt(face_count)) > 0.25);
    }
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
            _ = r.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0, .walk_amount = 1, .walk_phase = 1.3 });
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
    var undersuit = try init(a, .{ .clothing = .undersuit, .helmet = .visor, .armor = .none });
    defer undersuit.deinit(a);

    const center_y = visor.character.landmarks.chin_y + 0.47 * visor.character.landmarks.H;
    const head_half = visor.character.landmarks.head_half_width;
    const edge_x = 0.68 * 0.65 * head_half;
    var center_front = -std.math.inf(f32);
    var edge_front = -std.math.inf(f32);
    var visor_vertices: usize = 0;
    for (visor.character.mesh.vertices.items) |vertex| {
        if (vertex.material != .armor or @abs(vertex.pos.y - center_y) > 0.002) continue;
        visor_vertices += 1;
        try std.testing.expect(vertex.normal.z > 0.8);
        if (@abs(vertex.pos.x) < 0.015) center_front = @max(center_front, vertex.pos.z);
        if (@abs(vertex.pos.x) > edge_x) edge_front = @max(edge_front, vertex.pos.z);
    }
    try std.testing.expect(visor_vertices > 10);
    try std.testing.expect(center_front > edge_front + 0.005 * visor.character.landmarks.H);
    try std.testing.expect(visor.character.mesh.vertices.items.len > open.character.mesh.vertices.items.len + 100);
    try std.testing.expect(visor.character.mesh.vertices.items.len > undersuit.character.mesh.vertices.items.len + 300);
}

test "sealed ranger helmet follows skull dimensions instead of body scale" {
    const a = std.testing.allocator;
    var helmet = try init(a, .{ .clothing = .hardsuit, .armor = .none, .helmet = .sealed });
    defer helmet.deinit(a);

    const lm = helmet.character.landmarks;
    var max_x: f32 = 0;
    var max_front: f32 = -std.math.inf(f32);
    var shell_vertices: usize = 0;
    for (helmet.character.mesh.vertices.items) |vertex| {
        if (vertex.material != .armor or vertex.joints[0] != sk.Joint.head.idx()) continue;
        shell_vertices += 1;
        max_x = @max(max_x, @abs(vertex.pos.x));
        max_front = @max(max_front, vertex.pos.z);
    }
    try std.testing.expect(shell_vertices > 200);
    try std.testing.expect(max_x < lm.head_half_width + 0.052 * lm.H);
    try std.testing.expect(max_front < 0.53 * lm.H);
}

test "field jacket utility panels stay close to the torso and keep their palette data" {
    const a = std.testing.allocator;
    var jacket = try init(a, .{ .clothing = .field_jacket, .armor = .none, .helmet = .open });
    defer jacket.deinit(a);

    const B = jacket.character.landmarks.B;
    var panel_vertices: usize = 0;
    var fitted_front_vertices: usize = 0;
    for (jacket.character.mesh.vertices.items) |vertex| {
        if (vertex.material != .cloth_outer or vertex.joints[0] != sk.Joint.chest.idx()) continue;
        panel_vertices += 1;
        if (vertex.normal.z > 0.8) {
            const shell_z = surfaceZ(&jacket.character, vertex.pos.x, vertex.pos.y, .cloth_top) orelse continue;
            fitted_front_vertices += 1;
            const clearance = vertex.pos.z - shell_z;
            try std.testing.expect(clearance >= -0.001 * B and clearance < 0.03 * B);
        }
    }
    try std.testing.expect(panel_vertices > 100);
    try std.testing.expect(fitted_front_vertices > 20);
    try std.testing.expectEqual(jacket.character.mesh.vertices.items.len, jacket.character.color_index.items.len);
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

/// The skinned vertex shader (`render/skin.wgsl`, `vertex_skinned`) in Zig, reading the packed
/// palette exactly as the GPU does: for testing that both paths put every vertex in one place.
fn shaderSkin(palette: *const Palette, v: SkinnedVertex) [2]V {
    const q = struct {
        fn get(p: *const Palette, i: usize) Q {
            return .{ .x = p[i][0], .y = p[i][1], .z = p[i][2], .w = p[i][3] };
        }
    }.get;
    const pivot = q(palette, @as(usize, v.joints[0]) * 2);
    var real: Q = .{ .x = 0, .y = 0, .z = 0, .w = 0 };
    var dual: Q = .{ .x = 0, .y = 0, .z = 0, .w = 0 };
    for (0..4) |k| {
        var w = v.weights[k];
        if (w == 0) continue;
        const r = q(palette, @as(usize, v.joints[k]) * 2);
        const d = q(palette, @as(usize, v.joints[k]) * 2 + 1);
        if (r.dot(pivot) < 0) w = -w;
        real = .{ .x = real.x + r.x * w, .y = real.y + r.y * w, .z = real.z + r.z * w, .w = real.w + r.w * w };
        dual = .{ .x = dual.x + d.x * w, .y = dual.y + d.y * w, .z = dual.z + d.z * w, .w = dual.w + d.w * w };
    }
    const len = @sqrt(real.dot(real));
    if (len > 0.000001) {
        real = .{ .x = real.x / len, .y = real.y / len, .z = real.z / len, .w = real.w / len };
        dual = .{ .x = dual.x / len, .y = dual.y / len, .z = dual.z / len, .w = dual.w / len };
    }
    const t = dual.mul(real.conjugate());
    const p = real.rotate(V.init(v.position[0], v.position[1], v.position[2])).add(V.init(2 * t.x, 2 * t.y, 2 * t.z));
    return .{ p, real.rotate(V.init(v.normal[0], v.normal[1], v.normal[2])) };
}

test "the GPU palette skins every vertex where the CPU skinning puts it" {
    const a = std.testing.allocator;
    const poses = [_]Pose{
        .{ .feet = .{ 0, 0, 0 }, .yaw = 0, .walk_amount = 1, .walk_phase = 1.3, .motion = .run, .time = 2 },
        .{ .feet = .{ 0, 0, 0 }, .yaw = 0, .action = .swing, .action_t = 0.6, .arc = .overhead, .time = 3 },
    };
    for ([_]Profile{ .{}, .{ .species = .lion }, .{ .species = .spider }, .{ .species = .eagle, .clothing = .hardsuit } }) |profile| {
        var r = try init(a, profile);
        defer r.deinit(a);
        try std.testing.expect(r.gpuSkinnable());
        const vertices = try r.skinnedVertices(a);
        defer a.free(vertices);
        for (poses) |pose| {
            r.last_pose = null;
            _ = r.update(pose);
            var palette: Palette = undefined;
            r.last_pose = null;
            try std.testing.expect(r.posePalette(pose, &palette));
            var worst: f32 = 0;
            for (vertices, r.instance.pos, r.instance.nrm) |v, cpu_pos, cpu_nrm| {
                const gpu_skin = shaderSkin(&palette, v);
                worst = @max(worst, gpu_skin[0].sub(cpu_pos).length());
                try std.testing.expect(gpu_skin[1].normalizeOr(V.unit_y).dot(cpu_nrm.normalizeOr(V.unit_y)) > 0.999);
            }
            try std.testing.expect(worst < 1e-4);
        }
    }
}

test "faces shade from an upward-leaning sphere, so the jaw does not fall into shadow" {
    const a = std.testing.allocator;
    var r = try init(a, .{ .armor = .none, .helmet = .open });
    defer r.deinit(a);
    const lm = r.character.landmarks;
    var jaw: usize = 0;
    var lit: usize = 0;
    for (r.character.mesh.vertices.items) |v| {
        if (v.region != .face and v.region != .head) continue;
        // The visible jaw and chin, from the head's lower rim to the mouth (the dome capping
        // the underside sits inside the neck).
        if (v.material != .skin or v.pos.z < 0 or v.pos.y < lm.chin_y + 0.1 * lm.H or v.pos.y > lm.chin_y + 0.25 * lm.H) continue;
        jaw += 1;
        if (v.normal.y > -0.2) lit += 1;
    }
    // Only the very underside of the chin still faces down.
    try std.testing.expect(jaw > 20 and lit * 100 >= jaw * 95);
}

test "suits carry lit strips, cops and a buckle; full suits add a core and a back power pack" {
    const a = std.testing.allocator;
    var backs: [3]f32 = undefined;
    for ([_]Profile.Clothing{ .exo_rig, .hardsuit, .vanguard }, 0..) |clothing, k| {
        const profile: Profile = .{ .clothing = clothing, .armor = .none, .helmet = .open };
        var r = try init(a, profile);
        defer r.deinit(a);
        const glow = suitTones(profile).glow;
        var lit: usize = 0;
        var back: f32 = 0;
        const chest = r.character.skeleton.worldPos(.chest);
        for (r.character.mesh.vertices.items, r.character.color_index.items) |v, ci| {
            if (v.material != .armor) continue;
            if (std.meta.eql(r.character.palette.items[ci], glow)) lit += 1;
            if (@abs(v.pos.y - chest.y) < 0.15) back = @max(back, chest.z - v.pos.z);
        }
        try std.testing.expect(lit > 200);
        backs[k] = back;
    }
    // The power pack stands off the back; the vanguard's farthest.
    try std.testing.expect(backs[1] > backs[0] + 0.02 and backs[2] > backs[1]);
}

test "face presets match the face styles and give each one a distinct head" {
    const styles = std.enums.values(Profile.FaceStyle);
    try std.testing.expectEqual(spec.face_presets.len, styles.len);
    for (styles) |style| try std.testing.expectEqualStrings(@tagName(style), facePreset(style).name);
    const a = std.testing.allocator;
    var hero = try init(a, .{ .face_style = .hero });
    defer hero.deinit(a);
    var classic = try init(a, .{ .face_style = .classic });
    defer classic.deinit(a);
    // Human heads are 5.5-6.5 per head height; the hero has the shorter, thicker neck and bigger hands.
    const hb = hero.character.spec.body;
    try std.testing.expect(hb.head_ratio >= 5.5 and hb.head_ratio <= 6.5);
    try std.testing.expect(hb.head.neck_length < classic.character.spec.body.head.neck_length);
    try std.testing.expect(hero.character.spec.eyes.brow_tilt > classic.character.spec.eyes.brow_tilt);
    try std.testing.expect(hero.character.landmarks.hand_len > 0.092 * hb.height);
    // The face is a front-facing band: eyes sit about 0.55 of the head down from the crown.
    const lm = hero.character.landmarks;
    try std.testing.expectApproxEqAbs(@as(f32, 0.45), hero.character.spec.eyes.height, 0.03);
    try std.testing.expect(lm.shoulder_y < lm.chin_y and lm.chin_y - lm.shoulder_y < 0.3 * lm.B);
}
