//! Character description. Everything visible is derived from these numbers.
//! Lengths are in meters; most proportions are expressed in *head units*
//! (head height = height / head_ratio), which is how anime model sheets work.

const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;

pub const Rgb = struct {
    r: f32,
    g: f32,
    b: f32,
    pub fn init(r: f32, g: f32, b: f32) Rgb {
        return .{ .r = r, .g = g, .b = b };
    }
    pub fn hex(comptime v: u24) Rgb {
        return .{
            .r = @as(f32, @floatFromInt((v >> 16) & 0xff)) / 255.0,
            .g = @as(f32, @floatFromInt((v >> 8) & 0xff)) / 255.0,
            .b = @as(f32, @floatFromInt(v & 0xff)) / 255.0,
        };
    }
};

pub const BodySpec = struct {
    height: f32 = 1.58,
    /// Heads tall. Chibi ~2.5-3.5, shoujo/idol ~6-6.5, action/realistic ~7-8.
    head_ratio: f32 = 6.3,
    /// 0 = masculine (broad shoulders, narrow hips), 1 = feminine.
    femininity: f32 = 1.0,
    /// Crotch height / height. Anime legs are long: ~0.48-0.52.
    leg_ratio: f32 = 0.49,
    /// Multipliers on default widths (1 = default).
    shoulder_width: f32 = 1.0,
    waist_width: f32 = 1.0,
    hip_width: f32 = 1.0,
    limb_thickness: f32 = 1.0,
    /// 0 = flat, 1 = pronounced.
    bust: f32 = 0.45,
    /// Head shape: width relative to head height, jaw taper (0 round, 1 sharp V).
    head_width: f32 = 0.80,
    jaw_sharpness: f32 = 0.70,
    /// Arm angle below horizontal in the rest pose (A-pose), radians.
    arm_rest_angle: f32 = m.radians(40),
};

pub const EyeSpec = struct {
    /// Eye size as a fraction of face width. Anime: big.
    size: f32 = 0.24,
    /// Height / width of the eye opening.
    aspect: f32 = 1.15,
    /// Vertical position in the face UV (0 chin, 1 crown).
    height: f32 = 0.44,
    /// Horizontal distance from face center (face UV units).
    spacing: f32 = 0.20,
    tilt: f32 = 0.08,
    iris_color: Rgb = Rgb.hex(0x4a7fd6),
    iris_dark: Rgb = Rgb.hex(0x1d2b6b),
    pupil_size: f32 = 0.38,
    highlight_count: u8 = 2,
};

pub const HairStyle = enum { bob, long_straight, twin_tails, short_spiky };

pub const HairSpec = struct {
    /// The single antenna strand on top.
    ahoge: bool = true,
    style: HairStyle = .long_straight,
    color: Rgb = Rgb.hex(0x2b2140),
    /// Number of bang clumps across the forehead.
    bang_count: u8 = 7,
    /// Length of back hair in head units.
    length: f32 = 2.4,
    /// 0 = smooth, 1 = very spiky clump tips.
    spikiness: f32 = 0.35,
    /// How far clumps stand off the scalp (volume).
    volume: f32 = 1.0,
    /// Horizontal part offset (-1..1, 0 = center).
    part: f32 = 0.15,
    /// Random seed for per-clump variation.
    seed: u64 = 0x5eed,
    /// Spring-bone joints per dynamic clump chain (0 = static hair).
    chain_joints: u8 = 4,
};

pub const GarmentKind = enum {
    /// Offset shell over selected body regions (shirts, leggings, socks, gloves).
    shell,
    /// Lofted cone from the waist (skirts). Weighted to hips/thighs + spring chains.
    skirt,
};

pub const Coverage = enum {
    // shell presets
    tshirt,
    long_sleeve,
    tank,
    shorts,
    leggings,
    thigh_highs,
    shoes,
    gloves,
    // hard-surface armor presets (use with `hard = true`)
    /// Chest and abdomen shell with a high collar; `segments` splits the abdomen into bands.
    cuirass,
    /// Shoulder caps over the top of the upper arm.
    pauldrons,
    /// Forearm plates between elbow and wrist.
    vambraces,
    /// Armored hands and wrist cuffs.
    gauntlets,
    /// Hip plates over the belt line and upper thigh.
    faulds,
    /// Thigh plates.
    cuisses,
    /// Shin plates.
    greaves,
    /// Armored boots.
    sabatons,
    // skirt presets
    skirt,
};

pub const Neckline = enum { crew, v, high };

pub const GarmentSpec = struct {
    kind: GarmentKind = .shell,
    coverage: Coverage = .tshirt,
    color: Rgb = Rgb.hex(0xffffff),
    /// Layer order: larger = further out. Offset = layer * layer_step + looseness.
    layer: u8 = 1,
    /// Extra standoff from the body in meters (baggy clothes).
    looseness: f32 = 0.0,
    /// Hard-surface armor: every vertex binds rigidly to its dominant joint (plates move, they
    /// do not stretch), plates dome outward by `bulge` toward their centers, and rims thicken.
    hard: bool = false,
    bulge: f32 = 0.006,
    /// Hard garments: plate count along the limb (or abdomen bands for a cuirass), separated by
    /// small gaps so the armor articulates; 0 or 1 = one piece.
    segments: u8 = 0,
    /// Skirt: length below waist in body units (height / 6.3), flare (hem radius / hip radius).
    length: f32 = 1.1,
    flare: f32 = 1.75,
    /// Tops: neckline shape.
    neckline: Neckline = .crew,
    /// Skirt: number of pleats (0 = smooth), pleat depth in meters.
    pleats: u8 = 16,
    pleat_depth: f32 = 0.012,
};

pub const CharacterSpec = struct {
    body: BodySpec = .{},
    eyes: EyeSpec = .{},
    hair: HairSpec = .{},
    skin: Rgb = Rgb.hex(0xffe3d3),
    outfit: []const GarmentSpec = &.{},
    /// Tessellation density multiplier (LODs: 0.5, 1, 2).
    detail: f32 = 1.0,

    pub fn headHeight(s: CharacterSpec) f32 {
        return s.body.height / s.body.head_ratio;
    }
    /// Ring/column counts scaled by detail; never below `lo`.
    pub fn res(s: CharacterSpec, base: u32, lo: u32) u32 {
        const v: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(base)) * s.detail));
        return @max(lo, v);
    }
};

/// A ready-made outfit: school uniform (sailor-style top, pleated skirt, thigh-highs).
pub const school_uniform = [_]GarmentSpec{
    .{ .coverage = .thigh_highs, .color = Rgb.hex(0x1c1c28), .layer = 1 },
    .{ .coverage = .shoes, .color = Rgb.hex(0x5a3426), .layer = 2, .looseness = 0.006 },
    .{ .coverage = .long_sleeve, .color = Rgb.hex(0xf4f4f8), .layer = 1, .looseness = 0.004, .neckline = .v },
    .{ .kind = .skirt, .coverage = .skirt, .color = Rgb.hex(0x2b3a67), .layer = 3, .length = 1.05, .flare = 1.8, .pleats = 18 },
};

test "head units" {
    const s: CharacterSpec = .{};
    try std.testing.expectApproxEqAbs(s.body.height / 6.3, s.headHeight(), 1e-6);
}
