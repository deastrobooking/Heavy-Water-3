// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The psychoacoustic model: what the listener will not hear.
//!
//! The encoders have a budget and somewhere to spend it, and this is what
//! tells them where.  It produces, for each part of the spectrum, how much
//! quantization noise can be left there without anyone noticing.
//!
//! The first version of this decided how tonal a band was from its spectral
//! flatness, which is a reasonable guess and not much more: flatness cannot
//! tell a steady tone from a burst of noise that happens to be concentrated,
//! and it was computed per band, so a single tone in a wide band was averaged
//! against everything beside it.  Tonality is the thing this kind of model
//! most needs to get right -- a tone hides far less noise than a noise of the
//! same energy, by fifteen decibels or more -- so getting it from a better
//! measure is where the quality is.
//!
//! This is the shape of ISO/IEC 11172-3's informative Psychoacoustic Model 2,
//! whose idea is that **tonality is predictability**.  A steady sinusoid
//! advances its phase by the same amount every frame and holds its magnitude,
//! so the next frame can be extrapolated from the last two almost exactly.
//! Noise cannot be extrapolated at all.  So rather than ask what a band's
//! spectrum looks like, this asks how well each bin was predicted, which is a
//! per-bin measure and a far sharper one.
//!
//! Written from the published description rather than ported.  The models in
//! the encoders worth learning from -- LAME's above all -- are LGPL, and this
//! project is MIT; but a psychoacoustic model is not normative, no decoder
//! ever sees it, and the algorithm is in the literature.  What is implemented
//! from a description is not a derivative work of anyone's code.
//!
//! The constants at the bottom of the file are tuning, not specification.
//! They are set to values the literature gives and then moved by measurement;
//! nothing about them is authoritative and none of them can make a stream
//! invalid.

const std = @import("std");

const fft = @import("fft.zig");

/// Samples the model looks at once.
pub const window_len = 1024;
const bins = window_len / 2 + 1;

pub const subbands = 32;

/// Threshold calculation partitions: about a third of a critical band each,
/// which is fine enough to place a threshold and coarse enough that spreading
/// between them is a small matrix.
pub const max_partitions = 80;

/// Full scale, in dB SPL, under the usual convention for 16-bit audio.
const full_scale_db = 96.0;

fn barkOf(hz: f64) f64 {
    return 13.0 * std.math.atan(0.00076 * hz) +
        3.5 * std.math.atan((hz / 7500.0) * (hz / 7500.0));
}

/// Terhardt's threshold in quiet, in dB SPL.
fn quietOf(hz: f64) f64 {
    const khz = @max(hz, 20.0) / 1000.0;
    const value = 3.64 * std.math.pow(f64, khz, -0.8) -
        6.5 * @exp(-0.6 * (khz - 3.3) * (khz - 3.3)) +
        0.001 * std.math.pow(f64, khz, 4.0);
    return std.math.clamp(value, -20.0, full_scale_db);
}

/// Model 2's spreading function, in decibels, for a maskee `dz` critical
/// bands from the masker.
///
/// Schroeder's curve with an extra term that steepens the fall below the
/// masker: masking spreads upwards in frequency far more than downwards, and
/// the plain curve does not lean hard enough.
fn spreadingOf(dz: f64) f64 {
    const shifted = dz - 0.5;
    const lean = 8.0 * @min(shifted * shifted - 2.0 * shifted, 0.0);
    const x = dz + 0.474;
    return lean + 15.811389 + 7.5 * x - 17.5 * @sqrt(1.0 + x * x);
}

/// What one call to `analyze` worked out.
pub const Result = struct {
    /// Masking threshold of each partition, as a power on the same scale as
    /// the spectrum.
    threshold: [max_partitions]f64 = @splat(0),
    /// Signal energy of each partition.
    energy: [max_partitions]f64 = @splat(0),
    /// Perceptual entropy: roughly the bits needed to code the frame with its
    /// noise under the threshold everywhere.  A transient makes this jump,
    /// which is what a block-type decision watches.
    entropy: f64 = 0,
};

pub const Model = struct {
    sample_rate: u32,
    partition_count: usize,
    /// Which partition each transform bin falls in.
    partition_of_bin: [bins]u8,
    /// Where each partition starts and ends, in bins.
    partition_start: [max_partitions + 1]u16,
    /// Threshold in quiet of each partition, as a power.
    quiet: [max_partitions]f64,
    /// How much of a masker in one partition reaches another, as a gain, and
    /// the total each row applies.
    spreading: [max_partitions][max_partitions]f64,
    spread_norm: [max_partitions]f64,

    /// The last two frames' magnitude and phase, which is what makes a
    /// prediction possible.
    previous: [2][bins]f64,
    previous_phase: [2][bins]f64,
    /// The last two frames' thresholds, for holding pre-echo down.
    previous_threshold: [2][max_partitions]f64,
    /// Frames seen, so that the first two do not predict from nothing.
    seen: usize,

    pub fn init(sample_rate: u32) Model {
        var self: Model = undefined;
        self.sample_rate = sample_rate;
        self.previous = @splat(@splat(0));
        self.previous_phase = @splat(@splat(0));
        self.previous_threshold = @splat(@splat(0));
        self.seen = 0;

        const nyquist = @as(f64, @floatFromInt(sample_rate)) / 2.0;
        var highest: usize = 0;
        for (0..bins) |k| {
            const hz = nyquist * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(bins - 1));
            // Three partitions to a critical band.
            const partition: usize = @min(
                @as(usize, @intFromFloat(@max(barkOf(hz) * 3.0, 0))),
                max_partitions - 1,
            );
            self.partition_of_bin[k] = @intCast(partition);
            highest = @max(highest, partition);
        }
        self.partition_count = highest + 1;

        // Partition bounds, and the quietest bin in each, since a partition
        // is only as maskable as its most sensitive part.
        self.partition_start = @splat(0);
        self.quiet = @splat(std.math.inf(f64));
        var at: usize = 0;
        for (0..self.partition_count) |partition| {
            self.partition_start[partition] = @intCast(at);
            while (at < bins and self.partition_of_bin[at] == partition) : (at += 1) {
                const hz = nyquist * @as(f64, @floatFromInt(at)) / @as(f64, @floatFromInt(bins - 1));
                const power = std.math.pow(f64, 10.0, (quietOf(hz) - full_scale_db) / 10.0);
                self.quiet[partition] = @min(self.quiet[partition], power);
            }
            self.partition_start[partition + 1] = @intCast(at);
            if (self.quiet[partition] == std.math.inf(f64)) self.quiet[partition] = 1.0;
        }

        for (0..max_partitions) |to| {
            var total: f64 = 0;
            for (0..max_partitions) |from| {
                const dz = (@as(f64, @floatFromInt(to)) - @as(f64, @floatFromInt(from))) / 3.0;
                const db = spreadingOf(dz);
                const gain = if (db < -100) 0 else std.math.pow(f64, 10.0, db / 10.0);
                self.spreading[to][from] = gain;
                if (from < self.partition_count) total += gain;
            }
            self.spread_norm[to] = @max(total, 1e-30);
        }
        return self;
    }

    pub fn reset(self: *Model) void {
        self.previous = @splat(@splat(0));
        self.previous_phase = @splat(@splat(0));
        self.previous_threshold = @splat(@splat(0));
        self.seen = 0;
    }

    /// Look at one window of input and work out what it can hide.
    ///
    /// Call this at a fixed hop: the prediction that measures tonality
    /// compares this frame against the last two, and only means anything if
    /// they are the same distance apart every time.
    pub fn analyze(self: *Model, input: *const [window_len]f32, out: *Result) void {
        var re: [window_len]f64 = undefined;
        var im: [window_len]f64 = @splat(0);
        const gain = 4.0 / @as(f64, @floatFromInt(window_len));
        for (0..window_len) |k| {
            const phase = 2.0 * std.math.pi * @as(f64, @floatFromInt(k)) /
                @as(f64, @floatFromInt(window_len));
            const w = 0.5 - 0.5 * @cos(phase);
            re[k] = @as(f64, input[k]) * w * gain;
        }
        fft.transform(window_len, &re, &im);

        // Magnitude and phase, which is the form prediction works in.
        var magnitude: [bins]f64 = undefined;
        var phase: [bins]f64 = undefined;
        for (0..bins) |k| {
            magnitude[k] = @sqrt(re[k] * re[k] + im[k] * im[k]);
            phase[k] = std.math.atan2(im[k], re[k]);
        }

        // How badly each bin was predicted by the two before it.  A steady
        // tone advances its phase by a constant and holds its magnitude, so
        // extrapolating the last two lands almost exactly on this one and the
        // measure is near zero; noise lands anywhere and it approaches one.
        var unpredictability: [bins]f64 = undefined;
        for (0..bins) |k| {
            if (self.seen < 2) {
                // Nothing to predict from.  Assume the worst about tonality,
                // which is the safe direction: it asks for more accuracy
                // rather than less.
                unpredictability[k] = 0;
                continue;
            }
            const predicted_magnitude = 2.0 * self.previous[0][k] - self.previous[1][k];
            const predicted_phase = 2.0 * self.previous_phase[0][k] - self.previous_phase[1][k];
            const dr = magnitude[k] * @cos(phase[k]) -
                predicted_magnitude * @cos(predicted_phase);
            const di = magnitude[k] * @sin(phase[k]) -
                predicted_magnitude * @sin(predicted_phase);
            const distance = @sqrt(dr * dr + di * di);
            const scale = magnitude[k] + @abs(predicted_magnitude);
            unpredictability[k] = if (scale > 1e-30)
                std.math.clamp(distance / scale, 0.0, 1.0)
            else
                0.0;
        }

        // Gather into partitions, weighting unpredictability by energy so
        // that a loud tone in a partition is not talked out of its tonality
        // by the quiet noise beside it.
        var energy: [max_partitions]f64 = @splat(0);
        var weighted: [max_partitions]f64 = @splat(0);
        for (1..bins) |k| {
            const partition = self.partition_of_bin[k];
            const power = magnitude[k] * magnitude[k];
            energy[partition] += power;
            weighted[partition] += unpredictability[k] * power;
        }

        // Spread both across neighbouring partitions.
        var spread_energy: [max_partitions]f64 = @splat(0);
        var spread_weighted: [max_partitions]f64 = @splat(0);
        for (0..self.partition_count) |to| {
            var e: f64 = 0;
            var c: f64 = 0;
            for (0..self.partition_count) |from| {
                e += energy[from] * self.spreading[to][from];
                c += weighted[from] * self.spreading[to][from];
            }
            spread_energy[to] = e;
            spread_weighted[to] = c;
        }

        out.entropy = 0;
        for (0..self.partition_count) |partition| {
            const e = spread_energy[partition];
            out.energy[partition] = energy[partition];
            if (e <= 0) {
                out.threshold[partition] = self.quiet[partition];
                continue;
            }

            // Tonality from the spread, energy-weighted unpredictability.
            const ratio = std.math.clamp(spread_weighted[partition] / e, 1e-30, 1.0);
            const tonality = std.math.clamp(-0.299 - 0.43 * @log(ratio), 0.0, 1.0);

            // A tone needs its noise much further down than a noise does.
            const required = tonality * tone_masking_noise +
                (1.0 - tonality) * noise_masking_tone;
            const level = e / self.spread_norm[partition];
            var threshold = level * std.math.pow(f64, 10.0, -required / 10.0);

            // Pre-echo: hold the threshold near what the last frames allowed,
            // so that a loud frame cannot license noise across the quiet one
            // before it -- which is exactly what a listener hears in front of
            // a sharp attack.
            if (self.seen >= 2) {
                const recent = @min(
                    pre_echo_reach * self.previous_threshold[0][partition],
                    pre_echo_reach_2 * self.previous_threshold[1][partition],
                );
                if (recent > 0) threshold = @min(threshold, @max(recent, level * 1e-6));
            }
            threshold = @max(threshold, self.quiet[partition]);
            out.threshold[partition] = threshold;

            // Perceptual entropy, as the standard frames it: the bits a
            // partition needs are the log of how far its energy stands above
            // what may be hidden there.
            if (energy[partition] > threshold) {
                const width: f64 = @floatFromInt(self.partition_start[partition + 1] -
                    self.partition_start[partition]);
                out.entropy += width * std.math.log2(energy[partition] / threshold);
            }
        }

        self.previous_threshold[1] = self.previous_threshold[0];
        self.previous_threshold[0] = out.threshold;
        self.previous[1] = self.previous[0];
        self.previous[0] = magnitude;
        self.previous_phase[1] = self.previous_phase[0];
        self.previous_phase[0] = phase;
        self.seen += 1;
    }

    /// Signal-to-mask ratio per subband, in decibels, for Layer II.
    pub fn signalToMask(self: *const Model, out_result: *const Result, out: *[subbands]f32) void {
        const per_subband = (window_len / 2) / subbands;
        for (0..subbands) |sb| {
            var signal: f64 = 0;
            var mask = std.math.inf(f64);
            for (0..per_subband) |i| {
                const k = sb * per_subband + i;
                if (k == 0) continue;
                const partition = self.partition_of_bin[k];
                signal += out_result.energy[partition] /
                    @max(@as(f64, @floatFromInt(self.partition_start[partition + 1] -
                        self.partition_start[partition])), 1);
                mask = @min(mask, out_result.threshold[partition] /
                    @max(@as(f64, @floatFromInt(self.partition_start[partition + 1] -
                        self.partition_start[partition])), 1));
            }
            const ratio = 10.0 * std.math.log10(@max(signal, 1e-30) / @max(mask * per_subband, 1e-30));
            out[sb] = @floatCast(ratio);
        }
    }

    /// The share of a scalefactor band's energy that may be left as noise.
    ///
    /// A ratio rather than a power, because the two sides are on different
    /// scales: this model measures a windowed Fourier spectrum and the
    /// encoder quantizes an MDCT one, and nothing makes their units the same.
    /// What does carry across is the proportion -- how far below its own
    /// energy a band's noise has to sit -- which the caller then applies to
    /// the energy it actually measured.
    ///
    /// `starts` gives the first spectral line of each band and one past the
    /// last, in a spectrum of `lines` lines; the transform's bins are mapped
    /// onto that.
    pub fn maskToSignalPerBand(
        self: *const Model,
        result: *const Result,
        starts: []const u16,
        lines: usize,
        out: []f32,
    ) void {
        std.debug.assert(out.len + 1 <= starts.len);
        const half = window_len / 2;
        for (out, 0..) |*value, band| {
            const from = @as(usize, starts[band]) * half / lines;
            const to = @max(@as(usize, starts[band + 1]) * half / lines, from + 1);

            var energy: f64 = 0;
            var threshold: f64 = 0;
            for (from..@min(to, half)) |k| {
                if (k == 0) continue;
                const partition = self.partition_of_bin[k];
                const width: f64 = @floatFromInt(@max(
                    self.partition_start[partition + 1] - self.partition_start[partition],
                    1,
                ));
                energy += result.energy[partition] / width;
                threshold += result.threshold[partition] / width;
            }
            // A band the model saw nothing in is left to be judged on its own
            // energy alone, which is what the caller does with a ratio of one.
            value.* = if (energy > 1e-30)
                @floatCast(std.math.clamp(threshold / energy, 1e-12, 1.0))
            else
                1.0;
        }
    }
};

// ----------------------------------------------------------- tuning --------

/// How far below a tonal masker its noise has to sit, and below a noise-like
/// one, in decibels.  A tone is a far worse masker than a noise of the same
/// energy, which is the single most important thing the model knows and the
/// reason measuring tonality well is worth the trouble.
const tone_masking_noise = 24.5;
const noise_masking_tone = 6.0;

/// How much the threshold may rise above what the last frames allowed.  This
/// is what keeps a loud frame from licensing noise across the quiet one in
/// front of it, which is the artefact a listener notices most.
const pre_echo_reach = 2.0;
const pre_echo_reach_2 = 16.0;

const testing = std.testing;

fn steadyTone(hz: f64, amplitude: f64, rate: u32, at: usize, out: *[window_len]f32) void {
    for (out, 0..) |*value, n| {
        const phase = 2.0 * std.math.pi * hz * @as(f64, @floatFromInt(at + n)) /
            @as(f64, @floatFromInt(rate));
        value.* = @floatCast(amplitude * @sin(phase));
    }
}

/// Run the model over several hops of a signal and return the last result,
/// so that the prediction has history to work from.
fn settle(model: *Model, comptime fill: anytype, hops: usize, hop: usize) Result {
    var result: Result = .{};
    for (0..hops) |h| {
        var input: [window_len]f32 = undefined;
        fill(h * hop, &input);
        model.analyze(&input, &result);
    }
    return result;
}

test "a steady tone reads as tonal and noise does not" {
    // The whole point of the model.  Both signals are given the same energy
    // in the same place; what separates them is that one can be predicted
    // from its own past and the other cannot, and the thresholds have to
    // come out far apart because of it.
    const rate = 44100;
    const hop = 576;

    var tone_model = Model.init(rate);
    const tone = settle(&tone_model, struct {
        fn f(at: usize, out: *[window_len]f32) void {
            steadyTone(3000, 0.5, rate, at, out);
        }
    }.f, 8, hop);

    var noise_model = Model.init(rate);
    const noise = settle(&noise_model, struct {
        fn f(at: usize, out: *[window_len]f32) void {
            // Narrow band noise around 3 kHz: the same part of the spectrum
            // as the tone, so the comparison is about predictability alone.
            var local = std.Random.DefaultPrng.init(0x9015e +% at);
            const random = local.random();
            var previous: f64 = 0;
            for (out, 0..) |*value, n| {
                const white = random.float(f64) * 2 - 1;
                previous = 0.5 * previous + 0.5 * white;
                const carrier = @sin(2.0 * std.math.pi * 3000.0 * @as(f64, @floatFromInt(n)) / rate);
                value.* = @floatCast(0.5 * previous * carrier * 2.0);
            }
        }
    }.f, 8, hop);

    // Find the partition holding 3 kHz and compare how much noise each
    // signal is allowed to hide there, relative to its own energy.
    const model = Model.init(rate);
    const bin = @as(usize, @intFromFloat(3000.0 / (rate / 2.0) * (bins - 1)));
    const partition = model.partition_of_bin[bin];

    const tone_ratio = tone.energy[partition] / tone.threshold[partition];
    const noise_ratio = noise.energy[partition] / noise.threshold[partition];
    // The tone has to demand more accuracy than the noise: a larger ratio of
    // signal to what may be hidden under it.
    testing.expect(tone_ratio > noise_ratio * 4) catch |err| {
        std.debug.print(
            "tone demands {d:.1}, noise demands {d:.1}; expected the tone to ask far more\n",
            .{ 10 * std.math.log10(tone_ratio), 10 * std.math.log10(noise_ratio) },
        );
        return err;
    };
}

test "silence asks for nothing and stays at the threshold of hearing" {
    var model = Model.init(44100);
    const result = settle(&model, struct {
        fn f(at: usize, out: *[window_len]f32) void {
            _ = at;
            @memset(out, 0);
        }
    }.f, 6, 576);

    for (0..model.partition_count) |partition| {
        try testing.expectEqual(@as(f64, 0), result.energy[partition]);
        try testing.expectEqual(model.quiet[partition], result.threshold[partition]);
    }
    try testing.expectEqual(@as(f64, 0), result.entropy);
}

test "a transient raises the perceptual entropy" {
    // What a block-type decision watches: the entropy of a frame with an
    // attack in it stands well above that of the steady signal before it.
    const rate = 44100;
    var model = Model.init(rate);
    var steady: f64 = 0;
    var burst: f64 = 0;

    for (0..8) |h| {
        var input: [window_len]f32 = undefined;
        steadyTone(1000, 0.2, rate, h * 576, &input);
        var result: Result = .{};
        model.analyze(&input, &result);
        steady = result.entropy;
    }
    {
        var input: [window_len]f32 = undefined;
        steadyTone(1000, 0.2, rate, 8 * 576, &input);
        // A sharp attack in the second half of the window.
        for (window_len / 2..window_len) |n| input[n] = if (n % 7 == 0) 0.9 else -0.9;
        var result: Result = .{};
        model.analyze(&input, &result);
        burst = result.entropy;
    }
    testing.expect(burst > steady * 2) catch |err| {
        std.debug.print("steady entropy {d:.1}, transient {d:.1}\n", .{ steady, burst });
        return err;
    };
}

test "the threshold in quiet still decides for a very faint signal" {
    const rate = 44100;
    var model = Model.init(rate);
    const result = settle(&model, struct {
        fn f(at: usize, out: *[window_len]f32) void {
            // A hundred dB below full scale, which is under the threshold of
            // hearing at 1 kHz.
            steadyTone(1000, 1e-5, rate, at, out);
        }
    }.f, 6, 576);

    const bin = @as(usize, @intFromFloat(1000.0 / (rate / 2.0) * (bins - 1)));
    const partition = model.partition_of_bin[bin];
    try testing.expect(result.threshold[partition] >= model.quiet[partition]);
    try testing.expect(result.energy[partition] < result.threshold[partition]);
}

test "every supported sampling rate builds a model" {
    for ([_]u32{ 32000, 44100, 48000, 16000, 22050, 24000 }) |rate| {
        var model = Model.init(rate);
        try testing.expect(model.partition_count > 30);
        try testing.expect(model.partition_count <= max_partitions);

        var input: [window_len]f32 = undefined;
        steadyTone(1000, 0.3, rate, 0, &input);
        var result: Result = .{};
        model.analyze(&input, &result);
        for (0..model.partition_count) |partition| {
            try testing.expect(std.math.isFinite(result.threshold[partition]));
            try testing.expect(result.threshold[partition] > 0);
        }
        try testing.expect(std.math.isFinite(result.entropy));

        var smr: [subbands]f32 = undefined;
        model.signalToMask(&result, &smr);
        for (smr) |value| try testing.expect(std.math.isFinite(value));
    }
}
