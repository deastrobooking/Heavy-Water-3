// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Hybrid synthesis: the stages between the requantized spectrum and the
//! 32-subband time samples the polyphase filterbank wants.
//!
//! In order: alias reduction, the inverse MDCT with its block window, overlap
//! and add against the previous granule, and frequency inversion.

const std = @import("std");

const BlockType = @import("side_info.zig").BlockType;

/// Spectral lines in a granule, and time samples out of it.
pub const granule_len = 576;
/// Lines per subband, and IMDCT inputs per block.
pub const subband_len = 18;
pub const subbands = granule_len / subband_len;

/// The half of each transform that overlaps into the next granule.
pub const Overlap = [subbands][subband_len]f32;

/// ISO/IEC 11172-3 Table B.9: the alias reduction butterfly coefficients,
/// derived from c[i] as cs = 1/sqrt(1 + c^2) and ca = c/sqrt(1 + c^2).
const alias = blk: {
    const c = [8]f64{ -0.6, -0.535, -0.33, -0.185, -0.095, -0.041, -0.0142, -0.0037 };
    var cs: [8]f32 = undefined;
    var ca: [8]f32 = undefined;
    for (c, 0..) |ci, i| {
        const norm = @sqrt(1.0 + ci * ci);
        cs[i] = @floatCast(1.0 / norm);
        ca[i] = @floatCast(ci / norm);
    }
    break :blk .{ .cs = cs, .ca = ca };
};

/// Undo the aliasing the analysis filterbank introduced between neighbouring
/// subbands.
///
/// `long_subbands` is how many of the granule's lowest subbands were
/// transformed as long blocks: all 32 for a granule that is not short, the
/// mixed-block count for a mixed one, and none for a plain short block, which
/// was never aliased and is left alone.
pub fn reduceAlias(spectrum: *[granule_len]f32, long_subbands: usize) void {
    if (long_subbands < 2) return;
    for (1..long_subbands) |sb| {
        for (0..8) |i| {
            const lower = sb * subband_len - 1 - i;
            const upper = sb * subband_len + i;
            const l = spectrum[lower];
            const u = spectrum[upper];
            spectrum[lower] = l * alias.cs[i] - u * alias.ca[i];
            spectrum[upper] = u * alias.cs[i] + l * alias.ca[i];
        }
    }
}

/// The 18 outputs of the 36-point transform that are not implied by the
/// others: the first half of each half.  See `transform` for why.
const long_rows = [18]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 18, 19, 20, 21, 22, 23, 24, 25, 26 };
/// The same for a short block's 12-point transform.
const short_rows = [6]usize{ 0, 1, 2, 6, 7, 8 };

/// Padded to a power of two: a vector of 18 lanes is legalised into pieces
/// that cost more than the lanes it saves.
const long_lanes = 32;
const short_lanes = 8;
const LongVector = @Vector(long_lanes, f32);
const ShortVector = @Vector(short_lanes, f32);

/// cos(pi/72 * (2i + 1 + 18) * (2k + 1)), a column at a time: `long_cos[k]`
/// holds that coefficient for all 18 outputs at once.
///
/// Transposed for the same reason the synthesis filterbank's table is.  The
/// obvious orientation makes each output a dot product, and a dot product
/// ends in a sum across the vector, which costs more than the multiplying.
/// This way the 18 outputs accumulate in 18 lanes and are never summed
/// across at all.
const long_cos = blk: {
    @setEvalBranchQuota(20_000);
    var t: [18]LongVector = undefined;
    for (0..18) |k| {
        var column: [long_lanes]f32 = @splat(0);
        for (long_rows, 0..) |i, lane| {
            const angle = std.math.pi / 72.0 *
                @as(f64, @floatFromInt((2 * i + 19) * (2 * k + 1)));
            column[lane] = @floatCast(@cos(angle));
        }
        t[k] = column;
    }
    break :blk t;
};

/// cos(pi/24 * (2i + 1 + 6) * (2k + 1)), likewise transposed.
const short_cos = blk: {
    @setEvalBranchQuota(20_000);
    var t: [6]ShortVector = undefined;
    for (0..6) |k| {
        var column: [short_lanes]f32 = @splat(0);
        for (short_rows, 0..) |i, lane| {
            const angle = std.math.pi / 24.0 *
                @as(f64, @floatFromInt((2 * i + 7) * (2 * k + 1)));
            column[lane] = @floatCast(@cos(angle));
        }
        t[k] = column;
    }
    break :blk t;
};

/// The four block windows of ISO/IEC 11172-3 2.4.3.4.10.  Index by block type;
/// the short window is applied to each 12-point transform separately and so
/// only its first twelve entries are used.
const window = blk: {
    @setEvalBranchQuota(20_000);
    const longSine = struct {
        fn f(i: usize) f32 {
            return @floatCast(@sin(std.math.pi / 36.0 * (@as(f64, @floatFromInt(i)) + 0.5)));
        }
    }.f;
    const shortSine = struct {
        fn f(i: usize) f32 {
            return @floatCast(@sin(std.math.pi / 12.0 * (@as(f64, @floatFromInt(i)) + 0.5)));
        }
    }.f;
    var w: [4][36]f32 = @splat(@splat(0));
    for (0..36) |i| w[0][i] = longSine(i);
    for (0..18) |i| w[1][i] = longSine(i);
    for (18..24) |i| w[1][i] = 1;
    for (24..30) |i| w[1][i] = shortSine(i - 18);
    for (0..12) |i| w[2][i] = shortSine(i);
    for (6..12) |i| w[3][i] = shortSine(i - 6);
    for (12..18) |i| w[3][i] = 1;
    for (18..36) |i| w[3][i] = longSine(i);
    break :blk w;
};

/// Inverse MDCT of one subband, windowed, into 36 samples.
///
/// Only half the transform is computed. Writing the output before windowing
/// as x[i] = sum_k X[k] cos(pi/72 (2i + 19)(2k + 1)), the cosine's argument
/// at 17 - i and at i sum to pi(2k + 1), an odd multiple of pi, so
/// x[17 - i] = -x[i]; and at 53 - i and i they sum to 2pi(2k + 1), so
/// x[53 - i] = x[i].  Between them those give the second half of each half
/// for nothing.  `reference.zig` computes all 36 the plain way and a test
/// holds the two together.
fn transform(in: *const [subband_len]f32, out: *[36]f32, block_type: BlockType) void {
    if (block_type == .short) {
        @memset(out, 0);
        // The three windows' inputs are interleaved: window `w` holds the
        // values at 3k + w, which is how reordering left them.
        for (0..3) |w| {
            var sums: [2]ShortVector = @splat(@splat(0));
            for (0..3) |k| {
                inline for (0..2) |lane| {
                    sums[lane] += short_cos[2 * k + lane] *
                        @as(ShortVector, @splat(in[3 * (2 * k + lane) + w]));
                }
            }
            const x: [short_lanes]f32 = sums[0] + sums[1];
            const at = 6 * w + 6;
            for (0..3) |i| {
                out[at + i] += x[i] * window[2][i];
                out[at + 5 - i] -= x[i] * window[2][5 - i];
            }
            for (0..3) |m| {
                const i = 6 + m;
                out[at + i] += x[3 + m] * window[2][i];
                out[at + 17 - i] += x[3 + m] * window[2][17 - i];
            }
        }
        return;
    }

    // Three running totals rather than one: a multiply-add cannot start
    // until the one before it has finished, so a single accumulator makes
    // the chain decide how long this takes rather than the arithmetic.
    // Eighteen inputs divide evenly by three.
    var sums: [3]LongVector = @splat(@splat(0));
    var k: usize = 0;
    while (k < subband_len) : (k += 3) {
        inline for (0..3) |lane| {
            sums[lane] += long_cos[k + lane] * @as(LongVector, @splat(in[k + lane]));
        }
    }
    const x: [long_lanes]f32 = (sums[0] + sums[1]) + sums[2];

    const w = window[@intFromEnum(block_type)];
    for (0..9) |i| {
        out[i] = x[i] * w[i];
        out[17 - i] = -x[i] * w[17 - i];
    }
    for (0..9) |m| {
        const i = 18 + m;
        out[i] = x[9 + m] * w[i];
        out[53 - i] = x[9 + m] * w[53 - i];
    }
}

/// Transform every subband of a granule in place, overlapping each with the
/// tail `overlap` left by the previous granule of this channel and leaving
/// this granule's tail behind for the next one.
///
/// The lowest `mixed_long_subbands` subbands take the normal 18-point
/// transform whatever `block_type` says, which is what makes a mixed block
/// mixed; pass zero for every other kind of granule.
/// Returns the number of leading subbands that can carry anything, which the
/// filterbank uses to skip matrixing the silent ones.  It costs nothing to
/// work out here: the occupancy test below is being done anyway.
pub fn hybridSynthesis(
    spectrum: *[granule_len]f32,
    overlap: *Overlap,
    block_type: BlockType,
    mixed_long_subbands: usize,
) usize {
    var active: usize = 0;
    for (0..subbands) |sb| {
        const in = spectrum[sb * subband_len ..][0..subband_len];

        // An encoder writes nothing above its lowpass, so the top subbands
        // are usually all zeroes -- a quarter of them at 192 kbit/s, more at
        // less.  The transform of nothing is nothing, and only the tail of
        // the previous granule is left to hand over.  The sign bit is masked
        // off because requantization produces a negative zero wherever a
        // negative value quantized to nothing.
        var occupied: u32 = 0;
        for (in) |value| occupied |= @as(u32, @bitCast(value)) & 0x7fff_ffff;
        if (occupied == 0) {
            // The subband is silent this granule, but the tail the last one
            // left still has to be handed over, and if that is not silent
            // either then neither is the output.
            var tail: u32 = 0;
            for (overlap[sb]) |value| tail |= @as(u32, @bitCast(value)) & 0x7fff_ffff;
            @memcpy(in, &overlap[sb]);
            @memset(&overlap[sb], 0);
            if (tail != 0) active = sb + 1;
            continue;
        }

        active = sb + 1;
        const sb_type: BlockType = if (sb < mixed_long_subbands) .normal else block_type;
        var out: [36]f32 = undefined;
        transform(in, &out, sb_type);
        for (0..subband_len) |i| {
            spectrum[sb * subband_len + i] = out[i] + overlap[sb][i];
            overlap[sb][i] = out[i + subband_len];
        }
    }
    return active;
}

/// Flip the sign of every other sample in every other subband, compensating
/// for the modulation the analysis filterbank applied.
pub fn invertFrequency(spectrum: *[granule_len]f32) void {
    var sb: usize = 1;
    while (sb < subbands) : (sb += 2) {
        var i: usize = 1;
        while (i < subband_len) : (i += 2) {
            spectrum[sb * subband_len + i] = -spectrum[sb * subband_len + i];
        }
    }
}

const testing = std.testing;
const reference = @import("reference.zig");

test "the transform is the standard's, computed from half as many rows" {
    // Windowing is folded into `transform`, so the reference is windowed the
    // same way here rather than being compared bare.
    var prng = std.Random.DefaultPrng.init(0x1d);
    const random = prng.random();

    for ([_]BlockType{ .normal, .start, .stop }) |block_type| {
        for (0..64) |_| {
            var in: [subband_len]f32 = undefined;
            for (&in) |*value| value.* = random.float(f32) * 2 - 1;

            var got: [36]f32 = undefined;
            transform(&in, &got, block_type);

            var want: [36]f32 = undefined;
            reference.imdct(&in, &want);
            for (&want, window[@intFromEnum(block_type)]) |*value, coefficient| {
                value.* *= coefficient;
            }
            for (got, want) |g, w| try testing.expectApproxEqAbs(w, g, 1e-3);
        }
    }
}

test "a short block is three transforms laid over each other" {
    var prng = std.Random.DefaultPrng.init(0x2d);
    const random = prng.random();

    for (0..64) |_| {
        var in: [subband_len]f32 = undefined;
        for (&in) |*value| value.* = random.float(f32) * 2 - 1;

        var got: [36]f32 = undefined;
        transform(&in, &got, .short);

        // The three windows' inputs are interleaved, and their outputs are
        // windowed and added at six sample intervals.
        var want: [36]f32 = @splat(0);
        for (0..3) |w| {
            var values: [6]f32 = undefined;
            for (0..6) |k| values[k] = in[3 * k + w];
            var piece: [12]f32 = undefined;
            reference.imdct(&values, &piece);
            for (piece, 0..) |value, i| want[6 * w + 6 + i] += value * window[2][i];
        }
        for (got, want) |g, w| try testing.expectApproxEqAbs(w, g, 1e-3);
    }
}

test "alias reduction is an orthogonal rotation" {
    var spectrum: [granule_len]f32 = undefined;
    for (&spectrum, 0..) |*v, i| v.* = @floatFromInt(i % 17);
    const original = spectrum;

    reduceAlias(&spectrum, subbands);
    // The butterfly is a rotation, so the energy across each pair is kept.
    for (1..subbands) |sb| {
        for (0..8) |i| {
            const lower = sb * subband_len - 1 - i;
            const upper = sb * subband_len + i;
            const before = original[lower] * original[lower] + original[upper] * original[upper];
            const after = spectrum[lower] * spectrum[lower] + spectrum[upper] * spectrum[upper];
            try testing.expectApproxEqRel(before, after, 1e-5);
        }
    }
}

test "alias reduction leaves short blocks alone and mixed blocks nearly so" {
    var short_block: [granule_len]f32 = @splat(1);
    reduceAlias(&short_block, 0);
    try testing.expectEqual(@as(f32, 1), short_block[17]);
    try testing.expectEqual(@as(f32, 1), short_block[18]);

    var mixed_block: [granule_len]f32 = @splat(1);
    reduceAlias(&mixed_block, 2);
    // Only the boundary between subbands 1 and 2 is touched.
    try testing.expect(mixed_block[17] != 1);
    try testing.expectEqual(@as(f32, 1), mixed_block[35]);
    try testing.expectEqual(@as(f32, 1), mixed_block[36]);
}

test "the block windows meet the standard's shapes" {
    // Long: a half sine over all 36 points.
    try testing.expectApproxEqAbs(@as(f32, 0.043619), window[0][0], 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.999048), window[0][17], 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.043619), window[0][35], 1e-5);
    // Start: rises like a long block, holds at one, falls like a short one.
    try testing.expectApproxEqAbs(@as(f32, 1), window[1][18], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1), window[1][23], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.991445), window[1][24], 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.130526), window[1][29], 1e-5);
    try testing.expectEqual(@as(f32, 0), window[1][30]);
    // Stop is the start window reversed.
    for (0..36) |i| try testing.expectApproxEqAbs(window[1][35 - i], window[3][i], 1e-6);
    // Short: a half sine over 12 points, zero beyond.
    try testing.expectApproxEqAbs(@as(f32, 0.130526), window[2][0], 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.130526), window[2][11], 1e-5);
    try testing.expectEqual(@as(f32, 0), window[2][12]);
}

test "windows overlap to unity between consecutive long blocks" {
    // Overlap-add of the sine window with itself, half a block apart, must
    // reconstruct exactly; that is the whole point of the window's shape.
    for (0..18) |i| {
        const a = window[0][i + 18];
        const b = window[0][i];
        try testing.expectApproxEqAbs(@as(f32, 1), a * a + b * b, 1e-6);
    }
}

test "a constant spectrum transforms and overlaps back to something finite" {
    var spectrum: [granule_len]f32 = @splat(0);
    spectrum[0] = 1; // a single line in the lowest subband
    var overlap: Overlap = @splat(@splat(0));
    _ = hybridSynthesis(&spectrum, &overlap, .normal, 0);
    for (spectrum) |v| try testing.expect(std.math.isFinite(v));
    // A single spectral line spreads across the whole first subband and
    // leaves a tail for the next granule, but touches nothing above it.
    try testing.expect(@abs(spectrum[0]) > 0);
    try testing.expectEqual(@as(f32, 0), spectrum[subband_len]);
    try testing.expect(@abs(overlap[0][0]) > 0);
}

test "frequency inversion negates the odd samples of the odd subbands" {
    var spectrum: [granule_len]f32 = @splat(1);
    invertFrequency(&spectrum);
    try testing.expectEqual(@as(f32, 1), spectrum[0]);
    try testing.expectEqual(@as(f32, 1), spectrum[1]);
    try testing.expectEqual(@as(f32, 1), spectrum[subband_len]);
    try testing.expectEqual(@as(f32, -1), spectrum[subband_len + 1]);
    try testing.expectEqual(@as(f32, 1), spectrum[subband_len + 2]);
    try testing.expectEqual(@as(f32, 1), spectrum[2 * subband_len + 1]);
}
