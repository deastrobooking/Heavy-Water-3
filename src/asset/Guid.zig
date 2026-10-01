//! Stable 128-bit asset identity, written as 32 lowercase hex characters. A GUID is assigned
//! once (by `zig build import`) and never changes, so renaming or moving a source keeps every
//! save, scene, mod, and network message that refers to it valid.
const std = @import("std");
const Guid = @This();

value: u128,

pub const zero: Guid = .{ .value = 0 };

pub fn parse(text: []const u8) error{InvalidGuid}!Guid {
    if (text.len != 32) return error.InvalidGuid;
    for (text) |c| if (!(std.ascii.isDigit(c) or (c >= 'a' and c <= 'f'))) return error.InvalidGuid;
    const v = std.fmt.parseInt(u128, text, 16) catch return error.InvalidGuid;
    if (v == 0) return error.InvalidGuid;
    return .{ .value = v };
}

pub fn format(self: Guid) [32]u8 {
    var out: [32]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "{x:0>32}", .{self.value}) catch unreachable;
    return out;
}

/// A fresh random GUID (never zero).
pub fn generate(io: std.Io) Guid {
    var bytes: [16]u8 = undefined;
    while (true) {
        io.random(&bytes);
        const v = std.mem.readInt(u128, &bytes, .little);
        if (v != 0) return .{ .value = v };
    }
}

/// A stable GUID for content the engine generates in code (procedural meshes), derived from a
/// namespaced name so it is identical in every build without a sidecar.
pub fn derived(name: []const u8) Guid {
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(name, &digest, .{});
    const v = std.mem.readInt(u128, digest[0..16], .little);
    return .{ .value = if (v == 0) 1 else v };
}

pub fn eql(a: Guid, b: Guid) bool {
    return a.value == b.value;
}

pub fn jsonStringify(self: Guid, jw: anytype) !void {
    try jw.write(&self.format());
}

pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Guid {
    const text = try std.json.innerParse([]const u8, allocator, source, options);
    return parse(text) catch error.UnexpectedToken;
}

test "guids round-trip as 32 lowercase hex characters and reject anything else" {
    const g = try Guid.parse("a3f1c0de9b8e4f7aa1d2c3b4e5f60718");
    try std.testing.expectEqualStrings("a3f1c0de9b8e4f7aa1d2c3b4e5f60718", &g.format());
    for ([_][]const u8{ "", "A3F1C0DE9B8E4F7AA1D2C3B4E5F60718", "a3f1c0de9b8e4f7aa1d2c3b4e5f6071", "g3f1c0de9b8e4f7aa1d2c3b4e5f60718", "00000000000000000000000000000000" }) |bad| {
        try std.testing.expectError(error.InvalidGuid, Guid.parse(bad));
    }
    try std.testing.expect(Guid.derived("generated:block").eql(Guid.derived("generated:block")));
    try std.testing.expect(!Guid.derived("generated:block").eql(Guid.derived("generated:wheel")));
    const a = Guid.generate(std.testing.io);
    const b = Guid.generate(std.testing.io);
    try std.testing.expect(!a.eql(b) and a.value != 0);
    // JSON: a quoted string.
    const json = try std.json.Stringify.valueAlloc(std.testing.allocator, struct { id: Guid }{ .id = g }, .{});
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"id\":\"a3f1c0de9b8e4f7aa1d2c3b4e5f60718\"}", json);
    const back = try std.json.parseFromSlice(struct { id: Guid }, std.testing.allocator, json, .{});
    defer back.deinit();
    try std.testing.expect(back.value.id.eql(g));
}
