//! Player settings, kept in `saves/settings.json` apart from world saves. Every field has a
//! range; a missing or damaged file falls back to the defaults.
const std = @import("std");
const Settings = @This();
const Bindings = @import("Bindings.zig");

pub const path = "saves/settings.json";
pub const Field = enum { master_volume, effects_volume, ambience_volume, interface_volume, sensitivity, invert_y, fov, ui_scale, third_person, metrics };
pub const field_count = @typeInfo(Field).@"enum".fields.len;

/// Volumes in percent: everything, then the effects, ambience and interface buses.
master_volume: u8 = 80,
effects_volume: u8 = 80,
ambience_volume: u8 = 70,
interface_volume: u8 = 70,
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
/// Keyboard bindings (rebound on the controls screen).
bindings: Bindings = .{},

pub fn adjust(self: *Settings, field: Field, delta: i32) void {
    const d: f32 = @floatFromInt(delta);
    switch (field) {
        .master_volume => self.master_volume = volumeStep(self.master_volume, delta),
        .effects_volume => self.effects_volume = volumeStep(self.effects_volume, delta),
        .ambience_volume => self.ambience_volume = volumeStep(self.ambience_volume, delta),
        .interface_volume => self.interface_volume = volumeStep(self.interface_volume, delta),
        .sensitivity => self.sensitivity = std.math.clamp(self.sensitivity + 0.25 * d, 0.25, 3),
        .invert_y => self.invert_y = !self.invert_y,
        .fov => self.fov = @intCast(std.math.clamp(@as(i32, self.fov) + 5 * delta, 50, 100)),
        .ui_scale => self.ui_scale = std.math.clamp(self.ui_scale + 0.125 * d, 0.75, 1.5),
        .third_person => self.third_person = !self.third_person,
        .metrics => self.metrics = !self.metrics,
    }
}

fn volumeStep(current: u8, delta: i32) u8 {
    return @intCast(std.math.clamp(@as(i32, current) + 10 * delta, 0, 100));
}

pub fn label(field: Field) []const u8 {
    return switch (field) {
        .master_volume => "MASTER VOLUME",
        .effects_volume => "EFFECTS VOLUME",
        .ambience_volume => "AMBIENCE VOLUME",
        .interface_volume => "INTERFACE VOLUME",
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
        .master_volume => std.fmt.bufPrint(buffer, "{d}%", .{self.master_volume}) catch buffer,
        .effects_volume => std.fmt.bufPrint(buffer, "{d}%", .{self.effects_volume}) catch buffer,
        .ambience_volume => std.fmt.bufPrint(buffer, "{d}%", .{self.ambience_volume}) catch buffer,
        .interface_volume => std.fmt.bufPrint(buffer, "{d}%", .{self.interface_volume}) catch buffer,
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

/// The file's shape, with wide number types so an out-of-range value (such as a field of view
/// of 400) clamps instead of failing the whole file.
const Raw = struct {
    master_volume: i64 = 80,
    effects_volume: i64 = 80,
    ambience_volume: i64 = 70,
    interface_volume: i64 = 70,
    sensitivity: f64 = 1,
    invert_y: bool = false,
    fov: i64 = 60,
    ui_scale: f64 = 1,
    third_person: bool = false,
    metrics: bool = false,
    bindings: []const Bindings.Entry = &.{},
};

/// Parses settings, clamping every field into range; unknown fields are ignored.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) error{InvalidSettings}!Settings {
    const parsed = std.json.parseFromSlice(Raw, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return error.InvalidSettings;
    defer parsed.deinit();
    const r = parsed.value;
    const defaults: Settings = .{};
    return .{
        .master_volume = @intCast(std.math.clamp(r.master_volume, 0, 100)),
        .effects_volume = @intCast(std.math.clamp(r.effects_volume, 0, 100)),
        .ambience_volume = @intCast(std.math.clamp(r.ambience_volume, 0, 100)),
        .interface_volume = @intCast(std.math.clamp(r.interface_volume, 0, 100)),
        .sensitivity = if (std.math.isFinite(r.sensitivity)) @floatCast(std.math.clamp(r.sensitivity, 0.25, 3)) else defaults.sensitivity,
        .invert_y = r.invert_y,
        .fov = @intCast(std.math.clamp(r.fov, 50, 100)),
        .ui_scale = if (std.math.isFinite(r.ui_scale)) @floatCast(std.math.clamp(r.ui_scale, 0.75, 1.5)) else defaults.ui_scale,
        .third_person = r.third_person,
        .metrics = r.metrics,
        .bindings = Bindings.fromEntries(r.bindings),
    };
}

/// The settings file's JSON (bindings by action and key name).
pub fn toJson(self: Settings, allocator: std.mem.Allocator) ![]u8 {
    var entries: [Bindings.count]Bindings.Entry = undefined;
    const doc: Raw = .{ .master_volume = self.master_volume, .effects_volume = self.effects_volume, .ambience_volume = self.ambience_volume, .interface_volume = self.interface_volume, .sensitivity = self.sensitivity, .invert_y = self.invert_y, .fov = self.fov, .ui_scale = self.ui_scale, .third_person = self.third_person, .metrics = self.metrics, .bindings = self.bindings.toEntries(&entries) };
    return std.json.Stringify.valueAlloc(allocator, doc, .{ .whitespace = .indent_2 });
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
    const json = try self.toJson(allocator);
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
    for (0..3) |_| s.adjust(.master_volume, -1);
    try std.testing.expectEqual(@as(u8, 50), s.master_volume);
    for (0..20) |_| s.adjust(.effects_volume, 1);
    try std.testing.expectEqual(@as(u8, 100), s.effects_volume);
    _ = try s.bindings.bind(.stomp, .z);
    const json = try s.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);
    const back = try parse(std.testing.allocator, json);
    try std.testing.expectEqual(s, back);
    try std.testing.expectEqual(@as(u8, 100), (try parse(std.testing.allocator, "{\"fov\":200}")).fov);
    // One wild value clamps; the other settings survive.
    const wild = try parse(std.testing.allocator, "{\"fov\":400,\"invert_y\":true}");
    try std.testing.expect(wild.fov == 100 and wild.invert_y);
    try std.testing.expectError(error.InvalidSettings, parse(std.testing.allocator, "{\"fov\":"));
}
