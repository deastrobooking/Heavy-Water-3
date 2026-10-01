//! The game's sound: synthesized clips, the real-time mixer, and the system output device
//! (Mach `sysaudio`). The device pulls samples on its own high-priority thread through
//! `write`, which only renders the mixer; the game thread talks to the mixer through its
//! command ring. Without a device (or with `-Daudio=false`) the game runs silent.
const std = @import("std");
const mach = @import("mach");
const sysaudio = mach.sysaudio;
const Synth = @import("Synth.zig");
const Mixer = @import("Mixer.zig");
pub const Director = @import("Director.zig");
const Settings = @import("../game/Settings.zig");
const Audio = @This();

/// Frames rendered per mixer call inside the device callback.
const chunk = 256;
const max_channels = 8;

allocator: std.mem.Allocator,
clips: [Synth.sound_count][]const f32,
mixer: Mixer,
director: Director = .{},
ctx: sysaudio.Context,
player: sysaudio.Player,
channels: usize,
format: sysaudio.Format,
stereo: [chunk * 2]f32 = undefined,
spread: [chunk * max_channels]f32 = undefined,

/// Synthesizes the clips (a few milliseconds) and opens the default playback device.
pub fn create(allocator: std.mem.Allocator) !*Audio {
    const self = try allocator.create(Audio);
    errdefer allocator.destroy(self);
    var made: usize = 0;
    errdefer for (self.clips[0..made]) |c| allocator.free(c);
    for (&self.clips, 0..) |*clip, i| {
        clip.* = try Synth.generate(allocator, @enumFromInt(i));
        made += 1;
    }
    var ctx = try sysaudio.Context.init(null, allocator, .{});
    errdefer ctx.deinit();
    try ctx.refresh();
    const device = ctx.defaultDevice(.playback) orelse return error.NoAudioDevice;
    self.* = .{ .allocator = allocator, .clips = self.clips, .mixer = undefined, .ctx = ctx, .player = undefined, .channels = 0, .format = .f32 };
    self.mixer = .{ .clips = &self.clips };
    self.player = try ctx.createPlayer(device, write, .{ .user_data = self, .sample_rate = Synth.rate, .media_role = .game });
    errdefer self.player.deinit();
    self.channels = self.player.channels().len;
    self.format = self.player.format();
    self.mixer.rate = self.player.sampleRate();
    if (self.channels == 0 or self.channels > max_channels) return error.UnsupportedAudioDevice;
    try self.player.start();
    std.log.info("Audio: {d} Hz, {d} channels, {s}", .{ self.mixer.rate, self.channels, @tagName(self.format) });
    return self;
}

pub fn destroy(self: *Audio) void {
    // Stops the device thread before the mixer it reads goes away.
    self.player.deinit();
    self.ctx.deinit();
    for (self.clips) |c| self.allocator.free(c);
    self.allocator.destroy(self);
}

pub fn send(self: *Audio, command: Mixer.Command) void {
    self.mixer.send(command);
}

/// Applies the volume settings (percentages) to the master and the buses.
pub fn setVolumes(self: *Audio, s: Settings) void {
    const pct = struct {
        fn f(v: u8) f32 {
            return @as(f32, @floatFromInt(v)) / 100;
        }
    }.f;
    self.send(.{ .volume = .{ .bus = null, .value = pct(s.master_volume) } });
    self.send(.{ .volume = .{ .bus = .effects, .value = pct(s.effects_volume) } });
    self.send(.{ .volume = .{ .bus = .ambience, .value = pct(s.ambience_volume) } });
    self.send(.{ .volume = .{ .bus = .interface, .value = pct(s.interface_volume) } });
}

/// Device thread: render the mixer in chunks, spread stereo over the device's channels, and
/// convert to its sample format.
fn write(user: ?*anyopaque, output: []u8) void {
    const self: *Audio = @ptrCast(@alignCast(user));
    const sample_size: usize = self.format.size();
    const frame_bytes = sample_size * self.channels;
    const frames = output.len / frame_bytes;
    var done: usize = 0;
    while (done < frames) {
        // `@min` with a comptime bound narrows its type (to u9 here); widen before multiplying.
        const n: usize = @min(chunk, frames - done);
        self.mixer.render(self.stereo[0 .. n * 2]);
        for (0..n) |f| for (0..self.channels) |c| {
            self.spread[f * self.channels + c] = if (c < 2) self.stereo[f * 2 + c] else 0;
        };
        // A mono device hears both sides.
        if (self.channels == 1) for (0..n) |f| {
            self.spread[f] = (self.stereo[f * 2] + self.stereo[f * 2 + 1]) * 0.5;
        };
        sysaudio.convertTo(f32, self.spread[0 .. n * self.channels], self.format, output[done * frame_bytes ..][0 .. n * frame_bytes]);
        done += n;
    }
    // Any partial frame left over stays silent.
    @memset(output[frames * frame_bytes ..], 0);
}
