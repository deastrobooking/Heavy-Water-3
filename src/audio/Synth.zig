//! Procedural sound design: every effect and ambient loop is synthesized at startup from a few
//! oscillators, seeded noise and envelopes, so the game ships no audio files yet. Output is mono
//! f32 at `rate`, peak-normalized; loops crossfade their tail into their head so they repeat
//! without a click.
const std = @import("std");
const Synth = @This();

pub const rate: u32 = 48_000;
const tau = 2 * std.math.pi;

pub const Sound = enum {
    ui_move,
    ui_confirm,
    ui_back,
    ui_error,
    purchase,
    talk_blip,
    footstep,
    land,
    jump,
    dash,
    grapple,
    salvage,
    vault,
    restock,
    zap,
    slash,
    impact,
    boom,
    hive_zap,
    pickup,
    hurt,
    // Loops.
    wind,
    jet,
    canopy,
    engine,

    pub fn loops(s: Sound) bool {
        return switch (s) {
            .wind, .jet, .canopy, .engine => true,
            else => false,
        };
    }
};
pub const sound_count = @typeInfo(Sound).@"enum".fields.len;

/// Deterministic white noise (xorshift), in [-1, 1].
const Noise = struct {
    state: u64,
    fn next(self: *Noise) f32 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        return @as(f32, @floatFromInt(self.state >> 40)) / @as(f32, 1 << 23) - 1;
    }
};

/// One-pole low-pass: `amount` near 0 is dark, near 1 passes everything.
const Lowpass = struct {
    y: f32 = 0,
    fn step(self: *Lowpass, x: f32, amount: f32) f32 {
        self.y += amount * (x - self.y);
        return self.y;
    }
};

fn seconds(n: usize) f32 {
    return @as(f32, @floatFromInt(n)) / @as(f32, @floatFromInt(rate));
}

fn frames(duration: f32) usize {
    return @intFromFloat(duration * @as(f32, @floatFromInt(rate)));
}

/// Attack then exponential decay, normalized time `t` in seconds.
fn pluck(t: f32, attack: f32, decay: f32) f32 {
    if (t < attack) return t / attack;
    return @exp(-(t - attack) / decay);
}

fn tone(out: []f32, from: f32, to: f32, decay: f32, harmonics: []const f32) void {
    var phase: f32 = 0;
    for (out, 0..) |*s, i| {
        const t = seconds(i);
        const k = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(out.len));
        const f = from + (to - from) * k;
        phase += f / @as(f32, @floatFromInt(rate));
        var v: f32 = 0;
        for (harmonics, 1..) |h, n| v += h * @sin(tau * phase * @as(f32, @floatFromInt(n)));
        s.* += v * pluck(t, 0.004, decay);
    }
}

fn bell(out: []f32, start: f32, f: f32, decay: f32, gain: f32) void {
    const first = frames(start);
    if (first >= out.len) return;
    // Slightly inharmonic partials read as metal and glass.
    const partials = [_][2]f32{ .{ 1, 1 }, .{ 2.76, 0.45 }, .{ 5.4, 0.22 }, .{ 8.93, 0.1 } };
    for (out[first..], 0..) |*s, i| {
        const t = seconds(i);
        var v: f32 = 0;
        for (partials) |p| v += p[1] * @sin(tau * f * p[0] * t) * @exp(-t * p[0] / (decay * 3));
        s.* += gain * v * pluck(t, 0.002, decay);
    }
}

/// Filtered noise with a pitch-like sweep of the filter and an envelope.
fn whoosh(out: []f32, seed: u64, open_from: f32, open_to: f32, attack: f32, decay: f32) void {
    var noise: Noise = .{ .state = seed };
    var low: Lowpass = .{};
    var low2: Lowpass = .{};
    for (out, 0..) |*s, i| {
        const k = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(out.len));
        const amount = open_from + (open_to - open_from) * k;
        const band = low.step(noise.next(), amount) - low2.step(noise.next(), amount * 0.25);
        s.* += band * pluck(seconds(i), attack, decay);
    }
}

fn thud(out: []f32, f: f32, decay: f32, gain: f32) void {
    var phase: f32 = 0;
    for (out, 0..) |*s, i| {
        const t = seconds(i);
        // The pitch drops as the body settles.
        phase += f * (1 + 1.5 * @exp(-t * 40)) / @as(f32, @floatFromInt(rate));
        s.* += gain * @sin(tau * phase) * pluck(t, 0.002, decay);
    }
}

fn normalize(out: []f32, peak: f32) void {
    var max: f32 = 0;
    for (out) |s| max = @max(max, @abs(s));
    if (max == 0) return;
    for (out) |*s| s.* *= peak / max;
}

/// Crossfades the last `fade` samples into the first, then drops them: a seamless loop.
fn makeLoop(buffer: []f32, fade: usize) []f32 {
    const n = buffer.len - fade;
    for (0..fade) |i| {
        const w = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(fade));
        buffer[i] = buffer[i] * w + buffer[n + i] * (1 - w);
    }
    return buffer[0..n];
}

/// Synthesizes `sound`; the caller owns the returned samples.
pub fn generate(allocator: std.mem.Allocator, sound: Sound) ![]f32 {
    const durations = [sound_count]f32{ 0.035, 0.12, 0.1, 0.16, 0.7, 0.03, 0.09, 0.2, 0.22, 0.26, 0.24, 0.9, 2.4, 0.9, 0.16, 0.22, 0.12, 0.9, 0.2, 0.35, 0.25, 6.25, 1.25, 8, 1.0 };
    const loop_fade = frames(0.25);
    const extra = if (sound.loops()) loop_fade else 0;
    const buffer = try allocator.alloc(f32, frames(durations[@intFromEnum(sound)]) + extra);
    errdefer allocator.free(buffer);
    @memset(buffer, 0);
    var out = buffer;
    switch (sound) {
        .ui_move => tone(out, 2200, 2000, 0.012, &.{ 1, 0.2 }),
        .ui_confirm => {
            tone(out[0..frames(0.06)], 660, 660, 0.03, &.{ 1, 0.3 });
            tone(out[frames(0.05)..], 990, 990, 0.04, &.{ 1, 0.3 });
        },
        .ui_back => tone(out, 520, 360, 0.04, &.{ 1, 0.25 }),
        .ui_error => tone(out, 190, 170, 0.06, &.{ 1, 0, 0.33, 0, 0.2 }),
        .purchase => for ([_]f32{ 1046.5, 1318.5, 1568 }, 0..) |f, i| bell(out, @as(f32, @floatFromInt(i)) * 0.07, f, 0.25, 1),
        .talk_blip => tone(out, 1400, 1300, 0.012, &.{ 1, 0.5 }),
        .footstep => {
            whoosh(out, 0x51ed, 0.35, 0.15, 0.002, 0.025);
            thud(out, 95, 0.03, 0.8);
        },
        .land => {
            whoosh(out, 0x1a2d, 0.3, 0.08, 0.002, 0.06);
            thud(out, 58, 0.08, 1.2);
        },
        .jump => whoosh(out, 0x7a11, 0.08, 0.5, 0.05, 0.08),
        .dash => whoosh(out, 0xda5, 0.6, 0.12, 0.01, 0.1),
        .grapple => {
            tone(out, 1800, 300, 0.09, &.{ 1, 0.5, 0.33, 0.25 });
            whoosh(out, 0x9a99, 0.5, 0.2, 0.005, 0.12);
        },
        .salvage => for ([_]f32{ 1567.98, 2093, 2637 }, 0..) |f, i| bell(out, @as(f32, @floatFromInt(i)) * 0.11, f, 0.35, 0.8),
        .vault => {
            // A rising open fifth over a low root: the seed vault wakes.
            for ([_]f32{ 130.81, 196, 261.63, 392, 523.25 }, 0..) |f, i| {
                var phase: f32 = 0;
                for (out, 0..) |*s, k| {
                    const t = seconds(k);
                    phase += f / @as(f32, @floatFromInt(rate));
                    const swell = @min(1, t / (0.4 + 0.15 * @as(f32, @floatFromInt(i)))) * @exp(-@max(0, t - 1.2) / 0.5);
                    s.* += 0.3 * @sin(tau * phase) * swell;
                }
            }
            bell(out, 0.35, 1046.5, 0.6, 0.5);
        },
        .restock => {
            bell(out, 0, 784, 0.3, 1);
            bell(out, 0.18, 1046.5, 0.4, 1);
        },
        .zap => {
            // A bright descending square-ish chirp.
            tone(out, 1400, 380, 0.05, &.{ 1, 0, 0.33, 0, 0.2, 0, 0.14 });
            whoosh(out, 0x2a9, 0.7, 0.3, 0.001, 0.03);
        },
        .slash => {
            whoosh(out, 0x51a5, 0.15, 0.7, 0.03, 0.07);
            bell(out, 0.02, 1760, 0.12, 0.35);
        },
        .impact => {
            whoosh(out, 0x1b9a, 0.6, 0.2, 0.001, 0.03);
            thud(out, 140, 0.04, 0.6);
        },
        .boom => {
            whoosh(out, 0xb00, 0.12, 0.03, 0.004, 0.25);
            thud(out, 48, 0.3, 1.4);
        },
        .hive_zap => {
            // Lower and detuned: the Hive sounds wrong on purpose.
            tone(out, 620, 210, 0.07, &.{ 1, 0.4, 0.5, 0, 0.3 });
            tone(out, 655, 230, 0.07, &.{ 0.6, 0, 0.3 });
        },
        .pickup => {
            bell(out, 0, 1318.5, 0.12, 0.8);
            bell(out, 0.07, 1975.5, 0.18, 0.8);
        },
        .hurt => {
            thud(out, 85, 0.07, 1.2);
            whoosh(out, 0x4d7, 0.4, 0.1, 0.002, 0.06);
        },
        .engine => {
            // A turbine hum: four fans' blade-pass tones over a breathy duct roar.
            var noise: Noise = .{ .state = 0xe9e };
            var low: Lowpass = .{};
            const length = out.len - loop_fade;
            for (out, 0..) |*v, i| {
                const t = seconds(i);
                var hum: f32 = 0;
                for ([_]f32{ 96, 192, 288, 405 }, 0..) |f, k| {
                    const fitted = @round(f * seconds(length)) / seconds(length);
                    hum += @sin(tau * fitted * t) / @as(f32, @floatFromInt(k + 1));
                }
                v.* = hum * 0.5 + low.step(noise.next(), 0.15) * 0.6;
            }
            out = makeLoop(out, loop_fade);
        },
        .wind => {
            var noise: Noise = .{ .state = 0x3111d };
            var low: Lowpass = .{};
            for (out, 0..) |*s, i| {
                const t = seconds(i);
                // Slow gusts.
                const gust = 0.55 + 0.3 * @sin(tau * 0.16 * t) + 0.15 * @sin(tau * 0.41 * t + 1.3);
                s.* = low.step(noise.next(), 0.02 + 0.03 * gust) * gust;
            }
            out = makeLoop(out, loop_fade);
        },
        .jet => {
            var noise: Noise = .{ .state = 0x7e7 };
            var low: Lowpass = .{};
            for (out, 0..) |*s, i| {
                const t = seconds(i);
                s.* = low.step(noise.next(), 0.25) * 0.8 + 0.25 * @sin(tau * 112 * t) + 0.1 * @sin(tau * 224 * t);
            }
            out = makeLoop(out, loop_fade);
        },
        .canopy => {
            // A soft pad: a slowly breathing chord whose partials fit the loop exactly.
            const chord = [_]f32{ 110, 164.81, 220, 277.18, 329.63 };
            const length = out.len - loop_fade;
            for (chord, 0..) |f, i| {
                // Round each frequency to a whole number of cycles per loop.
                const cycles = @round(f * seconds(length));
                const fitted = cycles / seconds(length);
                for (out, 0..) |*s, k| {
                    const t = seconds(k);
                    const breathe = 0.6 + 0.4 * @sin(tau * t / 8 + @as(f32, @floatFromInt(i)));
                    s.* += 0.2 * @sin(tau * fitted * t) * breathe;
                }
            }
            out = makeLoop(out, loop_fade);
        },
    }
    normalize(out, switch (sound) {
        .wind, .jet, .canopy, .engine => 0.7,
        .ui_move, .talk_blip => 0.5,
        else => 0.9,
    });
    if (out.len == buffer.len) return out;
    // Loops drop their crossfaded tail: hand back an exactly sized buffer.
    const exact = try allocator.dupe(f32, out);
    allocator.free(buffer);
    return exact;
}

test "every sound is finite, audible, peak-limited, and loops join without a jump" {
    const a = std.testing.allocator;
    for (0..sound_count) |i| {
        const sound: Sound = @enumFromInt(i);
        const samples = try generate(a, sound);
        defer a.free(samples);
        try std.testing.expect(samples.len > 100);
        var peak: f32 = 0;
        for (samples) |s| {
            try std.testing.expect(std.math.isFinite(s));
            peak = @max(peak, @abs(s));
        }
        try std.testing.expect(peak > 0.3 and peak <= 0.9001);
        if (sound.loops()) {
            // The wrap from the last sample to the first is no bigger than an ordinary step.
            var largest: f32 = 0;
            for (samples[1..], samples[0 .. samples.len - 1]) |b, prev| largest = @max(largest, @abs(b - prev));
            try std.testing.expect(@abs(samples[0] - samples[samples.len - 1]) <= largest * 1.5 + 1e-3);
        }
    }
    // Deterministic: the same sound twice is identical.
    const x = try generate(a, .footstep);
    defer a.free(x);
    const y = try generate(a, .footstep);
    defer a.free(y);
    try std.testing.expectEqualSlices(f32, x, y);
}
