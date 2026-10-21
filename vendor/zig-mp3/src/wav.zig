// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Just enough of the RIFF WAVE container to read and write 16-bit PCM, for
//! the command line tool.  The library itself hands out samples, not files.

const std = @import("std");

pub const header_size = 44;

/// Build the fixed 44-byte header for a 16-bit PCM stream.  `data_bytes` is
/// the size of the sample data that follows, which a writer that does not yet
/// know it can fill in afterwards by rewriting these bytes.
pub fn header(channels: u8, sample_rate: u32, data_bytes: u32) [header_size]u8 {
    var out: [header_size]u8 = undefined;
    const bits_per_sample: u16 = 16;
    const block_align: u16 = @as(u16, channels) * bits_per_sample / 8;

    @memcpy(out[0..4], "RIFF");
    std.mem.writeInt(u32, out[4..8], 36 + data_bytes, .little);
    @memcpy(out[8..12], "WAVE");

    @memcpy(out[12..16], "fmt ");
    std.mem.writeInt(u32, out[16..20], 16, .little); // PCM fmt chunk size
    std.mem.writeInt(u16, out[20..22], 1, .little); // format 1: PCM
    std.mem.writeInt(u16, out[22..24], channels, .little);
    std.mem.writeInt(u32, out[24..28], sample_rate, .little);
    std.mem.writeInt(u32, out[28..32], sample_rate * block_align, .little);
    std.mem.writeInt(u16, out[32..34], block_align, .little);
    std.mem.writeInt(u16, out[34..36], bits_per_sample, .little);

    @memcpy(out[36..40], "data");
    std.mem.writeInt(u32, out[40..44], data_bytes, .little);
    return out;
}

/// What `parse` found: the format, and the sample data as it lies in the
/// file.
pub const Sound = struct {
    channels: u8,
    sample_rate: u32,
    /// Interleaved 16-bit little endian samples, still as bytes.
    data: []const u8,

    /// Samples per channel.
    pub fn frames(self: Sound) usize {
        return self.data.len / 2 / @max(self.channels, 1);
    }

    /// Sample `n` of channel `ch`, scaled to -1 ... 1.
    pub fn at(self: Sound, n: usize, ch: usize) f32 {
        const index = (n * self.channels + ch) * 2;
        const raw = std.mem.readInt(i16, self.data[index..][0..2], .little);
        return @as(f32, @floatFromInt(raw)) / 32768.0;
    }
};

pub const ParseError = error{
    NotRiffWave,
    /// Anything but linear 16-bit PCM, which is all this reads.
    UnsupportedFormat,
    Truncated,
};

/// Read a RIFF WAVE file's format and sample data.
///
/// Chunks are walked rather than assumed to be at fixed offsets: real files
/// put `LIST` and `fact` chunks before the data often enough that reading
/// byte 44 onwards and hoping is wrong.
pub fn parse(bytes: []const u8) ParseError!Sound {
    if (bytes.len < 12) return ParseError.Truncated;
    if (!std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WAVE")) {
        return ParseError.NotRiffWave;
    }

    var channels: u8 = 0;
    var sample_rate: u32 = 0;
    var data: ?[]const u8 = null;

    var at: usize = 12;
    while (at + 8 <= bytes.len) {
        const id = bytes[at..][0..4];
        const stated = std.mem.readInt(u32, bytes[at + 4 ..][0..4], .little);
        const body = at + 8;
        // A final chunk whose stated size runs past the end is taken as
        // reaching the end, which is what a truncated recording looks like.
        const size = @min(stated, bytes.len - body);

        if (std.mem.eql(u8, id, "fmt ")) {
            if (size < 16) return ParseError.Truncated;
            const format = std.mem.readInt(u16, bytes[body..][0..2], .little);
            const bits = std.mem.readInt(u16, bytes[body + 14 ..][0..2], .little);
            // 0xfffe is WAVE_FORMAT_EXTENSIBLE, which is PCM when its
            // sub-format says so; 16-bit is all this reads either way.
            if ((format != 1 and format != 0xfffe) or bits != 16) {
                return ParseError.UnsupportedFormat;
            }
            const stated_channels = std.mem.readInt(u16, bytes[body + 2 ..][0..2], .little);
            if (stated_channels == 0 or stated_channels > 2) return ParseError.UnsupportedFormat;
            channels = @intCast(stated_channels);
            sample_rate = std.mem.readInt(u32, bytes[body + 4 ..][0..4], .little);
        } else if (std.mem.eql(u8, id, "data")) {
            data = bytes[body..][0..size];
        }

        // Chunks are padded to an even length.
        at = body + size + (size & 1);
    }

    if (channels == 0 or sample_rate == 0) return ParseError.NotRiffWave;
    return .{
        .channels = channels,
        .sample_rate = sample_rate,
        .data = data orelse return ParseError.Truncated,
    };
}

const testing = std.testing;

test "a header this writes is one this reads" {
    var file: std.ArrayList(u8) = .empty;
    defer file.deinit(testing.allocator);
    const samples = [_]i16{ 0, 1000, -1000, 32767, -32768, 5 };
    var raw: [samples.len * 2]u8 = undefined;
    for (samples, 0..) |value, i| std.mem.writeInt(i16, raw[i * 2 ..][0..2], value, .little);
    try file.appendSlice(testing.allocator, &header(2, 44100, raw.len));
    try file.appendSlice(testing.allocator, &raw);

    const sound = try parse(file.items);
    try testing.expectEqual(@as(u8, 2), sound.channels);
    try testing.expectEqual(@as(u32, 44100), sound.sample_rate);
    try testing.expectEqual(@as(usize, 3), sound.frames());
    try testing.expectApproxEqAbs(@as(f32, 0), sound.at(0, 0), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1000.0 / 32768.0), sound.at(0, 1), 1e-6);
    // Frame 2 is (-32768, 5): the third pair of the interleaved run.
    try testing.expectApproxEqAbs(@as(f32, -1), sound.at(2, 0), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 5.0 / 32768.0), sound.at(2, 1), 1e-6);
}

test "chunks before the data are stepped over" {
    var file: std.ArrayList(u8) = .empty;
    defer file.deinit(testing.allocator);
    try file.appendSlice(testing.allocator, &header(1, 8000, 4));
    // Turn the header's own data chunk into a LIST, then append a real one,
    // so that the parser has to walk past something to find the samples.
    @memcpy(file.items[36..40], "LIST");
    std.mem.writeInt(u32, file.items[40..44][0..4], 3, .little);
    try file.appendSlice(testing.allocator, &[_]u8{ 'a', 'b', 'c', 0 }); // padded
    try file.appendSlice(testing.allocator, "data");
    try file.appendSlice(testing.allocator, &[_]u8{ 4, 0, 0, 0 });
    try file.appendSlice(testing.allocator, &[_]u8{ 0x10, 0x27, 0xf0, 0xd8 });

    const sound = try parse(file.items);
    try testing.expectEqual(@as(u8, 1), sound.channels);
    try testing.expectEqual(@as(usize, 2), sound.frames());
    try testing.expectApproxEqAbs(@as(f32, 10000.0 / 32768.0), sound.at(0, 0), 1e-6);
}

test "what is not a wave file is refused" {
    try testing.expectError(ParseError.Truncated, parse("RIFF"));
    try testing.expectError(ParseError.NotRiffWave, parse("RIFFxxxxWAVEfmt "));
    var eight_bit = header(1, 8000, 0);
    std.mem.writeInt(u16, eight_bit[34..36], 8, .little);
    try testing.expectError(ParseError.UnsupportedFormat, parse(&eight_bit));
}

test "the header describes a 16 bit stereo stream" {
    const h = header(2, 44100, 1000);
    try testing.expectEqualStrings("RIFF", h[0..4]);
    try testing.expectEqualStrings("WAVE", h[8..12]);
    try testing.expectEqualStrings("fmt ", h[12..16]);
    try testing.expectEqualStrings("data", h[36..40]);
    try testing.expectEqual(@as(u32, 1036), std.mem.readInt(u32, h[4..8], .little));
    try testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, h[22..24], .little));
    try testing.expectEqual(@as(u32, 44100), std.mem.readInt(u32, h[24..28], .little));
    try testing.expectEqual(@as(u32, 176400), std.mem.readInt(u32, h[28..32], .little));
    try testing.expectEqual(@as(u16, 4), std.mem.readInt(u16, h[32..34], .little));
    try testing.expectEqual(@as(u32, 1000), std.mem.readInt(u32, h[40..44], .little));
}

test "a mono header halves the block alignment and byte rate" {
    const h = header(1, 22050, 0);
    try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, h[22..24], .little));
    try testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, h[32..34], .little));
    try testing.expectEqual(@as(u32, 44100), std.mem.readInt(u32, h[28..32], .little));
}
