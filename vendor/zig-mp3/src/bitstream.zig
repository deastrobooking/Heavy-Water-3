// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! A most-significant-bit-first reader over a byte slice.
//!
//! Everything in an MPEG audio bitstream is packed this way, and almost
//! nothing in it is byte aligned, so the whole decoder reads through this.
//!
//! Reads past the end of the slice are not errors.  They return zero bits and
//! are counted in `overrun`, because a Layer III granule routinely asks for a
//! few more bits than its `part2_3_length` allows -- a corrupt or truncated
//! frame should degrade into silence rather than stop the stream, and the
//! caller checks `overrun` when it wants to know.

const std = @import("std");

const Reader = @This();

bytes: []const u8,
/// Read position, in bits from the start of `bytes`.
pos: usize = 0,
/// Bits that have been read past the end of `bytes`.
overrun: usize = 0,

pub fn init(bytes: []const u8) Reader {
    return .{ .bytes = bytes };
}

/// Eight bytes from `index`, most significant first, zero filled past the
/// end of `bytes`.
inline fn load(bytes: []const u8, index: usize) u64 {
    if (index + 8 <= bytes.len) return std.mem.readInt(u64, bytes[index..][0..8], .big);
    var word: u64 = 0;
    for (0..8) |k| {
        const at = index + k;
        word = (word << 8) | (if (at < bytes.len) bytes[at] else 0);
    }
    return word;
}

/// Bits between the read position and the end of the slice, saturating at
/// zero once the reader has overrun.
pub fn remaining(self: Reader) usize {
    const total = self.bytes.len * 8;
    return if (self.pos >= total) 0 else total - self.pos;
}

/// Read `n` bits, 0 <= n <= 32, and advance.
pub fn read(self: *Reader, n: u6) u32 {
    const value = self.peek(n);
    self.skip(n);
    return value;
}

/// Read a single bit and advance.
pub fn readBit(self: *Reader) u1 {
    return @truncate(self.read(1));
}

/// Read `n` bits without advancing.  Bits past the end read as zero and are
/// not counted as an overrun, since nothing has been consumed.
///
/// Eight bytes are loaded at once and shifted into place.  Huffman decoding
/// peeks before every code word, so this is the decoder's most travelled
/// path; taking the bits a byte at a time costs several times as much.
pub fn peek(self: Reader, n: u6) u32 {
    std.debug.assert(n <= 32);
    if (n == 0) return 0;

    const index = self.pos >> 3;
    const used: u6 = @as(u3, @truncate(self.pos));

    // Thirty-two bits starting at any bit of a byte span at most five bytes,
    // so eight is always enough and the shift below never runs off the end.
    const word = load(self.bytes, index);
    return @truncate((word << used) >> @intCast(64 - @as(u7, n)));
}

/// Advance by `n` bits without decoding them.
pub fn skip(self: *Reader, n: usize) void {
    const total = self.bytes.len * 8;
    self.pos += n;
    if (self.pos > total) self.overrun += self.pos - @max(total, self.pos - n);
}

/// Move the read position to an absolute bit offset.
pub fn seek(self: *Reader, bit: usize) void {
    self.pos = bit;
}

/// Advance to the next byte boundary, if not already on one.
pub fn alignToByte(self: *Reader) void {
    self.pos = (self.pos + 7) & ~@as(usize, 7);
}

test "reads bits most significant first" {
    var r = init(&[_]u8{ 0b1011_0010, 0b0100_1111 });
    try std.testing.expectEqual(@as(u32, 0b101), r.read(3));
    try std.testing.expectEqual(@as(u32, 0b10010), r.read(5));
    try std.testing.expectEqual(@as(u32, 0b0100_1111), r.read(8));
    try std.testing.expectEqual(@as(usize, 0), r.overrun);
    try std.testing.expectEqual(@as(usize, 0), r.remaining());
}

test "reads across byte boundaries" {
    var r = init(&[_]u8{ 0xff, 0x00, 0xff, 0x00 });
    try std.testing.expectEqual(@as(u32, 0xf), r.read(4));
    try std.testing.expectEqual(@as(u32, 0xf00f), r.read(16));
    try std.testing.expectEqual(@as(u32, 0xf00), r.read(12));
}

test "reads a full 32 bits" {
    var r = init(&[_]u8{ 0xde, 0xad, 0xbe, 0xef });
    try std.testing.expectEqual(@as(u32, 0xdeadbeef), r.read(32));
}

test "past the end reads zeroes and counts the overrun" {
    var r = init(&[_]u8{0b1100_0000});
    try std.testing.expectEqual(@as(u32, 0b11), r.read(2));
    try std.testing.expectEqual(@as(u32, 0), r.read(16));
    try std.testing.expectEqual(@as(usize, 10), r.overrun);
    try std.testing.expectEqual(@as(usize, 0), r.remaining());
}

test "peek does not advance and does not count an overrun" {
    var r = init(&[_]u8{0xa5});
    try std.testing.expectEqual(@as(u32, 0xa), r.peek(4));
    // Past the end the peek is zero-filled, as a read would be.
    try std.testing.expectEqual(@as(u32, 0xa500), r.peek(16));
    try std.testing.expectEqual(@as(usize, 0), r.pos);
    try std.testing.expectEqual(@as(usize, 0), r.overrun);
    try std.testing.expectEqual(@as(u32, 0xa), r.read(4));
}

test "alignToByte only moves when unaligned" {
    var r = init(&[_]u8{ 0, 0 });
    r.alignToByte();
    try std.testing.expectEqual(@as(usize, 0), r.pos);
    _ = r.read(1);
    r.alignToByte();
    try std.testing.expectEqual(@as(usize, 8), r.pos);
    r.alignToByte();
    try std.testing.expectEqual(@as(usize, 8), r.pos);
}

/// A bit cache for the decoder's innermost loop.
///
/// `Reader` loads eight bytes for every read.  That is fine where reads are
/// occasional, but Huffman decoding is a chain of dependent reads -- each
/// one's position depends on the width of the last -- so the load's latency
/// lands on the critical path of every single one and is most of what they
/// cost.  This keeps the next 57 bits or more in a register, so a read is a
/// shift, and touches memory about once per code word instead of three times.
///
/// The caller drives the refilling: call `refill` once, then read at most 57
/// bits before calling it again.  That is enough for a Huffman code word of
/// 19 bits and two escaped values of 14 apiece, which is the widest thing the
/// format asks for in one go.
pub const Cache = struct {
    bytes: []const u8,
    /// The next bits of the stream, most significant first.
    bits: u64 = 0,
    /// How many of `bits`'s top bits are valid.
    have: u32 = 0,
    /// Index of the next byte to pull in.
    next: usize = 0,

    /// Start reading at `bit`, which need not be byte aligned.
    pub fn init(bytes: []const u8, bit: usize) Cache {
        var self: Cache = .{ .bytes = bytes, .next = bit >> 3 };
        self.refill();
        // Only the offset within the byte: `refill` started at a byte
        // boundary, so that is what has to be thrown away.
        self.skip(@as(u3, @truncate(bit)));
        return self;
    }

    /// Bit position in `bytes` of the next unread bit.
    pub fn position(self: Cache) usize {
        return self.next * 8 - self.have;
    }

    /// Bring the cache up to at least 57 valid bits.  Past the end of the
    /// input this shifts in zeroes, matching `Reader`.
    ///
    /// A byte at a time: it runs two or three times per code word and a
    /// single wider load measured no faster, so this is the version that is
    /// obviously right.  `skip` shifts zeroes in at the bottom, which is what
    /// makes the `or` safe.
    pub inline fn refill(self: *Cache) void {
        while (self.have <= 56) {
            const byte: u64 = if (self.next < self.bytes.len) self.bytes[self.next] else 0;
            self.bits |= byte << @intCast(56 - self.have);
            self.next += 1;
            self.have += 8;
        }
    }

    /// The next `n` bits, 0 <= n <= 32, without consuming them.  There must
    /// be that many in hand.
    pub inline fn peek(self: Cache, n: u6) u32 {
        if (n == 0) return 0;
        return @truncate(self.bits >> @intCast(64 - @as(u7, n)));
    }

    /// The next 32 bits, for handing to a decoder that reports back how many
    /// of them it used.
    pub inline fn peek32(self: Cache) u32 {
        return @truncate(self.bits >> 32);
    }

    pub inline fn skip(self: *Cache, n: u6) void {
        self.bits <<= n;
        self.have -= n;
    }

    pub inline fn read(self: *Cache, n: u6) u32 {
        if (n == 0) return 0;
        const value = self.peek(n);
        self.skip(n);
        return value;
    }
};

test "the cache reads what the reader reads" {
    var prng = std.Random.DefaultPrng.init(0xb175);
    const random = prng.random();

    for (0..2000) |_| {
        var bytes: [40]u8 = undefined;
        random.bytes(&bytes);
        const len = random.uintAtMost(usize, bytes.len);
        const start = random.uintAtMost(usize, len * 8);

        var reader = init(bytes[0..len]);
        reader.seek(start);
        var cache = Cache.init(bytes[0..len], start);
        try std.testing.expectEqual(reader.pos, cache.position());

        var budget: u32 = 0;
        for (0..30) |_| {
            const n: u6 = @intCast(random.uintAtMost(u8, 32));
            // The caller is responsible for refilling; do it the way the
            // decoder does, once per group of reads.
            if (budget < n) {
                cache.refill();
                budget = 57;
            }
            budget -= n;
            try std.testing.expectEqual(reader.peek(n), cache.peek(n));
            try std.testing.expectEqual(reader.read(n), cache.read(n));
            try std.testing.expectEqual(reader.pos, cache.position());
        }
    }
}
