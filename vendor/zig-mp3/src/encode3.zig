// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! A Layer III encoder.
//!
//! Layer III adds three things to what Layer II needed, and this is where
//! they meet: a second transform behind the filterbank, Huffman coding of the
//! quantized spectrum, and a pair of nested loops that decide how finely to
//! quantize.  The loops are the heart of it.
//!
//!   * The *rate* loop asks how loud the quantizer's step has to be for the
//!     granule to fit the bits it has been given.  Bits fall as the step
//!     grows, so this is a search over one number.
//!
//!   * The *distortion* loop asks whether the noise that quantizing left
//!     behind is hidden.  Where a scalefactor band's noise is above what the
//!     psychoacoustic model says can be masked there, that band's scalefactor
//!     goes up, which quantizes it more finely at the cost of bits everywhere
//!     else -- so the rate loop runs again, and the two go round until either
//!     every band is hidden or nothing more can be done.
//!
//! What this does not do yet is written up in the README: long blocks only,
//! no bit reservoir, left and right coded independently, and MPEG-1 sampling
//! rates.  Each of those is a quality or efficiency limit rather than a
//! correctness one -- what comes out is a stream any decoder will read.

const std = @import("std");

const analysis = @import("analysis.zig");
const BitWriter = @import("bitwriter.zig");
const Header = @import("header.zig");
const huffman_encode = @import("huffman_encode.zig");
const imdct = @import("imdct.zig");
const mdct = @import("mdct.zig");
const psymodel2 = @import("psymodel2.zig");
const scalefactor_bands = @import("tables/scalefactor_bands.zig");
const side_info = @import("side_info.zig");

pub const granule_len = mdct.granule_len;
pub const subbands = mdct.subbands;
/// Granules in a frame, and samples of each channel one frame carries.
pub const granules = 2;
pub const frame_samples = granules * granule_len;
/// The largest frame Layer III can produce at an MPEG-1 rate, in bytes.
pub const max_frame_bytes = 1441;

/// The largest magnitude a Huffman table can name: fifteen from the code
/// tree, plus the thirteen bits of escape the widest tables carry.
const max_quantized = 15 + (1 << 13) - 1;

/// Scalefactor bands a long block has.  The twenty-second carries no
/// scalefactor of its own and is always coded at zero.
const long_bands = 21;

pub const Error = error{
    UnsupportedSampleRate,
    UnsupportedBitRate,
    UnsupportedChannelCount,
    NoSpace,
    WrongInputLength,
};

pub const Options = struct {
    sample_rate: u32,
    channels: u8 = 2,
    /// Bits per second across both channels.
    bitrate: u32,
};

/// ISO/IEC 11172-3 Table 9: slen1 and slen2 by `scalefac_compress`, the same
/// table the decoder reads.
const compress_lengths = [16][2]u8{
    .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ 0, 3 }, .{ 3, 0 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 3 },
    .{ 2, 1 }, .{ 2, 2 }, .{ 2, 3 }, .{ 3, 1 }, .{ 3, 2 }, .{ 3, 3 }, .{ 4, 2 }, .{ 4, 3 },
};

/// The bit rates Layer III can name at `sample_rate`, in bits per second.
pub fn bitRates(sample_rate: u32, out: *[14]u32) Error![]const u32 {
    var header = try headerFor(sample_rate);
    var count: usize = 0;
    for (1..15) |index| {
        header.bitrate_index = @intCast(index);
        out[count] = header.bitRate() orelse continue;
        count += 1;
    }
    return out[0..count];
}

fn headerFor(sample_rate: u32) Error!Header {
    const rates = [3]u32{ 44100, 48000, 32000 };
    for (rates, 0..) |base, index| {
        if (sample_rate != base) continue;
        return .{
            .version = .mpeg1,
            .layer = .layer3,
            .crc_protected = false,
            .bitrate_index = 1,
            .sample_rate_index = @intCast(index),
            .padding = false,
            .private = false,
            .mode = .stereo,
            .mode_extension = 0,
            .copyright = false,
            .original = true,
            .emphasis = .none,
        };
    }
    return Error.UnsupportedSampleRate;
}

/// 2^(x/4), which is every gain the format can name.
fn exp4(exponent: i32) f32 {
    return @floatCast(std.math.pow(f64, 2.0, @as(f64, @floatFromInt(exponent)) / 4.0));
}

/// What one granule of one channel was quantized into.
const Coded = struct {
    quantized: [granule_len]i32 = @splat(0),
    scalefac: [long_bands]u8 = @splat(0),
    global_gain: u8 = 210,
    scalefac_compress: u8 = 0,
    big_values: u16 = 0,
    count1_quads: u16 = 0,
    region0_count: u8 = 0,
    region1_count: u8 = 0,
    table_select: [3]u8 = @splat(0),
    count1table_select: u8 = 0,
    part2_length: usize = 0,
    part2_3_length: usize = 0,
};

pub const Encoder = struct {
    header: Header,
    channels: u8,
    filters: [2]analysis.State,
    transforms: [2]mdct.State,
    /// One model per channel: the tonality measure predicts each frame from
    /// the two before it in that channel, so the histories cannot be shared.
    models: [2]psymodel2.Model,
    /// The last window of input for each channel, so that the model sees a
    /// steady hop of one granule.
    history: [2][psymodel2.window_len]f32,
    padding_debt: u32,
    /// Widths of the long scalefactor bands at this sampling rate.
    widths: [22]u8,
    /// Where each band starts, in spectral lines.
    starts: [23]u16,

    pub fn init(options: Options) Error!Encoder {
        if (options.channels == 0 or options.channels > 2) {
            return Error.UnsupportedChannelCount;
        }
        var header = try headerFor(options.sample_rate);
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

        const row = scalefactor_bands.bands[
            scalefactor_bands.index(
                header.version.tableIndex(),
                header.sample_rate_index,
            )
        ];

        var self: Encoder = .{
            .header = header,
            .channels = options.channels,
            .filters = @splat(.{}),
            .transforms = @splat(.{}),
            .models = @splat(psymodel2.Model.init(options.sample_rate)),
            .history = @splat(@splat(0)),
            .padding_debt = 0,
            .widths = row.long_widths,
            .starts = undefined,
        };
        var at: u16 = 0;
        for (row.long_widths, 0..) |width, band| {
            self.starts[band] = at;
            at += width;
        }
        self.starts[22] = at;
        return self;
    }

    pub fn nextFrameBytes(self: *const Encoder) usize {
        var header = self.header;
        header.padding = self.paddingWanted();
        return header.frameSize().?;
    }

    fn paddingWanted(self: *const Encoder) bool {
        const rate = self.header.sampleRate();
        return self.padding_debt + (144 * self.header.bitRate().?) % rate >= rate;
    }

    /// Encode one frame: `frame_samples` samples of each channel,
    /// interleaved, in the range -1 to 1.
    pub fn encodeFrame(self: *Encoder, input: []const f32, out: []u8) Error!usize {
        const channels: usize = self.channels;
        if (input.len != frame_samples * channels) return Error.WrongInputLength;

        var header = self.header;
        header.padding = self.paddingWanted();
        const size = header.frameSize().?;
        if (out.len < size) return Error.NoSpace;
        const rate = header.sampleRate();
        self.padding_debt += (144 * header.bitRate().?) % rate;
        if (self.padding_debt >= rate) self.padding_debt -= rate;

        // 1. The filterbank, then the transform, for both granules of both
        // channels.
        var lines: [granules][2][granule_len]f32 = undefined;
        var pcm: [2][frame_samples]f32 = undefined;
        for (0..channels) |ch| {
            for (0..frame_samples) |n| pcm[ch][n] = input[n * channels + ch];
            for (0..granules) |gr| {
                var slots: [granule_len]f32 = undefined;
                for (0..18) |slot| {
                    var one: [subbands]f32 = undefined;
                    const at = (gr * 18 + slot) * subbands;
                    analysis.analyze(&self.filters[ch], pcm[ch][at..][0..subbands], &one);
                    for (0..subbands) |sb| slots[sb * 18 + slot] = one[sb];
                }
                // The decoder inverts the frequency of every other subband
                // between its transform and its filterbank, so this has to
                // happen between ours -- and since negating twice is doing
                // nothing, the decoder's own function is what undoes it.
                imdct.invertFrequency(&slots);
                mdct.forward(&self.transforms[ch], &slots, &lines[gr][ch], .normal, 0);
                // The decoder undoes the aliasing before its transform, so
                // this puts it in after ours.
                mdct.expandAlias(&lines[gr][ch], subbands);
            }
        }

        // 2. What can be hidden, per scalefactor band.  The model runs once
        // per granule rather than once per frame, at a hop of one granule,
        // which is what its prediction needs to mean anything.
        var thresholds: [granules][2][long_bands]f32 = undefined;
        for (0..channels) |ch| {
            for (0..granules) |gr| {
                const window = &self.history[ch];
                const keep = psymodel2.window_len - granule_len;
                std.mem.copyForwards(f32, window[0..keep], window[granule_len..]);
                @memcpy(window[keep..], pcm[ch][gr * granule_len ..][0..granule_len]);

                var result: psymodel2.Result = .{};
                self.models[ch].analyze(window, &result);
                var ratio: [long_bands]f32 = undefined;
                self.models[ch].maskToSignalPerBand(
                    &result,
                    self.starts[0 .. long_bands + 1],
                    granule_len,
                    &ratio,
                );
                self.thresholdsFor(&lines[gr][ch], &ratio, &thresholds[gr][ch]);
            }
        }

        // 3. The bits, shared out as the granules are coded so that one that
        // needs less leaves more for the next.
        const capacity = size - 4 - header.sideInfoSize();
        var left: usize = capacity * 8;
        var units: usize = granules * channels;

        var coded: [granules][2]Coded = undefined;
        for (0..granules) |gr| {
            for (0..channels) |ch| {
                const share = left / units;
                coded[gr][ch] = self.codeGranule(
                    &lines[gr][ch],
                    &thresholds[gr][ch],
                    @min(share, 4095),
                );
                left -= coded[gr][ch].part2_3_length;
                units -= 1;
            }
        }

        // 4. Write it.
        var writer = BitWriter.init(out[0..size]);
        writeHeader(&writer, header);
        self.writeSideInfo(&writer, &coded);
        std.debug.assert(writer.pos == (4 + header.sideInfoSize()) * 8);
        for (0..granules) |gr| {
            for (0..channels) |ch| {
                const before = writer.pos;
                self.writeScalefactors(&writer, &coded[gr][ch]);
                self.writeSpectrum(&writer, &coded[gr][ch]);
                std.debug.assert(writer.pos - before == coded[gr][ch].part2_3_length);
            }
        }
        std.debug.assert(writer.overrun == 0);
        return size;
    }

    /// Turn the model's per-band ratios into the noise power each scalefactor
    /// band may actually carry.
    ///
    /// The model measures a Fourier spectrum and this quantizes an MDCT one,
    /// so only the proportion carries across: how far below its own energy a
    /// band's noise has to sit.  That proportion is applied here to the
    /// energy the transform really produced.
    fn thresholdsFor(
        self: *const Encoder,
        spectrum: *const [granule_len]f32,
        ratio: *const [long_bands]f32,
        out: *[long_bands]f32,
    ) void {
        for (0..long_bands) |band| {
            const from = self.starts[band];
            const to = self.starts[band + 1];
            var energy: f64 = 0;
            for (from..to) |k| energy += @as(f64, spectrum[k]) * spectrum[k];
            out[band] = @floatCast(@max(energy * @as(f64, ratio[band]), 1e-30));
        }
    }

    /// The distortion loop, with the rate loop inside it.
    fn codeGranule(
        self: *const Encoder,
        spectrum: *const [granule_len]f32,
        thresholds: *const [long_bands]f32,
        budget: usize,
    ) Coded {
        var scalefac: [long_bands]u8 = @splat(0);
        var best: Coded = .{};
        var found = false;

        // Ten passes is enough for the scalefactors to settle on anything
        // this reaches; beyond that the loop is usually chasing a band it
        // cannot fix without starving the rest.
        for (0..10) |_| {
            const compress = chooseCompress(&scalefac) orelse break;
            const part2 = 11 * @as(usize, compress_lengths[compress][0]) +
                10 * @as(usize, compress_lengths[compress][1]);
            if (part2 >= budget) break;

            var attempt = self.rateLoop(spectrum, &scalefac, budget - part2);
            attempt.scalefac = scalefac;
            attempt.scalefac_compress = compress;
            attempt.part2_length = part2;
            attempt.part2_3_length = part2 + attempt.part2_3_length;
            best = attempt;
            found = true;

            // Which bands are still audible above their mask?
            var over: [long_bands]bool = @splat(false);
            var any = false;
            self.noiseOf(spectrum, &attempt, &over, thresholds, &any);
            if (!any) break;

            var raised = false;
            for (0..long_bands) |band| {
                if (!over[band]) continue;
                // Fifteen is the most any scalefactor length can name.
                if (scalefac[band] >= 15) continue;
                scalefac[band] += 1;
                raised = true;
            }
            if (!raised) break;
        }

        if (!found) {
            // Nothing fit, which means the budget will not hold even an empty
            // granule's scalefactors.  An all-zero granule always fits.
            best = .{};
            best.part2_3_length = 0;
        }
        return best;
    }

    /// Find the smallest quantizer step whose granule fits the bits given.
    ///
    /// Bits fall as `global_gain` rises, so this is a binary search over one
    /// number; the answer is the lowest gain that fits, which is the finest
    /// quantization the budget allows.
    fn rateLoop(
        self: *const Encoder,
        spectrum: *const [granule_len]f32,
        scalefac: *const [long_bands]u8,
        budget: usize,
    ) Coded {
        var low: u32 = 0;
        var high: u32 = 255;
        var best: Coded = .{};
        best.global_gain = 255;
        var have = false;

        while (low <= high) {
            const middle = (low + high) / 2;
            var attempt: Coded = .{};
            attempt.global_gain = @intCast(middle);
            // A step too small to code is as good as one too expensive: both
            // mean the search has to look higher, and treating them alike is
            // what keeps the predicate monotonic and the search valid.
            const fits = self.quantize(spectrum, scalefac, @intCast(middle), &attempt);
            self.partition(&attempt);
            const bits = if (fits) self.spectrumBits(&attempt) else std.math.maxInt(usize) / 2;
            if (bits <= budget) {
                attempt.part2_3_length = bits;
                best = attempt;
                have = true;
                if (middle == 0) break;
                high = middle - 1;
            } else {
                low = middle + 1;
            }
        }

        if (!have) {
            // Nothing fit even at the coarsest step, which only a budget of
            // almost nothing can do.  Send silence rather than something that
            // will not fit.
            best = .{};
            best.global_gain = 255;
            self.partition(&best);
            best.part2_3_length = self.spectrumBits(&best);
        }
        return best;
    }

    /// The exponent the decoder will apply to a band, as a quarter power of
    /// two.  This is `requantize` read backwards.
    fn exponentOf(global_gain: u8, scalefac: u8) i32 {
        // `scalefac_scale` is left clear, so each scalefactor step is two
        // quarters of a power of two.
        return @as(i32, global_gain) - 210 - 2 * @as(i32, scalefac);
    }

    /// Quantize, and say whether every value came out small enough to code.
    ///
    /// The largest magnitude any table can name is 8206: fifteen, plus the
    /// thirteen bits of escape the widest tables carry.  A value above that
    /// cannot be sent, and clamping it silently is worse than useless -- it
    /// destroys the line *and* hides from the rate loop the fact that its
    /// step is far too small, which is exactly the signal that loop searches
    /// on.  So it is reported instead.
    fn quantize(
        self: *const Encoder,
        spectrum: *const [granule_len]f32,
        scalefac: *const [long_bands]u8,
        global_gain: u8,
        out: *Coded,
    ) bool {
        for (0..long_bands + 1) |band| {
            const from = self.starts[band];
            const to = if (band < long_bands) self.starts[band + 1] else granule_len;
            const factor = if (band < long_bands) scalefac[band] else 0;
            const gain = exp4(exponentOf(global_gain, factor));
            for (from..@min(to, granule_len)) |k| {
                const size = @abs(spectrum[k]) / gain;
                // The standard's quantizer: the three-quarter power, rounded
                // with an offset that biases towards the smaller magnitude.
                const value = std.math.pow(f32, size, 0.75) + 0.4054;
                if (!(value < max_quantized + 1)) return false;
                const magnitude: i32 = @intFromFloat(value);
                out.quantized[k] = if (spectrum[k] < 0) -magnitude else magnitude;
            }
        }
        return true;
    }

    /// Split the spectrum into the three partitions the format codes it in:
    /// pairs, then quadruples of values no larger than one, then the run of
    /// zeroes at the top that is not coded at all.
    fn partition(self: *const Encoder, out: *Coded) void {
        var end: usize = granule_len;
        while (end > 0 and out.quantized[end - 1] == 0) end -= 1;
        // The quadruples have to start on a multiple of four.
        var quad_end = (end + 3) / 4 * 4;
        if (quad_end > granule_len) quad_end = granule_len;

        var start = quad_end;
        while (start >= 4) {
            var fits = true;
            for (out.quantized[start - 4 .. start]) |value| {
                if (@abs(value) > 1) fits = false;
            }
            if (!fits) break;
            start -= 4;
        }

        out.big_values = @intCast(start / 2);
        out.count1_quads = @intCast((quad_end - start) / 4);
        // Which of the two quadruple tables is cheaper is a whole-granule
        // decision, so it is made once here.
        var cost: [2]usize = @splat(0);
        for (0..2) |select| {
            for (0..out.count1_quads) |q| {
                const at = start + q * 4;
                cost[select] += huffman_encode.count1Cost(select, .{
                    out.quantized[at],     out.quantized[at + 1],
                    out.quantized[at + 2], out.quantized[at + 3],
                });
            }
        }
        out.count1table_select = if (cost[1] < cost[0]) 1 else 0;

        self.chooseRegions(out);
    }

    /// Where the three big-value regions divide, and which table each uses.
    ///
    /// The divisions land on scalefactor band boundaries, and the format
    /// sends them as band counts.  A third of the coded lines each is the
    /// usual choice: the point of dividing at all is that low, middle and
    /// high spectrum have different statistics, and a table that suits one
    /// suits the others badly.
    fn chooseRegions(self: *const Encoder, out: *Coded) void {
        const coded = @as(usize, out.big_values) * 2;
        if (coded == 0) {
            out.region0_count = 0;
            out.region1_count = 0;
            out.table_select = @splat(0);
            return;
        }

        var first: usize = 0;
        var second: usize = 0;
        for (0..long_bands) |band| {
            if (self.starts[band + 1] <= coded / 3) first = band + 1;
            if (self.starts[band + 1] <= coded * 2 / 3) second = band + 1;
        }
        // The counts are one less than the number of bands, and the fields
        // that carry them are four and three bits wide.
        first = std.math.clamp(first, 1, 16);
        second = std.math.clamp(second, first + 1, first + 8);
        out.region0_count = @intCast(first - 1);
        out.region1_count = @intCast(second - first - 1);

        // Clamped the same way the writer and the bit counter clamp it: the
        // band count can name a band past the end of the list, and all three
        // have to agree about where that lands.
        const bounds = [4]usize{
            0,
            @min(self.starts[@min(first, 22)], coded),
            @min(self.starts[@min(second, 22)], coded),
            coded,
        };
        for (0..3) |region| {
            out.table_select[region] = chooseTable(
                out.quantized[bounds[region]..bounds[region + 1]],
            );
        }
    }

    fn spectrumBits(self: *const Encoder, out: *const Coded) usize {
        const coded = @as(usize, out.big_values) * 2;
        var bits: usize = 0;
        if (coded > 0) {
            const first = @as(usize, out.region0_count) + 1;
            const second = first + @as(usize, out.region1_count) + 1;
            const bounds = [4]usize{
                0,
                @min(self.starts[@min(first, 22)], coded),
                @min(self.starts[@min(second, 22)], coded),
                coded,
            };
            for (0..3) |region| {
                const select = out.table_select[region];
                var k = bounds[region];
                while (k + 1 < bounds[region + 1] + 1 and k + 1 <= bounds[region + 1] - 1) : (k += 2) {
                    bits += huffman_encode.bigValueCost(
                        select,
                        @abs(out.quantized[k]),
                        @abs(out.quantized[k + 1]),
                    ) orelse return std.math.maxInt(usize) / 2;
                }
            }
        }
        const start = coded;
        for (0..out.count1_quads) |q| {
            const at = start + q * 4;
            bits += huffman_encode.count1Cost(out.count1table_select, .{
                out.quantized[at],     out.quantized[at + 1],
                out.quantized[at + 2], out.quantized[at + 3],
            });
        }
        return bits;
    }

    /// Which scalefactor bands are still louder than they are allowed to be.
    fn noiseOf(
        self: *const Encoder,
        spectrum: *const [granule_len]f32,
        out: *const Coded,
        over: *[long_bands]bool,
        thresholds: *const [long_bands]f32,
        any: *bool,
    ) void {
        for (0..long_bands) |band| {
            const from = self.starts[band];
            const to = self.starts[band + 1];
            const gain = exp4(exponentOf(out.global_gain, out.scalefac[band]));
            var noise: f64 = 0;
            for (from..to) |k| {
                const magnitude = @abs(out.quantized[k]);
                const back = std.math.pow(f32, @floatFromInt(magnitude), 4.0 / 3.0) * gain;
                const difference = @abs(spectrum[k]) - back;
                noise += @as(f64, difference) * difference;
            }
            over[band] = noise > thresholds[band];
            if (over[band]) any.* = true;
        }
    }

    fn writeSideInfo(
        self: *const Encoder,
        writer: *BitWriter,
        coded: *const [granules][2]Coded,
    ) void {
        const channels: usize = self.channels;
        // No bit reservoir: every granule's data begins where its own frame
        // says it does.
        writer.write(0, 9);
        writer.write(0, if (channels == 1) 5 else 3);
        for (0..channels) |_| writer.write(0, 4); // scfsi: no reuse
        for (0..granules) |gr| {
            for (0..channels) |ch| {
                const g = &coded[gr][ch];
                writer.write(@intCast(g.part2_3_length), 12);
                writer.write(g.big_values, 9);
                writer.write(g.global_gain, 8);
                writer.write(g.scalefac_compress, 4);
                writer.write(0, 1); // window_switching: long blocks only
                for (0..3) |region| writer.write(g.table_select[region], 5);
                writer.write(g.region0_count, 4);
                writer.write(g.region1_count, 3);
                writer.write(0, 1); // preflag
                writer.write(0, 1); // scalefac_scale
                writer.write(g.count1table_select, 1);
            }
        }
    }

    fn writeScalefactors(self: *const Encoder, writer: *BitWriter, g: *const Coded) void {
        _ = self;
        const slen = compress_lengths[g.scalefac_compress];
        for (0..11) |band| writer.write(g.scalefac[band], @intCast(slen[0]));
        for (11..long_bands) |band| writer.write(g.scalefac[band], @intCast(slen[1]));
    }

    fn writeSpectrum(self: *const Encoder, writer: *BitWriter, g: *const Coded) void {
        const coded = @as(usize, g.big_values) * 2;
        if (coded > 0) {
            const first = @as(usize, g.region0_count) + 1;
            const second = first + @as(usize, g.region1_count) + 1;
            const bounds = [4]usize{
                0,
                @min(self.starts[@min(first, 22)], coded),
                @min(self.starts[@min(second, 22)], coded),
                coded,
            };
            for (0..3) |region| {
                var k = bounds[region];
                while (k + 1 < bounds[region + 1]) : (k += 2) {
                    huffman_encode.writeBigValue(
                        writer,
                        g.table_select[region],
                        g.quantized[k],
                        g.quantized[k + 1],
                    );
                }
            }
        }
        for (0..g.count1_quads) |q| {
            const at = coded + q * 4;
            huffman_encode.writeCount1(writer, g.count1table_select, .{
                g.quantized[at],     g.quantized[at + 1],
                g.quantized[at + 2], g.quantized[at + 3],
            });
        }
    }
};

fn writeHeader(writer: *BitWriter, header: Header) void {
    writer.write(0x7ff, 11);
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

/// The cheapest table that can name every pair in a region.
fn chooseTable(values: []const i32) u8 {
    var best: u8 = 0;
    var best_cost: usize = std.math.maxInt(usize);
    for (1..32) |select| {
        if (huffman_encode.big_value[select] == null) continue;
        var cost: usize = 0;
        var usable = true;
        var k: usize = 0;
        while (k + 1 < values.len) : (k += 2) {
            cost += huffman_encode.bigValueCost(
                select,
                @abs(values[k]),
                @abs(values[k + 1]),
            ) orelse {
                usable = false;
                break;
            };
        }
        if (usable and cost < best_cost) {
            best_cost = cost;
            best = @intCast(select);
        }
    }
    return best;
}

/// The `scalefac_compress` whose two lengths hold these scalefactors and cost
/// the fewest bits, or null if none of them can.
fn chooseCompress(scalefac: *const [long_bands]u8) ?u8 {
    var first: u8 = 0;
    var second: u8 = 0;
    for (0..11) |band| first = @max(first, scalefac[band]);
    for (11..long_bands) |band| second = @max(second, scalefac[band]);

    var best: ?u8 = null;
    var best_cost: usize = std.math.maxInt(usize);
    for (compress_lengths, 0..) |slen, index| {
        if (first >= @as(u16, 1) << @intCast(slen[0])) continue;
        if (second >= @as(u16, 1) << @intCast(slen[1])) continue;
        const cost = 11 * @as(usize, slen[0]) + 10 * @as(usize, slen[1]);
        if (cost < best_cost) {
            best_cost = cost;
            best = @intCast(index);
        }
    }
    return best;
}

const testing = std.testing;

test "the header the encoder writes is the one it meant" {
    var encoder = try Encoder.init(.{ .sample_rate = 44100, .channels = 2, .bitrate = 192_000 });
    var input: [frame_samples * 2]f32 = @splat(0);
    var out: [max_frame_bytes]u8 = undefined;
    const size = try encoder.encodeFrame(&input, &out);

    const header = Header.parse(out[0..4].*) orelse return error.NotAHeader;
    try testing.expectEqual(Header.Layer.layer3, header.layer);
    try testing.expectEqual(@as(u32, 44100), header.sampleRate());
    try testing.expectEqual(@as(u32, 192_000), header.bitRate().?);
    try testing.expectEqual(size, header.frameSize().?);
}

test "unsupported settings are refused rather than approximated" {
    try testing.expectError(
        Error.UnsupportedSampleRate,
        Encoder.init(.{ .sample_rate = 22050, .bitrate = 128_000 }),
    );
    try testing.expectError(
        Error.UnsupportedBitRate,
        Encoder.init(.{ .sample_rate = 44100, .bitrate = 193_000 }),
    );
}

test "what is encoded decodes back to something like the input" {
    const mp3 = @import("root.zig");
    const rate = 44100;
    const frames = 20;
    const count = frames * frame_samples;

    var input = try testing.allocator.alloc(f32, count * 2);
    defer testing.allocator.free(input);
    for (0..count) |n| {
        const t = @as(f64, @floatFromInt(n)) / rate;
        const left = 0.45 * @sin(2.0 * std.math.pi * 1000.0 * t) +
            0.25 * @sin(2.0 * std.math.pi * 3200.0 * t);
        const right = 0.40 * @sin(2.0 * std.math.pi * 700.0 * t);
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

    // The filterbank pair delays by 481 samples and the transform by a
    // granule on top of it.
    const delay = analysis.delay + granule_len;
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
    // Nowhere near the ceiling a lossy coder could reach, but far enough
    // above it that a broken scalefactor, region or table would show.
    testing.expect(snr > 40) catch |err| {
        std.debug.print("Layer III round trip {d:.2} dB at 256 kbit/s\n", .{snr});
        return err;
    };
}

test "a granule given plenty of bits comes back close to what went in" {
    // The guard on the fault that cost the most to find.  Every structural
    // check passed while the encoder was producing noise: the frames were
    // well formed, the side information parsed, the Huffman data read back
    // exactly, and the arithmetic was self consistent.  What was wrong was
    // that the granule no longer stood for the spectrum it was made from, and
    // the only way to see that is to rebuild it and look.
    //
    // The quantizer had been clamping values too large for any table to name.
    // That did not make the bit count wrong in a way any assertion caught --
    // it made it a lie, so a granule of saturated lines fit a budget it should
    // never have fit, and the rate loop settled on a step far too small.
    var encoder = try Encoder.init(.{ .sample_rate = 44100, .channels = 1, .bitrate = 256_000 });
    var prng = std.Random.DefaultPrng.init(0x51ee);
    const random = prng.random();

    const Shape = enum { flat, decaying, spikes };
    for (std.enums.values(Shape)) |shape| {
        var spectrum: [granule_len]f32 = undefined;
        switch (shape) {
            .flat => for (&spectrum) |*value| {
                value.* = random.float(f32) - 0.5;
            },
            .decaying => for (&spectrum, 0..) |*value, k| {
                const decay = std.math.pow(f32, 0.995, @floatFromInt(k));
                value.* = (random.float(f32) - 0.5) * decay;
            },
            // A wide dynamic range is what exposed the fault: a few lines far
            // above the rest saturate on their own while everything around
            // them quantizes to nothing.
            .spikes => {
                for (&spectrum) |*value| value.* = (random.float(f32) - 0.5) * 1e-4;
                for ([_]usize{ 0, 3, 40, 200 }) |k| spectrum[k] = 30.0;
            },
        }

        // Thresholds far below the signal, so the distortion loop pushes the
        // scalefactors as hard as it can -- which is the state the fault
        // showed up in.
        var thresholds: [long_bands]f32 = @splat(1e-20);
        const coded = encoder.codeGranule(&spectrum, &thresholds, 4000);

        var signal: f64 = 0;
        var noise: f64 = 0;
        for (0..long_bands + 1) |band| {
            const from = encoder.starts[band];
            const to = if (band < long_bands) encoder.starts[band + 1] else granule_len;
            const factor = if (band < long_bands) coded.scalefac[band] else 0;
            const gain = exp4(Encoder.exponentOf(coded.global_gain, factor));
            for (from..@min(to, granule_len)) |k| {
                const size = std.math.pow(f32, @floatFromInt(@abs(coded.quantized[k])), 4.0 / 3.0);
                const back = if (coded.quantized[k] < 0) -size * gain else size * gain;
                signal += @as(f64, spectrum[k]) * spectrum[k];
                noise += @as(f64, back - spectrum[k]) * (back - spectrum[k]);
            }
        }
        const snr = 10 * std.math.log10(signal / @max(noise, 1e-30));
        testing.expect(snr > 15) catch |err| {
            std.debug.print("{t} spectrum rebuilt at {d:.2} dB from 4000 bits\n", .{ shape, snr });
            return err;
        };
    }
}

test "a step too small to code is refused rather than clamped" {
    var encoder = try Encoder.init(.{ .sample_rate = 44100, .channels = 1, .bitrate = 128_000 });
    var spectrum: [granule_len]f32 = @splat(0);
    spectrum[0] = 1.0;
    var coded: Coded = .{};

    // Gain 210 is the point where the exponent is zero, so the quantized
    // value is about one and everything is codeable.
    try testing.expect(encoder.quantize(
        &spectrum,
        &@as([long_bands]u8, @splat(0)),
        210,
        &coded,
    ));
    // Far below that the value cannot be named by any table, and saying so is
    // the whole point: the caller has to learn that its step is too small.
    try testing.expect(!encoder.quantize(
        &spectrum,
        &@as([long_bands]u8, @splat(0)),
        0,
        &coded,
    ));
}
