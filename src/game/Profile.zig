//! The player's name and appearance. Choices index fixed palettes drawn from the painterly
//! direction in docs/world.md, so every combination reads well and saves stay small.
const std = @import("std");
const Profile = @This();

pub const name_capacity = 20;

pub const skin_tones = [_][4]f32{
    .{ 0.98, 0.84, 0.72, 1 }, .{ 0.93, 0.76, 0.62, 1 }, .{ 0.84, 0.64, 0.49, 1 }, .{ 0.72, 0.52, 0.38, 1 },
    .{ 0.58, 0.40, 0.29, 1 }, .{ 0.44, 0.30, 0.22, 1 }, .{ 0.33, 0.22, 0.17, 1 }, .{ 0.80, 0.86, 0.78, 1 },
};
pub const hair_colors = [_][4]f32{
    .{ 0.08, 0.07, 0.07, 1 }, .{ 0.26, 0.16, 0.10, 1 }, .{ 0.45, 0.23, 0.12, 1 }, .{ 0.62, 0.24, 0.14, 1 },
    .{ 0.90, 0.76, 0.42, 1 }, .{ 0.82, 0.84, 0.88, 1 }, .{ 0.30, 0.55, 0.36, 1 }, .{ 0.36, 0.62, 0.92, 1 },
};
pub const outfit_colors = [_][4]f32{
    .{ 0.22, 0.42, 0.28, 1 }, .{ 0.42, 0.29, 0.18, 1 }, .{ 0.25, 0.36, 0.52, 1 }, .{ 0.62, 0.18, 0.18, 1 },
    .{ 0.86, 0.83, 0.74, 1 }, .{ 0.20, 0.21, 0.23, 1 }, .{ 0.18, 0.55, 0.50, 1 }, .{ 0.44, 0.30, 0.58, 1 },
};
/// Bioluminescent accent (visor and belt), echoing the Arbors' lumen.
pub const accent_colors = [_][4]f32{
    .{ 0.30, 0.95, 1.00, 1 }, .{ 1.00, 0.72, 0.25, 1 }, .{ 1.00, 0.40, 0.85, 1 }, .{ 0.60, 1.00, 0.35, 1 }, .{ 0.95, 0.95, 1.00, 1 },
};
pub const HairStyle = enum { short, ponytail, long, crest, hood };
/// Undersuit, field jacket, or a hard-surface armor suit over the undersuit: `exo_rig` (light
/// articulated limb plates), `hardsuit` (full segmented harness), `vanguard` (heavy hardsuit).
pub const Clothing = enum { undersuit, field_jacket, exo_rig, hardsuit, vanguard };
pub const Armor = enum { none, scout, sentinel, rootweave, skyguard };
pub const Helmet = enum { open, visor, sealed };
pub const Field = enum { name, height, build, skin, hair_style, hair_color, outfit, clothing, armor, helmet, accent };

name_buffer: [name_capacity]u8 = "RANGER".* ++ @as([name_capacity - 6]u8, @splat(0)),
name_len: u8 = 6,
/// Relative to the 1.8 m reference: 0.9–1.1.
height: f32 = 1,
/// Shoulder and limb width: 0.85–1.15.
build: f32 = 1,
skin: u8 = 2,
hair_style: HairStyle = .short,
hair_color: u8 = 1,
outfit: u8 = 0,
accent: u8 = 0,
clothing: Clothing = .field_jacket,
armor: Armor = .scout,
helmet: Helmet = .visor,

pub fn name(self: *const Profile) []const u8 {
    return self.name_buffer[0..self.name_len];
}

pub fn allowedChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == ' ' or c == '-';
}

/// Names are 1–20 characters of letters, digits, spaces, and hyphens, stored uppercase (the
/// HUD font is uppercase), and cannot start with a space.
pub fn setName(self: *Profile, text: []const u8) error{InvalidName}!void {
    if (text.len == 0 or text.len > name_capacity or text[0] == ' ') return error.InvalidName;
    for (text) |c| if (!allowedChar(c)) return error.InvalidName;
    self.name_buffer = @splat(0);
    for (text, 0..) |c, i| self.name_buffer[i] = std.ascii.toUpper(c);
    self.name_len = @intCast(text.len);
}

pub fn typeChar(self: *Profile, c: u8) void {
    if (!allowedChar(c) or self.name_len == name_capacity or (self.name_len == 0 and c == ' ')) return;
    self.name_buffer[self.name_len] = std.ascii.toUpper(c);
    self.name_len += 1;
}

pub fn backspace(self: *Profile) void {
    if (self.name_len == 0) return;
    self.name_len -= 1;
    self.name_buffer[self.name_len] = 0;
}

/// Steps a field by one choice (wrapping for palettes, clamped for proportions).
pub fn adjust(self: *Profile, field: Field, delta: i32) void {
    switch (field) {
        .name => {},
        .height => self.height = std.math.clamp(self.height + @as(f32, @floatFromInt(delta)) * 0.02, 0.9, 1.1),
        .build => self.build = std.math.clamp(self.build + @as(f32, @floatFromInt(delta)) * 0.05, 0.85, 1.15),
        .skin => self.skin = cycle(self.skin, delta, skin_tones.len),
        .hair_style => self.hair_style = @enumFromInt(cycle(@intFromEnum(self.hair_style), delta, std.meta.fields(HairStyle).len)),
        .hair_color => self.hair_color = cycle(self.hair_color, delta, hair_colors.len),
        .outfit => self.outfit = cycle(self.outfit, delta, outfit_colors.len),
        .clothing => self.clothing = @enumFromInt(cycle(@intFromEnum(self.clothing), delta, @typeInfo(Clothing).@"enum".fields.len)),
        .armor => self.armor = @enumFromInt(cycle(@intFromEnum(self.armor), delta, @typeInfo(Armor).@"enum".fields.len)),
        .helmet => self.helmet = @enumFromInt(cycle(@intFromEnum(self.helmet), delta, 3)),
        .accent => self.accent = cycle(self.accent, delta, accent_colors.len),
    }
}

fn cycle(value: anytype, delta: i32, count: usize) @TypeOf(value) {
    const n: i32 = @intCast(count);
    return @intCast(@mod(@as(i32, value) + delta, n));
}

/// JSON shape stored in saves.
pub const Doc = struct {
    name: []const u8,
    height: f32,
    build: f32,
    skin: u8,
    hair_style: HairStyle,
    hair_color: u8,
    outfit: u8,
    accent: u8,
    clothing: Clothing = .field_jacket,
    armor: Armor = .scout,
    helmet: Helmet = .visor,
};

pub fn toDoc(self: *const Profile) Doc {
    return .{ .name = self.name(), .height = self.height, .build = self.build, .skin = self.skin, .hair_style = self.hair_style, .hair_color = self.hair_color, .outfit = self.outfit, .accent = self.accent, .clothing = self.clothing, .armor = self.armor, .helmet = self.helmet };
}

pub fn fromDoc(doc: Doc) error{ InvalidName, InvalidProfile }!Profile {
    var result: Profile = .{};
    try result.setName(doc.name);
    if (!(doc.height >= 0.9 and doc.height <= 1.1) or !(doc.build >= 0.85 and doc.build <= 1.15)) return error.InvalidProfile;
    if (doc.skin >= skin_tones.len or doc.hair_color >= hair_colors.len or doc.outfit >= outfit_colors.len or doc.accent >= accent_colors.len) return error.InvalidProfile;
    result.height = doc.height;
    result.build = doc.build;
    result.skin = doc.skin;
    result.hair_style = doc.hair_style;
    result.hair_color = doc.hair_color;
    result.outfit = doc.outfit;
    result.accent = doc.accent;
    result.clothing = doc.clothing;
    result.armor = doc.armor;
    result.helmet = doc.helmet;
    return result;
}

test "names are validated, typed, and uppercased; fields wrap and clamp; documents round-trip" {
    var p: Profile = .{};
    try std.testing.expectEqualStrings("RANGER", p.name());
    try p.setName("Kaia Rootwalker");
    try std.testing.expectEqualStrings("KAIA ROOTWALKER", p.name());
    try std.testing.expectError(error.InvalidName, p.setName(""));
    try std.testing.expectError(error.InvalidName, p.setName(" lead"));
    try std.testing.expectError(error.InvalidName, p.setName("no_underscores"));
    try std.testing.expectError(error.InvalidName, p.setName("x" ** 21));
    while (p.name_len > 0) p.backspace();
    p.typeChar(' ');
    p.typeChar('z');
    p.typeChar('!');
    p.typeChar('9');
    try std.testing.expectEqualStrings("Z9", p.name());
    for (0..30) |_| p.typeChar('a');
    try std.testing.expectEqual(@as(u8, name_capacity), p.name_len);

    p.adjust(.skin, -3);
    try std.testing.expectEqual(@as(u8, 7), p.skin);
    p.adjust(.hair_style, -1);
    try std.testing.expectEqual(HairStyle.hood, p.hair_style);
    for (0..20) |_| p.adjust(.height, 1);
    try std.testing.expectEqual(@as(f32, 1.1), p.height);

    const back = try fromDoc(p.toDoc());
    try std.testing.expectEqualDeep(p, back);
    var bad = p.toDoc();
    bad.accent = accent_colors.len;
    try std.testing.expectError(error.InvalidProfile, fromDoc(bad));
    bad = p.toDoc();
    bad.height = 2;
    try std.testing.expectError(error.InvalidProfile, fromDoc(bad));
}
