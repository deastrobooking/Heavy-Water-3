// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Layer III Huffman decoding.
//!
//! Each table is turned at compile time into a 9-bit lookup table with a
//! binary tree hanging off the entries whose codes are longer than that.  Code
//! words run from 1 to 19 bits but the short ones dominate overwhelmingly, so
//! the common case is a single indexed load and the tree is walked a bit at a
//! time only for the rare long code.

const std = @import("std");

const BitReader = @import("bitstream.zig");
const data = @import("tables/huffman.zig");

/// Bits consumed by one lookup.  Nine covers every code word in tables 1-12,
/// 24-31 and both count1 tables outright.
const lut_bits = 9;

/// A decoded pair of quantized values, before linbits and signs are applied.
pub const Pair = struct { x: u8, y: u8 };

/// A lookup table entry, packed into a word.
///
/// Four bytes rather than the six a struct of these fields takes: the table
/// is read once per code word and the whole of it is hot, so its size is its
/// speed.  A resolved entry holds the code length and the pair; an entry for
/// a code too long to fit holds a zero length and where to continue.
const Entry = packed struct(u32) {
    /// Zero when the code is longer than `lut_bits`.
    len: u8,
    x: u8,
    y: u8,
    node: u8,
};

/// One internal node of the overflow tree.  A child value with the high bit
/// set is a leaf holding `(x << 4) | y`; otherwise it indexes `Table.nodes`.
const Node = [2]u16;

const leaf_flag: u16 = 0x8000;

pub const Table = struct {
    lut: [1 << lut_bits]Entry,
    nodes: [256]Node,

    /// A decoded pair together with the width of the code word it came from.
    pub const Code = struct { x: u8, y: u8, len: u8 };

    /// Decode one code word out of `word`, whose most significant bit is the
    /// next bit of the stream, without consuming anything.
    ///
    /// Reporting the width rather than advancing is what lets a caller that
    /// holds the stream in a register consume the code word and the sign bits
    /// that follow it with shifts alone.
    pub inline fn decodeWord(self: *const Table, word: u32) Code {
        const entry = self.lut[word >> (32 - lut_bits)];
        if (entry.len != 0) return .{ .x = entry.x, .y = entry.y, .len = entry.len };

        var node: u16 = entry.node;
        var used: u8 = lut_bits;
        while (true) {
            const bit: u1 = @truncate(word >> @intCast(31 - used));
            used += 1;
            const child = self.nodes[node][bit];
            if (child & leaf_flag != 0) {
                return .{
                    .x = @truncate(child >> 4),
                    .y = @truncate(child & 0xf),
                    .len = used,
                };
            }
            node = child;
        }
    }

    /// Read one code word and return the pair it stands for.
    pub fn decode(self: *const Table, reader: *BitReader) Pair {
        const code = self.decodeWord(reader.peek(32));
        reader.skip(code.len);
        return .{ .x = code.x, .y = code.y };
    }
};

fn build(comptime codes: []const data.Code) Table {
    @setEvalBranchQuota(100_000);
    var table: Table = .{
        .lut = @splat(.{ .len = 0, .x = 0, .y = 0, .node = 0 }),
        .nodes = @splat(.{ 0, 0 }),
    };

    // Node zero is the root, so zero doubles as "no child here yet".
    var used: u16 = 1;
    for (codes) |code| {
        var node: u16 = 0;
        var depth: u8 = 0;
        while (depth + 1 < code.len) : (depth += 1) {
            const bit = (code.code >> @intCast(code.len - 1 - depth)) & 1;
            if (table.nodes[node][bit] == 0) {
                table.nodes[node][bit] = used;
                used += 1;
            }
            node = table.nodes[node][bit];
        }
        const last = code.code & 1;
        std.debug.assert(table.nodes[node][last] == 0);
        table.nodes[node][last] = leaf_flag | (@as(u16, code.x) << 4) | code.y;
    }
    // A complete prefix code over at most 256 symbols has at most 255
    // internal nodes, which is what lets an entry hold one in a byte.
    std.debug.assert(used <= 256);

    for (codes) |code| {
        if (code.len <= lut_bits) {
            // Every index whose leading bits are this code word resolves to it.
            const shift = lut_bits - code.len;
            const first = code.code << @intCast(shift);
            for (0..@as(usize, 1) << @intCast(shift)) |i| {
                table.lut[first + i] = .{ .len = code.len, .x = code.x, .y = code.y, .node = 0 };
            }
        } else {
            // Park the walk at the node `lut_bits` bits in.  Several long
            // codes share a prefix and so share this entry; they agree on it.
            var node: u16 = 0;
            for (0..lut_bits) |depth| {
                const bit = (code.code >> @intCast(code.len - 1 - depth)) & 1;
                node = table.nodes[node][bit];
            }
            const index = code.code >> @intCast(code.len - lut_bits);
            // Internal nodes number fewer than 256, so the index fits a byte.
            table.lut[index] = .{ .len = 0, .x = 0, .y = 0, .node = @intCast(node) };
        }
    }
    return table;
}

const table_1 = build(&data.table_1);
const table_2 = build(&data.table_2);
const table_3 = build(&data.table_3);
const table_5 = build(&data.table_5);
const table_6 = build(&data.table_6);
const table_7 = build(&data.table_7);
const table_8 = build(&data.table_8);
const table_9 = build(&data.table_9);
const table_10 = build(&data.table_10);
const table_11 = build(&data.table_11);
const table_12 = build(&data.table_12);
const table_13 = build(&data.table_13);
const table_15 = build(&data.table_15);
const table_16 = build(&data.table_16);
const table_24 = build(&data.table_24);
const table_32 = build(&data.table_32);
const table_33 = build(&data.table_33);

/// A big-value table as chosen by `table_select` in the side information.
pub const BigValue = struct {
    table: *const Table,
    /// Extra magnitude bits read when a decoded value is 15.
    linbits: u8,
};

/// The 32 big-value tables.  Tables 4 and 14 are not defined by the standard
/// and must not be selected; table 0 means the region is all zeroes, and is
/// null here so that a caller has to notice.
pub const big_value = [32]?BigValue{
    null, // table 0: no data
    .{ .table = &table_1, .linbits = 0 },
    .{ .table = &table_2, .linbits = 0 },
    .{ .table = &table_3, .linbits = 0 },
    null, // table 4: not defined
    .{ .table = &table_5, .linbits = 0 },
    .{ .table = &table_6, .linbits = 0 },
    .{ .table = &table_7, .linbits = 0 },
    .{ .table = &table_8, .linbits = 0 },
    .{ .table = &table_9, .linbits = 0 },
    .{ .table = &table_10, .linbits = 0 },
    .{ .table = &table_11, .linbits = 0 },
    .{ .table = &table_12, .linbits = 0 },
    .{ .table = &table_13, .linbits = 0 },
    null, // table 14: not defined
    .{ .table = &table_15, .linbits = 0 },
    .{ .table = &table_16, .linbits = 1 },
    .{ .table = &table_16, .linbits = 2 },
    .{ .table = &table_16, .linbits = 3 },
    .{ .table = &table_16, .linbits = 4 },
    .{ .table = &table_16, .linbits = 6 },
    .{ .table = &table_16, .linbits = 8 },
    .{ .table = &table_16, .linbits = 10 },
    .{ .table = &table_16, .linbits = 13 },
    .{ .table = &table_24, .linbits = 4 },
    .{ .table = &table_24, .linbits = 5 },
    .{ .table = &table_24, .linbits = 6 },
    .{ .table = &table_24, .linbits = 7 },
    .{ .table = &table_24, .linbits = 8 },
    .{ .table = &table_24, .linbits = 9 },
    .{ .table = &table_24, .linbits = 11 },
    .{ .table = &table_24, .linbits = 13 },
};

/// The two count1 tables, selected by `count1table_select`.  The decoded `y`
/// holds four sign-less magnitudes of one bit each, most significant first:
/// v, w, x, y.
pub const count1 = [2]*const Table{ &table_32, &table_33 };

const all_tables = [_]struct { name: []const u8, codes: []const data.Code, table: *const Table }{
    .{ .name = "1", .codes = &data.table_1, .table = &table_1 },
    .{ .name = "2", .codes = &data.table_2, .table = &table_2 },
    .{ .name = "3", .codes = &data.table_3, .table = &table_3 },
    .{ .name = "5", .codes = &data.table_5, .table = &table_5 },
    .{ .name = "6", .codes = &data.table_6, .table = &table_6 },
    .{ .name = "7", .codes = &data.table_7, .table = &table_7 },
    .{ .name = "8", .codes = &data.table_8, .table = &table_8 },
    .{ .name = "9", .codes = &data.table_9, .table = &table_9 },
    .{ .name = "10", .codes = &data.table_10, .table = &table_10 },
    .{ .name = "11", .codes = &data.table_11, .table = &table_11 },
    .{ .name = "12", .codes = &data.table_12, .table = &table_12 },
    .{ .name = "13", .codes = &data.table_13, .table = &table_13 },
    .{ .name = "15", .codes = &data.table_15, .table = &table_15 },
    .{ .name = "16", .codes = &data.table_16, .table = &table_16 },
    .{ .name = "24", .codes = &data.table_24, .table = &table_24 },
    .{ .name = "32", .codes = &data.table_32, .table = &table_32 },
    .{ .name = "33", .codes = &data.table_33, .table = &table_33 },
};

test "every code word decodes back to its own symbol" {
    for (all_tables) |entry| {
        for (entry.codes) |code| {
            // Put the code word at the top of a buffer, followed by ones so
            // that a decoder reading too far is caught rather than fed zeroes.
            var buf: [8]u8 = @splat(0xff);
            for (0..code.len) |i| {
                const bit: u8 = @truncate((code.code >> @intCast(code.len - 1 - i)) & 1);
                const mask = @as(u8, 0x80) >> @intCast(i % 8);
                if (bit == 1) buf[i / 8] |= mask else buf[i / 8] &= ~mask;
            }
            var reader = BitReader.init(&buf);
            const pair = entry.table.decode(&reader);
            std.testing.expectEqual(Pair{ .x = code.x, .y = code.y }, pair) catch |err| {
                std.debug.print("table {s}, code 0x{x}/{d} bits\n", .{ entry.name, code.code, code.len });
                return err;
            };
            try std.testing.expectEqual(@as(usize, code.len), reader.pos);
        }
    }
}

test "the tables are complete prefix codes" {
    // Every one of the 2^19 possible bit patterns must decode, and the code
    // lengths must satisfy Kraft's equality exactly.
    for (all_tables) |entry| {
        var sum: f64 = 0;
        for (entry.codes) |code| sum += std.math.pow(f64, 2, -@as(f64, @floatFromInt(code.len)));
        try std.testing.expectApproxEqAbs(@as(f64, 1), sum, 1e-12);
    }
}

test "linbits match the standard" {
    // Tables 16-23 and 24-31 are the two escape families; everything below
    // 16 codes its values outright.
    for (big_value[0..16]) |maybe| {
        if (maybe) |t| try std.testing.expectEqual(@as(u8, 0), t.linbits);
    }
    try std.testing.expectEqual(@as(u8, 1), big_value[16].?.linbits);
    try std.testing.expectEqual(@as(u8, 13), big_value[23].?.linbits);
    try std.testing.expectEqual(@as(u8, 4), big_value[24].?.linbits);
    try std.testing.expectEqual(@as(u8, 13), big_value[31].?.linbits);
    try std.testing.expect(big_value[0] == null);
    try std.testing.expect(big_value[4] == null);
    try std.testing.expect(big_value[14] == null);
}
