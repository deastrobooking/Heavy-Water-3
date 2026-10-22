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

/// Head and face shape as plain data. Lengths are fractions of the head height (`H`) unless noted;
/// the face landmarks (eyes, nose, mouth) live in `EyeSpec` as heights in face UV (0 chin, 1 crown).
/// A face is just a value of this struct, so mods can define one in data. See `face_presets`.
pub const HeadSpec = struct {
    /// Skull width at its widest point, as a fraction of `H`.
    cranium_width: f32 = 0.88,
    /// Skull front-to-back depth, as a fraction of `H`.
    cranium_depth: f32 = 0.96,
    /// Uniform multiplier on the whole skull (1 = default). Above 1 gives a fuller forehead and dome.
    cranium_size: f32 = 1.0,
    /// Width at the cheekbones relative to the skull (1 = as wide as the skull).
    cheek_width: f32 = 1.0,
    /// Cheekbone height in face UV (0 chin, 1 crown); places the cheek relief.
    cheek_height: f32 = 0.30,
    /// 0 = round or boxy jaw, 1 = sharp V jaw.
    jaw_taper: f32 = 0.35,
    /// Width of the chin base relative to the skull before taper and point are applied.
    chin_width: f32 = 0.40,
    /// 0 = broad rounded chin, 1 = narrow point.
    chin_point: f32 = 0.25,
    /// How far the chin sits forward of the default slope, as a fraction of `H` (negative recedes).
    chin_jut: f32 = 0.0,
    /// Neck height from shoulder line to chin, in body units (`height / 6.3`). Anime necks are short.
    neck_length: f32 = 0.22,
    /// Neck girth multiplier (1 = default).
    neck_thickness: f32 = 1.0,
    /// Brow ridge relief, fraction of `H`. Small: the brow mostly reads from the decal.
    brow_ridge: f32 = 0.010,
    /// Cheek pad relief, fraction of `H`.
    cheek_fullness: f32 = 0.014,
    /// Nose bridge relief, fraction of `H`. The nose is a tiny bridge plus a shadow mark, not a bump.
    nose_bridge: f32 = 0.006,
    /// Nose tip relief, fraction of `H`.
    nose_tip: f32 = 0.014,

    /// Number of keyframes in `profile`.
    pub const key_count = 7;

    /// Keyframed outline of the head, chin to temple. `us` are heights in face UV; `half_w` is the
    /// half width and `front`/`back` the face and skull surface z (forward positive), in units of
    /// `H`. This is the single place a face shape becomes geometry.
    pub const Profile = struct {
        us: [key_count]f32,
        half_w: [key_count]f32,
        front: [key_count]f32,
        back: [key_count]f32,
    };

    pub fn profile(h: HeadSpec) Profile {
        const half = 0.5 * h.cranium_width * h.cranium_size;
        const d = 0.5 * h.cranium_depth * h.cranium_size;
        const t = std.math.clamp(h.jaw_taper, 0, 1);
        const pt = std.math.clamp(h.chin_point, 0, 1);
        const jut = h.chin_jut;
        const jaw = m.lerp(0.78, 0.56, t);
        // Anime chins are short and soft: the base stays wide and deep until the point is raised.
        const chin = h.chin_width * m.lerp(1.0, 0.55, pt) * m.lerp(1.0, 0.8, t);
        const cheek = h.cheek_width;
        return .{
            .us = .{ 0.11, 0.17, 0.26, 0.37, 0.50, 0.62, 0.72 },
            .half_w = .{
                half * chin,
                half * jaw * cheek,
                half * cheek * m.lerp(0.94, 0.84, t),
                half * cheek * m.lerp(0.99, 0.95, t),
                half,
                half * 1.02,
                half * 0.96,
            },
            .front = .{ d * 0.52 + jut, d * 0.78 + jut * 0.8, d * 0.92 + jut * 0.3, d * 0.99, d, d * 0.99, d * 0.94 },
            .back = .{ -d * 0.55, -d * 0.72, -d * 0.87, -d * 0.96, -d, -d, -d * 0.97 },
        };
    }
};

pub const BodySpec = struct {
    height: f32 = 1.58,
    /// Heads tall. Chibi ~2.5-3.5, anime action heroes ~5.5-6.5, realistic ~7-8.
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
    /// Head and face shape (skull, cheek, jaw, chin, neck).
    head: HeadSpec = .{},
    /// Hand and foot size multipliers; large hands and feet read well at gameplay distance.
    hand_scale: f32 = 1.15,
    foot_scale: f32 = 1.1,
    /// Arm angle below horizontal in the rest pose (A-pose), radians.
    arm_rest_angle: f32 = m.radians(40),
};

/// Eyes plus the other flat face marks (brows, nose shadow, mouth), all drawn as decals.
pub const EyeSpec = struct {
    /// Eye size as a fraction of face width. Anime: big.
    size: f32 = 0.24,
    /// Height / width of the eye opening.
    aspect: f32 = 1.15,
    /// Vertical position in the face UV (0 chin, 1 crown). About 0.55 down from the crown.
    height: f32 = 0.45,
    /// Horizontal distance from face center (face UV units).
    spacing: f32 = 0.20,
    tilt: f32 = 0.08,
    iris_color: Rgb = Rgb.hex(0x4a7fd6),
    iris_dark: Rgb = Rgb.hex(0x1d2b6b),
    pupil_size: f32 = 0.38,
    highlight_count: u8 = 2,
    /// Brow height above the top of the eye, in face UV.
    brow_gap: f32 = 0.045,
    /// Brow stroke length as a multiple of the eye width.
    brow_length: f32 = 1.05,
    /// Brow stroke thickness at the inner end, in face UV.
    brow_weight: f32 = 0.011,
    /// Brow slope: positive lowers the inner end (determined, fierce), negative raises it (gentle).
    brow_tilt: f32 = 0.12,
    /// Nose tip height in face UV (0 chin, 1 crown); also places the relief on the mesh.
    nose_height: f32 = 0.29,
    /// Opacity of the nose shadow mark (0 hides it).
    nose_mark: f32 = 0.45,
    /// Mouth line height in face UV.
    mouth_height: f32 = 0.19,
    /// Mouth half width in face UV.
    mouth_width: f32 = 0.06,
    /// Upper-lid cut: 0 = the round anime opening, toward 1 a flat lid that slants down to the
    /// inner corner (calm, cool or sharp eyes). Drawn per fragment, so it reaches the shader.
    lid: f32 = 0.0,
    /// Brow curve: positive arches the middle up, negative bows it down (face UV).
    brow_arch: f32 = 0.0,
    /// A painted, scarred or freckled mark over the skin, drawn per fragment under the eyes.
    mark: FaceMark = .none,
    /// Paint colour for the marks that take one (war paint, tech seams).
    mark_color: Rgb = Rgb.hex(0x30e0ff),
};

/// Face marks, in the order of `game/Profile.zig` (which re-exports this type); append only.
pub const FaceMark = enum { none, freckles, scar, war_paint, beauty_mark, tech_seams, tear_lines };

/// A named face: head shape for each presentation, eye shape and the head ratio that goes with
/// it. The table is comptime data; add a row (and a `Profile.FaceStyle` tag) to add a face.
pub const FacePreset = struct {
    name: []const u8,
    masculine: HeadSpec = .{},
    feminine: HeadSpec = .{},
    /// Heads tall for a human with this face.
    head_ratio: f32 = 6.3,
    eye_size_scale: f32 = 1.0,
    eye_aspect_scale: f32 = 1.0,
    /// Outer-corner lift of the eyes (negative droops toward the temple).
    eye_tilt: f32 = 0.06,
    eye_height_add: f32 = 0.0,
    /// Brow and mouth overrides; see `EyeSpec`.
    brow_weight: f32 = 0.011,
    brow_tilt: f32 = 0.12,
    brow_gap: f32 = 0.045,
    nose_mark: f32 = 0.45,
    mouth_width: f32 = 0.06,
    /// Eye shape and expression; see `EyeSpec.lid` and `EyeSpec.brow_arch`.
    eye_lid: f32 = 0.0,
    brow_arch: f32 = 0.0,
    /// Catch-lights in each iris (1 or 2).
    highlights: u8 = 1,
    /// Added to the resting smile (-1 frown .. 1 smile) the presentation gives.
    smile: f32 = 0.0,
};

/// In the order of `game/Profile.zig` `FaceStyle`; a test keeps the two in step.
pub const face_presets = [_]FacePreset{
    .{
        .name = "classic",
        .masculine = .{ .jaw_taper = 0.35, .chin_point = 0.25, .neck_thickness = 1.05 },
        .feminine = .{ .cranium_width = 0.85, .jaw_taper = 0.62, .chin_point = 0.42, .neck_length = 0.24, .neck_thickness = 0.88 },
        .head_ratio = 6.3,
        .eye_lid = 0.1,
        .brow_arch = 0.004,
    },
    .{
        .name = "soft",
        .masculine = .{ .cranium_width = 0.92, .cranium_size = 1.03, .cheek_width = 1.02, .jaw_taper = 0.12, .chin_point = 0.05, .cheek_fullness = 0.018 },
        .feminine = .{ .cranium_width = 0.90, .cranium_size = 1.03, .cheek_width = 1.02, .jaw_taper = 0.2, .chin_point = 0.1, .cheek_fullness = 0.018, .neck_length = 0.24, .neck_thickness = 0.88 },
        .head_ratio = 5.9,
        .eye_size_scale = 1.08,
        .eye_aspect_scale = 1.1,
        .eye_tilt = 0.03,
        .brow_weight = 0.009,
        .brow_tilt = 0.0,
        .brow_gap = 0.055,
        .brow_arch = 0.008,
        .highlights = 2,
        .smile = 0.12,
    },
    .{
        .name = "angular",
        .masculine = .{ .cranium_width = 0.84, .jaw_taper = 0.85, .chin_point = 0.7, .chin_jut = 0.02, .cheek_width = 0.98, .brow_ridge = 0.013 },
        .feminine = .{ .cranium_width = 0.82, .jaw_taper = 0.88, .chin_point = 0.75, .chin_jut = 0.02, .cheek_width = 0.98, .neck_length = 0.24, .neck_thickness = 0.86 },
        .head_ratio = 6.5,
        .eye_size_scale = 0.94,
        .eye_aspect_scale = 0.86,
        .eye_tilt = 0.12,
        .brow_weight = 0.012,
        .brow_tilt = 0.28,
        .nose_mark = 0.55,
        .eye_lid = 0.35,
        .brow_arch = -0.003,
    },
    .{
        .name = "heroic",
        .masculine = .{ .cranium_width = 0.90, .jaw_taper = 0.45, .chin_width = 0.46, .chin_point = 0.3, .chin_jut = 0.02, .brow_ridge = 0.013, .neck_thickness = 1.1 },
        .feminine = .{ .cranium_width = 0.86, .jaw_taper = 0.55, .chin_point = 0.35, .chin_jut = 0.015, .neck_length = 0.24, .neck_thickness = 0.9 },
        .head_ratio = 6.4,
        .eye_size_scale = 0.96,
        .eye_height_add = 0.01,
        .eye_tilt = 0.09,
        .brow_weight = 0.013,
        .brow_tilt = 0.2,
        .eye_lid = 0.18,
        .brow_arch = 0.004,
        .highlights = 2,
    },
    .{
        .name = "alien",
        .masculine = .{ .cranium_width = 0.82, .cranium_depth = 0.92, .cranium_size = 1.06, .jaw_taper = 0.7, .chin_point = 0.6, .nose_bridge = 0.0, .nose_tip = 0.004, .neck_length = 0.26 },
        .feminine = .{ .cranium_width = 0.80, .cranium_depth = 0.92, .cranium_size = 1.06, .jaw_taper = 0.75, .chin_point = 0.65, .nose_bridge = 0.0, .nose_tip = 0.004, .neck_length = 0.28, .neck_thickness = 0.85 },
        .head_ratio = 6.0,
        .eye_size_scale = 1.12,
        .eye_aspect_scale = 1.3,
        .eye_tilt = 0.14,
        .brow_weight = 0.006,
        .brow_tilt = -0.1,
        .nose_mark = 0.0,
        .mouth_width = 0.04,
        .brow_arch = 0.01,
        .highlights = 2,
    },
    // Dragon Ball Z hero: square strong jaw, short thick neck, heavy angled brows, sharp upswept eyes.
    .{
        .name = "hero",
        .masculine = .{ .cranium_depth = 0.98, .jaw_taper = 0.28, .chin_width = 0.50, .chin_point = 0.1, .chin_jut = 0.03, .brow_ridge = 0.015, .neck_length = 0.18, .neck_thickness = 1.18 },
        .feminine = .{ .cranium_width = 0.86, .jaw_taper = 0.45, .chin_width = 0.44, .chin_point = 0.2, .chin_jut = 0.02, .brow_ridge = 0.012, .neck_length = 0.2, .neck_thickness = 0.95 },
        .head_ratio = 6.1,
        .eye_aspect_scale = 0.84,
        .eye_tilt = 0.16,
        .brow_weight = 0.016,
        .brow_tilt = 0.36,
        .brow_gap = 0.035,
        .nose_mark = 0.6,
        .mouth_width = 0.055,
        .eye_lid = 0.42,
        .highlights = 2,
        .smile = -0.1,
    },
    // Young lead: round small-chinned head, big tall eyes set low, a ready smile.
    .{
        .name = "youthful",
        .masculine = .{ .cranium_width = 0.92, .cranium_size = 1.05, .jaw_taper = 0.4, .chin_width = 0.36, .chin_point = 0.35, .cheek_fullness = 0.017, .neck_thickness = 0.95 },
        .feminine = .{ .cranium_width = 0.90, .cranium_size = 1.05, .jaw_taper = 0.55, .chin_width = 0.34, .chin_point = 0.45, .cheek_fullness = 0.017, .neck_length = 0.24, .neck_thickness = 0.86 },
        .head_ratio = 5.6,
        .eye_size_scale = 1.16,
        .eye_aspect_scale = 1.12,
        .eye_tilt = 0.04,
        .eye_height_add = -0.015,
        .brow_weight = 0.008,
        .brow_tilt = 0.02,
        .brow_gap = 0.05,
        .brow_arch = 0.008,
        .nose_mark = 0.35,
        .mouth_width = 0.05,
        .highlights = 2,
        .smile = 0.25,
    },
    // Aristocrat: long narrow face, almond eyes under fine high-arched brows.
    .{
        .name = "noble",
        .masculine = .{ .cranium_width = 0.83, .cranium_depth = 0.98, .cheek_width = 0.97, .cheek_height = 0.33, .jaw_taper = 0.68, .chin_point = 0.5, .chin_jut = 0.01, .neck_length = 0.25 },
        .feminine = .{ .cranium_width = 0.81, .cheek_width = 0.97, .cheek_height = 0.33, .jaw_taper = 0.75, .chin_point = 0.6, .neck_length = 0.27, .neck_thickness = 0.84 },
        .head_ratio = 6.5,
        .eye_size_scale = 0.92,
        .eye_aspect_scale = 0.8,
        .eye_tilt = 0.1,
        .brow_weight = 0.008,
        .brow_tilt = 0.06,
        .brow_gap = 0.05,
        .brow_arch = 0.014,
        .nose_mark = 0.5,
        .mouth_width = 0.05,
        .eye_lid = 0.3,
        .smile = -0.05,
    },
    // Veteran: broad square jaw, heavy straight brows low over small hooded eyes.
    .{
        .name = "rugged",
        .masculine = .{ .cranium_width = 0.92, .cheek_width = 1.03, .jaw_taper = 0.08, .chin_width = 0.54, .chin_point = 0.05, .chin_jut = 0.025, .brow_ridge = 0.018, .nose_bridge = 0.009, .neck_length = 0.19, .neck_thickness = 1.2 },
        .feminine = .{ .cranium_width = 0.88, .cheek_width = 1.02, .jaw_taper = 0.3, .chin_width = 0.46, .chin_point = 0.15, .chin_jut = 0.015, .brow_ridge = 0.014, .neck_length = 0.21, .neck_thickness = 0.98 },
        .head_ratio = 6.5,
        .eye_size_scale = 0.86,
        .eye_aspect_scale = 0.8,
        .eye_tilt = 0.03,
        .eye_height_add = 0.008,
        .brow_weight = 0.018,
        .brow_tilt = 0.08,
        .brow_gap = 0.022,
        .brow_arch = -0.002,
        .nose_mark = 0.7,
        .mouth_width = 0.066,
        .eye_lid = 0.5,
        .smile = -0.2,
    },
    // Rival: narrow sharp eyes with a steep outer lift, brows slashed down to the nose.
    .{
        .name = "fierce",
        .masculine = .{ .cranium_width = 0.86, .jaw_taper = 0.72, .chin_point = 0.55, .chin_jut = 0.015, .cheek_width = 0.99, .brow_ridge = 0.014 },
        .feminine = .{ .cranium_width = 0.84, .jaw_taper = 0.8, .chin_point = 0.65, .chin_jut = 0.01, .neck_length = 0.24, .neck_thickness = 0.86 },
        .head_ratio = 6.3,
        .eye_size_scale = 1.0,
        .eye_aspect_scale = 0.78,
        .eye_tilt = 0.22,
        .brow_weight = 0.014,
        .brow_tilt = 0.42,
        .brow_gap = 0.03,
        .nose_mark = 0.5,
        .mouth_width = 0.055,
        .eye_lid = 0.6,
        .highlights = 2,
        .smile = 0.05,
    },
    // Healer: soft jaw, eyes drooping toward the temple under raised, worried brows.
    .{
        .name = "gentle",
        .masculine = .{ .cranium_width = 0.9, .cheek_width = 1.01, .jaw_taper = 0.25, .chin_point = 0.15, .cheek_fullness = 0.016 },
        .feminine = .{ .cranium_width = 0.88, .cheek_width = 1.01, .jaw_taper = 0.4, .chin_point = 0.25, .cheek_fullness = 0.016, .neck_length = 0.24, .neck_thickness = 0.88 },
        .head_ratio = 6.1,
        .eye_size_scale = 1.04,
        .eye_aspect_scale = 0.95,
        .eye_tilt = -0.07,
        .brow_weight = 0.009,
        .brow_tilt = -0.18,
        .brow_gap = 0.055,
        .brow_arch = 0.006,
        .nose_mark = 0.4,
        .mouth_width = 0.052,
        .eye_lid = 0.22,
        .highlights = 2,
        .smile = 0.2,
    },
    // Soldier: level eyes and level brows, a short flat mouth, nothing given away.
    .{
        .name = "stoic",
        .masculine = .{ .cranium_width = 0.88, .jaw_taper = 0.3, .chin_width = 0.48, .chin_point = 0.2, .brow_ridge = 0.014, .neck_thickness = 1.1 },
        .feminine = .{ .cranium_width = 0.85, .jaw_taper = 0.5, .chin_point = 0.35, .brow_ridge = 0.011, .neck_length = 0.23, .neck_thickness = 0.9 },
        .head_ratio = 6.4,
        .eye_size_scale = 0.94,
        .eye_aspect_scale = 0.82,
        .eye_tilt = 0.0,
        .brow_weight = 0.014,
        .brow_tilt = 0.02,
        .brow_gap = 0.03,
        .brow_arch = -0.004,
        .nose_mark = 0.55,
        .mouth_width = 0.048,
        .eye_lid = 0.45,
        .smile = -0.3,
    },
};

pub const HairStyle = enum { bob, long_straight, twin_tails, short_spiky, ponytail, bun, braids, curly, undercut, mohawk, short_curly, curly_fade, curly_coils, afro, long_curls, textured_crop, locs, swept_back, layered_shag, nova_spike, alien_crown, crew_cut, side_part, spiky_hero, widow_flame, fringe_spikes, super_flare, flip_bob, pilot_sweep, big_fringe, topknot, spike_tail, crown_braid, tempest_sweep };

/// Data-driven styles are described by `hair_style.StyleDef`; see `hair_library.zig`.
const hair_style = @import("hair_style.zig");

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
    /// Replaces the built-in definition of `style` (a mod's hairstyle). Must outlive the build.
    custom: ?*const hair_style.StyleDef = null,
    /// Adjustments for data-driven styles, 1 = as authored: spike tips and standing height,
    /// root lift and clump width, and overall length.
    spike_scale: f32 = 1,
    volume_scale: f32 = 1,
    length_scale: f32 = 1,
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

/// Overall outline of a hard-surface plate, the first thing the eye reads on a mecha silhouette.
/// `round` is the plain domed plate; `angular` flattens the dome into a keel ridge and facets;
/// `finned` raises fins along the outer sides; `dome` swells the plate into a shell; `wedge`
/// tapers a keel to a point toward the plate's far edge.
pub const Silhouette = enum { round, angular, finned, dome, wedge };

/// How a hard-surface garment (and the standalone armor pieces in `armor.zig`) is shaped. The
/// defaults reproduce the plain domed plate, so a garment that does not set a shape is unchanged.
pub const ShapeSpec = struct {
    silhouette: Silhouette = .round,
    /// Flare of each plate's far edge, 0 = none, 1 = strongly kicked out (a skirt or bell hem).
    flare: f32 = 0.0,
    /// Fin, keel or crest height in meters on a 1.8 m body (scaled with the body).
    crest: f32 = 0.0,
    /// 0 = boxy and chamfered, 0.6 and up = fully round. Also softens plate rims.
    roundness: f32 = 0.6,
    /// 0 = plates butt with a visible gap, 1 = each plate rides up over the next.
    overlap: f32 = 0.0,
};

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
    /// Hard garments: silhouette, flare, crest height, bevel and plate overlap.
    shape: ShapeSpec = .{},
    /// Hard garments: plate count along the limb (or abdomen bands for a cuirass), separated by
    /// small gaps so the armor articulates; 0 or 1 = one piece.
    segments: u8 = 0,
    /// Scale the protected span of a hard-surface plate. Values below 1 expose more of the
    /// undersuit; values above 1 extend coverage while keeping the plate centered on its limb.
    coverage_extent: f32 = 1.0,
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

test "every face preset yields an ordered, finite head profile with human head ratios" {
    for (face_presets) |fp| {
        try std.testing.expect(fp.head_ratio >= 5.5 and fp.head_ratio <= 6.5);
        try std.testing.expect(fp.highlights >= 1 and fp.highlights <= 2 and fp.eye_lid >= 0 and fp.eye_lid <= 0.8);
        for ([_]HeadSpec{ fp.masculine, fp.feminine }) |h| {
            const pr = h.profile();
            for (0..HeadSpec.key_count) |i| {
                if (i > 0) try std.testing.expect(pr.us[i] > pr.us[i - 1]);
                try std.testing.expect(pr.half_w[i] > 0.05 and pr.half_w[i] < 0.6);
                try std.testing.expect(pr.front[i] > pr.back[i] + 0.1);
            }
            // The chin is narrower than the cheek, and the skull is at least as wide as the chin.
            try std.testing.expect(pr.half_w[0] < pr.half_w[3]);
        }
    }
    // Jaw taper and chin point narrow the chin; a forward jut moves its front out.
    const round: HeadSpec = .{ .jaw_taper = 0, .chin_point = 0 };
    const sharp: HeadSpec = .{ .jaw_taper = 1, .chin_point = 1, .chin_jut = 0.05 };
    try std.testing.expect(sharp.profile().half_w[0] < round.profile().half_w[0]);
    try std.testing.expect(sharp.profile().front[0] > round.profile().front[0]);
}
