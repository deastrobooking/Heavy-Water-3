//! Portable controller profiles. A preset is plain, versioned JSON so players can attach it to a
//! support post or upload it to the Heavy Water preset library, then import it without a service
//! login or platform-specific binary data.
const std = @import("std");
const PadBindings = @import("../engine/PadBindings.zig");

pub const format_version: u32 = 1;
pub const max_name_bytes = 64;
pub const max_identity_bytes = 96;
pub const path = "saves/controller-presets";

pub const Preset = struct {
    format: u32 = format_version,
    name: []const u8 = "Custom controller",
    vendor: []const u8 = "",
    product: []const u8 = "",
    mapping: PadBindings.Mapping = .{},
};

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) error{InvalidPreset}!Preset {
    const preset = std.json.parseFromSliceLeaky(Preset, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return error.InvalidPreset;
    if (preset.format != format_version or preset.name.len == 0 or preset.name.len > max_name_bytes or
        preset.vendor.len > max_identity_bytes or preset.product.len > max_identity_bytes or !preset.mapping.validate()) return error.InvalidPreset;
    return preset;
}

pub fn toJson(allocator: std.mem.Allocator, preset: Preset) ![]u8 {
    if (preset.format != format_version or preset.name.len == 0 or preset.name.len > max_name_bytes or
        preset.vendor.len > max_identity_bytes or preset.product.len > max_identity_bytes or !preset.mapping.validate()) return error.InvalidPreset;
    return std.json.Stringify.valueAlloc(allocator, preset, .{ .whitespace = .indent_2 });
}

/// Writes one shareable profile. Names are path-safe and the save helper uses an atomic rename.
pub fn saveSlot(io: std.Io, allocator: std.mem.Allocator, slot: u8, preset: Preset) !void {
    if (slot >= 8) return error.InvalidSlot;
    const json = try toJson(allocator, preset);
    defer allocator.free(json);
    var name: [40]u8 = undefined;
    const filename = try std.fmt.bufPrint(&name, "{s}/slot-{d:0>2}.json", .{ path, slot + 1 });
    try @import("Save.zig").writeFile(io, filename, json);
}

pub fn loadSlot(io: std.Io, allocator: std.mem.Allocator, slot: u8) !Preset {
    if (slot >= 8) return error.InvalidSlot;
    var name: [40]u8 = undefined;
    const filename = try std.fmt.bufPrint(&name, "{s}/slot-{d:0>2}.json", .{ path, slot + 1 });
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, filename, allocator, .limited(16 << 10));
    defer allocator.free(bytes);
    return parse(allocator, bytes);
}

test "controller presets round-trip for sharing and reject unsupported or malformed profiles" {
    var preset: Preset = .{ .name = "Travel pad", .vendor = "Third party", .product = "Arcade controller" };
    preset.mapping.buttons[@intFromEnum(PadBindings.Action.fire)] = 5;
    preset.mapping.invert[3] = true;
    const json = try toJson(std.testing.allocator, preset);
    defer std.testing.allocator.free(json);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const back = try parse(arena.allocator(), json);
    try std.testing.expectEqualStrings(preset.name, back.name);
    try std.testing.expectEqualStrings(preset.product, back.product);
    try std.testing.expectEqual(preset.mapping, back.mapping);
    try std.testing.expectError(error.InvalidPreset, parse(arena.allocator(), "{\"format\":88}"));
    try std.testing.expectError(error.InvalidPreset, parse(arena.allocator(), "{\"format\":1,\"mapping\":{\"deadzone\":99}}"));
}
