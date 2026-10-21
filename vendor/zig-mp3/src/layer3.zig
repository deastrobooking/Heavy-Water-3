// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Decoding one Layer III granule: scalefactors, the Huffman coded spectrum,
//! requantization, joint stereo, reordering, and then out through the hybrid
//! and polyphase filterbanks.
//!
//! Every stage walks the same list of scalefactor band widths, so long, short
//! and mixed blocks differ only in which list they walk.  Band `i` of the list
//! and scalefactor `i` are the same band, and in the short lists each band
//! appears three times, once per window.

const std = @import("std");

const BitReader = @import("bitstream.zig");
const Header = @import("header.zig");
const huffman = @import("huffman.zig");
const imdct = @import("imdct.zig");
const side_info = @import("side_info.zig");
const synthesis = @import("synthesis.zig");
const sfb = @import("tables/scalefactor_bands.zig");

const BlockType = side_info.BlockType;
const Granule = side_info.Granule;
const SideInfo = side_info.SideInfo;

pub const granule_len = 576;
/// The longest band list is a short block's: 13 bands times three windows.
pub const max_bands = 39;

/// How a granule's spectrum is divided into scalefactor bands.
const Layout = struct {
    /// Band widths in spectral lines, in bitstream order.
    widths: []const u8,
    /// Leading entries that are long bands.  Equal to `widths.len` for a
    /// granule that is not short, and zero for a plain short block.
    long_bands: usize,
    /// Subbands a mixed block transforms as long blocks; zero otherwise.
    mixed_long_subbands: usize,

    /// First spectral line of the short region.
    fn shortStart(self: Layout) usize {
        return self.mixed_long_subbands * imdct.subband_len;
    }
};

fn layoutFor(header: Header, granule: *const Granule) Layout {
    const row = &sfb.bands[sfb.index(header.version.tableIndex(), header.sample_rate_index)];
    if (!granule.isShort()) {
        return .{
            .widths = row.long_widths[0..],
            .long_bands = row.long_widths.len,
            .mixed_long_subbands = 0,
        };
    }
    if (!granule.mixed_block) {
        return .{ .widths = row.short_widths[0..], .long_bands = 0, .mixed_long_subbands = 0 };
    }
    // A mixed block transforms its lowest two subbands as long blocks -- four
    // at 8 kHz, where the long region of the band table is longer to match.
    const eight_khz = header.version == .mpeg2_5 and header.sample_rate_index == 2;
    return .{
        .widths = row.mixed_widths[0 .. @as(usize, row.mixed_long) + row.mixed_short],
        .long_bands = row.mixed_long,
        .mixed_long_subbands = if (eight_khz) 4 else 2,
    };
}

// ---------------------------------------------------------- scalefactors ---

const Scalefactors = struct {
    /// One transmitted value per band, as sent.
    values: [max_bands + 1]u8 = @splat(0),
    /// The same values read as intensity stereo positions.  On the low
    /// sampling frequency layout a band whose scalefactor was all ones is not
    /// intensity coded, and is marked here with a value no position reaches.
    intensity: [max_bands + 1]u8 = @splat(0),
};

/// ISO/IEC 11172-3 Table 9: slen1 and slen2 by `scalefac_compress`.
const mpeg1_lengths = [16][2]u8{
    .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ 0, 3 }, .{ 3, 0 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 3 },
    .{ 2, 1 }, .{ 2, 2 }, .{ 2, 3 }, .{ 3, 1 }, .{ 3, 2 }, .{ 3, 3 }, .{ 4, 2 }, .{ 4, 3 },
};

/// Bands in each of the four MPEG-1 scalefactor partitions.  The first two
/// partitions use slen1 and the last two slen2; for a long block they are also
/// the four groups the scalefactor selection information refers to.
fn mpeg1Partitions(granule: *const Granule) [4]u8 {
    if (!granule.isShort()) return .{ 6, 5, 5, 5 };
    return if (granule.mixed_block) .{ 8, 9, 6, 12 } else .{ 9, 9, 6, 12 };
}

/// ISO/IEC 13818-3: bands in each partition, by partition set and by block
/// shape (long, short, mixed).  Sets 0 to 2 are for an ordinary channel and
/// sets 3 to 5 for the intensity coded right channel.
const lsf_partitions = [6][3][4]u8{
    .{ .{ 6, 5, 5, 5 }, .{ 9, 9, 9, 9 }, .{ 6, 9, 9, 9 } },
    .{ .{ 6, 5, 7, 3 }, .{ 9, 9, 12, 6 }, .{ 6, 9, 12, 6 } },
    .{ .{ 11, 10, 0, 0 }, .{ 18, 18, 0, 0 }, .{ 15, 18, 0, 0 } },
    .{ .{ 7, 7, 7, 0 }, .{ 12, 12, 12, 0 }, .{ 6, 15, 12, 0 } },
    .{ .{ 6, 6, 6, 3 }, .{ 12, 9, 9, 6 }, .{ 6, 12, 9, 6 } },
    .{ .{ 8, 8, 5, 0 }, .{ 15, 12, 9, 0 }, .{ 6, 18, 9, 0 } },
};

const LsfSizes = struct { lengths: [4]u8, set: usize };

/// Unpack the low sampling frequency `scalefac_compress`, which encodes both
/// the four scalefactor lengths and which partition set they apply to.
fn lsfSizes(scalefac_compress: u16, intensity: bool) LsfSizes {
    const c: u32 = scalefac_compress;
    if (!intensity) {
        if (c < 400) {
            const q = c >> 4;
            return .{ .lengths = .{ narrow(q / 5), narrow(q % 5), narrow((c % 16) >> 2), narrow(c % 4) }, .set = 0 };
        }
        if (c < 500) {
            const v = c - 400;
            const q = v >> 2;
            return .{ .lengths = .{ narrow(q / 5), narrow(q % 5), narrow(v % 4), 0 }, .set = 1 };
        }
        const v = c - 500;
        return .{ .lengths = .{ narrow(v / 3), narrow(v % 3), 0, 0 }, .set = 2 };
    }
    const c2 = c >> 1;
    if (c2 < 180) {
        return .{ .lengths = .{ narrow(c2 / 36), narrow((c2 % 36) / 6), narrow(c2 % 6), 0 }, .set = 3 };
    }
    if (c2 < 244) {
        const v = c2 - 180;
        return .{ .lengths = .{ narrow((v % 64) >> 4), narrow((v % 16) >> 2), narrow(v % 4), 0 }, .set = 4 };
    }
    const v = c2 - 244;
    return .{ .lengths = .{ narrow(v / 3), narrow(v % 3), 0, 0 }, .set = 5 };
}

/// The unpacked lengths are all small; this just keeps the expressions above
/// readable.
fn narrow(v: u32) u8 {
    return @intCast(v);
}

fn readScalefactors(
    reader: *BitReader,
    header: Header,
    info: *const SideInfo,
    gr: usize,
    ch: usize,
    granule: *const Granule,
    previous: *const Scalefactors,
    previous_short: bool,
    out: *Scalefactors,
) void {
    out.* = .{};

    if (!header.version.isLowSamplingFrequency()) {
        const slen = mpeg1_lengths[granule.scalefac_compress & 0xf];
        const lengths = [4]u8{ slen[0], slen[0], slen[1], slen[1] };
        const counts = mpeg1Partitions(granule);
        // Reuse is only defined between two long granules of one channel.
        const may_reuse = gr == 1 and !granule.isShort() and !previous_short;

        var band: usize = 0;
        for (0..4) |part| {
            const reuse = may_reuse and info.scfsi[ch][part];
            for (0..counts[part]) |_| {
                out.values[band] = if (reuse)
                    previous.values[band]
                else
                    @intCast(reader.read(@intCast(lengths[part])));
                out.intensity[band] = out.values[band];
                band += 1;
            }
        }
        return;
    }

    const shape: usize = if (!granule.isShort()) 0 else if (granule.mixed_block) 2 else 1;
    const intensity_channel = header.jointStereo().intensity_stereo and ch == 1;
    const sizes = lsfSizes(granule.scalefac_compress, intensity_channel);
    const counts = lsf_partitions[sizes.set][shape];

    var band: usize = 0;
    for (0..4) |part| {
        const bits = sizes.lengths[part];
        const all_ones: u32 = (@as(u32, 1) << @intCast(bits)) - 1;
        for (0..counts[part]) |_| {
            const value = if (bits == 0) 0 else reader.read(@intCast(bits));
            out.values[band] = @intCast(value);
            // An all-ones scalefactor marks a band the right channel did not
            // intensity code; 255 is past every real position.
            out.intensity[band] = if (bits != 0 and value == all_ones) 255 else @intCast(value);
            band += 1;
        }
    }
}

// -------------------------------------------------------------- spectrum ---

/// Every count1 quadruple, by its four magnitude bits and the sign bits that
/// followed them.
///
/// A quadruple is four values of -1, 0 or 1, and only the ones that are not
/// zero carry a sign, so working them out means four dependent tests.  There
/// are only 256 combinations of the two, so they are all worked out once here
/// instead.
const count1_values = blk: {
    @setEvalBranchQuota(20_000);
    var t: [256][4]i8 = undefined;
    for (0..16) |quad| {
        for (0..16) |signs| {
            var values: [4]i8 = undefined;
            var remaining: usize = @popCount(@as(u4, @intCast(quad)));
            for (0..4) |k| {
                if ((quad >> @intCast(3 - k)) & 1 == 0) {
                    values[k] = 0;
                    continue;
                }
                remaining -= 1;
                values[k] = if ((signs >> @intCast(remaining)) & 1 != 0) -1 else 1;
            }
            t[quad * 16 + signs] = values;
        }
    }
    break :blk t;
};

/// ISO/IEC 11172-3 Table B.6: extra high frequency attenuation when
/// `preflag` is set.
const pretab = [22]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 3, 2, 0 };

/// Read one Huffman coded value and its sign out of a bit cache the caller
/// has already refilled.  For the tables that have no escape, which is most
/// of them.
inline fn plainValue(bits: *BitReader.Cache, raw: u8) i32 {
    if (raw == 0) return 0;
    const signed: i32 = raw;
    return if (bits.read(1) == 1) -signed else signed;
}

/// The same where the table has an escape: a value of 15 is followed by
/// `linbits` more bits of magnitude, and is then never zero, so its sign
/// always follows and comes out of the same read.
inline fn escapedValue(bits: *BitReader.Cache, raw: u8, linbits: u8) i32 {
    if (raw == 15) {
        const extra = bits.read(@intCast(linbits + 1));
        const escaped: i32 = @intCast(15 + (extra >> 1));
        return if (extra & 1 != 0) -escaped else escaped;
    }
    return plainValue(bits, raw);
}

/// Decode the granule's quantized spectrum.  `end_bit` is where
/// `part2_3_length` says the granule stops; nothing beyond it is trusted.
///
/// Returns how many lines were actually coded.  Everything above that is
/// zero, and saying so lets requantization skip it -- which is most of the
/// spectrum at the bit rates anyone uses.
fn readSpectrum(
    reader: *BitReader,
    granule: *const Granule,
    layout: Layout,
    end_bit: usize,
    out: *[granule_len]i32,
) usize {
    // Region boundaries are counted in scalefactor bands, so turn them into
    // spectral lines.  A window-switched granule has no third region: its
    // `region1_count` is `region1_to_end`, which clamps to the last band.
    var offsets: [max_bands + 1]usize = undefined;
    offsets[0] = 0;
    for (layout.widths, 0..) |width, band| {
        offsets[band + 1] = @min(granule_len, offsets[band] + width);
    }
    const bands = layout.widths.len;
    const first = @as(usize, granule.region0_count) + 1;
    const second = first + @as(usize, granule.region1_count) + 1;
    const region_end = [3]usize{
        offsets[@min(first, bands)],
        offsets[@min(second, bands)],
        granule_len,
    };

    var index: usize = 0;
    const pairs = @min(@as(usize, granule.big_values) * 2, granule_len);

    // The spectrum is read through a cache held in registers rather than
    // through the reader, which would load eight bytes for every one of the
    // three reads a pair takes.  The reader is put back in step at the end.
    var bits = BitReader.Cache.init(reader.bytes, reader.pos);

    // A region at a time rather than a pair at a time: which region a pair
    // falls in, and which table that means, changes twice in a granule, and
    // working it out per pair costs more than the decoding does.
    var region: usize = 0;
    outer: while (region < 3) : (region += 1) {
        const limit = @min(region_end[region], pairs);
        if (index + 1 >= limit) continue;

        // Table 0 means the region holds nothing but zeroes and costs no
        // bits.  They still have to be written: the spectrum is no longer
        // cleared beforehand, only from the last coded line upwards.
        const selected = huffman.big_value[granule.table_select[region]] orelse {
            @memset(out[index..limit], 0);
            index = limit & ~@as(usize, 1);
            continue;
        };
        const table = selected.table;
        const linbits = selected.linbits;

        // Whether the table has an escape is fixed for the whole region, so
        // the test belongs out here rather than against every value.  Three
        // regions a granule against sixteen million values a minute.
        if (linbits == 0) {
            while (index + 1 < limit) : (index += 2) {
                if (bits.position() >= end_bit) break :outer;
                // One refill covers the whole pair: 19 bits of code word at
                // most and a sign for each value.
                bits.refill();
                const code = table.decodeWord(bits.peek32());
                bits.skip(@intCast(code.len));
                out[index] = plainValue(&bits, code.x);
                out[index + 1] = plainValue(&bits, code.y);
            }
        } else {
            while (index + 1 < limit) : (index += 2) {
                if (bits.position() >= end_bit) break :outer;
                // 19 bits of code word and 14 for each escaped value, against
                // the 57 a refill guarantees.
                bits.refill();
                const code = table.decodeWord(bits.peek32());
                bits.skip(@intCast(code.len));
                out[index] = escapedValue(&bits, code.x, linbits);
                out[index + 1] = escapedValue(&bits, code.y, linbits);
            }
        }
    }

    // The count1 partition runs until the granule's bits are used up.  A
    // quadruple that would overrun is discarded whole, as the encoder never
    // meant to send it.
    const table = huffman.count1[granule.count1table_select];
    while (index + 4 <= granule_len and bits.position() < end_bit) {
        // Six bits of code word at most and four signs: one refill over.
        bits.refill();
        const code = table.decodeWord(bits.peek32());
        bits.skip(@intCast(code.len));
        // The signs of the values that are not zero arrive as one run of
        // bits, and the two together name the quadruple outright.
        const quad = code.y;
        const signs = bits.read(@popCount(quad));
        const values = count1_values[@as(usize, quad) * 16 + signs];
        for (0..4) |k| out[index + k] = values[k];
        if (bits.position() > end_bit) {
            @memset(out[index .. index + 4], 0);
            break;
        }
        index += 4;
    }
    // Put the reader where the cache got to, so that anything looking at it
    // afterwards sees the truth.
    reader.seek(bits.position());
    @memset(out[index..], 0);
    return index;
}

/// The smallest quarter-step exponent the table covers.  Requantization can
/// reach about -400 with the largest scalefactors and the smallest global
/// gain; anything below the table underflows to nothing anyway.
const min_exponent = -512;

/// 2^(e/4), the whole of requantization's gain term.
///
/// The exponent is always an integer number of quarter steps, so this is
/// exact and a table beats calling a general power function per band.
const gains = blk: {
    @setEvalBranchQuota(200_000);
    var t: [640]f32 = undefined;
    for (0..640) |n| {
        const e = @as(f64, @floatFromInt(@as(i32, @intCast(n)) + min_exponent));
        t[n] = @floatCast(std.math.pow(f64, 2, e * 0.25));
    }
    break :blk t;
};

fn gainFor(exponent: i32) f32 {
    const at = exponent - min_exponent;
    if (at < 0) return 0;
    if (at >= gains.len) return gains[gains.len - 1];
    return gains[@intCast(at)];
}

/// v raised to 4/3, keeping v's sign, for the values that fit in a Huffman
/// code word without an escape.
///
/// Almost every spectral line is one of these, and having the sign already
/// in the table saves taking the absolute value and putting the sign back
/// afterwards on each of the 576 lines of every granule.
const small_pow43 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [31]f32 = undefined;
    for (0..31) |n| {
        const v: f64 = @floatFromInt(@as(i32, @intCast(n)) - 15);
        const size = std.math.pow(f64, @abs(v), 4.0 / 3.0);
        t[n] = @floatCast(if (v < 0) -size else size);
    }
    break :blk t;
};

const pow43 = blk: {
    @setEvalBranchQuota(200_000);
    var t: [1024]f32 = undefined;
    for (0..1024) |n| t[n] = @floatCast(std.math.pow(f64, @floatFromInt(n), 4.0 / 3.0));
    break :blk t;
};

fn magnitude(value: u32) f32 {
    if (value >= pow43.len) {
        // Only an escape coded value reaches this, and only a large one.
        @branchHint(.cold);
        return @floatCast(std.math.pow(f64, @floatFromInt(value), 4.0 / 3.0));
    }
    return pow43[value];
}

/// Turn quantized values into spectral lines, applying the granule's gain and
/// its scalefactors band by band.
fn requantize(
    granule: *const Granule,
    layout: Layout,
    scalefactors: *const Scalefactors,
    quantized: *const [granule_len]i32,
    coded: usize,
    out: *[granule_len]f32,
) void {
    const scale_step: i32 = 2 * (1 + @as(i32, @intFromBool(granule.scalefac_scale)));
    var line: usize = 0;

    for (layout.widths, 0..) |width, band| {
        // Bands above the last coded line are zero whatever their gain is.
        if (line >= coded) break;
        const count = @min(@as(usize, width), granule_len - line);
        const short = band >= layout.long_bands;

        // The gain is a power of two in quarter steps, so it stays exact.
        var exponent: i32 = @as(i32, granule.global_gain) - 210;
        if (short) {
            const window = (band - layout.long_bands) % 3;
            exponent -= 8 * @as(i32, granule.subblock_gain[window]);
        }
        var scalefactor: i32 = scalefactors.values[band];
        if (!short and granule.preflag and band < pretab.len) {
            scalefactor += pretab[band];
        }
        exponent -= scale_step * scalefactor;
        const gain = gainFor(exponent);

        for (line..line + count) |k| {
            const value = quantized[k];
            // One unsigned comparison covers both ends of the small table:
            // anything outside -15...15 wraps to something far above 30.
            const biased: u32 = @bitCast(value +% 15);
            if (biased <= 30) {
                out[k] = small_pow43[biased] * gain;
            } else {
                // Only an escape coded value gets here.  The sign moves
                // across as a bit rather than a branch, since spectral values
                // change sign about as often as not and in no pattern.
                @branchHint(.unlikely);
                const size = magnitude(@abs(value));
                const sign = @as(u32, @bitCast(value)) & 0x8000_0000;
                out[k] = @as(f32, @bitCast(@as(u32, @bitCast(size)) | sign)) * gain;
            }
        }
        line += count;
    }
    @memset(out[line..], 0);
}

// ---------------------------------------------------------------- stereo ---

/// ISO/IEC 11172-3 intensity stereo weights: is_ratio = tan(pos * pi / 12),
/// then the pair (is_ratio, 1) normalized to sum to one.  Position 6 is the
/// limit where the band moves entirely to the left channel.
const pan = blk: {
    var t: [7][2]f32 = undefined;
    for (0..7) |pos| {
        if (pos == 6) {
            t[pos] = .{ 1, 0 };
        } else {
            const ratio = @tan(@as(f64, @floatFromInt(pos)) * std.math.pi / 12.0);
            t[pos] = .{ @floatCast(ratio / (1 + ratio)), @floatCast(1 / (1 + ratio)) };
        }
    }
    break :blk t;
};

fn midSide(spectra: *[2][granule_len]f32, start: usize, count: usize) void {
    const norm = std.math.sqrt1_2;
    for (start..start + count) |k| {
        const mid = spectra[0][k];
        const side = spectra[1][k];
        spectra[0][k] = (mid + side) * norm;
        spectra[1][k] = (mid - side) * norm;
    }
}

fn processStereo(
    header: Header,
    layout: Layout,
    right: *const Granule,
    intensity: *[max_bands + 1]u8,
    spectra: *[2][granule_len]f32,
) void {
    const joint = header.jointStereo();
    if (!joint.intensity_stereo) {
        if (joint.ms_stereo) midSide(spectra, 0, granule_len);
        return;
    }

    // Intensity coding takes over above the highest band the right channel
    // actually sent data in.  A short block has three interleaved windows and
    // so three independent tops.
    var top = [3]i32{ -1, -1, -1 };
    {
        var line: usize = 0;
        for (layout.widths, 0..) |width, band| {
            if (line >= granule_len) break;
            const count = @min(@as(usize, width), granule_len - line);
            for (spectra[1][line .. line + count]) |value| {
                if (value != 0) {
                    top[band % 3] = @intCast(band);
                    break;
                }
            }
            line += count;
        }
    }
    if (layout.long_bands > 0) {
        const highest = @max(@max(top[0], top[1]), top[2]);
        top = .{ highest, highest, highest };
    }

    // The topmost band of each window carries no scalefactor of its own, so
    // it either inherits the position below it or falls back to the middle.
    const windows: usize = if (layout.long_bands == layout.widths.len) 1 else 3;
    const default_position: u8 = if (header.version == .mpeg1) 3 else 0;
    for (0..windows) |w| {
        const last = layout.widths.len - windows + w;
        const below = last - windows;
        intensity[last] = if (top[w] >= @as(i32, @intCast(below)))
            default_position
        else
            intensity[below];
    }

    const limit: u8 = if (header.version == .mpeg1) 7 else 64;
    const step: u3 = @intCast(right.scalefac_compress & 1);
    var line: usize = 0;
    for (layout.widths, 0..) |width, band| {
        if (line >= granule_len) break;
        const count = @min(@as(usize, width), granule_len - line);
        const position = intensity[band];

        if (@as(i32, @intCast(band)) > top[band % 3] and position < limit) {
            var left: f32 = undefined;
            var right_gain: f32 = undefined;
            if (header.version == .mpeg1) {
                left = pan[position][0];
                right_gain = pan[position][1];
            } else {
                // The low sampling frequency versions halve the weight every
                // one or two positions instead of panning by an angle.
                const shifted = (@as(u32, position) + 1) / 2 << step;
                const weight = std.math.exp2(-@as(f32, @floatFromInt(shifted)) * 0.25);
                if (position & 1 != 0) {
                    left = weight;
                    right_gain = 1;
                } else {
                    left = 1;
                    right_gain = weight;
                }
            }
            for (line..line + count) |k| {
                const value = spectra[0][k];
                spectra[0][k] = value * left;
                spectra[1][k] = value * right_gain;
            }
        } else if (joint.ms_stereo) {
            midSide(spectra, line, count);
        }
        line += count;
    }
}

// -------------------------------------------------------------- reorder ----

/// Short blocks arrive window by window within each band; the transform wants
/// them line by line.  The long region of a mixed block, and at 8 kHz the
/// short band that shares it, are left where they are.
fn reorder(spectrum: *[granule_len]f32, layout: Layout) void {
    var scratch: [granule_len]f32 = undefined;
    const start = layout.shortStart();

    var line: usize = 0;
    var band: usize = 0;
    while (band < layout.long_bands) : (band += 1) line += layout.widths[band];

    while (band + 2 < layout.widths.len) : (band += 3) {
        const width: usize = layout.widths[band];
        const span = width * 3;
        if (line + span > granule_len) break;
        if (line >= start) {
            for (0..3) |window| {
                for (0..width) |j| scratch[3 * j + window] = spectrum[line + window * width + j];
            }
            @memcpy(spectrum[line .. line + span], scratch[0..span]);
        }
        line += span;
    }
}

// ---------------------------------------------------------------- decode ---

/// Everything a Layer III decoder must remember between granules.
pub const State = struct {
    /// The tail of each channel's last transform, to overlap into the next.
    overlap: [2]imdct.Overlap = @splat(@splat(@splat(0))),
    filterbank: [2]synthesis.State = @splat(.{}),
    /// Intensity stereo positions taken from the right channel.
    intensity: [max_bands + 1]u8 = @splat(0),
    /// Granule 0's scalefactors, which granule 1 may reuse.
    previous: [2]Scalefactors = @splat(.{}),
    previous_short: [2]bool = @splat(false),

    /// Forget everything, for a seek or a change of stream.
    pub fn reset(self: *State) void {
        self.* = .{};
    }
};

/// Decode one granule of every channel into `out`, which holds
/// `576 * channels` interleaved samples.  `reader` must be positioned at the
/// granule's main data and is left at its end whatever the granule contained.
pub fn decodeGranule(
    state: *State,
    header: Header,
    info: *const SideInfo,
    gr: usize,
    reader: *BitReader,
    out: []f32,
) void {
    const channels = header.channels();
    std.debug.assert(out.len >= granule_len * @as(usize, channels));

    // Not zeroed: requantization writes every line of every channel it is
    // given, and the channels it is not given are never read.
    var spectra: [2][granule_len]f32 = undefined;
    var layouts: [2]Layout = undefined;

    for (0..channels) |ch| {
        const granule = info.get(gr, ch);
        const end = reader.pos + granule.part2_3_length;
        const layout = layoutFor(header, granule);
        layouts[ch] = layout;

        var scalefactors: Scalefactors = undefined;
        readScalefactors(
            reader,
            header,
            info,
            gr,
            ch,
            granule,
            &state.previous[ch],
            state.previous_short[ch],
            &scalefactors,
        );
        if (gr == 0) {
            state.previous[ch] = scalefactors;
            state.previous_short[ch] = granule.isShort();
        }
        if (ch == 1) state.intensity = scalefactors.intensity;

        var quantized: [granule_len]i32 = undefined;
        const coded = readSpectrum(reader, granule, layout, end, &quantized);
        requantize(granule, layout, &scalefactors, &quantized, coded, &spectra[ch]);

        // Whatever the granule did with its bits, the next one starts where
        // `part2_3_length` says it does.
        reader.seek(end);
    }

    if (channels == 2) {
        processStereo(header, layouts[0], info.get(gr, 1), &state.intensity, &spectra);
    }

    for (0..channels) |ch| {
        const granule = info.get(gr, ch);
        const layout = layouts[ch];
        if (granule.isShort()) reorder(&spectra[ch], layout);

        const long_subbands: usize = if (granule.isShort())
            layout.mixed_long_subbands
        else
            imdct.subbands;
        imdct.reduceAlias(&spectra[ch], long_subbands);
        const active = imdct.hybridSynthesis(
            &spectra[ch],
            &state.overlap[ch],
            granule.block_type,
            layout.mixed_long_subbands,
        );
        imdct.invertFrequency(&spectra[ch]);
        synthesis.synthesize(&state.filterbank[ch], &spectra[ch], out[ch..], channels, active);
    }
}

const testing = std.testing;

fn testGranule(block_type: BlockType, mixed: bool) Granule {
    return std.mem.zeroInit(Granule, .{
        .window_switching = block_type != .normal,
        .block_type = block_type,
        .mixed_block = mixed,
    });
}

test "the band layout follows the block type" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?; // MPEG-1 44.1 kHz

    const long = layoutFor(header, &testGranule(.normal, false));
    try testing.expectEqual(@as(usize, 22), long.widths.len);
    try testing.expectEqual(@as(usize, 22), long.long_bands);
    try testing.expectEqual(@as(usize, 0), long.mixed_long_subbands);

    const short = layoutFor(header, &testGranule(.short, false));
    try testing.expectEqual(@as(usize, 39), short.widths.len);
    try testing.expectEqual(@as(usize, 0), short.long_bands);

    // A start or stop block still uses the long bands; only `.short` switches.
    const start = layoutFor(header, &testGranule(.start, false));
    try testing.expectEqual(@as(usize, 22), start.widths.len);

    const mixed = layoutFor(header, &testGranule(.short, true));
    try testing.expectEqual(@as(usize, 8), mixed.long_bands);
    try testing.expectEqual(@as(usize, 38), mixed.widths.len);
    try testing.expectEqual(@as(usize, 2), mixed.mixed_long_subbands);
    try testing.expectEqual(@as(usize, 36), mixed.shortStart());
}

test "every band layout covers the whole spectrum" {
    for ([_]Header.Version{ .mpeg1, .mpeg2, .mpeg2_5 }) |version| {
        for (0..3) |rate| {
            const row = &sfb.bands[sfb.index(version.tableIndex(), @intCast(rate))];
            var long: usize = 0;
            for (row.long_widths) |w| long += w;
            var short: usize = 0;
            for (row.short_widths) |w| short += w;
            try testing.expectEqual(@as(usize, granule_len), long);
            try testing.expectEqual(@as(usize, granule_len), short);
            // Each short band appears once per window, with equal widths.
            var band: usize = 0;
            while (band < row.short_widths.len) : (band += 3) {
                try testing.expectEqual(row.short_widths[band], row.short_widths[band + 1]);
                try testing.expectEqual(row.short_widths[band], row.short_widths[band + 2]);
            }
        }
    }
}

test "the 8 kHz mixed block has a longer long region" {
    // The one place the mixed layout is not a splice of the other two.
    const header = Header.parse(.{ 0xff, 0xe3, 0x48, 0xc0 }).?;
    try testing.expectEqual(Header.Version.mpeg2_5, header.version);
    try testing.expectEqual(@as(u32, 8000), header.sampleRate());

    const mixed = layoutFor(header, &testGranule(.short, true));
    try testing.expectEqual(@as(usize, 6), mixed.long_bands);
    var lines: usize = 0;
    for (mixed.widths[0..mixed.long_bands]) |w| lines += w;
    try testing.expectEqual(@as(usize, 48), lines);
    // The transform still works in whole subbands, so it rounds up to four.
    try testing.expectEqual(@as(usize, 4), mixed.mixed_long_subbands);
    try testing.expectEqual(@as(usize, 72), mixed.shortStart());
}

test "MPEG-1 scalefactor partitions cover their block shapes" {
    // Long blocks send 21 scalefactors, short blocks 12 bands times three
    // windows, and mixed blocks 8 long bands plus 9 short ones times three.
    var total: usize = 0;
    for (mpeg1Partitions(&testGranule(.normal, false))) |n| total += n;
    try testing.expectEqual(@as(usize, 21), total);

    total = 0;
    for (mpeg1Partitions(&testGranule(.short, false))) |n| total += n;
    try testing.expectEqual(@as(usize, 36), total);

    total = 0;
    for (mpeg1Partitions(&testGranule(.short, true))) |n| total += n;
    try testing.expectEqual(@as(usize, 35), total);
}

test "the low sampling frequency scalefactor sizes match the modulus form" {
    // The standard states this unpacking as a division by a running product
    // of per-partition moduli.  Deriving it that way independently and
    // agreeing is a real check on the arithmetic above.
    const moduli = [6][4]u32{
        .{ 5, 5, 4, 4 }, .{ 5, 5, 4, 1 }, .{ 4, 3, 1, 1 },
        .{ 5, 6, 6, 1 }, .{ 4, 4, 4, 1 }, .{ 4, 3, 1, 1 },
    };
    for ([_]bool{ false, true }) |intensity| {
        for (0..512) |compress| {
            const got = lsfSizes(@intCast(compress), intensity);
            var remaining: i64 = @intCast(if (intensity) compress >> 1 else compress);
            var set: usize = if (intensity) 3 else 0;
            var want: [4]u8 = undefined;
            while (true) : (set += 1) {
                var product: u32 = 1;
                var n: usize = 4;
                while (n > 0) {
                    n -= 1;
                    const quotient = @divTrunc(remaining, @as(i64, product));
                    want[n] = @intCast(@mod(quotient, @as(i64, moduli[set][n])));
                    product *= moduli[set][n];
                }
                if (remaining - product < 0) break;
                remaining -= product;
            }
            try testing.expectEqual(set, got.set);
            try testing.expectEqualSlices(u8, &want, &got.lengths);
        }
    }
}

test "reordering turns window major short bands into line major ones" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?;
    const granule = testGranule(.short, false);
    const layout = layoutFor(header, &granule);

    // The first three bands of a 44.1 kHz short block are four lines wide, so
    // the first band occupies lines 0...12 as window 0, then 1, then 2.
    var spectrum: [granule_len]f32 = @splat(0);
    for (0..12) |n| spectrum[n] = @floatFromInt(n);
    reorder(&spectrum, layout);

    // Line j of window w moves from w * 4 + j to 3 * j + w.
    for (0..3) |w| {
        for (0..4) |j| {
            try testing.expectEqual(
                @as(f32, @floatFromInt(w * 4 + j)),
                spectrum[3 * j + w],
            );
        }
    }
}

test "reordering leaves the long region of a mixed block alone" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?;
    const granule = testGranule(.short, true);
    const layout = layoutFor(header, &granule);

    var spectrum: [granule_len]f32 = @splat(0);
    for (&spectrum, 0..) |*v, n| v.* = @floatFromInt(n);
    reorder(&spectrum, layout);
    for (0..36) |n| try testing.expectEqual(@as(f32, @floatFromInt(n)), spectrum[n]);
    // The first short band does move.
    try testing.expect(spectrum[37] != 37);
}

test "requantization is exact at unit gain" {
    // global_gain 210 with no scalefactors is the point where the gain term
    // is exactly one, so the output is the quantized value raised to 4/3.
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?;
    var granule = testGranule(.normal, false);
    granule.global_gain = 210;
    const layout = layoutFor(header, &granule);
    const scalefactors = Scalefactors{};

    var quantized: [granule_len]i32 = @splat(0);
    quantized[0] = 1;
    quantized[1] = -1;
    quantized[2] = 8;
    quantized[3] = -27;
    var out: [granule_len]f32 = undefined;
    requantize(&granule, layout, &scalefactors, &quantized, granule_len, &out);

    try testing.expectApproxEqAbs(@as(f32, 1), out[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, -1), out[1], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 16), out[2], 1e-4); // 8^(4/3)
    try testing.expectApproxEqAbs(@as(f32, -81), out[3], 1e-3); // 27^(4/3)

    // Four more of global gain is one more doubling.
    granule.global_gain = 214;
    requantize(&granule, layout, &scalefactors, &quantized, granule_len, &out);
    try testing.expectApproxEqAbs(@as(f32, 2), out[0], 1e-6);
}

test "a scalefactor attenuates by half a step, or a whole one when scaled" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?;
    var granule = testGranule(.normal, false);
    granule.global_gain = 210;
    const layout = layoutFor(header, &granule);

    var scalefactors = Scalefactors{};
    scalefactors.values[0] = 2;
    var quantized: [granule_len]i32 = @splat(0);
    quantized[0] = 1;
    var out: [granule_len]f32 = undefined;

    // scalefac_scale clear: each step is 2^-0.5, so two steps halve it.
    requantize(&granule, layout, &scalefactors, &quantized, granule_len, &out);
    try testing.expectApproxEqAbs(@as(f32, 0.5), out[0], 1e-6);

    // scalefac_scale set: each step is 2^-1, so two steps quarter it.
    granule.scalefac_scale = true;
    requantize(&granule, layout, &scalefactors, &quantized, granule_len, &out);
    try testing.expectApproxEqAbs(@as(f32, 0.25), out[0], 1e-6);
}

test "intensity stereo weights are the standard's tangent pans" {
    for (0..6) |position| {
        const ratio = @tan(@as(f64, @floatFromInt(position)) * std.math.pi / 12.0);
        try testing.expectApproxEqAbs(
            @as(f32, @floatCast(ratio / (1 + ratio))),
            pan[position][0],
            1e-6,
        );
        // The two weights always sum to one.
        try testing.expectApproxEqAbs(@as(f32, 1), pan[position][0] + pan[position][1], 1e-6);
    }
    // Position 6 is the limit of tan, where the band is wholly on the left.
    try testing.expectEqual([2]f32{ 1, 0 }, pan[6]);
}

test "mid/side is its own inverse up to the scaling the standard applies" {
    var spectra: [2][granule_len]f32 = @splat(@splat(0));
    spectra[0][0] = 3;
    spectra[1][0] = 1;
    midSide(&spectra, 0, 1);
    // L = (M + S)/sqrt(2), R = (M - S)/sqrt(2)
    try testing.expectApproxEqAbs(@as(f32, 4 * std.math.sqrt1_2), spectra[0][0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 2 * std.math.sqrt1_2), spectra[1][0], 1e-6);
    // Energy is preserved, which is the point of the 1/sqrt(2).
    midSide(&spectra, 0, 1);
    try testing.expectApproxEqAbs(@as(f32, 3), spectra[0][0], 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 1), spectra[1][0], 1e-5);
}

test "the preemphasis table is the standard's" {
    // ISO/IEC 11172-3 Table B.6, and zero for the band that carries no
    // scalefactor of its own.
    try testing.expectEqualSlices(u8, &.{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 3, 2, 0,
    }, &pretab);
}
