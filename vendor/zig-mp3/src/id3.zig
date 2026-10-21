// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Reading ID3 metadata.
//!
//! `tags.zig` finds these blocks and says how far to step over them, which is
//! all the decoder needs.  This reads what is inside them: ID3v1 and v1.1 at
//! the end of a file, and ID3v2.2, v2.3 and v2.4 at the front.
//!
//! Everything a tag yields is decoded to UTF-8, whatever the frame said it
//! was encoded in, so a caller never has to think about Latin-1 or UTF-16.
//! A tag owns its strings; `deinit` releases them.
//!
//! Tags come from strangers and are frequently malformed, so nothing here
//! trusts a length it is given.  A frame that runs past the end of the tag,
//! or claims a size of zero, or is compressed or encrypted, ends the frame
//! walk or is skipped rather than being made to fit.

const std = @import("std");

const Allocator = std.mem.Allocator;
const genres = @import("tables/id3_genres.zig");
const tags = @import("tags.zig");

pub const Version = enum {
    /// ID3v1 or v1.1, the fixed 128 byte block at the end of a file.
    v1,
    v2_2,
    v2_3,
    v2_4,

    pub fn isV2(self: Version) bool {
        return self != .v1;
    }
};

pub const Error = error{
    /// The frame walk found nothing that could be a frame.
    Malformed,
} || Allocator.Error;

/// One frame of a tag.
pub const Frame = struct {
    /// The frame identifier: four characters on ID3v2.3 and v2.4, three on
    /// v2.2, and for a tag synthesized from ID3v1 the v2.3 equivalent.
    id: [4]u8,
    /// The frame's payload, after unsynchronization, borrowed from the tag.
    /// Useful for the frames this does not interpret -- attached pictures,
    /// say.
    raw: []const u8,
    /// The frame's text, decoded to UTF-8, or empty for a frame that holds
    /// no text.  A text frame may carry several values, which is how ID3v2.4
    /// writes more than one artist; most callers want the first.
    values: []const []const u8,

    /// The identifier as a string, without the padding a v2.2 identifier has.
    pub fn name(self: *const Frame) []const u8 {
        return std.mem.sliceTo(&self.id, 0);
    }

    pub fn is(self: *const Frame, id: []const u8) bool {
        return std.mem.eql(u8, self.name(), id);
    }

    /// The frame's first value, if it has one.
    pub fn value(self: *const Frame) ?[]const u8 {
        return if (self.values.len == 0) null else self.values[0];
    }
};

/// A track number or disc number, which ID3 writes as "3" or "3/12".
pub const Position = struct {
    number: u32,
    total: ?u32 = null,
};

pub const Tag = struct {
    version: Version,
    frames: []const Frame,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Tag) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// The first frame with one of these identifiers.  Several are accepted
    /// because the identifiers were renamed between ID3v2.2 and v2.3, and
    /// again for a few fields in v2.4.
    pub fn frame(self: *const Tag, ids: []const []const u8) ?*const Frame {
        for (ids) |id| {
            for (self.frames) |*candidate| {
                if (candidate.is(id)) return candidate;
            }
        }
        return null;
    }

    /// The first value of the first frame with one of these identifiers.
    pub fn text(self: *const Tag, ids: []const []const u8) ?[]const u8 {
        const found = self.frame(ids) orelse return null;
        const first = found.value() orelse return null;
        return if (first.len == 0) null else first;
    }

    pub fn title(self: *const Tag) ?[]const u8 {
        return self.text(&.{ "TIT2", "TT2" });
    }
    pub fn artist(self: *const Tag) ?[]const u8 {
        return self.text(&.{ "TPE1", "TP1" });
    }
    pub fn albumArtist(self: *const Tag) ?[]const u8 {
        return self.text(&.{ "TPE2", "TP2" });
    }
    pub fn album(self: *const Tag) ?[]const u8 {
        return self.text(&.{ "TALB", "TAL" });
    }
    pub fn composer(self: *const Tag) ?[]const u8 {
        return self.text(&.{ "TCOM", "TCM" });
    }
    /// The value of a user defined text frame with this description.  These
    /// are how a tagger stores anything the standard has no frame for, and
    /// several taggers -- ffmpeg among them -- reach for one in preference to
    /// the standard frame even where there is one.  The description is
    /// matched without regard to case, since writers disagree about it.
    pub fn userText(self: *const Tag, description: []const u8) ?[]const u8 {
        for (self.frames) |*candidate| {
            if (!candidate.is("TXXX") and !candidate.is("TXX")) continue;
            if (candidate.values.len < 2) continue;
            if (!std.ascii.eqlIgnoreCase(candidate.values[0], description)) continue;
            return if (candidate.values[1].len == 0) null else candidate.values[1];
        }
        return null;
    }

    pub fn comment(self: *const Tag) ?[]const u8 {
        return self.text(&.{ "COMM", "COM" }) orelse self.userText("comment");
    }

    /// The recording year.  ID3v2.4 replaced the four digit year with a full
    /// timestamp, so this may be "2006" or "2006-05-01T13:00".
    pub fn year(self: *const Tag) ?[]const u8 {
        return self.text(&.{ "TDRC", "TYER", "TYE", "TDRL" });
    }

    /// The genre.  ID3v1 stores a number, and ID3v2 may too, written bare or
    /// in parentheses; all three forms resolve to a name here.
    pub fn genre(self: *const Tag) ?[]const u8 {
        const raw = self.text(&.{ "TCON", "TCO" }) orelse return null;
        var body = raw;
        if (body.len >= 3 and body[0] == '(') {
            const close = std.mem.indexOfScalar(u8, body, ')') orelse return raw;
            // "(17)Rock" names the genre twice; prefer the spelled out one.
            if (close + 1 < body.len) return body[close + 1 ..];
            body = body[1..close];
        }
        const index = std.fmt.parseInt(u8, body, 10) catch return raw;
        return genres.name(index) orelse raw;
    }

    pub fn track(self: *const Tag) ?Position {
        return parsePosition(self.text(&.{ "TRCK", "TRK" }) orelse return null);
    }

    pub fn disc(self: *const Tag) ?Position {
        return parsePosition(self.text(&.{ "TPOS", "TPA" }) orelse return null);
    }
};

fn parsePosition(raw: []const u8) ?Position {
    var parts = std.mem.splitScalar(u8, raw, '/');
    const first = std.mem.trim(u8, parts.first(), " ");
    const number = std.fmt.parseInt(u32, first, 10) catch return null;
    const rest = parts.next() orelse return .{ .number = number };
    const total = std.fmt.parseInt(u32, std.mem.trim(u8, rest, " "), 10) catch null;
    return .{ .number = number, .total = total };
}

// ------------------------------------------------------------- text ---------

const replacement = "\u{fffd}";

/// Latin-1 is a subset of Unicode by code point, so every byte is one code
/// point and the conversion cannot fail.
fn latin1ToUtf8(gpa: Allocator, bytes: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.ensureTotalCapacity(gpa, bytes.len);
    for (bytes) |byte| {
        if (byte < 0x80) {
            try out.append(gpa, byte);
        } else {
            try out.append(gpa, 0xc0 | (byte >> 6));
            try out.append(gpa, 0x80 | (byte & 0x3f));
        }
    }
    return out.toOwnedSlice(gpa);
}

/// Lenient UTF-16: an unpaired surrogate or a trailing odd byte becomes the
/// replacement character rather than an error, because a tag that is wrong
/// about its own text should still give up the rest of its fields.
fn utf16ToUtf8(
    gpa: Allocator,
    bytes: []const u8,
    endian: std.builtin.Endian,
) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.ensureTotalCapacity(gpa, bytes.len);

    var i: usize = 0;
    while (i + 1 < bytes.len) : (i += 2) {
        const unit = std.mem.readInt(u16, bytes[i..][0..2], endian);
        var code: u21 = unit;
        if (unit >= 0xd800 and unit <= 0xdbff) {
            const low = if (i + 3 < bytes.len)
                std.mem.readInt(u16, bytes[i + 2 ..][0..2], endian)
            else
                0;
            if (low >= 0xdc00 and low <= 0xdfff) {
                code = 0x10000 +
                    ((@as(u21, unit - 0xd800) << 10) | @as(u21, low - 0xdc00));
                i += 2;
            } else {
                try out.appendSlice(gpa, replacement);
                continue;
            }
        } else if (unit >= 0xdc00 and unit <= 0xdfff) {
            try out.appendSlice(gpa, replacement);
            continue;
        }
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(code, &encoded) catch {
            try out.appendSlice(gpa, replacement);
            continue;
        };
        try out.appendSlice(gpa, encoded[0..len]);
    }
    if (i < bytes.len) try out.appendSlice(gpa, replacement);
    return out.toOwnedSlice(gpa);
}

pub const Encoding = enum(u8) {
    latin1 = 0,
    /// UTF-16 with a byte order mark.
    utf16_bom = 1,
    /// UTF-16 big endian, no mark.  ID3v2.4 only.
    utf16_be = 2,
    /// ID3v2.4 only.
    utf8 = 3,
    _,
};

/// Decode a frame's text to UTF-8.  Values within a frame are separated by a
/// null, and stay separated here.
fn decodeText(
    gpa: Allocator,
    encoding: Encoding,
    bytes: []const u8,
) Allocator.Error![]const []const u8 {
    const decoded: []u8 = switch (encoding) {
        .latin1 => try latin1ToUtf8(gpa, bytes),
        .utf16_bom => blk: {
            // The mark is required here but is regularly missing.  Little
            // endian is the better guess when it is: it is what the taggers
            // that omit it write.
            if (bytes.len >= 2) {
                const mark = std.mem.readInt(u16, bytes[0..2], .little);
                if (mark == 0xfeff) break :blk try utf16ToUtf8(gpa, bytes[2..], .little);
                if (mark == 0xfffe) break :blk try utf16ToUtf8(gpa, bytes[2..], .big);
            }
            break :blk try utf16ToUtf8(gpa, bytes, .little);
        },
        .utf16_be => try utf16ToUtf8(gpa, bytes, .big),
        .utf8 => if (std.unicode.utf8ValidateSlice(bytes))
            try gpa.dupe(u8, bytes)
        else
            // Mislabelled Latin-1 is far more common than genuinely broken
            // UTF-8, and reading it that way recovers the text.
            try latin1ToUtf8(gpa, bytes),
        // An encoding the standard does not define; Latin-1 is the safest
        // reading, since it cannot fail and leaves ASCII intact.
        _ => try latin1ToUtf8(gpa, bytes),
    };

    var values: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, decoded, 0);
    while (parts.next()) |part| {
        // A single trailing null is a terminator, not an empty value.
        if (part.len == 0 and parts.index == null) break;
        try values.append(gpa, stripByteOrderMark(part));
    }
    return values.toOwnedSlice(gpa);
}

/// A byte order mark belongs to the encoding, not to the text.  Writers that
/// put several UTF-16 strings in one frame commonly mark each of them, so
/// this has to be done per value rather than once for the frame.
fn stripByteOrderMark(text: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, text, "\u{feff}")) text[3..] else text;
}

// ------------------------------------------------------------- ID3v2 --------

/// Undo the unsynchronization scheme, which hides 0xff 0x00 in place of a
/// 0xff followed by a byte that would otherwise look like a frame sync.
fn unsynchronize(gpa: Allocator, bytes: []const u8) Allocator.Error![]u8 {
    var out = try std.ArrayList(u8).initCapacity(gpa, bytes.len);
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        try out.append(gpa, bytes[i]);
        if (bytes[i] == 0xff and i + 1 < bytes.len and bytes[i + 1] == 0x00) i += 1;
    }
    return out.toOwnedSlice(gpa);
}

fn syncsafe(bytes: [4]u8) u32 {
    var value: u32 = 0;
    for (bytes) |byte| value = (value << 7) | (byte & 0x7f);
    return value;
}

/// Frame identifiers are upper case letters and digits.  Checking this is how
/// the walk tells a frame from padding, and how it tells whether a size it
/// guessed at was right.
fn plausibleId(id: []const u8) bool {
    for (id) |c| {
        if (!std.ascii.isUpper(c) and !std.ascii.isDigit(c)) return false;
    }
    return true;
}

const FrameLayout = struct { id_len: usize, header_len: usize };

fn layoutFor(version: Version) FrameLayout {
    return switch (version) {
        .v2_2 => .{ .id_len = 3, .header_len = 6 },
        else => .{ .id_len = 4, .header_len = 10 },
    };
}

/// ID3v2.4 states frame sizes as syncsafe integers, but a good many taggers
/// wrote them plain.  Where the two readings differ, the one that lands on
/// something that looks like the next frame is the right one.
fn frameSize(version: Version, raw: []const u8, body: []const u8, at: usize) usize {
    if (version == .v2_2) {
        return (@as(usize, raw[0]) << 16) | (@as(usize, raw[1]) << 8) | raw[2];
    }
    const plain = std.mem.readInt(u32, raw[0..4], .big);
    if (version == .v2_3) return plain;

    const safe = syncsafe(raw[0..4].*);
    if (safe == plain) return safe;

    const layout = layoutFor(version);
    const follows = struct {
        fn f(b: []const u8, next: usize, id_len: usize) bool {
            if (next == b.len) return true; // ends the tag exactly
            if (next + id_len > b.len) return false;
            if (b[next] == 0) return true; // padding
            return plausibleId(b[next..][0..id_len]);
        }
    }.f;

    const after_safe = at + layout.header_len + safe;
    const after_plain = at + layout.header_len + plain;
    if (after_safe <= body.len and follows(body, after_safe, layout.id_len)) return safe;
    if (after_plain <= body.len and follows(body, after_plain, layout.id_len)) return plain;
    return safe;
}

/// Parse an ID3v2 tag. `data` must begin with the tag's ten byte header and
/// hold at least the whole tag; anything after it is ignored.
pub fn parseV2(gpa: Allocator, data: []const u8) Error!?Tag {
    if (data.len < 10 or !std.mem.eql(u8, data[0..3], "ID3")) return null;
    if (data[3] == 0xff or data[4] == 0xff) return null;

    const version: Version = switch (data[3]) {
        2 => .v2_2,
        3 => .v2_3,
        4 => .v2_4,
        // A major version this does not know cannot be walked; the tag is
        // still well formed, so this is not an error, just nothing to read.
        else => return null,
    };

    const flags = data[5];
    const unsynchronized = flags & 0x80 != 0;
    const extended = flags & 0x40 != 0;

    for (data[6..10]) |byte| {
        if (byte & 0x80 != 0) return null; // not a syncsafe size, so not a tag
    }
    const declared = syncsafe(data[6..10].*);
    const available = @min(@as(usize, declared), data.len - 10);

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const scratch = arena.allocator();

    // Whole-tag unsynchronization is an ID3v2.3 thing; v2.4 marks it per
    // frame instead, and this flag then means every frame has it set.
    var body: []const u8 = data[10..][0..available];
    if (unsynchronized and version != .v2_4) {
        body = try unsynchronize(scratch, body);
    } else {
        body = try scratch.dupe(u8, body);
    }

    var at: usize = 0;
    if (extended) {
        if (body.len < at + 4) return .{
            .version = version,
            .frames = &.{},
            .arena = arena,
        };
        const size: usize = if (version == .v2_4)
            // v2.4 counts the extended header's own size in the figure.
            syncsafe(body[0..4].*)
        else
            // v2.3 does not, and states it plain.
            std.mem.readInt(u32, body[0..4], .big) + 4;
        at = @min(size, body.len);
    }

    const layout = layoutFor(version);
    var frames: std.ArrayList(Frame) = .empty;

    while (at + layout.header_len <= body.len) {
        const id = body[at..][0..layout.id_len];
        if (id[0] == 0) break; // padding runs to the end of the tag
        if (!plausibleId(id)) break;

        const size = frameSize(version, body[at + layout.id_len ..], body, at);
        const start = at + layout.header_len;
        if (size == 0 or start + size > body.len) break;

        // The two flag bytes exist from v2.3 on.
        const format_flags: u8 = if (version == .v2_2) 0 else body[at + 9];
        at = start + size;

        var payload = body[start..][0..size];

        // Compressed and encrypted frames need machinery this does not have;
        // skipping them keeps the rest of the tag readable.  The bits moved
        // between v2.3 and v2.4.
        const unreadable = switch (version) {
            .v1, .v2_2 => false,
            .v2_3 => format_flags & 0xc0 != 0, // compression, encryption
            .v2_4 => format_flags & 0x0c != 0,
        };
        if (unreadable) continue;

        if (version == .v2_4) {
            if (format_flags & 0x40 != 0) {
                if (payload.len == 0) continue;
                payload = payload[1..]; // group identifier
            }
            if (format_flags & 0x01 != 0) {
                if (payload.len < 4) continue;
                payload = payload[4..]; // data length indicator
            }
            if (format_flags & 0x02 != 0 or unsynchronized) {
                payload = try unsynchronize(scratch, payload);
            }
        }

        var entry: Frame = .{
            .id = @splat(0),
            .raw = payload,
            .values = &.{},
        };
        @memcpy(entry.id[0..layout.id_len], id);
        entry.values = try frameValues(scratch, entry.name(), payload);
        try frames.append(scratch, entry);
    }

    return .{
        .version = version,
        .frames = try frames.toOwnedSlice(scratch),
        .arena = arena,
    };
}

/// Pull the text out of a frame, for the frame kinds that hold any.
fn frameValues(gpa: Allocator, id: []const u8, payload: []const u8) Allocator.Error![]const []const u8 {
    if (id.len == 0) return &.{};

    // Comments and unsynchronized lyrics carry a language and a description
    // ahead of the text they are actually about.
    if (std.mem.eql(u8, id, "COMM") or std.mem.eql(u8, id, "COM") or
        std.mem.eql(u8, id, "USLT") or std.mem.eql(u8, id, "ULT"))
    {
        if (payload.len < 4) return &.{};
        const decoded = try decodeText(gpa, @enumFromInt(payload[0]), payload[4..]);
        // The description comes first and the comment after it; a frame with
        // no description leaves an empty one, which is normal.
        return if (decoded.len > 1) decoded[1..] else decoded;
    }

    // A URL frame is a bare Latin-1 URL, except the user defined one, which
    // has an encoding byte and a description like a text frame.
    if (id[0] == 'W') {
        if (std.mem.eql(u8, id, "WXXX") or std.mem.eql(u8, id, "WXX")) {
            if (payload.len < 1) return &.{};
            const decoded = try decodeText(gpa, @enumFromInt(payload[0]), payload[1..]);
            return if (decoded.len > 1) decoded[1..] else decoded;
        }
        return try decodeText(gpa, .latin1, payload);
    }

    if (id[0] != 'T') return &.{};
    if (payload.len < 1) return &.{};
    return try decodeText(gpa, @enumFromInt(payload[0]), payload[1..]);
}

// ------------------------------------------------------------- ID3v1 --------

/// ID3v1 pads its fields with nulls, spaces, or both.
fn trimV1(field: []const u8) []const u8 {
    return std.mem.trim(u8, std.mem.sliceTo(field, 0), " \t\r\n");
}

/// Parse the 128 byte ID3v1 block. `data` must begin with it.
///
/// The result is an ID3v2 shaped tag, with the fields under the identifiers
/// ID3v2.3 would give them, so that a caller need not care which it got.
pub fn parseV1(gpa: Allocator, data: []const u8) Error!?Tag {
    if (data.len < 128 or !std.mem.eql(u8, data[0..3], "TAG")) return null;

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const scratch = arena.allocator();

    var frames: std.ArrayList(Frame) = .empty;

    // ID3v1.1 took the last two bytes of the comment for a track number: a
    // null, then the track. A comment that fills the field is plain v1.
    var comment_field: []const u8 = data[97..127];
    var track: ?u8 = null;
    if (comment_field[28] == 0 and comment_field[29] != 0) {
        track = comment_field[29];
        comment_field = comment_field[0..28];
    }

    const fields = [_]struct { id: []const u8, bytes: []const u8 }{
        .{ .id = "TIT2", .bytes = data[3..33] },
        .{ .id = "TPE1", .bytes = data[33..63] },
        .{ .id = "TALB", .bytes = data[63..93] },
        .{ .id = "TYER", .bytes = data[93..97] },
        .{ .id = "COMM", .bytes = comment_field },
    };
    for (fields) |field| {
        const trimmed = trimV1(field.bytes);
        if (trimmed.len == 0) continue;
        try frames.append(scratch, try v1Frame(scratch, field.id, trimmed));
    }

    if (track) |number| {
        var buffer: [4]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d}", .{number}) catch unreachable;
        try frames.append(scratch, try v1Frame(scratch, "TRCK", text));
    }

    if (genres.name(data[127])) |name| {
        try frames.append(scratch, try v1Frame(scratch, "TCON", name));
    }

    return .{
        .version = .v1,
        .frames = try frames.toOwnedSlice(scratch),
        .arena = arena,
    };
}

fn v1Frame(gpa: Allocator, id: []const u8, text: []const u8) Allocator.Error!Frame {
    // ID3v1 is nominally Latin-1, but plenty of taggers -- ffmpeg among them
    // -- write UTF-8 into it, and text that is already valid UTF-8 was almost
    // certainly meant that way.
    const owned = if (std.unicode.utf8ValidateSlice(text))
        try gpa.dupe(u8, text)
    else
        try latin1ToUtf8(gpa, text);

    const values = try gpa.alloc([]const u8, 1);
    values[0] = owned;

    var frame: Frame = .{ .id = @splat(0), .raw = owned, .values = values };
    @memcpy(frame.id[0..id.len], id);
    return frame;
}

// ------------------------------------------------------------- whole file ---

/// Read whatever metadata a file carries: the ID3v2 tag at its front if it
/// has one, and otherwise the ID3v1 block at its end.
///
/// ID3v2 is preferred because it can say everything ID3v1 can and more; a
/// caller that wants both can ask for them separately.
pub fn parse(gpa: Allocator, data: []const u8) Error!?Tag {
    switch (tags.detect(data)) {
        .found => |tag| {
            if (tag.kind == .id3v2) {
                if (try parseV2(gpa, data)) |found| return found;
            }
        },
        else => {},
    }
    if (data.len >= 128) {
        if (try parseV1(gpa, data[data.len - 128 ..])) |found| return found;
    }
    return null;
}

const testing = std.testing;

/// Assemble an ID3v2 tag around some already-built frames.
fn buildTag(gpa: Allocator, major: u8, flags: u8, body: []const u8) ![]u8 {
    const out = try gpa.alloc(u8, 10 + body.len);
    @memcpy(out[0..3], "ID3");
    out[3] = major;
    out[4] = 0;
    out[5] = flags;
    var size = body.len;
    var n: usize = 4;
    while (n > 0) {
        n -= 1;
        out[6 + n] = @intCast(size & 0x7f);
        size >>= 7;
    }
    @memcpy(out[10..], body);
    return out;
}

/// One ID3v2.3 or v2.4 frame. `size_is_syncsafe` writes the size the way
/// v2.4 says to; passing false is how a good many real taggers get it wrong.
fn buildFrame(
    gpa: Allocator,
    id: []const u8,
    payload: []const u8,
    size_is_syncsafe: bool,
) ![]u8 {
    const out = try gpa.alloc(u8, 10 + payload.len);
    @memcpy(out[0..4], id);
    if (size_is_syncsafe) {
        var size = payload.len;
        var n: usize = 4;
        while (n > 0) {
            n -= 1;
            out[4 + n] = @intCast(size & 0x7f);
            size >>= 7;
        }
    } else {
        std.mem.writeInt(u32, out[4..8], @intCast(payload.len), .big);
    }
    out[8] = 0;
    out[9] = 0;
    @memcpy(out[10..], payload);
    return out;
}

fn latin1Frame(gpa: Allocator, id: []const u8, text: []const u8) ![]u8 {
    const payload = try std.mem.concat(gpa, u8, &.{ &[_]u8{0}, text });
    defer gpa.free(payload);
    return buildFrame(gpa, id, payload, true);
}

test "an ID3v2.3 tag yields its text frames" {
    const gpa = testing.allocator;
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(gpa);
    for ([_][2][]const u8{
        .{ "TIT2", "Sonata" },
        .{ "TPE1", "A Performer" },
        .{ "TALB", "A Record" },
        .{ "TYER", "1999" },
        .{ "TRCK", "3/12" },
    }) |pair| {
        const frame = try latin1Frame(gpa, pair[0], pair[1]);
        defer gpa.free(frame);
        try body.appendSlice(gpa, frame);
    }
    // Padding after the frames, which is where the walk must stop.
    const padding: [32]u8 = @splat(0);
    try body.appendSlice(gpa, &padding);

    const raw = try buildTag(gpa, 3, 0, body.items);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();

    try testing.expectEqual(Version.v2_3, tag.version);
    try testing.expectEqual(@as(usize, 5), tag.frames.len);
    try testing.expectEqualStrings("Sonata", tag.title().?);
    try testing.expectEqualStrings("A Performer", tag.artist().?);
    try testing.expectEqualStrings("A Record", tag.album().?);
    try testing.expectEqualStrings("1999", tag.year().?);
    try testing.expectEqual(Position{ .number = 3, .total = 12 }, tag.track().?);
    try testing.expect(tag.genre() == null);
}

test "Latin-1 text becomes UTF-8" {
    const gpa = testing.allocator;
    // 0xe9 is e-acute in Latin-1, U+00E9.
    const frame = try latin1Frame(gpa, "TPE1", &[_]u8{ 'C', 'a', 'f', 0xe9 });
    defer gpa.free(frame);
    const raw = try buildTag(gpa, 3, 0, frame);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    try testing.expectEqualStrings("Café", tag.artist().?);
}

test "UTF-16 text with either byte order mark becomes UTF-8" {
    const gpa = testing.allocator;
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try payload.append(gpa, 1); // encoding: UTF-16 with a mark
        try payload.appendSlice(gpa, if (endian == .little) "\xff\xfe" else "\xfe\xff");
        for ([_]u16{ 'C', 'a', 'f', 0xe9, 0x266b }) |unit| {
            var bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &bytes, unit, endian);
            try payload.appendSlice(gpa, &bytes);
        }
        const frame = try buildFrame(gpa, "TIT2", payload.items, true);
        defer gpa.free(frame);
        const raw = try buildTag(gpa, 3, 0, frame);
        defer gpa.free(raw);

        var tag = (try parseV2(gpa, raw)).?;
        defer tag.deinit();
        try testing.expectEqualStrings("Café♫", tag.title().?);
    }
}

test "a surrogate pair becomes one code point and a lone one is replaced" {
    const gpa = testing.allocator;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try payload.append(gpa, 1);
    try payload.appendSlice(gpa, "\xff\xfe");
    // U+1F3B5, then an unpaired high surrogate.
    for ([_]u16{ 0xd83c, 0xdfb5, 0xd800, 'x' }) |unit| {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, unit, .little);
        try payload.appendSlice(gpa, &bytes);
    }
    const frame = try buildFrame(gpa, "TIT2", payload.items, true);
    defer gpa.free(frame);
    const raw = try buildTag(gpa, 3, 0, frame);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    try testing.expectEqualStrings("🎵\u{fffd}x", tag.title().?);
}

test "ID3v2.4 keeps every value of a multi-valued frame" {
    const gpa = testing.allocator;
    const payload = "\x03" ++ "First\x00Second\x00Third";
    const frame = try buildFrame(gpa, "TPE1", payload, true);
    defer gpa.free(frame);
    const raw = try buildTag(gpa, 4, 0, frame);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    const artists = tag.frame(&.{"TPE1"}).?;
    try testing.expectEqual(@as(usize, 3), artists.values.len);
    try testing.expectEqualStrings("First", artists.values[0]);
    try testing.expectEqualStrings("Third", artists.values[2]);
    // The convenience accessor takes the first, which is what a caller
    // wanting one artist means.
    try testing.expectEqualStrings("First", tag.artist().?);
}

test "an ID3v2.4 frame size written the wrong way is still read" {
    // Sizes above 127 are where a plain integer and a syncsafe one diverge,
    // and where taggers that got it wrong become visible.
    const gpa = testing.allocator;
    var long: [201]u8 = undefined;
    long[0] = 0;
    @memset(long[1..], 'x');
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(gpa);
    const first = try buildFrame(gpa, "TIT2", &long, false); // plain size
    defer gpa.free(first);
    try body.appendSlice(gpa, first);
    const second = try latin1Frame(gpa, "TPE1", "Recovered");
    defer gpa.free(second);
    try body.appendSlice(gpa, second);

    const raw = try buildTag(gpa, 4, 0, body.items);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    try testing.expectEqual(@as(usize, 200), tag.title().?.len);
    // The frame after it is the real proof: a mis-read size would have put
    // the walk somewhere meaningless.
    try testing.expectEqualStrings("Recovered", tag.artist().?);
}

test "ID3v2.2 uses three character identifiers" {
    const gpa = testing.allocator;
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(gpa);
    for ([_][2][]const u8{ .{ "TT2", "Older" }, .{ "TP1", "Older Artist" } }) |pair| {
        const payload = try std.mem.concat(gpa, u8, &.{ &[_]u8{0}, pair[1] });
        defer gpa.free(payload);
        const frame = try gpa.alloc(u8, 6 + payload.len);
        defer gpa.free(frame);
        @memcpy(frame[0..3], pair[0]);
        frame[3] = 0;
        frame[4] = @intCast(payload.len >> 8);
        frame[5] = @intCast(payload.len & 0xff);
        @memcpy(frame[6..], payload);
        try body.appendSlice(gpa, frame);
    }
    const raw = try buildTag(gpa, 2, 0, body.items);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    try testing.expectEqual(Version.v2_2, tag.version);
    try testing.expectEqualStrings("Older", tag.title().?);
    try testing.expectEqualStrings("Older Artist", tag.artist().?);
    try testing.expectEqualStrings("TT2", tag.frames[0].name());
}

test "unsynchronization is undone before the frames are walked" {
    const gpa = testing.allocator;
    // The frame's text is 'a', 0xff, 'b'.  A 0xff in the tag could be read as
    // a frame sync by something scanning for audio, so the writer escapes it
    // to 0xff 0x00 -- and the frame's stated size counts the text as it is
    // after that escaping is undone, not as it sits in the file.
    var frame: std.ArrayList(u8) = .empty;
    defer frame.deinit(gpa);
    try frame.appendSlice(gpa, "TIT2");
    try frame.appendSlice(gpa, &[_]u8{ 0, 0, 0, 4 }); // encoding byte plus three
    try frame.appendSlice(gpa, &[_]u8{ 0, 0 }); // flags
    try frame.appendSlice(gpa, &[_]u8{ 0x00, 'a', 0xff, 0x00, 'b' }); // five, escaped

    const raw = try buildTag(gpa, 3, 0x80, frame.items);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    // A lone 0xff is not valid UTF-8, so the text reads as Latin-1: U+00FF.
    try testing.expectEqualStrings("a\u{00ff}b", tag.title().?);
}

test "a comment frame drops its language and description" {
    const gpa = testing.allocator;
    const payload = "\x00" ++ "eng" ++ "a description\x00" ++ "the comment";
    const frame = try buildFrame(gpa, "COMM", payload, true);
    defer gpa.free(frame);
    const raw = try buildTag(gpa, 3, 0, frame);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    try testing.expectEqualStrings("the comment", tag.comment().?);
}

test "an extended header is stepped over" {
    const gpa = testing.allocator;
    const frame = try latin1Frame(gpa, "TIT2", "Behind an extended header");
    defer gpa.free(frame);

    // ID3v2.3 states the extended header's size without counting the four
    // bytes the size itself takes.
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(gpa);
    try body.appendSlice(gpa, &[_]u8{ 0, 0, 0, 6 });
    const padding: [6]u8 = @splat(0);
    try body.appendSlice(gpa, &padding);
    try body.appendSlice(gpa, frame);

    const raw = try buildTag(gpa, 3, 0x40, body.items);
    defer gpa.free(raw);
    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    try testing.expectEqualStrings("Behind an extended header", tag.title().?);
}

test "compressed and encrypted frames are skipped, not misread" {
    const gpa = testing.allocator;
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(gpa);

    var compressed = try latin1Frame(gpa, "TIT2", "compressed rubbish");
    defer gpa.free(compressed);
    compressed[9] = 0x80; // ID3v2.3 compression flag
    try body.appendSlice(gpa, compressed);

    const plain = try latin1Frame(gpa, "TPE1", "Readable");
    defer gpa.free(plain);
    try body.appendSlice(gpa, plain);

    const raw = try buildTag(gpa, 3, 0, body.items);
    defer gpa.free(raw);
    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    try testing.expect(tag.title() == null);
    try testing.expectEqualStrings("Readable", tag.artist().?);
}

test "genres resolve whether written as a name, a number or both" {
    const gpa = testing.allocator;
    for ([_][2][]const u8{
        .{ "Rock", "Rock" },
        .{ "17", "Rock" },
        .{ "(17)", "Rock" },
        .{ "(17)Rock", "Rock" },
        .{ "(17)Prog Rock", "Prog Rock" },
        .{ "Not A Number", "Not A Number" },
        .{ "(RX)", "(RX)" },
        .{ "255", "255" }, // past the end of the list
    }) |pair| {
        const frame = try latin1Frame(gpa, "TCON", pair[0]);
        defer gpa.free(frame);
        const raw = try buildTag(gpa, 3, 0, frame);
        defer gpa.free(raw);
        var tag = (try parseV2(gpa, raw)).?;
        defer tag.deinit();
        try testing.expectEqualStrings(pair[1], tag.genre().?);
    }
}

test "an ID3v1 block reads as a tag of the same shape" {
    const gpa = testing.allocator;
    var raw: [128]u8 = @splat(0);
    @memcpy(raw[0..3], "TAG");
    @memcpy(raw[3..][0.."A Title".len], "A Title");
    @memcpy(raw[33..][0.."An Artist".len], "An Artist");
    @memcpy(raw[63..][0.."An Album".len], "An Album");
    @memcpy(raw[93..][0..4], "1987");
    @memcpy(raw[97..][0.."A comment".len], "A comment");
    raw[127] = 17; // Rock

    var tag = (try parseV1(gpa, &raw)).?;
    defer tag.deinit();
    try testing.expectEqual(Version.v1, tag.version);
    try testing.expectEqualStrings("A Title", tag.title().?);
    try testing.expectEqualStrings("An Artist", tag.artist().?);
    try testing.expectEqualStrings("An Album", tag.album().?);
    try testing.expectEqualStrings("1987", tag.year().?);
    try testing.expectEqualStrings("A comment", tag.comment().?);
    try testing.expectEqualStrings("Rock", tag.genre().?);
    try testing.expect(tag.track() == null);
}

test "ID3v1.1 takes the last of the comment for a track number" {
    const gpa = testing.allocator;
    var raw: [128]u8 = @splat(0);
    @memcpy(raw[0..3], "TAG");
    @memcpy(raw[97..][0.."Short".len], "Short");
    raw[97 + 28] = 0;
    raw[97 + 29] = 7;
    raw[127] = 255; // no genre

    var tag = (try parseV1(gpa, &raw)).?;
    defer tag.deinit();
    try testing.expectEqualStrings("Short", tag.comment().?);
    try testing.expectEqual(Position{ .number = 7, .total = null }, tag.track().?);
    try testing.expect(tag.genre() == null);

    // A comment filling the field is plain ID3v1 and keeps all thirty bytes.
    var full: [128]u8 = @splat(0);
    @memcpy(full[0..3], "TAG");
    @memset(full[97..127], 'x');
    full[127] = 255;
    var plain = (try parseV1(gpa, &full)).?;
    defer plain.deinit();
    try testing.expectEqual(@as(usize, 30), plain.comment().?.len);
    try testing.expect(plain.track() == null);
}

test "ID3v1 fields are trimmed of the padding they are written with" {
    const gpa = testing.allocator;
    var raw: [128]u8 = @splat(' ');
    @memcpy(raw[0..3], "TAG");
    @memcpy(raw[3..][0.."Padded".len], "Padded");
    raw[127] = 255;
    var tag = (try parseV1(gpa, &raw)).?;
    defer tag.deinit();
    try testing.expectEqualStrings("Padded", tag.title().?);
    // A field of nothing but padding is absent, not empty.
    try testing.expect(tag.artist() == null);
}

test "parse prefers the tag at the front and falls back to the one at the end" {
    const gpa = testing.allocator;
    const frame = try latin1Frame(gpa, "TIT2", "From ID3v2");
    defer gpa.free(frame);
    const v2 = try buildTag(gpa, 3, 0, frame);
    defer gpa.free(v2);

    var v1: [128]u8 = @splat(0);
    @memcpy(v1[0..3], "TAG");
    @memcpy(v1[3..][0.."From ID3v1".len], "From ID3v1");
    v1[127] = 255;

    const both = try std.mem.concat(gpa, u8, &.{ v2, "audio would go here", &v1 });
    defer gpa.free(both);
    var preferred = (try parse(gpa, both)).?;
    defer preferred.deinit();
    try testing.expectEqualStrings("From ID3v2", preferred.title().?);

    const only_v1 = try std.mem.concat(gpa, u8, &.{ "audio would go here", &v1 });
    defer gpa.free(only_v1);
    var fallback = (try parse(gpa, only_v1)).?;
    defer fallback.deinit();
    try testing.expectEqualStrings("From ID3v1", fallback.title().?);

    try testing.expect(try parse(gpa, "no tags here at all") == null);
}

test "nothing that is not a tag is read as one" {
    const gpa = testing.allocator;
    try testing.expect(try parseV2(gpa, "") == null);
    try testing.expect(try parseV2(gpa, "ID3") == null);
    try testing.expect(try parseV2(gpa, &[_]u8{
        0xff, 0xfb, 0x90, 0x00,
        0xff, 0xfb, 0x90, 0x00,
        0xff, 0xfb, 0x90, 0x00,
        0xff, 0xfb, 0x90, 0x00,
    }) == null);
    // A major version this does not know.
    var future: [32]u8 = @splat(0);
    @memcpy(future[0..3], "ID3");
    future[3] = 9;
    try testing.expect(try parseV2(gpa, &future) == null);
    // A size that is not syncsafe means the ten bytes are not a tag header.
    var bad: [32]u8 = @splat(0);
    @memcpy(bad[0..3], "ID3");
    bad[3] = 3;
    bad[8] = 0x80;
    try testing.expect(try parseV2(gpa, &bad) == null);
    try testing.expect(try parseV1(gpa, "TAG") == null);
}

test "a tag whose frames overrun it gives up what it has" {
    const gpa = testing.allocator;
    const good = try latin1Frame(gpa, "TIT2", "Present");
    defer gpa.free(good);
    var overrunning = try latin1Frame(gpa, "TPE1", "Truncated");
    defer gpa.free(overrunning);
    // Claim far more than the tag holds.
    std.mem.writeInt(u32, overrunning[4..8], 100000, .big);

    const body = try std.mem.concat(gpa, u8, &.{ good, overrunning });
    defer gpa.free(body);
    const raw = try buildTag(gpa, 3, 0, body);
    defer gpa.free(raw);

    var tag = (try parseV2(gpa, raw)).?;
    defer tag.deinit();
    try testing.expectEqualStrings("Present", tag.title().?);
    try testing.expect(tag.artist() == null);
}

test "a tag truncated by the file it was read from is still read as far as it goes" {
    const gpa = testing.allocator;
    const frame = try latin1Frame(gpa, "TIT2", "Survives");
    defer gpa.free(frame);
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(gpa);
    try body.appendSlice(gpa, frame);
    const padding: [500]u8 = @splat(0);
    try body.appendSlice(gpa, &padding); // padding the caller never got

    const raw = try buildTag(gpa, 3, 0, body.items);
    defer gpa.free(raw);
    var tag = (try parseV2(gpa, raw[0 .. raw.len - 400])).?;
    defer tag.deinit();
    try testing.expectEqualStrings("Survives", tag.title().?);
}

test "the genre list is the one the standard and its extensions describe" {
    try testing.expectEqual(@as(usize, 192), genres.names.len);
    try testing.expectEqualStrings("Blues", genres.names[0]);
    try testing.expectEqualStrings("Rock", genres.names[17]);
    try testing.expectEqualStrings("Alternative", genres.names[20]);
    try testing.expectEqualStrings("Classical", genres.names[32]);
    // The last of the original specification's list, and the first of
    // Winamp's extension to it.
    try testing.expectEqualStrings("Hard Rock", genres.names[79]);
    try testing.expectEqualStrings("Folk", genres.names[80]);
    try testing.expect(genres.name(191) != null);
    try testing.expect(genres.name(192) == null);
    for (genres.names) |name| try testing.expect(name.len > 0);
}
