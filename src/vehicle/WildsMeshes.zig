//! Modular rural buildings and an ancient-tech shrine for the mountain Wilds.
const std = @import("std");
const m = @import("../character/math.zig");
const cm = @import("../character/mesh.zig");
const prims = @import("prims.zig");
const Designs = @import("Designs.zig");
const RenderMesh = @import("../render/Mesh.zig");
const Vec3 = m.Vec3;
const Allocator = std.mem.Allocator;

const farm_palette: Designs.Palette = .{
    .paint = .{ 0.48, 0.27, 0.13 },
    .accent = .{ 0.16, 0.21, 0.19 },
    .lights = .{ 1.0, 0.56, 0.19 },
};
const temple_palette: Designs.Palette = .{
    .paint = .{ 0.35, 0.42, 0.43 },
    .accent = .{ 0.13, 0.20, 0.22 },
    .lights = .{ 0.24, 0.94, 0.88 },
};

fn finish(a: Allocator, mesh: *cm.Mesh, palette: Designs.Palette) !RenderMesh {
    mesh.computeNormals();
    return Designs.renderMesh(a, mesh, palette);
}

fn box(a: Allocator, mesh: *cm.Mesh, center: Vec3, half: Vec3, mat: cm.Material) !void {
    try prims.box(a, mesh, center, Vec3.unit_x, Vec3.unit_y, Vec3.unit_z, half, mat);
}

/// Compact timber cabin with a covered porch, peaked roof, windows, and a warm entry lamp.
pub fn cabin(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    try box(a, &mesh, Vec3.init(0, 2.2, 0), Vec3.init(4.8, 2.2, 4), .paint);
    try box(a, &mesh, Vec3.init(0, 4.55, 0), Vec3.init(5.25, 0.25, 4.5), .metal);
    for ([_]f32{ -1, 1 }) |side| {
        try prims.strut(a, &mesh, Vec3.init(0, 7.4, -4.6), Vec3.init(side * 5.8, 4.7, -4.6), Vec3.unit_z, 0.42, 0.34, .paint_accent);
        try prims.strut(a, &mesh, Vec3.init(side * 5.8, 4.7, -4.6), Vec3.init(0, 7.4, 4.6), Vec3.unit_z, 0.42, 0.34, .paint_accent);
        try box(a, &mesh, Vec3.init(side * 2.35, 3.0, 4.1), Vec3.init(1.0, 1.0, 0.12), .glass);
        // Porch posts and the broad timber verandah make the entrance readable at a distance.
        try prims.strut(a, &mesh, Vec3.init(side * 3.8, 0, 6.8), Vec3.init(side * 3.8, 4.7, 6.8), Vec3.unit_z, 0.34, 0.34, .metal);
    }
    try box(a, &mesh, Vec3.init(0, 0.3, 6.0), Vec3.init(4.4, 0.3, 2.8), .paint_accent);
    try box(a, &mesh, Vec3.init(0, 2.0, 4.16), Vec3.init(0.8, 1.75, 0.16), .metal);
    try box(a, &mesh, Vec3.init(1.2, 4.8, 0), Vec3.init(0.42, 1.45, 0.42), .metal);
    return finish(a, &mesh, farm_palette);
}

/// A high-shouldered field barn with open hay loft, sliding doors, and a tin roof.
pub fn barn(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    try box(a, &mesh, Vec3.init(0, 3.5, 0), Vec3.init(6.5, 3.5, 5.2), .paint_accent);
    try box(a, &mesh, Vec3.init(0, 6.7, 0), Vec3.init(6.9, 0.25, 5.6), .metal);
    for ([_]f32{ -1, 1 }) |side| {
        try prims.strut(a, &mesh, Vec3.init(0, 10.3, -5.8), Vec3.init(side * 7.4, 6.8, -5.8), Vec3.unit_z, 0.5, 0.38, .paint);
        try prims.strut(a, &mesh, Vec3.init(side * 7.4, 6.8, -5.8), Vec3.init(0, 10.3, 5.8), Vec3.unit_z, 0.5, 0.38, .paint);
        try box(a, &mesh, Vec3.init(side * 2.05, 2.7, 5.34), Vec3.init(2.0, 2.65, 0.18), .paint);
        try box(a, &mesh, Vec3.init(side * 6.25, 4.0, 0), Vec3.init(0.22, 3.3, 0.22), .metal);
        try box(a, &mesh, Vec3.init(side * 3.25, 7.8, -5.42), Vec3.init(1.25, 0.85, 0.12), .glass);
    }
    try box(a, &mesh, Vec3.init(0, 5.45, 5.38), Vec3.init(0.16, 2.9, 0.16), .metal);
    try box(a, &mesh, Vec3.init(0, 2.85, 5.4), Vec3.init(0.12, 2.55, 0.22), .metal);
    return finish(a, &mesh, farm_palette);
}

/// An old mountain sanctuary rebuilt around a living root and a gem-powered signal altar.
pub fn caveTemple(a: Allocator) !RenderMesh {
    var mesh: cm.Mesh = .{};
    defer mesh.deinit(a);
    try box(a, &mesh, Vec3.init(0, 0.35, 0), Vec3.init(7.2, 0.35, 5.6), .metal);
    try box(a, &mesh, Vec3.init(0, 0.75, 0), Vec3.init(6.8, 0.16, 5.2), .paint_accent);
    for ([_]f32{ -5.5, -2.0, 2.0, 5.5 }) |x| {
        try prims.strut(a, &mesh, Vec3.init(x, 0.9, 3.8), Vec3.init(x, 7.3, 3.8), Vec3.unit_z, 0.85, 0.75, .paint);
        try prims.strut(a, &mesh, Vec3.init(x, 0.9, -3.8), Vec3.init(x, 7.3, -3.8), Vec3.unit_z, 0.85, 0.75, .paint);
        try box(a, &mesh, Vec3.init(x, 4.5, 3.9), Vec3.init(0.18, 1.25, 0.12), .emissive);
    }
    // Stepped lintels and an inset arch silhouette, with a deliberate opening for traversal.
    try box(a, &mesh, Vec3.init(0, 7.7, 0), Vec3.init(7.4, 0.65, 5.7), .metal);
    try box(a, &mesh, Vec3.init(0, 8.8, -4.8), Vec3.init(6.3, 0.18, 0.55), .paint);
    for ([_]f32{ -5.5, 5.5 }) |x| try prims.strut(a, &mesh, Vec3.init(x, 7.8, -4.8), Vec3.init(x * 0.72, 10.1, -4.8), Vec3.unit_z, 0.65, 0.65, .paint_accent);
    // Central beacon plinth; emissive fins give the shrine a focal point in crystal light.
    try box(a, &mesh, Vec3.init(0, 1.35, -0.8), Vec3.init(1.8, 0.7, 1.7), .paint_accent);
    try box(a, &mesh, Vec3.init(0, 2.5, -0.8), Vec3.init(0.24, 1.25, 0.24), .emissive);
    for ([_]f32{ -1, 1 }) |side| try prims.strut(a, &mesh, Vec3.init(side * 0.3, 2.1, -0.8), Vec3.init(side * 1.0, 4.2, -0.8), Vec3.unit_z, 0.24, 0.2, .emissive);
    return finish(a, &mesh, temple_palette);
}
