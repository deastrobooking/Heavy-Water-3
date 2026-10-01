//! The district as a routing graph: plazas are nodes; generated roads and player bridges are
//! edges. Vehicles drive the right-hand lane and pedestrians walk either walkway, both as
//! offsets from the road's centre line, so the graph needs no separate lane geometry.
const std = @import("std");
const R = @import("../physics/Rotation.zig");
const District = @import("../procedural/District.zig");
const V = R.Vec3;
const Routes = @This();

pub const max_edges = District.base_edge_count + District.max_bridges;
pub const max_path = District.node_count;
/// Centre of the right-hand 3.5 m traffic lane.
pub const lane_offset: f32 = 1.75;
/// Centre of a 3 m walkway, outside both lanes.
pub const walkway_offset: f32 = 5;
pub const Path = struct {
    nodes: [max_path]u8 = undefined,
    len: usize = 0,
    pub fn slice(self: *const Path) []const u8 {
        return self.nodes[0..self.len];
    }
};

layout: *const District.Layout,
edges: [max_edges]District.Edge = undefined,
count: usize = 0,

/// The generated roads plus `bridges`, in that order.
pub fn init(layout: *const District.Layout, bridges: []const District.Edge) Routes {
    var self: Routes = .{ .layout = layout };
    for (layout.edges) |e| self.add(e);
    for (bridges) |e| self.add(e);
    return self;
}

fn add(self: *Routes, edge: District.Edge) void {
    if (self.count == max_edges) return;
    self.edges[self.count] = edge;
    self.count += 1;
}

pub fn connected(self: *const Routes, a: u8, b: u8) bool {
    for (self.edges[0..self.count]) |e| if (District.same(e, .{ .a = a, .b = b })) return true;
    return false;
}

/// Plazas one road away from `node`, in edge order.
pub fn neighbors(self: *const Routes, node: u8, out: *[max_edges]u8) []const u8 {
    var n: usize = 0;
    for (self.edges[0..self.count]) |e| {
        if (e.a == node) {
            out[n] = e.b;
            n += 1;
        } else if (e.b == node) {
            out[n] = e.a;
            n += 1;
        }
    }
    return out[0..n];
}

pub fn distance(self: *const Routes, a: u8, b: u8) f32 {
    const d = R.sub(self.layout.nodes[b].position, self.layout.nodes[a].position);
    return @sqrt(d[0] * d[0] + d[2] * d[2]);
}

/// Shortest route by road length (Dijkstra over six plazas), `from` first and `to` last, or
/// null when `to` is unreachable.
pub fn route(self: *const Routes, from: u8, to: u8) ?Path {
    const n = District.node_count;
    var best: [n]f32 = @splat(std.math.inf(f32));
    var previous: [n]u8 = @splat(0xFF);
    var done: [n]bool = @splat(false);
    best[from] = 0;
    for (0..n) |_| {
        var u: ?u8 = null;
        for (0..n) |i| if (!done[i] and std.math.isFinite(best[i]) and (u == null or best[i] < best[u.?])) {
            u = @intCast(i);
        };
        const current = u orelse break;
        done[current] = true;
        var buffer: [max_edges]u8 = undefined;
        for (self.neighbors(current, &buffer)) |v| {
            const cost = best[current] + self.distance(current, v);
            if (cost < best[v]) {
                best[v] = cost;
                previous[v] = current;
            }
        }
    }
    if (!std.math.isFinite(best[to])) return null;
    var reversed: Path = .{};
    var at = to;
    while (true) {
        reversed.nodes[reversed.len] = at;
        reversed.len += 1;
        if (at == from) break;
        at = previous[at];
    }
    var path: Path = .{ .len = reversed.len };
    for (0..reversed.len) |i| path.nodes[i] = reversed.nodes[reversed.len - 1 - i];
    return path;
}

/// Horizontal unit vector to the right of travel from `a` toward `b` (left-handed, +Y up).
pub fn right(a: V, b: V) V {
    const d = R.normalize(.{ b[0] - a[0], 0, b[2] - a[2] });
    return .{ d[2], 0, -d[0] };
}

/// Point at fraction `t` of the way between plaza centres, `offset` metres right of travel.
pub fn along(self: *const Routes, a: u8, b: u8, t: f32, offset: f32) V {
    const pa = self.layout.nodes[a].position;
    const pb = self.layout.nodes[b].position;
    return R.add(R.add(pa, R.scale(R.sub(pb, pa), t)), R.scale(right(pa, pb), offset));
}

/// Fraction of the way from plaza `a` to `b` for the projection of `p`.
pub fn progress(self: *const Routes, a: u8, b: u8, p: V) f32 {
    const pa = self.layout.nodes[a].position;
    const pb = self.layout.nodes[b].position;
    const d: V = .{ pb[0] - pa[0], 0, pb[2] - pa[2] };
    return R.dot(.{ p[0] - pa[0], 0, p[2] - pa[2] }, d) / R.dot(d, d);
}

/// Whether `p` is on the deck of the road between `a` and `b` (outside both plazas).
pub fn onRoad(self: *const Routes, a: u8, b: u8, p: V) bool {
    const s = District.span(self.layout, .{ .a = a, .b = b });
    const d: V = .{ s.b[0] - s.a[0], 0, s.b[2] - s.a[2] };
    const t = R.dot(.{ p[0] - s.a[0], 0, p[2] - s.a[2] }, d) / R.dot(d, d);
    if (t < 0 or t > 1) return false;
    const lateral = @abs(R.dot(.{ p[0] - s.a[0], 0, p[2] - s.a[2] }, right(s.a, s.b)));
    return lateral <= District.width / 2 + 1;
}

test "routes take the shortest road, follow added bridges, and reroute when one is removed" {
    const layout = try District.generate(310399555161);
    var routes = Routes.init(&layout, &.{});
    const loop = routes.route(1, 3).?;
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, loop.slice());
    const bridged = Routes.init(&layout, &.{.{ .a = 0, .b = 3 }});
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 3 }, bridged.route(1, 3).?.slice());
    try std.testing.expectEqualSlices(u8, &.{ 0, 3 }, bridged.route(0, 3).?.slice());
    // Without the bridge, a trip already bound for plaza 0 continues around the loop.
    try std.testing.expectEqualSlices(u8, &.{ 0, 5, 4, 3 }, routes.route(0, 3).?.slice());
    try std.testing.expectEqualSlices(u8, &.{2}, routes.route(2, 2).?.slice());
    routes.count = 1; // Only road 0–1 remains: plaza 3 is cut off.
    try std.testing.expect(routes.route(0, 3) == null);
}

test "lane and walkway offsets sit right of travel on the deck, and road membership excludes plazas" {
    const layout = try District.generate(310399555161);
    const routes = Routes.init(&layout, &.{});
    const lane = routes.along(0, 1, 0.5, lane_offset);
    const back = routes.along(1, 0, 0.5, lane_offset);
    // Opposite directions use opposite lanes 3.5 m apart.
    try std.testing.expectApproxEqAbs(@as(f32, 2 * lane_offset), R.length(R.sub(lane, back)), 1e-3);
    try std.testing.expect(routes.onRoad(0, 1, lane) and routes.onRoad(0, 1, routes.along(0, 1, 0.5, walkway_offset)));
    try std.testing.expect(!routes.onRoad(0, 1, routes.along(0, 1, 0.5, 12)));
    try std.testing.expect(!routes.onRoad(0, 1, layout.nodes[0].position));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), routes.progress(0, 1, lane), 1e-4);
}
