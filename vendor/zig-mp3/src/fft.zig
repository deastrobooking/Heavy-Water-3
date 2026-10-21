// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! A radix-2 FFT, for the encoder's psychoacoustic model.
//!
//! Nothing here is on the decoder's path; it exists because working out what
//! a listener will not hear means looking at the signal's spectrum, and the
//! filterbank's 32 subbands are far too coarse a view to do that with.
//!
//! Only the sizes the model asks for are ever used, and it only ever wants
//! the power spectrum of real input, so that is the whole interface.

const std = @import("std");

/// In-place complex FFT of `re` and `im`, whose length must be a power of two.
pub fn transform(comptime n: usize, re: *[n]f64, im: *[n]f64) void {
    comptime std.debug.assert(std.math.isPowerOfTwo(n));

    // Bit-reversal permutation.
    const bits = comptime std.math.log2_int(usize, n);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const j = @bitReverse(@as(std.meta.Int(.unsigned, bits), @intCast(i)));
        if (i < j) {
            std.mem.swap(f64, &re[i], &re[j]);
            std.mem.swap(f64, &im[i], &im[j]);
        }
    }

    // Butterflies, doubling the span each pass.
    var span: usize = 1;
    while (span < n) : (span *= 2) {
        const step = std.math.pi / @as(f64, @floatFromInt(span));
        var k: usize = 0;
        while (k < span) : (k += 1) {
            const angle = -step * @as(f64, @floatFromInt(k));
            const wr = @cos(angle);
            const wi = @sin(angle);
            var at = k;
            while (at < n) : (at += span * 2) {
                const other = at + span;
                const tr = wr * re[other] - wi * im[other];
                const ti = wr * im[other] + wi * re[other];
                re[other] = re[at] - tr;
                im[other] = im[at] - ti;
                re[at] += tr;
                im[at] += ti;
            }
        }
    }
}

/// The power spectrum of `n` real samples, Hann windowed, as `n/2 + 1` bins.
///
/// The window is normalised so that a full scale sine comes out at a power of
/// one in its bin, which is what makes the decibel figures the model works in
/// comparable with the threshold formulas it uses.
pub fn powerSpectrum(
    comptime n: usize,
    input: *const [n]f32,
    out: *[n / 2 + 1]f64,
) void {
    var re: [n]f64 = undefined;
    var im: [n]f64 = @splat(0);

    // A Hann window sums to n/2, so that is what a coherent sinusoid's
    // amplitude is scaled by; halve again because a real sine splits its
    // power between the positive and negative frequency bins.
    const gain = 4.0 / @as(f64, @floatFromInt(n));
    for (0..n) |k| {
        const phase = 2.0 * std.math.pi * @as(f64, @floatFromInt(k)) /
            @as(f64, @floatFromInt(n));
        const w = 0.5 - 0.5 * @cos(phase);
        re[k] = @as(f64, input[k]) * w * gain;
    }

    transform(n, &re, &im);
    for (0..n / 2 + 1) |k| out[k] = re[k] * re[k] + im[k] * im[k];
}

const testing = std.testing;

test "a sine appears in its own bin at unit power" {
    const n = 1024;
    var input: [n]f32 = undefined;
    // Exactly 64 cycles across the window, so the tone sits on bin 64 and
    // does not leak into its neighbours.
    for (&input, 0..) |*value, k| {
        const phase = 2.0 * std.math.pi * 64.0 * @as(f64, @floatFromInt(k)) / n;
        value.* = @floatCast(@sin(phase));
    }
    var power: [n / 2 + 1]f64 = undefined;
    powerSpectrum(n, &input, &power);

    var loudest: usize = 0;
    for (power, 0..) |value, k| if (value > power[loudest]) {
        loudest = k;
    };
    try testing.expectEqual(@as(usize, 64), loudest);
    // A full scale sine, so unit power in its bin.
    try testing.expectApproxEqAbs(@as(f64, 1.0), power[64], 0.02);
    // And nothing much anywhere else.
    for (power, 0..) |value, k| {
        if (k < 62 or k > 66) try testing.expect(value < 1e-6);
    }
}

test "the transform of an impulse is flat" {
    const n = 64;
    var re: [n]f64 = @splat(0);
    var im: [n]f64 = @splat(0);
    re[0] = 1;
    transform(n, &re, &im);
    for (0..n) |k| {
        try testing.expectApproxEqAbs(@as(f64, 1), re[k], 1e-12);
        try testing.expectApproxEqAbs(@as(f64, 0), im[k], 1e-12);
    }
}

test "the transform agrees with the sum it stands for" {
    // A direct discrete Fourier transform, which is what the fast one is
    // supposed to compute, on a size small enough to write out longhand.
    const n = 32;
    var prng = std.Random.DefaultPrng.init(0xff7);
    const random = prng.random();
    var re: [n]f64 = undefined;
    var im: [n]f64 = undefined;
    for (0..n) |k| {
        re[k] = random.float(f64) - 0.5;
        im[k] = random.float(f64) - 0.5;
    }
    const in_re = re;
    const in_im = im;

    transform(n, &re, &im);

    for (0..n) |k| {
        var want_re: f64 = 0;
        var want_im: f64 = 0;
        for (0..n) |t| {
            const angle = -2.0 * std.math.pi * @as(f64, @floatFromInt(k * t)) / n;
            want_re += in_re[t] * @cos(angle) - in_im[t] * @sin(angle);
            want_im += in_re[t] * @sin(angle) + in_im[t] * @cos(angle);
        }
        try testing.expectApproxEqAbs(want_re, re[k], 1e-10);
        try testing.expectApproxEqAbs(want_im, im[k], 1e-10);
    }
}
