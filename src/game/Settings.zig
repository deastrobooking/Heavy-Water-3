//! Player settings, kept in `saves/settings.json` apart from world saves. Every field has a
//! range; a missing or damaged file falls back to the defaults.
const std = @import("std");
const Settings = @This();

pub const path = "saves/settings.json";
pub const Field = enum { sensitivity, invert_y, fov, ui_scale, third_person, metrics };
pub const field_count = @typeInfo(Field).@"enum".fields.len;

/// Mouse and stick look speed multiplier, 0.25–3.
sensitivity: f32 = 1,
invert_y: bool = false,
/// Vertical field of view in degrees, 50–100.
fov: u8 = 60,
/// GUI size multiplier, 0.75–1.5.
ui_scale: f32 = 1,
/// Start in third person.
third_person: bool = false,
/// Performance overlay (F1).
metrics: bool = false,

pub fn adjust(self: *Settings, field: Field, delta: i32) void {
    const d: f32 = @floatFromInt(delta);
    switch (field) {
        .sensitivity => self.sensitivity = std.math.clamp(self.sensitivity + 0.25 * d, 0.25, 3),
        .invert_y => self.invert_y = !self.invert_y,
        .fov => self.fov = @intCast(std.math.clamp(@as(i32, self.fov) + 5 * delta, 50, 100)),
        .ui_scale => self.ui_scale = std.math.clamp(self.ui_scale + 0.125 * d, 0.75, 1.5),
        .third_person => self.third_person = !self.third_person,
        .metrics => self.metrics = !self.metrics,
    }
}

pub fn label(field: Field) []const u8 {
    return switch (field) {
        .sensitivity => "LOOK SENSITIVITY",
        .invert_y => "INVERT LOOK Y",
        .fov => "FIELD OF VIEW",
        .ui_scale => "INTERFACE SIZE",
        .third_person => "START IN THIRD PERSON",
        .metrics => "PERFORMANCE OVERLAY",
    };
}

pub fn value(self: Settings, field: Field, buffer: []u8) []const u8 {
    return switch (field) {
        .sensitivity => std.fmt.bufPrint(buffer, "{d:.2}X", .{self.sensitivity}) catch buffer,
        .invert_y => if (self.invert_y) "ON" else "OFF",
        .fov => std.fmt.bufPrint(buffer, "{d} DEG", .{self.fov}) catch buffer,
        .ui_scale => std.fmt.bufPrint(buffer, "{d:.0}%", .{self.ui_scale * 100}) catch buffer,
        .third_person => if (self.third_person) "ON" else "OFF",
        .metrics => if (self.metrics) "ON" else "OFF",
    };
}

pub fn fovRadians(self: Settings) f32 {
    return @as(f32, @floatFromInt(self.fov)) * std.math.pi / 180;
}

/// Parses settings, clamping every field into range; unknown fields are ignored.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) error{InvalidSettings}!Settings {
    const parsed = std.json.parseFromSlice(Settings, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return error.InvalidSettings;
    defer parsed.deinit();
    var s = parsed.value;
    if (!std.math.isFinite(s.sensitivity) or !std.math.isFinite(s.ui_scale)) return error.InvalidSettings;
    s.sensitivity = std.math.clamp(s.sensitivity, 0.25, 3);
    s.ui_scale = std.math.clamp(s.ui_scale, 0.75, 1.5);
    s.fov = std.math.clamp(s.fov, 50, 100);
    return s;
}

pub fn load(io: std.Io, allocator: std.mem.Allocator) Settings {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 << 10)) catch return .{};
    defer allocator.free(bytes);
    return parse(allocator, bytes) catch |err| {
        std.log.warn("{s}: {s}; using defaults", .{ path, @errorName(err) });
        return .{};
    };
}

pub fn store(self: Settings, io: std.Io, allocator: std.mem.Allocator) !void {
    const json = try std.json.Stringify.valueAlloc(allocator, self, .{ .whitespace = .indent_2 });
    defer allocator.free(json);
    try @import("Save.zig").writeFile(io, path, json);
}

test "settings stay in range and round-trip, and damaged files fall back" {
    var s: Settings = .{};
    for (0..20) |_| s.adjust(.sensitivity, 1);
    try std.testing.expectEqual(@as(f32, 3), s.sensitivity);
    for (0..20) |_| s.adjust(.fov, -1);
    try std.testing.expectEqual(@as(u8, 50), s.fov);
    s.adjust(.invert_y, 1);
    const json = try std.json.Stringify.valueAlloc(std.testing.allocator, s, .{});
    defer std.testing.allocator.free(json);
    const back = try parse(std.testing.allocator, json);
    try std.testing.expectEqual(s, back);
    try std.testing.expectEqual(@as(u8, 100), (try parse(std.testing.allocator, "{\"fov\":200}")).fov);
    try std.testing.expectError(error.InvalidSettings, parse(std.testing.allocator, "{\"fov\":"));
}
