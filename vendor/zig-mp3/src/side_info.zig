// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! Layer III side information: the fixed-size block after the frame header
//! that says how to read the frame's main data.
//!
//! MPEG-1 carries two granules and MPEG-2/2.5 one, and the low sampling
//! frequency layout also drops `scfsi` and `preflag` and widens
//! `scalefac_compress` from four bits to nine.

const std = @import("std");

const BitReader = @import("bitstream.zig");
const Header = @import("header.zig");

pub const BlockType = enum(u2) {
    /// The ordinary 18-point transform.
    normal = 0,
    /// Transition into a run of short blocks.
    start = 1,
    /// Three 6-point transforms in place of one 18-point transform.
    short = 2,
    /// Transition back out of short blocks.
    stop = 3,
};

pub const Granule = struct {
    /// Bits of main data belonging to this granule and channel: the
    /// scalefactors and the Huffman coded spectrum together.
    part2_3_length: u16,
    /// Number of value *pairs* in the big-values partition of the spectrum.
    big_values: u16,
    global_gain: u8,
    scalefac_compress: u16,
    window_switching: bool,
    block_type: BlockType,
    /// The lowest bands of a short block are coded as long bands instead.
    mixed_block: bool,
    table_select: [3]u5,
    /// Extra attenuation per short-block window, in steps of 8 in the gain
    /// exponent.
    subblock_gain: [3]u3,
    /// Scalefactor bands, counting entries of the band width list, in the
    /// first and second big-values regions.  The counts are one less than the
    /// number of bands, as the standard states them.  A `region1_count` of
    /// `region1_to_end` means the second region runs to the end of the big
    /// values, which is what a window-switched granule always wants.
    region0_count: u4,
    region1_count: u8,
    preflag: bool,
    /// Scalefactors are applied in steps of 1 rather than 0.5 dB units.
    scalefac_scale: bool,
    count1table_select: u1,

    /// Whether this granule's spectrum uses the short-block band layout.
    pub fn isShort(self: Granule) bool {
        return self.window_switching and self.block_type == .short;
    }
};

pub const SideInfo = struct {
    /// How many bytes *before* this frame's main data pointer the granule
    /// data begins -- the bit reservoir.  Zero means it begins here.
    main_data_begin: u16,
    /// Scalefactor selection information, per channel and per the four
    /// scalefactor band groups: when set, granule 1 reuses granule 0's
    /// scalefactors for that group.  Always false on MPEG-2 and MPEG-2.5.
    scfsi: [2][4]bool,
    granule: [2][2]Granule,

    pub fn get(self: *const SideInfo, gr: usize, ch: usize) *const Granule {
        return &self.granule[gr][ch];
    }
};

/// A `region1_count` large enough that the second big-values region always
/// reaches the end of the spectrum, whatever the band layout.
pub const region1_to_end: u8 = std.math.maxInt(u8);

pub const Error = error{
    /// `block_type` 0 with window switching set, which the standard forbids.
    InvalidBlockType,
    /// A `table_select` naming Huffman table 4 or 14, which do not exist.
    UndefinedHuffmanTable,
};

/// Parse the side information for `header` from `bytes`, which must be
/// exactly `header.sideInfoSize()` long.
pub fn parse(header: Header, bytes: []const u8) Error!SideInfo {
    std.debug.assert(bytes.len == header.sideInfoSize());
    const lsf = header.version.isLowSamplingFrequency();
    const channels = header.channels();

    var reader = BitReader.init(bytes);
    var info: SideInfo = .{
        .main_data_begin = @intCast(reader.read(if (lsf) 8 else 9)),
        .scfsi = @splat(@splat(false)),
        .granule = undefined,
    };

    if (lsf) {
        _ = reader.read(if (channels == 1) 1 else 2); // private_bits
    } else {
        _ = reader.read(if (channels == 1) 5 else 3); // private_bits
        for (0..channels) |ch| {
            for (0..4) |group| info.scfsi[ch][group] = reader.readBit() == 1;
        }
    }

    // Unused granules and channels are left in a defined, inert state so that
    // nothing downstream has to ask how many there are.
    info.granule = @splat(@splat(std.mem.zeroInit(Granule, .{
        .block_type = BlockType.normal,
        .table_select = [3]u5{ 0, 0, 0 },
        .subblock_gain = [3]u3{ 0, 0, 0 },
    })));

    for (0..header.granules()) |gr| {
        for (0..channels) |ch| {
            info.granule[gr][ch] = try parseGranule(&reader, lsf);
        }
    }
    std.debug.assert(reader.overrun == 0);
    return info;
}

fn parseGranule(reader: *BitReader, lsf: bool) Error!Granule {
    var g: Granule = undefined;
    g.part2_3_length = @intCast(reader.read(12));
    g.big_values = @intCast(reader.read(9));
    g.global_gain = @intCast(reader.read(8));
    g.scalefac_compress = @intCast(reader.read(if (lsf) 9 else 4));
    g.window_switching = reader.readBit() == 1;

    if (g.window_switching) {
        g.block_type = @enumFromInt(@as(u2, @truncate(reader.read(2))));
        if (g.block_type == .normal) return Error.InvalidBlockType;
        g.mixed_block = reader.readBit() == 1;
        for (0..2) |i| g.table_select[i] = @truncate(reader.read(5));
        g.table_select[2] = 0;
        for (0..3) |i| g.subblock_gain[i] = @truncate(reader.read(3));
        // Not transmitted: a short block that is not mixed starts its second
        // region one scalefactor band later.
        g.region0_count = if (g.block_type == .short and !g.mixed_block) 8 else 7;
        // A window-switched granule has no third region, and no
        // `table_select` for one, so the second region runs to the end.
        g.region1_count = region1_to_end;
    } else {
        g.block_type = .normal;
        g.mixed_block = false;
        for (0..3) |i| g.table_select[i] = @truncate(reader.read(5));
        g.region0_count = @truncate(reader.read(4));
        g.region1_count = @intCast(reader.read(3));
    }

    g.preflag = if (lsf) false else reader.readBit() == 1;
    g.scalefac_scale = reader.readBit() == 1;
    g.count1table_select = @truncate(reader.read(1));

    const used: u8 = if (g.window_switching) 2 else 3;
    for (g.table_select[0..used]) |t| {
        if (t == 4 or t == 14) return Error.UndefinedHuffmanTable;
    }
    return g;
}

const testing = std.testing;

/// Write `n` bits of `value`, most significant first, at bit offset `at`.
fn putBits(buf: []u8, at: *usize, value: u32, n: u6) void {
    var i: u6 = n;
    while (i > 0) {
        i -= 1;
        const bit: u8 = @truncate((value >> @intCast(i)) & 1);
        const mask = @as(u8, 0x80) >> @intCast(at.* % 8);
        if (bit == 1) buf[at.* / 8] |= mask else buf[at.* / 8] &= ~mask;
        at.* += 1;
    }
}

/// Bit offset of the first granule field in MPEG-1 mono side information.
const mono_granule_start = 9 + 5 + 4;

test "MPEG-1 stereo side information is 32 bytes of two granules" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0x00 }).?;
    try testing.expectEqual(@as(usize, 32), header.sideInfoSize());

    var bytes: [32]u8 = @splat(0);
    var pos: usize = 0;
    putBits(&bytes, &pos, 0x1ff, 9); // main_data_begin
    putBits(&bytes, &pos, 0, 3); // private bits
    putBits(&bytes, &pos, 0xff, 8); // scfsi, both channels

    const info = try parse(header, &bytes);
    try testing.expectEqual(@as(u16, 0x1ff), info.main_data_begin);
    try testing.expectEqual([4]bool{ true, true, true, true }, info.scfsi[0]);
    try testing.expectEqual([4]bool{ true, true, true, true }, info.scfsi[1]);
}

test "MPEG-1 mono side information is 17 bytes and has no second channel" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?;
    try testing.expectEqual(@as(usize, 17), header.sideInfoSize());
    const bytes: [17]u8 = @splat(0);
    const info = try parse(header, &bytes);
    try testing.expectEqual(@as(u16, 0), info.main_data_begin);
    // The unused channel is inert rather than undefined.
    try testing.expectEqual(@as(u16, 0), info.granule[0][1].part2_3_length);
    try testing.expectEqual(BlockType.normal, info.granule[1][1].block_type);
}

test "a granule reads its fields in order" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?; // MPEG-1 mono
    var bytes: [17]u8 = @splat(0);
    var pos: usize = mono_granule_start;
    putBits(&bytes, &pos, 1234, 12); // part2_3_length
    putBits(&bytes, &pos, 100, 9); // big_values
    putBits(&bytes, &pos, 200, 8); // global_gain
    putBits(&bytes, &pos, 5, 4); // scalefac_compress
    putBits(&bytes, &pos, 0, 1); // window_switching
    putBits(&bytes, &pos, 1, 5); // table_select
    putBits(&bytes, &pos, 2, 5);
    putBits(&bytes, &pos, 3, 5);
    putBits(&bytes, &pos, 6, 4); // region0_count
    putBits(&bytes, &pos, 2, 3); // region1_count
    putBits(&bytes, &pos, 1, 1); // preflag
    putBits(&bytes, &pos, 0, 1); // scalefac_scale
    putBits(&bytes, &pos, 1, 1); // count1table_select

    const info = try parse(header, &bytes);
    const g = info.get(0, 0);
    try testing.expectEqual(@as(u16, 1234), g.part2_3_length);
    try testing.expectEqual(@as(u16, 100), g.big_values);
    try testing.expectEqual(@as(u8, 200), g.global_gain);
    try testing.expectEqual(@as(u16, 5), g.scalefac_compress);
    try testing.expect(!g.window_switching);
    try testing.expectEqual([3]u5{ 1, 2, 3 }, g.table_select);
    try testing.expectEqual(@as(u4, 6), g.region0_count);
    try testing.expectEqual(@as(u8, 2), g.region1_count);
    try testing.expect(g.preflag);
    try testing.expect(!g.scalefac_scale);
    try testing.expectEqual(@as(u1, 1), g.count1table_select);
}

test "window switching implies a block type and fixed regions" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?;
    var bytes: [17]u8 = @splat(0);
    var pos: usize = mono_granule_start + 12 + 9 + 8 + 4;
    putBits(&bytes, &pos, 1, 1); // window_switching
    putBits(&bytes, &pos, @intFromEnum(BlockType.short), 2);
    putBits(&bytes, &pos, 0, 1); // not mixed

    const info = try parse(header, &bytes);
    const g = info.get(0, 0);
    try testing.expect(g.isShort());
    try testing.expect(!g.mixed_block);
    try testing.expectEqual(@as(u4, 8), g.region0_count);
    try testing.expectEqual(region1_to_end, g.region1_count);

    // Mixed short blocks keep region0 one band shorter.
    pos = mono_granule_start + 12 + 9 + 8 + 4;
    putBits(&bytes, &pos, 1, 1);
    putBits(&bytes, &pos, @intFromEnum(BlockType.short), 2);
    putBits(&bytes, &pos, 1, 1); // mixed
    const mixed = try parse(header, &bytes);
    try testing.expect(mixed.get(0, 0).mixed_block);
    try testing.expectEqual(@as(u4, 7), mixed.get(0, 0).region0_count);
}

test "MPEG-2 has one granule, no scfsi and a nine bit scalefac_compress" {
    const header = Header.parse(.{ 0xff, 0xf3, 0x40, 0xc0 }).?; // MPEG-2 mono
    try testing.expectEqual(@as(usize, 9), header.sideInfoSize());
    var bytes: [9]u8 = @splat(0);
    var pos: usize = 0;
    putBits(&bytes, &pos, 0xff, 8); // main_data_begin is eight bits here
    putBits(&bytes, &pos, 0, 1); // private bit
    putBits(&bytes, &pos, 777, 12); // part2_3_length
    putBits(&bytes, &pos, 0, 9); // big_values
    putBits(&bytes, &pos, 0, 8); // global_gain
    putBits(&bytes, &pos, 511, 9); // scalefac_compress

    const info = try parse(header, &bytes);
    try testing.expectEqual(@as(u16, 0xff), info.main_data_begin);
    try testing.expectEqual([4]bool{ false, false, false, false }, info.scfsi[0]);
    try testing.expectEqual(@as(u16, 777), info.get(0, 0).part2_3_length);
    try testing.expectEqual(@as(u16, 511), info.get(0, 0).scalefac_compress);
    // There is no preflag bit to read on the low sampling frequency layout.
    try testing.expect(!info.get(0, 0).preflag);
}

test "rejects block type 0 with window switching" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?;
    var bytes: [17]u8 = @splat(0);
    var pos: usize = mono_granule_start + 12 + 9 + 8 + 4;
    putBits(&bytes, &pos, 1, 1); // window_switching
    putBits(&bytes, &pos, 0, 2); // block_type 0: forbidden here
    try testing.expectError(Error.InvalidBlockType, parse(header, &bytes));
}

test "rejects the Huffman tables the standard leaves undefined" {
    const header = Header.parse(.{ 0xff, 0xfb, 0x90, 0xc0 }).?;
    var bytes: [17]u8 = @splat(0);
    var pos: usize = mono_granule_start + 12 + 9 + 8 + 4;
    putBits(&bytes, &pos, 0, 1); // no window switching
    putBits(&bytes, &pos, 14, 5); // table_select[0] = 14
    try testing.expectError(Error.UndefinedHuffmanTable, parse(header, &bytes));
}
