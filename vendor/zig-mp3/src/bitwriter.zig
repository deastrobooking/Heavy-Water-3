// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! A most-significant-bit-first bit writer: the mirror of `bitstream.zig`.
//!
//! Writes past the end of the buffer are dropped rather than reported, and
//! counted, in the same spirit as the reader's reads past the end returning
//! zeroes.  An encoder that has worked out its bit budget correctly never
//! overruns, and one that has not should fail its own check rather than
//! scribble past the end of a frame.

const std = @import("std");

const Writer = @This();

bytes: []u8,
/// Write position, in bits from the start of `bytes`.
pos: usize = 0,
/// Bits that would have gone past the end of `bytes`.
overrun: usize = 0,

pub fn init(bytes: []u8) Writer {
    @memset(bytes, 0);
    return .{ .bytes = bytes };
}

/// Write the low `n` bits of `value`, most significant first.
pub fn write(self: *Writer, value: u32, n: u6) void {
    var left = n;
    while (left > 0) {
        left -= 1;
        const bit: u1 = @truncate(value >> @intCast(left));
        self.writeBit(bit);
    }
}

pub fn writeBit(self: *Writer, bit: u1) void {
    if (self.pos >= self.bytes.len * 8) {
        self.overrun += 1;
        return;
    }
    // The buffer starts zeroed and is written once, so setting the one bits
    // is enough and there is nothing to clear.
    if (bit != 0) {
        self.bytes[self.pos / 8] |= @as(u8, 0x80) >> @intCast(self.pos % 8);
    }
    self.pos += 1;
}

/// Bits between the write position and the end of the buffer, saturating at
/// zero once the writer has overrun.
pub fn remaining(self: Writer) usize {
    const total = self.bytes.len * 8;
    return if (self.pos >= total) 0 else total - self.pos;
}

/// Advance to the next byte boundary, leaving zeroes behind.
pub fn alignToByte(self: *Writer) void {
    while (self.pos % 8 != 0) self.writeBit(0);
}

const testing = std.testing;
const Reader = @import("bitstream.zig");

test "what is written reads back" {
    var buffer: [64]u8 = undefined;
    var writer = Writer.init(&buffer);

    var prng = std.Random.DefaultPrng.init(0xb175);
    const random = prng.random();
    var widths: [40]u6 = undefined;
    var values: [40]u32 = undefined;
    var total: usize = 0;
    for (&widths, &values) |*width, *value| {
        width.* = random.intRangeAtMost(u6, 1, 24);
        value.* = random.int(u32) & (@as(u32, 0xffff_ffff) >> @intCast(32 - @as(u7, width.*)));
        if (total + width.* > buffer.len * 8) {
            width.* = 0;
            value.* = 0;
        }
        total += width.*;
        writer.write(value.*, width.*);
    }
    try testing.expectEqual(@as(usize, 0), writer.overrun);
    try testing.expectEqual(total, writer.pos);

    var reader = Reader.init(&buffer);
    for (widths, values) |width, value| {
        try testing.expectEqual(value, reader.read(width));
    }
}

test "bits land most significant first" {
    var buffer: [2]u8 = undefined;
    var writer = Writer.init(&buffer);
    writer.write(0b1011, 4);
    writer.write(0b0001, 4);
    try testing.expectEqual(@as(u8, 0b1011_0001), buffer[0]);
}

test "writing past the end is counted, not written" {
    var buffer: [1]u8 = undefined;
    var writer = Writer.init(&buffer);
    writer.write(0xff, 8);
    try testing.expectEqual(@as(usize, 0), writer.remaining());
    writer.write(0xff, 5);
    try testing.expectEqual(@as(usize, 5), writer.overrun);
    try testing.expectEqual(@as(u8, 0xff), buffer[0]);
}

test "aligning writes zeroes to the byte boundary" {
    var buffer: [2]u8 = undefined;
    var writer = Writer.init(&buffer);
    writer.write(0b111, 3);
    writer.alignToByte();
    try testing.expectEqual(@as(usize, 8), writer.pos);
    try testing.expectEqual(@as(u8, 0b1110_0000), buffer[0]);
}
