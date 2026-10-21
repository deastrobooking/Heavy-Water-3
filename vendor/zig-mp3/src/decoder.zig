// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The streaming decoder: finding frames in a byte stream and turning them
//! into PCM.
//!
//! Layer III spreads a frame's data backwards across earlier frames through
//! the bit reservoir, so frames cannot be decoded independently and the
//! decoder carries state.  Everything that state contains is thrown away by
//! `reset`, which is what a seek needs.

const std = @import("std");

const BitReader = @import("bitstream.zig");
const Header = @import("header.zig");
const layer12 = @import("layer12.zig");
const layer3 = @import("layer3.zig");
const side_info = @import("side_info.zig");
const tags = @import("tags.zig");
const vbr = @import("vbr.zig");

pub const max_channels = 2;
/// PCM samples per channel in the largest frame, an MPEG-1 Layer III one.
pub const max_samples_per_frame = 1152;
/// Elements a caller's output buffer needs for one frame.
pub const max_frame_samples = max_samples_per_frame * max_channels;
pub const FrameBuffer = [max_frame_samples]f32;

/// The bit reservoir reaches back at most 511 bytes, which is what nine bits
/// of `main_data_begin` can express.
const reservoir_capacity = 511;
/// Enough for the reservoir plus the largest frame that can follow it.
const assembly_capacity = reservoir_capacity + 1441;

/// A frame that was decoded into the caller's buffer.
pub const Frame = struct {
    header: Header,
    /// Input bytes the decoder used, counted from the start of the slice it
    /// was given, including anything skipped ahead of the frame.
    consumed: usize,
    /// Samples *per channel* written to the output buffer.  The buffer holds
    /// `samples * channels` interleaved values.
    samples: usize,
    channels: u8,
    sample_rate: u32,
};

pub const Step = union(enum) {
    /// The input does not hold a whole frame yet.  Append more and call
    /// again with the longer slice; nothing was consumed.
    need_more,
    /// This many bytes were consumed without producing audio: a metadata tag,
    /// rubbish between frames, a frame of a layer this decoder does not
    /// handle, or the first frames after a seek, whose data lived in a bit
    /// reservoir that has not been refilled yet.
    skipped: usize,
    frame: Frame,
};

pub const Decoder = struct {
    state: layer3.State = .{},
    /// Layers I and II share the filterbank but nothing else, so they keep
    /// their own history.
    state12: layer12.State = .{},
    /// Main data from previous frames, oldest first.
    reservoir: [reservoir_capacity]u8 = undefined,
    reservoir_len: usize = 0,
    assembly: [assembly_capacity]u8 = undefined,
    /// Bytes still to step over from a tag larger than one input slice.
    skipping: usize = 0,
    /// Whether the last thing read was a frame, which lets the next one be
    /// trusted without looking ahead to confirm it.
    synced: bool = false,
    /// Whether any frame has been looked at, so that the Xing, Info or VBRI
    /// header is only looked for where it can legitimately be.
    saw_first_frame: bool = false,
    /// That header, if the stream had one.
    stream_info: ?vbr.Info = null,

    pub fn init() Decoder {
        return .{};
    }

    /// Forget the bit reservoir, the filterbank history and the sync state.
    /// Decoding after a seek will be silent for a frame or two while the
    /// reservoir refills, which is what the standard's own encoders assume.
    ///
    /// What the stream *is* -- its Xing or VBRI header -- is not decoding
    /// state and survives, since a seek does not move the file's front matter.
    pub fn reset(self: *Decoder) void {
        self.state.reset();
        self.state12.reset();
        self.reservoir_len = 0;
        self.skipping = 0;
        self.synced = false;
    }

    /// The Xing, Info or VBRI header from the front of the stream, once the
    /// decoder has reached the frame that would carry it.
    pub fn info(self: *const Decoder) ?vbr.Info {
        return self.stream_info;
    }

    pub const Options = struct {
        /// True when `input` runs to the end of the stream, so that a final
        /// frame is not held back waiting for a successor to confirm it.
        end_of_input: bool = false,
    };

    /// Take the next step through `input`, writing any audio to `out`.
    pub fn next(
        self: *Decoder,
        input: []const u8,
        out: *FrameBuffer,
        options: Options,
    ) Step {
        if (self.skipping > 0) {
            const step = @min(self.skipping, input.len);
            if (step == 0) return .need_more;
            self.skipping -= step;
            return .{ .skipped = step };
        }

        var offset: usize = 0;
        while (true) {
            const rest = input[offset..];
            if (rest.len == 0) return if (offset == 0) .need_more else .{ .skipped = offset };

            switch (tags.detect(rest)) {
                .incomplete => return if (options.end_of_input)
                    .{ .skipped = input.len }
                else if (offset == 0) .need_more else .{ .skipped = offset },
                .found => |tag| {
                    const here = @min(tag.size, rest.len);
                    self.skipping = tag.size - here;
                    self.synced = false;
                    return .{ .skipped = offset + here };
                },
                .none => {},
            }

            if (rest.len < 4) {
                if (options.end_of_input) return .{ .skipped = input.len };
                return if (offset == 0) .need_more else .{ .skipped = offset };
            }

            const header = Header.parse(rest[0..4].*) orelse {
                offset += 1;
                self.synced = false;
                continue;
            };

            // Free format states no bit rate, so the frame runs to wherever
            // the next one starts.  This decoder does not reconstruct that.
            const size = header.frameSize() orelse {
                offset += 1;
                self.synced = false;
                continue;
            };
            if (size < 4 or size > assembly_capacity) {
                offset += 1;
                self.synced = false;
                continue;
            }

            if (rest.len < size) {
                if (!options.end_of_input) {
                    return if (offset == 0) .need_more else .{ .skipped = offset };
                }
                // A truncated final frame is not worth decoding.
                return .{ .skipped = input.len };
            }

            // An encoder's table of contents rides in a frame at the very
            // front of the stream.  It is not audio -- decoding it would emit
            // a frame of silence belonging to nobody -- and it identifies
            // itself well enough to need no confirmation, which matters
            // because LAME writes it in plain stereo even when the audio
            // frames that follow are joint stereo.
            if (!self.saw_first_frame and header.layer == .layer3) {
                if (vbr.parse(header, rest[0..size])) |found| {
                    self.saw_first_frame = true;
                    self.stream_info = found;
                    return .{ .skipped = offset + size };
                }
            }

            // A sync word turns up by chance every few kilobytes of arbitrary
            // data, so the first frame after a break has to be confirmed by
            // the one that should follow it.
            if (!self.synced) {
                if (rest.len < size + 4) {
                    if (!options.end_of_input) {
                        return if (offset == 0) .need_more else .{ .skipped = offset };
                    }
                } else {
                    const following = Header.parse(rest[size..][0..4].*);
                    if (following == null or !header.compatibleWith(following.?)) {
                        offset += 1;
                        continue;
                    }
                }
            }

            self.saw_first_frame = true;
            const samples = self.decodeFrame(header, rest[0..size], out);
            self.synced = true;
            if (samples == 0) return .{ .skipped = offset + size };
            return .{ .frame = .{
                .header = header,
                .consumed = offset + size,
                .samples = samples,
                .channels = header.channels(),
                .sample_rate = header.sampleRate(),
            } };
        }
    }

    /// Decode one whole Layer III frame, returning samples per channel, or
    /// zero when the frame could not be turned into audio.
    fn decodeFrame(self: *Decoder, header: Header, frame: []const u8, out: *FrameBuffer) usize {
        var offset: usize = 4;
        if (header.crc_protected) offset += 2;
        if (frame.len <= offset) return 0;

        // Layers I and II have no bit reservoir and nothing to assemble: the
        // frame holds everything it needs.
        if (header.layer != .layer3) {
            return layer12.decodeFrame(&self.state12, header, frame[offset..], out);
        }

        const side_size = header.sideInfoSize();
        if (frame.len < offset + side_size) return 0;

        const side = side_info.parse(header, frame[offset..][0..side_size]) catch return 0;
        offset += side_size;
        const main = frame[offset..];

        // The granule data begins `main_data_begin` bytes before this frame's
        // own, in whatever earlier frames put there.  Too far back means the
        // reservoir has not refilled since the last discontinuity.
        const begin: usize = side.main_data_begin;
        if (begin > self.reservoir_len) {
            self.pushReservoir(main);
            return 0;
        }

        const total = begin + main.len;
        if (total > self.assembly.len) {
            self.pushReservoir(main);
            return 0;
        }
        @memcpy(self.assembly[0..begin], self.reservoir[self.reservoir_len - begin .. self.reservoir_len]);
        @memcpy(self.assembly[begin..][0..main.len], main);
        self.pushReservoir(main);

        const channels = header.channels();
        var reader = BitReader.init(self.assembly[0..total]);
        for (0..header.granules()) |gr| {
            const at = gr * layer3.granule_len * @as(usize, channels);
            layer3.decodeGranule(&self.state, header, &side, gr, &reader, out[at..]);
        }
        return header.samplesPerFrame();
    }

    /// Append a frame's main data to the reservoir, keeping the most recent
    /// bytes and dropping whatever no longer fits.
    fn pushReservoir(self: *Decoder, data: []const u8) void {
        if (data.len >= self.reservoir.len) {
            @memcpy(&self.reservoir, data[data.len - self.reservoir.len ..]);
            self.reservoir_len = self.reservoir.len;
            return;
        }
        const keep = @min(self.reservoir_len, self.reservoir.len - data.len);
        std.mem.copyForwards(
            u8,
            self.reservoir[0..keep],
            self.reservoir[self.reservoir_len - keep ..][0..keep],
        );
        @memcpy(self.reservoir[keep..][0..data.len], data);
        self.reservoir_len = keep + data.len;
    }
};

/// Convert samples to signed 16-bit, clipping rather than wrapping.
///
/// Clipping is not just tidiness.  A well formed stream decodes to roughly
/// -1...1, but a corrupt one can claim the largest global gain together with
/// the largest quantized values and legitimately decode to something millions
/// of times bigger.  The decoder does not bound that -- doing so would be
/// guessing at what the caller wants -- so anything converting to integers
/// has to.
pub fn toInt16(samples: []const f32, out: []i16) void {
    std.debug.assert(out.len >= samples.len);
    for (samples, out[0..samples.len]) |sample, *pcm| {
        const scaled = sample * 32768.0;
        pcm.* = @intFromFloat(std.math.clamp(scaled, -32768.0, 32767.0));
    }
}

/// A whole decoded stream.
pub const Audio = struct {
    sample_rate: u32,
    channels: u8,
    /// Interleaved samples, `channels` per frame.
    samples: []f32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Audio) void {
        self.allocator.free(self.samples);
        self.* = undefined;
    }

    /// Samples per channel.
    pub fn frameCount(self: Audio) usize {
        return if (self.channels == 0) 0 else self.samples.len / self.channels;
    }

    pub fn duration(self: Audio) f64 {
        if (self.sample_rate == 0) return 0;
        return @as(f64, @floatFromInt(self.frameCount())) / @as(f64, @floatFromInt(self.sample_rate));
    }
};

pub const DecodeAllError = error{ OutOfMemory, NoAudio };

/// Decode a whole MP3 in memory.  The stream's format is taken from its first
/// decodable frame; later frames that disagree are skipped, since a change of
/// sample rate or channel count mid-file cannot be represented in one buffer.
pub fn decodeAll(allocator: std.mem.Allocator, input: []const u8) DecodeAllError!Audio {
    var decoder = Decoder.init();
    var samples: std.ArrayList(f32) = .empty;
    errdefer samples.deinit(allocator);

    var buffer: FrameBuffer = undefined;
    var offset: usize = 0;
    var sample_rate: u32 = 0;
    var channels: u8 = 0;

    while (offset < input.len) {
        switch (decoder.next(input[offset..], &buffer, .{ .end_of_input = true })) {
            .need_more => break,
            .skipped => |n| offset += n,
            .frame => |frame| {
                offset += frame.consumed;
                if (channels == 0) {
                    channels = frame.channels;
                    sample_rate = frame.sample_rate;
                }
                if (frame.channels != channels or frame.sample_rate != sample_rate) continue;
                try samples.appendSlice(
                    allocator,
                    buffer[0 .. frame.samples * @as(usize, frame.channels)],
                );
            },
        }
    }

    // `errdefer` releases the buffer on the way out.
    if (channels == 0) return error.NoAudio;
    return .{
        .sample_rate = sample_rate,
        .channels = channels,
        .samples = try samples.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

const testing = std.testing;

test "a stream of nothing but rubbish yields no audio" {
    var junk: [4096]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(1);
    rng.random().bytes(&junk);
    // Make sure no accidental sync word survives.
    for (&junk) |*byte| byte.* &= 0x7f;
    try testing.expectError(error.NoAudio, decodeAll(testing.allocator, &junk));
}

test "an empty input yields no audio" {
    try testing.expectError(error.NoAudio, decodeAll(testing.allocator, ""));
}

test "the reservoir keeps the most recent bytes" {
    var decoder = Decoder.init();
    var data: [600]u8 = undefined;
    for (&data, 0..) |*byte, n| byte.* = @truncate(n);

    decoder.pushReservoir(data[0..100]);
    try testing.expectEqual(@as(usize, 100), decoder.reservoir_len);
    try testing.expectEqual(@as(u8, 0), decoder.reservoir[0]);

    decoder.pushReservoir(data[100..500]);
    try testing.expectEqual(@as(usize, 500), decoder.reservoir_len);
    try testing.expectEqual(@as(u8, 99), decoder.reservoir[99]);

    // Overflowing drops the oldest bytes and keeps the newest 511.
    decoder.pushReservoir(data[500..600]);
    try testing.expectEqual(@as(usize, 511), decoder.reservoir_len);
    try testing.expectEqual(@as(u8, @truncate(600 - 511)), decoder.reservoir[0]);
    try testing.expectEqual(@as(u8, @truncate(599)), decoder.reservoir[510]);

    // A single push larger than the reservoir keeps only its tail.
    decoder.pushReservoir(&data);
    try testing.expectEqual(@as(usize, 511), decoder.reservoir_len);
    try testing.expectEqual(@as(u8, @truncate(600 - 511)), decoder.reservoir[0]);
}

test "a tag larger than the input is stepped over across calls" {
    var decoder = Decoder.init();
    var out: FrameBuffer = undefined;
    // An ID3v2 tag claiming 1000 bytes of body, of which we offer 20.
    var head: [20]u8 = @splat(0);
    @memcpy(head[0..10], &[_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 7, 0x68 });
    try testing.expectEqual(@as(usize, 1010), tags.detect(&head).found.size);

    try testing.expectEqual(Step{ .skipped = 20 }, decoder.next(&head, &out, .{}));
    try testing.expectEqual(@as(usize, 990), decoder.skipping);
    const more: [500]u8 = @splat(0);
    try testing.expectEqual(Step{ .skipped = 500 }, decoder.next(&more, &out, .{}));
    try testing.expectEqual(@as(usize, 490), decoder.skipping);
}

/// Build a Layer III frame: MPEG-1 mono, 32 kbit/s, 44.1 kHz, 104 bytes.
/// The side information is zeroed apart from `main_data_begin`, so the frame
/// decodes to silence, and the main data is whatever is left of the frame.
fn silentFrame(crc: bool, main_data_begin: u9) [104]u8 {
    var frame: [104]u8 = @splat(0);
    frame[0] = 0xff;
    frame[1] = if (crc) 0xfa else 0xfb; // protection bit is active low
    frame[2] = 0x10; // bit rate index 1, sampling frequency index 0
    frame[3] = 0xc0; // single channel
    const side_info_at: usize = if (crc) 6 else 4;
    frame[side_info_at] = @truncate(main_data_begin >> 1);
    frame[side_info_at + 1] = @as(u8, @truncate(main_data_begin & 1)) << 7;
    return frame;
}

test "a CRC protected frame has its side information two bytes further in" {
    // The two CRC bytes are zero, so a decoder reading the side information
    // from the wrong offset would see `main_data_begin` as zero and decode
    // the frame instead of holding it back for want of a bit reservoir.
    // Two frames, because an unsynced decoder confirms the first against the
    // second before trusting it.
    for ([_]bool{ false, true }) |crc| {
        {
            const frame = silentFrame(crc, 0);
            const stream = frame ++ frame;
            var decoder = Decoder.init();
            var out: FrameBuffer = undefined;
            const step = decoder.next(&stream, &out, .{ .end_of_input = true });
            try testing.expectEqual(@as(usize, 1152), step.frame.samples);
            try testing.expectEqual(@as(usize, 104), step.frame.consumed);
            try testing.expectEqual(@as(u8, 1), step.frame.channels);
            try testing.expectEqual(@as(u32, 44100), step.frame.sample_rate);
        }
        {
            const frame = silentFrame(crc, 511);
            const stream = frame ++ frame;
            var decoder = Decoder.init();
            var out: FrameBuffer = undefined;
            // Nothing has filled the reservoir, so 511 bytes back is nowhere.
            const step = decoder.next(&stream, &out, .{ .end_of_input = true });
            try testing.expectEqual(Step{ .skipped = 104 }, step);
        }
    }
}

test "the decoder always makes progress or asks for more" {
    // A caller loops on `next` until the input is used up.  A step that
    // consumes nothing without asking for more input would spin forever.
    var rng = std.Random.DefaultPrng.init(0xc0ffee);
    const random = rng.random();
    var out: FrameBuffer = undefined;

    for (0..200) |_| {
        var noise: [512]u8 = undefined;
        random.bytes(&noise);
        var decoder = Decoder.init();
        var offset: usize = 0;
        var steps: usize = 0;
        while (offset < noise.len) {
            steps += 1;
            try testing.expect(steps <= noise.len + 8);
            switch (decoder.next(noise[offset..], &out, .{ .end_of_input = true })) {
                .need_more => break,
                .skipped => |n| {
                    try testing.expect(n > 0);
                    offset += n;
                },
                .frame => |frame| {
                    try testing.expect(frame.consumed > 0);
                    offset += frame.consumed;
                },
            }
        }
    }
}

test "toInt16 survives whatever it is handed" {
    // Converting a float that does not fit the integer is illegal behaviour
    // in Zig, not merely wrong, so the clamp has to catch every case before
    // the conversion sees it -- including the ones no decoder produces but a
    // caller might pass in.
    const nasty = [_]f32{
        std.math.nan(f32),
        -std.math.nan(f32),
        std.math.inf(f32),
        -std.math.inf(f32),
        std.math.floatMax(f32),
        -std.math.floatMax(f32),
        std.math.floatMin(f32),
        1e30,
        -1e30,
        0,
        -0.0,
        1,
        -1,
        0.99999994,
        -0.99999994,
    };
    var out: [nasty.len]i16 = undefined;
    toInt16(&nasty, &out);
    for (out) |value| {
        try testing.expect(value >= -32768 and value <= 32767);
    }
    try testing.expectEqual(@as(i16, 32767), out[2]); // +infinity
    try testing.expectEqual(@as(i16, -32768), out[3]); // -infinity
    try testing.expectEqual(@as(i16, 0), out[9]);
    try testing.expectEqual(@as(i16, 32767), out[11]); // +1 saturates
    try testing.expectEqual(@as(i16, -32768), out[12]);
}

test "toInt16 clips instead of wrapping" {
    var out: [5]i16 = undefined;
    toInt16(&[_]f32{ 0, 1, -1, 2, -2 }, &out);
    try testing.expectEqual(@as(i16, 0), out[0]);
    try testing.expectEqual(@as(i16, 32767), out[1]);
    try testing.expectEqual(@as(i16, -32768), out[2]);
    try testing.expectEqual(@as(i16, 32767), out[3]);
    try testing.expectEqual(@as(i16, -32768), out[4]);
}
