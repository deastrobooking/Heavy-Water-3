//! Packaged MP3 playlist. A worker decodes frames into a bounded SPSC ring; the device callback
//! only copies and mixes ready samples, so file I/O and codec work stay off the real-time thread.
const std = @import("std");
const mp3 = @import("mp3");
const Music = @This();

pub const max_tracks = 64;
pub const track_name_capacity = 192;
const ring_capacity: u64 = 1 << 15;
const ring_mask = ring_capacity - 1;
const ring_reserve: u64 = @as(u64, @intCast(mp3.max_samples_per_frame)) * 16;
const command_capacity: u32 = 16;
const command_mask = command_capacity - 1;
const max_track_bytes = 128 << 20;
const target_music_gain: f32 = 0.17;

const Track = struct {
    name: [track_name_capacity]u8 = @splat(0),
    len: u16 = 0,
};
const Sample = struct { generation: u32, left: f32, right: f32 };
const Command = enum { previous, toggle, next };
pub const Status = struct {
    available: bool = false,
    playing: bool = false,
    track_name: []const u8 = "",
    track_index: usize = 0,
    track_count: usize = 0,
};

allocator: std.mem.Allocator,
io: std.Io,
target_rate: u32,
track_directory: []const u8 = "assets/Music",
tracks: [max_tracks]Track = @splat(.{}),
track_count: usize = 0,
samples: [ring_capacity]Sample = undefined,
sample_head: std.atomic.Value(u64) = .init(0),
sample_tail: std.atomic.Value(u64) = .init(0),
sample_generation: std.atomic.Value(u32) = .init(1),
current_track: std.atomic.Value(u32) = .init(0),
is_playing: std.atomic.Value(bool) = .init(true),
commands: [command_capacity]Command = undefined,
command_head: std.atomic.Value(u32) = .init(0),
command_tail: std.atomic.Value(u32) = .init(0),
wake: std.Io.Event = .unset,
stopping: std.atomic.Value(bool) = .init(false),
worker: std.Thread,

/// Scans the packaged music folder. A missing or empty folder simply leaves the sound-effects
/// system running without a soundtrack.
pub fn create(allocator: std.mem.Allocator, io: std.Io, target_rate: u32) !?*Music {
    const self = try allocator.create(Music);
    errdefer allocator.destroy(self);
    self.* = .{ .allocator = allocator, .io = io, .target_rate = target_rate, .worker = undefined };
    try self.discover();
    if (self.track_count == 0) {
        allocator.destroy(self);
        return null;
    }
    self.worker = try std.Thread.spawn(.{ .allocator = allocator }, workerMain, .{self});
    std.log.info("Music: {d} packaged MP3 track(s) from {s}", .{ self.track_count, self.track_directory });
    return self;
}

pub fn destroy(self: *Music) void {
    self.stopping.store(true, .release);
    self.wake.set(self.io);
    self.worker.join();
    self.allocator.destroy(self);
}

pub fn previous(self: *Music) void {
    self.send(.previous);
}

pub fn toggle(self: *Music) void {
    self.send(.toggle);
}

pub fn next(self: *Music) void {
    self.send(.next);
}

pub fn status(self: *const Music) Status {
    if (self.track_count == 0) return .{};
    const index: usize = @min(@as(usize, self.current_track.load(.acquire)), self.track_count - 1);
    const track = &self.tracks[index];
    const full_name = track.name[0..track.len];
    const label = if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |dot| full_name[0..dot] else full_name;
    return .{
        .available = true,
        .playing = self.is_playing.load(.acquire),
        .track_name = label,
        .track_index = index,
        .track_count = self.track_count,
    };
}

/// Mixes at most one ready ring-buffer sample per output frame. The callback does no allocation,
/// file access, decoding, locking, or waiting.
pub fn mix(self: *Music, output: []f32, master: f32) void {
    if (!self.is_playing.load(.acquire)) return;
    const generation = self.sample_generation.load(.acquire);
    var tail = self.sample_tail.load(.monotonic);
    const head = self.sample_head.load(.acquire);
    const gain = target_music_gain * master;
    var frame: usize = 0;
    while (frame < output.len / 2) : (frame += 1) {
        while (tail < head) {
            const sample = self.samples[@intCast(tail & ring_mask)];
            tail += 1;
            if (sample.generation != generation) continue;
            output[frame * 2] = std.math.clamp(output[frame * 2] + sample.left * gain, -1, 1);
            output[frame * 2 + 1] = std.math.clamp(output[frame * 2 + 1] + sample.right * gain, -1, 1);
            break;
        }
    }
    self.sample_tail.store(tail, .release);
    if (head - tail < ring_capacity / 2) self.wake.set(self.io);
}

fn discover(self: *Music) !void {
    if (try self.discoverFrom("assets/Music")) {
        self.track_directory = "assets/Music";
        return;
    }
    if (try self.discoverFrom("zig-out/assets/Music")) {
        self.track_directory = "zig-out/assets/Music";
        return;
    }
    std.log.info("No packaged MP3 tracks found in assets/Music or zig-out/assets/Music", .{});
}

fn discoverFrom(self: *Music, path: []const u8) !bool {
    var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return false;
    defer dir.close(self.io);
    var it = dir.iterate();
    while (self.track_count < max_tracks) {
        const entry = (try it.next(self.io)) orelse break;
        if (entry.kind != .file or !hasMp3Extension(entry.name) or entry.name.len > track_name_capacity) continue;
        var track: Track = .{ .len = @intCast(entry.name.len) };
        @memcpy(track.name[0..entry.name.len], entry.name);
        self.tracks[self.track_count] = track;
        self.track_count += 1;
    }
    sortTracks(self.tracks[0..self.track_count]);
    return self.track_count != 0;
}

fn hasMp3Extension(name: []const u8) bool {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return false;
    return std.ascii.eqlIgnoreCase(name[dot..], ".mp3");
}

fn lessTrack(a: Track, b: Track) bool {
    const left = a.name[0..a.len];
    const right = b.name[0..b.len];
    const count = @min(left.len, right.len);
    for (left[0..count], right[0..count]) |x, y| {
        const lower_x = std.ascii.toLower(x);
        const lower_y = std.ascii.toLower(y);
        if (lower_x != lower_y) return lower_x < lower_y;
    }
    return left.len < right.len;
}

fn sortTracks(tracks: []Track) void {
    for (1..tracks.len) |i| {
        const value = tracks[i];
        var at = i;
        while (at > 0 and lessTrack(value, tracks[at - 1])) : (at -= 1) tracks[at] = tracks[at - 1];
        tracks[at] = value;
    }
}

fn send(self: *Music, command: Command) void {
    const tail = self.command_tail.load(.monotonic);
    const next_tail = (tail + 1) & command_mask;
    if (next_tail == self.command_head.load(.acquire)) return;
    self.commands[tail] = command;
    self.command_tail.store(next_tail, .release);
    self.wake.set(self.io);
}

fn hasCommands(self: *const Music, head: u32) bool {
    return head != self.command_tail.load(.acquire);
}

fn waitForWork(self: *Music, command_head: u32, wait_for_space: bool) void {
    self.wake.reset();
    if (self.stopping.load(.acquire) or self.hasCommands(command_head)) return;
    if (wait_for_space) {
        const head = self.sample_head.load(.monotonic);
        const tail = self.sample_tail.load(.acquire);
        if (head - tail < ring_capacity - ring_reserve) return;
    }
    self.wake.waitUncancelable(self.io);
}

fn workerMain(self: *Music) void {
    var index: usize = 0;
    var generation: u32 = 1;
    var playing = true;
    var command_head: u32 = 0;
    var decoder = mp3.Decoder.init();
    var pcm: mp3.FrameBuffer = undefined;
    var resampler: Resampler = .{};
    var bytes: ?[]u8 = null;
    var offset: usize = 0;
    var decoded_frames: usize = 0;
    var logged_decode = false;
    var failed_tracks: usize = 0;
    defer if (bytes) |data| self.allocator.free(data);

    self.current_track.store(0, .release);
    self.sample_generation.store(generation, .release);
    self.is_playing.store(true, .release);

    while (!self.stopping.load(.acquire)) {
        var changed_track = false;
        while (command_head != self.command_tail.load(.acquire)) {
            const command = self.commands[command_head];
            command_head = (command_head + 1) & command_mask;
            self.command_head.store(command_head, .release);
            switch (command) {
                .toggle => playing = !playing,
                .previous => {
                    index = if (index == 0) self.track_count - 1 else index - 1;
                    changed_track = true;
                    failed_tracks = 0;
                },
                .next => {
                    index = (index + 1) % self.track_count;
                    changed_track = true;
                    failed_tracks = 0;
                },
            }
        }
        self.is_playing.store(playing, .release);

        if (changed_track) {
            if (bytes) |data| self.allocator.free(data);
            bytes = null;
            offset = 0;
            decoded_frames = 0;
            logged_decode = false;
            decoder = mp3.Decoder.init();
            resampler = .{};
            generation +%= 1;
            self.sample_generation.store(generation, .release);
            self.current_track.store(@intCast(index), .release);
        }

        if (!playing or self.stopping.load(.acquire)) {
            self.waitForWork(command_head, false);
            continue;
        }

        if (bytes == null) {
            var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
            const filename = self.tracks[index].name[0..self.tracks[index].len];
            const path_slice = std.fmt.bufPrint(&path, "{s}/{s}", .{ self.track_directory, filename }) catch unreachable;
            bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path_slice, self.allocator, .limited(max_track_bytes)) catch |err| {
                std.log.warn("music track {s} could not load ({s})", .{ filename, @errorName(err) });
                failed_tracks += 1;
                if (failed_tracks >= self.track_count) {
                    playing = false;
                    self.is_playing.store(false, .release);
                } else {
                    index = (index + 1) % self.track_count;
                    generation +%= 1;
                    self.sample_generation.store(generation, .release);
                    self.current_track.store(@intCast(index), .release);
                    offset = 0;
                    decoded_frames = 0;
                    logged_decode = false;
                    decoder = mp3.Decoder.init();
                    resampler = .{};
                }
                continue;
            };
            std.log.info("Music: playing {s}", .{filename});
        }

        const data = bytes.?;
        if (offset >= data.len) {
            if (decoded_frames == 0) {
                const filename = self.tracks[index].name[0..self.tracks[index].len];
                std.log.warn("music track {s} contained no decodable MP3 frames", .{filename});
                failed_tracks += 1;
                if (failed_tracks >= self.track_count) {
                    playing = false;
                    self.is_playing.store(false, .release);
                    continue;
                }
            } else {
                failed_tracks = 0;
            }
            self.allocator.free(data);
            bytes = null;
            index = (index + 1) % self.track_count;
            generation +%= 1;
            self.sample_generation.store(generation, .release);
            self.current_track.store(@intCast(index), .release);
            offset = 0;
            decoded_frames = 0;
            logged_decode = false;
            decoder = mp3.Decoder.init();
            resampler = .{};
            continue;
        }

        const step = decoder.next(data[offset..], &pcm, .{ .end_of_input = true });
        switch (step) {
            .need_more => offset = data.len,
            .skipped => |amount| {
                if (amount == 0) offset = data.len else offset += amount;
            },
            .frame => |frame| {
                offset += frame.consumed;
                decoded_frames += 1;
                if (!logged_decode) {
                    const filename = self.tracks[index].name[0..self.tracks[index].len];
                    std.log.info("Music: decoded {s} ({d} Hz)", .{ filename, frame.sample_rate });
                    logged_decode = true;
                }
                if (!resampler.decode(self, generation, frame, pcm[0 .. frame.samples * frame.channels], command_head)) continue;
            },
        }
        if (self.hasCommands(command_head)) continue;
        if (self.sample_head.load(.monotonic) - self.sample_tail.load(.acquire) >= ring_capacity - ring_reserve) {
            self.waitForWork(command_head, true);
        }
    }
}

const Resampler = struct {
    source_frames: u64 = 0,
    next_output_at: f64 = 0,
    source_step: f64 = 0,
    previous: [2]f32 = .{ 0, 0 },
    initialized: bool = false,

    fn decode(
        self: *Resampler,
        music: *Music,
        generation: u32,
        frame: mp3.Frame,
        input: []const f32,
        command_head: u32,
    ) bool {
        if (!self.initialized or (self.source_step != 0 and @as(f64, @floatFromInt(frame.sample_rate)) / @as(f64, @floatFromInt(music.target_rate)) != self.source_step)) {
            self.source_step = @as(f64, @floatFromInt(frame.sample_rate)) / @as(f64, @floatFromInt(music.target_rate));
            self.source_frames = 0;
            self.next_output_at = 0;
            self.initialized = true;
        }
        const channels: usize = @intCast(frame.channels);
        const frames = input.len / channels;
        for (0..frames) |i| {
            const current: [2]f32 = if (channels == 1)
                .{ input[i], input[i] }
            else
                .{ input[i * 2], input[i * 2 + 1] };
            const at: f64 = @floatFromInt(self.source_frames);
            if (self.source_frames == 0) {
                while (self.next_output_at <= at) : (self.next_output_at += self.source_step) {
                    if (!music.pushSample(generation, current, command_head)) return false;
                }
            } else {
                const previous_at = at - 1;
                while (self.next_output_at <= at) : (self.next_output_at += self.source_step) {
                    const amount: f32 = @floatCast(std.math.clamp(self.next_output_at - previous_at, 0, 1));
                    const sample = .{
                        self.previous[0] + (current[0] - self.previous[0]) * amount,
                        self.previous[1] + (current[1] - self.previous[1]) * amount,
                    };
                    if (!music.pushSample(generation, sample, command_head)) return false;
                }
            }
            self.previous = current;
            self.source_frames += 1;
        }
        return true;
    }
};

fn pushSample(self: *Music, generation: u32, stereo: [2]f32, command_head: u32) bool {
    while (true) {
        if (self.stopping.load(.acquire) or self.hasCommands(command_head)) return false;
        const head = self.sample_head.load(.monotonic);
        const tail = self.sample_tail.load(.acquire);
        if (head - tail < ring_capacity) {
            self.samples[@intCast(head & ring_mask)] = .{
                .generation = generation,
                .left = std.math.clamp(stereo[0], -1, 1),
                .right = std.math.clamp(stereo[1], -1, 1),
            };
            self.sample_head.store(head + 1, .release);
            return true;
        }
        self.waitForWork(command_head, true);
    }
}

test "packaged track filtering is case insensitive and only accepts MP3 files" {
    try std.testing.expect(hasMp3Extension("a.mp3"));
    try std.testing.expect(hasMp3Extension("a.MP3"));
    try std.testing.expect(!hasMp3Extension("a.opus"));
    try std.testing.expect(!hasMp3Extension("mp3"));
}

test "track ordering is stable and case insensitive" {
    var tracks = [_]Track{
        .{ .name = testName("zeta.mp3"), .len = 8 },
        .{ .name = testName("Alpha.mp3"), .len = 9 },
        .{ .name = testName("beta.mp3"), .len = 8 },
    };
    sortTracks(&tracks);
    try std.testing.expectEqualStrings("Alpha.mp3", tracks[0].name[0..tracks[0].len]);
    try std.testing.expectEqualStrings("beta.mp3", tracks[1].name[0..tracks[1].len]);
    try std.testing.expectEqualStrings("zeta.mp3", tracks[2].name[0..tracks[2].len]);
}

test "music status keeps its track label in playlist storage" {
    var music: Music = .{
        .allocator = std.testing.allocator,
        .io = undefined,
        .target_rate = 48_000,
        .track_count = 1,
        .worker = undefined,
    };
    music.tracks[0] = .{ .name = testName("Telecom Giants Master.mp3"), .len = 25 };

    const current = music.status();
    try std.testing.expectEqualStrings("Telecom Giants Master", current.track_name);
    try std.testing.expectEqual(@intFromPtr(&music.tracks[0].name[0]), @intFromPtr(current.track_name.ptr));
}

fn testName(value: []const u8) [track_name_capacity]u8 {
    var result: [track_name_capacity]u8 = @splat(0);
    @memcpy(result[0..value.len], value);
    return result;
}
