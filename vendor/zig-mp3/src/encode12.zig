// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! A Layer II encoder.
//!
//! The mirror of `layer12.zig`, and deliberately built on the same tables:
//! the allocation tables, the quantization classes and the scalefactors are
//! read out of the decoder rather than written again here, so the two cannot
//! drift apart.  What is *not* shared is the interesting part, because it is
//! the part the standard does not specify.  A decoder has one right answer;
//! an encoder has a budget and a choice about how to spend it, and every
//! choice made here -- which subbands get bits, how the scalefactors are
//! grouped, where the quantizer rounds -- is this encoder's own.
//!
//! A frame is 1152 samples of each channel:
//!
//!   1. the analysis filterbank turns them into 36 time slots of 32 subbands;
//!   2. the psychoacoustic model says how much noise each subband can hide;
//!   3. a scalefactor per subband and granule captures its peak;
//!   4. bits go to whichever subband is furthest from hiding its own noise,
//!      one step at a time, until the frame is full;
//!   5. the samples are quantized to what they were given and written out.
//!
//! Constant bit rate, stereo or mono.  Joint stereo is not attempted: it
//! decides that two channels are alike enough to share their upper subbands,
//! which is a judgement this has no way to make well yet, and coding both
//! channels in full is always correct if not always thrifty.

const std = @import("std");

const analysis = @import("analysis.zig");
const BitWriter = @import("bitwriter.zig");
const Header = @import("header.zig");
const layer12 = @import("layer12.zig");
const psymodel2 = @import("psymodel2.zig");

pub const subbands = layer12.subbands;
/// Samples of each channel one frame carries.
pub const frame_samples = layer12.max_samples;
/// Time slots in a frame, and granules of twelve.
const time_slots = frame_samples / subbands;
const granules = layer12.max_granules;

/// The largest frame Layer II can produce, in bytes.
pub const max_frame_bytes = 1728;

pub const Error = error{
    UnsupportedSampleRate,
    UnsupportedBitRate,
    UnsupportedChannelCount,
    /// The output buffer is smaller than the frame the settings ask for.
    NoSpace,
    /// The input is not one whole frame of every channel.
    WrongInputLength,
};

pub const Options = struct {
    sample_rate: u32,
    channels: u8 = 2,
    /// Bits per second across both channels.  Must be one the format can
    /// name for this sampling rate; `bitRates` lists them.
    bitrate: u32,
};

/// The bit rates Layer II can name at `sample_rate`, in bits per second.
///
/// The format cannot express an arbitrary rate: it sends an index into a
/// table of fourteen, and which table depends on the MPEG version.
pub fn bitRates(sample_rate: u32, out: *[14]u32) Error![]const u32 {
    const found = try describe(sample_rate);
    var count: usize = 0;
    for (1..15) |index| {
        var header = found.header;
        header.bitrate_index = @intCast(index);
        out[count] = header.bitRate() orelse continue;
        count += 1;
    }
    return out[0..count];
}

const Described = struct { header: Header };

fn describe(sample_rate: u32) Error!Described {
    const rates = [3]u32{ 44100, 48000, 32000 };
    var header: Header = .{
        .version = .mpeg1,
        .layer = .layer2,
        .crc_protected = false,
        .bitrate_index = 1,
        .sample_rate_index = 0,
        .padding = false,
        .private = false,
        .mode = .stereo,
        .mode_extension = 0,
        .copyright = false,
        .original = true,
        .emphasis = .none,
    };
    for (rates, 0..) |base, index| {
        if (sample_rate == base) {
            header.version = .mpeg1;
            header.sample_rate_index = @intCast(index);
            return .{ .header = header };
        }
        if (sample_rate == base / 2) {
            header.version = .mpeg2;
            header.sample_rate_index = @intCast(index);
            return .{ .header = header };
        }
    }
    return Error.UnsupportedSampleRate;
}

/// The signal-to-noise ratio each quantization class buys, in decibels.
///
/// A uniform quantizer of `n` levels over the same range as its input has a
/// noise power of one part in n^2 of the signal's, so this is 20 log10 n.
/// The standard tabulates measured figures instead, which differ by a decibel
/// or two at the coarse end; it makes no difference here, because what the
/// allocation loop needs from this is the order, not the values.
const class_snr = blk: {
    var t: [layer12.class_levels.len]f32 = undefined;
    for (layer12.class_levels, 0..) |levels, i| {
        t[i] = @floatCast(20.0 * std.math.log10(@as(f64, @floatFromInt(levels))));
    }
    break :blk t;
};

/// Sample bits one subband of one channel costs for a whole frame.
fn sampleBits(class: u8) usize {
    if (class == 0) return 0;
    if (class < 17) return time_slots * @as(usize, class);
    const levels = layer12.class_levels[class - 2];
    const width = levels + 2 - (levels >> 3);
    // Three time slots to a code word.
    return (time_slots / 3) * width;
}

/// Which of the three granules transmit a scalefactor, most significant bit
/// first, by selector.  The decoder reads this same pattern.
const scalefactor_pattern = [4]u3{ 0b111, 0b101, 0b100, 0b110 };

pub const Encoder = struct {
    header: Header,
    channels: u8,
    models: [2]psymodel2.Model,
    filters: [2]analysis.State,
    /// Carries the fraction of a slot a frame is short, so that padding is
    /// inserted exactly often enough to hold the stated bit rate.
    padding_debt: u32,
    /// Bits and bytes of the frame currently being built.
    total_bands: u8,
    /// Which allocation run each subband's code comes from.
    run_of_band: [subbands]layer12.Allocation,

    pub fn init(options: Options) Error!Encoder {
        if (options.channels == 0 or options.channels > 2) {
            return Error.UnsupportedChannelCount;
        }
        const found = try describe(options.sample_rate);
        var header = found.header;
        header.mode = if (options.channels == 1) .mono else .stereo;

        var index: ?u4 = null;
        for (1..15) |candidate| {
            header.bitrate_index = @intCast(candidate);
            if (header.bitRate() == options.bitrate) {
                index = @intCast(candidate);
                break;
            }
        }
        header.bitrate_index = index orelse return Error.UnsupportedBitRate;

        const table = layer12.allocationTable(header);
        var self: Encoder = .{
            .header = header,
            .channels = options.channels,
            .models = @splat(psymodel2.Model.init(options.sample_rate)),
            .filters = @splat(.{}),
            .padding_debt = 0,
            .total_bands = table.total,
            .run_of_band = undefined,
        };
        var band: usize = 0;
        for (table.runs) |run| {
            const end = @min(band + run.bands, table.total);
            while (band < end) : (band += 1) self.run_of_band[band] = run;
        }
        return self;
    }

    /// Bytes the next frame will occupy.  Varies by one, because most bit
    /// rates do not divide into a whole number of bytes per frame.
    pub fn nextFrameBytes(self: *const Encoder) usize {
        var header = self.header;
        header.padding = self.paddingWanted();
        return header.frameSize().?;
    }

    fn paddingWanted(self: *const Encoder) bool {
        const rate = self.header.sampleRate();
        const numerator = 144 * (self.header.bitRate().?);
        return self.padding_debt + numerator % rate >= rate;
    }

    /// Encode one frame.
    ///
    /// `input` is `frame_samples` samples of each channel, interleaved, in
    /// the range -1 to 1.  Returns the bytes written to `out`.
    pub fn encodeFrame(self: *Encoder, input: []const f32, out: []u8) Error!usize {
        const channels: usize = self.channels;
        if (input.len != frame_samples * channels) return Error.WrongInputLength;

        var header = self.header;
        header.padding = self.paddingWanted();
        const size = header.frameSize().?;
        if (out.len < size) return Error.NoSpace;

        // Book the padding, whether or not it was taken this time.
        const rate = header.sampleRate();
        self.padding_debt += 144 * header.bitRate().? % rate;
        if (self.padding_debt >= rate) self.padding_debt -= rate;

        // 1. The filterbank: 36 time slots of 32 subbands per channel.
        var sub: [2][subbands][time_slots]f32 = undefined;
        var pcm: [2][frame_samples]f32 = undefined;
        for (0..channels) |ch| {
            for (0..frame_samples) |n| pcm[ch][n] = input[n * channels + ch];
            for (0..time_slots) |slot| {
                var one: [subbands]f32 = undefined;
                analysis.analyze(&self.filters[ch], pcm[ch][slot * subbands ..][0..subbands], &one);
                for (0..subbands) |band| sub[ch][band][slot] = one[band];
            }
        }

        // 2. What the ear will not hear, from the first 1024 samples of the
        // frame.  The standard centres its window on the frame; this does
        // not, which costs a little accuracy at a transient and nothing at
        // all elsewhere.
        var smr: [2][subbands]f32 = undefined;
        for (0..channels) |ch| {
            var result: psymodel2.Result = .{};
            self.models[ch].analyze(pcm[ch][0..psymodel2.window_len], &result);
            self.models[ch].signalToMask(&result, &smr[ch]);
        }

        // 3. A scalefactor per subband, channel and granule, and the selector
        // saying which of the three are actually sent.
        var scale_index: [subbands][2][granules]u8 = undefined;
        var selector: [subbands][2]u8 = undefined;
        var scale_count: [subbands][2]u8 = undefined;
        for (0..self.total_bands) |band| {
            for (0..channels) |ch| {
                for (0..granules) |g| {
                    var peak: f32 = 0;
                    const from = g * (time_slots / granules);
                    for (sub[ch][band][from..][0 .. time_slots / granules]) |value| {
                        peak = @max(peak, @abs(value));
                    }
                    scale_index[band][ch][g] = scalefactorFor(peak);
                }
                const s = &scale_index[band][ch];
                const chosen = chooseSelector(s);
                selector[band][ch] = chosen.selector;
                scale_count[band][ch] = chosen.count;
                // The decoder repeats scalefactors the selector does not
                // send, so the ones not sent must be made to match what it
                // will use in their place.
                applySelector(s, chosen.selector);
            }
        }

        // 4. Spend the frame's bits.
        var code: [subbands][2]u8 = @splat(@splat(0));
        self.allocate(size, &smr, &scale_count, &code);

        // 5. Write it.
        var writer = BitWriter.init(out[0..size]);
        self.writeHeader(&writer, header);
        for (0..self.total_bands) |band| {
            for (0..channels) |ch| {
                writer.write(code[band][ch], self.run_of_band[band].width);
            }
        }
        for (0..self.total_bands) |band| {
            for (0..channels) |ch| {
                if (self.classOf(band, code[band][ch]) == 0) continue;
                writer.write(selector[band][ch], 2);
            }
        }
        for (0..self.total_bands) |band| {
            for (0..channels) |ch| {
                if (self.classOf(band, code[band][ch]) == 0) continue;
                const present = scalefactor_pattern[selector[band][ch]];
                var which: u3 = 4;
                for (0..granules) |g| {
                    if (present & which != 0) writer.write(scale_index[band][ch][g], 6);
                    which >>= 1;
                }
            }
        }
        self.writeSamples(&writer, &sub, &code, &scale_index);
        std.debug.assert(writer.overrun == 0);
        return size;
    }

    fn classOf(self: *const Encoder, band: usize, index: u8) u8 {
        const run = self.run_of_band[band];
        return layer12.allocation_codes[run.offset + index];
    }

    fn writeHeader(self: *const Encoder, writer: *BitWriter, header: Header) void {
        _ = self;
        writer.write(0x7ff, 11); // sync
        writer.write(@intFromEnum(header.version), 2);
        writer.write(@intFromEnum(header.layer), 2);
        writer.write(1, 1); // protection bit is active low: no CRC
        writer.write(header.bitrate_index, 4);
        writer.write(header.sample_rate_index, 2);
        writer.write(@intFromBool(header.padding), 1);
        writer.write(@intFromBool(header.private), 1);
        writer.write(@intFromEnum(header.mode), 2);
        writer.write(header.mode_extension, 2);
        writer.write(@intFromBool(header.copyright), 1);
        writer.write(@intFromBool(header.original), 1);
        writer.write(@intFromEnum(header.emphasis), 2);
    }

    /// Give bits to whichever subband is furthest from hiding its own noise,
    /// one quantization class at a time, until nothing more fits.
    ///
    /// The measure is the mask-to-noise ratio: how much better the subband's
    /// signal-to-noise ratio already is than it needs to be.  The subband
    /// with the smallest is the one a listener will notice first, so it goes
    /// next; a subband whose signal is under its own masking threshold has a
    /// large ratio from the start and is never chosen while anything audible
    /// is still wanting.
    fn allocate(
        self: *const Encoder,
        size: usize,
        smr: *const [2][subbands]f32,
        scale_count: *const [subbands][2]u8,
        code: *[subbands][2]u8,
    ) void {
        const channels: usize = self.channels;
        var left: isize = @intCast(size * 8 - 32);
        for (0..self.total_bands) |band| {
            left -= @as(isize, self.run_of_band[band].width) * @as(isize, @intCast(channels));
        }

        var stuck: [subbands][2]bool = @splat(@splat(false));
        while (true) {
            var best_band: usize = 0;
            var best_ch: usize = 0;
            var best: f32 = std.math.inf(f32);
            var any = false;
            for (0..self.total_bands) |band| {
                const width = self.run_of_band[band].width;
                const limit = (@as(usize, 1) << width) - 1;
                for (0..channels) |ch| {
                    if (stuck[band][ch] or code[band][ch] >= limit) continue;
                    const class = self.classOf(band, code[band][ch]);
                    const snr: f32 = if (class == 0) 0 else class_snr[class - 2];
                    const mnr = snr - smr[ch][band];
                    if (!any or mnr < best) {
                        any = true;
                        best = mnr;
                        best_band = band;
                        best_ch = ch;
                    }
                }
            }
            if (!any) return;

            const was = self.classOf(best_band, code[best_band][best_ch]);
            const now = self.classOf(best_band, code[best_band][best_ch] + 1);
            var delta: isize = @intCast(sampleBits(now));
            delta -= @intCast(sampleBits(was));
            // Turning a subband on for the first time also buys its selector
            // and its scalefactors.
            if (was == 0 and now != 0) {
                delta += 2 + 6 * @as(isize, scale_count[best_band][best_ch]);
            }
            if (delta <= left) {
                left -= delta;
                code[best_band][best_ch] += 1;
            } else {
                stuck[best_band][best_ch] = true;
            }
        }
    }

    fn writeSamples(
        self: *const Encoder,
        writer: *BitWriter,
        sub: *const [2][subbands][time_slots]f32,
        code: *const [subbands][2]u8,
        scale_index: *const [subbands][2][granules]u8,
    ) void {
        const channels: usize = self.channels;
        const per_granule = time_slots / granules;
        for (0..granules) |g| {
            var slot: usize = 0;
            while (slot < per_granule) : (slot += 3) {
                for (0..self.total_bands) |band| {
                    for (0..channels) |ch| {
                        const class = self.classOf(band, code[band][ch]);
                        if (class == 0) continue;
                        const levels = layer12.class_levels[class - 2];
                        const step = layer12.scale_steps[class - 2][scale_index[band][ch][g]];
                        const at = g * per_granule + slot;

                        if (class < 17) {
                            const half: i32 = (@as(i32, 1) << @intCast(class - 1)) - 1;
                            for (0..3) |k| {
                                const raw = quantize(sub[ch][band][at + k], step, half, levels);
                                writer.write(raw, @intCast(class));
                            }
                        } else {
                            // Three values in one code word, least significant
                            // first, which is the order the decoder unpacks.
                            const half: i32 = @intCast(levels / 2);
                            const width: u6 = @intCast(levels + 2 - (levels >> 3));
                            var word: u32 = 0;
                            var scale: u32 = 1;
                            for (0..3) |k| {
                                const raw = quantize(sub[ch][band][at + k], step, half, levels);
                                word += raw * scale;
                                scale *= levels;
                            }
                            writer.write(word, width);
                        }
                    }
                }
            }
        }
    }
};

/// Turn one subband sample into the code the decoder will read.
///
/// The decoder computes `(raw - half) * step`, so this is that inverted and
/// rounded, held inside the range the class can express.  Clamping rather
/// than wrapping matters: a value one past the end is a sample slightly
/// louder than its scalefactor promised, and clipping it is a small error
/// where wrapping it is a loud click.
fn quantize(value: f32, step: f32, half: i32, levels: u32) u32 {
    const scaled = @round(value / step) + @as(f32, @floatFromInt(half));
    const limit: f32 = @floatFromInt(levels - 1);
    return @intFromFloat(std.math.clamp(scaled, 0, limit));
}

/// The scalefactor index whose range just covers a peak of `peak`.
///
/// Table B.1's entry `i` is 2^(1 - i/3), and a subband quantized against it
/// can represent values up to about that, so the wanted index is the largest
/// whose scalefactor is still at least the peak.
fn scalefactorFor(peak: f32) u8 {
    if (!(peak > 0)) return 62;
    const index = @floor(3.0 * (1.0 - std.math.log2(peak)));
    return @intFromFloat(std.math.clamp(index, 0, 62));
}

const Chosen = struct { selector: u8, count: u8 };

/// Pick the scalefactor selector that sends the fewest of the three.
///
/// The three granules very often want the same scalefactor, or two the same,
/// and the format has a two-bit field for saying so: it is six bits saved per
/// subband per repeat, which at 32 subbands and two channels is worth having.
fn chooseSelector(s: *const [granules]u8) Chosen {
    if (s[0] == s[1] and s[1] == s[2]) return .{ .selector = 2, .count = 1 };
    if (s[0] == s[1]) return .{ .selector = 1, .count = 2 };
    if (s[1] == s[2]) return .{ .selector = 3, .count = 2 };
    return .{ .selector = 0, .count = 3 };
}

/// Make the scalefactors the selector does not send match the ones the
/// decoder will use in their place, so that what was quantized against is
/// what will be dequantized against.
fn applySelector(s: *[granules]u8, selector: u8) void {
    switch (selector) {
        1 => s[1] = s[0],
        2 => {
            s[1] = s[0];
            s[2] = s[0];
        },
        3 => s[2] = s[1],
        else => {},
    }
}

const testing = std.testing;

test "the header the encoder writes is the one it meant" {
    var encoder = try Encoder.init(.{ .sample_rate = 44100, .channels = 2, .bitrate = 192_000 });
    var input: [frame_samples * 2]f32 = @splat(0);
    var out: [max_frame_bytes]u8 = undefined;
    const size = try encoder.encodeFrame(&input, &out);

    const header = Header.parse(out[0..4].*) orelse return error.NotAHeader;
    try testing.expectEqual(Header.Layer.layer2, header.layer);
    try testing.expectEqual(Header.Version.mpeg1, header.version);
    try testing.expectEqual(@as(u32, 44100), header.sampleRate());
    try testing.expectEqual(@as(u32, 192_000), header.bitRate().?);
    try testing.expectEqual(@as(u8, 2), header.channels());
    try testing.expectEqual(size, header.frameSize().?);
}

test "unsupported settings are refused rather than approximated" {
    try testing.expectError(
        Error.UnsupportedSampleRate,
        Encoder.init(.{ .sample_rate = 44101, .bitrate = 192_000 }),
    );
    try testing.expectError(
        Error.UnsupportedBitRate,
        Encoder.init(.{ .sample_rate = 44100, .bitrate = 193_000 }),
    );
    try testing.expectError(
        Error.UnsupportedChannelCount,
        Encoder.init(.{ .sample_rate = 44100, .channels = 3, .bitrate = 192_000 }),
    );
}

test "the bit rates offered are the ones that work" {
    var buffer: [14]u32 = undefined;
    const rates = try bitRates(44100, &buffer);
    try testing.expect(rates.len == 14);
    for (rates) |rate| {
        var encoder = try Encoder.init(.{ .sample_rate = 44100, .bitrate = rate });
        try testing.expect(encoder.nextFrameBytes() > 0);
    }
}

test "padding holds the stated bit rate over many frames" {
    // 144 * 128000 / 44100 is not a whole number, so some frames have to
    // carry an extra byte; over a second of audio the average has to come out
    // at the rate that was asked for.
    var encoder = try Encoder.init(.{ .sample_rate = 44100, .channels = 2, .bitrate = 128_000 });
    var input: [frame_samples * 2]f32 = @splat(0);
    var out: [max_frame_bytes]u8 = undefined;
    var total: usize = 0;
    const count = 100;
    for (0..count) |_| total += try encoder.encodeFrame(&input, &out);

    const seconds = @as(f64, count * frame_samples) / 44100.0;
    const measured = @as(f64, @floatFromInt(total * 8)) / seconds;
    try testing.expectApproxEqRel(@as(f64, 128_000), measured, 0.005);
}

test "what is encoded decodes back to something like the input" {
    const mp3 = @import("root.zig");
    const rate = 44100;
    const frames = 24;
    const count = frames * frame_samples;

    var input: [count * 2]f32 = undefined;
    for (0..count) |n| {
        const t = @as(f64, @floatFromInt(n)) / rate;
        const left = 0.45 * @sin(2.0 * std.math.pi * 1000.0 * t) +
            0.25 * @sin(2.0 * std.math.pi * 3200.0 * t);
        const right = 0.40 * @sin(2.0 * std.math.pi * 700.0 * t) +
            0.20 * @sin(2.0 * std.math.pi * 5100.0 * t);
        input[n * 2] = @floatCast(left);
        input[n * 2 + 1] = @floatCast(right);
    }

    var encoder = try Encoder.init(.{ .sample_rate = rate, .channels = 2, .bitrate = 256_000 });
    var stream: std.ArrayList(u8) = .empty;
    defer stream.deinit(testing.allocator);
    var frame: [max_frame_bytes]u8 = undefined;
    for (0..frames) |f| {
        const size = try encoder.encodeFrame(
            input[f * frame_samples * 2 ..][0 .. frame_samples * 2],
            &frame,
        );
        try stream.appendSlice(testing.allocator, frame[0..size]);
    }

    var audio = try mp3.decodeAll(testing.allocator, stream.items);
    defer audio.deinit();
    try testing.expectEqual(@as(u32, rate), audio.sample_rate);
    try testing.expectEqual(@as(u8, 2), audio.channels);

    // The filterbank pair delays the signal by 481 samples, and the first and
    // last frames are the ones missing their neighbours' overlap, so the
    // comparison starts after one frame and stops before the last.
    const delay = analysis.delay;
    var signal: f64 = 0;
    var noise: f64 = 0;
    var n: usize = frame_samples;
    while (n < count - frame_samples) : (n += 1) {
        for (0..2) |ch| {
            const want = input[(n - delay) * 2 + ch];
            const got = audio.samples[n * 2 + ch];
            signal += @as(f64, want) * want;
            noise += @as(f64, got - want) * (got - want);
        }
    }
    const snr = 10 * std.math.log10(signal / @max(noise, 1e-30));
    // Better than 70 dB: at this bit rate the few subbands that carry
    // anything get most of the frame between them, so they are quantized
    // very finely indeed.
    testing.expect(snr > 70) catch |err| {
        std.debug.print("round trip SNR {d:.2} dB at 256 kbit/s\n", .{snr});
        return err;
    };
}
