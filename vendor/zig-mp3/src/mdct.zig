// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The forward modified discrete cosine transform, and the aliasing that goes
//! with it: the encoder's half of what `imdct.zig` undoes.
//!
//! Layer III puts a second transform behind the filterbank.  Each subband's
//! run of samples is windowed 36 at a time, overlapping by half, and turned
//! into 18 spectral lines -- or, where the signal has a transient in it, into
//! three sets of 6, which trades frequency resolution for the time resolution
//! that keeps quantization noise from smearing backwards into the silence
//! before a sharp attack.
//!
//! Written from the definition rather than as a mirror of the decoder's
//! version, which is folded up to exploit symmetries that only exist in the
//! inverse direction.  The test that matters is at the bottom: a granule
//! through this and back out of `imdct.hybridSynthesis` has to be the granule
//! that went in.
//!
//! Nothing here is normative.  A decoder is told what transform to invert; an
//! encoder may compute the lines it sends however it likes, and would still
//! be conformant if it computed them badly.  What makes this right is not the
//! standard but the round trip.

const std = @import("std");

const imdct = @import("imdct.zig");
const side_info = @import("side_info.zig");

const BlockType = side_info.BlockType;

pub const granule_len = imdct.granule_len;
pub const subband_len = imdct.subband_len;
pub const subbands = imdct.subbands;

/// cos(pi/72 (2i + 1 + 18)(2k + 1)) for the 36 point transform, and the same
/// with pi/24 and 2i + 1 + 6 for the 12 point one.  These are exactly the
/// coefficients the inverse uses; the transform is its own transpose.
const long_cos = blk: {
    @setEvalBranchQuota(50_000);
    var t: [18][36]f32 = undefined;
    for (0..18) |k| {
        for (0..36) |i| {
            const angle = std.math.pi / 72.0 *
                @as(f64, @floatFromInt((2 * i + 19) * (2 * k + 1)));
            t[k][i] = @floatCast(@cos(angle));
        }
    }
    break :blk t;
};

const short_cos = blk: {
    @setEvalBranchQuota(20_000);
    var t: [6][12]f32 = undefined;
    for (0..6) |k| {
        for (0..12) |i| {
            const angle = std.math.pi / 24.0 *
                @as(f64, @floatFromInt((2 * i + 7) * (2 * k + 1)));
            t[k][i] = @floatCast(@cos(angle));
        }
    }
    break :blk t;
};

/// The block windows, which are the decoder's own: the pair only reconstructs
/// if both halves window with the same shape.
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

/// The transform pair reconstructs at N/2 times the input, so the forward
/// direction carries the 2/N that puts it back.  N is 18 for a long block and
/// 6 for a short one.
const long_scale = 2.0 / 18.0;
const short_scale = 2.0 / 6.0;

/// One channel's transform history: the 18 samples of each subband that the
/// next granule's window still reaches back over.
pub const State = struct {
    previous: [subbands][subband_len]f32 = @splat(@splat(0)),

    pub fn reset(self: *State) void {
        self.* = .{};
    }
};

/// Transform one granule of subband samples into 576 spectral lines.
///
/// `input` is subband major, 32 subbands of 18 time slots, which is what the
/// analysis filterbank produces.  `block_type` and `mixed_long_subbands`
/// carry the same meaning they do in the decoder: the lowest
/// `mixed_long_subbands` take the long transform whatever the block type
/// says, which is what makes a mixed block mixed.
pub fn forward(
    state: *State,
    input: *const [granule_len]f32,
    out: *[granule_len]f32,
    block_type: BlockType,
    mixed_long_subbands: usize,
) void {
    for (0..subbands) |sb| {
        const now = input[sb * subband_len ..][0..subband_len];
        // The window reaches 36 samples back: the previous granule's 18 and
        // this granule's 18.
        var frame: [36]f32 = undefined;
        @memcpy(frame[0..subband_len], &state.previous[sb]);
        @memcpy(frame[subband_len..], now);

        const kind: BlockType = if (sb < mixed_long_subbands) .normal else block_type;
        const lines = out[sb * subband_len ..][0..subband_len];
        if (kind == .short) {
            forwardShort(&frame, lines);
        } else {
            forwardLong(&frame, lines, kind);
        }

        @memcpy(&state.previous[sb], now);
    }
}

fn forwardLong(frame: *const [36]f32, out: *[subband_len]f32, block_type: BlockType) void {
    const w = &window[@intFromEnum(block_type)];
    var z: [36]f32 = undefined;
    for (0..36) |i| z[i] = frame[i] * w[i];

    for (0..18) |k| {
        var sum: f32 = 0;
        for (0..36) |i| sum += z[i] * long_cos[k][i];
        out[k] = sum * long_scale;
    }
}

/// Three 12 point transforms across the middle 30 samples of the window.
///
/// The three overlap each other by six and sit where the inverse expects
/// them: window `w` covers samples 6w to 6w + 11 of the 36, and its six lines
/// are interleaved into the subband as 3k + w, which is the order the
/// decoder's reordering step undoes.
fn forwardShort(frame: *const [36]f32, out: *[subband_len]f32) void {
    for (0..3) |w| {
        var z: [12]f32 = undefined;
        for (0..12) |i| z[i] = frame[6 * w + 6 + i] * window[2][i];
        for (0..6) |k| {
            var sum: f32 = 0;
            for (0..12) |i| sum += z[i] * short_cos[k][i];
            out[3 * k + w] = sum * short_scale;
        }
    }
}

/// The rotations `imdct.reduceAlias` undoes, applied the other way round.
///
/// The decoder turns each pair of lines by a rotation matrix; this turns them
/// back by its transpose, which for a rotation is its inverse.  The signs are
/// the only thing to get right and the round trip is what says they are.
pub fn expandAlias(spectrum: *[granule_len]f32, long_subbands: usize) void {
    if (long_subbands < 2) return;
    for (1..long_subbands) |sb| {
        for (0..8) |i| {
            const lower = sb * subband_len - 1 - i;
            const upper = sb * subband_len + i;
            const l = spectrum[lower];
            const u = spectrum[upper];
            spectrum[lower] = l * alias.cs[i] + u * alias.ca[i];
            spectrum[upper] = u * alias.cs[i] - l * alias.ca[i];
        }
    }
}

/// The same coefficients the decoder uses, worked out the same way.
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

const testing = std.testing;

/// Run a signal through the forward transform and the decoder's inverse, and
/// say how much of it came back.
///
/// Returns the signal-to-noise ratio in decibels over the granules that had
/// a neighbour on both sides, since the first and last are missing half their
/// overlap and cannot reconstruct.
fn roundTrip(
    types: []const BlockType,
    mixed_long: usize,
    seed: u64,
) !f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    const granules = types.len;

    const input = try testing.allocator.alloc(f32, granules * granule_len);
    defer testing.allocator.free(input);
    const output = try testing.allocator.alloc(f32, granules * granule_len);
    defer testing.allocator.free(output);
    for (input) |*value| value.* = random.float(f32) - 0.5;

    var forward_state = State{};
    var overlap: imdct.Overlap = @splat(@splat(0));

    for (types, 0..) |block_type, g| {
        const mixed: usize = if (block_type == .short) mixed_long else 0;
        var lines: [granule_len]f32 = undefined;
        forward(
            &forward_state,
            input[g * granule_len ..][0..granule_len],
            &lines,
            block_type,
            mixed,
        );
        // The encoder's last step before quantization is the decoder's first
        // after it, applied the other way.
        const long_subbands: usize = if (block_type == .short) mixed else subbands;
        expandAlias(&lines, long_subbands);

        var spectrum = lines;
        imdct.reduceAlias(&spectrum, long_subbands);
        _ = imdct.hybridSynthesis(&spectrum, &overlap, block_type, mixed);
        @memcpy(output[g * granule_len ..][0..granule_len], &spectrum);
    }

    var signal: f64 = 0;
    var noise: f64 = 0;
    // One granule of delay: the window reaches back over the previous one, so
    // what comes out of granule g is what went into granule g-1.
    for (1..granules) |g| {
        for (0..granule_len) |i| {
            const want = input[(g - 1) * granule_len + i];
            const got = output[g * granule_len + i];
            signal += @as(f64, want) * want;
            noise += @as(f64, got - want) * (got - want);
        }
    }
    return 10 * std.math.log10(signal / @max(noise, 1e-30));
}

test "a run of long blocks survives the transform and its inverse" {
    const snr = try roundTrip(&(.{.normal} ** 8), 0, 0x1d);
    testing.expect(snr > 80) catch |err| {
        std.debug.print("long block round trip {d:.2} dB\n", .{snr});
        return err;
    };
}

test "a run of short blocks survives the transform and its inverse" {
    const snr = try roundTrip(&(.{.short} ** 8), 0, 0x2e);
    testing.expect(snr > 80) catch |err| {
        std.debug.print("short block round trip {d:.2} dB\n", .{snr});
        return err;
    };
}

test "a run of mixed blocks survives the transform and its inverse" {
    const snr = try roundTrip(&(.{.short} ** 8), 2, 0x3f);
    testing.expect(snr > 80) catch |err| {
        std.debug.print("mixed block round trip {d:.2} dB\n", .{snr});
        return err;
    };
}

test "switching between long and short blocks reconstructs across the join" {
    // The start and stop windows are asymmetric bridges and do not
    // reconstruct against copies of themselves: a start window's tapered half
    // is shaped to meet a short window, and only a short window.  So the only
    // meaningful test of them is the sequence they exist for, which is what a
    // granule with a transient in it actually produces.
    const sequence = [_]BlockType{
        .normal, .normal, .start, .short, .short, .stop, .normal, .normal,
    };
    const snr = try roundTrip(&sequence, 0, 0x40);
    testing.expect(snr > 80) catch |err| {
        std.debug.print("window switching round trip {d:.2} dB\n", .{snr});
        return err;
    };
}

test "aliasing is put back exactly as it was taken out" {
    var prng = std.Random.DefaultPrng.init(0x5a);
    const random = prng.random();
    var spectrum: [granule_len]f32 = undefined;
    for (&spectrum) |*value| value.* = random.float(f32) - 0.5;
    const original = spectrum;

    expandAlias(&spectrum, subbands);
    imdct.reduceAlias(&spectrum, subbands);
    for (original, spectrum) |want, got| {
        try testing.expectApproxEqAbs(want, got, 1e-5);
    }
}
