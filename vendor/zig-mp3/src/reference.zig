// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The filterbanks written the way the standard's flowcharts read, with none
//! of the rearrangement the real ones do for speed.
//!
//! Nothing calls these but the tests, which hold the fast implementations
//! against them.  Two implementations of the same specification, arrived at
//! differently, disagreeing is how a clever rearrangement that is subtly
//! wrong gets caught -- and the arithmetic here is transparent enough to be
//! checked against the standard by eye.

const std = @import("std");

const window = @import("tables/synthesis_window.zig");

const granule_len = 576;
const subbands = 32;
const slots = granule_len / subbands;

/// ISO/IEC 11172-3 Annex B.2, verbatim: a 1024 element vector shifted by 64
/// each time, the full 64x32 matrix, and the U vector assembled from it.
pub const SynthesisState = struct {
    v: [1024]f32 = @splat(0),
};

pub fn synthesize(
    state: *SynthesisState,
    spectrum: []const f32,
    out: []f32,
) void {
    const slot_count = spectrum.len / subbands;
    for (0..slot_count) |slot| {
        // Shift the vector up by 64.
        var i: usize = 1023;
        while (i >= 64) : (i -= 1) state.v[i] = state.v[i - 64];

        // Matrix the 32 subband samples into the first 64 places.
        for (0..64) |n| {
            var sum: f32 = 0;
            for (0..subbands) |j| {
                const angle = @as(f64, @floatFromInt((16 + n) * (2 * j + 1))) *
                    (std.math.pi / 64.0);
                sum += @as(f32, @floatCast(@cos(angle))) * spectrum[j * slot_count + slot];
            }
            state.v[n] = sum;
        }

        // Build the U vector out of alternating half blocks.
        var u: [512]f32 = undefined;
        for (0..8) |n| {
            for (0..32) |j| {
                u[64 * n + j] = state.v[128 * n + j];
                u[64 * n + 32 + j] = state.v[128 * n + 96 + j];
            }
        }

        // Window it, then sum every 32nd element.
        for (&u, window.d) |*value, coefficient| value.* *= coefficient;
        for (0..32) |j| {
            var sum: f32 = 0;
            for (0..16) |n| sum += u[j + 32 * n];
            out[slot * 32 + j] = sum;
        }
    }
}

/// ISO/IEC 11172-3 2.4.3.4.9, verbatim: every output computed from every
/// input, with none of the symmetry the real one exploits.
pub fn imdct(in: []const f32, out: []f32) void {
    const n = out.len; // 36 for a long block, 12 for a short one
    std.debug.assert(in.len * 2 == n);
    for (out, 0..) |*value, i| {
        var sum: f64 = 0;
        for (in, 0..) |x, k| {
            const angle = std.math.pi / @as(f64, @floatFromInt(2 * n)) *
                @as(f64, @floatFromInt((2 * i + 1 + n / 2) * (2 * k + 1)));
            sum += @as(f64, x) * @cos(angle);
        }
        value.* = @floatCast(sum);
    }
}

/// The bit reader written the plain way: one bit at a time, out of the byte
/// it falls in, with no attempt to read several at once.
///
/// The real one loads eight bytes and shifts, which is much faster and much
/// easier to get wrong near the end of a buffer.  This is what it is checked
/// against.
pub const BitReader = struct {
    bytes: []const u8,
    pos: usize = 0,
    overrun: usize = 0,

    pub fn peek(self: BitReader, n: u6) u32 {
        var value: u32 = 0;
        for (0..n) |i| {
            const at = self.pos + i;
            const byte: u8 = if (at >> 3 < self.bytes.len) self.bytes[at >> 3] else 0;
            const bit: u1 = @truncate(byte >> (7 - @as(u3, @truncate(at))));
            value = (value << 1) | bit;
        }
        return value;
    }

    pub fn read(self: *BitReader, n: u6) u32 {
        const value = self.peek(n);
        const total = self.bytes.len * 8;
        for (0..n) |i| {
            if (self.pos + i >= total) self.overrun += 1;
        }
        self.pos += n;
        return value;
    }
};
