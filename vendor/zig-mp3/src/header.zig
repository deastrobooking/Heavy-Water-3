// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The four-byte MPEG audio frame header.
//!
//! All three layers and all three MPEG versions are recognized here, because
//! finding frame boundaries in a stream means being able to size a frame you
//! do not intend to decode.  Only Layer III is decoded; see `layer3.zig`.

const std = @import("std");

pub const Version = enum(u2) {
    /// MPEG-2.5, the unofficial extension to 8, 11.025 and 12 kHz.
    mpeg2_5 = 0,
    reserved = 1,
    /// MPEG-2 LSF (ISO/IEC 13818-3): 16, 22.05 and 24 kHz.
    mpeg2 = 2,
    /// MPEG-1 (ISO/IEC 11172-3): 32, 44.1 and 48 kHz.
    mpeg1 = 3,

    /// Row order used by the tables that vary by version.
    pub fn tableIndex(self: Version) u2 {
        return switch (self) {
            .mpeg1 => 0,
            .mpeg2 => 1,
            .mpeg2_5 => 2,
            .reserved => unreachable,
        };
    }

    /// MPEG-2 and MPEG-2.5 share the "low sampling frequency" bitstream
    /// layout: one granule per frame, shorter side information, and a
    /// different scalefactor coding.
    pub fn isLowSamplingFrequency(self: Version) bool {
        return self != .mpeg1;
    }
};

pub const Layer = enum(u2) {
    reserved = 0,
    layer3 = 1,
    layer2 = 2,
    layer1 = 3,
};

pub const ChannelMode = enum(u2) {
    stereo = 0,
    joint_stereo = 1,
    dual_channel = 2,
    mono = 3,
};

pub const Emphasis = enum(u2) {
    none = 0,
    ms_50_15 = 1,
    reserved = 2,
    ccitt_j17 = 3,
};

/// Layer III joint stereo splits `mode_extension` into two independent flags.
pub const JointStereo = struct {
    ms_stereo: bool,
    intensity_stereo: bool,
};

pub const Header = @This();

version: Version,
layer: Layer,
/// A 16-bit CRC over parts of the frame follows the header.
crc_protected: bool,
bitrate_index: u4,
sample_rate_index: u2,
/// The frame carries one extra slot to keep the average bit rate exact.
padding: bool,
private: bool,
mode: ChannelMode,
mode_extension: u2,
copyright: bool,
original: bool,
emphasis: Emphasis,

/// True when `bytes` could begin a frame: 11 sync bits followed by field
/// values that are all defined.  A sync word alone is weak evidence -- it
/// occurs by chance every few kilobytes of arbitrary data -- so callers
/// searching for the first frame should confirm that the next frame follows
/// where this one's `frameSize` says it will.
pub fn isValid(bytes: [4]u8) bool {
    return parse(bytes) != null;
}

/// Parse a header, or return null if the four bytes are not one.
pub fn parse(bytes: [4]u8) ?Header {
    if (bytes[0] != 0xff or bytes[1] & 0xe0 != 0xe0) return null;

    const version: Version = @enumFromInt(@as(u2, @truncate(bytes[1] >> 3)));
    if (version == .reserved) return null;

    const layer: Layer = @enumFromInt(@as(u2, @truncate(bytes[1] >> 1)));
    if (layer == .reserved) return null;

    const bitrate_index: u4 = @truncate(bytes[2] >> 4);
    if (bitrate_index == 0xf) return null;

    const sample_rate_index: u2 = @truncate(bytes[2] >> 2);
    if (sample_rate_index == 3) return null;

    const emphasis: Emphasis = @enumFromInt(@as(u2, @truncate(bytes[3])));
    if (emphasis == .reserved) return null;

    return .{
        .version = version,
        .layer = layer,
        .crc_protected = bytes[1] & 1 == 0,
        .bitrate_index = bitrate_index,
        .sample_rate_index = sample_rate_index,
        .padding = bytes[2] & 2 != 0,
        .private = bytes[2] & 1 != 0,
        .mode = @enumFromInt(@as(u2, @truncate(bytes[3] >> 6))),
        .mode_extension = @truncate(bytes[3] >> 4),
        .copyright = bytes[3] & 8 != 0,
        .original = bytes[3] & 4 != 0,
        .emphasis = emphasis,
    };
}

/// Bit rate in bits per second, or null for the "free format" index 0, whose
/// rate is fixed for a stream but not stated in it.
pub fn bitRate(self: Header) ?u32 {
    if (self.bitrate_index == 0) return null;
    const row: usize = switch (self.version) {
        .mpeg1 => switch (self.layer) {
            .layer1 => 0,
            .layer2 => 1,
            .layer3 => 2,
            .reserved => unreachable,
        },
        else => switch (self.layer) {
            .layer1 => 3,
            .layer2, .layer3 => 4,
            .reserved => unreachable,
        },
    };
    // ISO/IEC 11172-3 Table 8 and ISO/IEC 13818-3 Table 8, in kbit/s.
    const table = [5][15]u16{
        .{ 0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448 },
        .{ 0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384 },
        .{ 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320 },
        .{ 0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256 },
        .{ 0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160 },
    };
    return @as(u32, table[row][self.bitrate_index]) * 1000;
}

pub fn sampleRate(self: Header) u32 {
    const base = [3]u32{ 44100, 48000, 32000 };
    return switch (self.version) {
        .mpeg1 => base[self.sample_rate_index],
        .mpeg2 => base[self.sample_rate_index] / 2,
        .mpeg2_5 => base[self.sample_rate_index] / 4,
        .reserved => unreachable,
    };
}

pub fn channels(self: Header) u8 {
    return if (self.mode == .mono) 1 else 2;
}

/// PCM samples per channel that decoding this frame produces.
pub fn samplesPerFrame(self: Header) u16 {
    return switch (self.layer) {
        .layer1 => 384,
        .layer2 => 1152,
        .layer3 => if (self.version.isLowSamplingFrequency()) 576 else 1152,
        .reserved => unreachable,
    };
}

/// Layer III granules per frame: two for MPEG-1, one for the low sampling
/// frequency versions.  Layers I and II have no granules.
pub fn granules(self: Header) u8 {
    std.debug.assert(self.layer == .layer3);
    return if (self.version.isLowSamplingFrequency()) 1 else 2;
}

/// Total frame size in bytes, including this header, or null in free format
/// where the size has to be found by looking for the next sync word.
pub fn frameSize(self: Header) ?usize {
    const rate = self.bitRate() orelse return null;
    const padding: usize = @intFromBool(self.padding);
    if (self.layer == .layer1) {
        // Layer I counts in four-byte slots.
        return (12 * rate / self.sampleRate() + padding) * 4;
    }
    return @as(usize, self.samplesPerFrame()) / 8 * rate / self.sampleRate() + padding;
}

/// Bytes of Layer III side information following the header and optional CRC.
pub fn sideInfoSize(self: Header) usize {
    std.debug.assert(self.layer == .layer3);
    if (self.version.isLowSamplingFrequency()) {
        return if (self.mode == .mono) 9 else 17;
    }
    return if (self.mode == .mono) 17 else 32;
}

/// The two joint stereo flags, both false unless the mode is joint stereo.
pub fn jointStereo(self: Header) JointStereo {
    if (self.mode != .joint_stereo) return .{ .ms_stereo = false, .intensity_stereo = false };
    return .{
        .ms_stereo = self.mode_extension & 2 != 0,
        .intensity_stereo = self.mode_extension & 1 != 0,
    };
}

/// True when two headers describe frames of the same stream.  Bit rate and
/// padding may vary frame to frame; the rest may not.
pub fn compatibleWith(self: Header, other: Header) bool {
    return self.version == other.version and
        self.layer == other.layer and
        self.sample_rate_index == other.sample_rate_index and
        self.mode == other.mode;
}

test "parses a 128 kbit/s 44.1 kHz stereo Layer III header" {
    const h = parse(.{ 0xff, 0xfb, 0x90, 0x00 }).?;
    try std.testing.expectEqual(Version.mpeg1, h.version);
    try std.testing.expectEqual(Layer.layer3, h.layer);
    try std.testing.expect(!h.crc_protected);
    try std.testing.expectEqual(@as(u32, 128_000), h.bitRate().?);
    try std.testing.expectEqual(@as(u32, 44_100), h.sampleRate());
    try std.testing.expectEqual(ChannelMode.stereo, h.mode);
    try std.testing.expectEqual(@as(usize, 417), h.frameSize().?);
    try std.testing.expectEqual(@as(usize, 32), h.sideInfoSize());
    try std.testing.expectEqual(@as(u16, 1152), h.samplesPerFrame());
    try std.testing.expectEqual(@as(u8, 2), h.granules());
}

test "padding adds one slot" {
    const unpadded = parse(.{ 0xff, 0xfb, 0x90, 0x00 }).?;
    const padded = parse(.{ 0xff, 0xfb, 0x92, 0x00 }).?;
    try std.testing.expectEqual(unpadded.frameSize().? + 1, padded.frameSize().?);
}

test "MPEG-2 halves the sample rate, the granule count and the side info" {
    const h = parse(.{ 0xff, 0xf3, 0x40, 0xc0 }).?;
    try std.testing.expectEqual(Version.mpeg2, h.version);
    try std.testing.expectEqual(Layer.layer3, h.layer);
    try std.testing.expectEqual(@as(u32, 22_050), h.sampleRate());
    try std.testing.expectEqual(@as(u32, 32_000), h.bitRate().?);
    try std.testing.expectEqual(@as(u16, 576), h.samplesPerFrame());
    try std.testing.expectEqual(@as(u8, 1), h.granules());
    try std.testing.expectEqual(ChannelMode.mono, h.mode);
    try std.testing.expectEqual(@as(usize, 9), h.sideInfoSize());
    try std.testing.expectEqual(@as(usize, 72 * 32000 / 22050), h.frameSize().?);
}

test "MPEG-2.5 quarters the sample rate" {
    const h = parse(.{ 0xff, 0xe3, 0x40, 0xc0 }).?;
    try std.testing.expectEqual(Version.mpeg2_5, h.version);
    try std.testing.expectEqual(@as(u32, 11_025), h.sampleRate());
}

test "rejects reserved and impossible fields" {
    try std.testing.expect(parse(.{ 0x00, 0x00, 0x00, 0x00 }) == null); // no sync
    try std.testing.expect(parse(.{ 0xff, 0xe0, 0x90, 0x00 }) == null); // no sync (10 bits)
    try std.testing.expect(parse(.{ 0xff, 0xeb, 0x90, 0x00 }) == null); // reserved version
    try std.testing.expect(parse(.{ 0xff, 0xf9, 0x90, 0x00 }) == null); // reserved layer
    try std.testing.expect(parse(.{ 0xff, 0xfb, 0xf0, 0x00 }) == null); // bitrate index 15
    try std.testing.expect(parse(.{ 0xff, 0xfb, 0x9c, 0x00 }) == null); // sample rate index 3
    try std.testing.expect(parse(.{ 0xff, 0xfb, 0x90, 0x02 }) == null); // reserved emphasis
}

test "free format has no stated bit rate or frame size" {
    const h = parse(.{ 0xff, 0xfb, 0x00, 0x00 }).?;
    try std.testing.expect(h.bitRate() == null);
    try std.testing.expect(h.frameSize() == null);
}

test "joint stereo flags come from the mode extension" {
    const both = parse(.{ 0xff, 0xfb, 0x90, 0x70 }).?;
    try std.testing.expectEqual(ChannelMode.joint_stereo, both.mode);
    try std.testing.expectEqual(JointStereo{ .ms_stereo = true, .intensity_stereo = true }, both.jointStereo());

    const plain = parse(.{ 0xff, 0xfb, 0x90, 0x40 }).?;
    try std.testing.expectEqual(ChannelMode.joint_stereo, plain.mode);
    try std.testing.expectEqual(JointStereo{ .ms_stereo = false, .intensity_stereo = false }, plain.jointStereo());

    // Outside joint stereo the same bits mean something else and both flags
    // must stay clear.
    const stereo = parse(.{ 0xff, 0xfb, 0x90, 0x30 }).?;
    try std.testing.expectEqual(ChannelMode.stereo, stereo.mode);
    try std.testing.expectEqual(@as(u2, 3), stereo.mode_extension);
    try std.testing.expectEqual(JointStereo{ .ms_stereo = false, .intensity_stereo = false }, stereo.jointStereo());
}

test "Layer I sizes in four byte slots" {
    const h = parse(.{ 0xff, 0xfe, 0x90, 0x00 }).?;
    try std.testing.expectEqual(Layer.layer1, h.layer);
    try std.testing.expectEqual(@as(u32, 288_000), h.bitRate().?);
    try std.testing.expectEqual(@as(u16, 384), h.samplesPerFrame());
    try std.testing.expectEqual(@as(usize, 312), h.frameSize().?);
}

const testing = std.testing;

test "every possible header is consistent with itself" {
    // Eleven of the 32 bits are the sync word, so there are only 2^21 headers
    // to consider and they can all be checked rather than sampled.  What this
    // is looking for is any pair of accessors that disagree -- a frame size
    // that does not match the bit rate it was derived from, a side
    // information size that does not match the version and channel mode.
    const rates = [_]u32{ 8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000 };

    var parsed: usize = 0;
    var free_format: usize = 0;
    for (0..1 << 21) |raw| {
        const bytes = [4]u8{
            0xff,
            0xe0 | @as(u8, @truncate(raw >> 16)),
            @truncate(raw >> 8),
            @truncate(raw),
        };
        try testing.expectEqual(parse(bytes) != null, isValid(bytes));
        const h = parse(bytes) orelse {
            // Rejection is only ever for one of these five reasons.
            const version: u2 = @truncate(bytes[1] >> 3);
            const layer: u2 = @truncate(bytes[1] >> 1);
            try testing.expect(version == 1 or layer == 0 or
                bytes[2] >> 4 == 0xf or (bytes[2] >> 2) & 3 == 3 or bytes[3] & 3 == 2);
            continue;
        };
        parsed += 1;

        try testing.expect(std.mem.indexOfScalar(u32, &rates, h.sampleRate()) != null);
        try testing.expect(h.channels() == 1 or h.channels() == 2);
        try testing.expectEqual(h.mode == .mono, h.channels() == 1);
        switch (h.samplesPerFrame()) {
            384, 576, 1152 => {},
            else => return error.UnexpectedFrameLength,
        }

        if (h.layer == .layer3) {
            // Only Layer III has granules, and only the low sampling
            // frequency versions halve the frame to fit one.
            try testing.expect(h.granules() == 1 or h.granules() == 2);
            try testing.expectEqual(
                @as(u16, if (h.granules() == 1) 576 else 1152),
                h.samplesPerFrame(),
            );
            switch (h.sideInfoSize()) {
                9, 17, 32 => {},
                else => return error.UnexpectedSideInfoSize,
            }
            try testing.expectEqual(
                h.version.isLowSamplingFrequency(),
                h.sideInfoSize() == 9 or (h.sideInfoSize() == 17 and h.mode != .mono),
            );
        }

        // A frame size is stated exactly when a bit rate is.
        try testing.expectEqual(h.bitRate() == null, h.frameSize() == null);
        if (h.frameSize()) |size| {
            // Big enough for a header, and no bigger than the largest frame
            // the tables allow: Layer II at 160 kbit/s and 8 kHz.
            try testing.expect(size >= 4);
            try testing.expect(size <= 2881);
            // The size must be the bit rate over the sample rate, in slots.
            const padding: usize = @intFromBool(h.padding);
            const expected: usize = if (h.layer == .layer1)
                (12 * h.bitRate().? / h.sampleRate() + padding) * 4
            else
                @as(usize, h.samplesPerFrame()) / 8 * h.bitRate().? / h.sampleRate() + padding;
            try testing.expectEqual(expected, size);
        } else {
            free_format += 1;
            try testing.expectEqual(@as(u4, 0), h.bitrate_index);
        }

        // The joint stereo flags mean nothing outside joint stereo.
        const joint = h.jointStereo();
        if (h.mode != .joint_stereo) {
            try testing.expect(!joint.ms_stereo and !joint.intensity_stereo);
        } else {
            try testing.expectEqual(h.mode_extension & 2 != 0, joint.ms_stereo);
            try testing.expectEqual(h.mode_extension & 1 != 0, joint.intensity_stereo);
        }

        try testing.expect(h.compatibleWith(h));
    }

    // A sanity check on the check.  Of the five fields that can be invalid,
    // three rule out a quarter of the values each, one an eighth and one a
    // sixteenth, so a shade under thirty per cent of headers should parse; a
    // change that quietly rejected everything would otherwise pass here.
    const valid = 3 * 3 * 15 * 3 * 3 * (1 << 21) / (4 * 4 * 16 * 4 * 4);
    try testing.expectEqual(valid, parsed);
    // One bit rate index in fifteen is free format.
    try testing.expectEqual(valid / 15, free_format);
}

test "compatibility ignores what may change from frame to frame" {
    const base = parse(.{ 0xff, 0xfb, 0x90, 0x00 }).?;
    // Bit rate and padding vary within a stream and must not break the match.
    try testing.expect(base.compatibleWith(parse(.{ 0xff, 0xfb, 0xa2, 0x00 }).?));
    // Everything else identifies the stream.
    try testing.expect(!base.compatibleWith(parse(.{ 0xff, 0xf3, 0x90, 0x00 }).?)); // version
    try testing.expect(!base.compatibleWith(parse(.{ 0xff, 0xfd, 0x90, 0x00 }).?)); // layer
    try testing.expect(!base.compatibleWith(parse(.{ 0xff, 0xfb, 0x94, 0x00 }).?)); // rate
    try testing.expect(!base.compatibleWith(parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?)); // mode
}
