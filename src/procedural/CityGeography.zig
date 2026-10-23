//! Shared city coordinates and source-raster arrival pixels for terrain and globe UI.
const std = @import("std");
const ChunkKey = @import("../world/ChunkKey.zig");
const Region = @import("../world/Region.zig");

pub const Coordinate = struct {
    latitude: f32,
    longitude: f32,
};

pub const RasterAnchor = struct {
    /// Normalized source pixel position, where (0, 0) is the northwest image corner.
    anchor_u: f32,
    anchor_v: f32,
};

// Coordinates are downtown arrival points. Anchor fractions are computed from the
// active export bounds documented in the Earth terrain instructions. These PNGs lack
// embedded georeferencing, so changing a bbox requires recalculating its fractions.
// Detroit bbox (-83.68, 42.05, -82.70, 42.75), EPSG:3857 output.
pub const detroit: Coordinate = .{
    .latitude = 42.3314,
    .longitude = -83.0458,
};
pub const detroit_raster_anchor: RasterAnchor = .{
    .anchor_u = 0.647142857,
    .anchor_v = 0.599339378,
};

// NYC uses the wider active bbox (-74.45, 40.45, -73.55, 41.12), EPSG:3857 output.
// The tighter alternate bbox in the instructions requires new anchor fractions.
pub const new_york: Coordinate = .{
    .latitude = 40.7128,
    .longitude = -74.0060,
};
pub const new_york_raster_anchor: RasterAnchor = .{
    .anchor_u = 0.493333333,
    .anchor_v = 0.608962228,
};

// Chicago bbox (-88.30, 41.50, -87.30, 42.24), EPSG:3857 output.
pub const chicago: Coordinate = .{
    .latitude = 41.8781,
    .longitude = -87.6298,
};
pub const chicago_raster_anchor: RasterAnchor = .{
    .anchor_u = 0.670200000,
    .anchor_v = 0.490500602,
};

pub const los_angeles: Coordinate = .{
    .latitude = 34.0522,
    .longitude = -118.2437,
};

// The Antarctic continent raster has no georeferencing or city arrival coordinate.
pub const antarctica: Coordinate = .{ .latitude = -82.0, .longitude = 0.0 };

pub const k2: Coordinate = .{ .latitude = 35.8800, .longitude = 76.5151 };
/// The low-gradient snowfield at source pixel (328, 1784) gives the expedition a safe landing.
pub const k2_raster_anchor: RasterAnchor = .{ .anchor_u = 0.16023449, .anchor_v = 0.87151930 };

/// Approximate GPS coordinate for a local open-world position. Each playable region's arrival
/// is its geographic origin; +X is east and -Z is north in the shared terrain frame.
pub fn atWorld(x: f32, z: f32) Coordinate {
    const key = ChunkKey.fromPosition(x, z);
    const region = Region.at(key.x, key.z);
    var origin = Region.detroit.arrival;
    var anchor = detroit;
    if (std.mem.eql(u8, region.title, Region.new_york.title)) {
        origin = Region.new_york.arrival;
        anchor = new_york;
    } else if (std.mem.eql(u8, region.title, Region.chicago.title)) {
        origin = Region.chicago.arrival;
        anchor = chicago;
    } else if (std.mem.eql(u8, region.title, Region.antarctica.title)) {
        origin = Region.antarctica.arrival;
        anchor = antarctica;
    } else if (std.mem.eql(u8, region.title, Region.k2.title)) {
        origin = Region.k2.arrival;
        anchor = k2;
    }

    const radius: f64 = 6_371_000;
    const radians = std.math.pi / 180.0;
    const latitude = @as(f64, anchor.latitude) * radians;
    const longitude = @as(f64, anchor.longitude) * radians;
    const east = @as(f64, x - origin[0]);
    const north = @as(f64, origin[1] - z);
    const distance = @sqrt(east * east + north * north);
    const angular = distance / radius;
    const bearing = std.math.atan2(east, north);
    const out_lat = std.math.asin(@sin(latitude) * @cos(angular) + @cos(latitude) * @sin(angular) * @cos(bearing));
    var out_lon = longitude + std.math.atan2(@sin(bearing) * @sin(angular) * @cos(latitude), @cos(angular) - @sin(latitude) * @sin(out_lat));
    if (out_lon > std.math.pi) out_lon -= 2 * std.math.pi;
    if (out_lon < -std.math.pi) out_lon += 2 * std.math.pi;
    return .{ .latitude = @floatCast(out_lat / radians), .longitude = @floatCast(out_lon / radians) };
}
