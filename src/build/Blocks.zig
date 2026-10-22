//! The player-built block grid: 1 m cells in sparse 16x16x16 sections. Cells are world-aligned
//! (cell (x, y, z) fills [x, x+1) x [y, y+1) x [z, z+1)). Sections live in a fixed pool that is
//! checked before any write, so a refused placement changes nothing. Edits list the terrain chunk
//! columns they touched; the game rebuilds those chunks' meshes and colliders.
const std = @import("std");
const ChunkKey = @import("../world/ChunkKey.zig");
const Blocks = @This();

pub const side = 16;
pub const section_cells = side * side * side;
pub const section_capacity = 256;
pub const dirty_capacity = 32;

pub const Shape = enum(u4) { empty = 0, cube, slab, ramp, stair, _ };
pub const placeable_shapes = [_]Shape{ .cube, .slab, .ramp, .stair };

pub const Cell = packed struct(u16) {
    shape: Shape = .empty,
    /// Quarter turns about the vertical axis.
    rot: u2 = 0,
    material: u6 = 0,
    flags: u4 = 0,

    pub const empty: Cell = .{};
    pub fn isEmpty(self: Cell) bool {
        return self.shape == .empty;
    }
};

pub const SectionKey = struct { x: i32, y: i32, z: i32 };
const Section = struct {
    key: SectionKey,
    count: u16,
    cells: [section_cells]Cell,
};

pub const Error = error{BlocksFull};

allocator: std.mem.Allocator,
sections: []Section,
count: usize = 0,
revision: u64 = 0,
dirty: [dirty_capacity]ChunkKey = undefined,
dirty_len: usize = 0,
dirty_overflow: bool = false,

pub fn create(allocator: std.mem.Allocator) !*Blocks {
    const self = try allocator.create(Blocks);
    errdefer allocator.destroy(self);
    self.* = .{ .allocator = allocator, .sections = try allocator.alloc(Section, section_capacity) };
    return self;
}

pub fn destroy(self: *Blocks) void {
    const allocator = self.allocator;
    allocator.free(self.sections);
    allocator.destroy(self);
}

pub fn sectionOf(x: i32, y: i32, z: i32) SectionKey {
    return .{ .x = @divFloor(x, side), .y = @divFloor(y, side), .z = @divFloor(z, side) };
}

fn index(x: i32, y: i32, z: i32) usize {
    const lx: usize = @intCast(@mod(x, side));
    const ly: usize = @intCast(@mod(y, side));
    const lz: usize = @intCast(@mod(z, side));
    return (ly * side + lz) * side + lx;
}

fn find(self: *const Blocks, key: SectionKey) ?usize {
    for (self.sections[0..self.count], 0..) |s, i| if (s.key.x == key.x and s.key.y == key.y and s.key.z == key.z) return i;
    return null;
}

pub fn get(self: *const Blocks, x: i32, y: i32, z: i32) Cell {
    const i = self.find(sectionOf(x, y, z)) orelse return .empty;
    return self.sections[i].cells[index(x, y, z)];
}

/// The terrain chunk column a cell belongs to (by its centre).
pub fn chunkOf(x: i32, z: i32) ChunkKey {
    return ChunkKey.fromPosition(@as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(z)) + 0.5);
}

/// Write one cell. Writing an empty cell where there is no section is a no-op; a new section is
/// taken from the pool only when it is needed, and refused when the pool is full.
pub fn set(self: *Blocks, x: i32, y: i32, z: i32, cell: Cell) Error!void {
    const key = sectionOf(x, y, z);
    const i = self.find(key) orelse blk: {
        if (cell.isEmpty()) return;
        if (self.count == section_capacity) return error.BlocksFull;
        self.sections[self.count] = .{ .key = key, .count = 0, .cells = @splat(Cell.empty) };
        self.count += 1;
        break :blk self.count - 1;
    };
    const section = &self.sections[i];
    const slot = &section.cells[index(x, y, z)];
    if (@as(u16, @bitCast(slot.*)) == @as(u16, @bitCast(cell))) return;
    if (slot.isEmpty() and !cell.isEmpty()) section.count += 1;
    if (!slot.isEmpty() and cell.isEmpty()) section.count -= 1;
    slot.* = cell;
    self.revision += 1;
    self.markDirty(x, z);
    if (section.count == 0) {
        self.sections[i] = self.sections[self.count - 1];
        self.count -= 1;
    }
}

fn markDirty(self: *Blocks, x: i32, z: i32) void {
    // A cell on a chunk edge also changes which faces its neighbour across the edge shows.
    for ([_][2]i32{ .{ 0, 0 }, .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |o| {
        const key = chunkOf(x + o[0], z + o[1]);
        for (self.dirty[0..self.dirty_len]) |k| {
            if (k.x == key.x and k.z == key.z) break;
        } else {
            if (self.dirty_len == dirty_capacity) {
                self.dirty_overflow = true;
            } else {
                self.dirty[self.dirty_len] = key;
                self.dirty_len += 1;
            }
        }
    }
}

pub const Dirty = struct { keys: []const ChunkKey, all: bool };
pub fn takeDirty(self: *Blocks, out: []ChunkKey) Dirty {
    const n = @min(self.dirty_len, out.len);
    @memcpy(out[0..n], self.dirty[0..n]);
    const all = self.dirty_overflow or n < self.dirty_len;
    self.dirty_len = 0;
    self.dirty_overflow = false;
    return .{ .keys = out[0..n], .all = all };
}

/// Every section whose cells fall in the chunk column `key`, for meshing.
pub fn sectionsIn(self: *const Blocks, key: ChunkKey, out: []usize) []usize {
    var n: usize = 0;
    for (self.sections[0..self.count], 0..) |s, i| {
        // A 16 m section never straddles a 128 m chunk edge: chunk edges sit at 64 + 128k,
        // a multiple of 16.
        const k = chunkOf(s.key.x * side, s.key.z * side);
        if (k.x != key.x or k.z != key.z or n == out.len) continue;
        out[n] = i;
        n += 1;
    }
    return out[0..n];
}

/// Distinct chunk columns that hold blocks.
pub fn chunks(self: *const Blocks, out: []ChunkKey) []ChunkKey {
    var n: usize = 0;
    for (self.sections[0..self.count]) |s| {
        const k = chunkOf(s.key.x * side, s.key.z * side);
        for (out[0..n]) |o| {
            if (o.x == k.x and o.z == k.z) break;
        } else if (n < out.len) {
            out[n] = k;
            n += 1;
        }
    }
    return out[0..n];
}

pub fn sectionAt(self: *const Blocks, i: usize) struct { key: SectionKey, cells: *const [section_cells]Cell } {
    return .{ .key = self.sections[i].key, .cells = &self.sections[i].cells };
}

pub fn clear(self: *Blocks) void {
    self.count = 0;
    self.revision += 1;
    self.dirty_overflow = true;
}

/// A section as save text: run-length pairs (count, cell), little-endian u16s, as base64.
pub fn encodeSection(allocator: std.mem.Allocator, cells: *const [section_cells]Cell) ![]u8 {
    var raw: std.ArrayList(u8) = .empty;
    defer raw.deinit(allocator);
    var i: usize = 0;
    while (i < section_cells) {
        const value: u16 = @bitCast(cells[i]);
        var run: usize = 1;
        while (i + run < section_cells and @as(u16, @bitCast(cells[i + run])) == value) run += 1;
        try raw.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToLittle(u16, @intCast(run))));
        try raw.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToLittle(u16, value)));
        i += run;
    }
    const encoder = std.base64.standard.Encoder;
    const text = try allocator.alloc(u8, encoder.calcSize(raw.items.len));
    _ = encoder.encode(text, raw.items);
    return text;
}

pub const CodecError = error{InvalidSection};

/// Decodes and validates (known shapes and materials only). Returns the filled-cell count.
pub fn decodeSection(text: []const u8, material_count: usize, out: *[section_cells]Cell) CodecError!usize {
    const decoder = std.base64.standard.Decoder;
    var raw: [section_cells * 4]u8 = undefined;
    const size = decoder.calcSizeForSlice(text) catch return error.InvalidSection;
    if (size > raw.len or size % 4 != 0) return error.InvalidSection;
    decoder.decode(raw[0..size], text) catch return error.InvalidSection;
    var at: usize = 0;
    var filled: usize = 0;
    var pos: usize = 0;
    while (pos < size) : (pos += 4) {
        const run = std.mem.readInt(u16, raw[pos..][0..2], .little);
        const cell: Cell = @bitCast(std.mem.readInt(u16, raw[pos + 2 ..][0..2], .little));
        if (run == 0 or at + run > section_cells) return error.InvalidSection;
        if (!cell.isEmpty()) {
            if (@intFromEnum(cell.shape) > @intFromEnum(Shape.stair) or cell.material >= material_count) return error.InvalidSection;
            filled += run;
        }
        @memset(out[at .. at + run], cell);
        at += run;
    }
    if (at != section_cells) return error.InvalidSection;
    return filled;
}

/// Install a decoded section (a loaded save). The caller checked the pool size.
pub fn loadSection(self: *Blocks, key: SectionKey, cells: *const [section_cells]Cell, filled: usize) Error!void {
    if (filled == 0) return;
    if (self.find(key) != null or self.count == section_capacity) return error.BlocksFull;
    self.sections[self.count] = .{ .key = key, .count = @intCast(filled), .cells = cells.* };
    self.count += 1;
    self.revision += 1;
    self.dirty_overflow = true;
}

test "cells round-trip in negative space and empty sections return to the pool" {
    const b = try create(std.testing.allocator);
    defer b.destroy();
    const stone: Cell = .{ .shape = .cube, .material = 1 };
    try b.set(-1, -1, -17, stone);
    try std.testing.expectEqual(stone, b.get(-1, -1, -17));
    try std.testing.expect(b.get(0, -1, -17).isEmpty());
    try std.testing.expectEqual(@as(usize, 1), b.count);
    try b.set(-1, -1, -17, .empty);
    try std.testing.expectEqual(@as(usize, 0), b.count);
    try b.set(5, 5, 5, .empty); // clearing empty space takes nothing
    try std.testing.expectEqual(@as(usize, 0), b.count);
}

test "a full pool refuses a new section and leaves the grid unchanged" {
    const b = try create(std.testing.allocator);
    defer b.destroy();
    for (0..section_capacity) |i| try b.set(@intCast(i * side), 0, 0, .{ .shape = .cube });
    const revision = b.revision;
    try std.testing.expectError(error.BlocksFull, b.set(0, 100, 0, .{ .shape = .cube }));
    try std.testing.expectEqual(revision, b.revision);
    try b.set(1, 0, 0, .{ .shape = .slab }); // an existing section still accepts cells
}

test "edits on a chunk edge dirty both chunk columns once" {
    const b = try create(std.testing.allocator);
    defer b.destroy();
    try b.set(63, 0, 0, .{ .shape = .cube }); // the last cell of chunk 0 before x = 64
    var keys: [dirty_capacity]ChunkKey = undefined;
    const dirty = b.takeDirty(&keys);
    try std.testing.expect(!dirty.all);
    try std.testing.expectEqual(@as(usize, 2), dirty.keys.len);
}

test "a section round-trips through its save text and bad text is refused" {
    var cells: [section_cells]Cell = @splat(Cell.empty);
    cells[3] = .{ .shape = .ramp, .rot = 2, .material = 4 };
    cells[4] = .{ .shape = .stair, .material = 1 };
    const text = try encodeSection(std.testing.allocator, &cells);
    defer std.testing.allocator.free(text);
    var back: [section_cells]Cell = undefined;
    try std.testing.expectEqual(@as(usize, 2), try decodeSection(text, 8, &back));
    try std.testing.expectEqualSlices(u16, @as(*const [section_cells]u16, @ptrCast(&cells)), @as(*const [section_cells]u16, @ptrCast(&back)));
    try std.testing.expectError(error.InvalidSection, decodeSection(text, 3, &back)); // unknown material
    try std.testing.expectError(error.InvalidSection, decodeSection("AAAA", 8, &back));
}
