// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Layer I and Layer II decoding.
//!
//! Both are far simpler than Layer III and are close enough to each other to
//! share almost everything.  A frame says how many bits each subband was
//! quantized to, then a scalefactor for each, then the quantized samples; the
//! samples go straight into the polyphase filterbank with none of Layer III's
//! Huffman coding, bit reservoir or hybrid transform.
//!
//! The two differ in three ways.  Layer I gives every subband four bits of
//! allocation and one scalefactor, and carries twelve time slots; Layer II
//! chooses the allocation's width from a table that depends on the bit rate
//! and sampling frequency, sends up to three scalefactors per subband with a
//! selector saying which are repeated, carries thirty-six slots in three
//! granules of twelve, and codes the three coarsest quantizations as triples
//! packed into one code word.

const std = @import("std");

const BitReader = @import("bitstream.zig");
const Header = @import("header.zig");
const synthesis = @import("synthesis.zig");

pub const subbands = synthesis.subbands;
/// Time slots in a granule, for both layers.
pub const slots = 12;
/// Samples one granule produces per channel.
pub const granule_len = subbands * slots;
/// Granules per frame: one for Layer I, three for Layer II.
pub const max_granules = 3;
/// The most samples a frame produces per channel.
pub const max_samples = granule_len * max_granules;

/// How a frame's subbands were quantized.
pub const ScaleInfo = struct {
    /// Subbands carrying data at all; the rest of the 32 are silent.
    total_bands: u8 = 0,
    /// Subbands below which the two channels are coded separately.  Above it,
    /// in joint stereo, they share one set of samples but keep their own
    /// scalefactors.
    stereo_bands: u8 = 0,
    /// Quantization class per subband and channel, indexed `band * 2 + ch`.
    /// Zero means the subband carries nothing.
    allocation: [2 * subbands]u8 = @splat(0),
    /// Which of the three scalefactors a subband actually transmitted.
    selection: [2 * subbands]u8 = @splat(0),
    /// Three scalefactors per subband and channel, one per granule, already
    /// folded together with the quantization step so that a decoded value
    /// need only be multiplied by one number.
    scalefactors: [2 * subbands][max_granules]f32 = @splat(@splat(0)),
};

// ------------------------------------------------------------- tables ------

/// One run of subbands whose allocations are the same width and read through
/// the same code table.
pub const Allocation = struct {
    /// Where the run's code table starts in `allocation_codes`.
    offset: u8,
    /// Bits of allocation per subband.
    width: u3,
    bands: u8,
};

/// The bit allocation tables of ISO/IEC 11172-3 Tables B.2a to B.2d and
/// 13818-3's Table B.1, laid end to end.
///
/// An entry is the quantization class the allocation names: zero for a
/// subband carrying nothing, 2 to 16 for a value quantized to that many bits,
/// and 17, 18 or 19 for the three classes that pack a triple of values into
/// one code word.
pub const allocation_codes = [_]u8{
    // 0: sixteen classes, four bits (Layer II, MPEG-1, lowest subbands)
    0,  17, 3,  4, 5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16,
    // 16: sixteen classes, four bits
    0,  17, 18, 3, 19, 4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 16,
    // 32: eight classes, three bits
    0,  17, 18, 3, 19, 4,  5,  16,
    // 40: four classes, two bits
    0,  17, 18, 16,
    // 44: sixteen classes, four bits (MPEG-2, and MPEG-1 at low rates)
    0,  17, 18, 19,
    4,  5,  6,  7, 8,  9,  10, 11, 12, 13, 14, 15,
    // 60: sixteen classes, four bits (MPEG-2, lowest subbands)
    0,  17, 18, 3,
    19, 4,  5,  6, 7,  8,  9,  10, 11, 12, 13, 14,
    // 76: sixteen classes, four bits (Layer I, every subband)
    0,  2,  3,  4,
    5,  6,  7,  8, 9,  10, 11, 12, 13, 14, 15, 16,
};

/// Levels each quantization class divides the range into.  Classes 2 to 16
/// are 2^n − 1 levels in n bits; 17, 18 and 19 are the grouped ones.
pub const class_levels = [18]u32{
    3, 7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383, 32767, 65535,
    3, 5, 9,
};

/// Everything that multiplies a decoded sample, save the power of two that
/// depends on the scalefactor index alone.
///
/// The standard requantizes a class of n bits as C(s'' + D) with
/// C = 2^n/(2^n − 1) and D = 2^-(n-1), which works out as 2(raw − half)/levels
/// once the code is read as a plain integer and centred.  Multiplying that by
/// the scalefactor of ISO/IEC 11172-3 Table B.1, which is 2^(1 − i/3), leaves
/// 2^(2 − r/3)/levels for the remainder r of the index, and a halving per
/// whole step of it that `readScalefactors` applies.
/// Six bits of scalefactor index against eighteen quantization classes is
/// only 1134 numbers, so the whole thing is a table rather than an
/// arithmetic: the index used to be split into a lookup for its remainder
/// and a division by the power of two its whole part named, and that
/// division was a floating point divide per scalefactor -- up to 64 of them
/// per Layer I frame, against 384 samples.
pub const scale_steps = blk: {
    @setEvalBranchQuota(200_000);
    var t: [class_levels.len][64]f32 = undefined;
    for (class_levels, 0..) |levels, class| {
        for (0..64) |index| {
            const exponent = 2.0 - @as(f64, @floatFromInt(index)) / 3.0;
            t[class][index] = @floatCast(std.math.pow(f64, 2, exponent) /
                @as(f64, @floatFromInt(levels)));
        }
    }
    break :blk t;
};

/// The runs of subbands a frame's allocations are read in, and how many
/// subbands carry data at all.
pub fn allocationTable(header: Header) struct { runs: []const Allocation, total: u8 } {
    if (header.layer == .layer1) {
        const runs = &[_]Allocation{.{ .offset = 76, .width = 4, .bands = 32 }};
        return .{ .runs = runs, .total = 32 };
    }
    if (header.version.isLowSamplingFrequency()) {
        const runs = &[_]Allocation{
            .{ .offset = 60, .width = 4, .bands = 4 },
            .{ .offset = 44, .width = 3, .bands = 7 },
            .{ .offset = 44, .width = 2, .bands = 19 },
        };
        return .{ .runs = runs, .total = 30 };
    }

    // MPEG-1 Layer II picks its table by the bit rate per channel, with free
    // format treated as the rate the standard's own table stops at.
    const stated = header.bitRate() orelse 192_000;
    const per_channel = if (header.mode == .mono) stated else stated / 2;
    const kbps = per_channel / 1000;

    if (kbps < 56) {
        const runs = &[_]Allocation{
            .{ .offset = 44, .width = 4, .bands = 2 },
            .{ .offset = 44, .width = 3, .bands = 10 },
        };
        return .{ .runs = runs, .total = if (header.sample_rate_index == 2) 12 else 8 };
    }

    const runs = &[_]Allocation{
        .{ .offset = 0, .width = 4, .bands = 3 },
        .{ .offset = 16, .width = 4, .bands = 8 },
        .{ .offset = 32, .width = 3, .bands = 12 },
        .{ .offset = 40, .width = 2, .bands = 7 },
    };
    const total: u8 = if (kbps >= 96 and header.sample_rate_index != 1) 30 else 27;
    return .{ .runs = runs, .total = total };
}

/// Subbands below which the channels are coded separately.
fn stereoBands(header: Header, total: u8) u8 {
    const bound: u8 = switch (header.mode) {
        .mono => 0,
        // The mode extension names the lowest subband the channels share.
        .joint_stereo => (@as(u8, header.mode_extension) << 2) + 4,
        else => 32,
    };
    return @min(bound, total);
}

// ------------------------------------------------------------- reading -----

/// Read a frame's allocations, scalefactor selectors and scalefactors.
pub fn readScaleInfo(reader: *BitReader, header: Header, info: *ScaleInfo) void {
    info.* = .{};
    const table = allocationTable(header);
    info.total_bands = table.total;
    info.stereo_bands = stereoBands(header, table.total);

    var band: usize = 0;
    for (table.runs) |run| {
        const codes = allocation_codes[run.offset..];
        const end = @min(band + run.bands, table.total);
        while (band < end) : (band += 1) {
            const first = codes[reader.read(run.width)];
            info.allocation[band * 2] = first;
            // Above the stereo bound the two channels share one allocation,
            // and one set of samples, but keep their own scalefactors.
            const second = if (band < info.stereo_bands)
                codes[reader.read(run.width)]
            else
                first;
            info.allocation[band * 2 + 1] = if (info.stereo_bands != 0) second else 0;
        }
        if (band >= table.total) break;
    }

    // Layer I sends one scalefactor per subband; Layer II says which of three
    // it sent, and selector 2 means "the same one throughout".
    for (info.allocation[0 .. table.total * 2], info.selection[0 .. table.total * 2]) |allocation, *selection| {
        selection.* = if (allocation == 0)
            no_scalefactors
        else if (header.layer == .layer1)
            2
        else
            @intCast(reader.read(2));
    }

    readScalefactors(reader, info, table.total);

    // Now that the scalefactors are read, the shared subbands carry no
    // samples of their own for the second channel.
    for (info.stereo_bands..table.total) |shared| info.allocation[shared * 2 + 1] = 0;
}

/// A selector value no frame uses, standing for "this subband sent none".
const no_scalefactors = 6;

/// Which of the three granules carry a scalefactor of their own, by
/// selector, most significant bit first.  Selector 0 sends all three, 2 sends
/// one for all three, and 1 and 3 send two with one of them repeated.
const scalefactor_pattern = [4]u3{ 0b111, 0b101, 0b100, 0b110 };

fn readScalefactors(reader: *BitReader, info: *ScaleInfo, total: u8) void {
    for (0..total * 2) |entry| {
        const allocation = info.allocation[entry];
        const present: u3 = if (allocation == 0)
            0
        else
            scalefactor_pattern[info.selection[entry]];

        var step: f32 = 0;
        var which: u3 = 4;
        var granule: usize = 0;
        while (granule < max_granules) : ({
            granule += 1;
            which >>= 1;
        }) {
            if (present & which != 0) {
                // Six bits, naming one of the 63 scalefactors of Table B.1
                // already divided by the class's level count.
                const index = reader.read(6);
                step = scale_steps[allocation - 2][index];
            }
            info.scalefactors[entry][granule] = step;
        }
    }
}

/// Read one granule: twelve time slots of every subband that carries data.
///
/// Layer I codes one sample at a time; Layer II packs its three coarsest
/// quantizations as a triple of values in a single code word, and reads the
/// rest three slots at a time.
pub fn readGranule(
    reader: *BitReader,
    info: *const ScaleInfo,
    header: Header,
    granule: usize,
    out: *[2][granule_len]f32,
) void {
    // Layer I reads one time slot at a time and Layer II three, and it is
    // worth compiling the two separately: the count is the trip count of the
    // innermost loop, and knowing it unrolls that loop and settles how many
    // slots the outer one makes.
    if (header.layer == .layer1) {
        readGranuleGrouped(1, reader, info, header, granule, out);
    } else {
        readGranuleGrouped(3, reader, info, header, granule, out);
    }
}

fn readGranuleGrouped(
    comptime group: usize,
    reader: *BitReader,
    info: *const ScaleInfo,
    header: Header,
    granule: usize,
    out: *[2][granule_len]f32,
) void {
    const channels = header.channels();

    // The subbands that carry anything, gathered once and then walked for
    // every time slot.  The alternative is to test all 64 subband-and-channel
    // pairs on each of the twelve slots, which for Layer I is 768 tests to
    // find the dozen or so subbands a frame at a middling bit rate actually
    // codes.  Gathering them also lifts the scalefactor loads out of the slot
    // loop, since they are fixed for the granule.
    var list: [2 * subbands]Active = undefined;
    var count: usize = 0;
    for (0..info.total_bands) |band| {
        // Above the stereo bound the two channels share one set of samples
        // but keep their own scalefactors, so the value read for the first is
        // scaled a second time and stored for the other as well.
        // `readScaleInfo` leaves the second channel's allocation zero across
        // that region, so it is still gathered, and read, once.
        const shared = channels == 2 and band >= info.stereo_bands;
        for (0..channels) |ch| {
            const allocation = info.allocation[band * 2 + ch];
            if (allocation == 0) continue;
            list[count] = .{
                .at = @intCast(band * slots),
                .step = info.scalefactors[band * 2 + ch][granule],
                .other = if (shared) info.scalefactors[band * 2 + 1][granule] else 0,
                .allocation = allocation,
                .ch = @intCast(ch),
                .shared = shared,
            };
            count += 1;
        }
    }

    var slot: usize = 0;
    while (slot < slots) : (slot += group) {
        for (list[0..count]) |band| {
            const at = band.at + slot;
            if (band.allocation < 17) {
                // The value is read as an unsigned integer and centred: a
                // class of n bits spans 2^n - 1 levels.
                const width: u6 = @intCast(band.allocation);
                const half: i32 = (@as(i32, 1) << @intCast(band.allocation - 1)) - 1;
                for (0..group) |k| {
                    const raw: i32 = @intCast(reader.read(width));
                    const value: f32 = @floatFromInt(raw - half);
                    out[band.ch][at + k] = value * band.step;
                    if (band.shared) out[1][at + k] = value * band.other;
                }
            } else {
                // Three values of 3, 5 or 9 levels packed into one code word
                // of 5, 7 or 10 bits, most significant value last.
                const levels: u32 = (@as(u32, 2) << @intCast(band.allocation - 17)) + 1;
                const width: u6 = @intCast(levels + 2 - (levels >> 3));
                const half: i32 = @intCast(levels / 2);
                var code = reader.read(width);
                for (0..group) |k| {
                    const raw: i32 = @intCast(code % levels);
                    const value: f32 = @floatFromInt(raw - half);
                    out[band.ch][at + k] = value * band.step;
                    if (band.shared) out[1][at + k] = value * band.other;
                    code /= levels;
                }
            }
        }
    }
}

/// One subband of one channel that a granule actually codes, with everything
/// the slot loop needs already looked up.
const Active = struct {
    /// Where the subband's samples start in the granule.
    at: u32,
    /// The multiplier that turns a centred code into a sample.
    step: f32,
    /// The same for the other channel, where the two share these samples.
    other: f32,
    allocation: u8,
    ch: u8,
    shared: bool,
};

/// Whether a granule writes this subband of this channel.  Above the stereo
/// bound the second channel is written from the first channel's samples
/// rather than from an allocation of its own, which `readScaleInfo` leaves
/// at zero.
fn writes(info: *const ScaleInfo, ch: usize, band: usize) bool {
    if (info.allocation[band * 2 + ch] != 0) return true;
    return ch == 1 and band >= info.stereo_bands and info.allocation[band * 2] != 0;
}

pub fn clearSilent(
    info: *const ScaleInfo,
    header: Header,
    out: *[2][granule_len]f32,
) void {
    const total = @as(usize, info.total_bands);
    for (0..header.channels()) |ch| {
        // Two shapes of clear, because they compile to quite different
        // things.  A single subband is a constant 48 bytes, which becomes a
        // few vector stores in place; the run above the last coded subband
        // is a length known only at runtime, and is a call.  Merging the
        // isolated ones into runs as well measured 5% slower, because it
        // turned every one of them into that call.
        var top: usize = 0;
        for (0..total) |band| if (writes(info, ch, band)) {
            top = band + 1;
        };
        for (0..top) |band| if (!writes(info, ch, band)) {
            @memset(out[ch][band * slots ..][0..slots], 0);
        };
        // Everything above the highest subband the frame writes, in one go.
        // For a real encoder, whose lowpass makes that region contiguous,
        // this is the whole of the clearing.
        @memset(out[ch][top * slots ..], 0);
    }
}

// -------------------------------------------------------------- decode -----

/// Everything a Layer I or II decoder must remember between frames: only the
/// filterbank's history, since neither layer has a bit reservoir.
pub const State = struct {
    filterbank: [2]synthesis.State = @splat(.{}),

    pub fn reset(self: *State) void {
        self.* = .{};
    }
};

/// Decode one frame's body -- everything after the header and its optional
/// CRC -- into `out`, interleaved.  Returns samples per channel.
pub fn decodeFrame(
    state: *State,
    header: Header,
    body: []const u8,
    out: []f32,
) usize {
    const channels = header.channels();
    const granules: usize = if (header.layer == .layer1) 1 else 3;

    var reader = BitReader.init(body);
    var info: ScaleInfo = undefined;
    readScaleInfo(&reader, header, &info);

    var samples: [2][granule_len]f32 = undefined;
    clearSilent(&info, header, &samples);
    for (0..granules) |granule| {
        readGranule(&reader, &info, header, granule, &samples);
        for (0..channels) |ch| {
            const at = granule * granule_len * @as(usize, channels) + ch;
            // Above `total_bands` a frame carries nothing at all, and at
            // low bit rates that is most of the spectrum: 64 kbit/s stereo
            // gets eight subbands of the thirty-two.
            synthesis.synthesize(
                &state.filterbank[ch],
                &samples[ch],
                out[at..],
                channels,
                info.total_bands,
            );
        }
    }
    return granules * granule_len;
}

// --------------------------------------------------------------- tests -----

test "the requantization matches the standard's own arithmetic" {
    // `scale_steps` folds four things into one multiplier: the scalefactor of
    // ISO/IEC 11172-3 Table B.1, the C and D of Table B.4, and reading the
    // code as a plain unsigned integer instead of the standard's sign-magnitude
    // fraction.  This works all four back out the long way and checks that the
    // product is the same number.
    //
    // C is 2^k / levels and D is 2^(1-k) for the ungrouped classes and one
    // half for the grouped ones, where k is the width the class would have if
    // it were not grouped: 2, 3 and 4 bits for 3, 5 and 9 levels.
    const widths = [class_levels.len]u6{
        2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
        2, 3, 4,
    };

    for (class_levels, widths, 0..) |levels, width, class| {
        const c = std.math.pow(f64, 2, @floatFromInt(width)) /
            @as(f64, @floatFromInt(levels));
        const d: f64 = if (class < 15)
            std.math.pow(f64, 2, 1.0 - @as(f64, @floatFromInt(width)))
        else
            0.5;

        for (0..63) |index| {
            // Table B.1 is 2^(1 - i/3), and the decoder splits it into a
            // table lookup for the remainder and a shift for the rest.
            const scalefactor = std.math.pow(f64, 2, 1.0 - @as(f64, @floatFromInt(index)) / 3.0);
            const step = scale_steps[class][index];

            // The code's centre.  For the ungrouped classes this is the
            // 2^(k-1) - 1 that a k-bit two's complement code sits around; for
            // the grouped ones, whose level count is not 2^k - 1, it is the
            // middle of the levels actually used.
            const half: i64 = @intCast(levels / 2);
            for (0..levels) |raw| {
                // The standard inverts the code's most significant bit and
                // reads what is left as a two's complement fraction.
                const inverted = raw ^ (@as(usize, 1) << (width - 1));
                const signed: i64 = if (inverted < @as(usize, 1) << (width - 1))
                    @intCast(inverted)
                else
                    @as(i64, @intCast(inverted)) - (@as(i64, 1) << width);
                const s2 = @as(f64, @floatFromInt(signed)) /
                    @as(f64, @floatFromInt(@as(u64, 1) << (width - 1)));
                const want = scalefactor * c * (s2 + d);

                const got = step * @as(f64, @floatFromInt(@as(i64, @intCast(raw)) - half));
                // The table is `f32`, which is what a scalefactor is once
                // it reaches a sample, so the agreement checked here is to
                // that precision and not to the `f64` the expectation is
                // worked out in.
                try std.testing.expectApproxEqRel(want, got, 1e-6);
            }
        }
    }
}

test "a hand built Layer I frame decodes to the values put into it" {
    // Two subbands of a mono frame, quantized to four and six bits, with the
    // codes chosen so that the centre, the bottom and the top of each class
    // all appear.
    const header: Header = .{
        .version = .mpeg1,
        .layer = .layer1,
        .crc_protected = false,
        .bitrate_index = 14,
        .sample_rate_index = 0,
        .padding = false,
        .private = false,
        .mode = .mono,
        .mode_extension = 0,
        .copyright = false,
        .original = false,
        .emphasis = .none,
    };

    var body: [452]u8 = @splat(0);
    var at: usize = 0;
    const put = struct {
        fn f(buffer: []u8, cursor: *usize, value: u32, width: u6) void {
            var left = width;
            while (left > 0) {
                left -= 1;
                const bit: u8 = @intCast((value >> @intCast(left)) & 1);
                buffer[cursor.* / 8] |= bit << @intCast(7 - cursor.* % 8);
                cursor.* += 1;
            }
        }
    }.f;

    // Allocations: four bits then six, and nothing in the other 30 subbands.
    put(&body, &at, 3, 4); // code 3 names four bits
    put(&body, &at, 5, 4); // code 5 names six bits
    for (2..subbands) |_| put(&body, &at, 0, 4);
    // Scalefactor index 3 is exactly 1.0 in Table B.1, so the expected values
    // are the requantized codes themselves.
    put(&body, &at, 3, 6);
    put(&body, &at, 3, 6);

    const first = [slots]u32{ 0, 7, 8, 15, 1, 14, 8, 8, 0, 15, 3, 12 };
    const second = [slots]u32{ 0, 31, 32, 63, 1, 62, 32, 32, 0, 63, 5, 58 };
    for (first, second) |a, b| {
        put(&body, &at, a, 4);
        put(&body, &at, b, 6);
    }

    var reader = BitReader.init(&body);
    var info: ScaleInfo = undefined;
    readScaleInfo(&reader, header, &info);
    try std.testing.expectEqual(@as(u8, 4), info.allocation[0]);
    try std.testing.expectEqual(@as(u8, 6), info.allocation[2]);
    try std.testing.expectEqual(@as(u8, 0), info.allocation[4]);

    var samples: [2][granule_len]f32 = undefined;
    clearSilent(&info, header, &samples);
    readGranule(&reader, &info, header, 0, &samples);

    for (first, second, 0..) |a, b, slot| {
        // C(s'' + D) reduces to 2(code - half)/levels at a scalefactor of one.
        const want_a = 2.0 * (@as(f32, @floatFromInt(a)) - 7.0) / 15.0;
        const want_b = 2.0 * (@as(f32, @floatFromInt(b)) - 31.0) / 63.0;
        try std.testing.expectApproxEqAbs(want_a, samples[0][slot], 1e-6);
        try std.testing.expectApproxEqAbs(want_b, samples[0][slots + slot], 1e-6);
    }
    // Everything above the two coded subbands is silent.
    for (samples[0][2 * slots ..]) |sample| try std.testing.expectEqual(@as(f32, 0), sample);
}
