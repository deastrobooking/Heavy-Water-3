//! Block materials, grouped into styles. A style is data: the materials a builder picks from and
//! their colours. The castle style comes first; dungeon, eco city and farm follow (BT4).
const std = @import("std");

pub const Material = struct {
    /// Stable id for saves and interchange; never reorder or reuse.
    id: []const u8,
    name: []const u8,
    color: [3]f32,
    /// How much the shade varies from cell to cell (hand-laid stone varies, glass does not).
    variation: f32 = 0.08,
};

pub const Style = enum { castle };

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
};
pub const count = all.len;

pub fn ofStyle(style: Style) []const u6 {
    return switch (style) {
        .castle => &[_]u6{ 0, 1, 2, 3, 4, 5, 6, 7 },
    };
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
    for (ofStyle(.castle)) |m| try std.testing.expect(m < count);
    try std.testing.expect(count <= 64); // a cell stores the material in six bits
}
