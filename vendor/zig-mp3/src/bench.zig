// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Where the decoder's time goes.
//!
//! Two measurements, because one alone misleads.  The first decodes a real
//! stream end to end, which is the number that matters.  The second times the
//! filterbank stages on their own: they are straight-line arithmetic over
//! fixed-size buffers with no data-dependent branching, so timing them on
//! arbitrary input measures exactly what they cost on real input.  What the
//! two do not account for between them is the bit-level work -- Huffman
//! decoding, scalefactors, requantization -- which is data dependent and is
//! reported as the remainder.

const std = @import("std");

const imdct = @import("imdct.zig");
const mp3 = @import("root.zig");
const synthesis = @import("synthesis.zig");

/// The streams measured end to end, one per layer.  Layer III is the one that
/// matters and is broken down by stage below; the other two are here because
/// they share the filterbank and nothing else, so a change to it should move
/// all three and a change to Layer III alone should move only the first.
const Clip = struct {
    name: []const u8,
    bytes: []const u8,
};

const clips = [_]Clip{
    .{ .name = "Layer III", .bytes = @embedFile("testdata/stereo44.mp3") },
    .{ .name = "Layer II", .bytes = @embedFile("testdata/layer2.mp2") },
    .{ .name = "Layer I", .bytes = @embedFile("testdata/layer1.mp1") },
};

/// The clip the stage breakdown belongs to.
const clip = clips[0].bytes;

/// Long enough that the timer's resolution and the odd scheduling hiccup do
/// not matter, short enough to run in a couple of seconds.
const stream_repeats = 1200;
const stage_repeats = 6000;
/// Each measurement is taken this many times and the best kept.
///
/// A mean is at the mercy of whatever else the machine is doing: another
/// build on another core will not make this code faster, only slower, so the
/// fastest run is the one least contaminated by anything else.
const attempts = 5;

const Measurement = struct {
    name: []const u8,
    /// Nanoseconds per granule and channel, which is the unit every stage of
    /// the decoder works in.
    per_granule_ns: f64,
};

/// Zig 0.16 has no free-standing timer; monotonic time comes from `Io`.
/// `.awake` is the clock that does not run while the machine is suspended,
/// which is the closest thing to a stopwatch.
const Stopwatch = struct {
    io: std.Io,
    start: std.Io.Timestamp,

    fn begin(io: std.Io) Stopwatch {
        return .{ .io = io, .start = .now(io, .awake) };
    }

    fn elapsedNs(self: Stopwatch) f64 {
        const now: std.Io.Timestamp = .now(self.io, .awake);
        return @floatFromInt(self.start.durationTo(now).nanoseconds);
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var out: [4096]u8 = undefined;
    var used: usize = 0;

    // ---------------------------------------------------------- end to end --
    var buffer: mp3.FrameBuffer = undefined;
    var total_per_granule: f64 = 0;

    for (clips) |entry| {
        var samples: u64 = 0;
        var frames: u64 = 0;
        var sample_rate: u32 = 0;
        var channels: u8 = 0;

        // Once outside the timer, so that the first pass paying for cold
        // caches and page faults does not land in the measurement.
        decodeOnce(entry.bytes, &buffer, &samples, &frames, &sample_rate, &channels);

        var elapsed_ns: f64 = std.math.inf(f64);
        for (0..attempts) |attempt| {
            samples = 0;
            frames = 0;
            const watch = Stopwatch.begin(io);
            for (0..stream_repeats) |_| {
                decodeOnce(entry.bytes, &buffer, &samples, &frames, &sample_rate, &channels);
            }
            const taken = watch.elapsedNs();
            if (attempt == 0 or taken < elapsed_ns) elapsed_ns = taken;
        }

        const seconds = elapsed_ns / std.time.ns_per_s;
        const audio_seconds =
            @as(f64, @floatFromInt(samples)) / @as(f64, @floatFromInt(sample_rate));
        const bytes = @as(f64, @floatFromInt(entry.bytes.len)) * stream_repeats;
        const produced = @as(f64, @floatFromInt(samples * channels));

        used += (try std.fmt.bufPrint(out[used..],
            \\{s}: {d} Hz, {d} channels, {d} frames
            \\  {d:.2} s of audio in {d:.3} s
            \\  {d:.0}x real time
            \\  {d:.1} MB/s of bitstream, {d:.1} M samples/s
            \\
        , .{
            entry.name,
            sample_rate,
            channels,
            frames / stream_repeats,
            audio_seconds,
            seconds,
            audio_seconds / seconds,
            bytes / seconds / (1024 * 1024),
            produced / seconds / 1_000_000,
        })).len;

        // A granule is 576 samples of one channel, and is the unit the stage
        // breakdown below is quoted in.  Only Layer III has granules.
        if (std.mem.eql(u8, entry.name, "Layer III")) {
            const granules = produced / 576.0;
            total_per_granule = elapsed_ns / granules;
            used += (try std.fmt.bufPrint(
                out[used..],
                "  {d:.0} ns per granule and channel\n",
                .{total_per_granule},
            )).len;
        }
        used += (try std.fmt.bufPrint(out[used..], "\n", .{})).len;
    }

    // ------------------------------------------------------------- stages ---
    const stages = [_]Measurement{
        .{ .name = "polyphase synthesis", .per_granule_ns = timePolyphase(io) },
        .{ .name = "IMDCT and windowing", .per_granule_ns = timeImdct(io, .normal) },
        .{ .name = "  the same, short blocks", .per_granule_ns = timeImdct(io, .short) },
        .{ .name = "alias reduction", .per_granule_ns = timeAlias(io) },
        .{ .name = "frequency inversion", .per_granule_ns = timeInversion(io) },
    };

    used += (try std.fmt.bufPrint(out[used..], "per granule and channel:\n", .{})).len;
    var accounted: f64 = 0;
    for (stages) |stage| {
        // The short block variant is shown for comparison, not counted: a
        // granule is one or the other, and long blocks are the common case.
        const counted = !std.mem.startsWith(u8, stage.name, "  ");
        if (counted) accounted += stage.per_granule_ns;
        used += (try std.fmt.bufPrint(out[used..], "  {s: <26}{d:7.0} ns  {d:5.1}%\n", .{
            stage.name,
            stage.per_granule_ns,
            stage.per_granule_ns / total_per_granule * 100,
        })).len;
    }
    const rest = total_per_granule - accounted;
    used += (try std.fmt.bufPrint(out[used..],
        \\  {s: <26}{d:7.0} ns  {d:5.1}%
        \\  {s: <26}{d:7.0} ns
        \\
    , .{
        "everything else",
        rest,
        rest / total_per_granule * 100,
        "total",
        total_per_granule,
    })).len;

    try std.Io.File.stdout().writeStreamingAll(io, out[0..used]);
}

fn decodeOnce(
    bytes: []const u8,
    buffer: *mp3.FrameBuffer,
    samples: *u64,
    frames: *u64,
    sample_rate: *u32,
    channels: *u8,
) void {
    var decoder = mp3.Decoder.init();
    var offset: usize = 0;
    while (offset < bytes.len) {
        switch (decoder.next(bytes[offset..], buffer, .{ .end_of_input = true })) {
            .need_more => break,
            .skipped => |n| offset += n,
            .frame => |frame| {
                offset += frame.consumed;
                samples.* += frame.samples;
                frames.* += 1;
                sample_rate.* = frame.sample_rate;
                channels.* = frame.channels;
                // Keep the optimizer from deciding none of this was needed.
                keep(buffer);
            },
        }
    }
}

/// Keep the optimizer from deleting the work that produced a buffer.
///
/// Handing `doNotOptimizeAway` one element only pins that element: the stores
/// to the rest are dead, and LLVM will happily delete the arithmetic behind
/// them, which makes a stage look several times cheaper than it is.  Passing
/// the address instead clobbers memory and keeps the lot.
fn keep(buffer: anytype) void {
    std.mem.doNotOptimizeAway(buffer);
}

fn spectrum(seed: u64) [576]f32 {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var out: [576]f32 = undefined;
    for (&out) |*value| value.* = random.float(f32) - 0.5;
    return out;
}

fn timePolyphase(io: std.Io) f64 {
    var state = synthesis.State{};
    var input = spectrum(1);
    // Stride two, because the stream being decoded is stereo and that is the
    // path it takes; stride one stores a whole vector at a time and is not
    // what the measurement is meant to represent.
    var out: [2 * 576]f32 = undefined;
    synthesis.synthesize(&state, &input, &out, 2, synthesis.subbands);

    var best: f64 = std.math.inf(f64);
    for (0..attempts) |_| {
        const watch = Stopwatch.begin(io);
        for (0..stage_repeats) |_| {
            synthesis.synthesize(&state, &input, &out, 2, synthesis.subbands);
            keep(&out);
        }
        best = @min(best, watch.elapsedNs() / stage_repeats);
    }
    return best;
}

fn timeImdct(io: std.Io, block_type: @import("side_info.zig").BlockType) f64 {
    var overlap: imdct.Overlap = @splat(@splat(0));
    const source = spectrum(2);
    var scratch: [576]f32 = source;
    _ = imdct.hybridSynthesis(&scratch, &overlap, block_type, 0);

    var best: f64 = std.math.inf(f64);
    for (0..attempts) |_| {
        const watch = Stopwatch.begin(io);
        for (0..stage_repeats) |_| {
            scratch = source;
            _ = imdct.hybridSynthesis(&scratch, &overlap, block_type, 0);
            keep(&scratch);
        }
        // The copy is part of the loop but not of the stage; a few hundred
        // bytes against tens of thousands of multiply-adds is noise.
        best = @min(best, watch.elapsedNs() / stage_repeats);
    }
    return best;
}

fn timeAlias(io: std.Io) f64 {
    const source = spectrum(3);
    var scratch: [576]f32 = source;
    var best: f64 = std.math.inf(f64);
    for (0..attempts) |_| {
        const watch = Stopwatch.begin(io);
        for (0..stage_repeats) |_| {
            scratch = source;
            imdct.reduceAlias(&scratch, 32);
            keep(&scratch);
        }
        best = @min(best, watch.elapsedNs() / stage_repeats);
    }
    return best;
}

fn timeInversion(io: std.Io) f64 {
    var scratch = spectrum(4);
    var best: f64 = std.math.inf(f64);
    for (0..attempts) |_| {
        const watch = Stopwatch.begin(io);
        for (0..stage_repeats) |_| {
            imdct.invertFrequency(&scratch);
            keep(&scratch);
        }
        best = @min(best, watch.elapsedNs() / stage_repeats);
    }
    return best;
}
