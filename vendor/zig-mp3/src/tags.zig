// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Recognizing the metadata blocks that get wrapped around MP3 data.
//!
//! Nothing here reads the contents of a tag: the decoder only needs to know
//! that a run of bytes is not audio and how far to step over it, and it must
//! be able to work that out without allocating.  `id3.zig` reads what is
//! inside them.

const std = @import("std");

pub const Kind = enum { id3v1, id3v2, ape };

pub const Tag = struct {
    kind: Kind,
    /// Total bytes to skip, header and body together.
    size: usize,
};

pub const Detection = union(enum) {
    /// `data` does not begin with a tag.
    none,
    /// `data` begins with something that may be a tag, but its header is not
    /// complete yet.  Try again with more.
    incomplete,
    found: Tag,
};

/// Identify a tag at the very start of `data`.
pub fn detect(data: []const u8) Detection {
    if (data.len >= 3 and std.mem.eql(u8, data[0..3], "ID3")) {
        if (data.len < 10) return .incomplete;
        // A major version of 0xff is reserved and never valid.
        if (data[3] == 0xff or data[4] == 0xff) return .none;
        // The size is four seven-bit groups so that it can never contain a
        // byte that looks like a frame sync.
        var size: usize = 0;
        for (data[6..10]) |byte| {
            if (byte & 0x80 != 0) return .none;
            size = (size << 7) | byte;
        }
        const footer: usize = if (data[5] & 0x10 != 0) 10 else 0;
        return .{ .found = .{ .kind = .id3v2, .size = 10 + size + footer } };
    }

    if (data.len >= 3 and std.mem.eql(u8, data[0..3], "TAG")) {
        if (data.len < 128) return .incomplete;
        return .{ .found = .{ .kind = .id3v1, .size = 128 } };
    }

    if (data.len >= 8 and std.mem.eql(u8, data[0..8], "APETAGEX")) {
        if (data.len < 32) return .incomplete;
        // The stated size covers the body and the footer but not this header.
        const size = std.mem.readInt(u32, data[12..16], .little);
        return .{ .found = .{ .kind = .ape, .size = 32 + @as(usize, size) } };
    }

    return .none;
}

const testing = std.testing;

test "an ID3v2 tag is ten bytes plus its syncsafe size" {
    var data: [310]u8 = @splat(0);
    @memcpy(data[0..10], &[_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 2, 1 });
    const tag = detect(&data).found;
    try testing.expectEqual(Kind.id3v2, tag.kind);
    try testing.expectEqual(@as(usize, 10 + (2 << 7) + 1), tag.size);
}

test "an ID3v2 footer adds another ten bytes" {
    var data: [50]u8 = @splat(0);
    @memcpy(data[0..10], &[_]u8{ 'I', 'D', '3', 4, 0, 0x10, 0, 0, 0, 20 });
    try testing.expectEqual(@as(usize, 40), detect(&data).found.size);
}

test "a size byte with its high bit set is not a syncsafe size" {
    const data = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0x80, 0 };
    try testing.expectEqual(Detection.none, detect(&data));
}

test "ID3v1 is always 128 bytes" {
    var data: [128]u8 = @splat(0);
    @memcpy(data[0..3], "TAG");
    try testing.expectEqual(@as(usize, 128), detect(&data).found.size);
}

test "a truncated tag header asks for more rather than guessing" {
    try testing.expectEqual(Detection.incomplete, detect("ID3"));
    try testing.expectEqual(Detection.incomplete, detect("TAG"));
    try testing.expectEqual(Detection.incomplete, detect("APETAGEX"));
}

test "an APE tag is its stated size plus a 32 byte header" {
    var data: [64]u8 = @splat(0);
    @memcpy(data[0..8], "APETAGEX");
    std.mem.writeInt(u32, data[12..16], 100, .little);
    const tag = detect(&data).found;
    try testing.expectEqual(Kind.ape, tag.kind);
    try testing.expectEqual(@as(usize, 132), tag.size);
}

test "audio is not a tag" {
    try testing.expectEqual(Detection.none, detect(&[_]u8{ 0xff, 0xfb, 0x90, 0x00 }));
    try testing.expectEqual(Detection.none, detect(""));
}
