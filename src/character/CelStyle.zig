//! Cel style: every number the character shader reads, per material, as plain data.
//!
//! This file is pure on purpose. It holds no GPU handles, pointers, slices or allocators, so a
//! mod loader can read and write it as a table of numbers and names, `validate` rejects values
//! the shader cannot draw, and `pack` produces the exact uniform the GPU path uploads. The CPU
//! reference (`toon.shadeCel`) and `render/skin_lit.wgsl` / `skin_hull.wgsl` read the same
//! fields, so what artists tune here is what both paths draw.
//!
//! Colours are linear RGB triples. Tints multiply the base colour; 1.0 leaves it unchanged.

const std = @import("std");
const enum_compat = @import("enum_compat");
const mesh = @import("mesh.zig");

pub const Material = mesh.Material;
pub const material_count = enum_compat.fields(Material).len;
pub const Rgb3 = [3]f32;

/// How light turns into shadow on one material.
pub const Ramp = struct {
    /// N.L at which the lit band ends and the shadow band begins.
    threshold: f32,
    /// Half-width of the terminator blur. 0.01 is a crisp anime edge, 0.1 a soft airbrushed one.
    softness: f32,
    /// Colour multiplier in the shadow band. A cool, saturated tint reads as anime; plain
    /// darkening reads as 3D.
    shadow_tint: Rgb3,
    /// N.L at which the shadow band gives way to the deep core shadow. Keep it at or below
    /// `threshold`; set it to -1 to disable the deep band.
    deep_threshold: f32,
    deep_tint: Rgb3,
};

/// A bright band on silhouette edges that face the light.
pub const Rim = struct {
    /// Fraction of the view-facing falloff the band covers (0 = none, 0.5 = wide).
    width: f32,
    /// Added fraction of the base colour.
    strength: f32,
};

/// A hard highlight: N.H crosses a threshold and a flat band of `tint` appears in the lit area.
pub const Specular = struct {
    /// N.H above which the band shows. Near 1 gives a small glint, 0.8 a broad sheen.
    threshold: f32,
    softness: f32,
    /// 0 turns the band off.
    strength: f32,
    tint: Rgb3,
};

/// Ink line drawn by the inverted hull behind the character.
pub const Outline = struct {
    /// Line width in screen pixels at the reference view; 0 draws no line for this material.
    width_px: f32,
    /// Ink colour as a multiplier of the base colour: a dark tint of it, not black.
    tint: Rgb3,
};

pub const MaterialStyle = struct {
    ramp: Ramp,
    rim: Rim,
    specular: Specular,
    outline: Outline,
    /// 0..1: mixes the material toward an unlit glowing base colour (lumen strips, visors).
    emissive: f32,
};

pub const CelStyle = struct {
    /// Indexed by `@intFromEnum(Material)`. Materials a character never uses are still read, so
    /// keep every entry valid.
    materials: [material_count]MaterialStyle,
    /// Softness of the face shadow terminator (the face shadow map threshold blur).
    face_softness: f32,
    /// Multiplies every outline width; 0 hides all character ink.
    outline_scale: f32,
    /// World-space limits on the extrusion, in metres. They stop far characters getting fat
    /// lines and close-ups getting hairlines (same role as `toon.outlineWidth`'s limits).
    outline_min_world: f32,
    outline_max_world: f32,

    pub fn get(self: *const CelStyle, material: Material) *const MaterialStyle {
        return &self.materials[@intFromEnum(material)];
    }

    pub const Error = error{ NotFinite, OutOfRange, DeepAboveLit };

    /// Rejects styles the shader cannot draw sensibly. A rejected style must not be uploaded.
    pub fn validate(self: *const CelStyle) Error!void {
        try range(self.face_softness, 0.001, 0.5);
        try range(self.outline_scale, 0, 8);
        try range(self.outline_min_world, 0, 0.1);
        try range(self.outline_max_world, self.outline_min_world, 0.1);
        for (self.materials) |s| {
            try range(s.ramp.threshold, -1, 1);
            try range(s.ramp.softness, 0.001, 0.5);
            try range(s.ramp.deep_threshold, -1, 1);
            if (s.ramp.deep_threshold > s.ramp.threshold) return error.DeepAboveLit;
            try rgb(s.ramp.shadow_tint);
            try rgb(s.ramp.deep_tint);
            try range(s.rim.width, 0, 0.6);
            try range(s.rim.strength, 0, 2);
            try range(s.specular.threshold, 0, 1);
            try range(s.specular.softness, 0.001, 0.5);
            try range(s.specular.strength, 0, 2);
            try rgb(s.specular.tint);
            try range(s.outline.width_px, 0, 12);
            try rgb(s.outline.tint);
            try range(s.emissive, 0, 1);
        }
    }

    fn range(x: f32, lo: f32, hi: f32) Error!void {
        if (!std.math.isFinite(x)) return error.NotFinite;
        if (x < lo or x > hi) return error.OutOfRange;
    }
    fn rgb(c: Rgb3) Error!void {
        for (c) |x| try range(x, 0, 2);
    }
};

/// Debug views for tuning, packed into the uniform header. Not part of a style.
pub const Debug = packed struct(u8) {
    /// Hide the ink lines.
    outline_off: bool = false,
    /// Show the bands as flat colours: lit white, shadow blue, deep violet, highlight yellow,
    /// rim red.
    ramp_view: bool = false,
    /// Show the face shadow mask on face vertices as a flat black/white.
    face_mask_view: bool = false,
    _pad: u5 = 0,
};

// ----------------------------------------------------------------------------- GPU table

pub const header_vec4s = 2;
pub const vec4s_per_material = 6;
pub const table_vec4s = header_vec4s + material_count * vec4s_per_material;
/// The uniform the skinned pipeline reads (`render/skin.wgsl`, `CelTable`).
pub const Table = [table_vec4s][4]f32;
pub const table_bytes = @sizeOf(Table);

/// Lays a style out for the GPU. Header: [0] = outline_scale, outline_min, outline_max, debug
/// bits; [1] = face_softness. Each material then takes six vec4s:
///   0 threshold, softness, deep_threshold, rim.width
///   1 shadow_tint.rgb, rim.strength
///   2 deep_tint.rgb, specular.threshold
///   3 specular.tint.rgb, specular.strength
///   4 outline.tint.rgb, outline.width_px
///   5 specular.softness, emissive, 0, 0
pub fn pack(style: *const CelStyle, debug: Debug) Table {
    var t: Table = undefined;
    t[0] = .{ style.outline_scale, style.outline_min_world, style.outline_max_world, @floatFromInt(@as(u8, @bitCast(debug))) };
    t[1] = .{ style.face_softness, 0, 0, 0 };
    for (style.materials, 0..) |s, i| {
        const b = header_vec4s + i * vec4s_per_material;
        t[b] = .{ s.ramp.threshold, s.ramp.softness, s.ramp.deep_threshold, s.rim.width };
        t[b + 1] = .{ s.ramp.shadow_tint[0], s.ramp.shadow_tint[1], s.ramp.shadow_tint[2], s.rim.strength };
        t[b + 2] = .{ s.ramp.deep_tint[0], s.ramp.deep_tint[1], s.ramp.deep_tint[2], s.specular.threshold };
        t[b + 3] = .{ s.specular.tint[0], s.specular.tint[1], s.specular.tint[2], s.specular.strength };
        t[b + 4] = .{ s.outline.tint[0], s.outline.tint[1], s.outline.tint[2], s.outline.width_px };
        t[b + 5] = .{ s.specular.softness, s.emissive, 0, 0 };
    }
    return t;
}

/// Reads one material back out of a packed table exactly as the shader does.
pub fn unpack(t: *const Table, material: Material) MaterialStyle {
    const b = header_vec4s + @as(usize, @intFromEnum(material)) * vec4s_per_material;
    return .{
        .ramp = .{ .threshold = t[b][0], .softness = t[b][1], .deep_threshold = t[b][2], .shadow_tint = .{ t[b + 1][0], t[b + 1][1], t[b + 1][2] }, .deep_tint = .{ t[b + 2][0], t[b + 2][1], t[b + 2][2] } },
        .rim = .{ .width = t[b][3], .strength = t[b + 1][3] },
        .specular = .{ .threshold = t[b + 2][3], .softness = t[b + 5][0], .strength = t[b + 3][3], .tint = .{ t[b + 3][0], t[b + 3][1], t[b + 3][2] } },
        .outline = .{ .width_px = t[b + 4][3], .tint = .{ t[b + 4][0], t[b + 4][1], t[b + 4][2] } },
        .emissive = t[b + 5][1],
    };
}

// ----------------------------------------------------------------------------- presets

const white: Rgb3 = .{ 1, 1, 1 };
const no_spec: Specular = .{ .threshold = 0.95, .softness = 0.02, .strength = 0, .tint = white };

fn base(ramp: Ramp) MaterialStyle {
    return .{
        .ramp = ramp,
        .rim = .{ .width = 0.22, .strength = 0.3 },
        .specular = no_spec,
        .outline = .{ .width_px = 1.6, .tint = .{ 0.30, 0.24, 0.26 } },
        .emissive = 0,
    };
}

/// The house look: the warm key / cool shadow of the scene ramp, with crisp bands.
pub const heavy_water: CelStyle = blk: {
    var s: CelStyle = .{ .materials = undefined, .face_softness = 0.04, .outline_scale = 1, .outline_min_world = 0.0006, .outline_max_world = 0.02 };
    const cloth_ramp: Ramp = .{ .threshold = 0.30, .softness = 0.05, .shadow_tint = .{ 0.74, 0.72, 0.90 }, .deep_threshold = -0.10, .deep_tint = .{ 0.56, 0.54, 0.76 } };
    for (&s.materials) |*m| m.* = base(cloth_ramp);
    const set = struct {
        fn at(style: *CelStyle, material: Material, value: MaterialStyle) void {
            style.materials[@intFromEnum(material)] = value;
        }
    }.at;
    // Skin: a soft, warm-to-cool shadow with a pink core, thin ink, faint rim.
    var skin = base(.{ .threshold = 0.18, .softness = 0.12, .shadow_tint = .{ 0.84, 0.68, 0.74 }, .deep_threshold = -0.20, .deep_tint = .{ 0.66, 0.52, 0.64 } });
    skin.rim = .{ .width = 0.20, .strength = 0.16 };
    skin.outline = .{ .width_px = 1.1, .tint = .{ 0.42, 0.26, 0.26 } };
    set(&s, .skin, skin);
    // Hair: two clean bands and a hard banded sheen across the crown; thin ink.
    var hair = base(.{ .threshold = 0.25, .softness = 0.04, .shadow_tint = .{ 0.70, 0.66, 0.88 }, .deep_threshold = -0.15, .deep_tint = .{ 0.52, 0.48, 0.74 } });
    hair.specular = .{ .threshold = 0.90, .softness = 0.018, .strength = 0.55, .tint = .{ 0.80, 0.74, 0.70 } };
    hair.outline = .{ .width_px = 1.0, .tint = .{ 0.30, 0.24, 0.30 } };
    set(&s, .hair, hair);
    // Eyes sit under the face decal: nearly flat and unlined.
    var eye = base(.{ .threshold = -0.5, .softness = 0.2, .shadow_tint = .{ 0.92, 0.92, 0.96 }, .deep_threshold = -1, .deep_tint = white });
    eye.rim = .{ .width = 0, .strength = 0 };
    eye.outline.width_px = 0;
    set(&s, .eye_white, eye);
    set(&s, .iris, eye);
    // Cloth: wide soft bands, a little rim, medium ink.
    var cloth = base(cloth_ramp);
    cloth.outline = .{ .width_px = 1.4, .tint = .{ 0.30, 0.26, 0.34 } };
    set(&s, .cloth_top, cloth);
    set(&s, .cloth_bottom, cloth);
    set(&s, .cloth_outer, cloth);
    var shoes = cloth;
    shoes.outline.width_px = 1.6;
    set(&s, .shoes, shoes);
    // Accents and lumen strips glow slightly.
    var accent = cloth;
    accent.emissive = 0.35;
    accent.outline.width_px = 1.0;
    set(&s, .accent, accent);
    // Armor: hard two-step ramp, a hard specular band, a hard rim, and crisp thick ink.
    var armor = base(.{ .threshold = 0.28, .softness = 0.02, .shadow_tint = .{ 0.62, 0.64, 0.84 }, .deep_threshold = -0.08, .deep_tint = .{ 0.42, 0.44, 0.66 } });
    armor.rim = .{ .width = 0.30, .strength = 0.42 };
    armor.specular = .{ .threshold = 0.86, .softness = 0.012, .strength = 0.50, .tint = .{ 0.95, 0.92, 0.86 } };
    armor.outline = .{ .width_px = 2.4, .tint = .{ 0.20, 0.20, 0.28 } };
    set(&s, .armor, armor);
    // Other hard-surface materials share the armor treatment so beasts and props read alike.
    var metal = armor;
    metal.specular.strength = 0.65;
    set(&s, .metal, metal);
    set(&s, .paint, armor);
    set(&s, .paint_accent, armor);
    set(&s, .carbon, armor);
    var glass = armor;
    glass.specular.strength = 0.8;
    glass.outline.width_px = 1.2;
    set(&s, .glass, glass);
    var rubber = cloth;
    rubber.outline.width_px = 2.0;
    set(&s, .rubber, rubber);
    var emissive = armor;
    emissive.emissive = 1;
    emissive.outline.width_px = 1.0;
    set(&s, .emissive, emissive);
    break :blk s;
};

/// A softer, painted look: wide blurred bands, hairline ink, no hard highlights.
pub const watercolor: CelStyle = blk: {
    var s = heavy_water;
    s.face_softness = 0.12;
    s.outline_scale = 0.55;
    for (&s.materials) |*m| {
        m.ramp.softness = @min(0.45, m.ramp.softness * 3 + 0.06);
        m.ramp.shadow_tint = .{ 0.5 + 0.5 * m.ramp.shadow_tint[0], 0.5 + 0.5 * m.ramp.shadow_tint[1], 0.5 + 0.5 * m.ramp.shadow_tint[2] };
        m.specular.softness = 0.08;
        m.specular.strength *= 0.5;
        m.rim.strength *= 0.6;
    }
    break :blk s;
};

/// Bold comic ink: thick near-black lines, hard bands, deep cold shadows.
pub const comic_ink: CelStyle = blk: {
    var s = heavy_water;
    s.outline_scale = 1.9;
    s.face_softness = 0.015;
    for (&s.materials) |*m| {
        m.ramp.softness = 0.012;
        m.ramp.threshold = 0.35;
        m.ramp.shadow_tint = .{ m.ramp.shadow_tint[0] * 0.8, m.ramp.shadow_tint[1] * 0.8, m.ramp.shadow_tint[2] * 0.95 };
        m.outline.tint = .{ m.outline.tint[0] * 0.45, m.outline.tint[1] * 0.45, m.outline.tint[2] * 0.45 };
        m.specular.softness = 0.006;
    }
    break :blk s;
};

/// One flat band with no highlights or rim: the base colours as authored.
pub const flat: CelStyle = blk: {
    var s = heavy_water;
    s.outline_scale = 0.8;
    for (&s.materials) |*m| {
        m.ramp.threshold = -0.6;
        m.ramp.deep_threshold = -1;
        m.ramp.shadow_tint = white;
        m.ramp.deep_tint = white;
        m.rim.strength = 0;
        m.specular.strength = 0;
    }
    break :blk s;
};

pub const Preset = struct { name: []const u8, style: *const CelStyle };
pub const presets = [_]Preset{
    .{ .name = "Heavy Water", .style = &heavy_water },
    .{ .name = "Watercolor", .style = &watercolor },
    .{ .name = "Comic ink", .style = &comic_ink },
    .{ .name = "Flat", .style = &flat },
};

test "every preset validates" {
    for (presets) |p| try p.style.validate();
}

test "validate rejects values the shader cannot draw" {
    var s = heavy_water;
    s.materials[0].ramp.softness = 0;
    try std.testing.expectError(error.OutOfRange, s.validate());
    s = heavy_water;
    s.materials[3].ramp.shadow_tint[1] = std.math.nan(f32);
    try std.testing.expectError(error.NotFinite, s.validate());
    s = heavy_water;
    s.materials[2].ramp.deep_threshold = 0.9;
    s.materials[2].ramp.threshold = 0.1;
    try std.testing.expectError(error.DeepAboveLit, s.validate());
    s = heavy_water;
    s.outline_max_world = s.outline_min_world / 2;
    try std.testing.expectError(error.OutOfRange, s.validate());
}

test "the GPU table round-trips every material" {
    for (presets) |p| {
        const t = pack(p.style, .{ .ramp_view = true });
        try std.testing.expectEqual(@as(f32, 2), t[0][3]);
        for (0..material_count) |i| {
            const material: Material = @enumFromInt(i);
            try std.testing.expectEqualDeep(p.style.get(material).*, unpack(&t, material));
        }
    }
    try std.testing.expectEqual(@as(usize, 0), table_bytes % 16);
}
