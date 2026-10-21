// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The polyphase analysis filterbank of ISO/IEC 11172-3 Annex C.
//!
//! This is the encoder's half of the pair `synthesis.zig` completes: it takes
//! 32 consecutive PCM samples and produces one sample for each of the 32
//! subbands, which is exactly what the decoder's filterbank consumes.  The
//! two are near-perfect-reconstruction, so running a signal through this and
//! then through the decoder's filterbank gives the signal back, delayed by
//! 481 samples and otherwise unchanged to within rounding; the test at the
//! bottom of this file is that round trip, and it is what says the window and
//! its sign convention are right.
//!
//! The window is the synthesis window divided by 32.  The standard prints the
//! two as separate tables -- C in Annex C and D in Annex B -- but they are the
//! same numbers scaled, so `tables/synthesis_window.zig` serves both and there
//! is one fewer table to get wrong.
//!
//! Written plainly rather than for speed.  Encoding is dominated by the
//! psychoacoustic model's FFT, not by this, and a filterbank that reads like
//! its flowchart is worth more here than one that does not.

const std = @import("std");

const window = @import("tables/synthesis_window.zig");

pub const subbands = 32;

/// The analysis window C[i], which is D[i]/32.
const c = blk: {
    @setEvalBranchQuota(10_000);
    var t: [512]f32 = undefined;
    for (window.d, 0..) |value, i| t[i] = value / 32.0;
    break :blk t;
};

/// cos((2k+1)(i-16)pi/64), the analysis matrix.
const matrix = blk: {
    @setEvalBranchQuota(200_000);
    var t: [subbands][64]f32 = undefined;
    for (0..subbands) |k| {
        for (0..64) |i| {
            const term = @as(i64, @intCast(2 * k + 1)) * (@as(i64, @intCast(i)) - 16);
            const angle = @as(f64, @floatFromInt(term)) * (std.math.pi / 64.0);
            t[k][i] = @floatCast(@cos(angle));
        }
    }
    break :blk t;
};

/// One channel's analysis history: the last 512 input samples, newest first.
pub const State = struct {
    x: [512]f32 = @splat(0),

    pub fn reset(self: *State) void {
        self.* = .{};
    }
};

/// Filter 32 PCM samples into one sample of each subband.
///
/// `input` is in time order and `out` is in subband order, so `out[k]` is
/// subband k's sample for this time slot.
pub fn analyze(state: *State, input: *const [subbands]f32, out: *[subbands]f32) void {
    // The buffer holds the newest sample at index 0, so the block shifts up
    // and the new samples go in reversed.
    var i: usize = 511;
    while (i >= subbands) : (i -= 1) state.x[i] = state.x[i - subbands];
    for (0..subbands) |k| state.x[subbands - 1 - k] = input[k];

    // Window, then fold the 512 windowed values down to 64 by adding every
    // 64th together.
    var y: [64]f32 = @splat(0);
    for (0..64) |n| {
        var sum: f32 = 0;
        for (0..8) |j| sum += c[n + 64 * j] * state.x[n + 64 * j];
        y[n] = sum;
    }

    for (0..subbands) |k| {
        var sum: f32 = 0;
        for (0..64) |n| sum += matrix[k][n] * y[n];
        out[k] = sum;
    }
}

const testing = std.testing;
const synthesis = @import("synthesis.zig");

/// The round trip's group delay, in samples.
pub const delay = 481;

test "analysis and synthesis reconstruct the signal they are given" {
    // The two filterbanks are designed as a pair, so this is the test that
    // says the analysis window, its scaling and its signs are all right: get
    // any of them wrong and the signal does not come back.
    var prng = std.Random.DefaultPrng.init(0xa11a1);
    const random = prng.random();

    const granules = 6;
    const count = granules * synthesis.granule_len;
    var signal: [count]f32 = undefined;
    var phase: f32 = 0;
    for (&signal, 0..) |*value, n| {
        phase += 0.03;
        value.* = 0.4 * @sin(phase) +
            0.3 * @sin(0.31 * @as(f32, @floatFromInt(n))) +
            0.05 * (random.float(f32) - 0.5);
    }

    var forward = State{};
    var back = synthesis.State{};
    var recovered: [count]f32 = undefined;

    // A granule at a time, which is the shape the decoder's filterbank takes:
    // eighteen time slots of 32 subbands, subband major.
    const sl = synthesis.slots;
    var at: usize = 0;
    while (at < count) : (at += synthesis.granule_len) {
        var spectrum: [synthesis.granule_len]f32 = undefined;
        for (0..sl) |slot| {
            var one: [subbands]f32 = undefined;
            analyze(&forward, signal[at + slot * subbands ..][0..subbands], &one);
            for (0..subbands) |k| spectrum[k * sl + slot] = one[k];
        }
        synthesis.synthesize(&back, &spectrum, recovered[at..][0..spectrum.len], 1, subbands);
    }

    var signal_power: f64 = 0;
    var error_power: f64 = 0;
    for (delay..count) |n| {
        const want = signal[n - delay];
        const got = recovered[n];
        signal_power += @as(f64, want) * want;
        error_power += @as(f64, got - want) * (got - want);
    }
    const snr = 10 * std.math.log10(signal_power / error_power);
    testing.expect(snr > 80) catch |err| {
        std.debug.print("round trip SNR {d:.2} dB, expected better than 80\n", .{snr});
        return err;
    };
}

test "a tone lands in the subband whose range holds it" {
    // Independent of the decoder: subband k covers frequencies from k/64 to
    // (k+1)/64 of the sampling rate, so a tone at the middle of that range
    // belongs to it and to almost nothing else.
    for ([_]usize{ 0, 1, 5, 11, 20, 31 }) |band| {
        var forward = State{};
        var energy: [subbands]f64 = @splat(0);
        const omega = 2.0 * std.math.pi * (@as(f64, @floatFromInt(band)) + 0.5) / 64.0;
        var n: usize = 0;
        while (n < 200 * subbands) : (n += subbands) {
            var input: [subbands]f32 = undefined;
            for (0..subbands) |k| {
                input[k] = @floatCast(@sin(omega * @as(f64, @floatFromInt(n + k))));
            }
            var one: [subbands]f32 = undefined;
            analyze(&forward, &input, &one);
            if (n < 32 * subbands) continue; // while the buffer fills
            for (0..subbands) |k| energy[k] += @as(f64, one[k]) * one[k];
        }
        var total: f64 = 0;
        for (energy) |e| total += e;
        try testing.expect(energy[band] / total > 0.99);
    }
}

test "silence in, silence out" {
    var state = State{};
    const quiet: [subbands]f32 = @splat(0);
    var out: [subbands]f32 = undefined;
    for (0..4) |_| analyze(&state, &quiet, &out);
    for (out) |value| try testing.expectEqual(@as(f32, 0), value);
}
