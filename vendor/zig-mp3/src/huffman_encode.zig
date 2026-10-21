// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Huffman coding in the writing direction.
//!
//! The tables are the decoder's own, turned inside out at compile time: where
//! `huffman.zig` builds a lookup from code words to pairs, this builds one
//! from pairs to code words out of the same `tables/huffman.zig` data.  There
//! is no second copy of the numbers to get wrong, and a test walks every entry
//! of every table through both directions to say so.
//!
//! Two things are coded here.  A *big value* is a pair of quantized spectral
//! values; if a table's alphabet stops at 15 then a 15 means "and this many
//! more", with the excess following in `linbits` bits.  Signs are not in the
//! tables at all -- they follow the code word, one bit for each value that is
//! not zero.  A *count1 quadruple* is four values that are each -1, 0 or 1,
//! coded as a four-bit magnitude pattern with the signs of the non-zero ones
//! after it.
//!
//! Choosing which table to use is the encoder's business, not this file's;
//! what this offers is the cost of a choice, so that the caller can compare.

const std = @import("std");

const BitWriter = @import("bitwriter.zig");
const data = @import("tables/huffman.zig");

/// One symbol's code word.  A length of zero means the table has no such
/// symbol.
pub const Code = struct {
    code: u32 = 0,
    len: u8 = 0,
};

/// A table as a lookup from the pair to its code.  Sixteen by sixteen covers
/// every table: the largest alphabet runs 0 to 15.
const Grid = [16][16]Code;

fn buildGrid(comptime codes: []const data.Code) Grid {
    var grid: Grid = @splat(@splat(.{}));
    for (codes) |entry| {
        grid[entry.x][entry.y] = .{ .code = entry.code, .len = entry.len };
    }
    return grid;
}

fn largest(comptime codes: []const data.Code) u8 {
    var most: u8 = 0;
    for (codes) |entry| most = @max(most, @max(entry.x, entry.y));
    return most;
}

const grid_1 = buildGrid(&data.table_1);
const grid_2 = buildGrid(&data.table_2);
const grid_3 = buildGrid(&data.table_3);
const grid_5 = buildGrid(&data.table_5);
const grid_6 = buildGrid(&data.table_6);
const grid_7 = buildGrid(&data.table_7);
const grid_8 = buildGrid(&data.table_8);
const grid_9 = buildGrid(&data.table_9);
const grid_10 = buildGrid(&data.table_10);
const grid_11 = buildGrid(&data.table_11);
const grid_12 = buildGrid(&data.table_12);
const grid_13 = buildGrid(&data.table_13);
const grid_15 = buildGrid(&data.table_15);
const grid_16 = buildGrid(&data.table_16);
const grid_24 = buildGrid(&data.table_24);
const grid_32 = buildGrid(&data.table_32);
const grid_33 = buildGrid(&data.table_33);

pub const BigTable = struct {
    grid: *const Grid,
    /// Extra magnitude bits written after a value of 15.
    linbits: u8,
    /// The largest value the code tree itself can name.  Where this is 15 the
    /// table escapes; where it is less, a value above it cannot be coded at
    /// all and the table must not be chosen.
    max: u8,

    fn escapes(self: BigTable) bool {
        return self.max == 15;
    }
};

/// The 32 selectable big-value tables, in the same order and with the same
/// `linbits` as the decoder's.  Table 0 means the region carries nothing;
/// tables 4 and 14 are not defined by the standard.
pub const big_value = [32]?BigTable{
    null,
    .{ .grid = &grid_1, .linbits = 0, .max = largest(&data.table_1) },
    .{ .grid = &grid_2, .linbits = 0, .max = largest(&data.table_2) },
    .{ .grid = &grid_3, .linbits = 0, .max = largest(&data.table_3) },
    null,
    .{ .grid = &grid_5, .linbits = 0, .max = largest(&data.table_5) },
    .{ .grid = &grid_6, .linbits = 0, .max = largest(&data.table_6) },
    .{ .grid = &grid_7, .linbits = 0, .max = largest(&data.table_7) },
    .{ .grid = &grid_8, .linbits = 0, .max = largest(&data.table_8) },
    .{ .grid = &grid_9, .linbits = 0, .max = largest(&data.table_9) },
    .{ .grid = &grid_10, .linbits = 0, .max = largest(&data.table_10) },
    .{ .grid = &grid_11, .linbits = 0, .max = largest(&data.table_11) },
    .{ .grid = &grid_12, .linbits = 0, .max = largest(&data.table_12) },
    .{ .grid = &grid_13, .linbits = 0, .max = largest(&data.table_13) },
    null,
    .{ .grid = &grid_15, .linbits = 0, .max = largest(&data.table_15) },
    .{ .grid = &grid_16, .linbits = 1, .max = 15 },
    .{ .grid = &grid_16, .linbits = 2, .max = 15 },
    .{ .grid = &grid_16, .linbits = 3, .max = 15 },
    .{ .grid = &grid_16, .linbits = 4, .max = 15 },
    .{ .grid = &grid_16, .linbits = 6, .max = 15 },
    .{ .grid = &grid_16, .linbits = 8, .max = 15 },
    .{ .grid = &grid_16, .linbits = 10, .max = 15 },
    .{ .grid = &grid_16, .linbits = 13, .max = 15 },
    .{ .grid = &grid_24, .linbits = 4, .max = 15 },
    .{ .grid = &grid_24, .linbits = 5, .max = 15 },
    .{ .grid = &grid_24, .linbits = 6, .max = 15 },
    .{ .grid = &grid_24, .linbits = 7, .max = 15 },
    .{ .grid = &grid_24, .linbits = 8, .max = 15 },
    .{ .grid = &grid_24, .linbits = 9, .max = 15 },
    .{ .grid = &grid_24, .linbits = 11, .max = 15 },
    .{ .grid = &grid_24, .linbits = 13, .max = 15 },
};

/// The two count1 tables, selected by `count1table_select`.
pub const count1 = [2]*const Grid{ &grid_32, &grid_33 };

/// What one pair costs in a given table, in bits, or null if the table cannot
/// name it.
///
/// The values are magnitudes; their signs cost a bit each and are counted
/// here, since a caller comparing tables has to compare like with like.
pub fn bigValueCost(select: usize, x: u32, y: u32) ?usize {
    const table = big_value[select] orelse return null;
    const coded_x = tryEscape(table, x) orelse return null;
    const coded_y = tryEscape(table, y) orelse return null;
    const entry = table.grid[coded_x][coded_y];
    if (entry.len == 0) return null;

    var bits: usize = entry.len;
    if (coded_x == 15 and table.escapes()) bits += table.linbits;
    if (coded_y == 15 and table.escapes()) bits += table.linbits;
    if (x != 0) bits += 1;
    if (y != 0) bits += 1;
    return bits;
}

/// The value as the code tree names it: itself, or 15 where the table escapes
/// and the excess fits in `linbits`.
fn tryEscape(table: BigTable, value: u32) ?u8 {
    if (value <= table.max and value < 15) return @intCast(value);
    if (!table.escapes()) return null;
    if (value - 15 >= @as(u32, 1) << @intCast(table.linbits)) return null;
    return 15;
}

/// Write one pair, its escapes and its signs.
pub fn writeBigValue(writer: *BitWriter, select: usize, x: i32, y: i32) void {
    const table = big_value[select].?;
    const magnitude_x: u32 = @intCast(@abs(x));
    const magnitude_y: u32 = @intCast(@abs(y));
    const coded_x = tryEscape(table, magnitude_x).?;
    const coded_y = tryEscape(table, magnitude_y).?;
    const entry = table.grid[coded_x][coded_y];
    std.debug.assert(entry.len != 0);

    writer.write(entry.code, @intCast(entry.len));
    // The order is fixed by the decoder: the first value's escape, then its
    // sign, then the second's escape, then its sign.
    if (coded_x == 15 and table.escapes()) {
        writer.write(magnitude_x - 15, @intCast(table.linbits));
    }
    if (magnitude_x != 0) writer.write(@intFromBool(x < 0), 1);
    if (coded_y == 15 and table.escapes()) {
        writer.write(magnitude_y - 15, @intCast(table.linbits));
    }
    if (magnitude_y != 0) writer.write(@intFromBool(y < 0), 1);
}

/// The four-bit magnitude pattern of a count1 quadruple, most significant bit
/// first, which is the order the decoder unpacks it in.
fn quadOf(values: [4]i32) u32 {
    var quad: u32 = 0;
    for (values, 0..) |value, k| {
        if (value != 0) quad |= @as(u32, 1) << @intCast(3 - k);
    }
    return quad;
}

/// What one count1 quadruple costs in a given table, in bits, signs included.
pub fn count1Cost(select: usize, values: [4]i32) usize {
    const entry = count1[select][0][quadOf(values)];
    var bits: usize = entry.len;
    for (values) |value| {
        if (value != 0) bits += 1;
    }
    return bits;
}

/// Write one count1 quadruple: the magnitude pattern, then the signs of the
/// values that are not zero, in order.
pub fn writeCount1(writer: *BitWriter, select: usize, values: [4]i32) void {
    const quad = quadOf(values);
    const entry = count1[select][0][quad];
    std.debug.assert(entry.len != 0);
    writer.write(entry.code, @intCast(entry.len));
    for (values) |value| {
        if (value != 0) writer.write(@intFromBool(value < 0), 1);
    }
}

const testing = std.testing;
const BitReader = @import("bitstream.zig");
const huffman = @import("huffman.zig");

/// Every distinct code tree, paired with a table select that reaches it.
const trees = [_]struct { codes: []const data.Code, select: usize }{
    .{ .codes = &data.table_1, .select = 1 },
    .{ .codes = &data.table_2, .select = 2 },
    .{ .codes = &data.table_3, .select = 3 },
    .{ .codes = &data.table_5, .select = 5 },
    .{ .codes = &data.table_6, .select = 6 },
    .{ .codes = &data.table_7, .select = 7 },
    .{ .codes = &data.table_8, .select = 8 },
    .{ .codes = &data.table_9, .select = 9 },
    .{ .codes = &data.table_10, .select = 10 },
    .{ .codes = &data.table_11, .select = 11 },
    .{ .codes = &data.table_12, .select = 12 },
    .{ .codes = &data.table_13, .select = 13 },
    .{ .codes = &data.table_15, .select = 15 },
    .{ .codes = &data.table_16, .select = 16 },
    .{ .codes = &data.table_24, .select = 24 },
};

test "every code word written is the code word read back" {
    // The two directions are built from the same numbers, so this is not a
    // check that the tables are right -- `gen_tables.py` and the decoder's
    // own tests are that.  It is a check that turning them inside out did not
    // lose or transpose anything, which a single wrong entry would.
    for (trees) |tree| {
        for (tree.codes) |entry| {
            var buffer: [8]u8 = undefined;
            var writer = BitWriter.init(&buffer);
            writer.write(entry.code, @intCast(entry.len));

            var reader = BitReader.init(&buffer);
            const pair = huffman.big_value[tree.select].?.table.decode(&reader);
            try testing.expectEqual(entry.x, pair.x);
            try testing.expectEqual(entry.y, pair.y);
            try testing.expectEqual(@as(usize, entry.len), reader.pos);
        }
    }
}

test "every table names every pair inside its alphabet" {
    // A table is a complete code over its alphabet, so there is no pair
    // within range it cannot write; a hole would show up as a value the
    // encoder could not code and would send it hunting for another table.
    for (trees) |tree| {
        const table = big_value[tree.select].?;
        for (0..@as(usize, table.max) + 1) |x| {
            for (0..@as(usize, table.max) + 1) |y| {
                try testing.expect(table.grid[x][y].len != 0);
                try testing.expect(bigValueCost(tree.select, @intCast(x), @intCast(y)) != null);
            }
        }
    }
}

test "a table refuses what it cannot name" {
    // Table 1's alphabet is 0 and 1, and nothing will make it hold a 2.
    try testing.expectEqual(@as(?usize, null), bigValueCost(1, 2, 0));
    try testing.expectEqual(@as(?usize, null), bigValueCost(1, 0, 2));
    // Table 16 escapes, but only as far as its linbits reach: select 16 has
    // one bit, so 15 and 16 are codeable and 17 is not.
    try testing.expect(bigValueCost(16, 16, 0) != null);
    try testing.expectEqual(@as(?usize, null), bigValueCost(16, 17, 0));
    // Select 23 has thirteen bits of escape and reaches much further.
    try testing.expect(bigValueCost(23, 8000, 0) != null);
    // Tables that do not exist are refused rather than reached for.
    try testing.expectEqual(@as(?usize, null), bigValueCost(0, 0, 0));
    try testing.expectEqual(@as(?usize, null), bigValueCost(4, 0, 0));
    try testing.expectEqual(@as(?usize, null), bigValueCost(14, 0, 0));
}

test "the cost of a pair is the number of bits it writes" {
    var prng = std.Random.DefaultPrng.init(0xc057);
    const random = prng.random();
    for (trees) |tree| {
        const table = big_value[tree.select].?;
        const reach: i32 = if (table.escapes())
            @intCast(15 + (@as(u32, 1) << @intCast(table.linbits)) - 1)
        else
            table.max;
        for (0..200) |_| {
            const x = random.intRangeAtMost(i32, -reach, reach);
            const y = random.intRangeAtMost(i32, -reach, reach);
            const cost = bigValueCost(tree.select, @abs(x), @abs(y)) orelse continue;

            var buffer: [16]u8 = undefined;
            var writer = BitWriter.init(&buffer);
            writeBigValue(&writer, tree.select, x, y);
            try testing.expectEqual(cost, writer.pos);
            try testing.expectEqual(@as(usize, 0), writer.overrun);
        }
    }
}

test "count1 quadruples are written as the decoder reads them" {
    // Every combination of four values from -1, 0 and 1, through both count1
    // tables and back out the way `layer3.zig` unpacks them.
    for (0..2) |select| {
        for (0..81) |combination| {
            var values: [4]i32 = undefined;
            var rest = combination;
            for (&values) |*value| {
                value.* = @as(i32, @intCast(rest % 3)) - 1;
                rest /= 3;
            }

            var buffer: [8]u8 = undefined;
            var writer = BitWriter.init(&buffer);
            writeCount1(&writer, select, values);
            try testing.expectEqual(count1Cost(select, values), writer.pos);

            var reader = BitReader.init(&buffer);
            const pair = huffman.count1[select].decode(&reader);
            const quad: u32 = pair.y;
            try testing.expectEqual(quadOf(values), quad);

            // The signs follow as one run, one per non-zero value.
            const signs = reader.read(@popCount(@as(u4, @intCast(quad))));
            var remaining: usize = @popCount(@as(u4, @intCast(quad)));
            for (values, 0..) |want, k| {
                if ((quad >> @intCast(3 - k)) & 1 == 0) {
                    try testing.expectEqual(@as(i32, 0), want);
                    continue;
                }
                remaining -= 1;
                const negative = (signs >> @intCast(remaining)) & 1 != 0;
                try testing.expectEqual(want, if (negative) @as(i32, -1) else 1);
            }
            try testing.expectEqual(writer.pos, reader.pos);
        }
    }
}
