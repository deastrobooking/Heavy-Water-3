// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The Xing, Info and VBRI headers.
//!
//! None of these are part of any MPEG standard.  They are a convention: the
//! encoder writes one silent frame at the front of the file and hides in it
//! the things a player cannot otherwise learn without reading the whole
//! stream -- how many frames there are, how long it is, where to seek to, and
//! how much silence the encoder added at each end.
//!
//! The frame carrying one of these is not audio and must not be decoded as
//! such, which is the decoder's main reason for looking.

const std = @import("std");

const Header = @import("header.zig");

pub const Kind = enum {
    /// A variable bit rate stream.
    xing,
    /// The same layout, written by LAME for constant bit rate streams.
    info,
    /// Fraunhofer's equivalent, at a fixed offset.
    vbri,
};

/// The LAME extension that follows the Xing fields.  Its delay and padding
/// are what gapless playback needs: an encoder cannot start encoding at
/// sample zero, so it prepends silence and reports how much.
pub const Lame = struct {
    /// The nine byte encoder identification, such as "LAME3.100".
    encoder: [9]u8,
    /// Samples of silence prepended by the encoder, to drop when playing.
    delay: u16,
    /// Samples of padding at the end, to drop when playing.
    padding: u16,

    pub fn name(self: *const Lame) []const u8 {
        return std.mem.sliceTo(&self.encoder, 0);
    }
};

/// A Layer III decoder cannot emit a sample until it has seen the granule
/// after it, so its output lags the encoder's input by this much.  The figure
/// is a property of the filterbank, is the same in every decoder, and is not
/// included in the encoder's own stated delay -- both have to be dropped.
pub const decoder_delay: u32 = 529;

pub const Info = struct {
    kind: Kind,
    /// Audio frames in the stream, not counting the frame this header is in.
    frames: ?u32 = null,
    /// Bytes of the stream the frame count covers.
    bytes: ?u32 = null,
    /// A hundred-entry seek table: `toc[n]` is the position, in 256ths of
    /// `bytes`, of the point `n` percent of the way through.
    toc: ?[100]u8 = null,
    quality: ?u32 = null,
    lame: ?Lame = null,

    /// Playing time in seconds, if the frame count is known.
    pub fn duration(self: Info, header: Header) ?f64 {
        const frames = self.frames orelse return null;
        var samples: i64 = @as(i64, frames) * header.samplesPerFrame();
        if (self.lame) |lame| samples -= @as(i64, lame.delay) + lame.padding;
        if (samples < 0) samples = 0;
        return @as(f64, @floatFromInt(samples)) / @as(f64, @floatFromInt(header.sampleRate()));
    }

    /// Samples per channel to drop from the front of the decoded stream so
    /// that playback starts where the encoder's input did.
    pub fn leadIn(self: Info) ?u32 {
        const lame = self.lame orelse return null;
        return @as(u32, lame.delay) + decoder_delay;
    }

    /// Samples per channel worth playing, after dropping the silence the
    /// encoder added at both ends.
    pub fn playableSamples(self: Info, header: Header) ?u64 {
        const frames = self.frames orelse return null;
        const lame = self.lame orelse return null;
        const total = @as(i64, frames) * header.samplesPerFrame();
        const playable = total - @as(i64, lame.delay) - @as(i64, lame.padding);
        return if (playable > 0) @intCast(playable) else 0;
    }

    /// Byte offset to seek to for a position `fraction` of the way through,
    /// relative to the start of the stream.  The table has one entry per
    /// percent, so this is coarse -- good enough to start decoding near the
    /// right place, not to land on an exact sample.
    pub fn seekOffset(self: Info, fraction: f64) ?u32 {
        const toc = self.toc orelse return null;
        const bytes = self.bytes orelse return null;
        const clamped = std.math.clamp(fraction, 0, 1);
        const index: usize = @min(99, @as(usize, @intFromFloat(clamped * 100)));
        return @intFromFloat(@as(f64, toc[index]) / 256.0 * @as(f64, @floatFromInt(bytes)));
    }
};

/// Look for one of these headers in `frame`, which must be a whole frame
/// starting at its four byte header.
pub fn parse(header: Header, frame: []const u8) ?Info {
    if (header.layer != .layer3) return null;

    // Xing and Info sit immediately after the side information; VBRI is at a
    // fixed offset instead, and ignores the channel mode.
    const after_side_info = 4 + @as(usize, if (header.crc_protected) 2 else 0) +
        header.sideInfoSize();
    if (parseXing(frame, after_side_info)) |info| return info;
    return parseVbri(frame, 36);
}

fn parseXing(frame: []const u8, at: usize) ?Info {
    if (frame.len < at + 8) return null;
    const magic = frame[at..][0..4];
    const kind: Kind = if (std.mem.eql(u8, magic, "Xing"))
        .xing
    else if (std.mem.eql(u8, magic, "Info"))
        .info
    else
        return null;

    const flags = std.mem.readInt(u32, frame[at + 4 ..][0..4], .big);
    var info: Info = .{ .kind = kind };
    var pos = at + 8;

    if (flags & 1 != 0) {
        if (frame.len < pos + 4) return info;
        info.frames = std.mem.readInt(u32, frame[pos..][0..4], .big);
        pos += 4;
    }
    if (flags & 2 != 0) {
        if (frame.len < pos + 4) return info;
        info.bytes = std.mem.readInt(u32, frame[pos..][0..4], .big);
        pos += 4;
    }
    if (flags & 4 != 0) {
        if (frame.len < pos + 100) return info;
        info.toc = frame[pos..][0..100].*;
        pos += 100;
    }
    if (flags & 8 != 0) {
        if (frame.len < pos + 4) return info;
        info.quality = std.mem.readInt(u32, frame[pos..][0..4], .big);
        pos += 4;
    }

    // The LAME extension always begins 120 bytes past the magic, whatever the
    // flags said, so it is found by offset rather than by following along.
    const lame_at = at + 120;
    if (frame.len >= lame_at + 36 and std.ascii.isPrint(frame[lame_at])) {
        const raw = frame[lame_at + 21 ..][0..3];
        info.lame = .{
            .encoder = frame[lame_at..][0..9].*,
            .delay = (@as(u16, raw[0]) << 4) | (raw[1] >> 4),
            .padding = (@as(u16, raw[1] & 0xf) << 8) | raw[2],
        };
    }
    return info;
}

fn parseVbri(frame: []const u8, at: usize) ?Info {
    if (frame.len < at + 26) return null;
    if (!std.mem.eql(u8, frame[at..][0..4], "VBRI")) return null;
    return .{
        .kind = .vbri,
        .quality = std.mem.readInt(u16, frame[at + 8 ..][0..2], .big),
        .bytes = std.mem.readInt(u32, frame[at + 10 ..][0..4], .big),
        .frames = std.mem.readInt(u32, frame[at + 14 ..][0..4], .big),
    };
}

const testing = std.testing;

const stereo_header = Header.parse(.{ 0xff, 0xfb, 0x90, 0x00 }).?; // MPEG-1 stereo
const mono_header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?; // MPEG-1 mono

test "an Info header is found after the side information" {
    var frame: [417]u8 = @splat(0);
    @memcpy(frame[0..4], &[_]u8{ 0xff, 0xfb, 0x90, 0x00 });
    const at = 4 + 32;
    @memcpy(frame[at..][0..4], "Info");
    std.mem.writeInt(u32, frame[at + 4 ..][0..4], 0b1111, .big);
    std.mem.writeInt(u32, frame[at + 8 ..][0..4], 193, .big);
    std.mem.writeInt(u32, frame[at + 12 ..][0..4], 80666, .big);
    for (0..100) |n| frame[at + 16 + n] = @intCast(n * 256 / 100);
    std.mem.writeInt(u32, frame[at + 116 ..][0..4], 78, .big);

    const info = parse(stereo_header, &frame).?;
    try testing.expectEqual(Kind.info, info.kind);
    try testing.expectEqual(@as(u32, 193), info.frames.?);
    try testing.expectEqual(@as(u32, 80666), info.bytes.?);
    try testing.expectEqual(@as(u32, 78), info.quality.?);
    try testing.expectEqual(@as(u8, 0), info.toc.?[0]);
    try testing.expectEqual(@as(u8, 253), info.toc.?[99]);
}

test "the header sits closer to the front of a mono frame" {
    var frame: [417]u8 = @splat(0);
    const at = 4 + 17;
    @memcpy(frame[at..][0..4], "Xing");
    std.mem.writeInt(u32, frame[at + 4 ..][0..4], 1, .big);
    std.mem.writeInt(u32, frame[at + 8 ..][0..4], 42, .big);
    const info = parse(mono_header, &frame).?;
    try testing.expectEqual(Kind.xing, info.kind);
    try testing.expectEqual(@as(u32, 42), info.frames.?);
    try testing.expect(info.bytes == null);
    try testing.expect(info.toc == null);
}

test "the LAME extension gives the encoder delay and padding" {
    var frame: [417]u8 = @splat(0);
    const at = 4 + 32;
    @memcpy(frame[at..][0..4], "Info");
    std.mem.writeInt(u32, frame[at + 4 ..][0..4], 1, .big);
    std.mem.writeInt(u32, frame[at + 8 ..][0..4], 193, .big);
    @memcpy(frame[at + 120 ..][0..9], "LAME3.100");
    // Delay 576 and padding 1187, packed twelve bits each.
    frame[at + 141] = 576 >> 4;
    frame[at + 142] = ((576 & 0xf) << 4) | (1187 >> 8);
    frame[at + 143] = 1187 & 0xff;

    const info = parse(stereo_header, &frame).?;
    const lame = info.lame.?;
    try testing.expectEqualStrings("LAME3.100", lame.name());
    try testing.expectEqual(@as(u16, 576), lame.delay);
    try testing.expectEqual(@as(u16, 1187), lame.padding);

    // 193 frames of 1152 samples, less the silence at each end.
    const seconds = info.duration(stereo_header).?;
    try testing.expectApproxEqAbs(@as(f64, (193 * 1152 - 576 - 1187)) / 44100.0, seconds, 1e-9);

    // The encoder's delay and the decoder's own add up to what a player must
    // drop before the first real sample.
    try testing.expectEqual(@as(u32, 576 + 529), info.leadIn().?);
    try testing.expectEqual(@as(u64, 193 * 1152 - 576 - 1187), info.playableSamples(stereo_header).?);
}

test "without a LAME extension there is nothing to trim" {
    var frame: [417]u8 = @splat(0);
    const at = 4 + 32;
    @memcpy(frame[at..][0..4], "Xing");
    std.mem.writeInt(u32, frame[at + 4 ..][0..4], 1, .big);
    std.mem.writeInt(u32, frame[at + 8 ..][0..4], 100, .big);
    const info = parse(stereo_header, &frame).?;
    try testing.expect(info.lame == null);
    try testing.expect(info.leadIn() == null);
    try testing.expect(info.playableSamples(stereo_header) == null);
    // Duration still works; it just cannot subtract the padding.
    try testing.expectApproxEqAbs(@as(f64, 100 * 1152) / 44100.0, info.duration(stereo_header).?, 1e-9);
}

test "a VBRI header is found at its own fixed offset" {
    var frame: [417]u8 = @splat(0);
    const at = 36;
    @memcpy(frame[at..][0..4], "VBRI");
    std.mem.writeInt(u16, frame[at + 8 ..][0..2], 75, .big);
    std.mem.writeInt(u32, frame[at + 10 ..][0..4], 123456, .big);
    std.mem.writeInt(u32, frame[at + 14 ..][0..4], 1000, .big);
    const info = parse(stereo_header, &frame).?;
    try testing.expectEqual(Kind.vbri, info.kind);
    try testing.expectEqual(@as(u32, 1000), info.frames.?);
    try testing.expectEqual(@as(u32, 123456), info.bytes.?);
    try testing.expectEqual(@as(u32, 75), info.quality.?);
}

test "an ordinary audio frame has no header in it" {
    var frame: [417]u8 = @splat(0xa5);
    @memcpy(frame[0..4], &[_]u8{ 0xff, 0xfb, 0x90, 0x00 });
    try testing.expect(parse(stereo_header, &frame) == null);
}

test "the seek table maps a fraction of the way through to a byte offset" {
    var info: Info = .{ .kind = .xing, .bytes = 25600 };
    var toc: [100]u8 = undefined;
    for (&toc, 0..) |*entry, n| entry.* = @intCast(n * 256 / 100);
    info.toc = toc;
    try testing.expectEqual(@as(u32, 0), info.seekOffset(0).?);
    try testing.expectEqual(@as(u32, 12800), info.seekOffset(0.5).?);
    // Out of range fractions clamp rather than running off the table.
    try testing.expectEqual(info.seekOffset(1).?, info.seekOffset(9.0).?);
    try testing.expectEqual(info.seekOffset(0).?, info.seekOffset(-1.0).?);
}
