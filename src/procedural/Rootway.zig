//! Steampunk transit galleries on the two Arbor ring approaches. The road remains walkable;
//! an elevated light-rail pair runs through the same ribbed, living-root canopy.
const std = @import("std");
const R = @import("../physics/Rotation.zig");
const V = R.Vec3;

const bronze: V = .{ 0.43, 0.25, 0.13 };
const brass: V = .{ 0.78, 0.53, 0.23 };
const rail: V = .{ 0.12, 0.68, 0.76 };
const gem_colors = [_]V{ .{ 0.18, 0.9, 0.82 }, .{ 0.92, 0.34, 0.72 }, .{ 1.0, 0.58, 0.18 } };

const ArchPoint = struct { x: f32, y: f32 };
const arch = [_]ArchPoint{
    .{ .x = -6.4, .y = 0.2 }, .{ .x = -6.4, .y = 5.6 }, .{ .x = -4.6, .y = 7.2 },
    .{ .x = -2.2, .y = 8.1 }, .{ .x = 0, .y = 8.35 }, .{ .x = 2.2, .y = 8.1 },
    .{ .x = 4.6, .y = 7.2 }, .{ .x = 6.4, .y = 5.6 }, .{ .x = 6.4, .y = 0.2 },
};

/// Adds a short covered root approach from an Arbor ring plaza toward the living tree.
/// `span` uses the district's bridge orientation and supports any city-piece accumulator.
pub fn geometry(span: anytype, out: anytype) !void {
    const length = span.horizontal();
    const orientation = span.rotation();
    const half_length = length / 2;

    // Riveted segmented ribs make the approach read as an engineered gallery grown into roots.
    var z: f32 = 1;
    var rib: usize = 0;
    while (z < length) : (z += 6) {
        for (0..arch.len - 1) |i| {
            const a = arch[i];
            const b = arch[i + 1];
            try beam(out, span, orientation, half_length, z, a, b, if (rib % 2 == 0) bronze else brass, 0.48);
        }
        for ([_]f32{ -6.4, 6.4 }) |x| {
            try localPiece(out, span, orientation, half_length, .{ x, 0.58, z }, .{ 1.0, 0.16, 0.2 }, brass, false);
            try localPiece(out, span, orientation, half_length, .{ x, 2.1, z }, .{ 0.68, 0.18, 0.18 }, bronze, false);
        }
        rib += 1;
    }

    // Twin rails and ties pass through the crown, above the road's full vehicle envelope.
    for ([_]f32{ -1.35, 1.35 }) |x| {
        try localPiece(out, span, orientation, half_length, .{ x, 6.05, half_length }, .{ 0.23, 0.2, length }, rail, false);
    }
    z = 0;
    while (z <= length) : (z += 4) try localPiece(out, span, orientation, half_length, .{ 0, 5.88, z }, .{ 3.2, 0.14, 0.32 }, bronze, false);

    // Root-knot portals use nested bronze bands and a three-colour crystal crest.
    for ([_]f32{ 0, length }) |portal_z| {
        for (0..arch.len - 1) |i| {
            const a = arch[i];
            const b = arch[i + 1];
            try beam(out, span, orientation, half_length, portal_z, a, b, brass, 0.72);
        }
        for (gem_colors, 0..) |color, i| {
            const offset: f32 = (@as(f32, @floatFromInt(i)) - 1) * 1.15;
            try localPiece(out, span, orientation, half_length, .{ offset, 8.1, portal_z }, .{ 0.76, 1.0, 0.72 }, color, false);
        }
    }

    // Faceted insets sit in brass sockets along both walls. Runtime emissive counterparts are
    // published by Sandbox so their jewel colours intensify at night.
    for (0..5) |i| {
        const jewel_z = length * (@as(f32, @floatFromInt(i)) + 0.5) / 5;
        for ([_]f32{ -5.55, 5.55 }) |x| {
            try localPiece(out, span, orientation, half_length, .{ x, 3.15, jewel_z }, .{ 1.72, 1.92, 0.24 }, brass, false);
        }
    }
}

fn beam(out: anytype, span: anytype, orientation: R.Quat, half_length: f32, z: f32, a: ArchPoint, b: ArchPoint, color: V, thickness: f32) !void {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const length = @sqrt(dx * dx + dy * dy);
    const local_rotation = R.axisAngle(.{ 0, 0, 1 }, std.math.atan2(-dx, dy));
    const rotation = R.mul(orientation, local_rotation);
    const center: V = .{ (a.x + b.x) / 2, (a.y + b.y) / 2, z - half_length };
    try out.add(.{
        .center = R.add(span.point(0.5), R.rotate(orientation, center)),
        .size = .{ thickness, thickness, length },
        .rotation = rotation,
        .color = color,
        .solid = true,
    });
}

fn localPiece(out: anytype, span: anytype, orientation: R.Quat, half_length: f32, local: V, size: V, color: V, solid: bool) !void {
    try out.add(.{
        .center = R.add(span.point(0.5), R.rotate(orientation, .{ local[0], local[1], local[2] - half_length })),
        .size = size,
        .rotation = orientation,
        .color = color,
        .solid = solid,
    });
}
