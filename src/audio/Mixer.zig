//! Real-time mixer. The game thread only `send`s commands into a single-producer,
//! single-consumer ring; the audio thread drains it in `render` and owns every voice, so the
//! two never lock each other. One-shot sounds play on a fixed pool of voices (the oldest is
//! stolen when full); each looping sound has one voice whose gain glides toward its target, so
//! loops fade instead of clicking. Buses scale effects, ambience and interface separately under a
//! master volume, and a soft limiter keeps the sum below full scale.
const std = @import("std");
const Synth = @import("Synth.zig");
const Mixer = @This();

pub const Sound = Synth.Sound;
pub const Bus = enum { effects, ambience, interface };
pub const bus_count = @typeInfo(Bus).@"enum".fields.len;
pub const voice_count = 32;
pub const queue_capacity = 256;

pub const Play = struct {
    sound: Sound,
    bus: Bus = .effects,
    gain: f32 = 1,
    /// -1 left … 1 right.
    pan: f32 = 0,
    /// Playback speed (1 = as synthesized).
    pitch: f32 = 1,
};
pub const Command = union(enum) {
    play: Play,
    /// A loop's target gain (0 silences it) and pan; it glides there over ~80 ms.
    loop: struct { sound: Sound, gain: f32, pan: f32 = 0, bus: Bus = .ambience },
    volume: struct { bus: ?Bus, value: f32 },
};

const Voice = struct {
    sound: Sound = .ui_move,
    bus: Bus = .effects,
    position: f32 = 0,
    pitch: f32 = 1,
    left: f32 = 0,
    right: f32 = 0,
    age: u32 = 0,
    active: bool = false,
};
const Loop = struct {
    position: f32 = 0,
    gain: f32 = 0,
    target: f32 = 0,
    pan: f32 = 0,
    bus: Bus = .ambience,
};

/// Immutable synthesized clips, shared read-only with the audio thread.
clips: *const [Synth.sound_count][]const f32,
/// Output sample rate (clips are at `Synth.rate`).
rate: u32 = Synth.rate,
voices: [voice_count]Voice = @splat(.{}),
loops: [Synth.sound_count]Loop = @splat(.{}),
master: f32 = 1,
buses: [bus_count]f32 = @splat(1),
queue: [queue_capacity]Command = undefined,
head: std.atomic.Value(u32) = .init(0),
tail: std.atomic.Value(u32) = .init(0),
/// Commands dropped because the ring was full (game thread only).
dropped: u32 = 0,
/// Voices stolen because all were busy (audio thread only).
stolen: u32 = 0,

/// Game thread: queue a command. Never blocks; drops it (and counts) when the ring is full.
pub fn send(self: *Mixer, command: Command) void {
    const tail = self.tail.load(.monotonic);
    const next = (tail + 1) % queue_capacity;
    if (next == self.head.load(.acquire)) {
        self.dropped += 1;
        return;
    }
    self.queue[tail] = command;
    self.tail.store(next, .release);
}

fn panGains(pan: f32, gain: f32) [2]f32 {
    // Equal-power pan.
    const angle = (std.math.clamp(pan, -1, 1) + 1) * std.math.pi / 4;
    return .{ gain * @cos(angle), gain * @sin(angle) };
}

fn apply(self: *Mixer, command: Command) void {
    switch (command) {
        .play => |p| {
            if (p.sound.loops()) return;
            var slot: usize = 0;
            var oldest: u32 = 0;
            for (self.voices, 0..) |v, i| {
                if (!v.active) {
                    slot = i;
                    break;
                }
                if (v.age >= oldest) {
                    oldest = v.age;
                    slot = i;
                }
            } else self.stolen += 1;
            const g = panGains(p.pan, std.math.clamp(p.gain, 0, 4));
            self.voices[slot] = .{ .sound = p.sound, .bus = p.bus, .pitch = std.math.clamp(p.pitch, 0.25, 4), .left = g[0], .right = g[1], .active = true };
        },
        .loop => |l| {
            if (!l.sound.loops()) return;
            const loop = &self.loops[@intFromEnum(l.sound)];
            loop.target = std.math.clamp(l.gain, 0, 4);
            loop.pan = l.pan;
            loop.bus = l.bus;
        },
        .volume => |v| {
            const value = std.math.clamp(v.value, 0, 1);
            if (v.bus) |b| self.buses[@intFromEnum(b)] = value else self.master = value;
        },
    }
}

fn sample(clip: []const f32, position: f32) f32 {
    const i: usize = @intFromFloat(position);
    const frac = position - @floor(position);
    const a = clip[i];
    const b = if (i + 1 < clip.len) clip[i + 1] else 0;
    return a + (b - a) * frac;
}

/// Audio thread: applies queued commands and mixes `out.len / 2` stereo frames (interleaved).
pub fn render(self: *Mixer, out: []f32) void {
    var head = self.head.load(.monotonic);
    while (head != self.tail.load(.acquire)) {
        self.apply(self.queue[head]);
        head = (head + 1) % queue_capacity;
        self.head.store(head, .release);
    }
    @memset(out, 0);
    const step = @as(f32, @floatFromInt(Synth.rate)) / @as(f32, @floatFromInt(self.rate));
    const frame_count = out.len / 2;
    for (&self.voices) |*v| {
        if (!v.active) continue;
        v.age +|= 1;
        const clip = self.clips[@intFromEnum(v.sound)];
        const gain = self.master * self.buses[@intFromEnum(v.bus)];
        for (0..frame_count) |f| {
            if (v.position >= @as(f32, @floatFromInt(clip.len))) {
                v.active = false;
                break;
            }
            const s = sample(clip, v.position) * gain;
            out[f * 2] += s * v.left;
            out[f * 2 + 1] += s * v.right;
            v.position += step * v.pitch;
        }
    }
    // Loops glide toward their target gain (about 80 ms) and wrap around their clip.
    const glide = 1 - @exp(-1 / (0.08 * @as(f32, @floatFromInt(self.rate))));
    for (&self.loops, 0..) |*l, i| {
        if (l.gain < 1e-4 and l.target == 0) {
            l.gain = 0;
            continue;
        }
        const clip = self.clips[i];
        const length: f32 = @floatFromInt(clip.len);
        const bus = self.master * self.buses[@intFromEnum(l.bus)];
        for (0..frame_count) |f| {
            l.gain += (l.target - l.gain) * glide;
            const g = panGains(l.pan, l.gain * bus);
            const s = sample(clip, l.position);
            out[f * 2] += s * g[0];
            out[f * 2 + 1] += s * g[1];
            l.position += step;
            if (l.position >= length) l.position -= length;
        }
    }
    // Soft limiter: transparent at low levels, never past full scale.
    for (out) |*s| s.* = std.math.tanh(s.*);
}

pub fn activeVoices(self: *const Mixer) usize {
    var n: usize = 0;
    for (self.voices) |v| n += @intFromBool(v.active);
    return n;
}

fn testClips(a: std.mem.Allocator) !*[Synth.sound_count][]const f32 {
    const clips = try a.create([Synth.sound_count][]const f32);
    for (clips, 0..) |*c, i| c.* = try Synth.generate(a, @enumFromInt(i));
    return clips;
}

fn freeClips(a: std.mem.Allocator, clips: *[Synth.sound_count][]const f32) void {
    for (clips) |c| a.free(c);
    a.destroy(clips);
}

test "one-shots play to their end, pan, respect buses, and are stolen oldest-first" {
    const a = std.testing.allocator;
    const clips = try testClips(a);
    defer freeClips(a, clips);
    var m: Mixer = .{ .clips = clips };
    var out: [512]f32 = undefined;
    m.send(.{ .play = .{ .sound = .ui_move, .pan = -1 } });
    m.render(&out);
    var left: f32 = 0;
    var right: f32 = 0;
    for (0..out.len / 2) |f| {
        left += @abs(out[f * 2]);
        right += @abs(out[f * 2 + 1]);
    }
    try std.testing.expect(left > 1 and right < 1e-3);
    // ui_move is 35 ms: done after enough frames.
    for (0..8) |_| m.render(&out);
    try std.testing.expectEqual(@as(usize, 0), m.activeVoices());

    // A muted bus contributes nothing; master scales everything.
    m.send(.{ .volume = .{ .bus = .interface, .value = 0 } });
    m.send(.{ .play = .{ .sound = .ui_confirm, .bus = .interface } });
    m.render(&out);
    for (out) |s| try std.testing.expectEqual(@as(f32, 0), s);

    for (0..voice_count + 3) |_| m.send(.{ .play = .{ .sound = .vault } });
    m.render(&out);
    try std.testing.expectEqual(@as(usize, voice_count), m.activeVoices());
    // The muted confirm still holds a voice, so four of the 35 vaults took a busy voice.
    try std.testing.expectEqual(@as(u32, 4), m.stolen);
    for (out) |s| try std.testing.expect(@abs(s) < 1);
}

test "loops fade in and out smoothly, and a full queue drops instead of blocking" {
    const a = std.testing.allocator;
    const clips = try testClips(a);
    defer freeClips(a, clips);
    var m: Mixer = .{ .clips = clips };
    var out: [960]f32 = undefined;
    m.send(.{ .loop = .{ .sound = .wind, .gain = 1 } });
    m.render(&out);
    // 10 ms in, the gain is still gliding up.
    try std.testing.expect(m.loops[@intFromEnum(Sound.wind)].gain > 0.05 and m.loops[@intFromEnum(Sound.wind)].gain < 0.3);
    var largest_step: f32 = 0;
    var previous: f32 = out[out.len - 2];
    m.send(.{ .loop = .{ .sound = .wind, .gain = 0 } });
    for (0..100) |_| {
        m.render(&out);
        for (0..out.len / 2) |f| {
            largest_step = @max(largest_step, @abs(out[f * 2] - previous));
            previous = out[f * 2];
        }
    }
    try std.testing.expect(largest_step < 0.1);
    try std.testing.expect(m.loops[@intFromEnum(Sound.wind)].gain < 1e-3);
    // Non-loops cannot be looped and loops cannot be one-shots.
    m.send(.{ .loop = .{ .sound = .footstep, .gain = 1 } });
    m.send(.{ .play = .{ .sound = .wind } });
    m.render(&out);
    try std.testing.expectEqual(@as(usize, 0), m.activeVoices());

    for (0..queue_capacity + 10) |_| m.send(.{ .play = .{ .sound = .ui_move } });
    try std.testing.expectEqual(@as(u32, 11), m.dropped);
}
