//! Player terrain edits: a sparse lattice of height offsets on the 2 m terrain grid, added on top
//! of the generated height in one place (`CityHeightmaps.heightAt`), so the chunk mesh,
//! `Terrain.surface`, physics ground, scatter and culling all agree.
//!
//! Tiles are 64x64 lattice points. A chunk's 65 vertices per side share their edge points with the
//! next chunk, so every lattice point belongs to exactly one tile (the one whose chunk centre is
//! nearest) and both chunks read the same value. Storage is a fixed pool that is never freed while
//! the world runs: the chunk worker reads cells with atomic loads while the main thread writes with
//! atomic stores, and every edit also invalidates the chunks it touched, so a half-applied read is
//! only ever shown until the chunk is rebuilt. Writers are the main thread only.
const std = @import("std");
const ChunkKey = @import("ChunkKey.zig");
const TerrainEdit = @This();

/// Distance between lattice points: the terrain grid (`Chunk.extent / Chunk.cells`).
pub const spacing: f32 = 2;
pub const tile_side = 64;
pub const tile_cells = tile_side * tile_side;
/// Meters per stored unit. 1/16 m lets a gentle dab accumulate instead of rounding away.
pub const unit: f32 = 1.0 / 16.0;
/// Edits stay within +/-32 m of the generated ground.
pub const max_units: i16 = 512;
pub const tile_capacity = 96;
pub const journal_capacity = 32768;
pub const stroke_capacity = 32;
pub const dirty_capacity = 64;

pub const Error = error{TerrainEditFull};

const Tile = struct {
    key: ChunkKey,
    cells: [tile_cells]i16,
};
pub const Change = struct { ix: i32, iz: i32, before: i16, after: i16 };
const Stroke = struct { start: u32, end: u32 };

/// The overlay the terrain reads. Set once by the game; null (the default) means no edits.
pub var active: std.atomic.Value(?*TerrainEdit) = .init(null);

allocator: std.mem.Allocator,
tiles: []Tile,
count: std.atomic.Value(usize) = .init(0),
revision: u64 = 0,
journal: []Change,
journal_len: u32 = 0,
strokes: [stroke_capacity]Stroke = undefined,
stroke_len: u32 = 0,
stroke_cursor: u32 = 0,
dirty: [dirty_capacity]ChunkKey = undefined,
dirty_len: usize = 0,
dirty_overflow: bool = false,

pub fn create(allocator: std.mem.Allocator) !*TerrainEdit {
    const self = try allocator.create(TerrainEdit);
    errdefer allocator.destroy(self);
    const tiles = try allocator.alloc(Tile, tile_capacity);
    errdefer allocator.free(tiles);
    const journal = try allocator.alloc(Change, journal_capacity);
    self.* = .{ .allocator = allocator, .tiles = tiles, .journal = journal };
    return self;
}

/// The caller must have unpublished the overlay and stopped every reader (the chunk workers).
pub fn destroy(self: *TerrainEdit) void {
    const allocator = self.allocator;
    allocator.free(self.tiles);
    allocator.free(self.journal);
    allocator.destroy(self);
}

/// Height offset in meters at a world position (bilinear between lattice points).
pub fn delta(x: f32, z: f32) f32 {
    const self = active.load(.acquire) orelse return 0;
    if (self.count.load(.acquire) == 0) return 0;
    return self.sample(x, z);
}

pub fn sample(self: *const TerrainEdit, x: f32, z: f32) f32 {
    const gx = x / spacing;
    const gz = z / spacing;
    const fx0 = @floor(gx);
    const fz0 = @floor(gz);
    const u = gx - fx0;
    const v = gz - fz0;
    const ix: i32 = @intFromFloat(std.math.clamp(fx0, -1e8, 1e8));
    const iz: i32 = @intFromFloat(std.math.clamp(fz0, -1e8, 1e8));
    const h00: f32 = @floatFromInt(self.get(ix, iz));
    const h10: f32 = @floatFromInt(self.get(ix + 1, iz));
    const h01: f32 = @floatFromInt(self.get(ix, iz + 1));
    const h11: f32 = @floatFromInt(self.get(ix + 1, iz + 1));
    const top = h00 + (h10 - h00) * u;
    const bottom = h01 + (h11 - h01) * u;
    return (top + (bottom - top) * v) * unit;
}

fn tileOf(ix: i32) i32 {
    return @divFloor(ix + tile_side / 2, tile_side);
}

fn cellIndex(ix: i32, iz: i32) usize {
    const lx: usize = @intCast(ix + tile_side / 2 - tileOf(ix) * tile_side);
    const lz: usize = @intCast(iz + tile_side / 2 - tileOf(iz) * tile_side);
    return lz * tile_side + lx;
}

fn findTile(self: *const TerrainEdit, key: ChunkKey) ?*Tile {
    const n = self.count.load(.acquire);
    for (self.tiles[0..n]) |*tile| if (tile.key.x == key.x and tile.key.z == key.z) return @constCast(tile);
    return null;
}

/// Stored units at a lattice point (0 where nothing was ever edited).
pub fn get(self: *const TerrainEdit, ix: i32, iz: i32) i16 {
    const tile = self.findTile(.{ .x = tileOf(ix), .z = tileOf(iz) }) orelse return 0;
    return @atomicLoad(i16, &tile.cells[cellIndex(ix, iz)], .monotonic);
}

pub fn meters(self: *const TerrainEdit, ix: i32, iz: i32) f32 {
    return @as(f32, @floatFromInt(self.get(ix, iz))) * unit;
}

/// Make sure every tile under the lattice window exists. Checks the pool first, so a refusal
/// leaves the overlay unchanged.
pub fn reserve(self: *TerrainEdit, ix0: i32, iz0: i32, ix1: i32, iz1: i32) Error!void {
    var missing: usize = 0;
    var tz = tileOf(iz0);
    while (tz <= tileOf(iz1)) : (tz += 1) {
        var tx = tileOf(ix0);
        while (tx <= tileOf(ix1)) : (tx += 1) {
            if (self.findTile(.{ .x = tx, .z = tz }) == null) missing += 1;
        }
    }
    if (self.count.load(.monotonic) + missing > tile_capacity) return error.TerrainEditFull;
    tz = tileOf(iz0);
    while (tz <= tileOf(iz1)) : (tz += 1) {
        var tx = tileOf(ix0);
        while (tx <= tileOf(ix1)) : (tx += 1) {
            if (self.findTile(.{ .x = tx, .z = tz }) != null) continue;
            const n = self.count.load(.monotonic);
            self.tiles[n] = .{ .key = .{ .x = tx, .z = tz }, .cells = @splat(0) };
            self.count.store(n + 1, .release);
        }
    }
}

/// Start a new undoable gesture (a press). Edits until the next call belong to it.
pub fn beginStroke(self: *TerrainEdit) void {
    self.stroke_len = self.stroke_cursor; // a new edit discards the redo tail
    self.journal_len = if (self.stroke_len == 0) 0 else self.strokes[self.stroke_len - 1].end;
    if (self.stroke_len == stroke_capacity) self.dropOldestStroke();
    self.strokes[self.stroke_len] = .{ .start = self.journal_len, .end = self.journal_len };
    self.stroke_len += 1;
    self.stroke_cursor = self.stroke_len;
}

fn dropOldestStroke(self: *TerrainEdit) void {
    const gone = self.strokes[0].end;
    std.mem.copyForwards(Change, self.journal[0 .. self.journal_len - gone], self.journal[gone..self.journal_len]);
    self.journal_len -= gone;
    for (1..self.stroke_len) |i| self.strokes[i - 1] = .{ .start = self.strokes[i].start - gone, .end = self.strokes[i].end - gone };
    self.stroke_len -= 1;
    self.stroke_cursor = self.stroke_len;
}

/// Write one lattice point. The window must have been reserved. Returns false if the value did
/// not change. Clamps to the +/-32 m band.
pub fn put(self: *TerrainEdit, ix: i32, iz: i32, units: i16) bool {
    const value = std.math.clamp(units, -max_units, max_units);
    const tile = self.findTile(.{ .x = tileOf(ix), .z = tileOf(iz) }) orelse return false;
    const cell = &tile.cells[cellIndex(ix, iz)];
    const before = @atomicLoad(i16, cell, .monotonic);
    if (before == value) return false;
    @atomicStore(i16, cell, value, .monotonic);
    self.revision += 1;
    self.record(.{ .ix = ix, .iz = iz, .before = before, .after = value });
    self.markDirty(ix, iz);
    return true;
}

fn record(self: *TerrainEdit, change: Change) void {
    if (self.stroke_len == 0) return;
    // A stroke larger than the whole journal keeps its newest changes only.
    while (self.journal_len == journal_capacity and self.stroke_len > 1) self.dropOldestStroke();
    if (self.journal_len == journal_capacity) return;
    self.journal[self.journal_len] = change;
    self.journal_len += 1;
    self.strokes[self.stroke_len - 1].end = self.journal_len;
}

fn markDirty(self: *TerrainEdit, ix: i32, iz: i32) void {
    // A vertex on a chunk edge is drawn by both chunks, and normals look half a meter out.
    const wx = @as(f32, @floatFromInt(ix)) * spacing;
    const wz = @as(f32, @floatFromInt(iz)) * spacing;
    const lo = ChunkKey.fromPosition(wx - 1, wz - 1);
    const hi = ChunkKey.fromPosition(wx + 1, wz + 1);
    var z = lo.z;
    while (z <= hi.z) : (z += 1) {
        var x = lo.x;
        while (x <= hi.x) : (x += 1) self.pushDirty(.{ .x = x, .z = z });
    }
}

fn pushDirty(self: *TerrainEdit, key: ChunkKey) void {
    for (self.dirty[0..self.dirty_len]) |k| if (k.x == key.x and k.z == key.z) return;
    if (self.dirty_len == dirty_capacity) {
        self.dirty_overflow = true;
        return;
    }
    self.dirty[self.dirty_len] = key;
    self.dirty_len += 1;
}

/// Chunks whose terrain changed since the last call. After an overflow every chunk is dirty
/// (`all` is true and `keys` is empty). The renderer rebuilds what it holds.
pub const Dirty = struct { keys: []const ChunkKey, all: bool };
pub fn takeDirty(self: *TerrainEdit, out: []ChunkKey) Dirty {
    const n = @min(self.dirty_len, out.len);
    @memcpy(out[0..n], self.dirty[0..n]);
    const all = self.dirty_overflow or n < self.dirty_len;
    self.dirty_len = 0;
    self.dirty_overflow = false;
    return .{ .keys = out[0..n], .all = all };
}

pub fn undo(self: *TerrainEdit) bool {
    if (self.stroke_cursor == 0) return false;
    self.stroke_cursor -= 1;
    const stroke = self.strokes[self.stroke_cursor];
    var i = stroke.end;
    while (i > stroke.start) {
        i -= 1;
        self.restore(self.journal[i].ix, self.journal[i].iz, self.journal[i].before);
    }
    return true;
}

pub fn redo(self: *TerrainEdit) bool {
    if (self.stroke_cursor == self.stroke_len) return false;
    const stroke = self.strokes[self.stroke_cursor];
    self.stroke_cursor += 1;
    for (self.journal[stroke.start..stroke.end]) |change| self.restore(change.ix, change.iz, change.after);
    return true;
}

fn restore(self: *TerrainEdit, ix: i32, iz: i32, units: i16) void {
    const tile = self.findTile(.{ .x = tileOf(ix), .z = tileOf(iz) }) orelse return;
    @atomicStore(i16, &tile.cells[cellIndex(ix, iz)], units, .monotonic);
    self.revision += 1;
    self.markDirty(ix, iz);
}

/// Every edited point, for saving.
pub fn forEachTile(self: *const TerrainEdit, context: anytype, comptime visit: fn (@TypeOf(context), ChunkKey, *const [tile_cells]i16) anyerror!void) !void {
    for (self.tiles[0..self.count.load(.acquire)]) |*tile| try visit(context, tile.key, &tile.cells);
}

/// Replace the whole overlay (a loaded save). Checked first, so a refusal changes nothing.
pub fn loadTile(self: *TerrainEdit, key: ChunkKey, cells: *const [tile_cells]i16) Error!void {
    const base_x = key.x * tile_side - tile_side / 2;
    const base_z = key.z * tile_side - tile_side / 2;
    try self.reserve(base_x, base_z, base_x + tile_side - 1, base_z + tile_side - 1);
    const tile = self.findTile(key).?;
    for (cells, 0..) |value, i| @atomicStore(i16, &tile.cells[i], std.math.clamp(value, -max_units, max_units), .monotonic);
    self.revision += 1;
    self.dirty_overflow = true;
}

/// Forget every edit (new world or load). Readers keep working; the caller invalidates chunks.
pub fn clear(self: *TerrainEdit) void {
    for (self.tiles[0..self.count.load(.monotonic)]) |*tile| for (&tile.cells) |*cell| @atomicStore(i16, cell, 0, .monotonic);
    self.count.store(0, .release);
    self.journal_len = 0;
    self.stroke_len = 0;
    self.stroke_cursor = 0;
    self.revision += 1;
    self.dirty_overflow = true;
}

/// A tile as text for a save: run-length pairs (count, value), both little-endian i16/u16, as base64.
pub fn encodeTile(allocator: std.mem.Allocator, cells: *const [tile_cells]i16) ![]u8 {
    var raw: std.ArrayList(u8) = .empty;
    defer raw.deinit(allocator);
    var i: usize = 0;
    while (i < tile_cells) {
        var run: usize = 1;
        while (i + run < tile_cells and cells[i + run] == cells[i] and run < std.math.maxInt(u16)) run += 1;
        try raw.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToLittle(u16, @intCast(run))));
        try raw.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToLittle(i16, cells[i])));
        i += run;
    }
    const encoder = std.base64.standard.Encoder;
    const text = try allocator.alloc(u8, encoder.calcSize(raw.items.len));
    _ = encoder.encode(text, raw.items);
    return text;
}

pub const CodecError = error{InvalidTile};

pub fn decodeTile(text: []const u8, out: *[tile_cells]i16) CodecError!void {
    const decoder = std.base64.standard.Decoder;
    var raw: [tile_cells * 4]u8 = undefined;
    const size = decoder.calcSizeForSlice(text) catch return error.InvalidTile;
    if (size > raw.len or size % 4 != 0) return error.InvalidTile;
    decoder.decode(raw[0..size], text) catch return error.InvalidTile;
    var at: usize = 0;
    var pos: usize = 0;
    while (pos < size) : (pos += 4) {
        const run = std.mem.readInt(u16, raw[pos..][0..2], .little);
        const value = std.mem.readInt(i16, raw[pos + 2 ..][0..2], .little);
        if (run == 0 or at + run > tile_cells or value < -max_units or value > max_units) return error.InvalidTile;
        @memset(out[at .. at + run], value);
        at += run;
    }
    if (at != tile_cells) return error.InvalidTile;
}

test "a tile round-trips through its save text and bad text is refused" {
    var cells: [tile_cells]i16 = @splat(0);
    cells[5] = 40;
    cells[6] = 40;
    cells[tile_cells - 1] = -512;
    const text = try encodeTile(std.testing.allocator, &cells);
    defer std.testing.allocator.free(text);
    try std.testing.expect(text.len < 100);
    var back: [tile_cells]i16 = undefined;
    try decodeTile(text, &back);
    try std.testing.expectEqualSlices(i16, &cells, &back);
    try std.testing.expectError(error.InvalidTile, decodeTile("AAAA", &back));
    try std.testing.expectError(error.InvalidTile, decodeTile("!!!!", &back));
}

test "tiles own their lattice points once, so neighbouring chunks read the same edge value" {
    const edit = try create(std.testing.allocator);
    defer edit.destroy();
    // World x = 64 is the last vertex of chunk 0 and the first of chunk 1.
    try edit.reserve(32, 0, 32, 0);
    try std.testing.expect(edit.put(32, 0, 40));
    try std.testing.expectEqual(@as(i16, 40), edit.get(32, 0));
    try std.testing.expectEqual(@as(i32, 1), tileOf(32));
    try std.testing.expectEqual(@as(i32, 0), tileOf(31));
    try std.testing.expectEqual(@as(i32, -1), tileOf(-33));
    try std.testing.expectEqual(@as(i32, 0), tileOf(-32));
    active.store(edit, .release);
    defer active.store(null, .release);
    try std.testing.expectApproxEqAbs(@as(f32, 40) * unit, delta(64, 0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 20) * unit, delta(63, 0), 1e-6); // halfway to the unedited neighbour
}

test "a full pool refuses an edit and changes nothing" {
    const edit = try create(std.testing.allocator);
    defer edit.destroy();
    var tx: i32 = 0;
    while (tx < tile_capacity) : (tx += 1) try edit.reserve(tx * tile_side, 0, tx * tile_side, 0);
    try std.testing.expectEqual(@as(usize, tile_capacity), edit.count.load(.monotonic));
    const revision = edit.revision;
    try std.testing.expectError(error.TerrainEditFull, edit.reserve(-500, 0, 20000, 0));
    try std.testing.expectEqual(@as(usize, tile_capacity), edit.count.load(.monotonic));
    try std.testing.expectEqual(revision, edit.revision);
}

test "strokes undo and redo as one gesture and a new stroke drops the redo tail" {
    const edit = try create(std.testing.allocator);
    defer edit.destroy();
    try edit.reserve(0, 0, 4, 0);
    edit.beginStroke();
    _ = edit.put(1, 0, 10);
    _ = edit.put(2, 0, 20);
    edit.beginStroke();
    _ = edit.put(1, 0, 30);
    try std.testing.expect(edit.undo());
    try std.testing.expectEqual(@as(i16, 10), edit.get(1, 0));
    try std.testing.expect(edit.undo());
    try std.testing.expectEqual(@as(i16, 0), edit.get(1, 0));
    try std.testing.expectEqual(@as(i16, 0), edit.get(2, 0));
    try std.testing.expect(!edit.undo());
    try std.testing.expect(edit.redo());
    try std.testing.expectEqual(@as(i16, 20), edit.get(2, 0));
    edit.beginStroke();
    _ = edit.put(3, 0, 5);
    try std.testing.expect(!edit.redo());
}

test "edits are clamped to the band and mark the touched chunks dirty once" {
    const edit = try create(std.testing.allocator);
    defer edit.destroy();
    try edit.reserve(31, 0, 33, 0);
    _ = edit.put(32, 0, 30000);
    try std.testing.expectEqual(max_units, edit.get(32, 0));
    var keys: [dirty_capacity]ChunkKey = undefined;
    const dirty = edit.takeDirty(&keys);
    try std.testing.expect(!dirty.all);
    try std.testing.expectEqual(@as(usize, 2), dirty.keys.len); // chunks 0 and 1 both draw x = 64
    try std.testing.expectEqual(@as(usize, 0), edit.takeDirty(&keys).keys.len);
}
