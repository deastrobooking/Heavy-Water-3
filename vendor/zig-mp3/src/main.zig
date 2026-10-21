// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! A small command line front end: report on an MP3, or decode it to WAV.

const std = @import("std");
const mp3 = @import("mp3");

const native_endian = @import("builtin").cpu.arch.endian();

const usage =
    \\usage: zig-mp3 [--raw] <input.mp3> [output.wav]
    \\       zig-mp3 --encode [--bitrate <kbit/s>] <input.wav> <output.mp2>
    \\
    \\With one file argument, describe the stream.  With two, decode it to a
    \\16-bit PCM WAV file; an output of "-" writes to standard output.
    \\
    \\  --raw            keep the silence the encoder padded the stream with,
    \\                   instead of trimming it as a player would.
    \\  --encode         go the other way: read a 16-bit PCM WAV file and
    \\                   write MPEG-1 Layer II.
    \\  --bitrate <n>    kbit/s for --encode, across both channels.  Must be
    \\                   one the format can name; the default is 192.
    \\  --layer <n>      which layer --encode writes: 2 or 3.  The default
    \\                   is 3.
    \\
;

const Options = struct {
    raw: bool = false,
    encode: bool = false,
    bitrate: u32 = 192_000,
    layer: u8 = 3,
    input: []const u8,
    output: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    const options = parseArgs(argv) catch {
        try write(io, .stderr(), usage);
        return error.Usage;
    };

    const input = std.Io.Dir.cwd().readFileAlloc(io, options.input, gpa, .unlimited) catch |err| {
        try report(io, "cannot read {s}: {t}\n", .{ options.input, err });
        return err;
    };
    defer gpa.free(input);

    if (options.encode) return compress(io, gpa, options, input, options.output.?);
    if (options.output) |path| return convert(io, gpa, options, input, path);
    return describe(io, gpa, input);
}

fn parseArgs(argv: []const [:0]const u8) !Options {
    var raw = false;
    var encode = false;
    var bitrate: u32 = 192_000;
    var layer: u8 = 3;
    var files: [2][]const u8 = undefined;
    var count: usize = 0;
    var at: usize = 1;
    while (at < argv.len) : (at += 1) {
        const arg = argv[at];
        if (std.mem.eql(u8, arg, "--raw")) {
            raw = true;
        } else if (std.mem.eql(u8, arg, "--encode")) {
            encode = true;
        } else if (std.mem.eql(u8, arg, "--layer")) {
            at += 1;
            if (at == argv.len) return error.Usage;
            layer = std.fmt.parseInt(u8, argv[at], 10) catch return error.Usage;
            if (layer != 2 and layer != 3) return error.Usage;
        } else if (std.mem.eql(u8, arg, "--bitrate")) {
            at += 1;
            if (at == argv.len) return error.Usage;
            const kbps = std.fmt.parseInt(u32, argv[at], 10) catch return error.Usage;
            bitrate = kbps * 1000;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            // Anything else long is a typo or --help; either way, say how.
            return error.Usage;
        } else {
            if (count == files.len) return error.Usage;
            files[count] = arg;
            count += 1;
        }
    }
    if (count == 0) return error.Usage;
    // Encoding has nowhere to put its output without a second name.
    if (encode and count < 2) return error.Usage;
    return .{
        .raw = raw,
        .encode = encode,
        .bitrate = bitrate,
        .layer = layer,
        .input = files[0],
        .output = if (count > 1) files[1] else null,
    };
}

fn write(io: std.Io, file: std.Io.File, bytes: []const u8) !void {
    try file.writeStreamingAll(io, bytes);
}

fn report(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, fmt, args) catch return;
    try write(io, .stderr(), text);
}

/// Decode the whole stream, keeping only what the caller asked for.
const Walk = struct {
    channels: u8 = 0,
    sample_rate: u32 = 0,
    frames: usize = 0,
    samples: usize = 0,
    skipped: usize = 0,
    bitrate_total: u64 = 0,
    constant_bitrate: bool = true,
    first: ?mp3.Header = null,
    info: ?mp3.VbrInfo = null,
};

fn walk(input: []const u8) Walk {
    var decoder = mp3.Decoder.init();
    var buffer: mp3.FrameBuffer = undefined;
    var state: Walk = .{};
    var offset: usize = 0;

    while (offset < input.len) {
        switch (decoder.next(input[offset..], &buffer, .{ .end_of_input = true })) {
            .need_more => break,
            .skipped => |n| {
                state.skipped += n;
                offset += n;
            },
            .frame => |frame| {
                offset += frame.consumed;
                if (state.first == null) {
                    state.first = frame.header;
                    state.channels = frame.channels;
                    state.sample_rate = frame.sample_rate;
                } else if (frame.channels != state.channels or
                    frame.sample_rate != state.sample_rate)
                {
                    continue;
                }
                const rate = frame.header.bitRate() orelse 0;
                if (state.frames > 0 and (state.first.?.bitRate() orelse 0) != rate) {
                    state.constant_bitrate = false;
                }
                state.bitrate_total += rate;
                state.frames += 1;
                state.samples += frame.samples;
            },
        }
    }
    state.info = decoder.info();
    return state;
}

fn describe(io: std.Io, gpa: std.mem.Allocator, input: []const u8) !void {
    const state = walk(input);
    const header = state.first orelse {
        try report(io, "no MPEG audio found\n", .{});
        return error.NoAudio;
    };

    var out: [1024]u8 = undefined;
    var used: usize = 0;
    const seconds = @as(f64, @floatFromInt(state.samples)) /
        @as(f64, @floatFromInt(state.sample_rate));
    const average = if (state.frames == 0) 0 else state.bitrate_total / state.frames / 1000;

    used += (try std.fmt.bufPrint(out[used..],
        \\{t} {t}, {d} Hz, {d} channel{s} ({t})
        \\{s} {d} kbit/s
        \\{d} frames, {d} samples per channel, {d:.3} s
        \\
    , .{
        header.version,                                        header.layer,
        state.sample_rate,                                     state.channels,
        if (state.channels == 1) "" else "s",                  header.mode,
        if (state.constant_bitrate) "constant" else "average", average,
        state.frames,                                          state.samples,
        seconds,
    })).len;

    if (state.info) |info| {
        used += (try std.fmt.bufPrint(out[used..], "{t} header: ", .{info.kind})).len;
        if (info.frames) |n| used += (try std.fmt.bufPrint(out[used..], "{d} frames, ", .{n})).len;
        if (info.bytes) |n| used += (try std.fmt.bufPrint(out[used..], "{d} bytes, ", .{n})).len;
        used += (try std.fmt.bufPrint(out[used..], "seek table {s}\n", .{
            if (info.toc == null) "absent" else "present",
        })).len;
        if (info.lame) |lame| {
            used += (try std.fmt.bufPrint(
                out[used..],
                "{s}: {d} samples of delay, {d} of padding\n",
                .{ lame.name(), lame.delay, lame.padding },
            )).len;
        }
        if (info.duration(header)) |d| {
            used += (try std.fmt.bufPrint(out[used..], "stated duration {d:.3} s\n", .{d})).len;
        }
    }
    if (state.skipped > 0) {
        used += (try std.fmt.bufPrint(out[used..], "{d} bytes skipped\n", .{state.skipped})).len;
    }
    try write(io, .stdout(), out[0..used]);
    try describeTags(io, gpa, input);
}

fn describeTags(io: std.Io, gpa: std.mem.Allocator, input: []const u8) !void {
    var tag = (try mp3.id3.parse(gpa, input)) orelse return;
    defer tag.deinit();

    var out: [4096]u8 = undefined;
    var used: usize = 0;
    used += (try std.fmt.bufPrint(out[used..], "\n{t} tag, {d} frames\n", .{
        tag.version,
        tag.frames.len,
    })).len;

    const named = [_]struct { label: []const u8, value: ?[]const u8 }{
        .{ .label = "title", .value = tag.title() },
        .{ .label = "artist", .value = tag.artist() },
        .{ .label = "album", .value = tag.album() },
        .{ .label = "album artist", .value = tag.albumArtist() },
        .{ .label = "composer", .value = tag.composer() },
        .{ .label = "year", .value = tag.year() },
        .{ .label = "genre", .value = tag.genre() },
        .{ .label = "comment", .value = tag.comment() },
    };
    for (named) |field| {
        const value = field.value orelse continue;
        if (out.len - used < value.len + 32) break;
        used += (try std.fmt.bufPrint(out[used..], "  {s: <13}{s}\n", .{ field.label, value })).len;
    }
    if (tag.track()) |position| {
        used += (try std.fmt.bufPrint(out[used..], "  {s: <13}{d}", .{ "track", position.number })).len;
        if (position.total) |total| {
            used += (try std.fmt.bufPrint(out[used..], " of {d}", .{total})).len;
        }
        used += (try std.fmt.bufPrint(out[used..], "\n", .{})).len;
    }
    if (tag.disc()) |position| {
        used += (try std.fmt.bufPrint(out[used..], "  {s: <13}{d}", .{ "disc", position.number })).len;
        if (position.total) |total| {
            used += (try std.fmt.bufPrint(out[used..], " of {d}", .{total})).len;
        }
        used += (try std.fmt.bufPrint(out[used..], "\n", .{})).len;
    }
    try write(io, .stdout(), out[0..used]);
}

fn convert(
    io: std.Io,
    gpa: std.mem.Allocator,
    options: Options,
    input: []const u8,
    path: []const u8,
) !void {
    const to_stdout = std.mem.eql(u8, path, "-");
    const file = if (to_stdout)
        std.Io.File.stdout()
    else
        try std.Io.Dir.cwd().createFile(io, path, .{});
    defer if (!to_stdout) file.close(io);

    // Samples are written as they are decoded rather than collected first.
    // Ten minutes of stereo is two hundred megabytes as `f32`, and moving it
    // twice costs as much again as the decoding did.
    var held: std.ArrayList(u8) = .empty;
    defer held.deinit(gpa);

    var decoder = mp3.Decoder.init();
    var buffer: mp3.FrameBuffer = undefined;
    var encoded: [mp3.max_frame_samples]i16 = undefined;

    var channels: u8 = 0;
    var sample_rate: u32 = 0;
    var written: usize = 0;
    // Silence the encoder added, counted in interleaved samples.
    var lead_in: usize = 0;
    var playable: ?usize = null;

    var offset: usize = 0;
    while (offset < input.len) {
        switch (decoder.next(input[offset..], &buffer, .{ .end_of_input = true })) {
            .need_more => break,
            .skipped => |n| offset += n,
            .frame => |frame| {
                offset += frame.consumed;
                if (channels == 0) {
                    channels = frame.channels;
                    sample_rate = frame.sample_rate;
                    if (!options.raw) {
                        if (decoder.info()) |info| {
                            if (info.leadIn()) |lead| lead_in = lead * channels;
                            if (info.playableSamples(frame.header)) |count| {
                                playable = @as(usize, @intCast(count)) * channels;
                            }
                        }
                    }
                    // A placeholder, rewritten at the end once the length is
                    // known; standard output cannot be gone back to, so its
                    // header is held until then.
                    if (!to_stdout) {
                        try file.writeStreamingAll(io, &mp3.wav.header(channels, sample_rate, 0));
                    }
                }
                if (frame.channels != channels or frame.sample_rate != sample_rate) continue;

                var samples: []const f32 = buffer[0 .. frame.samples * @as(usize, frame.channels)];
                const drop = @min(lead_in, samples.len);
                lead_in -= drop;
                samples = samples[drop..];
                if (playable) |*left| {
                    const take = @min(left.*, samples.len);
                    samples = samples[0..take];
                    left.* -= take;
                }
                if (samples.len == 0) continue;

                // The library's conversion, which the compiler vectorises;
                // writing the samples one at a time through `writeInt` did
                // not, and cost a twentieth of the whole program.
                mp3.toInt16(samples, &encoded);
                const pcm = encoded[0..samples.len];
                if (native_endian != .little) {
                    for (pcm) |*sample| sample.* = @byteSwap(sample.*);
                }
                const bytes = std.mem.sliceAsBytes(pcm);
                if (to_stdout) {
                    try held.appendSlice(gpa, bytes);
                } else {
                    try file.writeStreamingAll(io, bytes);
                }
                written += bytes.len;
            },
        }
    }

    if (channels == 0) {
        try report(io, "no MPEG audio found\n", .{});
        return error.NoAudio;
    }

    const head = mp3.wav.header(channels, sample_rate, @intCast(written));
    if (to_stdout) {
        try file.writeStreamingAll(io, &head);
        try file.writeStreamingAll(io, held.items);
    } else {
        // Now that the length is known, put it where the placeholder was.
        try file.writePositionalAll(io, &head, 0);
    }
}

/// Encode a WAV file to MPEG-1 Layer II.
fn compress(
    io: std.Io,
    gpa: std.mem.Allocator,
    options: Options,
    input: []const u8,
    path: []const u8,
) !void {
    const sound = mp3.wav.parse(input) catch |err| {
        try report(io, "cannot read {s} as a wave file: {t}\n", .{ options.input, err });
        return err;
    };

    var layer2: ?mp3.Encoder = null;
    var layer3: ?mp3.Encoder3 = null;
    if (options.layer == 2) {
        layer2 = mp3.Encoder.init(.{
            .sample_rate = sound.sample_rate,
            .channels = sound.channels,
            .bitrate = options.bitrate,
        }) catch |err| {
            try reportEncodeError(io, sound.sample_rate, options, err);
            return err;
        };
    } else {
        layer3 = mp3.Encoder3.init(.{
            .sample_rate = sound.sample_rate,
            .channels = sound.channels,
            .bitrate = options.bitrate,
        }) catch |err| {
            try reportEncodeError(io, sound.sample_rate, options, err);
            return err;
        };
    }

    const to_stdout = std.mem.eql(u8, path, "-");
    const file = if (to_stdout)
        std.Io.File.stdout()
    else
        try std.Io.Dir.cwd().createFile(io, path, .{});
    defer if (!to_stdout) file.close(io);

    const per_frame: usize = if (options.layer == 2)
        mp3.encode.frame_samples
    else
        mp3.encode3.frame_samples;
    const channels: usize = sound.channels;
    const pcm = try gpa.alloc(f32, per_frame * channels);
    defer gpa.free(pcm);
    var frame: [@max(mp3.encode.max_frame_bytes, mp3.encode3.max_frame_bytes)]u8 = undefined;

    const total = sound.frames();
    var at: usize = 0;
    var written: usize = 0;
    var frames: usize = 0;
    while (at < total) : (at += per_frame) {
        // The last frame is filled out with silence: the format has no way to
        // say that a frame is part full.
        for (0..per_frame) |n| {
            for (0..channels) |ch| {
                pcm[n * channels + ch] =
                    if (at + n < total) sound.at(at + n, ch) else 0;
            }
        }
        const size = if (layer2) |*one|
            try one.encodeFrame(pcm, &frame)
        else
            try layer3.?.encodeFrame(pcm, &frame);
        try file.writeStreamingAll(io, frame[0..size]);
        written += size;
        frames += 1;
    }

    var out: [256]u8 = undefined;
    const text = try std.fmt.bufPrint(
        &out,
        "layer {d}: {d} frames, {d} bytes, {d} Hz, {d} channel{s}, {d} kbit/s\n",
        .{
            options.layer,
            frames,
            written,
            sound.sample_rate,
            sound.channels,
            if (sound.channels == 1) "" else "s",
            options.bitrate / 1000,
        },
    );
    try write(io, .stderr(), text);
}

fn reportEncodeError(io: std.Io, sample_rate: u32, options: Options, err: anyerror) !void {
    try report(io, "cannot encode {d} Hz at {d} bit/s as layer {d}: {t}\n", .{
        sample_rate, options.bitrate, options.layer, err,
    });
    if (err == error.UnsupportedBitRate) try reportBitRates(io, sample_rate, options.layer);
}

fn reportBitRates(io: std.Io, sample_rate: u32, layer: u8) !void {
    var buffer: [14]u32 = undefined;
    const rates = (if (layer == 2)
        mp3.encode.bitRates(sample_rate, &buffer)
    else
        mp3.encode3.bitRates(sample_rate, &buffer)) catch return;
    var out: [256]u8 = undefined;
    var used: usize = 0;
    used += (try std.fmt.bufPrint(out[used..], "available: ", .{})).len;
    for (rates, 0..) |rate, i| {
        used += (try std.fmt.bufPrint(out[used..], "{s}{d}", .{
            if (i == 0) "" else " ",
            rate / 1000,
        })).len;
    }
    used += (try std.fmt.bufPrint(out[used..], " kbit/s\n", .{})).len;
    try write(io, .stderr(), out[0..used]);
}
