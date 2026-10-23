//! Block materials, grouped into styles. Building styles have eight shared roles, so a selection
//! can be re-skinned role by role. The glass palette uses the same eight slots for glazing swatches.
const std = @import("std");

pub const Material = struct {
    /// Stable id for saves and interchange; never reorder or reuse.
    id: []const u8,
    name: []const u8,
    color: [3]f32,
    /// How much the shade varies from cell to cell (hand-laid stone varies, glass does not).
    variation: f32 = 0.08,
};

/// `platformer` is the mechanisms: its eight "materials" are springs, boost strips, crumbling
/// blocks, hazards, checkpoints, pressure plates, gates and movers (see `game/Platformer.zig`).
/// `glass` is a swatch palette of architectural glazing and glass blocks.
pub const Style = enum { castle, dungeon, eco_city, farm, platformer, glass };
pub const style_count = 6;
/// What each of a style's eight materials is for; restyling keeps the role.
pub const Role = enum { main, dark, accent, wood, roof, nature, metal, color };

/// Index in this table is what a cell stores. Append only.
pub const all = [_]Material{
    .{ .id = "castle.stone", .name = "STONE", .color = .{ 0.62, 0.60, 0.56 } },
    .{ .id = "castle.dark_stone", .name = "DARK STONE", .color = .{ 0.36, 0.35, 0.37 } },
    .{ .id = "castle.sandstone", .name = "SANDSTONE", .color = .{ 0.80, 0.70, 0.52 } },
    .{ .id = "castle.timber", .name = "TIMBER", .color = .{ 0.47, 0.32, 0.20 } },
    .{ .id = "castle.slate", .name = "SLATE ROOF", .color = .{ 0.28, 0.33, 0.42 } },
    .{ .id = "castle.moss", .name = "MOSS STONE", .color = .{ 0.43, 0.52, 0.36 } },
    .{ .id = "castle.iron", .name = "IRON", .color = .{ 0.24, 0.25, 0.27 }, .variation = 0.02 },
    .{ .id = "castle.banner", .name = "BANNER RED", .color = .{ 0.66, 0.14, 0.14 }, .variation = 0.02 },
    .{ .id = "dungeon.brick", .name = "DUNGEON BRICK", .color = .{ 0.33, 0.29, 0.30 } },
    .{ .id = "dungeon.blackstone", .name = "BLACKSTONE", .color = .{ 0.16, 0.15, 0.18 } },
    .{ .id = "dungeon.bone", .name = "BONE", .color = .{ 0.82, 0.78, 0.66 }, .variation = 0.05 },
    .{ .id = "dungeon.rotwood", .name = "ROTWOOD", .color = .{ 0.30, 0.24, 0.18 } },
    .{ .id = "dungeon.vault", .name = "VAULT STONE", .color = .{ 0.24, 0.24, 0.30 } },
    .{ .id = "dungeon.fungus", .name = "GLOW FUNGUS", .color = .{ 0.30, 0.62, 0.52 }, .variation = 0.12 },
    .{ .id = "dungeon.grate", .name = "IRON GRATE", .color = .{ 0.20, 0.19, 0.18 }, .variation = 0.02 },
    .{ .id = "dungeon.ember", .name = "EMBER", .color = .{ 0.95, 0.46, 0.14 }, .variation = 0.04 },
    .{ .id = "eco.livewood", .name = "LIVING WOOD", .color = .{ 0.56, 0.42, 0.28 } },
    .{ .id = "eco.bark", .name = "BARK", .color = .{ 0.34, 0.25, 0.18 } },
    .{ .id = "eco.glass", .name = "GREEN GLASS", .color = .{ 0.62, 0.86, 0.84 }, .variation = 0.01 },
    .{ .id = "eco.bamboo", .name = "BAMBOO", .color = .{ 0.74, 0.70, 0.40 } },
    .{ .id = "eco.green_roof", .name = "GREEN ROOF", .color = .{ 0.38, 0.62, 0.30 }, .variation = 0.1 },
    .{ .id = "eco.leaf", .name = "LEAF", .color = .{ 0.24, 0.52, 0.26 }, .variation = 0.12 },
    .{ .id = "eco.solar", .name = "SOLAR LEAF", .color = .{ 0.16, 0.24, 0.44 }, .variation = 0.02 },
    .{ .id = "eco.bloom", .name = "BLOOM", .color = .{ 0.92, 0.52, 0.70 }, .variation = 0.06 },
    .{ .id = "farm.plank", .name = "PLANK", .color = .{ 0.66, 0.50, 0.32 } },
    .{ .id = "farm.dark_plank", .name = "DARK PLANK", .color = .{ 0.42, 0.30, 0.20 } },
    .{ .id = "farm.hay", .name = "HAY", .color = .{ 0.86, 0.74, 0.38 }, .variation = 0.1 },
    .{ .id = "farm.post", .name = "FENCE POST", .color = .{ 0.52, 0.38, 0.24 } },
    .{ .id = "farm.thatch", .name = "THATCH", .color = .{ 0.70, 0.58, 0.32 }, .variation = 0.1 },
    .{ .id = "farm.soil", .name = "TILLED SOIL", .color = .{ 0.36, 0.25, 0.17 }, .variation = 0.1 },
    .{ .id = "farm.iron", .name = "TOOL IRON", .color = .{ 0.30, 0.31, 0.33 }, .variation = 0.02 },
    .{ .id = "farm.barn_red", .name = "BARN RED", .color = .{ 0.62, 0.18, 0.14 }, .variation = 0.04 },
    .{ .id = "platform.spring", .name = "SPRING", .color = .{ 0.36, 0.92, 0.42 }, .variation = 0 },
    .{ .id = "platform.boost", .name = "BOOST STRIP", .color = .{ 0.20, 0.86, 0.96 }, .variation = 0 },
    .{ .id = "platform.crumble", .name = "CRUMBLE", .color = .{ 0.74, 0.60, 0.44 }, .variation = 0.14 },
    .{ .id = "platform.hazard", .name = "HAZARD", .color = .{ 0.96, 0.30, 0.12 }, .variation = 0.04 },
    .{ .id = "platform.checkpoint", .name = "CHECKPOINT", .color = .{ 1.00, 0.82, 0.24 }, .variation = 0 },
    .{ .id = "platform.plate", .name = "PRESSURE PLATE", .color = .{ 0.50, 0.58, 0.78 }, .variation = 0 },
    .{ .id = "platform.gate", .name = "GATE", .color = .{ 0.30, 0.30, 0.44 }, .variation = 0.02 },
    .{ .id = "platform.mover", .name = "MOVER", .color = .{ 0.68, 0.40, 0.96 }, .variation = 0 },
    .{ .id = "glass.clear", .name = "CLEAR GLASS", .color = .{ 0.76, 0.91, 0.93 }, .variation = 0 },
    .{ .id = "glass.ocean", .name = "OCEAN GLASS", .color = .{ 0.28, 0.67, 0.84 }, .variation = 0.01 },
    .{ .id = "glass.emerald", .name = "EMERALD GLASS", .color = .{ 0.28, 0.72, 0.58 }, .variation = 0.01 },
    .{ .id = "glass.amber", .name = "AMBER GLASS", .color = .{ 0.92, 0.61, 0.28 }, .variation = 0.01 },
    .{ .id = "glass.rose", .name = "ROSE GLASS", .color = .{ 0.88, 0.48, 0.59 }, .variation = 0.01 },
    .{ .id = "glass.frosted", .name = "FROSTED GLASS", .color = .{ 0.72, 0.84, 0.88 }, .variation = 0.02 },
    .{ .id = "glass.smoke", .name = "SMOKED GLASS", .color = .{ 0.34, 0.43, 0.51 }, .variation = 0.01 },
    .{ .id = "glass.mirror", .name = "MIRROR GLASS", .color = .{ 0.63, 0.73, 0.79 }, .variation = 0 },
};
pub const count = all.len;

/// The eight materials of a style, in `Role` order.
pub fn ofStyle(style: Style) []const u6 {
    return switch (style) {
        .castle => &[_]u6{ 0, 1, 2, 3, 4, 5, 6, 7 },
        .dungeon => &[_]u6{ 8, 9, 10, 11, 12, 13, 14, 15 },
        .eco_city => &[_]u6{ 16, 17, 18, 19, 20, 21, 22, 23 },
        .farm => &[_]u6{ 24, 25, 26, 27, 28, 29, 30, 31 },
        .platformer => &[_]u6{ 32, 33, 34, 35, 36, 37, 38, 39 },
        .glass => &[_]u6{ 40, 41, 42, 43, 44, 45, 46, 47 },
    };
}

pub fn styleName(style: Style) []const u8 {
    return switch (style) {
        .castle => "CASTLE",
        .dungeon => "DUNGEON",
        .eco_city => "ECO CITY",
        .farm => "FARM",
        .platformer => "PLATFORMER",
        .glass => "GLASS",
    };
}

/// The style and role a material belongs to.
pub fn roleOf(material: u6) struct { style: Style, role: usize } {
    return .{ .style = @enumFromInt(material / 8), .role = material % 8 };
}

/// The same role in another style: how restyling maps a material. Mechanisms are not a look, so
/// they never restyle and nothing restyles into them.
pub fn restyle(material: u6, to: Style) u6 {
    if (to == .platformer or roleOf(material).style == .platformer) return material;
    if (to == roleOf(material).style) return material;
    if (roleOf(material).style == .glass) return ofRole(to, .accent);
    return ofStyle(to)[roleOf(material).role];
}

pub fn ofRole(style: Style, role: Role) u6 {
    return ofStyle(style)[@intFromEnum(role)];
}

/// A small, stable per-cell shade change so walls read as laid blocks, not one flat sheet.
pub fn shade(material: u6, x: i32, y: i32, z: i32) [3]f32 {
    const m = all[material];
    var h: u32 = @bitCast(x *% 73856093 ^ y *% 19349663 ^ z *% 83492791);
    h = (h ^ (h >> 13)) *% 0x5bd1e995;
    const t = @as(f32, @floatFromInt(h >> 16 & 0xff)) / 255.0 * 2 - 1;
    const k = 1 + t * m.variation;
    return .{ m.color[0] * k, m.color[1] * k, m.color[2] * k };
}

test "material ids are unique and every style names real materials" {
    for (all, 0..) |a, i| for (all[0..i]) |b| try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
    for (0..style_count) |s| for (ofStyle(@enumFromInt(s)), 0..) |m, role| {
        try std.testing.expect(m < count);
        try std.testing.expectEqual(@as(usize, s), @intFromEnum(roleOf(m).style));
        try std.testing.expectEqual(role, roleOf(m).role);
    };
    try std.testing.expectEqual(ofRole(.farm, .roof), restyle(ofRole(.castle, .roof), .farm));
    try std.testing.expect(count <= 64); // a cell stores the material in six bits
}
