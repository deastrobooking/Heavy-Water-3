//! Data-driven sci-fi armor: rounded, anime-mecha pieces assembled from plain data.
//!
//! An `ArmorSetDef` is a name, four colours, a `ShapeSpec` (the silhouette family that hard-surface
//! garments in `clothing.zig` read too), a visor shape and a list of `Piece`s. `emitSet` turns a
//! def into rigid meshes on a built `Character`. Every piece is a handful of superellipsoid
//! "blobs" bound at full weight to one joint (hard plates move, they never stretch), and pieces
//! that sit on the body are pushed out of whatever is underneath, measured from the character's
//! own mesh, so they do not clip through the body at rest.
//!
//! The tables are plain `const` data and `ArmorSetDef.validate` checks one without touching any
//! global state, so a mod loader can build defs at runtime, validate them, and pass them to
//! `emitSet`. Nothing here depends on the game's `Profile`: the game maps a profile onto a
//! `Context` and a def name.
//!
//! Coordinates inside a piece are `(out, along, front)` in meters on a 1.8 m body; the frame
//! scales them to the character. For limb anchors `along` runs from the joint toward its child
//! (down the limb), `out` is the side that faces up and away from the body, and `front` is +Z.
//! For trunk, neck and head anchors `along` is up, `out` is +X on the left half (mirrored for
//! the right), and `front` is +Z. Mirroring a piece reuses the same numbers on both sides.

const std = @import("std");
const m = @import("math.zig");
const mesh_mod = @import("mesh.zig");
const skel_mod = @import("skeleton.zig");
const spec_mod = @import("spec.zig");
const char_mod = @import("character.zig");

const Vec3 = m.Vec3;
const Quat = m.Quat;
const Rgb = spec_mod.Rgb;
const ShapeSpec = spec_mod.ShapeSpec;
const Material = mesh_mod.Material;
const Joint = skel_mod.Joint;
const Character = char_mod.Character;
const Allocator = std.mem.Allocator;

/// Pieces per set; keeps a set's triangle budget bounded.
pub const max_pieces = 64;

/// Where a piece attaches. Sided anchors resolve to the left or right joint per `Sides`.
pub const Anchor = enum { chest, hips, neck, head, upper_arm, forearm, hand, thigh, shin };

pub const Sides = enum {
    /// Both sides, mirrored (trunk and head anchors mirror across X).
    both,
    left,
    right,
    /// One piece on the midline (trunk and head anchors only). On a trunk or head anchor, left and right place one piece on that half.
    center,
};

/// When a piece is built.
pub const Fit = enum {
    always,
    /// Only when no hard-surface suit already plates the body.
    bare,
    /// Only over a hardsuit or vanguard.
    suited,
    /// Only with a visor or sealed helmet.
    helmeted,
    /// Only with a sealed helmet.
    sealed,
};

/// A named color slot, resolved against the set's palette and the player's accent.
pub const ColorSlot = enum { metal, secondary, trim, dark, accent, glow };

pub const Kind = enum {
    /// One superellipsoid from `offset`, `size`, `exponent`, `taper`, `tilt`.
    blob,
    /// Shoulder dome with a rim ring; the silhouette adds fins, keels, steps or a layered plate.
    dome_pauldron,
    /// Oversized gauntlet over the hand: wrist cuff, mitten, knuckle ring, lit tip, optional spikes.
    fist_guard,
    /// Forearm cannon that runs past the hand, with coil bands and a lit muzzle (Mega Man style).
    buster_arm,
    /// Shin plate with knee cup, ankle cuff and silhouette-driven side fins or front keel.
    finned_greave,
    /// Back-of-calf thruster housing with a nozzle and glow.
    thruster_calf,
    /// Flared rounded plate that kicks out by the shape's flare (hip skirt, tassets, flaps).
    skirt_plate,
    /// Chest dome placed on the torso front surface, shaped by the silhouette.
    chest_dome,
    /// Lit ring and glow disc on the torso front surface.
    core,
    /// Back pack with thruster nozzles and silhouette-driven wings.
    backpack,
    /// Helmet crest fin along the top of a sealed helmet.
    crest,
    /// Helmet antenna; mirrored pair gives a V-fin.
    antenna,
    /// Side-of-head pod with a swept fin (ear guard, scouter arm).
    ear_fin,
    /// Neck ring with silhouette-driven rear blades.
    collar,
    /// Faceted jewel on a flat setting, positioned absolutely from the anchor joint.
    gem,
};

pub const GemCut = enum { brilliant, star, teardrop };

pub const VisorShape = enum {
    /// Curved wrap-around lens with a lit slit and cheek plates.
    wrap,
    /// Narrow wide slit under a brow.
    slit,
    /// Two angled eye slits (mobile-suit eyes).
    twin,
    /// One round lens centered on the face.
    mono,
    /// One lens over the left eye only, with an arm to the ear (scouter).
    scouter,
    /// No lens.
    none,
};

pub const Piece = struct {
    kind: Kind,
    anchor: Anchor,
    sides: Sides = .both,
    when: Fit = .always,
    /// `(out, along, front)` placement in meters on a 1.8 m body.
    offset: [3]f32 = .{ 0, 0, 0 },
    /// Radii of a `blob`, or the overall dimensions of the shaped kinds that take a size.
    size: [3]f32 = .{ 0.05, 0.05, 0.05 },
    /// Uniform scale for the fixed-layout kinds (fist guard, buster, greave, thruster, ear fin, collar).
    scale: f32 = 1,
    /// `blob`: pitch about out, yaw about along, roll about front, radians.
    tilt: [3]f32 = .{ 0, 0, 0 },
    /// `blob`: superellipsoid exponent, 1 = ellipsoid, lower = boxier.
    exponent: f32 = 1,
    /// `blob`: widening toward +along (-0.9 .. 0.9).
    taper: f32 = 0,
    color: ColorSlot = .metal,
    material: Material = .armor,
    /// Push the piece out of the body underneath it (limb and trunk anchors).
    fit: bool = true,
    /// Overrides the set's shape for this piece.
    shape: ?ShapeSpec = null,
};

pub const ValidateError = error{ EmptyName, NameTooLong, BadName, TooManyPieces, BadShape, BadPiece, BadColor, DuplicateName };

pub const ArmorSetDef = struct {
    /// Lowercase identifier, equal to the `Profile.Armor` tag that selects it.
    name: []const u8,
    /// Display name.
    title: []const u8 = "",
    metal: Rgb,
    secondary: Rgb,
    trim: Rgb,
    dark: Rgb = Rgb.hex(0x17242f),
    /// Silhouette family: read by the hard-surface garments of a suit (`clothing.zig`) and as the
    /// default for the set's own pieces.
    shape: ShapeSpec = .{},
    visor: VisorShape = .wrap,
    pieces: []const Piece = &.{},

    /// Checks everything `emitSet` relies on. Pure: reads only the def.
    pub fn validate(def: ArmorSetDef) ValidateError!void {
        if (def.name.len == 0) return error.EmptyName;
        if (def.name.len > 32) return error.NameTooLong;
        for (def.name) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return error.BadName;
        if (def.pieces.len > max_pieces) return error.TooManyPieces;
        try checkShape(def.shape);
        for ([_]Rgb{ def.metal, def.secondary, def.trim, def.dark }) |c| try checkColor(c);
        for (def.pieces) |p| {
            if (p.shape) |s| try checkShape(s);
            for (p.offset) |v| if (!(std.math.isFinite(v) and @abs(v) <= 1.0)) return error.BadPiece;
            for (p.size) |v| if (!(std.math.isFinite(v) and v > 0 and v <= 0.6)) return error.BadPiece;
            for (p.tilt) |v| if (!(std.math.isFinite(v) and @abs(v) <= m.pi)) return error.BadPiece;
            if (!(std.math.isFinite(p.scale) and p.scale > 0.1 and p.scale <= 3)) return error.BadPiece;
            if (!(std.math.isFinite(p.exponent) and p.exponent >= 0.3 and p.exponent <= 1.5)) return error.BadPiece;
            if (!(std.math.isFinite(p.taper) and @abs(p.taper) <= 0.9)) return error.BadPiece;
            const sided = switch (p.anchor) {
                .upper_arm, .forearm, .hand, .thigh, .shin => true,
                else => false,
            };
            if (sided and p.sides == .center) return error.BadPiece;
        }
    }
};

fn checkShape(s: ShapeSpec) ValidateError!void {
    const ok = std.math.isFinite(s.flare) and s.flare >= 0 and s.flare <= 1.5 and
        std.math.isFinite(s.crest) and s.crest >= 0 and s.crest <= 0.25 and
        std.math.isFinite(s.roundness) and s.roundness >= 0 and s.roundness <= 1 and
        std.math.isFinite(s.overlap) and s.overlap >= 0 and s.overlap <= 1;
    if (!ok) return error.BadShape;
}

fn checkColor(c: Rgb) ValidateError!void {
    for ([_]f32{ c.r, c.g, c.b }) |v| if (!(std.math.isFinite(v) and v >= 0 and v <= 2)) return error.BadColor;
}

/// Validates every def and that names are unique.
pub fn validateAll(defs: []const ArmorSetDef) ValidateError!void {
    for (defs, 0..) |d, i| {
        try d.validate();
        for (defs[0..i]) |e| if (std.mem.eql(u8, d.name, e.name)) return error.DuplicateName;
    }
}

pub fn find(defs: []const ArmorSetDef, name: []const u8) ?*const ArmorSetDef {
    for (defs) |*d| if (std.mem.eql(u8, d.name, name)) return d;
    return null;
}

pub const Helmet = enum { open, visor, sealed };

/// What the game tells the builder about the wearer.
pub const Context = struct {
    /// Body height against the 1.8 m reference; every length is multiplied by it.
    scale: f32 = 1,
    /// Lateral build multiplier (about 0.85 to 1.15).
    build: f32 = 1,
    /// The player's accent colour; the `glow` slot is this over-brightened.
    accent: Rgb = Rgb.hex(0x4dffff),
    helmet: Helmet = .open,
    /// A hardsuit or vanguard already plates the limbs and torso.
    suited: bool = false,
    gem: Rgb = Rgb.hex(0x52f4fa),
    gem_cut: GemCut = .brilliant,
};

fn slotColor(def: *const ArmorSetDef, ctx: Context, slot: ColorSlot) Rgb {
    return switch (slot) {
        .metal => def.metal,
        .secondary => def.secondary,
        .trim => def.trim,
        .dark => def.dark,
        .accent => .{ .r = ctx.accent.r * 1.2, .g = ctx.accent.g * 1.2, .b = ctx.accent.b * 1.2 },
        .glow => .{ .r = ctx.accent.r * 1.55, .g = ctx.accent.g * 1.55, .b = ctx.accent.b * 1.55 },
    };
}

fn applies(when: Fit, ctx: Context) bool {
    return switch (when) {
        .always => true,
        .bare => !ctx.suited,
        .suited => ctx.suited,
        .helmeted => ctx.helmet != .open,
        .sealed => ctx.helmet == .sealed,
    };
}

// ---------------------------------------------------------------- frames
const Frame = struct {
    origin: Vec3,
    out: Vec3,
    along: Vec3,
    front: Vec3,
    /// Meters per reference meter.
    unit: f32,
    /// Extra scale on the out axis (build).
    wide: f32 = 1,
    /// Head frames: sideways padding for the real head width.
    pad: f32 = 0,
    /// The basis is a reflection, so triangle winding flips.
    mirrored: bool = false,

    fn localPos(f: Frame, p: Vec3) Vec3 {
        const pad = if (@abs(p.x) > 0.02) std.math.sign(p.x) * f.pad else 0;
        return Vec3.init(p.x * f.unit * f.wide + pad, p.y * f.unit, p.z * f.unit);
    }
    fn world(f: Frame, local: Vec3) Vec3 {
        return f.origin.add(f.out.scale(local.x)).add(f.along.scale(local.y)).add(f.front.scale(local.z));
    }
    fn vec(f: Frame, local: Vec3) Vec3 {
        return f.out.scale(local.x).add(f.along.scale(local.y)).add(f.front.scale(local.z));
    }
};

fn makeFrame(ch: *const Character, anchor: Anchor, left: bool, side: f32, ctx: Context) Frame {
    const s = &ch.skeleton;
    const lm = ch.landmarks;
    var f: Frame = .{ .origin = Vec3.zero, .out = Vec3.unit_x, .along = Vec3.unit_y, .front = Vec3.unit_z, .unit = ctx.scale, .wide = ctx.build };
    const trunk_out = Vec3.init(side, 0, 0);
    switch (anchor) {
        .chest => {
            f.origin = s.worldPos(.chest);
            f.out = trunk_out;
        },
        .hips => {
            f.origin = s.worldPos(.hips);
            f.out = trunk_out;
        },
        .neck => {
            f.origin = s.worldPos(.neck);
            f.out = trunk_out;
        },
        .head => {
            f.origin = Vec3.init(0, lm.chin_y + 0.56 * lm.H, -0.02 * lm.H);
            f.out = trunk_out;
            f.unit = lm.H / (1.8 / 6.3);
            f.wide = 1;
            f.pad = lm.head_half_width - 0.4 * (1.8 / 6.3) * f.unit;
        },
        else => {
            const joints = limbJoints(anchor, left);
            const origin = s.worldPos(joints.joint);
            const target = if (joints.child) |c| s.worldPos(c) else origin.add(origin.sub(s.worldPos(joints.parent.?)));
            f.origin = origin;
            f.along = target.sub(origin).normalizeOr(Vec3.unit_y.neg());
            f.front = Vec3.unit_z.sub(f.along.scale(Vec3.unit_z.dot(f.along))).normalizeOr(Vec3.unit_z);
            f.out = f.front.cross(f.along).scale(side);
        },
    }
    const det = f.out.cross(f.along).dot(f.front);
    f.mirrored = det < 0;
    return f;
}

const LimbJoints = struct { joint: Joint, child: ?Joint = null, parent: ?Joint = null };

fn limbJoints(anchor: Anchor, left: bool) LimbJoints {
    return switch (anchor) {
        .upper_arm => if (left) .{ .joint = .upper_arm_l, .child = .lower_arm_l } else .{ .joint = .upper_arm_r, .child = .lower_arm_r },
        .forearm => if (left) .{ .joint = .lower_arm_l, .child = .hand_l } else .{ .joint = .lower_arm_r, .child = .hand_r },
        .hand => if (left) .{ .joint = .hand_l, .parent = .lower_arm_l } else .{ .joint = .hand_r, .parent = .lower_arm_r },
        .thigh => if (left) .{ .joint = .thigh_l, .child = .shin_l } else .{ .joint = .thigh_r, .child = .shin_r },
        .shin => if (left) .{ .joint = .shin_l, .child = .foot_l } else .{ .joint = .shin_r, .child = .foot_r },
        else => unreachable,
    };
}

fn anchorJoint(anchor: Anchor, left: bool) Joint {
    return switch (anchor) {
        .chest => .chest,
        .hips => .hips,
        .neck => .neck,
        .head => .head,
        else => limbJoints(anchor, left).joint,
    };
}

// ---------------------------------------------------------------- fitting
/// Max radius of the body mesh around an axis, binned by position along the axis and angle, from
/// the vertices bound to a few joints. Pieces are pushed out to at least this radius.
const Envelope = struct {
    const slabs = 12;
    const sectors = 16;
    a: Vec3,
    axis: Vec3,
    len: f32,
    e1: Vec3,
    e2: Vec3,
    r: [slabs][sectors]f32,

    fn build(ch: *const Character, count: usize, include: []const Joint, a: Vec3, b: Vec3, e1: ?Vec3) Envelope {
        const d = b.sub(a);
        const len = @max(d.length(), 1e-4);
        const axis = d.scale(1 / len);
        const first = e1 orelse Vec3.anyPerpendicular(axis);
        const u = first.sub(axis.scale(first.dot(axis))).normalizeOr(Vec3.anyPerpendicular(axis));
        var env: Envelope = .{ .a = a, .axis = axis, .len = len, .e1 = u, .e2 = axis.cross(u), .r = @splat(@splat(0)) };
        for (ch.mesh.vertices.items[0..count]) |v| {
            if (v.material == .hair) continue;
            var inc = false;
            for (include) |j| inc = inc or v.joints[0] == j.idx();
            if (!inc) continue;
            const rel = v.pos.sub(a);
            const s = rel.dot(axis) / len;
            if (s < -0.3 or s > 1.3) continue;
            const radial = rel.sub(axis.scale(rel.dot(axis)));
            const r = radial.length();
            const slab: usize = @intFromFloat(std.math.clamp(@floor(m.saturate(s) * slabs), 0, slabs - 1));
            const bin = env.sectorOf(radial);
            env.r[slab][bin] = @max(env.r[slab][bin], r);
        }
        // Dilate one bin each way so sparse vertices do not leave holes.
        const src = env.r;
        for (0..slabs) |i| for (0..sectors) |k| {
            var best: f32 = 0;
            for ([_]i32{ -1, 0, 1 }) |di| for ([_]i32{ -1, 0, 1 }) |dk| {
                const ii = @as(i32, @intCast(i)) + di;
                if (ii < 0 or ii >= slabs) continue;
                const kk: usize = @intCast(@mod(@as(i32, @intCast(k)) + dk, sectors));
                best = @max(best, src[@intCast(ii)][kk]);
            };
            env.r[i][k] = best;
        };
        return env;
    }

    fn sectorOf(env: *const Envelope, radial: Vec3) usize {
        const ang = std.math.atan2(radial.dot(env.e2), radial.dot(env.e1));
        const f = @mod(ang / m.tau + 1.0, 1.0) * sectors;
        return @as(usize, @intFromFloat(@floor(f))) % sectors;
    }

    /// Body radius at axis parameter `s` (0..1) and angle `ang` (0 along `e1`).
    fn radiusAt(env: *const Envelope, s: f32, ang: f32) f32 {
        const fs = m.saturate(s) * (slabs - 1);
        const si: usize = @min(@as(usize, @intFromFloat(@floor(fs))), slabs - 2);
        const ts = fs - @as(f32, @floatFromInt(si));
        const fa = @mod(ang / m.tau + 1.0, 1.0) * sectors;
        const k0: usize = @as(usize, @intFromFloat(@floor(fa))) % sectors;
        const k1 = (k0 + 1) % sectors;
        const ta = fa - @floor(fa);
        const r0 = m.lerp(env.r[si][k0], env.r[si][k1], ta);
        const r1 = m.lerp(env.r[si + 1][k0], env.r[si + 1][k1], ta);
        return m.lerp(r0, r1, ts);
    }

    /// Moves `p` radially outward until it clears the body by `clearance`.
    fn push(env: *const Envelope, p: Vec3, clearance: f32) Vec3 {
        const rel = p.sub(env.a);
        const along = rel.dot(env.axis);
        const s = along / env.len;
        if (s < -0.35 or s > 1.35) return p;
        const radial = rel.sub(env.axis.scale(along));
        const r = radial.length();
        const dir = if (r > 1e-5) radial.scale(1 / r) else env.e1;
        const body_r = env.radiusAt(s, std.math.atan2(dir.dot(env.e2), dir.dot(env.e1)));
        if (body_r <= 0) return p;
        const need = body_r + clearance;
        if (r >= need) return p;
        return env.a.add(env.axis.scale(along)).add(dir.scale(need));
    }
};

/// Lazily built envelopes over the mesh as it was when the set began, one per anchor joint.
const Fitter = struct {
    ch: *const Character,
    count: usize,
    envs: [skel_mod.humanoid_joint_count]?Envelope = @splat(null),

    fn envelope(self: *Fitter, anchor: Anchor, left: bool, frame: Frame) ?*const Envelope {
        const joint = anchorJoint(anchor, left);
        const key = joint.idx();
        if (key >= self.envs.len) return null;
        if (self.envs[key] == null) {
            const lm = self.ch.landmarks;
            const s = &self.ch.skeleton;
            const e: ?Envelope = switch (anchor) {
                .head, .neck => null,
                .chest, .hips => Envelope.build(self.ch, self.count, &.{ .hips, .spine, .chest, .shoulder_l, .shoulder_r }, Vec3.init(0, lm.crotch_y, 0), Vec3.init(0, lm.shoulder_y + 0.05 * lm.B, 0), Vec3.unit_z),
                .upper_arm => blk: {
                    const lj = limbJoints(anchor, left);
                    const sh: Joint = if (left) .shoulder_l else .shoulder_r;
                    break :blk Envelope.build(self.ch, self.count, &.{ lj.joint, sh }, s.worldPos(lj.joint).sub(frame.along.scale(0.07 * frame.unit)), s.worldPos(lj.child.?), null);
                },
                .forearm, .thigh, .shin => blk: {
                    const lj = limbJoints(anchor, left);
                    break :blk Envelope.build(self.ch, self.count, &.{lj.joint}, s.worldPos(lj.joint), s.worldPos(lj.child.?), null);
                },
                .hand => blk: {
                    const lj = limbJoints(anchor, left);
                    const o = s.worldPos(lj.joint);
                    break :blk Envelope.build(self.ch, self.count, &.{lj.joint}, o, o.add(frame.along.scale(lm.hand_len)), null);
                },
            };
            self.envs[key] = e;
        }
        return if (self.envs[key]) |*e| e else null;
    }
};

// ---------------------------------------------------------------- blobs
const BlobOpts = struct {
    exp: f32 = 1,
    taper: f32 = 0,
    rot: Quat = Quat.identity,
    color: ColorSlot = .metal,
    /// null = the piece's own material / fit setting.
    material: ?Material = null,
    fit: ?bool = null,
};

fn sgnPow(v: f32, e: f32) f32 {
    return std.math.sign(v) * std.math.pow(f32, @abs(v), e);
}

fn paletteIndex(a: Allocator, ch: *Character, c: Rgb) !u8 {
    for (ch.palette.items, 0..) |p, i| {
        if (p.r == c.r and p.g == c.g and p.b == c.b) return @intCast(i);
    }
    if (ch.palette.items.len >= std.math.maxInt(u8)) return @intCast(ch.palette.items.len - 1);
    try ch.palette.append(a, c);
    return @intCast(ch.palette.items.len - 1);
}

const Builder = struct {
    a: Allocator,
    ch: *Character,
    def: *const ArmorSetDef,
    ctx: Context,
    piece: *const Piece,
    frame: Frame,
    joint: Joint,
    left: bool,
    side: f32,
    fitter: *Fitter,
    sh: ShapeSpec,

    fn v3(p: [3]f32) Vec3 {
        return Vec3.init(p[0], p[1], p[2]);
    }

    fn blob(b: *Builder, center_ref: Vec3, radii_ref: Vec3, o: BlobOpts) !void {
        const rows = 8;
        const cols = 14;
        const f = b.frame;
        const c = f.localPos(center_ref);
        const radii = Vec3.init(radii_ref.x * f.unit * f.wide, radii_ref.y * f.unit, radii_ref.z * f.unit);
        const e = std.math.clamp(o.exp, 0.3, 1.5);
        const palette = try paletteIndex(b.a, b.ch, slotColor(b.def, b.ctx, o.color));
        const material = o.material orelse b.piece.material;
        const want_fit = o.fit orelse b.piece.fit;
        const env = if (want_fit) b.fitter.envelope(b.piece.anchor, b.left, f) else null;
        const first = b.ch.mesh.vertexCount();
        const clearance = 0.008 * f.unit;
        for (0..rows + 1) |r| for (0..cols) |k| {
            const lat = m.pi * @as(f32, @floatFromInt(r)) / rows;
            const ang = m.tau * @as(f32, @floatFromInt(k)) / cols;
            const sl = @sin(lat);
            const u = Vec3.init(sgnPow(sl, e) * sgnPow(@cos(ang), e), sgnPow(@cos(lat), e), sgnPow(sl, e) * sgnPow(@sin(ang), e));
            const kf = @max(0.15, 1 + o.taper * u.y);
            var pos = Vec3.init(u.x * radii.x * kf, u.y * radii.y, u.z * radii.z * kf);
            // Gradient of the implicit surface, adjusted for the taper.
            const ge = 2 / e - 1;
            const gx = sgnPow(u.x, ge) / radii.x;
            const gy = sgnPow(u.y, ge) / radii.y;
            const gz = sgnPow(u.z, ge) / radii.z;
            const gy_t = gy - (gx * u.x * radii.x + gz * u.z * radii.z) * o.taper / (radii.y * kf);
            var n = Vec3.init(gx / kf, gy_t, gz / kf).normalizeOr(Vec3.unit_y);
            pos = c.add(o.rot.rotate(pos));
            n = o.rot.rotate(n);
            var world = f.world(pos);
            if (env) |en| world = en.push(world, clearance);
            const wn = f.vec(n);
            _ = try b.ch.mesh.addVertex(b.a, .{ .pos = world, .normal = wn.normalizeOr(Vec3.unit_y), .joints = .{ b.joint.idx(), 0, 0, 0 }, .material = material });
            try b.ch.color_index.append(b.a, palette);
        };
        try b.ch.mesh.stitchRings(b.a, first, rows + 1, cols, true, f.mirrored);
    }

    /// A blob placed relative to a parent blob's center and rotation.
    fn part(b: *Builder, parent_c: Vec3, parent_rot: Quat, local: Vec3, radii: Vec3, o: BlobOpts) !void {
        var opts = o;
        opts.rot = parent_rot.mul(o.rot);
        try b.blob(parent_c.add(parent_rot.rotate(local)), radii, opts);
    }
};

fn eulerQ(pitch: f32, yaw: f32, roll: f32) Quat {
    return Quat.fromEuler(pitch, yaw, roll);
}

/// Superellipsoid exponent for a shape: boxy and chamfered at low roundness, an ellipsoid from 0.6.
fn expOf(sh: ShapeSpec) f32 {
    var e = m.lerp(0.5, 1.0, m.saturate((sh.roundness - 0.2) / 0.4));
    if (sh.silhouette == .angular) e = @min(e, 0.7);
    return e;
}

// ---------------------------------------------------------------- piece kinds
fn emitPiece(b: *Builder) !void {
    const p = b.piece;
    const sh = b.sh;
    const e = expOf(sh);
    const k = p.scale;
    const C = Builder.v3(p.offset);
    const S = Builder.v3(p.size);
    const crest = @max(sh.crest, 0.025);
    switch (p.kind) {
        .blob => try b.blob(C, S, .{ .exp = p.exponent, .taper = p.taper, .rot = eulerQ(p.tilt[0], p.tilt[1], p.tilt[2]), .color = p.color }),
        .dome_pauldron => {
            var R = S;
            var roll: f32 = 0;
            switch (sh.silhouette) {
                .dome => R = S.scale(1.18),
                .wedge => {
                    R.x *= 1.2;
                    roll = 0.3;
                },
                else => {},
            }
            const q = Quat.fromAxisAngle(Vec3.unit_z, roll);
            try b.blob(C, R, .{ .exp = e, .rot = q, .color = p.color });
            const rim_r = 1.04 + 0.2 * sh.flare;
            try b.part(C, q, Vec3.init(0, R.y * 0.55, 0), Vec3.init(R.x * rim_r, R.y * 0.2, R.z * rim_r), .{ .exp = 0.65, .color = .secondary });
            switch (sh.silhouette) {
                .finned => try b.part(C, q, Vec3.init(0.25 * R.x, -0.9 * R.y, -0.15 * R.z), Vec3.init(0.010, crest * 0.6, R.z * 0.55), .{ .exp = 0.7, .rot = eulerQ(0, 0, 0.5), .color = .trim }),
                .angular => try b.part(C, q, Vec3.init(0.1 * R.x, -0.8 * R.y, 0), Vec3.init(0.012, crest * 0.5 + R.y * 0.35, R.z * 0.9), .{ .exp = 0.7, .color = .trim }),
                .wedge => try b.part(C, q, Vec3.init(0.3 * R.x, 0.85 * R.y, 0), Vec3.init(R.x * 0.75, R.y * 0.4, R.z * 0.8), .{ .exp = e, .color = .trim }),
                else => {},
            }
            if (sh.overlap > 0.3 and sh.silhouette != .wedge) {
                try b.part(C, q, Vec3.init(0.15 * R.x, 0.8 * R.y, 0), Vec3.init(R.x * 0.82, R.y * 0.38, R.z * 0.88), .{ .exp = e, .color = .secondary });
            }
        },
        .fist_guard => {
            const g: f32 = if (sh.silhouette == .dome) 1.12 else 1.0;
            try b.blob(Vec3.init(0, 0.0, 0).scale(k), Vec3.init(0.046, 0.03, 0.042).scale(k), .{ .exp = 0.7, .color = .secondary });
            try b.blob(Vec3.init(0, 0.085, 0).scale(k), Vec3.init(0.05 * g, 0.09, 0.043 * g).scale(k), .{ .exp = e, .color = p.color });
            try b.blob(Vec3.init(0, 0.15, 0).scale(k), Vec3.init(0.054, 0.022, 0.047).scale(k), .{ .exp = 0.65, .color = .trim });
            try b.blob(Vec3.init(0, 0.172, 0).scale(k), Vec3.init(0.03, 0.01, 0.026).scale(k), .{ .color = .glow });
            if (sh.silhouette == .angular or sh.silhouette == .finned) {
                for ([_]f32{ -1, 1 }) |s| {
                    try b.blob(Vec3.init(s * 0.026, 0.168, 0).scale(k), Vec3.init(0.009, 0.03 + crest * 0.6, 0.009).scale(k), .{ .exp = 0.8, .color = .trim, .fit = false });
                }
            }
        },
        .buster_arm => {
            try b.blob(Vec3.init(0, 0.18, 0).scale(k), Vec3.init(0.056, 0.2, 0.056).scale(k), .{ .exp = 0.85, .color = p.color });
            try b.blob(Vec3.init(0, 0.0, 0).scale(k), Vec3.init(0.05, 0.03, 0.05).scale(k), .{ .exp = 0.7, .color = .secondary });
            try b.blob(Vec3.init(0, 0.12, 0).scale(k), Vec3.init(0.062, 0.014, 0.062).scale(k), .{ .exp = 0.7, .color = .secondary });
            try b.blob(Vec3.init(0, 0.25, 0).scale(k), Vec3.init(0.062, 0.014, 0.062).scale(k), .{ .exp = 0.7, .color = .secondary });
            try b.blob(Vec3.init(0, 0.385, 0).scale(k), Vec3.init(0.05, 0.028, 0.05).scale(k), .{ .exp = 0.7, .color = .trim });
            try b.blob(Vec3.init(0, 0.405, 0).scale(k), Vec3.init(0.032, 0.01, 0.032).scale(k), .{ .color = .glow, .fit = false });
            try b.blob(Vec3.init(0.05, 0.17, 0).scale(k), Vec3.init(0.008, 0.07, 0.014).scale(k), .{ .color = .glow });
        },
        .finned_greave => {
            const g: f32 = if (sh.silhouette == .dome) 1.1 else 1.0;
            const taper: f32 = if (sh.silhouette == .wedge) -0.3 else 0;
            try b.blob(Vec3.init(0, 0.2, 0.008).scale(k), Vec3.init(0.05 * g, 0.2, 0.046 * g).scale(k), .{ .exp = e, .taper = taper, .color = p.color });
            try b.blob(Vec3.init(0, 0.01, 0.03).scale(k), Vec3.init(0.046, 0.04, 0.04).scale(k), .{ .exp = e, .color = .secondary });
            try b.blob(Vec3.init(0, 0.385, 0).scale(k), Vec3.init(0.05, 0.022, 0.05).scale(k), .{ .exp = 0.65, .color = .trim });
            switch (sh.silhouette) {
                .finned, .wedge => try b.blob(Vec3.init(0.055 + crest * 0.4, 0.17, -0.01).scale(k), Vec3.init(crest * 0.5 + 0.01, 0.14, 0.012).scale(k), .{ .exp = 0.7, .rot = eulerQ(0, 0.5, 0), .color = .trim, .fit = false }),
                .angular => try b.blob(Vec3.init(0, 0.18, 0.04).scale(k), Vec3.init(0.012, 0.17, 0.02).scale(k), .{ .exp = 0.7, .color = .trim }),
                else => {},
            }
        },
        .thruster_calf => {
            try b.blob(Vec3.init(0, 0.15, -0.058).scale(k), Vec3.init(0.042, 0.12, 0.034).scale(k), .{ .exp = e, .color = p.color });
            try b.blob(Vec3.init(0, 0.285, -0.07).scale(k), Vec3.init(0.03, 0.045, 0.03).scale(k), .{ .exp = 0.8, .taper = 0.55, .color = .dark });
            try b.blob(Vec3.init(0, 0.325, -0.07).scale(k), Vec3.init(0.02, 0.008, 0.02).scale(k), .{ .color = .glow, .fit = false });
            for ([_]f32{ -1, 1 }) |s| {
                try b.blob(Vec3.init(s * 0.04, 0.15, -0.055).scale(k), Vec3.init(0.008, 0.1, 0.02).scale(k), .{ .exp = 0.7, .color = .trim });
            }
        },
        .skirt_plate => {
            // Kick the lower edge out along the dominant horizontal offset.
            const kick = sh.flare * 0.45;
            var q = eulerQ(0, 0, 0);
            if (@abs(C.x) > @abs(C.z)) {
                q = eulerQ(0, 0, -kick * std.math.sign(C.x));
            } else if (C.z != 0) {
                q = eulerQ(kick * std.math.sign(C.z), 0, 0);
            }
            q = q.mul(eulerQ(p.tilt[0], p.tilt[1], p.tilt[2]));
            try b.blob(C, S, .{ .exp = e, .rot = q, .color = p.color });
            try b.part(C, q, Vec3.init(0, S.y * 0.92, 0), Vec3.init(S.x * 1.02, S.y * 0.12, S.z * 1.1), .{ .exp = 0.65, .color = .trim });
        },
        .chest_dome => {
            const fz = frontSurface(b, C);
            const cz = fz + C.z - S.z * 0.35;
            const c = Vec3.init(C.x, C.y, cz);
            var R = S;
            var taper: f32 = 0;
            switch (sh.silhouette) {
                .dome => R = S.scale(1.1),
                .wedge => taper = -0.45,
                else => {},
            }
            try b.blob(c, R, .{ .exp = e, .taper = taper, .color = p.color });
            try b.blob(c.add(Vec3.init(0, -R.y * 0.78, -R.z * 0.15)), Vec3.init(R.x * 0.9, R.y * 0.2, R.z * 0.8), .{ .exp = 0.65, .color = .secondary });
            switch (sh.silhouette) {
                .angular => try b.blob(c.add(Vec3.init(0, 0, R.z * 0.75)), Vec3.init(0.014, R.y * 0.8, 0.02 + crest * 0.4), .{ .exp = 0.7, .color = .trim, .fit = false }),
                .finned => for ([_]f32{ -1, 1 }) |s| {
                    try b.blob(c.add(Vec3.init(s * R.x * 0.95, R.y * 0.4, -R.z * 0.2)), Vec3.init(crest * 0.5, R.y * 0.6, 0.01), .{ .exp = 0.7, .rot = eulerQ(0, 0, -s * 0.4), .color = .trim, .fit = false });
                },
                else => {},
            }
        },
        .core => {
            const fz = frontSurface(b, C) + C.z;
            const r = S.x;
            try b.blob(Vec3.init(C.x, C.y, fz + 0.004), Vec3.init(r, r, 0.012), .{ .exp = 0.8, .color = .trim, .fit = false });
            try b.blob(Vec3.init(C.x, C.y, fz + 0.012), Vec3.init(r * 0.5, r * 0.5, 0.008), .{ .color = .glow, .fit = false });
        },
        .backpack => {
            const bz = backSurface(b, C);
            const cz = bz + C.z - S.z * 0.55;
            const c = Vec3.init(C.x, C.y, cz);
            try b.blob(c, S, .{ .exp = e, .color = p.color });
            for ([_]f32{ -1, 1 }) |s| {
                const nz = Vec3.init(s * S.x * 0.5, -S.y * 1.05, -S.z * 0.2);
                try b.blob(c.add(nz), Vec3.init(0.022, 0.04, 0.022), .{ .exp = 0.85, .taper = -0.5, .color = .dark, .fit = false });
                try b.blob(c.add(nz).add(Vec3.init(0, -0.04, 0)), Vec3.init(0.014, 0.008, 0.014), .{ .color = .glow, .fit = false });
                switch (sh.silhouette) {
                    .finned, .angular, .wedge => try b.blob(c.add(Vec3.init(s * (S.x + crest * 0.5), S.y * 0.5, 0)), Vec3.init(crest * 0.7 + 0.03, S.y * 0.9, 0.008), .{ .exp = 0.7, .rot = eulerQ(0, 0, -s * 0.45), .color = .secondary, .fit = false }),
                    else => {},
                }
            }
        },
        .crest => {
            const L = @max(S.y, crest * 0.5);
            try b.blob(Vec3.init(C.x, 0.145 + C.y, -0.02 + C.z), Vec3.init(S.x, L, S.z), .{ .exp = 0.7, .rot = eulerQ(-0.25, 0, 0), .color = p.color, .fit = false });
            if (sh.silhouette == .finned or sh.silhouette == .dome) {
                try b.blob(Vec3.init(C.x, 0.12 + C.y, 0.06 + C.z), Vec3.init(S.x, L * 0.6, S.z * 0.5), .{ .exp = 0.7, .rot = eulerQ(0.1, 0, 0), .color = .trim, .fit = false });
            }
        },
        .antenna => {
            const L = 0.04 + crest * 0.5;
            const c = Vec3.init(0.045 + C.x, 0.12 + C.y, 0.10 + C.z);
            try b.blob(c, Vec3.init(0.014, 0.014, 0.014), .{ .color = .secondary, .fit = false });
            try b.blob(c.add(Vec3.init(0.02, L * 0.9, 0)), Vec3.init(0.006, L, 0.006), .{ .exp = 0.9, .rot = eulerQ(0, 0, -0.5), .color = p.color, .fit = false });
        },
        .ear_fin => {
            const c = Vec3.init(0.125 + C.x, -0.03 + C.y, -0.02 + C.z);
            try b.blob(c, Vec3.init(0.018, 0.04, 0.035).scale(k), .{ .exp = e, .color = p.color, .fit = false });
            if (sh.crest > 0 or sh.silhouette == .finned or sh.silhouette == .angular) {
                try b.blob(c.add(Vec3.init(0.02, crest * 0.5, -0.03)), Vec3.init(0.006, crest * 0.6, 0.05).scale(k), .{ .exp = 0.7, .rot = eulerQ(-0.5, 0, 0), .color = .trim, .fit = false });
            }
        },
        .collar => {
            try b.blob(Vec3.init(0, -0.012, 0).add(C).scale(k), Vec3.init(0.075, 0.016, 0.07).scale(k), .{ .exp = 0.8, .color = .trim, .fit = false });
            switch (sh.silhouette) {
                .finned, .angular, .wedge => for ([_]f32{ -1, 1 }) |s| {
                    try b.blob(Vec3.init(s * 0.05, 0.03 + crest * 0.3, -0.06).add(C), Vec3.init(0.01, crest * 0.6, 0.04), .{ .exp = 0.7, .rot = eulerQ(0, 0, -s * 0.3), .color = p.color, .fit = false });
                },
                else => {},
            }
        },
        .gem => {
            const center = b.frame.world(b.frame.localPos(C));
            try faceted_gem(b.a, b.ch, b.joint, center, S.x * b.frame.unit, b.ctx.gem, b.ctx.gem_cut);
        },
    }
}

/// Front surface of the torso (local z, reference meters) at a piece offset; falls back to a
/// plausible depth when the envelope is empty.
fn frontSurface(b: *Builder, c: Vec3) f32 {
    return torsoDepth(b, c, true);
}
fn backSurface(b: *Builder, c: Vec3) f32 {
    return torsoDepth(b, c, false);
}
fn torsoDepth(b: *Builder, c: Vec3, front: bool) f32 {
    const f = b.frame;
    const fallback: f32 = if (front) 0.14 else -0.14;
    const env = b.fitter.envelope(b.piece.anchor, b.left, f) orelse return fallback;
    const lp = f.localPos(c);
    const world = f.world(Vec3.init(lp.x, lp.y, 0));
    const s = (world.y - env.a.y) / env.len;
    const dx = (world.x - env.a.x);
    // Angle toward the side the piece sits on; zero is straight ahead.
    const ang_front = std.math.atan2(dx, 0.14);
    const ang = if (front) ang_front else m.pi - ang_front;
    const r = env.radiusAt(s, ang);
    if (r <= 0) return fallback;
    const z = r * @cos(ang_front);
    return ((if (front) z else -z) - f.origin.z) / f.unit;
}

// ---------------------------------------------------------------- gems
fn mixc(a: Rgb, b: Rgb, t: f32) Rgb {
    return .{ .r = a.r + (b.r - a.r) * t, .g = a.g + (b.g - a.g) * t, .b = a.b + (b.b - a.b) * t };
}

/// A set jewel with a raised table and individually coloured radial facets.
fn faceted_gem(a: Allocator, ch: *Character, joint: Joint, center: Vec3, radius: f32, base_color: Rgb, cut: GemCut) !void {
    const colors = [_]Rgb{ mixc(base_color, Rgb.hex(0xffffff), 0.48), base_color, mixc(base_color, Rgb.hex(0x102033), 0.32) };
    var palette: [3]u8 = undefined;
    for (colors, 0..) |c, i| palette[i] = try paletteIndex(a, ch, c);
    const facets: usize = switch (cut) {
        .brilliant => 8,
        .star => 5,
        .teardrop => 6,
    };
    const rx = radius * (if (cut == .teardrop) @as(f32, 0.78) else 1);
    const ry = radius * (if (cut == .teardrop) @as(f32, 1.25) else 0.82);
    const top = center.add(Vec3.init(0, 0, radius * 0.32));
    for (0..facets) |i| {
        const phase: f32 = if (cut == .star) m.pi / 2.0 else 0;
        const a0 = phase + m.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(facets));
        const a1 = phase + m.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(facets));
        const p0 = center.add(Vec3.init(@cos(a0) * rx, @sin(a0) * ry, 0));
        const p1 = center.add(Vec3.init(@cos(a1) * rx, @sin(a1) * ry, 0));
        const shade = palette[i % 3];
        const v0 = try ch.mesh.addVertex(a, .{ .pos = top, .normal = Vec3.unit_z, .joints = .{ joint.idx(), 0, 0, 0 }, .material = .armor });
        const v1 = try ch.mesh.addVertex(a, .{ .pos = p0, .normal = Vec3.unit_z, .joints = .{ joint.idx(), 0, 0, 0 }, .material = .armor });
        const v2 = try ch.mesh.addVertex(a, .{ .pos = p1, .normal = Vec3.unit_z, .joints = .{ joint.idx(), 0, 0, 0 }, .material = .armor });
        try ch.color_index.appendSlice(a, &.{ palette[0], shade, palette[(i + 1) % 3] });
        try ch.mesh.addTri(a, v0, v1, v2);
    }
}

// ---------------------------------------------------------------- set assembly
/// Builds every applicable piece of `def` onto `ch`. Validates first and changes nothing if the
/// def is invalid. Pieces fit to the character as it was when the call began.
pub fn emitSet(a: Allocator, ch: *Character, def: *const ArmorSetDef, ctx: Context) !void {
    try def.validate();
    var fitter: Fitter = .{ .ch = ch, .count = ch.mesh.vertices.items.len };
    for (def.pieces) |*piece| {
        if (!applies(piece.when, ctx)) continue;
        const sides: []const f32 = switch (piece.sides) {
            .both => &.{ 1, -1 },
            .left, .center => &.{1},
            .right => &.{-1},
        };
        for (sides) |side| {
            const left = side > 0;
            var b: Builder = .{
                .a = a,
                .ch = ch,
                .def = def,
                .ctx = ctx,
                .piece = piece,
                .frame = makeFrame(ch, piece.anchor, left, side, ctx),
                .joint = anchorJoint(piece.anchor, left),
                .left = left,
                .side = side,
                .fitter = &fitter,
                .sh = piece.shape orelse def.shape,
            };
            try emitPiece(&b);
        }
    }
}

// ---------------------------------------------------------------- visors
/// Curved lens: a strip bowed toward the viewer, optionally rolled in the face plane.
fn curvedPanel(a: Allocator, ch: *Character, center: Vec3, half_w: f32, half_h: f32, depth: f32, roll: f32, color: Rgb, rows: u32, cols: u32) !void {
    const base = ch.mesh.vertexCount();
    const joint = Joint.head.idx();
    const palette = try paletteIndex(a, ch, color);
    const cr = @cos(roll);
    const sr = @sin(roll);
    for (0..rows + 1) |row| for (0..cols + 1) |column| {
        const v = @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(rows)) * 2 - 1;
        const u = @as(f32, @floatFromInt(column)) / @as(f32, @floatFromInt(cols)) * 2 - 1;
        const width_scale = 1 - 0.10 * v * v;
        const lx = u * half_w * width_scale;
        const ly = v * half_h;
        const x = center.x + lx * cr - ly * sr;
        const y = center.y + lx * sr + ly * cr;
        const z = center.z + depth * (1 - u * u);
        const nl = Vec3.init(2 * depth * u / (half_w * width_scale), 0.18 * v, 1);
        const normal = Vec3.init(nl.x * cr - nl.y * sr, nl.x * sr + nl.y * cr, nl.z).normalize();
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

fn headBlob(a: Allocator, ch: *Character, center: Vec3, radii: Vec3, color: Rgb) !void {
    const rows = 8;
    const cols = 14;
    const first = ch.mesh.vertexCount();
    const palette = try paletteIndex(a, ch, color);
    for (0..rows + 1) |r| for (0..cols) |k| {
        const lat = m.pi * @as(f32, @floatFromInt(r)) / rows;
        const ang = m.tau * @as(f32, @floatFromInt(k)) / cols;
        const n = Vec3.init(@sin(lat) * @cos(ang), @cos(lat), @sin(lat) * @sin(ang));
        _ = try ch.mesh.addVertex(a, .{ .pos = center.add(Vec3.init(n.x * radii.x, n.y * radii.y, n.z * radii.z)), .normal = Vec3.init(n.x / radii.x, n.y / radii.y, n.z / radii.z).normalize(), .joints = .{ Joint.head.idx(), 0, 0, 0 }, .material = .armor });
        try ch.color_index.append(a, palette);
    };
    try ch.mesh.stitchRings(a, first, rows + 1, cols, true, false);
}

/// The face lens for a visor or sealed helmet, plus the cheek plates that frame it. `wrap` is the
/// original ranger visor, kept bit for bit.
pub fn emitVisor(a: Allocator, ch: *Character, shape: VisorShape, metal: Rgb, dark: Rgb, glow: Rgb) !void {
    const lm = ch.landmarks;
    const center = Vec3.init(0, lm.chin_y + 0.47 * lm.H, 0.41 * lm.H);
    const hw = 0.65 * lm.head_half_width;
    const H = lm.H;
    switch (shape) {
        .none => return,
        .wrap => {
            try curvedPanel(a, ch, center, hw, 0.09 * H, 0.04 * H, 0, dark, 8, 24);
            try curvedPanel(a, ch, center.add(Vec3.init(0, 0.04 * H, 0.004 * H)), 0.72 * hw, 0.010 * H, 0.044 * H, 0, glow, 2, 20);
        },
        .slit => {
            try curvedPanel(a, ch, center.add(Vec3.init(0, 0.01 * H, 0)), hw, 0.05 * H, 0.04 * H, 0, dark, 4, 24);
            try curvedPanel(a, ch, center.add(Vec3.init(0, 0.012 * H, 0.004 * H)), 0.8 * hw, 0.008 * H, 0.044 * H, 0, glow, 2, 20);
        },
        .twin => for ([_]f32{ -1, 1 }) |s| {
            const c = center.add(Vec3.init(s * 0.5 * hw, 0.005 * H, 0));
            try curvedPanel(a, ch, c, 0.46 * hw, 0.04 * H, 0.04 * H, -s * 0.22, dark, 3, 12);
            try curvedPanel(a, ch, c.add(Vec3.init(0, 0, 0.004 * H)), 0.34 * hw, 0.011 * H, 0.043 * H, -s * 0.22, glow, 2, 10);
        },
        .mono => {
            try curvedPanel(a, ch, center.add(Vec3.init(0, 0.01 * H, 0)), 0.42 * hw, 0.07 * H, 0.05 * H, 0, dark, 6, 12);
            try curvedPanel(a, ch, center.add(Vec3.init(0, 0.01 * H, 0.004 * H)), 0.2 * hw, 0.03 * H, 0.054 * H, 0, glow, 3, 8);
        },
        .scouter => {
            const c = center.add(Vec3.init(0.38 * hw, 0.01 * H, 0));
            try curvedPanel(a, ch, c, 0.34 * hw, 0.06 * H, 0.05 * H, 0, glow, 5, 10);
            try curvedPanel(a, ch, c.add(Vec3.init(0, 0, 0.004 * H)), 0.26 * hw, 0.04 * H, 0.052 * H, 0, dark, 4, 8);
            // Arm from the lens back to the ear pod.
            try headBlob(a, ch, Vec3.init(lm.head_half_width + 0.004 * H, lm.chin_y + 0.47 * lm.H, 0.2 * H), Vec3.init(0.012 * H, 0.012 * H, 0.2 * H), metal);
        },
    }
    for ([_]f32{ -1, 1 }) |side| {
        try headBlob(a, ch, center.add(Vec3.init(side * hw, -0.01 * H, -0.018 * H)), Vec3.init(0.035 * H, 0.12 * H, 0.045 * H), metal);
    }
}

// ---------------------------------------------------------------- the built-in sets
const rim_dark = Rgb.hex(0x17242f);

// -- plain armor: scout, rootweave and skyguard pods. Offsets keep the original hand-tuned
// ellipsoid positions, now expressed as data in the limb frames.
const pod = struct {
    fn chest(bulk: f32) [2]Piece {
        return .{
            .{ .kind = .blob, .anchor = .chest, .when = .bare, .offset = .{ 0.09, 0.005, 0.075 }, .size = .{ 0.105, 0.16, 0.09 * bulk }, .material = .cloth_outer, .fit = false },
            .{ .kind = .blob, .anchor = .chest, .sides = .center, .when = .bare, .offset = .{ 0, 0.01, -0.09 }, .size = .{ 0.15, 0.20, 0.095 }, .color = .dark, .material = .cloth_outer, .fit = false },
        };
    }
};

const scout_pieces = pod.chest(1) ++ [_]Piece{
    .{ .kind = .blob, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.06, -0.185 }, .size = .{ 0.038, 0.10, 0.012 }, .color = .accent, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.045, 0.168 }, .size = .{ 0.027, 0.058, 0.009 }, .color = .accent, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .upper_arm, .when = .bare, .offset = .{ 0, 0.04, 0 }, .size = .{ 0.105, 0.105, 0.105 }, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .forearm, .when = .bare, .offset = .{ 0, 0.12, 0.035 }, .size = .{ 0.060, 0.12, 0.065 }, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .shin, .when = .bare, .offset = .{ 0, 0.02, 0.055 }, .size = .{ 0.071, 0.09, 0.055 }, .material = .cloth_outer, .fit = false },
};

const sentinel_pieces = pod.chest(1.15) ++ [_]Piece{
    .{ .kind = .blob, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.06, -0.185 }, .size = .{ 0.038, 0.10, 0.012 }, .color = .accent, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.045, 0.168 }, .size = .{ 0.027, 0.058, 0.009 }, .color = .accent, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .upper_arm, .when = .bare, .offset = .{ 0, 0.04, 0 }, .size = .{ 0.121, 0.121, 0.105 }, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .forearm, .when = .bare, .offset = .{ 0, 0.12, 0.035 }, .size = .{ 0.060, 0.12, 0.065 }, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .shin, .when = .bare, .offset = .{ 0, 0.02, 0.055 }, .size = .{ 0.071, 0.09, 0.055 }, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .thigh, .when = .bare, .offset = .{ 0.035, 0.16, 0.04 }, .size = .{ 0.090, 0.15, 0.075 }, .material = .cloth_outer, .fit = false },
    .{ .kind = .blob, .anchor = .shin, .when = .bare, .offset = .{ 0, 0.21, 0.025 }, .size = .{ 0.061, 0.16, 0.069 }, .material = .cloth_outer, .fit = false },
};

const rootweave_pieces = scout_pieces ++ [_]Piece{
    .{ .kind = .blob, .anchor = .upper_arm, .offset = .{ 0.025, -0.02, 0.035 }, .size = .{ 0.13, 0.075, 0.105 }, .fit = false },
    .{ .kind = .blob, .anchor = .forearm, .offset = .{ 0.035, 0, 0.025 }, .size = .{ 0.070, 0.16, 0.065 }, .color = .secondary, .fit = false },
    .{ .kind = .blob, .anchor = .chest, .offset = .{ 0.065, -0.035, 0.153 }, .size = .{ 0.012, 0.13, 0.010 }, .color = .accent, .fit = false },
};

const skyguard_pieces = scout_pieces ++ [_]Piece{
    .{ .kind = .blob, .anchor = .upper_arm, .offset = .{ 0.045, -0.03, 0 }, .size = .{ 0.15, 0.055, 0.08 }, .fit = false },
    .{ .kind = .blob, .anchor = .forearm, .offset = .{ 0.022, 0.025, 0.026 }, .size = .{ 0.046, 0.14, 0.036 }, .color = .secondary, .fit = false },
    .{ .kind = .blob, .anchor = .shin, .offset = .{ 0, 0.025, 0.045 }, .size = .{ 0.055, 0.12, 0.04 }, .fit = false },
    .{ .kind = .blob, .anchor = .forearm, .offset = .{ 0.018, -0.035, 0.061 }, .size = .{ 0.008, 0.085, 0.006 }, .color = .accent, .fit = false },
};

/// The chest jewel (setting plus cut stone) and two small stones, then the set's own pods.
fn gemKit(comptime extra: []const Piece) [extra.len + 3]Piece {
    const base = [_]Piece{
        .{ .kind = .blob, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.045, 0.177 }, .size = .{ 0.071, 0.071, 0.014 }, .color = .secondary, .material = .metal, .fit = false },
        .{ .kind = .gem, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.045, 0.192 }, .size = .{ 0.056, 0.056, 0.056 } },
        .{ .kind = .gem, .anchor = .chest, .offset = .{ 0.145, 0.075, 0.12 }, .size = .{ 0.022, 0.022, 0.022 } },
    };
    var out: [extra.len + 3]Piece = undefined;
    for (base, 0..) |p, i| out[i] = p;
    for (extra, 0..) |p, i| out[base.len + i] = p;
    return out;
}

const gem_aegis_pieces = scout_pieces ++ gemKit(&.{
    .{ .kind = .blob, .anchor = .upper_arm, .offset = .{ 0.025, -0.03, 0.012 }, .size = .{ 0.105, 0.065, 0.075 }, .fit = false },
    .{ .kind = .blob, .anchor = .forearm, .offset = .{ 0, 0, 0.035 }, .size = .{ 0.052, 0.12, 0.046 }, .fit = false },
});

const starforge_pieces = scout_pieces ++ gemKit(&.{
    .{ .kind = .blob, .anchor = .upper_arm, .offset = .{ 0.045, -0.04, 0.01 }, .size = .{ 0.16, 0.08, 0.095 }, .fit = false },
    .{ .kind = .blob, .anchor = .hips, .offset = .{ 0.11, -0.015, 0.025 }, .size = .{ 0.075, 0.10, 0.065 }, .fit = false },
});

const deep_prism_pieces = scout_pieces ++ gemKit(&.{
    .{ .kind = .blob, .anchor = .upper_arm, .offset = .{ 0.04, -0.04, 0.01 }, .size = .{ 0.13, 0.075, 0.09 }, .fit = false },
    .{ .kind = .blob, .anchor = .forearm, .offset = .{ 0, 0, 0.036 }, .size = .{ 0.064, 0.145, 0.055 }, .fit = false },
    .{ .kind = .blob, .anchor = .shin, .offset = .{ 0, 0.02, 0.042 }, .size = .{ 0.075, 0.14, 0.05 }, .fit = false },
});

// -- mecha sets built from the shaped pieces.
const mobile_suit_shape: ShapeSpec = .{ .silhouette = .angular, .flare = 0.35, .crest = 0.045, .roundness = 0.35, .overlap = 0.6 };
const mobile_suit_pieces = [_]Piece{
    .{ .kind = .dome_pauldron, .anchor = .upper_arm, .offset = .{ 0.04, -0.03, 0 }, .size = .{ 0.10, 0.085, 0.105 } },
    .{ .kind = .fist_guard, .anchor = .hand },
    .{ .kind = .finned_greave, .anchor = .shin },
    .{ .kind = .skirt_plate, .anchor = .thigh, .offset = .{ 0.015, 0.07, 0.09 }, .size = .{ 0.075, 0.095, 0.02 } },
    .{ .kind = .skirt_plate, .anchor = .hips, .offset = .{ 0.19, -0.09, 0 }, .size = .{ 0.022, 0.085, 0.075 }, .color = .secondary, .fit = false },
    .{ .kind = .skirt_plate, .anchor = .hips, .offset = .{ 0.06, -0.07, -0.16 }, .size = .{ 0.07, 0.08, 0.02 }, .fit = false },
    .{ .kind = .chest_dome, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.04, 0 }, .size = .{ 0.15, 0.12, 0.075 } },
    .{ .kind = .core, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.0, 0.02 }, .size = .{ 0.034, 0.034, 0.034 } },
    .{ .kind = .collar, .anchor = .neck, .sides = .center, .color = .metal },
    .{ .kind = .backpack, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.02, 0 }, .size = .{ 0.095, 0.115, 0.05 } },
    .{ .kind = .antenna, .anchor = .head, .when = .sealed, .color = .trim },
    .{ .kind = .crest, .anchor = .head, .sides = .center, .when = .sealed, .size = .{ 0.009, 0.045, 0.1 }, .color = .secondary },
    .{ .kind = .ear_fin, .anchor = .head, .when = .helmeted, .color = .metal },
};

const buster_shape: ShapeSpec = .{ .silhouette = .round, .flare = 0.1, .crest = 0.05, .roundness = 1.0, .overlap = 0.0 };
const buster_pieces = [_]Piece{
    .{ .kind = .buster_arm, .anchor = .forearm, .sides = .left },
    .{ .kind = .fist_guard, .anchor = .hand, .sides = .right },
    .{ .kind = .dome_pauldron, .anchor = .upper_arm, .offset = .{ 0.035, -0.025, 0 }, .size = .{ 0.085, 0.07, 0.085 } },
    .{ .kind = .chest_dome, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.035, 0 }, .size = .{ 0.13, 0.11, 0.06 } },
    .{ .kind = .core, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.04, 0.015 }, .size = .{ 0.03, 0.03, 0.03 } },
    .{ .kind = .skirt_plate, .anchor = .hips, .offset = .{ 0.19, -0.08, 0 }, .size = .{ 0.025, 0.07, 0.07 }, .color = .secondary, .fit = false },
    .{ .kind = .finned_greave, .anchor = .shin, .shape = .{ .silhouette = .round, .roundness = 1 } },
    .{ .kind = .crest, .anchor = .head, .sides = .center, .when = .sealed, .size = .{ 0.012, 0.05, 0.11 }, .shape = .{ .silhouette = .finned, .crest = 0.06, .roundness = 1 } },
    .{ .kind = .ear_fin, .anchor = .head, .when = .helmeted, .color = .secondary, .shape = .{ .silhouette = .round, .roundness = 1 } },
};

const iron_titan_shape: ShapeSpec = .{ .silhouette = .angular, .flare = 0.55, .crest = 0.07, .roundness = 0.2, .overlap = 0.3 };
const iron_titan_pieces = [_]Piece{
    .{ .kind = .dome_pauldron, .anchor = .upper_arm, .offset = .{ 0.045, -0.035, 0 }, .size = .{ 0.11, 0.09, 0.11 }, .shape = .{ .silhouette = .finned, .flare = 0.4, .crest = 0.09, .roundness = 0.25 } },
    .{ .kind = .fist_guard, .anchor = .hand },
    .{ .kind = .finned_greave, .anchor = .shin, .shape = .{ .silhouette = .finned, .flare = 0.5, .crest = 0.075, .roundness = 0.2 } },
    .{ .kind = .thruster_calf, .anchor = .shin },
    .{ .kind = .chest_dome, .anchor = .chest, .offset = .{ 0.075, 0.05, 0 }, .size = .{ 0.085, 0.085, 0.06 }, .color = .secondary },
    .{ .kind = .chest_dome, .anchor = .chest, .sides = .center, .offset = .{ 0, -0.07, 0 }, .size = .{ 0.13, 0.07, 0.06 } },
    .{ .kind = .skirt_plate, .anchor = .thigh, .offset = .{ 0.0, 0.08, 0.07 }, .size = .{ 0.08, 0.1, 0.02 } },
    .{ .kind = .collar, .anchor = .neck, .sides = .center, .color = .metal },
    .{ .kind = .backpack, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.03, 0 }, .size = .{ 0.10, 0.12, 0.05 }, .shape = .{ .silhouette = .finned, .crest = 0.12, .roundness = 0.3 } },
    .{ .kind = .antenna, .anchor = .head, .when = .sealed, .color = .metal, .offset = .{ 0.03, 0.01, -0.02 }, .shape = .{ .silhouette = .finned, .crest = 0.14 } },
    .{ .kind = .ear_fin, .anchor = .head, .when = .helmeted, .color = .trim },
};

const battle_plate_shape: ShapeSpec = .{ .silhouette = .wedge, .flare = 0.45, .crest = 0.06, .roundness = 0.55, .overlap = 0.2 };
const battle_plate_pieces = [_]Piece{
    .{ .kind = .dome_pauldron, .anchor = .upper_arm, .offset = .{ 0.05, -0.04, 0 }, .size = .{ 0.115, 0.07, 0.11 } },
    .{ .kind = .chest_dome, .anchor = .chest, .sides = .center, .offset = .{ 0, 0.03, 0 }, .size = .{ 0.17, 0.12, 0.05 } },
    .{ .kind = .skirt_plate, .anchor = .hips, .sides = .center, .offset = .{ 0, -0.07, 0.16 }, .size = .{ 0.075, 0.09, 0.02 }, .fit = false },
    .{ .kind = .skirt_plate, .anchor = .hips, .sides = .center, .offset = .{ 0, -0.07, -0.16 }, .size = .{ 0.075, 0.09, 0.02 }, .fit = false },
    .{ .kind = .blob, .anchor = .forearm, .offset = .{ 0, 0.16, 0 }, .size = .{ 0.052, 0.03, 0.05 }, .exponent = 0.7, .color = .trim },
    .{ .kind = .blob, .anchor = .shin, .offset = .{ 0, 0.34, 0 }, .size = .{ 0.054, 0.03, 0.052 }, .exponent = 0.7, .color = .trim },
    .{ .kind = .ear_fin, .anchor = .head, .sides = .left, .when = .helmeted, .color = .trim, .shape = .{ .silhouette = .round, .crest = 0.03 } },
};

/// The built-in sets, in the order of the `Profile.Armor` tags they match.
pub const builtin_sets = [_]ArmorSetDef{
    .{ .name = "none", .title = "No armor", .metal = Rgb.hex(0x71868e), .secondary = Rgb.hex(0x71868e), .trim = Rgb.hex(0x17242f) },
    .{ .name = "scout", .title = "Scout", .metal = Rgb.hex(0x71868e), .secondary = Rgb.hex(0x425c3c), .trim = Rgb.hex(0x17242f), .pieces = &scout_pieces },
    .{ .name = "sentinel", .title = "Sentinel", .metal = Rgb.hex(0xc1cbd0), .secondary = Rgb.hex(0x71868e), .trim = Rgb.hex(0x17242f), .shape = .{ .silhouette = .dome, .roundness = 0.6 }, .pieces = &sentinel_pieces },
    .{ .name = "rootweave", .title = "Rootweave", .metal = Rgb.hex(0x66815a), .secondary = Rgb.hex(0x425c3c), .trim = Rgb.hex(0x17242f), .shape = .{ .silhouette = .round, .overlap = 0.4 }, .pieces = &rootweave_pieces },
    .{ .name = "skyguard", .title = "Skyguard", .metal = Rgb.hex(0x477b88), .secondary = Rgb.hex(0x31535f), .trim = Rgb.hex(0x17242f), .shape = .{ .silhouette = .wedge, .flare = 0.25, .crest = 0.03 }, .pieces = &skyguard_pieces },
    .{ .name = "gem_aegis", .title = "Gem Aegis", .metal = Rgb.hex(0x9baebc), .secondary = Rgb.hex(0x263b4d), .trim = Rgb.hex(0x17242f), .pieces = &gem_aegis_pieces },
    .{ .name = "starforge", .title = "Starforge", .metal = Rgb.hex(0x8d719f), .secondary = Rgb.hex(0x263b4d), .trim = Rgb.hex(0x17242f), .shape = .{ .silhouette = .angular, .crest = 0.03, .roundness = 0.5 }, .pieces = &starforge_pieces },
    .{ .name = "deep_prism", .title = "Deep Prism", .metal = Rgb.hex(0x397982), .secondary = Rgb.hex(0x263b4d), .trim = Rgb.hex(0x17242f), .shape = .{ .silhouette = .dome }, .pieces = &deep_prism_pieces },
    .{ .name = "mobile_suit", .title = "Mobile Suit", .metal = Rgb.hex(0xe9edf4), .secondary = Rgb.hex(0x2d4f9e), .trim = Rgb.hex(0xc8232c), .dark = Rgb.hex(0x1b2430), .shape = mobile_suit_shape, .visor = .twin, .pieces = &mobile_suit_pieces },
    .{ .name = "buster", .title = "Buster", .metal = Rgb.hex(0x2f6fd6), .secondary = Rgb.hex(0x4cc4f0), .trim = Rgb.hex(0x14285c), .dark = Rgb.hex(0x101c38), .shape = buster_shape, .visor = .slit, .pieces = &buster_pieces },
    .{ .name = "iron_titan", .title = "Iron Titan", .metal = Rgb.hex(0xb0262c), .secondary = Rgb.hex(0x2a4d9c), .trim = Rgb.hex(0xc9d0d8), .dark = Rgb.hex(0x222831), .shape = iron_titan_shape, .visor = .slit, .pieces = &iron_titan_pieces },
    .{ .name = "battle_plate", .title = "Battle Plate", .metal = Rgb.hex(0xf1ead2), .secondary = Rgb.hex(0x2a3c78), .trim = Rgb.hex(0xd9a93a), .dark = Rgb.hex(0x232a40), .shape = battle_plate_shape, .visor = .scouter, .pieces = &battle_plate_pieces },
};

// ---------------------------------------------------------------- tests
fn testCharacter(gpa: Allocator, build_scale: f32) !Character {
    var s: spec_mod.CharacterSpec = .{ .detail = 0.7 };
    s.body.height = 1.8 * build_scale;
    return Character.build(gpa, s);
}

test "built-in sets validate, have unique names and fit the piece budget" {
    try validateAll(&builtin_sets);
    for (builtin_sets) |d| try std.testing.expect(d.pieces.len <= max_pieces);
}

test "validation rejects broken defs and never panics on them" {
    const ok: ArmorSetDef = .{ .name = "x", .metal = Rgb.hex(0xffffff), .secondary = Rgb.hex(0xffffff), .trim = Rgb.hex(0xffffff) };
    try ok.validate();
    var bad = ok;
    bad.name = "";
    try std.testing.expectError(error.EmptyName, bad.validate());
    bad.name = "Upper Case";
    try std.testing.expectError(error.BadName, bad.validate());
    bad = ok;
    bad.shape.roundness = 2;
    try std.testing.expectError(error.BadShape, bad.validate());
    bad.shape = .{ .crest = std.math.nan(f32) };
    try std.testing.expectError(error.BadShape, bad.validate());
    bad = ok;
    bad.metal = .{ .r = 5, .g = 0, .b = 0 };
    try std.testing.expectError(error.BadColor, bad.validate());
    bad = ok;
    const huge = [_]Piece{.{ .kind = .blob, .anchor = .chest, .size = .{ 3, 0.1, 0.1 } }};
    bad.pieces = &huge;
    try std.testing.expectError(error.BadPiece, bad.validate());
    const lonely = [_]Piece{.{ .kind = .blob, .anchor = .forearm, .sides = .center }};
    bad.pieces = &lonely;
    try std.testing.expectError(error.BadPiece, bad.validate());
    const dup = [_]ArmorSetDef{ ok, ok };
    try std.testing.expectError(error.DuplicateName, validateAll(&dup));
    // An invalid def changes nothing on a character.
    const gpa = std.testing.allocator;
    var ch = try testCharacter(gpa, 1);
    defer ch.deinit(gpa);
    const before = ch.mesh.vertices.items.len;
    bad.pieces = &huge;
    try std.testing.expectError(error.BadPiece, emitSet(gpa, &ch, &bad, .{}));
    try std.testing.expectEqual(before, ch.mesh.vertices.items.len);
}

fn armorBounds(ch: *const Character, first: usize) struct { min: Vec3, max: Vec3 } {
    var lo = Vec3.splat(std.math.floatMax(f32));
    var hi = Vec3.splat(-std.math.floatMax(f32));
    for (ch.mesh.vertices.items[first..]) |v| {
        lo = lo.min(v.pos);
        hi = hi.max(v.pos);
    }
    return .{ .min = lo, .max = hi };
}

test "every built-in set emits finite, rigid, outward-wound, bounded armor on tall and small bodies" {
    const gpa = std.testing.allocator;
    for ([_]f32{ 1.0, 0.9 }) |height| {
        for (&builtin_sets) |*def| {
            var ch = try testCharacter(gpa, height);
            defer ch.deinit(gpa);
            const first = ch.mesh.vertices.items.len;
            const first_index = ch.mesh.indices.items.len;
            try emitSet(gpa, &ch, def, .{ .scale = height, .helmet = .sealed });
            try std.testing.expectEqual(ch.mesh.vertices.items.len, ch.color_index.items.len);
            for (ch.mesh.vertices.items[first..]) |v| {
                // Rigid: one joint, full weight.
                try std.testing.expectEqual(@as(f32, 1), v.weights[0]);
                try std.testing.expectEqual(@as(f32, 0), v.weights[1] + v.weights[2] + v.weights[3]);
                for ([_]f32{ v.pos.x, v.pos.y, v.pos.z, v.normal.x, v.normal.y, v.normal.z }) |c| try std.testing.expect(std.math.isFinite(c));
                try std.testing.expect(@abs(v.normal.length() - 1) < 1e-3);
            }
            for (ch.mesh.indices.items[first_index..]) |i| try std.testing.expect(i < ch.mesh.vertices.items.len);
            if (ch.mesh.vertices.items.len == first) continue;
            // Bounded: armor stays within a body-sized box around the character.
            const bb = armorBounds(&ch, first);
            const h = ch.landmarks.height;
            try std.testing.expect(bb.min.y > -0.1 * h and bb.max.y < 1.2 * h);
            try std.testing.expect(bb.min.x > -0.6 * h and bb.max.x < 0.6 * h);
            try std.testing.expect(bb.min.z > -0.6 * h and bb.max.z < 0.6 * h);
            // Winding agrees with normals on the great majority of triangles (degenerate pole
            // triangles carry no area and are skipped).
            var agree: usize = 0;
            var total: usize = 0;
            var t: usize = first_index;
            while (t + 2 < ch.mesh.indices.items.len) : (t += 3) {
                const p0 = ch.mesh.vertices.items[ch.mesh.indices.items[t]];
                const p1 = ch.mesh.vertices.items[ch.mesh.indices.items[t + 1]];
                const p2 = ch.mesh.vertices.items[ch.mesh.indices.items[t + 2]];
                const n = p1.pos.sub(p0.pos).cross(p2.pos.sub(p0.pos));
                if (n.length() < 1e-9) continue;
                const avg = p0.normal.add(p1.normal).add(p2.normal);
                total += 1;
                if (n.dot(avg) > 0) agree += 1;
            }
            // Gem facets are flat fans and the visors are panels, so allow a margin.
            try std.testing.expect(total == 0 or agree * 100 >= total * 90);
        }
    }
}

test "fitted limb and trunk pieces stay outside the body at rest" {
    // One fitted piece per shaped kind on each limb; the vertices that belong to fitted parts
    // (everything but the free-standing glow discs and fins) must clear the body envelope.
    const gpa = std.testing.allocator;
    const probe_pieces = [_]Piece{
        .{ .kind = .dome_pauldron, .anchor = .upper_arm, .offset = .{ 0.04, -0.03, 0 }, .size = .{ 0.10, 0.085, 0.105 } },
        .{ .kind = .buster_arm, .anchor = .forearm },
        .{ .kind = .fist_guard, .anchor = .hand },
        .{ .kind = .skirt_plate, .anchor = .thigh, .offset = .{ 0.015, 0.07, 0.09 }, .size = .{ 0.075, 0.095, 0.02 } },
        .{ .kind = .finned_greave, .anchor = .shin },
        .{ .kind = .thruster_calf, .anchor = .shin },
    };
    for (std.enums.values(spec_mod.Silhouette)) |sil| {
        const def: ArmorSetDef = .{ .name = "probe", .metal = Rgb.hex(0xffffff), .secondary = Rgb.hex(0x888888), .trim = Rgb.hex(0x444444), .shape = .{ .silhouette = sil, .crest = 0.06, .flare = 0.4 }, .pieces = &probe_pieces };
        var ch = try testCharacter(gpa, 1);
        defer ch.deinit(gpa);
        const first = ch.mesh.vertices.items.len;
        try emitSet(gpa, &ch, &def, .{});
        var fitter: Fitter = .{ .ch = &ch, .count = first };
        var inside: usize = 0;
        var total: usize = 0;
        for ([_]Anchor{ .upper_arm, .forearm, .thigh, .shin }) |anchor| {
            const frame = makeFrame(&ch, anchor, true, 1, .{});
            const env = fitter.envelope(anchor, true, frame).?;
            for (ch.mesh.vertices.items[first..]) |v| {
                if (v.joints[0] != anchorJoint(anchor, true).idx()) continue;
                const rel = v.pos.sub(env.a);
                const s = rel.dot(env.axis) / env.len;
                if (s < -0.3 or s > 1.3) continue;
                const radial = rel.sub(env.axis.scale(rel.dot(env.axis)));
                const body_r = env.radiusAt(s, std.math.atan2(radial.dot(env.e2), radial.dot(env.e1)));
                total += 1;
                if (radial.length() < body_r - 0.003) inside += 1;
            }
        }
        try std.testing.expect(total > 500);
        // Free-standing fins and glow discs are outside the body by construction, so the fitted
        // bulk dominates; allow a sliver for envelope bin edges.
        try std.testing.expect(inside * 50 <= total);
    }
}

test "different sets and different shapes produce visibly different silhouettes" {
    const gpa = std.testing.allocator;
    var extents: [builtin_sets.len]Vec3 = undefined;
    var counts: [builtin_sets.len]usize = undefined;
    for (&builtin_sets, 0..) |*def, i| {
        var ch = try testCharacter(gpa, 1);
        defer ch.deinit(gpa);
        const first = ch.mesh.vertices.items.len;
        try emitSet(gpa, &ch, def, .{ .helmet = .sealed });
        counts[i] = ch.mesh.vertices.items.len - first;
        const bb = armorBounds(&ch, first);
        extents[i] = if (counts[i] == 0) Vec3.zero else bb.max.sub(bb.min);
    }
    // The four mecha sets all add geometry and no two share the same overall outline.
    for (8..builtin_sets.len) |i| {
        try std.testing.expect(counts[i] > 1500);
        for (8..i) |j| {
            const d = extents[i].sub(extents[j]);
            try std.testing.expect(@abs(d.x) + @abs(d.y) + @abs(d.z) > 0.01 or counts[i] != counts[j]);
        }
    }
    // The same pauldron under the five silhouettes gives five different meshes.
    var seen: [5]f32 = undefined;
    for (std.enums.values(spec_mod.Silhouette), 0..) |sil, i| {
        const set: ArmorSetDef = .{
            .name = "probe",
            .metal = Rgb.hex(0xffffff),
            .secondary = Rgb.hex(0x888888),
            .trim = Rgb.hex(0x444444),
            .shape = .{ .silhouette = sil, .crest = 0.08, .flare = 0.5, .roundness = 0.3, .overlap = 0.5 },
            .pieces = &.{.{ .kind = .dome_pauldron, .anchor = .upper_arm, .offset = .{ 0.04, -0.03, 0 }, .size = .{ 0.1, 0.085, 0.105 } }},
        };
        var ch = try testCharacter(gpa, 1);
        defer ch.deinit(gpa);
        const first = ch.mesh.vertices.items.len;
        try emitSet(gpa, &ch, &set, .{});
        var acc: f32 = 0;
        for (ch.mesh.vertices.items[first..]) |v| acc += v.pos.x * 0.37 + v.pos.y * 0.73 + v.pos.z * 0.11;
        seen[i] = acc;
    }
    for (0..5) |i| for (0..i) |j| try std.testing.expect(@abs(seen[i] - seen[j]) > 1e-3);
}

test "armor is deterministic" {
    const gpa = std.testing.allocator;
    var hashes: [2]u64 = undefined;
    for (&hashes) |*h| {
        var ch = try testCharacter(gpa, 1);
        defer ch.deinit(gpa);
        try emitSet(gpa, &ch, &builtin_sets[8], .{ .helmet = .sealed });
        h.* = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(ch.mesh.vertices.items));
    }
    try std.testing.expectEqual(hashes[0], hashes[1]);
}
