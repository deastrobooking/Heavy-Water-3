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
pub const Error = error{ InvalidPgm, UnsupportedPgm, InvalidDimensions, InvalidSettings, InvalidHeightmap, OutOfMemory };

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

fn validSettings(settings: Settings) bool {
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
