//! `HWPK` content packs: compiled assets addressed by GUID, so content can ship outside the
//! executable and load in the background. Layout (little-endian):
//!
//!   header  "HWPK", format u32, entry count u32, reserved u32
//!   entries count × { guid u128, kind u8, pad [7]u8, offset u64, size u64, blake3 [32]u8 }
//!   blobs   each 16-byte aligned, in entry order
//!
//! `Pack.open` validates the header and table (bounds, ordering, overlap, unique GUIDs) before
//! anything is read; each blob's hash is checked when it is loaded, so a damaged pack fails one
//! asset with a clear error instead of corrupting memory.
const std = @import("std");
const Guid = @import("Guid.zig");
const Meta = @import("Meta.zig");
const Pack = @This();

pub const magic = "HWPK";
pub const format_version: u32 = 1;
pub const header_size = 16;
pub const entry_size = 16 + 8 + 8 + 8 + 32;
pub const max_entries = 4096;
pub const Error = error{ NotAPack, UnsupportedPackVersion, TooManyEntries, Truncated, InvalidEntry, DuplicateGuid, HashMismatch, UnknownAsset };

pub const Entry = struct { guid: Guid, kind: Meta.Kind, offset: u64, size: u64, hash: [32]u8 };

entries: []Entry,

/// Parses the table of contents from the first bytes of a pack whose total length is
/// `pack_size`. `bytes` must hold at least the header and table.
pub fn open(allocator: std.mem.Allocator, bytes: []const u8, pack_size: u64) (Error || error{OutOfMemory})!Pack {
    if (bytes.len < header_size or !std.mem.eql(u8, bytes[0..4], magic)) return error.NotAPack;
    if (std.mem.readInt(u32, bytes[4..8], .little) != format_version) return error.UnsupportedPackVersion;
    const count = std.mem.readInt(u32, bytes[8..12], .little);
    if (count > max_entries) return error.TooManyEntries;
    const table_end = header_size + @as(u64, count) * entry_size;
    if (bytes.len < table_end or pack_size < table_end) return error.Truncated;
    const entries = try allocator.alloc(Entry, count);
    errdefer allocator.free(entries);
    var previous_end: u64 = table_end;
    for (entries, 0..) |*e, i| {
        const raw = bytes[header_size + i * entry_size ..][0..entry_size];
        const kind_byte = raw[16];
        if (kind_byte >= @typeInfo(Meta.Kind).@"enum".fields.len) return error.InvalidEntry;
        e.* = .{
            .guid = .{ .value = std.mem.readInt(u128, raw[0..16], .little) },
            .kind = @enumFromInt(kind_byte),
            .offset = std.mem.readInt(u64, raw[24..32], .little),
            .size = std.mem.readInt(u64, raw[32..40], .little),
            .hash = raw[40..72].*,
        };
        if (e.guid.value == 0 or e.offset % 16 != 0 or e.offset < previous_end or e.size > pack_size or e.offset > pack_size - e.size) return error.InvalidEntry;
        previous_end = e.offset + e.size;
        for (entries[0..i]) |other| if (other.guid.eql(e.guid)) return error.DuplicateGuid;
    }
    return .{ .entries = entries };
}

pub fn deinit(self: Pack, allocator: std.mem.Allocator) void {
    allocator.free(self.entries);
}

pub fn find(self: Pack, guid: Guid) ?Entry {
    for (self.entries) |e| if (e.guid.eql(guid)) return e;
    return null;
}

/// Checks a loaded blob against its table entry.
pub fn verify(entry: Entry, blob: []const u8) Error!void {
    if (blob.len != entry.size) return error.Truncated;
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(blob, &digest, .{});
    if (!std.mem.eql(u8, &digest, &entry.hash)) return error.HashMismatch;
}

pub const Input = struct { guid: Guid, kind: Meta.Kind, data: []const u8 };

/// Writes a pack holding `inputs` in order.
pub fn write(allocator: std.mem.Allocator, inputs: []const Input) (Error || error{OutOfMemory})![]u8 {
    if (inputs.len > max_entries) return error.TooManyEntries;
    var size: u64 = header_size + inputs.len * entry_size;
    for (inputs, 0..) |in, i| {
        for (inputs[0..i]) |other| if (other.guid.eql(in.guid)) return error.DuplicateGuid;
        size = std.mem.alignForward(u64, size, 16) + in.data.len;
    }
    const out = try allocator.alloc(u8, size);
    @memset(out, 0);
    @memcpy(out[0..4], magic);
    std.mem.writeInt(u32, out[4..8], format_version, .little);
    std.mem.writeInt(u32, out[8..12], @intCast(inputs.len), .little);
    var at: u64 = header_size + inputs.len * entry_size;
    for (inputs, 0..) |in, i| {
        at = std.mem.alignForward(u64, at, 16);
        const raw = out[header_size + i * entry_size ..][0..entry_size];
        std.mem.writeInt(u128, raw[0..16], in.guid.value, .little);
        raw[16] = @intFromEnum(in.kind);
        std.mem.writeInt(u64, raw[24..32], at, .little);
        std.mem.writeInt(u64, raw[32..40], in.data.len, .little);
        std.crypto.hash.Blake3.hash(in.data, raw[40..72], .{});
        @memcpy(out[at..][0..in.data.len], in.data);
        at += in.data.len;
    }
    return out;
}

test "packs round-trip by GUID, verify blobs, and reject damaged tables" {
    const a = std.testing.allocator;
    const g1 = try Guid.parse("11111111111111111111111111111111");
    const g2 = try Guid.parse("22222222222222222222222222222222");
    const bytes = try write(a, &.{ .{ .guid = g1, .kind = .model, .data = "first blob" }, .{ .guid = g2, .kind = .blueprint, .data = "second" } });
    defer a.free(bytes);
    const pack = try open(a, bytes, bytes.len);
    defer pack.deinit(a);
    const e2 = pack.find(g2).?;
    try std.testing.expectEqual(Meta.Kind.blueprint, e2.kind);
    try std.testing.expectEqualStrings("second", bytes[e2.offset..][0..e2.size]);
    try std.testing.expectEqual(@as(u64, 0), e2.offset % 16);
    try verify(e2, bytes[e2.offset..][0..e2.size]);
    try std.testing.expectError(error.HashMismatch, verify(e2, "sECOND"));
    try std.testing.expect(pack.find(try Guid.parse("33333333333333333333333333333333")) == null);

    // Damage: magic, version, truncation, an entry pointing past the end, duplicate GUIDs.
    var broken = try a.dupe(u8, bytes);
    defer a.free(broken);
    broken[0] = 'X';
    try std.testing.expectError(error.NotAPack, open(a, broken, broken.len));
    broken[0] = 'H';
    broken[4] = 9;
    try std.testing.expectError(error.UnsupportedPackVersion, open(a, broken, broken.len));
    broken[4] = 1;
    try std.testing.expectError(error.Truncated, open(a, broken[0..40], 40));
    std.mem.writeInt(u64, broken[header_size + entry_size + 32 ..][0..8], 1 << 40, .little);
    try std.testing.expectError(error.InvalidEntry, open(a, broken, broken.len));
    try std.testing.expectError(error.DuplicateGuid, write(a, &.{ .{ .guid = g1, .kind = .model, .data = "a" }, .{ .guid = g1, .kind = .model, .data = "b" } }));
}
