// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The polyphase synthesis filterbank of ISO/IEC 11172-3 Annex B.2.
//!
//! Eighteen times per granule it takes one sample from each of the 32
//! subbands and produces 32 consecutive PCM samples, running them through a
//! 512-tap window over the last sixteen blocks of filtered history.  It is
//! the decoder's hot spot by a wide margin, so it is written for speed:
//!
//!   * The standard's 64x32 matrix is computed as 32 rows rather than 64.
//!     Writing the matrix as D[u] = sum_j s[j] cos(u(2j+1)pi/64), the row the
//!     standard calls N[i] is D[16 + i], and D obeys D[64 - u] = -D[u], which
//!     makes D[32] zero and gives the upper half of the rows for nothing.
//!
//!   * The history is kept as sixteen blocks of 64 in a ring of blocks.
//!     Every one of the window's 32-value reads falls inside a single block
//!     -- the standard reads the first half of the even blocks and the second
//!     half of the odd ones -- so nothing ever straddles the wrap, and the
//!     whole windowing and summing step is sixteen vector multiply-adds.
//!
//! `reference.zig` has the same filter written the way the standard's
//! flowchart reads, and a test holds the two against each other.

const std = @import("std");

const window = @import("tables/synthesis_window.zig");

pub const subbands = 32;
/// A Layer III granule: 32 subbands of 18 time slots.
pub const granule_len = 576;
/// Time slots in one of those.  Layers I and II hand over twelve at a time
/// instead, which is why the count is taken from the input rather than fixed.
pub const slots = granule_len / subbands;

/// The history the window runs over: sixteen blocks of 64.
const blocks = 16;
const block_len = 64;

const Block = @Vector(subbands, f32);

/// The 64 rows of the standard's matrix are a rearrangement of the 32 values
/// actually computed: row i is D[16 + i], D[32] is zero, and above that D[u]
/// is -D[64 - u].  Written as two shuffles and two sign patterns, the whole
/// rearrangement is six vector operations instead of sixty-four moves.
const rows_low = blk: {
    var m: [subbands]i32 = undefined;
    var signs: [subbands]f32 = undefined;
    for (0..subbands) |i| {
        if (i < 16) {
            m[i] = @intCast(16 + i); // D[16 + i]
            signs[i] = 1;
        } else if (i == 16) {
            m[i] = 0; // D[32], which is zero; the sign pattern makes it so
            signs[i] = 0;
        } else {
            m[i] = @intCast(48 - i); // -D[64 - (16 + i)]
            signs[i] = -1;
        }
    }
    break :blk .{ .order = m, .signs = @as(Block, signs) };
};

const rows_high = blk: {
    var m: [subbands]i32 = undefined;
    for (0..subbands) |i| m[i] = @intCast(if (i < 16) 16 - i else i - 16);
    break :blk m;
};

/// cos(u(2j+1)pi/64) for the 32 rows that are not implied by the others,
/// stored a column at a time: `cosines[j]` holds that coefficient for every
/// u at once.
///
/// Transposed, because the obvious orientation makes the matrix product 32
/// dot products, and a dot product ends in a horizontal sum across the vector
/// -- which costs more than the multiplying did.  This way the 32 results
/// accumulate in 32 lanes and never have to be summed across at all.
const cosines = blk: {
    @setEvalBranchQuota(200_000);
    var table: [subbands]Block = undefined;
    for (0..subbands) |j| {
        var column: [32]f32 = undefined;
        for (0..32) |u| {
            const angle = @as(f64, @floatFromInt(u * (2 * j + 1))) * (std.math.pi / 64.0);
            column[u] = @floatCast(@cos(angle));
        }
        table[j] = column;
    }
    break :blk table;
};

fn blockAt(values: []const f32, at: usize) Block {
    return values[at..][0..subbands].*;
}

/// One channel's filterbank history.  Reset it when the stream is
/// discontinuous -- after a seek, say -- or the first granule decoded will
/// mix in the samples on either side of the join.
pub const State = struct {
    /// Sixteen blocks of 64 filtered values, newest at `head`.
    v: [blocks * block_len]f32 = @splat(0),
    /// Which block is the newest.  Blocks are whole, so shifting the history
    /// is a decrement rather than a copy.
    head: usize = 0,

    pub fn reset(self: *State) void {
        self.* = .{};
    }
};

/// Filter one granule of one channel.
///
/// `spectrum` is subband major: 32 subbands of however many time slots it
/// holds, which is 18 for a Layer III granule and 12 for a Layer I or II one.
/// One PCM sample comes out per input sample, written to `out` every `stride`
/// elements, which is how a caller interleaves channels.
/// `active` is the number of leading subbands that may carry anything; the
/// rest are known to be zero and are not matrixed.  Multiplying a zero
/// subband by its row of cosines and adding the result changes nothing, so
/// passing a smaller `active` gives bit-identical output for less work.
/// Pass `subbands` when nothing is known.
///
/// It is worth knowing: an encoder writes nothing above its lowpass, and
/// Layer II at low bit rates carries as few as eight of the thirty-two
/// subbands, so most of this loop is otherwise spent multiplying by zero.
pub fn synthesize(
    state: *State,
    spectrum: []const f32,
    out: []f32,
    stride: usize,
    active: usize,
) void {
    std.debug.assert(spectrum.len % subbands == 0);
    std.debug.assert(active <= subbands);
    const slot_count = spectrum.len / subbands;
    std.debug.assert(out.len >= (spectrum.len - 1) * stride + 1);

    for (0..slot_count) |slot| {
        // Gather the slot's subband samples. The spectrum is subband major,
        // so this is the one strided read; everything after it runs over
        // contiguous memory.
        var accumulator: Block = @splat(0);
        for (0..active) |j| {
            const sample: Block = @splat(spectrum[j * slot_count + slot]);
            accumulator += cosines[j] * sample;
        }
        state.head = (state.head + blocks - 1) & (blocks - 1);

        // The 64 rows, as two shuffles of the 32 values just computed.
        const rows = state.v[state.head * block_len ..][0..block_len];
        rows[0..subbands].* = @shuffle(f32, accumulator, undefined, rows_low.order) *
            rows_low.signs;
        rows[subbands..][0..subbands].* =
            -@shuffle(f32, accumulator, undefined, rows_high);

        // The standard builds a 512 element vector out of alternating half
        // blocks of the history, multiplies it by the window and sums every
        // 32nd element.  Folding those together leaves sixteen multiply-adds
        // of 32 lanes each, and each half block lies inside one ring block.
        var total: Block = @splat(0);
        for (0..8) |i| {
            const even = ((state.head + 2 * i) & (blocks - 1)) * block_len;
            const odd = ((state.head + 2 * i + 1) & (blocks - 1)) * block_len;
            total += blockAt(&state.v, even) * blockAt(&window.d, 64 * i);
            total += blockAt(&state.v, odd + 32) * blockAt(&window.d, 64 * i + 32);
        }

        const at = slot * subbands;
        if (stride == 1) {
            out[at..][0..subbands].* = total;
        } else {
            const lanes: [subbands]f32 = total;
            for (lanes, 0..) |sample, lane| out[(at + lane) * stride] = sample;
        }
    }
}

const testing = std.testing;
const reference = @import("reference.zig");

test "silence in, silence out" {
    var state = State{};
    const quiet: [granule_len]f32 = @splat(0);
    var out: [granule_len]f32 = @splat(1);
    synthesize(&state, &quiet, &out, 1, subbands);
    for (out) |v| try testing.expectEqual(@as(f32, 0), v);
}

test "the filterbank is what the standard's flowchart describes" {
    // The reference is the flowchart written out: the full 64x32 matrix, the
    // U vector built by hand, the window applied to it, and every 32nd
    // element summed. Several granules, because the two have to stay in step
    // as the history fills and wraps.
    var fast = State{};
    var slow = reference.SynthesisState{};
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const random = prng.random();

    for (0..40) |granule| {
        var spectrum: [granule_len]f32 = undefined;
        for (&spectrum) |*value| value.* = random.float(f32) * 2 - 1;

        var got: [granule_len]f32 = undefined;
        var want: [granule_len]f32 = undefined;
        synthesize(&fast, &spectrum, &got, 1, subbands);
        reference.synthesize(&slow, &spectrum, &want);

        for (got, want, 0..) |g, w, i| {
            testing.expectApproxEqAbs(w, g, 1e-4) catch |err| {
                std.debug.print("granule {d}, sample {d}: {d} against {d}\n", .{ granule, i, g, w });
                return err;
            };
        }
    }
}

test "the filterbank is linear" {
    var a: [granule_len]f32 = undefined;
    var b: [granule_len]f32 = undefined;
    var sum_in: [granule_len]f32 = undefined;
    var rng = std.Random.DefaultPrng.init(0x5eed);
    const random = rng.random();
    for (0..granule_len) |i| {
        a[i] = random.float(f32) - 0.5;
        b[i] = random.float(f32) - 0.5;
        sum_in[i] = a[i] + b[i];
    }

    var out_a: [granule_len]f32 = undefined;
    var out_b: [granule_len]f32 = undefined;
    var out_sum: [granule_len]f32 = undefined;
    var s1 = State{};
    var s2 = State{};
    var s3 = State{};
    synthesize(&s1, &a, &out_a, 1, subbands);
    synthesize(&s2, &b, &out_b, 1, subbands);
    synthesize(&s3, &sum_in, &out_sum, 1, subbands);
    for (0..granule_len) |i| {
        try testing.expectApproxEqAbs(out_a[i] + out_b[i], out_sum[i], 1e-4);
    }
}

test "a constant subband lands on that subband's frequency edge" {
    // A steady value in subband k comes out as a tone at one edge of that
    // subband's range, k * rate / 64 wide: the lower edge for even k and the
    // upper edge for odd k.  That alternation is exactly what the frequency
    // inversion step in `imdct.zig` exists to undo, and checking for it here
    // pins down the matrix, the window and the order they are combined in.
    // Over 576 samples an edge at m * rate / 64 is bin 9m.
    for ([_]usize{ 0, 1, 4, 9 }) |band| {
        var state = State{};
        var spectrum: [granule_len]f32 = @splat(0);
        for (0..slots) |slot| spectrum[band * slots + slot] = 1;

        var out: [granule_len]f32 = undefined;
        // Let the 512-tap window fill with history before measuring.
        for (0..3) |_| synthesize(&state, &spectrum, &out, 1, subbands);

        var peak_bin: usize = 0;
        var peak: f64 = -1;
        for (0..granule_len / 2) |bin| {
            var re: f64 = 0;
            var im: f64 = 0;
            for (out, 0..) |v, n| {
                const angle = -2.0 * std.math.pi * @as(f64, @floatFromInt(bin * n)) /
                    @as(f64, @floatFromInt(granule_len));
                re += @as(f64, v) * @cos(angle);
                im += @as(f64, v) * @sin(angle);
            }
            const magnitude = re * re + im * im;
            if (magnitude > peak) {
                peak = magnitude;
                peak_bin = bin;
            }
        }
        const edge = if (band % 2 == 0) band else band + 1;
        try testing.expectEqual(9 * edge, peak_bin);
    }
}

test "stride interleaves without disturbing neighbouring samples" {
    var state = State{};
    var spectrum: [granule_len]f32 = @splat(0);
    spectrum[0] = 1;
    var out: [granule_len * 2]f32 = @splat(-1);
    synthesize(&state, &spectrum, &out, 2, subbands);
    for (0..granule_len) |i| try testing.expectEqual(@as(f32, -1), out[i * 2 + 1]);
}

test "a stride of one gives the same samples as any other" {
    var direct = State{};
    var strided = State{};
    var prng = std.Random.DefaultPrng.init(7);
    var spectrum: [granule_len]f32 = undefined;
    for (&spectrum) |*value| value.* = prng.random().float(f32) - 0.5;

    var one: [granule_len]f32 = undefined;
    var three: [granule_len * 3]f32 = undefined;
    synthesize(&direct, &spectrum, &one, 1, subbands);
    synthesize(&strided, &spectrum, &three, 3, subbands);
    for (0..granule_len) |i| try testing.expectEqual(one[i], three[i * 3]);
}
