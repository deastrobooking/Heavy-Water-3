//! Versioned heightmap asset format and dependency-free PGM importer.
const std = @import("std");
const Heightmap = @This();

pub const format_version: u16 = 1;
pub const header_size = 32;
pub const max_dimension = 4096;
pub const max_samples = 16 * 1024 * 1024;
pub const Settings = struct {
    world_width: f32 = 512,
    world_depth: f32 = 512,
    base_height: f32 = 0,
    elevation: f32 = 128,
};
pub const Error = error{ InvalidPgm, UnsupportedPgm, InvalidPng, UnsupportedPng, InvalidDimensions, InvalidSettings, InvalidHeightmap, OutOfMemory };

width: u32,
height: u32,
settings: Settings,
samples: []u16,

pub fn deinit(self: Heightmap, allocator: std.mem.Allocator) void {
    allocator.free(self.samples);
}

pub fn importPgm(allocator: std.mem.Allocator, bytes: []const u8, settings: Settings) (Error || error{OutOfMemory})!Heightmap {
    if (!validSettings(settings)) return error.InvalidSettings;
    var reader: PgmReader = .{ .bytes = bytes };
    const magic = reader.token() orelse return error.InvalidPgm;
    if (!std.mem.eql(u8, magic, "P2") and !std.mem.eql(u8, magic, "P5")) return error.UnsupportedPgm;
    const width = try reader.number();
    const height = try reader.number();
    const max_value = try reader.number();
    if (width < 2 or height < 2 or width > max_dimension or height > max_dimension or width * height > max_samples) return error.InvalidDimensions;
    if (max_value == 0 or max_value > 65535) return error.InvalidPgm;

    const samples = try allocator.alloc(u16, width * height);
    errdefer allocator.free(samples);
    if (magic[1] == '2') {
        for (samples) |*sample_value| {
            const value = try reader.number();
            if (value > max_value) return error.InvalidPgm;
            sample_value.* = scaleSample(value, max_value);
        }
        if (reader.token() != null) return error.InvalidPgm;
    } else {
        reader.finishBinaryHeader() catch return error.InvalidPgm;
        const bytes_per_sample: usize = if (max_value > 255) 2 else 1;
        const byte_count = samples.len * bytes_per_sample;
        if (reader.at > bytes.len or bytes.len - reader.at < byte_count) return error.InvalidPgm;
        for (samples, 0..) |*sample_value, i| {
            const value: u32 = if (bytes_per_sample == 1)
                bytes[reader.at + i]
            else
                std.mem.readInt(u16, bytes[reader.at + i * 2 ..][0..2], .big);
            if (value > max_value) return error.InvalidPgm;
            sample_value.* = scaleSample(value, max_value);
        }
    }
    return .{ .width = width, .height = height, .settings = settings, .samples = samples };
}

/// Imports 16-bit grayscale, non-interlaced PNG elevation data. Filter types 0–4 and
/// multiple IDAT chunks are supported; color and alpha PNGs are rejected explicitly.
pub fn importPng(allocator: std.mem.Allocator, bytes: []const u8, settings: Settings) (Error || error{OutOfMemory})!Heightmap {
    if (!validSettings(settings)) return error.InvalidSettings;
    const signature = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
    if (bytes.len < signature.len or !std.mem.eql(u8, bytes[0..8], &signature)) return error.InvalidPng;
    var width: u32 = 0;
    var height: u32 = 0;
    var saw_header = false;
    var saw_end = false;
    var compressed: std.ArrayList(u8) = .empty;
    defer compressed.deinit(allocator);
    var at: usize = 8;
    while (at + 12 <= bytes.len) {
        const length = std.mem.readInt(u32, bytes[at..][0..4], .big);
        at += 4;
        const kind = bytes[at..][0..4];
        at += 4;
        if (length > bytes.len - at -| 4) return error.InvalidPng;
        const data = bytes[at..][0..length];
        at += length;
        // Chunk CRC is checked before consuming its data.
        const expected_crc = std.mem.readInt(u32, bytes[at..][0..4], .big);
        if (pngCrc(kind, data) != expected_crc) return error.InvalidPng;
        at += 4;
        if (std.mem.eql(u8, kind, "IHDR")) {
            if (saw_header or length != 13) return error.InvalidPng;
            width = std.mem.readInt(u32, data[0..4], .big);
            height = std.mem.readInt(u32, data[4..8], .big);
            if (width < 2 or height < 2 or width > max_dimension or height > max_dimension or @as(u64, width) * height > max_samples) return error.InvalidDimensions;
            if (data[8] != 16 or data[9] != 0 or data[10] != 0 or data[11] != 0 or data[12] != 0) return error.UnsupportedPng;
            saw_header = true;
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            if (!saw_header or saw_end) return error.InvalidPng;
            try compressed.appendSlice(allocator, data);
        } else if (std.mem.eql(u8, kind, "IEND")) {
            if (length != 0 or !saw_header) return error.InvalidPng;
            saw_end = true;
            break;
        } else if (kind[0] & 0x20 == 0 and !std.mem.eql(u8, kind, "IHDR")) {
            // Unknown critical chunks can change pixel interpretation.
            return error.UnsupportedPng;
        }
    }
    if (!saw_header or !saw_end or compressed.items.len == 0) return error.InvalidPng;

    const row_bytes = @as(usize, width) * 2;
    const scanline_bytes = row_bytes + 1;
    const raw_len = scanline_bytes * @as(usize, height);
    const filtered = try allocator.alloc(u8, raw_len);
    defer allocator.free(filtered);
    var compressed_reader: std.Io.Reader = .fixed(compressed.items);
    var inflate_window: [@import("std").compress.flate.max_window_len]u8 = undefined;
    var inflater = std.compress.flate.Decompress.init(&compressed_reader, .zlib, &inflate_window);
    inflater.reader.readSliceAll(filtered) catch return error.InvalidPng;
    const rows = try allocator.alloc(u8, row_bytes * @as(usize, height));
    defer allocator.free(rows);
    for (0..height) |y| {
        const filter = filtered[y * scanline_bytes];
        if (filter > 4) return error.InvalidPng;
        for (0..row_bytes) |x| {
            const raw = filtered[y * scanline_bytes + 1 + x];
            const left: u8 = if (x >= 2) rows[y * row_bytes + x - 2] else 0;
            const up: u8 = if (y > 0) rows[(y - 1) * row_bytes + x] else 0;
            const upper_left: u8 = if (y > 0 and x >= 2) rows[(y - 1) * row_bytes + x - 2] else 0;
            const predictor: u8 = switch (filter) {
                0 => 0,
                1 => left,
                2 => up,
                3 => @intCast((@as(u16, left) + up) / 2),
                4 => paeth(left, up, upper_left),
                else => unreachable,
            };
            rows[y * row_bytes + x] = raw +% predictor;
        }
    }
    const samples = try allocator.alloc(u16, @as(usize, width) * height);
    errdefer allocator.free(samples);
    for (samples, 0..) |*sample_value, i| sample_value.* = std.mem.readInt(u16, rows[i * 2 ..][0..2], .big);
    return .{ .width = width, .height = height, .settings = settings, .samples = samples };
}

fn paeth(a: u8, b: u8, c: u8) u8 {
    const p: i32 = @as(i32, a) + b - c;
    const da = @abs(p - a);
    const db = @abs(p - b);
    const dc = @abs(p - c);
    return if (da <= db and da <= dc) a else if (db <= dc) b else c;
}

fn pngCrc(kind: []const u8, data: []const u8) u32 {
    var crc: u32 = 0xffff_ffff;
    for (kind) |byte| crc = crcByte(crc, byte);
    for (data) |byte| crc = crcByte(crc, byte);
    return ~crc;
}

fn crcByte(initial: u32, byte: u8) u32 {
    var crc = initial ^ byte;
    for (0..8) |_| crc = if (crc & 1 != 0) (crc >> 1) ^ 0xedb8_8320 else crc >> 1;
    return crc;
}

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) (Error || error{OutOfMemory})!Heightmap {
    if (bytes.len < header_size or !std.mem.eql(u8, bytes[0..4], "HWMH")) return error.InvalidHeightmap;
    if (std.mem.readInt(u16, bytes[4..6], .little) != format_version or std.mem.readInt(u16, bytes[6..8], .little) != 0) return error.InvalidHeightmap;
    const width = std.mem.readInt(u32, bytes[8..12], .little);
    const height = std.mem.readInt(u32, bytes[12..16], .little);
    if (width < 2 or height < 2 or width > max_dimension or height > max_dimension or width * height > max_samples) return error.InvalidDimensions;
    const sample_count: usize = @as(usize, width) * height;
    if (bytes.len != header_size + sample_count * 2) return error.InvalidHeightmap;
    const settings: Settings = .{
        .world_width = @bitCast(std.mem.readInt(u32, bytes[16..20], .little)),
        .world_depth = @bitCast(std.mem.readInt(u32, bytes[20..24], .little)),
        .base_height = @bitCast(std.mem.readInt(u32, bytes[24..28], .little)),
        .elevation = @bitCast(std.mem.readInt(u32, bytes[28..32], .little)),
    };
    if (!validSettings(settings)) return error.InvalidSettings;
    const samples = try allocator.alloc(u16, sample_count);
    errdefer allocator.free(samples);
    for (samples, 0..) |*sample_value, i| sample_value.* = std.mem.readInt(u16, bytes[header_size + i * 2 ..][0..2], .little);
    return .{ .width = width, .height = height, .settings = settings, .samples = samples };
}

/// A validated read-only view over an encoded map. Useful for large built-in maps that should
/// remain in the executable's immutable asset pages instead of copying samples onto the heap.
pub const View = struct {
    width: u32,
    height: u32,
    settings: Settings,
    encoded_samples: []const u8,

    pub fn sample(self: View, x: f32, z: f32) ?f32 {
        const u = x / self.settings.world_width + 0.5;
        const v = z / self.settings.world_depth + 0.5;
        if (u < 0 or u > 1 or v < 0 or v > 1) return null;
        const px = u * @as(f32, @floatFromInt(self.width - 1));
        const pz = v * @as(f32, @floatFromInt(self.height - 1));
        const x0: usize = @intFromFloat(@floor(px));
        const z0: usize = @intFromFloat(@floor(pz));
        const x1 = @min(x0 + 1, self.width - 1);
        const z1 = @min(z0 + 1, self.height - 1);
        const fx = px - @floor(px);
        const fz = pz - @floor(pz);
        const h00 = self.heightAt(x0, z0);
        const h10 = self.heightAt(x1, z0);
        const h01 = self.heightAt(x0, z1);
        const h11 = self.heightAt(x1, z1);
        const top = h00 + (h10 - h00) * fx;
        const bottom = h01 + (h11 - h01) * fx;
        return top + (bottom - top) * fz;
    }

    fn heightAt(self: View, x: usize, z: usize) f32 {
        const i = (z * @as(usize, self.width) + x) * 2;
        const value = std.mem.readInt(u16, self.encoded_samples[i..][0..2], .little);
        return self.settings.base_height + (@as(f32, @floatFromInt(value)) / 65535) * self.settings.elevation;
    }
};

pub fn view(bytes: []const u8) Error!View {
    if (bytes.len < header_size or !std.mem.eql(u8, bytes[0..4], "HWMH")) return error.InvalidHeightmap;
    if (std.mem.readInt(u16, bytes[4..6], .little) != format_version or std.mem.readInt(u16, bytes[6..8], .little) != 0) return error.InvalidHeightmap;
    const width = std.mem.readInt(u32, bytes[8..12], .little);
    const height = std.mem.readInt(u32, bytes[12..16], .little);
    if (width < 2 or height < 2 or width > max_dimension or height > max_dimension or @as(u64, width) * height > max_samples) return error.InvalidDimensions;
    const sample_count: usize = @as(usize, width) * height;
    if (bytes.len != header_size + sample_count * 2) return error.InvalidHeightmap;
    const settings: Settings = .{
        .world_width = @bitCast(std.mem.readInt(u32, bytes[16..20], .little)),
        .world_depth = @bitCast(std.mem.readInt(u32, bytes[20..24], .little)),
        .base_height = @bitCast(std.mem.readInt(u32, bytes[24..28], .little)),
        .elevation = @bitCast(std.mem.readInt(u32, bytes[28..32], .little)),
    };
    if (!validSettings(settings)) return error.InvalidSettings;
    return .{ .width = width, .height = height, .settings = settings, .encoded_samples = bytes[header_size..] };
}

pub fn encode(self: Heightmap, allocator: std.mem.Allocator) ![]u8 {
    if (self.width < 2 or self.height < 2 or self.width > max_dimension or self.height > max_dimension or self.width * self.height > max_samples or self.samples.len != @as(usize, self.width) * self.height) return error.InvalidDimensions;
    if (!validSettings(self.settings)) return error.InvalidSettings;
    const bytes = try allocator.alloc(u8, header_size + self.samples.len * 2);
    @memcpy(bytes[0..4], "HWMH");
    std.mem.writeInt(u16, bytes[4..6], format_version, .little);
    std.mem.writeInt(u16, bytes[6..8], 0, .little);
    std.mem.writeInt(u32, bytes[8..12], self.width, .little);
    std.mem.writeInt(u32, bytes[12..16], self.height, .little);
    std.mem.writeInt(u32, bytes[16..20], @bitCast(self.settings.world_width), .little);
    std.mem.writeInt(u32, bytes[20..24], @bitCast(self.settings.world_depth), .little);
    std.mem.writeInt(u32, bytes[24..28], @bitCast(self.settings.base_height), .little);
    std.mem.writeInt(u32, bytes[28..32], @bitCast(self.settings.elevation), .little);
    for (self.samples, 0..) |sample_value, i| std.mem.writeInt(u16, bytes[header_size + i * 2 ..][0..2], sample_value, .little);
    return bytes;
}

/// Bilinear sample. The raster is centered on the origin; PGM row zero maps to negative Z.
pub fn sample(self: Heightmap, x: f32, z: f32) ?f32 {
    const u = x / self.settings.world_width + 0.5;
    const v = z / self.settings.world_depth + 0.5;
    if (u < 0 or u > 1 or v < 0 or v > 1) return null;
    const px = u * @as(f32, @floatFromInt(self.width - 1));
    const pz = v * @as(f32, @floatFromInt(self.height - 1));
    const x0: usize = @intFromFloat(@floor(px));
    const z0: usize = @intFromFloat(@floor(pz));
    const x1 = @min(x0 + 1, self.width - 1);
    const z1 = @min(z0 + 1, self.height - 1);
    const fx = px - @floor(px);
    const fz = pz - @floor(pz);
    const h00 = self.heightAt(x0, z0);
    const h10 = self.heightAt(x1, z0);
    const h01 = self.heightAt(x0, z1);
    const h11 = self.heightAt(x1, z1);
    const top = h00 + (h10 - h00) * fx;
    const bottom = h01 + (h11 - h01) * fx;
    return top + (bottom - top) * fz;
}

fn heightAt(self: Heightmap, x: usize, z: usize) f32 {
    const normalized = @as(f32, @floatFromInt(self.samples[z * self.width + x])) / 65535;
    return self.settings.base_height + normalized * self.settings.elevation;
}

pub fn validSettings(settings: Settings) bool {
    return std.math.isFinite(settings.world_width) and settings.world_width > 0 and settings.world_width <= 1_000_000 and
        std.math.isFinite(settings.world_depth) and settings.world_depth > 0 and settings.world_depth <= 1_000_000 and
        std.math.isFinite(settings.base_height) and @abs(settings.base_height) <= 1_000_000 and
        std.math.isFinite(settings.elevation) and settings.elevation > 0 and settings.elevation <= 1_000_000;
}

fn scaleSample(value: u32, max_value: u32) u16 {
    return @intCast((@as(u64, value) * 65535 + max_value / 2) / max_value);
}

const PgmReader = struct {
    bytes: []const u8,
    at: usize = 0,

    fn skipSpaceAndComments(self: *PgmReader) void {
        while (self.at < self.bytes.len) {
            const c = self.bytes[self.at];
            if (std.ascii.isWhitespace(c)) {
                self.at += 1;
            } else if (c == '#') {
                while (self.at < self.bytes.len and self.bytes[self.at] != '\n' and self.bytes[self.at] != '\r') self.at += 1;
            } else break;
        }
    }

    fn token(self: *PgmReader) ?[]const u8 {
        self.skipSpaceAndComments();
        const start = self.at;
        while (self.at < self.bytes.len and !std.ascii.isWhitespace(self.bytes[self.at]) and self.bytes[self.at] != '#') self.at += 1;
        return if (self.at == start) null else self.bytes[start..self.at];
    }

    fn number(self: *PgmReader) Error!u32 {
        const value = self.token() orelse return error.InvalidPgm;
        return std.fmt.parseInt(u32, value, 10) catch error.InvalidPgm;
    }

    fn finishBinaryHeader(self: *PgmReader) Error!void {
        if (self.at >= self.bytes.len or !std.ascii.isWhitespace(self.bytes[self.at])) return error.InvalidPgm;
        if (self.bytes[self.at] == '\r' and self.at + 1 < self.bytes.len and self.bytes[self.at + 1] == '\n') {
            self.at += 2;
        } else self.at += 1;
    }
};

test "imports 16-bit P2 data, encodes a validated asset, and bilinearly samples heights" {
    const source = "P2\n# authored sample\n3 2\n1000\n0 250 500\n750 1000 125\n";
    const map = try importPgm(std.testing.allocator, source, .{ .world_width = 20, .world_depth = 10, .base_height = -5, .elevation = 100 });
    defer map.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 3), map.width);
    try std.testing.expectApproxEqAbs(@as(f32, 20), map.sample(0, -5).?, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 95), map.sample(0, 5).?, 0.01);
    try std.testing.expect(map.sample(11, 0) == null);
    const encoded = try map.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    const decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u16, map.samples, decoded.samples);
    try std.testing.expectEqualDeep(map.settings, decoded.settings);
}

test "imports binary 16-bit P5 samples in network byte order" {
    const source = "P5\n2 2\n65535\n\x00\x00\x80\x00\xff\xff\x40\x00";
    const map = try importPgm(std.testing.allocator, source, .{});
    defer map.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u16, &.{ 0, 32768, 65535, 16384 }, map.samples);
}

test "rejects malformed maps and unsafe settings" {
    try std.testing.expectError(error.UnsupportedPgm, importPgm(std.testing.allocator, "P6\n2 2\n255\n", .{}));
    try std.testing.expectError(error.InvalidPgm, importPgm(std.testing.allocator, "P2\n2 2\n255\n0 1 2", .{}));
    try std.testing.expectError(error.InvalidDimensions, importPgm(std.testing.allocator, "P2\n1 2\n255\n0 1\n", .{}));
    try std.testing.expectError(error.InvalidSettings, importPgm(std.testing.allocator, "P2\n2 2\n255\n0 1 2 3\n", .{ .elevation = 0 }));
}
