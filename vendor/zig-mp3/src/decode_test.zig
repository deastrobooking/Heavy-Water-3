// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Whole-stream tests against reference decodings.
//!
//! The `.pcm` files in `testdata` were produced by ffmpeg's own decoder, not
//! by this one, so agreement with them is evidence rather than a tautology.
//! `tools/check-against-ffmpeg.py` runs the same comparison over a much wider
//! matrix of sampling rates, bit rates and channel modes.
//!
//! Agreement is measured as signal-to-noise ratio against the reference, in
//! decibels.  Two decoders that differ only in the last bit of a 16-bit sample
//! score around 80 dB, which is what these all do; anything materially wrong
//! with a window, a table or a stereo mode drops it by tens of decibels.

const std = @import("std");

const mp3 = @import("root.zig");

const Clip = struct {
    name: []const u8,
    mp3: []const u8,
    reference: []const u8,
    sample_rate: u32,
    channels: u8,
    /// The largest difference from the reference, in units of the last bit of
    /// a 16-bit sample, that the clip is allowed to show.  Layer III rounds
    /// the same arithmetic ffmpeg does and agrees to one; Layers I and II
    /// requantize by a different route and agree to two.
    tolerance: u32 = 1,
};

fn clips() [5]Clip {
    return .{
        .{
            .name = "MPEG-1 44100 Hz joint stereo",
            .mp3 = @embedFile("testdata/stereo44.mp3"),
            .reference = @embedFile("testdata/stereo44.pcm"),
            .sample_rate = 44100,
            .channels = 2,
        },
        .{
            .name = "MPEG-2 22050 Hz mono",
            .mp3 = @embedFile("testdata/mono22.mp3"),
            .reference = @embedFile("testdata/mono22.pcm"),
            .sample_rate = 22050,
            .channels = 1,
        },
        .{
            .name = "MPEG-2.5 11025 Hz mono",
            .mp3 = @embedFile("testdata/mono11.mp3"),
            .reference = @embedFile("testdata/mono11.pcm"),
            .sample_rate = 11025,
            .channels = 1,
        },
        .{
            .name = "MPEG-1 44100 Hz Layer I joint stereo",
            .mp3 = @embedFile("testdata/layer1.mp1"),
            .reference = @embedFile("testdata/layer1.pcm"),
            .sample_rate = 44100,
            .channels = 2,
            .tolerance = 2,
        },
        .{
            .name = "MPEG-1 44100 Hz Layer II stereo",
            .mp3 = @embedFile("testdata/layer2.mp2"),
            .reference = @embedFile("testdata/layer2.pcm"),
            .sample_rate = 44100,
            .channels = 2,
            .tolerance = 2,
        },
    };
}

const Agreement = struct {
    snr_db: f64,
    peak_difference: u32,
    count: usize,
};

fn compare(decoded: []const f32, reference: []const u8) Agreement {
    const count = @min(decoded.len, reference.len / 2);
    var signal: f64 = 0;
    var noise: f64 = 0;
    var peak: u32 = 0;
    for (0..count) |n| {
        const want: i32 = std.mem.readInt(i16, reference[n * 2 ..][0..2], .little);
        const scaled = std.math.clamp(decoded[n] * 32768.0, -32768.0, 32767.0);
        const got: i32 = @intFromFloat(scaled);
        const difference = got - want;
        signal += @as(f64, @floatFromInt(want)) * @as(f64, @floatFromInt(want));
        noise += @as(f64, @floatFromInt(difference)) * @as(f64, @floatFromInt(difference));
        peak = @max(peak, @abs(difference));
    }
    const snr = if (noise == 0) std.math.inf(f64) else 10 * std.math.log10(signal / noise);
    return .{ .snr_db = snr, .peak_difference = peak, .count = count };
}

test "decoded streams match ffmpeg's decoding of the same files" {
    for (clips()) |clip| {
        var audio = try mp3.decodeAll(std.testing.allocator, clip.mp3);
        defer audio.deinit();

        try std.testing.expectEqual(clip.sample_rate, audio.sample_rate);
        try std.testing.expectEqual(clip.channels, audio.channels);
        try std.testing.expectEqual(clip.reference.len / 2, audio.samples.len);

        const result = compare(audio.samples, clip.reference);
        std.testing.expect(result.snr_db > 70) catch |err| {
            std.debug.print(
                "{s}: SNR {d:.2} dB over {d} samples, peak difference {d}\n",
                .{ clip.name, result.snr_db, result.count, result.peak_difference },
            );
            return err;
        };
        // Rounding to 16 bits is the only difference there should be.
        std.testing.expect(result.peak_difference <= clip.tolerance) catch |err| {
            std.debug.print("{s}: peak difference {d}, allowed {d}\n", .{
                clip.name, result.peak_difference, clip.tolerance,
            });
            return err;
        };
    }
}

test "feeding the decoder in small pieces gives the same result" {
    // A caller pulling from a socket sees the stream a few bytes at a time,
    // and must get back exactly what a caller holding all of it gets.
    for (clips()) |clip| {
        var whole = try mp3.decodeAll(std.testing.allocator, clip.mp3);
        defer whole.deinit();

        for ([_]usize{ 1, 7, 64, 500 }) |chunk| {
            var decoder = mp3.Decoder.init();
            var buffer: mp3.FrameBuffer = undefined;
            var piecewise: std.ArrayList(f32) = .empty;
            defer piecewise.deinit(std.testing.allocator);

            var start: usize = 0;
            var available: usize = 0;
            while (start < clip.mp3.len) {
                available = @min(available + chunk, clip.mp3.len - start);
                const window = clip.mp3[start..][0..available];
                const final = start + available == clip.mp3.len;
                switch (decoder.next(window, &buffer, .{ .end_of_input = final })) {
                    .need_more => if (final) break else continue,
                    .skipped => |n| {
                        start += n;
                        available -= n;
                    },
                    .frame => |frame| {
                        try piecewise.appendSlice(
                            std.testing.allocator,
                            buffer[0 .. frame.samples * @as(usize, frame.channels)],
                        );
                        start += frame.consumed;
                        available -= frame.consumed;
                    },
                }
            }

            std.testing.expectEqualSlices(f32, whole.samples, piecewise.items) catch |err| {
                std.debug.print("{s}: mismatch at chunk size {d}\n", .{ clip.name, chunk });
                return err;
            };
        }
    }
}

test "resetting mid stream costs at most a frame or two of audio" {
    // A seek throws away the bit reservoir and the filterbank history, so the
    // decoder cannot reproduce the frames that depended on them; it must
    // recover quickly and quietly rather than produce noise.
    const clip = clips()[0];
    var whole = try mp3.decodeAll(std.testing.allocator, clip.mp3);
    defer whole.deinit();

    var decoder = mp3.Decoder.init();
    var buffer: mp3.FrameBuffer = undefined;
    var offset: usize = 0;
    var produced: usize = 0;
    var reset_done = false;

    while (offset < clip.mp3.len) {
        switch (decoder.next(clip.mp3[offset..], &buffer, .{ .end_of_input = true })) {
            .need_more => break,
            .skipped => |n| offset += n,
            .frame => |frame| {
                offset += frame.consumed;
                produced += frame.samples * @as(usize, frame.channels);
                if (!reset_done and produced > whole.samples.len / 2) {
                    decoder.reset();
                    reset_done = true;
                }
            },
        }
    }
    try std.testing.expect(reset_done);
    // Nothing is dropped outright: every frame after the reset still decodes,
    // even if the first of them is not what a continuous decode would give.
    try std.testing.expect(produced >= whole.samples.len - 2 * 1152 * 2);
}

test "a stream with rubbish spliced into it still decodes the good frames" {
    const clip = clips()[1];
    var clean = try mp3.decodeAll(std.testing.allocator, clip.mp3);
    defer clean.deinit();

    // Splice 300 bytes of noise into the middle, on a frame boundary or not.
    var spliced: std.ArrayList(u8) = .empty;
    defer spliced.deinit(std.testing.allocator);
    const cut = clip.mp3.len / 2;
    try spliced.appendSlice(std.testing.allocator, clip.mp3[0..cut]);
    var rng = std.Random.DefaultPrng.init(9);
    var noise: [300]u8 = undefined;
    rng.random().bytes(&noise);
    for (&noise) |*byte| byte.* &= 0x7f; // no accidental sync words
    try spliced.appendSlice(std.testing.allocator, &noise);
    try spliced.appendSlice(std.testing.allocator, clip.mp3[cut..]);

    var damaged = try mp3.decodeAll(std.testing.allocator, spliced.items);
    defer damaged.deinit();

    try std.testing.expectEqual(clean.sample_rate, damaged.sample_rate);
    try std.testing.expectEqual(clean.channels, damaged.channels);
    // The frames on either side of the splice are lost to resynchronization
    // and the reservoir, but the great majority survive.
    try std.testing.expect(damaged.samples.len > clean.samples.len * 4 / 5);
}

test "corruption of a real stream never crashes the decoder" {
    // Bit flips and truncations, over a stream that is otherwise valid, reach
    // much further into the decoder than random noise does: the frames still
    // sync, so the damage lands in side information, scalefactors and Huffman
    // data, where a decoder is most likely to index off the end of something.
    // Debug builds check every bound, so a crash here is a real defect.
    var rng = std.Random.DefaultPrng.init(0x6d7033);
    const random = rng.random();
    var buffer: mp3.FrameBuffer = undefined;

    for (clips()) |clip| {
        const scratch = try std.testing.allocator.alloc(u8, clip.mp3.len);
        defer std.testing.allocator.free(scratch);

        for (0..200) |_| {
            @memcpy(scratch, clip.mp3);
            for (0..random.uintLessThan(usize, 48) + 1) |_| {
                const at = random.uintLessThan(usize, scratch.len);
                scratch[at] ^= @as(u8, 1) << random.int(u3);
            }
            const input = scratch[0 .. random.uintLessThan(usize, scratch.len) + 1];

            var decoder = mp3.Decoder.init();
            var offset: usize = 0;
            var steps: usize = 0;
            while (offset < input.len) {
                steps += 1;
                // Every step consumes at least one byte or asks for more.
                try std.testing.expect(steps <= input.len);
                switch (decoder.next(input[offset..], &buffer, .{ .end_of_input = true })) {
                    .need_more => break,
                    .skipped => |n| {
                        try std.testing.expect(n > 0);
                        offset += n;
                    },
                    .frame => |frame| {
                        try std.testing.expect(frame.consumed > 0);
                        offset += frame.consumed;
                        // Garbage in must still come out as numbers.
                        const count = frame.samples * @as(usize, frame.channels);
                        for (buffer[0..count]) |sample| {
                            try std.testing.expect(std.math.isFinite(sample));
                        }
                    },
                }
            }
        }
    }
}

test "every decoded sample is finite and within range" {
    for (clips()) |clip| {
        var audio = try mp3.decodeAll(std.testing.allocator, clip.mp3);
        defer audio.deinit();
        for (audio.samples) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            try std.testing.expect(@abs(sample) <= 4);
        }
    }
}
