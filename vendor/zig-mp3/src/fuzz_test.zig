// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Fuzzing the decoder.
//!
//! Feeding an MP3 decoder uniformly random bytes barely tests it.  A frame
//! sync is four bytes of structure, so random input almost never gets past
//! the sync scanner, and the interesting code -- side information,
//! scalefactors, Huffman decoding, the block layouts, the bit reservoir --
//! is never reached.  So the streams here are *built*: a header template
//! that stays fixed the way a real file's does, frames sized from it, bodies
//! of arbitrary bytes, and tags and rubbish spliced in.  That puts arbitrary
//! data exactly where a decoder is most likely to mishandle it, while still
//! getting it there.
//!
//! The generator takes its choices from a `Choices`, which is either Zig's
//! `Smith` or a seeded pseudo-random source.  Both matter:
//!
//!   * `zig build fuzz --fuzz` drives it through `Smith`, letting the fuzzer
//!     steer.  Zig 0.16 cannot populate the coverage table that guides that,
//!     so it is not much use yet, but the targets are here and correct for
//!     when it is.
//!   * `zig build test` drives it from a fixed seed, several hundred streams
//!     per target.  This is what actually exercises the decoder today, and
//!     it is deterministic, so a failure reproduces.
//!
//! `std.testing.fuzz` outside of fuzz mode runs a target once per corpus
//! entry, and a corpus entry is not arbitrary bytes -- it is `Smith`'s own
//! encoding, in which `eos` reads one byte and stops on anything non-zero
//! and a ranged value reads eight bytes that must land inside the range.
//! Random bytes therefore decode to "stop immediately, everything minimal",
//! which is why the seeded path below exists rather than a random corpus.

const std = @import("std");

const Smith = std.testing.Smith;

const BitReader = @import("bitstream.zig");
const Header = @import("header.zig");
const huffman = @import("huffman.zig");
const id3 = @import("id3.zig");
const reference = @import("reference.zig");
const imdct = @import("imdct.zig");
const mp3 = @import("root.zig");
const encode12 = @import("encode12.zig");
const encode3 = @import("encode3.zig");
const psymodel2 = @import("psymodel2.zig");
const scalefactor_bands = @import("tables/scalefactor_bands.zig");
const layer12 = @import("layer12.zig");
const side_info = @import("side_info.zig");
const synthesis = @import("synthesis.zig");
const tags = @import("tags.zig");
const vbr = @import("vbr.zig");

/// Room for the largest frame there is, several times over.
const stream_capacity = 8192;
/// Frames per generated stream: enough for the bit reservoir to fill and for
/// granule-to-granule state to matter, without making a test run slow.
const max_frames = 24;

// ------------------------------------------------------------- choices -----

/// A unique identity for a place where a choice is made.  `Smith`'s own
/// wrappers derive one from the return address, which does not survive being
/// called through the indirection below, so call sites name themselves.
fn site(comptime name: []const u8) u32 {
    return @truncate(std.hash.Wyhash.hash(0x5173, name));
}

/// Where the generator's decisions come from.
const Choices = union(enum) {
    smith: *Smith,
    random: std.Random,

    fn int(self: Choices, T: type, comptime name: []const u8, at_least: T, at_most: T) T {
        return switch (self) {
            .smith => |s| s.valueRangeAtMostWithHash(T, at_least, at_most, site(name)),
            .random => |r| r.intRangeAtMost(T, at_least, at_most),
        };
    }

    fn boolean(self: Choices, comptime name: []const u8) bool {
        return switch (self) {
            .smith => |s| s.valueWithHash(bool, site(name)),
            .random => |r| r.boolean(),
        };
    }

    /// True one time in `odds`.
    fn chance(self: Choices, comptime name: []const u8, odds: u8) bool {
        return self.int(u8, name, 0, odds - 1) == 0;
    }

    fn fill(self: Choices, comptime name: []const u8, out: []u8) void {
        if (out.len == 0) return;
        switch (self) {
            .smith => |s| s.bytesWithHash(out, site(name)),
            .random => |r| r.bytes(out),
        }
    }

    /// Whether the generator should stop.  Under the fuzzer this is the
    /// fuzzer's decision; under the seeded source the caller's own limits
    /// bound the loop instead.
    fn finished(self: Choices, comptime name: []const u8) bool {
        return switch (self) {
            .smith => |s| s.eosWithHash(site(name)),
            .random => false,
        };
    }
};

// ------------------------------------------------------------- invariants ---

/// What came out of a stream, so that a caller can tell how far in the input
/// actually reached.
const Decoded = struct {
    frames: usize = 0,
    /// Frames that produced something other than silence, meaning the
    /// scalefactors, the Huffman data and both filterbanks all ran on real
    /// content rather than on an empty granule.
    audible: usize = 0,

    fn add(self: *Decoded, other: Decoded) void {
        self.frames += other.frames;
        self.audible += other.audible;
    }
};

/// Decode a whole stream and check everything that must hold however mangled
/// the input is.
fn decodeStream(input: []const u8) !Decoded {
    var decoder = mp3.Decoder.init();
    var buffer: mp3.FrameBuffer = undefined;

    var offset: usize = 0;
    var steps: usize = 0;
    var result: Decoded = .{};
    while (offset < input.len) {
        // Every step consumes at least one byte, so a stream cannot take more
        // steps than it has bytes.  Checking that here turns a decoder that
        // stops making progress into a failure rather than a hang.
        steps += 1;
        try std.testing.expect(steps <= input.len);

        switch (decoder.next(input[offset..], &buffer, .{ .end_of_input = true })) {
            .need_more => break,
            .skipped => |n| {
                try std.testing.expect(n > 0);
                try std.testing.expect(n <= input.len - offset);
                offset += n;
            },
            .frame => |frame| {
                try std.testing.expect(frame.consumed > 0);
                try std.testing.expect(frame.consumed <= input.len - offset);
                // A frame that comes back at all is a whole frame.
                try std.testing.expectEqual(
                    @as(usize, frame.header.samplesPerFrame()),
                    frame.samples,
                );
                try std.testing.expectEqual(frame.header.channels(), frame.channels);
                try std.testing.expectEqual(frame.header.sampleRate(), frame.sample_rate);

                const count = frame.samples * @as(usize, frame.channels);
                try std.testing.expect(count <= buffer.len);
                // Arbitrary input must still come out as numbers: an infinity
                // or a NaN would mean a gain or an index had run away.  The
                // magnitude is deliberately not bounded -- a frame claiming
                // the largest global gain and the largest quantized values
                // legitimately decodes to something enormous, and clamping
                // that is the caller's business, not the decoder's.
                var loudest: f32 = 0;
                for (buffer[0..count]) |sample| {
                    try std.testing.expect(std.math.isFinite(sample));
                    loudest = @max(loudest, @abs(sample));
                }
                offset += frame.consumed;
                result.frames += 1;
                if (loudest > 0) result.audible += 1;
            },
        }
    }
    return result;
}

/// Collect every sample a stream decodes to, handing the decoder `chunk`
/// bytes at a time.  A chunk of the whole length is the ordinary case.
fn collect(
    gpa: std.mem.Allocator,
    input: []const u8,
    chunk: usize,
    into: *std.ArrayList(f32),
) !void {
    std.debug.assert(chunk > 0);
    var decoder = mp3.Decoder.init();
    var buffer: mp3.FrameBuffer = undefined;

    var start: usize = 0;
    var available: usize = 0;
    var steps: usize = 0;
    while (start < input.len) {
        steps += 1;
        try std.testing.expect(steps <= input.len * 2 + 16);
        available = @min(available + chunk, input.len - start);
        const final = start + available == input.len;
        switch (decoder.next(input[start..][0..available], &buffer, .{ .end_of_input = final })) {
            .need_more => if (final) break else continue,
            .skipped => |n| {
                try std.testing.expect(n > 0 and n <= available);
                start += n;
                available -= n;
            },
            .frame => |frame| {
                try std.testing.expect(frame.consumed > 0 and frame.consumed <= available);
                const count = frame.samples * @as(usize, frame.channels);
                for (buffer[0..count]) |sample| {
                    try std.testing.expect(std.math.isFinite(sample));
                }
                try into.appendSlice(gpa, buffer[0..count]);
                start += frame.consumed;
                available -= frame.consumed;
            },
        }
    }
}

// --------------------------------------------------------- stream building --

/// The header fields a real stream holds fixed from beginning to end.
/// Keeping them fixed is what lets consecutive frames confirm each other, so
/// that the decoder synchronizes and reaches the code past the sync scanner.
fn chooseTemplate(choices: Choices) [4]u8 {
    const versions = [3]u2{ 0, 2, 3 }; // MPEG-2.5, MPEG-2, MPEG-1; never reserved
    const version = versions[choices.int(u8, "version", 0, 2)];
    const layer: u2 = switch (choices.int(u8, "layer", 0, 15)) {
        0, 1 => 3, // Layer I
        2, 3 => 2, // Layer II
        else => 1, // Layer III, which is most of the decoder
    };
    const protected = choices.chance("crc", 8);
    const sample_rate = choices.int(u2, "rate", 0, 2);
    const mode = choices.int(u2, "mode", 0, 3);
    const mode_extension = choices.int(u2, "mode_ext", 0, 3);

    return .{
        0xff,
        // The protection bit is active low.
        0xe0 | (@as(u8, version) << 3) | (@as(u8, layer) << 1) | @intFromBool(!protected),
        @as(u8, sample_rate) << 2,
        (@as(u8, mode) << 6) | (@as(u8, mode_extension) << 4),
    };
}

/// Append one frame, its body arbitrary bytes.  Always writes at least one
/// byte, so a caller looping on it terminates.
fn appendFrame(choices: Choices, template: [4]u8, out: []u8) usize {
    std.debug.assert(out.len > 4);
    var raw = template;
    // Bit rate and padding are the two fields a real stream varies frame to
    // frame.  Index 0 is free format, whose size the frame does not state and
    // which this decoder steps over rather than decodes; it comes up rarely
    // so that most frames still have a size, but it does come up.
    const bitrate: u4 = if (choices.chance("free_format", 12))
        0
    else
        choices.int(u4, "bitrate", 1, 14);
    raw[2] = (raw[2] & 0x0c) |
        (@as(u8, bitrate) << 4) |
        (@as(u8, @intFromBool(choices.boolean("padding"))) << 1);

    const header = Header.parse(raw) orelse {
        @memcpy(out[0..4], &raw);
        return 4;
    };
    const size = header.frameSize() orelse {
        @memcpy(out[0..4], &raw);
        return 4;
    };

    // A frame that will not fit is written as far as it goes, which is the
    // truncated final frame and worth reaching in its own right.
    const written = @min(size, out.len);
    @memcpy(out[0..4], &raw);
    choices.fill("body", out[4..written]);

    // `main_data_begin` says how far back into the bit reservoir the granule
    // data starts.  Left to chance it averages half of its 511 byte range,
    // which almost always points further back than the reservoir holds, and
    // the frame is turned away before any of the interesting code runs.
    // Biasing it small is what gets scalefactors, Huffman decoding and the
    // block layouts fuzzed at all; a wide value still gets through one time
    // in eight, so the rejection path stays covered.
    const side_info_at = 4 + @as(usize, if (header.crc_protected) 2 else 0);
    if (header.layer == .layer3 and written > side_info_at + 2) {
        const back = if (choices.chance("reservoir_far", 8))
            choices.int(u16, "reservoir_wide", 0, 511)
        else
            choices.int(u16, "reservoir", 0, 63);
        if (header.version.isLowSamplingFrequency()) {
            out[side_info_at] = @truncate(back);
        } else {
            // Nine bits, so the ninth is the top bit of the next byte.
            out[side_info_at] = @truncate(back >> 1);
            out[side_info_at + 1] = (out[side_info_at + 1] & 0x7f) |
                (@as(u8, @truncate(back & 1)) << 7);
        }
    }
    return written;
}

/// Append an ID3v2 tag whose stated size the generator chooses, so that the
/// skipping is exercised against sizes that do and do not match what follows.
fn appendTag(choices: Choices, out: []u8) usize {
    if (out.len < 10) return appendJunk(choices, out);
    @memcpy(out[0..3], "ID3");
    out[3] = 4;
    out[4] = 0;
    const footer = choices.chance("tag_footer", 8);
    out[5] = if (footer) 0x10 else 0;

    const body = choices.int(u16, "tag_size", 0, 300);
    out[6] = 0;
    out[7] = 0;
    out[8] = @truncate(body >> 7);
    out[9] = @truncate(body & 0x7f);

    const stated = 10 + @as(usize, body) + @as(usize, if (footer) 10 else 0);
    const written = @min(stated, out.len);
    choices.fill("tag_body", out[10..written]);
    return written;
}

fn appendJunk(choices: Choices, out: []u8) usize {
    const written = @min(@as(usize, choices.int(u16, "junk", 1, 64)), out.len);
    choices.fill("junk_bytes", out[0..written]);
    return written;
}

/// Build a stream into `out` and return its length.
fn buildStream(choices: Choices, out: []u8) usize {
    const template = chooseTemplate(choices);
    const wanted = switch (choices) {
        .smith => max_frames,
        .random => choices.int(u8, "frames", 1, max_frames),
    };

    var len: usize = 0;
    var frames: usize = 0;
    while (len + 4 < out.len and frames < wanted) {
        if (choices.finished("more")) break;
        len += switch (choices.int(u8, "piece", 0, 15)) {
            0 => appendTag(choices, out[len..]),
            1 => appendJunk(choices, out[len..]),
            else => b: {
                frames += 1;
                break :b appendFrame(choices, template, out[len..]);
            },
        };
    }
    return len;
}

// --------------------------------------------------------- the targets -----

/// A built stream, decoded whole and then again a few bytes at a time.
///
/// The two must produce the same samples.  How the input is divided up is the
/// caller's business and none of the decoder's, so anything that made the two
/// differ would be state kept across a call that should not have been -- the
/// kind of bug that only shows up against a real network.
fn checkBuiltStream(choices: Choices, gpa: std.mem.Allocator) !Decoded {
    var buffer: [stream_capacity]u8 = undefined;
    const len = buildStream(choices, &buffer);
    const input = buffer[0..len];
    const decoded = try decodeStream(input);

    var whole: std.ArrayList(f32) = .empty;
    defer whole.deinit(gpa);
    var pieces: std.ArrayList(f32) = .empty;
    defer pieces.deinit(gpa);

    const chunk: usize = choices.int(u16, "chunk", 1, 1024);
    try collect(gpa, input, @max(input.len, 1), &whole);
    try collect(gpa, input, chunk, &pieces);
    try std.testing.expectEqualSlices(f32, whole.items, pieces.items);
    return decoded;
}

/// Whatever the bytes are, the decoder must not fall over on them.  This is
/// the unstructured target; it mostly reaches the sync scanner and the tag
/// skipper, which is exactly what the built streams do not dwell on.
fn checkArbitraryBytes(choices: Choices, scratch: []u8) !void {
    const len = switch (choices) {
        .smith => |s| s.sliceWithHash(scratch[0..@min(scratch.len, 4096)], site("arbitrary")),
        .random => |r| r.intRangeAtMost(u32, 0, @intCast(@min(scratch.len, 4096))),
    };
    choices.fill("arbitrary_bytes", scratch[0..len]);
    _ = try decodeStream(scratch[0..len]);
}

/// Side information over arbitrary bytes, for every frame shape there is.
fn checkSideInfo(choices: Choices) !void {
    var raw: [32]u8 = undefined;
    choices.fill("side_info", &raw);

    const shapes = [_][4]u8{
        .{ 0xff, 0xfb, 0x90, 0x00 }, // MPEG-1 stereo, 32 bytes
        .{ 0xff, 0xfb, 0x90, 0xc0 }, // MPEG-1 mono, 17 bytes
        .{ 0xff, 0xf3, 0x40, 0x00 }, // MPEG-2 stereo, 17 bytes
        .{ 0xff, 0xf3, 0x40, 0xc0 }, // MPEG-2 mono, 9 bytes
    };
    for (shapes) |bytes| {
        const header = Header.parse(bytes).?;
        const info = side_info.parse(header, raw[0..header.sideInfoSize()]) catch |err| {
            // The only two things it rejects, and both are real.
            try std.testing.expect(err == error.InvalidBlockType or
                err == error.UndefinedHuffmanTable);
            continue;
        };
        // The low sampling frequency layout has no scalefactor selection
        // information, and the parser must not invent any.
        if (header.version.isLowSamplingFrequency()) {
            for (info.scfsi) |channel| {
                for (channel) |set| try std.testing.expect(!set);
            }
        }
        for (0..header.granules()) |gr| {
            for (0..header.channels()) |ch| {
                const granule = info.get(gr, ch);
                if (granule.window_switching) {
                    try std.testing.expect(granule.block_type != .normal);
                } else {
                    try std.testing.expectEqual(side_info.BlockType.normal, granule.block_type);
                    try std.testing.expect(!granule.mixed_block);
                }
                for (granule.table_select) |table| {
                    try std.testing.expect(table != 4 and table != 14);
                }
            }
        }
    }
}

/// The Huffman decoder must always terminate, always advance, and always
/// return a pair its table can represent, however arbitrary the bits are.
fn checkHuffman(choices: Choices) !void {
    var raw: [96]u8 = undefined;
    choices.fill("huffman", &raw);

    for (huffman.big_value) |maybe| {
        const selected = maybe orelse continue;
        var reader = BitReader.init(&raw);
        while (reader.remaining() > 0) {
            const before = reader.pos;
            const pair = selected.table.decode(&reader);
            try std.testing.expect(pair.x <= 15 and pair.y <= 15);
            // Every code word is at least one bit, so this cannot spin.
            try std.testing.expect(reader.pos > before);
        }
    }
    for (huffman.count1) |table| {
        var reader = BitReader.init(&raw);
        while (reader.remaining() > 0) {
            const before = reader.pos;
            const pair = table.decode(&reader);
            // The count1 tables pack four one-bit magnitudes into `y`.
            try std.testing.expectEqual(@as(u8, 0), pair.x);
            try std.testing.expect(pair.y <= 15);
            try std.testing.expect(reader.pos > before);
        }
    }
}

/// The filterbanks are the parts written for speed rather than for reading,
/// and both of them get their answers from half the arithmetic the standard
/// describes.  `reference.zig` has them written the plain way; this runs the
/// two side by side over arbitrary spectra and an arbitrary number of
/// granules, which is what puts the synthesis history's ring buffer through
/// every alignment it can be in.
fn checkFilterbanks(choices: Choices) !void {
    var fast = synthesis.State{};
    var slow = reference.SynthesisState{};

    // Layer III hands the filterbank eighteen time slots per granule and
    // Layers I and II hand it twelve, and either may be writing into one
    // channel of an interleaved pair rather than a buffer of its own.  Both
    // the slot count and the stride are taken from the arguments now, so
    // both are chosen here.
    const slot_count: usize = if (choices.boolean("fb_slots")) 18 else 12;
    const stride: usize = if (choices.boolean("fb_stride")) 2 else 1;
    const lines = slot_count * synthesis.subbands;

    const granules = choices.int(u8, "fb_granules", 1, 24);
    for (0..granules) |_| {
        var spectrum: [576]f32 = undefined;
        // Bounded, because the two sum in different orders and comparing
        // them means comparing rounding, not scale.
        for (spectrum[0..lines]) |*value| {
            value.* = @as(f32, @floatFromInt(choices.int(i16, "fb_line", -1000, 1000))) / 1000.0;
        }

        var got: [576 * 2]f32 = undefined;
        var want: [576]f32 = undefined;
        // Filled with rubbish first, so that writing to the wrong place --
        // or not writing at all -- shows up rather than reading back as the
        // zero it should have been.
        @memset(std.mem.sliceAsBytes(got[0..]), 0x5a);
        synthesis.synthesize(&fast, spectrum[0..lines], got[0 .. lines * stride], stride, synthesis.subbands);
        reference.synthesize(&slow, spectrum[0..lines], want[0..lines]);
        for (0..lines) |i| {
            try std.testing.expectApproxEqAbs(want[i], got[i * stride], 1e-3);
        }
        // The gaps between the strided samples belong to the other channel
        // and must come back exactly as they were left.
        if (stride == 2) {
            for (0..lines) |i| {
                try std.testing.expectEqual(
                    @as(u32, 0x5a5a5a5a),
                    @as(u32, @bitCast(got[i * 2 + 1])),
                );
            }
        }
    }

    // The inverse MDCT, over whichever block shape was asked for.
    const shapes = [_]side_info.BlockType{ .normal, .start, .short, .stop };
    const block_type = shapes[choices.int(u8, "fb_block", 0, 3)];
    var in: [18]f32 = undefined;
    for (&in) |*value| {
        value.* = @as(f32, @floatFromInt(choices.int(i16, "fb_in", -1000, 1000))) / 1000.0;
    }

    var spectrum: [576]f32 = @splat(0);
    @memcpy(spectrum[0..18], &in);
    var overlap: imdct.Overlap = @splat(@splat(0));
    _ = imdct.hybridSynthesis(&spectrum, &overlap, block_type, 0);
    for (spectrum) |value| try std.testing.expect(std.math.isFinite(value));
}

/// Build a Layer III frame carrying an encoder's table of contents, with the
/// magic in the right place so that the parser actually walks it.
///
/// Left to arbitrary bytes this code is never reached at all: the magic is
/// four bytes at an offset that depends on the header, so the chance of
/// hitting it is nil.
fn buildVbrFrame(choices: Choices, out: []u8) usize {
    if (out.len < 200) return 0;

    const versions = [3]u2{ 0, 2, 3 };
    const version = versions[choices.int(u8, "vbr_version", 0, 2)];
    const protected = choices.chance("vbr_crc", 8);
    const mode = choices.int(u2, "vbr_mode", 0, 3);
    out[0] = 0xff;
    out[1] = 0xe0 | (@as(u8, version) << 3) | (1 << 1) | @intFromBool(!protected);
    out[2] = (@as(u8, choices.int(u4, "vbr_bitrate", 1, 14)) << 4) |
        (@as(u8, choices.int(u2, "vbr_rate", 0, 2)) << 2);
    out[3] = @as(u8, mode) << 6;

    const header = Header.parse(out[0..4].*) orelse return 4;
    const size = @min(header.frameSize() orelse return 4, out.len);
    if (size < 200) return size;
    choices.fill("vbr_body", out[4..size]);

    if (choices.chance("vbr_kind", 3)) {
        // Fraunhofer's, at a fixed offset and with no flags.
        @memcpy(out[36..40], "VBRI");
        return size;
    }

    const at = 4 + @as(usize, if (header.crc_protected) 2 else 0) + header.sideInfoSize();
    if (at + 8 > size) return size;
    @memcpy(out[at..][0..4], if (choices.boolean("vbr_info")) "Info" else "Xing");

    // Which fields are present is a flag word, and disagreeing with what
    // actually follows is one of the ways a real file is broken.
    const flags = choices.int(u8, "vbr_flags", 0, 15);
    std.mem.writeInt(u32, out[at + 4 ..][0..4], flags, .big);

    // Plausible values rather than arbitrary ones for the fields themselves.
    // A random 32-bit frame count is always enormous, and an enormous one
    // hides every edge the arithmetic has -- a stream shorter than the
    // silence the encoder says it padded it with, for one.
    var pos = at + 8;
    if (flags & 1 != 0 and pos + 4 <= size) {
        // Weighted towards the small end: a stream of a handful of frames is
        // shorter than the silence an encoder claims to have padded it with,
        // and that is where the arithmetic can go negative.
        const frames = if (choices.chance("vbr_short", 4))
            choices.int(u16, "vbr_few", 0, 8)
        else
            choices.int(u16, "vbr_frames", 0, 4000);
        std.mem.writeInt(u32, out[pos..][0..4], frames, .big);
        pos += 4;
    }
    if (flags & 2 != 0 and pos + 4 <= size) {
        std.mem.writeInt(u32, out[pos..][0..4], choices.int(u16, "vbr_bytes", 0, 65535), .big);
        pos += 4;
    }
    if (flags & 4 != 0) pos += 100; // the seek table, left as arbitrary bytes
    if (flags & 8 != 0 and pos + 4 <= size) {
        std.mem.writeInt(u32, out[pos..][0..4], choices.int(u8, "vbr_quality", 0, 100), .big);
    }

    // The LAME extension sits at a fixed offset whatever the flags said.
    const lame_at = at + 120;
    if (lame_at + 36 <= size and !choices.chance("vbr_no_lame", 4)) {
        @memcpy(out[lame_at..][0..9], "LAME3.100");
        const delay = choices.int(u16, "vbr_delay", 0, 4095);
        const padding = choices.int(u16, "vbr_padding", 0, 4095);
        out[lame_at + 21] = @truncate(delay >> 4);
        out[lame_at + 22] = @truncate(((delay & 0xf) << 4) | (padding >> 8));
        out[lame_at + 23] = @truncate(padding);
    }
    return size;
}

/// Whatever a table of contents claims, nothing it yields may be nonsense: a
/// duration has to be a finite number of seconds, and a seek has to land
/// inside the file it describes.
fn checkVbr(choices: Choices) !void {
    var frame: [2048]u8 = undefined;
    const len = buildVbrFrame(choices, &frame);
    if (len < 4) return;
    const header = Header.parse(frame[0..4].*) orelse return;

    const info = vbr.parse(header, frame[0..len]) orelse return;
    if (info.duration(header)) |seconds| {
        try std.testing.expect(std.math.isFinite(seconds));
        try std.testing.expect(seconds >= 0);
    }
    if (info.playableSamples(header)) |count| {
        try std.testing.expect(count <= @as(u64, info.frames.?) * header.samplesPerFrame());
    }
    if (info.leadIn()) |lead| {
        try std.testing.expectEqual(@as(u32, info.lame.?.delay) + vbr.decoder_delay, lead);
    }
    // A seek has to stay inside the stream, however the fraction is given.
    for ([_]f64{ -1, 0, 0.001, 0.5, 0.999, 1, 2, 1e30 }) |fraction| {
        if (info.seekOffset(fraction)) |offset| {
            try std.testing.expect(offset <= info.bytes.?);
        }
    }
    if (info.toc) |_| try std.testing.expect(info.bytes != null or info.seekOffset(0.5) == null);
}

/// The one shot interface, which allocates where the streaming one does not.
fn checkDecodeAll(choices: Choices, gpa: std.mem.Allocator) !void {
    var buffer: [stream_capacity]u8 = undefined;
    const len = buildStream(choices, &buffer);

    var audio = mp3.decodeAll(gpa, buffer[0..len]) catch |err| {
        try std.testing.expect(err == error.NoAudio or err == error.OutOfMemory);
        return;
    };
    defer audio.deinit();

    try std.testing.expect(audio.channels == 1 or audio.channels == 2);
    try std.testing.expect(audio.sample_rate > 0);
    // Whole frames only: a stream cannot end mid-sample.
    try std.testing.expectEqual(@as(usize, 0), audio.samples.len % audio.channels);
    try std.testing.expectEqual(audio.samples.len / audio.channels, audio.frameCount());
    try std.testing.expect(std.math.isFinite(audio.duration()));
    try std.testing.expect(audio.duration() >= 0);
    for (audio.samples) |sample| try std.testing.expect(std.math.isFinite(sample));

    // Conversion has to clamp rather than wrap, whatever it is handed.
    const pcm = try gpa.alloc(i16, audio.samples.len);
    defer gpa.free(pcm);
    mp3.toInt16(audio.samples, pcm);
}

/// The bit reader loads eight bytes at a time and shifts them into place,
/// which is where a buffer's last few bytes are easiest to get wrong.  This
/// runs it and the plain one-bit-at-a-time reader over the same bytes with
/// the same sequence of reads and requires them to agree on every value, on
/// where they ended up, and on how far past the end they went.
///
/// Short buffers are the interesting case, so they are what it mostly makes.
fn checkBitReader(choices: Choices) !void {
    var bytes: [24]u8 = undefined;
    const len: usize = choices.int(u8, "bits_len", 0, bytes.len);
    choices.fill("bits_bytes", bytes[0..len]);

    var fast = BitReader.init(bytes[0..len]);
    var slow = reference.BitReader{ .bytes = bytes[0..len] };

    const reads = choices.int(u8, "bits_reads", 1, 40);
    for (0..reads) |_| {
        // Zero and 32 are both worth hitting: one returns nothing, the other
        // fills the result exactly.
        const width: u6 = @intCast(choices.int(u8, "bits_width", 0, 32));

        try std.testing.expectEqual(slow.peek(width), fast.peek(width));
        // Peeking must not move anything.
        try std.testing.expectEqual(slow.pos, fast.pos);

        try std.testing.expectEqual(slow.read(width), fast.read(width));
        try std.testing.expectEqual(slow.pos, fast.pos);
        try std.testing.expectEqual(slow.overrun, fast.overrun);

        // Occasionally jump somewhere else, including past the end, which is
        // what a granule whose `part2_3_length` lies does.
        if (choices.chance("bits_seek", 6)) {
            const to: usize = choices.int(u16, "bits_to", 0, 300);
            fast.seek(to);
            slow.pos = to;
        }
    }
    try std.testing.expectEqual(slow.pos >= len * 8, fast.remaining() == 0);
}

/// The register cache the Huffman loop reads through, against the plain
/// reader, driven the way the decoder drives it: refill, then a run of reads
/// no wider than the refill guarantees.
///
/// Short buffers again, because the cache pulls in eight bytes at a time and
/// the end of the input is where that is easiest to get wrong.
fn checkBitCache(choices: Choices) !void {
    var bytes: [24]u8 = undefined;
    const len: usize = choices.int(u8, "cache_len", 0, bytes.len);
    choices.fill("cache_bytes", bytes[0..len]);

    const start: usize = choices.int(u16, "cache_start", 0, @intCast(len * 8 + 16));
    var slow = reference.BitReader{ .bytes = bytes[0..len] };
    slow.pos = start;
    var fast = BitReader.Cache.init(bytes[0..len], start);
    try std.testing.expectEqual(slow.pos, fast.position());

    for (0..12) |_| {
        // A refill guarantees 57 bits, which is what the decoder spends
        // before refilling again.
        fast.refill();
        var budget: u32 = 57;
        while (budget > 0) {
            const n: u6 = @intCast(choices.int(u8, "cache_width", 0, @min(32, budget)));
            try std.testing.expectEqual(slow.peek(n), fast.peek(n));
            try std.testing.expectEqual(slow.read(n), fast.read(n));
            try std.testing.expectEqual(slow.pos, fast.position());
            if (n == 0) break;
            budget -= n;
        }
    }
}

/// Decoding, resetting at arbitrary points, and decoding on.  A reset throws
/// away the bit reservoir and both filterbanks' history, and the filterbank
/// keeps its history in a ring buffer written at two places at once, so this
/// is where an index that is wrong by a block would show itself.
fn checkResets(choices: Choices) !void {
    var buffer: [stream_capacity]u8 = undefined;
    const len = buildStream(choices, &buffer);
    const input = buffer[0..len];

    var decoder = mp3.Decoder.init();
    var out: mp3.FrameBuffer = undefined;
    var offset: usize = 0;
    var steps: usize = 0;
    while (offset < input.len) {
        steps += 1;
        try std.testing.expect(steps <= input.len);
        if (choices.chance("reset", 5)) decoder.reset();
        switch (decoder.next(input[offset..], &out, .{ .end_of_input = true })) {
            .need_more => break,
            .skipped => |n| offset += n,
            .frame => |frame| {
                offset += frame.consumed;
                const count = frame.samples * @as(usize, frame.channels);
                for (out[0..count]) |sample| {
                    try std.testing.expect(std.math.isFinite(sample));
                }
            },
        }
    }
}

/// Build something ID3v2 shaped: the right magic and a syncsafe size, with
/// frames whose identifiers, sizes, flags and text encodings are all chosen.
/// Getting the header right is what makes the parser walk the frames instead
/// of turning the whole thing away at the door.
fn buildId3(choices: Choices, out: []u8) usize {
    if (out.len < 32) return 0;
    const ids = [_][]const u8{
        "TIT2", "TPE1", "TALB", "TCON", "TRCK", "TPOS", "TYER", "TDRC",
        "COMM", "TXXX", "WXXX", "APIC", "USLT", "TSSE", "PRIV", "\x00\x00\x00\x00",
    };

    @memcpy(out[0..3], "ID3");
    out[3] = choices.int(u8, "id3_major", 2, 4);
    out[4] = 0;
    // Unsynchronization, an extended header, and the flags nothing reads.
    out[5] = choices.int(u8, "id3_flags", 0, 0xff) & 0xf0;

    var at: usize = 10;
    if (out[5] & 0x40 != 0 and out.len > at + 10) {
        // An extended header, whose stated size is as likely to be wrong as
        // right; the parser has to survive either.
        const size = choices.int(u8, "id3_ext", 0, 32);
        std.mem.writeInt(u32, out[at..][0..4], size, .big);
        at = @min(at + 4 + @as(usize, size), out.len);
    }

    const frames = choices.int(u8, "id3_frames", 0, 12);
    for (0..frames) |_| {
        const header_len: usize = if (out[3] == 2) 6 else 10;
        if (at + header_len + 2 > out.len) break;

        const id = ids[choices.int(u8, "id3_id", 0, ids.len - 1)];
        const id_len: usize = if (out[3] == 2) 3 else 4;
        @memcpy(out[at..][0..id_len], id[0..id_len]);

        const room = out.len - at - header_len;
        const size = @min(@as(usize, choices.int(u16, "id3_size", 0, 400)), room);
        if (out[3] == 2) {
            out[at + 3] = @truncate(size >> 16);
            out[at + 4] = @truncate(size >> 8);
            out[at + 5] = @truncate(size);
        } else if (out[3] == 3 or choices.chance("id3_plain_size", 3)) {
            std.mem.writeInt(u32, out[at + 4 ..][0..4], @intCast(size), .big);
            out[at + 8] = choices.int(u8, "id3_flag0", 0, 0xff);
            out[at + 9] = choices.int(u8, "id3_flag1", 0, 0xff);
        } else {
            var n: usize = 4;
            var remaining = size;
            while (n > 0) {
                n -= 1;
                out[at + 4 + n] = @truncate(remaining & 0x7f);
                remaining >>= 7;
            }
            out[at + 8] = choices.int(u8, "id3_flag0b", 0, 0xff);
            out[at + 9] = choices.int(u8, "id3_flag1b", 0, 0xff);
        }

        const payload = out[at + header_len ..][0..size];
        choices.fill("id3_payload", payload);
        // The first byte of a text frame names its encoding, and the parser
        // branches hard on it; leaving it to chance would spend most of the
        // budget on the undefined ones.
        if (payload.len > 0) payload[0] = choices.int(u8, "id3_encoding", 0, 4);
        at += header_len + size;
    }

    // The tag's own size, which the generator sometimes gets wrong on purpose.
    var stated = if (choices.chance("id3_bad_size", 4))
        @as(usize, choices.int(u16, "id3_wrong", 0, 4000))
    else
        at - 10;
    var n: usize = 4;
    while (n > 0) {
        n -= 1;
        out[6 + n] = @intCast(stated & 0x7f);
        stated >>= 7;
    }
    return at;
}

/// Everything a tag yields must be valid UTF-8, whatever it claimed to be
/// encoded in, and the parser must not leak whatever it was given.
fn checkId3(choices: Choices, gpa: std.mem.Allocator) !void {
    var raw: [4096]u8 = undefined;
    const len = if (choices.chance("id3_shaped", 3)) blk: {
        // Sometimes just arbitrary bytes, so the "this is not a tag at all"
        // paths keep being reached.
        const n: usize = choices.int(u16, "id3_raw_len", 0, 512);
        choices.fill("id3_raw", raw[0..n]);
        break :blk n;
    } else buildId3(choices, &raw);

    var tag = (try id3.parse(gpa, raw[0..len])) orelse return;
    defer tag.deinit();

    for (tag.frames) |frame| {
        try std.testing.expect(frame.name().len <= 4);
        for (frame.values) |value| {
            try std.testing.expect(std.unicode.utf8ValidateSlice(value));
        }
    }
    // The accessors must agree with themselves and not read out of bounds.
    for ([_]?[]const u8{
        tag.title(),    tag.artist(),  tag.album(), tag.albumArtist(),
        tag.composer(), tag.comment(), tag.year(),  tag.genre(),
    }) |maybe| {
        if (maybe) |text| try std.testing.expect(std.unicode.utf8ValidateSlice(text));
    }
    _ = tag.track();
    _ = tag.disc();
}

/// Tag detection and the encoder headers: neither may claim something of no
/// size, and neither may read past what it was given.
fn checkHeaders(choices: Choices) !void {
    var raw: [512]u8 = undefined;
    const len: usize = choices.int(u16, "header_len", 0, raw.len);
    choices.fill("header_bytes", raw[0..len]);
    // Arbitrary bytes almost never begin with a sync word -- one in four
    // thousand -- so left to chance none of this is ever reached.  Most of
    // the time, put one there.
    if (len >= 4 and !choices.chance("header_garbage", 8)) {
        raw[0] = 0xff;
        raw[1] |= 0xe0;
    }
    const input = raw[0..len];

    switch (tags.detect(input)) {
        .none, .incomplete => {},
        .found => |tag| try std.testing.expect(tag.size > 0),
    }

    if (input.len < 4) return;
    const header = Header.parse(input[0..4].*) orelse return;
    try std.testing.expect(header.sampleRate() > 0);
    try std.testing.expect(header.samplesPerFrame() > 0);
    if (header.bitRate()) |rate| {
        try std.testing.expect(rate > 0);
        try std.testing.expect(header.frameSize().? >= 4);
    } else {
        try std.testing.expect(header.frameSize() == null);
    }
    if (header.layer != .layer3) return;
    const info = vbr.parse(header, input) orelse return;
    if (info.duration(header)) |seconds| {
        try std.testing.expect(seconds >= 0 and std.math.isFinite(seconds));
    }
    if (info.seekOffset(0.5)) |offset| {
        try std.testing.expect(offset <= info.bytes.?);
    }
}

// ------------------------------------------- the seeded, deterministic run --

/// What a run of `checkLayer12` reached.  Layers I and II have far fewer
/// paths than Layer III, but the ones they do have are easy to leave
/// untouched: an encoder picks the grouped quantization classes only at low
/// bit rates, joint stereo only when it decides the channels are alike, and
/// never asks a frame for more bits than it holds.
const Layer12Coverage = struct {
    layer1: usize = 0,
    layer2: usize = 0,
    /// Subbands quantized with one of the three classes that pack a triple of
    /// values into a single code word.
    grouped: usize = 0,
    /// Subbands above the joint stereo bound, where the two channels share
    /// one set of samples but keep their own scalefactors.
    shared: usize = 0,
    /// Frames using the MPEG-2 allocation table rather than one of MPEG-1's.
    low_sampling: usize = 0,
    /// Frames whose allocations ask for more bits than the frame carries, so
    /// that the reader runs off the end and starts returning zeroes.  A
    /// corrupt or hostile stream reaches this and nothing else does.
    overrun: usize = 0,
    /// Frames handed a body shorter than the header says, which is not
    /// something the decoder itself produces -- it steps over a truncated
    /// final frame -- but which this function is entitled to survive.
    short: usize = 0,
    /// Which scalefactor selectors turned up, as a bit per value.  Layer II
    /// sends one of four, and two of them repeat a scalefactor across
    /// granules in a way the other two do not.
    selectors: u8 = 0,
    /// Which subband counts turned up, as a bit per distinct value.  There
    /// are five: 32 for Layer I, and 8, 12, 27 and 30 for Layer II depending
    /// on the bit rate, the sampling frequency and the version.
    band_counts: u64 = 0,
    /// Frames that decoded to something other than silence.
    audible: usize = 0,

    fn add(self: *Layer12Coverage, other: Layer12Coverage) void {
        self.layer1 += other.layer1;
        self.layer2 += other.layer2;
        self.grouped += other.grouped;
        self.shared += other.shared;
        self.low_sampling += other.low_sampling;
        self.overrun += other.overrun;
        self.short += other.short;
        self.selectors |= other.selectors;
        self.band_counts |= other.band_counts;
        self.audible += other.audible;
    }
};

/// Decode one arbitrary Layer I or Layer II frame body.
///
/// Every field a frame can carry is chosen freely, so the allocations name
/// classes an encoder would never pick, the scalefactors point anywhere in
/// their table, and the subbands between them routinely ask for more bits
/// than the frame has.  None of that is illegal for a decoder to be handed,
/// and all of it must produce finite, bounded samples.
fn checkLayer12(choices: Choices) !Layer12Coverage {
    const versions = [3]u2{ 0, 2, 3 }; // MPEG-2.5, MPEG-2, MPEG-1
    const raw: [4]u8 = .{
        0xff,
        0xe0 |
            (@as(u8, versions[choices.int(u8, "l12_version", 0, 2)]) << 3) |
            (@as(u8, if (choices.boolean("l12_layer")) 3 else 2) << 1) |
            1, // never CRC protected; the body is all payload
        (@as(u8, choices.int(u4, "l12_bitrate", 1, 14)) << 4) |
            (@as(u8, choices.int(u2, "l12_rate", 0, 2)) << 2),
        (@as(u8, choices.int(u2, "l12_mode", 0, 3)) << 6) |
            (@as(u8, choices.int(u2, "l12_mode_ext", 0, 3)) << 4),
    };
    const header = Header.parse(raw) orelse return .{};
    const size = header.frameSize() orelse return .{};
    if (size <= 4) return .{};

    var body: [1728]u8 = undefined; // the largest a frame body can be
    var length = @min(size - 4, body.len);
    var coverage: Layer12Coverage = .{};
    // One frame in eight is cut short.  The decoder steps over a truncated
    // final frame rather than decoding it, so this is defence rather than a
    // path in the current caller; it costs nothing to hold to it.
    if (choices.chance("l12_short", 8)) {
        length = choices.int(u11, "l12_length", 0, @intCast(length));
        coverage.short += 1;
    }
    choices.fill("l12_body", body[0..length]);

    if (header.layer == .layer1) coverage.layer1 += 1 else coverage.layer2 += 1;

    // Read the allocations a second time, on their own, to see what the
    // generator actually reached.
    var reader = BitReader.init(body[0..length]);
    var info: layer12.ScaleInfo = undefined;
    layer12.readScaleInfo(&reader, header, &info);
    if (header.version.isLowSamplingFrequency() and header.layer == .layer2) {
        coverage.low_sampling += 1;
    }
    // Walk the granules on this reader too, so that the overrun counted is
    // the whole frame's and not just its allocations: a frame runs out of
    // bits in its samples far more often than in its scalefactors.
    {
        var scratch: [2][layer12.granule_len]f32 = undefined;
        layer12.clearSilent(&info, header, &scratch);
        const granules: usize = if (header.layer == .layer1) 1 else 3;
        for (0..granules) |g| layer12.readGranule(&reader, &info, header, g, &scratch);
    }
    if (reader.overrun > 0) coverage.overrun += 1;
    if (info.total_bands < 64) {
        coverage.band_counts |= @as(u64, 1) << @intCast(info.total_bands);
    }
    for (0..info.total_bands) |band| {
        for (0..2) |ch| {
            const allocation = info.allocation[band * 2 + ch];
            if (allocation >= 17) coverage.grouped += 1;
            if (allocation != 0) {
                coverage.selectors |= @as(u8, 1) << @intCast(info.selection[band * 2 + ch]);
            }
        }
        if (band >= info.stereo_bands and header.channels() == 2) coverage.shared += 1;
    }

    // Decode twice, from fresh state, into buffers left holding different
    // rubbish.  Anything the decoder leaves untouched, or reads before
    // writing, shows up as a difference; anything it computes comes out the
    // same both times.
    var first: [layer12.max_samples * 2]f32 = undefined;
    var second: [layer12.max_samples * 2]f32 = undefined;
    @memset(std.mem.sliceAsBytes(first[0..]), 0x5a);
    @memset(std.mem.sliceAsBytes(second[0..]), 0xa5);

    var state: layer12.State = .{};
    const produced = layer12.decodeFrame(&state, header, body[0..length], &first);
    var again: layer12.State = .{};
    const produced_again = layer12.decodeFrame(&again, header, body[0..length], &second);
    try std.testing.expectEqual(produced, produced_again);

    const channels: usize = header.channels();
    try std.testing.expect(produced == layer12.granule_len or
        produced == layer12.granule_len * 3);
    const written = produced * channels;
    try std.testing.expectEqualSlices(
        u8,
        std.mem.sliceAsBytes(first[0..written]),
        std.mem.sliceAsBytes(second[0..written]),
    );

    for (first[0..written]) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        // A ceiling nothing a frame can say may reach.  Requantization
        // keeps a subband sample within the loudest scalefactor, which is 2;
        // matrixing sums 32 of those with coefficients no larger than one;
        // and dewindowing sums sixteen taps of D, whose worst column adds up
        // to 2.74.  That is 175, and arbitrary input here reaches 67.
        try std.testing.expect(@abs(sample) < 256);
        if (sample != 0) coverage.audible += 1;
    }
    return coverage;
}

/// What a run of `checkEncoder` reached.
///
/// An encoder chooses, so most of what matters here is whether the choosing
/// ever took its less common branches: the packed quantization classes, the
/// scalefactor selectors that repeat a value across granules, subbands given
/// everything and subbands given nothing.
const EncoderCoverage = struct {
    frames: usize = 0,
    /// Frames carrying the extra byte that holds the average bit rate exact.
    padded: usize = 0,
    /// Scalefactor selectors used, as a bit per value.  Three of the four say
    /// that granules share a scalefactor, and an encoder that never noticed
    /// they could would still be correct, just wasteful.
    selectors: u8 = 0,
    /// Subbands given one of the three classes that pack a triple of values
    /// into one code word.
    grouped: usize = 0,
    /// Subbands given nothing at all, and subbands given the most their table
    /// can name.  Both ends of the allocation loop.
    silent: usize = 0,
    maxed: usize = 0,
    /// Which shapes of input were tried, as a bit per shape.
    shapes: u8 = 0,
    mono: usize = 0,
    stereo: usize = 0,
    /// Rounds where the input was a tone with bits enough that the signal had
    /// to survive being coded, and did.
    ///
    /// Everything else here is structural, and structure is not enough: the
    /// worst fault this encoder has had produced frames that were correct in
    /// every measurable way and carried noise.  Only listening to the output
    /// catches that.
    fidelity: usize = 0,

    fn add(self: *EncoderCoverage, other: EncoderCoverage) void {
        self.frames += other.frames;
        self.padded += other.padded;
        self.selectors |= other.selectors;
        self.grouped += other.grouped;
        self.silent += other.silent;
        self.maxed += other.maxed;
        self.shapes |= other.shapes;
        self.mono += other.mono;
        self.stereo += other.stereo;
        self.fidelity += other.fidelity;
    }
};

/// The shapes of input the encoder is tried on.
///
/// Uniform noise alone is a poor test: it lights every subband at a similar
/// level, so the allocation loop takes the same path every time and the
/// interesting corners -- everything silent, one subband loud and the rest
/// empty, samples past full scale -- are never reached.
const Shape = enum {
    silence,
    noise,
    tone,
    /// Samples well outside -1 to 1, which an encoder is handed often enough.
    clipped,
    /// Almost nothing, with occasional impulses: the sparsest spectrum there
    /// is, and the one that leaves the most subbands empty.
    impulses,
    /// A constant, which is all in the lowest subband and nothing anywhere
    /// else.
    direct_current,
};

fn fillShape(
    choices: Choices,
    shape: Shape,
    rate: u32,
    channels: usize,
    at: usize,
    pcm: []f32,
) void {
    switch (shape) {
        .silence => @memset(pcm, 0),
        .noise => for (pcm) |*value| {
            value.* = @as(f32, @floatFromInt(choices.int(i16, "enc_noise", -20000, 20000))) /
                16384.0;
        },
        .clipped => for (pcm) |*value| {
            value.* = @as(f32, @floatFromInt(choices.int(i16, "enc_loud", -32768, 32767))) /
                4096.0;
        },
        .direct_current => {
            const level = @as(f32, @floatFromInt(choices.int(i16, "enc_dc", -30000, 30000))) /
                32768.0;
            @memset(pcm, level);
        },
        .impulses => {
            @memset(pcm, 0);
            const count = choices.int(u8, "enc_impulses", 1, 8);
            for (0..count) |_| {
                const where = choices.int(u16, "enc_impulse_at", 0, @intCast(pcm.len - 1));
                pcm[where] = if (choices.boolean("enc_impulse_sign")) 0.95 else -0.95;
            }
        },
        .tone => {
            // Loud, and in the middle of the band where hearing is sharpest.
            // The point of this shape is that its survival can be insisted
            // on, and a tone that is very quiet or very high need not survive
            // at all -- a model that spends bits on either is a bad model,
            // not a good one.  Those extremes are covered structurally by the
            // other shapes; 8 kHz is under the lowest supported Nyquist.
            const hz = @as(f64, @floatFromInt(choices.int(u16, "enc_hz", 100, 2000)));
            const amplitude = @as(f64, @floatFromInt(choices.int(u8, "enc_amp", 50, 160))) / 200.0;
            for (0..pcm.len / channels) |n| {
                // Counted from the start of the whole run, not of this frame,
                // so that the tone is one continuous signal rather than one
                // that jumps back to its start every frame.
                const t = 2.0 * std.math.pi * @as(f64, @floatFromInt(at + n)) /
                    @as(f64, @floatFromInt(rate));
                // A fundamental and two harmonics rather than a bare sine.
                // One sine is an unusually easy thing to code -- it occupies
                // a single scalefactor band and leaves the loops nothing to
                // trade off -- and an encoder can be badly wrong while still
                // getting it right.
                const value = amplitude * (0.6 * @sin(hz * t) +
                    0.3 * @sin(2.0 * hz * t) +
                    0.1 * @sin(3.0 * hz * t));
                for (0..channels) |ch| pcm[n * channels + ch] = @floatCast(value);
            }
        },
    }
}

/// Encode arbitrary samples and check that what comes out is a stream this
/// decoder reads back as the thing the encoder said it was making.
///
/// The encoder is the one part of this library that is allowed to choose, so
/// there is no reference to hold it against and no output to predict.  What
/// there is instead is a contract: whatever the input, every frame must be
/// the size its header claims, must parse as the scale information it was
/// written as, must decode, and must give back the right number of finite
/// samples.
fn checkEncoder(
    choices: Choices,
    gpa: std.mem.Allocator,
    shape: Shape,
    layer: u8,
) !EncoderCoverage {
    // Layer III here writes only MPEG-1 rates; Layer II reaches the low ones
    // as well.
    const rates = [_]u32{ 44100, 48000, 32000, 22050, 24000, 16000 };
    const count = if (layer == 2) rates.len else 3;
    const rate = rates[choices.int(u8, "enc_rate", 0, @intCast(count - 1))];
    const channels: u8 = if (choices.boolean("enc_mono")) 1 else 2;

    var offered: [14]u32 = undefined;
    const available = (if (layer == 2)
        encode12.bitRates(rate, &offered)
    else
        encode3.bitRates(rate, &offered)) catch return .{};
    // A tone is the one shape whose survival can be measured, so those rounds
    // are given the most bits the format offers and run long enough to
    // measure: the point of them is the fidelity check at the end, and a
    // round that cannot reach it is a round that tests nothing new.
    const bitrate = if (shape == .tone)
        // The upper half rather than the very top: plenty for a tone to
        // survive, but not so much that the loops never have to choose.
        available[
            choices.int(
                u8,
                "enc_bitrate",
                @intCast(available.len / 2),
                @intCast(available.len - 1),
            )
        ]
    else
        available[choices.int(u8, "enc_bitrate", 0, @intCast(available.len - 1))];

    var coverage: EncoderCoverage = .{};
    if (layer == 3) return try checkEncoder3(choices, gpa, shape, rate, channels, bitrate);

    var encoder = try encode12.Encoder.init(.{
        .sample_rate = rate,
        .channels = channels,
        .bitrate = bitrate,
    });

    if (channels == 1) coverage.mono += 1 else coverage.stereo += 1;

    coverage.shapes |= @as(u8, 1) << @intCast(@intFromEnum(shape));

    // Six frames rather than one, so that a tone has run long enough for
    // the filterbanks to fill and the fidelity check below to mean something.
    const frames = if (shape == .tone) 6 else choices.int(u8, "enc_frames", 1, 6);
    const per_frame = encode12.frame_samples * @as(usize, channels);
    const pcm = try gpa.alloc(f32, per_frame * frames);
    defer gpa.free(pcm);
    var stream: std.ArrayList(u8) = .empty;
    defer stream.deinit(gpa);
    var frame: [encode12.max_frame_bytes]u8 = undefined;

    for (0..frames) |f| {
        fillShape(
            choices,
            shape,
            rate,
            channels,
            f * encode12.frame_samples,
            pcm[f * per_frame ..][0..per_frame],
        );
        const size = try encoder.encodeFrame(pcm[f * per_frame ..][0..per_frame], &frame);
        coverage.frames += 1;

        // The header has to describe the frame that carries it.
        const header = Header.parse(frame[0..4].*) orelse return error.NotAHeader;
        try std.testing.expectEqual(size, header.frameSize().?);
        try std.testing.expectEqual(rate, header.sampleRate());
        try std.testing.expectEqual(bitrate, header.bitRate().?);
        try std.testing.expectEqual(channels, header.channels());
        try std.testing.expectEqual(encode12.subbands * 36, header.samplesPerFrame());
        if (header.padding) coverage.padded += 1;

        // Read back what was written with the decoder's own parser, which is
        // both a check that the two agree about the layout and the only way
        // to see what the allocation loop decided.
        var reader = BitReader.init(frame[4..size]);
        var info: layer12.ScaleInfo = undefined;
        layer12.readScaleInfo(&reader, header, &info);
        try std.testing.expect(reader.overrun == 0);
        for (0..info.total_bands) |band| {
            for (0..channels) |ch| {
                const allocation = info.allocation[band * 2 + ch];
                if (allocation == 0) {
                    coverage.silent += 1;
                    continue;
                }
                if (allocation >= 17) coverage.grouped += 1;
                if (allocation == 16) coverage.maxed += 1;
                coverage.selectors |= @as(u8, 1) << @intCast(info.selection[band * 2 + ch]);
            }
        }

        try stream.appendSlice(gpa, frame[0..size]);
    }

    var audio = try mp3.decodeAll(gpa, stream.items);
    defer audio.deinit();
    try std.testing.expectEqual(rate, audio.sample_rate);
    try std.testing.expectEqual(channels, audio.channels);
    try std.testing.expectEqual(
        @as(usize, frames) * encode12.frame_samples * channels,
        audio.samples.len,
    );
    for (audio.samples) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        try std.testing.expect(@abs(sample) < 64);
    }
    // Silence in has to be silence out: the scalefactors go to the quietest
    // they can, every code lands on the centre of its range, and nothing the
    // filterbank does to a run of zeroes makes them anything else.
    if (shape == .silence) {
        for (audio.samples) |sample| try std.testing.expectEqual(@as(f32, 0), sample);
    }
    // And a tone given bits enough has to come back out as that tone.
    if (shape == .tone) {
        if (fidelityOf(pcm, audio.samples, channels, 481)) |snr| {
            coverage.fidelity += 1;
            std.testing.expect(snr > fidelity_floor) catch |err| {
                std.debug.print("layer 2 tone survived at only {d:.2} dB\n", .{snr});
                return err;
            };
        }
    }
    return coverage;
}

/// The bar a coded tone has to clear, in decibels.
///
/// This is a "the signal is still there" check and not a quality one.  How
/// good the encoders sound is measured by `tools/check-encoder.py` against
/// the ceiling each layer's budget sets, which for Layer II at 192 kbit/s in
/// stereo is only about 13 dB to begin with -- so a bar set anywhere near
/// what a good encode reaches would fail on settings that are behaving
/// perfectly.  What this catches is the signal being destroyed rather than
/// merely coded coarsely, and destruction reads as a fraction of a decibel.
const fidelity_floor = 4.0;

/// How much of a tone survived being encoded and decoded again, in decibels,
/// or null when the run was too short or too poorly resourced to say.
///
/// The filterbanks delay the signal, and Layer III's transform delays it by a
/// granule more; both are fixed and known, so the comparison is against the
/// input shifted by that much.  Only a tone is worth checking this way -- the
/// other shapes are noise, impulses or silence, where a signal-to-noise ratio
/// against the input says little.
fn fidelityOf(
    input: []const f32,
    decoded: []const f32,
    channels: usize,
    delay: usize,
) ?f64 {
    const skip = (delay + 2400) * channels;
    if (decoded.len <= skip or input.len <= skip) return null;
    var signal: f64 = 0;
    var noise: f64 = 0;
    var n = skip;
    while (n < @min(decoded.len, input.len)) : (n += 1) {
        const want = input[n - delay * channels];
        const got = decoded[n];
        signal += @as(f64, want) * want;
        noise += @as(f64, got - want) * (got - want);
    }
    if (signal == 0) return null;
    return 10 * std.math.log10(signal / @max(noise, 1e-30));
}

/// Encode arbitrary samples as Layer III and check what comes back.
///
/// There is no allocation field to read back here the way there is for Layer
/// II, so what is checked is the contract: the header describes its own
/// frame, the side information parses, every granule's bits are inside the
/// frame that carries them, and the whole thing decodes to the right number
/// of finite samples.
fn checkEncoder3(
    choices: Choices,
    gpa: std.mem.Allocator,
    shape: Shape,
    rate: u32,
    channels: u8,
    bitrate: u32,
) !EncoderCoverage {
    var encoder = try encode3.Encoder.init(.{
        .sample_rate = rate,
        .channels = channels,
        .bitrate = bitrate,
    });

    var coverage: EncoderCoverage = .{};
    if (channels == 1) coverage.mono += 1 else coverage.stereo += 1;
    coverage.shapes |= @as(u8, 1) << @intCast(@intFromEnum(shape));

    // Six frames rather than one, so that a tone has run long enough for
    // the filterbanks to fill and the fidelity check below to mean something.
    const frames = if (shape == .tone) 6 else choices.int(u8, "enc_frames", 1, 6);
    const per_frame = encode3.frame_samples * @as(usize, channels);
    const pcm = try gpa.alloc(f32, per_frame * frames);
    defer gpa.free(pcm);
    var stream: std.ArrayList(u8) = .empty;
    defer stream.deinit(gpa);
    var frame: [encode3.max_frame_bytes]u8 = undefined;

    for (0..frames) |f| {
        fillShape(
            choices,
            shape,
            rate,
            channels,
            f * encode3.frame_samples,
            pcm[f * per_frame ..][0..per_frame],
        );
        const size = try encoder.encodeFrame(pcm[f * per_frame ..][0..per_frame], &frame);
        coverage.frames += 1;

        const header = Header.parse(frame[0..4].*) orelse return error.NotAHeader;
        try std.testing.expectEqual(size, header.frameSize().?);
        try std.testing.expectEqual(rate, header.sampleRate());
        try std.testing.expectEqual(bitrate, header.bitRate().?);
        try std.testing.expectEqual(channels, header.channels());
        if (header.padding) coverage.padded += 1;

        // The side information has to parse, and what it claims about the
        // granules has to fit in the frame that carries them.
        const info = try side_info.parse(header, frame[4..][0..header.sideInfoSize()]);
        try std.testing.expectEqual(@as(u16, 0), info.main_data_begin);
        var used: usize = 0;
        for (0..2) |gr| {
            for (0..channels) |ch| {
                const g = info.get(gr, ch);
                used += g.part2_3_length;
                try std.testing.expect(g.big_values <= 288);
                if (g.big_values == 288) coverage.maxed += 1;
                if (g.big_values == 0) coverage.silent += 1;
                coverage.selectors |= @as(u8, 1) << @intCast(g.count1table_select);
                if (g.table_select[0] >= 16) coverage.grouped += 1;
            }
        }
        const capacity = (size - 4 - header.sideInfoSize()) * 8;
        try std.testing.expect(used <= capacity);

        try stream.appendSlice(gpa, frame[0..size]);
    }

    var audio = try mp3.decodeAll(gpa, stream.items);
    defer audio.deinit();
    try std.testing.expectEqual(rate, audio.sample_rate);
    try std.testing.expectEqual(channels, audio.channels);
    try std.testing.expectEqual(
        @as(usize, frames) * encode3.frame_samples * channels,
        audio.samples.len,
    );
    for (audio.samples) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        try std.testing.expect(@abs(sample) < 64);
    }
    if (shape == .silence) {
        for (audio.samples) |sample| try std.testing.expectEqual(@as(f32, 0), sample);
    }
    if (shape == .tone) {
        if (fidelityOf(pcm, audio.samples, channels, 481 + 576)) |snr| {
            coverage.fidelity += 1;
            std.testing.expect(snr > fidelity_floor) catch |err| {
                std.debug.print("layer 3 tone survived at only {d:.2} dB\n", .{snr});
                return err;
            };
        }
    }
    return coverage;
}

/// What a run of `checkPsyModel` reached.
const PsyCoverage = struct {
    frames: usize = 0,
    /// Partitions left sitting at the threshold of hearing, because nothing
    /// in the signal could mask anything there, and partitions raised above
    /// it.  Both are ordinary and a run that never reached one of them would
    /// be testing half the model.
    at_hearing_floor: usize = 0,
    above_hearing_floor: usize = 0,
    /// Frames the model thought were worth spending bits on at all.
    audible: usize = 0,
    /// Bands where the whole of the energy may be left as noise, and bands
    /// demanding better than a thousandth of it.  These are the two ends of
    /// what the encoders are actually handed.  The hard clamp inside
    /// `maskToSignalPerBand` is a guard rather than a path -- the required
    /// ratio tops out near 24 dB, so nothing legitimate reaches it -- and is
    /// not counted here for that reason.
    ratio_wide_open: usize = 0,
    ratio_demanding: usize = 0,
    /// Wider than a byte because there are eight shapes and the mask needs a
    /// bit past the last of them.
    shapes: u16 = 0,
    rates: u8 = 0,

    fn add(self: *PsyCoverage, other: PsyCoverage) void {
        self.frames += other.frames;
        self.at_hearing_floor += other.at_hearing_floor;
        self.above_hearing_floor += other.above_hearing_floor;
        self.audible += other.audible;
        self.ratio_wide_open += other.ratio_wide_open;
        self.ratio_demanding += other.ratio_demanding;
        self.shapes |= other.shapes;
        self.rates |= other.rates;
    }
};

/// Shapes chosen for what they do to the arithmetic rather than to the
/// allocation: the model is a dense run of logarithms, divisions and a
/// spreading convolution, and what breaks that is range.
const PsyShape = enum {
    silence,
    noise,
    tone,
    /// A square wave at full scale: as much energy as the format can carry.
    square,
    /// Far past full scale.  A caller is not supposed to hand this over, and
    /// handing it over must not produce an infinity.
    enormous,
    /// Down near where floats stop being evenly spaced.
    minute,
    /// One sample in an otherwise empty window, which is the widest spectrum
    /// there is and the worst case for the prediction.
    impulse,
    /// Full scale flipping every sample: all the energy at the very top of
    /// the band, where the threshold of hearing is highest.
    nyquist,
};

fn fillPsyShape(choices: Choices, shape: PsyShape, rate: u32, at: usize, out: *[psymodel2.window_len]f32) void {
    switch (shape) {
        .silence => @memset(out, 0),
        .noise => for (out) |*value| {
            value.* = @as(f32, @floatFromInt(choices.int(i16, "psy_noise", -32768, 32767))) /
                32768.0;
        },
        .square => for (out, 0..) |*value, n| {
            value.* = if (((at + n) / 32) % 2 == 0) 1.0 else -1.0;
        },
        .enormous => for (out) |*value| {
            value.* = @as(f32, @floatFromInt(choices.int(i16, "psy_huge", -32768, 32767))) *
                1e20;
        },
        .minute => for (out) |*value| {
            value.* = @as(f32, @floatFromInt(choices.int(i16, "psy_tiny", -32768, 32767))) *
                1e-30;
        },
        .impulse => {
            @memset(out, 0);
            out[choices.int(u16, "psy_at", 0, psymodel2.window_len - 1)] = 1.0;
        },
        .nyquist => for (out, 0..) |*value, n| {
            value.* = if ((at + n) % 2 == 0) 1.0 else -1.0;
        },
        .tone => {
            const hz = @as(f64, @floatFromInt(choices.int(u16, "psy_hz", 20, 20000)));
            const amplitude = @as(f64, @floatFromInt(choices.int(u8, "psy_amp", 1, 200))) / 200.0;
            for (out, 0..) |*value, n| {
                const phase = 2.0 * std.math.pi * hz * @as(f64, @floatFromInt(at + n)) /
                    @as(f64, @floatFromInt(rate));
                value.* = @floatCast(amplitude * @sin(phase));
            }
        },
    }
}

/// Drive the psychoacoustic model over a run of frames and hold it to what it
/// promises.
///
/// The model is the one part of the encoders with no right answer to check
/// against -- it is a judgement, and two reasonable models disagree.  What can
/// be insisted on is that the judgement is a usable one: every threshold a
/// real, positive number no smaller than the threshold of hearing, every
/// ratio a proportion between nothing and everything, and the whole thing
/// unchanged by being run twice.
fn checkPsyModel(choices: Choices, shape: PsyShape) !PsyCoverage {
    const rates = [_]u32{ 44100, 48000, 32000, 22050, 24000, 16000 };
    const which = choices.int(u8, "psy_rate", 0, rates.len - 1);
    const rate = rates[which];

    var model = psymodel2.Model.init(rate);
    var coverage: PsyCoverage = .{};
    coverage.shapes |= @as(u16, 1) << @intCast(@intFromEnum(shape));
    coverage.rates |= @as(u8, 1) << @intCast(which);

    // Enough frames that the prediction has history behind it and the
    // pre-echo limit has something to reach back to.
    const psy_frames = 8;
    const frames = choices.int(u8, "psy_frames", 3, psy_frames);
    const hop = 576;

    // Generated once and kept, because the run has to be repeatable: the
    // shapes draw on the same source of choices the rest of the target does,
    // so asking for them twice gives two different signals and compares
    // nothing.
    var source: [psy_frames * hop]f32 = undefined;
    for (0..frames) |f| {
        var fresh: [psymodel2.window_len]f32 = undefined;
        fillPsyShape(choices, shape, rate, f * hop, &fresh);
        @memcpy(source[f * hop ..][0..hop], fresh[0..hop]);
    }

    var window: [psymodel2.window_len]f32 = @splat(0);
    var last: psymodel2.Result = .{};

    // The scalefactor band layout the Layer III encoder would hand over.
    const row = scalefactor_bands.bands[scalefactor_bands.index(0, 0)];
    var starts: [23]u16 = undefined;
    var at: u16 = 0;
    for (row.long_widths, 0..) |width, band| {
        starts[band] = at;
        at += width;
    }
    starts[22] = at;

    for (0..frames) |f| {
        const keep = psymodel2.window_len - hop;
        std.mem.copyForwards(f32, window[0..keep], window[hop..]);
        @memcpy(window[keep..], source[f * hop ..][0..hop]);

        var result: psymodel2.Result = .{};
        model.analyze(&window, &result);
        last = result;
        coverage.frames += 1;

        for (0..model.partition_count) |partition| {
            const threshold = result.threshold[partition];
            const energy = result.energy[partition];
            try std.testing.expect(std.math.isFinite(threshold));
            try std.testing.expect(std.math.isFinite(energy));
            try std.testing.expect(energy >= 0);
            // Nothing may be hidden below the quietest thing that can be
            // heard, whatever the signal does.
            try std.testing.expect(threshold >= model.quiet[partition]);
            if (threshold == model.quiet[partition]) {
                coverage.at_hearing_floor += 1;
            } else {
                coverage.above_hearing_floor += 1;
            }
        }
        try std.testing.expect(std.math.isFinite(result.entropy));
        try std.testing.expect(result.entropy >= 0);
        if (result.entropy > 0) coverage.audible += 1;

        // What the encoders are actually handed.
        var smr: [psymodel2.subbands]f32 = undefined;
        model.signalToMask(&result, &smr);
        for (smr) |value| try std.testing.expect(std.math.isFinite(value));

        var ratio: [21]f32 = undefined;
        model.maskToSignalPerBand(&result, starts[0..22], 576, &ratio);
        for (ratio) |value| {
            try std.testing.expect(std.math.isFinite(value));
            // A proportion of a band's energy, so never negative and never
            // more than the whole of it: an encoder told it could leave more
            // noise than there is signal would code nothing at all.
            try std.testing.expect(value > 0 and value <= 1.0);
            if (value == 1.0) coverage.ratio_wide_open += 1;
            if (value < 1e-3) coverage.ratio_demanding += 1;
        }
    }

    // The same input has to give the same answer, and a reset has to leave
    // nothing of what came before.  The tonality measure predicts each frame
    // from the two before it, so state is exactly what this model is made of
    // and exactly what a reset has to clear.
    {
        var again = psymodel2.Model.init(rate);

        // Feed it something else first, so that a reset has something to
        // undo, then clear it and replay the run from the start.
        var rubbish: [psymodel2.window_len]f32 = undefined;
        for (0..3) |f| {
            fillPsyShape(choices, .noise, rate, f * hop, &rubbish);
            var thrown: psymodel2.Result = .{};
            again.analyze(&rubbish, &thrown);
        }
        again.reset();
        again.reset(); // twice, because clearing what is already clear is not a change

        var replay: [psymodel2.window_len]f32 = @splat(0);
        var repeated: psymodel2.Result = .{};
        for (0..frames) |f| {
            const keep = psymodel2.window_len - hop;
            std.mem.copyForwards(f32, replay[0..keep], replay[hop..]);
            @memcpy(replay[keep..], source[f * hop ..][0..hop]);
            again.analyze(&replay, &repeated);
        }

        try std.testing.expectEqualSlices(
            u8,
            std.mem.sliceAsBytes(last.threshold[0..model.partition_count]),
            std.mem.sliceAsBytes(repeated.threshold[0..model.partition_count]),
        );
        try std.testing.expectEqual(last.entropy, repeated.entropy);
    }
    return coverage;
}

/// How many inputs each target sees.  `zig build test -Dfuzz-rounds=50000`
/// turns the same tests into a campaign.
const rounds = @import("build_options").fuzz_rounds;

fn seeded(comptime name: []const u8) std.Random.DefaultPrng {
    return std.Random.DefaultPrng.init(std.hash.Wyhash.hash(0x6d7033, name));
}

test "built streams decode without falling over" {
    var prng = seeded("built");
    var decoded: Decoded = .{};
    for (0..rounds) |_| {
        decoded.add(try checkBuiltStream(.{ .random = prng.random() }, std.testing.allocator));
    }

    // The generator has to actually reach the decoder, and reach past the
    // parts of it that reject a frame early.  Without this a change that
    // made every generated stream empty, or unsyncable, or rejected for want
    // of a bit reservoir, would leave the fuzzing silently testing nothing --
    // which is exactly what an earlier version of this file did.  The floors
    // are set an order of magnitude below what it currently manages.
    try std.testing.expect(decoded.frames > rounds);
    try std.testing.expect(decoded.audible > rounds);
}

test "Layer I and II frames survive arbitrary bodies" {
    var prng = seeded("layer12");
    var coverage: Layer12Coverage = .{};
    for (0..rounds) |_| {
        coverage.add(try checkLayer12(.{ .random = prng.random() }));
    }

    // As with the built streams, the floors are there so that a change which
    // stopped the generator reaching these paths fails loudly rather than
    // quietly testing nothing.  Each is well under what it currently manages.
    try std.testing.expect(coverage.layer1 > rounds / 4);
    try std.testing.expect(coverage.layer2 > rounds / 4);
    try std.testing.expect(coverage.audible > rounds);
    try std.testing.expect(coverage.grouped > rounds / 8);
    try std.testing.expect(coverage.shared > rounds / 8);
    try std.testing.expect(coverage.low_sampling > rounds / 32);
    try std.testing.expect(coverage.overrun > rounds / 8);
    try std.testing.expect(coverage.short > rounds / 32);
    // All four scalefactor selectors, and all five subband counts: 32 for
    // Layer I, and 8, 12, 27 and 30 for Layer II.
    try std.testing.expectEqual(@as(u8, 0b1111), coverage.selectors & 0b1111);
    const wanted_counts = (@as(u64, 1) << 8) | (@as(u64, 1) << 12) |
        (@as(u64, 1) << 27) | (@as(u64, 1) << 30) | (@as(u64, 1) << 32);
    try std.testing.expectEqual(wanted_counts, coverage.band_counts & wanted_counts);
}

test "the psychoacoustic model gives a usable answer for any signal" {
    var prng = seeded("psymodel");
    var coverage: PsyCoverage = .{};
    const shapes = std.enums.values(PsyShape);
    // The shapes are walked rather than drawn, so that even the shortest run
    // tries all of them.
    for (0..@max(rounds / 8, shapes.len)) |round| {
        coverage.add(try checkPsyModel(
            .{ .random = prng.random() },
            shapes[round % shapes.len],
        ));
    }

    // Every shape and every sampling rate, and the floors set an order of
    // magnitude below what a run reaches: over 2,500 rounds this sees 398,269
    // partitions left at the threshold of hearing, 565,164 raised above it,
    // 128,329 bands that may hide everything and 13,328 that may hide almost
    // nothing.
    const taken: usize = @max(rounds / 8, std.enums.values(PsyShape).len);
    const every_shape = (@as(u16, 1) << @intCast(std.enums.values(PsyShape).len)) - 1;
    try std.testing.expectEqual(every_shape, coverage.shapes);
    try std.testing.expectEqual(@as(u8, 0b111111), coverage.rates);
    try std.testing.expect(coverage.frames > taken * 2);
    try std.testing.expect(coverage.audible > taken / 2);
    // Both ends of the threshold: partitions nothing could mask anything in,
    // and partitions raised above the threshold of hearing by the signal.
    try std.testing.expect(coverage.at_hearing_floor > taken);
    try std.testing.expect(coverage.above_hearing_floor > taken);
    // And both ends of what the encoders are handed.
    try std.testing.expect(coverage.ratio_wide_open > taken);
    try std.testing.expect(coverage.ratio_demanding > taken / 4);
}

test "encoded streams decode back to the shape they claim" {
    var prng = seeded("encoder");
    var coverage: EncoderCoverage = .{};
    const shapes = std.enums.values(Shape);
    // Each round encodes and decodes up to four whole frames, so this one is
    // far heavier than the others and runs proportionally fewer times.  The
    // shapes are walked in turn rather than drawn, so that even the shortest
    // run tries all of them; the fuzzer's own entry point still chooses.
    // The layer advances once per pass over the shapes rather than once per
    // round.  Alternating both together locks them to each other whenever the
    // shape count is even -- which it is -- so half the pairings never come
    // up at all, and the tone never met Layer III.
    for (0..@max(rounds / 40, shapes.len * 2)) |round| {
        coverage.add(try checkEncoder(
            .{ .random = prng.random() },
            std.testing.allocator,
            shapes[round % shapes.len],
            if ((round / shapes.len) % 2 == 0) 2 else 3,
        ));
    }

    // Floors, so that a change which stopped reaching these fails rather than
    // quietly testing nothing.
    // Set an order of magnitude below what it currently manages: over a
    // thousand encoder rounds this reaches 45,802 grouped subbands, 30,694
    // silent ones, 2,542 at the top of their table and 316 padded frames.
    const taken = @max(rounds / 40, std.enums.values(Shape).len * 2);
    try std.testing.expect(coverage.frames >= taken);
    try std.testing.expect(coverage.mono > 0);
    try std.testing.expect(coverage.stereo > 0);
    try std.testing.expect(coverage.padded > 0);
    try std.testing.expect(coverage.grouped > taken);
    try std.testing.expect(coverage.silent > taken);
    try std.testing.expect(coverage.maxed > taken / 4);
    // Structure is not enough on its own: the encoder's worst fault made
    // frames that were correct in every measurable way and carried noise.
    // One shape in six is the tone, and each shape meets both layers, so a
    // run that walks the shapes twice reaches this at least twice.
    try std.testing.expect(coverage.fidelity > taken / 12);
    // All four scalefactor selectors, and every shape of input.
    try std.testing.expectEqual(@as(u8, 0b1111), coverage.selectors & 0b1111);
    const every_shape = (@as(u8, 1) << @intCast(std.enums.values(Shape).len)) - 1;
    try std.testing.expectEqual(every_shape, coverage.shapes);
}

test "arbitrary bytes decode without falling over" {
    var prng = seeded("arbitrary");
    var scratch: [4096]u8 = undefined;
    for (0..rounds) |_| {
        try checkArbitraryBytes(.{ .random = prng.random() }, &scratch);
    }
}

test "side information survives arbitrary bytes" {
    var prng = seeded("side info");
    for (0..rounds) |_| try checkSideInfo(.{ .random = prng.random() });
}

test "Huffman decoding survives arbitrary bits" {
    var prng = seeded("huffman");
    for (0..rounds) |_| try checkHuffman(.{ .random = prng.random() });
}

test "frame, tag and encoder headers survive arbitrary bytes" {
    var prng = seeded("headers");
    for (0..rounds) |_| try checkHeaders(.{ .random = prng.random() });
}

test "the filterbanks agree with the standard's own arithmetic" {
    var prng = seeded("filterbanks");
    // Each round is up to 24 granules of both filterbanks, so this one is
    // heavier than the others and runs proportionally fewer times.
    for (0..@max(rounds / 20, 1)) |_| {
        try checkFilterbanks(.{ .random = prng.random() });
    }
}

test "encoder tables of contents survive being wrong about themselves" {
    var prng = seeded("vbr");
    for (0..rounds) |_| try checkVbr(.{ .random = prng.random() });
}

test "the one shot interface survives arbitrary streams" {
    var prng = seeded("decode all");
    for (0..rounds) |_| {
        try checkDecodeAll(.{ .random = prng.random() }, std.testing.allocator);
    }
}

// `decodeAll` grows a buffer as it goes, so every point it can fail at has to
// leave nothing behind.
test "the one shot interface leaks nothing when it runs out of memory" {
    const Case = struct {
        fn run(gpa: std.mem.Allocator, bytes: []const u8) !void {
            var audio = mp3.decodeAll(gpa, bytes) catch |err| {
                if (err == error.NoAudio) return;
                return err;
            };
            audio.deinit();
        }
    };
    var prng = seeded("decode all oom");
    for (0..8) |_| {
        var buffer: [2048]u8 = undefined;
        const len = buildStream(.{ .random = prng.random() }, &buffer);
        try std.testing.checkAllAllocationFailures(
            std.testing.allocator,
            Case.run,
            .{buffer[0..len]},
        );
    }
}

test "the fast bit reader agrees with the plain one" {
    var prng = seeded("bits");
    for (0..rounds) |_| try checkBitReader(.{ .random = prng.random() });
}

test "the register cache agrees with the plain reader" {
    var prng = seeded("cache");
    for (0..rounds) |_| try checkBitCache(.{ .random = prng.random() });
}

test "resetting at arbitrary points leaves the decoder working" {
    var prng = seeded("resets");
    for (0..rounds) |_| try checkResets(.{ .random = prng.random() });
}

test "ID3 tags survive arbitrary bytes" {
    var prng = seeded("id3");
    for (0..rounds) |_| {
        try checkId3(.{ .random = prng.random() }, std.testing.allocator);
    }
}

// The tag parser allocates, so it has to be right when allocation fails --
// every early return has to release what it had taken.  This runs tags with
// the allocator failing at each point in turn.
test "the ID3 parser leaks nothing when it runs out of memory" {
    const Case = struct {
        fn run(gpa: std.mem.Allocator, bytes: []const u8) !void {
            var tag = (try id3.parse(gpa, bytes)) orelse return;
            tag.deinit();
        }
    };

    var prng = seeded("id3 oom");
    for (0..24) |_| {
        var raw: [1024]u8 = undefined;
        const len = buildId3(.{ .random = prng.random() }, &raw);
        try std.testing.checkAllAllocationFailures(
            std.testing.allocator,
            Case.run,
            .{raw[0..len]},
        );
    }
}

// ------------------------------------------------- the fuzzer's entry points --

fn fuzzBuiltStream(_: void, smith: *Smith) anyerror!void {
    _ = try checkBuiltStream(.{ .smith = smith }, std.testing.allocator);
}

fn fuzzArbitraryBytes(_: void, smith: *Smith) anyerror!void {
    var scratch: [4096]u8 = undefined;
    try checkArbitraryBytes(.{ .smith = smith }, &scratch);
}

fn fuzzLayer12(_: void, smith: *Smith) anyerror!void {
    _ = try checkLayer12(.{ .smith = smith });
}

fn fuzzPsyModel(_: void, smith: *Smith) anyerror!void {
    const choices: Choices = .{ .smith = smith };
    const shapes = std.enums.values(PsyShape);
    const shape = shapes[choices.int(u8, "psy_shape", 0, @intCast(shapes.len - 1))];
    _ = try checkPsyModel(choices, shape);
}

fn fuzzEncoder(_: void, smith: *Smith) anyerror!void {
    const choices: Choices = .{ .smith = smith };
    const shapes = std.enums.values(Shape);
    const shape = shapes[choices.int(u8, "enc_shape", 0, @intCast(shapes.len - 1))];
    const layer: u8 = if (choices.boolean("enc_layer")) 2 else 3;
    _ = try checkEncoder(choices, std.testing.allocator, shape, layer);
}

fn fuzzSideInfo(_: void, smith: *Smith) anyerror!void {
    try checkSideInfo(.{ .smith = smith });
}

fn fuzzHuffman(_: void, smith: *Smith) anyerror!void {
    try checkHuffman(.{ .smith = smith });
}

fn fuzzHeaders(_: void, smith: *Smith) anyerror!void {
    try checkHeaders(.{ .smith = smith });
}

fn fuzzId3(_: void, smith: *Smith) anyerror!void {
    try checkId3(.{ .smith = smith }, std.testing.allocator);
}

fn fuzzBitReader(_: void, smith: *Smith) anyerror!void {
    try checkBitReader(.{ .smith = smith });
}

fn fuzzBitCache(_: void, smith: *Smith) anyerror!void {
    try checkBitCache(.{ .smith = smith });
}

fn fuzzResets(_: void, smith: *Smith) anyerror!void {
    try checkResets(.{ .smith = smith });
}

fn fuzzFilterbanks(_: void, smith: *Smith) anyerror!void {
    try checkFilterbanks(.{ .smith = smith });
}

fn fuzzVbr(_: void, smith: *Smith) anyerror!void {
    try checkVbr(.{ .smith = smith });
}

fn fuzzDecodeAll(_: void, smith: *Smith) anyerror!void {
    try checkDecodeAll(.{ .smith = smith }, std.testing.allocator);
}

test "fuzz built streams" {
    try std.testing.fuzz({}, fuzzBuiltStream, .{});
}

test "fuzz arbitrary bytes" {
    try std.testing.fuzz({}, fuzzArbitraryBytes, .{});
}

test "fuzz Layer I and II frames" {
    try std.testing.fuzz({}, fuzzLayer12, .{});
}

test "fuzz the psychoacoustic model" {
    try std.testing.fuzz({}, fuzzPsyModel, .{});
}

test "fuzz encoding" {
    try std.testing.fuzz({}, fuzzEncoder, .{});
}

test "fuzz side information" {
    try std.testing.fuzz({}, fuzzSideInfo, .{});
}

test "fuzz Huffman decoding" {
    try std.testing.fuzz({}, fuzzHuffman, .{});
}

test "fuzz frame, tag and encoder headers" {
    try std.testing.fuzz({}, fuzzHeaders, .{});
}

test "fuzz ID3 tags" {
    try std.testing.fuzz({}, fuzzId3, .{});
}

test "fuzz the bit reader against the plain one" {
    try std.testing.fuzz({}, fuzzBitReader, .{});
}

test "fuzz the register cache against the plain reader" {
    try std.testing.fuzz({}, fuzzBitCache, .{});
}

test "fuzz decoding across resets" {
    try std.testing.fuzz({}, fuzzResets, .{});
}

test "fuzz the filterbanks against the standard's arithmetic" {
    try std.testing.fuzz({}, fuzzFilterbanks, .{});
}

test "fuzz encoder tables of contents" {
    try std.testing.fuzz({}, fuzzVbr, .{});
}

test "fuzz the one shot interface" {
    try std.testing.fuzz({}, fuzzDecodeAll, .{});
}
