//! The first city's elevated light-rail loop. Tracks share the six-plaza route, with stations at
//! the three market towers; station decks are walkable and the guide rails stay above traffic.
const std = @import("std");
const R = @import("../physics/Rotation.zig");
const V = R.Vec3;
const Span = struct {
    a: V,
    b: V,
    fn point(self: @This(), t: f32) V {
        return R.add(self.a, R.scale(R.sub(self.b, self.a), t));
    }
    fn length(self: @This()) f32 {
        return R.length(R.sub(self.b, self.a));
    }
    fn rotation(self: @This()) R.Quat {
        const d = R.sub(self.b, self.a);
        const horizontal = @sqrt(d[0] * d[0] + d[2] * d[2]);
        return R.mul(R.axisAngle(.{ 0, 1, 0 }, std.math.atan2(d[0], d[2])), R.axisAngle(.{ 1, 0, 0 }, -std.math.atan2(d[1], horizontal)));
    }
};

pub const stop_nodes = [_]u8{ 1, 3, 5 };
pub const stop_names = [_][]const u8{ "SOUTH LINE", "NORTH LINE", "WEST LINE" };
pub const track_height: f32 = 5.5;

/// Adds a paired luminous track above each bridge and a small boarding platform at each stop.
pub fn geometry(layout: anytype, out: anytype) !void {
    for (layout.edges) |edge| try track(layout, edge, out);
    for (stop_nodes, 0..) |node, i| try station(layout, node, @intCast(i), out);
}

fn track(layout: anytype, edge: anytype, out: anytype) !void {
    const span = roadSpan(layout, edge);
    const rotation = span.rotation();
    const length = span.length();
    const mid = span.point(0.5);
    const side = R.rotate(rotation, .{ 1, 0, 0 });
    const rise: V = .{ 0, track_height, 0 };
    const cyan: V = .{ 0.11, 0.72, 0.82 };
    const dark: V = .{ 0.16, 0.22, 0.25 };

    // Twin rails and cross ties form a clearly legible transit line above the road deck.
    for ([_]f32{ -1.35, 1.35 }) |offset| try out.add(.{
        .center = R.add(R.add(mid, rise), R.scale(side, offset)),
        .size = .{ 0.24, 0.22, length },
        .rotation = rotation,
        .color = cyan,
        .solid = false,
    });
    var distance: f32 = 0;
    while (distance <= length) : (distance += 8) {
        const point = R.add(span.point(distance / length), rise);
        try out.add(.{ .center = point, .size = .{ 3.25, 0.16, 0.42 }, .rotation = rotation, .color = dark, .solid = false });
    }

    // Outboard pylons support the rail deck without putting columns in traffic or walkways.
    var along: f32 = 30;
    while (along < length - 20) : (along += 60) {
        const point = span.point(along / length);
        for ([_]f32{ -8.1, 8.1 }) |offset| {
            const base = R.add(point, R.scale(side, offset));
            try out.add(.{ .center = R.add(base, .{ 0, track_height / 2, 0 }), .size = .{ 0.85, track_height - 0.7, 0.85 }, .rotation = rotation, .color = dark });
            try out.add(.{ .center = R.add(base, .{ 0, track_height - 0.8, 0 }), .size = .{ 1.2, 0.32, 1.2 }, .rotation = rotation, .color = cyan, .solid = false });
        }
    }
}

fn station(layout: anytype, node_id: u8, stop: u8, out: anytype) !void {
    const node = layout.nodes[node_id];
    const p = node.position;
    const deck: V = .{ 22, 0.55, 8 };
    const roof_y = track_height - 0.3;
    const charcoal: V = .{ 0.12, 0.18, 0.22 };
    const glass: V = .{ 0.16, 0.56, 0.62 };
    const light: V = .{ 0.16, 0.84, 0.91 };
    const platform: V = .{ p[0], p[1] + 0.4, p[2] };

    // Boarding deck sits just over the plaza, with a clear running lane through its centre.
    try out.add(.{ .center = platform, .size = deck, .color = charcoal });
    for ([_]f32{ -9, 9 }) |x| {
        for ([_]f32{ -2.9, 2.9 }) |z| try out.add(.{ .center = .{ p[0] + x, p[1] + roof_y / 2, p[2] + z }, .size = .{ 0.42, roof_y, 0.42 }, .color = glass });
        try out.add(.{ .center = .{ p[0] + x, p[1] + roof_y, p[2] }, .size = .{ 0.5, 0.28, 7 }, .color = light, .solid = false });
    }
    try out.add(.{ .center = .{ p[0], p[1] + roof_y, p[2] }, .size = .{ 19, 0.45, 6.4 }, .color = charcoal });
    // Luminous station wayfinding bars sit above the platform canopy.
    try out.add(.{ .center = .{ p[0], p[1] + roof_y + 0.42, p[2] }, .size = .{ 8, 0.18, 0.18 }, .color = light, .solid = false });
    _ = stop; // The menu and map use the same ordered stop_names table.
}

fn roadSpan(layout: anytype, edge: anytype) Span {
    const a = layout.nodes[edge.a].position;
    const b = layout.nodes[edge.b].position;
    const horizontal = R.normalize(.{ b[0] - a[0], 0, b[2] - a[2] });
    return .{
        .a = R.add(a, R.scale(horizontal, 19.5)),
        .b = R.sub(b, R.scale(horizontal, 19.5)),
    };
}

pub fn destinationNode(stop: usize) ?u8 {
    return if (stop < stop_nodes.len) stop_nodes[stop] else null;
}
