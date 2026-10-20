//! Shared city coordinates and source-raster arrival pixels for terrain and globe UI.

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
